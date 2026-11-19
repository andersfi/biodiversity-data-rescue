# Single entry point: Rscript run.R <verb> [args]
# Verbs are documented in README.md and implemented in R/cmd_*.R.

HELP <- "Usage: Rscript run.R <verb> [args]

  status                    gold-set state, latest run per step, suggested next step
  check                     validate gold set, manifest and knowledge cards; write the worklist
  gbif [label]              GBIF baseline and survey groups for the scope -> runs/gbif/ (network)
  match [label]             match gold-set surveys against GBIF -> runs/match/
  read [label]              reading test on local full texts -> runs/read/      (phase 3)
  read manifest [--dry-run] check the local full texts against fulltext_manifest.csv
  report                    rebuild runs/README.md and runs/goldset/

Files you edit: config/, goldset/goldset.csv, goldset/stations.csv, protocol/, knowledge/.
"

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || args[1] %in% c("-h", "--help", "help")) {
  cat(HELP)
  quit(status = 0)
}

for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f)

verb <- args[1]
rest <- args[-1]
switch(verb,
  status = cmd_status(rest),
  check  = cmd_check(rest),
  gbif   = cmd_gbif(rest),
  match  = cmd_match(rest),
  read   = cmd_read(rest),
  report = cmd_report(rest),
  { cat(HELP); stop("Unknown verb: ", verb, call. = FALSE) }
)
