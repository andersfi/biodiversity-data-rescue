-- Register schema for biodiversity-data-rescue.
-- Built by scripts/00_build_db.R through R/db.R::db_init().
-- Data model: docs/design.md, "Data model (SQLite register)".
-- Survey fields follow Humboldt Extension concepts (https://tdwg.github.io/hc/terms/)
-- where they exist; the Humboldt term is given in a comment.
-- Every entity has a stable `uri` besides its integer id (architecture rule 6).

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Every article, report or dataset found.
CREATE TABLE IF NOT EXISTS document (
  document_id     INTEGER PRIMARY KEY,
  uri             TEXT NOT NULL UNIQUE,          -- doi:..., handle:..., nva:..., url:...
  doi             TEXT,
  handle          TEXT,
  url             TEXT,
  type            TEXT NOT NULL CHECK (type IN
                    ('article', 'report', 'note', 'thesis', 'dataset', 'webpage', 'other')),
  title           TEXT NOT NULL,
  year            INTEGER,
  institution     TEXT,
  institution_ror TEXT,
  series          TEXT,                          -- e.g. "NINA Rapport 1988"
  isbn            TEXT,
  licence         TEXT,
  fulltext_status TEXT NOT NULL DEFAULT 'unknown' CHECK (fulltext_status IN
                    ('unknown', 'open', 'closed', 'fetched', 'not_found')),
  source          TEXT,                          -- API the record came from
  run_id          INTEGER REFERENCES run_log(run_id),
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- One professional sampling effort.
CREATE TABLE IF NOT EXISTS survey (
  survey_id                 INTEGER PRIMARY KEY,
  uri                       TEXT NOT NULL UNIQUE,  -- survey:<slug>
  title                     TEXT NOT NULL,
  target_taxonomic_scope    TEXT,                  -- hc:targetTaxonomicScope
  taxon_completeness        TEXT,                  -- hc:taxonCompletenessReported
  area                      TEXT,                  -- hc:geospatialScopeAreaValue (free text for now)
  sites                     TEXT,                  -- stations / vannlokalitetkode, ';'-separated
  site_count                INTEGER,               -- hc:siteCount
  period_start              TEXT,                  -- ISO 8601 date or year; hc:eventDurationValue context
  period_end                TEXT,
  protocol                  TEXT,                  -- hc:protocolNames / protocolDescriptions
  sampling_effort           TEXT,                  -- hc:samplingEffortValue + unit, free text
  absences_recorded         TEXT CHECK (absences_recorded IN
                              ('yes', 'no', 'not_stated')),  -- hc:isAbsenceReported
  responsible_institution   TEXT,
  institution_ror           TEXT,
  commissioned_by           TEXT,
  notes                     TEXT,
  created_at                TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Many-to-many link between documents and surveys.
CREATE TABLE IF NOT EXISTS document_survey (
  document_id   INTEGER NOT NULL REFERENCES document(document_id),
  survey_id     INTEGER NOT NULL REFERENCES survey(survey_id),
  role          TEXT NOT NULL CHECK (role IN ('primary', 'summary', 'mention')),
  page_evidence TEXT,                              -- e.g. "s. 12; vedlegg A"
  PRIMARY KEY (document_id, survey_id)
);

-- Relevant GBIF datasets.
CREATE TABLE IF NOT EXISTS gbif_dataset (
  gbif_dataset_id     INTEGER PRIMARY KEY,
  uri                 TEXT NOT NULL UNIQUE,        -- gbif-dataset:<key>
  dataset_key         TEXT NOT NULL UNIQUE,
  title               TEXT NOT NULL,
  dataset_type        TEXT,                        -- OCCURRENCE, SAMPLING_EVENT, ...
  publisher           TEXT,
  publisher_key       TEXT,
  publisher_ror       TEXT,
  taxonomic_coverage  TEXT,
  temporal_coverage   TEXT,
  geographic_coverage TEXT,
  method              TEXT,
  doi                 TEXT,
  fetched_at          TEXT,
  run_id              INTEGER REFERENCES run_log(run_id)
);

-- Possible survey–dataset matches, scored per dimension (docs/design.md, Matching).
CREATE TABLE IF NOT EXISTS candidate_pair (
  candidate_pair_id INTEGER PRIMARY KEY,
  uri               TEXT NOT NULL UNIQUE,          -- pair:<survey slug>--<dataset key>
  survey_id         INTEGER NOT NULL REFERENCES survey(survey_id),
  gbif_dataset_id   INTEGER NOT NULL REFERENCES gbif_dataset(gbif_dataset_id),
  subset_filter     TEXT,                          -- e.g. datasetName / recordedBy filter inside the dataset
  score_taxon       REAL,
  score_time        REAL,
  score_place       REAL,
  score_method      REAL,
  score_institution REAL,
  score_direct_link REAL,
  score_total       REAL,
  model_judgement   TEXT CHECK (model_judgement IN ('same', 'partly', 'different', 'not_stated')),
  model_reason      TEXT,
  model_run_id      INTEGER REFERENCES run_log(run_id),
  human_decision    TEXT CHECK (human_decision IN ('same', 'partly', 'different')),
  decided_by        TEXT,
  decided_at        TEXT,
  UNIQUE (survey_id, gbif_dataset_id, subset_filter)
);

-- Current status per survey. History is kept: the current row has the latest set_at.
CREATE TABLE IF NOT EXISTS survey_status (
  survey_status_id INTEGER PRIMARY KEY,
  survey_id        INTEGER NOT NULL REFERENCES survey(survey_id),
  category         TEXT NOT NULL CHECK (category IN
                     ('in_gbif', 'in_gbif_no_effort', 'partly_in_gbif',
                      'open_elsewhere', 'exists_not_available', 'unidentified')),
  taxon_group      TEXT NOT NULL DEFAULT 'EPT', -- status refers to pilot taxa (open question in design.md)
  reason           TEXT NOT NULL,
  set_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  set_by           TEXT NOT NULL
);

-- Knowledge cards loaded from knowledge/ by scripts/01_load_knowledge.R.
CREATE TABLE IF NOT EXISTS knowledge_card (
  knowledge_card_id INTEGER PRIMARY KEY,
  uri               TEXT NOT NULL UNIQUE,          -- knowledge:<id>
  card_id           TEXT NOT NULL UNIQUE,
  type              TEXT NOT NULL CHECK (type IN ('aggregator', 'source', 'precedent', 'vocabulary')),
  title             TEXT NOT NULL,
  path              TEXT NOT NULL,
  fields_json       TEXT NOT NULL,                 -- full front matter as JSON
  body              TEXT NOT NULL,
  file_sha256       TEXT NOT NULL,
  last_confirmed    TEXT NOT NULL,
  confirmed_by      TEXT NOT NULL,
  loaded_at         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Survey (or survey type) covered by an aggregator dataset such as Vannmiljø.
CREATE TABLE IF NOT EXISTS aggregator_coverage (
  aggregator_coverage_id INTEGER PRIMARY KEY,
  aggregator_card_id     TEXT NOT NULL REFERENCES knowledge_card(card_id),
  survey_id              INTEGER REFERENCES survey(survey_id),
  survey_type            TEXT,                     -- when coverage is stated for a type, not a survey
  coverage               TEXT NOT NULL CHECK (coverage IN ('full', 'partial')),
  evidence               TEXT NOT NULL,
  CHECK (survey_id IS NOT NULL OR survey_type IS NOT NULL)
);

-- Provenance per search or LLM batch (architecture rule 4).
CREATE TABLE IF NOT EXISTS run_log (
  run_id          INTEGER PRIMARY KEY,
  kind            TEXT NOT NULL CHECK (kind IN ('search', 'llm', 'gbif', 'load')),
  step            TEXT NOT NULL,
  batch           TEXT,
  backend         TEXT,                            -- claude_code | ellmer
  provider        TEXT,
  model           TEXT,
  model_version   TEXT,
  prompt_file     TEXT,
  prompt_sha256   TEXT,
  schema_version  TEXT,
  query           TEXT,                            -- for searches
  n_records       INTEGER,
  n_expected      INTEGER,                         -- total reported by the API
  input_tokens    INTEGER,                         -- NULL when unknown
  output_tokens   INTEGER,
  started_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  finished_at     TEXT
);

-- Cache of LLM answers so no record is assessed twice (architecture rule 5).
-- Not a table in the design note; required by rule 5.
CREATE TABLE IF NOT EXISTS llm_answer (
  llm_answer_id   INTEGER PRIMARY KEY,
  step            TEXT NOT NULL,
  record_uri      TEXT NOT NULL,
  content_sha256  TEXT NOT NULL,
  schema_version  TEXT NOT NULL,
  answer_json     TEXT NOT NULL,
  run_id          INTEGER NOT NULL REFERENCES run_log(run_id),
  answered_at     TEXT NOT NULL,
  UNIQUE (step, record_uri, content_sha256, schema_version)
);

CREATE INDEX IF NOT EXISTS idx_document_survey_survey ON document_survey(survey_id);
CREATE INDEX IF NOT EXISTS idx_candidate_pair_survey  ON candidate_pair(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_status_survey   ON survey_status(survey_id, set_at);
