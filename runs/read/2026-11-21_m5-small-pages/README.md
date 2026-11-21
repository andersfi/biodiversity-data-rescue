# read run `2026-11-21_m5-small-pages`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:34:27Z |
| finished | 2026-11-21T18:35:40Z |
| git commit | `184945e` |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-small-pages/` |

Reading-test cell: model `small`, input `pages`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 15689 |
| mean output tokens | 3406 |
| mean seconds | 14.1 |
| escalation rate | 0 |
| accuracy, verified rows | 0.819 (n = 28) |
| accuracy, all rows | 0.831 (n = 30) |
| invented values, all rows | 1 of 3 |
| station precision / recall | 0.091 / 0.333 |
| key pages inside selected pages | 0.68 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 14738 | 2 | 11959 | 2777 | 4535 | 18.5 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 11700 | 2 | 8921 | 2777 | 1479 | 8.1 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 17845 | 2 | 15066 | 2777 | 5002 | 19.3 |  |
| NINA Rapport 1988 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 16516 | 2 | 13737 | 2777 | 1726 | 8.5 | not_stated_vs_pages:data_statement |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 17647 | 2 | 14868 | 2777 | 4287 | 16 | count_mismatch:stations |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- NINA Rapport 1988 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): count_mismatch
