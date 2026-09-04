# Progress — crd_search() errors on ragnar list columns (#27)

## Session 2026-09-04

- Plan-mode exploration — reproduced the failure offline (deterministic `embed` function,
  no Ollama, no bucket), which settled the issue's open question about whether a real-ragnar
  regression fixture is possible. It is.
- Multi-element-cell contract decided with the user: first element plus a warning.
- Created branch `27-crd-search-errors-on-ragnar-list-columns` off main.
- Scaffolded PWF baseline from issue #27 with approved phases.
- Next: Phase 1 — fixture helper and the failing regression test.

### Phase 1 — regression test (complete)

- Discovered mid-implementation that the "every list cell is length 1" premise was a
  fixture artifact: `as.numeric()` on length-1 list cells works, so the six-document
  fixture passed against the very bug it was written for. Re-measured on a multi-chunk
  corpus — 24% of rows are merged and multi-element — and re-opened the contract decision
  with the user, who chose direction-aware reduction (max for bm25, min for
  cosine_distance) with no warning.
- Plan-agent review landed concurrently and reached the same conclusion from ragnar's
  source (`chunks_deoverlap()`), plus found a leaked duckdb writer connection, two missed
  call sites, a vacuous warning assertion, a 7-character fixture key that could never
  resolve, and an embed function that did not bin as its comment claimed. All folded in.
- Confirmed red against unfixed code with the reported error verbatim.
- Next: Phase 2 — `.crd_flat()` and its call sites.
