# Task: Backlog move 1: store and check upkeep (#32, #38, #51, #49, #54, #26, #47) (#58)

**If we do it:** R CMD check gates on warnings, ingest failures are read from ragnar's own report, the push dry run stops printing other stores' provenance, and a degraded search can no longer pass as a semantic one. **If we never do:** each of these seven stays a small known defect, and new warnings keep landing unseen.

## Context

Move 1 of `planning/backlog.md` collects seven small defects into one PR. R CMD check has
three warnings, so CI gates only on errors (#32, #38). The ingest takes failure reasons from
worker warnings, and ragnar's progress output is still switched off (#51, #49). The push dry
run prints every store's provenance (#54), and the manifest has no notes field (#26). A
degraded hybrid search can return BM25 rows silently (#47). Branch
`58-backlog-move-1-store-and-check-upkeep-32` will be cut from origin/main at e286d8b. The
umbrella #58 is claimed after approval.

## Decided at the gate (owner, 2026-11-27)

- **#47: option 1.** `crd_search()` gains `fallback = c("error", "bm25")`, defaulting to
  `"error"`. A changed public default means `Bump: minor`.
- **#54: merge PR #55 (LeonidasZhak) as its own PR first.** It does exactly what the gate
  asks: the dry run prints this store's entry, and `show_full_manifest = TRUE` prints the
  whole manifest. This branch reviews #55. The merge waits for the owner's word, asked
  mid-run. Batch 3 here carries only #26 and starts after #55 is merged.
- Mechanism, decided in the plan:
  - **#49:** progress becomes an argument, `progress = rlang::is_interactive()`, on
    `crd_store_build()` and `crd_store_update()`. Each per-file progress line prints an
    absolute local path. A non-interactive run writes those lines to logs that get
    committed, which is #54's concern again.
  - **#47:** with `"error"`, a failed embed aborts with the
    `cred_retrieval_error_<reason>` / `cred_retrieval_error` pair that the `vss` path already
    raises, so one handler covers both methods. (Corrected by the plan review, B1: the plan had
    named the warning class.) `fallback` is ignored under `vss` and `bm25`.
  - **#49:** `.crd_store_ingest()` keeps its own default of `FALSE`. Only the two exported
    functions default to interactive.
  - **#26:** `notes = ""` writes `""`. A note is replaced, never field-merged.
  - **#49 probe:** the measurement uses file names with brace markup. The probe file names
    stay in the scratchpad and are not committed. Public text says only what ragnar 0.4.0's
    NEWS says, that origins are printed literally.

## Phase 1: Review PR #55 (outside contributor, #54)
- [x] Run `/code-check` on #55's diff in a scratch worktree of its head. Check that the
      `held` env refactor keeps `prepare`'s `topenv()` at `baseenv()` (the structure test)
      and that it is needed for zero lints. Check that its NEWS bullet merges cleanly
      against main at v0.8.1.
- [x] Write the findings to `planning/active/review-pr55.md`. Ask the owner to merge it
      (via `/gh-pr-merge`) or say what to raise on #55. Go on with Phases 2-4 while the
      answer is pending.

## Phase 2: Check clean (batch 1: #32, #38)
- [x] Before building: `bash "$T/skills/_shared/members_check.sh" "$(git remote get-url origin)" 58 <branch> --batch 1`
- [x] `DESCRIPTION`: `Imports: tibble` (returned by `crd_search()`, `R/zotero.R`,
      `R/docx.R`, `R/pdf.R`, `R/rmd.R` and used in tests), `Suggests: openxlsx` (the guarded
      path in `crd_aud_fmt_xlsx()`)
- [x] Replace the 13 non-ASCII string literals with ASCII `--`: `R/audit.R` 316, 472 and
      603; `R/store.R` 186, 611, 633, 3054, 3065, 3197, 3326, 3337, 3388 and 3397 (from
      `getParseData` `STR_CONST`). Comments stay. No test matches an em dash.
- [x] `tools:::.check_package_ASCII_code(".")` comes back empty, and `devtools::check()`
      shows 0 warnings
- [x] Remove `error-on: '"error"'` and its comment from `.github/workflows/R-CMD-check.yaml`

## Phase 3: Ingest reporting on ragnar 0.4.0 (batch 2: #51, #49)
- [x] Before building: `members_check.sh ... 58 <branch> --batch 2`
- [x] #49, measured first: run a scratch ingest under ragnar 0.4.0 with `progress = TRUE` on
      files whose names carry brace markup. Confirm that each name prints literally and that
      nothing is evaluated. 0.4.0 uses `cli_alert_info("ingested: {origin}")`. Record the
      verdict in `findings.md`, with no probe names.
- [x] If the measurement passes: add `progress = rlang::is_interactive()` to
      `crd_store_build()` and `crd_store_update()` and pass it to `.crd_store_ingest()`
      (`R/store.R` ~2353, ~2656). Replace the test that fails when progress is on with one
      that checks the argument reaches ragnar, plus an end-to-end ingest of a file named
      with harmless markup (`{.strong x}`) whose line prints literally. Update the roxygen
      (~1967, ~2265) and the `CLAUDE.md` bullet "ragnar's progress output stays off". If the
      measurement fails, record what still fails, keep progress off, and file nothing
      upstream without the owner's word.
- [x] Plan review folded in (review-plan.md): #51 and #49 land together, written to the
      post-#51 contract (O1). The crashed-worker mock builds `ingest_summary` (B3), with a
      message unlike any warning text (AC1). A missing path that was not an error gets a reason
      naming ragnar's status (G2). The ingest roxygen and the CLAUDE.md "keeps it by path"
      bullet are updated (G3). The `{.strong x}` test collects every message (G6).
      test-store-build.R:426 and the :482 mock are changed deliberately (G7).
- [x] #51: keep `ragnar_store_ingest()`'s return value and read its `ingest_summary`
      attribute. The reason for an unreported failure is `message` where
      `status == "error"`. Drop the `worker_errors` map and keep the muffling handler. The
      `documents` table still decides what was ingested. Tests in
      `tests/testthat/test-store-build.R`: the crashed-worker test stays, and the reason
      equals the summary's message.

## Phase 4: Search fallback (batch 4: #47)
- [x] Before building: `members_check.sh ... 58 <branch> --batch 4`
- [x] `crd_search(fallback = c("error", "bm25"))`, matched with `rlang::arg_match()`. With
      `"error"`, abort with the reason-subclassed error the `vss` path raises (~1306-1318,
      `.crd_retrieval_fallback_msg()`). The message says to pass `fallback = "bm25"` for
      keyword-only results. `"bm25"` keeps today's warning (once per reason and store).
- [x] Update existing fallback tests to pass `fallback = "bm25"` or to expect the error. Add
      a test where two degraded calls both error. Update `?crd_search` "Diagnosing a
      fallback", the vignette and README wherever they rely on the silent fallback (grep
      `crd_search(`), and any internal caller.
- [x] Plan review folded in (review-plan.md): `.crd_retrieval_abort()` takes `method`, and
      its tail no longer claims hybrid degrades (B2). Tests that pass `fallback = "bm25"`:
      test-store-fallback.R 487, 505, 531, 550, 588, 602, 620, and
      test-store-embed-check.R 490 (G1). Grep the sentence for every claim that hybrid falls
      back or warns once (G4: `crd_search` details and a code comment, `.crd_retrieval_failure`,
      `.crd_store_probe_id`, `crd_store_connect` and its `check_model = FALSE` advice,
      helper-store.R, two CLAUDE.md bullets). Neither the vignette nor README calls
      `crd_search()`. Grep the org for `crd_search(` callers and name the break in NEWS (A5).
- [x] NEWS: the changed default leads the entry. PR body: `Bump: minor`.

## Phase 5: Push manifest notes (batch 3: #26; #54 is left to #55)
- [x] Before building: `members_check.sh ... 58 <branch> --batch 3 --skip 54`. Start only
      after #55 is merged, then `git merge origin/main`. If #55 is not merged once Phases
      2-4 are done, ask again rather than build on a conflicting base.
- [x] Add `notes = NULL` to `crd_store_push()` (`chk_string` when given), written into the
      entry. `.crd_manifest_merge()` keeps the existing entry's `notes` when the new entry
      has none. Document that `notes = ""` clears a note.
- [x] Tests in `tests/testthat/test-store-push.R`: a pure merge test where notes survive a
      push without them, while `built_by` from the old entry does not (AC2). A dry-run test
      whose preview shows a note preserved from the existing manifest (AC3). An atomic
      existing entry does not crash the merge (G8). The `.crd_manifest_merge` roxygen and the
      CLAUDE.md "merged, never replaced" bullet are updated.

## Owed at the end (reported, done after merge)

None.

## Validation
- [ ] Tests pass (`devtools::test()`, ragnar 0.4.0 installed)
- [ ] `lintr::lint_package()` 0 lints; `devtools::document()`; `pkgdown::check_pkgdown()`
      (new arguments only, no new exports)
- [ ] `devtools::check()` 0 errors, 0 warnings. CI's R-CMD-check is green without `error-on`
- [ ] `/code-check branch` clean (three-round floor)
- [ ] PWF checkboxes match landed work. `/planning-archive`, then `/gh-pr-push`, whose body
      carries `Closes #58`, `#32`, `#38`, `#51`, `#49`, `#47`, `#26` (#54 closes with #55)
      and `Bump: minor`

How each change is proved: the check output for batch 1, CI going green after `error-on` is
removed, the scratch probe and an end-to-end mirai ingest for batch 2, the condition-class
tests for batch 4, and the pure-merge and dry-run tests for batch 3.

