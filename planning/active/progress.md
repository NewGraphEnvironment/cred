# Progress — crd_search() errors on ragnar list columns (#27)

## Session 2026-09-04

- Plan-mode exploration — reproduced the failure offline (deterministic `embed` function,
  no Ollama, no bucket), which settled the issue's open question about whether a real-ragnar
  regression fixture is possible. It is.
- Multi-element-cell contract decided with the user: first element plus a warning.
- Created branch `27-crd-search-errors-on-ragnar-list-columns` off main.
- Scaffolded PWF baseline from issue #27 with approved phases.
- Next: Phase 1 — fixture helper and the failing regression test.
