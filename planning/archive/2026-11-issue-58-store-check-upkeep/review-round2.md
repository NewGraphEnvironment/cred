## Checklist read

- code-check.md: every H3 under `## Mechanisms` read as prose, table rows skipped (14 of 14). From the standalone rules I read "Documentation Staleness" and "An assertion that matches an interpolated value cannot see the claim around it". The other standalone, Security and Spreadsheets/PDF headings (18) were not read: they do not apply to this diff.
- code-check-r.md: read "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are", "`match()` treats NA as a matchable VALUE, so two unknowns join to each other", "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one", "A `function(...)` mock hides arguments the real callee no longer accepts", "`cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package", "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared" and "A `skip_if_not()` skips only its own `test_that()` block". About 155 headings not read.
- code-check-shell.md: 0 read (the only shell in the diff is the deletion of a YAML `with:` block); all headings unread.
- code-check-spatial.md: 0 read (not applicable); all headings unread.

## Verification run (own detached worktree at 6f35848, now removed)

- Full suite, `NOT_CRAN=true` with `test_dir()`: 331 test blocks, 0 failed, 0 errors. The 2 skips are both in test-docx.R. The ragnar, duckdb and mirai tests all ran, including the new cli-markup progress test and the live-Ollama "missing model" test.
- `devtools::check(manual = FALSE)`: 0 errors, **0 warnings**, 3 notes. The notes are `.lintr` as a hidden file, a tracked `README.html`, and `.data` with no visible binding. All three were there before this branch, and none fails under the flows default `error-on: '"warning"'` (I confirmed that default in flows@v1).
- `devtools::document()` changed nothing, so man/ matches the roxygen. `tools:::.check_package_ASCII_code(".")` returns `character(0)`. `tools:::.check_packages_used_in_tests(".", testdir = "tests/testthat")` finds nothing.
- ragnar 0.4.0 source:
  - `ragnar_retrieve()` has no fallback of its own, so every embed failure still reaches cred's `error =` handler. That handler now aborts for all five reasons through `.crd_retrieval_abort()`, the same path vss takes.
  - `ragnar_store_ingest()` sets `ingest_summary` (path = `as.character(paths)`, not normalised) on its local store copy and returns that copy, early returns included.
  - Its progress line is `cli_alert_info("ingested: {origin}")`, a substituted value, so the claim that ragnar prints each origin literally holds. The test checks this with the path in fixed-string mode.
- Sentence sweep: I read every hit for fall back, degrade, once per session, progress-off wording, `cred_retrieval_fallback_*` and `cred_retrieval_error_*` across R/, man/, NEWS.md, the top of CLAUDE.md and tests/. Every statement about the default hybrid path, the error and warning classes, and the once-per-session guard is now true. The `\describe` items in `?crd_search` keep `cred_retrieval_fallback_<reason>` labels, but the preface says the reasons are the same under both classes.
- Tests that call the default hybrid path (test-store.R:280, test-store-update.R:92 and :679, test-store-search.R:34 and :77, test-store-fallback.R:602) run on stores whose embedder works, and they pass under the erroring default. So none of them was silently passing through a fallback. Every failing-embedder test that relied on the old default now passes `fallback = "bm25"` and still asserts the warning class. The new default-path test asserts the error class on two calls in a row, which only an error with no frequency guard can pass.

## Clean

No issues found.

index, diff and changed files read from file
