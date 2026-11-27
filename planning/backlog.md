# cred backlog: move order

**Verified:** 2026-11-27 against 18 open issues · **Produced by:** a read of every unbatched open
issue body (`gh issue list --state open`) and its comments (none had any) · each older premise
checked against `origin/main` at 6b1874b (all 18 still hold: none disproved, none done) · open work
in downstream repos searched (`repo:<owner>/<repo> is:open cred`): a downstream corpus repo has open
issues waiting on #45 and on #53

How to use this file: `/backlog-sweep` writes it. Take the first move in **Moves** that is not
ticked and not **waiting**; `/planning-init <umbrella>` plans it, one phase per batch, one PR.
A move that waits only on other moves is `open`, with them in `waits on`; `**waiting**` is for
a blocker outside this file (the owner, another repo, a PR, a count).
When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue, naming the move it was split from, and places it nowhere in this file. The split may be recorded by number only in a `**Verified:**` paragraph, the move's state cell, its batch's carry line or an `## Order` table's `gate` cell, which `backlog_moves.sh unplaced` reads as provenance: the next `/backlog-sweep` reads the issue as unplaced, and folds it into a move other than the one it was split from.
`/gh-pr-merge` step 9c ticks the move on merge, and opens a move `**waiting** on PR #N` (this
repo's PR, and no other condition) when that PR merges; `/compact-prep` names the next, skipping a
move whose `waits on` names a move not yet ticked. A plan that defers one of its batches sets that
section's first line to `- [ ] Not yet in a move`: the tick leaves it open and says so, and `next`
names it once the move is done, for the next pass to place. A `NONE` from
`backlog_moves.sh next` that names batch sections means those batches have no move yet, and a
plain `NONE` is not the end either while an open issue is named nowhere here (`/compact-prep`
counts them): run `/backlog-sweep` again, the backlog is not finished.

## Moves

| move | umbrella | batches | state | lane | waits on | model |
|---|---|---|---|---|---|---|
| - [ ] 1 | #58 | 1, 2, 3, 4: check clean, ingest reporting, push manifest, search fallback (7 issues) | open: start here | A | — | sonnet |
| - [ ] 2 | #59 | 5, 6: audit match accuracy, review app grouping (4 issues) | open | B | 1 | opus |
| - [ ] 3 | #60 | 7, 8: store document identity and page, WAL-safe Zotero read (3 issues) | open | A | 1 | fable then opus |
| - [ ] 4 | #61 | 9, 10: docs, pre-commit hook (3 issues) | open | B | 2, 3 | sonnet |

Tracks are separate efforts, not moves: none in this repo.

## Order

| # | tracking | batch | issues | gate | why here |
|---|---|---|---:|---|---|
| 1 | #58 | Check clean: #32, #38 | 2 | none: `Imports: tibble`, `Suggests: openxlsx`, ASCII strings, then drop `error-on` | one `R CMD check` run verifies all three warnings, and `error-on` goes only once all are cleared |
| 2 | #58 | Ingest reporting on ragnar 0.4.0: #51, #49 | 2 | measure whether 0.4.0's progress message handles the file names that got it turned off | both live in `.crd_store_ingest()`, tested against one ragnar 0.4.0 ingest |
| 3 | #58 | Push manifest output: #54, #26 | 2 | the dry run prints this store's entry by default, the full manifest behind an argument | both change what `crd_store_push()` writes or prints, one test file |
| 4 | #58 | Search fallback: #47 | 1 | option 1, 2 or 3 of the issue (changes a public default) | a small change to `crd_search()`, in the store-side PR |
| 5 | #59 | Audit match accuracy: #36, #9 | 2 | a new `weak` status and/or new `review_flag` values, stored in every audit CSV | both change what an automated verdict means, and meet in `crd_aud_score()` |
| 6 | #59 | Review app grouping: #21, #18 | 2 | the `claim_group` column (stored in the CSV) and which tiers are in scope | one review-app module; grouping also flows through `crd_aud_write`, `crd_aud_upd`, `crd_aud_score` |
| 7 | #60 | Store document identity and page: #53, #56 | 2 | the new per-document tables or columns (stored data); measure first whether the markdown reader's text aligns with pdftools' pages | both add a record per document at ingest, so one rebuild of every store pays for both |
| 8 | #60 | WAL-safe Zotero read: #45 | 1 | export a guarded-copy reader, or only document quitting Zotero before a build | the Zotero read layer batch 7 extends |
| 9 | #61 | Docs: #34, #17 | 2 | none | one pkgdown build and one review copy; the vignette describes the app as batch 6 leaves it |
| 10 | #61 | Pre-commit hook: #3 | 1 | the default audit CSV path; block only on newly staged `no_match` rows | blocks on the statuses batch 5 may redefine |

### 1. Check clean

- [ ] Carried by move 1, #58

**Touches:** `DESCRIPTION`, `R/store.R`, `R/audit.R`, `.github/workflows/R-CMD-check.yaml`

#32 and #38 describe the same three warnings; #38 adds removing `error-on` once they are cleared.
`Imports: tibble` (`crd_search()` and the audit functions return tibbles), `Suggests: openxlsx`
(a guarded optional path in `crd_aud_fmt_xlsx()`), and the em dashes in string literals in
`R/store.R` and `R/audit.R` replaced by ASCII.

### 2. Ingest reporting on ragnar 0.4.0

- [ ] Carried by move 1, #58

**Touches:** `R/store.R`, `tests/testthat/test-store-build.R`, `CLAUDE.md`

#51 reads ragnar 0.4.0's `ingest_summary` for each failed document's reason, keeping the
`documents` table as the record of what was ingested. #49 turns ragnar's per-file progress back
on for builds and updates if 0.4.0 prints file names safely, or records what still fails.

### 3. Push manifest output

- [ ] Carried by move 1, #58

**Touches:** `R/store.R`, `tests/testthat/test-store-push.R`

#54: the dry run prints only the pushed store's entry and the list of store names, so a logged
dry run carries no other store's provenance. #26: a `notes` field written when given and
preserved by the merge when not.

### 4. Search fallback

- [ ] Carried by move 1, #58

**Touches:** `R/store.R`, `tests/testthat/test-store.R`

#47: a degraded hybrid search warns only once per reason and store, so later degraded calls
return BM25 rows silently. The gate picks one of the issue's three options.

### 5. Audit match accuracy

- [ ] Carried by move 2, #59

**Touches:** `R/rmd.R`, `R/sentence.R`, `R/audit.R`, `tests/testthat/test-rmd.R`, `tests/testthat/test-sentence.R`, `tests/testthat/test-score.R`

#36: on hard-wrapped Rmd, `crd_cit_ext_rmd()` returns the line, not the sentence, so `auto` rows
match unrelated passages; unwrap paragraphs before splitting sentences, and consider a stricter
`min_score` or a `weak` status. #9: check `no_match` rows against the abstract too, as a
`review_flag` that `crd_aud_score()` reads.

### 6. Review app grouping

- [ ] Carried by move 2, #59

**Touches:** `R/review.R`, `R/audit.R`, `tests/testthat/test-audit.R`

#21: a `claim_group` for rows sharing a paraphrase, kept through `crd_aud_upd()`, sorted together
in the app, with later tiers for a grouped view and group risk flags. #18: the app reloads its
CSV when another session rewrites it.

### 7. Store document identity and page

- [ ] Carried by move 3, #60

**Touches:** `R/store.R`, `R/zotero.R`, `tests/testthat/test-store-build.R`, `tests/testthat/test-store-update.R`, `tests/testthat/test-zotero.R`

#53: record each document's parent item key, library and item version at ingest, a resolve
check, and the parent key and library in `crd_search()`. #56: record where each PDF page starts
in the stored text, so `crd_search()` returns `page` and `page_end`. A downstream corpus repo
waits on #53 to re-key its stores.

### 8. WAL-safe Zotero read

- [ ] Carried by move 3, #60

**Touches:** `R/zotero.R`, `tests/testthat/test-zotero.R`

#45: Zotero 10 keeps its database in WAL mode, and the `immutable=1` read misses commits not yet
checkpointed, so a build soon after a sync can use an older library. A downstream corpus repo
waits on the fix.

### 9. Docs

- [ ] Carried by move 4, #61

**Touches:** `README.Rmd`, `README.md`, `vignettes/`

#34: the README describes corpus search beside the audit, and drops the shipped roadmap item.
#17: an audit-trail vignette on the CSV-as-state, git-as-history workflow.

### 10. Pre-commit hook

- [ ] Carried by move 4, #61

**Touches:** `inst/hooks/`, `R/hook.R`, `tests/testthat/test-hook.R`

#3: `crd_hook_install()` and a hook template that runs `crd_aud_upd()` on commit and blocks only
when newly staged rows are `no_match`.

## Singles

- #2: pre-draft passage retrieval, mostly covered by `crd_search()` now. Its open asks are a
  page for each passage (batch 7), docx sources and a formatter for drafting prompts. Re-scope
  it after move 3 lands, or close it on the owner's word.

## Closed and transferred

- none in this pass.
