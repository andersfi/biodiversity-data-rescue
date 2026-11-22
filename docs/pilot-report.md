# Pilot: infrastructure needs and first results (2026-11-22)

A pilot of the pipeline in `CLAUDE.md` (steps 0–3) on one source, NVA, with a
random sample of 275 reports. All figures were computed from
`data/register.sqlite`, `data/gbif/` and the files in `data/fulltext/nva/`
(local only); each table names its source. Intervals are 95 %: Wilson
intervals for shares, mean ± 1.96 standard errors for totals. Model agreement
is not accuracy: no answers have been checked by a person yet.

## 1 What was done

| Item | Result | Source |
|---|---|---|
| GBIF cube (step 0) | 98,958,531 records with coordinates (96,114,205 matched to the backbone), 2,181 datasets, 47,998 cells of 5 km, 9,896,740 cube rows; NO 97,089,027 records, SJ 1,869,504 | `data/gbif/cube.parquet`: `n_records`, `n_records_matched`, `datasetkey`, `eeacellcode`, `countrycode` |
| GBIF downloads | cube DOI 10.15468/dl.myq3sw, taxon names DOI 10.15468/dl.xf8qy8 | `logs/queries.jsonl` |
| NVA search (step 1) | 15,618 reports; 10,259 match both an organism term and a field term; 9,081 of those have an open PDF (50.1 GB) = the frame | `document`: `passes_terms`, `n_open_pdf`, `open_pdf_size` |
| Samples | `pilot25` (25) + `pilot250` (250) = 275, random from the frame | `pilot_sample`: `sample_name` |
| Screening (step 2) | title, abstract, keywords → 7 fixed categories + borderline flag | `screening` |
| Extraction (step 3) | pdftotext or OCR, up to 14 pages selected by code, model fills a fixed schema | `chunk`, `doc_facts`, `extraction`, `extraction_survey` |

Model runs: Claude Haiku 5.5 three times (v1 through the `claude` command line
with its default thinking; v2 through the API without thinking; v3 through
the API with adaptive thinking, the current main run), and three models on
NTNU's own service for comparison. Prompts and schemas are in `prompts/`.

## 2 Infrastructure needs for the full frame

Per-document means from the pilot (Haiku v3) scaled to the frame.

| Step | Units | Tokens in (M) | Tokens out (M) | Cost (USD) | Time | Disk | Mode |
|---|---|---|---|---|---|---|---|
| PDF download | 9,081 PDFs | – | – | – | not measured | 50.1 GB | sequential, NVA API |
| Text + page selection | 9,081 | – | – | – | ≈ 1.5 h (275 in < 3 min) | small | sequential, local |
| OCR of scanned PDFs | 1,354 (1,016–1,780) PDFs, 98,000 (73,500–128,900) pages | – | – | – | 136 (102–179) core-hours = 13.7 (10.3–18.0) h on 12 cores | 0.16 GB text | parallel over pages |
| Screening, 10,259 | 10,259 records | 24.7 ± 0.8 | 2.6 ± 0.2 | 3.77 ± 0.12 | 7.5 ± 0.5 h | | sequential API calls |
| Screening, all 15,618 | 15,618 records | 37.6 ± 1.3 | 4.0 ± 0.3 | 5.74 ± 0.18 | 11.5 ± 0.8 h | | sequential API calls |
| Extraction | 9,081 PDFs | 120.7 ± 4.6 | 13.6 ± 1.3 | 18.88 ± 0.91 | 22.6 ± 6.9 h | 0.07 GB raw JSON | sequential API calls |

Sources: tokens, cost, time: `screening` and `extraction` (`input_tokens`,
`cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`,
`cost_usd`, `seconds`); OCR: `doc_facts` (`text_source`, `ocr_pages`) and the
per-page CPU times in `data/fulltext/nva/<id>.ocr.json` (5.0 CPU s per page,
median 3.7, p90 7.4; 41 of 275 sampled PDFs scanned, 14.9 %, 11.2–19.6 %);
disk: `document.open_pdf_size`, file sizes of `.ocr.txt` and `data/llm/`.

