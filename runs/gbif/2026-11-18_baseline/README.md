# gbif run `2026-11-18_baseline`

Reconstructed on 2026-11-19 from files made before run folders existed
(see `run.json`). Full occurrence records are in local `data/raw/gbif/`.

GBIF baseline for scope `pilot-ept-trondheim` (EPT, Trondheim kommune,
GADM `NOR.15.24_1`): 18,415 records in 13 datasets; 81 survey groups from the
NTNU benthic and Vannmiljø datasets.

Files:

- `baseline.tsv`: records per dataset with type, years, protocols, eventID and basisOfRecord
- `reference.tsv`: the hand-checked table behind docs/design.md ("Pilot scope")
- `comparison.tsv`: `baseline.tsv` against `reference.tsv` (no differences)
- `survey_groups.tsv`: dataset × datasetName × recordedBy × year
- `config/scope.yaml`: scope as of commit `576e12a`
