# Findings — crd_store_build(): an oversize chunk aborts the build; a NUL byte skips a paper (#35)

## Issue context

**If done:** `crd_store_build()` builds a store from a collection that holds a long book or a PDF whose text carries a NUL byte, embedding what it can and naming what it could not. **If never:** one oversize chunk aborts the whole build and leaves no store, so a collection with a textbook in it cannot be searched at all.

## Problem

Building a four-paper collection (cred 0.3.0, ragnar 0.3.0, Ollama `nomic-embed-text`):

```r
cred::crd_store_build("data/rag/model_selection.duckdb", collection = "model_selection")
```

1. **A long book aborts the build.** *The Elements of Statistical Learning* (2nd ed., 764 pages) yields a chunk longer than the embedding model's context, and Ollama answers `HTTP 400 Bad Request. the input length exceeds the context length`. `ragnar_store_ingest()` stops and no store file is written, so the two papers already ingested are lost too.
2. **A NUL byte skips a paper.** The arXiv PDF of Bates, Hastie & Tibshirani, "Cross-validation: what does it estimate and how well does it do it?" (2104.00673v4) fails in ragnar's `prepare()` with `Embedded NUL in string`. It is skipped with only a warning.

`crd_store_build()` calls `ragnar_store_ingest(store, src$src_path)` with ragnar's default chunking and no cap on chunk length (`deparse(cred::crd_store_build)`).

## Proposed

- Cap each chunk below the embedding model's context (chunk the markdown to a token budget, or split any chunk over it) so no single page can abort a build.
- Ingest document by document: a document that fails to read or embed is skipped, the build finishes, and the summary names each skipped document and why.
- Strip NUL bytes from extracted text before chunking.

## Context

Found while checking the statistics citations of a package article: the citations were verified against the PDFs' text directly, but the shared store for the collection could not be built.


## Plan-time measurements (2026-10-31)

Summarised in `task_plan.md`. Probes ran against the PDFs named in the issue, a local
Ollama 0.24.0 and ragnar 0.3.0; scripts were throwaway and are not committed.

- ESL: 1,923,671 markdown characters, 2,404 chunks (default `markdown_chunk()`, target 1,600).
  Chunk text median 1,600 / p99 1,933 / max 2,072 characters; heading context at most 13.
- Token counts per chunk (Ollama `prompt_eval_count`, one input per call): median 434,
  p99 1,510, max 2,039. Two chunks (indices 2274, 2275) return 400; both start
  `# Values Type\\n••••…` at 1,887 and 1,706 characters.
- `•` = 2 tokens per character: 1,000 → 2,002 tokens OK; 1,800 → 400.
- Prose (`"salmon "` repeated) at 16,000 and 20,000 characters → 2,048 tokens, OK (truncated).
  `中` x3000 → 2,048, OK. `truncate: false` on 20,000 prose characters → the same 400.
- Bates et al. (arXiv 2104.00673v4): `read_as_markdown()` → `Embedded NUL in string` via
  reticulate; with `options(ragnar.markitdown.use_reticulate = FALSE)` the CLI route fails too
  (`embedded nul in string`). `pdftools::pdf_text()` → 43 pages, 204,561 characters.
- Upstream: ollama/ollama#14186 (open, 2026-02-10): truncate ignored since 0.13.5. On 0.24.0
  truncation works for prose, so the `•` case is a narrower residue of it.

## Implementation facts (2026-10-31)

- **ragnar re-raises a worker's error with `warning(cond)` but keeps its error class**, so it
  reaches `error =` calling handlers and never `warning =` ones; `muffleWarning` is still the
  restart available (measured with a `simpleError` passed to `warning()`). A skip is therefore
  its own class, `cred_ingest_skip`, and mirai carries the class back from the worker (the e2e
  test asserts no warning escapes).
- `store@embed` from `ragnar_store_create()` deparses to
  `function (x) ragnar::embed_ollama(x = x, model = "nomic-embed-text")` with environment
  `base`, so `prepare` can close over it and be serialised to workers.
- `ragnar::embed_ollama()`'s 400 is classed
  `httr2_http_400 / httr2_http / httr2_error / rlang_error / error / condition`; connection
  refused is `httr2_failure`.
- An ingest whose every document is skipped returns cleanly (the index builds on an empty
  store), so `crd_store_build()`'s zero-ingested stop is what deletes the store.
