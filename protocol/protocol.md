# Protocol: Norwegian grey literature with primary species field data, and its availability in GBIF

Systematic map protocol, structured after the ROSES reporting standard for
systematic map protocols (Haddaway et al. 2018) and the CEE Guidelines.
**Draft 2026-11-22.** Items marked **TODO** are for Anders to decide.

Authors: Anders G. Finstad (NTNU). TODO: co-authors, competing interests,
funding.

## 1 Background

Field surveys in Norway are often commissioned by management (environmental
impact assessments, monitoring, restoration follow-up) and carried out by
research institutes and consultancies. Results are published as grey
literature: reports, notes and memos. The primary species data behind them
(species, place, time, method) are often not published as open data, or only
partly, for example through Vannmiljø. These data are valuable for
biodiversity status and trend analyses but hard to find and reuse.

No overview exists of how much grey literature contains such data, who produces
it, and how much of it is in GBIF. This map provides that overview and a
prioritised list of data worth rescuing.

Stakeholders (Miljødirektoratet, Artsdatabanken, GBIF Norway, consultancies)
are involved after preliminary results exist (decided 2026-11-22).

## 2 Objective and question

**Primary question:** What Norwegian grey literature reports field surveys with
primary species data, and are those data available in GBIF?

**Secondary questions:**

1. How are these documents distributed over producer type (management, applied
   research, consultancy), period, region, taxonomic group and survey method?
2. What do the documents say about where the data are (appendix, Vannmiljø,
   Artskart/GBIF, "on request", nothing)?
3. What share of the surveys is likely in GBIF, partly in GBIF, or not
   identified there?

**Question elements:**

| Element | Definition |
|---|---|
| Population | Species (all taxonomic groups) in Norway, terrestrial, freshwater and marine, including Svalbard, Jan Mayen and the Norwegian economic zone at sea |
| Exposure / intervention | A field survey: a planned sampling effort by an institution or firm that records species in the field |
| Outcome | Primary species data presented in the document (species lists per site, counts, tables, maps with occurrences) and their availability in GBIF |
| Document type | Norwegian-language grey literature (see section 4) |

## 3 Scope

**Included documents** come from

- management: Miljødirektoratet, Statsforvalteren, fylkeskommuner, kommuner,
  Fiskeridirektoratet, Statens vegvesen and similar bodies;
- applied research: NINA, NIVA, HI, Norsk Polarinstitutt, NORCE/LFI,
  Vestlandsforsking, the natural history museums;
- consultancies: general (Sweco, Rambøll, Multiconsult, Norconsult, COWI,
  Asplan Viak) and specialist (Rådgivende Biologer, BioFokus, Åkerblå and many
  small firms).

Publication period: from when digital reports exist in the sources; no fixed
start year. Peer-reviewed articles and theses (master/PhD) are out, also when
they report surveys, but they are noted when found (kept in the `document`
table with their type, not screened further).

## 4 Search

### 4.1 Languages

Norwegian (bokmål and nynorsk). Titles and abstracts in English are searched as
well, because many institute reports have an English abstract. TODO: Swedish
and English-only documents about Norway in or out?

### 4.2 Sources

The model never searches; all records come from API results or files
(CLAUDE.md, rule 2). Planned sources, to be listed with URL and access in
`search/sources.csv`:

| Source | Covers | Access |
|---|---|---|
| NVA (Nasjonalt vitenarkiv) | NINA, NIVA, HI, NORCE, museums, many others | API |
| Brage repositories | institute and university series | OAI-PMH |
| OpenAlex | reports with DOI, abstracts | API (openalexR) |
| Crossref / DataCite | report DOIs; datasets cited by reports | API |
| Miljødirektoratet's publication list, Vannmiljø/Vann-nett report links | management reports | TODO: API or listing? |
| Statsforvalteren, kommuner, Statens vegvesen | EIA and monitoring reports | TODO: no common API; which ones, and how? |
| Consultancy websites (Rådgivende Biologer, BioFokus, Åkerblå ...) | specialist reports | TODO: listing pages; ask before scraping |
| Artskart / Artsdatabanken | report references in datasets | TODO |

TODO: which sources are in the first round. Proposal: NVA and OpenAlex first,
because they have APIs and cover the institutes; management and consultancy
sources after the first recall test.

### 4.3 Search string

Built from two term groups in `search/terms.csv`: organism terms (artsgrupper
and common names, e.g. *bunndyr, fisk, karplanter, fugl, lav, moser,
insekter*) and field-survey terms (*kartlegging, registrering,
undersøkelse, overvåking, prøvefiske, el-fiske, sparkeprøve, transekt,
biologisk mangfold, konsekvensutredning*). A document is a hit when it
matches at least one term from each group. Terms are extended with litsearchr
from a set of known relevant documents. TODO: approve the term lists.

### 4.4 Comprehensiveness

Recall is tested against the gold set (`goldset/goldset.csv`), which was built
independently of the search. Gold-set documents are never fed to the pipeline
(CLAUDE.md, Data policy). Target: 90 % of gold-set documents found by at least
one source; Anders assesses this himself after the first pilot run. TODO: the
gold set's coverage outside Trondheim and freshwater.

### 4.5 Records and deduplication

Records from all sources are imported and deduplicated with synthesisr (DOI,
handle, normalised title + year), and stored in the `document` table. Raw API
responses are kept in `data/raw/`; each query is logged in
`logs/queries.jsonl` with a timestamp, and fetched counts are checked against
the totals the API reports. Numbers per source and after deduplication go into
a PRISMA-style flow diagram (PRISMA2020 package).

