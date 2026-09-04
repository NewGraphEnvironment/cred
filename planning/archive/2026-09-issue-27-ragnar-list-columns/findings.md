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

### CORRECTION — the "every cell is length 1" finding was a fixture artifact

The first probe used six one-sentence documents. Each produced a single chunk, so every
overlap group was one row and every cell was length 1. That is a property of the fixture,
not of ragnar, and it is the CLAUDE.md "fixture that cannot reach the failure mode"
pattern applied to the exact branch the contract was being written for.

`ragnar_retrieve()` defaults to `deoverlap = TRUE` and delegates to
`ragnar:::chunks_deoverlap()`, which summarises by `(origin, doc_id, overlap_grp)` with
`start = first(start)`, `end = last(end)`, and `across(-c(start, end, context, text),
\(x) list(unlist(x)))`. That `across()` is the list-column factory, and **a cell's length
is the number of retrieved chunks merged into that row.**

`markdown_chunk()` defaults `target_overlap = 0.5` and `crd_store_build()` (R/store.R:568)
ingests through it, so adjacent chunks merge routinely on a production store.

Re-measured on a 30-document corpus of multi-chunk documents, 4 queries x 3 `top_k`:

```
rows total      : 104
multi-chunk rows: 25  (24%)
rows where first-element picks the WRONG metric: 5
```

The error itself needs a multi-element cell. Measured:

```
as.numeric(list(1, 2, 3))          -> 1, 2, 3        # length-1 cells are FINE
as.numeric(list(1, numeric(0), 3)) -> 1, NA, 3
as.numeric(list(1, NULL, 3))       -> ERROR: 'list' object cannot be coerced to type 'double'
as.numeric(list(c(1, 2), 3))       -> ERROR: 'list' object cannot be coerced to type 'double'
```

A merged row, in full:

```
origin  : /tmp/storage/K25/doc.pdf     start: 1   end: 2402
chunk_id: 97,98
cosine  : 2.324581e-06, 3.099442e-06
bm25    : 0.01430294,   NA
```

So `first` is not merely arbitrary — where the leading chunk's `bm25` is `NA` and a later
one's is real, it drops to `cosine_distance` and reports the wrong metric for a row that
does have a bm25 score.

### Facts that survived the correction


- **BM25-only retrieval returns atomic columns** — long-form `metric_name` / `metric_value`,
  every column atomic. So a fixture built on `ragnar_retrieve_bm25()` **cannot** reach the
  failure. The test must go through `ragnar_retrieve()`.
- **The column set is variable.** A query BM25 matches nothing on returns a frame with no
  `bm25` column at all (8 columns, not 9). The existing `cand <- intersect(...)` handles this.
- **ragnar fills a metric's misses with `NA`** rather than dropping them, so a merged row
  commonly reads `c(NA, 1.26)` — which is exactly why the reduction must ignore NAs.
- **`origin` round-trips only via `MarkdownDocument(text, origin = ...)`.** Assigning
  `chunk$origin <- ...` after `markdown_chunk()` is silently dropped — the column comes back
  all `NA`, which would leave `citation_key` resolution untested.

### Incidental

`ragnar_retrieve(top_k = 4)` on a 6-document store returned **6 rows**: `top_k` is per-method
and hybrid unions the two result sets. Out of scope here, but it means a caller asking for 5
passages can get up to 10.

## Design decision — how a merged row reduces

Decided **after** the correction above, with the numbers in hand: reduce by the metric's
own direction — `max(na.rm = TRUE)` for `bm25`, `min(na.rm = TRUE)` for `cosine_distance`
— and take the first `chunk_id`, matching ragnar's own `start = first(start)`. No warning:
24% of rows are merged, so warning would be noise on most searches rather than signal.

The earlier choice ("first element plus a warning") was made on the disproved premise and
is recorded here because the retraction is the useful part: the fixture agreed with the
contract because both were too small.

## Review findings folded in (Plan agent, 2026-09-04)

Reached B1 independently from ragnar's source, which corroborates the measurement above.
Also caught, and acted on:

- Writer duckdb connection never disconnected before opening the reader; both leaked.
  Fixed with the `DBI::dbDisconnect(store@con, shutdown = TRUE)` pattern already at
  R/store.R:563.
- `as.character(res$metric_name)` (R/store.R:292) missing from the call-site enumeration.
- `text` (R/store.R:392) is the only tibble column read with no `%in% names(res)` guard.
- `.crd_zot_key_from_path()` calls `dirname()`, which **errors** on a list — so flattening
  `origin` fixes a second latent throw rather than being pure defence.
- `expect_match(w, "2")` on a warning was satisfiable by the column name `"bm25"` alone.
  Moot once the warning was dropped, but the assertion was vacuous as written.
- Fixture attachment keys were `TOYKEY%d` — 7 characters, failing
  `.crd_zot_key_from_path()`'s `^[A-Z0-9]{8}$`. Now `TOYKEY%02d`, and the helper no longer
  claims to cover Zotero resolution (there is no `zotero.sqlite` under `tempdir()`).
- `.crd_test_embed` used `adist(ch, "a")`, which returns 0 for `"a"` and 1 for everything
  else — not the character binning its comment described. Verified and replaced with
  `utf8ToInt`.
- ragnar sets `environment(embed) <- baseenv()` before serialising, so the embed function
  must reference nothing outside base. Noted in the helper.
- Restore-the-bug must be `git checkout HEAD -- R/store.R`, not a hand-written passthrough.

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

