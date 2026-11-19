# GBIF occurrence and registry access via rgbif (read-only API).
# Every call is logged in runs/queries.jsonl and its parsed response kept as
# JSON in data/raw/gbif/ (CLAUDE.md, Data policy).

RAW_GBIF_DIR <- "data/raw/gbif"
QUERY_LOG <- "runs/queries.jsonl"

read_scope <- function(path = "config/scope.yaml") yaml::read_yaml(path)

scope_taxon_keys <- function(scope) vapply(scope$taxa$gbif_taxon_keys, `[[`, 0, "key")

.log_query <- function(source, call, args, n_records, n_expected, raw_file) {
  dir.create(dirname(QUERY_LOG), showWarnings = FALSE, recursive = TRUE)
  entry <- list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                source = source, call = call, args = args,
                n_records = n_records, n_expected = n_expected, raw_file = raw_file)
  cat(as.character(jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null")), "\n",
      file = QUERY_LOG, append = TRUE, sep = "")
}

.save_raw <- function(obj, call, args) {
  dir.create(RAW_GBIF_DIR, showWarnings = FALSE, recursive = TRUE)
  key <- digest::digest(list(call, args), algo = "sha256")
  f <- file.path(RAW_GBIF_DIR, sprintf("%s_%s_%s.json", call,
                                       format(Sys.time(), "%Y%m%dT%H%M%S"), substr(key, 1, 12)))
  jsonlite::write_json(obj, f, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  f
}

#' Occurrence count plus facets for one query. Explicit failure on API errors.
gbif_facets <- function(args, facets, facet_limit = 1000) {
  a <- c(args, list(limit = 0, facet = facets, facetLimit = facet_limit))
  res <- do.call(rgbif::occ_search, a)
  n <- res$meta$count
  if (is.null(n)) stop("GBIF returned no count for ", jsonlite::toJSON(args, auto_unbox = TRUE))
  raw <- .save_raw(list(meta = res$meta, facets = res$facets), "occ_search_facets", a)
  .log_query("gbif", "rgbif::occ_search", a, n_records = n, n_expected = n, raw_file = raw)
  out <- lapply(facets, function(f) {
    x <- res$facets[[f]]
    if (is.null(x) || !nrow(x)) return(data.frame(name = character(), count = integer()))
    data.frame(name = as.character(x$name), count = as.integer(x$count))
  })
  names(out) <- facets
  list(count = n, facets = out)
}

#' Fetch all occurrences for a query, paging until the API's total is reached.
#' Stops if the number fetched differs from the total (rule 7).
gbif_occurrences <- function(args, page_size = 300, max_records = 100000) {
  n_total <- gbif_facets(args, facets = character())$count
  if (n_total > max_records) stop("Query returns ", n_total, " records; use GBIF download instead.")
  pages <- list()
  start <- 0
  while (start < n_total) {
    res <- do.call(rgbif::occ_search, c(args, list(limit = page_size, start = start)))
    if (is.null(res$data) || !nrow(res$data)) stop("Empty page at start = ", start)
    pages[[length(pages) + 1]] <- res$data
    start <- start + nrow(res$data)
  }
  df <- dplyr::bind_rows(pages)
  if (nrow(df) != n_total) stop(sprintf("Fetched %d records, API reports %d", nrow(df), n_total))
  dup <- sum(duplicated(df$key))
  if (dup) stop(dup, " duplicated occurrence keys across pages (index changed while paging?)")
  raw <- .save_raw(df, "occ_search_records", args)
  .log_query("gbif", "rgbif::occ_search (paged)", args, n_records = nrow(df),
             n_expected = n_total, raw_file = raw)
  df
}

#' Dataset metadata from the GBIF registry.
gbif_dataset_meta <- function(key) {
  d <- rgbif::dataset_get(key)
  org <- rgbif::organizations(uuid = d$publishingOrganizationKey)$data
  raw <- .save_raw(list(dataset = d, organization = org), "dataset_get", list(uuid = key))
  .log_query("gbif", "rgbif::dataset_get", list(uuid = key), 1, 1, raw)
  data.frame(dataset_key = key, title = d$title, dataset_type = d$type,
             publisher = org$title, publisher_key = d$publishingOrganizationKey,
             doi = d$doi %||% NA_character_)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
