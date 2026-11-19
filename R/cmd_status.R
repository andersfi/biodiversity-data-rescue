# Verb `status`: gold-set state, latest run per step and one suggested next
# step. Reads files only; changes nothing.

cmd_status <- function(args) {
  gs <- read_goldset()
  bad <- validate_goldset(gs)
  inc <- table(factor(gs$include, levels = c("yes", "candidate", "no")))
  n_todo <- sum(gs$expected_status == "todo")
  cat(sprintf("Gold set  %d rows: include yes %d / candidate %d / no %d; expected_status todo %d%s\n",
              nrow(gs), inc[["yes"]], inc[["candidate"]], inc[["no"]], n_todo,
              if (nrow(bad)) sprintf("; %d VALIDATION ERRORS", nrow(bad)) else ""))
  cat(sprintf("          goldset.csv SHA-256 %s\n\n", substr(sha256_file(GOLDSET_FILE), 1, 12)))

  cat("Latest run per step\n")
  latest <- lapply(RUN_STEPS, latest_run)
  names(latest) <- RUN_STEPS
  for (s in RUN_STEPS) {
    r <- latest[[s]]
    cat(sprintf("  %-7s %s\n", s, if (is.null(r)) "not run" else
      sprintf("%s  (commit %s)  %s", r$id, r$git_commit, r$metrics)))
  }
  cat("\nNext: ", status_next_step(nrow(bad), inc[["yes"]], latest), "\n", sep = "")
}

#' One suggested next step, from the first unmet condition.
status_next_step <- function(n_invalid, n_yes, latest) {
  if (n_invalid > 0) return("fix goldset.csv, then `Rscript run.R check`")
  if (is.null(latest$gbif)) return("`Rscript run.R gbif` (GBIF records for the scope)")
  if (n_yes == 0) return(paste("verify rows in goldset.csv and set include = yes",
                               "(see runs/goldset/worklist.md); then `Rscript run.R check`"))
  if (is.null(latest$match)) return("`Rscript run.R match` (match gold-set surveys against GBIF)")
  "`Rscript run.R report`, then compare runs in runs/README.md"
}
