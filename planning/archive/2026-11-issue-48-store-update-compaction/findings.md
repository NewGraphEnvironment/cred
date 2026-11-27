# Findings — crd_store_update() leaves freed blocks in the store: 32 to 76 % of an updated file is free space (#48)

## Issue context

## Problem

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

## Options

- Have `crd_store_update()` write a compacted copy when it finishes, for example by building into a new file, or
  `ATTACH` + `COPY FROM DATABASE`, checking that the FTS and vector indexes come through, then swap it in.
- Or have `crd_store_push()` report free blocks from `pragma database_size` and refuse, or warn, above some share.
- In the meantime, a `crd_store_build(overwrite = TRUE)` over the same keys gives a compact file. That downstream work does
  this before pushing.

## Repro

Update a built store with `crd_store_update()` (any change in its keys), then compare `pragma database_size` with
the file's size before and after.


## Found since (2026-11-18, #43)

- **ragnar 0.4.0 adds growth of its own.** Its read-write connect upgrades a pre-0.4.0 store by rebuilding `embeddings` with `CREATE TABLE ... AS`, and duckdb keeps the freed space: a read-write open that wrote nothing took two real stores from 28.6 to 52.7 MB and 94.6 to 175.4 MB (about 1.85x), under duckdb 1.5.6 and 2.0.0 alike. `crd_store_update()` opens its copy read-write, so the first update of every pre-0.4.0 store that changes anything carries this on top of the growth above (`research/ragnar-versions.md`).
- **`COPY FROM DATABASE` works as the compaction.** `ATTACH` the upgraded file read-only and `COPY FROM DATABASE` into a fresh one: 52.7 MB back to 27.8 MB (smaller than the original 28.6 MB), with all three HNSW indexes present, and the copy retrieves. The probe is in cred's `planning/archive/2026-11-issue-43-ragnar-versions/findings.md`. Still to check before relying on it: the FTS index, `cred_sources` and `cred_ragnar` come through, and the HNSW indexes keep their metric.

## Phase 1 measurements (2026-11-26; ragnar 0.4.0, duckdb 1.5.6, toy fixture from `local_update_world()`)

`PRAGMA database_size`, 256 KiB blocks. Build keys A+B, update to A+B+C, update to B+C, then a fresh build of
B+C:

| store | file | total blocks | used | free |
|---|---|---|---|---|
| build A+B | 4,993,024 | 19 | 19 | 0 |
| update +C | 7,090,176 | 27 | 19 | 8 |
| update -A | 6,828,032 | 27 | 19 | 8 |
| fresh B+C | 4,993,024 | 19 | 19 | 0 |

So the toy fixture separates an updated store from a fresh build, and a fresh build carries **no** free blocks:
ragnar's temporary FTS `chunks` table leaves none at this scale. The parity target is therefore 0 free here.

Objects in a 0.4.0 store (fresh build): schema `fts_main_chunks` (5 tables, macros `match_bm25` and
`tokenize`), tables `documents`, `embeddings`, `metadata`, `cred_sources`, `cred_ragnar`, view `chunks`,
sequences `chunk_id_seq` and `doc_id_seq`, three HNSW indexes. Under duckdb 1.5.6 even ragnar's own
`ragnar_store_build_index()` is recorded as `CREATE INDEX store_hnsw_cosine_index ON embeddings USING HNSW
(embedding);`, no metric, which confirms that a `COPY FROM DATABASE` carrying indexes would lose them.

Compaction probe (a 3-document store copied, opened through ragnar read-write, HNSW indexes and
`fts_main_chunks` dropped, checkpointed; then `ATTACH src (READ_ONLY)`, `ATTACH dst`, `COPY FROM DATABASE src
TO dst` from an in-memory connection; then `ragnar_store_build_index()` on dst):

- work copy after the drops: 19 total, 11 used, 8 free; copied file before the index: 11 blocks, 0 free;
  after the index: 19 total, 19 used, 0 free, no `.wal`. Identical to a fresh build.
- Object inventory of the compacted file identical to the source's (schemas, tables, view, sequences, macros,
  index SQL). Sequences carry their values (`doc_id_seq` 4, `chunk_id_seq` 22), and a further
  `.crd_store_ingest()` into the compacted file works (4 distinct doc_ids).
- `metadata` (the serialised embedder) identical; `contents()` identical; BM25 scores identical; cosine
  `EXPLAIN` uses HNSW.

Probe scripts: the session scratchpad (`probe1.R`, `probe2.R`); the measurement is reproduced by the Phase 2
tests.

## Phase 4: a real store (2026-11-27 UTC; ragnar 0.4.0, duckdb 1.5.6, m-series Mac)

A scratch copy of a real 924.3 MB store (404 documents, pre-0.4.0 schema, 0 % free), updated to remove one
document (no embedder needed; sources mocked to the store's own origins minus one, so every other document is
kept). Same input copy for both; main's code from a worktree of `origin/main` (d08ff2c), the branch at 9af4078.

| code | file after | blocks total / used / free | update wall time |
|---|---|---|---|
| main | 1,109.8 MB | 4,439 / 3,696 / 743 (17 %) | 74.8 s |
| branch | 923.5 MB | 3,694 / 3,691 / 3 (0 %) | 33.8 s |

- BM25 top 20 for "culvert fish passage": identical chunks and scores between the two.
- Object inventory identical (schemas, tables, view, sequences, macros, index SQL); cosine `EXPLAIN` uses HNSW
  on both.
- The branch is **faster**, not slower: main's copy had ragnar 0.4.0's upgrade recreate the three HNSW
  indexes, then the update rebuilt them; the branch drops them before the upgrade and builds once, on a
  file with no dead blocks. The copy itself costs less than the index build it saves.
- This store grew 1.20x under main, not the 1.85x the two smaller stores in `research/ragnar-versions.md`
  showed: the growth depends on the store.

Script: the session scratchpad's `real_update.R` (`Rscript real_update.R <cred checkout> <store> <out>`).

## Errors Encountered

| Error | Resolution |
|-------|------------|