- Output tokens include thinking (on average 154 per screening and 960 per
  extraction call; `thinking_tokens`).
- Calls ran one at a time. The API allows parallel calls, so wall time can be
  cut several-fold; cost does not change. The extraction time interval is wide
  because of one 5-minute HTTP timeout with retries (see section 6).
- On NTNU's service (no cost per token) the same 275 documents took 19.6 min
  with 8 parallel calls (Mistral, about 830 documents per hour, both steps) and
  51–96 min with 6 (GLM about 290, Borealis about 110 documents per hour).
  The service allows 10 parallel requests per key.

## 3 Model choice

| Run | Path | Thinking | Cents per screening | Cents per extraction | s per extraction call | Same screening category as v3 | Same `eligible` as v3 | Known negatives right (of 5) |
|---|---|---|---|---|---|---|---|---|
| Haiku v1 | `claude` CLI, old prompts | CLI default | 0.051 | 0.272 | 13.1 | 247/275 (89.8 %) | 217/232 (93.5 %) | 5 |
| Haiku v2 | API | off | 0.029 | 0.158 | 3.3 | 222/274 (81.0 %) | 237/266 (89.1 %) | 0 |
| Haiku v3 | API | adaptive | 0.037 | 0.208 | 8.9 | – | – | 5 |
| Mistral-Medium-3.5-128B-instant | NTNU | none | 0 | 0 | 18.7 | 183/274 (66.8 %) | 234/254 (92.1 %) | 5 |
| GLM-5.3-Flash-instant | NTNU | reasons (8,700 tokens per extraction) | 0 | 0 | 56.3 | 237/275 (86.2 %) | 249/267 (93.3 %) | 5 |
| borealis-27b | NTNU | none | 0 | 0 | 74.5 | 207/275 (75.3 %) | 153/244 (62.7 %) | 1 (+1 unclear) |

Sources: `screening_v1`, `screening_v2`, `screening`, `screening_cmp`
(`category`, `cost_usd`); `extraction_v1`, `extraction_v2`, `extraction`,
`extraction_cmp` (`eligible`, `cost_usd`, `seconds`); `model` in the `_cmp`
tables. Haiku v1 and v2 costs and times are for the 234 and 227 reports read
with pdftotext; v3 for all 273. Known negatives: five reports v2 marked eligible that are clearly not
species field surveys (a hate-speech survey, a dental literature review, a
pupil questionnaire, the SEAPOP programme plan, a chlorophyll-and-nutrients
report).

| Comparison with Haiku v3 | Mistral | GLM | Borealis |
|---|---|---|---|
| Screening: v3 include → other exclude | 53 | 10 | 12 |
| Screening: v3 exclude → other include | 2 | 10 | 19 |
| Eligible yes (with / without borderline) | 132 / 121 of 255 | 163 / 125 of 269 | 210 / 210 of 246 |
| Borderline flags in extraction | 11 | 38 | 0 |
| Both yes: same `study_type` | 78.6 % | 83.0 % | 42.2 % |
| Both yes: same `funding_type` | 81.7 % | 89.8 % | 66.4 % |
| Both yes: same first-survey `data_statement` | 65.9 % | 49.7 % | 60.6 % |
| Both yes: same set of field years | 75.2 % | 88.2 % | 73.1 % |
| Failed calls (screen + extract) | 21 (lists over limit) | 6 (truncated at 32,000 output tokens) | 29 (28 lists over limit, 1 HTTP 502) |

Haiku v3: 3 failed calls (2 lists over limit, 1 timeout); eligible yes 153 /
129 of 273. Sources as above plus `extraction_survey`, `extraction_survey_cmp`
(`data_statement`, `years`), `llm_failure`, `llm_failure_cmp` (`error`).

What the numbers support:
- Thinking matters for Haiku: without it (v2) eligibility was looser and all
  five known negatives were wrong; with adaptive thinking (v3) they are right
  and v3 agrees with v1 on 93.5 % of `eligible`.
