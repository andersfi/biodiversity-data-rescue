# biodiversity-data-rescue

Find professional biological surveys described in scientific and grey literature
and data repositories, record them in a register, and determine whether their data
are in GBIF, partly in GBIF, available elsewhere, or not available.

Pilot: EPT taxa (Ephemeroptera, Plecoptera, Trichoptera) in Trondheim kommune.
Scope lives in `config/scope.yaml`; design, data model and decision log in
`docs/design.md`; working rules in `CLAUDE.md`.

## Setup

R 4.5 with renv:

```r
renv::restore()
```

## Scripts

| Command | What it does |
|---|---|
| `Rscript scripts/00_build_db.R` | Build the SQLite register (`data/register.sqlite`) from `db/schema.sql` |
| `Rscript scripts/01_load_knowledge.R` | Validate knowledge cards in `knowledge/` and load them |
| `Rscript scripts/02_gbif_baseline.R` | GBIF records per dataset for the scope; writes `reports/gbif_baseline_*.tsv` and a comparison with the reference table |
| `Rscript scripts/03_gbif_fetch_survey_records.R` | Fetch scope records from the NTNU benthic and Vannmiljø datasets and group them by survey |
| `Rscript scripts/goldset_import.R` | Build `goldset/goldset.csv` from a candidate file and validate it |
| `Rscript scripts/goldset_append.R <csv>` | Validate candidate rows and append them to the gold set |
| `Rscript scripts/goldset_fulltext_manifest.R` | Check the local gold-set full texts against `goldset/fulltext_manifest.csv` by SHA-256 |
| `Rscript -e 'testthat::test_dir("tests/testthat")'` | Run the tests |

## Layout

`config/` scope and LLM settings · `goldset/` gold set, manifest, reference tables ·
`knowledge/` domain knowledge cards · `schemas/` JSON Schemas · `prompts/` LLM prompts ·
`R/` functions · `scripts/` pipeline steps · `db/` register schema · `logs/` query log ·
`reports/` outputs · `data/` local only (raw API responses, LLM batches, register).

Full texts in `goldset/fulltext/` are local only and are never read by the pipeline.
