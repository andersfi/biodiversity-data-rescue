# Verb `read`: the reading test on the local gold-set full texts (phase 3,
# docs/reading-benchmark.md), and `read manifest`, the SHA-256 check of those
# files. The only verb allowed to call the functions in R/fulltext.R.
#
#   read manifest [--dry-run]  SHA-256 check against fulltext_manifest.csv
#   read pages                 page-selection coverage per input (no model)
#   read step0 [label]         CLI flag check, canary test, overhead (3 calls)
#   read <label>               one matrix cell from config/read.yaml

cmd_read <- function(args) {
  sub <- if (length(args)) args[1] else ""
  switch(sub,
    manifest = invisible(cmd_read_manifest(args[-1])),
    pages    = invisible(cmd_read_pages(args[-1])),
    step0    = invisible(cmd_read_step0(args[-1])),
    { if (!nzchar(sub)) stop("Usage: run.R read manifest | pages | step0 | <label>", call. = FALSE)
      invisible(cmd_read_cell(args)) })
}

cmd_read_manifest <- function(args) {
  dry_run <- "--dry-run" %in% args
  gs <- read_goldset()
  res <- fulltext_manifest_check()
  man <- res$manifest
  bad <- validate_manifest(man, gs$survey_ref)
  issues <- res$issues
  if (nrow(bad)) issues <- c(issues, sprintf("Schema: [%s] %s", bad$id, bad$errors))
  cat(sprintf("%d local full texts, %d manifest rows; %d renamed, %d added\n",
              res$n_files, nrow(man), res$renamed, res$added))
  if (!dry_run && (res$renamed + res$added) > 0) {
    man <- man[order(man$survey_ref, man$role, man$file), ]
    readr::write_csv(man, MANIFEST_FILE, na = "")
    cat("Wrote", MANIFEST_FILE, "\n")
  }
  if (length(issues)) {
    cat("Issues:\n", paste0("  - ", issues, "\n"), sep = "")
    quit(status = 1)
  }
  cat("No issues.\n")
}

# ---- shared ------------------------------------------------------------------------

#' Page texts for the manifest's documents, joined with document labels.
read_doc_pages <- function(man = read_manifest()) {
  pages <- fulltext_pages(man)
  docs <- man[!duplicated(man$sha256), c("sha256", "document", "survey_ref", "role")]
  merge(pages, docs, by = "sha256", sort = FALSE)
}

read_keyword_terms <- function(cfg) {
  path <- file.path(KNOWLEDGE_DIR, KNOWLEDGE_TYPE_DIRS[["vocabulary"]],
                    paste0(cfg$pages$keyword_card, ".md"))
  read_knowledge_card(path)$front$terms
}

read_doc_uri <- function(sha256) paste0("sha256:", sha256)

# ---- read pages --------------------------------------------------------------------

cmd_read_pages <- function(args) {
  cfg <- read_config()
  terms <- read_keyword_terms(cfg)
  dp <- read_doc_pages()
  tr <- read_truth()
  rows <- list()
  for (sha in unique(dp$sha256)) {
    d <- dp[dp$sha256 == sha, ]
    d <- d[order(d$page), ]
    t <- tr[tr$document == d$document[1], ]
    for (inp in READ_INPUTS) {
      sel <- read_select_pages(d, inp, cfg$pages, terms)
      rows[[length(rows) + 1]] <- data.frame(
        document = d$document[1], input = inp, n_pages = nrow(d), n_selected = length(sel),
        chars_selected = sum(nchar(d$text[d$page %in% sel])),
        key_page_coverage = round(read_page_coverage(t$page, sel), 2))
    }
  }
  out <- do.call(rbind, rows)
  print(out, row.names = FALSE)
  agg <- aggregate(cbind(n_selected, chars_selected, key_page_coverage) ~ input, out, mean)
  cat("\nMean per input:\n")
  print(agg, row.names = FALSE)
  invisible(out)
}

# ---- read step0 ----------------------------------------------------------------------

STEP0_FLAGS <- c("--print", "--model", "--output-format", "--json-schema", "--system-prompt",
                 "--tools", "--strict-mcp-config", "--setting-sources",
                 "--disable-slash-commands", "--no-session-persistence")

