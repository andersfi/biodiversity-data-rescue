# biodiversity-data-rescue

Find professional biological surveys described in scientific literature, grey
literature and data repositories, record them in a structured register, and
determine whether their data are published in GBIF, partly published, available
elsewhere, or not available.

Owner: Anders G. Finstad (NTNU, Gjærevollsenteret). Public repo on the personal
GitHub account `andersfi` during the pilot; it will move to an organisation later.
Everything committed is public: no full texts, no long quotes, no secrets.

Design background, data model, status categories, literature and the decision
log are in `docs/design.md`. Read it before changing structure.

## Current phase: pilot

1. Build a verification set (gold set) in a limited taxonomic and geographic scope:
   surveys we know are in GBIF, partly in GBIF, available elsewhere, not available,
   plus borderline and negative cases.
2. Build a minimal pipeline (search → screening → extraction → GBIF comparison)
   and measure it against the gold set.
3. Expand scope gradually.

Scope lives in `config/scope.yaml` and will change. Never hard-code taxa, regions
or periods. Do not run large searches or LLM batches before Anders has approved
the scope and the gold set.

## Working with Anders

- He writes Norwegian; answer in Norwegian (bokmål). Code, comments, file names,
  identifiers and commit messages are in English.
- He is a domain expert (GBIF, Darwin Core, freshwater surveys) and reads R best.
  Explain design choices briefly; skip basics.
- Ask before: `sudo`; deleting or overwriting anything outside `data/`; changing
  the database schema; adding a data source, an LLM provider or any service that
  receives data (the read-only APIs in `docs/design.md` are fine).
- Structural redesign decisions go back to Anders. When a decision is made, add it
  to the decision log at the end of `docs/design.md` and update this file if needed.

## Git and attribution (hard rule)

- Never list Claude or any AI as author, co-author or contributor. No
  `Co-Authored-By` lines and no "Generated with Claude Code" in commits or PRs.
  Anders is the sole author; he declares AI use himself.
- Small commits with descriptive English messages.
- Never commit `data/`, `.env`, API keys, PDFs or other full texts.

## Stack

- R 4.5 with renv. Packages: ellmer (LLM), DBI + RSQLite (register), duckdb
  (GBIF analyses), httr2 (APIs), rgbif, openalexR, yaml, jsonlite, jsonvalidate
  (JSON Schema), digest (hashes), dplyr, purrr, readr, testthat.
- R packages compile from source on this laptop. A failed install usually means a
  missing system `-dev` library: find it, then ask Anders before `sudo apt install`.
- IPv6 can hang on this machine. `~/.curlrc` only fixes the curl CLI, not R. If an
  httr2 request hangs, force IPv4 (e.g. `req_options(ipresolve = 1)`).
- Python only where R has no reasonable option (e.g. GROBID or Docling for PDFs
  later), in a project venv.
- Quarto is not installed; ask before adding reports that need it.

## Repository layout

```
config/          scope.yaml (taxa, region, period, sources), llm.yaml (backend, models)
protocol/        inclusion criteria and scope decisions (markdown)
goldset/         goldset.csv: known surveys with expected status
  fulltext/      local only, in .gitignore: Anders' copies of the gold-set reports
  fulltext_manifest.csv   in git: file, sha256, bytes, survey_ref, role, document
knowledge/       domain knowledge cards (markdown + YAML front matter)
  aggregators/   shared datasets such as Vannmiljø and what they cover
  sources/       where report series live and how to search them
  precedents/    decided borderline cases with reasons
  vocabulary/    synonyms for methods, taxa and places
prompts/         one prompt file per LLM step
schemas/         JSON Schema per LLM step, gold set row and knowledge card
R/               functions (db.R, llm.R, sources_*.R, ...)
scripts/         one script per pipeline step, numbered
db/schema.sql    the register is built from this
logs/            query log (small, in git) so raw data can be re-fetched
reports/         summaries and figures
docs/design.md   design notes and decision log
data/            local only, in .gitignore
  raw/           API responses as received, PDFs
  llm_in/        batches to the model
  llm_out/       answers from the model
  register.sqlite
```

## Architecture rules

1. All LLM calls go through `R/llm.R`. Nothing else talks to a model.
2. All database access goes through named functions in `R/db.R`. No SQL elsewhere.
3. Every LLM answer is validated against its JSON Schema before it touches the
   database. Invalid answers raise an error; they are not repaired silently.
4. Every LLM batch is logged in `run_log`: backend, provider, model and version,
   prompt file and its SHA-256, schema version, number of records, input and
   output tokens (NA if unknown), timestamp.
5. Never assess the same record twice. Cache key: record URI + SHA-256 of the
   content sent + schema version. Re-runs send only new or changed records.
