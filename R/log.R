# Query log (CLAUDE.md rule 6): one JSON line per API query in logs/queries.jsonl.

QUERY_LOG <- "logs/queries.jsonl"

log_query <- function(source, call, args, n_records = NA, n_expected = NA, ...) {
  dir.create(dirname(QUERY_LOG), showWarnings = FALSE, recursive = TRUE)
  entry <- c(list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                  source = source, call = call, args = args,
                  n_records = n_records, n_expected = n_expected), list(...))
  cat(as.character(jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null")), "\n",
      file = QUERY_LOG, append = TRUE, sep = "")
}
