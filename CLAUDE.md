# biodiversity-data-rescue

A systematic map (CEE style) of Norwegian grey literature that reports field
surveys with primary species data, and of whether those data are published in
GBIF. Owner: Anders G. Finstad (NTNU). Public repo on `andersfi`: everything
committed is public.

## Scope

- **Documents:** Norwegian-language grey literature from
  - management: Miljødirektoratet, Statsforvalteren, fylkeskommuner, kommuner,
    Fiskeridirektoratet, Statens vegvesen and similar
  - applied research: NINA, NIVA, HI, Norsk Polarinstitutt, NORCE/LFI,
    Vestlandsforsking, the natural history museums
  - consultancies: general (Sweco, Rambøll, Multiconsult, Norconsult, COWI,
    Asplan Viak) and specialist (Rådgivende Biologer, BioFokus, Åkerblå and many
    small firms)
- **In:** field surveys that collect and present primary data on species.
- **Out:** surveys of habitat types only, water chemistry, geology or other
  abiotic data; documents that only compile existing data.

## Pipeline

| Step | Script | Question | Done by | Output |
|---|---|---|---|---|
| 0 GBIF cube | `scripts/00_gbif_cube.R` | What is in GBIF for Norway, where, when, from whom? | code (GBIF SQL download) | `data/gbif/cube.parquet` |
| 1 Search | `scripts/01_search.R` | Which documents may hold species field data? | code | `document` table |
| 2 Screen | `scripts/02_screen.R` | Does the title/abstract indicate own species field data? | small model, fixed categories; Anders checks samples | `screening` table |
| 3 Extract | `scripts/03_extract.R` | What can be matched against GBIF (where, when, taxa, who, method, data statement)? | code first (regex, name and place lookups), then small model | `chunk` and `extraction` tables |
| 4 Match | `scripts/04_match.R` | Are the data likely in GBIF? | code (cube for candidates, GBIF API to confirm) | `match` table |

Step 0 is independent of the others and can run first.

## How we work

- **One step at a time.** Each step is one script in `scripts/`, with functions
  in `R/`, producing one table. When a step runs, stop and show Anders: counts,
  10–20 example rows, and problems found. Do not start the next step until he
  says so.
- **Simple first.** No frameworks, abstractions or generic machinery before a
  step needs them. Prefer existing packages over own code.
- Anders writes Norwegian; answer in Norwegian (bokmål). Code, comments, file
  names and commit messages in English. He reads R best; explain choices briefly.
- Ask before: `sudo`; deleting anything outside `data/`; adding a service that
  receives data; large downloads or LLM batches.
- Record decisions in the decision log at the end of `docs/design.md`.

## Packages

synthesisr (import, deduplication), revtools (manual screening), litsearchr
(search-term discovery; GitHub, not CRAN), PRISMA2020 (flow diagram), ellmer
(LLM calls, batch), pdftools, rgbif, duckdb, arrow, DBI + RSQLite, httr2,
openalexR, dplyr, readr, purrr, testthat. Managed with renv.

R packages compile from source on this laptop; a failed install usually means a
missing system `-dev` library (ask before `sudo apt install`). IPv6 can hang: if
an httr2 request hangs, use `req_options(ipresolve = 1)`.

## Rules

1. Explicit failure. No silent fallbacks. Check fetched counts against the
   totals an API reports.
2. The model never searches. Records come from API results or files; the model
   only reads them.
3. Model output uses fixed categories and fields, with `not_stated` allowed.
   Validate before storing. Log model, prompt file, date and token counts.
4. Prompts and search-term lists are files in git (`prompts/`, `search/`).
5. Use the smallest model that works. Send only the relevant text chunks.
6. Keep raw API responses in `data/raw/`; log each query with a timestamp in
   `logs/queries.jsonl`.
7. Credentials come only from `~/.Renviron` via `Sys.getenv()`
   (`GBIF_USER`, `GBIF_PWD`, `GBIF_EMAIL`, `openalexR.apikey`,
   `ANTHROPIC_API_KEY`, `NTNU_API_BASE_URL`, `NTNU_API_KEY`). Never write them
   to the repo or print them.

## Git and attribution (hard rule)

- Never list Claude or any AI as author, co-author or contributor. No
  `Co-Authored-By` lines and no "Generated with Claude Code" in commits or PRs.
  Anders is the sole author; he declares AI use himself.
- Small commits with descriptive English messages.
- Never commit `data/`, `goldset/fulltext/`, `.env`, `.Renviron`, credentials,
  PDFs or other full texts.

## Layout

```
protocol/protocol.md    ROSES-style protocol for the systematic map
search/                 terms.csv (organism terms, field terms), sources.csv
prompts/                one file per model step
R/                      functions
scripts/                00_gbif_cube.R, 01_search.R, ...
goldset/                goldset.csv; fulltext_manifest.csv; reference/
  fulltext/             local only (.gitignore): reports Anders supplied
knowledge/              domain notes in markdown (context, not code)
docs/design.md          background and decision log
logs/                   query log
data/                   local only (.gitignore): raw/, gbif/, register.sqlite
```

## Data policy

- Full texts are copyrighted: never commit them; quote only short passages with
  page numbers. Ask before bulk full-text harvesting (the research exception for
  text and data mining is not confirmed in force in Norway).
- `goldset/fulltext/` is for manual checks only. No pipeline step may read it;
  every candidate must come from a search. Otherwise recall against the gold set
  means nothing.

## GBIF cube (step 0)

- `rgbif::occ_download_sql()`; check the query with `occ_download_sql_prep()`
  and list columns with `occ_download_describe("sql")$fields`. The SQL API is
  marked experimental. Each download gets a DOI: log it.
- Filter: `countrycode` NO or SJ (Svalbard and Jan Mayen), records with coordinates.
- Grid: `GBIF_EEARGCode(5000, decimallatitude, decimallongitude, 0)`: 5 km cells
  to start with; narrow later if needed. The last argument must be 0: any
  other value moves points randomly within their uncertainty, which breaks
  matching. Keep coordinate uncertainty as a coarse class instead.
- Start without person names. Suggested dimensions: countrycode, datasetkey,
  publishingorgkey, institutioncode, basisofrecord, occurrencestatus, year,
  month, classkey, orderkey, 5 km cell, uncertainty class. Measures: record
  count, species count if supported, first and last eventdate.
- It is undocumented whether array columns (`recordedby`, `samplingprotocol`)
  work in GROUP BY. Test on a small area before the national query.
- Norway has about 98 million records; the largest datasets are Artsobservasjoner
  (~39 M) and "Visuelle undersøkelser – petroleumsvirksomhet" (~33 M).
- Store the result as Parquet in `data/gbif/` and query it with DuckDB.
