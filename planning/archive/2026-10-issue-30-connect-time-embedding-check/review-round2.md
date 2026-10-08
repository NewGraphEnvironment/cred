# Review round 2 — branch `30-no-connect-time-embedding-model-check-cr`

Reviewer: subagent code review, read-only. Read in full: the branch diff (11 files),
`R/store.R`, `tests/testthat/test-store-embed-check.R`,
`tests/testthat/test-store-fallback.R`, `tests/testthat/helper-store.R`,
`DESCRIPTION`, `CLAUDE.md`, `planning/active/review-round1.md`, and the
`/code-check` checklist.

All probes ran in a throwaway copy at
`…/scratchpad/rev2/cred`. The working tree was never modified (`git status`
clean before and after, confirmed both sides).

**Control, in the copy, branch as committed:**

| check | result |
|---|---|
| `devtools::test()` | `FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 602` |
| `devtools::test(filter = "store")` | `FAIL 0 \| PASS 470` |
| `lintr::lint_package()` | 0 lints |
| `devtools::document()` | no diff in `man/` |
| non-ASCII **string literals** in `R/store.R` vs `origin/main` | 10 vs 10, `setdiff` empty — none added |
| local Ollama during these runs | **running** (so the mocked `.crd_ollama_check` tests are not passing because the service is absent) |

---

## Findings

### 1. **[fragile]** `tests/testthat/test-store-embed-check.R:312` — "a provider suffix in the manifest label is not a mismatch" is structurally incapable of failing

The test asserts silence. It gets silence whatever the code does, because the test
immediately above it (`:294`) already emitted the label-mismatch warning on the
**same cached store**, and that warning is

```r
.frequency = "once",
.frequency_id = paste0("cred_store_model_label_", .crd_store_loc(store))
```

— keyed on the store **location only**. `local_ragnar_store_named()` is cached for
the whole run, so the second call's warning is muffled by rlang before the
comparison matters. Neither label test calls `local_fallback_warnings_always()` or
`local_reset_fallback_warnings()`, which exist in `helper-store.R` for exactly this.

Measured, in the copy. Mutation M10 — drop `.crd_model_norm()` from the label
compare, so `"mxbai-embed-large (ollama)"` vs `"mxbai-embed-large"` *is* a
mismatch, which is the one defect this test exists to reject:

```
M10 applied, file order as committed   -> FAIL 0 | PASS 470   (full "store" filter)
M10 applied, this block run FIRST      -> FAIL 1   ("Test failed with 1 failure")
M10 + `local_fallback_warnings_always()` added to the block -> FAIL 1 at :320
control + that same one-line addition  -> FAIL 0 | PASS 85
```

