# Matching gold-set surveys against the scope's GBIF records (verb `match`).
# Rule-based and readable on purpose: every survey gets one value and one source
# per evidence dimension, a score, and one of three bands. Thresholds and
# weights come from config/match.yaml. Inputs from the gold set are only what a
# reader could extract from the documents: period, stations (goldset/stations.csv),
# region, institution, title, documents and doc_ids. `where_data_are`,
# `gbif_dataset_keys`, `expected_status` and `notes` are the answer key and are
# used only to score the result.

MATCH_CONFIG_FILE <- "config/match.yaml"
STATIONS_FILE <- "goldset/stations.csv"
STATIONS_COLUMNS <- c("survey_ref", "years", "station", "waterbody", "locality",
                      "vannlokalitetkode", "former_municipality", "crs", "x", "y",
                      "date", "document", "page", "verified", "note")
STATIONS_CRS <- c("EPSG:25832", "EPSG:4326")
BANDS <- c("likely_in_gbif", "uncertain", "likely_not_in_gbif")
STATUS_NOT_PUBLISHED <- c("open_elsewhere", "exists_not_available")
MATCH_INPUT_COLUMNS <- c("survey_ref", "title", "institution", "region", "period",
                         "documents", "doc_ids")
EVIDENCE_DIMS <- c("place_time", "institution", "dataset_name", "direct_link")

read_match_config <- function(path = MATCH_CONFIG_FILE) yaml::read_yaml(path)

# ---- stations ---------------------------------------------------------------------

read_stations <- function(path = STATIONS_FILE) {
  readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                  na = character(), progress = FALSE)
}

#' Problems in stations.csv as a data.frame(row, survey_ref, problem).
validate_stations <- function(st, survey_refs) {
  probs <- list()
  add <- function(i, msg) probs[[length(probs) + 1]] <<- data.frame(
    row = i, survey_ref = if (i > 0) st$survey_ref[i] else "", problem = msg)
  if (!identical(names(st), STATIONS_COLUMNS)) {
    add(0, paste("header must be:", paste(STATIONS_COLUMNS, collapse = ",")))
    return(do.call(rbind, probs))
  }
  for (i in seq_len(nrow(st))) {
    r <- st[i, ]
    if (!r$survey_ref %in% survey_refs) add(i, "survey_ref not in goldset.csv")
    if (!all(parse_period(r$years)$ok)) add(i, sprintf("years '%s' does not parse", r$years))
    if (!nzchar(r$station)) add(i, "station is empty")
    if (nzchar(r$crs) && !r$crs %in% STATIONS_CRS) add(i, sprintf("crs '%s' not supported", r$crs))
    has_xy <- nzchar(r$x) || nzchar(r$y)
    if (has_xy && (!nzchar(r$crs) || is.na(suppressWarnings(as.numeric(r$x))) ||
                   is.na(suppressWarnings(as.numeric(r$y)))))
      add(i, "x/y need a crs and numeric values")
    if (nzchar(r$crs) && !has_xy) add(i, "crs given without x/y")
    if (nzchar(r$vannlokalitetkode) && !grepl("^[0-9]{3}-[0-9]+-[A-Z]$", r$vannlokalitetkode))
      add(i, "vannlokalitetkode must look like 123-45-R")
    if (!r$verified %in% c("yes", "no")) add(i, "verified must be yes or no")
  }
  if (!length(probs)) return(data.frame(row = integer(), survey_ref = character(),
                                        problem = character()))
  do.call(rbind, probs)
}

