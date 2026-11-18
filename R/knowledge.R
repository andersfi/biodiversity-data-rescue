# Knowledge cards: markdown files with YAML front matter in knowledge/<type>/.
# knowledge/_templates/ holds templates and is never loaded.

KNOWLEDGE_DIR <- "knowledge"
KNOWLEDGE_TYPE_DIRS <- c(aggregator = "aggregators", source = "sources",
                         precedent = "precedents", vocabulary = "vocabulary")

list_knowledge_files <- function(dir = KNOWLEDGE_DIR) {
  f <- list.files(file.path(dir, KNOWLEDGE_TYPE_DIRS), pattern = "\\.md$", full.names = TRUE)
  sort(f[!startsWith(basename(f), "_")])
}

#' Parse one card. Returns list(front = <list>, body = <chr>, path, sha256).
read_knowledge_card <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  delim <- which(lines == "---")
  if (length(delim) < 2 || delim[1] != 1) stop("No YAML front matter in ", path, call. = FALSE)
  front <- yaml::yaml.load(paste(lines[2:(delim[2] - 1)], collapse = "\n"))
  # YAML parses dates as strings with yaml.load; keep everything as plain values.
  front <- lapply(front, function(x) if (inherits(x, "Date")) format(x) else x)
  body <- paste(lines[-(1:delim[2])], collapse = "\n")
  list(front = front, body = trimws(body), path = path,
       sha256 = digest::digest(file = path, algo = "sha256"))
}

#' Validate a parsed card. Also checks that the card sits in the folder for its type.
#' Front matter as JSON. Array fields stay arrays even with one element.
knowledge_front_json <- function(front) {
  for (k in intersect(c("link_keys", "where", "applies_to", "survey_refs", "tags"), names(front))) {
    front[[k]] <- I(unlist(front[[k]]) %||% character())
  }
  jsonlite::toJSON(front, auto_unbox = TRUE, null = "null")
}

validate_knowledge_card <- function(card, check_folder = TRUE) {
  js <- knowledge_front_json(card$front)
  res <- schema_validator("knowledge_card")$validate(js, verbose = TRUE)
  errs <- if (isTRUE(res)) character() else
    paste(attr(res, "errors")$instancePath, attr(res, "errors")$message)
  expected_dir <- unname(KNOWLEDGE_TYPE_DIRS[as.character(card$front$type %||% "")])
  if (check_folder && !is.na(expected_dir) && basename(dirname(card$path)) != expected_dir) {
    errs <- c(errs, sprintf("type '%s' belongs in knowledge/%s/", card$front$type, expected_dir))
  }
  errs
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Select the cards relevant to a batch (rule 11: send only relevant cards).
knowledge_for_batch <- function(con, card_ids) {
  cards <- db_knowledge_cards(con)
  missing <- setdiff(card_ids, cards$card_id)
  if (length(missing)) stop("Unknown knowledge cards: ", paste(missing, collapse = ", "))
  cards[cards$card_id %in% card_ids, ]
}
