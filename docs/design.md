# Design notes: biodiversity-data-rescue

Last updated 2026-11-19. Decisions are logged at the end of this file.

## Framing

The project is a systematic map of data availability, in the sense used by the
Collaboration for Environmental Evidence: find documents, code what they
describe, and place each item in an overview. The item is the **survey**: one
professional sampling effort with a defined taxonomic scope, area, period and
protocol. A survey can be described in several documents (report, article,
dataset), and one report can describe many surveys. GBIF datasets relate to
surveys many-to-many as well.

The share of surveys whose data cannot be identified is expected to be large. It
is a result in its own right and is reported with its uncertainty.

## Pilot scope (decided 2026-11-18)

- **Taxa:** EPT — Ephemeroptera (GBIF taxonKey 1225), Plecoptera (787),
  Trichoptera (1003). Widely used indicator taxa in aquatic surveys.
- **Area:** Trondheim kommune, GADM GID `NOR.15.24_1` (GADM level 2). GADM uses
  boundaries from before 2020, so Klæbu (`NOR.15.8_1`, 2,040 EPT records) is
  outside. Exact boundaries matter less than keeping the volume small.
- **Survey types:** water quality monitoring, restoration and its follow-up,
  freshwater biological surveys and similar work that records EPT taxa.

GBIF baseline on 2026-11-18 (`gadmGid=NOR.15.24_1`, the three taxon keys):
18,415 records in 13 datasets. Three datasets hold 94 %:

| Dataset | Records | Type | Years | Notes |
|---|---|---|---|---|
| Freshwater benthic invertebrates ecological collection NTNU University Museum (`33591b80-0e31-480c-82ce-2f57211b10e6`) | 14,057 | sampling event | 1978–2024 (28 years) | Surber and sweep samples; eventID present. Peaks 1978–79 and 2014–2020. |
| Vannmiljø – artsforekomster, Miljødirektoratet (`46293000-ddd1-4c32-a1e7-b5e793223ecd`) | 2,159 | occurrence | 2011–2025 (13 years) | Benthic sampling protocols; recorded by consultancies (Rambøll, Multiconsult, Norconsult, Sweco), NIVA, NINA and NTNU; `waterBody` holds the Vannmiljø locality code. |
| Terrestrial and limnic invertebrates systematic collection, NTNU University Museum (`1bec5de3-758c-4ed2-ab13-1597601ad07a`) | 1,050 | occurrence | 1936–2015 | Mostly malaise traps; no eventID. |

The rest: iBOL, NINA Vanndata, INSDC, Artsobservasjoner, Miljølære.no, national
insect monitoring, UiO entomology, Luomus, iNaturalist. Full table in
`runs/gbif/2026-11-18_baseline/reference.tsv`.

## Pipeline

| Step | Actor | What happens → output | Tools |
|---|---|---|---|
| A1 Define | Human | Inclusion criteria (systematic surveys with a described method, by an institution or consultancy; not recreational catches or single records). Gold set. → protocol, gold set | `protocol/`, `goldset/` |
| A2 Query plan | LLM, large model | Queries per source in Norwegian (bokmål and nynorsk), Swedish and English, with method and taxon terms. → versioned query plan | Claude in chat or Claude Code |
| A3 Search | Script + API | Full paging per source; raw responses and queries logged. → document list | httr2, openalexR, rgbif; OAI-PMH for Brage repositories |
| A4 Screening | LLM, small model in batch | Title and abstract against the criteria, tuned for high recall (when in doubt, include). → candidate documents | `R/llm.R` (claude_code now, ellmer later) |
| A5 Calibration | Human | Recall against the gold set, precision on samples. Below target → back to A2. → approved candidates | review app or spreadsheet |
| B1 Full text | Script | Open PDFs via Unpaywall, CORE, NVA; text and tables out; OCR for scans. → text with page numbers | pdftools; later GROBID or Docling |
| B2 Extraction | LLM, mid-size model | From methods and tables: who, which taxa, where, when, protocol, effort, absences recorded, where the data are. Page number per field. One document can yield several surveys. → survey records | `R/llm.R`, schema built on Humboldt terms |
| B3 Normalise | Script + API | Taxa to GBIF Backbone and Artsdatabanken; places to Kartverket place names and NVE's lake database; institutions to ROR; periods to ISO dates. → comparable records | rgbif, httr2 |
| B4 Spot checks | Human | Extraction checked against the source text, especially coordinates, periods and effort. → error rate per field | review app |
| C1 GBIF cube | Script + API | Norwegian GBIF data aggregated to dataset × taxon × year × grid cell, plus dataset metadata. Candidate pairs scored on overlap. → candidate pairs | GBIF SQL Download via rgbif, DuckDB, GBIF registry API |
| C2 Uncertain pairs | LLM, small model | Reads the survey description and the dataset metadata; answers same / partly / different, with a reason. → judged pairs | `R/llm.R` |
| C3 Status | Human | Approves thresholds, reviews uncertain pairs and samples, sets status per survey. → status overview | review app |

