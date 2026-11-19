# Verb `check`: validate what Anders edits (gold set, stations, manifest,
# knowledge cards), load the knowledge cards into the register, and write the worklist to
# runs/goldset/worklist.md. Deterministic; no network.

WORKLIST_FILE <- "runs/goldset/worklist.md"

cmd_check <- function(args) {
  problems <- character()
  gs <- read_goldset()
  bad <- validate_goldset(gs)
  if (nrow(bad)) problems <- c(problems, sprintf("goldset.csv [%s] %s", bad$id, bad$errors))
  mbad <- validate_manifest(read_manifest(), gs$survey_ref)
  if (nrow(mbad)) problems <- c(problems, sprintf("fulltext_manifest.csv [%s] %s", mbad$id, mbad$errors))
  st <- read_stations()
  sbad <- validate_stations(st, gs$survey_ref)
  if (nrow(sbad)) problems <- c(problems, sprintf("stations.csv row %d [%s] %s", sbad$row,
                                                  sbad$survey_ref, sbad$problem))
  cards <- lapply(list_knowledge_files(), read_knowledge_card)
  kerr <- knowledge_errors(cards)
  if (length(kerr)) problems <- c(problems, kerr)
  if (length(problems)) {
    cat("Validation failed:\n", paste0("  - ", problems, "\n"), sep = "")
    quit(status = 1)
  }
  cat(sprintf("goldset.csv: %d rows valid (schema %s)\n", nrow(gs), schema_version("goldset_row")))
  cat(sprintf("fulltext_manifest.csv: valid\n"))
  cat(sprintf("stations.csv: %d stations for %d surveys valid; %d not verified\n", nrow(st),
              length(unique(st$survey_ref)), sum(st$verified != "yes")))

  con <- db_connect()
  on.exit(db_disconnect(con))
  db_init(con)
  removed <- knowledge_load(con, cards)
  cat(sprintf("knowledge: %d cards valid and loaded%s\n", length(cards),
              if (length(removed)) paste0("; removed ", paste(removed, collapse = ", ")) else ""))

  wl <- goldset_worklist(gs)
  write_worklist(wl, gs)
  counts <- table(factor(wl$item, levels = WORKLIST_ITEMS))
  cat(sprintf("\nWorklist (%s):\n", WORKLIST_FILE))
  for (k in names(WORKLIST_ITEMS)) cat(sprintf("  %-20s %3d  %s\n", WORKLIST_ITEMS[[k]], counts[[WORKLIST_ITEMS[[k]]]], k))
}

WORKLIST_ITEMS <- c("rows without a decided expected_status" = "status_todo",
                    "rows still candidate (not verified)" = "candidate",
                    "rows without doc_ids" = "no_doc_ids",
                    "GBIF status but no gbif_dataset_keys" = "gbif_status_no_key")

write_worklist <- function(wl, gs, path = WORKLIST_FILE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  out <- c("# Gold-set worklist", "",
           sprintf("_Written by `Rscript run.R check`. goldset.csv SHA-256 `%s`._",
                   substr(sha256_file(GOLDSET_FILE), 1, 12)), "")
  for (k in names(WORKLIST_ITEMS)) {
    rows <- wl[wl$item == WORKLIST_ITEMS[[k]], c("survey_ref", "include", "expected_status")]
    out <- c(out, sprintf("## %s (%d)", k, nrow(rows)), "",
             if (nrow(rows)) md_table(rows) else "None.", "")
  }
  writeLines(out, path, useBytes = TRUE)
}

#' Validation errors for parsed knowledge cards, including duplicated ids.
knowledge_errors <- function(cards) {
  ids <- vapply(cards, function(c) as.character(c$front$id %||% NA), "")
  errs <- lapply(cards, validate_knowledge_card)
  errs[duplicated(ids)] <- lapply(errs[duplicated(ids)], c, "duplicated id")
  unlist(lapply(seq_along(cards), function(i)
    if (length(errs[[i]])) sprintf("%s: %s", cards[[i]]$path, errs[[i]])))
}

#' Load valid cards into the register in one transaction; remove cards whose
#' files are gone. Returns the removed card ids.
knowledge_load <- function(con, cards) {
  ids <- vapply(cards, function(c) as.character(c$front$id), "")
  run_id <- db_run_start(con, kind = "load", step = "load_knowledge",
                         schema_version = schema_version("knowledge_card"))
  removed <- character()
  DBI::dbWithTransaction(con, {
    for (card in cards) {
      db_upsert_knowledge_card(con, list(
        card_id = card$front$id, type = card$front$type, title = card$front$title,
        path = card$path, fields_json = as.character(knowledge_front_json(card$front)),
        body = card$body, file_sha256 = card$sha256,
        last_confirmed = card$front$last_confirmed, confirmed_by = card$front$confirmed_by))
    }
    removed <- db_delete_knowledge_cards_except(con, ids)
  })
  db_run_finish(con, run_id, n_records = length(cards))
  removed
}
