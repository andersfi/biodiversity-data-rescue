# biodiversity-data-rescue

Find professional biological surveys described in scientific and grey literature,
record them in a register, and determine whether their data are in GBIF, partly in
GBIF, available elsewhere, or not available.

Pilot: EPT taxa (Ephemeroptera, Plecoptera, Trichoptera) in Trondheim kommune.
The pipeline has three links, measured separately against the gold set:
**find** (does search find the document?), **read** (are the right fields
extracted?) and **match** (given a correct description, is the GBIF status
right?). Design, data model and decision log: [`docs/design.md`](docs/design.md).

**Current state:** [runs/README.md](runs/README.md) (all runs) ·
[gold set and sources](runs/goldset/README.md) ·
[worklist](runs/goldset/worklist.md)

## Three zones

| Zone | Folders | Who changes it |
|---|---|---|
| **Edit** | `config/` (scope, LLM settings), `goldset/goldset.csv` (the only answer key), `goldset/stations.csv`, `goldset/fulltext_manifest.csv`, `protocol/`, `knowledge/` | Anders |
| **Code** | `run.R`, `R/`, `prompts/`, `schemas/`, `db/`, `tests/` | code changes, reviewed |
| **Generated** | `runs/` (committed: run folders, reports, query log) and `data/` (local only: raw API responses, LLM batches, register) | only by `run.R` |

`goldset/archive/` keeps the original candidate files for provenance; no code reads
them. `goldset/fulltext/` holds local copies of gold-set reports (never committed).

## Verbs

```
Rscript run.R                      help
Rscript run.R status               gold-set state, latest run per step, suggested next step
Rscript run.R check                validate gold set, manifest, knowledge cards; write the worklist
Rscript run.R gbif [label]         GBIF baseline + survey groups for the scope (network)
Rscript run.R match [label]        match gold-set surveys against GBIF (config/match.yaml)
Rscript run.R read [label]         reading test on the local full texts       (phase 3)
Rscript run.R read manifest        SHA-256 check of the local full texts
Rscript run.R report               rebuild runs/README.md and runs/goldset/
```

Each run of `gbif`, `match`, `read` (and later search) writes
`runs/<step>/<YYYY-MM-DD>_<label>/` with `run.json` (git commit, SHA-256 of the
gold set, times), `config/` (copies of the config used), `metrics.json` and a short
`README.md`. Large intermediate files go to `data/runs/<step>/<id>/`.

## Workflow

1. Edit `goldset/goldset.csv` (or `config/`, `knowledge/`).
2. `Rscript run.R check`: fix anything it reports; the worklist shows what is open.
3. `Rscript run.R match` (or `read`): one new run folder per run.
4. `Rscript run.R report`: compare the new run with earlier ones in `runs/README.md`.

## Setup

R 4.5 with renv: `renv::restore()`. Tests:
`Rscript -e 'testthat::test_dir("tests/testthat")'`.
