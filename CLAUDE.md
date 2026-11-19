# biodiversity-data-rescue

Rules for working in this repository. What the project is, the zones and the verbs:
`README.md`. Design, data model, status categories, the gold set, the LLM file
contract and the decision log: `docs/design.md` (read it before changing structure).

Owner: Anders G. Finstad (NTNU, Gjærevollsenteret). Public repo on the personal
GitHub account `andersfi` during the pilot; it will move to an organisation later.
Everything committed is public: no full texts, no long quotes, no secrets.

## Phase and scope

- Pilot: build the gold set, measure find, read and match separately, then widen
  the scope step by step.
- Scope lives in `config/scope.yaml` and will change. Never hard-code taxa,
  regions or periods.
- No large searches or LLM batches before Anders has approved the scope and the
  gold set.

## Working with Anders

- He writes Norwegian; answer in Norwegian (bokmål). Code, comments, file names,
  identifiers and commit messages are in English.
- He is a domain expert (GBIF, Darwin Core, freshwater surveys) and reads R best.
  Explain design choices briefly; skip basics.
- Ask before: `sudo`; new R packages; deleting or overwriting anything outside
  `data/`; changing the database schema; adding a data source, an LLM provider or
  any service that receives data (the read-only APIs in `docs/design.md` are fine).
- Structural redesign decisions go back to Anders. When a decision is made, add it
  to the decision log at the end of `docs/design.md` and update this file if needed.
- Start every summary with deviations and what you were unsure of.
- No numbers estimated by hand: what has not been run says "not run".

## Git and attribution (hard rule)

- Never list Claude or any AI as author, co-author or contributor. No
  `Co-Authored-By` lines and no "Generated with Claude Code" in commits or PRs.
  Anders is the sole author; he declares AI use himself.
- Small commits with descriptive English messages.
- Never commit `data/`, `.env`, API keys, PDFs or other full texts.

## Repository rules

- One entry point: `Rscript run.R <verb>`. A new pipeline step is a verb backed by
  `R/cmd_<verb>.R`; no stand-alone scripts, never two ways to do the same thing.
- Only `run.R` writes to `runs/`. Run folders and `metrics.json` are committed;
  large intermediate files go to `data/runs/`.
- `goldset/goldset.csv` is the only answer key. `gbif_dataset_keys` is never an
  input to matching.

## Architecture rules

1. All LLM calls go through `R/llm.R`. Nothing else talks to a model.
2. All database access goes through named functions in `R/db.R`. No SQL elsewhere.
3. Every LLM answer is validated against its JSON Schema before it touches the
   database. Invalid answers raise an error; they are not repaired silently.
4. Every LLM batch is logged in `run_log`: backend, provider, model and version,
   prompt file and its SHA-256, schema version, number of records, input and
   output tokens (NA if unknown), timestamp, run folder.
5. Never assess the same record twice. Cache key: record URI + SHA-256 of the
   content sent + schema version. Re-runs send only new or changed records.
6. Every entity has a stable URI (`doi:…`, `handle:…`, `survey:<slug>`,
   `gbif-dataset:<key>`) besides its integer id.
7. Explicit failure. No silent fallbacks and no catch-and-continue over API
   errors. Check fetched counts against the totals the API reports.
8. The model is never a search engine. Records come only from API results; the
   model writes queries and reads records.
9. "not_stated" is always an allowed value in extraction schemas. The model must
   not fill in values the source does not give.
10. Prompts live as files in `prompts/`, versioned by git, never only in the DB.
11. Use the smallest model that passes the gold set. Send only the knowledge cards
    relevant to a batch, and only the relevant pages of a full text.

When you act as the `claude_code` backend: follow the prompt file exactly, answer
only from the record and the knowledge cards supplied with the batch, use
`not_stated` when the source is silent, write valid JSONL, and report the model
you ran as.

## Data and full texts

- `data/` stays local. Raw API responses are kept as received; every query is
  logged in `runs/queries.jsonl`.
- Full texts are copyrighted: never commit them; quote only short passages with
  page numbers. Ask before bulk full-text harvesting (the research TDM exception
  is not confirmed in force in Norway).
- `goldset/fulltext/` may be read only by the `read` verb (through
  `R/fulltext.R`). Search and screening never read it.

## Machine notes

- R 4.5 with renv; packages compile from source. A failed install usually means a
  missing system `-dev` library: find it, then ask before `sudo apt install`.
- IPv6 can hang on this machine; `~/.curlrc` only fixes the curl CLI. If an httr2
  request hangs, force IPv4 (`req_options(ipresolve = 1)`).
- Python only where R has no reasonable option (GROBID or Docling later), in a
  project venv. Quarto is not installed; ask before adding reports that need it.
