# Steps 2 and 3 with another model, for comparison with the main run.
#
#   Rscript scripts/02b_compare_models.R <model> [provider]
#
# Runs screening and extraction for every document in `pilot_sample` with the
# current prompts and schemas, through NTNU's OpenAI-compatible service
# (provider "ntnu", the default) or the Anthropic API ("anthropic").
# Extraction reads the pages already selected in step 3 (`chunk`) from the
# local PDF text or OCR text; nothing is downloaded or OCR-ed. Calls run
# PARALLEL at a time (parallel::mclapply over documents); the parent writes the
# rows. Output: tables `screening_cmp`, `extraction_cmp`,
# `extraction_survey_cmp` (as the main tables, plus `model` in
# extraction_survey_cmp) and failures in `llm_failure_cmp`; raw replies in
# data/llm/cmp/<model>/. The main tables are not touched. Documents already
# done for this model and prompt are skipped. The run stops after more than
# MAX_FAILURES failed calls, or on a rate-limit, overload or billing error.
# LIMIT=3 runs the first 3 documents only (a test).

source("R/log.R")
source("R/llm.R")
source("R/rows.R")
source("R/ocr.R")
source("R/extract.R")

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Usage: Rscript scripts/02b_compare_models.R <model> [provider]")
MODEL <- args[1]
PROVIDER <- if (length(args) > 1) args[2] else "ntnu"
DB_PATH <- "data/register.sqlite"
SCREEN_PROMPT <- "prompts/screen.md"
SCREEN_SCHEMA <- "prompts/screen.schema.json"
EXTRACT_PROMPT <- "prompts/extract.md"
EXTRACT_SCHEMA <- "prompts/extract.schema.json"
PARALLEL <- 8
BATCH <- 32
MAX_FAILURES <- 25
# Output token limit: GLM-5.3-Flash-instant reasons for up to ~15,000 tokens
# before its answer, close to the main run's 16,000.
MAX_TOKENS <- 32000
THINKING <- if (PROVIDER == "anthropic") {
  as.character(jsonlite::toJSON(LLM_THINKING, auto_unbox = TRUE))
} else "provider_default"
RAW_DIR <- file.path("cmp", gsub("[^A-Za-z0-9._-]", "_", MODEL))

now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
screen_sha <- file_sha256(SCREEN_PROMPT)
extract_sha <- file_sha256(EXTRACT_PROMPT)