## Three links, measured separately (decided 2026-11-19)

The pipeline is judged link by link, so a weak result can be traced to its cause:

- **find**: does search find the document? Recall against the gold set (rows
  not found via that source).
- **read**: does the model extract the right fields from the report? Accuracy
  against a hand-verified answer key, per field.
- **match**: given a correct description of the survey, is the GBIF status right?
  Measured against `expected_status`, using gold-set rows as if read perfectly.

The costliest error is calling a survey unpublished when its data are in GBIF.
Match therefore gives a probability band, not a hard class: "not in GBIF" only
when the evidence clearly says so; uncertain cases go to Anders for review.

Search, including building queries, is a separate problem and is tested later:
it cannot be tested meaningfully on one set of reports from one municipality.

Every run writes a folder `runs/<step>/<date>_<label>/` (provenance, config
copies, metrics, short README), so the effect of a change in the gold set, the
config or the code can be seen run by run in `runs/README.md`. Verbs and folders
are listed in `README.md`.

## Data model (SQLite register)

| Table | Content | Key fields |
|---|---|---|
| document | every article, report or dataset found | uri, doi/handle/url, type, year, institution, licence, full-text status |
| survey | one professional sampling effort | uri, taxonomic scope, area, period, protocol, effort, absences recorded, responsible institution |
| document_survey | link between them | role (primary source or mention), page evidence |
| gbif_dataset | relevant GBIF datasets | datasetKey, publisher, taxonomic/temporal/geographic coverage, method |
| candidate_pair | possible survey–dataset matches | score per dimension, model judgement, human decision |
| survey_status | current status per survey | category, reason, date, who set it |
| knowledge_card | loaded from `knowledge/` | id, type, fields, file hash |
| aggregator_coverage | survey or survey type covered by an aggregator dataset | aggregator id, coverage (full/partial), evidence |
| run_log | provenance per search or LLM batch | backend, model, prompt hash, schema version, tokens, timestamp |

Survey fields use Humboldt Extension concepts where they exist (target taxonomic
scope, sampling effort, absence reporting, temporal and spatial scope). Term list:
https://tdwg.github.io/hc/terms/ (ratified by TDWG 2024-02-28). This keeps the
register comparable with GBIF metadata and ready for later publication.

DuckDB is used for the GBIF cube and matching. Move the register to PostgreSQL
with PostGIS only when several people need to write to it at the same time.

## Matching against GBIF

A match needs overlap in taxon, time and place. Method, institution and direct
links (a DOI or report cited in the other source) strengthen it. High scores are
accepted with spot checks; medium scores go to the model, then to a human; low
scores count as no match.

| Dimension | Survey side | GBIF side |
|---|---|---|
| Taxon | taxonomic scope or species list | taxa in the cube; taxonomic coverage in metadata |
| Time | period | years with records; temporal coverage |
| Place | area, lake or grid cell | grid cells with records; geographic coverage |
| Method | protocol | samplingProtocol; methods in metadata |
| Institution | responsible institution | publisher, ROR id |
| Direct link | DOI or data statement in the document | references in the metadata |

