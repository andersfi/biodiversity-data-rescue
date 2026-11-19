# R/report.R: period parsing, source-matrix rules, recall/precision.
# Synthetic inputs only; no repository data.

local({
  withr::local_dir(ROOT)
  sys.source("R/report.R", envir = globalenv())
})

# ---- parse_period ----------------------------------------------------------------

test_that("parse_period handles years, ranges, multiple intervals and '?'", {
  p <- parse_period(c("2009", "1982–1986", "1982-1986; 1999", "2025?", "1989; 2014–2015?"),
                    id = c("a", "b", "c", "d", "e"))
  expect_true(all(p$ok))
  expect_equal(p$start, c(2009L, 1982L, 1982L, 1999L, 2025L, 1989L, 2014L))
  expect_equal(p$end,   c(2009L, 1986L, 1986L, 1999L, 2025L, 1989L, 2015L))
  expect_equal(p$uncertain, c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, TRUE))
  expect_equal(p$id, c("a", "b", "c", "c", "d", "e", "e"))
})

test_that("parse_period marks unparseable periods instead of dropping them", {
  p <- parse_period(c("ca. 1990", "", "1999–1990", "1990s", NA), id = 1:5)
  expect_equal(nrow(p), 5)
  expect_false(any(p$ok))
  expect_true(all(is.na(p$start)))
  expect_false(any(p$uncertain))
})

# ---- institution_group -----------------------------------------------------------

test_that("institution_group ignores the client and applies the precedence", {
  x <- c("NIVA (oppdragsgiver Trondheim kommune)", "NTNU Vitenskapsmuseet",
         "NINA (oppdragsgiver NTNU)", "Sweco Norge AS (oppdragsgiver Norsk Luftambulanse)",
         "Multiconsult", "Rambøll Norge AS; Uni Research Miljø (Bergen)", "ukjent",
         "Ecology Consulting AS")
  expect_equal(as.character(institution_group(x)),
               c("NIVA", "NTNU", "NINA", "consultancy", "consultancy", "consultancy",
                 "other", "consultancy"))
})

# ---- source-matrix rules ---------------------------------------------------------

KEYS <- c("33591b80-0e31-480c-82ce-2f57211b10e6", "46293000-ddd1-4c32-a1e7-b5e793223ecd",
          "33591b81-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
AGG <- "46293000-ddd1-4c32-a1e7-b5e793223ecd"

test_that("extract_dataset_keys resolves full keys and unique prefixes only", {
  k <- extract_dataset_keys(c(
    "in 46293000-ddd1-4c32-a1e7-b5e793223ecd",
    "bunndyr (33591b80, 12 funn) og (edd9b710, 4)",
    "prefix 33591b8 is too short",
    "nva-like 0199377c9621-d9eb8cb1-c9be-41fd-a2d9-4f0e56aa1882"), KEYS)
  expect_equal(k[[1]]$keys, AGG)
  expect_equal(k[[2]]$keys, KEYS[1])
  expect_equal(k[[2]]$unresolved, "edd9b710")
  expect_length(k[[3]]$keys, 0)
  expect_length(k[[4]]$keys, 0)
})

test_that("rule_gbif_dataset: key or datasetName match -> yes; status -> no; else unknown", {
  where <- c(paste("NTNU (", KEYS[1], ")"),
             'GBIF, datasetName "Sagelva (Hovedfagsoppgave)"',
             'GBIF, datasetName "Not a group"',
             paste("Vannmiljø", AGG),
             "Ikke i GBIF",
             paste("NTNU (", KEYS[1], ")"))
  status <- c("in_gbif", "in_gbif", "in_gbif", "partly_in_gbif", "open_elsewhere", "open_elsewhere")
  r <- rule_gbif_dataset(where, status, KEYS, AGG, c("Sagelva (Hovedfagsoppgave)"))
  expect_equal(as.vector(r), c("yes", "yes", "unknown", "unknown", "no", "unknown"))
  expect_equal(attr(r, "conflict"), c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE))
})

test_that("rule_vannmiljo: key, or code + year inside period", {
  groups <- data.frame(year = c("2019", "2014"),
                       waterbodies = c("Vannlokalitetkode: 122-77-R", "Vannlokalitetkode: 123-110-R"))
  where <- c(paste("Vannmiljø", AGG), "stasjon 122-77-R", "stasjon 122-77-R",
             "stasjon 122-77-R", "Vannmiljø i GBIF: 285 funn", "nothing")
  period <- c("2014", "2018–2020", "2015", "2019", "2014", "2014")
  status <- c("partly_in_gbif", "todo", "todo", "open_elsewhere", "partly_in_gbif", "unidentified")
  r <- rule_vannmiljo(where, status, period, KEYS, AGG, groups)
  expect_equal(as.vector(r), c("yes", "yes", "unknown", "unknown", "unknown", "no"))
  expect_equal(attr(r, "conflict"), c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE))
})

