# Gold-set and source status report (scripts/report_goldset.R).
#
# Pure functions: they read repository files and return data frames, plots or
# markdown. No network calls and no SQL; when the register is used, it goes
# through R/db.R. The report never reads the local full-text folder; the manifest is used
# only to count rows that have a local full text.

# ---- constants -------------------------------------------------------------------

# Fixed colour per expected_status, used in every figure. Okabe-Ito palette
# (colour-blind safe); the six real statuses pass a CVD separation check.
# Provisional and negative values are neutral greys.
STATUS_LEVELS <- c("in_gbif", "in_gbif_no_effort", "partly_in_gbif", "open_elsewhere",
                   "exists_not_available", "unidentified", "todo", "not_applicable")
STATUS_COLOURS <- c(in_gbif = "#009E73", in_gbif_no_effort = "#56B4E9",
                    partly_in_gbif = "#E69F00", open_elsewhere = "#0072B2",
                    exists_not_available = "#D55E00", unidentified = "#CC79A7",
                    todo = "#9E9E9E", not_applicable = "#D9D9D9")

# Statuses whose definition says the data are not in GBIF (docs/design.md,
# "Status categories"). Used only to set GBIF/Vannmiljø cells to "no".
STATUS_NOT_IN_GBIF <- c("open_elsewhere", "exists_not_available", "unidentified",
                        "not_applicable")

INSTITUTION_GROUPS <- c("NTNU", "NINA", "NIVA", "consultancy", "other")

# Consultancies seen in the gold set and in Vannmiljø, plus legal-form tokens
# (Norwegian/Swedish AS/AB) that mark a company.
CONSULTANCY_PATTERN <- paste0("\\b(Multiconsult|Ramb(ø|o)ll|Sweco|Norconsult|COWI|Asplan|",
                              "Ecofact|Faun|Pelagia|AS|AB)\\b")

# Source-matrix columns: id -> label. The first five are "sources" (used for
# coverage and overlap); no_document is a property of the row.
EVIDENCE_COLUMNS <- c(gbif_dataset = "GBIF dataset", vannmiljo = "Vannmiljø (via GBIF)",
                      nva = "NVA id", doi_handle = "DOI / handle",
                      citation_only = "Report citation only", no_document = "No document")
SOURCE_COLUMNS <- setdiff(names(EVIDENCE_COLUMNS), "no_document")
EVIDENCE_VALUES <- c("yes", "no", "unknown")

# found_via value -> pipeline source (scope.yaml `sources`). Recall for a source
# is measured only on rows not found via that source (docs/design.md, "Gold set").
FOUND_VIA_SOURCE <- c(gbif_baseline = "gbif", nva_targeted = "nva", nva_search = "nva")

BENCHMARK_COLUMNS <- c("source", "run", "n_eligible", "n_found", "recall",
                       "n_screened", "precision")

# ---- file helpers ----------------------------------------------------------------

#' Latest file in `dir` matching `pattern`. Names end in an ISO date, so the
#' lexical maximum is the newest. Errors if nothing matches.
latest_file <- function(dir, pattern) {
  f <- sort(list.files(dir, pattern = pattern, full.names = TRUE))
  if (!length(f)) stop("No file matching '", pattern, "' in ", dir, call. = FALSE)
  f[length(f)]
}

read_tsv_chr <- function(path) {
  readr::read_tsv(path, col_types = readr::cols(.default = readr::col_character()),
                  na = character(), locale = readr::locale(encoding = "UTF-8"),
                  progress = FALSE)
}

short_sha256 <- function(path, n = 12) substr(digest::digest(file = path, algo = "sha256"), 1, n)

#' Last commit touching `paths`, and whether any of them has uncommitted changes.
#' Uses only the local git repository.
git_input_state <- function(paths) {
  args <- c("log", "-1", shQuote("--format=%h|%cs"), "--", shQuote(paths))
  out <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = FALSE))
  if (!length(out) || !nzchar(out[1])) stop("git log found no commit for the report inputs")
  parts <- strsplit(out[1], "|", fixed = TRUE)[[1]]
  dirty <- suppressWarnings(system2("git", c("status", "--porcelain", "--", shQuote(paths)),
                                    stdout = TRUE, stderr = FALSE))
  list(commit = parts[1], date = parts[2], dirty = length(dirty) > 0)
}

