# Design notes: biodiversity-data-rescue

Last updated 2026-11-18. Decisions are logged at the end of this file.

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
`goldset/reference/gbif_ept_trondheim_2026-11-18.tsv`.

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

`goldset/goldset.csv`, one row per survey: `survey_ref`, `title`, `institution`,
`taxon_group`, `region`, `period`, `method`, `documents` (DOIs, handles or URLs,
semicolon-separated), `expected_status`, `where_data_are`, `is_borderline`,
`include` (yes/no), `found_via`, `notes`. `found_via` records how a row entered
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