#' Inverse transverse Mercator (UTM, northern hemisphere, GRS80 ≈ WGS84 at
#' metre level). Standard series (Snyder 1987, eq. 8-17 ff.).
utm_to_lonlat <- function(x, y, zone = 32, a = 6378137, f = 1 / 298.257222101) {
  k0 <- 0.9996
  e2 <- f * (2 - f)
  ep2 <- e2 / (1 - e2)
  x <- x - 500000
  mu <- (y / k0) / (a * (1 - e2 / 4 - 3 * e2^2 / 64 - 5 * e2^3 / 256))
  e1 <- (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))
  phi1 <- mu + (3 * e1 / 2 - 27 * e1^3 / 32) * sin(2 * mu) +
    (21 * e1^2 / 16 - 55 * e1^4 / 32) * sin(4 * mu) +
    (151 * e1^3 / 96) * sin(6 * mu) + (1097 * e1^4 / 512) * sin(8 * mu)
  n1 <- a / sqrt(1 - e2 * sin(phi1)^2)
  t1 <- tan(phi1)^2
  c1 <- ep2 * cos(phi1)^2
  r1 <- a * (1 - e2) / (1 - e2 * sin(phi1)^2)^1.5
  d <- x / (n1 * k0)
  lat <- phi1 - (n1 * tan(phi1) / r1) *
    (d^2 / 2 - (5 + 3 * t1 + 10 * c1 - 4 * c1^2 - 9 * ep2) * d^4 / 24 +
       (61 + 90 * t1 + 298 * c1 + 45 * t1^2 - 252 * ep2 - 3 * c1^2) * d^6 / 720)
  lon <- (zone * 6 - 183) * pi / 180 +
    (d - (1 + 2 * t1 + c1) * d^3 / 6 +
       (5 - 2 * c1 + 28 * t1 - 3 * c1^2 + 8 * ep2 + 24 * t1^2) * d^5 / 120) / cos(phi1)
  data.frame(lon = lon * 180 / pi, lat = lat * 180 / pi)
}

#' lon/lat (WGS84) for station rows; NA where no coordinates are given.
station_lonlat <- function(st) {
  lon <- lat <- rep(NA_real_, nrow(st))
  x <- suppressWarnings(as.numeric(st$x))
  y <- suppressWarnings(as.numeric(st$y))
  g <- st$crs == "EPSG:4326"
  lon[g] <- x[g]
  lat[g] <- y[g]
  u <- st$crs == "EPSG:25832"
  if (any(u)) {
    ll <- utm_to_lonlat(x[u], y[u], zone = 32)
    lon[u] <- ll$lon
    lat[u] <- ll$lat
  }
  data.frame(lon = lon, lat = lat)
}

haversine_m <- function(lon1, lat1, lon2, lat2) {
  r <- pi / 180
  h <- sin((lat2 - lat1) * r / 2)^2 + cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2
  2 * 6371008.8 * asin(pmin(1, sqrt(h)))
}

# ---- names ------------------------------------------------------------------------

#' Lower-case word tokens of at least `min_chars`, minus stop words.
name_tokens <- function(x, min_chars = 4, stop = character()) {
  x <- tolower(ifelse(is.na(x), "", x))
  w <- unlist(strsplit(x, "[^[:alnum:]æøåäöü]+"))
  w <- w[nchar(w) >= min_chars & !grepl("^[0-9]+$", w)]
  unique(setdiff(w, tolower(stop)))
}

#' Stop words: config list plus the tokens of the scope's region label.
match_stopwords <- function(cfg, scope) {
  c(cfg$name_stopwords, name_tokens(scope$region$label, 1))
}

# ---- station-years ----------------------------------------------------------------

#' One row per survey × station × year: how the station can be located
#' (coords, code, name or none) and whether it lies in a municipality the scope
#' excludes. Surveys without rows in stations.csv get one pseudo-station built
#' from the place names in their `region` field.
survey_station_years <- function(gs, st, scope, cfg) {
  excluded <- vapply(scope$region$excluded_neighbours %||% list(), `[[`, "", "label")
  stop_words <- match_stopwords(cfg, scope)
  ll <- station_lonlat(st)
  out <- list()
  for (i in seq_len(nrow(gs))) {
    ref <- gs$survey_ref[i]
    rows <- which(st$survey_ref == ref)
    if (length(rows)) {
      for (j in rows) {
        yrs <- period_years(st$years[j])
        names_j <- name_tokens(paste(st$waterbody[j], st$station[j]), cfg$min_token_chars, stop_words)
        method <- if (!is.na(ll$lon[j])) "coords" else if (nzchar(st$vannlokalitetkode[j])) "code" else
          if (length(names_j)) "name" else "none"
        out[[length(out) + 1]] <- data.frame(
          survey_ref = ref, station = st$station[j], year = yrs,
          lon = ll$lon[j], lat = ll$lat[j], code = st$vannlokalitetkode[j],
          names = paste(names_j, collapse = ";"), method = method,
          excluded = st$former_municipality[j] %in% excluded,
          station_source = "stations.csv")
      }
    } else {
      yrs <- period_years(gs$period[i])
      if (!length(yrs)) next
      names_i <- name_tokens(gs$region[i], cfg$min_token_chars, stop_words)
      out[[length(out) + 1]] <- data.frame(
        survey_ref = ref, station = "(region)", year = yrs, lon = NA_real_, lat = NA_real_,
        code = "", names = paste(names_i, collapse = ";"),
        method = if (length(names_i)) "name" else "none", excluded = FALSE,
        station_source = "goldset.csv region")
    }
  }
  if (!length(out)) return(data.frame())
  do.call(rbind, out)
}

