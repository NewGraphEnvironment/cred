# crd_search() errors on ragnar list columns (#27)

## Outcome

`crd_search()` errored on every store built with ragnar 0.3.0 — and misleadingly, since the
store pull verified fine, so consumers met it as an apparent store problem.
`ragnar_retrieve()` defaults to `deoverlap = TRUE`, merging adjacent retrieved chunks into
one row and returning the per-chunk values as list columns; `as.numeric()` errors on a
multi-element cell. Fixed with `.crd_flat()`, which reduces such a column in the metric's
own direction — `max` for `bm25`, `min` for the distances — dropping the `NA`s that mark a
chunk a metric did not retrieve, so a merged passage is scored by the best chunk that
actually matched.

The durable lesson is about **fixtures, twice over**. The first regression test used six
one-sentence documents; each produced a single chunk, every cell was length 1, and
`as.numeric()` handles those perfectly well — so the test **passed against the unfixed
code**. The premise it rested on ("cells are always length 1") was a property of the
fixture, not of ragnar, and it had already been written into the plan and used to settle a
design decision with the user before anyone measured it on a realistic corpus.

The second lesson is that a fix can reintroduce the defect it replaced. Round 2's fix
grouped the score loop by metric; round 3 found that rows whose `metric_name` is absent
then never entered the loop and came back all-`NA` — the exact "silently produces an
all-NA score" failure `.crd_retrieval_score()`'s roxygen says it exists to end. Three
review rounds found 3, 4 and 3 issues; the third round was not redundant.

Also fixed, found by review rather than by the issue: `@return` promised rows "ordered
best-match first" and never delivered it. Rows come back in document order, and
neighbouring rows can carry different metrics whose scores are not comparable, so no single
ranking exists to return. Documented rather than sorted — interleaving two incomparable
scales needs a stated rule, and that is a behaviour change beyond this issue. Worth a
follow-up issue if ranking is wanted.

## Measurement

- **Merged rows are ordinary, not exceptional.** 24% of rows across 104 rows / 4 queries /
  3 `top_k` values. This is what killed the first proposed contract ("first element plus a
  warning"): it would have warned on roughly a quarter of every real search.
- **"First element" is wrong, not merely arbitrary.** On ~5% of rows the leading chunk's
  `bm25` is `NA` while a later one's is real, so first-element falls through to
  `cosine_distance` and reports the **wrong metric** for a row that has a BM25 score.
- **Every metric ragnar offers besides BM25 is a distance.**
  `ragnar:::method_to_info()` maps `cosine_distance`, `euclidean_distance` and
  `negative_inner_product` all to `"ASC"`. This reversed the default direction for an
  unrecognised metric from `"max"` to `"min"` — the intuitive guess was the wrong one, and
  a comment asserting it had already shipped into a commit.
- **The two branches gave two different wrong answers.** For one metric with one set of
  values: pivoted returned `NA, NA` (column dropped), long-form returned `0.9, 0.5` (wrong
  direction). The table was authoritative for direction but not membership; that asymmetry
  is the mechanism that kept the class recurring.
- **Restore-the-bug, from `main`:** `.crd_flat` absent from the namespace, 6 occurrences of
  `'list' object cannot be coerced to type 'double'`, 16 failures. Reinstated: 94 pass.
- **Guards mutation-tested rather than assumed:** reverting the score loop to round 2's
  version fails 2 tests; switching `.crd_flat`'s name-based group lookup to positional
  fails 7.
- **Fixture determinism:** identical across 3 independent rebuilds — 8 rows, max cell
  length 3, 5 multi-element rows. Multi-element cells appear from `top_k = 3` upward
  (3→1, 5→2, 6→4, 8→4, 10→5, 12→6, 20→8), so the chosen 10 has margin rather than sitting
  on a floor.
- **Final:** 344 pass, 0 fail, 2 pre-existing skips; 0 lints; NAMESPACE unchanged at 25
  exports. `devtools::check()` 3 warnings / 3 notes, all six confirmed pre-existing at
  `main`.

## Evidence

`planning/archive/2026-09-issue-27-ragnar-list-columns/review-round*.md` — the three
code-check rounds, each with the measurements behind its findings.

Closed by: PR for #27 (commits `cb74a73`, `ae17e24`, `79db8ae`, `881ab51`, `88c8d9d`)
