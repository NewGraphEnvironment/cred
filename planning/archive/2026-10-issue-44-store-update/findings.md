# Findings — crd_store_build(): no way to add or drop a few documents without rebuilding the whole store (#44)

## Issue context

## Problem

`crd_store_build()` only builds from scratch. On an existing store it stops unless `overwrite = TRUE`, and then it creates an empty store and converts and embeds every PDF again. Adding one paper to a store costs as much as building it.

Measured with cred 0.5.0 and ragnar 0.3.1 (2026-10-31): a 263-document store (46,600 chunks, 633 MB) took 26 min to rebuild. The next day one paper's PDF reached the library through a duplicate merge. Getting that one document into the store means another 26-minute rebuild.

## What ragnar already does

- `ragnar_store_ingest()` works on an existing store. Its per-document update step (`ragnar_store_update()`, v2 stores) compares a document's chunks with those stored under the same `origin` and returns without embedding when nothing changed. A changed document has its embeddings replaced.
- Given only the new paths, it converts and embeds only those PDFs.
- ragnar exports no function to delete a document. A removal is a delete from `documents` and `embeddings` by `origin` (`doc_id`).

## Proposal

An update mode for `crd_store_build()` (`update = TRUE`), or a separate `crd_store_update()` taking the same `collection` / `citation_keys` / `library` arguments:

