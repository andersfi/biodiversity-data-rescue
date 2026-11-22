# Step 2: screen title/abstract of a pilot sample with a small model.
#
#   Rscript scripts/02_screen.R [sample_name]
#
# Without a sample name, all documents in `pilot_sample` are screened.
# One model call per document through the Anthropic API (R/llm.R) (prompts/screen.md + prompts/screen.schema.json).
# Output: table `screening` in data/register.sqlite; failed calls go to table
# `llm_failure`. Raw API response: data/llm/screen/<identifier>.json.
# Documents already screened with the same prompt and model are skipped, so a
# stopped run resumes where it stopped. The run stops after more than
# MAX_FAILURES failed documents, or at once when the API reports a rate limit,
# overload or billing problem.

source("R/llm.R")
source("R/rows.R")

args <- commandArgs(trailingOnly = TRUE)
DB_PATH <- "data/register.sqlite"
SAMPLE_NAME <- if (length(args)) args[1] else NA_character_
PROMPT_FILE <- "prompts/screen.md"
SCHEMA_FILE <- "prompts/screen.schema.json"
MAX_FAILURES <- 25
THINKING <- as.character(jsonlite::toJSON(LLM_THINKING, auto_unbox = TRUE))

prompt_sha <- file_sha256(PROMPT_FILE)

con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
docs <- DBI::dbGetQuery(con, "
  SELECT d.document_id, d.title, d.abstract, d.tags, d.publisher, d.year
  FROM document d
  WHERE d.document_id IN (SELECT document_id FROM pilot_sample
                          WHERE ?1 IS NULL OR sample_name = ?1)
  ORDER BY d.document_id", params = list(SAMPLE_NAME))
if (!nrow(docs)) stop("No documents in pilot_sample for sample ", SAMPLE_NAME)

done <- if (DBI::dbExistsTable(con, "screening")) {
  DBI::dbGetQuery(con, "SELECT document_id FROM screening WHERE prompt_sha256 = ? AND model = ?",
                  params = list(prompt_sha, LLM_MODEL))$document_id
} else character()
todo <- docs[!docs$document_id %in% done, ]
message(sprintf("Sample: %d; already screened: %d; to screen: %d",
                nrow(docs), nrow(docs) - nrow(todo), nrow(todo)))
# LIMIT=3 Rscript scripts/02_screen.R screens only the first 3 (a test).
if (nzchar(Sys.getenv("LIMIT"))) todo <- utils::head(todo, as.integer(Sys.getenv("LIMIT")))

n_fail <- 0
for (i in seq_len(nrow(todo))) {
  d <- todo[i, ]
  identifier <- sub("^nva:", "", d$document_id)
  record <- screen_record(d)
  res <- tryCatch({
    r <- llm_call(record, PROMPT_FILE, SCHEMA_FILE)
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
    if (is_limit_error(conditionMessage(res))) stop("Rate limit, overload or billing error reported; stopping")
    if (n_fail > MAX_FAILURES) stop(sprintf("More than %d failures; stopping", MAX_FAILURES))
    next
  }
  o <- res$output
  row <- screen_row(d$document_id, res, LLM_MODEL, THINKING, PROMPT_FILE, prompt_sha, record, now)
  DBI::dbWriteTable(con, "screening", row, append = TRUE)
  message(sprintf("[%d/%d] %s %s (%s) %.1fs $%.5f", i, nrow(todo), d$document_id,
                  o$category, o$confidence, res$seconds, res$cost_usd))
}

print(DBI::dbGetQuery(con, "
  SELECT category, COUNT(*) AS n FROM screening
  WHERE document_id IN (SELECT document_id FROM pilot_sample
                        WHERE ?1 IS NULL OR sample_name = ?1)
    AND prompt_sha256 = ?2 AND model = ?3
  GROUP BY category ORDER BY n DESC", params = list(SAMPLE_NAME, prompt_sha, LLM_MODEL)))
message(sprintf("Failures this run: %d", n_fail))
DBI::dbDisconnect(con)
