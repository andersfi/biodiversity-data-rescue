# Gold set: read, normalise and validate goldset/goldset.csv.

GOLDSET_FILE <- "goldset/goldset.csv"
GOLDSET_COLUMNS <- c("survey_ref", "title", "institution", "taxon_group", "region", "period",
                     "method", "documents", "expected_status", "where_data_are",
                     "is_borderline", "include", "found_via", "notes")

read_goldset <- function(path = GOLDSET_FILE) {
  readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                  na = character(), locale = readr::locale(encoding = "UTF-8"))
}

write_goldset <- function(df, path = GOLDSET_FILE) {
  stopifnot(identical(names(df), GOLDSET_COLUMNS))
  readr::write_csv(df, path, na = "")
}

# Split "value (comment)" into value and comment.
.split_paren <- function(x) {
  m <- regmatches(x, regexec("^\\s*([^()]*?)\\s*\\((.*)\\)\\s*$", x))
  value <- vapply(seq_along(x), function(i) if (length(m[[i]])) m[[i]][2] else trimws(x[i]), "")
  comment <- vapply(m, function(z) if (length(z)) z[3] else NA_character_, "")
  list(value = value, comment = comment)
}

.append_note <- function(notes, add) {
  ifelse(is.na(add), notes, ifelse(nzchar(notes), paste0(notes, " ", add), add))
}

#' Normalise candidate rows to the controlled vocabulary in schemas/goldset_row.json.
#' Lossless: parenthesised comments in expected_status and found_via move to notes.
normalise_goldset <- function(df) {
  for (col in setdiff(GOLDSET_COLUMNS, names(df))) df[[col]] <- ""
  df <- df[GOLDSET_COLUMNS]
  df[] <- lapply(df, function(x) trimws(ifelse(is.na(x), "", x)))

  st <- .split_paren(df$expected_status)
  df$expected_status <- tolower(st$value)
  df$notes <- .append_note(df$notes, ifelse(is.na(st$comment), NA,
                                            sprintf("[expected_status %s.]", st$comment)))

  fv <- .split_paren(df$found_via)
  df$found_via <- fv$value
  df$notes <- .append_note(df$notes, ifelse(is.na(fv$comment), NA,
                                            sprintf("[found_via: %s.]", fv$comment)))
  df
}

validate_goldset <- function(df) {
  rows <- df_rows(df)
  bad <- validate_records(rows, "goldset_row", id_field = "survey_ref")
  dup <- df$survey_ref[duplicated(df$survey_ref)]
  if (length(dup)) {
    bad <- rbind(bad, data.frame(index = match(dup, df$survey_ref), id = dup,
                                 errors = "duplicated survey_ref"))
  }
  bad
}
