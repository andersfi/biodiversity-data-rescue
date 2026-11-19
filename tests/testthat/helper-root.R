# Tests run from tests/testthat; the code uses paths relative to the project root.
ROOT <- normalizePath(file.path(testthat::test_path(), "..", ".."))
at_root <- function(env = parent.frame()) withr::local_dir(ROOT, .local_envir = env)

local({
  withr::local_dir(ROOT)
  for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) {
    sys.source(f, envir = globalenv())
  }
})
