# Review round 2 — `27-crd-search-errors-on-ragnar-list-columns`

Scope: `R/store.R` (`.crd_flat`, `.crd_retrieval_score`, `crd_search`),
`tests/testthat/helper-store.R`, `tests/testthat/test-store-search.R`.

**Note on what was reviewed.** The supplied `round2.diff` went stale during the review —
the round-1 fixes to `helper-store.R` and `test-store-search.R` (version floor on
`skip_if_not_installed`, the removed `.crd_test_multi_row()` phantom, the top_k
measurement table, the non-discriminating-branch notes) landed in the working tree while
this was in progress. Everything below is verified against the **current working tree**,
not against the diff file. `lintr::lint()` is 0 on all three files;
`testthat::test_file("tests/testthat/test-store-search.R")` is 66 passing, 0 failures.

---

## Findings

### 1. [bug] R/store.R:411 — `@return` promises an ordering the default path does not deliver

```r
#' @return A [tibble][tibble::tibble] ordered best-match first, with columns:
```

`ragnar_retrieve()` does not re-sort after `chunks_deoverlap()`. Read from ragnar 0.3.0:

```r
# chunks_deoverlap()
arrange(..., origin, doc_id, start)          # <- the last ordering applied
summarize(.by = c(origin, doc_id, overlap_grp), ...)
# ragnar_retrieve() returns `chunks` unchanged after this
```

Measured on the fixture store, `top_k = 10L`, `method = "hybrid"` (the default):

| row | chunk_id | score  | metric          |
|-----|----------|--------|-----------------|
| 1   | 2        | 0.0350 | bm25            |
| 2   | 5        | 0.0347 | bm25            |
| 3   | 12       | 0.0347 | bm25            |
| 4   | 18       | 0.0763 | cosine_distance |
| 5   | 29       | 0.0757 | cosine_distance |
| 6   | 34       | 0.0350 | bm25            |
| 7   | 42       | 0.0345 | bm25            |
| 8   | 46       | 0.0346 | bm25            |

Rows come back in document order (`origin`, `doc_id`, `start`), and `crd_search()` builds
the tibble in `res` order without sorting. The score column is not monotone in either
direction, and — since consecutive rows carry *different metrics* — it could not be sorted
into a meaningful "best first" order even if someone tried.

Why it matters: this is the documented contract of an exported function. A caller doing
`crd_search(...)[1, ]` or `head(out, 3)` to get "the best passages" gets an arbitrary
document-order slice. That is a silent wrong answer, not an error.

The line itself is unchanged from `main`, so the defect predates the branch — but the
branch rewrote the bullets immediately beneath it to describe deoverlap semantics
(merged passages, best-of-constituents scores, `top_k` meaning), which is exactly the
change that makes this line false. Leaving it is the "documentation staleness" class:
the code learned something and the docs did not.

Two fixes, either acceptable:
- state the truth — hybrid results are returned in document order, and `score` is
  comparable only within `metric`; or
- keep the promise by sorting within-metric before returning, which needs a stated rule
  for interleaving two incomparable scales.

---

### 2. [fragile] R/store.R:361 — the `metric_value` branch hardcodes `reduce = "max"` for a metric that may be a distance

```r
if ("metric_value" %in% names(res)) {
  return(list(
    score  = .crd_flat(res$metric_value, "numeric", "max"),   # <- direction is fixed
    metric = ... .crd_flat(res$metric_name, "character", "first") ...
```

Eleven lines below, the wide branch gets this exactly right and says why:

```r
directions <- c(bm25 = "max", cosine_distance = "min")
```

In the long-form branch the metric is *known* — it is sitting in `res$metric_name` — and
for `method = "vss"` it is `cosine_distance`, where **lower is better**. `"max"` there
selects the worst constituent, not the best.

Reachability today is nil, and I verified rather than assumed it:

```
ragnar_retrieve_bm25(store, text, top_k = 3L, ..., k, b, conjunctive, filter)
ragnar_retrieve_vss (store, query, top_k = 3L, ..., method, query_vector, filter)
```

Neither takes `deoverlap`, so `metric_value` arrives atomic and `.crd_flat()` returns at
`if (!is.list(x)) return(coerce(x))` before `reduce` is ever consulted. Confirmed
empirically: `ragnar_retrieve_vss()` returns `metric_name = "cosine_distance"` and a
plain `numeric` `metric_value`.

So this is dead today and wrong the day it stops being dead — and the failure mode is the
silent one (worst-match score, right type, no error). Since `metric_name` is already read
two lines down, deriving the direction from it costs nothing; `"first"` would also be
honest, since the argument is unreachable.

---

### 3. [fragile] R/store.R:324 vs :327 — `suppressWarnings()` on one branch only, and the test that claims otherwise cannot fail

The two branches disagree about warnings:

```r
if (!is.list(x)) return(coerce(x))                              # NOT suppressed
...
v <- suppressWarnings(coerce(unlist(cell, use.names = FALSE)))  # suppressed
```

Measured:

```r
.crd_flat(c("a", "b"), "numeric")
#> Warning: NAs introduced by coercion
#> [1] NA NA

.crd_flat(list("a", "b"), "numeric")
#> [1] NA NA          # silent
```

The test asserting the property is titled `".crd_flat passes atomic input through
unchanged and never warns"`, and every input it feeds is structurally incapable of
warning:

```r
expect_silent(got <- .crd_flat(c(1.5, 2.5), "numeric", "max"))  # numeric -> numeric
expect_identical(.crd_flat(c(1L, 2L), "integer"), c(1L, 2L))    # integer -> integer
expect_identical(.crd_flat(c("a", NA), "character"), c("a", NA))# character -> character
expect_silent(.crd_flat(list(c(1, 2), c(3, 4)), "numeric", "max"))
```

