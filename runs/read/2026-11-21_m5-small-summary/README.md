# read run `2026-11-21_m5-small-summary`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:32:48Z |
| finished | 2026-11-21T18:33:23Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-small-summary/` |

Reading-test cell: model `small`, input `summary`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 6854 |
| mean output tokens | 1238 |
| mean seconds | 6.8 |
| escalation rate | 0 |
| accuracy, verified rows | 0.708 (n = 28) |
| accuracy, all rows | 0.694 (n = 30) |
| invented values, all rows | 0 of 3 |
| station precision / recall | NaN / 0 |
| key pages inside selected pages | 0.48 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 5 | 6390 | 2 | 6388 | 0 | 1401 | 7.7 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 4 | 7424 | 2 | 4645 | 2777 | 1159 | 6.5 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 6 | 8157 | 2 | 5378 | 2777 | 1098 | 6.3 | not_stated_vs_pages:data_statement |
| NINA Rapport 1988 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 5 | 7250 | 2 | 4471 | 2777 | 1328 | 6.9 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 3 | 5050 | 2 | 2271 | 2777 | 1204 | 6.4 | not_stated_vs_pages:data_statement |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- NIVA-rapport 6784 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): not_stated_vs_pages