#' GBIF dataset keys of aggregator knowledge cards, named by card id.
aggregator_dataset_keys <- function(files = list_knowledge_files()) {
  cards <- lapply(files, read_knowledge_card)
  cards <- Filter(function(c) identical(c$front$type, "aggregator") &&
                    !is.null(c$front$gbif_dataset), cards)
  stats::setNames(vapply(cards, function(c) c$front$gbif_dataset, ""),
                  vapply(cards, function(c) c$front$id, ""))
}

#' Number of gold-set rows that have at least one local full text, from the
#' manifest only (the full-text folder itself is never read).
fulltext_row_count <- function(manifest, survey_refs) {
  refs <- trimws(unlist(strsplit(manifest$survey_ref, ";", fixed = TRUE)))
  sum(survey_refs %in% refs)
}

# ---- markdown helpers ------------------------------------------------------------

md_escape <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- gsub("|", "\\|", x, fixed = TRUE)
  gsub("[\r\n]+", " ", x)
}

#' Markdown pipe table. `align` is a vector of "l"/"r"/"c", recycled.
md_table <- function(df, align = NULL) {
  if (!nrow(df)) return("_(no rows)_")
  if (is.null(align)) align <- ifelse(vapply(df, is.numeric, logical(1)), "r", "l")
  align <- rep_len(align, ncol(df))
  rule <- c(l = ":---", r = "---:", c = ":---:")[align]
  body <- apply(as.data.frame(lapply(df, md_escape)), 1, paste, collapse = " | ")
  paste(c(paste0("| ", paste(md_escape(names(df)), collapse = " | "), " |"),
          paste0("| ", paste(rule, collapse = " | "), " |"),
          paste0("| ", body, " |")), collapse = "\n")
}

truncate_text <- function(x, n = 100) {
  x <- gsub("\\s+", " ", trimws(x))
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "…"), x)
}

fmt_int <- function(x) formatC(x, format = "d", big.mark = ",")

# ---- institution groups ----------------------------------------------------------

#' Group an institution string. Rule: drop "(oppdragsgiver …)" (the client is
#' not the institution), then take the first match in the order NTNU, NINA,
#' NIVA, consultancy (CONSULTANCY_PATTERN), other.
institution_group <- function(x) {
  y <- gsub("\\(\\s*oppdragsgiver[^)]*\\)", "", x, ignore.case = TRUE)
  out <- rep("other", length(y))
  rules <- list(NTNU = "\\bNTNU\\b", NINA = "\\bNINA\\b", NIVA = "\\bNIVA\\b",
                consultancy = CONSULTANCY_PATTERN)
  for (g in rev(names(rules))) out[grepl(rules[[g]], y, perl = TRUE)] <- g
  factor(out, levels = INSTITUTION_GROUPS)
}

# ---- period parsing --------------------------------------------------------------

#' Parse gold-set `period` strings into intervals.
#'
#' Rules: the string is split on ";"; each part is a year ("2009"), a range
#' ("1982–1986", en dash, em dash or hyphen, start <= end), optionally followed
#' by "?" which marks the interval as uncertain. A "?" also makes the part
#' uncertain when it stands before the year ("?2009"). Anything else, or a range
#' with start > end, is returned with ok = FALSE and NA years; the caller must
#' list those rows.
#'
#' Returns one row per interval: id, part, start, end, uncertain, ok, raw.
parse_period <- function(period, id = seq_along(period)) {
  rows <- lapply(seq_along(period), function(i) {
    raw <- if (is.na(period[i])) "" else period[i]
    parts <- trimws(strsplit(raw, ";", fixed = TRUE)[[1]])
    if (!length(parts)) parts <- ""
    do.call(rbind, lapply(seq_along(parts), function(k) {
      p <- parts[k]
      uncertain <- grepl("?", p, fixed = TRUE)
      core <- trimws(gsub("?", "", p, fixed = TRUE))
      start <- end <- NA_integer_
      if (grepl("^[0-9]{4}$", core)) {
        start <- end <- as.integer(core)
      } else if (grepl("^[0-9]{4}\\s*[-–—]\\s*[0-9]{4}$", core)) {
        yy <- as.integer(regmatches(core, gregexpr("[0-9]{4}", core))[[1]])
        if (yy[1] <= yy[2]) { start <- yy[1]; end <- yy[2] }
      }
      ok <- !is.na(start)
      data.frame(id = id[i], part = k, start = start, end = end,
                 uncertain = ok & uncertain, ok = ok, raw = raw, stringsAsFactors = FALSE)
    }))
  })
  do.call(rbind, rows)
}

