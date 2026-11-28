# Findings — Backlog move 1: store and check upkeep (#58)

## Issue context

**If we do it:** R CMD check gates on warnings, ingest failures are read from ragnar's own report, the push dry run stops printing other stores' provenance, and a degraded search can no longer pass as a semantic one. **If we never do:** each of these seven stays a small known defect, and new warnings keep landing unseen.

Planned from `planning/backlog.md`. Run `/planning-init <this issue>`: one phase per batch, one PR. If the plan finds a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue naming move 1.

## Batch 1: Check clean
Why here: one `R CMD check` verifies all three warnings, and `error-on` can only go once they're all cleared. Touches: `DESCRIPTION`, `R/store.R`, `R/audit.R`, `.github/workflows/R-CMD-check.yaml`. Decided at the gate: nothing; the fixes are the ones #32 lists.

| issue | title |
|---|---|
| #32 | R CMD check: 3 pre-existing WARNINGs |
| #38 | Clear the R CMD check WARNINGs so CI gates on warnings |

## Batch 2: Ingest reporting on ragnar 0.4.0
Why here: both sit in `.crd_store_ingest()` and are tested against one ragnar 0.4.0 ingest. Touches: `R/store.R`, `tests/testthat/test-store-build.R`, `CLAUDE.md`. Gate: measure whether 0.4.0's progress message handles the file names that got it turned off, before turning it on.

| issue | title |
|---|---|
| #51 | Use ragnar 0.4.0's ingest_summary for failed documents |
| #49 | Turn ragnar's ingest progress back on if ragnar 0.4.0 fixed it |

## Batch 3: Push manifest output
Why here: both change what `crd_store_push()` writes or prints. Touches: `R/store.R`, `tests/testthat/test-store-push.R`. Gate: the dry run prints this store's entry by default, with the full manifest behind an argument.

| issue | title |
|---|---|
| #54 | crd_store_push() dry run prints every store's manifest entry |
| #26 | crd_store_push(): a notes field the manifest merge preserves |

## Batch 4: Search fallback
Why here: a small change to `crd_search()` in the same file. Touches: `R/store.R`, `tests/testthat/test-store.R`. Gate: option 1, 2 or 3 from #47, since it changes a public default.

| issue | title |
|---|---|
| #47 | crd_search(): make the BM25 fallback opt-in, or warn on every degraded call |


## R CMD check after batch 1 (2026-11-27)

`devtools::check(args = "--no-manual")` on 57e0019: 0 errors, 0 warnings, 3 notes (`.lintr` hidden,
`README.html` at top level, `.data` global binding), all out of scope. R CMD build also warned that
the code uses the native pipe and needs R >= 4.1.0, so DESCRIPTION now declares `Depends: R (>= 4.1.0)`.

## ragnar 0.4.0's progress line and file names (#49), measured 2026-11-27

A scratch ingest under ragnar 0.4.0, duckdb 1.5.6 and R 4.5.2, with `progress = TRUE`, used six
files whose names carry cli brace markup, including one that would run code if evaluated. All six
printed literally on their `ingested:` lines, and nothing was evaluated (a marker file the
evaluating name would create was absent). ragnar 0.4.0 writes the line as
`cli_alert_info("ingested: {origin}")`, which substitutes the value rather than parsing it.
The same run confirmed that `ingest_summary` reaches the caller on the returned store, with
status `ok` for each file. The probe stays in the session scratchpad.
Progress comes back for interactive sessions only, because each line names a full local path.

## PR #55 review

See `review-pr55.md`. Mergeable once its NEWS bullet moves out of the released 0.8.0 section.
The merge waits for the owner's word.

## #47: who calls crd_search(), and what else said hybrid falls back (2026-11-27)

`gh api search/code q='org:NewGraphEnvironment "crd_search("'` (default branches): the only code
caller outside cred is knowledge's `scripts/0150-store.R` (`ACTION=query`), which now errors where
it printed BM25 rows with no embedding service. The org's shared conventions already treat a `bm25` row from a
hybrid search as a failed search. Neither README nor the vignette calls `crd_search()`.
Sentences rewritten in the sentence grep: `crd_search` details, its "Diagnosing a fallback"
section and frequency line, a code comment, `.crd_retrieval_abort`, `.crd_retrieval_failure`,
`.crd_store_probe_id`, the `crd_store_connect` roxygen (two places) and its mismatch error's
`check_model = FALSE` advice, `helper-store.R`, and two CLAUDE.md bullets.

## Errors Encountered

| Error | Resolution |
|-------|------------|
