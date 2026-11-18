# GBIF baseline for the scope in config/scope.yaml: occurrences per dataset,
# with type, years, sampling protocols, eventID presence and basisOfRecord.
# Writes reports/gbif_baseline_<scope>_<date>.tsv and compares it with the
# reference table goldset/reference/gbif_ept_trondheim_2026-11-18.tsv.
# GBIF changes over time: differences are reported, not tuned away.
#
# Usage: Rscript scripts/02_gbif_baseline.R

source("R/db.R")
source("R/sources_gbif.R")

REFERENCE <- "goldset/reference/gbif_ept_trondheim_2026-11-18.tsv"

scope <- read_scope()
taxa <- scope_taxon_keys(scope)
gid <- scope$region$gadm_gid
cat(sprintf("Scope %s: taxonKeys %s, gadmGid %s\n", scope$name, paste(taxa, collapse = ","), gid))

con <- db_connect()
on.exit(db_disconnect(con))
db_init(con)
run_id <- db_run_start(con, kind = "gbif", step = "gbif_baseline",
                       query = jsonlite::toJSON(list(taxonKey = taxa, gadmGid = gid), auto_unbox = TRUE))

# The three orders are disjoint, so counts per taxon can be summed.
base_args <- function(k) {
  a <- list(taxonKey = k, gadmGid = gid)
  if (!is.null(scope$period$start)) a$year <- paste0(scope$period$start, ",", scope$period$end)
  a
}

per_taxon <- lapply(taxa, function(k) gbif_facets(base_args(k), facets = "datasetKey"))
total <- sum(vapply(per_taxon, `[[`, 0, "count"))
by_ds <- dplyr::bind_rows(lapply(per_taxon, function(x) x$facets$datasetKey)) |>
  dplyr::group_by(dataset_key = name) |>
  dplyr::summarise(n = sum(count), .groups = "drop") |>
  dplyr::arrange(dplyr::desc(n))
if (sum(by_ds$n) != total) {
  stop(sprintf("Facet sum %d differs from total %d (facetLimit too low?)", sum(by_ds$n), total))
}
cat(sprintf("%d records in %d datasets\n", total, nrow(by_ds)))

# One facet call per taxon key and dataset, summed over the three disjoint orders.
DS_FACETS <- c("year", "samplingProtocol", "basisOfRecord")
dataset_facets <- function(key) {
  per <- lapply(taxa, function(k) gbif_facets(c(base_args(k), list(datasetKey = key)), DS_FACETS))
  sums <- lapply(DS_FACETS, function(f) {
    dplyr::bind_rows(lapply(per, function(x) x$facets[[f]])) |>
      dplyr::group_by(name) |> dplyr::summarise(count = sum(count), .groups = "drop") |>
      dplyr::arrange(dplyr::desc(count), name)
  })
  c(setNames(sums, DS_FACETS), list(n_per_taxon = vapply(per, `[[`, 0, "count")))
}

rows <- lapply(seq_len(nrow(by_ds)), function(i) {
  key <- by_ds$dataset_key[i]
  meta <- gbif_dataset_meta(key)
  fc <- dataset_facets(key)
  if (sum(fc$n_per_taxon) != by_ds$n[i]) stop("Count mismatch for dataset ", key)
  yr <- fc$year; pr <- fc$samplingProtocol; bo <- fc$basisOfRecord
  # eventID presence in a sample of up to 3 records, filled across the taxa in order.
  smp <- NULL
  for (k in taxa[fc$n_per_taxon > 0]) {
    need <- 3 - NROW(smp)
    if (need == 0) break
    smp <- dplyr::bind_rows(smp, rgbif::occ_search(taxonKey = k, gadmGid = gid,
                                                   datasetKey = key, limit = need)$data)
  }
  ev <- if ("eventID" %in% names(smp)) sum(!is.na(smp$eventID) & nzchar(smp$eventID)) else 0
  db_upsert_gbif_dataset(con, c(as.list(meta), list(
    fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), run_id = run_id)))
  years <- sort(as.integer(yr$name))
  data.frame(
    datasetKey = key, n = by_ds$n[i], title = meta$title, type = meta$dataset_type,
    publisher = meta$publisher,
    years = if (length(years)) sprintf("%d-%d", min(years), max(years)) else "",
    n_years = length(years),
    protocols = paste(sprintf("%s(%d)", head(pr$name, 3), head(pr$count, 3)), collapse = "; "),
    eventID_in_sample = sprintf("%d/%d", ev, nrow(smp)),
    basis = paste(bo$name, collapse = ",")
  )
})
baseline <- dplyr::bind_rows(rows)
db_run_finish(con, run_id, n_records = total)

dir.create("reports", showWarnings = FALSE)
out <- sprintf("reports/gbif_baseline_%s_%s.tsv", scope$name, Sys.Date())
readr::write_tsv(baseline, out, na = "")
cat("Wrote", out, "\n\n")

# ---- comparison with the reference table ------------------------------------
ref <- readr::read_tsv(REFERENCE, col_types = readr::cols(.default = "c"))
cmp <- dplyr::full_join(
  ref |> dplyr::transmute(datasetKey, title_ref = title, n_ref = as.integer(n),
                          years_ref = years, n_years_ref = as.integer(n_years)),
  baseline |> dplyr::transmute(datasetKey, title_now = title, n_now = n,
                               years_now = years, n_years_now = n_years),
  by = "datasetKey") |>
  dplyr::mutate(diff = n_now - n_ref,
                title = dplyr::coalesce(title_now, title_ref)) |>
  dplyr::arrange(dplyr::desc(dplyr::coalesce(n_now, n_ref)))
cmp_out <- sprintf("reports/gbif_baseline_comparison_%s.tsv", Sys.Date())
readr::write_tsv(cmp, cmp_out, na = "")
cat(sprintf("Reference %s: %d records in %d datasets\n", basename(REFERENCE),
            sum(as.integer(ref$n)), nrow(ref)))
cat(sprintf("Now:       %d records in %d datasets\n\n", total, nrow(baseline)))
changed <- cmp |> dplyr::filter(is.na(diff) | diff != 0 | years_ref != years_now)
if (nrow(changed)) {
  cat("Differences (see", cmp_out, "):\n")
  print(as.data.frame(changed[, c("datasetKey", "title", "n_ref", "n_now", "diff",
                                  "years_ref", "years_now")]), row.names = FALSE)
} else {
  cat("No differences per dataset.\n")
}
