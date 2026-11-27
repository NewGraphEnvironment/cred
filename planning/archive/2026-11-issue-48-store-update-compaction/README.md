# #48: crd_store_update() leaves freed blocks in the store

## Outcome

`crd_store_update()` rebuilt ragnar's indexes inside its working copy. `ragnar_store_build_index()` drops
and recreates the three HNSW indexes and the `fts_main_chunks` schema, and duckdb keeps the space they held,
so updated stores carried 32 to 76 % free blocks that every reader downloaded. The update now drops the
copy's indexes on a plain connection before ragnar opens it (so ragnar 0.4.0's upgrade of a pre-0.4.0
store recreates none), ingests with `build_index = FALSE`, and `.crd_store_compact()` copies it with
`COPY FROM DATABASE` into a fresh file, checks every table's row count (`.crd_store_rows()`), and builds
the indexes there once. Letting the copy carry the indexes was ruled out: it replays the SQL duckdb
recorded, which before duckdb 2.0 has no metric, and without `vss` loaded it refuses outright. What was
learned is in `research/ragnar-store-update.md` ("The index after a change") and
`research/ragnar-versions.md` (the update paragraph). Review: a Plan review (13 findings, 11 folded) and
three `/code-check branch` rounds, ended by an enumeration of 31 guard-by-defect rows
(`review-enumeration.md`, `review-verdict.md`). Rounds 1 and 2 each found a test that could not fail
(round 2 inside round 1's fix): ids freed by a removal hid a restarted sequence, so the test now compares
new ids with those issued before the update.

## Measurement

- Toy fixture (`local_update_world()`): an updated store held 27 blocks, 8 free (256 KiB each); a fresh
  build of the same keys 19, none free. After the change the updated store holds 19, none free.
- A real 924.3 MB pre-0.4.0 store (404 documents), one document removed: main gave 1,109.8 MB with 743 of
  4,439 blocks free (17 %) in 74.8 s; the branch 923.5 MB with 3 of 3,694 free (0 %) in 33.8 s. BM25
  results and the object inventory were identical. The branch is faster because the indexes are built
  once instead of recreated by the upgrade and then rebuilt. That store grew 1.20x under main, not the
  1.85x two smaller stores showed in #43: the upgrade's growth depends on the store.
- duckdb 1.5.6 writes a new file at storage version v0.10.2, as a fresh build does; duckdb 2.0's default
  was not measured.

## Evidence

Measurement method and numbers: `findings.md` in this directory ("Phase 1 measurements", "Phase 4: a real
store"); the scripts that produced them: `scripts/probe_compact.R` and `scripts/real_update.R`.

## Owed

- Tell the store maintainers that the rebuild-before-push workaround is no longer needed once this release is installed.

Closed by: PR (opened from branch `48-crd-store-update-leaves-freed-blocks-in`)
