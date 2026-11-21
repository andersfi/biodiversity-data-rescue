# read run `2026-11-21_m5-cascade-summary`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:46:06Z |
| finished | 2026-11-21T18:47:32Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-cascade-summary/` |

Reading-test cell: model `small`, input `summary`, cascade `TRUE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 17628 |
| mean output tokens | 1980 |
| mean seconds | 16.9 |
| escalation rate | 0.8 |
| accuracy, verified rows | 0.732 (n = 28) |
| accuracy, all rows | 0.717 (n = 30) |
| invented values, all rows | 0 of 3 |
| station precision / recall | NaN / 0 |
| key pages inside selected pages | 0.48 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 5 | 6390 | 2 | 373 | 6015 | 1678 | 8.2 | not_stated_vs_pages:data_statement |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 5 | 6369 | 2 | 352 | 6015 | 432 | 4.8 | not_stated_vs_pages:data_statement |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 5 | 6368 | 2 | 351 | 6015 | 524 | 5.8 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 4 | 7425 | 2 | 371 | 7052 | 1067 | 6.3 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 4 | 7405 | 2 | 351 | 7052 | 251 | 4.2 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 4 | 7401 | 2 | 347 | 7052 | 383 | 5.6 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 6 | 8157 | 2 | 373 | 7782 | 1375 | 8.6 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 6 | 8138 | 2 | 354 | 7782 | 240 | 6.1 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 6 | 8131 | 2 | 347 | 7782 | 547 | 9.9 | not_stated_vs_pages:data_statement |
| NINA Rapport 1988 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 5 | 7253 | 2 | 374 | 6877 | 1304 | 7 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 3 | 5051 | 2 | 374 | 4675 | 1365 | 7.9 | not_stated_vs_pages:data_statement |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 3 | 5028 | 2 | 351 | 4675 | 230 | 4.1 | not_stated_vs_pages:data_statement |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 3 | 5026 | 2 | 349 | 4675 | 506 | 6.2 | not_stated_vs_pages:data_statement |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- NIVA-rapport 6784 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): not_stated_vs_pages
