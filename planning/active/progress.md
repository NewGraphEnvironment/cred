# Progress — No connect-time embedding-model check (#30)

## Session 2026-10-08

- Plan-mode exploration of `R/store.R` (1766 lines), `helper-store.R`, `test-store*.R`
- Two forks put to the user at the plan gate, both answered: error on a confirmed width
  mismatch (with `check_model = FALSE` escape), live probe on by default
- Created branch `30-no-connect-time-embedding-model-check-cr` off main
- Scaffolded PWF baseline from issue #30 with approved phases
- Next: Phase 1 — factor the per-reason remedy out of the fallback message

### Phase 1 — shared remedy builder

- `.crd_embed_remedy(reason, cond, store)` now holds the per-reason body;
  `.crd_retrieval_fallback_msg()` is head + remedy
- Purity measured, not assumed: sourced `HEAD:R/store.R` into an env parented on the loaded
  namespace and compared both builders across 5 reasons x 4 causes x 2 stores (NULL and a real
  16-wide ragnar store) = 40 combinations. **IDENTICAL** on all 40, including a hostile
  `model "with ; semicolon"` cause
- `test-store-fallback.R:634` drift guard retargeted at `.crd_embed_remedy` — it parses the
  function holding the branches, so moving them moved its subject. Gained an assertion that the
  wrapper still routes through the shared builder, so retargeting cannot keep the guard green
  while the message grows a private copy of the branches
- Next: Phase 2 — `.crd_ollama_check()` on the shared remedy

### Phase 2 — `.crd_ollama_check()` on the shared remedy

- Tests written first and confirmed red against the old code: 10 failures, including a 404
  naming `cred-absent-30` that still printed `ollama pull nomic-embed-text`
- Two defects found while implementing, neither in the issue body:
  1. the old function reduced the error to `conditionMessage()` **at the point of catching it**,
     discarding the condition class the classifier dispatches on. Keeps the condition now
  2. `.crd_fallback_model()`'s last resort is the hardcoded `nomic-embed-text`, and a connection
     failure names no model and has no store — so `.crd_ollama_check("mxbai-embed-large")` would
     have told the user to pull a model they never asked about. Added a `requested` tier,
     above the hardcoded default and below both pieces of failure-specific evidence
- `base_url` added as an internal seam so the `connection` tier is tested through the REAL
  `embed_ollama()` against a refused port, not a mock. `NULL` default rather than a copy of
  ragnar's literal
- `testthat` pin bumped 3.1.8 -> 3.2.0: `local_mocked_bindings(.package = )` needs it, and on an
  older install it errors rather than skipping
- Next: Phase 3 — `crd_search(method = "vss")` classified error

### Phase 3 — classified error for `method = "vss"`

- `.crd_retrieval_abort()` raises `cred_retrieval_error_<reason>` with the shared remedy and
  the original condition as an rlang `parent`
- Measured before choosing the shape: `conditionMessage()` on a chained rlang error **already
  folds in** `"Caused by error: ! <parent>"`, so restating the cause inline would have printed
  it twice. The fallback warning keeps its inline cause because a warning has no parent to render
- That measurement surfaced a latent bug in the newly-shared text: the `service` remedy said
  "the status **above**", true in a warning and false in a chained error, where the parent
  renders below. Reworded to "the status it returned" — position-independent, which is what
  shared text has to be. No assertion pinned the old word
- `bm25` left unwrapped on purpose: it needs no embedding, so wrapping it would turn a search
  that still works on a broken-embedder store into an error. Pinned by its own test
- Next: Phase 4 — the connect-time check

### Phase 4 — the connect-time check, plus the plan review

- `.crd_embed_width()`, `.crd_store_loc()`, `.crd_store_probe_id()`,
  `.crd_check_store_embedding()`, `.crd_store_open()`; `crd_store_connect(check_model = TRUE)`
- Plan review (Plan agent, read-only, spawned at the baseline and folded in on arrival) returned
  five blockers. Triaged by probe, in both directions:
  - **B5 confirmed and fixed** — `.crd_ollama_check()`'s `unknown` remedy told a caller of
    `crd_store_build()` to verify the file with `crd_store_connect()`, *before the store exists*.
    Reproduced in one call. Fixed with an explicit `context` argument, because `store`-absence is
    the wrong discriminator: an existing test passes no store and correctly expects the
    searcher's text
  - **B4 half-confirmed** — the leaked connection is real and now cleaned up with `on.exit`. The
    predicted consequence, that a retry under a different `read_only` would be refused, does
    **not** reproduce on ragnar 0.3.0: read-write then read-only on one file both succeed
  - **B2/G6 confirmed** — the planned fixture could not reach the error through
    `crd_store_connect()`; replaced with an on-disk copy, which also removed the mocking
  - **B3 already avoided** (distinct id prefix) but **untested**; the test added for it was
    itself defective, found by mutation M4
  - **B1 already resolved** in the landed design: the tail runs on all three paths
  - **G1/G2/G3/G4/O1/O2/Ac2/S1 already satisfied** by the implementation, which had diverged
    from the plan's one-line specs in exactly the ways asked for
  - **Ac4 partly disproved** — the review is right that the two `expect_no_match` assertions must
    **not** reverse, and the plan was wrong to say they should. Reasoning accepted and recorded
    in Phase 5