1. Resolve sources exactly as a build does (`.crd_zot_collection_pdfs()` / `.crd_zot_key_pdfs()`), with the same left-out and missing-file reporting.
2. Compare the resolved `src_path`s with the store's `documents.origin`.
3. Ingest only paths that are new or whose file changed (a recorded md5 or mtime, or just let ragnar's update skip the unchanged ones).
4. Delete documents whose origin is no longer resolved: an item trashed, a PDF replaced, a member removed from the collection.
5. Report added / replaced / removed counts, and rebuild the index if ingest does not.

The result should hold the same documents a full build from the same arguments would. A test can check that: build A, update with one paper added and one removed, then compare the origins with a fresh build of B.

## Notes

- Pushing still uploads the whole file (`crd_store_push()`), which is minutes rather than a rebuild.
- An origin is an absolute local path, so an update on a machine whose Zotero data directory is elsewhere would see every document as removed and every source as new. Compare origins relative to `zotero_dir` (or by attachment key, the `storage/<KEY>/` folder name) rather than as full paths.


## Exploration (2026-10-31, ragnar 0.3.1 installed)

- `ragnar_store_ingest()` → `prepare_ingest_paths()` marks each path `is_new_origin` by a LEFT JOIN on
  `documents.origin`, and `do_ingest_remote_work()` embeds in the worker only when `embed = is_new_origin`.
  But cred's `.crd_ingest_prepare()` embeds inside `prepare` itself, unconditionally. So an existing,
  unchanged origin handed to ingest is read **and embedded** in full before `ragnar_store_update_v2()`
  anti-joins its chunks against the stored ones and returns. ragnar's skip saves the DB write only.
- `ragnar_store_update_v2()` deletes `embeddings` by `doc_id` and upserts `documents` in one transaction
  per document; `ragnar_store_build_index()` runs once, at the end of ingest (`build_index = TRUE`).
- ragnar exports no delete. A removal is `DELETE FROM embeddings WHERE doc_id IN (...)` and the same on
  `documents`; the `chunks` view joins them.
- `.crd_zot_key_from_path()` already reads the attachment key as `basename(dirname(path))` matching
  `^[A-Z0-9]{8}$`; the origin id uses the same rule on the path text.

## Plan review: what each finding came to (2026-10-31)

Review in `review-plan.md`. Each verdict says what established it.

| # | Finding | Verdict |
|---|---------|---------|
| 1 | FK refuses deletes in one transaction | **Real**, hit independently before the review arrived (`Violates foreign key constraint because key "doc_id: 1"`); fixed with two statements. M14 pins it on ragnar 0.3.1 |
| 2 | Unreadable same-origin replacement recorded as replaced | **Real**: reproduced by a test before the fix (`replaced: 1`, new md5). Fixed by dropping replaced docs before ingest, the plan's original design |
| 3 | WAL left beside the copy | Fixed defensively (CHECKPOINT, refuse rename if `<work>.wal`). Not reproduced: no test reaches a persisting WAL |
| 4 | `verify = TRUE` overwrites an unpushed update; cached instance | Documented in roxygen and the final message. Not reproduced |
| 5 | Permanently unreadable source rewrites the store every update | **Real**: test written first, red, then fixed (unchanged result discards the copy) |
| 6 | Zero-document result | Fixed and tested. Removal-fraction guard **not added**: a wrong collection or library errors at resolution; a threshold is a number nobody has measured |
| 7 | Per-document unrecorded rule | Already the draft's rule; roxygen now states it per file |
| 8 | WAL remedy text unverified | Remedy reduced to "close it and retry"; the ragnar_store_connect suggestion removed |
| 9 | Checks before copy; one index build | Done: probe and diff read-only on the original; with replaced docs dropped first, the index is built once (by ingest, or once after a removal-only drop) |
| 10 | ragnar 0.3.1 vs 0.3.1.9000 store formats | Not cred's to fix (affects build too). Phase 5 runs the tests under the dev ragnar. Dev ragnar's mtime skip cannot bite: ragnar is never handed an origin it holds |
| 11 | Deletes need vss loaded | Holds: deletes go through `ragnar_store_connect()`'s connection |
| 12 | Linked files / renamed attachments re-ingest | Documented in roxygen |
| 13 | Parity conditional on files present | Parity test has every file present; the kept-missing and missing-unresolved cases have their own tests |
| 14 | Compare embeddings and orphans | Added to `contents()` |
| 15 | Missing tests | Added: unreadable replacement, permanently unreadable, rename FALSE, zero docs, missing-unresolved. Not added: leftover work WAL (no way to make duckdb leave one after CHECKPOINT + disconnect in-process) |
| 16 | File size beside the owed timing; leftover copies | Leftover `.updating-*` copies now warn; owed item amended to record size |

## Mutation table (2026-10-31, ragnar 0.3.1, duckdb 1.5.2)

Each guard's defect restored in `R/store.R` alone, the owning test file run, the file restored
(driver: a python script over the committed tree, one mutation at a time).

| Mutation | Red tests |
|----------|-----------|
| M1 origin id ignores the `storage/` component | linked-file id test |
| M2 changed md5 not seen | changed file; changed elsewhere; unreadable replacement |
| M3 replaced doc not dropped before ingest | changed file; changed elsewhere; unreadable replacement |
| M4 no index rebuild after a removal-only update | **survived** the BM25 hit checks (results come through the `chunks` view, so a removed doc vanishes from a stale index); red once the test compared BM25 scores with a fresh build's ("after a removal the index scores as a fresh build's does") |
| M5 a resolved file missing locally is removed | kept-and-named test |
| M6 zero-document guard off | zero-document test |
| M7 an unchanged result rewrites the store | unreadable replacement (second update's md5) |
| M8 embedder probe off | embedder test (errors with ragnar's message instead) |
| M9 WAL refusal off | refusal test |
| M10 build writes no record | build report test; failed-write test |
| M11 copy not cleaned up | failure test; rename test |
| M12 a failed rename not reported | rename test |
| M13 unrecorded files not announced | legacy-store test |
| M14 deletes in one transaction | 9 tests error on the FK (ragnar 0.3.1 schema only) |
| M15 a replaced-and-unreadable file's new md5 recorded | unreadable replacement |

Not mutated: the CHECKPOINT and `<work>.wal` check before the rename (no in-process way to make duckdb
keep a WAL after CHECKPOINT and disconnect), and the leftover-copy warning.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `Violates foreign key constraint because key "doc_id: 1" is still referenced` deleting embeddings then documents in one `dbWithTransaction()` | Two autocommit statements; atomicity comes from the copy (ragnar 0.3.1 schema has the FK, dev ragnar dropped it) |

## /code-check branch (2026-10-31, 23:05-23:50Z)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 2 (unreadable file gives NA md5 into ragnar; roxygen overstated "not written") | 2 | 0 | — |
| 2 | 1 (connect's mismatch error and "connect" remedy reused: `check_model`, manifest, BM25) | 1 | 0 | n |
| 3 | 2 (borrowed check probes twice and spends connect's once-warning; WAL remedy cannot apply to a stale log) | 2 | 0 | **y** (round 2's wrapper) |

Mechanism (round 3): code borrowed from another caller still assumes that caller's situation (build: exists =
readable; connect: manifest, `check_model`, BM25 as consolation). Ended by enumeration: every cred function
`crd_store_update()` calls, parsed from its body (16): `.crd_embed_remedy`, `.crd_embed_width`,
`.crd_fallback_model`, `.crd_have`, `.crd_indent_cause`, `.crd_need`, `.crd_origin_id`, `.crd_retrieval_failure`,
`.crd_sources_read`, `.crd_sources_write`, `.crd_store_ingest`, `.crd_store_meta_brief`, `.crd_store_report`,
`.crd_store_skipped`, `.crd_store_sources`, `.crd_store_who`. Each is new for the update, pure, or checked
against the update's situation by round 3 (its table, items 1-14) and holds; `.crd_check_store_embedding` no
longer appears. Round 3's two new guards mutation-tested: M16 (width compare off) and M17 (stale-log remedy
dropped) both red.
