# Step 0: GBIF cube for Norway, Svalbard and Jan Mayen via the GBIF SQL
# download API (rgbif).
# The SQL API is experimental; every download gets a DOI, which is logged.
#
# Two tables per area: the cube (counts per dataset, year, month, class, order,
# grid cell, ...) and a taxon name table (keys next to the interpreted,
# verbatim and vernacular names GBIF holds, per dataset).

# Country codes in scope: Norway (incl. offshore records in the economic zone)
# and Svalbard and Jan Mayen, which GBIF codes separately.
COUNTRY_CODES <- c("NO", "SJ")

CUBE_DIR <- "data/gbif"
CUBE_RAW_DIR <- "data/raw/gbif"

# EEA reference grid cell size in metres.
CELL_M <- 5000

# Taxon keys come back as text ids (e.g. "V2") although described as INT.
TEXT_COLS <- c("classkey", "orderkey", "taxonkey", "specieskey")

# Coordinate uncertainty as a coarse class. The grid cell is computed with
# uncertainty 0 (no random displacement of points), so this column carries it.
UNCERTAINTY_CLASS_SQL <- "CASE
    WHEN coordinateuncertaintyinmeters IS NULL THEN 'unknown'
    WHEN coordinateuncertaintyinmeters <= 100 THEN '0-100m'
    WHEN coordinateuncertaintyinmeters <= 1000 THEN '100m-1km'
    WHEN coordinateuncertaintyinmeters <= 10000 THEN '1-10km'
    ELSE '>10km' END"

#' WHERE clause shared by the cube and the taxon table. `extra_where` narrows
#' it (test area); NULL = all countries in COUNTRY_CODES. OR rather than IN,
#' which is untested on the SQL API.
where_sql <- function(extra_where = NULL) {
  country <- sprintf("(%s)", paste(sprintf("countrycode = '%s'", COUNTRY_CODES),
                                   collapse = " OR "))
  paste(c(country, "hascoordinate = TRUE", extra_where), collapse = "\n  AND ")
}

#' SQL for the cube. classkey/orderkey are keys in GBIF's current backbone;
#' class and order names are kept next to them.
cube_sql <- function(extra_where = NULL) {
  dims <- "countrycode, datasetkey, publishingorgkey, institutioncode, basisofrecord, occurrencestatus,
  \"year\", \"month\", classkey, \"class\", orderkey, \"order\""
  cell <- sprintf("GBIF_EEARGCode(%d, decimallatitude, decimallongitude, 0)", CELL_M)
  sprintf("SELECT
  %s,
  %s AS eeacellcode,
  %s AS uncertaintyclass,
  COUNT(*) AS n_records,
  COUNT(taxonkey) AS n_records_matched,
  COUNT(DISTINCT specieskey) AS n_species,
  MIN(eventdategte) AS first_eventdate,
  MAX(eventdatelte) AS last_eventdate
FROM occurrence
WHERE %s
GROUP BY
  %s,
  %s,
  %s", dims, cell, UNCERTAINTY_CLASS_SQL, where_sql(extra_where), dims, cell,
          UNCERTAINTY_CLASS_SQL)
}

