# Progress — crd_store_build(): no way to add or drop a few documents without rebuilding the whole store (#44)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user
- Gate decisions: md5 record table in the store; new export `crd_store_update()`
- Created branch `44-crd-store-build-no-way-to-add-or-drop-a` off origin/main
- Scaffolded PWF baseline from issue #44 with approved phases
- Next: start Phase 1
- Phase 1: `.crd_origin_id()`, `.crd_sources_read()/_write()` and build's record write landed with tests
  (test-store-update.R; test-store-build.R record + failed-write tests). The extra `cred_sources` table
  was checked against `ragnar_store_connect()`, `ragnar_store_build_index()`, `crd_store_connect()`,
  `crd_search()` and `.crd_store_describe()` on a copy of the offline fixture: no change.
- Phase 2: `.crd_store_sources()`, `.crd_store_who()`, `.crd_store_skipped()`, `.crd_store_report()` extracted from
  `crd_store_build()`; build tests unchanged and green. One wording change: "Ingesting several PDFs for" is now
  "Taking several PDFs for", since an update keeps some of them rather than ingesting (no test asserted it).
