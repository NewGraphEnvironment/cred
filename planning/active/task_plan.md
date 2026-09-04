# Task: crd_search() errors on ragnar list columns: 'list' object cannot be coerced to type 'double' (#27)

`crd_search()` fails on any store retrieved with ragnar 0.3.0: the retrieval frame comes back
with **list columns**, and `.crd_retrieval_score()` coerces them with `as.numeric()`.

```
Error in withCallingHandlers(...) : 'list' object cannot be coerced to type 'double'
Calls: crd_search -> .crd_retrieval_score
```

There is no `metric_value` column under hybrid retrieval, so `.crd_retrieval_score()`
(`R/store.R:286`) falls past its first branch to the `cand` loop and reaches
`as.numeric(res[[m]])` on a list. `suppressWarnings()` cannot help — coercing a list is an
**error**, not a warning. `chunk_id` is a list column too, so `as.integer(res$chunk_id)` at
`R/store.R:389` throws the same way once execution reaches it.

The failure is misleading: the store pull succeeds and verifies, so each consumer
rediscovers it as an apparent store problem.

## The contract — corrected after measurement

The first version of this plan said list cells were always length 1 and proposed
"first element plus a warning". **That was an artifact of a six-document fixture.**
`ragnar_retrieve()` defaults to `deoverlap = TRUE` and merges adjacent retrieved chunks
into one row, so a cell holds one value per constituent chunk. On a realistic corpus 24%
of rows are multi-element (104 rows, 4 queries, 3 `top_k` values), and `as.numeric()` on
a list of length-1 scalars works fine — only the multi-element cell throws.

So a warning would fire on most real searches, and "first" is not merely arbitrary: on
~5% of rows the leading chunk's `bm25` is `NA` while a later one's is real, which
misattributes the metric. Reduce by the metric's own direction instead:

| column | reduction | why |
|---|---|---|
| `bm25` | `max(na.rm = TRUE)` | higher is better; the best constituent is what retrieved the passage |
| `cosine_distance` | `min(na.rm = TRUE)` | lower is better |
| `chunk_id`, `origin`, `text` | first | matches ragnar's own `start = first(start)` |
| empty cell / all-NA | typed `NA` | never `-Inf` from `max(numeric(0))`, never untyped `NA` |

No warning: this is ragnar's ordinary output, not an anomaly.

`.crd_flat(x, type, reduce)` — `type` always comes from the call site and is never
inferred from the data, so one character cell cannot promote a numeric column.

## Phase 1: Regression test that actually reaches the failure

- [x] `tests/testthat/helper-store.R` — `local_ragnar_store()` building a real ragnar v2
      store offline with a deterministic `embed`. Documents are long enough to chunk
      several times, which is what makes retrieval merge them; a six-document fixture of
      one-chunk documents passes against the bug. One cached store per file; the writer
      connection is closed before the reader opens, and the reader is deferred to
      `teardown_env()`.
- [x] Assert the **premise**: the retrieval frame has list score columns AND at least one
      cell of length > 1, and the untouched frame still raises the reported error. Length-1
      cells coerce fine, so "is a list column" alone is not the premise.
- [x] Failing test: `crd_search()` on that store returns atomic columns.
- [x] A merged row is scored by its best constituent, per metric direction — the assertion
      that separates this fix from a first-element one.
- [x] Unit tests for `.crd_flat`: typed NA for empty cells, NA constituents ignored,
      all-NA not becoming `-Inf`, atomic passthrough, missing column, zero-row frame.
- [x] Confirmed red against unfixed code with the reported error verbatim:
      `Error in crd_search(...): 'list' object cannot be coerced to type 'double'`
      (test-store-search.R:34 and :65). The `.crd_flat` "could not find function" errors
      are a vacuous red and prove nothing.

## Phase 2: The reducer and its call sites

- [x] `.crd_flat(x, type, reduce)` in `R/store.R`, with the rationale for direction-aware
      reduction in its `@noRd` block.
- [x] `.crd_retrieval_score()` — `metric_value`, `metric_name` (R/store.R:292, missed by
      the first enumeration) and the `cand` loop, now carrying a direction per metric.
- [x] `crd_search()` — `chunk_id`, `start`, `end`, `origin`, `text`. `origin` is genuine
      defence: `.crd_zot_key_from_path()` calls `dirname()`, which errors on a list.
      `text` at R/store.R:392 is also the only column read with no `%in% names(res)`
      guard — give it one.
- [x] `devtools::test()` green.

## Phase 3: Verify, document, release

- [x] **Restore the bug** with `git stash` / `git checkout HEAD -- R/store.R` — the source
      that had it, not a hand-written passthrough, which is a different program failing a
      different way. Proof is the original error string, not a pass/fail count.
- [x] `lintr::lint_package()` — no new lints against the `HEAD` baseline.
- [x] `devtools::document()`; read what it writes — no unexpected `.Rd`, no export lost.
- [x] Docs: `crd_search()`'s `@return` for the reduction and what `chunk_id` means on a
      merged row; `@param top_k` for the fact that hybrid retrieves per method and then
      merges, so the row count is neither `top_k` nor `2 * top_k`;
      `.crd_retrieval_score()`'s block for the list-column shape.
- [ ] `NEWS.md` entry; bump `DESCRIPTION` to 0.3.1 as the **final** commit.
- [ ] `devtools::check()` clean, with no leftover duckdb connections or undeletable temp
      files from the fixture.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
