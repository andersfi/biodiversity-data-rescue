# Reading benchmark (phase 3): plan

Status: **approved 2026-11-21 (decision log in `docs/design.md`); built:**
`run.R read pages | step0 | <label>`, `R/read.R`, `llm_cli_call` in `R/llm.R`,
`schemas/extraction.json`, `prompts/extraction.md`, `config/read.yaml`, the
page-keyword card and a draft `goldset/extraction_truth.csv` (unverified).
**Not built:** the end-to-end score through `match` (section 3, "final
status"). Every number marked "not run" is measured in the runs below, never
estimated by hand.

The reading link answers one question: given a gold-set document, does the model
extract the fields that matching needs, without inventing values? It is measured
on the local full texts in `goldset/fulltext/` (allowed for the `read` verb
only, decided 2026-11-19) and scored twice: per field against an answer key, and
end to end by running the extracted description through `run.R match` and
comparing the band with the gold status.

## 1. Answer key

### What reading must deliver

Phase 2 matching (`R/match.R`, `MATCH_INPUT_COLUMNS` plus `goldset/stations.csv`)
uses these survey fields. Title, documents and `doc_ids` come from bibliographic
metadata (the find link), not from reading. Reading must deliver:

| Field | Used by matching as | Answer key |
|---|---|---|
| `period` | years sampled (station-years) | `goldset/extraction_truth.csv` |
| `institution` | institution evidence: the publisher (utgiver) of the document (rule from Anders 2026-11-21) | `extraction_truth.csv` |
| `stations` | station name, waterbody, x/y + crs as printed, vannlokalitetkode, years, former municipality | `goldset/stations.csv` (already drafted, `verified = no`) |
| `region` | place names when no stations are given | `extraction_truth.csv` |
| `taxon_scope` | were EPT sampled at all (yes/no/not_stated) | `extraction_truth.csv` |
| `data_statement` | not used by matching today; needed to tell `open_elsewhere` (species lists in an appendix, Vannmiljø) from `exists_not_available` ("on request") | `extraction_truth.csv` |

`data_statement` categories: `appendix_species_list`, `vannmiljo`, `gbif`,
`other_database`, `on_request`, `other_report` (data in another report the
document refers to), `not_stated`. `vannmiljo` only when the document says its
own data were reported there, not when it used data from Vannmiljø.

`data_statement` is included because matching cannot separate the two
not-in-GBIF statuses; only the document can.

### `goldset/extraction_truth.csv`

One row per document × field (stations stay in `stations.csv`, one row per
station, so they are not duplicated):

```
survey_ref, document, field, value, page, verified
trd-bunndyr-2020, NINA Rapport 1988, period, 2020, 9, no
trd-bunndyr-2020, NINA Rapport 1988, institution, NINA, 2, no
trd-bunndyr-2020, NINA Rapport 1988, data_statement, "artsliste per stasjon i vedlegg", 40, no
trd-bunndyr-2014, ..., stations, not_stated, , no
```

- `value = not_stated` is a valid answer: the document does not give it. These
  rows are what the "invented values" rate is measured on.
- `document` is the `document` column of `goldset/fulltext_manifest.csv`; the
  key is per document, because a summary report and the primary report for the
  same year can say different things.
- Validated by `run.R check` like `stations.csv` (field names from a fixed list,
  survey_ref and document must exist).

### Which documents

All 18 local full texts in `goldset/fulltext_manifest.csv`. They cover 12
gold-set surveys and include the useful contrasts: primary report vs annual
summary for the same year (2020–2023), coordinates given (2013, 2019–2023,
Bymarka) vs names only (2024–2025), one multi-survey note
(`2018-14 Notat Gjettjønna`) and one document that only cites a survey (Sweco).
Fewer than 18 loses one of these contrasts; more needs full texts that are not
there (2009–2012, 2014–2018; the NTNU rows).

### Manual work for Anders

Claude drafts the key from the full texts (as for `stations.csv`), every row
`verified = no`, with page numbers; Anders checks it. The work is counted in
values to check, not hours:

- stations: 259 rows in `goldset/stations.csv` (already drafted);
- other fields: 18 documents × 5 fields = 90 values in `extraction_truth.csv`
  (to be drafted).

The circularity risk (Claude drafts the key that Claude is then tested against)
is handled by the check: only rows with `verified = yes` count, and the report
gives the score separately for verified and unverified rows until all are
verified.

## 2. Cascade

1. **Page selection (script, no model).** `pdftotext` per page (poppler is
   installed; no new package). Keep pages 1–3 (title page, colophon:
   institution, report number) plus the top-k pages by a keyword score. The
   keywords come from a knowledge card (`knowledge/`), not from code: station
   table words (stasjon, St.nr., UTM, Øst, Nord, kartreferanse,
   vannlokalitet), period words (innsamlet, prøvetatt, dato, month names),
   data words (vedlegg, artsliste, Vannmiljø, GBIF, data). `k` lives in
   `config/read.yaml`. Page selection is scored on its own: share of answer-key
   `page` values inside the selected pages.
2. **Small model on the selected pages**, with the extraction prompt, the
   schema and only the relevant knowledge cards.
3. **Escalate to the next model size** (small → medium → large) for a document
   when any of these holds:
   - **Schema failure:** the answer does not validate against
     `schemas/extraction.json` (one retry is not allowed; it escalates).
   - **Value not in the text:** an extracted coordinate, vannlokalitetkode,
     station number or year does not occur verbatim in the selected pages'
     text. This is the main guard against invented values.
   - **not_stated against the pages:** the model says `not_stated` but the
     selected pages match the field's trigger pattern (UTM pair or decimal
     coordinates for `stations`, a four-digit year next to a sampling word for
     `period`, "vedlegg"/"artsliste"/"Vannmiljø" for `data_statement`).
   - **Count mismatch:** the number of stations extracted differs from the
     number of coordinate-like table rows found by the page script.
   - **Two readings disagree** (only in cells with repeated readings): the
     two small-model readings differ on any field after normalisation.
   The rules are exact and logged per document: which rule fired, on which
   field, and what the bigger model then answered.