So the guard is correct in the shipped code and the test cannot say so. This is the
hazard `helper-store.R:298-300` already records ("the sentinel environment is
package-level … leakage otherwise crosses test FILES"), arriving *within* one file.

Cheapest fix is one line, and it was checked in both directions above:

```r
test_that("a provider suffix in the manifest label is not a mismatch", {
  store <- local_ragnar_store_named()
  local_fallback_warnings_always()
  ...
```

Worth noting the sibling at `:294` is order-sensitive rather than vacuous — it
captures the warning, so if anything ever fires that id first, `cnd` stays `NULL`
and `expect_s3_class(NULL, …)` fails. The two tests are a pair whose correctness
depends on their order in the file, with nothing saying so.

### 2. **[fragile]** `tests/testthat/test-store-fallback.R:693` — the widened enumeration is complete over three contexts someone typed, not over the contexts the function accepts

This is round 1's finding 2, one level out. The dispatch is over `reason × context`;
the fix enumerates the product — but with `context` restated as a literal:

```r
contexts <- c("search", "build", "connect")
```

while the source of truth is `.crd_embed_remedy()`'s own
`context = c("search", "build", "connect")` formal. A fourth context added later —
the branch has already grown from one caller to three in a single issue — is invisible
to the guard, and the failure it hides is the same one round 1 found: a recognised
reason served the "cred does not recognise this failure" text.

Measured. Mutation: add `"push"` to the `match.arg` roster, give it its own
fallthrough branch, and gate `dimension` off it (`&& !identical(context, "push")`),
which is precisely the M8 shape re-committed for a new context:

```
contexts hardcoded (as committed)                  -> FAIL 0  (store-fallback, all green)
contexts <- eval(formals(.crd_embed_remedy)$context) -> FAIL 1, info "dimension push"
same derived form, mutation reverted                -> FAIL 0  (green on shipped code)
```

Fix is the one line, verified green on the control:

```r
contexts <- eval(formals(.crd_embed_remedy)$context)
```

Same instrument the block already uses for `reason` (it parses the classifier and
asserts against `.crd_fallback_reasons()` rather than restating the set), and the
same reason `.crd_fallback_reasons()` exists at all.

Excluding `"unknown"` from the inner loop is correct and hides nothing — `unknown`
*is* the fallthrough, so including it would assert `x != x`.

### 3. **[fragile]** `R/store.R:373-377` — the round-1 fix guarded the cleanup's success branch; the cleanup itself is still unguarded

The new test at `:496` does constrain what it was written for: it reaches the tail
with `check_model = TRUE` on a consistent store and *uses* the result
(`dbIsValid` + a bm25 search), so `ok <- TRUE` cannot be deleted silently (M7). I
confirmed the `on.exit(unlink(copy))` inside `test_that()` genuinely fires
(measured: file gone after the block), so it leaks no temp file, and the copy is a
fresh path so neither the cached fixture's connection nor its file is reachable
from it.

What it does not constrain is the `on.exit` handler — the entire reason the block
exists. Measured, M9:

```
delete the whole `ok <- FALSE` / `on.exit(…)` pair, keeping the check call
  -> FAIL 0 | WARN 0 | SKIP 2 | PASS 602
```

So the connection leak that round 1's B4 triage identified and this branch closed is
reproducible with the suite still green. Round 1 verified the error branch by hand
with `lsof`; nothing in the tree does.

Note the obvious discriminator does **not** work, so don't reach for it: after an
aborted connect with the cleanup deleted, reopening the same file read-write
succeeds (measured, duckdb as installed) — consistent with the code comment's own
"does NOT reproduce on ragnar 0.3.0". A mock on the call the cleanup makes is the
route that works, and `::` dispatch does reach a `local_mocked_bindings` mock
(measured separately on `ragnar::embed_ollama` via `do.call`):

```r
real <- DBI::dbDisconnect              # capture before mocking
closed <- 0L
local_mocked_bindings(
  dbDisconnect = function(conn, ...) { closed <<- closed + 1L; real(conn, ...) },
  .package = "DBI"
)
expect_error(suppressMessages(crd_store_connect(local_store_copy_bad_width(), verify = FALSE)),
             class = "cred_store_embedding_mismatch")
expect_gt(closed, 0L)
```

### 4. **[fragile]** `R/store.R:319` and `R/store.R:274` — both "must not fire on a healthy store" guards inside `.crd_check_store_embedding()` are uncovered

Same shape as finding 3, and these two decide whether a *healthy* store is refused
or nagged. Measured independently, full `filter = "store"` run each:

| mutation | result |
|---|---|
| M13 — drop `!.crd_have(got)` from `R/store.R:319`, leaving `if (identical(got, as.integer(meta$size)))` | **FAIL 0 \| PASS 470** |
| M11 — drop `.crd_is_model_name(meta$model)` from the label tier's condition (`R/store.R:274`) | **FAIL 0 \| PASS 470** |

- **M13** is the guard that keeps an *unreadable* probe result from being reported as
  a width mismatch, which is the one tier that **errors**. Without it, an embedder
  returning anything `.crd_embed_width()` reads as `NA` (a list, a zero-length
  vector) aborts the connect with `its recorded embedder now returns: NA-wide`. Not
  reachable from ragnar's own embedders, which is why I am not calling it a bug —
  but it is the guard whose roxygen says the check is "supposed to degrade quietly".
- **M11** is reachable in production. `.crd_store_model_from_meta()` returns `NA`
  whenever the store's `embed_func` carries no `model = "…"` literal — a store built
  by anything other than `crd_store_build()` — and without the guard every such
  store warns `the store records: NA / the manifest says: <label>` on connect.

This also makes `task_plan.md`'s mutation table over-claim: it is introduced as
"restore the defect and prove each guard fires", and three guards this branch added
(`R/store.R:274`, `:319`, `:373-377`) have no mutation that fires. M1–M8 cover the
wiring and the dispatch, not the tolerance guards. Worth a line in the table saying
which guards are covered by inspection only, rather than leaving the table read as
complete — that is the same "enumeration narrower than the dispatch" reading round 1
applied to the drift guard.

### 5. **[fragile]** `R/store.R:1198-1201` — the vss error contradicts itself when the reason is `unknown`

`.crd_retrieval_abort()` appends `"Both other methods still work on this store"`
unconditionally, including behind the `unknown` remedy, which says the opposite two
lines earlier. Measured verbatim:

```
Semantic retrieval failed, and method = "vss" has no fallback.
  cred does not recognise this failure, so no remedy is prescribed. Semantic
  retrieval is unavailable and the store itself may be at fault - confirm it is
  the file the manifest describes with crd_store_connect().
  Both other methods still work on this store: "hybrid" would have
  degraded to BM25 with a warning, and "bm25" needs no embedding at all.
Caused by error:
! Catalog Error: Index vss_idx does not exist
```

"The store itself may be at fault" and "both other methods still work on this store"
cannot both be offered. The two clauses after the colon are each true as statements
about *cred's behaviour* ("hybrid would have degraded", "bm25 needs no embedding");
the lead-in converts them into a claim about this store that the `unknown` branch
exists precisely because cred cannot make. One word fixes it —
`"Neither other method needs the embedder: …"` — and it stays accurate for the four
reasons where the store is not a suspect.

---

## Checked and clean

Everything else the brief singled out.

- **The build-time `dimension` text is accurate for every way it can be reached.**
  `context = "build"` has exactly one caller, `.crd_ollama_check()`, invoked at
  `R/store.R:1595` — *before* `ragnar_store_create()`, so "There is no store to
  compare against yet" holds. `store` is always `NULL` on that path, so
  `.crd_fallback_model(cond, NULL, requested = model)` names the model the caller
  asked for, which is the tier Phase 2 added. (With `overwrite = TRUE` a file does
  exist at `store_path` at that moment; the sentence is about the store being built,
  and the remedy it prescribes — `ncol(embed_ollama('probe', model = …))` — is right
  either way.)
- **The ungated `dimension` text at `context = "connect"` is defensible.** It is
  effectively unreachable (`.crd_dim_patterns` matches duckdb binder text raised
  while *querying*; the connect probe calls the embedder directly), and the text it
  now serves — "treat this store as unverified", "compare what the store records
  against what the service now returns" — reads correctly at connect. One stale
  comment: the block at `R/store.R:1116-1119` still reasons that "reaching this
  warning at all means connect either was not asked to check or already passed",
  which is false now that connect is a caller. Its conclusion (do not prescribe
  `crd_store_connect()` here — circular) survives.
- **`.crd_embed_width()` cannot report a wrong width on a healthy store.**
  Re-derived rather than taken from round 1: `ragnar_store_create()` fixes
  `embedding_size` from `ncol(embed(…))`, the same read, so any shape that makes
  `ncol()` return the "wrong" axis (a transposed matrix, a 1-column frame) was
  recorded through the same wrong axis and the two agree. The `length()` fallback
  only engages where `ncol()` is `NULL`, which is where it is the right read.
- **`.crd_store_open()` wiring.** All three `crd_store_connect()` return paths route
  through it; the structural guard at `test-store-embed-check.R:379` computes that
  rather than recalling it. The `verify = FALSE` early return is unchanged
  (missing-file guard, message) and correctly passes `entry = NULL`, which skips the
  label tier. The `on.exit(unlink(part))` at `R/store.R:521` and the one in
  `.crd_store_open()` are in different frames and cannot interact; on the download
  path the abort happens after `file.rename()`, so `unlink(part)` is a no-op on a
  path that no longer exists and the verified download is kept.
- **The roxygen claim about `embed_func` is true.** Verified directly rather than
  from the prose: `ragnar:::process_embed_func()` evaluates a non-character `model`
  in the original environment and writes it in as a literal, then re-parents to
  `baseenv()`. On `crd_store_build()`'s exact shape
  (`function(x) ragnar::embed_ollama(x, model = model)`) the stored function comes
  back as `function(x) ragnar::embed_ollama(x = x, model = "mxbai-embed-large")`
  with `<environment: base>` — self-contained, so the connect probe works and
  `.crd_store_model_from_meta()`'s regex finds the literal. `base_url` is untouched
  unless supplied, so the Ollama/`embed_openai()` asymmetry in `?crd_store_connect`
  is accurate.
- **Frequency-id schemes.** `cred_store_probe_<reason>_<loc>`,
  `cred_retrieval_fallback_<reason>_<loc>` and `cred_store_model_label_<loc>` have
  disjoint prefixes, so no key collides for any reason or store. The behavioural test
  at `:467` is the one carrying the property, as its comment says. (The label id is
  still inlined rather than extracted the way `.crd_store_probe_id()` was — harmless
  only because no test restates it; finding 1 is a different problem with the same
  warning.)
- **`.crd_fallback_model(cond = NULL, …)` and tier order.** Code order
  (condition-named → store-recorded → requested → hardcoded) matches the roxygen,
  `requested` passes through `.crd_is_model_name()` like the other two, and both
  directions of requested-vs-service-named precedence are pinned at
  `test-store-embed-check.R:54` and `:86`. `.crd_check_store_embedding()`'s abort
  passes `store =` by name, so the new `cond` default applies.
- **The error tier is not reachable vacuously.** Its two tests assert the premise
  first — `.crd_embed_width(broken@embed("probe")) == 8L` at `:233`, and
  `cnd$store_size == 8L` / `cnd$embed_width == 16L` at `:446-447`, which is what
  separates "fired for the recorded width" from "fired because the file was missing
  or duckdb refused the configuration", both of which also error on that call.
- **`local_store_copy_bad_width()`** cannot reach the cached fixture: it copies the
  file and opens a separate driver on the copy, so neither the `UPDATE` nor the
  `dbDisconnect(shutdown = TRUE)` touches `.crd_store_cache$store`. Running
  `test-store-embed-check.R` alone (`PASS 85`) and in the full suite both pass with
  no downstream retrieval failures, and the file sorts before every other
  `test-store*` file, so later files take the cached store intact.
- **Mocking takes effect.** Confirmed directly that `local_mocked_bindings(.package
  = "ragnar")` reaches `do.call(ragnar::embed_ollama, args)` (sentinel error came
  back through `::`). This matters more than round 1 could know: Ollama **is**
  running on this machine, so a bypassed mock would have made
  `.crd_ollama_check("nomic-embed-text")` succeed and `expect_match(NULL, …)` error.
- **`testthat (>= 3.2.0)`** is required and used — `local_mocked_bindings(.package =)`,
  and `expect_no_match`/`expect_no_error`, which `test-store-fallback.R` was already
  using under the old 3.1.8 pin. `expect_false(…, info = )` is legal (the `info`
  restriction is on the comparison expectations, not `expect_false`).
- **Planning files vs code.** No claim contradicts the code except the mutation
  table's implied completeness (finding 4). `progress.md`'s and
  `task_plan.md`'s accounts of the two round-1 fixes match what landed, including
  the two places the #30 plan was wrong.

## Mutations run (all in the copy; control `FAIL 0 | PASS 602`)

| mutation | result |
|---|---|
| M9 — delete `.crd_store_open()`'s whole `on.exit` cleanup | **0 failures** — finding 3 |
| M10 — drop `.crd_model_norm()` from the label compare | **0 failures** in file order; 1 when the block runs first — finding 1 |
| M11 — drop the label tier's `.crd_is_model_name(meta$model)` guard | **0 failures** — finding 4 |
| M13 — drop `!.crd_have(got)` before the width compare | **0 failures** — finding 4 |
| add a 4th `context` whose `dimension` dispatch falls through | **0 failures**; 1 with `contexts` derived from `formals()` — finding 2 |
| control | 0 failures, 602 passes |
