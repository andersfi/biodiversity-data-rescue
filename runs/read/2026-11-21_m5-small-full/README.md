# read run `2026-11-21_m5-small-full`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:38:43Z |
| finished | 2026-11-21T18:40:19Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-small-full/` |

Reading-test cell: model `small`, input `full`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 66437 |
| mean output tokens | 4879 |
| mean seconds | 18.9 |
| escalation rate | 0 |
| accuracy, verified rows | 0.807 (n = 28) |
| accuracy, all rows | 0.786 (n = 30) |
| invented values, all rows | 2 of 3 |
| station precision / recall | 0.5 / 0.667 |
| key pages inside selected pages | 1 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 30 | 31624 | 2 | 28845 | 2777 | 4333 | 17.6 |  |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 41 | 35193 | 2 | 32414 | 2777 | 1488 | 8.6 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 45 | 51447 | 2 | 48668 | 2777 | 5803 | 20.9 |  |
| NINA Rapport 1988 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 62 | 54868 | 2 | 52089 | 2777 | 7194 | 26 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 172 | 159053 | 2 | 156274 | 2777 | 5575 | 21.3 |  |

## Review list

- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
