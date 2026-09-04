# Progress — crd_search() errors on ragnar list columns (#27)

## Session 2026-09-04

- Plan-mode exploration — reproduced the failure offline (deterministic `embed` function,
  no Ollama, no bucket), which settled the issue's open question about whether a real-ragnar
  regression fixture is possible. It is.
- Multi-element-cell contract decided with the user: first element plus a warning.
- Created branch `27-crd-search-errors-on-ragnar-list-columns` off main.
- Scaffolded PWF baseline from issue #27 with approved phases.
- Next: Phase 1 — fixture helper and the failing regression test.

### Phase 1 — regression test (complete)

- Discovered mid-implementation that the "every list cell is length 1" premise was a
  fixture artifact: `as.numeric()` on length-1 list cells works, so the six-document
  fixture passed against the very bug it was written for. Re-measured on a multi-chunk
  corpus — 24% of rows are merged and multi-element — and re-opened the contract decision
  with the user, who chose direction-aware reduction (max for bm25, min for
  cosine_distance) with no warning.
- Plan-agent review landed concurrently and reached the same conclusion from ragnar's
  source (`chunks_deoverlap()`), plus found a leaked duckdb writer connection, two missed
  call sites, a vacuous warning assertion, a 7-character fixture key that could never
  resolve, and an embed function that did not bin as its comment claimed. All folded in.
- Confirmed red against unfixed code with the reported error verbatim.
- Next: Phase 2 — `.crd_flat()` and its call sites.

### Phase 2 — the reducer (complete)

- `.crd_flat(x, type, reduce, n)` in `R/store.R`. `type` always comes from the call site,
  never inferred, so one character cell cannot promote a numeric column. `n` turns an
  absent column into typed `NA`s — the frame's column set is variable (no `bm25` column at
  all when nothing matched lexically) and a zero-length column is a tibble recycling error.
- `.crd_retrieval_score()` reduces per metric direction: `max` for `bm25`, `min` for
  `cosine_distance`. Preference order (bm25 first) preserved.
- `crd_search()` routes `chunk_id`, `start`, `end`, `origin`, `text` through the same path.
- Full suite green: 316 pass, 0 fail, 2 pre-existing skips.

### Phase 3 — verification

- **Restore-the-bug done properly**: `git checkout HEAD -- R/store.R` (the source that had
  it, not a hand-written passthrough). Result: 10 failures, and test-store-search.R:34
  reported `'list' object cannot be coerced to type 'double'` verbatim. Fix reinstated:
  66 pass, 0 fail.
- `lintr::lint_package()` — 0 lints. `R/store.R` alone went 69 -> 63 default-linter hits.
- `devtools::document()` — only `crd_search.Rd` rewritten, NAMESPACE untouched at 25
  exports. One pre-existing `@noRd must not be followed by any text` warning at
  R/store.R:985 confirmed present at HEAD by stashing; left alone as unrelated.
- `devtools::check()` — 3 warnings, 3 notes, **all six confirmed pre-existing** (non-ASCII
  in R/audit.R and R/store.R at 43 lines on HEAD; undeclared `tibble`/`openxlsx` from
  R/audit.R and test-eval-inline.R; `.data` bindings; `.lintr`; top-level `data-raw`/`dev`).
  `checking tests ... OK` and `checking for detritus in the temp directory ... OK`, so the
  fixture's duckdb connections and tempfile clean up.

### Code-check round 1 — 3 findings, all fixed

Verdict was no bugs and no security issues; the reviewer independently reproduced the
fixture reaching the failure, ran the restore-the-bug check against HEAD's real bytes, and
proved test 3 discriminates `max` from `first` (a simulated first-element reducer fails on
2 of 5 merged rows). All three findings were about **coverage claimed but not held**:

1. `expect_type(out$start/end, "integer")` **cannot fail** — `chunks_deoverlap()` excludes
   `start`/`end`/`context`/`text` from the `across()` that makes list columns, and groups
   by `origin`, so those four are atomic before `crd_search()` sees them. The `.crd_flat()`
   calls on them are deliberate defence, not something the test guards. Now labelled as
   such instead of sitting among assertions that do discriminate.
2. The `cosine_distance` **min** direction is never exercised by the integration test.
   Confirmed and extended: there ARE 90 rows across queries where
   `first(cosine) != min(cosine)`, but every one also carries a bm25 score and is claimed
   by the branch above; and `ragnar_retrieve_vss()` returns atomic long-form columns, so
   the vss path cannot reach it either. Unreachable through any real frame from this
   fixture. The hand-built unit test is now labelled THE ONLY GUARD on that direction,
   with the reason, so it is not deleted later as a redundant edge case.
3. Two false claims in the `top_k` comment: 10 is **not** the smallest value producing a
   multi-element cell (measured 3->1, 5->2, 6->4, 8->4, 10->5, 12->6, 20->8), and it cited
   `.crd_test_multi_row()`, a helper that never existed. Replaced with the measured table
   and a note that raising `top_k` to clear a red premise assertion is papering over an
   upstream change.

Also taken from the "considered and dismissed" list: `skip_if_not_installed("ragnar")`
gained a `"0.3.0"` floor. The fixture uses v2-only API and DESCRIPTION carries an unpinned
`Remotes: tidyverse/ragnar`, so an older install would have ERRORed all four tests instead
of skipping them.

Suite after fixes: 317 pass, 0 fail, 2 pre-existing skips. 0 lints.

### Code-check round 2 — 4 findings, all fixed

Reviewed the complete diff including the fix. No blocker. One user-facing bug, three
latent. All four independently reproduced here before acting on them.

