# OCR for PDFs without a text layer: pdftoppm renders each page, tesseract
# reads it. The text goes to <identifier>.ocr.txt next to the PDF, with a form
# feed after each page (the shape of `pdftotext -layout` output), and the timing
# to <identifier>.ocr.json.

OCR_DPI <- 300
OCR_LANG <- "nor+eng"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Path of the OCR text (and its timing sidecar) for a PDF.
ocr_txt_path <- function(pdf) sub("\\.pdf$", ".ocr.txt", pdf, ignore.case = TRUE)
ocr_json_path <- function(pdf) sub("\\.pdf$", ".ocr.json", pdf, ignore.case = TRUE)

#' Number of pages from pdfinfo.
pdf_n_pages <- function(pdf) {
  out <- suppressWarnings(system2("pdfinfo", shQuote(pdf), stdout = TRUE, stderr = TRUE))
  if ((attr(out, "status") %||% 0L) != 0) stop("pdfinfo failed on ", pdf, ": ",
                                              paste(out, collapse = " "))
  n <- as.integer(sub("^Pages:\\s+", "", grep("^Pages:", out, value = TRUE)))
  if (length(n) != 1 || is.na(n) || n < 1) stop("No page count from pdfinfo for ", pdf)
  n
}

#' OCR one page. Returns list(text, cpu_seconds, wall_seconds). CPU time is the
#' user + system time of the two child processes. Errors when either fails.
ocr_page <- function(pdf, page, work_dir) {
  t0 <- proc.time()
  prefix <- file.path(work_dir, sprintf("p%05d", page))
  out <- suppressWarnings(system2("pdftoppm", c("-r", OCR_DPI, "-gray", "-png", "-singlefile",
                                                "-f", page, "-l", page, shQuote(pdf),
                                                shQuote(prefix)),
                                  stdout = TRUE, stderr = TRUE))
  if ((attr(out, "status") %||% 0L) != 0) {
    stop(sprintf("pdftoppm failed on page %d: %s", page, paste(out, collapse = " ")))
  }
  png <- paste0(prefix, ".png")
  on.exit(unlink(png))
  if (!file.exists(png)) stop(sprintf("pdftoppm wrote no image for page %d", page))
  err <- paste0(prefix, ".err")
  on.exit(unlink(err), add = TRUE)
  txt <- suppressWarnings(system2("tesseract", c(shQuote(png), "stdout", "-l", OCR_LANG),
                                  stdout = TRUE, stderr = err,
                                  env = "OMP_THREAD_LIMIT=1"))
  if ((attr(txt, "status") %||% 0L) != 0) {
    stop(sprintf("tesseract failed on page %d: %s", page,
                 paste(readLines(err, warn = FALSE), collapse = " ")))
  }
  t1 <- proc.time()
  d <- t1 - t0
  list(text = paste(enc2utf8(txt), collapse = "\n"),
       cpu_seconds = unname(d["user.child"] + d["sys.child"]),
       wall_seconds = unname(d["elapsed"]))
}

#' OCR all pages of a PDF in parallel and write the .ocr.txt and .ocr.json
#' files. Any page failure stops the document (no file is written). Returns the
#' timing list that is also written to the .ocr.json.
ocr_pdf <- function(pdf, cores) {
  n <- pdf_n_pages(pdf)
  work_dir <- tempfile("ocr-")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE))
  t0 <- Sys.time()
  res <- parallel::mclapply(seq_len(n), function(p) ocr_page(pdf, p, work_dir),
                            mc.cores = cores, mc.preschedule = FALSE)
  wall <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  bad <- vapply(res, function(r) inherits(r, "try-error") || is.null(r$text), logical(1))
  if (any(bad)) {
    msg <- vapply(res[bad], function(r) if (inherits(r, "try-error")) as.character(r)
                  else "worker returned nothing", "")
    stop(sprintf("OCR failed on %d of %d pages: %s", sum(bad), n, trimws(msg[1])))
  }
  text <- vapply(res, `[[`, "", "text")
  txt_path <- ocr_txt_path(pdf)
  tmp <- paste0(txt_path, ".part")
  con <- file(tmp, open = "w", encoding = "UTF-8")
  writeLines(paste0(text, "\f"), con, sep = "")
  close(con)
  timing <- list(pages = n, cores = cores, seconds = wall,
                 cpu_seconds = vapply(res, `[[`, 0, "cpu_seconds"),
                 page_wall_seconds = vapply(res, `[[`, 0, "wall_seconds"),
                 dpi = OCR_DPI, lang = OCR_LANG,
                 tesseract = system2("tesseract", "--version", stdout = TRUE)[1],
                 made_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  jsonlite::write_json(timing, ocr_json_path(pdf), auto_unbox = TRUE, digits = NA, pretty = TRUE)
  file.rename(tmp, txt_path)
  timing
}