# ---- source-matrix rules -----------------------------------------------------------
# Each rule takes gold-set columns (vectors) and returns "yes"/"no"/"unknown".
# A cell is "yes" only on a recorded identifier or an exact match; "no" only
# where the gold set itself asserts absence; everything else is "unknown".

UUID_RE <- "(?<![0-9a-f-])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f-])"
KEY_PREFIX_RE <- "(?<![0-9a-f-])[0-9a-f]{8}(?![0-9a-f-])"
VANNLOKALITET_RE <- "\\b[0-9]{3}-[0-9]+-[RLrl]\\b"

#' GBIF dataset keys cited in free text: full UUIDs, plus 8-hex prefixes that
#' resolve to exactly one of `known_keys`. Returns list(keys, unresolved).
extract_dataset_keys <- function(text, known_keys) {
  text <- tolower(ifelse(is.na(text), "", text))
  lapply(text, function(t) {
    full <- regmatches(t, gregexpr(UUID_RE, t, perl = TRUE))[[1]]
    rest <- gsub(UUID_RE, " ", t, perl = TRUE)
    pre <- unique(regmatches(rest, gregexpr(KEY_PREFIX_RE, rest, perl = TRUE))[[1]])
    hit <- lapply(pre, function(p) known_keys[startsWith(known_keys, p)])
    resolved <- unlist(hit[lengths(hit) == 1])
    list(keys = unique(c(full, resolved)), unresolved = pre[lengths(hit) != 1])
  })
}

# Combine evidence with the gold set's claim. Evidence for GBIF on a row whose
# status says "not in GBIF" is a conflict: the cell cannot be decided, so it is
# "unknown" and attr(, "conflict") marks the row for the Flags table.
.no_if_status <- function(yes, expected_status) {
  says_no <- expected_status %in% STATUS_NOT_IN_GBIF
  out <- ifelse(yes & !says_no, "yes", ifelse(says_no & !yes, "no", "unknown"))
  structure(out, conflict = yes & says_no)
}

#' Rule: GBIF dataset (not an aggregator). "yes" if where_data_are cites a
#' non-aggregator datasetKey, or quotes datasetName "…" equal to a datasetName
#' of a non-aggregator group in gbif_survey_groups; "no" if expected_status says
#' the data are not in GBIF; "unknown" otherwise, including when both hold.
rule_gbif_dataset <- function(where_data_are, expected_status, known_keys,
                              aggregator_keys, group_dataset_names) {
  keys <- extract_dataset_keys(where_data_are, known_keys)
  by_key <- vapply(keys, function(k) any(!k$keys %in% aggregator_keys), logical(1))
  quoted <- regmatches(where_data_are,
                       gregexpr('datasetName\\s+"([^"]+)"', where_data_are, perl = TRUE))
  names_cited <- lapply(quoted, function(q) sub('^datasetName\\s+"([^"]+)"$', "\\1", q))
  by_name <- vapply(names_cited, function(n) any(n %in% group_dataset_names), logical(1))
  .no_if_status(by_key | by_name, expected_status)
}

#' Rule: Vannmiljø via GBIF. "yes" if where_data_are cites the aggregator's
#' datasetKey, or cites a vannlokalitetkode that occurs in an aggregator group
#' (gbif_survey_groups) in a year inside the row's parsed period; "no" if
#' expected_status says the data are not in GBIF; "unknown" otherwise,
#' including when both hold (a conflict, listed under Flags).
rule_vannmiljo <- function(where_data_are, expected_status, period, known_keys,
                           aggregator_key, aggregator_groups) {
  keys <- extract_dataset_keys(where_data_are, known_keys)
  by_key <- vapply(keys, function(k) aggregator_key %in% k$keys, logical(1))
  codes <- lapply(toupper(where_data_are), function(t)
    unique(regmatches(t, gregexpr(VANNLOKALITET_RE, t, perl = TRUE))[[1]]))
  iv <- parse_period(period)
  by_code <- vapply(seq_along(where_data_are), function(i) {
    if (!length(codes[[i]]) || !nrow(aggregator_groups)) return(FALSE)
    p <- iv[iv$id == i & iv$ok, ]
    if (!nrow(p)) return(FALSE)
    yr <- as.integer(aggregator_groups$year)
    in_period <- vapply(yr, function(y) any(y >= p$start & y <= p$end), logical(1))
    g_codes <- toupper(regmatches(aggregator_groups$waterbodies,
                                  gregexpr(VANNLOKALITET_RE, aggregator_groups$waterbodies,
                                           perl = TRUE)))
    any(in_period & vapply(g_codes, function(gc) any(gc %in% codes[[i]]), logical(1)))
  }, logical(1))
  .no_if_status(by_key | by_code, expected_status)
}

