# Review: CI round 3 (commits 9c6f403, 7794d9d against 121c998)

## Checklist read

- code-check.md, `## Mechanisms`: the prose of all fourteen H3s (evidence-table rows skipped).
  Applied mainly: "A fixture that cannot reach the failure mode", "Restore the bug and prove the
  guard fires", "A guard's scope, escape hatches, and remedies", "A guard that fails toward pass".
- code-check-r.md, in full: "duckdb refuses a parent delete in the transaction that deleted its
  children", "`expect_false(identical(x, y))` cannot fail when the two are different types",
  "A `skip_if_not()` skips only its own `test_that()` block", "testthat counts an uncaught error
  under `error`, not `failed`".
- Agent rules: section 3, "Presence is not provenance" and "Measure before you characterise".

## Measurements (2026-11-18, ragnar 0.4.0, duckdb 1.5.6 default library vs 2.0.0 via `R_LIBS`)

1. Recorded index SQL, for `CREATE INDEX ic ON e USING HNSW (v) WITH (metric = 'cosine')`:
   - 1.5.6: `CREATE INDEX ic ON e USING HNSW (v);`
   - 2.0.0: `CREATE INDEX ic ON e USING HNSW (v) WITH (metric = 'cosine' );`
   - `.crd_test_index_sql_has_metric(local_pre040_store())` reads FALSE on 1.5.6 and TRUE on 2.0.0.
2. In a detached worktree of 7794d9d, test-store.R's three pre-0.4.0 blocks pass on both versions
   (4/4/4 expectations, 0 failed, 0 error). CI for 9c6f403 R-CMD-check: success.
3. **Mutation:** with the record-only `ragnar::ragnar_store_build_index(store)` deleted from
   `crd_store_update()` (R/store.R:2657-2659), the pre-0.4.0 tests in test-store-update.R:
   - duckdb 1.5.6: block "an update that only records a pre-0.4.0 store's files rebuilds the index
     the upgrade broke" **fails 1** (the final `.crd_test_cosine_indexed()`).
   - duckdb 2.0.0: the same block **passes, 0 failed, 0 error**.
4. Header: a file created under 1.5.6 and then written by 2.0.0 (a new table, checkpointed) still
   reads `v1.5.6` in its header. The header names the duckdb that **created the file**, not the one
   that last wrote it or made its indexes. The real `pine.duckdb` header reads `v1.4.3`; read
   read-only under 1.5.6, its `duckdb_indexes().sql` has no metric on any of its three HNSW indexes.
5. Other version-dependent CLAUDE.md sentences, checked: the foreign key reverse reference keeping a
   renamed table's old name, and the transactional parent delete being refused, both reproduce on
   1.5.6 **and** on 2.0.0.

## Findings

- **[severity: fragile]** tests/testthat/test-store-update.R:552-566, guarding R/store.R:2653-2659.
  This is the same reach defect 9c6f403 fixed in test-store.R, left in the sibling test. Under
  duckdb 2.0.0, the version CI runs, the fixture's indexes record their metric and ragnar 0.4.0's
  upgrade keeps them. So the final `expect_true(.crd_test_cosine_indexed(path))` holds whether or
  not the update rebuilds the index. Measured: with the record-only rebuild deleted, the block goes
  red on 1.5.6 and stays green on 2.0.0 (Measurements, 3). On CI nothing guards the rebuild that
  #43 added for the record-only path, and the test's title still says it covers it.
  test-store-update.R:536-537 has the same reach on CI for the changing update; there the ingest's
  own rebuild is what it guards. A fixture that reaches the defect on every duckdb: after
  `.crd_test_to_pre040()`, recreate the cosine and ip indexes without `WITH (metric = ...)` (which
  is what the real stores record), check that `.crd_test_cosine_indexed()` is FALSE first, then
  update and expect TRUE.
  - **Rule:** code-check.md, "A fixture that cannot reach the failure mode" (and "Restore the bug
    and prove the guard fires").

- **[severity: fragile]** CLAUDE.md:355-356 ("measured on 1.4.3 and 1.5.6") and
  research/ragnar-versions.md:46 ("measured: 1.4.3, the real stores' version"). Nobody measured an
  index being created under 1.4.3. The 1.4.3 comes from the real stores' file header, which names
  the duckdb that created the file and is not rewritten by later writers (Measurements, 4). So the
  duckdb that made those stores' indexes is not recorded: ragnar builds the index at the end of
  every ingest, and a later session could have run it under 1.5.x. What *was* measured on the real
  stores is the outcome: their recorded SQL has no metric, and the upgrade loses it under both
  1.5.6 and 2.0.0. The rule's conclusion (real old stores lose the metric) therefore stands. Only
  the "measured on 1.4.3" provenance overstates. It matters because the "before 2.0" boundary is
  partly argued from that data point. Accurate wording: "the real stores (files created under
  1.4.3) record no metric; index creation measured under 1.5.6 only".
  - **Rule:** none in the code-check files; CLAUDE.md agent rules section 3, "Presence is not
    provenance".

No bugs in the code itself: the R/store.R changes touch only comments and the warning's wording,
and the helper's `.crd_test_index_sql_has_metric()` reads the right row on both versions.

## Mechanism and enumeration

