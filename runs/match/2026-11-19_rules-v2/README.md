# match run `2026-11-19_rules-v2`

| item | value |
| :--- | :--- |
| started | 2026-11-19T13:27:08Z |
| finished | 2026-11-19T13:27:09Z |
| git commit | `2d18980` + uncommitted changes |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/match/2026-11-19_rules-v2/` |

Gold-set rows matched against 18,415 scope records from gbif run `2026-11-19_all-records`, as if every row were read perfectly (no LLM, no search). Thresholds: `config/match.yaml` (copied in `config/`).

Only include = yes rows count (n = 0). Candidate rows (n = 48) are shown separately and are **provisional**.

## Main metric and error rates

| include | rows | n | false "unpublished" | false "published" | uncertain |
| :--- | :--- | ---: | :--- | :--- | :--- |
| yes | all | 0 | 0/0 | 0/0 | 0/0 |
| yes | not found via gbif_baseline | 0 | 0/0 | 0/0 | 0/0 |
| candidate (provisional) | all | 48 | 0/19 (0 %, 95 % CI 0–17 %) | 0/13 (0 %, 95 % CI 0–23 %) | 21/48 (44 %, 95 % CI 31–58 %) |
| candidate (provisional) | not found via gbif_baseline | 25 | 0/6 (0 %, 95 % CI 0–39 %) | 0/13 (0 %, 95 % CI 0–23 %) | 21/25 (84 %, 95 % CI 65–94 %) |

## Confusion table: expected_status × band

include = yes:

(no rows)

include = candidate (provisional):

| expected_status | likely_in_gbif | uncertain | likely_not_in_gbif |
| :--- | ---: | ---: | ---: |
| in_gbif | 15 | 0 | 0 |
| partly_in_gbif | 0 | 4 | 0 |
| open_elsewhere | 0 | 11 | 2 |
| todo | 10 | 6 | 0 |

## Errors

None.

## partly_in_gbif: computed coverage vs notes

| survey_ref | band | coverage | years | notes |
| :--- | :--- | :--- | :--- | :--- |
| trd-bunndyr-2014 | uncertain | NA | 0/1 | Antall stasjoner fra NVA-sammendraget. GBIF viser bare stasjoner med EPT-funn, så andelen kan være undervurdert. [found_via: kjent årlig serie, jf. forordet i … |
| trd-bunndyr-2015 | uncertain | NA | 0/1 | Antall stasjoner fra NVA-sammendraget. GBIF viser bare stasjoner med EPT-funn, så andelen kan være undervurdert. [found_via: kjent årlig serie, jf. forordet i … |
| trd-bunndyr-2016 | uncertain | NA | 0/1 | Antall stasjoner fra NVA-sammendraget. GBIF viser bare stasjoner med EPT-funn, så andelen kan være undervurdert. [found_via: kjent årlig serie, jf. forordet i … |
| trd-bunndyr-2017 | uncertain | NA | 0/1 | Antall stasjoner fra NVA-sammendraget. GBIF viser bare stasjoner med EPT-funn, så andelen kan være undervurdert. [found_via: kjent årlig serie, jf. forordet i … |

## All surveys

| survey_ref | include | gold | band | score | coverage | located | place | inst | name | link |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | ---: | :--- |
| trd-bunndyr-2009 | candidate | open_elsewhere | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2010 | candidate | open_elsewhere | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2011 | candidate | open_elsewhere | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2012 | candidate | open_elsewhere | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2013 | candidate | open_elsewhere | likely_not_in_gbif | 0.00 | 0 % | 100 % | 0.00 | NA | 0 | NA |
| trd-bunndyr-2014 | candidate | partly_in_gbif | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2015 | candidate | partly_in_gbif | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2016 | candidate | partly_in_gbif | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2017 | candidate | partly_in_gbif | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2018 | candidate | open_elsewhere | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-bunndyr-2019 | candidate | open_elsewhere | uncertain | 0.09 | 14 % | 100 % | 0.14 | 0 | 0 | NA |
| trd-bunndyr-2020 | candidate | open_elsewhere | uncertain | 0.02 | 3 % | 100 % | 0.03 | 0 | 0 | NA |
| trd-bunndyr-2021 | candidate | open_elsewhere | uncertain | 0.02 | 3 % | 100 % | 0.03 | 0 | 0 | NA |
| trd-bunndyr-2022 | candidate | open_elsewhere | uncertain | 0.06 | 9 % | 100 % | 0.09 | 0 | 0 | NA |
| trd-bunndyr-2023 | candidate | open_elsewhere | likely_not_in_gbif | 0.00 | 0 % | 100 % | 0.00 | NA | 0 | NA |
| trd-bunndyr-2024 | candidate | open_elsewhere | uncertain | 0.00 | 0 % | 0 % | 0.00 | NA | 0 | NA |
| trd-bunndyr-2025 | candidate | open_elsewhere | uncertain | 0.02 | 6 % | 0 % | 0.03 | 0 | 0 | NA |
| trd-ilabekken-2009 | candidate | todo | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-vikelva-2024 | candidate | todo | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-sjoskogbekken | candidate | todo | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-ristelva | candidate | todo | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| trd-uglabekken-restaurering | candidate | todo | uncertain | 0.00 | NA | 0 % | NA | NA | 0 | NA |
| nat-restaureringsuksess-2025 | candidate | todo | uncertain | 0.20 | 0 % | 0 % | 0.00 | NA | 1 | NA |
| ntnu-bymarka-rotenon-2015-2019 | candidate | in_gbif | likely_in_gbif | 0.97 | 96 % | 100 % | 0.96 | 1 | 1 | NA |
| ntnu-glennsettjonna-2017-2018 | candidate | in_gbif | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| ntnu-gjettjonna-2016-2017 | no | in_gbif | uncertain | 0.00 | 0 % | 0 % | 0.00 | NA | 0 | NA |
| sweco-ku-prehospitalt-senter-2024 | no | not_applicable | uncertain | 0.33 | 100 % | 0 % | 0.50 | 0 | 0 | NA |
| multiconsult-123-113-642-2018-2019 | candidate | todo | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| ramboll-123-113-642-2021-2025 | candidate | todo | likely_in_gbif | 0.87 | 80 % | 100 % | 0.80 | 1 | 1 | NA |
| ramboll-uni-123-606-2017-2025 | candidate | todo | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| ramboll-122-76-2023-2024 | candidate | todo | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| sweco-122-76-2020 | candidate | todo | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| sweco-123-649-2022 | candidate | todo | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| norconsult-123-647-2019-2025 | candidate | todo | likely_in_gbif | 0.64 | 71 % | 50 % | 0.46 | 1 | 1 | NA |
| niva-123-29-603-2018-2024 | candidate | todo | likely_in_gbif | 0.57 | 36 % | 100 % | 0.36 | 1 | 1 | NA |
| nina-122-77-2019 | candidate | todo | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| ntnu-nidelva-nye-svean-2011 | candidate | in_gbif | likely_in_gbif | 1.00 | 100 % | 100 % | 1.00 | 1 | 1 | NA |
| ntnu-vikerauntjonna-rotenon-1989-2015 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-jonsvatnet-2020 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-leirelva-uglabekken-1994-2000 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-nidelva-trekant-1982-1999 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-nidelva-brattsberg-1982-1986 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-nidelva-leirfoss-1999-2001 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-nidelva-laksefisk-2001 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-vannrammedirektiv-2008 | candidate | in_gbif | likely_in_gbif | 0.50 | 100 % | 0 % | 0.50 | 1 | 0 | NA |
| ntnu-sagelva-1978-1979 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-haukvatnet-sik-1978 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-sushydro-kilvatnet-phd-2023-2024 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-sushydro-kilvatnet-msc-2023 | candidate | in_gbif | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |
| ntnu-gisvolldam-2013 | candidate | todo | likely_in_gbif | 0.67 | 100 % | 0 % | 0.50 | 1 | 1 | NA |

Files: `results.tsv` (all evidence with sources), `station_years.tsv`, `review.md` (uncertain list).
