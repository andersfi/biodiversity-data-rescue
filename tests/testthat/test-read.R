# Reading test (phase 3): clean-context command, record leak check, answer key
# validation, page selection, cascade rules and scoring. No model is called.

test_that("the headless command switches off tools, MCP, settings, skills and sessions", {
  a <- llm_cli_args("claude-haiku-5-5", "PROMPT", "{}")
  expect_equal(a[1], "-p")
  expect_equal(a[which(a == "--model") + 1], "claude-haiku-5-5")
  expect_equal(a[which(a == "--tools") + 1], "")
  expect_equal(a[which(a == "--setting-sources") + 1], "")
  expect_equal(a[which(a == "--system-prompt") + 1], "PROMPT")
  expect_equal(a[which(a == "--output-format") + 1], "json")
  for (f in c("--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
              "--json-schema")) expect_true(f %in% a, info = f)
  expect_false("--mcp-config" %in% a)
})

test_that("a call runs outside the repo, sends the record on stdin and parses usage", {
  at_root()
  # Fake CLI: echoes its working directory and stdin as a JSON result.
  fake <- tempfile(fileext = ".sh")
  writeLines(c("#!/bin/sh",
               "rec=$(cat | tr -d '\\n\"')",
               "printf '{\"type\":\"result\",\"is_error\":false,\"result\":\"%s|%s|%s\",\"usage\":{\"input_tokens\":5,\"cache_creation_input_tokens\":7,\"cache_read_input_tokens\":11,\"output_tokens\":3},\"modelUsage\":{\"m\":{}},\"duration_ms\":1}' \"$(pwd)\" \"$rec\" \"$(ls -A | wc -l)\""),
             fake)
  Sys.chmod(fake, "0755")
  pf <- tempfile(fileext = ".md"); writeLines("p", pf)
  res <- llm_cli_call("hello record", "m", pf, cli = fake)
  parts <- strsplit(res$output, "|", fixed = TRUE)[[1]]
  expect_false(startsWith(parts[1], normalizePath(ROOT)))
  expect_equal(trimws(parts[3]), "0")   # the working directory is empty
  expect_equal(parts[2], "hello record")
  expect_equal(llm_cli_input_total(res), 23)
  expect_equal(res$models, "m")
})

test_that("a failing or erroring call stops; nothing is repaired", {
  at_root()
  fail <- tempfile(fileext = ".sh")
  writeLines(c("#!/bin/sh", "echo boom >&2", "exit 3"), fail); Sys.chmod(fail, "0755")
  err <- tempfile(fileext = ".sh")
  writeLines(c("#!/bin/sh", "cat >/dev/null", "echo '{\"is_error\":true,\"result\":\"limit\"}'"), err)
  Sys.chmod(err, "0755")
  pf <- tempfile(fileext = ".md"); writeLines("p", pf)
  expect_error(llm_cli_call("x", "m", pf, cli = fail), "status 3")
  expect_error(llm_cli_call("x", "m", pf, cli = err), "limit")
  expect_error(llm_cli_call("x", "m", pf, schema = "extraction", cli = err), "limit")
})

test_that("the model-facing schema drops the fields R adds", {
  at_root()
  s <- jsonlite::fromJSON(llm_model_schema("extraction"), simplifyVector = FALSE)
  expect_setequal(unlist(s$required), "surveys")
  expect_null(s$properties$uri)
  expect_null(s[["x-meta-fields"]])
})

test_that("records carry no gold-set answers outside the page text", {
  at_root()
  gs <- read_goldset()
  pages <- data.frame(page = 1:2, text = c("Title page NINA", "Stations 2020"))
  rec <- read_record_text(pages, 1:2)
  expect_length(read_record_leaks(rec, pages$text, gs), 0)
  bad <- paste(rec, gs$survey_ref[1])
  expect_true(gs$survey_ref[1] %in% read_record_leaks(bad, pages$text, gs))
  wd <- gs$where_data_are[nchar(gs$where_data_are) >= 25][1]
  expect_true(wd %in% read_record_leaks(paste(rec, wd), pages$text, gs))
})

test_that("extraction_truth.csv is valid and rejects bad rows", {
  at_root()
  gs <- read_goldset(); man <- read_manifest(); tr <- read_truth()
  expect_equal(nrow(validate_truth(tr, gs$survey_ref, man)), 0)
  bad <- tr[1:3, ]
  bad$field[1] <- "colour"
  bad$value[2] <- "not_stated"          # page still given
  bad$document[3] <- "No such report"
  probs <- validate_truth(bad, gs$survey_ref, man)
  expect_true(any(grepl("field 'colour'", probs$problem)))
  expect_true(any(grepl("page given for not_stated", probs$problem)))
  expect_true(any(grepl("not in fulltext_manifest", probs$problem)))
})

