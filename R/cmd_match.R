# Verb `match`: match gold-set surveys against the scope's GBIF records as if
# every row had been read perfectly (phase 2: no LLM, no search). Writes
# runs/match/<date>_<label>/ with results.tsv (one row per survey: evidence,
# score, band, gold status), station_years.tsv, review.md (the uncertain list)
# and metrics.json. Only include = yes rows count in the metrics; candidate
# rows are reported separately as provisional.

cmd_match <- function(args) {
  label <- if (length(args)) args[1] else "rules"
  # Latest finished gbif run whose local data still hold the scope records.
  idx <- runs_index()
  idx <- idx[idx$step == "gbif" & nzchar(idx$finished_at) &
               file.exists(file.path(idx$data_dir, "scope_records.rds")), ]
  if (!nrow(idx)) {
    stop("No gbif run with data/runs/gbif/<id>/scope_records.rds: run `Rscript run.R gbif` first.",
         call. = FALSE)
  }
  gbif_run <- idx[nrow(idx), ]
  rec_file <- file.path(gbif_run$data_dir, "scope_records.rds")
  gs <- read_goldset()
  st <- read_stations()
  if (nrow(validate_goldset(gs)) || nrow(validate_stations(st, gs$survey_ref))) stop("Gold set or stations.csv invalid; run `Rscript run.R check`.", call. = FALSE)

  run <- run_start("match", label, args,
                   config_files = c("config/scope.yaml", MATCH_CONFIG_FILE))
  cfg <- read_match_config()
  scope <- read_scope()
  recs <- readRDS(rec_file)
  datasets <- readRDS(file.path(gbif_run$data_dir, "scope_datasets.rds"))
  res <- match_goldset(gs, st, recs, datasets, scope, cfg)

  readr::write_tsv(res$results, file.path(run$dir, "results.tsv"), na = "")
  readr::write_tsv(res$station_years, file.path(run$dir, "station_years.tsv"), na = "")
  writeLines(match_review_md(res$results), file.path(run$dir, "review.md"))

  m <- match_all_metrics(res$results)
  m$gbif_run <- gbif_run$id
  m$n_scope_records <- nrow(recs)
  run_finish(run, m, match_readme(res$results, m, cfg, gbif_run$id))
  cat(sprintf("Wrote %s\n", run$dir))
}

#' Match every gold-set row; returns results (one row per survey) and station_years.
match_goldset <- function(gs, st, recs, datasets, scope, cfg) {
  inputs <- gs[, MATCH_INPUT_COLUMNS]
  sy <- survey_station_years(inputs, st, scope, cfg)
  m <- match_station_years(sy, recs, cfg)
  stop_words <- match_stopwords(cfg, scope)
  ev <- do.call(rbind, lapply(seq_len(nrow(inputs)), function(i)
    survey_evidence(inputs[i, ], m$station_years, m$hits, recs, datasets, cfg, stop_words)))
  ev$score <- match_score(ev, cfg$weights)
  ev$band <- match_band(ev$score, ev$coverage, ev$located, cfg$bands)
  # The answer key is joined only after the bands are set.
  key <- gs[, c("survey_ref", "include", "expected_status", "found_via", "notes")]
  results <- merge(key, ev, by = "survey_ref", sort = FALSE)
  results <- results[match(gs$survey_ref, results$survey_ref), ]
  results$error <- ifelse(results$expected_status %in% STATUS_IN_GBIF &
                            results$band == "likely_not_in_gbif", "false_unpublished",
                   ifelse(results$expected_status %in% STATUS_NOT_PUBLISHED &
                            results$band == "likely_in_gbif", "false_published", ""))
  results$wrong_pull <- ""
  for (i in which(nzchar(results$error)))
    results$wrong_pull[i] <- wrong_pull(results[i, ], results$error[i] == "false_published")
  list(results = results, station_years = m$station_years)
}

#' Metrics for include = yes (counting) and candidate (provisional), each for
#' all rows and for rows not found via the GBIF baseline (whose titles and
#' places were written from GBIF, so name evidence is circular for them).
match_all_metrics <- function(res) {
  sets <- list(yes = res$include == "yes", candidate = res$include == "candidate")
  out <- list()
  for (s in names(sets)) {
    sub <- res[sets[[s]], ]
    out[[s]] <- list(all = match_metrics(sub),
                     not_found_via_gbif = match_metrics(sub[sub$found_via != "gbif_baseline", ]))
  }
  # Scalar headline values for runs/README.md.
  fu <- out$yes$all$false_unpublished
  fc <- out$candidate$all$false_unpublished
  c(list(n_yes = sum(sets$yes),
         false_unpublished_yes = if (fu$n) sprintf("%d/%d", fu$count, fu$n) else "n = 0",
         false_unpublished_candidate = sprintf("%d/%d (provisional)", fc$count, fc$n),
         uncertain_candidate = sprintf("%d/%d", out$candidate$all$uncertain$count,
                                       out$candidate$all$uncertain$n)),
    out)
}

