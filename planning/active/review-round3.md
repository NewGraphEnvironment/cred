# Code-check round 3 (#48): the mechanism behind rounds 1 and 2, swept

## Checklist read

- **code-check.md**: every H3 under `## Mechanisms`, prose only, table rows skipped (14 of 14):
  A guard that fails toward pass; A fixture that cannot reach the failure mode (in full); A proxy
  is not the property; Verification that reads its own output; A guard's scope, escape hatches,
  and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove
  the guard fires (in full); A shared working tree, and what generators leave in it; A wrapper's
  exit is not the work; Zero-length, empty, and unset are three different things; The probe is
  broken before the world is; Written data outlives the fix; Serialization loses meaning
  silently; One fact derived twice. Not read: the 28 headings under Rules that stand alone,
  Security and Spreadsheets and PDFs.
- **code-check-r.md**, 11 read: A database driver's value is not a base R type; duckdb refuses a
  parent delete in the transaction that deleted its children; duckdb in R: the query that
  autoloads `icu`...; A `function(...)` mock hides arguments the real callee no longer accepts;
  Copy a live SQLite database with its `-wal`; `tryCatch()` nests its handlers...; Under
  `R CMD check`, tests run from a temp dir against the INSTALLED package; `fs::file_move()` onto
  an existing directory nests the source inside it; testthat counts an uncaught error under
  `error`, not `failed`; Tests that silently do not run; `tempfile()` lives in the session
  tempdir.... About 121 not read.
- **code-check-shell.md**: none read (the diff has no shell code). 75 not read.
- **code-check-spatial.md**: none read (nothing spatial in the diff). 98 not read.

## The mechanism

Rounds 1 and 2 both had **an assertion about the update's end state, read from a quantity that a
later step of the same update overwrites or reuses**. A restarted sequence's ids were not held by
any row once the document holding them was gone. Freed blocks are reused by whatever writes next.
So the defect left no trace in what the assertion read, and the fixture state could not reach the
failure. The fix in each case was to compare with something captured **independently of the
artifact the defect produced** (ids issued before the update; a fresh build), at a grain the later
step cannot clean up: what was issued, not what is held. A third instance is below.

## Findings

- **[severity: fragile]** tests/testthat/test-store-update.R:612. The pre-0.4.0 test's new
  `expect_lte(free, fresh free)` cannot see a missing compaction. Its comment says the compaction
  removes the space ragnar's upgrade freed. But with indexes dropped first, the update's single
  in-place index build reuses every freed block. **Proven:** I replaced
  `.crd_store_compact(work, compact)` with building the index in `work` and renaming that, keeping
  the drop and `build_index = FALSE`. The resulting store has 20 blocks, 0 free; the fresh build
  has 19 blocks, 0 free. The assertion stays green and so does all of that test (10 passes). At
  HEAD the store has 19 blocks, 0 free. So only the block total separates the two, and this test
  does not assert it (D1 asserts both). Free blocks stand in for "no larger than a fresh build"
  here: the rounds 1/2 mechanism, freed space consumed before it is read. It does go red against
  the exact prior `store.R` (in-place rebuild with indexes kept), so the assertion is not idle. It
  just does not guard what its comment says, and NEWS's "no longer grows when an update upgrades
  it" has no guard on the pre-0.4.0 path. Add `expect_lte(...[["total"]], ...[["total"]])` beside it.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode"; code-check.md "A proxy is not the property"

- **[severity: fragile]** R/store.R:2770 (`.crd_store_compact` row-count check). Nothing tests this
  guard, and it fails toward pass on an empty table list. **Proven:** with the `stop()` replaced by
  `if (FALSE)`, every update test stays green (M5). With the guard kept and a planted loss after the
  COPY (`DELETE FROM cred_to.main.cred_ragnar`), it fires and the updates error (M6), so today it
  works. With the loss planted and the guard deleted, only the stamp test notices, and only
  because the planted table is `cred_ragnar`; a loss in `cred_sources` or `metadata` would depend
  on `contents()` or nothing (M6b). Changing the filter to a name that matches nothing
  (`database_name = 'cred_fromX'`) leaves the loop with zero iterations and the suite green (M9).
  The guard's own premise, that the list holds the tables just copied, is not asserted. The cheap
  fix is `if (nrow(tables) == 0L) stop(...)`, or compare the two databases' table lists before
  counting. One test that plants a loss through a mocked `DBI::dbExecute` (or a spy on the COPY)
  would close it.
  - **Rule:** code-check.md "A guard that fails toward pass"; code-check.md "Restore the bug and prove the guard fires"