Mechanism: what ragnar 0.4.0's upgrade rebuilds depends on the duckdb that **created each HNSW
index**, not on the duckdb or ragnar that runs. The fixture creates its indexes under whatever duckdb
is installed, so every assertion whose expected value turns on "the upgrade lost the metric" changes
meaning between 1.5.x (local) and 2.0.0 (CI).

| # | Where | Depends on | duckdb 1.5.x | duckdb 2.0.0 | Stated versions = measured? |
|---|---|---|---|---|---|
| 1 | test-store.R:270-272, fixture `fk == 1`, `hnsw == 3` | none in practice (`USING HNSW` appears in both SQL forms) | holds | holds | n/a |
| 2 | test-store.R:273, fixture cosine-indexed before upgrade | index built WITH metric under either | holds | holds | n/a |
| 3 | test-store.R:292,304, `cosine_indexed == recorded_metric` after RW connect | index creator's duckdb | FALSE == FALSE: pins the ragnar defect | TRUE == TRUE: cannot see the defect, as its comment says ("where the fixture can reach it") | yes |
| 4 | test-store.R:288-310 comments ("real ... stores ... made under duckdb 1.4.3") | header vs index creator | — | — | **no**: 1.4.3 is the file creator (finding 2) |
| 5 | test-store-update.R:534-535, `fk == 0`, `hnsw == 3` after update | ragnar 0.4.0 upgrade | holds | holds | n/a |
| 6 | test-store-update.R:536-537, cosine-indexed after a changing update | index creator's duckdb | guards the ingest's rebuild | vacuous for the rebuild (upgrade keeps metric) | comment "can lose" is accurate |
| 7 | test-store-update.R:560, precondition before record-only update | none | holds | holds | n/a |
| 8 | test-store-update.R:565, cosine-indexed after record-only update | index creator's duckdb | **guards** R/store.R:2657 (mutation red) | **vacuous** (mutation green) | title overstates on CI: finding 1 |
| 9 | test-store-update.R:504-521, md5 unchanged / not upgraded on a no-op update | ragnar opens copy, not original | holds | holds | n/a |
| 10 | test-store-push.R:541-581, `store_schema == "pre-0.4.0"` | schema columns only | holds | holds | n/a |
| 11 | helper-store.R:420-423 comment "1.5.x without, 2.0 with" | duckdb at index creation | measured 1.5.6 | measured 2.0.0 | "1.5.x" generalises from 1.5.6 |
| 12 | helper-store.R:448-452 comment "before 2.0 lacks the metric" | as above | 1.5.6 measured; 1.0-1.4 not | — | extrapolated below 1.5.6 |
| 13 | helper-store.R:465-467, `.crd_test_index_sql_has_metric()` | as above | FALSE | TRUE | yes (measured here) |
| 14 | R/store.R:443-446, `.crd_warn_upgrade` roxygen "created by duckdb before 2.0 (as in every such store measured)" | as above | true for 1.5.6; the real stores record no metric | false for 2.0-made indexes, which it excludes | the "before 2.0" boundary is extrapolated from 1.5.6 and the real stores' outcome |
| 15 | R/store.R:469, warning "may go unused" | hedged | holds | holds | n/a |
| 16 | R/store.R:537-538, man/crd_store_connect.Rd:32-33 "can lose" | hedged | holds | holds | n/a |
| 17 | R/store.R:2653-2656 comment "recreates HNSW indexes made by duckdb before 2.0 without their metric" | as 14 | as 14 | as 14 | as 14 |
| 18 | NEWS.md:10-15 "can go unused", "about 1.85x on two real stores" | hedged; size measured | holds | pine 52.7 MB under 2.0 too (research) | yes |
| 19 | CLAUDE.md:355-357 "lacks the metric ... before 2.0 (measured on 1.4.3 and 1.5.6 ...); one built under duckdb 2.0 would keep it" | as 14 | 1.5.6 measured | 2.0.0 measured (CI and here) | **1.4.3 not measured** (finding 2) |
| 20 | CLAUDE.md:363-364 "under duckdb 2.0 they record them, so the upgrade keeps them" | as 14 | — | holds, measured | yes |
| 21 | CLAUDE.md:364-366 renamed table's old name in the FK reverse reference | duckdb | holds (1.5.6) | holds (2.0.0, measured here) | yes |
| 22 | CLAUDE.md, "Deletes are two statements ... duckdb refuses the parent delete" (unchanged bullet) | duckdb + ragnar 0.3.1 FK | holds (1.5.6) | holds (2.0.0, measured here) | yes |
| 23 | research/ragnar-versions.md:6-7 provenance "duckdb 1.5.6, and 2.0.0 ...; file headers duckdb 1.4.3" | — | — | — | accurate as written ("file headers") |
| 24 | research/ragnar-versions.md:43-51 "1.5.x without, 2.0.0 with"; "measured: 1.4.3"; "pine ... under 2.0.0 lost the metric"; "why the regression test passed on CI" | as 14 | 1.5.6 measured | 2.0.0 measured | "measured: 1.4.3" **no** (finding 2); "1.0 to 1.3 untested" is honest but 1.4.x/other 1.5.x are also unmeasured as index creators |
| 25 | research/ragnar-versions.md:83-84 "Every update that changes something rebuilds the index, so it also restores the HNSW metrics the upgrade loses" | — | holds | holds (nothing lost) | n/a |