## 5 Screening

### 5.1 Eligibility criteria

| Criterion | Include | Exclude |
|---|---|---|
| Document type | grey literature from the producers in section 3 | peer-reviewed articles, theses (noted, see 3), news, popular texts |
| Language | Norwegian (TODO: see 4.1) | other |
| Geography | survey in Norway | survey only outside Norway |
| Survey | own field survey: the authors or their commissioners collected the data | compilations of existing data only; desk studies; reviews |
| Data | primary species data presented (species per site/time, counts, species lists, occurrence maps or appendices) | habitat types only (e.g. NiN mapping without species), water chemistry, geology or other abiotic data; indices only without species (TODO: ASPT/index without species list: in or out?) |

When in doubt at title/abstract level: include (high recall), decide at full
text.

**Borderline cases** are included and flagged (`borderline` with a type), so
analyses can be run with and without them (decided 2026-11-22). Types so far:
`register_compilation` (records others collected in the field and reported to a
register, e.g. Rovbase), `catch_sampling` (samples from catches or landings),
`biota_contaminants` (contaminants measured in organisms), `other`.

### 5.2 Process

1. **Title and abstract.** A small language model assigns one fixed category
   per document: `include`, `exclude_no_field_survey`,
   `exclude_no_species_data`, `exclude_abiotic_only`, `exclude_compilation`,
   `exclude_outside_scope`, `not_stated` (not enough text to decide). The
   prompt is a file in `prompts/`. Model, prompt file, date and token counts
   are logged.
2. **Consistency check.** Anders screens a random sample by hand (revtools)
   before the model run is accepted: TODO sample size (e.g. 200) and the
   agreement needed (e.g. no missed `include` the model labelled `exclude_*`;
   Cohen's kappa ≥ 0.6). Disagreements are discussed and the prompt revised;
   the revision is logged.
3. **Full text.** TODO: at full-text level, model or human? Proposed: the
   extraction step (6) confirms eligibility; documents where it finds no
   species data are excluded there, with a reason.

Documents without accessible full text are kept with status
`no_full_text` and counted in the flow diagram.

## 6 Data coding

### 6.1 Coding strategy

Code first (regular expressions, name and place lookups), then a small model
only for the text chunks that code points to (methods sections, tables, data
statements). One document can yield several surveys. Every field allows
`not_stated`, and every value carries a page number. Model output is validated
against fixed categories before it is stored.

### 6.2 Coding schema (draft)

| Field | Content | Values |
|---|---|---|
| document_id | id in `document` | |
| producer | who published the report | name; type: management / research / consultancy |
| commissioner | who ordered the survey | name or `not_stated` |
| funder | who paid for the survey (often in the preface or acknowledgements) | name(s) or `not_stated` |
| funding_type | public or private money; decides which data-availability recommendations apply | public / private / mixed / not_stated |
| fieldwork_by | who did the field work | name(s) or `not_stated` |
| period | years (and months if stated) of field work | ISO years, ranges |
| place | stations, localities, waterbodies, municipalities, coordinates | text + resolved geometry (place-name lookup); precision class |
| taxa | taxonomic groups surveyed, species if listed | names as written (Norwegian and Latin); group list; GBIF backbone keys where resolvable |
| method | sampling method | fixed list (TODO: e.g. el-fiske, garn, sparkeprøve, transekt, punkttaksering, felle, visuelt, eDNA, other) |
| effort_stated | is sampling effort reported? | yes / no / not_stated |
| absences_stated | are absences or zero counts reported? | yes / no / not_stated |
| data_form | how species data are presented | table in text / appendix / map / summary only / not_stated |
| data_statement | where the document says the data are | appendix / vannmiljo / artskart_gbif / other_database / other_report / on_request / none / not_stated |
| study_type | what kind of study it is (often in the preface or acknowledgements) | commissioned_study / environmental_impact_assessment / monitoring_programme / restoration_followup / mapping_inventory / research / other / not_stated |

TODO: approve the method and study-type lists.

### 6.3 Consistency check

Anders checks extraction against the full text on a sample, per field
(TODO: sample size); the verified gold-set answers
(`goldset/extraction_truth.csv`) are the first test set.

## 7 Matching against GBIF

For each survey, candidate GBIF datasets are found in the GBIF cube
(`data/gbif/cube.parquet`: dataset × publisher × institution × basis of record ×
year × month × class × order × 1 km EEA cell × uncertainty class) by overlap in
place, time and taxon, and confirmed with the GBIF API (records, dataset
metadata). Evidence from place, time, taxon, institution, method and direct
links (DOI or report cited in the dataset) is weighed together; no single
dimension is a veto. Result per survey: a status (`docs/design.md`, Status
categories) with a likelihood band; "not in GBIF" only on clear evidence.

## 8 Study validity

Not assessed: a systematic map describes the evidence base and does not judge
the quality of individual surveys. Effort and absence reporting (6.2) is coded
as a proxy for reuse value.

## 9 Mapping and presentation

- Flow diagram (PRISMA2020) with counts per step and source.
- The coded database as an open table (TODO: where: Zenodo, GBIF as a
  metadata-only dataset, or both?).
- Heat maps of documents by producer type × taxonomic group × period, and of
  status in GBIF; a map of surveyed places against GBIF coverage.
- Knowledge gaps and clusters; a prioritised list of surveys whose data are
  worth publishing.

## 10 Deviations

Changes to this protocol are logged with date and reason in the decision log
of `docs/design.md`.