1. **[bug]** `@return` promised "ordered best-match first" and the default path does not
   deliver it. `ragnar_retrieve()` does not re-sort after `chunks_deoverlap()`, whose last
   ordering is `arrange(origin, doc_id, start)`. Measured: `chunk_id` ascending (document
   order), `score` not monotone, and neighbouring rows carry *different metrics* whose
   scores are not comparable — so no single ranking exists to return. A caller doing
   `head(out, 3)` for "the best passages" was getting an arbitrary slice, silently. The
   line predates the branch, but this branch rewrote the bullets beneath it to describe
   deoverlap semantics, which is what makes the sentence false.
   Fixed by **documenting the truth** plus a worked `arrange()` snippet for ranking within
   one metric. Deliberately not fixed by sorting: interleaving two incomparable scales
   needs a stated rule and is a behaviour change beyond this issue.
2. **[fragile]** The long-form `metric_value` branch hardcoded `reduce = "max"`, but that
   shape is what `method = "vss"` returns and its metric is `cosine_distance`, where lower
   is better — "max" would select the *worst* constituent, silently and with the right
   type. Dead today (neither `ragnar_retrieve_bm25()` nor `_vss()` takes `deoverlap`, so
   `metric_value` arrives atomic and `.crd_flat()` returns before consulting `reduce`).
   Fixed by deriving the direction from `metric_name`, via a single `.crd_metric_dirs`
   table both branches now read — the two disagreeing is what produced the defect.
3. **[fragile]** `suppressWarnings()` on the list branch only. Measured:
   `.crd_flat(c("a","b"), "numeric")` warned, `.crd_flat(list("a","b"), "numeric")` was
   silent. The only reachable warning is "NAs introduced by coercion", which means a score
   column holds non-numeric data — silencing it yields an all-NA `score`, the exact silent
   failure this function exists to end. Suppression removed.
   The test asserting the property was titled "never warns" and fed only inputs
   structurally incapable of warning (numeric -> numeric), so it passed for every possible
   implementation. Replaced with one that feeds input that *can* warn and asserts both
   branches behave identically.
   Fixing that surfaced a second-order problem: per-cell coercion emitted one warning per
   row where the atomic branch emitted one per vector. `.crd_flat` now coerces once over
   the flattened column and reduces by group, so the branches are genuinely identical
   rather than approximately so. All edge cases re-verified after the rewrite.
4. **[fragile]** The merged-row test indexed two independent retrievals by the same `i`
   while asserting only equal `nrow`. Added `expect_identical(out$text, res$text)`.

Restore-the-bug re-run against the final code, this time from `main` rather than `HEAD`
(HEAD had moved and already contained the fix — the earlier run was valid only because it
predated the fix commit): `.crd_flat` absent from the namespace, 5 occurrences of
`'list' object cannot be coerced to type 'double'`, 13 failures. Fix reinstated: 78 pass.

Suite: 328 pass, 0 fail, 2 pre-existing skips. 0 lints. `document()` rewrote only
`crd_search.Rd`; NAMESPACE unchanged at 25 exports.

### Code-check round 3 — 3 findings, including a regression round 2 introduced

The third round earned its keep: it found that **round 2's own fix reintroduced the
failure it replaced**, on a different shape.

1. **[bug, regression]** Grouping the long-form score loop by metric meant rows whose
   `metric_name` is absent or `NA` never entered the loop body — returning an all-`NA`
   `score` while `metric_value` sat right there. Measured: `main` and the first fix commit
   both returned `1.2, 0.8`; round 2's version returned `NA, NA`. That is precisely the
   silent failure `.crd_retrieval_score()`'s own roxygen says it exists to end.
   Latent rather than live (ragnar always emits `metric_name` beside `metric_value` as a
   SQL constant), but the `else rep(NA_character_, n)` branch exists because that shape is
   meant to be supported. Fixed by grouping on `ifelse(is.na(metric), "", metric)` so
   unresolved rows are still scored, and pinned by a regression test that fails against
   round 2's loop.
2. **[fragile — the mechanism, and the reason this class kept recurring]** The direction
   table was a single source of truth for **direction** but not for **metric membership**,
   and the two branches consumed it incompatibly: long-form as a lookup-with-default
   (unknown metric scored), pivoted as the roster (unknown column dropped entirely).
   Measured on one metric with one set of values: pivoted gave `NA, NA`; long-form gave
   `0.9, 0.5`. Two different wrong answers for the same input.
   Worse, the comment justifying the `"max"` default was **false**. Read from
   `ragnar:::method_to_info()`: `cosine_distance`, `euclidean_distance` and
   `negative_inner_product` are all `"ASC"` — every metric ragnar offers besides BM25 is a
   distance, so the intuitive default was the wrong one.
   Fixed by making the table authoritative for membership too: the pivoted branch now
   enumerates score columns present in the frame and resolves each through
   `.crd_metric_direction()`, so a metric can only be handled one way. The default is
   `"min"`, with the evidence recorded rather than the guess. A type guard (numeric or
   list) backs up `.crd_non_metric_cols`, so the exclusion list does not have to be
   complete for a character column to be safe from being read as a score.
3. **[fragile]** The ">= ten cells" test's stated rationale was false — `split()` groups by
   an *integer* factor, whose levels sort numerically, so there is no `"10"` before `"2"`
   hazard and two of its three assertions could not discriminate. Rewritten to say that
   plainly, keep the identity check labelled as an identity check, and put the weight on
   the gap cases, which are what actually discriminate.

Both new guards mutation-tested: reverting to round 2's loop fails 2 tests; position-based
lookup in `.crd_flat` fails 7.

Final: 344 pass, 0 fail, 2 pre-existing skips. 0 lints. NAMESPACE unchanged at 25 exports.
Restore-the-bug from `main`: `.crd_flat` absent, 6 occurrences of the reported error,
16 failures; reinstated 94 pass.
