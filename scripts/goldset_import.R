# One-off: build goldset/goldset.csv from the candidate file Anders supplied and
# validate every row against schemas/goldset_row.json.
# Usage: Rscript scripts/goldset_import.R [candidate_csv]
# Refuses to overwrite an existing goldset.csv unless --force is given.

source("R/validate.R")
source("R/goldset.R")

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
args <- setdiff(args, "--force")
src <- if (length(args)) args[[1]] else "goldset/goldset_candidates_trondheim_bunndyr.csv"

if (file.exists(GOLDSET_FILE) && !force) {
  stop(GOLDSET_FILE, " exists. Use --force to rebuild it from ", src, call. = FALSE)
}

cand <- read_goldset(src)
gs <- normalise_goldset(cand)

changed <- vapply(c("expected_status", "found_via"), function(col) {
  sum(cand[[col]] != gs[[col]])
}, integer(1))
cat(sprintf("Read %d rows from %s\n", nrow(cand), src))
cat("Normalised values:", paste(names(changed), changed, sep = "=", collapse = ", "), "\n")

bad <- validate_goldset(gs)
write_goldset(gs)
cat("Wrote", GOLDSET_FILE, "\n")
if (nrow(bad)) {
  cat(sprintf("\n%d invalid rows:\n", nrow(bad)))
  cat(sprintf("  [%s] %s\n", bad$id, bad$errors), sep = "")
  quit(status = 1)
}
cat("All", nrow(gs), "rows valid against schemas/goldset_row.json\n")
print(table(expected_status = gs$expected_status, include = gs$include))