con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
docs <- DBI::dbGetQuery(con, "
  SELECT d.document_id, d.title, d.abstract, d.tags, d.publisher, d.year, d.funders,
         f.status
  FROM document d LEFT JOIN doc_facts f USING (document_id)
  WHERE d.document_id IN (SELECT document_id FROM pilot_sample)
  ORDER BY d.document_id")
done_ids <- function(table, sha) {
  if (!DBI::dbExistsTable(con, table)) return(character())
  DBI::dbGetQuery(con, sprintf("SELECT document_id FROM %s WHERE model = ? AND prompt_sha256 = ?",
                               table), params = list(MODEL, sha))$document_id
}
docs$do_screen <- !docs$document_id %in% done_ids("screening_cmp", screen_sha)
docs$do_extract <- docs$status %in% "ok" & !docs$document_id %in% done_ids("extraction_cmp", extract_sha)
docs <- docs[docs$do_screen | docs$do_extract, ]
if (nzchar(Sys.getenv("LIMIT"))) docs <- utils::head(docs, as.integer(Sys.getenv("LIMIT")))
message(sprintf("%s (%s): %d to screen, %d to extract", MODEL, PROVIDER, sum(docs$do_screen),
                sum(docs$do_extract)))

#' Record for extraction from the pages selected in step 3.
extract_record_from_db <- function(d, chunk) {
  pdf <- file.path(FULLTEXT_DIR, paste0(sub("^nva:", "", d$document_id), ".pdf"))
  txt <- document_pages(pdf)
  if (length(txt$pages) != nrow(chunk)) {
    stop(sprintf("Page count %d differs from chunk table (%d)", length(txt$pages), nrow(chunk)))
  }
  extract_record(d, txt$pages, chunk)
}

#' One call with schema check; returns the result or the error.
one_call <- function(record, prompt, schema, step, id) {
  tryCatch({
    r <- llm_call(record, prompt, schema, model = MODEL, provider = PROVIDER,
                  max_tokens = MAX_TOKENS)
    save_raw_call(r, file.path(RAW_DIR, step), sub("^nva:", "", id))
    check_output(r$output, schema)
    r
  }, error = function(e) e)
}

#' Both steps for one document (in a worker). Returns rows and failures.
run_doc <- function(d, chunk) {
  out <- list(screen = NULL, extract = NULL, survey = NULL, failure = NULL)
  fail <- function(step, e, sha) data.frame(step = step, document_id = d$document_id,
                                            error = conditionMessage(e), prompt_sha256 = sha,
                                            model = MODEL, failed_at = now())
  if (d$do_screen) {
    record <- screen_record(d)
    res <- one_call(record, SCREEN_PROMPT, SCREEN_SCHEMA, "screen", d$document_id)
    if (inherits(res, "error")) out$failure <- fail("screen", res, screen_sha) else
      out$screen <- screen_row(d$document_id, res, MODEL, THINKING, SCREEN_PROMPT, screen_sha,
                               record, now())
  }
  if (d$do_extract) {
    record <- tryCatch(extract_record_from_db(d, chunk), error = function(e) e)
    res <- if (inherits(record, "error")) record else
      one_call(record, EXTRACT_PROMPT, EXTRACT_SCHEMA, "extract", d$document_id)
    if (inherits(res, "error")) {
      out$failure <- rbind(out$failure, fail("extract", res, extract_sha))
    } else {
      out$extract <- extraction_row(d$document_id, res, MODEL, THINKING, EXTRACT_PROMPT,
                                    extract_sha, record, now())
      s <- survey_rows(d$document_id, res$output$surveys)
      if (!is.null(s)) out$survey <- cbind(s, model = MODEL)
    }
  }
  out
}

write_rows <- function(table, df, delete = TRUE) {
  if (is.null(df) || !nrow(df)) return(invisible())
  if (delete && DBI::dbExistsTable(con, table)) {
    for (id in unique(df$document_id)) {
      DBI::dbExecute(con, sprintf("DELETE FROM %s WHERE document_id = ? AND model = ?", table),
                     params = list(id, MODEL))
    }
  }
  DBI::dbWriteTable(con, table, df, append = TRUE)
}

n_fail <- 0
t_all <- Sys.time()
batches <- split(seq_len(nrow(docs)), ceiling(seq_len(nrow(docs)) / BATCH))
for (b in batches) {
  chunks <- lapply(docs$document_id[b], function(id) {
    DBI::dbGetQuery(con, "SELECT page, n_chars, selected, reasons FROM chunk
                          WHERE document_id = ? ORDER BY page", params = list(id))
  })
  res <- parallel::mclapply(seq_along(b), function(k) run_doc(docs[b[k], ], chunks[[k]]),
                            mc.cores = PARALLEL, mc.preschedule = FALSE)
  bad <- vapply(res, function(r) inherits(r, "try-error"), logical(1))
  if (any(bad)) stop("Worker crashed: ", as.character(res[[which(bad)[1]]]))
  get <- function(name) do.call(rbind, lapply(res, `[[`, name))
  DBI::dbWithTransaction(con, {
    write_rows("screening_cmp", get("screen"))
    write_rows("extraction_cmp", get("extract"))
    ext_ids <- unique(get("extract")$document_id)
    if (length(ext_ids) && DBI::dbExistsTable(con, "extraction_survey_cmp")) {
      for (id in ext_ids) DBI::dbExecute(con, "DELETE FROM extraction_survey_cmp
                                               WHERE document_id = ? AND model = ?",
                                         params = list(id, MODEL))
    }
    write_rows("extraction_survey_cmp", get("survey"), delete = FALSE)
    write_rows("llm_failure_cmp", get("failure"), delete = FALSE)
  })
  f <- get("failure")
  n_fail <- n_fail + if (is.null(f)) 0 else nrow(f)
  message(sprintf("%d/%d documents, %d failures, %.1f min", max(b), nrow(docs), n_fail,
                  as.numeric(difftime(Sys.time(), t_all, units = "mins"))))
  if (!is.null(f)) for (i in seq_len(nrow(f))) message("  FAILED ", f$step[i], " ",
                                                         f$document_id[i], ": ", f$error[i])
  if (!is.null(f) && any(is_limit_error(f$error))) stop("Rate limit, overload or billing error; stopping")
  if (n_fail > MAX_FAILURES) stop(sprintf("More than %d failures; stopping", MAX_FAILURES))
}
message(sprintf("Done: %s, wall time %.1f min, failures %d", MODEL,
                as.numeric(difftime(Sys.time(), t_all, units = "mins")), n_fail))
DBI::dbDisconnect(con)
