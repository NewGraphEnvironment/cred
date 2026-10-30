# Code-check round 2: #40 (branch `40-crd-zot-src-lookup-a-key-resolves-across`, HEAD b887e19)

## Checklist read

- `index_code-check.md`, `index_code-check-r.md`, `index_code-check-shell.md`, `index_code-check-spatial.md`: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms` (table rows skipped), plus "Documentation Staleness" and "An assertion that matches an interpolated value cannot see the claim around it". The other 21 headings were not read in full: the rest of the standalone rules, Security, and Spreadsheets/PDFs.
- `code-check-r.md`: read 21 sections in full: "A `data-raw/` script must load the source tree…", "Regenerated binaries churn git…", "Tests that silently do not run", "testthat counts an uncaught error…", "A `skip_if_not()` skips only…", "Base name shadowing in formal args", "Cross-function consistency…", "`$` on a list partial-matches…", "A database driver's value is not a base R type…", "`paste()` with a zero-length argument…", "Under `R CMD check`, tests run from a temp dir…", "`dbConnect(SQLite(), path)` CREATES the file…", "`sort()` and `order()` collate by `LC_COLLATE`…", "A library call that dispatches on a global option is not a pure function", "`tryCatch(warning = )` DISCARDS…", "`match()` treats NA as a matchable VALUE…", "`expect_message(expr, regexp)` checks only the FIRST condition…", "`unlist()` prefixes a `split()` group's name…", "`[[` on a named ATOMIC vector…", "`data.frame()` recycles a scalar against a zero-length column", "Postgres row order…" (the first shape only), "A `pkg::` call in a test…", "A `function(...)` mock…", "`ifelse()` with an all-NA test…". The other ~94 headings were read at index level only.
- `code-check-shell.md`: index only (70 headings). The diff has no shell.
- `code-check-spatial.md`: index only (93 headings). The diff has no spatial code.

## Round 1 fixes, re-reviewed

Mutation table. Each fix was put back in an rsync copy (not the checkout), then `NOT_CRAN=true testthat::test_file("test-zotero.R")` was run on the copy, counting `failed | error`:

| restored | result |
|---|---|
| `"user"` = every library without a group (fix 1) | 4 failed + 2 errors, including the new "\"user\" is My Library alone" test |
| `aurl.value = purl.value` (fix 2) | 1 failed: "with no item URL…" |
| no zero-member stop (fix 3) | 1 failed: "a collection with no items of its own…" |
| no `if (nrow(best) == 0L) return(empty)` (fix 4) | 1 failed: "empty results keep their column types" |
| no `as.character()` on the abstract (fix 4) | 1 failed: same test |
| no `CAST`/`as.character()` in `.crd_zot_resolve_keys` (fix 4) | **0**: survives |
| no `as.character()` on the collection members' `citation_key`/`title` (fix 4) | **0**: survives |

The two surviving casts are untested, but removing them shows no defect. Every path they cover is either already typed by a later guard (`return(empty)`) or ends in `crd_store_build()`'s "No PDF attachments resolved" stop. They are recorded here for completeness, not raised as findings.

Fix 2 matches Zotero's rule. In SQLite a NULL sorts last under `DESC`, so for a parent with no URL, `'' = ''` gives 1 (not reachable), an attachment with a URL gives 0, and one without a URL gives NULL. That is the same order Zotero's `value=? DESC` produces with `?=''`. Fix 1's `libraries.type` values ('user', 'group', 'feed') are Zotero's.

## Findings

- **[severity: bug]** R/store.R:1536 (`.crd_zot_collection_pdfs`) and R/store.R:1741-1745 (`crd_store_build`). The collection path takes members by membership alone and never applies the duplicate-key refusal that `.crd_zot_resolve_keys()` gives the key path. When two live items in one library share a citation key (the fixture's R-base, items 170/172), both are ingested under that one key, with no warning. The build then reports it as `Ingesting several PDFs for 1 item(s): R-base (2)`, because the count is keyed by citation key and the message calls each key an item. `.crd_zot_key_pdfs("R-base", library = "user")` refuses the same key with `cred_zot_ambiguous`. Probe: a collection holding items 170 and 172 in library 1 returns two `sources` rows, both `R-base` (`rbase_a.pdf`, `rbase_b.pdf`), with `left_out` empty and no condition raised. At search time `.crd_zot_key_from_path()` labels chunks from both works `R-base`, so a passage can be attributed to the key the report's bibliography resolves to the *other* work. That is the misattribution the package exists to catch, and CLAUDE.md:99-100 says such a key is "left unresolved with a warning, never picked". Fix: resolve the members' keys through `.crd_zot_resolve_keys(con, keys, hits$library_id)`. That also catches a key shared with a live item outside the collection. Move the keys it returns as unresolved into `left_out` as "unresolved (see warning)", as the key path does. Count the "several PDFs" message by `item_id`, not by citation key.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" ; code-check.md "One fact derived twice"

- **[severity: fragile]** tests/testthat/test-zotero.R:287. `crd_zot_src_lookup(character(), zotero_dir = dir)` passes no `library` and does not pin the option. `.crd_zot_library()` runs before the empty-keys return, so in a session with `cred.zotero_library` set, the test errors instead of returning 0 rows. The roxygen ("once per session with `options(cred.zotero_library = )`") and the vignette both recommend setting that option. Probe with `options(cred.zotero_library = "NewGraphEnvironment")`: `Zotero library "NewGraphEnvironment" not found…`. Every other no-`library` call in the file pins the option (`withr::local_options(cred.zotero_library = NULL)` at lines 20, 197, 209, 313), and the test at line 326 exists for exactly this case. Fix: add `withr::local_options(cred.zotero_library = NULL)` to this block.
  - **Rule:** code-check-r.md "A library call that dispatches on a global option is not a pure function"

- **[severity: fragile]** R/zotero.R:321 (message), R/zotero.R:256-258 (roxygen), CLAUDE.md:105. Fix 2 changed the URL rule, and three statements of it were not updated. All three still give the reason for the pick as "URL matching the item" / "the attachment whose URL is the item's own". When the item has no URL, the code now prefers *any* attachment that has a URL over an older one without. For the fixture's `nourl2019Parent`, the user-facing message says the file was taken for "URL matching the item" when its URL matches nothing. Only the internal `.crd_zot_attachments` roxygen (zotero.R:177-179) states the new rule. The test for this message (`bottoms2023Critical`) matches only the interpolated file names, so it cannot see the reason clause. Separately, CLAUDE.md:98 still says "Every lookup takes `library`". That is the claim round 1 (#5) corrected in the architecture tree. `crd_search()`'s key resolution (`.crd_zot_key_from_path`) takes no `library`, so the sentence remains in a second place.
  - **Rule:** code-check.md "An assertion that matches an interpolated value cannot see the claim around it" ; code-check.md "A guard's scope, escape hatches, and remedies"

## Checked and not raised

- The `library` formal shadows `base::library` ("Base name shadowing in formal args"). None of these functions calls `library()`, so nothing fails.
- The toy DB declares `itemDataValues.value TEXT NOT NULL`, while `helper-zotero.R` now declares it untyped, as Zotero does. The drift test compares column names only, so this type difference is not checked. No code path behaves differently, because every read is now cast.
- `paste0("file:", db_path, "?mode=ro&immutable=1")` breaks on a data directory containing `?`, `#` or `%`. This predates the branch: the old code built the same URI.
- When the first member of a collection (lowest itemID) is a note with a NULL key, RSQLite types the untyped column correctly (probe returned `chr`).
- `tibble::` is used in tests and R code but is not declared. This predates the branch (it is on main), and R CMD check findings are identical to main's.
- Zero-length paths were run or traced: an empty key set, an all-unresolved key set, a collection with no members, a collection whose members are all left out, and a DB with no collections. None raises a recycling error.