period_years <- function(period) {
  p <- parse_period(period)
  p <- p[p$ok, ]
  if (!nrow(p)) return(integer())
  sort(unique(unlist(Map(seq, p$start, p$end))))
}

#' Indices of scope records matching one station-year, by the station's method.
match_one_station_year <- function(s, recs, rec_tokens, radius_m) {
  same_year <- which(!is.na(recs$year) & recs$year == s$year)
  if (!length(same_year) || s$method == "none") return(integer())
  by_code <- if (nzchar(s$code)) {
    txt <- paste(recs$waterBody[same_year], recs$locality[same_year], recs$locationID[same_year])
    same_year[grepl(s$code, txt, fixed = TRUE)]
  } else integer()
  if (s$method == "coords") {
    # Coordinates or, when the station also has a code, the code (coordinates in
    # reports are often rounded).
    d <- haversine_m(s$lon, s$lat, recs$decimalLongitude[same_year], recs$decimalLatitude[same_year])
    return(sort(union(same_year[!is.na(d) & d <= radius_m], by_code)))
  }
  if (s$method == "code") return(by_code)
  want <- strsplit(s$names, ";", fixed = TRUE)[[1]]
  same_year[vapply(rec_tokens[same_year], function(t) any(want %in% t), logical(1))]
}

#' Station-years with the number of matched records, and the long table of
#' matched record indices (for the survey-level evidence).
match_station_years <- function(sy, recs, cfg) {
  for (f in c("waterBody", "locality", "locationID", "decimalLatitude", "decimalLongitude"))
    if (!f %in% names(recs)) recs[[f]] <- NA
  rec_tokens <- lapply(paste(recs$waterBody, recs$locality), name_tokens,
                       min_chars = cfg$min_token_chars)
  idx <- lapply(seq_len(nrow(sy)), function(k)
    match_one_station_year(sy[k, ], recs, rec_tokens, cfg$station_radius_m))
  sy$n_records <- lengths(idx)
  sy$datasets <- vapply(idx, function(i) paste(sort(unique(substr(recs$datasetKey[i], 1, 8))),
                                               collapse = ";"), "")
  list(station_years = sy,
       hits = data.frame(survey_ref = rep(sy$survey_ref, lengths(idx)),
                         rec = unlist(idx, use.names = FALSE)))
}

# ---- evidence, score, band --------------------------------------------------------

#' Institution names of a survey: the institution field without the client
#' ("oppdragsgiver ...") and years, split on ; / , and "og".
institution_names <- function(x) {
  x <- gsub("\\((oppdragsgiver|samling)[^)]*\\)", "", x)
  x <- gsub("\\b(19|20)[0-9]{2}([-–][0-9]{2,4})?\\b", "", x)
  p <- trimws(unlist(strsplit(x, "[;/,]|\\bog\\b|\\bmed\\b")))
  p[nzchar(p)]
}

#' Report numbers and ids of a survey's documents, as lower-case needles.
document_needles <- function(documents, doc_ids) {
  ids <- trimws(unlist(strsplit(doc_ids, ";", fixed = TRUE)))
  ids <- sub("^(nva|doi|handle):", "", ids[nzchar(ids)])
  rep_no <- regmatches(documents, gregexpr(
    "(?i)(rapport|report|notat)\\s+(nr\\.?\\s*)?[0-9]{1,4}([-/][0-9]{1,4})?", documents, perl = TRUE))[[1]]
  unique(tolower(gsub("\\s+", " ", c(ids, rep_no))))
}

