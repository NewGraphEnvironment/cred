## Checklist read

- Index: checklist1.txt (all four FULL TEXT files listed).
- code-check-r.md, read in full by heading: "A `data-raw/` script must load the source tree, not the installed package"; "`R CMD build` ships every top-level directory not in `.Rbuildignore`"; "`.Rbuildignore` has no comment syntax — every line is a live regex"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package".
- code-check.md: the opening prose of every H3 under `## Mechanisms`, with "A guard's scope, escape hatches, and remedies" read for its point that a remedy in an error message is code the caller will run.

## Clean

No issues found.

What I checked:

1. `.Rbuildignore` (`^data-raw$`, `^dev$`).
   - `tools:::inRbuildignore()` run over the tree, directories included, excludes `data-raw` and `dev` at the directory level. No other path is newly excluded. Both lines are valid anchored regexes, and neither is a comment line.
   - Nothing that runs from a built package reads either directory. A grep for `data-raw`, `dev/`, the script names and `logs` across `R/`, `tests/`, `vignettes/`, `inst/`, `man/`, `DESCRIPTION`, `NAMESPACE`, `_pkgdown.yml` and `.github/` finds one hit, a comment in `tests/testthat/test-matching.R:7`. No test, vignette or example reads a path under either directory, and `helper-store.R`'s `"raw"` is a `readBin` type, not a path.
   - `.lintr`'s `"data-raw"` exclusion is a separate mechanism, so this change does not touch it.
   - The tracked files now kept out of the build are `data-raw/{make_hexsticker.R, make_toy_zotero.R, ragnar_store_compat.R, nge-icon_white.png, logs/ragnar_store_compat/20261118_results.tsv}` and `dev/{00_setup.R, dev.R}`. None is runtime data.

2. Message at `R/store.R:2964`, in `.crd_store_describe()`. The hunk header says `crd_store_update`, but the line is in `.crd_store_describe()`.
   - Old text: "Rebuilding or updating the store with crd_store_build() or crd_store_update() stamps it." This was false for an update that changes nothing.
   - New text: "A rebuild with crd_store_build(), or a crd_store_update() that changes the store, stamps it." This matches the code:
     - `crd_store_build()` calls `.crd_ragnar_stamp_write()` unconditionally after ingest (line 2370). If that write fails it warns, and the warning already names the failure.
     - `crd_store_update()` writes `cred_ragnar` only at line 2660, which is on the kept-copy path. Both "Store is current" early returns (the pre-copy `same_rec` return and the post-ingest return when nothing was ingested or dropped and the record is unchanged) return before it. So an update that leaves an unstamped store unchanged does not stamp it, which is what the new wording says.
     - A store with no `cred_sources` record never takes the first early return, because `same_rec()` is FALSE when `rec` is NULL. Its record changes, the copy is kept, and the store is stamped. This is consistent with "that changes the store".
   - Tests match only "records no ragnar version", in `test-store-push.R` at lines 530 and 536. The changed sentence is not asserted anywhere, so nothing breaks.
