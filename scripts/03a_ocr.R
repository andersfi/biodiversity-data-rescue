# Step 3a: OCR for sampled PDFs without a text layer.
#
#   Rscript scripts/03a_ocr.R [sample_name]
#
# Takes the documents in `pilot_sample` whose `doc_facts.status` is
# 'no_text_layer' or 'ocr_failed' (or that already use OCR text), OCRs every
# page (R/ocr.R: pdftoppm at 300 dpi, grey; tesseract nor+eng; pages in
# parallel) to data/fulltext/nva/<identifier>.ocr.txt, and recomputes `chunk`
# and `doc_facts` for them from the OCR text with the step 3 functions. A
# document whose .ocr.txt exists is not OCR-ed again. A failed page fails the
# document: status 'ocr_failed' with the message in `error`.
# Run before scripts/03_extract.R, which then reads the OCR text for these
# documents.

source("R/log.R")
source("R/llm.R")
source("R/ocr.R")
source("R/extract.R")

args <- commandArgs(trailingOnly = TRUE)
DB_PATH <- "data/register.sqlite"
SAMPLE_NAME <- if (length(args)) args[1] else NA_character_
CORES <- parallel::detectCores() - 2

now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)

# New doc_facts columns (once); existing rows were all read with pdftotext.
cols <- DBI::dbListFields(con, "doc_facts")
if (!"text_source" %in% cols) {
  DBI::dbExecute(con, "ALTER TABLE doc_facts ADD COLUMN text_source TEXT")
  DBI::dbExecute(con, "ALTER TABLE doc_facts ADD COLUMN ocr_seconds REAL")
  DBI::dbExecute(con, "ALTER TABLE doc_facts ADD COLUMN ocr_pages INTEGER")
  DBI::dbExecute(con, "UPDATE doc_facts SET text_source = 'pdftotext' WHERE status = 'ok'")
}

docs <- DBI::dbGetQuery(con, "
  SELECT d.document_id, d.title, d.publisher, d.year, d.funders
  FROM document d JOIN doc_facts f USING (document_id)
  WHERE d.document_id IN (SELECT document_id FROM pilot_sample
                          WHERE ?1 IS NULL OR sample_name = ?1)
    AND (f.status IN ('no_text_layer', 'ocr_failed') OR f.text_source = 'ocr')
  ORDER BY d.document_id", params = list(SAMPLE_NAME))
message(sprintf("Documents for OCR: %d; cores: %d", nrow(docs), CORES))

replace_rows <- function(table, df) {
  DBI::dbExecute(con, sprintf("DELETE FROM %s WHERE document_id = ?", table),
                 params = list(df$document_id[1]))
  DBI::dbWriteTable(con, table, df, append = TRUE)
}

duck <- gbif_species_db()
t_all <- Sys.time()
for (i in seq_len(nrow(docs))) {
  d <- docs[i, ]
  pdf <- file.path(FULLTEXT_DIR, paste0(sub("^nva:", "", d$document_id), ".pdf"))
  res <- tryCatch({
    if (!file.exists(ocr_txt_path(pdf))) ocr_pdf(pdf, CORES)
    txt <- document_pages(pdf)
    if (txt$text_source != "ocr") stop("pdftotext has enough text; not an OCR document")
    document_code_part(d, pdf, txt, duck, now())
  }, error = function(e) e)
  if (inherits(res, "error")) {
    DBI::dbExecute(con, "UPDATE doc_facts SET status = 'ocr_failed', text_source = 'ocr',
                         error = ?, made_at = ? WHERE document_id = ?",
                   params = list(conditionMessage(res), now(), d$document_id))
    message(sprintf("[%d/%d] %s OCR FAILED: %s", i, nrow(docs), d$document_id,
                    conditionMessage(res)))
    next
  }
  replace_rows("chunk", res$chunk)
  replace_rows("doc_facts", res$facts)
  f <- res$facts
  message(sprintf("[%d/%d] %s %d pages, %.0f s, %.0f chars/page: %s", i, nrow(docs),
                  d$document_id, f$n_pages, f$ocr_seconds, f$n_chars_total / f$n_pages, f$status))
}
DBI::dbDisconnect(duck, shutdown = TRUE)
message(sprintf("Total wall time: %.1f min",
                as.numeric(difftime(Sys.time(), t_all, units = "mins"))))
print(DBI::dbGetQuery(con, "SELECT text_source, status, COUNT(*) AS n FROM doc_facts
                            GROUP BY text_source, status"))
DBI::dbDisconnect(con)