4. The large model's answer is final. If it still breaks a rule, the document
   goes to a review list (as uncertain matches do); it is not repaired.

## 3. Test matrix

Axes:

- **model size:** small, medium, large (section 5);
- **input:** `summary` (the document's own sammendrag/abstract pages, found by
  the page script), `pages` (selected pages), `full` (whole text);
- **cascade:** off (one model only) or on (starts small, escalates).

The cascade only makes sense starting small, so the cells are 3 sizes × 3
inputs without cascade (9 cells) plus cascade on for `summary` and `pages` (2
cells): **11 cells**. Each cell is one run in `runs/read/<date>_<cell>/`.

Per cell, reported in the run's `README.md` and `metrics.json`:

| Measure | Definition |
|---|---|
| accuracy per field | exact or normalised match with `verified = yes` key rows; stations scored per station (name + coordinates within 50 m or code equal) with precision and recall |
| invented values | share of key rows `not_stated` where the model gave a value; Wilson 95 % interval |
| final status | the extracted description run through `match` (same `config/match.yaml`); confusion table gold status × band, and false "unpublished" as in phase 2 |
| tokens and time | input and output tokens and seconds per report, as reported by Claude Code; for cascade cells also per step and the escalation rate |
| tokens vs accuracy | one figure: x = mean tokens per report (log), y = field accuracy, one point per cell, colour = input, shape = cascade |

Costs are given as tokens, always relative to the cheapest cell; never
converted to kroner.

## 4. Backend

### Command (from the installed CLI, `claude --help`, version 2.1.328)

Flags confirmed in the installed help text: `-p/--print`, `--model`,
`--output-format json`, `--json-schema`, `--system-prompt`, `--tools ""`,
`--strict-mcp-config`, `--mcp-config`, `--setting-sources`,
`--disable-slash-commands`, `--no-session-persistence`, `--permission-mode`.
`--bare` would give the cleanest context but reads only `ANTHROPIC_API_KEY`,
not the subscription login, so it cannot be used now.

Proposed command, run by `R/llm.R` for one document in a fresh empty temporary
directory:

```sh
cd "$(mktemp -d)" && claude -p \
  --model <model id from config/read.yaml> \
  --output-format json \
  --json-schema "$(cat <repo>/schemas/extraction.json)" \
  --system-prompt "$(cat <repo>/prompts/extraction.md)" \
  --tools "" \
  --strict-mcp-config \
  --setting-sources "" \
  --disable-slash-commands \
  --no-session-persistence \
  < record.txt          # selected pages + relevant knowledge cards
```

To verify in step 0 before anything is built on it: that `-p` reads the record
from stdin, that `--setting-sources ""` is accepted, and which fields the JSON
output carries (model, input/output tokens, duration). Not run.

### Clean context

Each reading may see only the prompt, the record (pages) and the relevant
cards. How this is ensured:

- the working directory is a new empty temp directory, so no project
  `CLAUDE.md`, gold set, answer key or repo files are discovered;
- `--tools ""` removes every tool: the model cannot read files, run commands
  or fetch anything, even if something were reachable;
- `--strict-mcp-config` without `--mcp-config`: no MCP servers;
  `--setting-sources ""`: no user, project or local settings;
  `--disable-slash-commands`: no skills; `--no-session-persistence`: nothing
  saved or resumed;
- `--system-prompt` replaces the default system prompt.

Tested two ways:

1. **Without a model (testthat):** the command built by `R/llm.R` has all the
   flags above and a working directory outside the repo; the record sent
   contains no gold-set survey_ref, `expected_status`, `where_data_are` or
   answer-key value (checked against `goldset/goldset.csv`,
   `goldset/stations.csv` and `goldset/extraction_truth.csv`).
2. **With a model, once (canary):** a record that asks the model to repeat
   any instructions, file contents or memory it has besides the record. The
   test fails if the answer contains a canary string from the repo's
   `CLAUDE.md`, `~/.claude/CLAUDE.md`, the auto-memory index or the gold set.
   This also shows whether user-level memory still leaks in without `--bare`;
   if it does, the plan stops there and goes back to Anders.