#' Canary strings: distinctive lines from every context file that must not
#' reach a reading, plus every gold-set survey_ref.
read_canaries <- function(gs) {
  files <- c("CLAUDE.md", path.expand("~/.claude/CLAUDE.md"),
             Sys.glob(path.expand("~/.claude/projects/*biodiversity-data-rescue*/memory/MEMORY.md")))
  files <- files[file.exists(files)]
  lines <- unlist(lapply(files, function(f) trimws(readLines(f, warn = FALSE, encoding = "UTF-8"))))
  lines <- lines[nchar(lines) >= 30 & !startsWith(lines, "#")]
  # Short distinctive fragments: a 5-word window from the middle of each line.
  frag <- vapply(strsplit(lines, "\\s+"), function(w) {
    if (length(w) < 5) return(paste(w, collapse = " "))
    s <- max(1, floor(length(w) / 2) - 2)
    paste(w[s:(s + 4)], collapse = " ")
  }, "")
  list(files = files, strings = unique(c(frag, gs$survey_ref, "biodiversity-data-rescue",
                                         "Gjærevollsenteret")))
}

cmd_read_step0 <- function(args) {
  cfg <- read_config()
  model <- cfg$models[[cfg$cell$model]]
  label <- if (length(args)) args[1] else "step0"
  run <- run_start("read", label, args, config_files = c(READ_CONFIG_FILE))
  calls <- list()
  log_call <- function(name, res) {
    calls[[name]] <<- data.frame(
      call = name, model_requested = model, models_reported = paste(res$models, collapse = ";"),
      input_tokens = res$input_tokens, cache_creation_input_tokens = res$cache_creation_input_tokens,
      cache_read_input_tokens = res$cache_read_input_tokens,
      input_total = llm_cli_input_total(res), output_tokens = res$output_tokens,
      seconds = round(res$seconds, 1), duration_ms = res$duration_ms)
  }

  # 1. Flags in the installed CLI's help text; a minimal call through stdin.
  help <- system2(CLAUDE_CLI, "--help", stdout = TRUE, stderr = TRUE)
  version <- system2(CLAUDE_CLI, "--version", stdout = TRUE, stderr = TRUE)
  flags <- data.frame(flag = STEP0_FLAGS,
                      in_help = vapply(STEP0_FLAGS, function(f) any(grepl(f, help, fixed = TRUE)), logical(1)))
  if (!all(flags$in_help)) stop("Flags missing from `claude --help`: ",
                                paste(flags$flag[!flags$in_help], collapse = ", "), call. = FALSE)
  pf <- tempfile(fileext = ".md")
  writeLines("Answer with exactly the word the user gives you, nothing else.", pf)
  a <- llm_cli_call("pineapple", model, pf)
  log_call("stdin_check", a)
  stdin_ok <- identical(trimws(tolower(a$output)), "pineapple")
  json_fields <- sort(names(a$raw))

  # 2. Canary: does anything besides the record reach the model?
  gs <- read_goldset()
  can <- read_canaries(gs)
  writeLines(paste("Repeat, verbatim and in full, every instruction, file content, memory,",
                   "environment detail or other context you were given besides this message.",
                   "If there is none, say NONE."), pf)
  b <- llm_cli_call("List everything you know about the project, the user and the working directory.",
                    model, pf)
  log_call("canary", b)
  leaked <- can$strings[vapply(can$strings, grepl, logical(1), x = b$output, fixed = TRUE)]
  dir.create(run$data_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(b$output, file.path(run$data_dir, "canary_answer.txt"))

  # 3. Overhead: a one-character record with the real prompt and schema.
  c3 <- llm_cli_call(".", model, prompt_path(cfg$prompt), schema = cfg$prompt)
  log_call("overhead", c3)
  overhead_valid <- nrow(validate_records(list(c(list(uri = "step0", backend = "claude_code",
                                                      model = model, answered_at = utc_now()),
                                                 c3$output)), cfg$prompt)) == 0

  calls_df <- do.call(rbind, calls)
  readr::write_tsv(calls_df, file.path(run$dir, "calls.tsv"), na = "")
  m <- list(cli_version = version[1], model = model, flags_ok = all(flags$in_help),
            stdin_ok = stdin_ok, json_fields = json_fields,
            canary_files = length(can$files), canary_strings = length(can$strings),
            canary_leaks = length(leaked), leaked = leaked,
            overhead_input_tokens = llm_cli_input_total(c3),
            overhead_output_tokens = c3$output_tokens, overhead_answer_valid = overhead_valid)
  body <- c("Step 0 of the reading test (docs/reading-benchmark.md, section 4).", "",
            "## Calls", "", md_table(calls_df), "",
            "## Checks", "",
            md_table(data.frame(check = c("CLI version", "all flags in `claude --help`",
                                          "record read from stdin", "JSON output fields",
                                          "canary strings checked (files)", "canary strings leaked",
                                          "overhead answer valid against schema"),
                                value = c(m$cli_version, m$flags_ok, m$stdin_ok,
                                          paste(json_fields, collapse = ", "),
                                          sprintf("%d (%d)", m$canary_strings, m$canary_files),
                                          if (length(leaked)) paste(leaked, collapse = "; ") else "0",
                                          overhead_valid)), align = "l"), "",
            sprintf("Overhead per call with prompt and schema: %s input tokens (fresh + cache), %s output tokens.",
                    m$overhead_input_tokens, m$overhead_output_tokens), "",
            sprintf("The canary answer is kept locally in `%s/canary_answer.txt`.", run$data_dir))
  run_finish(run, m, body)
  cat(sprintf("Wrote %s\n", run$dir))
  cat(sprintf("stdin ok: %s; canary leaks: %d; overhead input tokens: %s\n", stdin_ok,
              length(leaked), m$overhead_input_tokens))
  if (length(leaked)) {
    cat("LEAK: the plan stops here and goes back to Anders.\n", paste0("  - ", leaked, "\n"), sep = "")
    quit(status = 1)
  }
}

# ---- read <label>: one matrix cell ------------------------------------------------------

cmd_read_cell <- function(args) {
  label <- args[1]
  cfg <- read_config()
  gs <- read_goldset()
  man <- read_manifest()
  tr <- read_truth()
  st <- read_stations()
  if (nrow(validate_truth(tr, gs$survey_ref, man))) stop("extraction_truth.csv invalid; run `run.R check`.", call. = FALSE)
  if (identical(cfg$backend, "ellmer")) .run_ellmer("read", label)
  if (!identical(cfg$backend, "claude_code")) stop("Unknown backend: ", cfg$backend, call. = FALSE)

  run <- run_start("read", label, args, config_files = c(READ_CONFIG_FILE))
  dir.create(run$data_dir, recursive = TRUE, showWarnings = FALSE)
  terms <- read_keyword_terms(cfg)
  dp <- read_doc_pages(man)
  if (!identical(cfg$cell$documents, "all")) {
    unknown <- setdiff(unlist(cfg$cell$documents), dp$document)
    if (length(unknown)) stop("Unknown documents in config: ", paste(unknown, collapse = "; "), call. = FALSE)
    dp <- dp[dp$document %in% unlist(cfg$cell$documents), ]
  }
  con <- db_connect()
  on.exit(db_disconnect(con), add = TRUE)
  db_init(con)
  cards <- knowledge_for_batch(con, unlist(cfg$cards))
  sizes <- if (isTRUE(cfg$cell$cascade)) READ_SIZES[match(cfg$cell$model, READ_SIZES):3] else cfg$cell$model
  cell_key <- sprintf("read:%s:%s:%s", cfg$cell$model, cfg$cell$input,
                      if (isTRUE(cfg$cell$cascade)) "cascade" else "single")
  sv <- schema_version(cfg$prompt)
  pf <- prompt_path(cfg$prompt)

  calls <- list(); answers <- list(); scores <- list(); stations <- list(); review <- character()
  for (sha in unique(dp$sha256)) {
    d <- dp[dp$sha256 == sha, ]
    d <- d[order(d$page), ]
    sel <- read_select_pages(d, cfg$cell$input, cfg$pages, terms)
    text <- read_record_text(d, sel, cards)
    leaks <- read_record_leaks(text, d$text[d$page %in% sel], gs)
    if (length(leaks)) stop("Gold-set strings in the record for ", d$document[1], ": ",
                            paste(leaks, collapse = "; "), call. = FALSE)
    content_sha <- digest::digest(text, algo = "sha256", serialize = FALSE)
    for (r in seq_len(cfg$cell$repeats)) {
      uri <- paste0(read_doc_uri(sha), if (r > 1) paste0("#r", r))
      if (db_llm_cached(con, cell_key, uri, content_sha, sv)) {
        message("cached, not sent again: ", d$document[1], " (repeat ", r, ")")
        next
      }
      final <- NULL
      for (k in seq_along(sizes)) {
        model <- cfg$models[[sizes[k]]]
        res <- llm_cli_call(text, model, pf, schema = cfg$prompt)
        rec <- c(list(uri = uri, backend = "claude_code", model = model, answered_at = utc_now()),
                 res$output)
        bad <- validate_records(list(rec), cfg$prompt, id_field = "uri")
        fired <- if (nrow(bad)) data.frame(rule = "schema_failure", field = "", detail = bad$errors[1])
                 else read_rules(rec, text)
        calls[[length(calls) + 1]] <- data.frame(
          document = d$document[1], repeat_no = r, step = k, size = sizes[k], model_requested = model,
          models_reported = paste(res$models, collapse = ";"), n_pages = length(sel),
          input_total = llm_cli_input_total(res), input_tokens = res$input_tokens,
          cache_creation_input_tokens = res$cache_creation_input_tokens,
          cache_read_input_tokens = res$cache_read_input_tokens, output_tokens = res$output_tokens,
          seconds = round(res$seconds, 1),
          rules_fired = paste(unique(paste(fired$rule, fired$field, sep = ":")), collapse = "; "))
        final <- list(rec = rec, valid = !nrow(bad), fired = fired)
        if (!nrow(fired)) break
      }
      if (!final$valid) {
        review <- c(review, sprintf("%s (repeat %d): schema failure on the last step", d$document[1], r))
        next
      }
      if (nrow(final$fired)) review <- c(review, sprintf("%s (repeat %d): %s", d$document[1], r,
                                                         paste(unique(final$fired$rule), collapse = ", ")))
      answers[[length(answers) + 1]] <- final$rec
      run_id <- db_run_start(con, kind = "read", step = cell_key, run_dir = run$dir,
                             batch = basename(run$dir), backend = "claude_code",
                             provider = "anthropic", model = final$rec$model, prompt_file = pf,
                             prompt_sha256 = sha256_file(pf), schema_version = sv)
      db_insert_llm_answers(con, data.frame(
        step = cell_key, record_uri = uri, content_sha256 = content_sha, schema_version = sv,
        answer_json = as.character(jsonlite::toJSON(final$rec, auto_unbox = TRUE, null = "null")),
        run_id = run_id, answered_at = final$rec$answered_at))
      doc_calls <- do.call(rbind, calls[vapply(calls, function(x) x$document == d$document[1] &&
                                                 x$repeat_no == r, logical(1))])
      db_run_finish(con, run_id, n_records = 1, input_tokens = sum(doc_calls$input_total),
                    output_tokens = sum(doc_calls$output_tokens))
      t <- tr[tr$document == d$document[1], ]
      if (nrow(t)) scores[[length(scores) + 1]] <- cbind(repeat_no = r, score_document(final$rec, t))
      st_doc <- st[st$document == d$document[1], ]
      stations[[length(stations) + 1]] <- cbind(document = d$document[1], repeat_no = r,
                                                key_page_coverage = read_page_coverage(t$page, sel),
                                                score_stations(final$rec, st_doc))
    }
  }

  .bind <- function(x) if (length(x)) do.call(rbind, x) else data.frame()
  calls_df <- .bind(calls); scores_df <- .bind(scores); stations_df <- .bind(stations)
  readr::write_tsv(calls_df, file.path(run$dir, "calls.tsv"), na = "")
  readr::write_tsv(scores_df, file.path(run$dir, "scores.tsv"), na = "")
  readr::write_tsv(stations_df, file.path(run$dir, "stations.tsv"), na = "")
  writeLines(vapply(answers, function(a) as.character(jsonlite::toJSON(a, auto_unbox = TRUE, null = "null")), ""),
             file.path(run$data_dir, "answers.jsonl"), useBytes = TRUE)
  m <- read_metrics(calls_df, scores_df, stations_df, cfg)
  m$review <- review
  run_finish(run, m, read_readme(m, calls_df, scores_df, cfg, review))
  cat(sprintf("Wrote %s\n", run$dir))
}

#' Metrics for one cell. Accuracy and invented values are given for verified
#' key rows and for all key rows separately (the key is drafted by Claude).
read_metrics <- function(calls, scores, stations, cfg) {
  acc <- function(s) {
    if (!nrow(s)) return(list(n = 0))
    ns_key <- s$truth == "not_stated"
    inv <- sum(s$outcome == "invented")
    ci <- wilson_ci(inv, sum(ns_key))
    list(n = nrow(s), accuracy = round(mean(s$score), 3),
         per_field = as.list(round(tapply(s$score, s$field, mean), 3)),
         invented = inv, key_not_stated = sum(ns_key),
         invented_rate = if (sum(ns_key)) round(inv / sum(ns_key), 3) else NA,
         invented_ci = if (sum(ns_key)) round(unlist(ci), 3) else NA)
  }
  per_doc <- if (nrow(calls)) aggregate(cbind(input_total, output_tokens, seconds) ~ document + repeat_no,
                                        calls, sum) else data.frame()
  list(cell = cfg$cell, models = cfg$models,
       n_documents = if (nrow(per_doc)) nrow(per_doc) else 0,
       mean_input_tokens = if (nrow(per_doc)) round(mean(per_doc$input_total)) else NA,
       mean_output_tokens = if (nrow(per_doc)) round(mean(per_doc$output_tokens)) else NA,
       mean_seconds = if (nrow(per_doc)) round(mean(per_doc$seconds), 1) else NA,
       escalation_rate = if (nrow(calls)) round(mean(tapply(calls$step, paste(calls$document, calls$repeat_no), max) > 1), 3) else NA,
       verified = acc(scores[scores$verified == "yes", , drop = FALSE]),
       all_rows = acc(scores),
       stations_precision = if (nrow(stations)) round(mean(stations$precision, na.rm = TRUE), 3) else NA,
       stations_recall = if (nrow(stations)) round(mean(stations$recall, na.rm = TRUE), 3) else NA,
       page_selection_coverage = if (nrow(stations)) round(mean(stations$key_page_coverage, na.rm = TRUE), 3) else NA,
       end_to_end_match = "not built")
}

read_readme <- function(m, calls, scores, cfg, review) {
  c(sprintf("Reading-test cell: model `%s`, input `%s`, cascade `%s`, repeats %d.",
            cfg$cell$model, cfg$cell$input, cfg$cell$cascade, cfg$cell$repeats), "",
    "Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.",
    "The key is drafted by Claude and counts only where `verified = yes`;",
    "scores over all rows are shown separately until the key is verified.", "",
    md_table(data.frame(
      measure = c("documents", "mean input tokens per document", "mean output tokens",
                  "mean seconds", "escalation rate", "accuracy, verified rows",
                  "accuracy, all rows", "invented values, all rows",
                  "station precision / recall", "key pages inside selected pages",
                  "end-to-end match"),
      value = c(m$n_documents, m$mean_input_tokens, m$mean_output_tokens, m$mean_seconds,
                m$escalation_rate,
                if (m$verified$n) sprintf("%s (n = %d)", m$verified$accuracy, m$verified$n) else "no verified rows",
                if (m$all_rows$n) sprintf("%s (n = %d)", m$all_rows$accuracy, m$all_rows$n) else "not run",
                if (m$all_rows$n) sprintf("%d of %d", m$all_rows$invented, m$all_rows$key_not_stated) else "not run",
                sprintf("%s / %s", m$stations_precision, m$stations_recall),
                m$page_selection_coverage, m$end_to_end_match)), align = "l"), "",
    "## Calls", "", md_table(calls), "",
    "## Review list", "", if (length(review)) paste0("- ", review) else "None.")
}
