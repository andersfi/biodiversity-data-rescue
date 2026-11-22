# biodiversity-data-rescue

A systematic map (CEE style) of Norwegian grey literature that reports field
surveys with primary species data, from management agencies, applied research
institutes and consultancies, and of whether those data are published in GBIF.
Surveys of habitat types or abiotic data only, and documents that only compile
existing data, are out of scope.

## Pipeline

| Step | Script | Output |
|---|---|---|
| 0 GBIF cube | `scripts/00_gbif_cube.R` | `data/gbif/cube.parquet` |
| 1 Search | `scripts/01_search.R` | `document` table |
| 2 Screen | `scripts/02_screen.R` | `screening` table |
| 3 Extract | `scripts/03_extract.R` | `chunk` and `extraction` tables |
| 4 Match | `scripts/04_match.R` | `match` table |

## Current state

Steps 0–3 have run as a pilot on 275 sampled NVA reports; step 4 is not
started. Results and infrastructure needs:
[`docs/pilot-report.md`](docs/pilot-report.md). Step 0 aggregates GBIF
occurrences for Norway and Svalbard/Jan Mayen by dataset, publisher, year,
month, class, order and 5 km cell via the GBIF SQL download API (see the
header of `scripts/00_gbif_cube.R`).

## Layout

`scripts/` one script per step; `R/` functions; `prompts/` and `search/`
model prompts and search terms; `goldset/` gold set of known reports;
`knowledge/` domain notes; `logs/queries.jsonl` query log; `data/` local only
(raw API responses, GBIF cube).

Protocol: [`protocol/protocol.md`](protocol/protocol.md). Background and
decision log: [`docs/design.md`](docs/design.md).

## Setup

R with renv: `renv::restore()`. GBIF credentials `GBIF_USER`, `GBIF_PWD` and
`GBIF_EMAIL` go in `~/.Renviron`.

The earlier pilot code is at git tag `v0-oppsett`.
