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
- Plan review (Plan agent) delivered 22:44Z; recorded in `review-plan.md`, verdicts in findings.md. Blocker 2
  (an unreadable same-origin replacement counted as replaced, new md5 recorded) reproduced by a test before the
  fix (`replaced: 1` where a build leaves it out). Reworked `crd_store_update()`: checks and the embedder probe
  run read-only on the original before the copy; replaced docs are deleted before the ingest, so ragnar is never
  handed an origin it holds; a result with nothing ingested or dropped and an unchanged record discards the
  copy; a zero-document result is refused; CHECKPOINT and a `<work>.wal` check before the rename; leftover
  `.updating-*` copies warn; the final message says to push or open with `verify = FALSE`.
- Mutation table run (15 mutations, 22:50-22:58Z): 14 red at once; M4 (no index rebuild after a removal-only
  update) survived the BM25 hit checks and was pinned by a new test comparing BM25 scores with a fresh build.
  Table in findings.md. CLAUDE.md gains the update's design; `?crd_store_build` links `crd_store_update()`.
