# Gold set: read, validate and list open work in goldset/goldset.csv,
# the only answer key in the project. Anders edits the file directly.

GOLDSET_FILE <- "goldset/goldset.csv"
GOLDSET_COLUMNS <- c("survey_ref", "title", "institution", "taxon_group", "region", "period",
                     "method", "documents", "doc_ids", "expected_status", "where_data_are",
                     "gbif_dataset_keys", "is_borderline", "include", "found_via", "notes")
MANIFEST_FILE <- "goldset/fulltext_manifest.csv"

# Statuses that say the EPT data are (at least partly) in GBIF.
STATUS_IN_GBIF <- c("in_gbif", "in_gbif_no_effort", "partly_in_gbif")

read_goldset <- function(path = GOLDSET_FILE) {
  readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                  na = character(), locale = readr::locale(encoding = "UTF-8"),
                  progress = FALSE)
}

write_goldset <- function(df, path = GOLDSET_FILE) {
  stopifnot(identical(names(df), GOLDSET_COLUMNS))
  readr::write_csv(df, path, na = "")
}

read_manifest <- function(path = MANIFEST_FILE) {
  man <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                         na = character(), progress = FALSE)
  man$bytes <- as.integer(man$bytes)
  man
}

#' Schema errors, duplicated survey_refs and a wrong column order.
validate_goldset <- function(df) {
  bad <- data.frame(index = integer(), id = character(), errors = character())
  if (!identical(names(df), GOLDSET_COLUMNS)) {
    bad <- rbind(bad, data.frame(index = 0L, id = "(header)", errors = sprintf(
      "columns must be: %s", paste(GOLDSET_COLUMNS, collapse = ","))))
    return(bad)
  }
  bad <- rbind(bad, validate_records(df_rows(df), "goldset_row", id_field = "survey_ref"))
  dup <- df$survey_ref[duplicated(df$survey_ref)]
  if (length(dup)) {
    bad <- rbind(bad, data.frame(index = match(dup, df$survey_ref), id = dup,
                                 errors = "duplicated survey_ref"))
  }
  bad
}

#' Manifest rows: schema errors and survey_refs missing from the gold set.
validate_manifest <- function(man, survey_refs) {
  bad <- validate_records(df_rows(man), "fulltext_manifest_row", id_field = "file")
  refs <- unique(trimws(unlist(strsplit(man$survey_ref, ";", fixed = TRUE))))
  unknown <- setdiff(refs, survey_refs)
  if (length(unknown)) {
    bad <- rbind(bad, data.frame(index = NA_integer_, id = unknown,
                                 errors = "survey_ref in manifest but not in goldset.csv"))
  }
  bad
}

#' Open work in the gold set, one row per (survey_ref, item). Items:
#' - status_todo: expected_status is todo
#' - candidate: include is candidate (unverified)
#' - no_doc_ids: no nva:/doi:/handle: id (negative cases excluded)
#' - gbif_status_no_key: status says GBIF but gbif_dataset_keys is empty
goldset_worklist <- function(gs) {
  item <- function(cond, what) {
    if (!any(cond)) return(NULL)
    data.frame(survey_ref = gs$survey_ref[cond], item = what,
               include = gs$include[cond], expected_status = gs$expected_status[cond])
  }
  out <- rbind(
    item(gs$expected_status == "todo", "status_todo"),
    item(gs$include == "candidate", "candidate"),
    item(!nzchar(gs$doc_ids) & gs$expected_status != "not_applicable", "no_doc_ids"),
    item(gs$expected_status %in% STATUS_IN_GBIF & !nzchar(gs$gbif_dataset_keys),
         "gbif_status_no_key"))
  if (is.null(out)) {
    return(data.frame(survey_ref = character(), item = character(), include = character(),
                      expected_status = character()))
  }
  out
}