test_that("document rules: NVA, DOI/handle, citation only, no document", {
  docs <- c("NINA-rapport 1150 (nva:0198cc7b01d9-d9512475-6eb0-4009-9384-995b9af5b68e)",
            "doi:10.1000/xyz123", "https://hdl.handle.net/11250/123",
            "NTNU VM notat 2016-3 (ISBN 978-82-8322-063-6)", "TM 2020/01", "", "  ")
  expect_equal(rule_nva(docs), c("yes", rep("unknown", 6)))
  expect_equal(rule_doi_handle(docs), c("unknown", "yes", "yes", rep("unknown", 4)))
  expect_equal(rule_citation_only(docs), c("no", "no", "no", "yes", "yes", "no", "no"))
  expect_equal(rule_no_document(docs), c(rep("no", 5), "yes", "yes"))
})

test_that("coverage and combinations count yes per source and exclusive rows", {
  m <- data.frame(survey_ref = c("a", "b", "c", "d"),
                  gbif_dataset = c("yes", "yes", "no", "unknown"),
                  vannmiljo = c("yes", "no", "no", "unknown"),
                  nva = c("unknown", "unknown", "yes", "unknown"),
                  doi_handle = "unknown", citation_only = c("no", "no", "no", "no"))
  cv <- source_coverage(m)
  expect_equal(cv$n_rows, c(2, 1, 1, 0, 0))
  expect_equal(cv$n_only_this, c(1, 0, 1, 0, 0))
  cb <- source_combinations(m)
  expect_equal(sum(cb$n), 4)
  expect_equal(cb$n[cb$combination == "gbif_dataset+vannmiljo"], 1)
  expect_equal(cb$n[cb$combination == "(none)"], 1)
})

# ---- benchmark_recall ------------------------------------------------------------

test_that("benchmark_recall excludes rows found via the source and computes precision", {
  gs <- data.frame(
    survey_ref = paste0("s", 1:6),
    include = c("yes", "yes", "yes", "yes", "candidate", "no"),
    expected_status = c("in_gbif", "open_elsewhere", "in_gbif", "not_applicable", "in_gbif", "in_gbif"),
    found_via = c("anders", "nva_targeted", "gbif_baseline", "anders", "anders", "anders"))
  runs <- data.frame(source = c("nva", "gbif"), run = c("r1", "r2"))
  hits <- data.frame(source = c("nva", "nva", "nva", "gbif"),
                     run = c("r1", "r1", "r1", "r2"),
                     survey_ref = c("s1", "s2", "s5", "s1"))
  samples <- data.frame(source = "nva", run = "r1", n_screened = 20L, n_relevant = 5L)
  b <- benchmark_recall(gs, runs, hits, samples)
  expect_named(b, BENCHMARK_COLUMNS)
  # nva: eligible s1, s3 (s2 found via nva_targeted, s4 not_applicable, s5/s6 not yes)
  expect_equal(b$n_eligible, c(2, 2))
  expect_equal(b$n_found, c(1, 1))
  expect_equal(b$recall, c(0.5, 0.5))
  expect_equal(b$n_screened, c(20L, NA))
  expect_equal(b$precision, c(0.25, NA))
  # gbif: eligible s1, s2 (s3 found via gbif_baseline)
  b2 <- benchmark_recall(gs, runs[2, ], hits, samples, include_levels = c("yes", "candidate"))
  expect_equal(b2$n_eligible, 3)
})

test_that("benchmark_recall with no runs returns the empty table structure", {
  b <- benchmark_recall(data.frame(), data.frame(), data.frame(), data.frame())
  expect_named(b, BENCHMARK_COLUMNS)
  expect_equal(nrow(b), 0)
})

# ---- markdown --------------------------------------------------------------------

test_that("md_table escapes pipes and right-aligns numbers", {
  t <- md_table(data.frame(a = "x|y", n = 3))
  expect_match(t, "x\\|y", fixed = TRUE)
  expect_match(t, "| :--- | ---: |", fixed = TRUE)
})
