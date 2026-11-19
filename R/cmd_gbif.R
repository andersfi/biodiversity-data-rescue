# Verb `gbif`: GBIF baseline and survey groups for the scope in config/scope.yaml.
# The only verb that uses the network (read-only GBIF API). Writes
# runs/gbif/<date>_<label>/ with baseline.tsv (records per dataset),
# comparison.tsv (against the previous gbif run) and survey_groups.tsv
# (dataset × datasetName × recordedBy × year). Full occurrence records go to
# data/runs/gbif/<id>/. GBIF changes over time: differences are reported, not
# tuned away.

# Datasets where surveys can be told apart (dataset × collector × period ×
# locality × eventID). The names are used as `source` in survey_groups.tsv; an
# aggregator must have the same name as its knowledge card id.
SURVEY_GROUP_DATASETS <- c(
  ntnu_benthic = "33591b80-0e31-480c-82ce-2f57211b10e6",
  vannmiljo    = "46293000-ddd1-4c32-a1e7-b5e793223ecd"
)
SURVEY_RECORD_FIELDS <- c(
  "key", "datasetKey", "datasetName", "recordedBy", "identifiedBy", "institutionCode",
  "eventID", "parentEventID", "eventDate", "year", "month", "locality", "waterBody",
  "locationID", "municipality", "stateProvince", "decimalLatitude", "decimalLongitude",
  "samplingProtocol", "samplingEffort", "basisOfRecord", "order", "scientificName",
  "individualCount", "occurrenceRemarks", "eventRemarks", "fieldNumber", "projectId")

cmd_gbif <- function(args) {
  label <- if (length(args)) args[1] else "baseline"
  scope <- read_scope()
  previous <- latest_run("gbif", require_file = "baseline.tsv")
  run <- run_start("gbif", label, args)
  con <- db_connect()
  on.exit(db_disconnect(con))
  db_init(con)

  baseline <- gbif_baseline(con, scope, run)
  readr::write_tsv(baseline, file.path(run$dir, "baseline.tsv"), na = "")
  cmp <- if (is.null(previous)) NULL else {
    gbif_compare(read_tsv_chr(file.path(previous$dir, "baseline.tsv")), baseline)
  }
  if (!is.null(cmp)) readr::write_tsv(cmp, file.path(run$dir, "comparison.tsv"), na = "")
  groups <- gbif_survey_groups(con, scope, run)
  readr::write_tsv(groups, file.path(run$dir, "survey_groups.tsv"), na = "")

  changed <- if (is.null(cmp)) NA_integer_ else
    sum(is.na(cmp$diff) | cmp$diff != 0 | cmp$years_ref != cmp$years_now)
  metrics <- list(n_records = sum(baseline$n), n_datasets = nrow(baseline),
                  n_survey_groups = nrow(groups),
                  previous_run = if (is.null(previous)) NA_character_ else previous$id,
                  n_datasets_changed = changed)
  run_finish(run, metrics, c(
    sprintf("GBIF baseline for scope `%s`: %s records in %d datasets; %d survey groups.",
            scope$name, fmt_int(sum(baseline$n)), nrow(baseline), nrow(groups)), "",
    if (is.null(previous)) "No previous gbif run to compare with." else
      sprintf("Compared with `%s`: %d datasets changed (see `comparison.tsv`).", previous$id, changed),
    "", "Files: `baseline.tsv`, `comparison.tsv`, `survey_groups.tsv`."))
  cat(sprintf("Wrote %s\n", run$dir))
}

