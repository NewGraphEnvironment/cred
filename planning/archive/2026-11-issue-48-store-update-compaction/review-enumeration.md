# Code-check enumeration for #48 (ends the loop after round 3)

Round 2 found a defect inside round 1's fix, so only an enumeration ends the loop. Round 3 named the
mechanism: an assertion about the updated store that reads a quantity the update itself reuses or
overwrites (freed ids, freed blocks), so the defect leaves no trace in what the test reads. The cure
is to compare against something captured outside the defective store (ids issued before, a fresh
build). The candidate set is every assertion and guard the branch adds: 31 guard-by-defect rows.

Rows 1-27 are round 3's table (`review-round3.md`, "Per-guard list"), run at f2a8336. Its two
findings (rows "D4 pre-0.4.0 free" under M1, and the row-count guard under M5 and M9) were fixed in
c5924ed and re-proven below. Rows 28-31 were planted at c5924ed in a detached worktree, one process
per mutation, against all 36 tests in `test-store-update.R`.

| # | guard | planted defect | red? |
|---|---|---|---|
| 28 | pre-0.4.0 test `expect_lte(total)` (new) | M1 no compaction | RED: 20 > 19 |
| 29 | free-space test `free` and `total` | M1 no compaction | RED: 1 > 0 free, 20 > 19 total |
| 30 | "a compaction that loses rows, or finds no tables" (mocked loss in `cred_sources`; mocked empty list) | row-count check replaced by `if (FALSE)` | RED (both halves) |
| 31 | `.crd_store_rows()` unit test (two schemas, a deleted row, an unattached name) | n/a: reads a real database | passes; distinguishes the deleted row |

Rows that cannot go red, and why that stands:

- `COUNT(*) == COUNT(DISTINCT chunk_id)`: subsumed by the issued-id check, which fails first on any
  reuse. Harmless backstop.
- The three `.wal` checks (work after close, compacted file in `.crd_store_compact()`, compacted file
  before the rename): duckdb leaves no WAL after a clean shutdown, so no test reaches them. They
  fail toward refusing, never toward a bad store.
- `paste0(compact, ".wal")` in `on.exit()`: the mock writes no WAL; reasoned.
- The leftover `.updating-*` warning: asserted by no test before or after; the branch changed only
  its wording, and its glob already matches `-compact`.
- Inventory scope: constraints, column defaults and sequence positions are outside
  `.crd_test_inventory()`; its comment no longer claims otherwise (c5924ed). Constraints were probed
  identical on duckdb 1.5.6 by round 3; a lost `doc_id` key would make the second ingest's
  `ON CONFLICT` error.

Nothing in the set sits above its source of truth: every guard that can be reached goes red under the
defect it exists for.
