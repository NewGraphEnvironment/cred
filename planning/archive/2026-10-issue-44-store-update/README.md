## Outcome

Added `crd_store_update()`, which brings a built ragnar store up to date with Zotero: sources resolve as in
`crd_store_build()`, documents are matched by origin id (the `storage/<KEY>/<file>` tail, so a store built on
another machine updates cleanly), and changed PDFs are seen by an md5 that build and update now record in a
`cred_sources` table inside the store. Only new and changed PDFs are read and embedded; documents whose source
no longer resolves are removed; the work happens on a copy renamed over the store when finished, so a failure
or an empty result leaves the store untouched, and a result that changes nothing is not written. What was
learned: ragnar's own skip saves cred nothing (cred's `prepare` embeds before ragnar compares); ragnar 0.3.1's
foreign key makes a transactional delete fail while the development ragnar, which CI installs, does not; and
most review findings came from one mechanism, code borrowed from build or connect still assuming that caller's
situation (exists = readable; connect's `check_model`, manifest and BM25 advice). Durable facts are in
[`research/ragnar-store-update.md`](../../../research/ragnar-store-update.md).

## Measurement

- Plan review: 16 findings; 2 blockers, both real (FK on 0.3.1, reproduced independently before the review
  arrived; an unreadable same-origin replacement recorded as replaced, reproduced by a red test).
- Mutation table: 17 guards restored one at a time; 16 red at once, one (the removal-only index rebuild)
  survived the BM25 hit checks and was pinned by comparing BM25 scores with a fresh build (`findings.md`).
- `/code-check branch`: 3 rounds, 5 findings, all fixed with a test red first; ended by enumerating the 16 cred
  functions the update calls.
- Final runs: `devtools::test()` 896 passed, 0 failed (ragnar 0.3.1); store tests 300 passed under ragnar
  0.3.1.9000; `R CMD check` 0 errors, warnings only those on main (#32, #38).
- The speed-up itself is not measured yet: see Owed.

## Owed

- Time a real one-paper update against the 26-minute rebuild on the shared store, with the store file size before and after (duckdb does not shrink a file after deletes), and put the measured numbers in the archive README

Closed by: PR (see branch `44-crd-store-build-no-way-to-add-or-drop-a`)