fmt_rate <- function(r) {
  if (!r$n) return(sprintf("%d/%d", r$count, r$n))
  sprintf("%d/%d (%.0f %%, 95 %% CI %.0f–%.0f %%)", r$count, r$n, 100 * r$share,
          100 * r$ci95_lower, 100 * r$ci95_upper)
}

match_metric_table <- function(m) {
  rows <- list()
  for (s in c("yes", "candidate")) for (v in c("all", "not_found_via_gbif")) {
    x <- m[[s]][[v]]
    rows[[length(rows) + 1]] <- data.frame(
      include = if (s == "yes") "yes" else "candidate (provisional)",
      rows = if (v == "all") "all" else "not found via gbif_baseline",
      n = x$n_rows,
      `false "unpublished"` = fmt_rate(x$false_unpublished),
      `false "published"` = fmt_rate(x$false_published),
      uncertain = fmt_rate(x$uncertain), check.names = FALSE)
  }
  do.call(rbind, rows)
}

evidence_line <- function(r) {
  f <- function(v) if (is.na(v)) "NA" else sprintf("%.2f", v)
  c(sprintf("- place × time: %s — %s", f(r$place_time), r$place_time_source),
    sprintf("- taxon: %d matched EPT records — %s", r$taxon, r$taxon_source),
    sprintf("- institution: %s — %s", f(r$institution), r$institution_source),
    sprintf("- dataset name: %s — %s", f(r$dataset_name), r$dataset_name_source),
    sprintf("- direct link: %s — %s", f(r$direct_link), r$direct_link_source))
}

match_review_md <- function(res) {
  u <- res[res$band == "uncertain", ]
  out <- c("# Review list: uncertain matches", "",
           "Surveys the rules could not place in or out of GBIF. Decide by hand; the",
           "evidence is listed per survey. Gold status shown for comparison only.", "")
  for (i in seq_len(nrow(u))) {
    r <- u[i, ]
    out <- c(out, sprintf("## %s (include %s, gold %s)", r$survey_ref, r$include, r$expected_status),
             "", sprintf("score %s, coverage %s, located %.0f %%, station-years %d (%d excluded by scope)",
                         if (is.na(r$score)) "NA" else sprintf("%.2f", r$score),
                         if (is.na(r$coverage)) "NA" else sprintf("%.2f", r$coverage),
                         100 * r$located, r$n_station_years, r$n_excluded), "",
             evidence_line(r), "")
  }
  out
}

match_readme <- function(res, m, cfg, gbif_id) {
  yes <- res[res$include == "yes", ]
  cand <- res[res$include == "candidate", ]
  err <- res[nzchar(res$error) & res$include %in% c("yes", "candidate"), ]
  partly <- res[res$expected_status == "partly_in_gbif", ]
  pct <- function(x) ifelse(is.na(x), "NA", sprintf("%.0f %%", 100 * x))
  c(sprintf("Gold-set rows matched against %s scope records from gbif run `%s`, as if every row were read perfectly (no LLM, no search). Thresholds: `config/match.yaml` (copied in `config/`).",
            fmt_int(m$n_scope_records), gbif_id), "",
    sprintf("Only include = yes rows count (n = %d). Candidate rows (n = %d) are shown separately and are **provisional**.",
            nrow(yes), nrow(cand)), "",
    "## Main metric and error rates", "", md_table(match_metric_table(m)), "",
    "## Confusion table: expected_status × band", "",
    "include = yes:", "", if (nrow(yes)) md_table(confusion_table(yes)) else "(no rows)", "",
    "include = candidate (provisional):", "", md_table(confusion_table(cand)), "",
    "## Errors", "",
    if (nrow(err)) md_table(data.frame(survey_ref = err$survey_ref, include = err$include,
      gold = err$expected_status, band = as.character(err$band), error = err$error,
      score = sprintf("%.2f", err$score), coverage = pct(err$coverage),
      `pulled the wrong way` = err$wrong_pull, check.names = FALSE)) else "None.", "",
    "## partly_in_gbif: computed coverage vs notes", "",
    md_table(data.frame(survey_ref = partly$survey_ref, band = as.character(partly$band),
                        coverage = pct(partly$coverage),
                        years = partly$years_with_records,
                        notes = truncate_text(partly$notes, 160))), "",
    "## All surveys", "",
    md_table(data.frame(survey_ref = res$survey_ref, include = res$include,
      gold = res$expected_status, band = as.character(res$band),
      score = ifelse(is.na(res$score), "NA", sprintf("%.2f", res$score)),
      coverage = pct(res$coverage), located = pct(res$located),
      place = ifelse(is.na(res$place_time), "NA", sprintf("%.2f", res$place_time)),
      inst = ifelse(is.na(res$institution), "NA", res$institution),
      name = ifelse(is.na(res$dataset_name), "NA", res$dataset_name),
      link = ifelse(is.na(res$direct_link), "NA", res$direct_link))), "",
    "Files: `results.tsv` (all evidence with sources), `station_years.tsv`, `review.md` (uncertain list).")
}
