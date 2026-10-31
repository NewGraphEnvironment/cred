# Code-check: dev-ragnar fix (c0fd677), round 1

## Checklist read

- **code-check-r.md**: read 12 in full. They were "Tests that silently do not run", "Reproducibility", "`$` on a list partial-matches, so a longer sibling key answers for a missing one", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package", "Two repos pinning the same remote at different tags is an unsolvable install", "`tryCatch(warning = )` DISCARDS the value the expression produced", "Do not abort inside a handler for a warning raised from C++; note it and abort after the call returns", "`match()` treats NA as a matchable VALUE, so two unknowns join to each other", "`[[` on a named ATOMIC vector with an absent key is an error, not `NULL`", "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared", "A `function(...)` mock hides arguments the real callee no longer accepts", and "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one". 103 not read.
- **code-check-shell.md**: none read, because the diff has no shell. 70 not read.
- **code-check-spatial.md**: none read, because the diff has no spatial code. 93 not read.
- **code-check.md**: read the prose, without table rows, of all 14 H3s under `## Mechanisms`. 23 not read (the stand-alone, security and spreadsheet rules).

## What was checked

- Read the dev ragnar `R/ingest.R` (06f7c3e). A failed worker reaches the main process as `rlang::warn(message, class = "ragnar_ingest_worker_error", path = task$path, call = NULL)`. `task$path` is `new_paths$origin[[i]]`, taken from `unique(as.character(paths))`. That is the same string `prepare` receives, so it is the key that both the notes and `.crd_store_ingest()`'s `unique(paths)` use. The worker's class is lost, as the CLAUDE.md, roxygen and research prose say.
- Ran `test-store-build.R` in a copy under each ragnar, with `NOT_CRAN=true` and `test_file`. With ragnar 0.3.0 it gave 19 tests, 75 passes, 0 failures, 0 errors and 0 skips. With dev 0.3.1.9000 (`R_LIBS=devlib`) it gave the same.
- Mutation: I made the dev handler a no-op that neither records nor muffles, then ran under dev ragnar. "an ingest finishes past an unreadable document and names it", the real mirai end-to-end test, failed. So did "an ingest takes ragnar's ragnar_ingest_worker_error warnings too", with 2 failures. Both guards fire.
- `worker_errors[unsaid]` is a single-bracket lookup on a named character vector. It gives NA for an absent key, which is then replaced by the default, and `character(0)` for an empty `unsaid`. The `[[<-` assignment appends by name. `w$path` cannot partial-match, because no other condition field starts with `path`. The guard fails toward letting the warning through, which keeps the failure visible.
- Under dev ragnar, worker failures that are not skips are now muffled as well. They are not lost: `crd_store_build()` lists every `ing$skipped` reason in its "Skipped N PDF(s)" warning, and it stops when nothing was ingested. A main-process interrupt is unaffected and still unlinks the store.
- The test's mock has an explicit `(store, paths, prepare, progress)` signature, which matches the call site. `rlang` is declared in DESCRIPTION. `lintr::lint_package()` reports 0 lints.
- [#43](https://github.com/NewGraphEnvironment/cred/issues/43) exists, and its title is about the ragnar version gap.

## Clean
No issues found.
