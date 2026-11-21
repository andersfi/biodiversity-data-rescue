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

FULLTEXT_PAGES_DIR <- "data/read/pages"

#' Page texts of the local full texts, one row per document x page.
#'
#' Runs `pdftotext -layout` (poppler) once per file and splits on form feeds.
#' Output is cached under data/read/pages/<sha256>/ (local, never committed),
#' keyed on the file's SHA-256, so a changed file is extracted again.
#' The manifest's SHA-256 is checked against the file before extracting.
#'
#' Returns data.frame(sha256, file, page, text).
fulltext_pages <- function(man = read_manifest(), dir = FULLTEXT_DIR,
                           cache = FULLTEXT_PAGES_DIR) {
  if (!nzchar(Sys.which("pdftotext"))) stop("pdftotext (poppler-utils) not found", call. = FALSE)
  man <- man[!duplicated(man$sha256), ]
  out <- lapply(seq_len(nrow(man)), function(i) {
    path <- file.path(dir, man$file[i])
    if (!file.exists(path)) stop("Full text missing on disk: ", man$file[i], call. = FALSE)
    cdir <- file.path(cache, man$sha256[i])
    txt <- file.path(cdir, "fulltext.txt")
    if (!file.exists(txt)) {
      sha <- digest::digest(path, algo = "sha256", file = TRUE)
      if (!identical(sha, man$sha256[i])) {
        stop("SHA-256 of ", man$file[i], " differs from the manifest; run `run.R read manifest`",
             call. = FALSE)
      }
      dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
      status <- system2("pdftotext", c("-layout", "-enc", "UTF-8", shQuote(path), shQuote(txt)),
                        stdout = FALSE, stderr = FALSE)
      if (status != 0 || !file.exists(txt)) stop("pdftotext failed on ", man$file[i], call. = FALSE)
    }
    raw <- readChar(txt, file.size(txt), useBytes = TRUE)
    Encoding(raw) <- "UTF-8"
    # pdftotext ends every page with a form feed; strsplit drops a trailing
    # empty field, so blank last pages are padded back from pdfinfo's count.
    pages <- strsplit(raw, "\f", fixed = TRUE)[[1]]
    n_pdf <- .pdf_page_count(path)
    if (length(pages) < n_pdf) pages <- c(pages, rep("", n_pdf - length(pages)))
    if (length(pages) != n_pdf) {
      stop(sprintf("%s: %d text pages but pdfinfo reports %d", man$file[i], length(pages), n_pdf),
           call. = FALSE)
    }
    data.frame(sha256 = man$sha256[i], file = man$file[i], page = seq_along(pages), text = pages)
  })
  do.call(rbind, out)
}

.pdf_page_count <- function(path) {
  info <- system2("pdfinfo", shQuote(path), stdout = TRUE, stderr = FALSE)
  n <- as.integer(sub("^Pages:\\s+", "", grep("^Pages:", info, value = TRUE)))
  if (length(n) != 1 || is.na(n)) stop("pdfinfo gave no page count for ", path, call. = FALSE)
  n
}