- `devtools::test()`: 587 pass, 0 fail. `lintr::lint_package()`: 0 lints
- Next: Phase 5 — the corrected sweep, docs, NEWS, version

### Phase 5 — sweep, docs, NEWS, 0.4.0

- `?crd_store_connect` rewritten: two layers rather than one, which sees what, what *neither*
  sees (a weights change at constant width), and that the probe executes code recorded in the
  store — ragnar pins the model into `embed_func` but not `base_url`, so an Ollama store's probe
  never leaves the machine while an `embed_openai()` store bills a request on every connect
- `@param verify` corrected: it stops contacting `source`, and no longer claims to be "fully
  offline", which `check_model` made false
- Sweep covered 8 sites, including the two the plan missed. The plan's instruction to reverse
  two assertions was itself wrong and was not followed — reasoning recorded in the test comments
- `NEWS.md` 0.3.2's internal contradiction corrected in place with a note; version 0.4.0
- `devtools::test()` 587 pass / 0 fail · `lintr` 0 lints · `pkgdown::check_pkgdown()` clean
- `devtools::check()`: 0 errors, 3 warnings, 4 notes — **identical on a worktree of
  `origin/main`**, so all pre-existing. Filed as
  [#32](https://github.com/NewGraphEnvironment/cred/issues/32) rather than fixed here, since the
  fixes touch `DESCRIPTION` and `R/audit.R` for reasons unrelated to #30. The one new
  non-ASCII instance this branch added was fixed, so the count is unchanged by it

### /code-check round 1 — two findings, both real

- **The cleanup's success path was unguarded.** Deleting `ok <- TRUE` from `.crd_store_open()`
  left the suite green at 587 passes while every default-path connect returned a store whose
  duckdb connection had been shut down (`dbIsValid()` FALSE, any search "Invalid connection").
  Reproduced before fixing. The error branch had a test; the two tests reaching the tail took
  the other routes. Added a test that connects with defaults and *uses* the result
- **The `dimension` remedy was gated on `context == "search"`**, so the other two contexts fell
  through to text opening "cred does not recognise this failure" — false for a reason the
  classifier had recognised. Ungated, with a store-less form for `build` that says only what can
  be established: no store exists yet, so it is the embedder or the model, not a mismatch
- **And the terminating enumeration had narrowed.** The drift guard greps
  `identical(reason, ...)`, which reported `dimension` as wired while it was wired for one of
  three contexts: the enumeration was over `reason`, the dispatch over `reason x context`.
  Extended to the product
- 602 passes, 0 lints. Both fixes mutation-checked (M7, M8) before committing

### /code-check round 2 — five findings, one of them inside round 1's fix

- **Round 1's fix, one level out.** It widened the drift guard from `reason` to
  `reason x context` and then *hardcoded* the context roster, while `match.arg()`'s list is the
  source of truth. Now derived with `eval(formals(.crd_embed_remedy)$context)`. The pair is what
  proves it: a 4th context with a falling-through `dimension` dispatch reddens the derived
  roster and leaves the hardcoded one green
- **A test that could not fail.** "A provider suffix is not a mismatch" ran after a block that
  had already spent the label warning's once-per-session slot on the same cached store, so rlang
  muffled it whatever the code did — removing `.crd_model_norm()` from the compare, the exact
  defect the test rejects, left the suite green. Fixed with `local_fallback_warnings_always()`
- **The cleanup handler was still uncovered** — round 1 guarded `ok <- TRUE`, not the `on.exit`
  itself. And the obvious discriminator does not work: after an aborted connect, reopening the
  file read-write succeeds on this duckdb. Observing `DBI::dbDisconnect` does
- **Both "must not fire on a healthy store" guards were uncovered**, one of them reachable in
  production: without `.crd_is_model_name(meta$model)`, any store whose `embed_func` has no
  `model = "..."` literal warns `records: NA` against the manifest on every connect
- **The vss error contradicted itself** for `reason = "unknown"`: "the store itself may be at
  fault", then two lines later "Both other methods still work on this store". The closing line
  now says what is true of the methods, not of the store
- My own fix for the cleanup was **vacuous and the mutation run caught it**:
  `local_store_copy_bad_width()` calls `DBI::dbDisconnect()` itself, so the counter was already
  1 before the connect. Same mechanism the round was reporting, reproduced inside its own fix
- 611 passes, 0 lints. All five mutation-checked

### /code-check round 3 — the mechanism, computed

Round 3 was asked for the mechanism rather than more instances, and it enumerated instead of
recalling: **38 code decision points** (parsed from the changed functions), of which 24 were
covered by a measured mutation, 3 behaviour-preserving, 5 unreachable and **6 reachable with no
mutation**; and **47 absence/warning assertions** in the changed tests, 18 exposed to rlang's
once-per-session state, all of which it checked individually and found isolated. Verdict:
**not fully covered**, computed rather than asserted.

Five findings, all fixed and all mutation-checked (N1-N7 above):

- `.crd_embed_remedy()`'s `connect` fallthrough was untested, and the mutant has
  `crd_store_connect()` telling the reader to run `crd_store_connect()` — round 1's finding one
  branch over. The `build` twin was covered; the asymmetry is what gave it away
- **Nothing in the suite exercised `verify = TRUE`** — all nine `crd_store_connect()` calls in
  `tests/` passed `verify = FALSE`. So neither verified site's `entry` nor its `check_model` was
  constrained, and **the label tier is reachable in production by no other route**, since
  `verify = FALSE` passes `entry = NULL` by design. Covered now by mocking the one function on
  that path that touches the network, with the md5 taken from the fixture at test time
- `.crd_have(entry$embedding_model)` — the fourth conjunct of the label tier, uncovered and
  production-reachable via an entry `.crd_manifest_merge()` passes through verbatim
- Round 2's vss-contradiction fix was itself unpinned; restoring the wording was silent
- `local_reset_fallback_warnings()` re-armed one of three id schemes while reading as "the
  warnings for this store". The label id was inline, so the helper had to restate it — extracted
  to `.crd_store_label_id()` and the reset set now derived
- 628 passes, 0 lints

### /code-check round 4 — two findings, both inside round 3's fixes

- **The download site had never been executed.** Round 3 covered `verify = TRUE` by mocking
  `.crd_manifest_read`, but only the md5-match return ever ran: its mutations dropped `entry`
  and `check_model` from *both* verified sites at once, so one test on one site turned them red.
  A `stop()` placed before the download branch was silent. Covered now by mocking `.crd_aws`
  alongside the manifest read — the mock writes the `.part-<pid>` file the real `aws s3 cp`
  would have, and the manifest's md5 comes from that same file so the post-download verify
  passes for the right reason
- **General lesson, worth carrying out of this issue:** *a mutation applied to N sites at once
  certifies coverage of exactly one of them.* Mutate one site at a time, or the table
  over-claims in the direction it exists to prevent
- **Round 3's finding 5 reproduced inside its own fix.** `.crd_all_warning_ids()` derived from
  the three id *functions* and its test restated the same three, so pointing an emitter's
  `.frequency_id` at a fourth function escaped both. The guard now walks the namespace for what
  the **emitters** actually pass
- Round 4 also closed enumeration B *mechanically* rather than per-site: running both changed
  test files twice in one session gives identical results, so no assertion is green because of
  rlang frequency state in either direction
- 639 passes, 0 lints. M-A, M-B, P2, P5 each fire

### /code-check round 5 — closed

- **0 findings.** 43 code decision points: 32 covered by a measured mutation, 3
  behaviour-preserving, 5 unreachable, 3 cosmetic-and-accepted, 0 uncovered and consequential.
  50 test-side assertions closed mechanically by a double run in one session
- All four of round 4's probes now fire on the site they name, and M-D confirms both halves of
  the new download test are load-bearing
- For the first time in five rounds the loop's signature — a defect inside the previous round's
  fix — does not appear, and it was looked for on both axes earlier fixes failed on
- Took round 5's second note: `local_mocked_download_of()`'s `model`/`size` formals went dead
  when the manifest mock moved inline, so a call site passing `size = 16L` read as load-bearing
  and was not. Removed
- Left round 5's first note recorded rather than chased: the namespace walk cannot see an emitter
  passing a bare variable id, and round 5 calls that gap unproven-closed rather than open
- Spend: 6 subagents (1 plan review + 5 review rounds), over the usual bound. The justification
  is the signature above — four consecutive rounds found a defect inside the previous fix
