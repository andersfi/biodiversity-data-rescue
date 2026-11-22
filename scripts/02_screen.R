# Step 2: screen title/abstract of the pilot sample with a small model.
#
#   Rscript scripts/02_screen.R
#
# One model call per document (prompts/screen.md + prompts/screen.schema.json).
# Output: table `screening` in data/register.sqlite; failed calls go to table
# `llm_failure`. Raw CLI output: data/llm/screen/<identifier>.json.
# Documents already screened with the same prompt and model are skipped.

source("R/llm.R")

DB_PATH <- "data/register.sqlite"
SAMPLE_NAME <- "pilot25"
PROMPT_FILE <- "prompts/screen.md"
SCHEMA_FILE <- "prompts/screen.schema.json"
MAX_FAILURES <- 5

prompt_sha <- file_sha256(PROMPT_FILE)

con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
docs <- DBI::dbGetQuery(con, "
  SELECT d.document_id, d.title, d.abstract, d.tags, d.publisher, d.year
  FROM pilot_sample s JOIN document d USING (document_id)
  WHERE s.sample_name = ? ORDER BY d.document_id", params = list(SAMPLE_NAME))

done <- if (DBI::dbExistsTable(con, "screening")) {
  DBI::dbGetQuery(con, "SELECT document_id FROM screening WHERE prompt_sha256 = ? AND model = ?",
                  params = list(prompt_sha, LLM_MODEL))$document_id
} else character()
todo <- docs[!docs$document_id %in% done, ]
message(sprintf("Sample: %d; already screened: %d; to screen: %d",
                nrow(docs), nrow(docs) - nrow(todo), nrow(todo)))

screen_record <- function(d) {
  val <- function(x, empty) if (is.na(x) || !nzchar(trimws(x))) empty else x
  paste(c(paste("Title:", val(d$title, "(no title)")),
          paste("Abstract:", val(d$abstract, "(no abstract)")),
          paste("Keywords:", val(gsub(";", "; ", d$tags), "(none)")),
          paste("Publisher:", val(d$publisher, "(not given)")),
          paste("Year:", val(as.character(d$year), "(not given)"))),
        collapse = "\n")
}

n_fail <- 0
for (i in seq_len(nrow(todo))) {
  d <- todo[i, ]
  identifier <- sub("^nva:", "", d$document_id)
  record <- screen_record(d)
  res <- tryCatch({
    r <- llm_cli_call(record, PROMPT_FILE, SCHEMA_FILE)
    save_raw_call(r, "screen", identifier)
    check_output(r$output, SCHEMA_FILE)
    r
  }, error = function(e) e)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (inherits(res, "error")) {
    n_fail <- n_fail + 1
    message(sprintf("[%d/%d] %s FAILED: %s", i, nrow(todo), d$document_id, conditionMessage(res)))
    DBI::dbWriteTable(con, "llm_failure", data.frame(
      step = "screen", document_id = d$document_id, error = conditionMessage(res),
      prompt_sha256 = prompt_sha, model = LLM_MODEL, failed_at = now), append = TRUE)
    if (n_fail > MAX_FAILURES) stop(sprintf("More than %d failures; stopping", MAX_FAILURES))
    next
  }
  o <- res$output
  row <- data.frame(
    document_id = d$document_id, category = o$category, confidence = o$confidence,
    taxon_groups = join(o$taxon_groups), reason = o$reason,
    model = LLM_MODEL, model_ids = join(res$models), prompt_file = PROMPT_FILE,
    prompt_sha256 = prompt_sha, screened_at = now, n_chars_in = nchar(record),
    input_tokens = res$input_tokens,
    cache_creation_input_tokens = res$cache_creation_input_tokens,
    cache_read_input_tokens = res$cache_read_input_tokens,
    output_tokens = res$output_tokens, cost_usd = res$cost_usd, seconds = res$seconds)
  DBI::dbWriteTable(con, "screening", row, append = TRUE)
  message(sprintf("[%d/%d] %s %s (%s) %.1fs $%.5f", i, nrow(todo), d$document_id,
                  o$category, o$confidence, res$seconds, res$cost_usd))
}

print(DBI::dbGetQuery(con, "
  SELECT category, COUNT(*) AS n FROM screening s JOIN pilot_sample p USING (document_id)
  WHERE p.sample_name = ? AND s.prompt_sha256 = ? AND s.model = ?
  GROUP BY category ORDER BY n DESC", params = list(SAMPLE_NAME, prompt_sha, LLM_MODEL)))
message(sprintf("Failures this run: %d", n_fail))
DBI::dbDisconnect(con)
