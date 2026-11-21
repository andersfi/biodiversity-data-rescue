# read run `2026-11-21_m5-large-pages`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:36:25Z |
| finished | 2026-11-21T18:38:41Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-large-pages/` |

Reading-test cell: model `large`, input `pages`, cascade `FALSE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 20627 |
| mean output tokens | 3672 |
| mean seconds | 26.8 |
| escalation rate | 0 |
| accuracy, verified rows | 0.772 (n = 28) |
| accuracy, all rows | 0.787 (n = 30) |
| invented values, all rows | 2 of 3 |
| station precision / recall | 0 / 0 |
| key pages inside selected pages | 0.68 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 14711 | 2 | 11932 | 2777 | 1715 | 13.9 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 11675 | 2 | 8896 | 2777 | 515 | 6.1 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 17821 | 2 | 15042 | 2777 | 2112 | 16.7 |  |
| NINA Rapport 1988 | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 16489 | 2 | 13710 | 2777 | 1013 | 10.3 | not_stated_vs_pages:data_statement |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 42441 | 4 | 22039 | 20398 | 13004 | 87 | not_stated_vs_pages:data_statement; not_stated_vs_pages:stations; count_mismatch:stations |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- NINA Rapport 1988 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): not_stated_vs_pages, count_mismatch
