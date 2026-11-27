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


## Errors Encountered

| Error | Resolution |
|-------|------------|
