# Code-check round 3: crd_store_update() (#44)

Base bed2089, HEAD a64d6b4. The update suite was run on a copy
(`scratchpad/review3-copy`): 25 tests, 0 failed, 0 errors, 0 skipped. Probes were run there
as an extra test file, never in the checkout.

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, with table rows skipped.
  From `## Rules that stand alone`, I used only the index lines. I did not read the remaining
  23 H3s in full.
- **code-check-r.md**: I read these sections: "`$` on a list partial-matches", "`match()` treats
  NA as a matchable VALUE", "`paste()` with a zero-length argument", "`data.frame()` recycles a
  scalar", "`dbConnect(SQLite(), path)` CREATES the file", "`tryCatch()` nests its handlers",
  "`tryCatch(warning = )` DISCARDS the value", "Under `R CMD check`, tests run from a temp dir
  against the INSTALLED package", "A `pkg::` call in a test passes `devtools::test()` and fails
  `R CMD check` if `pkg` is undeclared", "A `function(...)` mock hides arguments", "`expect_message(expr,
  regexp)` checks only the FIRST condition", "`expect_false(identical(x, y))` cannot fail",
  "`c(name = x)` keeps `x`'s own name", "`vapply(..., USE.NAMES = FALSE)`" and "Base name shadowing
  in formal args". That is 15 of 115; I did not read the other 100.
- **code-check-shell.md**: none read (0 of 70). The diff contains no shell.
- **code-check-spatial.md**: none read (0 of 94). The diff contains no spatial code.

## Mechanism

**Code borrowed from another caller still assumes that caller's situation.** The update
reuses helpers whose correctness was established for one of two other callers:

- a build into an empty store, whose worker catches any file it cannot read;
- a connect, which has a manifest and a `check_model` opt-out, and whose user only wants to
  search.

The update takes these helpers over without re-checking the assumptions behind them. In each
original caller, two things happened to coincide. In the update they no longer do.

- **Round 1.** In a build, "the file exists" was the same as "the file can be read", because
  the worker caught any difference. In the update that difference is the deciding fact.
- **Round 2.** In connect, an embedding problem could be followed by "BM25 is unaffected, pass
  `check_model = FALSE`". In an update there is no such argument and BM25 is no help.

Round 2 fixed only the mismatch tier of the borrowed check. The other tiers still carry
connect's assumptions.

### Every place the mechanism reaches

| # | Borrowed helper or proxy | Holds? |
|---|---|---|
| 1 | `.crd_store_sources()` (from build): the left-out, several-PDFs and zero-resolved messages | Holds. None of them says anything that is build-only. Refusing a zero-resolution is right for an update. |
| 2 | `.crd_store_who()`: looks keys up by exact `src_path` | Holds. The update passes only `src` paths, or `prepare`'s echo of them (the notes origin is the `path` it was given). |
| 3 | `.crd_store_skipped()` | Holds. |
| 4 | `.crd_store_report()`: the "Every PDF was... markitdown failing on this machine" heuristic | Holds. It looks at the ingested subset, which is the same inference as a small build makes. |
| 5 | `.crd_store_ingest()`: `ingested = paths[paths %in% docs]` treats "in the documents table" as "ingested by this run" | Holds, though it depends on the call site. This is exact only when no path passed in is already held. The update guarantees that: an added file's id is absent from `docs$id`, and a replaced file's documents are deleted first. |
| 5b | `.crd_store_ingest()`: rebuilds the index even when every document failed | Holds on both ragnar versions. 0.3.1 calls `build_index` after its loop; 0.3.1.9000's `finish_ingest()` does too. Both were read from the installed and the dev library. |
| 6a | `.crd_check_store_embedding()`, mismatch tier | Holds. It is re-raised with update wording and keeps its class (round 2). |
| 6b | `.crd_check_store_embedding()`, manifest-label tier | Holds. `entry` is `NULL`, so this tier never runs. |
| 6c | `.crd_check_store_embedding()`, probe-failure tier | **Does not hold.** See finding 1. |
| 6d | `.crd_check_store_embedding()`, silent-skip tiers (`embedding_size` unreadable, or a probe width that cannot be read) | Holds, through a backstop. The check fails toward pass, but duckdb refuses the insert. Probed: with the check mocked to a no-op and the embedder narrowed, the update raised `Conversion Error: Cannot cast array of size 8 to array of size 16`, and the store's md5 was unchanged. The roxygen sentence "a different width ... stops the update" is therefore true, but the user sees a raw duckdb message. |
| 7 | `.crd_embed_remedy(context = "update")` | Holds. `connection`, `model` and `service` are worded for any caller. `unknown` has its own update branch. The non-build `dimension` text is worded for search, but no update path reaches it: its patterns match duckdb array errors, and the update's probe is a bare embedder call. |
| 8 | `.crd_retrieval_failure()`, `.crd_fallback_model()`, `.crd_indent_cause()` | Hold. |
| 9 | `.crd_origin_id()` reuses the 8-character `[A-Z0-9]` key rule of `.crd_zot_key_from_path()` | Holds. `.crd_zot_src_path()` builds stored paths as `<zotero_dir>/storage/<DB key>/<file>`, and Zotero's key alphabet is a subset of that pattern. |
| 10 | Proxy `here <- !is.na(md5)`, standing for "can be read" | Holds after round 1. A file whose md5 can be read but which the reader cannot read becomes a skipped document. |
| 11 | Proxy `file.exists(<store>.wal)`, standing for "a process has it open" | **Does not hold.** See finding 2. (A process holding the store read-only leaves no WAL. That case is covered by the documented "Close any connection".) |
| 12 | The md5 record as a change-detection cache | Holds. It is written only for files that were ingested, and inside the copy before the rename. A replaced file whose ingest fails is left unrecorded, so the next update retries it rather than stranding it. |
| 13 | `n_docs == 0`, standing for "the update would empty the store"; the "Store is current" predicate | Hold. |
| 14 | Build's `md5[ing$ingested]` lookup by name. `md5sum()` names its result with `path.expand()`ed paths. | Holds. `src_path` has already been expanded by `.crd_zot_src_path()`. |
| 15 | Same-session effect of `dbDisconnect(shutdown = TRUE)` on another read-only connection to the store | Holds. Probed: the other connection still answers queries. |