test_that("page selection keeps the first pages and the best keyword pages", {
  d <- data.frame(page = 1:10, text = c(rep("intro", 3), "stasjon UTM øst nord", rep("x", 5),
                                        "Sammendrag\nshort"))
  cfg <- list(first_pages = 2, top_k = 1, summary_terms = c("sammendrag"))
  terms <- list(stations = c("stasjon", "utm", "øst", "nord"))
  expect_equal(read_select_pages(d, "pages", cfg, terms), c(1, 2, 4))
  expect_equal(read_select_pages(d, "summary", cfg, terms), c(1, 2, 10))
  expect_equal(read_select_pages(d, "full", cfg, terms), 1:10)
  expect_equal(read_page_coverage(c("4", "", "7"), c(1, 2, 4)), 0.5)
})

survey <- function(period = "2020", stations = list(), status = "given", ds = list("not_stated")) {
  list(label = "s", period = list(value = period, page = 1),
       institution = list(value = "Norsk institutt for naturforskning (NINA)", page = 1),
       region = list(value = "Trondheim kommune; Byneset", page = 1),
       taxon_scope = list(value = "yes", page = 1),
       data_statement = list(value = ds, quote = "not_stated", page = NULL),
       stations = list(status = status, items = stations))
}

test_that("cascade rules fire on invented values, ignored text and count mismatch", {
  text <- "[page 1]\nSt. 1 Uglabekken 568287 7029232\nSt. 2 Kystadbekken 566802 7029517\nInnsamlet oktober 2020. Artsliste i vedlegg."
  it <- function(x, y) list(station = "1", waterbody = "w", x = x, y = y, crs_as_printed = "UTM",
                            vannlokalitetkode = "not_stated", page = 1)
  ok <- list(surveys = list(survey(stations = list(it("568287", "7029232"), it("566802", "7029517")),
                                   ds = list("appendix_species_list"))))
  expect_equal(nrow(read_rules(ok, text)), 0)
  invented <- list(surveys = list(survey(period = "2019", stations = list(it("568287", "7029999"), it("566802", "7029517")),
                                         ds = list("appendix_species_list"))))
  r <- read_rules(invented, text)
  expect_true(all(c("value_not_in_text") %in% r$rule))
  expect_true("period" %in% r$field[r$rule == "value_not_in_text"])
  ignored <- list(surveys = list(survey(period = "not_stated", status = "not_stated")))
  r <- read_rules(ignored, text)
  expect_setequal(r$field[r$rule == "not_stated_vs_pages"], c("stations", "period", "data_statement"))
  expect_true("count_mismatch" %in% r$rule)
})

test_that("fields are scored with not_stated as its own outcome", {
  expect_equal(score_field("period", "2015-2017", "2015;2016;2017")$score, 1)
  expect_equal(score_field("institution", "Norsk institutt for naturforskning (NINA)", "NINA")$score, 1)
  expect_equal(score_field("region", "Trondheim kommune;Byneset", "Byneset, Trondheim kommune")$score, 1)
  expect_equal(score_field("region", "Trondheim kommune;Gaula", "Trondheim kommune")$score, 0.5)
  expect_equal(score_field("data_statement", "vannmiljo;gbif", c("gbif", "vannmiljo"))$score, 1)
  expect_equal(score_field("period", "not_stated", "2020")$outcome, "invented")
  expect_equal(score_field("period", "2020", "not_stated")$outcome, "missed")
  expect_equal(score_field("data_statement", "not_stated", "not_stated")$outcome, "both_not_stated")
})

test_that("a document with two surveys aligns each key survey to its best answer", {
  ans <- list(surveys = list(survey(period = "2016-2017"), survey(period = "2017-2018")))
  t <- data.frame(survey_ref = c("a", "b"), document = "d", field = "period",
                  value = c("2017-2018", "2016-2017"), verified = "no")
  s <- score_document(ans, t)
  expect_equal(s$score, c(1, 1))
  expect_equal(s$aligned_survey, c(2, 1))
})

test_that("stations match on code or on coordinates within 50 m", {
  st <- data.frame(vannlokalitetkode = c("", "123-45-R"), x = c("568287", ""), y = c("7029232", ""),
                   crs = c("EPSG:25832", ""))
  it <- function(x, y, code = "not_stated") list(station = "s", waterbody = "w", x = x, y = y,
                                                 crs_as_printed = "UTM", vannlokalitetkode = code, page = 1)
  ans <- list(surveys = list(survey(stations = list(it("568300", "7029240"), it("not_stated", "not_stated", "123-45-r"),
                                                    it("1", "2")))))
  s <- score_stations(ans, st)
  expect_equal(s$matched, 2)
  expect_equal(s$recall, 1)
  expect_equal(s$precision, 2 / 3)
})
