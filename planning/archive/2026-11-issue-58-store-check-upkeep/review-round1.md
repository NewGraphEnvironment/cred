# Review round 1 (cred#58, branch diff against origin/main e286d8b)

## Checklist read

- code-check.md: prose of all 14 H3s under `## Mechanisms` (table rows skipped). The H3s under "Rules that stand alone", Security and "Spreadsheets and PDFs" were not read; none fits this diff.
- code-check-r.md: read 11 headings: "Tests that silently do not run"; "A `skip_if_not()` skips only its own `test_that()` block"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"; "`expect_message(expr, regexp)` checks only the FIRST condition, so a progress line hides the message under test"; "`cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation"; "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared"; "testthat 3e `expect_message()` returns the condition, not the expression's value"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one"; "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are". The rest (about 150) were not read in full.
- code-check-shell.md: none read. The only shell-adjacent change removes a `with:` block from a workflow YAML.
- code-check-spatial.md: none read. Nothing spatial in the diff.

## Clean

No issues found.

What I checked, against a detached scratch worktree of HEAD 15832cf (now removed):

- **`.crd_store_ingest()` reads `ingest_summary` (#51).** In ragnar 0.4.0's `ragnar_store_ingest()` source, `summary$path` is `as.character(paths)` as passed in. `prepare_ingest_paths()` only `unique()`s, and never normalises, so `task$path` equals the input and `match(unsaid, ing_summary$path)` lines up. A worker error sets `status = "error"` and `message`, and the attribute is set on the store returned by `finish_ingest()` and by the empty-paths early return. The `ifelse()` test can never be NA (it is `!is.na(row) & %in% & !is.na()`), and an empty `unsaid` gives `character(0)`. `unsaid` is never NA, because ragnar refuses NA paths. The crash test discriminates: the crashed path raises no warning, so the old code would have given "see ragnar's warning".
- **`crd_search(fallback =)` (#47).** `.crd_retrieval_abort()` is called from inside the only handler of `tryCatch(error =)`, so nothing re-catches it. It carries the vss classes and `parent = cond`. Under `"error"` the frequency slot is never used. `rlang::arg_match()` refuses an unknown value. No code in `R/`, the vignettes, the README or the examples calls hybrid `crd_search()` (`R CMD check` ran the examples clean). Every test that still calls the hybrid default runs on a store with a deterministic offline embedder (`.crd_test_embed`, `local_pre040_store`, `local_update_world`), so CI without Ollama does not newly error. I found no string left that says hybrid falls back, apart from historical NEWS entries.
- **Progress (#49).** In ragnar 0.4.0 the line is `cli::cli_alert_info("ingested: {origin}")`, with the origin as a value, and `cli_alert` does not wrap. `.crd_need()` refuses an older loaded ragnar. testthat sets `rlang_interactive = FALSE`, so the build test's default-off arm holds whether the suite is run interactively or not. The mocks' arguments match ragnar's formals, which the test asserts.
- **R CMD check.** `rcmdcheck(--as-cran --no-tests)` on HEAD gave 0 errors and 0 warnings, with only pre-existing NOTEs. `tools:::.check_package_ASCII_code(".")` returned nothing. `tools:::.check_packages_used_in_tests(".", testdir = "tests/testthat")` returned nothing. `mirai` is a hard Import of ragnar 0.4.0, so the `skip_if_not_installed("mirai")` tests run in CI. `openxlsx` is guarded by `requireNamespace()`. The default `error-on` in `flows` r-cmd-check.yaml@v1 is `'"warning"'`, as intended.
- **Tests.** I ran test-store-update, test-store, test-store-fallback, test-store-build, test-store-search and test-store-embed-check with `NOT_CRAN=true` after `load_all()`. All had 0 failed and 0 errors (704 passed).

One coverage note, not a finding: nothing asserts that `crd_store_update()` passes its `progress` through. Hard-coding `progress = FALSE` at R/store.R:2704 would leave the suite green. The build path does have that test.

index, diff and changed files read from file