`as.numeric()` on doubles never warns, so `expect_silent()` there passes for every
possible implementation of `.crd_flat()` — including one with the `suppressWarnings()`
deleted. The "never warns" half of that test name is asserted where it cannot fail and is
false where it can. This is the premise-satisfied-by-structure shape in `code-check.md`:
the assertion is correct and the input cannot reach it.

The other half is worth naming separately, because it points the opposite way. On the
list branch, the *only* thing `suppressWarnings()` can silence is
`NAs introduced by coercion` — ragnar's genuine `NA` cells are already `NA_real_` and
coerce cleanly, which I confirmed. So it exists solely to swallow the signal that a score
column holds non-numeric data, and swallowing it produces an all-`NA` `score` column:
the precise silent failure the roxygen block above credits the *old* code with
(*"silently produces an all-`NA` score on the default code path"*).

Not reachable through `crd_search()` as it stands — I walked every column: `origin`
(chr→chr), `chunk_id` (list of int), `start`/`end` (int→int), `text` (chr→chr),
`metric_value` (num→num), `metric_name` (chr→chr). None can warn. So this is a contract
defect, not a live bug. Make the branches agree, and let the test feed an input that can
actually warn if the claim is going to stay in the test name.

---

### 4. [fragile] test-store-search.R:63-67 — two independent retrievals assumed row-aligned, with only `nrow` asserted

```r
res <- ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = .crd_test_top_k())
out <- crd_search(store, .crd_test_query(), top_k = .crd_test_top_k())

expect_identical(nrow(out), nrow(res))
...
for (i in multi) { ... expect_equal(out$score[i], max(b, na.rm = TRUE)) ... }
```

Every assertion in the loop indexes both frames by the same `i`, but the two frames come
from two separate round-trips to duckdb. Equal row *counts* is the only thing checked;
equal row *order* is assumed. Ties in the FTS/VSS ordering, or a future ragnar that sorts
the deoverlapped output (see finding 1), break the correspondence.

It most likely fails loudly rather than passing wrongly, so this is low severity. The
guard is one line and pins the actual invariant the loop needs:

```r
expect_identical(out$text, res$text)   # same rows, same order
```

---

## Checked and found sound

Recording these because several were the review's stated focus and a "no finding" is only
worth anything if the check could have produced one.

- **`.crd_flat` branch sweep.** All-NA cells → typed `NA`, not `-Inf` (`max(numeric(0))`
  is never reached; the `length(v) == 0L` guard fires first). Empty list → `integer(0)`.
  Nested list cell → `unlist()` recurses correctly: `.crd_flat(list(list(1, 2), 3),
  "numeric", "max")` is `c(2, 3)`. `unlist(vals)` on an all-`na` result keeps the type
  because each `na` is typed.
- **`n =` padding.** Only consulted when `x` is `NULL`; a present-but-zero-length column
  ignores it (`.crd_flat(list(), "numeric", n = 3)` → `numeric(0)`). Unreachable:
  `crd_search()` early-returns on `nrow(res) == 0L`, and a data.frame column is always
  `nrow` long. Not a finding, but it is a gap between the `@param n` prose and the code.
- **Metric preference order.** `directions[names(directions) %in% names(res)]` is logical
  subsetting, which preserves the declaration order, so `bm25` is always visited first
  and `take <- is.na(score) & !is.na(v)` gives it the win. Verified on the fixture: the 5
  merged rows split 4 bm25 / 1 cosine_distance, and one row (`bm25 = [NA, NA, 0.0345]`)
  has a leading `NA` with a later real score — the exact case where `"first"` would have
  misattributed the row to `cosine_distance`. The fixture does reach the bug.
- **`end` with `"max"`.** `chunks_deoverlap()` sets `end = last(end)` and excludes `end`
  from the `across(..., list(unlist(x)))` list-ification, so it arrives atomic
  (`typeof(res$end)` is `"integer"`) and `reduce` is a no-op. Correct in both the actual
  and the hypothetical case.
- **`expect_gt(max(lengths(res$bm25)), 1L)`.** Deterministic under `withr::with_seed(1L)`
  given fixed ragnar/duckdb; measured `lengths(res$bm25) = 3,2,1,3,1,1,3,2`. Version
  sensitivity is real but the round-1 comment now says so, and it fails loudly at the
  premise rather than letting the behaviour tests pass for the wrong reason.
- **Fixture resource handling.** `testthat::teardown_env()` is documented and implemented
  as *after all test files*, not per file, so the run-scoped `.crd_store_cache` and the
  run-scoped teardown agree — no stale connection is handed to a second test file. The
  writer is disconnected with `shutdown = TRUE` before the read-only reader opens.
  (The `# One store per test file.` comment at helper-store.R:48 is imprecise — it is one
  store per *run* — but the code is right.)
- **`.crd_test_embed` base-R purity.** `numeric`, `vapply`, `utf8ToInt`, `tolower`,
  `as.character`, `t`, `sqrt`, `sum` — all base. Survives
  `environment(embed) <- baseenv()`. The `+ 1e-6` floor also means an empty chunk cannot
  produce `NaN` from a zero-norm divide.
- **`type = "integer"` truncation and factor/Date cells.** `as.integer(3.9)` → `3` and
  `as.numeric(factor("7"))` → `1` (level code) are both live traps in `.crd_flat`, but
  neither is reachable: `chunk_id`/`start`/`end` come back as `integer` from duckdb, and
  no retrieval column is a factor. Noting them only so a future call site adding a
  double-valued or factor column knows the coercion is unguarded.

---

## Verdict

No blocker. Finding 1 is a real user-facing wrong answer and should land with this
branch, since this branch is what makes the sentence false. Findings 2-4 are latent.
