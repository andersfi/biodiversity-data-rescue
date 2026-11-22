# Model calls through the headless `claude` CLI (`claude -p`).
#
# One call per record, in a fresh empty temporary directory, with every tool,
# MCP server, setting source, slash command and session file switched off, and
# the default system prompt replaced by the prompt file. The record goes in on
# stdin. Nothing is retried. The CLI reports `total_cost_usd`, the API price of
# the call.

CLAUDE_CLI <- "claude"
LLM_MODEL <- "haiku"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Arguments for one headless call (unquoted; quoting happens in llm_cli_call).
llm_cli_args <- function(model, system_prompt, schema_json = NULL) {
  stopifnot(is.character(model), length(model) == 1, nzchar(model),
            is.character(system_prompt), length(system_prompt) == 1)
  c("-p",
    "--model", model,
    "--output-format", "json",
    if (!is.null(schema_json)) c("--json-schema", schema_json),
    "--system-prompt", system_prompt,
    "--tools", "",
    "--strict-mcp-config",
    "--setting-sources", "",
    "--disable-slash-commands",
    "--no-session-persistence")
}

#' Text of a file as one string.
read_text <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

#' SHA-256 of a file.
file_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

#' Run one headless call. Errors on a non-zero exit, on is_error, and (with a
#' schema) when no structured output comes back.
#'
#' Returns list(output (parsed structured output, or the text result), models
#' (model ids in modelUsage), the four token counts, cost_usd, duration_ms,
#' seconds (wall), raw (parsed JSON)).
llm_cli_call <- function(record_text, prompt_file, schema_file = NULL, model = LLM_MODEL,
                         cli = CLAUDE_CLI, timeout = 900) {
  system_prompt <- read_text(prompt_file)
  schema_json <- if (!is.null(schema_file)) as.character(jsonlite::minify(read_text(schema_file)))
  args <- llm_cli_args(model, system_prompt, schema_json)

  wd <- tempfile("llm-wd-")
  io <- tempfile("llm-io-")
  dir.create(wd)
  dir.create(io)
  on.exit(unlink(c(wd, io), recursive = TRUE), add = TRUE)
  rec <- file.path(io, "record.txt")
  err <- file.path(io, "stderr.txt")
  writeLines(enc2utf8(record_text), rec, useBytes = TRUE)

  t0 <- Sys.time()
  out <- withr::with_dir(wd, suppressWarnings(
    system2(cli, shQuote(args), stdin = rec, stdout = TRUE, stderr = err, timeout = timeout)))
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  status <- attr(out, "status") %||% 0L
  if (status != 0) {
    stop(sprintf("claude -p exited with status %s: %s", status,
                 paste(utils::head(c(readLines(err, warn = FALSE), out), 20), collapse = "\n")),
         call. = FALSE)
  }
  raw <- tryCatch(jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE),
                  error = function(e) stop("claude -p output is not JSON: ",
                                           substr(paste(out, collapse = "\n"), 1, 500), call. = FALSE))
  if (isTRUE(raw$is_error)) stop("claude -p reported an error: ", raw$result %||% "", call. = FALSE)
  output <- if (!is.null(schema_file)) raw$structured_output else raw$result
  if (is.null(output)) stop("claude -p returned no ",
                            if (!is.null(schema_file)) "structured_output" else "result", call. = FALSE)
  u <- raw$usage %||% list()
  num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
  list(output = output,
       models = names(raw$modelUsage %||% list()),
       input_tokens = num(u$input_tokens),
       cache_creation_input_tokens = num(u$cache_creation_input_tokens),
       cache_read_input_tokens = num(u$cache_read_input_tokens),
       output_tokens = num(u$output_tokens),
       cost_usd = num(raw$total_cost_usd),
       duration_ms = num(raw$duration_ms),
       seconds = secs,
       raw = raw)
}

#' Check a parsed JSON value against a JSON schema (the subset used in
#' prompts/*.schema.json: type, enum, required, additionalProperties, items,
#' maxItems). Returns a character vector of problems; empty when valid.
validate_schema <- function(x, schema, path = "$") {
  type <- schema$type
  is_scalar <- function(v) !is.list(v) && length(v) == 1 && !is.na(v)
  ok <- switch(type,
               object = is.list(x) && (length(x) == 0 || !is.null(names(x))),
               array = is.list(x) && is.null(names(x)),
               string = is.character(x) && is_scalar(x),
               integer = is.numeric(x) && is_scalar(x) && x == round(x),
               boolean = is.logical(x) && is_scalar(x),
               stop("Schema type not handled: ", type))
  if (!ok) return(sprintf("%s: not of type %s", path, type))
  problems <- character()
  if (!is.null(schema$enum) && !(x %in% unlist(schema$enum))) {
    problems <- c(problems, sprintf("%s: '%s' not in enum", path, x))
  }
  if (type == "object") {
    missing <- setdiff(unlist(schema$required), names(x))
    if (length(missing)) problems <- c(problems, sprintf("%s: missing %s", path,
                                                         paste(missing, collapse = ", ")))
    extra <- setdiff(names(x), names(schema$properties))
    if (isFALSE(schema$additionalProperties) && length(extra)) {
      problems <- c(problems, sprintf("%s: unknown field %s", path, paste(extra, collapse = ", ")))
    }
    for (nm in intersect(names(x), names(schema$properties))) {
      problems <- c(problems, validate_schema(x[[nm]], schema$properties[[nm]],
                                              paste0(path, ".", nm)))
    }
  }
  if (type == "array") {
    if (!is.null(schema$maxItems) && length(x) > schema$maxItems) {
      problems <- c(problems, sprintf("%s: %d items, max %d", path, length(x), schema$maxItems))
    }
    for (i in seq_along(x)) {
      problems <- c(problems, validate_schema(x[[i]], schema$items, sprintf("%s[%d]", path, i)))
    }
  }
  problems
}

#' Stop when `output` does not match the schema file.
check_output <- function(output, schema_file) {
  problems <- validate_schema(output, jsonlite::read_json(schema_file))
  if (length(problems)) {
    stop("Model output fails schema check: ", paste(problems, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
}

#' Store the raw CLI JSON of one call.
save_raw_call <- function(res, step, identifier) {
  dir <- file.path("data/llm", step)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(res$raw, file.path(dir, paste0(identifier, ".json")),
                       auto_unbox = TRUE, null = "null", pretty = TRUE, digits = NA)
}

#' Collapse a list of strings or numbers to a `;`-joined string (NA when empty).
join <- function(x) {
  x <- unlist(x)
  if (length(x)) paste(x, collapse = ";") else NA_character_
}
