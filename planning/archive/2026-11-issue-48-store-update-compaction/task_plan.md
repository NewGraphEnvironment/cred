# Task: crd_store_update() leaves freed blocks in the store: 32 to 76 % of an updated file is free space (#48)

`crd_store_update()` leaves the space it frees inside the duckdb file, so an updated store carries 32 to 76 % free blocks (three stores measured) and
everyone who pulls it downloads that space.

Measured with cred 0.7.0, ragnar 0.3.0.9000 and duckdb 1.5.6 (`pragma database_size`, 256 KiB blocks), on three stores
updated in place by downstream work:

| store | documents before → after | file | used blocks | free blocks |
|---|---|---|---|---|
| bull_trout | 171 → 173 | 541 MiB | 1,465 (366 MiB) | 699 (32 %) |
| bull_trout_grayling | 35 → 197 | 1.3 GiB | 1,667 (417 MiB) | 4,026 (71 %) |
| habitat_modelling | 266 → 414 | 3.6 GiB | 3,584 (896 MiB) | 11,312 (76 %) |

A fresh `crd_store_build()` of the same keys runs about 13–17 KiB per chunk; these ran 20–56 KiB per chunk. Even
adding 2 documents to a 171-document store (the first row) grew the file by about 44 %, so it looks like the update
rewrites the store's tables or indexes, not only the new rows. duckdb reuses free blocks but never shrinks the file, and
`crd_store_push()` uploads the whole file.

## Context

An updated store carries 32 to 76 % free blocks (three real stores), and `crd_store_push()` uploads the whole
file, so every `crd_store_connect()` downloads the slack. Exploration found where it comes from:
`ragnar_store_build_index()` (ragnar 0.4.0, `ragnar_store_build_index_v2`) drops and recreates all three HNSW
indexes, rebuilds the `fts_main_chunks` schema, and creates then drops a temporary `chunks` table. Every update
rebuilds the index on its working copy (`R/store.R:2622-2648`), so each one frees the old indexes inside the
file, and duckdb never shrinks it. ragnar 0.4.0's read-write upgrade of a pre-0.4.0 store adds ~1.85x on top.

The fix: build the indexes **once**, on a compacted file. `ragnar_store_ingest()` takes `build_index = FALSE`,
so the update can write documents into its copy without indexes, `COPY FROM DATABASE` that copy into a fresh
file, build the indexes there, and rename the fresh file over the store.

## Decided at the gate

Approved by the owner at the plan gate, 2026-11-26.

Mechanism, decided in the plan (agent-operations §4, mechanism promoted):

- **Compact in `crd_store_update()`, not a warning in `crd_store_push()`.** It removes the cause; the issue
  offers either. A store already bloated is compacted by its next update that changes anything.
- **Drop the indexes on the working copy and build them once on the compacted file**, rather than letting
  `COPY FROM DATABASE` carry them. duckdb before 2.0 records an HNSW index's SQL without its metric
  (`research/ragnar-versions.md`), and a copy replays that SQL, so under duckdb 1.5.6 (installed here) the
  cosine and inner-product indexes would come back as L2. Building on the fresh file uses ragnar's own SQL with
  explicit metrics, under any duckdb, and skips the redundant index rebuild inside the copy.
- **Always compact a kept copy**, no free-share threshold: the index build has to happen anyway, so the copy
  is the only extra cost (measured in Phase 4).
- **The compacted file is `<store>.updating-<pid>-compact`**, so the existing leftover warning
  (`Sys.glob(paste0(store_path, ".updating-*"))`) and the `on.exit()` cleanup cover it.
- **Target is parity with a fresh `crd_store_build()`**, not zero free blocks: a fresh build also frees ragnar's
  temporary FTS table.
- #50 was closed as a duplicate of this issue; its asks (FTS, `cred_sources`, `cred_ragnar` and HNSW metrics
  survive the copy) are the acceptance checks below. The issue has no comments.

## Phase 1: Measure before building

- [x] On main, with `local_update_world()`'s fixture: `PRAGMA database_size` (`free_blocks`, `total_blocks`)
      and file size of an updated store vs a fresh build of the same keys. If the toy store does not separate
      them, enlarge the fixture (`.crd_test_prose()` length, more docs) until it does: the new test must fail on
      main.
- [x] Inventory the objects in a 0.4.0 store (`duckdb_tables()`, `duckdb_views()`, `duckdb_sequences()`,
      `duckdb_functions()` macros, `duckdb_schemas()`, `duckdb_indexes()`), and check `ATTACH ... (READ_ONLY)` +
      `COPY FROM DATABASE src TO dst` (explicit aliases, from an in-memory connection) carries every
      non-index object once HNSW indexes and `fts_main_*` schemas are dropped from the source.
