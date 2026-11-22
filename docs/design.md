# Design notes: biodiversity-data-rescue

Last updated 2026-11-21. Background only; the plan and the rules are in
`CLAUDE.md`, the method in `protocol/protocol.md`. Decisions are logged at the
end of this file.

## Background

The project maps Norwegian grey literature that reports field surveys with
primary species data, and whether those data are published in GBIF. It follows
the systematic map method of the Collaboration for Environmental Evidence: find
documents, screen them against fixed criteria, code what they describe, and
place each item in an overview. A report can describe several surveys, and a
survey can be split over several reports or GBIF datasets.

The share of surveys whose data cannot be found in GBIF or elsewhere is expected
to be large. It is a result in its own right and is reported with its
uncertainty. The costliest error is calling data unpublished when they are in
GBIF, so matching reports a likelihood, and "not in GBIF" needs clear evidence.

## What the pilot (2026-11-18 to 2026-11-21) taught us

The first pilot (EPT taxa in Trondheim kommune; code at tag `v0-oppsett`)
built a gold set, a rule-based matcher and a reading benchmark across models.

- **GBIF baseline (2026-11-18).** EPT in Trondheim: 18,415 records in 13
  datasets; three hold 94 %: NTNU's freshwater benthic collection
  (`33591b80-0e31-480c-82ce-2f57211b10e6`, sampling events with eventID),
  Vannmiljø – artsforekomster (`46293000-ddd1-4c32-a1e7-b5e793223ecd`, records
  from consultancies, NIVA, NINA and NTNU; `waterBody` holds the
  vannlokalitetkode) and NTNU's terrestrial and limnic invertebrate collection.
- **Aggregators.** Many water surveys are only partly in GBIF, through
  Vannmiljø (`knowledge/aggregators/vannmiljo.md`).
- **Matching.** Place must be matched on stations, grid cells or
  vannlokalitetkode, not municipality alone: GBIF's GADM layer still has Klæbu
  as its own unit. Institution names in GBIF often differ from the report's,
  so no single dimension is a veto; evidence is weighed together.
- **Reading.** Who "the institution" is must be defined: in the reading key it
  became the publisher, not who did the field work. A data statement is
  "reported to Vannmiljø" only when the document says so.
- **Unit of analysis.** Rules for merging one survey across several documents
  are still open: annual reports of one programme, one study over four notes,
  one note with two surveys in two municipalities.

## Status categories

Kept from the pilot as a starting point for the `match` table.

| Status | Meaning |
|---|---|
| in_gbif | matches a dataset in taxon, time, place and institution, with protocol and effort |
| in_gbif_no_effort | records are in GBIF but without protocol, effort or absences |
| partly_in_gbif | only some years, taxa or sites are covered (e.g. via Vannmiljø) |
| open_elsewhere | data in a repository, a report appendix or a national database, not in GBIF |
| exists_not_available | the document says data exist, but internally or "on request" |
| unidentified | data status cannot be established |

## Gold set

`goldset/goldset.csv` (one row per survey) is the answer key for recall and
matching; `goldset/stations.csv` and `goldset/extraction_truth.csv` hold
stations and verified reading answers. It was built independently of the
pipeline's search, and must stay so: rows proposed by Claude are `candidate`
until Anders verifies them. Local full texts in `goldset/fulltext/` are for
manual checks only (CLAUDE.md, Data policy).

## Sources

Read-only APIs considered: OpenAlex, Crossref, DataCite, GBIF (registry,
occurrence search, SQL download), NVA, Brage repositories (OAI-PMH), CORE,
Unpaywall, Kartverket place names, NVE lake database, ROR, Artsdatabanken.

Lessons from a DataCite test (2026-10-21, gill-net freshwater query, 450 DOIs):
filter out GBIF download DOIs (prefix `10.15468/dl.`); merge versions
(`IsVersionOf`, title + publisher); "Nordic" is a method word (Nordic multi-mesh
gillnets) and gives false geographic hits; flag geography, never exclude on it;
method words often appear only in the description.

## Evidence base

- Screening: otto-SR reached 96–97 % sensitivity in medical reviews; a 2026
  software-engineering study lost 47 % of relevant papers on average (18–85 %
  across reviews). Recall depends on field and criteria: calibrate locally.
