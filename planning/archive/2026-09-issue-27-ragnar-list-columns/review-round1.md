# Code check — round 1

**Scope:** staged diff on `27-crd-search-errors-on-ragnar-list-columns` — two new files,
`tests/testthat/helper-store.R` and `tests/testthat/test-store-search.R`.

**Note on tree state:** the brief said `.crd_flat()` lands in the next commit. It is already
in the working tree (unstaged, `R/store.R:309`, with a 4th argument `n`). That let me run the
tests green *and* restore the bug properly, which is stronger evidence than the brief expected.

---

## Verified good (measured, not read)

Everything below was measured against ragnar 0.3.0 / duckdb 1.5.2 on this machine, not inferred.

| Question | Answer |
|---|---|
| Does the fixture reach the failure? | **Yes.** `ragnar_retrieve(top_k = 10)` → 8 rows, `bm25` cell lengths `3 2 1 3 1 1 3 2`, no `metric_value`, and `as.numeric(res$bm25)` raises `'list' object cannot be coerced to type 'double'` verbatim. |
| Restore-the-bug (HEAD's real bytes via `git show HEAD:R/store.R`) | **Genuine red.** Tests 2 and 3 ERROR; the premise test (4 assertions) and the bm25 control (4) correctly stay green. Proof the broken code was live: `exists(".crd_flat", asNamespace("cred")) == FALSE` printed before the run. |
| Does test 3 distinguish `max` from `first` on bm25? | **Yes.** Simulated a first-element reducer against test 3's assertions → FAILS on row 1 (score `0.03465` vs `0.03498`) and row 7 (metric mismatch: `b[1]` is `NA`, so `first` picks `cosine_distance`). Not vacuous. |
| `withr::defer(envir = testthat::teardown_env())` | **Works.** Full `test_dir` run: 316 pass / 0 fail / 0 error / 2 skip; **0** leftover `*.duckdb` in `tempdir()`, **0** open duckdb connections after. |
| Cached store valid across `test_that` blocks? | Yes — all four integration blocks share one connection successfully. |
| Re-running in one session (stale closed connection)? | Safe. Two consecutive `test_file()` calls in one session: 66 pass both times. testthat re-sources the helper, so `.crd_store_cache` is a fresh env per run. |
| Writer disconnect → read-only reconnect with duckdb | **Safe.** `DBI::dbDisconnect(store@con, shutdown = TRUE)` leaves no `.wal`; `ragnar_store_connect(read_only = TRUE)` reconnects and hybrid retrieval works. |
| `expect_gt(max(lengths(res$bm25)), 1L)` flaky? | **Not flaky, and with margin** — see finding 3 for the margin, which is larger than the comment claims. Deterministic across repeat calls (`nrow` and `lengths` identical). |
| `.crd_test_embed` outside base R? | **Clean.** Only `numeric`, `utf8ToInt`, `tolower`, `as.character`, `sqrt`, `sum`, `vapply`, `t`; `dim_n` is a local. Survives `environment(embed) <- baseenv()` — verified by the read-only reconnect actually embedding the query. |
| lintr on both new files | 0 lints (repo `.lintr` config). |
| `withr`, `DBI`, `ragnar`, `duckdb` in Suggests | Yes, all four. |

---

## Findings

### 1. **[fragile]** `test-store-search.R:41-42` (and :46 in part) — assertions that cannot fail

```r
expect_type(out$start, "integer")
expect_type(out$end,   "integer")
```

`ragnar:::chunks_deoverlap()` list-ifies with `across(-c(start, end, context, text), \(x) list(unlist(x)))`
— `start`, `end`, `context` and `text` are **excluded by construction**, and `origin` is a
grouping key. Measured on the fixture: `start` and `end` come back `int`, `origin` and `text`
come back `chr`, in every retrieval at every `top_k` I tried.

So those columns are already atomic before `crd_search()` sees them. These two assertions pass
identically whether the unstaged Phase-2 `.crd_flat()` call sites for `start`/`end`/`origin`/`text`
(`R/store.R:470,479,480,481`) exist or are reverted to bare `as.integer()`/`as.character()`.
`expect_false(any(vapply(out, is.list, ...)))` at :46 is real coverage for `score`/`metric`/`chunk_id`
and decoration for these four.

Why it matters here rather than being nitpicking: the file header asserts *"the integration tests
construct nothing by hand"* as the reason they are trustworthy, and Phase 2 adds four `.crd_flat()`
call sites the net does not hold. Four of the nine columns are defended by an assertion that is
structurally incapable of going red.

Cheapest honest fix is **not** more tests — it is one comment saying those four columns cannot be
list columns and the `.crd_flat()` calls on them are deliberate defence, so a later reader does not
mistake a green suite for evidence about them.

### 2. **[fragile]** `test-store-search.R:78-80` — the `cosine_distance` direction is never exercised

The test's own docstring is *"per metric direction — higher is better for bm25, lower is better
for cosine_distance"*. The bm25 half discriminates (finding above). The cosine half does not.

Measured, counting multi-element rows that reach the `else if` branch and asking whether
`first(cosine) != min(cosine)`:

```
top_k=3   multi=1  cosine-branch rows=0   first!=min: 0
top_k=5   multi=2  cosine-branch rows=1   first!=min: 0
top_k=6   multi=4  cosine-branch rows=2   first!=min: 0
top_k=10  multi=5  cosine-branch rows=1   first!=min: 0     <- the value the tests use
top_k=12  multi=6  cosine-branch rows=0   first!=min: 0
top_k=20  multi=8  cosine-branch rows=1   first!=min: 0
```

**Zero at every `top_k`.** A `min` → `first` regression on `cosine_distance` passes the integration
test at any setting. The only guard on that direction is the hand-built unit test at :175
(`.crd_retrieval_score prefers the lowest distance within a merged row`) — which is precisely the
shape `findings.md` says *"is what would let this recur"*.

This is the "guard's scope is a coincidence" pattern: reachability of that branch depends on
retrieval happening to return a row's constituents in ascending-distance order, which is not a
property anyone chose. Not necessarily fixable by tuning the fixture — but the comment at :58-62
currently claims coverage the integration test does not have, and the unit test at :175 should be
labelled as the *only* guard for that direction rather than as a supplementary edge case.

### 3. **[fragile]** `helper-store.R:113-115` — two false claims in the comment that justifies `top_k`

```r
# top_k for the regression tests. Chosen because it is the smallest value at
# which this fixture produces a merged, multi-element cell — the shape the bug
# needs. `.crd_test_multi_row()` asserts that rather than trusting it.
.crd_test_top_k <- function() 10L
```

Both sentences are wrong:

- **`10L` is not the smallest.** Measured: `top_k = 3` already yields a multi-element cell
  (max length 2, 1 multi row); 5→2 rows, 6→4, 8→4, 10→5, 12→6, 20→8. The comment states zero
  margin where the real usable range is 3..≥20 with 5 multi rows at the chosen value. That
  understatement is the harmful direction: someone meeting a future red premise test will read
  "10 is the floor" and raise `top_k` to paper over an upstream change, which is exactly what the
  premise test exists to surface.
- **`.crd_test_multi_row()` does not exist** anywhere in the repo (`grep -rn` → this comment line
  only). The assertion it refers to is `expect_gt(max(lengths(res$bm25)), 1L)` at
  `test-store-search.R:23`.

---

## Considered and dismissed

- **`expect_gt(max(lengths(res$bm25)), 1L)` when `bm25` is absent** — `lengths(NULL)` is
  `integer(0)`, `max()` gives `-Inf` with a warning, and the assertion **fails**. Same for
  `which(lengths(res$bm25) > 1L)` at :69 → premise at :70 fails. Fails loud, safe direction.
- **`.crd_flat`'s `n =` argument is untested** — it only fires when a retrieval frame lacks
  `chunk_id`/`start`/`end`/`origin`/`text`, and both `ragnar_retrieve()` and
  `ragnar_retrieve_bm25()` always return all five. Unreachable defensive code; testing it would be
  gold-plating.
- **Writer connection leaks if `ragnar_store_insert()` or `build_index()` throws** — the
  `dbDisconnect` is not in an `on.exit`. Test-only, and the whole run aborts anyway.
- **Rows where both `bm25` and `cosine_distance` are all-NA get no score assertion** in test 3's
  loop — not reachable on this fixture, and `chunk_id` is still asserted.
- **`skip_if_not_installed("ragnar")` carries no version floor**, while `DESCRIPTION` has
  `Remotes: tidyverse/ragnar` (an unpinned branch) and the fixture uses v2-only API
  (`MarkdownDocument`, `markdown_chunk`, `version = 2`) — `findings.md` already records a
  version-mismatch error hit during development. An older ragnar would **error** all four tests
  rather than skip. Real but low-probability; `skip_if_not_installed("ragnar", "0.3.0")` closes it
  if you want it closed. Not counted as a finding.

---

## Verdict

No bugs, no security issues. The regression net is real where it matters most — the fixture
genuinely reaches the reported failure, the restore-the-bug check goes red on HEAD's actual bytes,
and the bm25 `max`-vs-`first` distinction is provably discriminating. The three findings are all
about **coverage the file claims but does not have** (`start`/`end`, the `cosine_distance`
direction) or **comments stating measurements that are false** (`top_k`, a helper that does not
exist). All three are comment/labelling fixes, not code changes.
