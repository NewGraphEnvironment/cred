# Review — round 3 (#27)

Scope: what rounds 1–2's fixes broke or missed. Focus on the newest commit
(`881ab51`), which rewrote `.crd_flat()` and split `.crd_retrieval_score()`'s
long-form branch into a per-metric loop.

## `.crd_flat()` — checked, clean

The rewrite was scrutinised for the two failures it could plausibly have
introduced. Both were tested, neither is present:

- **Empty / `NULL` cells.** `split()` does drop the group (`names(groups)` is
  `"2" "3"` for `list(numeric(0), c(1,2), 3)`), but `groups[["1"]]` on a list
  returns `NULL` rather than erroring, so the cell falls through to
  `length(v) == 0L` and yields a typed `NA` on the right row. Verified for a
  leading, middle and trailing gap, and for `NULL` cells.
- **Two-digit indices.** `split()` groups by an *integer* factor, whose levels
  are `sort(unique(x))` — numeric, not lexical — so names come back
  `"1" … "12"` in order. No misalignment past ten cells.

Behaviour is equivalent to the previous per-cell implementation on every shape
tested, including mixed-type coercion and the single-warning contract.

## Findings

- **[bug]** `R/store.R:398-406` (`.crd_retrieval_score()`, long-form branch) —
  the new loop derives `score` **only for rows whose `metric` resolved**:

  ```r
  score <- rep(NA_real_, n)
  for (m in unique(metric[!is.na(metric)])) { ... }
  ```

  So when `metric_name` is absent — the shape the very next lines explicitly
  handle with `metric <- rep(NA_character_, n)` — the loop body never runs and
  **every score is `NA`**, discarding a `metric_value` column that is sitting
  right there. Same for any individual row whose `metric_name` cell is `NA`.

  Measured:

  ```
  data.frame(metric_value = c(1.2, 0.8))   # no metric_name
  main / ae17e24 -> score: 1.2  0.8
  HEAD           -> score: NA   NA
  ```

  This is a regression: `main` returned `as.numeric(res$metric_value)` and
  `ae17e24` returned `.crd_flat(res$metric_value, "numeric", "max")`. It is
  also precisely the failure `.crd_retrieval_score()`'s own roxygen says it
  exists to end ("silently produces an all-`NA` score"), reintroduced on a
  different shape by the fix for the first one.

  Reachability: not through ragnar 0.3.0 — `ragnar_retrieve_bm25_tbl()` and
  `ragnar_retrieve_vss_tbl()` both set `metric_name` as a SQL constant
  alongside `metric_value`, so the two always arrive together. So this is
  latent, not live. But the `else rep(NA_character_, n)` branch exists because
  someone decided that shape must be supported, and it now silently drops data
  instead. Fix: fall back to a single `.crd_flat(res$metric_value, "numeric",
  "max")` pass over the rows the loop did not claim, rather than leaving them
  `NA`.

- **[fragile — this is the mechanism]** `R/store.R:274-285, 407, 415` — the
  direction table is a single source of truth for **direction**, but not for
  **metric membership**, and the two branches consume it in structurally
  different ways. That asymmetry is what will keep producing this defect class.

  | branch | how it consumes `.crd_metric_dirs` | unknown metric |
  |---|---|---|
  | long-form | `.crd_metric_direction(m)` — table is a *lookup with a default* | scored, direction `"max"` |
  | pivoted | `.crd_metric_dirs[names(...) %in% names(res)]` — table is the *roster* | column ignored entirely; `score` and `metric` both `NA` |

  Measured on the same metric, same values:

  ```
  euclidean_distance, cells list(c(0.9, 0.2), 0.5)
  pivoted   -> score NA   NA        metric NA NA      (dropped)
  long-form -> score 0.9  0.5       (direction "max")
  ```

  Both answers are wrong, and they are wrong differently. `ragnar`'s
  `method_to_info()` supports `cosine_distance`, `euclidean_distance` and
  `negative_inner_product` — **all three are `ASC`, lower-is-better**. So the
  comment justifying the `"max"` default ("a new similarity metric is far more
  likely to be higher-is-better than a distance") is contradicted by the only
  upstream that supplies these names: every non-`bm25` metric ragnar offers is
  a distance.

  Not live today only because `crd_search()` has no `...` and never passes
  `method =` through to `ragnar_retrieve()`. The moment a `method` passthrough
  is added — the obvious next feature — the pivoted path silently returns an
  all-`NA` score column and the long-form path silently returns the worst
  constituent of every merged row.

  Fix shape: make the table the authority for membership as well as direction.
  Have the pivoted branch enumerate the metric columns actually present in
  `res` (everything not in the known non-metric set) and resolve each through
  `.crd_metric_direction()`, so a metric can only be handled one way; and set
  the unknown default from ragnar's roster (`"min"`), or warn rather than
  guess.

- **[fragile]** `tests/testthat/test-store-search.R` — the
  ">= ten cells" test's stated rationale is false, and it is the rationale a
  future reader will act on. The comment says `split()` names *"sort lexically
  — `\"10\"` before `\"2\"`"*; they do not, because the grouping vector is
  integer. Measured:

  ```r
  g <- split(1:12, rep(1:12, 1))
  identical(lapply(1:12, \(i) g[[i]]), lapply(1:12, \(i) g[[as.character(i)]]))
  #> TRUE
  ```

  So the first two assertions in that test (`as.list(1:12)`, and `multi`) pass
  identically for a positional `groups[[i]]` implementation and cannot
  discriminate. Only the third (`gap`, an empty cell at index 10) does — and it
  discriminates because of the *gap*, which the test directly above it already
  covers, not because of two-digit names. Matters because a reader trusting the
  comment could keep the two inert assertions and delete `gap` as the redundant
  one, leaving nothing.

## Not findings

- `.crd_flat()`'s name-based lookup, empty cells, `NULL` cells, and >= 10 cells:
  tested, correct (above).
- `res$metric_value[idx]` is correct for both a list column and an atomic one,
  and `score[idx] <- ` lands on the right rows — verified with a mixed-metric
  long-form frame (`c(5, 0.2, 7)` in, same out, per-metric directions applied).
- Full `filter = "store"` suite: `FAIL 0 | WARN 0 | SKIP 0 | PASS 203`.
