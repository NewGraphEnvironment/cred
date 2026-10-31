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
- Phase 3+4: `crd_store_update()` with 12 end-to-end tests through ragnar's real mirai ingest (offline embed,
  text reader, files under `<zotero>/storage/<KEY>/`). Two deviations from the plan, both forced by the code:
  - The two deletes run as separate statements, not one transaction: duckdb's FK check on `embeddings`
    refused deleting a document in the transaction that deleted its embeddings (`Violates foreign key
    constraint because key "doc_id: 1" is still referenced`). The copy-then-rename gives the atomicity.
  - The update probes the store's own `@embed` (and runs `.crd_check_store_embedding()`) instead of
    `.crd_ollama_check(model)`: the recorded embedder is what the worker uses, and it need not be Ollama.
    It probes only when something is to be ingested, so a removal-only update needs no embedding service.
  - A legacy store whose update has nothing else to do still gets its record written (via the copy), so
    the window in which a change cannot be seen does not stay open; "untouched" holds once a record exists.
  - Removed documents are dropped before the ingest so ragnar's index build covers them; a replaced
    document ingested under a new origin (store built on another machine) has its old doc dropped after,
    followed by an index rebuild.
