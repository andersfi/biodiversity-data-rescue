# Append candidate rows to goldset/goldset.csv after validating them.
# Refuses rows whose survey_ref already exists.
# Usage: Rscript scripts/goldset_append.R <candidates.csv>

source("R/validate.R")
source("R/goldset.R")

src <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(src)) stop("Usage: Rscript scripts/goldset_append.R <candidates.csv>", call. = FALSE)

gs <- read_goldset()
new <- normalise_goldset(read_goldset(src))
dup <- intersect(new$survey_ref, gs$survey_ref)
if (length(dup)) stop("survey_ref already in gold set: ", paste(dup, collapse = ", "), call. = FALSE)

bad <- validate_goldset(rbind(gs, new))
if (nrow(bad)) {
  stop("Invalid rows, nothing written:\n", paste(sprintf("  [%s] %s", bad$id, bad$errors),
                                                 collapse = "\n"), call. = FALSE)
}
write_goldset(rbind(gs, new))
cat(sprintf("Appended %d rows from %s; gold set now has %d rows\n", nrow(new), src, nrow(gs) + nrow(new)))
