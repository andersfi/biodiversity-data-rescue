# All database access goes through the named functions in this file
# (architecture rule 2). No SQL elsewhere in the project.

SCHEMA_FILE <- "db/schema.sql"
DEFAULT_DB_PATH <- "data/register.sqlite"

#' Open a connection to the register. Foreign keys are enforced.
db_connect <- function(path = DEFAULT_DB_PATH) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

db_disconnect <- function(con) DBI::dbDisconnect(con)

# Split schema.sql into statements. The schema has no triggers, so ';' at the
# end of a line is a safe statement boundary. Comments are stripped first.
.schema_statements <- function(schema_file) {
  sql <- readLines(schema_file, warn = FALSE, encoding = "UTF-8")
  sql <- sub("--.*$", "", sql)
  stmts <- strsplit(paste(sql, collapse = "\n"), ";\\s*\n")[[1]]
  stmts <- trimws(stmts)
  stmts[nzchar(stmts)]
}

#' Create all tables from db/schema.sql. Idempotent (CREATE ... IF NOT EXISTS).
#' Records the SHA-256 of the schema file in schema_meta.
db_init <- function(con, schema_file = SCHEMA_FILE) {
  if (!file.exists(schema_file)) stop("Schema file not found: ", schema_file)
  for (s in .schema_statements(schema_file)) DBI::dbExecute(con, s)
  DBI::dbExecute(
    con,
    "INSERT INTO schema_meta (key, value) VALUES ('schema_sha256', ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value",
    params = list(digest::digest(file = schema_file, algo = "sha256"))
  )
  invisible(con)
}

db_tables <- function(con) sort(DBI::dbListTables(con))

db_count <- function(con, table) {
  stopifnot(table %in% DBI::dbListTables(con))
  DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", DBI::dbQuoteIdentifier(con, table)))$n
}

# ---- run_log -----------------------------------------------------------------

#' Start a run and return its run_id. `fields` is a named list of run_log columns.
db_run_start <- function(con, kind, step, ...) {
  fields <- c(list(kind = kind, step = step), list(...))
  .insert(con, "run_log", fields)
}

db_run_finish <- function(con, run_id, n_records = NA, input_tokens = NA, output_tokens = NA) {
  DBI::dbExecute(
    con,
    "UPDATE run_log SET n_records = ?, input_tokens = ?, output_tokens = ?,
       finished_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE run_id = ?",
    params = list(as.integer(n_records), as.integer(input_tokens),
                  as.integer(output_tokens), as.integer(run_id))
  )
  invisible(run_id)
}

db_get_run <- function(con, run_id) {
  DBI::dbGetQuery(con, "SELECT * FROM run_log WHERE run_id = ?", params = list(as.integer(run_id)))
}

# ---- knowledge cards -----------------------------------------------------------

#' Insert or replace a knowledge card (keyed on card_id).
db_upsert_knowledge_card <- function(con, card) {
  required <- c("card_id", "type", "title", "path", "fields_json", "body",
                "file_sha256", "last_confirmed", "confirmed_by")
  missing <- setdiff(required, names(card))
  if (length(missing)) stop("Knowledge card is missing: ", paste(missing, collapse = ", "))
  card$uri <- paste0("knowledge:", card$card_id)
  cols <- c("uri", required)
  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO knowledge_card (%s) VALUES (%s)
       ON CONFLICT(card_id) DO UPDATE SET %s,
         loaded_at = strftime('%%Y-%%m-%%dT%%H:%%M:%%SZ', 'now')",
      paste(cols, collapse = ", "),
      paste(rep("?", length(cols)), collapse = ", "),
      paste(sprintf("%s = excluded.%s", cols[-1], cols[-1]), collapse = ", ")
    ),
    params = unname(lapply(card[cols], as.character))
  )
}

db_knowledge_cards <- function(con, type = NULL) {
  if (is.null(type)) return(DBI::dbGetQuery(con, "SELECT * FROM knowledge_card ORDER BY card_id"))
  DBI::dbGetQuery(con, "SELECT * FROM knowledge_card WHERE type = ? ORDER BY card_id",
                  params = list(type))
}

#' Remove cards whose files no longer exist, so the table mirrors knowledge/.
db_delete_knowledge_cards_except <- function(con, keep_ids) {
  current <- DBI::dbGetQuery(con, "SELECT card_id FROM knowledge_card")$card_id
  for (id in setdiff(current, keep_ids)) {
    DBI::dbExecute(con, "DELETE FROM knowledge_card WHERE card_id = ?", params = list(id))
  }
  invisible(setdiff(current, keep_ids))
}

# ---- GBIF datasets -------------------------------------------------------------

db_upsert_gbif_dataset <- function(con, ds) {
  stopifnot(all(c("dataset_key", "title") %in% names(ds)))
  ds$uri <- paste0("gbif-dataset:", ds$dataset_key)
  cols <- intersect(c("uri", "dataset_key", "title", "dataset_type", "publisher",
                      "publisher_key", "doi", "fetched_at", "run_id"), names(ds))
  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO gbif_dataset (%s) VALUES (%s)
       ON CONFLICT(dataset_key) DO UPDATE SET %s",
      paste(cols, collapse = ", "),
      paste(rep("?", length(cols)), collapse = ", "),
      paste(sprintf("%s = excluded.%s", setdiff(cols, "dataset_key"),
                    setdiff(cols, "dataset_key")), collapse = ", ")
    ),
    params = unname(ds[cols])
  )
}

# ---- LLM answer cache (rule 5) ---------------------------------------------------

#' Which of the given (uri, content_sha256) pairs already have an answer?
db_llm_cached <- function(con, step, uris, content_sha256, schema_version) {
  if (!length(uris)) return(logical(0))
  hit <- DBI::dbGetQuery(
    con,
    "SELECT record_uri, content_sha256 FROM llm_answer WHERE step = ? AND schema_version = ?",
    params = list(step, schema_version)
  )
  paste(uris, content_sha256) %in% paste(hit$record_uri, hit$content_sha256)
}

db_insert_llm_answers <- function(con, answers) {
  # answers: data.frame with step, record_uri, content_sha256, schema_version,
  # answer_json, run_id, answered_at
  required <- c("step", "record_uri", "content_sha256", "schema_version",
                "answer_json", "run_id", "answered_at")
  missing <- setdiff(required, names(answers))
  if (length(missing)) stop("LLM answers are missing: ", paste(missing, collapse = ", "))
  DBI::dbWithTransaction(con, {
    for (i in seq_len(nrow(answers))) .insert(con, "llm_answer", as.list(answers[i, required]))
  })
  invisible(nrow(answers))
}

db_llm_answers <- function(con, step) {
  DBI::dbGetQuery(con, "SELECT * FROM llm_answer WHERE step = ?", params = list(step))
}

# ---- internal ------------------------------------------------------------------

.insert <- function(con, table, fields) {
  fields <- fields[!vapply(fields, function(x) length(x) == 0 || all(is.na(x)), logical(1))]
  DBI::dbExecute(
    con,
    sprintf("INSERT INTO %s (%s) VALUES (%s)", table,
            paste(names(fields), collapse = ", "),
            paste(rep("?", length(fields)), collapse = ", ")),
    params = unname(lapply(fields, function(x) if (is.factor(x)) as.character(x) else x))
  )
  DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
}
