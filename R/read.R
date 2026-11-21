# Reading test (phase 3): page selection, record building, cascade rules and
# scoring. Plan: docs/reading-benchmark.md. Works on page texts handed in by
# the `read` verb; never touches the full-text files itself.

READ_CONFIG_FILE <- "config/read.yaml"
TRUTH_FILE <- "goldset/extraction_truth.csv"
TRUTH_COLUMNS <- c("survey_ref", "document", "field", "value", "page", "verified", "note")
TRUTH_FIELDS <- c("period", "institution", "region", "taxon_scope", "data_statement")
DATA_CATEGORIES <- c("appendix_species_list", "vannmiljo", "gbif", "other_database",
                     "on_request", "other_report", "not_stated")
READ_SIZES <- c("small", "medium", "large")
READ_INPUTS <- c("summary", "pages", "full")

read_config <- function(path = READ_CONFIG_FILE) {
  cfg <- yaml::read_yaml(path)
  stopifnot(cfg$cell$model %in% READ_SIZES, cfg$cell$input %in% READ_INPUTS,
            is.logical(cfg$cell$cascade), all(READ_SIZES %in% names(cfg$models)))
  cfg
}

# ---- answer key -------------------------------------------------------------------

read_truth <- function(path = TRUTH_FILE) {
  if (!file.exists(path)) stop("No answer key: ", path, call. = FALSE)
  readr::read_csv(path, col_types = readr::cols(.default = "c"), na = character(),
                  progress = FALSE)
}

#' Problems in extraction_truth.csv; zero rows when valid.
validate_truth <- function(tr, survey_refs, man) {
  probs <- list()
  add <- function(i, msg) probs[[length(probs) + 1]] <<- data.frame(
    row = i, survey_ref = if (i > 0) tr$survey_ref[i] else "", problem = msg)
  if (!identical(names(tr), TRUTH_COLUMNS)) {
    add(0, paste("header must be:", paste(TRUTH_COLUMNS, collapse = ",")))
    return(do.call(rbind, probs))
  }
  pairs <- do.call(rbind, lapply(seq_len(nrow(man)), function(i)
    data.frame(survey_ref = trimws(strsplit(man$survey_ref[i], ";")[[1]]), document = man$document[i])))
  key <- paste(tr$survey_ref, tr$document, tr$field)
  for (i in seq_len(nrow(tr))) {
    r <- tr[i, ]
    if (!r$survey_ref %in% survey_refs) add(i, "survey_ref not in goldset.csv")
    if (!any(pairs$survey_ref == r$survey_ref & pairs$document == r$document))
      add(i, "survey_ref + document not in fulltext_manifest.csv")
    if (!r$field %in% TRUTH_FIELDS) add(i, sprintf("field '%s' not one of %s", r$field,
                                                   paste(TRUTH_FIELDS, collapse = ", ")))
    if (!nzchar(r$value)) add(i, "value is empty (use not_stated)")
    if (r$field == "period" && r$value != "not_stated" &&
        !grepl("^[0-9]{4}(-[0-9]{4})?(;[0-9]{4}(-[0-9]{4})?)*$", r$value))
      add(i, "period must look like 2020, 2015-2019 or 2015;2017")
    if (r$field == "taxon_scope" && !r$value %in% c("yes", "no", "not_stated"))
      add(i, "taxon_scope must be yes, no or not_stated")
    if (r$field == "data_statement" &&
        !all(trimws(strsplit(r$value, ";")[[1]]) %in% DATA_CATEGORIES))
      add(i, paste("data_statement categories:", paste(DATA_CATEGORIES, collapse = ", ")))
    if (r$value == "not_stated" && nzchar(r$page)) add(i, "page given for not_stated")
    if (r$value != "not_stated" && !grepl("^[0-9]+$", r$page)) add(i, "page must be a number")
    if (!r$verified %in% c("yes", "no")) add(i, "verified must be yes or no")
  }
  if (any(duplicated(key))) add(0, paste("duplicated survey_ref+document+field:",
                                         paste(unique(key[duplicated(key)]), collapse = "; ")))
  if (!length(probs)) return(data.frame(row = integer(), survey_ref = character(), problem = character()))
  do.call(rbind, probs)
}

# ---- page selection (no model) --------------------------------------------------------