- GLM is the closest to Haiku v3 on every measure, but it reasons at length
  and is slow (56 s per extraction).
- Mistral is fast and agrees on eligibility, but screens strictly (53 v3
  includes excluded at screening) and fails more often on list limits.
- Borealis marks most reports eligible (79 that v3 calls `no`), never uses the
  borderline flag, and writes reasons in Norwegian; it does not fit this task
  as prompted.

What they do not support: which model is right. Agreement between models says
nothing about accuracy until a human-checked sample exists. Five
negatives are too few for an error rate. On five reports per model read side by
side, Haiku v3 and GLM extracted comparable detail. Mistral merged surveys and
added background years. Borealis missed years, coordinates and surveys.

## 4 What the reports contain (Haiku v3)

| Measure | Value | Frame (9,081) |
|---|---|---|
| Eligible yes, with borderline | 153/275 = 55.6 % (49.7–61.4) | 5,052 (4,516–5,575) |
| Eligible yes, without borderline | 129/275 = 46.9 % (41.1–52.8) | 4,260 (3,732–4,796) |

Source: `extraction` (`eligible`, `borderline`); denominator 275 sampled PDFs
(2 had failed extraction calls and count as not eligible).

Among the 153 eligible reports (`extraction`, `extraction_survey`):

| Field | Distribution |
|---|---|
| `study_type` | monitoring_programme 75, commissioned_study 42, research 15, environmental_impact_assessment 10, mapping_inventory 5, restoration_followup 5, not_stated 1 |
| `funding_type` | public 83, private 35, mixed 20, not_stated 15 |
| `data_statement` (218 surveys) | not_stated 147, appendix 27, vannmiljo 15, other_database 14, none 8, other_report 3, artskart_gbif 2, on_request 2 |
| Reports stating delivery to a database (vannmiljo, artskart_gbif, other_database) | 21 of 153 |
| `methods` (mentions) | other 76, visual_survey 42, electrofishing 34, grab_or_core 20, kick_sample 17, plankton_net 16, camera_or_acoustic 15, gillnet 14, not_stated 14, trawl_or_seine 13, transect 10, vegetation_plot 10, trap 9, edna 3, point_count 2 |
| Coordinates copied by the model (`places_json`) | 30 of 153 reports |
| Coordinate-like strings in the full text (`doc_facts.n_coordinate_like` > 0) | 34 of 153 reports |

By publisher (`document.publisher`, top 5 by sampled reports):

| Publisher | Extracted | Yes | Yes without borderline |
|---|---|---|---|
| NIVA | 75 | 48 | 40 |
| NINA | 58 | 43 | 38 |
| Havforskningsinstituttet | 19 | 11 | 7 |
| NIBIO | 19 | 13 | 10 |
| NORCE Research AS | 19 | 15 | 15 |

By decade (`document.year`; scanned = `doc_facts.text_source = 'ocr'`):

| Decade | Sampled | Scanned | Yes | Yes without borderline |
|---|---|---|---|---|
| 1940s | 1 | 0 | 0 | 0 |
| 1970s | 4 | 3 | 2 | 2 |
| 1980s | 15 | 13 | 9 | 8 |
| 1990s | 33 | 23 | 15 | 13 |
| 2000s | 55 | 2 | 36 | 27 |
| 2010s | 92 | 0 | 51 | 43 |
| 2020s | 75 | 0 | 40 | 36 |

Scanned (OCR) reports: 20 of 41 eligible (17 without borderline).

## 5 Borderline cases

Borderline reports are included and flagged (protocol 5.1). Haiku v3 flags 26
at screening (biota_contaminants 12, other 10, register_compilation 3,
catch_sampling 1) and 24 at extraction, all on eligible reports
(`screening.borderline`, `extraction.borderline`, `borderline_reason`):

