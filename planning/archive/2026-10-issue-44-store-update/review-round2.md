# Code-check round 2: #44 branch diff (bed2089...HEAD, planning/ excluded)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms` was read, with the table rows
  skipped. Of "Rules that stand alone", Security, and Spreadsheets and PDFs, only the index lines
  were read: none of them names a tool or shape this diff uses.
- **code-check-r.md**: 17 sections were read in full: "`on.exit()` at a script's top level never
  fires", "`$` on a list partial-matches", "A database driver's value is not a base R type",
  "`paste()` with a zero-length argument", "Under `R CMD check`, tests run from a temp dir",
  "`dbConnect(SQLite(), path)` CREATES the file", "`vapply(..., USE.NAMES = FALSE)`",
  "`tryCatch(warning = )` DISCARDS the value", "`match()` treats NA as a matchable VALUE",
  "`expect_message(expr, regexp)` checks only the FIRST condition", "`data.frame()` recycles a
  scalar", "`tempfile()` lives in the session tempdir", "A `pkg::` call in a test",
  "`c(name = x)` keeps `x`'s own name", "A `function(...)` mock hides arguments", "`tryCatch()`
  nests its handlers", and "`fs::file_move()` onto an existing directory". The other headings
  (about 100) were checked against their index lines only.
- **code-check-shell.md**, **code-check-spatial.md**: index only, 0 sections read. The diff has no
  shell code and no spatial code.

Probes were run in a copy of the repo
(`/private/tmp/claude-501/-Users-airvine-Projects-repo-cred-a/829770c7-1d55-4024-ae02-1f922609273f/scratchpad/review2-copy`)
with ragnar 0.3.1, duckdb 1.5.2 and testthat 3.3.2. The checkout was not touched.

- `test-store-update.R` at ae3b5e7: 23 of 23 tests pass, with no failures and no errors.
- **The round-1 fix holds and its guard fires.** With `here <- !is.na(md5)` mutated back to
  `here <- exists`, the test "a stored file this machine cannot read is kept like a missing one"
  goes red (error = TRUE). After the fix, every NA source in `crd_store_update()` is closed:
  `replaced`, `to_ingest` and `new_rec()` read only rows where `here` is TRUE, and `keep_old` reads
  only rows where `!is.na(was)`.
- duckdb runs a `DELETE ... WHERE doc_id = ?` once for each element of a parameter vector longer
  than one (checked with 2 ids). So the two-statement delete removes every dropped document, not
  only the first. No test drops more than one document at a time; this probe covers that case.

## Findings

- **[severity: fragile]** R/store.R:2375 (`crd_store_update()` calls
  `.crd_check_store_embedding(store, name = basename(store_path))`), and the remedy text at
  R/store.R:345-352. When the update meets a width mismatch, it stops correctly, before anything is
  copied. But the error it raises was written for `crd_store_connect()`, and two of its claims are
  wrong when the caller is `crd_store_update()`. Reproduced by swapping in `.crd_test_embed_narrow`
  as the store's embed and running an update that adds a file. The message ends:

  ```
  ...looking healthy, and the md5 compare cannot see it: this store has exactly
  the bytes the manifest recorded.
  ...
  or rebuild with crd_store_build(). BM25 retrieval needs no embedding and is
  unaffected, so pass check_model = FALSE to open the store anyway.
  ```

  `crd_store_update()` has no `check_model` argument. A user who follows the last remedy gets
  `unused argument`. Even if the argument existed, "open the store anyway" would be the wrong
  advice: the update would then embed new chunks at the wrong width. The sentence "this store has
  exactly the bytes the manifest recorded" asserts something the update never checked. A local
  store that is being updated has often been updated before and not yet pushed, and the update's
  own success message says its md5 no longer matches the manifest. The probe-failure branch just
  above it (`.crd_embed_remedy(..., context = "connect")`, line 2372) has the same problem in a
  milder form: its `unknown` remedy says "BM25 needs no embedding and is unaffected", which does
  not apply to an update that cannot add anything. Nothing tests either message on the update path.
  The test "a removal needs no embedder…" only matches the opening line, "could not embed, so
  nothing can be added".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

## Considered, not flagged

- **Within-item dedupe combined with keep-missing.** `.crd_zot_pdf_sources()` dedupes identical
  bytes only among files that exist locally. Suppose a store is built where both copies of a
  duplicated attachment exist, so the second copy is deduped out. It is then updated where only
  the second copy is present. The update keeps the stored first copy (missing here) and adds the
  second, so that item's text is stored twice until the first copy syncs. This follows from the
  accepted keep-missing divergence, so it is not re-flagged. It is noted because "answer every
  query twice" is exactly what the dedupe exists to prevent.
- A store with no record, updated on a machine holding none of its files, is rewritten once to
  carry an empty record, and is "current" after that. This is harmless and does not repeat.
- The early "Store is current" exit and the exit after ingest both compare the record as
  `paste(origin_id, md5)`. An md5 is always 32 hex characters, so a space inside a linked path
  cannot make two different pairs read the same.