#' Keyword score per page: occurrences of the card's terms as whole words.
read_page_scores <- function(text, terms) {
  terms <- unique(tolower(unlist(terms)))
  low <- tolower(text)
  vapply(low, function(t) {
    sum(vapply(terms, function(w) {
      pat <- sprintf("(?<![[:alnum:]])\\Q%s\\E(?![[:alnum:]])", w)
      hits <- gregexpr(pat, t, perl = TRUE)[[1]]
      sum(hits > 0)
    }, numeric(1)))
  }, numeric(1), USE.NAMES = FALSE)
}

#' Pages to send for one document.
#'  full    : every page
#'  pages   : first_pages + top_k by keyword score
#'  summary : first_pages + each page with a summary heading and the page after
read_select_pages <- function(doc_pages, input, cfg_pages, terms) {
  n <- nrow(doc_pages)
  first <- seq_len(min(cfg_pages$first_pages, n))
  sel <- switch(input,
    full = seq_len(n),
    pages = {
      s <- read_page_scores(doc_pages$text, terms)
      s[first] <- -Inf
      ord <- order(-s, seq_len(n))
      top <- ord[seq_len(min(cfg_pages$top_k, n))]
      c(first, top[is.finite(s[top]) & s[top] > 0])
    },
    summary = {
      pat <- sprintf("(?im)^\\s*(%s)\\s*$", paste(cfg_pages$summary_terms, collapse = "|"))
      hit <- which(grepl(pat, doc_pages$text, perl = TRUE))
      c(first, hit, hit + 1)
    },
    stop("Unknown input: ", input, call. = FALSE))
  sort(unique(sel[sel >= 1 & sel <= n]))
}

#' Record text sent to the model: pages with [page N] markers, then cards.
read_record_text <- function(doc_pages, pages, cards = NULL) {
  p <- doc_pages[doc_pages$page %in% pages, ]
  body <- paste(sprintf("[page %d]\n%s", p$page, p$text), collapse = "\n\n")
  if (!is.null(cards) && nrow(cards)) {
    body <- paste0(body, "\n\n", paste(sprintf("[card %s]\n%s", cards$card_id, cards$body),
                                       collapse = "\n\n"))
  }
  body
}

#' Gold-set strings that must never reach the model: survey_ref slugs anywhere in
#' the record, and expected_status / where_data_are / notes values in the parts
#' that are not page text (the wrapper and the cards). Returns the hits.
read_record_leaks <- function(record_text, page_texts, gs) {
  wrapper <- record_text
  for (t in page_texts) wrapper <- sub(t, "", wrapper, fixed = TRUE)
  slugs <- gs$survey_ref[vapply(gs$survey_ref, grepl, logical(1), x = record_text, fixed = TRUE)]
  long <- unique(c(gs$where_data_are, gs$notes))
  long <- long[nchar(long) >= 25]
  hits_long <- long[vapply(long, grepl, logical(1), x = wrapper, fixed = TRUE)]
  status <- paste0("expected_status")
  c(slugs, hits_long, if (grepl(status, wrapper, fixed = TRUE)) status)
}

#' Share of answer-key pages inside the selected pages (page selection score).
read_page_coverage <- function(truth_pages, selected) {
  tp <- suppressWarnings(as.integer(truth_pages))
  tp <- tp[!is.na(tp)]
  if (!length(tp)) return(NA_real_)
  mean(tp %in% selected)
}

# ---- cascade rules (docs/reading-benchmark.md, section 2.3) ------------------------

UTM_PAIR_RE <- "(?<![0-9])[1-9][0-9]{5}(?:[.,][0-9]+)?\\s+[67][0-9]{6}(?:[.,][0-9]+)?(?![0-9])"
DEC_COORD_RE <- "(?<![0-9])(5[89]|6[0-9]|7[01])[.,][0-9]{3,}"
SAMPLING_YEAR_RE <- "(?i)(innsaml|prøvetak|prøvetatt|samlet inn|undersøkt|feltarbeid)[^\\n]{0,80}(19|20)[0-9]{2}|(19|20)[0-9]{2}[^\\n]{0,80}(innsaml|prøvetak|prøvetatt|samlet inn|feltarbeid)"
DATA_WORD_RE <- "(?i)(vedlegg|artsliste|vannmiljø)"

.squash <- function(x) gsub("\\s+", " ", x)

