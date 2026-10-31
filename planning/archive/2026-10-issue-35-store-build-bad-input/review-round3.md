# Code-check round 3 — #35 (branch `35-crd-store-build-an-oversize-chunk-aborts`, HEAD b64d5b3)

## Checklist read

- **code-check-r.md** (115 H3): read in full: "Tests that silently do not run"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package"; "`strsplit()` drops a trailing empty field, so a trailing separator vanishes"; "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one"; "Do not abort inside a handler for a warning raised from C++; note it and abort after the call returns"; "`tryCatch(warning = )` DISCARDS the value the expression produced"; "`tempfile()` lives in the session tempdir, so a path printed in an error names a file R is about to delete"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared"; "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are". 10 read, 105 not.
- **code-check-shell.md** (70 H3): read "Parallel writers sharing one output file interleave mid-record". 1 read, 69 not.
- **code-check-spatial.md** (93 H3): none apply (no spatial code). 0 read, 93 not.
- **code-check.md** (37 H3): the prose of all 14 H3s under `## Mechanisms` (tables skipped). 14 read, 23 not.

## The mechanism behind rounds 1 and 2

Both round-1 defects came from one assumption: **how a dependency or the OS behaves, written from memory or from reading a neighbouring function, without checking the installed code or measuring.** The 4 KB splice assumed appends from parallel processes stay atomic. The two ragnar prose errors described internals as recalled: the primary key sits on `embeddings`, not on the `chunks` view, and the main process makes `max(3 * n_workers, 20)` tries, not 20. In `code-check.md` this is the "never measured" state under "A guard's scope, escape hatches, and remedies". Nothing about such a claim is stale, so nothing near it contradicts it.

## Where that mechanism reaches in this diff, each claim checked

All of these were checked against installed ragnar 0.3.0, mirai 2.6.1, httr2 1.3.0 and a live Ollama 0.24.0 with `nomic-embed-text`, or by a mutation run in a temp copy.

| claim (where) | how checked | verdict |
|---|---|---|
| A worker's embed error is swallowed (`tryCatch(..., error = function(e) NULL)`) (CLAUDE.md, roxygen, research) | `ragnar:::do_ingest_remote_work` | true |
| The main process re-embeds unembedded chunks with no handler (same) | `ragnar:::ragnar_store_update_v2`: `store@embed(...)` with no tryCatch | true |
| Chunks returned with an `embedding` column skip both embeds (research) | `do_embed` returns early when `"embedding" %in% names(chunks)`; `update_v2` checks the same | true |
| A read error comes back as `warning(cond)` with its class kept (CLAUDE.md, `.crd_store_ingest` roxygen, research) | `ragnar_store_ingest`: `class(cond) <- cond$condition.class; warning(cond)`. Removing the `invokeRestart("muffleWarning")` turned test 14 into an error | true; the guard fires |
| Workers run with `ragnar.embed.req_retry = FALSE`; the main process makes `max(3 * n_workers, 20)` tries within 180 s (roxygen, research) | `ragnar_store_ingest` source | true |
| The retry option is read at call time inside the worker's embed | `ragnar:::embed_req_retry` calls `getOption()` on every request; `embed_ollama` calls it | true |
| httr2 retries 429 and 503 only, so a 400 is not retried (roxygen) | `httr2::req_retry` defaults: `retry_on_failure = FALSE`, default transient statuses | true |
| `embeddings` has `PRIMARY KEY (doc_id, start, "end")`; `chunks` is a view joining `embeddings` to `documents` (CLAUDE.md, roxygen, research) | DDL in `ragnar_store_create_v2` | true |
| `text` must equal `stri_sub(document, start, end)` (research, test helper) | `update_v2` check (applies only when a `text` column is present) | true |
| A store's `@embed` is re-parented to `baseenv()` (CLAUDE.md, roxygen, test comments) | `ragnar_store_create(embed = function(x) ragnar::embed_ollama(x, model = "nomic-embed-text"))@embed` has environment `<base>`; `model` is inlined as a literal | true |
| `embed_ollama` sends 10 inputs per request (roxygen "batches of ten", research) | `batch_size = 10L` | true |
| `input_of()` matches what ragnar's worker embeds (code comment) | matches `do_embed`'s `ifelse(nzchar(context), ...)`. The main-process path joins differently, but the comment names the worker | true |
| 400 classes are `httr2_http_400 / httr2_http / httr2_error / rlang_error / error`; connection refused is `httr2_failure` (research, test comment) | live probe through `ragnar::embed_ollama` | true (`rlang_error` appears twice in the live class vector; harmless) |
| Context 2,048 tokens and `num_ctx 8192` (research) | `/api/show` | true |
| Truncation table: 20k prose gives 2048 tokens; 3000 x `中` gives 2048; 1000 x `•` gives 2002; 1800 x `•` gives 400; `truncate: false` gives 400 (research) | live `/api/embed` probe | all five reproduced |
| ollama/ollama#14186 is open, "truncate ignored since 0.13.5" (research) | `gh issue view` | true |
| `markdown_chunk()` default target is 1,600 characters (research) | `args(ragnar::markdown_chunk)` | true |
| The CLI route reads with `stri_read_lines` (research) | `ragnar:::read_as_markdown_cli` | true |
| `read_as_markdown()` sets `origin = path`, so `documents.origin` equals the path `.crd_store_ingest` compares | source | true |
| Duplicate paths (keyD and keyA share one file) are ingested once (`crd_store_build` comment) | `prepare_ingest_paths` calls `unique()`, so one worker per file and no double notes | true |
| `prepare` reaches nothing outside base R and `pkg::` | `codetools::findGlobals(prepare)`: every global resolves from its baseenv-parented environment | true |
| Halves of neighbouring chunks can repeat a range (roxygen, test) | replacing the `duplicated()` dedupe with all-TRUE turned test 6 red | true; the guard fires |
| A split is not reported for chunks handed back unsplit (roxygen) | changing `flush("read_pdftools")` to `flush()` turned test 11 red | true; the guard fires |

## Places two workers or two processes share state

- **Notes directory.** One `tempfile("notes-<pid>-")` per `prepare` call, written once. Each call flushes exactly once: `skip()` and the success and failure paths are mutually exclusive. File names cannot collide across processes because the pid is in the name, and within a process `tempfile()` checks for existence. No appends are left.
- **DuckDB store.** Workers receive `store` serialised but use only `@embed`; every write happens in the main process (`ragnar_store_update`).
- **R options.** `ragnar.embed.req_retry` is set per call and restored by `on.exit()`, and is local to each worker process.
- **Ollama.** One server takes concurrent requests. A busy server's 429 or 503 is retried in the worker (20 tries within 180 s).
- **Test 16's flag file** is shared on purpose, across processes, through the filesystem.

## Other checks

- The full `test-store-build.R` run (`NOT_CRAN=true`, temp copy) passed: 18 tests, 0 failed, 0 errors.
- `markdown_chunk()` returns at least 1 row for every non-whitespace input probed (`"x"`, `"---\n---"`, `"<!-- -->"`, `"#"`, NBSP, ZWSP, `"\f"`). So `nrow(NULL)` cannot be reached after the batch loop.
- markitdown returns `""` for a PDF with no text layer, and the pdftools fallback joins its empty pages to `"\n\n"`. `trimws()` empties that, so the document is skipped as intended.
- `pdftools` is in Imports and `withr` is in Suggests. `mirai` is reached only through `skip_if_not_installed`.

## Clean

No issues found.
