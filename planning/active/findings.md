# Findings — crd_search() errors on ragnar list columns (#27)

## Probe results (2026-09-04, ragnar 0.3.0, duckdb 1.5.2, R 4.5.x, macOS arm64)

The load-bearing finding: **the bug reproduces with no network, no Ollama, and no bucket
access.** A store created with a deterministic local `embed` function takes the identical
`ragnar_retrieve()` code path and returns the same list columns.

```
$ chunk_id       :List of 3   ..$ : int 1
$ cosine_distance:List of 3   ..$ : num 0.000495
$ bm25           :List of 3   ..$ : num 1.26 / NA
```

This settles the issue's open question about whether a regression test can use a real ragnar
path rather than a hand-built frame with atomic columns. It can, so the fixture cannot be the
kind that is structurally incapable of reaching the failure.

### Four facts the fix and its test depend on

- **BM25-only retrieval returns atomic columns** — long-form `metric_name` / `metric_value`,
  every column atomic. So a fixture built on `ragnar_retrieve_bm25()` **cannot** reach the
  failure. The test must go through `ragnar_retrieve()`.
- **The column set is variable.** A query BM25 matches nothing on returns a frame with no
  `bm25` column at all (8 columns, not 9). The existing `cand <- intersect(...)` handles this.
- **Every list cell observed is length 1.** ragnar fills a metric's misses with `NA` rather
  than dropping them, so a row found only by VSS carries `bm25 = NA`, still length 1.
- **`origin` round-trips only via `MarkdownDocument(text, origin = ...)`.** Assigning
  `chunk$origin <- ...` after `markdown_chunk()` is silently dropped — the column comes back
  all `NA`, which would leave `citation_key` resolution untested.

### Incidental

`ragnar_retrieve(top_k = 4)` on a 6-document store returned **6 rows**: `top_k` is per-method
and hybrid unions the two result sets. Out of scope here, but it means a caller asking for 5
passages can get up to 10.

## Design decision — multi-element cells

No probe produced a cell of length != 1. The issue asked for this to be decided deliberately
rather than by accident; user chose **first element plus a warning** over erroring or silently
taking the best score. Erroring would turn an unanticipated ragnar shape change into the same
class of hard breakage this issue exists to fix; taking the best score silently is the
accident the issue objected to.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `ragnar_store_insert()`: input compatible with store version 1, store is version 2 | Wrap text in `markdown_chunk()` before insert |
| Fixture `origin` came back all `NA` | Set it via `MarkdownDocument(text, origin = )`, not by assigning a column on the chunks object |

## Issue context

## Problem

`crd_search()` fails on any store retrieved with ragnar 0.3.0: the retrieval frame comes back
with **list columns**, and `.crd_retrieval_score()` coerces them with `as.numeric()`.

```
Error in withCallingHandlers(...) : 'list' object cannot be coerced to type 'double'
Calls: crd_search -> .crd_retrieval_score
```

## Repro

Three lines against any store in the bucket (here `peace`, 117 docs):

```r
s   <- cred::crd_store_connect("peace", dir = "data/rag", verify = FALSE)
res <- ragnar::ragnar_retrieve(s, "fish passage culvert barrier", top_k = 3)
vapply(res, function(x) class(x)[1], "")
#>          origin          doc_id        chunk_id           start             end
#>     "character"       "integer"          "list"       "integer"       "integer"
#> cosine_distance            bm25         context            text
#>          "list"          "list"     "character"     "character"
```

## Cause

There is **no `metric_value` column**, so `.crd_retrieval_score()` (`R/store.R:286`) falls past
its first branch to the `cand` loop and reaches:

```r
v <- suppressWarnings(as.numeric(res[[m]]))   # R/store.R:303 -- res[[m]] is a list
```

`suppressWarnings()` does not help: coercing a list is an **error**, not a warning. So the
guard reads as defensive but cannot catch this.

`chunk_id` is a list column too, so `as.integer(res$chunk_id)` at `R/store.R:389` would throw
the same way if execution reached it.

## What changes if we fix it, and what happens if we never do

**If we fix it:** `crd_search()` works again, and with it every documented "query the store"
step in the repos that depend on cred. **If we never do:** those steps stay broken while the
stores themselves are fine, so each consumer rediscovers it as an apparent store problem — the
misleading part is that the pull succeeds and only the search fails.

## Proposed Solution

Flatten before coercion, in both places, rather than widening the `suppressWarnings()`:

- `R/store.R:290,303` — reduce each candidate column to an atomic numeric (e.g. via
  `vapply(x, function(e) as.numeric(e)[1], numeric(1))`, or `unlist()` where a scalar per row is
  guaranteed) before `as.numeric()`.
- `R/store.R:389` — same for `chunk_id` before `as.integer()`.

Worth deciding deliberately what a multi-element cell should mean rather than silently taking
the first, since that choice is currently made by accident.

A regression test wants a fixture that actually reaches the failure — a store retrieved through
the real ragnar path, not a hand-built frame with atomic columns, which is what would let this
recur.

## Versions

cred 0.3.0, ragnar 0.3.0, R 4.5.2, macOS arm64. Found while validating the fieldwork-prep
pipeline on a second machine.

Relates to NewGraphEnvironment/knowledge#4