#' SQL for the taxon name table: per dataset, the taxon keys with the
#' interpreted, verbatim and vernacular names, so that names in reports can be
#' looked up.
taxa_sql <- function(extra_where = NULL) {
  dims <- "countrycode, datasetkey, taxonkey, specieskey, taxonrank, kingdom, \"class\", \"order\", family,
  species, scientificname, v_scientificname, vernacularname"
  sprintf("SELECT
  %s,
  COUNT(*) AS n_records
FROM occurrence
WHERE %s
GROUP BY
  %s", dims, where_sql(extra_where), dims)
}

#' Records per facet value (`datasetKey` or `year`) from occurrence search for
#' the same filter (all COUNTRY_CODES in one request, rgbif's ";" syntax), to
#' check a table against. Returns columns `key`, `n_search` with the search
#' total as attribute "total".
#'
#' Stops if the combined total differs from the sum of single-country totals, or
#' if the facets do not add up. Records without a year are not in the
#' year facet, so for `year` the facet sum is compared with a search that also
#' requires a year. rgbif's occ_search() defaults to occurrenceStatus = "PRESENT";
#' the SQL filter has no such restriction, so absences are included here too.
expected_counts <- function(search_args, facet = c("datasetKey", "year")) {
  facet <- match.arg(facet)
  search <- function(extra = list(), ...) {
    do.call(rgbif::occ_search, c(list(hasCoordinate = TRUE, occurrenceStatus = NULL,
                                      limit = 0, ...), search_args, extra))
  }
  countries <- paste(COUNTRY_CODES, collapse = ";")
  res <- search(country = countries, facet = facet, facetLimit = 100000)
  n <- res$meta$count
  if (is.null(n)) stop("GBIF occurrence search returned no count")
  n_single <- vapply(COUNTRY_CODES, function(cc) {
    m <- search(country = cc)$meta$count
    if (is.null(m)) stop("GBIF occurrence search returned no count for ", cc)
    as.numeric(m)
  }, numeric(1))
  if (sum(n_single) != n) {
    stop(sprintf("Search for %s reports %s, single countries sum to %s", countries, n,
                 sum(n_single)))
  }
  fc <- res$facets[[facet]]
  if (is.null(fc)) stop("GBIF occurrence search returned no ", facet, " facet")
  out <- data.frame(key = as.character(fc$name), n_search = as.numeric(fc$count))
  n_facet_total <- n
  if (facet == "year") {
    if ("year" %in% names(search_args)) stop("search_args already filter on year")
    n_facet_total <- search(list(year = "1,3000"), country = countries)$meta$count
    if (is.null(n_facet_total)) stop("GBIF occurrence search returned no count")
  }
  if (sum(out$n_search) != n_facet_total) {
    stop(sprintf("%s facets sum to %s, search total is %s (facetLimit too low?)",
                 facet, sum(out$n_search), n_facet_total))
  }
  attr(out, "total") <- n
  attr(out, "total_with_facet") <- n_facet_total
  out
}

#' Submit an SQL download and return its key. Credentials come from GBIF_USER,
#' GBIF_PWD and GBIF_EMAIL in ~/.Renviron (read by rgbif).
submit_sql_download <- function(sql) {
  for (v in c("GBIF_USER", "GBIF_PWD", "GBIF_EMAIL")) {
    if (!nzchar(Sys.getenv(v))) stop(v, " is not set in ~/.Renviron")
  }
  key <- as.character(rgbif::occ_download_sql(sql, format = "SQL_TSV_ZIP"))
  message("Submitted GBIF SQL download ", key)
  key
}

#' Wait for a submitted download, fetch the zip and return key, DOI and path.
wait_download <- function(key) {
  message("Waiting for ", key, " ...")
  meta <- rgbif::occ_download_wait(key, status_ping = 30, quiet = TRUE)
  if (meta$status != "SUCCEEDED") stop("Download ", key, " ended with status ", meta$status)
  existing_download(key)
}

#' Key, DOI, row count and local zip of a finished download (fetched if missing).
existing_download <- function(key) {
  meta <- rgbif::occ_download_meta(key)
  if (meta$status != "SUCCEEDED") stop("Download ", key, " has status ", meta$status)
  zip <- file.path(CUBE_RAW_DIR, paste0(key, ".zip"))
  if (!file.exists(zip)) {
    dir.create(CUBE_RAW_DIR, recursive = TRUE, showWarnings = FALSE)
    zip <- as.character(rgbif::occ_download_get(key, path = CUBE_RAW_DIR))
  }
  list(key = key, doi = meta$doi, zip = zip, total_records = meta$totalRecords,
       sql = meta$request$sql %||% NA_character_)
}

#' Stop unless a finished download was made with this SQL query.
check_same_sql <- function(dl, sql) {
  if (!identical(gsub("\\s+", " ", trimws(dl$sql)), gsub("\\s+", " ", trimws(sql)))) {
    stop("Download ", dl$key, " was made with a different SQL query")
  }
}

#' Read the TSV in the zip with DuckDB, compare record counts with occurrence
#' search, write Parquet and a check table next to it. Returns a summary list.
#'
#' `expected` is a named list of `expected_counts()` results, names being the
#' check dimension: "dataset" (column datasetkey) and/or "year" (column year).
#'
#' The SQL table includes records whose name did not match the backbone (NULL
#' taxonkey); occurrence search leaves them out (2026-11-21, national: 2.8 M of
#' 97 M records). So search is compared with the matched count only: the cube's
#' n_records_matched, or n_records where taxonkey is not NULL in the taxon
#' table. The matched count is expected to agree with search; small differences
#' can remain because the SQL snapshot and the search index are not updated at
#' the same moment. Stops if the row count differs from GBIF's, or if the total
#' matched count differs from search by more than `tolerance` (relative).
#' Per-key differences are kept in the check table for inspection.
write_cube <- function(dl, out_file, expected, tolerance = 0.005) {
  exdir <- file.path(tempdir(), dl$key)
  files <- utils::unzip(dl$zip, exdir = exdir)
  tsv <- files[grepl("\\.(csv|tsv|txt)$", files, ignore.case = TRUE)]
  if (length(tsv) != 1) stop("Expected one data file in ", dl$zip, ", found: ",
                             paste(basename(files), collapse = ", "))
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  header <- strsplit(readLines(tsv, n = 1), "\t")[[1]]
  text_cols <- intersect(TEXT_COLS, header)
  types <- if (length(text_cols)) sprintf(", types = {%s}", paste(
    sprintf("'%s': 'VARCHAR'", text_cols), collapse = ", ")) else ""
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE cube AS SELECT * FROM read_csv('%s', delim = '\t', header = true,
       quote = '', sample_size = -1%s)", tsv, types))
  # Dates arrive as Unix seconds.
  fields <- DBI::dbListFields(con, "cube")
  fix <- c(first_eventdate = "CAST(make_timestamp(CAST(first_eventdate AS BIGINT) * 1000000) AS DATE)",
           last_eventdate = "CAST(make_timestamp(CAST(last_eventdate AS BIGINT) * 1000000) AS DATE)")
  fix <- fix[names(fix) %in% fields]
  if (length(fix)) DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE TABLE cube AS SELECT * REPLACE (%s) FROM cube",
    paste(sprintf("%s AS %s", fix, names(fix)), collapse = ", ")))
  # Records with a backbone match: cube column, or taxon table rows with a taxonkey.
  matched <- if ("n_records_matched" %in% fields) {
    "COALESCE(SUM(n_records_matched), 0)"
  } else if ("taxonkey" %in% fields) {
    "COALESCE(SUM(n_records) FILTER (WHERE taxonkey IS NOT NULL), 0)"
  } else stop("Table has neither n_records_matched nor taxonkey")
  s <- as.list(DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n_rows, SUM(n_records) AS n_records, %s AS n_matched,
            COUNT(DISTINCT datasetkey) AS n_datasets FROM cube", matched)))
  s$n_unmatched <- s$n_records - s$n_matched
  if ("eeacellcode" %in% fields) {
    s$n_cells <- DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT eeacellcode) AS n FROM cube")$n
  }
  if (!is.null(dl$total_records) && !is.na(dl$total_records) &&
      dl$total_records != s$n_rows) {
    stop(sprintf("Table has %d rows, GBIF reports %s", s$n_rows, dl$total_records))
  }

  columns <- c(dataset = "datasetkey", year = "\"year\"")
  check <- do.call(rbind, lapply(names(expected), function(dim) {
    col <- columns[[dim]]
    cube_counts <- DBI::dbGetQuery(con, sprintf(
      "SELECT CAST(%s AS VARCHAR) AS key, SUM(n_records) AS n_table,
              %s AS n_matched FROM cube
       WHERE %s IS NOT NULL GROUP BY 1", col, matched, col))
    m <- merge(cube_counts, expected[[dim]], by = "key", all = TRUE)
    for (v in c("n_table", "n_matched", "n_search")) m[[v]][is.na(m[[v]])] <- 0
    m$diff <- m$n_matched - m$n_search
    m <- m[order(-abs(m$diff), -m$n_table), ]
    data.frame(dimension = dim, m)
  }))
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  check_file <- sub("\\.parquet$", "_check.tsv", out_file)
  utils::write.table(check, check_file, sep = "\t", row.names = FALSE, quote = FALSE)

  n_expected <- attr(expected[[1]], "total")
  s$n_expected <- n_expected
  s$rel_diff <- (s$n_matched - n_expected) / n_expected
  s$n_differing <- as.list(tapply(check$diff != 0, check$dimension, sum))
  if ("year" %in% names(expected)) {
    s$n_records_null_year <- DBI::dbGetQuery(con,
      "SELECT COALESCE(SUM(n_records), 0) AS n FROM cube WHERE \"year\" IS NULL")$n
  }
  s$check_file <- check_file
  if (abs(s$rel_diff) > tolerance) {
    stop(sprintf(paste0("Table has %s matched records (%s in all), search reports %s ",
                        "(%.3f %%, tolerance %.3f %%); see %s"),
                 s$n_matched, s$n_records, n_expected, 100 * s$rel_diff, 100 * tolerance, check_file))
  }
  DBI::dbExecute(con, sprintf("COPY cube TO '%s' (FORMAT parquet)", out_file))
  s
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
