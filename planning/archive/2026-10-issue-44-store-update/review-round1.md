# Code-check round 1: #44 branch diff (bed2089...HEAD, planning/ excluded)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, table rows skipped. Of the
  "Rules that stand alone", Security and PDF sections, only the index lines were read: none of
  them names a tool or shape this diff uses.
- **code-check-r.md**: 12 sections read in full: "A database driver's value is not a base R type",
  "`paste()` with a zero-length argument", "Under `R CMD check`, tests run from a temp dir",
  "`dbConnect(SQLite(), path)` CREATES the file", "`match()` treats NA as a matchable VALUE",
  "`[[` on a named ATOMIC vector", "`tryCatch()` nests its handlers", "`data.frame()` recycles a
  scalar", "A `function(...)` mock hides arguments", "`fs::file_move()` onto an existing
  directory", "`tempfile()` lives in the session tempdir", "`ifelse()` with an all-NA test". The
  remaining ~100 headings were checked against their index lines only.
- **code-check-shell.md**, **code-check-spatial.md**: index only, 0 sections read. The diff has no
  shell and no spatial code.

Both findings were reproduced in a copy of the repo
(`/private/tmp/claude-501/-Users-airvine-Projects-repo-cred-a/829770c7-1d55-4024-ae02-1f922609273f/scratchpad/review1-copy`),
using ragnar 0.3.1 and duckdb 1.5.2, with probe tests added to the end of
`test-store-update.R`. The checkout was not touched.

## Findings

- **[severity: bug]** R/store.R `crd_store_update()`, at `md5[here] <- unname(tools::md5sum(paths[here]))`
  and the `replaced` / `new_rec()` lines that follow it. The code treats "the file exists" as
  meaning "its md5 was read". `tools::md5sum()` returns `NA` for a file that exists but cannot be
  read: no read permission, or a file replaced between `file.exists()` and `md5sum()`. That `NA`
  then spreads in two ways:
  1. **The file is stored and has a record.** `replaced` becomes `NA`, so `paths[added | replaced]`
     puts `NA_character_` into `to_ingest`. ragnar's own `check_character(allow_na = FALSE)` then
     aborts the whole update with `` `paths` can't contain NA values ``. Reproduced: build keyA and
     keyB, `chmod 000` keyB, then update with keyA, keyB and keyC. The update errors, keyC is never
     added, and the store is unchanged.
  2. **The file is stored but has no record** (a store built before records existed, or a build
     whose record write failed). `replaced` is FALSE and `take` is TRUE, so `new_rec()` puts an
     `NA` md5 into the record. The other files are ingested into the copy first. After that,
     `.crd_sources_write()` fails on the `NOT NULL` column, with duckdb's
     `TransactionContext Error: Current transaction is aborted`. Reproduced: keyC was read and
     embedded, then the copy was thrown away.

  Neither case loses data: the update fails toward leaving the store as it was. But one
  unreadable stored PDF blocks every update of that store, with an error that does not name the
  file. `crd_store_build()` given the same file skips it with a warning and goes on. Fix:
  set `here <- !is.na(md5)` after hashing (an unreadable file is then kept the way a missing one
  is), or report it by name.
  - **Rule:** code-check.md "A guard that fails toward pass" ; code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** R/store.R, roxygen of `crd_store_update()`, "What a failure costs"
  paragraph (and the same text in man/crd_store_update.Rd). The paragraph says: "When nothing has
  changed, or nothing that changed could be read, the store is not written at all." This is false
  for a stored file whose bytes changed and which can no longer be read. The update drops its old
  document, writes the store and changes the store's md5 (the test "a changed file that can no
  longer be read…" asserts `removed: 1`). The roxygen's own "How a changed file is seen"
  paragraph says so too ("loses its document"). The sentence holds only for a new file that cannot
  be read. A reader relying on it would expect the store's md5, and so its match with the
  manifest, to survive an update that read nothing. The CLAUDE.md wording ("nothing ingested or
  dropped, record unchanged") is the accurate one.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"