- Refused chunks are searched for within batches of ten (embed_ollama's batch size), so a
  2,404-chunk book with two refused chunks re-embeds a few batches, not the book.

## Mutation table

Each defect restored in a scratch copy; `test-store-build.R` run under `load_all()`.

| Defect restored | Tests red |
|---|---|
| refused chunk not split (`stop(emb)`) | 3 (split, drop, e2e split) |
| no pdftools fallback | 1 (fallback) |
| `prepare` parented on the cred namespace | 1 (self-contained) |
| `prepare` calls a cred helper | 8 (every test that runs `prepare`) |
| skip not muffled | 1 (e2e unreadable) |
| every embed error treated as a 400 | 2 (unembedded, e2e service down) |
| floor of 0 instead of `min_chars` | 1 (drop) |
| `crd_store_build()` returns every attempted file | 1 (report) |
| `complete <- TRUE` before the zero-ingested stop | 1 (no store left) |

## Plan review disposition

Review in `review-plan.md`. Each claim was probed before it was acted on.

| Finding | Verdict | Action |
|---|---|---|
| B1 duplicate ranges | **Reproduced**: prose + 4,000 `•`, limit 700 → 48 rows, 2 repeated ranges; `ragnar_store_update()` fails with `duplicate key "1, 4801, 5200"`. The live ESL build happened to miss it. | Keep a range once; test via an in-memory store |
| B2 handler class | True of the plan text; the code was already right (measured earlier) | Plan text corrected |
| G1 batch bisection | True of the plan text | Phase 2b and the roxygen |
| G2 worker retries off | Confirmed: `embed_req_retry()` reads `ragnar.embed.req_retry`, which ragnar sets to `FALSE` in workers | `prepare` sets the main-process policy locally |
| G3 any 400 splits | Real cost risk | Split only on 400 + "context length" (class first, message only within the class) |
| G4 stale notes | Real | Notes held, written in one `cat()` on the outcome |
| G5 worker crash | Already covered by `unsaid` | None |
| G7 counts / first key | Real | Note once per chunk; `who()` joins keys |
| A2 markitdown missing | Real | Message when every PDF fell back |
| AC1 e2e cannot prove no-cred | True | Plan claim reworded; the structure test is the guard |
| AC2 always-true assertion | True (`chunks` is a view on `embeddings`) | Replaced with a split-row count |
| AC3 cuttable marker | True | Single-character refusal |
| AC4 no timing baseline | Fair | Phase 3 compares against main on the papers main can build |

Mutation table, review fixes:

| Defect restored | Tests red |
|---|---|
| no range dedupe | 1 (neighbouring halves) |
| no retry in `prepare` | 1 (retry) |
| every 400 splits | 1 (non-context 400) |
| all held notes written on the unsplit path | 1 (no split reported) |
| a note per halving | 1 (split) |

## Live verification (2026-10-31, Ollama 0.24.0, nomic-embed-text, ragnar 0.3.0)

The four-paper collection from the issue, built with the branch at `6c4e5a5`:

- Completed in **4.25 min**: 4 documents, 2,838 chunks. Before the change it aborted and left no store.
- ESL: 2 chunks refused whole and split (one note each). Bates et al.: read with pdftools after
  markitdown's `Embedded NUL in string.`
- `crd_store_connect(verify = FALSE)` (connect-time embedding probe on) then `crd_search()` for
  a cross-validation query: 5 of 7 rows from Bates et al., 2 from ESL.
- An earlier build at `19f82ac`, before the review fixes, gave the same counts in 4.28 min. The
  duplicate-range defect (B1) is real, but ESL's halves did not collide.

**Cost of embedding inside `prepare`**: the two papers both versions can build
(`bengio_grandvalet2004NoUnbiased`, `chen_yang2021OneStandard`), alternating main and branch:
main 10.6 s and 10.4 s, branch 10.5 s and 10.6 s, 177 chunks each. No measurable cost.

## Upstream drafts (NOT posted; each needs the user's word)

A third report, about ragnar's progress output and file names, goes to tidyverse/ragnar
**privately** (the user's choice, 2026-10-31). Its draft is deliberately not in this public
repository.

### Comment on ollama/ollama#14186

> On 0.24.0 truncation works for ordinary text but still fails for some inputs.
> With `nomic-embed-text` (context 2048) and the default `truncate`:
>
> ```sh
> curl -s localhost:11434/api/embed -d "{\"model\":\"nomic-embed-text\",\"input\":\"$(python3 -c 'print("•"*1800)')\"}"
> # {"error":"the input length exceeds the context length"}
> ```
>
> 20,000 characters of prose, or 3,000 × `中`, are truncated to 2,048 tokens and embed. 1,000 ×
> `•` is 2,002 tokens and embeds. 1,800 × `•` (about 3,600 tokens) returns the 400. We met it on a
> textbook figure that markitdown renders as a run of `•`.

### Issue for tidyverse/ragnar

> **`ragnar_store_ingest()`: one chunk the embedding provider refuses aborts the whole ingest**
>
> In `do_ingest_remote_work()` a worker's embed error is swallowed, and the chunks come back
> unembedded. `ragnar_store_update_v2()` then embeds them in the main process with no handler,
> so a single refused chunk ends the ingest and discards every document not yet written. Seen
> with Ollama `nomic-embed-text`, which answers 400 "the input length exceeds the context length"
> for a ~1,900-character run of `•` glyphs (ollama/ollama#14186).
>
> Separately, `read_as_markdown()` fails with `Embedded NUL in string` when markitdown's text
> contains a NUL, through both the reticulate and the CLI routes (`stri_read_lines`). Stripping
> `\x00` in `_ragnartools/markitdown.py` before the string crosses into R would fix it.
> Example: arXiv 2104.00673v4.
>
> ragnar 0.3.0. We work around both in a custom `prepare`: it embeds in the worker, splits a
> refused chunk, and falls back to pdftools text.

## R CMD check (2026-10-31, at 37c20da)

`devtools::check(vignettes = FALSE, args = "--no-manual")`: 0 errors, 3 warnings, 3 notes, and
the tests passed (`testthat.R` 13 s), including the mirai worker tests against the installed
package. Every warning and note is also on main: non-ASCII in R/audit.R and R/store.R (main
has the same two files), undeclared `tibble`/`openxlsx`, `.lintr`, top-level `data-raw`/`dev`,
and `.data` bindings.

## Code-check rounds

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|---|---|---|---|---|
| 1 | 2 (shared notes log splices past 4 KB; two prose claims about ragnar) | 2 | 0 | n/a |
| 2 | 0 (Clean); one unreported invalid-UTF-8 case probed: `MarkdownDocument()` refuses invalid UTF-8 inside the reader's tryCatch, so it is unreachable | 0 | 0 | n |
| 3 | 0 (Clean); asked for the mechanism behind round 1 (claims about dependency or OS behaviour made from memory rather than the installed code or a measurement) and checked every such claim in the diff, plus shared state between workers | 0 | 0 | n |

Ended on a clean round 3 with no inside-a-fix finding in any round. Full suite after: FAIL 0 |
SKIP 2 | PASS 790 (the 2 skips predate the branch).

## Code-check rounds on the CI fix (c0fd677)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|---|---|---|---|---|
| 1 | 0 (Clean) | 0 | 0 | n/a |
| 2 | 0 (Clean) | 0 | 0 | n |
| 3 | 1: ragnar's per-file progress output does not handle every file name safely (both ragnar versions), so "One PDF never costs the build" was false. Upstream; reproduced; 0 of the local Zotero storage paths affected | claim qualified (8e89bfd) | 0 | n (pre-existing on the branch) |
| 4 | 3, inside round 3's fix (redacted record in `review-devfix-round4.md`): the consequence was more serious than round 3 said, the qualification's wording was wrong, and the drafted upstream fix did not work | user chose (2026-10-31): close it in cred and report to ragnar privately. ragnar's progress is off in `crd_store_build()`, with a test that fails if it is turned on; public ragnar draft withdrawn; wording replaced | 0 | **y** |

Rounds 2 and 3 ran concurrently: round 1 changed nothing, so both reviewed the same tree.
Round 3 also enumerated every ragnar function the ingest reaches that differs between 0.3.0
and 0.3.1.9000 (27 changed, 13 dev-only); only worker-failure reporting differs in effect.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| PR #42's R-CMD-check failed at `test-store-build.R:362`: `Actually got a <ragnar_ingest_worker_error>` | CI installs ragnar's development branch (`Remotes: tidyverse/ragnar`, 0.3.1.9000 at `06f7c3e`), which reports a worker failure as a `ragnar_ingest_worker_error` warning with a `path` field and drops the worker's class. Every local run, R CMD check included, used 0.3.0. Reproduced locally with dev ragnar in a scratch library (`R_LIBS`, so the workers load it too); `.crd_store_ingest()` now handles both forms; 75/75 pass under each; removing the new handler is red on both. Version gap filed as #43. |
