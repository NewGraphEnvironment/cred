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

## The contract

One internal flattener, used everywhere a retrieval column is coerced:

| cell length | result | note |
|---|---|---|
| 1 | the value | the only shape observed |
| 0 | `NA` | |
| >1 | first element | **plus a warning** naming the column and how many rows |

Decided during planning rather than left to accident. The warning is the point: if ragnar's
shape changes we hear about it instead of scoring on an arbitrary element.

## Phase 1: Regression test that actually reaches the failure

- [ ] `tests/testthat/helper-store.R` — `local_ragnar_store()` building a real ragnar v2
      store in a temp dir with a deterministic offline `embed` function; origins shaped like
      Zotero attachment paths. Skips when `ragnar` or `duckdb` is absent.
- [ ] Assert the **premise** in the test: the frame `ragnar_retrieve()` returns has at least
      one list column. If a future ragnar stops producing them, the test fails naming the
      real cause instead of passing vacuously.
- [ ] Failing test: `crd_search()` on that store returns a tibble with atomic `score`,
      `chunk_id`, `origin`, `text` — currently the reported error.
- [ ] Unit tests for the flattener directly: length 0, 1, >1 (warning fired and first element
      taken), all-`NA`, and atomic input passed through unchanged.
- [ ] Confirm the tests fail against current `main` before the fix lands.

## Phase 2: The flattener and its call sites

- [ ] `.crd_flat()` in `R/store.R` implementing the contract above, with the rationale for
      the multi-element choice in its `@noRd` block.
- [ ] Wire into `.crd_retrieval_score()` — both branches.
- [ ] Wire into `crd_search()` — `chunk_id`, `start`, `end`, and also `origin` / `text`:
      `as.character()` on a list does not error, it deparses, so those are the silent half.
- [ ] `devtools::test()` green; the Phase 1 tests now pass.

## Phase 3: Verify, document, release

- [ ] **Restore the bug** (patch `.crd_flat` to a passthrough in both the namespace and the
      attached `package:cred` binding) and confirm the new tests go red. Print a value only
      the broken version produces, so the restoration is evidenced rather than assumed.
- [ ] `lintr::lint_package()` — 0 new lints against the `HEAD` baseline.
- [ ] `devtools::document()`; read what it writes — no unexpected `.Rd`, no export lost.
- [ ] Update `crd_search()`'s `@return` to state that `score` is flattened and what a
      multi-valued cell does.
- [ ] `NEWS.md` entry; bump `DESCRIPTION` to 0.3.1 as the **final** commit.
- [ ] `devtools::check()` clean.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
