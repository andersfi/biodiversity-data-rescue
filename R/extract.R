# Step 3, code part: fetch open PDFs from NVA, get text per page, select the
# pages the model reads, and derive simple facts from the whole text.

# ---- Page selection rules (edit here) -----------------------------------------
# All patterns are Perl regexes matched case-insensitively against page text.

FRONT_N_PAGES <- 4          # first pages with more than FRONT_MIN_CHARS characters
FRONT_MIN_CHARS <- 300
FRONT_WORD_MAX_PAGE <- 15   # front-matter words count only on the first pages
FRONT_WORDS <- c("forord", "føreord", "sammendrag", "samandrag", "referat", "abstract",
                 "summary", "takk", "oppdragsgiver", "oppdragsgjevar", "finansier")

METHOD_WORDS <- c("metode", "materiale og metoder?", "feltarbeid", "prøvetaking",
                  "innsamling", "stasjon", "lokalitet", "UTM", "koordinat", "el-?fiske",
                  "elektrofiske", "garn", "sparkeprøve", "transekt", "taksering", "feller",
                  "ruteanalyse", "befaring", "undersøkelsesområde", "områdebeskrivelse")
METHOD_N_PAGES <- 5
METHOD_MIN_SCORE <- 2       # distinct method words on the page

DATA_WORDS <- c("vedlegg", "artsliste", "Vannmiljø", "Artskart", "Artsobservasjoner",
                "GBIF", "rådata", "databasen?", "lagret i", "innrapportert")
DATA_N_PAGES <- 4

MAX_PAGES <- 14             # per document
MAX_PAGE_CHARS <- 5000      # each page is truncated to this
MIN_CHARS_PER_PAGE <- 200   # below this on average: no text layer (scanned)

# ---- Code-derived facts ------------------------------------------------------------

YEAR_MIN <- 1850
YEAR_MAX <- 2026
YEAR_MIN_COUNT <- 3
# UTM easting/northing pairs (6 + 7 digits, optional zone), MGRS references
# (32V NM 123 456), decimal degrees in the range of Norway, and degree-minute
# notation.
COORD_PATTERNS <- c(
  utm = "\\b(?:3[2-6][VW]?\\s*)?\\d{6}\\s*[EeØø]?[ ,;/]+\\d{7}\\s*[Nn]?\\b",
  mgrs = "\\b3[2-6][VW]\\s*[A-Z]{2}\\s*\\d{3,5}[ ,]*\\d{3,5}\\b",
  decimal = "\\b(?:5[7-9]|[67]\\d)[.,]\\d{3,}\\s*°?\\s*[NnS]?[ ,;/]+0?\\d{1,2}[.,]\\d{3,}\\b",
  dms = "\\b\\d{1,2}\\s*°\\s*\\d{1,2}(?:[.,]\\d+)?\\s*['’′]"
)
SPECIES_CANDIDATE <- "\\b[A-Z][a-z]{2,}\\s[a-z]{3,}\\b"
N_SPECIES_LISTED <- 30
TAXA_PARQUET <- "data/gbif/taxa.parquet"

NVA_API <- "https://api.nva.unit.no/publication"
FULLTEXT_DIR <- "data/fulltext/nva"

# ---- Fetch ---------------------------------------------------------------------------

#' Download the open PDF of one NVA publication to <dest_dir>/<identifier>.pdf
#' through the filelink route (JSON with a presigned URL in `id`). Skips a file
#' that is already present. Logs the fetch. Returns the file path.
nva_fetch_pdf <- function(identifier, file_id, dest_dir = FULLTEXT_DIR) {
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dest_dir, paste0(identifier, ".pdf"))
  if (file.exists(dest)) return(dest)
  req <- function(url) {
    httr2::request(url) |>
      httr2::req_user_agent("biodiversity-data-rescue (R httr2)") |>
      httr2::req_options(ipresolve = 1) |>
      httr2::req_timeout(300)
  }
  link_url <- sprintf("%s/%s/filelink/%s", NVA_API, identifier, file_id)
  link <- httr2::resp_body_json(httr2::req_perform(req(link_url)))
  if (is.null(link$id)) stop("No presigned URL in filelink response for ", identifier)
  tmp <- paste0(dest, ".part")
  resp <- httr2::req_perform(req(link$id), path = tmp)
  head <- readBin(tmp, "raw", 5)
  if (!identical(rawToChar(head), "%PDF-")) {
    unlink(tmp)
    stop("Downloaded file is not a PDF: ", identifier)
  }
  file.rename(tmp, dest)
  log_query("nva", call = "GET publication/{id}/filelink/{fileId} + presigned download",
            args = list(identifier = identifier, file_id = file_id),
            n_records = 1, n_expected = 1,
            bytes = file.size(dest), sha256 = file_sha256(dest), path = dest)
  dest
}

