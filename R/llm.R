# All LLM calls go through this file (architecture rule 1).
#
# File contract (CLAUDE.md, "LLM file contract"):
#   in : data/llm_in/<step>_<batch>.jsonl   uri, text fields, content_sha256,
#                                           schema_version, prompt_file
#   out: data/llm_out/<step>_<batch>.jsonl  same uris, fields per schemas/<step>.json,
#                                           plus backend, model, answered_at
#
# Backends behind one interface:
#   claude_code  Claude Code itself answers the batch file (pilot).
#   ellmer       provider from config/llm.yaml (stub; not implemented yet).
# Import and validation are identical for both.
#
# Depends on R/db.R and R/validate.R.

LLM_IN_DIR <- "data/llm_in"
LLM_OUT_DIR <- "data/llm_out"
LLM_CONFIG <- "config/llm.yaml"

llm_config <- function(path = LLM_CONFIG) yaml::read_yaml(path)

llm_paths <- function(step, batch) {
  name <- sprintf("%s_%s.jsonl", step, batch)
  list(input = file.path(LLM_IN_DIR, name), output = file.path(LLM_OUT_DIR, name))
}

prompt_path <- function(step) file.path("prompts", paste0(step, ".md"))

# SHA-256 of the exact content sent for one record (text fields only).
.content_sha <- function(record, text_fields) {
  digest::digest(jsonlite::toJSON(record[text_fields], auto_unbox = TRUE), algo = "sha256",
                 serialize = FALSE)
}

.write_jsonl <- function(rows, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  lines <- vapply(rows, function(r) as.character(jsonlite::toJSON(r, auto_unbox = TRUE, na = "null")), "")
  writeLines(enc2utf8(lines), path, useBytes = TRUE)
}

.read_jsonl <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  lapply(seq_along(lines), function(i) {
    tryCatch(jsonlite::fromJSON(lines[i], simplifyVector = FALSE),
             error = function(e) stop(sprintf("%s line %d is not valid JSON: %s",
                                              path, i, conditionMessage(e)), call. = FALSE))
  })
}

#' Write a batch input file. Records already answered for the same step, content
#' and schema version are skipped (rule 5). Returns the number of records written.
#'
#' @param records data.frame with a `uri` column and the text fields.
llm_write_batch <- function(con, step, batch, records, text_fields) {
  stopifnot("uri" %in% names(records), all(text_fields %in% names(records)))
  if (anyDuplicated(records$uri)) stop("Duplicated uri in batch", call. = FALSE)
  pf <- prompt_path(step)
  if (!file.exists(pf)) stop("Prompt file not found: ", pf, call. = FALSE)
  sv <- schema_version(step)

  rows <- lapply(seq_len(nrow(records)), function(i) {
    r <- as.list(records[i, c("uri", text_fields), drop = FALSE])
    r$content_sha256 <- .content_sha(r, text_fields)
    r$schema_version <- sv
    r$prompt_file <- pf
    r
  })
  sha <- vapply(rows, `[[`, "", "content_sha256")
  cached <- db_llm_cached(con, step, records$uri, sha, sv)
  rows <- rows[!cached]
  message(sprintf("%s/%s: %d records, %d cached, %d to send", step, batch,
                  nrow(records), sum(cached), length(rows)))
  if (length(rows)) .write_jsonl(rows, llm_paths(step, batch)$input)
  invisible(length(rows))
}

#' Run a batch with the configured backend.
llm_run <- function(step, batch, backend = llm_config()$backend) {
  switch(backend,
    claude_code = .run_claude_code(step, batch),
    ellmer      = .run_ellmer(step, batch),
    stop("Unknown LLM backend: ", backend, call. = FALSE)
  )
}

# The claude_code backend does not call anything: Claude Code reads the input
# file, the prompt and the supplied knowledge cards, and writes the output file.
.run_claude_code <- function(step, batch) {
  p <- llm_paths(step, batch)
  if (!file.exists(p$input)) stop("No input file: ", p$input, call. = FALSE)
  message(paste(
    "claude_code backend: ask Claude Code to answer the batch.",
    sprintf("  input : %s", p$input),
    sprintf("  prompt: %s", prompt_path(step)),
    sprintf("  schema: %s", schema_path(step)),
    sprintf("  output: %s", p$output),
    "Then run llm_import() with the model Claude Code reports.", sep = "\n"))
  invisible(p$output)
}

.run_ellmer <- function(step, batch) {
  stop("ellmer backend not implemented yet (see config/llm.yaml).", call. = FALSE)
}

#' Validate an answer file and store it. Errors on any invalid line, on uris that
#' do not match the input file, or on a model name that differs from `model`.
#' Logs the batch in run_log. Returns the run_id.
llm_import <- function(con, step, batch, provider, model, model_version = NA,
                       input_tokens = NA, output_tokens = NA) {
  p <- llm_paths(step, batch)
  inp <- .read_jsonl(p$input)
  out <- .read_jsonl(p$output)
  in_uri <- vapply(inp, `[[`, "", "uri")
  out_uri <- vapply(out, function(r) as.character(r$uri %||% NA), "")

  if (anyDuplicated(out_uri)) stop("Duplicated uri in ", p$output, call. = FALSE)
  extra <- setdiff(out_uri, in_uri)
  missing <- setdiff(in_uri, out_uri)
  if (length(extra) || length(missing)) {
    stop(sprintf("uri mismatch in %s: %d missing, %d not in input", p$output,
                 length(missing), length(extra)), call. = FALSE)
  }
  assert_valid(out, step, id_field = "uri")
  models <- unique(vapply(out, `[[`, "", "model"))
  if (!identical(models, model)) {
    stop("Output reports model(s) ", paste(models, collapse = ", "), ", expected ", model,
         call. = FALSE)
  }

  pf <- inp[[1]]$prompt_file
  sv <- inp[[1]]$schema_version
  if (!identical(sv, schema_version(step))) {
    stop("Schema version changed since the batch was written: ", sv, " vs ",
         schema_version(step), call. = FALSE)
  }
  backend <- unique(vapply(out, `[[`, "", "backend"))
  stopifnot(length(backend) == 1)

  run_id <- db_run_start(con, kind = "llm", step = step, batch = batch, backend = backend,
                         provider = provider, model = model, model_version = model_version,
                         prompt_file = pf,
                         prompt_sha256 = digest::digest(file = pf, algo = "sha256"),
                         schema_version = sv)
  sha <- setNames(vapply(inp, `[[`, "", "content_sha256"), in_uri)
  db_insert_llm_answers(con, data.frame(
    step = step, record_uri = out_uri, content_sha256 = unname(sha[out_uri]),
    schema_version = sv,
    answer_json = vapply(out, function(r) as.character(jsonlite::toJSON(r, auto_unbox = TRUE)), ""),
    run_id = run_id,
    answered_at = vapply(out, `[[`, "", "answered_at")
  ))
  db_run_finish(con, run_id, n_records = length(out),
                input_tokens = input_tokens, output_tokens = output_tokens)
  run_id
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
