# Progress — Add ragnar-powered retrieval for evidence search (#22)

## Session 2026-08-31

- Plan-mode exploration — 10 findings recorded in `findings.md`, phases approved by user
- Three design decisions settled with the user: deps in Suggests, dual build input,
  `aws` CLI for the S3 pull
- Created branch `22-add-ragnar-powered-retrieval-for-evidenc` off main
- Scaffolded PWF baseline from issue #22 with approved phases
- Next: Phase 1 — store resolution (`crd_store_connect`)
- Implemented all four phases; `crd_store_connect()`, `crd_search()`, `crd_store_build()` exported
- `/code-check` round 1 — 5 real findings (shell injection via unquoted `system2()` args,
  non-atomic store overwrite, missing `on.exit` in the builder, `nzchar(NA)` guard hole,
  `.Rbuildignore` shipping internal dirs). All fixed and verified empirically
- `/code-check` round 2 — 2 findings: `complete <- TRUE` was set after the reporting queries so a
  throw there would delete a fully built store (fixed); bucket URI in `findings.md` (scrubbed
  from the working tree and kept out of history, since nothing had been pushed)
- Caught independently before review: `ragnar_retrieve()` pivots metrics wider, so the default
  hybrid path produced an all-`NA` score. Fixed with `.crd_retrieval_score()` + a `metric` column
- 181 tests passing, 0 lints, tarball ships no internal directories
