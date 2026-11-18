# Check goldset/fulltext/ against goldset/fulltext_manifest.csv.
#
# This is the ONLY script allowed to reference goldset/fulltext/ (CLAUDE.md,
# "Gold-set full texts"; enforced by tests/testthat/test-fulltext-isolation.R).
# It reads the files as bytes to compute SHA-256 and never parses their content.
#
# - Rows are matched on SHA-256, not on file name.
# - A hash match under a different name updates `file` to the name on disk.
# - Files not in the manifest are added only if listed in ADDITIONS below;
#   anything else is reported and the script exits with status 1.
# - Manifest rows whose hash is not on disk are reported and kept.
#
# Usage: Rscript scripts/goldset_fulltext_manifest.R [--dry-run]

source("R/validate.R")
source("R/goldset.R")

FULLTEXT_DIR <- "goldset/fulltext"
MANIFEST_FILE <- "goldset/fulltext_manifest.csv"
dry_run <- "--dry-run" %in% commandArgs(trailingOnly = TRUE)

# Files Anders has identified but that were missing from the manifest.
# Matched on a file-name pattern so Unicode normalisation of "å" does not matter.
# Added 2026-11-18 on Anders' instruction.
ADDITIONS <- data.frame(
  pattern    = c("^2019_Vannoverv", "^2020_Vannoverv", "^2023_Vannoverv"),
  survey_ref = c("trd-bunndyr-2019", "trd-bunndyr-2020", "trd-bunndyr-2023"),
  role       = "summary",
  document   = c("Vannovervåking i Trondheim 2019 (TM 2020/01)",
                 "Vannovervåking i Trondheim 2020 (TM 2021/01)",
                 "Vannovervåking i Trondheim 2023 (versjon 2)")
)

# ---- hash files on disk ------------------------------------------------------
files <- sort(list.files(FULLTEXT_DIR, all.files = FALSE, no.. = TRUE))
files <- files[!dir.exists(file.path(FULLTEXT_DIR, files))]
disk <- data.frame(
  file   = files,
  sha256 = vapply(file.path(FULLTEXT_DIR, files), digest::digest, "", algo = "sha256", file = TRUE,
                  USE.NAMES = FALSE),
  bytes  = as.integer(file.size(file.path(FULLTEXT_DIR, files)))
)
cat(sprintf("%d files in %s\n", nrow(disk), FULLTEXT_DIR))

man <- readr::read_csv(MANIFEST_FILE, col_types = readr::cols(.default = "c"), na = character())
man$bytes <- as.integer(man$bytes)
cat(sprintf("%d rows in %s\n\n", nrow(man), MANIFEST_FILE))

issues <- character()
note <- function(...) issues <<- c(issues, sprintf(...))

# ---- duplicates --------------------------------------------------------------
if (any(duplicated(disk$sha256))) {
  note("Identical files on disk: %s", paste(disk$file[duplicated(disk$sha256) |
         duplicated(disk$sha256, fromLast = TRUE)], collapse = ", "))
}
if (any(duplicated(man$sha256))) note("Duplicated sha256 in manifest")

# ---- match on hash -----------------------------------------------------------
idx <- match(man$sha256, disk$sha256)
renamed <- 0L
for (i in seq_len(nrow(man))) {
  j <- idx[i]
  if (is.na(j)) {
    note("In manifest, no file with this hash on disk: %s (%s)", man$file[i], man$sha256[i])
    next
  }
  if (!identical(man$bytes[i], disk$bytes[j])) {
    note("Byte count differs for %s: manifest %d, disk %d", disk$file[j], man$bytes[i], disk$bytes[j])
  }
  if (!identical(enc2utf8(man$file[i]), enc2utf8(disk$file[j]))) {
    cat(sprintf("rename  %-55s -> %s\n", man$file[i], disk$file[j]))
    man$file[i] <- disk$file[j]
    renamed <- renamed + 1L
  }
}

# ---- files on disk missing from the manifest ---------------------------------
missing <- disk[!disk$sha256 %in% man$sha256, ]
added <- 0L
for (k in seq_len(nrow(missing))) {
  hit <- which(vapply(ADDITIONS$pattern, grepl, logical(1), x = missing$file[k]))
  if (length(hit) != 1) {
    note("On disk, not in manifest and no mapping given: %s", missing$file[k])
    next
  }
  a <- ADDITIONS[hit, ]
  man <- rbind(man, data.frame(file = missing$file[k], sha256 = missing$sha256[k],
                               bytes = missing$bytes[k], survey_ref = a$survey_ref,
                               role = a$role, document = a$document))
  cat(sprintf("add     %-55s -> %s (%s)\n", missing$file[k], a$survey_ref, a$role))
  added <- added + 1L
}

# ---- consistency with the gold set ------------------------------------------
if (file.exists(GOLDSET_FILE)) {
  refs <- unique(unlist(strsplit(man$survey_ref, ";", fixed = TRUE)))
  unknown <- setdiff(refs, read_goldset()$survey_ref)
  if (length(unknown)) note("survey_ref not in goldset.csv: %s", paste(unknown, collapse = ", "))
}

bad <- validate_records(df_rows(man), "fulltext_manifest_row", id_field = "file")
for (r in seq_len(nrow(bad))) note("Schema: [%s] %s", bad$id[r], bad$errors[r])

# ---- write and report --------------------------------------------------------
cat(sprintf("\n%d renamed, %d added, %d rows in manifest\n", renamed, added, nrow(man)))
if (!dry_run && (renamed + added) > 0) {
  man <- man[order(man$survey_ref, man$role, man$file), ]
  readr::write_csv(man, MANIFEST_FILE, na = "")
  cat("Wrote", MANIFEST_FILE, "\n")
}
if (length(issues)) {
  cat("\nIssues:\n", paste0("  - ", issues, "\n"), sep = "")
  quit(status = 1)
}
cat("No issues.\n")
