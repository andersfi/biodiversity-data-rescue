# Validate every knowledge card in knowledge/ and load them into the register.
# Any invalid card stops the load; nothing is written in that case.
# Usage: Rscript scripts/01_load_knowledge.R [db_path]

source("R/db.R")
source("R/validate.R")
source("R/knowledge.R")

args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args)) args[[1]] else DEFAULT_DB_PATH

files <- list_knowledge_files()
cards <- lapply(files, read_knowledge_card)
errors <- lapply(cards, validate_knowledge_card)
ids <- vapply(cards, function(c) as.character(c$front$id %||% NA), "")
if (any(duplicated(ids))) errors[duplicated(ids)] <- lapply(errors[duplicated(ids)], c, "duplicated id")

bad <- lengths(errors) > 0
if (any(bad)) {
  for (i in which(bad)) cat(files[i], ":\n", paste0("  - ", errors[[i]], "\n"), sep = "")
  stop(sum(bad), " of ", length(files), " knowledge cards are invalid; nothing loaded.", call. = FALSE)
}

con <- db_connect(path)
on.exit(db_disconnect(con))
db_init(con)
removed <- character()
run_id <- db_run_start(con, kind = "load", step = "load_knowledge",
                       schema_version = schema_version("knowledge_card"))
invisible(DBI::dbWithTransaction(con, {
  for (card in cards) {
    db_upsert_knowledge_card(con, list(
      card_id = card$front$id, type = card$front$type, title = card$front$title,
      path = card$path,
      fields_json = as.character(knowledge_front_json(card$front)),
      body = card$body, file_sha256 = card$sha256,
      last_confirmed = card$front$last_confirmed, confirmed_by = card$front$confirmed_by
    ))
  }
  removed <<- db_delete_knowledge_cards_except(con, ids)
}))
db_run_finish(con, run_id, n_records = length(cards))

cat(sprintf("Loaded %d knowledge cards into %s\n", length(cards), path))
for (c in cards) cat(sprintf("  %-12s %s\n", c$front$type, c$front$id))
if (length(removed)) cat("Removed cards no longer in knowledge/:", paste(removed, collapse = ", "), "\n")
