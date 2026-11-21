# read run `2026-11-21_m5-medium-pages`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:35:42Z |
| finished | 2026-11-21T18:36:23Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-medium-pages/` |

Reading-test cell: model `medium`, input `pages`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 15670 |
| mean output tokens | 1093 |
| mean seconds | 7.8 |
| escalation rate | 0 |
| accuracy, verified rows | 0.738 (n = 28) |
| accuracy, all rows | 0.756 (n = 30) |
| invented values, all rows | 2 of 3 |
| station precision / recall | 0 / 0 |
| key pages inside selected pages | 0.68 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 14719 | 2 | 11940 | 2777 | 1807 | 11.5 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 11683 | 2 | 8904 | 2777 | 255 | 3.9 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 17826 | 2 | 15047 | 2777 | 387 | 4.3 |  |
| NINA Rapport 1988 | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 16494 | 2 | 13715 | 2777 | 292 | 4.3 | not_stated_vs_pages:data_statement |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 17630 | 2 | 14851 | 2777 | 2722 | 15 | count_mismatch:stations |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- NINA Rapport 1988 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): count_mismatch