## Findings

- **[severity: fragile]** R/store.R:2385 (`.crd_check_store_embedding(store, name = basename(store_path))`
  inside `crd_store_update()`). The update calls connect's whole check to get its mismatch tier,
  and that check probes the embedder a second time. If this second probe fails after the update's
  own probe has just succeeded, the check behaves as it would for connect:
  - It warns with connect's text: "This is not evidence about the store. BM25 retrieval needs no
    embedding and is unaffected; semantic retrieval will not work until this does".
  - It returns without stopping, and the update goes on to ingest.
  - It uses up connect's once-per-session warning slot for that store and reason
    (`.crd_store_probe_id(reason, store)`, keyed on the store's own path). A later
    `crd_store_connect()` in the same session that meets a real probe failure therefore stays
    silent. That is the diagnosis loss described in #29, arriving from a third caller.

  Second failures that can cause this: a rate limit (429) on two calls made back to back, or a
  flaky remote embedder (this is also the billed second request CLAUDE.md warns about for
  `embed_openai()` stores). Reproduced with an embedder that fails only its second call
  (`HTTP 429`): the connect warning printed and the update completed.

  The mechanism is the same as in round 2: the round-2 fix re-worded the one tier it met, and the
  sibling tier still speaks to connect's caller. The update already holds `probe`, so it could
  compare `.crd_embed_width(probe)` with `.crd_store_meta_brief(store)$size` itself. That would
  remove the second request, the connect wording and the shared frequency slot.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" ; code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** R/store.R:2335-2338 (the write-ahead-log refusal). The message names
  two causes, "a process has it open **or did not close it**", and gives one remedy: "Close it
  and retry." For the second cause there is nothing to close, and retrying refuses forever:
  - A read-only connection does not replay and remove a stale WAL, and `crd_store_connect()`
    defaults to `read_only = TRUE`, so normal use never clears it.
  - Probed: a process that wrote to a duckdb file was killed with `kill -9`. The `.wal` was left
    beside the file. A read-only connect and disconnect left the `.wal` in place; a read-write
    connect and disconnect removed it.

  A crashed or killed R session that held the store read-write leaves exactly this state. So does
  a `crd_store_build()` killed after its ingest, because its `on.exit` cleanup does not run on
  SIGKILL. The user then has a store the update refuses, with no stated way out. The remedy needs
  to name the stale-log case and its fix: open it once read-write and close it, for example
  `DBI::dbDisconnect(DBI::dbConnect(duckdb::duckdb(), path), shutdown = TRUE)` once no process
  holds it.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

No other issues found. In particular, the decision table (added, replaced, unrecorded, kept
because missing, removed) agrees with `new_rec()`, `same_rec()`, `current()` and the summary
counts in every case I traced. The failure paths (`n_docs == 0`, a failed rename, an interrupt,
a failed ingest) all disconnect before the copy is unlinked, because the `on.exit` handlers run
in the order they were added.
