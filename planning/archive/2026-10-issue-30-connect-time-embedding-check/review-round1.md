# Review round 1 — branch `30-no-connect-time-embedding-model-check-cr`

Reviewer: subagent code review, read-only. Diff reviewed in full (11 files), plus
`R/store.R`, `tests/testthat/test-store-embed-check.R`,
`tests/testthat/test-store-fallback.R`, `tests/testthat/helper-store.R`,
`DESCRIPTION`, `CLAUDE.md`.

All probes were run in a throwaway copy of the tree at
`/private/tmp/claude-501/.../scratchpad/rev/cred`. The working tree was not touched.

**Control measurements on the branch as it stands** (in the copy):

| check | result |
|---|---|
| `devtools::test()` | `FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 587` |
| `test_local(filter = "store-embed-check")` alone | `FAIL 0 \| PASS 82` — file is order-independent |
| `lintr::lint_package()` | 0 lints |
| `devtools::document()` | no diff in `man/` — generated docs are in sync |
| new non-ASCII **string literals** vs `origin/main` | 10 vs 10 — none added |
| `::` calls in the new test file | `DBI`, `duckdb`, `ragnar`, `rlang`, `withr` — all in `Suggests` |
| `[ragnar::embed_openai()]` link target | resolves; `embed_openai` is an alias in `embed_ollama.Rd` |

---

## Findings

### 1. **[fragile]** `R/store.R:373-380` — the new cleanup's *success* path is unguarded; a mutation that returns a dead connection on every default-path connect leaves the whole suite green

`.crd_store_open()` registers

```r
ok <- FALSE
on.exit(if (!ok) try(DBI::dbDisconnect(store@con, shutdown = TRUE), silent = TRUE), add = TRUE)
.crd_check_store_embedding(store, entry = entry, name = name)
ok <- TRUE
store
```

The error branch is correct and I verified it (below). The `ok <- TRUE` line, however,
is the only thing standing between every default `crd_store_connect()` call and a
returned store whose duckdb connection has been shut down — and **nothing in the suite
tests it**.

Measured, in the copy:

- Deleting `ok <- TRUE` (nothing else) → `devtools::test(filter = "store")`
  `FAIL 0 | PASS 455`, and the full suite is likewise green.
- Against that same mutant, on a freshly built consistent store:

  ```
  st <- crd_store_connect(p, verify = FALSE)
  DBI::dbIsValid(st@con)   # FALSE
  crd_search(st, "culvert fish", method = "bm25")   # Error: Invalid connection
  ```

So the mutant breaks **every** caller on the default path and no test says so.

Why no test reaches it: the only two tests that call `crd_store_connect()` through the
new tail are `test-store-embed-check.R:349` (mismatch → expects an error, so it exercises
the `!ok` branch) and `:363` (`check_model = FALSE`, which returns at
`R/store.R:367` *before* the `on.exit` is registered). `test-store.R:99` is the
missing-file guard. There is no test that connects with the default
`check_model = TRUE` to a **consistent** store and then uses the result.

The mutation table in `planning/active/task_plan.md` lists M1–M6; this mutation is not
among them, and M1 ("delete the check from `.crd_store_open()`'s tail") exercises the
opposite direction.

For the record, the shipped code *is* correct — I confirmed both halves:

- consistent store, default args → `crd_search(..., "bm25")` returns rows, `@con` valid;
- bad-width store (`UPDATE metadata SET embedding_size = 8`) → errors
  `cred_store_embedding_mismatch`, and `lsof` on the store path reports **0** open
  descriptors for the R process afterwards, i.e. the cleanup really closes it.

Cheapest fix: one assertion on the existing bad-width fixture's healthy sibling —
connect a consistent store with defaults and assert `DBI::dbIsValid(out@con)` (or do a
`bm25` search on it, which is what `:363` already does for the `check_model = FALSE`
case). Adding it to the mutation table as M7 would close the gap the table was built to
prove absent.

Also relevant to the brief's explicit questions, all checked and **clean**:

- `.crd_store_open()` never closes a connection it does not own — it only ever closes the
  one `ragnar::ragnar_store_connect()` returned to it two lines earlier.
- `add = TRUE` ordering against `crd_store_connect()`'s own `on.exit(unlink(part))`
  (`R/store.R:521`) is a non-issue: different frames, so no interaction.
- `shutdown = TRUE` cannot reach a sibling connection. Measured on duckdb 1.5.2: two
  independent `dbConnect(duckdb(), path, read_only = TRUE)` connections to one file, then
  `dbDisconnect(b, shutdown = TRUE)` — `a` stays valid and still queries. The hazard
  `helper-store.R:144-146` records applies only to an S7 *copy* sharing one `@con`, which
  the shipped code never constructs.