expand_years <- function(v) {
  if (is.null(v) || identical(v, "not_stated") || !nzchar(v)) return(integer())
  unlist(lapply(strsplit(v, ";", fixed = TRUE)[[1]], function(p) {
    y <- as.integer(strsplit(trimws(p), "-", fixed = TRUE)[[1]])
    if (length(y) == 2) seq(y[1], y[2]) else y
  }))
}

#' Coordinate pairs found by the page script (unique), for the count rule.
read_coordinate_rows <- function(text) {
  m <- regmatches(text, gregexpr(UTM_PAIR_RE, text, perl = TRUE))
  unique(.squash(unlist(m)))
}

#' Which escalation rules fire for one answer. `text` is the text sent.
#' Returns a data.frame(rule, field, detail); zero rows when none fire.
read_rules <- function(answer, text) {
  flat <- .squash(text)
  out <- list()
  fire <- function(rule, field, detail) out[[length(out) + 1]] <<- data.frame(rule = rule, field = field, detail = detail)
  ns <- function(x) is.null(x) || identical(x, "not_stated")
  coord_rows <- read_coordinate_rows(text)
  for (s in answer$surveys) {
    yrs <- expand_years(s$period$value)
    # Years in ranges need not be printed; only the end points must be.
    ends <- unique(unlist(lapply(strsplit(s$period$value, ";", fixed = TRUE)[[1]],
                                 function(p) strsplit(p, "-", fixed = TRUE)[[1]])))
    if (!ns(s$period$value)) for (y in ends) if (!grepl(y, flat, fixed = TRUE))
      fire("value_not_in_text", "period", y)
    items <- s$stations$items
    for (it in items) {
      for (k in c("x", "y", "vannlokalitetkode")) {
        v <- it[[k]]
        if (!ns(v) && !grepl(.squash(v), flat, fixed = TRUE)) fire("value_not_in_text", "stations", paste(k, v))
      }
    }
    if (identical(s$stations$status, "not_stated") &&
        (length(coord_rows) || grepl(DEC_COORD_RE, text, perl = TRUE)))
      fire("not_stated_vs_pages", "stations", "coordinates on the pages")
    if (ns(s$period$value) && grepl(SAMPLING_YEAR_RE, text, perl = TRUE))
      fire("not_stated_vs_pages", "period", "year next to a sampling word")
    if (identical(unlist(s$data_statement$value), "not_stated") && grepl(DATA_WORD_RE, text, perl = TRUE))
      fire("not_stated_vs_pages", "data_statement", "vedlegg/artsliste/Vannmiljø on the pages")
  }
  n_items <- sum(vapply(answer$surveys, function(s) length(s$stations$items), integer(1)))
  if (length(coord_rows) && n_items != length(coord_rows))
    fire("count_mismatch", "stations", sprintf("%d extracted, %d coordinate rows", n_items, length(coord_rows)))
  if (!length(out)) return(data.frame(rule = character(), field = character(), detail = character()))
  do.call(rbind, out)
}

#' Fields on which two readings differ after normalisation (repeated readings).
read_disagreement <- function(a, b) {
  key <- function(ans) vapply(ans$surveys, function(s) paste(
    s$period$value, tolower(s$institution$value), s$taxon_scope$value,
    paste(sort(unlist(s$data_statement$value)), collapse = ";"),
    length(s$stations$items), sep = "|"), "")
  ka <- sort(key(a)); kb <- sort(key(b))
  if (identical(ka, kb)) character() else "surveys"
}

# ---- scoring ----------------------------------------------------------------------

.norm <- function(x) trimws(gsub("\\s+", " ", tolower(x)))

#' Keys of a name: the text in parentheses and the text outside them.
name_keys <- function(x) {
  inside <- regmatches(x, gregexpr("\\(([^)]+)\\)", x))[[1]]
  inside <- gsub("[()]", "", inside)
  outside <- trimws(gsub("\\([^)]*\\)", "", x))
  k <- .norm(c(inside, outside))
  k[nchar(k) >= 3]
}