NVA_RE <- "\\bnva:[0-9a-f]{12}-[0-9a-f-]+"
DOI_RE <- "(\\bdoi:\\s*|doi\\.org/|\\b)10\\.[0-9]{4,9}/[^\\s;,)]+"
HANDLE_RE <- "\\b(hdl|handle):\\s*[^\\s;,)]+|hdl\\.handle\\.net/"

#' Rule: NVA id. "yes" if documents contains "nva:<id>"; else "unknown"
#' (a missing id does not show the report is absent from NVA).
rule_nva <- function(documents) {
  ifelse(grepl(NVA_RE, documents, ignore.case = TRUE, perl = TRUE), "yes", "unknown")
}

#' Rule: DOI or handle. "yes" if documents contains a DOI (10.xxxx/…) or a
#' handle written as hdl:/handle:/hdl.handle.net; else "unknown".
rule_doi_handle <- function(documents) {
  hit <- grepl(DOI_RE, documents, ignore.case = TRUE, perl = TRUE) |
    grepl(HANDLE_RE, documents, ignore.case = TRUE, perl = TRUE)
  ifelse(hit, "yes", "unknown")
}

#' Rule: report citation only. Decidable from the field: "yes" if documents is
#' non-empty and has no NVA id, DOI or handle (an ISBN is not a repository id);
#' "no" otherwise.
rule_citation_only <- function(documents) {
  d <- trimws(ifelse(is.na(documents), "", documents))
  has_id <- rule_nva(d) == "yes" | rule_doi_handle(d) == "yes"
  ifelse(nzchar(d) & !has_id, "yes", "no")
}

#' Rule: no document. "yes" if documents is empty, "no" otherwise.
rule_no_document <- function(documents) {
  d <- trimws(ifelse(is.na(documents), "", documents))
  ifelse(nzchar(d), "no", "yes")
}

#' Survey × evidence matrix (wide): survey_ref, expected_status, include and one
#' column per EVIDENCE_COLUMNS id.
source_matrix <- function(gs, known_keys, aggregator_keys, groups) {
  agg_ids <- names(aggregator_keys)
  vm_id <- "vannmiljo"
  if (!vm_id %in% agg_ids) stop("No aggregator knowledge card with id 'vannmiljo' and a gbif_dataset")
  non_agg_names <- unique(groups$datasetName[!groups$source %in% agg_ids & nzchar(groups$datasetName)])
  vm_groups <- groups[groups$source == vm_id, , drop = FALSE]
  gb <- rule_gbif_dataset(gs$where_data_are, gs$expected_status, known_keys,
                          unname(aggregator_keys), non_agg_names)
  vm <- rule_vannmiljo(gs$where_data_are, gs$expected_status, gs$period, known_keys,
                       unname(aggregator_keys[vm_id]), vm_groups)
  out <- data.frame(
    survey_ref = gs$survey_ref, expected_status = gs$expected_status, include = gs$include,
    gbif_dataset = as.vector(gb), vannmiljo = as.vector(vm),
    nva = rule_nva(gs$documents),
    doi_handle = rule_doi_handle(gs$documents),
    citation_only = rule_citation_only(gs$documents),
    no_document = rule_no_document(gs$documents),
    stringsAsFactors = FALSE)
  attr(out, "conflict") <- attr(gb, "conflict") | attr(vm, "conflict")
  out
}

#' Per source: rows covered ("yes") and rows covered only by that source.
source_coverage <- function(m, cols = SOURCE_COLUMNS) {
  yes <- as.matrix(m[cols]) == "yes"
  data.frame(source = unname(EVIDENCE_COLUMNS[cols]),
             n_rows = colSums(yes),
             n_only_this = colSums(yes & rowSums(yes) == 1),
             n_unknown = colSums(as.matrix(m[cols]) == "unknown"),
             row.names = NULL, check.names = FALSE)
}

