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