- `local_store_copy_bad_width()` is safe w.r.t. the cached fixture: it copies the file and
  opens a separate driver on the copy, so neither the `UPDATE` nor the
  `dbDisconnect(shutdown = TRUE)` can reach `.crd_store_cache$store`. Running
  `test-store-embed-check.R` alone and in the full suite both pass, with no downstream
  retrieval failures.

### 2. **[fragile]** `R/store.R:1058`, `:1116-1131` — gating the `dimension` remedy on `context == "search"` makes two contexts claim the failure was unrecognised, and blinds the terminating drift guard to context

`.crd_embed_remedy()`'s dimension branch is

```r
if (identical(reason, "dimension") && identical(context, "search")) {
```

so a `dimension` classification arriving with `context = "build"` or `"connect"` falls
through to the two context-specific fallthroughs, both of which open with *"cred does
not recognise this failure, so no remedy is prescribed"*. Measured:

```
reason: dimension
--- connect ---
  cred does not recognise this failure, so no remedy is prescribed. Semantic
  retrieval will not work until it does; BM25 needs no embedding and is
  unaffected.
--- build ---
  cred does not recognise this failure, so no remedy is prescribed. The store
  cannot be built without embeddings, and nothing here says why this model
  could not produce one.
```

That sentence is false for a reason the classifier did recognise. Live reachability is
low — both non-search callers invoke an embedder directly (`.crd_ollama_check()` via
`ragnar::embed_ollama`, `.crd_check_store_embedding()` via `store@embed`), and
`.crd_dim_patterns` matches duckdb binder text raised while *querying* a store — so I am
not claiming a user hits this today. Two reasons it is still worth a line:

- A custom `embed_func` or a future ragnar that surfaces a cast/size error from the
  embedder lands there, and the message actively denies having classified it.
