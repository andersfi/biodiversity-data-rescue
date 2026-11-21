# read run `2026-11-21_m5-medium-full`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:40:22Z |
| finished | 2026-11-21T18:41:26Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-medium-full/` |

Reading-test cell: model `medium`, input `full`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 66418 |
| mean output tokens | 2117 |
| mean seconds | 12.6 |
| escalation rate | 0 |
| accuracy, verified rows | 0.864 (n = 28) |
| accuracy, all rows | 0.873 (n = 30) |
| invented values, all rows | 1 of 3 |
| station precision / recall | 0.5 / 0.667 |
| key pages inside selected pages | 1 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 30 | 31606 | 2 | 28827 | 2777 | 1472 | 8.9 | value_not_in_text:stations |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 41 | 35177 | 2 | 32398 | 2777 | 278 | 4.3 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 45 | 51428 | 2 | 48649 | 2777 | 3494 | 18.7 |  |
| NINA Rapport 1988 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 62 | 54848 | 2 | 52069 | 2777 | 2904 | 15.4 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 172 | 159032 | 2 | 156253 | 2777 | 2437 | 15.5 | count_mismatch:stations |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): value_not_in_text
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): count_mismatch