No security issue and no data-loss bug found in the runtime path. Probed and holding on duckdb
1.5.6:
- constraints (PK `documents(doc_id)`, UNIQUE `origin`, PK `embeddings(doc_id, start, end)`,
  NOT NULLs), column types and defaults, and table SQL are identical between an updated
  (compacted) store and a fresh build;
- sequence counters carry through the COPY (updated `chunk_id_seq` 22 / `doc_id_seq` 4, against
  the fresh build's 15 / 3).

## Per-guard list

Planted defects ran in a detached worktree at f2a8336, one process per mutation, against ten
update tests. Red counts `failed > 0 | error`. The mutation is checked for exactly one match, for
the new text being present, and for the file parsing. Worktree removed afterwards.

| guard | planted defect | red? | how known |
|---|---|---|---|
| D1 `expect_lte(free)` / `expect_lte(total)` | M1 no compaction (index built in `work`, renamed) | RED (f2) | proven |
| D1 same | M8 FTS schemas not dropped (copied, then rebuilt in compacted file) | RED (f2) | proven |
| D1 same | exact prior `store.R` (d08ff2c, ingest signature patched to take `build_index`) | RED (f2) | proven |
| D1 `expect_identical(contents, fresh)` | M7 no index build | not separately; test errors on bm25 | proven (test RED) |
| D1 `new$doc/new$chunk > issued` | restarted sequences | RED | proven in round 2 |
| D1 `COUNT(*) == COUNT(DISTINCT chunk_id)` | restarted chunk sequence | cannot fire alone: any reuse is also `<= issued` and fails the line above first | reasoned (subsumed backstop, harmless) |
| D1 `bm25_hits > 0` | M7 no index build in compaction | RED (error) | proven |
| D2 inventory identical to fresh | M7 no index build | RED (f4, e1) | proven |
| D2 inventory | M1 no compaction | green (inventory has no size) | proven, as designed |
| D2 inventory scope | COPY dropping a constraint or column default | would stay green: `duckdb_constraints()`, `duckdb_columns()` and sequence counters are outside it, so its comment "two stores that agree here and in their rows are the same store" over-claims (counters differ by design, 22 vs 15). D1's second ingest needs PK `doc_id` for `ON CONFLICT`, so that one loss would error; UNIQUE `origin` loss would be silent | reasoned; constraints probed identical on 1.5.6 |
| D2 `.crd_test_cosine_indexed` / `expect_length(indexes, 3)` | M7 | RED | proven |
| D3 md5 unchanged + `list.files` | M4 `compact` dropped from `on.exit` | RED (f1) | proven |
| D3 | `paste0(compact, ".wal")` dropped from `on.exit` | green: the mock writes no WAL | reasoned |
| renamefail test (`file.rename` mocked FALSE) | M4 | RED (f1) | proven: it now also covers the compacted file's cleanup |
| D4 pre-0.4.0 `expect_lte(free)` | M1 no compaction | **green** (20 vs 19 total, 0 free both) | proven, **Finding 1** |
| D4 same | exact prior `store.R` | RED (f1) | proven |
| D4 same | M8 FTS not dropped | RED (f1) | proven |
| D6 pre-0.4.0 record-only `cosine_indexed` | M7 no index build | RED (f1) | proven |
| `.crd_store_drop_indexes` HNSW loop | M11 removed | RED everywhere an update writes (COPY refuses an HNSW index) | proven |
| `.crd_store_drop_indexes` whole call | M2 removed | RED (same) | proven |
| ingest `build_index = FALSE` | M3 `TRUE` | RED on every test that ingests (D5, D1, D2, stamp); green on removal-only tests, where it is not reached | proven |
| row-count guard (`.crd_store_compact`) | M5 deleted | **green on all** | proven, **Finding 2** |
| row-count guard | M6 row loss planted, guard kept | RED (fires) | proven |
| row-count guard | M9 table list empty | **green on all** (zero-iteration loop) | proven, **Finding 2** |
| WAL check on `work` after close (`crd_store_update`) | M10 deleted | green: duckdb leaves no WAL after a clean shutdown, so no test can reach it | proven green, reasoned unreachable |
| WAL check on `to` in `.crd_store_compact`, and again before the rename | deleted | green, same reason | reasoned |
| leftover `.updating-*` warning | any | no test asserts it (pre-existing; the branch changed only its words; the glob also matches `-compact`) | reasoned |
| test-store-build.R `mock_args %in% formals(ragnar_store_ingest)` | ragnar without `build_index` | RED by construction; the mock has no `...`, so a new argument from cred also errors | reasoned |

index, diff and changed files read from file
