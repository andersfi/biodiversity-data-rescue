# Step 3: extraction for a pilot sample. Code first, then the model.
#
#   Rscript scripts/03_extract.R [sample_name]
#
# Without a sample name, all documents in `pilot_sample` are processed.
# 1. Fetch the open PDF of each sampled document to data/fulltext/nva/.
# 2. Text per page (pdftotext, or the OCR text from scripts/03a_ocr.R for PDFs
#    without a text layer); select pages by the rules in R/extract.R.
# 3. Code-derived facts per document.
# 4. One model call per document through the Anthropic API (R/llm.R;
#    prompts/extract.md + schema) on the selected pages. n_sites -1 (not
#    stated) is stored as NA.
# Output tables in data/register.sqlite: `chunk` (one row per page),
# `doc_facts` (one row per document), `extraction` (one row per document),
# `extraction_survey` (one row per survey); failed calls go to `llm_failure`.
# Raw API response: data/llm/extract/<identifier>.json. Documents already
# extracted with the same prompt and model are not sent again, and PDFs already
# on disk are not fetched again, so a stopped run resumes where it stopped.
# A failed download, text extraction or model call is recorded and the run
# continues; it stops after more than MAX_FAILURES failed documents in total,
# or at once when the API reports a rate limit, overload or billing problem.

source("R/log.R")
source("R/llm.R")
source("R/ocr.R")
source("R/extract.R")

args <- commandArgs(trailingOnly = TRUE)
DB_PATH <- "data/register.sqlite"
SAMPLE_NAME <- if (length(args)) args[1] else NA_character_
PROMPT_FILE <- "prompts/extract.md"
SCHEMA_FILE <- "prompts/extract.schema.json"
MAX_FAILURES <- 25
CODE_ONLY <- nzchar(Sys.getenv("CODE_ONLY"))

