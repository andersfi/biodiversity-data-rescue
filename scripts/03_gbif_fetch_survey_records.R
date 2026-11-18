# Fetch all scope occurrences from the GBIF datasets where surveys can be told
# apart (dataset × collector × period × locality × eventID), for building
# gold-set candidates (found_via = gbif_baseline).
# Writes data/raw/gbif/survey_records_<dataset>.rds and a grouped summary to
# reports/gbif_survey_groups_<date>.tsv.
#
# Usage: Rscript scripts/03_gbif_fetch_survey_records.R

source("R/db.R")
source("R/sources_gbif.R")

DATASETS <- c(
  ntnu_benthic = "33591b80-0e31-480c-82ce-2f57211b10e6",
  vannmiljo    = "46293000-ddd1-4c32-a1e7-b5e793223ecd"
)
KEEP <- c("key", "datasetKey", "datasetName", "recordedBy", "identifiedBy", "institutionCode",
          "eventID", "parentEventID", "eventDate", "year", "month", "locality", "waterBody",
          "locationID", "municipality", "stateProvince", "decimalLatitude", "decimalLongitude",
          "samplingProtocol", "samplingEffort", "basisOfRecord", "order", "scientificName",
          "individualCount", "occurrenceRemarks", "eventRemarks", "fieldNumber", "projectId")

scope <- read_scope()
gid <- scope$region$gadm_gid

con <- db_connect()
on.exit(db_disconnect(con))
db_init(con)

all <- list()
for (nm in names(DATASETS)) {
  key <- DATASETS[[nm]]
  run_id <- db_run_start(con, kind = "gbif", step = "gbif_survey_records", batch = nm,
                         query = jsonlite::toJSON(list(datasetKey = key, gadmGid = gid,
                                                       taxonKey = scope_taxon_keys(scope)),
                                                  auto_unbox = TRUE))
  recs <- dplyr::bind_rows(lapply(scope_taxon_keys(scope), function(k) {
    gbif_occurrences(list(taxonKey = k, gadmGid = gid, datasetKey = key))
  }))
  recs <- recs[, intersect(KEEP, names(recs))]
  saveRDS(recs, file.path(RAW_GBIF_DIR, sprintf("survey_records_%s.rds", nm)))
  db_run_finish(con, run_id, n_records = nrow(recs))
  cat(sprintf("%s: %d records\n", nm, nrow(recs)))
  all[[nm]] <- recs
}

# Group: dataset × datasetName × recordedBy × year, with localities and eventID prefixes.
grp <- dplyr::bind_rows(all, .id = "source") |>
  dplyr::mutate(event_prefix = sub("[-_:/][^-_:/]*$", "", eventID)) |>
  dplyr::group_by(source, datasetName, recordedBy, year) |>
  dplyr::summarise(
    n = dplyr::n(),
    dates = paste(sort(unique(substr(eventDate, 1, 10))), collapse = ";"),
    n_localities = dplyr::n_distinct(locality),
    localities = paste(head(sort(unique(locality)), 15), collapse = "; "),
    waterbodies = paste(head(sort(unique(waterBody)), 25), collapse = "; "),
    protocols = paste(sort(unique(samplingProtocol)), collapse = "; "),
    event_prefixes = paste(head(sort(unique(event_prefix)), 5), collapse = "; "),
    .groups = "drop") |>
  dplyr::arrange(source, datasetName, year)
out <- sprintf("reports/gbif_survey_groups_%s.tsv", Sys.Date())
readr::write_tsv(grp, out, na = "")
cat("Wrote", out, "with", nrow(grp), "groups\n")