#' Score one field. Returns list(outcome, score): outcome is one of
#' correct, wrong, invented (key not_stated, answer gave a value),
#' missed (key has a value, answer not_stated), both_not_stated (correct).
score_field <- function(field, truth, answer) {
  t_ns <- identical(truth, "not_stated")
  a_ns <- identical(answer, "not_stated") || identical(answer, list("not_stated")) ||
    identical(unlist(answer), "not_stated")
  if (t_ns && a_ns) return(list(outcome = "both_not_stated", score = 1))
  if (t_ns) return(list(outcome = "invented", score = 0))
  if (a_ns) return(list(outcome = "missed", score = 0))
  s <- switch(field,
    period = as.numeric(setequal(expand_years(truth), expand_years(answer))),
    taxon_scope = as.numeric(identical(truth, answer)),
    data_statement = as.numeric(setequal(trimws(strsplit(truth, ";")[[1]]), unlist(answer))),
    institution = {
      parts <- trimws(strsplit(truth, ";")[[1]])
      a <- .norm(answer)
      mean(vapply(parts, function(p) any(vapply(name_keys(p), grepl, logical(1), x = a, fixed = TRUE)),
                  logical(1)))
    },
    region = {
      parts <- .norm(trimws(strsplit(truth, ";")[[1]]))
      a <- .norm(answer)
      mean(vapply(parts, grepl, logical(1), x = a, fixed = TRUE))
    },
    stop("Unknown field: ", field))
  list(outcome = if (s == 1) "correct" else "wrong", score = s)
}

.answer_value <- function(s, field) {
  v <- s[[field]]$value
  if (field == "data_statement") unlist(v) else v
}

#' Score one document's answer against its key rows (several surveys possible).
#' Each key survey is aligned to the answer survey with the highest summed
#' score. Returns one row per key row.
score_document <- function(answer, truth_doc) {
  rows <- list()
  for (sr in unique(truth_doc$survey_ref)) {
    t <- truth_doc[truth_doc$survey_ref == sr, ]
    cand <- lapply(answer$surveys, function(s) lapply(seq_len(nrow(t)), function(i)
      score_field(t$field[i], t$value[i], .answer_value(s, t$field[i]))))
    tot <- vapply(cand, function(cs) sum(vapply(cs, `[[`, 0, "score")), 0)
    best <- which.max(tot)
    cs <- cand[[best]]
    rows[[sr]] <- data.frame(survey_ref = sr, document = t$document, field = t$field,
                             truth = t$value, verified = t$verified,
                             answer = vapply(seq_len(nrow(t)), function(i)
                               paste(.answer_value(answer$surveys[[best]], t$field[i]), collapse = ";"), ""),
                             outcome = vapply(cs, `[[`, "", "outcome"),
                             score = vapply(cs, `[[`, 0, "score"),
                             aligned_survey = best)
  }
  do.call(rbind, rows)
}

#' Station precision and recall for one document. A extracted station matches a
#' key station when the vannlokalitetkode is equal, or when both give numeric
#' coordinates in the same units within `radius_m` (UTM metres compared
#' directly; decimal degrees by haversine). Coordinates are compared as printed:
#' the key keeps the document's own system.
score_stations <- function(answer, st_doc, radius_m = 50) {
  items <- unlist(lapply(answer$surveys, function(s) s$stations$items), recursive = FALSE)
  n_a <- length(items); n_t <- nrow(st_doc)
  if (!n_a || !n_t) return(data.frame(n_answer = n_a, n_truth = n_t, matched = 0L,
                                      precision = if (n_a) 0 else NA_real_,
                                      recall = if (n_t) 0 else NA_real_))
  num <- function(v) suppressWarnings(as.numeric(gsub(",", ".", gsub("\\s", "", v))))
  ok <- matrix(FALSE, n_a, n_t)
  for (i in seq_len(n_a)) {
    it <- items[[i]]
    ax <- num(it$x); ay <- num(it$y)
    for (j in seq_len(n_t)) {
      code <- st_doc$vannlokalitetkode[j]
      if (nzchar(code) && toupper(code) == toupper(it$vannlokalitetkode)) { ok[i, j] <- TRUE; next }
      tx <- num(st_doc$x[j]); ty <- num(st_doc$y[j])
      if (anyNA(c(ax, ay, tx, ty))) next
      d <- if (st_doc$crs[j] == "EPSG:4326") haversine_m(ax, ay, tx, ty) else sqrt((ax - tx)^2 + (ay - ty)^2)
      ok[i, j] <- d <= radius_m
    }
  }
  # Greedy one-to-one assignment.
  matched <- 0L
  while (any(ok)) {
    ij <- which(ok, arr.ind = TRUE)[1, ]
    matched <- matched + 1L
    ok[ij[1], ] <- FALSE
    ok[, ij[2]] <- FALSE
  }
  data.frame(n_answer = n_a, n_truth = n_t, matched = matched,
             precision = matched / n_a, recall = matched / n_t)
}
