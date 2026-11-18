# JSON Schema validation (architecture rule 3). Invalid records raise an error;
# nothing is repaired silently.

schema_path <- function(name) file.path("schemas", paste0(name, ".json"))

schema_version <- function(name) {
  v <- jsonlite::read_json(schema_path(name))[["x-schema-version"]]
  if (is.null(v)) stop("Schema has no x-schema-version: ", name)
  v
}

.validators <- new.env(parent = emptyenv())

schema_validator <- function(name) {
  if (is.null(.validators[[name]])) {
    .validators[[name]] <- jsonvalidate::json_schema$new(schema_path(name), engine = "ajv")
  }
  .validators[[name]]
}

#' Validate a list of records (each a named list) against a schema.
#' Returns a data.frame with one row per invalid record (index, id, errors);
#' zero rows when everything is valid.
validate_records <- function(records, name, id_field = NULL) {
  v <- schema_validator(name)
  out <- list()
  for (i in seq_along(records)) {
    js <- jsonlite::toJSON(records[[i]], auto_unbox = TRUE, null = "null", na = "null", digits = NA)
    res <- v$validate(js, verbose = TRUE)
    if (!isTRUE(res)) {
      err <- attr(res, "errors")
      msg <- paste(sprintf("%s %s", err$instancePath, err$message), collapse = "; ")
      id <- if (!is.null(id_field)) as.character(records[[i]][[id_field]]) else as.character(i)
      out[[length(out) + 1]] <- data.frame(index = i, id = id, errors = msg)
    }
  }
  if (!length(out)) return(data.frame(index = integer(), id = character(), errors = character()))
  do.call(rbind, out)
}

#' Same, but stop with a readable message if any record is invalid.
assert_valid <- function(records, name, id_field = NULL) {
  bad <- validate_records(records, name, id_field)
  if (nrow(bad)) {
    stop(sprintf("%d of %d records fail schema '%s':\n%s", nrow(bad), length(records), name,
                 paste(sprintf("  [%s] %s", bad$id, bad$errors), collapse = "\n")), call. = FALSE)
  }
  invisible(TRUE)
}

#' data.frame -> list of row lists (character columns kept as character).
df_rows <- function(df) {
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
}