- Extraction: Gougherty & Clipp 2024 (npj Biodiversity) found country 100 %,
  year 72 %, exact coordinates 34 %, and invented values where data were missing.
- Closest tools: ARETE (R package, occurrences from text, arXiv 2511.04573);
  Telletxea et al. 2026 on stray data in environmental assessment reports.
- Reporting: the 2025 position statement from Cochrane, Campbell, JBI and CEE
  (with RAISE): humans are responsible; validate before use; report tool,
  version, date, purpose and validation in the methods note.

## Legal

The research exception for text and data mining (new § 50 f in åndsverkloven)
has a committee recommendation in Innst. 31 L (2026–2027). Check whether it is
enacted and in force before bulk full-text harvesting. It requires lawful
access.

## Open questions

- Where to draw "professional" (consultancies, NGOs with protocols, student
  theses)?
- Rules for merging one survey across several documents (see above).
- Status per taxon group? A survey can be in GBIF for benthos but only partly
  for amphibians.
- Recurring consultancy series in Vannmiljø (same stations, new contractor every
  few years): one survey per year, per contractor or per series?

## Decision log

- 2026-11-18: Unit of analysis is the survey. R with ellmer, DBI/RSQLite and
  DuckDB. Knowledge cards as markdown + YAML in git. LLM file contract with a
  `claude_code` backend during the pilot, ellmer later. Private repo on
  `andersfi`, moved to an organisation after the pilot. No AI attribution in git.
- 2026-11-18: Pilot scope is EPT taxa in Trondheim kommune (GADM `NOR.15.24_1`),
  water quality, restoration and freshwater biological surveys. Gold set built
  independently of the pipeline search.
- 2026-11-18: Project layout as in `CLAUDE.md`; `design.md` moved to `docs/`, the
  manifest to `goldset/`, the GBIF reference table to `goldset/reference/`.
  Commit and PR attribution switched off in `.claude/settings.json` (`attribution`).
- 2026-11-18: Gold-set reports supplied by Anders are kept locally in
  `goldset/fulltext/` (in `.gitignore`), with a manifest (file, SHA-256,
  survey_ref, role) in git. They are for manual verification only; the pipeline
  must find the documents through its own sources.
- 2026-11-19: Status reporting as markdown with PNG figures (2x) in
  `reports/goldset/`, generated by `scripts/report_goldset.R` and rendered
  directly by GitHub. Relative paths only, so the same files can be published as
  a GitHub Page later. Deterministic: the header shows the last commit of the
  input files, not the run time. Report text in English, like `docs/`.
- 2026-11-19: The repository is public. Nothing that cannot be public is
  committed (full texts, long quotes, secrets).
- 2026-11-19: The pipeline is measured as three separate links: find, read,
  match (section "Three links"). Match reports a probability band; "not in GBIF"
  only on clear evidence, uncertain cases go to review.
- 2026-11-19: The reading test may use the local full texts in
  `goldset/fulltext/`. Reading and search are separate links; search (including
  query building) is a separate problem for later. Search and screening still
  never read the full texts; the exception is limited to the `read` verb.
- 2026-11-19: LLM provider for now: only Anthropic via Claude Code on Anders'
  subscription, no API key. NTNU's API, the Anthropic API and local models come
  after design and workflow are settled; not built or tested before then.
- 2026-11-19: One entry point `Rscript run.R <verb>` (status, check, gbif,
  match, read, report) replaces the numbered scripts. Three zones: what Anders
  edits, code, generated (`runs/` committed, `data/` local). Every run writes
  `runs/<step>/<date>_<label>/`. `reports/` and `logs/` were folded into `runs/`
  (the status report is now `runs/goldset/README.md`; the query log
  `runs/queries.jsonl`). The GBIF reference table became the first gbif run;
  later gbif runs compare with the previous run. Candidate files moved to
  `goldset/archive/`; `goldset_import.R` and `goldset_append.R` removed (edit
  `goldset.csv` directly). Gold set gains `doc_ids` and `gbif_dataset_keys`.
  `run_log` gains `run_dir` and the kinds `match` and `read`; an outdated
  register is rebuilt, not migrated.
- 2026-11-19: Stations go in a separate file `goldset/stations.csv` (one row
  per survey × station), not a column. Claude fills it first from the local
  full texts and the rows' own fields, marked `verified = no`; Anders checks it
  before it is used as the answer key for reading.
