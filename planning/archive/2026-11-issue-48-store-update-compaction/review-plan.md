# Plan review for #48 (Plan agent, 2026-11-27 UTC)

Spawned after the baseline, read the plan against the issue, `R/store.R`, the tests and ragnar 0.4.0's source.
Each finding with its verdict after a probe.

| # | Kind | Finding | Verdict |
|---|---|---|---|
| 1 | Blocker | An assertion that recorded index SQL is ragnar's fails under duckdb 1.5.6, which records no metric | Not applicable as written: the inventory test compares the updated store with a fresh build under the same duckdb, and cosine use is asserted by `EXPLAIN` (`.crd_test_cosine_indexed()`) |
| 2 | Gap | Existing `on.exit()` removes only the working copy; the compacted file and its `.wal` need their own cleanup; the leftover warning's "each the size of the store" is wrong for it | Folded (Phase 3) |
| 3 | Gap | No test that sequences survive the copy | Folded: the free-space test's second update ingests into a compacted file and asserts unique `doc_id`/`chunk_id`. Phase 1 probe showed both sequences carried under duckdb 1.5.6; CI's 2.0 is covered by the test |
| 4 | Gap | An in-memory connection spills to `.tmp` in the working directory | Folded: `temp_directory` under `tempdir()` |
| 5 | Ordering | Drop the indexes before ragnar's read-write connect, so the pre-0.4.0 upgrade recreates none | Folded (Phase 3) |
| 6 | Assumption | Ingest, update_v2, connect and build_index need no existing index; `embed_func` copies as data | Holds (also seen in the Phase 1 probe) |
| 7 | Assumption | Toy fixture may not separate update from build | Disproved by Phase 1: 27 blocks, 8 free vs 19, 0 free |
| 8 | Acceptance | Only the free-space test is red on main; the failed-compaction test errors on main for the wrong reason; object parity is a regression guard | Accepted and noted in the plan; the pre-0.4.0 free-space assertion is a second red test |
| 9 | Gap | Disk-space wording understates the peak (three files) | Folded (Phase 5 roxygen) |
| 10 | Gap | `local_update_world()`'s ingest mock must forward `build_index` | Folded (Phase 3) |
| 11 | Gap | Post-copy check should cover every table, not only `documents`/`embeddings` | Folded: every `main` table's row count |
| 12 | Scope | Comments saying the update rebuilds the index become false | Folded (Phase 3) |
| 13 | Acceptance | Check the compacted file's `.wal`, not `work`'s, before the rename | Folded (Phase 3) |