#' Rows per combination of sources with "yes" (UpSet-style), largest first.
source_combinations <- function(m, cols = SOURCE_COLUMNS) {
  yes <- as.matrix(m[cols]) == "yes"
  key <- apply(yes, 1, function(r) paste(cols[r], collapse = "+"))
  key[key == ""] <- "(none)"
  tab <- table(key)
  out <- data.frame(combination = names(tab), n = as.integer(tab), stringsAsFactors = FALSE)
  out[order(-out$n, out$combination), , drop = FALSE]
}

#' Rows where the evidence contradicts expected_status, or where the gold set
#' says GBIF but no GBIF evidence could be resolved.
matrix_flags <- function(m) {
  in_gbif_status <- m$expected_status %in% c("in_gbif", "in_gbif_no_effort", "partly_in_gbif")
  any_gbif <- m$gbif_dataset == "yes" | m$vannmiljo == "yes"
  conflict <- attr(m, "conflict") %||% rep(FALSE, nrow(m))
  rbind(
    data.frame(survey_ref = m$survey_ref[in_gbif_status & !any_gbif],
               flag = "status says GBIF; no datasetKey or survey-group match in where_data_are"),
    data.frame(survey_ref = m$survey_ref[conflict],
               flag = "status says not in GBIF, but where_data_are matches GBIF evidence; cell set to unknown")
  )
}

#' Short summary of the matrix, generated from the numbers.
matrix_summary_text <- function(m, coverage, flags) {
  n <- nrow(m)
  none <- sum(rowSums(as.matrix(m[SOURCE_COLUMNS]) == "yes") == 0)
  unknown <- sum(as.matrix(m[SOURCE_COLUMNS]) == "unknown")
  top <- coverage[order(-coverage$n_rows, coverage$source), ][1, ]
  only <- coverage[coverage$n_only_this > 0, ]
  only_txt <- if (nrow(only)) paste(sprintf("%s (%d)", only$source, only$n_only_this),
                                    collapse = ", ") else "none"
  c(sprintf("- %d gold-set rows; %d of %d source cells are `unknown`.",
            n, unknown, n * length(SOURCE_COLUMNS)),
    sprintf("- The source covering most rows is %s (%d of %d).", top$source, top$n_rows, n),
    sprintf("- Rows covered by exactly one source: %s.", only_txt),
    sprintf("- %d rows have no source marked `yes`.", none),
    sprintf("- %d rows have no document at all; %d rows cite a report without a repository id.",
            sum(m$no_document == "yes"), sum(m$citation_only == "yes")),
    sprintf("- %d rows are flagged below (status and evidence disagree, or a GBIF status lacks a resolvable datasetKey).",
            length(unique(flags$survey_ref))))
}

# ---- benchmarks ------------------------------------------------------------------