# ---- Text ----------------------------------------------------------------------------

#' Text per page with `pdftotext -layout -enc UTF-8`. Runs of three or more
#' spaces become two (keeps table columns apart, saves tokens); trailing
#' spaces go. Returns a character vector, one element per page.
pdf_pages <- function(path) {
  out <- suppressWarnings(system2("pdftotext", c("-layout", "-enc", "UTF-8", shQuote(path), "-"),
                                  stdout = TRUE, stderr = FALSE))
  status <- attr(out, "status") %||% 0L
  if (status != 0) stop("pdftotext failed with status ", status, " on ", path)
  split_pages(out)
}

#' Pages of an OCR text file written by ocr_pdf() (R/ocr.R).
ocr_pages <- function(txt_path) {
  split_pages(readLines(txt_path, warn = FALSE, encoding = "UTF-8"))
}

#' Lines of `pdftotext -layout` output (form feed between pages) to one
#' cleaned string per page.
split_pages <- function(lines) {
  txt <- paste(enc2utf8(lines), collapse = "\n")
  pages <- strsplit(txt, "\f", fixed = TRUE)[[1]]
  # pdftotext ends the last page with a form feed too.
  if (length(pages) && !nzchar(trimws(pages[length(pages)]))) pages <- pages[-length(pages)]
  pages <- gsub(" {3,}", "  ", pages)
  gsub("[ \t]+(\n|$)", "\\1", pages, perl = TRUE)
}

#' Characters on a page (as sent to the model, before truncation).
page_chars <- function(pages) nchar(trimws(pages))

# ---- Page selection ----------------------------------------------------------------

#' Which of `words` match each page (logical matrix pages x words).
word_hits <- function(pages, words) {
  m <- vapply(words, function(w) grepl(w, pages, ignore.case = TRUE, perl = TRUE),
              logical(length(pages)))
  matrix(m, nrow = length(pages), dimnames = list(NULL, words))
}

#' One row per page: page, n_chars, selected (0/1), reasons (`;`-joined).
#' Priority when more than MAX_PAGES are chosen: the first FRONT_N_PAGES text
#' pages, then method pages (best score first), then data pages, then other
#' front-matter pages.
select_pages <- function(pages) {
  n <- length(pages)
  n_chars <- page_chars(pages)
  reasons <- vector("list", n)
  add <- function(p, r) for (i in p) reasons[[i]] <<- c(reasons[[i]], r)

  front_first <- utils::head(which(n_chars > FRONT_MIN_CHARS), FRONT_N_PAGES)
  first <- seq_len(min(n, FRONT_WORD_MAX_PAGE))
  front_words <- first[rowSums(word_hits(pages[first], FRONT_WORDS)) > 0]
  add(front_first, "front")
  add(setdiff(front_words, front_first), "front")

  score <- rowSums(word_hits(pages, METHOD_WORDS))
  ok <- which(score >= METHOD_MIN_SCORE)
  method <- utils::head(ok[order(-score[ok], ok)], METHOD_N_PAGES)
  add(method, "method")

  # Earliest page per data word, outside the front pages (otherwise the table
  # of contents, which lists "Vedlegg", takes the place).
  front <- union(front_first, front_words)
  dh <- word_hits(pages, DATA_WORDS)
  dh[front, ] <- FALSE
  data <- unique(unlist(lapply(seq_len(ncol(dh)), function(j) utils::head(which(dh[, j]), 1))))
  data <- utils::head(data[order(-rowSums(dh)[data], data)], DATA_N_PAGES)
  add(data, "data")

  priority <- unique(c(front_first, method, data, front_words))
  selected <- sort(utils::head(priority, MAX_PAGES))
  data.frame(page = seq_len(n), n_chars = n_chars,
             selected = as.integer(seq_len(n) %in% selected),
             reasons = vapply(reasons, function(r) if (length(r)) paste(unique(r), collapse = ";")
                              else NA_character_, ""))
}

# ---- Facts ---------------------------------------------------------------------------

#' Distinct four-digit years that occur at least YEAR_MIN_COUNT times.
years_in_text <- function(text) {
  y <- as.integer(regmatches(text, gregexpr("(?<!\\d)(1[89]\\d\\d|20[0-2]\\d)(?!\\d)", text,
                                            perl = TRUE))[[1]])
  y <- y[y >= YEAR_MIN & y <= YEAR_MAX]
  tab <- table(y)
  join(sort(as.integer(names(tab)[tab >= YEAR_MIN_COUNT])))
}

#' Number of coordinate-like strings (sum over COORD_PATTERNS).
n_coordinate_like <- function(text) {
  sum(vapply(COORD_PATTERNS, function(p) {
    m <- gregexpr(p, text, perl = TRUE)[[1]]
    if (m[1] == -1) 0L else length(m)
  }, integer(1)))
}