### Step 0 result (run `runs/read/2026-11-21_step0-c/`)

- All flags exist in CLI 2.1.330; the record is read from stdin;
  `--setting-sources ""` is accepted. `--json-schema` rejects the draft
  2020-12 `$schema` key, so `R/llm.R` drops it from the model-facing schema.
- Canary: none of the 121 canary strings (repo `CLAUDE.md`, the auto-memory
  index, gold-set survey_refs) came back. But the replaced system prompt is
  not the whole context: the model still reported the temporary working
  directory, platform, date, its model id, and that it "has an account email
  address for the user" (the address itself was not repeated). So the CLI
  injects environment and account context even with `--system-prompt`. None of
  it is gold-set information, but the context is not strictly "prompt +
  record + cards". The model also declined to repeat its instructions
  verbatim, so the canary shows absence of leaks only as far as the model is
  willing to reveal them.
- Overhead: 612 input tokens for a one-word call without schema; 3342 with the
  extraction prompt and schema and a one-character record.

### Overhead

Run once with an empty record (same flags) and log the input tokens: that is
Claude Code's own system-prompt overhead per call. It is subtracted where
tokens are compared across cells and reported separately. Not run.

### Logging

`run_log` stays one row per batch (backend, model, prompt SHA-256, schema
version, summed tokens, run folder), as rule 4 requires. Per-document values
(model actually used, cascade step, rule that fired, input and output tokens,
seconds) go to `runs/read/<id>/calls.tsv`. This avoids a register schema
change; if Anders prefers a `llm_call` table, that is a schema change to
approve.

### Run configuration

`config/read.yaml`, backend-neutral:

```yaml
backend: claude_code          # claude_code | ellmer (stub)
models:                       # per step; ids as the backend names them
  small: <id>
  medium: <id>
  large: <id>
cell:
  model: small                # or cascade
  input: pages                # summary | pages | full
  cascade: false
  repeats: 1
pages:
  first_pages: 3
  top_k: 8
```

`run.R read <cell-label>` reads this file; one matrix cell is one run.
`ellmer` keeps the same function signature and logging and stops with an
explicit "not implemented" error, as today.

### Subscription limits

The matrix runs on Anders' subscription, whose limits are not known here. The
`full` cells are the risk: the largest local text is 218 pages. Proposed
order, stopping after each step to look at the numbers:

1. step 0: flag check, canary test, overhead (3 calls);
2. reduced matrix: all 11 cells, but 5 documents per cell and 1 reading;
3. if the limits allow: all 18 documents per cell;
4. repeats (section 5).

The reduction is in documents per cell, not in cells, so every comparison
stays possible. If the reduced matrix already hits the limit, `full` cells are
run on the 5 shortest documents and marked as such.

## 5. Recommendations

**Model sizes**, from what the installed Claude Code offers (aliases in
`claude --help`: `fable`, `opus`, `sonnet`; Haiku by full id):

- small: Haiku 5.5 (`claude-haiku-5-5`)
- medium: Sonnet 5.5 (`claude-sonnet-5-5`)
- large: Opus 5.5 (`claude-opus-5-5`)

Fable 5.2 is also available; where it belongs is a decision for Anders, not
assumed here.

**Repeated readings.** Claude Code does not expose temperature, so readings
can differ between runs. Start with 1 reading per cell (step 2 above), then 3
readings for the cells that matter (the cheapest cell that passes, and its
neighbours). Three readings show whether disagreement exists and what it
costs; more are only worth it if three disagree often. The agreement rate is
reported per field.

## 6. Scaling to Norway

The national estimate is a formula, filled in only with measured or sourced
numbers:

```
tokens = N_reports × T_report × (1 + e) × r + N_reports × O
```

- `N_reports`: number of relevant reports in Norway. **Not guessed.** It must
  come from counts in the sources: NVA (report series NINA Rapport, NIVA-rapport,
  NTNU VM notat and others, filtered on freshwater / benthos), Vannmiljø
  (registered investigations per contractor), Miljødirektoratets
  rapportdatabase, and county-governor report series. Each count with its query
  in `runs/queries.jsonl`.
- `T_report`: tokens per report for the chosen cell (measured, section 3).
- `e`: escalation rate of the cascade (measured).
- `r`: readings per report (1 in production unless section 5 says otherwise).
- `O`: Claude Code overhead per call (measured, section 4).

Assumptions stated with the estimate: the gold-set documents are
representative of the national mix (they are not: one municipality, mostly
NINA/NIVA annual reports); report length distribution taken from NVA metadata
where page counts exist.

## Decisions needed from Anders

1. Fields for `extraction_truth.csv` (section 1): the five fields plus
   stations, including `data_statement`.
2. Claude drafts `extraction_truth.csv` like `stations.csv`, Anders verifies.
3. Per-document logging in `calls.tsv` (no schema change) or an `llm_call`
   table (schema change).
4. Model sizes, and where Fable 5.2 belongs.
5. The step order for the subscription (section 4), with a stop after step 0.
