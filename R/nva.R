# Step 1, source NVA (Nasjonalt vitenarkiv): search API for reports.
# GET https://api.nva.unit.no/search/resources, open, no key.
#
# `query` searches all metadata; several words are AND-ed; there is no OR, so
# each organism term is its own request series. Paging uses sort=identifier and
# the `nextSearchAfterResults` link (search_after), which has no 10,000 limit.
# A series ends at a page with no hits or no next link.

NVA_URL <- "https://api.nva.unit.no/search/resources"
NVA_PAGE_SIZE <- 100
NVA_MAX_TERM_HITS <- 30000
NVA_RAW_DIR <- "data/raw/nva"

# Reports are selected by publication instance type, not by contextType=Report:
# many reports (e.g. older NIVA reports) are ReportResearch with context Book
# and are missed by contextType=Report (158,083 vs 174,616 on 2026-11-22).
# A comma-separated instanceType is OR-ed by the API.
NVA_REPORT_TYPES <- c("ReportResearch", "ReportBasic", "ReportWorkingPaper",
                      "ReportPolicy", "ConferenceReport", "ReportBookOfAbstract")

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Base request: IPv4 only (IPv6 hangs on this machine), about 3 requests per
#' second, retries on transient errors.
nva_req <- function(url) {
  httr2::request(url) |>
    httr2::req_headers(Accept = "application/json") |>
    httr2::req_user_agent("biodiversity-data-rescue (R httr2)") |>
    httr2::req_options(ipresolve = 1) |>
    httr2::req_timeout(120) |>
    httr2::req_throttle(capacity = 3, fill_time_s = 1) |>
    httr2::req_retry(max_tries = 5)
}

#' Fetch all report hits for one term. Each raw page is saved gzip-compressed
#' as <raw_dir>/<term>_<page>.json.gz. Returns the flattened hits (one row
#' per hit), the API's totalHits and the number of requests. Stops when the
#' number fetched differs from totalHits.
nva_fetch_term <- function(term, raw_dir, max_hits = NVA_MAX_TERM_HITS) {
  dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
  file_stem <- gsub("[^[:alnum:]]+", "_", term)
  req <- nva_req(NVA_URL) |>
    httr2::req_url_query(query = term,
                         instanceType = paste(NVA_REPORT_TYPES, collapse = ","),
                         size = NVA_PAGE_SIZE, sort = "identifier")
  pages <- list()
  total <- NULL
  page <- 0
  repeat {
    page <- page + 1
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_raw(resp)
    con <- gzfile(file.path(raw_dir, sprintf("%s_%04d.json.gz", file_stem, page)), "wb")
    writeBin(body, con)
    close(con)
    d <- jsonlite::fromJSON(rawToChar(body), simplifyVector = FALSE)
    if (is.null(total)) {
      total <- d$totalHits
      if (total > max_hits) {
        stop(sprintf("Term '%s' has %d hits (limit %d); stopping", term, total, max_hits))
      }
    } else if (d$totalHits != total) {
      stop(sprintf("Term '%s': totalHits changed from %d to %d while paging",
                   term, total, d$totalHits))
    }
    if (length(d$hits) == 0) break
    pages[[page]] <- dplyr::bind_rows(lapply(d$hits, nva_flatten_hit))
    # The last page sometimes has no next link, sometimes one that returns no
    # hits; both end the series and the count check below decides.
    if (is.null(d$nextSearchAfterResults)) break
    req <- nva_req(d$nextSearchAfterResults)
  }
  hits <- dplyr::bind_rows(pages)
  if (nrow(hits) != total) {
    stop(sprintf("Term '%s': fetched %d hits, API reports %d", term, nrow(hits), total))
  }
  if (nrow(hits)) hits$organism_term <- term
  list(hits = hits, total = total, n_requests = page)
}

#' One hit as a one-row list with the fields of the `document` table that come
#' from NVA.
nva_flatten_hit <- function(h) {
  # purrr::pluck matches names exactly; `$` would partially match, e.g.
  # `ctx$series` returns `seriesNumber` when there is no `series`.
  get <- function(x, ...) purrr::pluck(x, ..., .default = NULL)
  chr <- function(x, ...) as.character(get(x, ...) %||% NA_character_)
  ctx <- get(h, "entityDescription", "reference", "publicationContext")

  handle <- get(h, "handle")
  if (is.null(handle)) {
    handles <- Filter(function(x) identical(get(x, "type"), "HandleIdentifier"),
                      get(h, "additionalIdentifiers") %||% list())
    if (length(handles)) handle <- get(handles[[1]], "value")
  }

  funders <- vapply(get(h, "fundings") %||% list(), function(f) {
    src <- get(f, "source", "labels", "nb") %||% get(f, "source", "labels", "en") %||%
      get(f, "source", "identifier") %||% ""
    paste(c(src, get(f, "identifier")), collapse = ": ")
  }, character(1))

  files <- get(h, "associatedArtifacts") %||% list()
  open_pdf <- Filter(function(a) identical(get(a, "type"), "OpenFile") &&
                       identical(get(a, "mimeType"), "application/pdf"), files)
  pdf <- NULL
  if (length(open_pdf)) {
    sizes <- vapply(open_pdf, function(a) as.numeric(get(a, "size") %||% NA), numeric(1))
    pdf <- open_pdf[[which.max(replace(sizes, is.na(sizes), -1))]]
  }
  tags <- unlist(get(h, "entityDescription", "tags"))

  list(
    identifier = get(h, "identifier"),
    title = chr(h, "entityDescription", "mainTitle"),
    abstract = chr(h, "entityDescription", "abstract"),
    year = as.integer(get(h, "entityDescription", "publicationDate", "year") %||% NA),
    language = sub(".*/", "", chr(h, "entityDescription", "language")),
    instance_type = chr(h, "entityDescription", "reference", "publicationInstance", "type"),
    publisher = chr(ctx, "publisher", "name"),
    series = chr(ctx, "series", "name"),
    series_number = chr(ctx, "seriesNumber"),
    doi = as.character(get(h, "doi") %||% get(h, "entityDescription", "reference", "doi") %||%
                         NA_character_),
    handle = as.character(handle %||% NA_character_),
    funders = if (length(funders)) paste(funders, collapse = ";") else NA_character_,
    tags = if (length(tags)) paste(tags, collapse = ";") else NA_character_,
    n_open_pdf = length(open_pdf),
    open_pdf_file_id = chr(pdf, "identifier"),
    open_pdf_name = chr(pdf, "name"),
    open_pdf_size = as.numeric(get(pdf, "size") %||% NA),
    open_pdf_license = chr(pdf, "license", "name")
  )
}

#' Match field-term regex stems case-insensitively against `text`. Returns the
#' matched stems per element, `;`-separated (NA when none), and their count.
match_field_terms <- function(text, stems) {
  text <- tolower(ifelse(is.na(text), "", text))
  hit <- vapply(stems, function(s) grepl(tolower(s), text, perl = TRUE),
                logical(length(text)))
  hit <- matrix(hit, nrow = length(text))
  matched <- apply(hit, 1, function(r) if (any(r)) paste(stems[r], collapse = ";") else NA_character_)
  list(field_terms = matched, n_field_terms = as.integer(rowSums(hit)))
}