**Implementation (phase 2, `run.R match`, rule-based).** Each gold-set survey is
expanded to station-years (`goldset/stations.csv`, else place names from
`region`). A station-year is covered when a scope record of the same year lies
within `station_radius_m` of the station, or carries the station's
vannlokalitetkode, or (name-only stations) names the waterbody. Stations in a
municipality the scope excludes are left out of the denominator. Per survey:
coverage (share of station-years covered), and a value with its source for
place × time (as coverage, but name-only station-years count half), taxon (matched EPT records), institution (in recordedBy,
institutionCode or publisher of matched records), dataset name (title tokens in
datasetName or dataset title in the survey's years) and direct link (a document
id or report number in a scope dataset's registry entry; absence is not
evidence). The score is the weighted mean of the assessable dimensions. Bands:
`likely_in_gbif` (score above a threshold), `likely_not_in_gbif` only with a low
score, no coverage and most station-years located by coordinates or code;
everything else `uncertain`, listed in `review.md` with its evidence. Weights
and thresholds are in `config/match.yaml`. Inputs are only fields a reader
could extract; `where_data_are`, `gbif_dataset_keys`, `expected_status` and
`notes` are joined after banding, for scoring. Main metric: false "unpublished"
(gold `in_gbif`/`in_gbif_no_effort`/`partly_in_gbif` banded
`likely_not_in_gbif`) with a Wilson 95 % interval; only `include = yes` rows
count, candidate rows are reported as provisional. Rows found via the GBIF
baseline are also reported separately, because their titles and places were
written from GBIF and name evidence is circular for them. No statistical model
until the gold set has enough verified rows per band (see the open questions).

## Status categories

| Status | Criteria | Next action |
|---|---|---|
| in_gbif | matches a dataset in taxon, time, place and institution, with protocol and effort | none |
| in_gbif_no_effort | records are in GBIF but without protocol, effort or absences | add events and Humboldt fields |
| partly_in_gbif | only some years, taxa or sites are covered (e.g. via an aggregator such as Vannmiljø) | publish the rest |
| open_elsewhere | data in a repository, a report appendix or a national database, not in GBIF | standardise and publish via IPT |
| exists_not_available | the document says data exist, but internally or "on request" | request the data |
| unidentified | the survey is described, but data status cannot be established | ask the institution; prioritise by value |

`in_gbif_no_effort` is kept separate because such records cannot support analyses
that need effort or absences.

## Knowledge cards

Domain knowledge accumulates during review (for example that many water surveys
are partly in the Vannmiljø dataset). It is stored as one markdown file per card
in `knowledge/`, with YAML front matter validated by
`schemas/knowledge_card.json` and loaded into the register by a build script.
Types:

- **aggregator**: shared datasets, what they contain, how to link to them, known gaps
- **source**: where institutions' report series live and how to search them
- **precedent**: a decided borderline case with the decision and the reason;
  used as examples in prompts so judgements stay consistent
- **vocabulary**: synonyms for methods, taxa and places

Required front matter: `id`, `type`, `title`, `source` (evidence), `last_confirmed`,
`confirmed_by`. Illustrative example (facts to be filled in):

```yaml
---
id: vannmiljo
type: aggregator
title: Vannmiljø
owner: Miljødirektoratet
coverage: partial
link_keys: [vannlokalitetkode]   # appears in GBIF waterBody as "vannlokalitetkode: 123-606-r"
in_gbif: partial
gbif_dataset: 46293000-ddd1-4c32-a1e7-b5e793223ecd   # "Vannmiljø - artsforekomster"
source: "Anders; GBIF baseline 2026-11-18"
last_confirmed: 2026-11-18
confirmed_by: andersfi
---
Many water surveys are here, but often only parts of them. In Trondheim,
2011–2025 EPT records come from consultancies (Rambøll, Multiconsult,
Norconsult, Sweco), NIVA, NINA and NTNU. TODO: whether all species data in
Vannmiljø reach GBIF, and whether index values (e.g. ASPT) exist without
species lists.
```

Only cards relevant to a batch go into the model's context.

## Gold set

