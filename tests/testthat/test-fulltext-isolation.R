# Decision 2026-11-19 (docs/design.md): the local gold-set full texts may be
# read only by the `read` verb. Search and screening never read them.
#  1. Only R/fulltext.R may reference the folder.
#  2. Only R/cmd_read.R (the `read` verb) calls the fulltext_* functions, and
#     only run.R's `read` branch calls cmd_read().

code_files <- function() {
  # Executable code and model inputs. JSON Schemas only describe fields.
  files <- c("run.R", list.files(c("R", "prompts", "config", "db"), recursive = TRUE,
                                 full.names = TRUE, pattern = "\\.(R|r|md|ya?ml|json|sql|py|sh)$"))
  files[file.exists(files)]
}
uses <- function(files, pattern) {
  files[vapply(files, function(f) any(grepl(pattern, readLines(f, warn = FALSE), perl = TRUE)),
               logical(1))]
}

test_that("only R/fulltext.R references goldset/fulltext/", {
  at_root()
  # "goldset/fulltext" (not "fulltext_manifest"), or a "fulltext" path
  # component built with file.path().
  pattern <- "goldset/fulltext(?![_A-Za-z0-9])|[\"']fulltext[\"']"
  expect_setequal(uses(code_files(), pattern), "R/fulltext.R")
})

test_that("only the read verb calls the full-text functions", {
  at_root()
  defined <- ls(envir = local({ e <- new.env(); sys.source("R/fulltext.R", envir = e); e }))
  fns <- grep("^fulltext_", defined, value = TRUE)
  expect_gt(length(fns), 0)
  pattern <- sprintf("\\b(%s)\\s*\\(", paste(fns, collapse = "|"))
  callers <- uses(code_files(), pattern)
  expect_true("R/cmd_read.R" %in% callers)
  expect_true(all(callers %in% c("R/fulltext.R", "R/cmd_read.R")), info = paste(callers, collapse = ", "))
})

test_that("the read verb is the only verb dispatching to cmd_read", {
  at_root()
  expect_setequal(uses(code_files(), "\\bcmd_read\\s*\\("), "run.R")
})
