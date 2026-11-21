# read run `2026-11-21_m5-medium-summary`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:33:26Z |
| finished | 2026-11-21T18:33:47Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-medium-summary/` |

Reading-test cell: model `medium`, input `summary`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 6834 |
| mean output tokens | 302 |
| mean seconds | 4 |
| escalation rate | 0 |
| accuracy, verified rows | 0.723 (n = 28) |
| accuracy, all rows | 0.708 (n = 30) |
| invented values, all rows | 0 of 3 |
| station precision / recall | NaN / 0 |
| key pages inside selected pages | 0.48 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 5 | 6368 | 2 | 6366 | 0 | 443 | 4.9 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 4 | 7406 | 2 | 4627 | 2777 | 255 | 3.6 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 6 | 8135 | 2 | 5356 | 2777 | 240 | 3.7 | not_stated_vs_pages:data_statement |
| NINA Rapport 1988 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 5 | 7231 | 2 | 4452 | 2777 | 332 | 4.2 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 3 | 5028 | 2 | 2249 | 2777 | 240 | 3.6 | not_stated_vs_pages:data_statement |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- NIVA-rapport 6784 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): not_stated_vs_pages
