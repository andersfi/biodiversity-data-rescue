# R/runs.R and the `status` verb's next-step rule.

fake_run <- function(root, step, id, finished = TRUE, metrics = list(n = 1)) {
  d <- file.path(root, step, id)
  dir.create(d, recursive = TRUE)
  jsonlite::write_json(list(step = step, id = id, git_commit = "abc1234",
                            goldset_sha256 = "f00", started_at = "2026-11-19T00:00:00Z",
                            finished_at = if (finished) "2026-11-19T00:01:00Z" else NULL),
                       file.path(d, "run.json"), auto_unbox = TRUE, null = "null")
  jsonlite::write_json(metrics, file.path(d, "metrics.json"), auto_unbox = TRUE)
}

test_that("runs_index and latest_run read run folders", {
  root <- withr::local_tempdir()
  expect_equal(nrow(runs_index(root)), 0)
  fake_run(root, "gbif", "2026-11-18_baseline", metrics = list(n_records = 5, prev = NA))
  fake_run(root, "gbif", "2026-11-19_again")
  fake_run(root, "match", "2026-11-19_unfinished", finished = FALSE)
  idx <- runs_index(root)
  expect_equal(idx$id, c("2026-11-18_baseline", "2026-11-19_again", "2026-11-19_unfinished"))
  expect_match(idx$metrics[1], "n_records = 5")
  expect_equal(latest_run("gbif", root)$id, "2026-11-19_again")
  expect_null(latest_run("match", root))
  expect_null(latest_run("read", root))
})

test_that("run_start rejects bad labels and unknown steps", {
  expect_error(run_start("gbif", "Has Space"), "Label")
  expect_error(run_start("nope", "x"), "Unknown step")
})

test_that("status suggests the first unmet step", {
  some <- list(id = "x")
  expect_match(status_next_step(1, 0, list()), "fix goldset")
  expect_match(status_next_step(0, 0, list(gbif = NULL)), "run.R gbif")
  expect_match(status_next_step(0, 0, list(gbif = some)), "include = yes")
  expect_match(status_next_step(0, 3, list(gbif = some)), "run.R match")
  expect_match(status_next_step(0, 3, list(gbif = some, match = some)), "run.R report")
})
