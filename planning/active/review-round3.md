# Code-check round 3 — cred#58 branch (b18063f vs origin/main a1866c9)

## Checklist read

- code-check-r.md, read in full: "`$` on a list partial-matches, so a longer sibling key answers for a missing one"; "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"; "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared". Index lines read for the rest; about 160 headings not read in full (spatial, shell, glue, xml, Postgres and similar, none of which this diff uses).
- code-check.md: prose of every H3 under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; and the remaining mechanisms skimmed), table rows skipped. Rules-that-stand-alone and Security: index only (about 30 not read in full).
- code-check-shell.md: index only; nothing read in full (the shell change is one YAML deletion). About 110 headings not read.
- code-check-spatial.md: index only; nothing applicable. About 120 headings not read.

## Probes run

- Partial match through the merge's carry-over logic, R 4.5: an old entry `list(md5 = "x", notes_private = "internal only")` merged with `list(md5 = "y")` yields `list(md5 = "y", notes = "internal only")`.
- `tests/testthat/test-store-push.R` in my own worktree of b18063f (NOT_CRAN=true): 0 failed, no error, 114 passed.
- Retry path: `entry` is not mutated by `.crd_manifest_merge()` (it is pure and R copies on modify), so each re-merge reads the fresh manifest and carries *its* notes when the caller gave none, or the caller's notes when given. Correct.
- JSON round trip (`fromJSON(simplifyVector = FALSE)` and `write_json(auto_unbox = TRUE, null = "null", na = "null")`): `""` round-trips as `""`; a hand-written array note reads as a list and is written back as an array (auto_unbox does not unbox a list); `NA` is refused by `chk_string`; a JSON `null` note reads as NULL and is dropped from the entry, which is harmless.
- ragnar 0.4.0's `ingest_summary`: `tibble(path = as.character(paths), status, n_chunks, message)`, set on the returned store. Matches what `.crd_store_ingest()` reads; its `ifelse()` test is never NA (`&` with `%in%` and `!is.na`), and a zero-length `unsaid` gives `character(0)`.
- `tools:::.check_package_ASCII_code()` on the tree: clean. `tools:::.check_packages_used_in_tests()`: clean. flows `r-cmd-check.yaml@v1` defaults `error-on` to `'"warning"'`, so dropping the override does gate on warnings, as NEWS says.

## Findings

- **[severity: fragile]** R/store.R:3192 — `old$notes` (and `entry$notes`) use `$` on a list parsed from JSON, which partial-matches. If the old entry in the manifest has no `notes` key but has a key that starts with `notes` (for example `notes_private`; the issue says at least one entry was merged into `log.json` by hand), `old$notes` returns that field's value. The merge then writes it into the new entry as `notes`, a field the pusher never set, while dropping the original key, because the rest of the entry is replaced. Probe above confirms it. That breaks the "replaced whole except notes" contract stated in roxygen, CLAUDE.md and NEWS for exactly the unknown shapes the merge says it tolerates. Fix: read `old[["notes"]]` and `entry[["notes"]]`. The write side, `entry$notes <- notes`, is an assignment and is not affected.
  - **Rule:** code-check-r.md "`$` on a list partial-matches, so a longer sibling key answers for a missing one"

No other issues. The retry loop, the dry-run preview (which shows only the pushed store's merged entry, notes included), the `fallback` abort path (an abort raised inside the `tryCatch` error handler escapes it, and there is no outer handler), the `progress` pass-through and the DESCRIPTION changes all check out.

index, diff and changed files read from file