#' Evidence for one survey: a value and a source per dimension, plus coverage.
survey_evidence <- function(g, sy, hits, recs, datasets, cfg, stop_words) {
  s <- sy[sy$survey_ref == g$survey_ref & !sy$excluded, ]
  n_sy <- nrow(s)
  assessable <- s$method != "none"
  covered <- s$n_records > 0
  coverage <- if (any(assessable)) sum(covered & assessable) / sum(assessable) else NA_real_
  # Place × time evidence: like coverage, but a station-year matched only by a
  # place name counts with name_only_factor (names are coarser than coordinates
  # or codes).
  w_sy <- ifelse(s$method == "name", cfg$name_only_factor, 1)
  place_time <- if (any(assessable)) sum(w_sy[covered & assessable]) / sum(assessable) else NA_real_
  located <- if (n_sy) sum(s$method %in% c("coords", "code")) / n_sy else 0
  r <- recs[hits$rec[hits$survey_ref == g$survey_ref], , drop = FALSE]
  r <- r[!duplicated(r$key), , drop = FALSE]
  meta <- datasets[datasets$dataset_key %in% r$datasetKey, , drop = FALSE]

  # Institution: any institution token in recordedBy / institutionCode / publisher of matched records.
  inst_tok <- name_tokens(paste(institution_names(g$institution), collapse = " "),
                          min_chars = 4, stop = stop_words)
  rec_inst <- name_tokens(paste(c(r$recordedBy, r$institutionCode, meta$publisher), collapse = " "),
                          min_chars = 4)
  inst_hit <- intersect(inst_tok, rec_inst)
  inst_val <- if (!nrow(r) || !length(inst_tok)) NA_real_ else as.numeric(length(inst_hit) > 0)

  # Dataset name: title tokens in datasetName or dataset title of records in the survey's years.
  title_tok <- name_tokens(g$title, cfg$min_token_chars, stop_words)
  yrs <- unique(s$year)
  in_years <- recs[!is.na(recs$year) & recs$year %in% yrs, , drop = FALSE]
  ds_years <- datasets[datasets$dataset_key %in% in_years$datasetKey, , drop = FALSE]
  name_txt <- name_tokens(paste(c(unique(in_years$datasetName), ds_years$title), collapse = " "),
                          cfg$min_token_chars)
  name_hit <- intersect(title_tok, name_txt)
  name_val <- if (!length(title_tok)) NA_real_ else as.numeric(length(name_hit) > 0)

  # Direct link: a document id or report number in a scope dataset's registry entry.
  needles <- document_needles(g$documents, g$doc_ids)
  link_ds <- if (length(needles)) datasets$dataset_key[vapply(tolower(datasets$meta_text), function(t)
    any(vapply(needles, grepl, logical(1), x = t, fixed = TRUE)), logical(1))] else character()
  link_val <- if (length(link_ds)) 1 else NA_real_   # absence is not evidence

  methods <- table(factor(s$method, levels = c("coords", "code", "name", "none")))
  data.frame(
    survey_ref = g$survey_ref,
    n_station_years = n_sy,
    n_excluded = sum(sy$survey_ref == g$survey_ref & sy$excluded),
    located = located,
    coverage = coverage,
    place_time = place_time,
    place_time_source = sprintf("%d/%d station-years with records within %d m / by code / by name, name-only weighted %s (methods: %s)",
                                sum(covered & assessable), sum(assessable), cfg$station_radius_m,
                                format(cfg$name_only_factor),
                                paste(sprintf("%s %d", names(methods), methods), collapse = ", ")),
    taxon = nrow(r),
    taxon_source = if (nrow(r)) paste(sprintf("%s %d", names(table(r$order)), table(r$order)),
                                      collapse = ", ") else "no matched records",
    years_with_records = sprintf("%d/%d", length(unique(s$year[covered])), length(yrs)),
    institution = inst_val,
    institution_source = if (is.na(inst_val)) "not assessable" else
      sprintf("survey tokens [%s]; found [%s]", paste(inst_tok, collapse = ","),
              paste(inst_hit, collapse = ",")),
    dataset_name = name_val,
    dataset_name_source = if (is.na(name_val)) "no distinctive title tokens" else
      sprintf("title tokens [%s]; found [%s]", paste(title_tok, collapse = ","),
              paste(name_hit, collapse = ",")),
    direct_link = link_val,
    direct_link_source = if (length(link_ds)) sprintf("[%s] in dataset %s",
      paste(needles, collapse = ","), paste(substr(link_ds, 1, 8), collapse = ";")) else
      sprintf("none of [%s] in dataset metadata", paste(needles, collapse = ",")),
    matched_datasets = paste(sort(unique(substr(r$datasetKey, 1, 8))), collapse = ";"),
    stringsAsFactors = FALSE)
}

