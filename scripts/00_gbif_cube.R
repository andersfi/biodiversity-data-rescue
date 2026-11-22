# Step 0: GBIF cube for Norway, Svalbard and Jan Mayen (CLAUDE.md, "GBIF cube").
# Country codes NO and SJ (COUNTRY_CODES in R/gbif_cube.R); both tables carry
# countrycode as a dimension so the two can be told apart.
#
#   Rscript scripts/00_gbif_cube.R test       box 63-64 N, 10-11.5 E (around Trondheim), all years
#   Rscript scripts/00_gbif_cube.R national   all of NO and SJ
#
# Each mode makes two SQL downloads: the cube (5 km EEA grid) and the taxon name
# table. Outputs in data/gbif/: cube[_test_trondheim_box].parquet and
# taxa[_test_trondheim_box].parquet, each with a *_check.tsv comparing record
# counts with occurrence search (cube: per dataset and per year; taxa: per
# dataset).
#
# Optional second and third arguments are the keys of finished cube and taxa
# downloads: they are checked and written again without new downloads
# (e.g. `test 0007104-261118162104854 0007105-261118162104854`).
#
# Only run `national` after Anders has approved the test.

source("R/log.R")
source("R/gbif_cube.R")

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args)) args[1] else "test"
existing_keys <- if (length(args) > 1) args[-1] else character()
if (!length(existing_keys) %in% c(0, 2)) stop("Give both a cube and a taxa key, or none")

# A coordinate box, not a county: GADM level-1 assignment in the SQL table and in
# occurrence search differ near county borders, so a county cannot be checked
# against search counts (2026-11-21, download 0007092-261118162104854).
# BETWEEN is not supported by the GBIF SQL API.
if (mode == "test") {
  where <- c("decimallatitude >= 63", "decimallatitude <= 64",
             "decimallongitude >= 10", "decimallongitude <= 11.5")
  search_args <- list(decimalLatitude = "63,64", decimalLongitude = "10,11.5")
  suffix <- "_test_trondheim_box"
} else if (mode == "national") {
  where <- NULL
  search_args <- list()
  suffix <- ""
} else {
  stop("Unknown mode: ", mode, " (test, national)")
}

tables <- list(
  cube = list(sql = cube_sql(where), dims = c("dataset", "year")),
  taxa = list(sql = taxa_sql(where), dims = "dataset")
)

by_dataset <- expected_counts(search_args, "datasetKey")
by_year <- expected_counts(search_args, "year")
cat("Expected records (occurrence search):", attr(by_dataset, "total"), "\n")

# Submit both downloads before waiting for either.
if (length(existing_keys)) {
  keys <- setNames(existing_keys, names(tables))
} else {
  keys <- vapply(tables, function(t) submit_sql_download(t$sql), character(1))
}

for (name in names(tables)) {
  t <- tables[[name]]
  cat("\n", name, " SQL:\n", t$sql, "\n\n", sep = "")
  if (length(existing_keys)) {
    dl <- existing_download(keys[[name]])
    check_same_sql(dl, t$sql)
  } else {
    dl <- wait_download(keys[[name]])
    log_query("gbif", "rgbif::occ_download_sql", list(mode = mode, table = name, sql = t$sql),
              n_expected = attr(by_dataset, "total"), download_key = dl$key, doi = dl$doi,
              raw_file = dl$zip)
  }
  out <- file.path(CUBE_DIR, paste0(name, suffix, ".parquet"))
  expected <- list(dataset = by_dataset, year = by_year)[t$dims]
  s <- write_cube(dl, out, expected)
  log_query("gbif", "cube check", list(mode = mode, table = name, download_key = dl$key),
            n_records = s$n_records, n_matched = s$n_matched, n_unmatched = s$n_unmatched,
            n_expected = s$n_expected, n_rows = s$n_rows,
            rel_diff = s$rel_diff, n_differing = s$n_differing,
            n_records_null_year = s$n_records_null_year, doi = dl$doi, out_file = out)
  cat(sprintf(paste0("%s: download %s (DOI %s)\nRows: %s; records: %s; matched: %s; unmatched: %s\n",
                     "Search: %s; matched - search: %+.0f (%+.3f %%)\n",
                     "Keys differing: %s (see %s)\nDatasets: %s; cells: %s; NULL-year records: %s\n",
                     "Wrote %s\n"),
              name, dl$key, dl$doi, s$n_rows, s$n_records, s$n_matched, s$n_unmatched,
              s$n_expected, s$n_matched - s$n_expected, 100 * s$rel_diff,
              paste(names(s$n_differing), unlist(s$n_differing), sep = "=", collapse = ", "),
              s$check_file, s$n_datasets, s$n_cells %||% "-", s$n_records_null_year %||% "-", out))
}
