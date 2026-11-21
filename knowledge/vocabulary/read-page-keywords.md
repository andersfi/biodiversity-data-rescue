---
id: read-page-keywords
type: vocabulary
title: Words that mark the pages a reader needs
concept: Page selection for the reading test (stations, sampling period, data availability)
terms:
  stations: [stasjon, stasjoner, st.nr, stasjonsnr, utm, øst, nord, koordinater, kartreferanse, vannlokalitet, vannlokalitetkode, lokalitet]
  period: [innsamlet, innsamling, prøvetatt, prøvetaking, prøvetakingen, dato, januar, februar, mars, april, mai, juni, juli, august, september, oktober, november, desember]
  topic: [bunndyr, bunndyrsamfunn, døgnfluer, steinfluer, vårfluer, ept, aspt, sparkemetoden, sparkeprøve, sparkeprøver, invertebrater]
  data: [vedlegg, artsliste, artslister, taksaliste, vannmiljø, gbif, artsdatabanken, data, datasett]
source: "docs/reading-benchmark.md, section 2 (plan approved 2026-11-21)"
last_confirmed: 2026-11-21
confirmed_by: draft-not-confirmed
---
Used by the `read` verb to score pages (`R/read.R`, `read_select_pages`):
each term counts once per occurrence on a page, matched as a whole word,
case-insensitive. The groups are keys of `terms`; they are not languages here.
Not sent to the model.