prompt_sha <- file_sha256(PROMPT_FILE)
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
docs <- DBI::dbGetQuery(con, "
  SELECT d.document_id, d.title, d.publisher, d.year, d.funders, d.open_pdf_file_id
  FROM document d
  WHERE d.document_id IN (SELECT document_id FROM pilot_sample
                          WHERE ?1 IS NULL OR sample_name = ?1)
  ORDER BY d.document_id", params = list(SAMPLE_NAME))
if (!nrow(docs)) stop("No documents in pilot_sample for sample ", SAMPLE_NAME)
message(sprintf("Sample: %d documents", nrow(docs)))

replace_rows <- function(table, df) {
  if (DBI::dbExistsTable(con, table)) {
    DBI::dbExecute(con, sprintf("DELETE FROM %s WHERE document_id = ?", table),
                   params = list(df$document_id[1]))
  }
  DBI::dbWriteTable(con, table, df, append = TRUE)
}

# ---- Code part -----------------------------------------------------------------------

failed_facts <- function(id, status, msg, bytes = NA_real_) {
  replace_rows("doc_facts", data.frame(
    document_id = id, n_pages = NA_integer_, n_chars_total = NA_integer_,
    n_pages_selected = NA_integer_, n_chars_selected = NA_integer_,
    status = status, pdf_bytes = bytes, years_in_text = NA_character_,
    n_coordinate_like = NA_integer_, n_gbif_species = NA_integer_,
    gbif_species = NA_character_, error = msg, made_at = now(), text_source = NA_character_,
    ocr_seconds = NA_real_, ocr_pages = NA_integer_))
}

n_fail <- 0
duck <- gbif_species_db()
records <- list()
for (i in seq_len(nrow(docs))) {
  d <- docs[i, ]
  identifier <- sub("^nva:", "", d$document_id)
  path <- tryCatch(nva_fetch_pdf(identifier, d$open_pdf_file_id), error = function(e) e)
  if (inherits(path, "error")) {
    n_fail <- n_fail + 1
    message(sprintf("[%d] %s download failed: %s", i, d$document_id, conditionMessage(path)))
    failed_facts(d$document_id, "download_failed", conditionMessage(path))
    if (n_fail > MAX_FAILURES) stop(sprintf("More than %d failures; stopping", MAX_FAILURES))
    next
  }
  txt <- tryCatch(document_pages(path), error = function(e) e)
  if (inherits(txt, "error")) {
    n_fail <- n_fail + 1
    message(sprintf("[%d] %s text failed: %s", i, d$document_id, conditionMessage(txt)))
    failed_facts(d$document_id, "text_failed", conditionMessage(txt), file.size(path))
    if (n_fail > MAX_FAILURES) stop(sprintf("More than %d failures; stopping", MAX_FAILURES))
    next
  }
  part <- document_code_part(d, path, txt, duck, now())
  replace_rows("chunk", part$chunk)
  replace_rows("doc_facts", part$facts)
  if (!is.null(part$record)) records[[d$document_id]] <- part$record
  message(sprintf("[%d] %s pages %d, selected %d, %s (%s)", i, d$document_id,
                  part$facts$n_pages, part$facts$n_pages_selected, part$facts$status,
                  txt$text_source))
}
DBI::dbDisconnect(duck, shutdown = TRUE)

# ---- Model part ----------------------------------------------------------------------

# CODE_ONLY=1 Rscript scripts/03_extract.R runs the code part only.
if (CODE_ONLY) {
  DBI::dbDisconnect(con)
  quit(save = "no")
}

done <- if (DBI::dbExistsTable(con, "extraction")) {
  DBI::dbGetQuery(con, "SELECT document_id FROM extraction WHERE prompt_sha256 = ? AND model = ?",
                  params = list(prompt_sha, LLM_MODEL))$document_id
} else character()
todo <- setdiff(names(records), done)
# LIMIT=3 Rscript scripts/03_extract.R sends only the first 3 (a test).
if (nzchar(Sys.getenv("LIMIT"))) todo <- utils::head(todo, as.integer(Sys.getenv("LIMIT")))
message(sprintf("To extract: %d (already done: %d)", length(todo),
                length(intersect(names(records), done))))

for (i in seq_along(todo)) {
  id <- todo[i]
  identifier <- sub("^nva:", "", id)
  record <- records[[id]]
  res <- tryCatch({
    r <- llm_call(record, PROMPT_FILE, SCHEMA_FILE)
    save_raw_call(r, "extract", identifier)
    check_output(r$output, SCHEMA_FILE)
    r
  }, error = function(e) e)
  if (inherits(res, "error")) {
    n_fail <- n_fail + 1
    message(sprintf("[%d/%d] %s FAILED: %s", i, length(todo), id, conditionMessage(res)))
    DBI::dbWriteTable(con, "llm_failure", data.frame(
      step = "extract", document_id = id, error = conditionMessage(res),
      prompt_sha256 = prompt_sha, model = LLM_MODEL, failed_at = now()), append = TRUE)
    if (is_limit_error(conditionMessage(res))) stop("Rate limit, overload or billing error reported; stopping")
    if (n_fail > MAX_FAILURES) stop(sprintf("More than %d failures; stopping", MAX_FAILURES))
    next
  }
  o <- res$output
  surveys <- o$surveys
  ext <- data.frame(
    document_id = id, eligible = o$eligible, eligible_reason = o$eligible_reason,
    borderline = o$borderline, borderline_reason = o$borderline_reason,
    producer = o$producer, commissioner = o$commissioner, funders = join(o$funders),
    funding_type = o$funding_type, study_type = o$study_type,
    study_context_page = o$study_context_page, n_surveys = length(surveys),
    more_surveys = o$more_surveys, model = LLM_MODEL, model_ids = join(res$models),
    prompt_file = PROMPT_FILE, prompt_sha256 = prompt_sha, extracted_at = now(),
    n_chars_in = nchar(record), input_tokens = res$input_tokens,
    cache_creation_input_tokens = res$cache_creation_input_tokens,
    cache_read_input_tokens = res$cache_read_input_tokens,
    output_tokens = res$output_tokens, cost_usd = res$cost_usd, seconds = res$seconds)
  surv <- do.call(rbind, lapply(seq_along(surveys), function(k) {
    s <- surveys[[k]]
    data.frame(
      document_id = id, survey_no = k, taxon_groups = join(s$taxon_groups),
      taxa_names = join(s$taxa_names), years = join(s$years), months = join(s$months),
      places_json = as.character(jsonlite::toJSON(s$places, auto_unbox = TRUE)),
      n_sites = if (s$n_sites == -1) NA_integer_ else as.integer(s$n_sites),
      methods = join(s$methods), method_text = s$method_text,
      fieldwork_by = s$fieldwork_by, effort_stated = s$effort_stated,
      absences_stated = s$absences_stated, data_form = join(s$data_form),
      data_statement = s$data_statement, data_statement_quote = s$data_statement_quote,
      pages = join(s$pages))
  }))
  DBI::dbWithTransaction(con, {
    replace_rows("extraction", ext)
    if (DBI::dbExistsTable(con, "extraction_survey")) {
      DBI::dbExecute(con, "DELETE FROM extraction_survey WHERE document_id = ?", params = list(id))
    }
    if (!is.null(surv)) DBI::dbWriteTable(con, "extraction_survey", surv, append = TRUE)
  })
  message(sprintf("[%d/%d] %s eligible=%s surveys=%d %.1fs $%.5f", i, length(todo), id,
                  o$eligible, length(surveys), res$seconds, res$cost_usd))
}

in_sample <- "document_id IN (SELECT document_id FROM pilot_sample
                               WHERE ?1 IS NULL OR sample_name = ?1)"
print(DBI::dbGetQuery(con, paste("SELECT status, COUNT(*) AS n FROM doc_facts WHERE", in_sample,
                                 "GROUP BY status"), params = list(SAMPLE_NAME)))
print(DBI::dbGetQuery(con, paste("SELECT eligible, COUNT(*) AS n FROM extraction WHERE", in_sample,
                                 "AND prompt_sha256 = ?2 AND model = ?3 GROUP BY eligible"),
                      params = list(SAMPLE_NAME, prompt_sha, LLM_MODEL)))
message(sprintf("Failures this run: %d", n_fail))
DBI::dbDisconnect(con)
