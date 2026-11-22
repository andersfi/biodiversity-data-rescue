# Step 1 (pilot): search NVA for reports, one request series per organism term
# in search/terms.csv. Field terms are matched afterwards in code against
# title + abstract + tags; non-matching documents are kept (passes_terms).
#
#   Rscript scripts/01_search.R
#
# Raw pages: data/raw/nva/<run date>/<term>_<page>.json.gz
# Output: table `document` in data/register.sqlite (replaced on each run).

source("R/log.R")
source("R/nva.R")

MAX_TOTAL_HITS <- 250000
DB_PATH <- "data/register.sqlite"

terms <- readr::read_csv("search/terms.csv", show_col_types = FALSE)
organism_terms <- unique(terms$term[terms$term_group == "organism"])
field_stems <- unique(terms$term[terms$term_group == "field"])

run_date <- format(Sys.Date())
raw_dir <- file.path(NVA_RAW_DIR, run_date)

results <- list()
n_total <- 0
n_requests <- 0
for (term in organism_terms) {
  retrieved_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res <- nva_fetch_term(term, raw_dir)
  n_total <- n_total + res$total
  n_requests <- n_requests + res$n_requests
  if (n_total > MAX_TOTAL_HITS) {
    stop(sprintf("Raw hits exceed %d after term '%s'; stopping", MAX_TOTAL_HITS, term))
  }
  log_query("nva", call = "GET search/resources",
            args = list(query = term,
                        instanceType = paste(NVA_REPORT_TYPES, collapse = ","),
                        size = NVA_PAGE_SIZE,
                        sort = "identifier"),
            n_records = nrow(res$hits), n_expected = res$total,
            n_requests = res$n_requests, raw_dir = raw_dir)
  if (nrow(res$hits)) res$hits$retrieved_at <- retrieved_at
  results[[term]] <- res$hits
  message(sprintf("%-20s %6d hits, %4d requests", term, res$total, res$n_requests))
}

hits <- dplyr::bind_rows(results)
term_counts <- dplyr::count(hits, organism_term, name = "n_hits")
message(sprintf("Requests: %d; raw hits: %d", n_requests, nrow(hits)))

# One row per document; keep the organism terms that found it.
document <- hits |>
  dplyr::group_by(identifier) |>
  dplyr::mutate(organism_terms = paste(unique(organism_term), collapse = ";")) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::select(-organism_term)

field <- match_field_terms(paste(document$title, document$abstract, document$tags,
                                 sep = "\n"), field_stems)
document <- document |>
  dplyr::mutate(document_id = paste0("nva:", identifier), source = "nva",
                field_terms = field$field_terms, n_field_terms = field$n_field_terms,
                passes_terms = n_field_terms >= 1) |>
  dplyr::select(document_id, source, title, abstract, year, language, instance_type,
                publisher, series, series_number, doi, handle, funders, tags,
                n_open_pdf, open_pdf_file_id, open_pdf_name, open_pdf_size,
                open_pdf_license, organism_terms, field_terms, n_field_terms,
                passes_terms, retrieved_at)

message(sprintf("Unique documents: %d; passes_terms: %d", nrow(document),
                sum(document$passes_terms)))

dir.create(dirname(DB_PATH), showWarnings = FALSE, recursive = TRUE)
con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
DBI::dbWriteTable(con, "document", as.data.frame(document), overwrite = TRUE)
stopifnot(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM document")$n == nrow(document))
DBI::dbDisconnect(con)

print(term_counts[order(-term_counts$n_hits), ], n = Inf)
