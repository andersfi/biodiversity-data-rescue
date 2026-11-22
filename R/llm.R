# Model calls through the Anthropic API with ellmer.
#
# One call per record: system prompt = the prompt file, user turn = the record
# text, structured output constrained by the JSON schema file
# (`output_config.format`). Thinking as set in LLM_THINKING; no prompt
# caching. Our code retries nothing; ellmer (httr2) retries a request up to 3
# tries in all on HTTP 429, 503 and 529 and on connection failures, with a
# 5-minute timeout per try. The API key comes from ANTHROPIC_API_KEY (~/.Renviron).

LLM_MODEL <- "claude-haiku-5-5"
# Extended thinking. Adaptive thinking (the model decides how much to think)
# at the API's default effort for this model (medium) is the closest the API
# offers to the `claude` CLI default used in v1. list(type = "disabled") turns
# it off (the v2 run).
LLM_THINKING <- list(type = "adaptive")
# Output tokens include thinking tokens, so leave room for both.
LLM_MAX_TOKENS <- 16000

# USD per million tokens for claude-haiku-5-5 (prompts under 100k tokens),
# fitted exactly from the cost the `claude` CLI reported in the v1 runs
# (`screening_v1`). Cache writes there were 1-hour writes; calls here do not
# cache, so that price is not used in practice.
PRICE_INPUT <- 0.10
PRICE_OUTPUT <- 0.50
PRICE_CACHE_WRITE <- 0.20
PRICE_CACHE_READ <- 0.01

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Text of a file as one string.
read_text <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

#' SHA-256 of a file.
file_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

#' The schema file as JSON text for the API, without `maxItems`, which the
#' API's structured output does not support. check_output() still enforces it.
api_schema <- function(schema_file) {
  drop <- function(x) {
    if (!is.list(x)) return(x)
    x$maxItems <- NULL
    lapply(x, drop)
  }
  as.character(jsonlite::toJSON(drop(jsonlite::read_json(schema_file)), auto_unbox = TRUE))
}

#' Price of one call from its token counts.
llm_cost <- function(input, cache_write, cache_read, output) {
  (input * PRICE_INPUT + cache_write * PRICE_CACHE_WRITE + cache_read * PRICE_CACHE_READ +
     output * PRICE_OUTPUT) / 1e6
}

#' Chat object for one call. "anthropic": the Anthropic API (key
#' ANTHROPIC_API_KEY). "ntnu": NTNU's OpenAI-compatible service (base URL
#' NTNU_API_BASE_URL + "/v1", key NTNU_API_KEY), strict json_schema output.
llm_chat <- function(provider, model, prompt_file, max_tokens) {
  system_prompt <- read_text(prompt_file)
  switch(provider,
    anthropic = ellmer::chat_anthropic(
      system_prompt = system_prompt, model = model, cache = "none",
      params = ellmer::params(max_tokens = max_tokens),
      api_args = list(thinking = LLM_THINKING), echo = "none"),
    ntnu = ellmer::chat_openai_compatible(
      base_url = paste0(sub("/+$", "", Sys.getenv("NTNU_API_BASE_URL")), "/v1"),
      name = "NTNU", system_prompt = system_prompt, model = model,
      credentials = function() Sys.getenv("NTNU_API_KEY"),
      params = ellmer::params(max_tokens = max_tokens), strict = TRUE, echo = "none"),
    stop("Unknown provider: ", provider, call. = FALSE))
}

#' Run one call. Errors on an API error, on a reply that did not end normally
#' (Anthropic stop_reason other than end_turn, OpenAI finish_reason other than
#' stop: e.g. truncated, or refusal), and on empty or non-JSON output.
#'
#' Returns list(output (parsed structured output, or the text), models (model
#' id the API reports), the four token counts, thinking_tokens (part of
#' output_tokens), cost_usd (from PRICE_*; 0 for ntnu), cost_usd_ellmer
#' (ellmer's own price), seconds (wall), raw (API response JSON)).
llm_call <- function(record_text, prompt_file, schema_file = NULL, model = LLM_MODEL,
                     provider = "anthropic", max_tokens = LLM_MAX_TOKENS) {
  chat <- llm_chat(provider, model, prompt_file, max_tokens)
  t0 <- Sys.time()
  out <- tryCatch(
    if (!is.null(schema_file)) {
      chat$chat_structured(record_text, type = ellmer::type_from_schema(text = api_schema(schema_file)),
                           convert = FALSE)
    } else {
      chat$chat(record_text)
    },
    error = function(e) e)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  turn <- chat$last_turn()
  if (!is.null(turn)) {
    stop_reason <- if (provider == "anthropic") turn@json$stop_reason else
      turn@json$choices[[1]]$finish_reason
    if (!identical(stop_reason, if (provider == "anthropic") "end_turn" else "stop")) {
      stop(sprintf("Reply did not end normally: stop reason %s", stop_reason %||% "missing"),
           call. = FALSE)
    }
  }
  if (inherits(out, "error")) stop(conditionMessage(out), call. = FALSE)
  if (is.null(turn)) stop("No assistant turn returned", call. = FALSE)
  if (!is.null(schema_file) && (!is.list(out) || !length(out))) {
    stop("Empty or non-JSON structured output", call. = FALSE)
  }
  raw <- turn@json
  u <- raw$usage %||% list()
  num <- function(x) if (is.null(x)) 0 else as.numeric(x)
  tok <- if (provider == "anthropic") {
    list(input_tokens = num(u$input_tokens),
         cache_creation_input_tokens = num(u$cache_creation_input_tokens),
         cache_read_input_tokens = num(u$cache_read_input_tokens),
         output_tokens = num(u$output_tokens),
         thinking_tokens = num(u$output_tokens_details$thinking_tokens))
  } else {
    cached <- num(u$prompt_tokens_details$cached_tokens)
    list(input_tokens = num(u$prompt_tokens) - cached, cache_creation_input_tokens = 0,
         cache_read_input_tokens = cached, output_tokens = num(u$completion_tokens),
         thinking_tokens = num(u$completion_tokens_details$reasoning_tokens))
  }
  cost <- if (provider == "anthropic") {
    llm_cost(tok$input_tokens, tok$cache_creation_input_tokens, tok$cache_read_input_tokens,
             tok$output_tokens)
  } else 0
  c(list(output = out, models = raw$model %||% NA_character_), tok,
    list(cost_usd = cost, cost_usd_ellmer = as.numeric(turn@cost %||% NA_real_),
         seconds = secs, raw = raw))
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

#' TRUE when an error message says the API refused for rate, load or billing
#' (429 rate limit, 529 overloaded, credit balance). A run stops on such an
#' error instead of recording one failure per document. ellmer has already
#' retried 429 and 529 by then.
is_limit_error <- function(msg) {
  grepl("\\b429\\b|\\b529\\b|rate.?limit|overloaded|credit balance|billing", msg,
        ignore.case = TRUE)
}

#' Store the raw API response JSON of one call under data/llm/<step>/.
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