#' Distinct Latin binomials in `text` that are species names in the GBIF taxa
#' table. `duck` is a DuckDB connection with a view `gbif_species(species)`.
gbif_species_in_text <- function(text, duck) {
  text <- gsub("-\n\\s*", "", text)          # join words hyphenated over lines
  text <- gsub("\\s+", " ", text)
  cand <- unique(regmatches(text, gregexpr(SPECIES_CANDIDATE, text, perl = TRUE))[[1]])
  if (!length(cand)) return(character())
  duckdb::duckdb_register(duck, "cand", data.frame(species = cand), overwrite = TRUE)
  on.exit(duckdb::duckdb_unregister(duck, "cand"))
  DBI::dbGetQuery(duck, "SELECT species FROM cand SEMI JOIN gbif_species USING (species)
                         ORDER BY species")$species
}

#' DuckDB connection with the distinct GBIF species names as a table.
gbif_species_db <- function(path = TAXA_PARQUET) {
  if (!file.exists(path)) stop("Not found: ", path)
  duck <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(duck, sprintf("CREATE TABLE gbif_species AS SELECT DISTINCT species
                                FROM read_parquet('%s') WHERE species IS NOT NULL", path))
  duck
}

# ---- Record for the model -----------------------------------------------------------

#' Metadata header followed by the selected pages.
extract_record <- function(doc, pages, chunk) {
  val <- function(x) if (is.na(x) || !nzchar(trimws(x))) "(not given)" else x
  header <- c(paste("Title:", val(doc$title)),
              paste("Publisher:", val(doc$publisher)),
              paste("Year:", val(as.character(doc$year))),
              paste("Funders in catalogue:", val(gsub(";", "; ", doc$funders))))
  sel <- chunk$page[chunk$selected == 1]
  body <- vapply(sel, function(p) sprintf("=== PAGE %d ===\n%s", p,
                                          substr(trimws(pages[p]), 1, MAX_PAGE_CHARS)), "")
  paste(c(header, "", body), collapse = "\n")
}

# ---- Code part per document ---------------------------------------------------------

#' Text pages of a PDF: pdftotext, or the OCR text (R/ocr.R) when pdftotext
#' gives too little text and an .ocr.txt exists. Returns list(pages,
#' text_source, ocr (the .ocr.json timing, or NULL)).
document_pages <- function(path) {
  pages <- pdf_pages(path)
  if (!length(pages)) stop("pdftotext returned no pages")
  ocr_txt <- ocr_txt_path(path)
  if (mean(page_chars(pages)) >= MIN_CHARS_PER_PAGE || !file.exists(ocr_txt)) {
    return(list(pages = pages, text_source = "pdftotext", ocr = NULL))
  }
  pages <- ocr_pages(ocr_txt)
  if (!length(pages)) stop("OCR text file has no pages: ", ocr_txt)
  list(pages = pages, text_source = "ocr",
       ocr = jsonlite::read_json(ocr_json_path(path), simplifyVector = TRUE))
}

#' Page selection, facts and model record for one document. `d` is one row of
#' `document`; `txt` comes from document_pages(). Status is "ok" when the text
#' has at least MIN_CHARS_PER_PAGE characters per page on average, else
#' "no_text_layer" (pdftotext) or "ocr_failed" (OCR). Returns list(chunk,
#' facts, record (NULL unless ok)).
document_code_part <- function(d, path, txt, duck, made_at) {
  pages <- txt$pages
  chunk <- select_pages(pages)
  text <- paste(pages, collapse = "\n")
  ok <- mean(chunk$n_chars) >= MIN_CHARS_PER_PAGE
  status <- if (ok) "ok" else if (txt$text_source == "ocr") "ocr_failed" else "no_text_layer"
  sel <- chunk$page[chunk$selected == 1]
  species <- gbif_species_in_text(text, duck)
  facts <- data.frame(
    document_id = d$document_id, n_pages = length(pages), n_chars_total = sum(chunk$n_chars),
    n_pages_selected = length(sel),
    n_chars_selected = sum(pmin(chunk$n_chars[sel], MAX_PAGE_CHARS)),
    status = status, pdf_bytes = file.size(path),
    years_in_text = years_in_text(text), n_coordinate_like = n_coordinate_like(text),
    n_gbif_species = length(species), gbif_species = join(utils::head(species, N_SPECIES_LISTED)),
    error = if (ok) NA_character_ else sprintf("%.0f characters per page on average",
                                               mean(chunk$n_chars)),
    made_at = made_at, text_source = txt$text_source,
    ocr_seconds = txt$ocr$seconds %||% NA_real_, ocr_pages = txt$ocr$pages %||% NA_integer_)
  list(chunk = data.frame(document_id = d$document_id, chunk), facts = facts,
       record = if (ok) extract_record(d, pages, chunk))
}