| Type | n | Reports (year, publisher) |
|---|---|---|
| biota_contaminants | 11 | Moser som metallindikatorer (1984, NIVA); Miljøgifter i sediment og organismer, Ranafjorden (1993, NIVA); Miljøgift i fisk og skalldyr, Grenlandsfjordene (1996, NIVA); Kvikksølv i Sørfjorden (2000, NIVA); Kvikksølv i fisk fra innsjøer i Hedmark (2002, NIVA); Hvitt fosfor i skytefeltene (2008, NINA); Miljøundersøkelser i Sløvåg (2009, NIVA); Tilsynsprogrammet for skjell 2011 (2012, HI); Miljøgifter i Kristiansandsfjorden 2013 (2014, NIVA); Miljøgifter i Mjøsa 2016 (2017, NIVA); Health monitoring of wild anadromous salmonids (2022, HI) |
| other | 6 | Pelagisk kvalitet – tokt (2004, SINTEF Ocean); Rømt laks – atferd og gjenfangst (2007, HI); Helsetilstanden i norske skoger (2008, NIBIO); Tjære i reindrifta (2011, NIBIO); Menneskelig ferdsel på Langøra Nord (2013, HiNT); Aksjon pærebrann 2020 (2022, NIBIO) |
| register_compilation | 4 | Familiegrupper av gaupe (2008, NINA); Bestandsovervåking av jerv 2014 (2014, Rovdata/NINA); Inventering av varg 2018–2019 (2019, NINA); Inventering av lodjur 2021 (2021, NINA) |
| catch_sampling | 3 | Klororganiske forbindelser i fisk (2007, HI); Pilotanlegg for mottak av fisk (2016, Nofima); Genetiske undersøkelser av laksen i Fortunelva (2021, NINA) |

Of these 24, GLM flagged 22 (19 with the same type), Mistral 9 of 23 extracted (8 same type), Borealis none (`extraction_cmp.borderline`).

## 6 Weaknesses found

| Weakness | Evidence | Source |
|---|---|---|
| `taxon_groups` is free text | 115 distinct strings in 338 mentions | `extraction_survey.taxon_groups` |
| "other" is the most common method | 76 mentions; in 35.7 % of surveys | `extraction_survey.methods` |
| Absences rarely stated | absences_stated: not_stated 179, yes 30, no 15 (224 surveys) | `extraction_survey.absences_stated` |
| Site counts often missing | `n_sites` NA (not stated) in 42.9 % of surveys | `extraction_survey.n_sites` |
| OCR tables unreliable | running text, æøå and Latin names read well; table columns lose alignment, wide tables get noise | manual check of three pages (1979, 1981, 1996) |
| List limits | the API does not enforce `maxItems`; Haiku v3 exceeds a limit in 2 of 550 calls, Mistral in 21, Borealis in 28, GLM in none | `llm_failure`, `llm_failure_cmp` |
| NVA matching | whole words with some fuzziness, no prefixes, so compound words need their own terms; 22 of 23 gold-set NVA documents found (the last is a journal article) | `docs/design.md`, 2026-11-22 |
| English reports | 92.1 % of their selected pages are front pages only (Norwegian: 46.0 %), as the method and data keywords are Norwegian | `chunk.reasons`, `document.language` |
| Publisher name variants | in the frame: 27 strings for NINA (2,090 reports), 9 for HI (576), 5 for NIVA (2,353) | `document.publisher` |
| Network | one Haiku call hung for 3 × 5 min with 0 bytes received (likely the IPv6 hang); ellmer has no hook to set `ipresolve` | `llm_failure.error` |

## 7 Open decisions for Anders

1. Model for the full run: Haiku v3 (≈ 23 USD and ≈ 30 h sequential for the
   frame), GLM on NTNU (no token cost, ≈ 32 h at 6 parallel), or both on a
   human-checked sample first.
2. Go-ahead for the full run: PDF download (50 GB), OCR (≈ 140 core-hours),
   screening and extraction.
3. Fixed lists for methods and study type (replace "other"; add e.g.
   telemetry, genetic sampling, snow tracking) and a fixed list of taxon groups.
4. Size of the human-checked sample for screening and extraction (protocol
   5.2 and 6.3), so that models can be compared on accuracy.
5. Remaining sources after NVA (consultancies, county governors, Vannmiljø
   reports) and English-language page selection.
