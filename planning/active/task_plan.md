# Task: crd_store_build(): no way to add or drop a few documents without rebuilding the whole store (#44)

`crd_store_build()` only builds from scratch. On an existing store it stops unless `overwrite = TRUE`, and then it creates an empty store and converts and embeds every PDF again. Adding one paper to a store costs as much as building it.

Measured with cred 0.5.0 and ragnar 0.3.1 (2026-10-31): a 263-document store (46,600 chunks, 633 MB) took 26 min to rebuild. The next day one paper's PDF reached the library through a duplicate merge. Getting that one document into the store means another 26-minute rebuild.

## Context (from the approved plan)

`crd_store_build()` only builds from scratch. Adding one paper to a 263-document store meant a
26-minute rebuild (issue, measured 2026-10-31). An update should resolve sources the way a build
does, ingest only what is new or changed, drop what is no longer resolved, and leave the store
holding the documents a fresh build from the same arguments would hold.

## What exploration changed from the issue's proposal

- **Letting ragnar skip unchanged files saves nothing in cred.** `ragnar_store_update_v2()` skips
  an unchanged document only at the database step. cred's `.crd_ingest_prepare()`
  (`R/store.R:1717`) reads, chunks and **embeds** in the worker before that step. So cred must
  choose what to hand ragnar itself, and changed-file detection needs a record (gate decision 1).
- **ragnar runs one transaction per document, and the index is rebuilt only at the end of
  `ragnar_store_ingest()`.** An update interrupted in place leaves the index stale. Building's
  answer (delete the store on failure) would destroy the user's existing store. So the update
  works on a sibling copy and renames it into place only on success.
- **The worker embeds whatever the store's `@embed` resolves to.** The update therefore takes no
  `model`. It runs the connect-time width probe `.crd_check_store_embedding()` and
  `.crd_ollama_check()` on the store's recorded model (`.crd_store_model_from_meta()`) before it
  ingests anything.
- **Origins are absolute paths.** Both sides are compared by an origin id: the
  `storage/<KEY>/<file>` tail when a path has that shape (the same 8-character key rule as
  `.crd_zot_key_from_path()`, `R/zotero.R:426`), and the full path for a linked file. The rule
  works on the path text alone, so it needs no `zotero_dir` for an origin written on another
  machine.

## Decided at the gate (the user, 2026-10-31)

1. **Changed PDFs are detected by md5 recorded in the store.** `crd_store_build()` and
   `crd_store_update()` write a `cred_sources` table (`origin_id`, `md5`) into the `.duckdb`. The
   update re-ingests a file only when its md5 differs from the record. A store built before this
   change has no record: its first update records the current files' md5 for the documents it
   keeps, and a message says that changes made before that update cannot be seen.
2. **The API is a new export, `crd_store_update(store_path, collection, citation_keys,
   zotero_dir, library)`.** It has no `model` argument. `crd_store_build()`'s signature does not
   change, and the two share internal helpers for resolving and reporting.

Decided by me (reject the plan to change any of these):

- **A resolved source whose file is missing on this machine keeps its stored document**, and a
  message names it. A build would leave it out. Keeping it fails toward not-clobbering: a
  partially synced Zotero `storage/` would otherwise strip the store.
- **No sources resolved is an error, as in a build.** It never empties the store.
- **Nothing to add, replace or remove: the store is not touched**, and a message says it is
  current.

## Phase 1: Origin identity and the source record
- [ ] Tests first: `.crd_origin_id()` maps a storage path and a foreign-prefix storage path to the same id, and returns a linked path whole; record write and read round-trip; reading a store with no record returns `NULL`
- [ ] `.crd_origin_id(paths)`, `.crd_sources_read(con)`, `.crd_sources_write(con, origins, md5)` in `R/store.R`
- [ ] `crd_store_build()` writes the record after ingest, for ingested files only. A failed write warns and keeps the store, because `complete` is already `TRUE` by then
- [ ] Check that `ragnar_store_connect()` and `crd_search()` still work on a store carrying the extra table, and that `.crd_store_describe()` counts are unchanged

## Phase 2: Share build's resolve and report
- [ ] Move the resolve, left-out, several-PDFs and missing-file reporting (`R/store.R:2016-2047`) into `.crd_store_sources()`
- [ ] Move the post-ingest report (pdftools reads, split, dropped, skipped, `who()`) into `.crd_store_report()`
- [ ] `crd_store_build()` behaves as before: the existing `test-store-build.R` report tests pass unchanged

## Phase 3: `crd_store_update()`
- [ ] Tests first (the Phase 4 tests that can be written against the signature)
- [ ] Diff: resolved sources against the store's `documents.origin` by origin id, giving added (new id), replaced (md5 differs from the record), removed (stored id no longer resolved, apart from the missing-file case above) and kept
- [ ] Guards: refuse when `<store>.wal` exists (a copy would miss it); refuse a missing store; run the width probe and `.crd_ollama_check()` on the store's recorded model
- [ ] Work on a sibling copy (`<store>.updating-<pid>`). Delete the removed and replaced documents from `embeddings` and `documents` by `doc_id`. Ingest the added and replaced paths through `.crd_store_ingest()` (which rebuilds the index). If the ingest had nothing to do, rebuild the index with `ragnar_store_build_index()`. Update the record, disconnect with `shutdown = TRUE`, then `file.rename()` over the original and check that it returned TRUE. On any failure, `on.exit` removes the copy
- [ ] Report added / replaced / removed / kept counts, plus the shared ingest report. Return invisibly the build-shaped tibble (`citation_key`, `src_path`) of the store's sources
- [ ] Roxygen with a `\dontrun{}` example (it needs Zotero and Ollama, like build's), `devtools::document()`, add to `_pkgdown.yml` and run `pkgdown::check_pkgdown()`

## Phase 4: Tests that prove it
- [ ] Parity, end to end through the real ingest (mirai workers, offline embed, text reader, as in `test-store-build.R:348`): build from {A, B}, update to {B, C}, build fresh from {B, C}, and compare origin ids and the md5 records
- [ ] A changed file (same path, new bytes) is replaced; an unchanged one is not handed to ingest
- [ ] Portability: a store whose origins carry another machine's prefix re-ingests and removes nothing
- [ ] A failure during ingest leaves the original store byte-identical (md5 before and after) and no `.updating` file behind
- [ ] Legacy store (no `cred_sources`): kept documents are recorded and the message is emitted
- [ ] Nothing to do: the file is untouched (mtime and md5 unchanged)
- [ ] Missing local file for a stored document: kept, and named
- [ ] Restore each guard's defect and watch its test go red (mutation table in `findings.md`)

## Phase 5: Docs and conventions
- [ ] `CLAUDE.md`: the architecture line for `store.R`, the update's two design decisions (copy-then-rename; origin id and md5 record), and the measured fact that ragnar's skip saves nothing under cred's `prepare`
- [ ] `?crd_store_build` points to `crd_store_update()`; check the vignette and README for build-only claims that are no longer true
- [ ] Run the store tests against the development ragnar in a scratch library with `R_LIBS` set (CLAUDE.md, mirai workers)

## Owed at the end (reported, done after merge)

- [ ] Time a real one-paper update against the 26-minute rebuild on the shared store, and put the measured number in the archive README

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()` reports 0 lints, `devtools::check()` is clean
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the parity test (update A→B equals a fresh build of B, by origin id and md5) is the
acceptance test the issue names. The failure test proves the original store is untouched by md5.
Each guard is mutation-tested. A live update on a real collection is the post-merge measurement.

