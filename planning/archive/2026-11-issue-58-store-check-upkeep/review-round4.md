# Code-check round 4: cred#58 branch (ee8ef01 against a1866c9)

## Checklist read

- **code-check-r.md**, 8 headings read in full: "`$` on a list partial-matches, so a longer sibling key answers for a missing one"; "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"; "`[[` on a named ATOMIC vector with an absent key is an error, not `NULL`"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "`expect_message(expr, regexp)` checks only the FIRST condition, so a progress line hides the message under test"; "testthat 3e `expect_message()` returns the condition, not the expression's value"; "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared". 124 of 132 not read.
- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, table rows skipped. 24 of 38 not read.
- **code-check-shell.md**: none read (the only shell-adjacent change is removing a `with:` block from a reusable-workflow call). 75 of 75 not read.
- **code-check-spatial.md**: none read (no spatial code in the diff). 98 of 98 not read.

## Clean

No issues found.

What I checked beyond reading:

- Ran `test-store-push.R` (115 pass), `test-store-fallback.R` (189 pass) and `test-store-build.R` (87 pass) with `NOT_CRAN=true` in my own detached worktree of ee8ef01: 0 failed, 0 error, 0 skipped.
- Put the round-3 defect back in that copy (`old$notes` for `old[["notes"]]`, the bytes from b18063f). Only ".crd_manifest_merge carries notes by its exact name only" went red, so the regression test can detect the defect.
- Read ragnar 0.4.0's `ragnar_store_ingest()` and `prepare_ingest_paths()`. `ingest_summary` is `tibble(path = as.character(paths), status, n_chunks, message)`. Its `path` holds the input strings as given, never normalised, and is matched against `task$path` from the same strings. So `match(unsaid, ing_summary$path)` lines up with cred's paths, and `message` is a character column. The `ifelse()` test cannot be NA: it is built only from `!is.na()` and `%in%`. A zero-length `unsaid` gives `character(0)`.
- The `.crd_retrieval_abort()` call inside the `hybrid` handler propagates: a `tryCatch()` handler runs after its own handlers have unwound, and `crd_search()` has no outer catch.
- `rlang::arg_match(fallback)` is called in the frame whose formal it reads. `rlang::is_interactive()` returns FALSE under testthat, so the progress-default assertions are deterministic.
- `tools:::.check_package_ASCII_code(".")` returns `character(0)`. Every package the tests reach with `::` is declared in DESCRIPTION.
- The CAS retry calls `.crd_manifest_merge()` again with the original `entry`, which carries no notes when `notes = NULL`, so notes are re-carried from the freshly read manifest. This is correct.

## Mechanism enumeration

**The mechanism.** `$` on a list does exact matching only when the exact name is present. When it is absent, `$` falls back to a unique prefix match, so a longer sibling key (`notes_private` for `notes`) answers for the missing one. This applies to every list: anything parsed from JSON, a data frame (`$.data.frame` partial-matches with a warning), a pairlist, and a condition object. It does not apply to environments, S4 slots or tibbles: a tibble warns and returns NULL. The read itself does not fail. The damage lands on the `is.null()` guard after it, which reads "present" for a key that is absent. **`$<-` matches exactly but reads its target through `$` first**, so `x$stores[[k]] <- v` on a list with only `stores_retired` copies the sibling's whole contents into a new `stores` (measured: `list(stores_retired = list(a = 1))` becomes `stores = list(a = 1, b = 2)`).

Every `$` read added by the diff, plus context lines the diff changes:

| # | Site | Object | Exposure | Verdict |
|---|------|--------|----------|---------|
| 1 | R/store.R:3193 `entry[["notes"]]`, `old[["notes"]]` | parsed manifest entry; cred-built entry | `[[` is exact | **Safe** (the round-3 fix; restoring `$` reds the regression test) |
| 2 | R/store.R:3193 `entry$notes <- ...` | cred-built list | assignment to a top-level key, no `$` read of a nested target | **Safe** |
| 3 | R/store.R:3191 `old <- existing$stores[[name]]` (new line) | parsed manifest (`fromJSON(simplifyVector = FALSE)`) | `$stores` partial-matches when the manifest has no `stores` key and exactly one `stores*` sibling | **Latent, unreachable for any manifest cred writes.** Every merge writes `stores`, and an exact name always wins. Its exposure is the same as pre-existing lines 3188 and 3194, which in that case already copy the sibling block whole into `stores`. Converting only 3191 would make it disagree with 3188 and 3194, so convert all three together or none. Not raised as a finding. |
| 4 | R/store.R:3410 `entry$notes <- notes` | cred-built list from `.crd_store_describe()` | assignment | **Safe** |
| 5 | Adding a `notes` key to entries: does it newly answer any existing read? | manifest entries | only a read of a prefix of `notes` (`$n`, `$no`, `$not`, `$note`) could pick it up | **Safe.** A grep of R/ finds no such read on a manifest entry or the manifest; `manifest_note` is top-level and not a prefix match for anything read. |
| 6 | R/store.R:2033-2039 `ing_summary$path`, `$status`, `$message` | ragnar's `ingest_summary` tibble, or cred's empty tibble | tibble `$` is exact. A base `data.frame` from a future ragnar would partial-match, but 0.4.0 always carries all four exact names, and an exact name wins. | **Safe** under the `ragnar (>= 0.4.0)` floor |
| 7 | R/store.R `w$path` in the `ragnar_ingest_worker_error` handler (context line; the handler body changed) | rlang condition object (list) | `path` is present by name; no other field starts with `path` | **Safe** |
| 8 | test-store-push.R `out$stores$alpha$...`, `kept$current$notes`, `fromJSON(...)$stores` | test lists and parsed JSON | exact names present in each assertion that should pass; where an assertion expects absence (`$documents`, `beta$notes`), no sibling key shares the prefix | **Safe.** The regression test itself uses `expect_identical(out$stores$alpha, list(md5 = "y"))`, a whole-object compare, so a partial match in the test cannot hide the defect. |
| 9 | test-store-build.R `formals(f)$progress` | pairlist (partial-matches) | `progress` is an exact formal of both functions | **Safe** |
| 10 | test-store-build.R `.crd_build_seen$progress`; test-store-update.R `world$progress` | environments | `$` on an environment is exact | **Safe** (an unreached mock leaves NULL, which fails `expect_identical`, so neither test is vacuous) |
| 11 | test-store-build.R `res$skipped$reason`, `res$skipped$origin` | cred-built list holding a tibble | exact names; tibble `$` is exact | **Safe** |

index, diff and changed files read from file
