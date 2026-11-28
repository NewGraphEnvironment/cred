## Outcome

Backlog move 1 (#58) cleared seven small store and check defects in one PR, across four batches.
R CMD check now passes with no warnings, and CI fails on a new one (#32, #38). To get there,
tibble went into Imports and openxlsx into Suggests, 13 string literals lost their em dashes, and
`Depends: R (>= 4.1.0)` was added, because R CMD build warned that the native pipe needs it.
`.crd_store_ingest()` now takes a crashed worker's reason from ragnar 0.4.0's `ingest_summary`
(#51). ragnar's per-file progress is back for interactive builds and updates (#49).
`crd_search()`'s BM25 fallback is opt-in (#47): by default a hybrid search that cannot embed the
query stops, with the `vss` path's error classes. `crd_store_push()` takes `notes`, which a
later push without them keeps (#26). #54 was an outside contributor's PR #55. It was reviewed
here, and its NEWS entry was moved out of a section that had already shipped. Once the owner
approved its CI, it was merged and released as v0.9.0 before batch 3.

What was learned:
- ragnar sets `ingest_summary` on the store it **returns**, not on the one passed in, so the
  value of the ingest call has to be kept.
- A plan review caught the plan naming the warning class (`cred_retrieval_fallback_*`) for the
  new error path. The class `vss` raises is `cred_retrieval_error_*`.
- Code-check round 3 caught `$` partial matching in the notes carry: an old `notes_private` key
  would answer for `notes`. Round 4 enumerated every `$` read in the diff and found nothing
  unsafe that the branch adds.

## Measurement

- R CMD check, before and after: 3 warnings, then 0. On the final head (`--no-manual`):
  0 errors, 0 warnings, 3 notes (`.lintr`, `README.html`, `.data`), all out of scope.
- Progress output (#49):
  - Method: a scratch ingest under ragnar 0.4.0 with `progress = TRUE`, on six files whose
    names carry cli brace markup, one of them a name that would create a file if evaluated.
  - Result: all six printed literally on their `ingested:` lines, and the marker file was
    absent.
  - What changed because of it: progress comes back, as `progress = rlang::is_interactive()`.
- Full suite at ee8ef01: 1034 passed, 0 failed, 2 skipped (docx).
- Mutation checks: each new guard was shown to fail with its defect restored.
  - Update progress pass-through hard-coded to `FALSE`: 1 test failed.
  - Notes carry dropped: 2 failed.
  - `old$notes` restored: 1 failed.
- Code-check ended clean after 4 rounds (`review-verdict.md`). Round 3's single finding was in
  new code, not inside an earlier fix.

Closed by: the PR for branch `58-backlog-move-1-store-and-check-upkeep-32`
