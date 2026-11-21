# read run `2026-11-21_m5-large-full`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:41:29Z |
| finished | 2026-11-21T18:46:03Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-large-full/` |

Reading-test cell: model `large`, input `full`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 112221 |
| mean output tokens | 7803 |
| mean seconds | 54.5 |
| escalation rate | 0 |
| accuracy, verified rows | 0.859 (n = 28) |
| accuracy, all rows | 0.868 (n = 30) |
| invented values, all rows | 2 of 3 |
| station precision / recall | 0.5 / 0.667 |
| key pages inside selected pages | 1 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 30 | 31598 | 2 | 28819 | 2777 | 1712 | 13.8 |  |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 41 | 35168 | 2 | 32389 | 2777 | 577 | 7.2 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 45 | 107390 | 4 | 53192 | 54194 | 8322 | 57.3 |  |
| NINA Rapport 1988 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 62 | 54842 | 2 | 52063 | 2777 | 3133 | 22.8 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 172 | 332109 | 4 | 170302 | 161803 | 25270 | 171.3 | not_stated_vs_pages:data_statement; not_stated_vs_pages:stations; count_mismatch:stations |

## Review list

- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): not_stated_vs_pages, count_mismatch