#' Weighted mean over the dimensions that could be assessed (NA if none).
match_score <- function(ev, weights) {
  w <- unlist(weights[EVIDENCE_DIMS])
  v <- as.matrix(ev[, EVIDENCE_DIMS, drop = FALSE])
  num <- rowSums(sweep(v, 2, w, `*`), na.rm = TRUE)
  den <- rowSums(sweep(!is.na(v), 2, w, `*`))
  ifelse(den > 0, num / den, NA_real_)
}

#' Asymmetric bands: "likely_not_in_gbif" needs a low score, low coverage and
#' enough located station-years; anything not clearly in or out is uncertain.
match_band <- function(score, coverage, located, b) {
  out <- rep("uncertain", length(score))
  out[!is.na(score) & score >= b$in_gbif_min_score] <- "likely_in_gbif"
  not <- !is.na(score) & score <= b$not_in_gbif_max_score &
    !is.na(coverage) & coverage <= b$not_in_gbif_max_coverage &
    located >= b$not_in_gbif_min_located
  out[not & out != "likely_in_gbif"] <- "likely_not_in_gbif"
  factor(out, levels = BANDS)
}

# ---- metrics ----------------------------------------------------------------------

#' Wilson score interval for x successes out of n.
wilson_ci <- function(x, n, conf = 0.95) {
  if (n == 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - conf) / 2)
  p <- x / n
  centre <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(lower = max(0, centre - half), upper = min(1, centre + half))
}

rate <- function(x, n) {
  ci <- wilson_ci(x, n)
  list(count = x, n = n, share = if (n) x / n else NA_real_,
       ci95_lower = unname(ci["lower"]), ci95_upper = unname(ci["upper"]))
}

#' Evidence dimensions that pulled towards the wrong band for one error row.
wrong_pull <- function(row, towards_in) {
  v <- unlist(row[EVIDENCE_DIMS])
  bad <- if (towards_in) names(v)[!is.na(v) & v >= 0.5] else names(v)[!is.na(v) & v < 0.5]
  na <- names(v)[is.na(v)]
  paste(c(if (length(bad)) paste(bad, collapse = ", "),
          if (length(na)) paste0("(not assessable: ", paste(na, collapse = ", "), ")")),
        collapse = " ")
}

#' Metrics for one subset of result rows (gold columns plus band and evidence).
match_metrics <- function(res) {
  pos <- res$expected_status %in% STATUS_IN_GBIF
  neg <- res$expected_status %in% STATUS_NOT_PUBLISHED
  false_unpub <- pos & res$band == "likely_not_in_gbif"
  false_pub <- neg & res$band == "likely_in_gbif"
  list(
    n_rows = nrow(res),
    n_gold_in_gbif = sum(pos),
    n_gold_not_published = sum(neg),
    false_unpublished = rate(sum(false_unpub), sum(pos)),
    false_published = rate(sum(false_pub), sum(neg)),
    uncertain = rate(sum(res$band == "uncertain"), nrow(res)),
    errors = res$survey_ref[false_unpub | false_pub])
}

confusion_table <- function(res) {
  t <- table(factor(res$expected_status, levels = STATUS_LEVELS), res$band)
  t <- t[rowSums(t) > 0, , drop = FALSE]
  data.frame(expected_status = rownames(t), unclass(t)[, BANDS, drop = FALSE],
             row.names = NULL, check.names = FALSE)
}
