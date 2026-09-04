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
