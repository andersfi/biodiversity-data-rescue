# CLAUDE.md, "Gold-set full texts": the pipeline never reads goldset/fulltext/.
# Only the manifest script may reference that folder.

test_that("only the manifest script references goldset/fulltext/", {
  at_root()
  allowed <- "scripts/goldset_fulltext_manifest.R"
  files <- list.files(c("R", "scripts", "prompts", "config", "db"), recursive = TRUE,
                      full.names = TRUE, pattern = "\\.(R|r|md|ya?ml|json|sql|py|sh)$")
  # Matches "goldset/fulltext" and "goldset/fulltext/" but not "fulltext_manifest",
  # and also a "fulltext" path component built with file.path().
  pattern <- "goldset/fulltext(?![_A-Za-z0-9])|[\"']fulltext[\"']"
  hits <- files[vapply(files, function(f) {
    any(grepl(pattern, readLines(f, warn = FALSE), perl = TRUE))
  }, logical(1))]
  expect_true(allowed %in% hits)
  expect_setequal(hits, allowed)
})
