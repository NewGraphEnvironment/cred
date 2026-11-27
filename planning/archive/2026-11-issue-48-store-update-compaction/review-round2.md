# Code-check round 2, #48 (branch vs d08ff2c, HEAD ab25ccc)

## Checklist read

- code-check.md: the prose of every H3 under `## Mechanisms`, table rows skipped. Read in full: "A guard
  that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the
  property", and the start of "Verification that reads its own output" (my output was cut off there).
  The remaining 10 Mechanisms headings, from "A guard's scope, escape hatches, and remedies" on, I
  took from their index lines only. None of `## Rules that stand alone`, Security or Spreadsheets
  read in full (about 27 headings not read).
- code-check-r.md: read 4 sections in full: "A `function(...)` mock hides arguments the real callee
  no longer accepts", "duckdb refuses a parent delete in the transaction that deleted its children",
  "`tempfile()` lives in the session tempdir, so a path printed in an error names a file R is about to
  delete", "A database driver's value is not a base R type — and it fails twice". The rest from
  their index lines only (about 150 not read).
- code-check-shell.md: index lines only (0 read in full). The diff has no shell code.
- code-check-spatial.md: index lines only (0 read in full). Nothing spatial in the diff.

## Findings

- **[severity: fragile]** tests/testthat/test-store-update.R:471-479 ("an updated store carries no
  more free space than a fresh build (#48)"): round 1's fix makes the `doc_id` restart reachable, but
  the `chunk_id` check still cannot fail, and `chunk_id` is the case the test's own comment names
  ("`chunk_id`, the FTS index's key, has no constraint and would repeat silently"). The fixture
  removes **keyA**, which held the low ids, so a restarted `chunk_id_seq` hands keyC exactly the ids
  the removal freed. Measured in a detached worktree at ab25ccc, ids per document:

  | step | keyA | keyB | keyC |
  |---|---|---|---|
  | build A, B | doc 1, chunks 1-7 | doc 2, chunks 8-14 | |
  | update B (drop A, compact) | | doc 2, chunks 8-14 | |
  | update B, C, `chunk_id_seq` restarted at 1 after the COPY | | doc 2, chunks 8-14 | doc 3, chunks **1-7** |

  No duplicate, so `COUNT(*) = COUNT(DISTINCT chunk_id)` holds. I planted a restart of
  `chunk_id_seq` only, recreated under its own name with `START 1` right after `COPY FROM DATABASE`
  in `.crd_store_compact()`. **All of test-store-update.R stayed green**, the inventory test
  included, because the name was kept. A restart of both sequences does go red (keyC is not
  ingested, and `contents()` and `bm25_hits()` fail), so the check that works today is the
  `doc_id` side, reached indirectly. On the installed duckdb 1.5.6 there is no live bug: a
  standalone probe shows `COPY FROM DATABASE` recreates a sequence with `START` at its current
  position, and the next insert takes the next id. The gap is the one round 1 raised: this test is the
  only guard for CI's duckdb 2.0, and on its `chunk_id` half it is vacuous. To reach it, remove the
  document holding the low ids (drop keyB and keep keyA, so a restart collides with keyA's 1-7), or
  assert that the new document's `min(chunk_id)` is above the largest id issued before (14 here).
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode"; code-check.md "Restore the bug and prove the guard fires"

No other findings. Checked and found sound:

- Every exit from `crd_store_update()` after the copy (error, the "Store is current" early return,
  a failure inside `.crd_store_compact()`, the rename) unlinks `work`, `compact` and both `.wal`s.
  `.crd_store_compact()`'s own `on.exit` closes its connection before the outer unlink runs. The store
  is untouched until `file.rename()`, and its FALSE is checked.
- `COPY FROM DATABASE` carries both sequences at their current values (duckdb 1.5.6, probed); a
  leftover `-compact` from a crashed run with the same pid makes the COPY fail, not merge, and is then
  unlinked.
- `.crd_store_drop_indexes()` runs on a plain connection before ragnar opens the copy, so the 0.4.0
  upgrade finds no HNSW SQL to replay. `INSTALL vss` needs nothing ragnar's own connect did not
  already need.
- The row-count check compares every table of the source with the copy, and a table that is missing
  from the copy reads as NA, which also refuses.
- `build_index` is a formal of ragnar 0.4.0's `ragnar_store_ingest()`, and both mocks carry it. The
  mock in test-store-build.R asserts its argument names against `formals()`.
- No file path goes into a cli format string; the new messages use `stop()`/`warning()` with `paste`.
- Unverified, not a finding: the compacted file is created by the running duckdb with that duckdb's
  default storage version, where an in-place update used to keep the store's own. A fresh
  `crd_store_build()` already behaves this way, so the only open question is whether duckdb 2.0's
  default can be read by 1.x readers. I had no 2.0 to test.

index, diff and changed files read from file
