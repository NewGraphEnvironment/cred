# Review: fix round 2 (commit c956349 against its parent)

## Checklist read

- Index: `checklist1.txt` in full.
- `code-check-r.md`, read by heading: "`R CMD build` ships every top-level directory not in `.Rbuildignore`", "`R CMD build` ships the `.git` FILE when you build from a worktree", "`.Rbuildignore` has no comment syntax — every line is a live regex", "A `data-raw/` script must load the source tree, not the installed package", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package".
- `code-check.md`: the opening prose of every H3 under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice).
- `code-check-shell.md`, `code-check-spatial.md`: no heading names a tool or shape this diff uses.

## What was checked

1. **The tarball, not the config.** `R CMD build --no-build-vignettes --no-manual` from a `git worktree add --detach` of c956349 (worktree removed after). Top-level entries in `cred_0.7.0.tar.gz`: `.lintr DESCRIPTION inst LICENSE man NAMESPACE NEWS.md R README.html README.md tests vignettes`. Zero entries under `cred/data-raw/` or `cred/dev/`; `.git`, `planning`, `research` also absent. This confirms what round 1 could only infer from `tools:::inRbuildignore()`, which returns FALSE for children such as `dev/dev.R`: R removes the excluded directory recursively.
2. **Nothing depends on data-raw/ or dev/ shipping.** `git grep` outside planning/research/CLAUDE.md: only `.lintr`'s exclusion (lintr does not read `.Rbuildignore`, so unaffected), the scripts themselves, and the comment in `tests/testthat/test-matching.R:7`. `README.Rmd` uses `man/figures/logo.png` (committed; `make_hexsticker.R` writes it there, so the build does not need data-raw). `_pkgdown.yml`, `vignettes/*.Rmd` and `DESCRIPTION` name neither. The three workflows call `NewGraphEnvironment/flows@v1`; fetched `r-cmd-check.yaml` and `r-pkgdown.yaml` at `v1`: neither references data-raw or dev, and pkgdown runs with `install = FALSE` against the package installed from the built source, which needs neither.
3. **The corrected warning, on every path that reaches it.** The only caller of `.crd_store_describe()` is `crd_store_push()` (R/store.R:3213). The warning fires when the store has no `cred_ragnar` stamp. Its remedy sentence, "A rebuild with crd_store_build(), or a crd_store_update() that changes the store, stamps it.", holds:
   - `crd_store_build()` stamps every completed build (R/store.R:2370). The stamp write is in a `tryCatch` and can fail with its own warning; that is the old text's case too, and the build says so itself.
   - `crd_store_update()` stamps (R/store.R:2660, no handler) on every path that keeps the copy, and both "Store is current" exits return before it. A store with no `cred_sources` record makes `same_rec()` FALSE, so it is always kept and stamped; a recorded, unchanged store is not, which is the case the old sentence got wrong and the new one names.
   - Other copies of the claim (roxygen at R/store.R:2074 "each time they write it", R/store.R:3111, NEWS.md:20, man/crd_store_push.Rd:80) do not say an update always stamps, so nothing else carries the corrected over-claim.

## Clean

No issues found.

## Outside this commit (not a finding)

- The brief says `README.html` is a local untracked file. It is **tracked** (`git ls-files README.html` lists it, last touched in aeef3f1, and it is also listed in `.gitignore`, which has no effect on a tracked file), and it ships in the tarball built from a clean worktree. It predates this commit and breaks nothing, but the premise in the brief is wrong.
