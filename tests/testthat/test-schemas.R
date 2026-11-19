good_row <- list(
  survey_ref = "trd-test-2020", title = "T", institution = "NINA", taxon_group = "bunndyr",
  region = "Trondheim", period = "2020", method = "", documents = "", doc_ids = "",
  expected_status = "in_gbif", where_data_are = "", gbif_dataset_keys = "",
  is_borderline = "no", include = "yes", found_via = "anders", notes = "")

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

test_that("doc_ids and gbif_dataset_keys follow their patterns", {
  at_root()
  ok <- modifyList(good_row, list(
    doc_ids = "nva:0198cc7b01d9-d9512475;doi:10.1/x",
    gbif_dataset_keys = "33591b80-0e31-480c-82ce-2f57211b10e6;46293000-ddd1-4c32-a1e7-b5e793223ecd"))
  expect_equal(nrow(validate_records(list(ok), "goldset_row")), 0)
  bad <- list(modifyList(good_row, list(doc_ids = "ISBN 978-82")),
              modifyList(good_row, list(doc_ids = "nva:a; nva:b")),
              modifyList(good_row, list(gbif_dataset_keys = "33591b80")))
  expect_equal(nrow(validate_records(bad, "goldset_row")), length(bad))
})

test_that("goldset_worklist lists todo, candidate, missing ids and missing keys", {
  gs <- as.data.frame(rbind(
    modifyList(good_row, list(survey_ref = "a", include = "candidate", expected_status = "todo")),
    modifyList(good_row, list(survey_ref = "b", doc_ids = "nva:x")),
    modifyList(good_row, list(survey_ref = "c", include = "no", expected_status = "not_applicable"))))
  gs[] <- lapply(gs, unlist)
  wl <- goldset_worklist(gs)
  expect_setequal(paste(wl$survey_ref, wl$item),
                  c("a status_todo", "a candidate", "a no_doc_ids", "b gbif_status_no_key"))
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