- [x] Confirm `ragnar_store_build_index()` on the copied file gives three HNSW indexes usable for cosine,
      ip and L2 (`EXPLAIN`), and BM25 scores identical to a fresh build. Record all of it in `findings.md`.

## Phase 2: Failing tests (`tests/testthat/test-store-update.R`, `helper-store.R`)

- [x] Helper `.crd_test_db_size(path)`: `PRAGMA database_size` read-only, returning free and total blocks.
- [x] An update (add, then remove) leaves no more free blocks than a fresh build of the same keys, and a file
      no larger than it by more than one block's worth. Fails on main. The second update ingests into a
      compacted file, so it also asserts unique `doc_id` and `chunk_id` (sequences survive the copy; review).
- [x] The updated store holds the same objects as a fresh build: tables (incl. `cred_sources`, `cred_ragnar`),
      the `chunks` view, the `fts_main_chunks` schema, three HNSW indexes whose recorded SQL is ragnar's, and
      `.crd_test_cosine_indexed()` TRUE.
- [x] A compaction that fails (mock the copy step to error) leaves the store byte-identical (md5) and no
      `.updating-*` file behind. (On main it errors only because the mocked function does not exist: a guard
      for the cleanup, not a red test of the bug; review.)
- [x] The existing pre-0.4.0 tests (cosine indexed after an update; record-only update) stay as the guard
      for the two `build_index` branches this removes.

## Phase 3: Implementation (`R/store.R`)

- [x] `.crd_store_ingest()` gains `build_index = TRUE`, passed to `ragnar_store_ingest()`; `crd_store_build()`
      unchanged. Test mocks that wrap it forward `build_index` (code-check-r: a `function(...)` mock hides
      arguments).
- [x] `crd_store_update()`: drop the working copy's HNSW indexes (from `duckdb_indexes()` on `embeddings`) and
      `fts_main_*` schemas on a plain DBI connection **before** ragnar's read-write connect, so ragnar 0.4.0's
      upgrade of a pre-0.4.0 store finds no indexes to recreate (review); ingest with `build_index = FALSE`; remove the two
      `ragnar_store_build_index()` branches (dropped-only, record-only); write record and stamp; checkpoint and
      close.
- [x] New internal `.crd_store_compact(from, to)`: in-memory connection with `temp_directory` under
      `tempdir()` (an in-memory database spills to `.tmp` in the working directory; review), `ATTACH` both,
      `COPY FROM DATABASE`, refuse unless every `main` table's row count matches (`cred_sources`, `cred_ragnar`
      and `metadata` included; review), `DETACH`; then `ragnar_store_connect(to,
      read_only = FALSE)`, `ragnar_store_build_index()`, `CHECKPOINT`, disconnect, no `.wal` beside the compacted
      file. The update renames the compacted file into place; any failure stops with the store unchanged. Its
      own `on.exit()` removes the compacted file and its `.wal`; the leftover warning stops saying "each the
      size of the store"; the comments that say the update rebuilds the index on the copy go (review).
- [x] Tests from Phase 2 pass; full `devtools::test()` green.

## Phase 4: Measure on a real store

- [x] On a scratch copy of a real store (e.g. a `data/rag/*.duckdb` in a sibling report repo), an update that
      removes one document (needs no embedder), on main and on the branch: file size, `PRAGMA database_size`,
      wall time, and BM25/hybrid results against the main-updated copy. Record in `findings.md` and the archive
      README's Measurement section.

## Phase 5: Docs and release notes

- [x] Roxygen of `crd_store_update()`: "What a failure costs" (the compacted copy; at the peak three files sit
      together: the store, the working copy, larger than the store after a pre-0.4.0 upgrade, and the compacted
      copy, about the store's used size; review), the pre-0.4.0 paragraph (the 1.85x growth no longer reaches the pushed
      file). `devtools::document()`.
- [x] Grep the 1.85x / growth sentences across `CLAUDE.md`, `research/ragnar-versions.md`,
      `research/ragnar-store-update.md`, roxygen and NEWS; correct each that now describes the update (the
      read-write connect still grows a file, so those stay).
- [x] NEWS bullet under the development heading; `lintr::lint_package()` 0 new lints; `devtools::check()`.

## Owed at the end (reported, done after merge)

- [ ] Tell the store maintainers that the rebuild-before-push workaround is no longer needed once this
      release is installed.

## Validation

- [x] Tests pass
- [x] `/code-check` clean (once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

Verification: the Phase 2 free-blocks test fails on main and passes on the branch (restore the bug and see it
go red); object parity and BM25 score parity with a fresh build; existing cosine-index tests stay green under
duckdb 1.5.6 locally and 2.0 on CI; Phase 4's real-store numbers.