#' Records per dataset with type, years, protocols, eventID presence, basisOfRecord.
gbif_baseline <- function(con, scope, run) {
  taxa <- scope_taxon_keys(scope)
  gid <- scope$region$gadm_gid
  run_id <- db_run_start(con, kind = "gbif", step = "gbif_baseline", run_dir = run$dir,
                         query = jsonlite::toJSON(list(taxonKey = taxa, gadmGid = gid),
                                                  auto_unbox = TRUE))
  # The scope taxa are disjoint orders, so counts per taxon can be summed.
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
  ds_facets <- c("year", "samplingProtocol", "basisOfRecord")
  dataset_facets <- function(key) {
    per <- lapply(taxa, function(k) gbif_facets(c(base_args(k), list(datasetKey = key)), ds_facets))
    sums <- lapply(ds_facets, function(f) {
      dplyr::bind_rows(lapply(per, function(x) x$facets[[f]])) |>
        dplyr::group_by(name) |> dplyr::summarise(count = sum(count), .groups = "drop") |>
        dplyr::arrange(dplyr::desc(count), name)
    })
    c(stats::setNames(sums, ds_facets), list(n_per_taxon = vapply(per, `[[`, 0, "count")))
  }
  rows <- lapply(seq_len(nrow(by_ds)), function(i) {
    key <- by_ds$dataset_key[i]
    meta <- gbif_dataset_meta(key)
    fc <- dataset_facets(key)
    if (sum(fc$n_per_taxon) != by_ds$n[i]) stop("Count mismatch for dataset ", key)
    # eventID presence in a sample of up to 3 records, filled across the taxa in order.
    smp <- NULL
    for (k in taxa[fc$n_per_taxon > 0]) {
      need <- 3 - NROW(smp)
      if (need == 0) break
      smp <- dplyr::bind_rows(smp, rgbif::occ_search(taxonKey = k, gadmGid = gid,
                                                     datasetKey = key, limit = need)$data)
    }
    ev <- if ("eventID" %in% names(smp)) sum(!is.na(smp$eventID) & nzchar(smp$eventID)) else 0
    db_upsert_gbif_dataset(con, c(as.list(meta), list(fetched_at = utc_now(), run_id = run_id)))
    years <- sort(as.integer(fc$year$name))
    data.frame(
      datasetKey = key, n = by_ds$n[i], title = meta$title, type = meta$dataset_type,
      publisher = meta$publisher,
      years = if (length(years)) sprintf("%d-%d", min(years), max(years)) else "",
      n_years = length(years),
      protocols = paste(sprintf("%s(%d)", utils::head(fc$samplingProtocol$name, 3),
                                utils::head(fc$samplingProtocol$count, 3)), collapse = "; "),
      eventID_in_sample = sprintf("%d/%d", ev, NROW(smp)),
      basis = paste(fc$basisOfRecord$name, collapse = ","))
  })
  db_run_finish(con, run_id, n_records = total)
  dplyr::bind_rows(rows)
}

#' Compare two baseline tables per dataset; `diff` = now − previous.
gbif_compare <- function(prev, now) {
  dplyr::full_join(
    prev |> dplyr::transmute(datasetKey, title_ref = title, n_ref = as.integer(n),
                             years_ref = years, n_years_ref = as.integer(n_years)),
    now |> dplyr::transmute(datasetKey, title_now = title, n_now = as.integer(n),
                            years_now = years, n_years_now = as.integer(n_years)),
    by = "datasetKey") |>
    dplyr::mutate(diff = n_now - n_ref, title = dplyr::coalesce(title_now, title_ref)) |>
    dplyr::arrange(dplyr::desc(dplyr::coalesce(n_now, n_ref)))
}

#' Fetch all scope records from SURVEY_GROUP_DATASETS and group them.
gbif_survey_groups <- function(con, scope, run) {
  gid <- scope$region$gadm_gid
  dir.create(run$data_dir, recursive = TRUE, showWarnings = FALSE)
  all <- list()
  for (nm in names(SURVEY_GROUP_DATASETS)) {
    key <- SURVEY_GROUP_DATASETS[[nm]]
    run_id <- db_run_start(con, kind = "gbif", step = "gbif_survey_records", batch = nm,
                           run_dir = run$dir,
                           query = jsonlite::toJSON(list(datasetKey = key, gadmGid = gid,
                                                         taxonKey = scope_taxon_keys(scope)),
                                                    auto_unbox = TRUE))
    recs <- dplyr::bind_rows(lapply(scope_taxon_keys(scope), function(k) {
      gbif_occurrences(list(taxonKey = k, gadmGid = gid, datasetKey = key))
    }))
    recs <- recs[, intersect(SURVEY_RECORD_FIELDS, names(recs))]
    saveRDS(recs, file.path(run$data_dir, sprintf("survey_records_%s.rds", nm)))
    db_run_finish(con, run_id, n_records = nrow(recs))
    all[[nm]] <- recs
  }
  dplyr::bind_rows(all, .id = "source") |>
    dplyr::mutate(event_prefix = sub("[-_:/][^-_:/]*$", "", eventID)) |>
    dplyr::group_by(source, datasetName, recordedBy, year) |>
    dplyr::summarise(
      n = dplyr::n(),
      dates = paste(sort(unique(substr(eventDate, 1, 10))), collapse = ";"),
      n_localities = dplyr::n_distinct(locality),
      localities = paste(utils::head(sort(unique(locality)), 15), collapse = "; "),
      waterbodies = paste(utils::head(sort(unique(waterBody)), 25), collapse = "; "),
      protocols = paste(sort(unique(samplingProtocol)), collapse = "; "),
      event_prefixes = paste(utils::head(sort(unique(event_prefix)), 5), collapse = "; "),
      .groups = "drop") |>
    dplyr::arrange(source, datasetName, year)
}
