# Run folders: every run of a pipeline step writes runs/<step>/<YYYY-MM-DD>_<label>/
# with run.json (provenance), config/ (copies of the config used), metrics.json
# and README.md. These are committed; large intermediate files go to
# data/runs/<step>/<run id>/.

RUNS_DIR <- "runs"
RUN_STEPS <- c("gbif", "search", "match", "read")
LABEL_RE <- "^[a-z0-9]+(-[a-z0-9]+)*$"

git_head <- function() {
  sha <- suppressWarnings(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE,
                                  stderr = FALSE))
  if (!length(sha)) stop("Not a git repository, or git is not available")
  dirty <- suppressWarnings(system2("git", c("status", "--porcelain", "--untracked-files=no"),
                                    stdout = TRUE, stderr = FALSE))
  list(commit = sha[1], dirty = length(dirty) > 0)
}

sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' Start a run: create its folder, copy the config files and write run.json.
#' Refuses to reuse an existing folder (pick another label).
run_start <- function(step, label, args = character(),
                      config_files = "config/scope.yaml", date = Sys.Date()) {
  if (!step %in% RUN_STEPS) stop("Unknown step '", step, "'; one of ", paste(RUN_STEPS, collapse = ", "))
  if (!grepl(LABEL_RE, label)) stop("Label must be lower-case letters, digits and '-': ", label)
  id <- sprintf("%s_%s", format(date, "%Y-%m-%d"), label)
  dir <- file.path(RUNS_DIR, step, id)
  if (dir.exists(dir)) stop("Run folder exists: ", dir, ". Use another label.", call. = FALSE)
  dir.create(file.path(dir, "config"), recursive = TRUE)
  for (f in config_files) file.copy(f, file.path(dir, "config", basename(f)))
  g <- git_head()
  run <- list(step = step, label = label, id = id, dir = dir,
              verb_args = as.list(args),
              git_commit = g$commit, git_dirty = g$dirty,
              goldset_sha256 = sha256_file(GOLDSET_FILE),
              started_at = utc_now(), finished_at = NULL,
              data_dir = file.path("data", "runs", step, id))
  .write_json(run[setdiff(names(run), "dir")], file.path(dir, "run.json"))
  run
}

#' Finish a run: write metrics.json and README.md, set finished_at.
run_finish <- function(run, metrics, readme_body) {
  run$finished_at <- utc_now()
  .write_json(run[setdiff(names(run), "dir")], file.path(run$dir, "run.json"))
  .write_json(metrics, file.path(run$dir, "metrics.json"))
  head <- c(sprintf("# %s run `%s`", run$step, run$id), "",
            md_table(data.frame(
              item = c("started", "finished", "git commit", "goldset.csv SHA-256", "local files"),
              value = c(run$started_at, run$finished_at,
                        paste0("`", run$git_commit, "`", if (isTRUE(run$git_dirty)) " + uncommitted changes" else ""),
                        paste0("`", substr(run$goldset_sha256, 1, 12), "`"),
                        paste0("`", run$data_dir, "/`"))), align = "l"),
            "")
  writeLines(c(head, readme_body), file.path(run$dir, "README.md"), useBytes = TRUE)
  invisible(run)
}

.write_json <- function(x, path) {
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null",
                              na = "null", digits = NA), path, useBytes = TRUE)
}

#' All runs, one row each, sorted by step and id.
runs_index <- function(root = RUNS_DIR) {
  files <- sort(Sys.glob(file.path(root, "*", "*", "run.json")))
  if (!length(files)) {
    return(data.frame(step = character(), id = character(), dir = character(),
                      started_at = character(), finished_at = character(),
                      git_commit = character(), goldset_sha256 = character(),
                      metrics = character()))
  }
  rows <- lapply(files, function(f) {
    r <- jsonlite::fromJSON(f, simplifyVector = TRUE)
    mf <- file.path(dirname(f), "metrics.json")
    m <- if (file.exists(mf)) jsonlite::fromJSON(mf, simplifyVector = TRUE) else list()
    scalars <- m[vapply(m, function(v) is.atomic(v) && length(v) == 1, logical(1))]
    data.frame(step = r$step, id = r$id, dir = dirname(f),
               started_at = r$started_at %||% "", finished_at = r$finished_at %||% "",
               git_commit = r$git_commit %||% "", goldset_sha256 = r$goldset_sha256 %||% "",
               metrics = paste(sprintf("%s = %s", names(scalars), unlist(scalars)), collapse = "; "))
  })
  out <- do.call(rbind, rows)
  out[order(out$step, out$id), ]
}

#' Latest run of a step (by id, which starts with the date), or NULL.
latest_run <- function(step, root = RUNS_DIR, require_file = NULL) {
  idx <- runs_index(root)
  idx <- idx[idx$step == step & nzchar(idx$finished_at), ]
  if (!is.null(require_file)) idx <- idx[file.exists(file.path(idx$dir, require_file)), ]
  if (!nrow(idx)) return(NULL)
  idx[nrow(idx), ]
}
