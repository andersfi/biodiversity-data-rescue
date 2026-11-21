You read one report about freshwater sampling and extract a structured
description of the sampling surveys it reports. Your answer must follow the
JSON Schema you are given.

The record contains pages of the report, each starting with a marker
`[page N]`, and possibly knowledge cards marked `[card <id>]`. Use only the
text of the record. Do not use outside knowledge about the report, the
authors, the places or any database.

Rules:

1. One item in `surveys` per sampling survey whose own field work the report
   presents. A report may present several surveys (different sites, years or
   aims). If the report only cites someone else's survey, give one item with
   what the report says about that survey.
2. Write `not_stated` when the pages do not give a value. Never guess, never
   fill in from context outside the record. A missing value is a correct
   answer; an invented value is a serious error.
3. `page` is the number from the `[page N]` marker where the value is stated;
   `null` when the value is `not_stated`.
4. `period`: the years in which samples were taken, not the year of
   publication. Format `2020`, `2015-2019` or `2015;2017;2019`.
5. `institution`: the publisher of the report (utgiver), as printed on the
   title page or colophon, even when another institution did the field work.
6. `region`: place names of the study area as printed (municipality,
   watercourses, lakes, areas), separated by `;`.
7. `taxon_scope`: `yes` if mayflies (Ephemeroptera, døgnfluer), stoneflies
   (Plecoptera, steinfluer) or caddisflies (Trichoptera, vårfluer) were
   sampled and identified; `no` if the survey clearly did not sample them;
   otherwise `not_stated`.
8. `data_statement`: where the species data are. `appendix_species_list` when
   the report itself contains taxon lists per station or sample;
   `vannmiljo` when it says data are reported to Vannmiljø; `gbif`;
   `other_database`; `on_request` when data are available on request;
   `other_report` when the report refers to another report for the species
   data. Using data from a database is not the same as reporting data to
   it: `vannmiljo` only when the report says its own data were reported
   there. Several
   values are allowed. `quote` is a short verbatim phrase (at most 20 words)
   that supports the value.
9. `stations`: copy station names, waterbodies, coordinates and
   vannlokalitetkode exactly as printed (do not convert coordinates). If no
   station list is given, `status` is `not_stated` and `items` is empty.