- 2026-11-19: Match thresholds after the first run: keep the strict rule for
  `likely_not_in_gbif`; name-only place evidence counts half
  (`name_only_factor`); radius and the `likely_in_gbif` threshold unchanged until
  verified rows exist. No single evidence dimension acts as a veto (institution
  names in GBIF often differ from the survey's); dimensions are only weighed
  together.

- 2026-11-21: Reading benchmark plan (`docs/reading-benchmark.md`) approved
  with its recommendations: answer key `goldset/extraction_truth.csv` with
  period, institution, region, taxon_scope and data_statement (stations stay
  in `stations.csv`), drafted by Claude from the local full texts with
  `verified = no` and checked by Anders; per-document call logging in
  `runs/read/<id>/calls.tsv` (no schema change); models small = Haiku 5.5,
  medium = Sonnet 5.5, large = Opus 5.5, Fable 5.2 outside the matrix; build,
  run step 0 (flags, canary, overhead), then stop for review. The reading
  calls use headless `claude -p` from `R/llm.R` (`llm_cli_call`), one call
  per document in an empty temporary directory. The LLM cache key for a cell
  is `read:<model>:<input>:<cascade|single>` in `llm_answer.step`, so cells do
  not reuse each other's answers but a re-run of a cell does.
- 2026-11-21: Answer key verified by Anders. Rules from the review:
  `institution` in the reading key is the publisher (utgiver) of the
  document (the municipal annual reports: Trondheim kommune), not who did the
  field work; `period` covers every year a document reports for the survey,
  not only its new field work; `data_statement = vannmiljo` only when the
  document says its data were reported to Vannmiljø, not when it used data
  from there; new category `other_report` for documents that refer to another
  report for the species data. Extraction schema 0.2.0. Matching still uses
  the gold set's own `institution` column; whether it should use the
  publisher too is open.
- 2026-11-21: Anders accepts the environment and account context that
  `claude -p` injects despite `--system-prompt` (step 0 canary: working
  directory, platform, date, model id, existence of an account email; no
  repo, memory or gold-set content). The reading matrix may run with it.

- 2026-11-21: **Plan simplified.** The project becomes a systematic map (CEE
  style) of Norwegian grey literature with primary species field data, and of
  whether those data are in GBIF. Four steps plus a GBIF cube, one script each
  in `scripts/` (00 cube, 01 search, 02 screen, 03 extract, 04 match), each
  producing one table; one step at a time, with a stop for Anders' review after
  each. Dropped: the `run.R` verbs, the `runs/` folders, the LLM backend and
  file contract, knowledge-card loading, JSON schemas, the SQLite schema in
  `db/`, the three-link benchmark and their tests (all at tag `v0-oppsett`).
  Kept: renv, the gold set, `knowledge/` as plain text, this file. Scope: all of
  Norway, all taxa, documents from management, applied research and
  consultancies (CLAUDE.md, Scope). The query log moves to `logs/queries.jsonl`.
  Models are called through ellmer; the smallest model that works.
- 2026-11-21: GBIF cube built with the SQL download API: grid cells by
  `GBIF_EEARGCode(1000, lat, lon, 0)` (no random displacement), coordinate
  uncertainty kept as a class; first and last event date from
  `eventdategte`/`eventdatelte` (delivered as Unix seconds, stored as DATE).
  `classkey`/`orderkey` are keys in GBIF's current backbone and arrive as text
  (e.g. `V2`), so they are kept as text with the class and order names beside
  them. Parquet written with DuckDB (`COPY ... FORMAT parquet`), since arrow is
  not installed and duckdb is. Array columns (`recordedby`) work in GROUP BY
  (download 0007105-261118162104854). A county filter cannot be checked against
  occurrence search (GADM assignment differs near borders), so the test area
  is a coordinate box. The cube is checked per dataset and per year against
  search, with a tolerance of 0.5 % on the total; differences are kept in
  `data/gbif/*_check.tsv`. Two causes of difference were found in the box over
  all years (4,615,173 records in the cube): rgbif's `occ_search()` defaults to
  `occurrenceStatus = "PRESENT"`, so the check must pass `occurrenceStatus =
  NULL` to count absences (20,777); and the SQL table includes records whose
  name did not match the backbone (NULL `taxonkey`, 9,173 records, 0.2 %),
  which search leaves out. With both accounted for, the cube and search agree
  exactly per dataset.
- 2026-11-21 (Anders): The repo stays public; nothing that cannot be public is
  committed. The pilot state is tagged `v0-oppsett`; the pilot's GBIF baseline
  table is kept as `goldset/reference/gbif_baseline_2026-11-18.tsv`.
- 2026-11-21 (Anders): The cube starts coarse: 5 km cells
  (`GBIF_EEARGCode(5000, ...)`), because places read from report text are
  imprecise; narrow later if 5 km proves too coarse. A perfect match between
  the cube and occurrence search is not expected or needed (the end product
  matches GBIF datasets against reports, which is never exact); the 0.5 %
  tolerance only guards against gross errors. The test area is a coordinate
  box around Trondheim over all years, checked per dataset and per year.
- 2026-11-21 (Anders): Taxa are matched on keys, but reports use Norwegian and
  Latin names, so names must be kept with the keys. Step 0 therefore also
  writes a taxon name table (`data/gbif/taxa.parquet`: dataset × taxon key ×
  species key × rank × higher taxa × interpreted, verbatim and vernacular
  names, with record counts). `vernacularname` is filled in only some datasets
  (55 % of records in the test box; not in Artsobservasjoner or Vannmiljø), so
  Norwegian names must mainly come from Artsdatabanken's name database in step
  3 (TODO: decide source and access). A cube with a species dimension
  (dataset × year × species × cell) is not built now: 618,000 rows for the test
  box alone at 10 km; step 4 confirms species overlap with the GBIF API instead.
- 2026-11-21: National cube run (downloads 0007213-261118162104854, DOI
  10.15468/dl.4sa9uj, and 0007214-261118162104854, DOI 10.15468/dl.8kjwp8).
  97,040,157 records with coordinates in 1,692 datasets and 35,296 cells of
  5 km; 9,658,290 cube rows; 416,628 taxon name rows. 2,808,693 records (2.9 %)
  have a name with no backbone match, 2.57 million of them "Virgularia
  glacialis" in the petroleum dataset. The cube therefore carries
  `n_records_matched` (`COUNT(taxonkey)`) next to `n_records`, and the check
  compares the matched count with occurrence search: it agreed exactly for
  every dataset and every year (94,231,464). 33.8 million records are
  absences (`NOT_DETECTED`), 33.4 million of them in "Visuelle undersøkelser -
  petroleumsvirksomhet"; step 4 must handle occurrence status and this dataset
  explicitly.
- 2026-11-22 (Anders): Geographic scope includes Svalbard, Jan Mayen and the
  Norwegian economic zone; the cube therefore covers country codes NO and SJ,
  with `countrycode` as a dimension. Publication period: from when digital
  reports exist. Peer-reviewed articles and theses are out but noted.
  Stakeholders are involved after preliminary results. Extraction also records
  who funded the survey (public or private) and the study type. Recall target
  90 % of the gold set, assessed by Anders after the first pilot. Everything is
  committed and pushed continuously; credentials stay outside the repo.
- 2026-11-22: Pilot search of one source, NVA, reports only
  (`scripts/01_search.R`): one query per organism term in `search/terms.csv`,
  field terms matched in code on title, abstract and keywords. Reports are
  selected by `instanceType` (six report types), not `contextType=Report`,
  because NVA files many NIVA reports under the context Book. 15,618 unique
  reports; 10,259 match a field term; 9,081 of those have an open PDF (50 GB).
  22 of the gold set's 23 NVA documents were found (the last is a journal
  article). NVA matches whole words with some fuzziness, not prefixes, so
  compound words need their own terms (TODO).
- 2026-11-22: Pilot of steps 2 and 3 on a random sample of 25 reports (seed
  20261122, frame: field-term match and open PDF) to estimate cost. The model
  is called through the `claude` command line (`R/llm.R`), not ellmer, because
  the machine has no API key; cost is the API-equivalent price it reports.
  Smallest model (Haiku 5.5). Screening: 0.05 cents per report. Extraction on
  pages selected in code (front matter, method and data pages, at most 14):
  0.39 cents per report, 15 s. 6 of 25 PDFs are scans without a text layer and
  were not extracted (OCR not decided). Step 4 is not built yet.
