# Code-check round 1, #48 (branch vs d08ff2c)

## Checklist read

- code-check.md: the prose of every H3 under `## Mechanisms`, table rows skipped (14 headings;
  the last few, from "A fix lands in one of two callers that share a harness" on, read only in
  part because the output was cut off). None of the `## Rules that stand alone`, Security or
  Spreadsheets sections read (27 headings not read).
- code-check-r.md: read 4 sections in full: "A `function(...)` mock hides arguments the real
  callee no longer accepts", "duckdb refuses a parent delete in the transaction that deleted its
  children", "duckdb in R: the query that autoloads `icu` binds unreliably, so `LOAD icu` before
  it", "Copy a live SQLite database with its `-wal`". The rest I took from their index lines only
  (about 150 not read).
- code-check-shell.md: index lines only (0 read in full). The diff has no shell code.
- code-check-spatial.md: index lines only (0 read in full). Nothing spatial in the diff.

## Findings

- **[severity: fragile]** tests/testthat/test-store-update.R:469-476: the sequence assertions in
  "an updated store carries no more free space than a fresh build (#48)" can never fail. The
  comment says "The second update ingested into a compacted file", but it did not. The second
  call is `update(path, c("keyB", "keyC"))` on a store that already holds A, B and C with
  unchanged md5s, so `to_ingest` is empty and it only drops keyA. No test in the file ingests
  into a store an earlier compaction produced. Proof: in a detached worktree I changed
  `.crd_store_compact()` so that, after `COPY FROM DATABASE`, `documents.doc_id` and
  `embeddings.chunk_id` take their defaults from new sequences that `START 1`. That is a restarted
  sequence. This test, with both of its `COUNT(*) = COUNT(DISTINCT ...)` checks, still passed, and
  so did every other test in test-store-update.R except the inventory test. That one failed only
  because my planted sequences added two names, so a reset that kept the names would pass it too.
  - **Why it matters:** `embeddings.chunk_id` has no unique constraint, and it is the id the FTS
    index is keyed on (ragnar's DDL calls it "need a unique id for fts"). If the copy restarted
    the sequence, the next update's ingest would write duplicate chunk_ids without any error, and
    BM25 would merge chunks. A restarted `doc_id_seq` would at least fail loudly on the
    primary key.
  - **No live bug on the installed stack:** a standalone probe on duckdb 1.5.6 shows that
    `COPY FROM DATABASE` recreates a sequence with `START` at its current position. Its
    `start_value` was 6 after 5 nextvals, and the next insert took id 6.
  - **What is unverified:** this suite is the only guard for duckdb 2.0, which CI runs, and on 2.0
    the guard is vacuous. To make it reachable, the second update should ingest something, for
    example a third `update(path, c("keyA", "keyB", "keyC"))` after the drop, before the
    distinct-id checks.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode" ; code-check.md "Restore the bug and prove the guard fires"

No other findings. Checked and found sound:

- Every path out of the update, error or early return, cleans up `work`, `compact` and their
  `.wal` files on exit.
- `file.rename()`'s FALSE is checked, and the store is untouched until the final rename.
- `.crd_store_drop_indexes()` runs before ragnar opens the copy, so `upgrade_v2_store()` finds no
  HNSW SQL to replay.
- Each table's row count is compared with the copy's.
- The `build_index` argument exists in ragnar 0.4.0's `ragnar_store_ingest()`, and both mocks
  carry it.
- No file path goes into a cli format string.

index, diff and changed files read from file
