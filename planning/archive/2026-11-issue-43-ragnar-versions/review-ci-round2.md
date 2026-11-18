## Checklist read

- code-check.md, `## Mechanisms`: the prose of every H3 (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice), and Documentation Staleness.
- code-check-r.md, from the index, by heading for the shapes the diff uses: Tests that silently do not run; testthat counts an uncaught error under `error`, not `failed`; A `skip_if_not()` skips only its own `test_that()` block; Under `R CMD check`, tests run from a temp dir against the INSTALLED package; `on.exit()` at a script's top level never fires; duckdb refuses a parent delete in the transaction that deleted its children.
- code-check-shell.md and code-check-spatial.md: no heading names a tool or shape this diff uses.

## Method

- Ran the pre-0.4.0 tests in `test-store.R` on HEAD (7794d9d) in a detached worktree, under duckdb 1.5.6 (default library) and duckdb 2.0.0 (`R_LIBS=.../lib/duck2`), both with ragnar 0.4.0, `NOT_CRAN=true`: all three tests pass under both (0 failed, 0 error).
- Mutation: replaced the record-only `ragnar::ragnar_store_build_index(store)` in `crd_store_update()` (R/store.R:2658) with `invisible(NULL)` in the worktree, then ran `test-store-update.R`:
  - duckdb 1.5.6: "an update that only records a pre-0.4.0 store's files rebuilds the index the upgrade broke" goes red, 1 failed.
  - duckdb 2.0.0: the same test stays green, 0 failed.
- Worktree removed afterwards. The repository's own files were not edited.

## Findings

- **[severity: fragile]** tests/testthat/test-store-update.R:551-566. This commit makes the `test-store.R` assertion conditional on the duckdb that created the fixture's indexes. Its sibling, the test that guards the record-only index rebuild, got no such change, and it has the same blind spot. Under duckdb 2.0 the fixture's indexes record their metric, so ragnar 0.4.0's upgrade keeps the cosine index and there is nothing broken for the rebuild to fix. The final `expect_true(.crd_test_cosine_indexed(path))` then passes with or without R/store.R:2657-2659. I measured this: with the rebuild removed, the test fails under duckdb 1.5.6 and passes under duckdb 2.0.0. CI runs duckdb 2.0.0, so CI no longer guards the record-only rebuild. A deletion of that line, or a refactor that loses it, would merge green. The test's name ("rebuilds the index the upgrade broke") is false on CI, which hides this.
  - Fix: assert the premise the test depends on, or make the vacuity visible. For example, `skip_if(.crd_test_index_sql_has_metric(path), "indexes made under duckdb >= 2.0 record their metric, so ragnar's upgrade breaks nothing to rebuild")` after `.crd_test_to_pre040()`. CI then shows a SKIP instead of a pass that proves nothing, and the guard still fires on a duckdb 1.5.x machine. Its sibling at line 523 needs no change: the ingest path always rebuilds the index, so its cosine assertion is not this line's guard.
  - **Rule:** code-check.md, "A fixture that cannot reach the failure mode" (assert the premise beside the property; make vacuity visible), and "Restore the bug and prove the guard fires". It is also an instance of code-check.md, "A fix lands in one of two callers that share a harness": the fix reached one of two tests that share `local_pre040_store()` / `.crd_test_to_pre040()` and its duckdb-dependent premise.

## Fixes from round 1 (commit 7794d9d), checked

- CLAUDE.md, NEWS.md, R/store.R (roxygen for `.crd_warn_upgrade()` and `crd_store_connect(read_only=)`, the warning text, and the `crd_store_update()` comment), and research/ragnar-versions.md now hedge correctly ("can", "may", "as in every such store measured", "measured on 1.4.3 and 1.5.6", "1.0 to 1.3 untested"). man/crd_store_connect.Rd matches the roxygen. The research provenance line now names duckdb 2.0.0 and the 1.4.3 headers of the real stores. I found no remaining sentence that claims the metric loss for every store or every duckdb.
- The new `test-store.R` assertion `expect_identical(.crd_test_cosine_indexed(path), recorded_metric)` passes under both duckdb 1.5.6 and 2.0.0. `.crd_test_index_sql_has_metric()` returns FALSE when the index row is missing, but the fixture test above it already asserts three HNSW indexes and a working cosine index before the upgrade, so that case cannot slip through here.
