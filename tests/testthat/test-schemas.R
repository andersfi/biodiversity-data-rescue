good_row <- list(
  survey_ref = "trd-test-2020", title = "T", institution = "NINA", taxon_group = "bunndyr",
  region = "Trondheim", period = "2020", method = "", documents = "", expected_status = "in_gbif",
  where_data_are = "", is_borderline = "no", include = "yes", found_via = "anders", notes = "")

test_that("gold-set row schema accepts a valid row and rejects bad values", {
  at_root()
  expect_equal(nrow(validate_records(list(good_row), "goldset_row")), 0)
  bad <- list(
    modifyList(good_row, list(expected_status = "open_elsewhere (antatt)")),
    modifyList(good_row, list(found_via = "google")),
    modifyList(good_row, list(include = "maybe")),
    modifyList(good_row, list(survey_ref = "Has Spaces")),
    modifyList(good_row, list(expected_status = "todo", include = "yes")),
    modifyList(good_row, list(expected_status = "not_applicable", include = "yes")),
    good_row[-1]
  )
  expect_equal(nrow(validate_records(bad, "goldset_row")), length(bad))
  expect_equal(nrow(validate_records(
    list(modifyList(good_row, list(expected_status = "todo", include = "candidate"))),
    "goldset_row")), 0)
})

test_that("normalise_goldset moves parenthesised comments to notes", {
  df <- as.data.frame(modifyList(good_row, list(expected_status = "open_elsewhere (antatt)",
                                               found_via = "nva_targeted (kjent serie)",
                                               notes = "N.")))
  out <- normalise_goldset(df)
  expect_equal(out$expected_status, "open_elsewhere")
  expect_equal(out$found_via, "nva_targeted")
  expect_match(out$notes, "antatt")
  expect_match(out$notes, "kjent serie")
})

test_that("goldset.csv is valid", {
  at_root()
  skip_if_not(file.exists(GOLDSET_FILE))
  gs <- read_goldset()
  expect_identical(names(gs), GOLDSET_COLUMNS)
  bad <- validate_goldset(gs)
  expect_equal(nrow(bad), 0, info = paste(bad$id, bad$errors, collapse = "\n"))
})

test_that("all knowledge cards and templates validate", {
  at_root()
  cards <- list_knowledge_files()
  templates <- list.files("knowledge/_templates", full.names = TRUE)
  expect_length(templates, 4)
  for (f in cards) expect_length(validate_knowledge_card(read_knowledge_card(f)), 0)
  # Templates are not in a type folder, so only the schema is checked.
  for (f in templates) {
    expect_length(validate_knowledge_card(read_knowledge_card(f), check_folder = FALSE), 0)
  }
  bad <- read_knowledge_card("knowledge/aggregators/vannmiljo.md")
  bad$front$last_confirmed <- NULL
  expect_gt(length(validate_knowledge_card(bad)), 0)
})

test_that("full-text manifest rows validate", {
  at_root()
  man <- readr::read_csv("goldset/fulltext_manifest.csv", col_types = readr::cols(.default = "c"))
  man$bytes <- as.integer(man$bytes)
  bad <- validate_records(df_rows(man), "fulltext_manifest_row", "file")
  expect_equal(nrow(bad), 0, info = paste(bad$id, bad$errors, collapse = "\n"))
  expect_gt(nrow(validate_records(list(list(file = "a.pdf", sha256 = "xyz", bytes = 1L,
    survey_ref = "a", role = "primary", document = "d")), "fulltext_manifest_row")), 0)
})

test_that("screening draft schema compiles and enforces not_stated", {
  at_root()
  ok <- list(uri = "doi:10.1/x", decision = "uncertain", reason = "r",
             survey_type = "not_stated", taxa_in_scope = "not_stated",
             area_in_scope = "not_stated", collects_new_data = "not_stated",
             backend = "claude_code", model = "m", answered_at = "2026-11-18T10:00:00Z")
  expect_equal(nrow(validate_records(list(ok), "screening")), 0)
  expect_equal(nrow(validate_records(list(modifyList(ok, list(taxa_in_scope = ""))),
                                     "screening")), 1)
})
