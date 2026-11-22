# Pilot samples for steps 2-3, to measure tokens, cost, time and yield.
# Frame: documents that pass the field terms and have an open PDF.
#
#   Rscript scripts/01b_sample.R [name] [size] [seed] [exclude]
#
#   Rscript scripts/01b_sample.R                                 # pilot25, 25, 20261122
#   Rscript scripts/01b_sample.R pilot250 250 20261123 pilot25   # disjoint from pilot25
#
# `exclude` is a comma-separated list of earlier sample names whose documents
# are removed from the frame before drawing, so that samples can be pooled.
# Output: rows appended to table `pilot_sample` in data/register.sqlite.
# Re-running draws the same documents (fixed seed, frame ordered by
# document_id); a sample already stored under the name is never rewritten, and
# the script stops if the new draw differs from it.

args <- commandArgs(trailingOnly = TRUE)
DB_PATH <- "data/register.sqlite"
SAMPLE_NAME <- if (length(args) >= 1) args[1] else "pilot25"
N <- if (length(args) >= 2) as.integer(args[2]) else 25L
SEED <- if (length(args) >= 3) as.numeric(args[3]) else 20261122
EXCLUDE <- if (length(args) >= 4) strsplit(args[4], ",", fixed = TRUE)[[1]] else character()
if (is.na(N) || N < 1) stop("Sample size must be a positive integer")
if (is.na(SEED)) stop("Seed must be a number")
if (SAMPLE_NAME %in% EXCLUDE) stop("A sample cannot exclude itself")

con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
frame <- DBI::dbGetQuery(con, "
  SELECT document_id FROM document
  WHERE passes_terms = 1 AND open_pdf_file_id IS NOT NULL
  ORDER BY document_id")
message(sprintf("Frame: %d documents", nrow(frame)))

excluded <- character()
for (ex in EXCLUDE) {
  ex_ids <- if (DBI::dbExistsTable(con, "pilot_sample")) {
    DBI::dbGetQuery(con, "SELECT document_id FROM pilot_sample WHERE sample_name = ?",
                    params = list(ex))$document_id
  } else character()
  if (!length(ex_ids)) stop("Sample to exclude not found: ", ex)
  excluded <- union(excluded, ex_ids)
}
pool <- setdiff(frame$document_id, excluded)
message(sprintf("Excluded (%s): %d; pool: %d", paste(EXCLUDE, collapse = ", "),
                length(excluded), length(pool)))
if (N > length(pool)) stop("Sample size larger than the pool")

set.seed(SEED)
ids <- sort(sample(pool, N))

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