- More importantly, the **terminating check weakened**. `test-store-fallback.R:658`
  derives branch coverage by `grep('identical\\(reason, "', deparse(.crd_embed_remedy))`.
  That grep sees `"dimension"` and reports it wired; it cannot see that the branch is
  wired for one of three contexts. The whole point of that block (per its own comment:
  "a reason the classifier can return with no branch in the message builder silently gets
  the 'unknown' text") is now satisfiable by a reason that *does* get the unknown text in
  two of three contexts. The repo's own convention is to terminate by enumeration — the
  enumeration here is now over `reason` only, while the dispatch is over
  `reason × context`.

Either make the dimension text context-independent (the store-record lines in it read
fine at connect, and the `ncol(ragnar::embed_ollama(...))` one-liner is exactly the probe
connect just ran), or extend the drift guard to the `reason × context` product so the
grep cannot report partial coverage as complete.

---

## Checked and clean

Everything the brief singled out, other than the two findings above.

- **`.crd_embed_width()`** — reads every shape correctly and does not over-report on a
  healthy store. Measured: `matrix(0,1,16)`→16, `matrix(0,4,768)`→768, `numeric(16)`→16,
  `data.frame(a,b)`→2, `tibble(a,b,c)`→3, `matrix("a",1,5)`→5, `array(0,c(1,16,2))`→16,
  `list(1,2)`→NA, `numeric(0)`→NA, `NULL`→NA. It cannot disagree with a healthy store by
  construction: `ragnar_store_create()` sets `embedding_size = ncol(embed("foo"))`
  (confirmed in its signature), the same `ncol` cred uses, and the `length()` fallback
  only engages for an embedder returning a bare vector — which `ncol()` could not have
  measured at create time, so such a store must have been given an explicit
  `embedding_size`, and the fallback is then the *right* read. Only pathological input
  (`.crd_embed_width(NA)` → `1L`, a scalar "failed without raising" return) yields a
  width where NA would be kinder; not reachable from any real embedder, so not reported.
- **`.crd_check_store_embedding()` tiers** — ordering is as documented; the label tier
  runs before the size gate because it does not need the size, and a label warning
  followed by a width abort signals both. No tier can fire on a healthy store: the label
  tier requires `entry$embedding_model`, a model-shaped store record, and disagreement
  after `.crd_model_norm()`; the error tier requires a readable size, a callable
  embedder, a *successful* probe, a non-NA width, and inequality. Every read is tolerant
  (`.crd_store_meta_brief()` returns all-NA, `store@embed` and the probe are both
  `tryCatch`ed, `.crd_indent_cause(character(0))` returns `""` rather than erroring). The
  error tier cannot be reached vacuously, and its test asserts the premise
  (`.crd_embed_width(broken@embed("probe")) == 8L`) before asserting the error.
- **`crd_store_connect()` return paths** — all three now route through `.crd_store_open()`;
  I confirmed by mutation that reverting the `verify = FALSE` site to a direct
  `ragnar::ragnar_store_connect()` turns the suite red (4 failures, at
  `test-store-embed-check.R:445` and `:448` and the structural guard at `:387`). The
  `verify = FALSE` early return still behaves (missing-file guard unchanged, message
  unchanged, `entry = NULL` correctly skips the label tier).
- **Frequency-id scheme** — `cred_store_probe_<reason>_<loc>` vs
  `cred_retrieval_fallback_<reason>_<loc>` vs `cred_store_model_label_<loc>`: distinct
  prefixes, so no key can collide for any reason or store. Verified behaviourally by
  mutation: pointing the probe warning at `.crd_retrieval_fallback_id()` fails
  `test-store-embed-check.R:484`, which is the test that carries the property (the scheme
  comparison at `:420` alone would not have). Minor note, not a finding:
  `.crd_retrieval_fallback_id()` (`:1212`) still inlines its own copy of
  `.crd_store_loc()`'s `nzchar(NA)` guard rather than calling the new helper — one fact
  derived twice, though the two are currently identical.
- **`.crd_embed_remedy(context = )`** — `match.arg` default is `"search"`, which is right
  for both of its context-less callers (`.crd_retrieval_fallback_msg()` and
  `.crd_retrieval_abort()`, both genuinely searches). No caller receives text that cannot
  apply to it, with the single exception in finding 2.
- **`.crd_fallback_model(cond = NULL, ...)`** — the NULL-condition guard is correct;
  `.crd_check_store_embedding()`'s abort passes `store =` by name so the new `cond`
  default applies. Tier order in code (condition-named → store-recorded → requested →
  hardcoded) matches the roxygen, and `requested` is validated through
  `.crd_is_model_name()` like the other two before reaching a paste-me line. The two
  tests at `test-store-embed-check.R:54` and `:86` pin both directions of the
  requested-vs-service-named precedence.
- **`.crd_retrieval_abort()`** — `rlang::abort(parent = )` keeps the cause reachable as
  `cnd$parent` and folds its message into `conditionMessage()` of the outer condition;
  the test asserts the literal `"Caused by error"` plus a remedy token in the same
  string, so self-sufficiency is measured rather than assumed. `bm25` is correctly left
  unwrapped and `test-store-embed-check.R:174` pins that.
- **Mocking** — `local_mocked_bindings(.package = "ragnar")` genuinely takes effect
  through `do.call(ragnar::embed_ollama, args)`: the assertions in those blocks
  (`expect_match(msg, "so it is running")`) would fail on `NULL` if the mock were
  bypassed, and would fail differently if the real localhost call were reached. The
  `function(...)` mock would normally be the "hides a dropped argument" trap, but the
  `base_url` seam is separately exercised through the **real** `embed_ollama()` against
  loopback port 1 (`:27`, `:40`, `:54`, `:106`), so the signature is covered.
- **`expect_silent()` / `expect_no_error()` tests do constrain.** Checked each:
  `:246` would fire on any warning or message from a consistent store; `:274`
  (`embedding_size` unreadable) would reach the probe and abort on
  `identical(16L, NA_integer_)` if the early return were removed; `:286` (`@embed <- NULL`)
  likewise; `:312` (provider suffix) would warn without `.crd_model_norm()`. The two
  `expect_no_error(withCallingHandlers(...))` blocks are not vacuous because the
  subsequent `expect_s3_class(cnd, ...)` fails on `NULL` when no warning fires.
- **`DESCRIPTION`** — `testthat (>= 3.2.0)` is required and used (`.package =` in
  `local_mocked_bindings`); `expect_no_match`/`expect_no_error` are covered by the same
  floor. Version `0.4.0` + `Date: 2026-10-08`; `CITATION.cff` left to the CI job, matching
  prior releases.
- **Planning files vs code** — no contradicting claims found. `task_plan.md` records the
  two places the plan was wrong (the `expect_no_match` pair that must *not* reverse, and
  the mock-based fixture that shared a connection) and both match the landed code.
  `findings.md`'s error ledger matches `helper-store.R`'s and the new test file's
  comments.
- **Claims I spot-verified rather than taking from the prose** —
  `ragnar:::process_embed_func()` does inject `model` as a character literal and does
  *not* inject `base_url` unless it was supplied (`rlang::call_match(defaults = FALSE)`),
  so the roxygen's "for an Ollama store the probe never leaves the machine / for
  `embed_openai()` it is a billed request on every connect" is accurate. That default-on
  third-party request is documented with `check_model = FALSE` as the opt-out and was a
  plan-gate decision, so it is noted, not flagged.

## Mutations run

| mutation | result |
|---|---|
| delete `ok <- TRUE` from `.crd_store_open()` | **0 failures** — finding 1 |
| probe warning reuses `.crd_retrieval_fallback_id()` | 1 failure (`:484`) — guard fires |
| `verify = FALSE` path reverted to a direct `ragnar::ragnar_store_connect()` | 4 failures — guard fires |
| control (branch as committed) | 0 failures, 587 passes |
