# Code-check round 4 (CI fix), #48

Diff: `tests/testthat/test-store-update.R`, "an updated store holds every object a
fresh build holds, its indexes usable": `expect_identical(got$views, "main.chunks")`
becomes `expect_true("main.chunks" %in% got$views)`.

## Checklist read

Index read; rules applied: "Verification that reads its own output", "A fixture that
cannot reach the failure mode", "A guard that fails toward pass", "Zero-length, empty,
and unset are three different things", "Restore the bug and prove the guard fires".
None is broken by this diff.

## Clean

Evidence:

- **Only one assertion in the file assumed duckdb 1.5.6.** CI run 45940061185
  (duckdb 2.0.1, ragnar 0.4.0) reports `[ FAIL 1 | WARN 0 | SKIP 4 | PASS 987 ]`, the
  single failure at `test-store-update.R:254`. testthat continues after a failed
  `expect_*`, so the lines after it in the same block ran under duckdb 2.0 and passed:
  `expect_identical(got, .crd_test_inventory(fresh))`, the tables check,
  `expect_length(got$indexes, 3L)`, `.crd_test_cosine_indexed(path)` and `bm25_hits`.
  The two SKIPs that matter are the Ollama ones in `test-store-fallback.R`, not in this
  file.
- **The comparison with a fresh build is independent of the code under test.**
  `.crd_store_compact()` has one caller, `R/store.R:2689`, inside `crd_store_update()`;
  `crd_store_build()` does not compact. So `fresh` never goes through `COPY FROM DATABASE`
  and its views cannot share a defect the compaction introduces. A compaction that dropped
  or added a view would still fail line 252 under either duckdb. This is not "Verification
  that reads its own output".
- **What the exact match checked that the new line does not:** that neither store holds a
  view other than `main.chunks`. Both stores are written by ragnar and duckdb, so that was
  a fact about those versions, not about #48; dropping it loses nothing #48 owes.
- **The new line keeps the non-vacuity floor.** If `.crd_test_inventory()`'s view query
  returned nothing on both stores (wrong `database_name`, `internal` flag flipped), line
  252 would pass on two empty vectors; `"main.chunks" %in% got$views` still fails then, as
  the old line did. Same for tables (`all(... %in% got$tables)`) and indexes
  (`expect_length(..., 3L)`).
- **Helper under duckdb 2.0:** `.crd_test_inventory()` has no version-specific literal.
  `schemas`, `sequences` and `macros` have no absolute floor, so on two empty results the
  comparison would pass on them, but that predates this diff and each is covered
  functionally elsewhere: sequences by the issued-id assertions in the free-space test
  (`expect_gt(new$chunk, issued$chunk)`, `expect_gt(new$n, 0)`), the FTS macros by
  `bm25_hits(path, "zzzonlykeyC") > 0`, which calls them. `.crd_test_cosine_indexed()`
  greps an `EXPLAIN` plan for `HNSW` and passed on CI under 2.0.1, so it is not vacuous
  there. `.crd_test_index_sql_has_metric()` is the one helper written around a
  1.5.6/2.0 difference, and it is not used by this block.
- **The new comment is accurate:** CI's `actual` reads
  `"fts_main_chunks.index_metadata" "main.chunks"`, and line 252 passed there.

Not run: the test under duckdb 2.0 locally (CI on 2a1f0df is in progress at review time).