6. Every entity has a stable URI (`doi:…`, `handle:…`, `survey:<slug>`,
   `gbif-dataset:<key>`) besides its integer id, so the register can be exported
   to a knowledge graph.
7. Explicit failure. No silent fallbacks and no catch-and-continue over API
   errors. Check fetched counts against the totals the API reports.
8. The model is never a search engine. Records come only from API results; the
   model writes queries and reads records.
9. "not_stated" is always an allowed value in extraction schemas. The model must
   not fill in values the source does not give.
10. Prompts live as files in `prompts/`, versioned by git, never only in the DB.
11. Use the smallest model that passes the gold set. Large models only for design
    work (query plans, schemas). Send only the knowledge cards relevant to a batch,
    and only the relevant pages of a full text.

## LLM file contract

- A script writes `data/llm_in/<step>_<batch>.jsonl`: one record per line with
  `uri`, the text fields, `schema_version` and `prompt_file`.
- The answer is `data/llm_out/<step>_<batch>.jsonl`: same `uri`s, fields per
  `schemas/<step>.json`, plus `backend`, `model`, `answered_at`.
- `R/llm.R` offers two backends behind one interface; import and validation are
  identical for both:
  - `claude_code` (pilot): Claude Code itself answers the batch file.
  - `ellmer` (later): calls the provider in `config/llm.yaml` —
    `chat_anthropic()`, `chat_openai_compatible()` for NTNU's API or a local
    server, or `chat_ollama()`.

When you act as the `claude_code` backend: follow the prompt file exactly, answer
only from the record and the knowledge cards supplied with the batch, use
`not_stated` when the source is silent, write valid JSONL, and report the model
you ran as.

## Data policy

- `data/` stays local. Raw API responses are kept as received, with the query and
  timestamp also written to `logs/queries.jsonl`.
- Full texts are copyrighted: never commit them, and quote only short passages
  with page numbers.
- The text-and-data-mining exception for research is not confirmed in force in
  Norway (see `docs/design.md`). Ask before bulk full-text harvesting.
- `.gitignore` contains at least: `data/`, `goldset/fulltext/`, `.env`, `*.pdf`,
  `.Rhistory`, `.RData`, `renv/library/`.

## Gold-set full texts

`goldset/fulltext/` holds reports Anders has supplied for the gold set. They are
there so we can check results by hand, not so the pipeline can find them.

- The pipeline never reads `goldset/fulltext/` in search, screening or
  extraction. Every candidate must come from an API result. If the pipeline
  could see these files, recall against the gold set would mean nothing.
- Allowed uses: checking a gold-set row by hand (stations, dates, methods, data
  statements), and comparing extraction output with the report after a run.
- `goldset/fulltext_manifest.csv` links each file to its gold-set row by
  `survey_ref` (several refs separated by `;`) and `role` (`primary`, `summary`,
  `cites`). The SHA-256 shows whether the pipeline later fetched the same file
  from the source. Update the manifest when files are added; never commit the
  files.

## Reference: the old MVP

`~/projects/biodiversity-data-finder-old` (Python, June 2026). Port ideas, not code:

- the architecture rules above (from its `claude.md`)
- `provenance.json` next to every downloaded file (`core.py::download_search`)
- bounded inspection of a dataset: README plus the first rows of the first
  CSV/TSV, at most 64 KB (`zenodo.py::fetch_assessment_payload`); useful for
  checking datasets that are "available elsewhere"
- JSON-LD export of the register (`cli.py::_export_jsonld`)

Do not port: free-text criteria generation, Zenodo-only search (DataCite covers
Zenodo), the single DwC-readiness score, the reticulate wrapper, its `.env`.

## Commands

- `Rscript scripts/00_build_db.R`: build the register from `db/schema.sql`
- `Rscript scripts/01_load_knowledge.R`: validate and load knowledge cards
- `Rscript scripts/02_gbif_baseline.R`: GBIF baseline for the scope, compared with
  `goldset/reference/`
- `Rscript scripts/03_gbif_fetch_survey_records.R`: fetch and group records from the
  NTNU benthic and Vannmiljø datasets
- `Rscript scripts/goldset_import.R` / `scripts/goldset_append.R <csv>`: build or
  extend `goldset/goldset.csv`, validated against `schemas/goldset_row.json`
- `Rscript scripts/goldset_fulltext_manifest.R`: SHA-256 check of `goldset/fulltext/`
  (the only script allowed to reference that folder)
- `Rscript scripts/report_goldset.R`: status report `reports/goldset/README.md` with
  figures (deterministic, no network; functions in `R/report.R`)
- `Rscript -e 'testthat::test_dir("tests/testthat")'`: tests