`goldset/goldset.csv` is the only answer key. One row per survey: `survey_ref`,
`title`, `institution`, `taxon_group`, `region`, `period`, `method`, `documents`
(citations, free text), `doc_ids` (`nva:`/`doi:`/`handle:` ids, `;`-separated),
`expected_status`, `where_data_are` (free text), `gbif_dataset_keys` (full GBIF
dataset keys holding the survey's pilot-taxa records, `;`-separated; an answer
key for matching, never an input to it), `is_borderline`, `include`
(yes/candidate/no), `found_via`, `notes`. `doc_ids` and `gbif_dataset_keys` were
first filled mechanically from the free-text fields (2026-11-19); empty means not
known. `Rscript run.R check` validates the file against
`schemas/goldset_row.json` and lists open work. `found_via` records how a row entered
the gold set (`anders`, `kommune_page`, `gbif_baseline`, `reference_list`,
`nva_targeted` for a known series looked up by title, `nva_search` for anything
discovered by open search). Recall for a source is measured only on rows that were
not found via that source. Target for the pilot: 30–60 rows covering every
status category, including partial cases and negative cases (recreational
fishing, single records).

`expected_status` refers to the pilot taxa (EPT), not to every taxon group in the
survey. Negative cases (documents with no survey in scope) get `include = no` and
`expected_status = not_applicable`, with the reason in `notes`.

The gold set must be built independently of the pipeline's own literature
search, otherwise recall is overestimated. Sources: Anders' knowledge, the GBIF
baseline (surveys identifiable from dataset × collector × period × locality),
reports known from Trondheim kommune and the institutions, and reference lists
in key reports. Rows proposed by Claude are marked `candidate` until Anders has
verified them.

### Stations

`goldset/stations.csv` holds the stations of gold-set surveys, one row per
survey × station: `survey_ref`, `years` (same syntax as `period`), `station`,
`waterbody`, `locality`, `vannlokalitetkode`, `former_municipality` (stated by
the source, e.g. Klæbu before 2020), `crs` (`EPSG:25832` for UTM 32V as printed,
`EPSG:4326` for lat/lon), `x`, `y`, `date`, `document`, `page`, `verified`
(yes/no), `note`. Coordinates are kept as printed in the source; the matcher
converts them. It is part of the answer key for reading (phase 3) and an input
to matching (phase 2: as if read perfectly). First filled by Claude from the
local full texts and the rows' `region` field (2026-11-19, all `verified = no`);
Anders checks it. Surveys without a row in this file are matched on the place
names in `region`.

### Gold-set full texts

`goldset/fulltext/` holds local copies of gold-set reports supplied by Anders.
They are never committed (copyright); `goldset/fulltext_manifest.csv` links each
file to its gold-set rows by `survey_ref` (several refs separated by `;`) and
`role` (`primary`, `summary`, `cites`), with a SHA-256 that shows whether the
pipeline later fetched the same file from the source.

Allowed uses: checking a gold-set row by hand, and the reading test (`run.R
read`, decided 2026-11-19), where reading is measured on its own. Search and
screening never read these files: every candidate must come from an API result,
otherwise recall against the gold set would mean nothing. Only `R/fulltext.R`
references the folder and only the `read` verb calls it
(`tests/testthat/test-fulltext-isolation.R`).

## Sources (read-only APIs)

OpenAlex, Crossref, DataCite, GBIF (registry, occurrence search, SQL Download),
NVA, Brage repositories (OAI-PMH), CORE, Unpaywall, Kartverket place names, NVE
lake database, ROR, Artsdatabanken. Sources without an API are found with web
search and logged as such.

Lessons from the DataCite test on 2026-10-21 (gill-net freshwater query, 450 DOIs,
220 unique datasets, 31 Nordic freshwater):

- filter out GBIF download DOIs (prefix `10.15468/dl.`), which are not datasets
- merge versions (`IsVersionOf`, title + publisher)
- "Nordic" is a method word (Nordic multi-mesh gillnets) and gives false
  geographic hits
- a regex geo filter missed Pasvik and Finnmarksvidda: flag geography, never
  exclude on it
- method words often appear only in the description, not in the title or subjects