#' Recall and precision per source and run.
#'
#' `runs`: data.frame(source, run). `hits`: data.frame(source, run, survey_ref),
#' the gold-set rows a run retrieved. `samples`: data.frame(source, run,
#' n_screened, n_relevant), a hand-checked sample of the run's output.
#' Eligible rows: include in `include_levels`, expected_status not
#' not_applicable, and found_via not mapped to the run's source.
benchmark_recall <- function(gs, runs, hits, samples, found_via_source = FOUND_VIA_SOURCE,
                             include_levels = "yes") {
  empty <- stats::setNames(data.frame(matrix(nrow = 0, ncol = length(BENCHMARK_COLUMNS))),
                           BENCHMARK_COLUMNS)
  if (!nrow(runs)) return(empty)
  base <- gs$include %in% include_levels & gs$expected_status != "not_applicable"
  src_of_row <- unname(found_via_source[gs$found_via])
  rows <- lapply(seq_len(nrow(runs)), function(i) {
    s <- runs$source[i]; r <- runs$run[i]
    eligible <- gs$survey_ref[base & (is.na(src_of_row) | src_of_row != s)]
    got <- hits$survey_ref[hits$source == s & hits$run == r]
    n_found <- sum(eligible %in% got)
    smp <- samples[samples$source == s & samples$run == r, , drop = FALSE]
    n_scr <- if (nrow(smp)) sum(smp$n_screened) else NA_integer_
    n_rel <- if (nrow(smp)) sum(smp$n_relevant) else NA_integer_
    data.frame(source = s, run = r, n_eligible = length(eligible), n_found = n_found,
               recall = if (length(eligible)) n_found / length(eligible) else NA_real_,
               n_screened = n_scr,
               precision = if (!is.na(n_scr) && n_scr > 0) n_rel / n_scr else NA_real_,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' Eligible rows per source if a run happened today, for each include level set.
benchmark_eligible <- function(gs, sources, found_via_source = FOUND_VIA_SOURCE) {
  src_of_row <- unname(found_via_source[gs$found_via])
  ok <- gs$expected_status != "not_applicable"
  data.frame(source = sources,
             `include = yes` = vapply(sources, function(s)
               sum(ok & gs$include == "yes" & (is.na(src_of_row) | src_of_row != s)), 1L),
             `include = yes or candidate` = vapply(sources, function(s)
               sum(ok & gs$include %in% c("yes", "candidate") &
                     (is.na(src_of_row) | src_of_row != s)), 1L),
             check.names = FALSE, row.names = NULL)
}

# ---- GBIF year facets ------------------------------------------------------------

#' Records per year per dataset for the scope, from the year facets logged in
#' logs/queries.jsonl (latest query per dataset × taxon). Raw responses live in
#' data/raw/ (local only). Returns NULL with attr "missing" if any raw file is
#' absent.
gbif_year_counts <- function(log_path, scope, dataset_keys) {
  lines <- readLines(log_path, warn = FALSE, encoding = "UTF-8")
  q <- lapply(lines, jsonlite::fromJSON)
  taxa <- vapply(scope$taxa$gbif_taxon_keys, function(t) as.integer(t$key), 1L)
  pick <- Filter(function(e) identical(e$args$facet, "year") &&
                   identical(e$args$gadmGid, scope$region$gadm_gid) &&
                   !is.null(e$args$datasetKey) && e$args$datasetKey %in% dataset_keys &&
                   as.integer(e$args$taxonKey) %in% taxa, q)
  if (!length(pick)) stop("No year-facet queries in ", log_path, " for the requested datasets")
  idx <- data.frame(ds = vapply(pick, function(e) e$args$datasetKey, ""),
                    taxon = vapply(pick, function(e) as.integer(e$args$taxonKey), 1L),
                    ts = vapply(pick, function(e) e$timestamp, ""),
                    file = vapply(pick, function(e) e$raw_file, ""),
                    n_expected = vapply(pick, function(e) as.integer(e$n_expected), 1L))
  idx <- idx[order(idx$ds, idx$taxon, idx$ts, idx$file), ]
  idx <- idx[!duplicated(idx[c("ds", "taxon")], fromLast = TRUE), ]
  missing_combos <- setdiff(as.vector(outer(dataset_keys, taxa, paste)), paste(idx$ds, idx$taxon))
  if (length(missing_combos)) stop("Year facets missing for: ", paste(missing_combos, collapse = ", "))
  absent <- idx$file[!file.exists(idx$file)]
  if (length(absent)) return(structure(NULL, missing = absent))
  rows <- lapply(seq_len(nrow(idx)), function(i) {
    js <- jsonlite::fromJSON(idx$file[i])
    yr <- js$facets$year
    if (!identical(as.integer(js$meta$count), idx$n_expected[i]))
      stop("Count in ", idx$file[i], " differs from the query log")
    if (is.null(yr) || !length(yr)) return(NULL)
    data.frame(datasetKey = idx$ds[i], year = as.integer(yr$name), n = as.integer(yr$count))
  })
  out <- do.call(rbind, rows)
  out <- stats::aggregate(n ~ datasetKey + year, data = out, FUN = sum)
  out[order(out$datasetKey, out$year), ]
}

# ---- plots -----------------------------------------------------------------------

report_theme <- function() {
  ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                   panel.grid.major = ggplot2::element_line(colour = "#E6E6E6", linewidth = 0.3),
                   axis.text = ggplot2::element_text(colour = "#444444"),
                   legend.position = "bottom",
                   plot.title.position = "plot",
                   plot.background = ggplot2::element_rect(fill = "white", colour = NA))
}

status_scale <- function(aes = "fill", present = STATUS_LEVELS) {
  f <- if (aes == "fill") ggplot2::scale_fill_manual else ggplot2::scale_colour_manual
  f(values = STATUS_COLOURS, breaks = intersect(STATUS_LEVELS, present), drop = TRUE,
    name = "expected_status")
}

#' Save a plot as PNG at 2x (192 dpi). Cairo, white background; deterministic
#' for identical input.
save_png <- function(plot, path, width = 8, height = 5) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  grDevices::png(path, width = width, height = height, units = "in", res = 192,
                 type = "cairo", bg = "white")
  on.exit(grDevices::dev.off())
  if (inherits(plot, "gtable")) { grid::grid.newpage(); grid::grid.draw(plot) } else print(plot)
  invisible(path)
}

plot_status_by_found_via <- function(gs) {
  d <- as.data.frame(table(found_via = gs$found_via,
                           expected_status = factor(gs$expected_status, levels = STATUS_LEVELS)))
  d <- d[d$Freq > 0, ]
  ggplot2::ggplot(d, ggplot2::aes(x = found_via, y = Freq, fill = expected_status)) +
    ggplot2::geom_col(width = 0.65, colour = "white", linewidth = 0.5) +
    status_scale("fill", unique(as.character(d$expected_status))) +
    ggplot2::labs(x = "found_via", y = "Gold-set rows") +
    report_theme()
}

plot_timeline <- function(gs, iv) {
  d <- iv[iv$ok, ]
  d$survey_ref <- gs$survey_ref[d$id]
  d$status <- factor(gs$expected_status[d$id], levels = STATUS_LEVELS)
  d$group <- institution_group(gs$institution)[d$id]
  first <- stats::aggregate(start ~ survey_ref, data = d, FUN = min)
  lev <- first$survey_ref[order(-first$start, first$survey_ref)]
  d$survey_ref <- factor(d$survey_ref, levels = lev)
  # A year y spans [y, y + 1), so single years are visible.
  d$mid <- (d$start + d$end + 1) / 2
  d$len <- d$end + 1 - d$start
  ggplot2::ggplot(d, ggplot2::aes(x = mid, y = survey_ref, width = len)) +
    ggplot2::geom_tile(data = d[!d$uncertain, ], ggplot2::aes(fill = status),
                       height = 0.7, colour = NA) +
    ggplot2::geom_tile(data = d[d$uncertain, ], ggplot2::aes(colour = status),
                       height = 0.7, fill = NA, linetype = "22", linewidth = 0.6) +
    status_scale("fill", unique(as.character(d$status))) +
    status_scale("colour", unique(as.character(d$status[d$uncertain]))) +
    ggplot2::facet_grid(rows = ggplot2::vars(group), scales = "free_y", space = "free_y") +
    ggplot2::guides(colour = ggplot2::guide_legend(title = "uncertain period (dashed outline)")) +
    ggplot2::labs(x = "Year", y = NULL) +
    report_theme() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(size = 7),
                   strip.text.y = ggplot2::element_text(angle = 0, hjust = 0, face = "bold"),
                   legend.box = "vertical")
}

plot_source_matrix <- function(m) {
  ord <- order(factor(m$expected_status, levels = STATUS_LEVELS), m$survey_ref, decreasing = FALSE)
  lev <- rev(m$survey_ref[ord])
  cols <- names(EVIDENCE_COLUMNS)
  long <- data.frame(survey_ref = rep(m$survey_ref, length(cols)),
                     column = rep(unname(EVIDENCE_COLUMNS[cols]), each = nrow(m)),
                     value = unlist(m[cols], use.names = FALSE))
  strip <- data.frame(survey_ref = m$survey_ref, column = "expected_status",
                      value = m$expected_status)
  d <- rbind(strip, long)
  d$survey_ref <- factor(d$survey_ref, levels = lev)
  d$column <- factor(d$column, levels = c("expected_status", unname(EVIDENCE_COLUMNS[cols])))
  fills <- c(yes = "#2B2B2B", no = "#FFFFFF", unknown = "#BDBDBD", STATUS_COLOURS)
  present <- unique(d$value)
  ggplot2::ggplot(d, ggplot2::aes(x = column, y = survey_ref, fill = value)) +
    ggplot2::geom_tile(colour = "#9E9E9E", linewidth = 0.25, width = 0.92, height = 0.85) +
    ggplot2::geom_text(data = d[d$value == "unknown", ], label = "?", size = 2.4,
                       colour = "#444444") +
    ggplot2::scale_fill_manual(values = fills,
                               breaks = c(intersect(EVIDENCE_VALUES, present),
                                          intersect(STATUS_LEVELS, present)),
                               name = NULL) +
    ggplot2::scale_x_discrete(position = "top",
                              labels = function(x) vapply(x, function(l)
                                paste(strwrap(l, 11), collapse = "\n"), "")) +
    ggplot2::labs(x = NULL, y = NULL) +
    report_theme() +
    ggplot2::theme(panel.grid.major = ggplot2::element_blank(),
                   axis.text.x.top = ggplot2::element_text(size = 8, vjust = 0),
                   axis.text.y = ggplot2::element_text(size = 7))
}

#' UpSet-like figure: bars of rows per source combination over a dot matrix.
plot_source_overlap <- function(m, cols = SOURCE_COLUMNS) {
  comb <- source_combinations(m, cols)
  comb$x <- factor(comb$combination, levels = comb$combination)
  bars <- ggplot2::ggplot(comb, ggplot2::aes(x = x, y = n)) +
    ggplot2::geom_col(width = 0.6, fill = "#4D4D4D") +
    ggplot2::geom_text(ggplot2::aes(label = n), vjust = -0.4, size = 3, colour = "#333333") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(x = NULL, y = "Gold-set rows") +
    report_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_blank(),
                   panel.grid.major.x = ggplot2::element_blank())
  dots <- expand.grid(combination = comb$combination, set = cols, stringsAsFactors = FALSE)
  dots$on <- mapply(function(cmb, s) s %in% strsplit(cmb, "+", fixed = TRUE)[[1]],
                    dots$combination, dots$set)
  dots$x <- factor(dots$combination, levels = comb$combination)
  dots$set <- factor(unname(EVIDENCE_COLUMNS[dots$set]), levels = rev(unname(EVIDENCE_COLUMNS[cols])))
  lines <- dots[dots$on, ]
  matrix_plot <- ggplot2::ggplot(dots, ggplot2::aes(x = x, y = set)) +
    ggplot2::geom_point(ggplot2::aes(colour = on), size = 3) +
    ggplot2::geom_line(data = lines, ggplot2::aes(group = x), colour = "#2B2B2B", linewidth = 0.6) +
    ggplot2::scale_colour_manual(values = c(`TRUE` = "#2B2B2B", `FALSE` = "#E0E0E0"), guide = "none") +
    ggplot2::labs(x = NULL, y = NULL) +
    report_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_blank(),
                   panel.grid.major = ggplot2::element_blank())
  g1 <- ggplot2::ggplotGrob(bars)
  g2 <- ggplot2::ggplotGrob(matrix_plot)
  g <- rbind(g1, g2, size = "max")  # gtable method
  panels <- g$layout$t[grepl("^panel", g$layout$name)]
  g$heights[panels] <- grid::unit(c(3, 1.6), "null")
  g
}

