# Verb `read`: the reading test on the local gold-set full texts (phase 3,
# not built yet), and `read manifest`, the SHA-256 check of those files.
# The only verb allowed to call the functions in R/fulltext.R.

cmd_read <- function(args) {
  if (length(args) && args[1] == "manifest") return(invisible(cmd_read_manifest(args[-1])))
  stop("`read` is not implemented yet (phase 3: plan in docs/reading-benchmark.md). ",
       "Only `read manifest` works.", call. = FALSE)
}

cmd_read_manifest <- function(args) {
  dry_run <- "--dry-run" %in% args
  gs <- read_goldset()
  res <- fulltext_manifest_check()
  man <- res$manifest
  bad <- validate_manifest(man, gs$survey_ref)
  issues <- res$issues
  if (nrow(bad)) issues <- c(issues, sprintf("Schema: [%s] %s", bad$id, bad$errors))
  cat(sprintf("%d local full texts, %d manifest rows; %d renamed, %d added\n",
              res$n_files, nrow(man), res$renamed, res$added))
  if (!dry_run && (res$renamed + res$added) > 0) {
    man <- man[order(man$survey_ref, man$role, man$file), ]
    readr::write_csv(man, MANIFEST_FILE, na = "")
    cat("Wrote", MANIFEST_FILE, "\n")
  }
  if (length(issues)) {
    cat("Issues:\n", paste0("  - ", issues, "\n"), sep = "")
    quit(status = 1)
  }
  cat("No issues.\n")
}
