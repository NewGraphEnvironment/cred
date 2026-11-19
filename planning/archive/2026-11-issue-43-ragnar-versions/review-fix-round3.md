## Checklist read

- Index: checklist1.txt, read in full.
- code-check-r.md, full sections read: "`R CMD build` ships every top-level directory not in `.Rbuildignore`", "`.Rbuildignore` has no comment syntax — every line is a live regex", "A `data-raw/` script must load the source tree, not the installed package", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package".
- code-check.md: the H3 prose under `## Mechanisms` (the index's first sentence of each, plus "A guard's scope, escape hatches, and remedies" and "A fixture that cannot reach the failure mode" applied to the reach below).
- code-check-shell.md and code-check-spatial.md: no heading names a tool or shape this diff uses.

## Clean

No issues found.

## Reach of the change (the mechanism earlier rounds hit)

### Every path that reaches the corrected warning

The warning lives only in `.crd_store_describe()` (R/store.R:2954-2965), which has one package caller,
`crd_store_push()` (R/store.R:3213, for both `dry_run = TRUE` and a real push), plus direct calls in
tests (test-store-push.R:509, 522, 543, 572; test-store-update.R:81-82). It fires in all three
branches (schema contradicts the session, no ragnar installed, session fallback), and the corrected
sentence is appended to each.

The sentence claims: a rebuild stamps, and an update stamps exactly when it changes the store.
Checked against every exit of both functions:

| path | changes the store | stamps | holds |
|---|---|---|---|
| `crd_store_build()` success (R/store.R:2369) | yes (new store) | yes, in `tryCatch`; a failed write warns in its own words | yes |
| `crd_store_build()` abort before `complete` | store deleted | no | n/a (no store) |
| update: refusals (args, no store, `.wal`, embedder probe, width mismatch) | no | no | yes |
| update: first "Store is current" return (nothing to ingest, nothing dropped, record same) | no | no | yes — the old text promised a stamp here and was wrong |
| update: "no documents" stop | no (copy discarded) | no | yes |
| update: second "Store is current" return (ingest attempted, nothing ingested/dropped, record same) | no (copy discarded) | no | yes |
| update: kept copy (R/store.R:2660, then rename) | yes | yes, unguarded: a failed write aborts before the rename, so the store is left unchanged and unstamped together | yes |

Converse also holds: every path that stamps in `crd_store_update()` is the kept-copy path, which
replaces the store. The new test at test-store-update.R:205 covers build stamps / unchanged update
keeps / changed update restamps. No test asserts the remedy sentence's wording, so none broke
(the two `grepl()` assertions match "records no ragnar version" and "not installed" only).

Other prose stating the same fact, grepped for the sentence: `.crd_ragnar_stamp_read` roxygen
("each time they write it"), `?crd_store_push` / man/crd_store_push.Rd ("the ragnar that last built or
updated it"), NEWS.md:20-21, CLAUDE.md:359-361. None claims an unchanged update stamps; all hold.

### Every consumer of the two excluded directories

`git grep` for `data-raw`, `dev/`, and each script's name over the tracked tree (R/, tests/,
vignettes/, inst/, .github/, _pkgdown.yml, README.Rmd, DESCRIPTION):

| consumer | reads from | affected by exclusion | holds |
|---|---|---|---|
| `dev/dev.R` sourcing `data-raw/make_hexsticker.R`, `data-raw/make_toy_zotero.R` | source tree | no | yes |
| `data-raw/make_hexsticker.R` (`data-raw/nge-icon_white.png`) | source tree, run from repo root | no | yes |
| `data-raw/ragnar_store_compat.R`, its log under `data-raw/logs/` | source tree; cited by research/ and planning/ (both already excluded) | no | yes |
| `.lintr` exclusion `"data-raw"` | source tree | no | yes |
| tests/testthat/test-matching.R:7 | a comment only | no | yes |
| helper-zotero.R / test-zotero.R | build their own fixture / read `inst/extdata` via `system.file()` | no | yes |
| vignettes, R/, man/, .github workflows, _pkgdown.yml | — | no reference to either directory | yes |

No test, vignette or example reads either directory, so nothing breaks under `R CMD check` when they
are absent from the tarball.

Verified against the tarball, not the config: `R CMD build --no-build-vignettes --no-manual` of a
detached worktree at c956349 gave `cred_0.7.0.tar.gz` with 0 entries under `cred/data-raw/` or
`cred/dev/`; top level is `.lintr DESCRIPTION inst/ LICENSE man/ NAMESPACE NEWS.md R/ README.html
README.md tests/ vignettes/`. Both patterns are anchored and contain no metacharacter that widens
them (`-` outside a class is literal), and `.Rbuildignore` still carries no comment lines. Worktree
removed afterwards.

## Notes outside this diff (not findings)

- The brief calls `README.html` "a local untracked file". It is **tracked** (`git ls-files README.html`
  returns it, despite `.gitignore`), so it ships in the tarball, as the build above shows. Pre-existing.
- The build's stamp-failure warning (R/store.R:2373) says push "will record this session's ragnar
  instead". That holds when the push runs in the build session (the schema then always agrees with it);
  a push from a different session records that session's ragnar, or none if its schema check rules it
  out. Pre-existing wording, and the push warns in its own words either way.