plot_gbif_datasets <- function(baseline) {
  d <- data.frame(title = baseline$title, n = as.numeric(baseline$n))
  d$title <- factor(d$title, levels = d$title[order(d$n, d$title)])
  ggplot2::ggplot(d, ggplot2::aes(x = n, y = title)) +
    ggplot2::geom_segment(ggplot2::aes(x = 1, xend = n, yend = title), colour = "#BDBDBD",
                          linewidth = 0.5) +
    ggplot2::geom_point(size = 2.6, colour = "#0072B2") +
    ggplot2::geom_text(ggplot2::aes(x = n * 1.5, label = fmt_int(n)), hjust = 0, size = 2.8,
                       colour = "#333333") +
    ggplot2::scale_x_log10(labels = scales::label_comma(),
                           limits = c(0.7, max(d$n) * 6), expand = c(0, 0)) +
    ggplot2::scale_y_discrete(labels = function(x) truncate_text(x, 60)) +
    ggplot2::labs(x = "Records (log scale)", y = NULL) +
    report_theme()
}

plot_gbif_years <- function(years, titles) {
  d <- years
  d$title <- factor(truncate_text(titles[d$datasetKey], 100),
                    levels = truncate_text(titles, 100))
  ggplot2::ggplot(d, ggplot2::aes(x = year, y = n)) +
    ggplot2::geom_col(width = 0.8, fill = "#0072B2") +
    ggplot2::facet_wrap(ggplot2::vars(title), ncol = 1, scales = "free_y") +
    ggplot2::scale_y_continuous(labels = scales::label_comma(),
                                expand = ggplot2::expansion(mult = c(0, 0.08))) +
    ggplot2::labs(x = "Year", y = "Records") +
    report_theme() +
    ggplot2::theme(strip.text = ggplot2::element_text(hjust = 0, face = "bold"))
}
