# Local gold-set full texts (Anders' copies of the reports).
#
# The ONLY code file allowed to reference goldset/fulltext/, and its functions
# may only be called from the `read` verb (R/cmd_read.R). Search and screening
# never read these files. Both rules are enforced by
# tests/testthat/test-fulltext-isolation.R (decision 2026-11-19, docs/design.md).

FULLTEXT_DIR <- "goldset/fulltext"

# Files Anders has identified but that were missing from the manifest.
# Matched on a file-name pattern so Unicode normalisation of "å" does not matter.
# Added 2026-11-18 on Anders' instruction.
FULLTEXT_ADDITIONS <- data.frame(
  pattern    = c("^2019_Vannoverv", "^2020_Vannoverv", "^2023_Vannoverv"),
  survey_ref = c("trd-bunndyr-2019", "trd-bunndyr-2020", "trd-bunndyr-2023"),
  role       = "summary",
  document   = c("Vannovervåking i Trondheim 2019 (TM 2020/01)",
                 "Vannovervåking i Trondheim 2020 (TM 2021/01)",
                 "Vannovervåking i Trondheim 2023 (versjon 2)")
)

#' Check the local full texts against the manifest by SHA-256. Files are read
#' as bytes only; their content is never parsed here.
#'
#' - Rows are matched on SHA-256, not on file name.
#' - A hash match under a different name updates `file` to the name on disk.
#' - Files not in the manifest are added only if FULLTEXT_ADDITIONS maps them.
#' - Manifest rows whose hash is not on disk are reported and kept.
#'
#' Returns list(manifest, issues, renamed, added). Writes nothing.
fulltext_manifest_check <- function(man = read_manifest(), dir = FULLTEXT_DIR,
                                    additions = FULLTEXT_ADDITIONS) {
  files <- sort(list.files(dir, all.files = FALSE, no.. = TRUE))
  files <- files[!dir.exists(file.path(dir, files))]
  disk <- data.frame(
    file   = files,
    sha256 = vapply(file.path(dir, files), digest::digest, "", algo = "sha256", file = TRUE,
                    USE.NAMES = FALSE),
    bytes  = as.integer(file.size(file.path(dir, files))))
  issues <- character()
  note <- function(...) issues <<- c(issues, sprintf(...))

  if (any(duplicated(disk$sha256))) {
    note("Identical files on disk: %s", paste(disk$file[duplicated(disk$sha256) |
           duplicated(disk$sha256, fromLast = TRUE)], collapse = ", "))
  }
  if (any(duplicated(man$sha256))) note("Duplicated sha256 in manifest")

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
      man$file[i] <- disk$file[j]
      renamed <- renamed + 1L
    }
  }

  missing <- disk[!disk$sha256 %in% man$sha256, ]
  added <- 0L
  for (k in seq_len(nrow(missing))) {
    hit <- which(vapply(additions$pattern, grepl, logical(1), x = missing$file[k]))
    if (length(hit) != 1) {
      note("On disk, not in manifest and no mapping given: %s", missing$file[k])
      next
    }
    a <- additions[hit, ]
    man <- rbind(man, data.frame(file = missing$file[k], sha256 = missing$sha256[k],
                                 bytes = missing$bytes[k], survey_ref = a$survey_ref,
                                 role = a$role, document = a$document))
    added <- added + 1L
  }
  list(manifest = man, n_files = nrow(disk), issues = issues, renamed = renamed, added = added)
}
