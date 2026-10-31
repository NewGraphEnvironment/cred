# Code-check round 2: dev-ragnar fix (c0fd677, #35)

## Checklist read

- **code-check.md**: all 14 `## Mechanisms` H3s (prose, `|` rows skipped). Of the remaining
  headings I read "Documentation Staleness" and "An assertion that matches an interpolated value
  cannot see the claim around it". 26 not read.
- **code-check-r.md**: "`$` on a list partial-matches, so a longer sibling key answers for a
  missing one", "`[[` on a named ATOMIC vector with an absent key is an error, not `NULL`",
  "`match()` treats NA as a matchable VALUE, so two unknowns join to each other",
  "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one",
  "Do not abort inside a handler for a warning raised from C++; note it and abort after the call returns",
  "A `function(...)` mock hides arguments the real callee no longer accepts",
  "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared",
  "Tests that silently do not run", "A `skip_if_not()` skips only its own `test_that()` block",
  "Under `R CMD check`, tests run from a temp dir against the INSTALLED package",
  "`paste()` with a zero-length argument returns length ONE, not zero",
  "testthat's failure snapshots land in `tests/` and ride in on `git add -A`". 101 not read.
- **code-check-shell.md**: none apply (no shell in the diff). 75 not read.
- **code-check-spatial.md**: none apply. 113 not read.

## What was checked

- **Dev ragnar's `R/ingest.R` at 06f7c3e** (the devlib DESCRIPTION's `RemoteSha` matches):
  every `is_error_value()` result (mirai error, interrupt, nng error) goes through one
  `rlang::warn(class = "ragnar_ingest_worker_error", path = task$path, call = NULL)`.
  `task$path` is `new_paths$origin[[i]]`, which is `unique(as.character(paths))` passed through a
  DuckDB register/select round trip. So it is the input string, and `worker_errors[unsaid]` keys
  on the same strings `setdiff(paths, ...)` produces. A failed task is followed by `next` with no
  store write, so on a fresh store (the only caller, `crd_store_build()`, always creates one) a
  muffled path can never also be in `documents` and silently drop out of `skipped`.
- **ragnar 0.3.0** (default library): `warning(cond)` with `class(cond) <- cond$condition.class`.
  No `ragnar_ingest_worker_error` exists there, so the new handler is inert and the old
  `error =` branch is unchanged. Under dev ragnar no error-class condition reaches the main
  process, so the `error =` branch is inert. The two branches cannot both fire for one document.
- **Handler mechanics**: `rlang::warn()` signals through `warning()`, so `muffleWarning` exists.
  `x[[""]] <- v` on a `character()` does not error (measured), so the handler cannot abort the
  ingest from inside. When `path` is malformed the warning is not muffled, so it prints, and the
  fallback reason "see ragnar's warning" stays true. `[` on character subscripts matches
  exactly, and absent names give `NA`, which the fallback replaces.
- **Every failed document reaches the user**: under 0.3.0 a `cred_ingest_skip` is muffled and
  its reason is in the notes, and any other failure prints, with a fallback reason. Under dev,
  every failure is muffled and carries the note's reason or ragnar's message. Both feed
  `crd_store_build()`'s "Skipped N PDF(s)" warning, or its "No PDF could be ingested" stop.
- **Tests**: `test-store-build.R` passes 19/19 under ragnar 0.3.0 and 19/19 under 0.3.1.9000
  (`R_LIBS` = devlib, mirai workers included), run in a scratch copy.
- **Restore the bug**, under dev ragnar:
  - Dropping the new handler's `invokeRestart("muffleWarning")` fails the end-to-end test
    ("an ingest finishes past an unreadable document and names it", with real mirai workers)
    and the new mocked test.
  - Replacing the `worker_errors[unsaid]` lookup with `NA` fails the new test, on the
    "Worker interrupted." reason.
- The mock replaces only `ragnar::ragnar_store_ingest`, and its formals match the call site
  (`store, paths, prepare =, progress =`). `rlang` is in Imports, so the test's `rlang::warn`
  is declared.
- **Prose** (CLAUDE.md bullet, roxygen, research file): each version-specific claim matches the
  two sources read. A grep for other copies of the "class kept" sentence outside
  `planning/archive` finds only the rewritten ones.

## Clean
No issues found.
