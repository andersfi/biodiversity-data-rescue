# read run `2026-11-21_m5-cascade-pages`

| item | value |
| :--- | :--- |
| started | 2026-11-21T18:47:35Z |
| finished | 2026-11-21T18:50:33Z |
| git commit | `184945e` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_m5-cascade-pages/` |

Reading-test cell: model `small`, input `pages`, cascade `TRUE`, repeats 1.

Scores against `goldset/extraction_truth.csv` and `goldset/stations.csv`.
The key is drafted by Claude and counts only where `verified = yes`;
scores over all rows are shown separately until the key is verified.

| measure | value |
| :--- | :--- |
| documents | 5 |
| mean input tokens per document | 36599 |
| mean output tokens | 6214 |
| mean seconds | 35.1 |
| escalation rate | 0.8 |
| accuracy, verified rows | 0.766 (n = 28) |
| accuracy, all rows | 0.782 (n = 30) |
| invented values, all rows | 2 of 3 |
| station precision / recall | 0 / 0 |
| key pages inside selected pages | 0.68 |
| end-to-end match | not built |

## Calls

| document | repeat_no | step | size | model_requested | models_reported | n_pages | input_total | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | output_tokens | seconds | rules_fired |
| :--- | ---: | ---: | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 14738 | 2 | 373 | 14363 | 4121 | 16.8 | not_stated_vs_pages:data_statement |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 14718 | 2 | 353 | 14363 | 1869 | 11.7 | not_stated_vs_pages:data_statement |
| NTNU VM naturhistorisk notat 2018-14 | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 14714 | 2 | 349 | 14363 | 1737 | 14.6 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 11704 | 2 | 375 | 11327 | 1460 | 7.9 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 11683 | 2 | 354 | 11327 | 248 | 3.9 | not_stated_vs_pages:data_statement |
| Sweco fagrapport naturmangfold, prosjekt 10242512 | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 11678 | 2 | 349 | 11327 | 558 | 6.9 | not_stated_vs_pages:data_statement |
| NIVA-rapport 6784 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 17846 | 2 | 374 | 17470 | 4327 | 16.7 |  |
| NINA Rapport 1988 | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 16517 | 2 | 374 | 16141 | 1593 | 8.3 | not_stated_vs_pages:data_statement |
| NINA Rapport 1988 | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 16496 | 2 | 353 | 16141 | 346 | 4 |  |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 1 | small | claude-haiku-5-5 | claude-haiku-5-5 | 11 | 17649 | 2 | 373 | 17274 | 4848 | 19.2 | count_mismatch:stations |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 2 | medium | claude-sonnet-5-5 | claude-sonnet-5-5 | 11 | 17628 | 2 | 352 | 17274 | 2641 | 14.3 | count_mismatch:stations |
| Vannovervåking i Trondheim 2020 (TM 2021/01) | 1 | 3 | large | claude-opus-5-5 | claude-opus-5-5 | 11 | 17624 | 2 | 348 | 17274 | 7323 | 51.1 | not_stated_vs_pages:stations; not_stated_vs_pages:data_statement; count_mismatch:stations |

## Review list

- NTNU VM naturhistorisk notat 2018-14 (repeat 1): not_stated_vs_pages
- Sweco fagrapport naturmangfold, prosjekt 10242512 (repeat 1): not_stated_vs_pages
- Vannovervåking i Trondheim 2020 (TM 2021/01) (repeat 1): not_stated_vs_pages, count_mismatch
