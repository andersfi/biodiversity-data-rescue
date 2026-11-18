expected_tables <- c("aggregator_coverage", "candidate_pair", "document", "document_survey",
                     "gbif_dataset", "knowledge_card", "llm_answer", "run_log", "schema_meta",
                     "survey", "survey_status")

test_that("db_init creates every table and is idempotent", {
  at_root()
  con <- db_connect(tempfile(fileext = ".sqlite"))
  on.exit(db_disconnect(con))
  db_init(con)
  expect_setequal(db_tables(con), expected_tables)
  expect_silent(db_init(con))
  expect_setequal(db_tables(con), expected_tables)
})

test_that("foreign keys and CHECK constraints are enforced", {
  at_root()
  con <- db_connect(tempfile(fileext = ".sqlite"))
  on.exit(db_disconnect(con))
  db_init(con)
  expect_equal(DBI::dbGetQuery(con, "PRAGMA foreign_keys")[[1]], 1L)
  expect_error(DBI::dbExecute(con,
    "INSERT INTO survey_status (survey_id, category, reason, set_by) VALUES (999, 'in_gbif', 'x', 'test')"))
  DBI::dbExecute(con, "INSERT INTO survey (uri, title) VALUES ('survey:test', 'Test')")
  expect_error(DBI::dbExecute(con,
    "INSERT INTO survey_status (survey_id, category, reason, set_by) VALUES (1, 'maybe', 'x', 'test')"))
  expect_error(DBI::dbExecute(con, "INSERT INTO survey (uri, title) VALUES ('survey:test', 'Dup')"))
})

test_that("run_log and llm answer cache round-trip", {
  at_root()
  con <- db_connect(tempfile(fileext = ".sqlite"))
  on.exit(db_disconnect(con))
  db_init(con)
  id <- db_run_start(con, kind = "llm", step = "screening", backend = "claude_code",
                     model = "test-model", schema_version = "0.1.0")
  db_run_finish(con, id, n_records = 1)
  expect_equal(db_get_run(con, id)$n_records, 1L)
  expect_true(is.na(db_get_run(con, id)$input_tokens))
  db_insert_llm_answers(con, data.frame(step = "screening", record_uri = "doi:10.1/x",
    content_sha256 = "abc", schema_version = "0.1.0", answer_json = "{}", run_id = id,
    answered_at = "2026-11-18T00:00:00Z"))
  expect_equal(db_llm_cached(con, "screening", c("doi:10.1/x", "doi:10.1/x", "doi:10.1/y"),
                             c("abc", "changed", "abc"), "0.1.0"), c(TRUE, FALSE, FALSE))
  expect_false(db_llm_cached(con, "screening", "doi:10.1/x", "abc", "0.2.0"))
})
