# Pilot sample: 25 documents for steps 2-3, to measure tokens, cost and time.
# Frame: documents that pass the field terms and have an open PDF.
#
#   Rscript scripts/01b_sample.R
#
# Output: table `pilot_sample` in data/register.sqlite. Re-running draws the
# same 25 (fixed seed, frame ordered by document_id); an existing sample of the
# same name is only rewritten when it is identical.

DB_PATH <- "data/register.sqlite"
SAMPLE_NAME <- "pilot25"
SEED <- 20261122
N <- 25

con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
frame <- DBI::dbGetQuery(con, "
  SELECT document_id FROM document
  WHERE passes_terms = 1 AND open_pdf_file_id IS NOT NULL
  ORDER BY document_id")
message(sprintf("Frame: %d documents", nrow(frame)))

set.seed(SEED)
ids <- sort(sample(frame$document_id, N))

if (DBI::dbExistsTable(con, "pilot_sample")) {
  old <- DBI::dbGetQuery(con, "SELECT document_id FROM pilot_sample WHERE sample_name = ?",
                         params = list(SAMPLE_NAME))
  if (nrow(old) && !identical(sort(old$document_id), ids)) {
    stop("Existing sample '", SAMPLE_NAME, "' differs from the new draw; stopping")
  }
  if (nrow(old)) {
    message("Sample '", SAMPLE_NAME, "' already stored and identical; nothing written")
  }
} else {
  old <- data.frame()
}
if (!nrow(old)) {
  sample_tbl <- data.frame(document_id = ids, sample_name = SAMPLE_NAME, seed = SEED,
                           drawn_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  DBI::dbWriteTable(con, "pilot_sample", sample_tbl, append = TRUE)
}

print(DBI::dbGetQuery(con, "
  SELECT substr(d.document_id, 5, 12) AS id, d.year, substr(d.publisher, 1, 25) AS publisher,
         substr(d.title, 1, 70) AS title, round(d.open_pdf_size / 1e6, 2) AS pdf_mb
  FROM pilot_sample s JOIN document d USING (document_id)
  WHERE s.sample_name = ? ORDER BY d.document_id", params = list(SAMPLE_NAME)))
DBI::dbDisconnect(con)