## LLM file contract

- A step writes `data/llm_in/<step>_<batch>.jsonl`: one record per line with
  `uri`, the text fields, `schema_version` and `prompt_file`.
- The answer is `data/llm_out/<step>_<batch>.jsonl`: same `uri`s, fields per
  `schemas/<step>.json`, plus `backend`, `model`, `answered_at`.
- `R/llm.R` offers backends behind one interface; import and validation are
  identical for all:
  - `claude_code` (pilot): Claude Code answers the batch file, on Anders'
    subscription (no API key).
  - `ellmer` (later): the provider in `config/llm.yaml`: `chat_anthropic()`,
    `chat_openai_compatible()` for NTNU's API or a local server, or
    `chat_ollama()`. Not built or tested until design and workflow are settled
    (decided 2026-11-19).

## Reference: the old MVP

`~/projects/biodiversity-data-finder-old` (Python, June 2026). Ideas worth
porting, not code: its architecture rules (now in `CLAUDE.md`); a
`provenance.json` next to every downloaded file (`core.py::download_search`);
bounded inspection of a dataset, README plus the first rows of the first CSV/TSV,
at most 64 KB (`zenodo.py::fetch_assessment_payload`), useful for datasets that
are "available elsewhere"; JSON-LD export of the register
(`cli.py::_export_jsonld`). Not to port: free-text criteria generation,
Zenodo-only search (DataCite covers Zenodo), the single DwC-readiness score, the
reticulate wrapper, its `.env`.

## Evidence base

- Screening: otto-SR reached 96–97 % sensitivity in medical reviews; a 2026
  software-engineering study lost 47 % of relevant papers on average (18–85 %
  across reviews). Recall depends on field and criteria: calibrate locally.
- Extraction: Gougherty & Clipp 2024 (npj Biodiversity) found country 100 %, year
  72 %, exact coordinates 34 %, and invented values where data were missing.
- Closest tools: ARETE (R package, occurrences from text, arXiv 2511.04573);
  Telletxea et al. 2026 on stray data in environmental assessment reports.
- Reporting: the 2025 position statement from Cochrane, Campbell, JBI and CEE
  (with RAISE): humans are responsible; validate before use; report tool, version,
  date, purpose and validation in the methods note.

## Legal

The research exception for text and data mining (new § 50 f in åndsverkloven) has
a committee recommendation in Innst. 31 L (2026–2027). Check whether it is enacted
and in force before bulk full-text harvesting. It requires lawful access.

## Energy

Large model once per topic for design; small model in batches per record; cache
so nothing is judged twice; send only relevant pages and knowledge cards; log
tokens per batch so use can be reported.

## Open questions

- Include Klæbu to match today's Trondheim kommune?
- Where exactly to draw "professional" (consultancies, NGOs with protocols,
  student theses).
- NTNU's LLM API: OpenAI-compatible? structured output? approved data class?
- Rules for merging the same survey across several documents. Cases so far: the
  kommune programme is split per year (one report per year); NTNU's Bymarka
  before/after study is one survey across four notes; NTNU note 2018-14 is one
  document with two surveys in two municipalities.
- Status per taxon group? Bymarka is `in_gbif` for benthos and zooplankton but
  only partly for amphibians (visual records missing). If the scope widens,
  `survey_status` may need a taxon-group column.
- Gold-set schema (proposed 2026-11-18, not decided): `expected_status = todo` is
  allowed only on rows with `include = candidate`, so unverified candidates validate.
  Remove it, or keep it?
- Register schema (proposed 2026-11-18, not decided): an `llm_answer` table holds
  the cache required by architecture rule 5; `document_survey.role` uses
  `primary`/`summary`/`mention`.
- Recurring consultancy series in Vannmiljø (same stations, new contractor every few
  years, e.g. 123-113-R/123-642-R by Multiconsult then Rambøll): one survey per year,
  per contractor or per series?
- Spatial matching must use stations or vannlokalitetkode, not municipality
  alone: GBIF's GADM layer still has Klæbu as its own unit, and NIVA records in
  Klæbu were first mistaken for Trondheim's programme.

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
