# Task: No connect-time embedding-model check: crd_store_connect() verifies md5, which cannot see a model change (#30)

## Problem

`crd_store_connect()`'s `@details` claimed that verification catches a store "built against a
different embedding model". It does not. The MD5 compare answers *"is this the file the manifest
describes"* — a stale copy, a truncated download, a local rebuild nobody pushed. A store whose
embedding model has moved underneath it has **exactly the bytes the manifest recorded**, so the
compare is structurally unable to see it.

The manifest already carries `embedding_model` and `embedding_size`, and `.crd_check_model()`
(`R/store.R`) already knows how to compare them — but it runs on **push** only, never on connect.

This was found while fixing #29, whose first draft of the dimension-mismatch warning sent users
to `crd_store_connect()` to verify a model mismatch. That would have been a remedy that cannot
detect the condition, which is the defect #29 itself is.

## Decisions taken at the plan gate

| fork | decision |
|---|---|
| confirmed width mismatch at connect | **error**, with `check_model = FALSE` escape — matches the md5 path and `crd_store_push(allow_model_mismatch = FALSE)` |
| live probe | **on by default**; skipped silently when unprobe-able; `verify = FALSE` keeps the offline path offline |

## Design

**The probe is the whole point.** `ncol(store@embed("<probe>"))` against
`SELECT embedding_size FROM metadata` is the *exact* condition that produces #29's `dimension`
fallback, and it uses the store's **own recorded embedder** — ragnar does
`embed <- unserialize(metadata$embed_func[[1L]])`, so this is not "a model name reconstructed
from a string", it is the thing that will actually embed queries.

**Width is the detectable part, and this must not over-claim.** A model that changed weights
while keeping its width is invisible to any check here. The docs say so.

**Severity tracks the evidence**, four tiers:

| evidence | outcome |
|---|---|
| probe ran, widths differ | **error** (escape: `check_model = FALSE`) |
| manifest label disagrees with the store's own record | **warning** — the manifest's model is the pusher's env label (`.crd_store_describe()` falls back to `CRED_EMBED_MODEL`), so it is the weaker half |
| probe could not run (no Ollama) | **not a mismatch** — classified via `.crd_retrieval_failure()`, reported once per session as "could not check" |
| store records no embedder, or `embedding_size` unreadable | skipped silently |

## Phase 1: Factor the per-reason remedy out of the fallback message

Enabling change for 2, 3 and 4, and the fix for "two accounts of one dead port".

- [x] `.crd_embed_remedy(reason, cond, store = NULL)` carries the per-reason body
- [x] `.crd_retrieval_fallback_msg()` becomes `head + remedy`, keeping its exact current text
- [x] `tests/testthat/test-store-fallback.R` stays green — the text is byte-identical across 40
      reason x cause x store combinations (verified against `HEAD:R/store.R`). The one edit is
      the structural drift guard at `:634`, which parses the function holding the branches and
      so had to follow them; it gained an assertion that the wrapper still routes through
      `.crd_embed_remedy()`
- [x] `store = NULL` stays safe in the `dimension` branch (`.crd_store_meta_brief(NULL)` is all-`NA`)

## Phase 2: `.crd_ollama_check()` on the shared remedy

- [x] Replace the fixed `ollama serve` + `ollama pull` remedy with `.crd_embed_remedy()` under an
      error-shaped head (`R/store.R:1072`, called from `crd_store_build()` at `:1162`)
- [x] Test: a `connection` failure does not lead with `ollama pull`
- [x] Test: a `service` failure does not print `ollama serve`

## Phase 3: `crd_search(method = "vss")` classified error

- [x] Wrap the `vss` branch, classify, re-raise with `rlang::abort(parent = e, class = c("cred_retrieval_error_<reason>", "cred_retrieval_error"))`
- [x] Message says no fallback exists for vss
- [x] Leave `bm25` unwrapped — it needs no embedding
- [x] Test via `local_ragnar_store_failing("dimension")` + `method = "vss"`

## Phase 4: The connect-time check

- [x] `.crd_embed_width(x)` — `ncol()` on a matrix, `length()` on a vector, `NA` otherwise
- [x] `.crd_check_store_embedding(store, entry = NULL, name)` — the four tiers, every read
      tolerant; reuse `.crd_model_norm()`. **Not** `.crd_check_model()`, which compares against
      *other* stores
- [x] `crd_store_connect()` gains `check_model = TRUE`; its three
      `return(ragnar_store_connect(...))` sites collapse into one tail helper so the check cannot
      be added to two paths and missed on the third
- [x] "Could not check" uses `rlang::warn(.frequency = "once")`, keyed on reason **and** store
      location
- [x] Offline fixtures — **the planned one was wrong.** `@embed` on a copy of the cached store
      shares its duckdb connection, so `.crd_store_open()`'s failure cleanup closed the *shared*
      connection and every later test file lost retrieval. Replaced by a throwaway `file.copy()`
      of the store with `UPDATE metadata SET embedding_size = 8` — no mocked bindings, real
      `ragnar_store_connect()` unserialise path
- [x] Mutation table: restore the defect and prove each guard fires

## Phase 5: The stale-claim sweep, docs, NEWS, version

#29's correct statement that connect *cannot* see a model change becomes half-true: still true
of **md5**, false of connect as a whole. Grep the sentence, not the one instance.

*The line numbers below are as written at plan time and went stale the moment Phase 1 shifted
the file. They are left as written; the sweep was done by grepping the sentence, which is the
rule the phase exists to apply.*

- [x] `R/store.R:169-170` (`@details`) and `:790-793` (dimension remedy comment)
- [x] `R/store.R:905` / `man/crd_search.Rd:106` — the `cred_retrieval_fallback_dimension` entry
- [x] `man/crd_store_connect.Rd:50-51`
- [x] `CLAUDE.md:202-206`
- [x] `tests/testthat/test-store-fallback.R` — **the plan was wrong here.** The two
      `expect_no_match(msg, "crd_store_connect")` assertions must NOT reverse: they pair with
      the "md5 CAN see a stale file" block, and reversing one collapses the pair into two tests
      asserting the same thing. The prescribed one-liner also gathers exactly the evidence the
      connect probe gathers, more cheaply, and covers the in-session swap no reconnect can see.
      Comments rewritten to record the reasoning; assertions and message text untouched
- [x] Two sites the plan MISSED, both found by the review, both reading as authoritative: the
      `CLAUDE.md` bullet asserting that md5 is what catches a model change, and
      `test-store-fallback.R`'s own file header stating the opposite of what the file proves
- [x] `NEWS.md` 0.3.2 contradicted itself eighteen lines apart — it said md5 verification exists
      to catch a width mismatch, and then that md5 is structurally unable to see one. Corrected
      with a note saying so; the rest of 0.3.2 left as history
- [x] `devtools::check()` measured against a worktree of `origin/main`: identical 3 warnings /
      4 notes, so all pre-existing. Filed as
      [#32](https://github.com/NewGraphEnvironment/cred/issues/32)
- [x] `devtools::document()`, `NEWS.md`, version bump to 0.4.0 as the final commit
- [x] CLAUDE.md design-decision bullet

## Validation

- [x] `devtools::test()` passes
- [x] `lintr::lint_package()` is 0 lints
- [x] `/code-check` clean
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope

Detecting a model whose **weights** changed at constant width — no local signal exists for it.
The docs say so rather than implying the check is complete.

## Mutation table

Run in an isolated copy of the tree, control green:

| mutation | failures |
|---|---|
| M1 delete the check from `.crd_store_open()`'s tail | 3 |
| M2 `.crd_embed_width()` always `NA` | 10 |
| M3 restore `.crd_ollama_check()`'s old fixed remedy | 8 |
| M4 probe warning reuses the search fallback id | 1 |
| M5 check warns unconditionally | 4 |
| M6 vss branch unwrapped again | 9 |
| control | **0** |

Two more after `/code-check` round 1, both of which it found by measuring rather than reading:

| mutation | failures |
|---|---|
| M7 delete `ok <- TRUE` from `.crd_store_open()` | 0 → **2** |
| M8 re-gate the `dimension` remedy on `context == "search"` | 0 → **2** |

M7 is the one worth keeping in mind: the cleanup's *error* branch had a test and its *success*
branch did not, so a mutant that handed back a shut-down connection on **every** default connect
left the suite green at 587 passes. The table itself was built to prove the absence of exactly
that, and it had the gap.

Five more after round 2, every one a guard that decides **not** to act:

| mutation | failures |
|---|---|
| M9 delete the whole `on.exit` cleanup in `.crd_store_open()` | 0 → **1** |
| M10 drop `.crd_model_norm()` from the label compare | 0 → **1** |
| M11 drop `.crd_is_model_name(meta$model)` from the label tier | 0 → **1** |
| M13 drop `!.crd_have(got)` from the width compare | 0 → **1** |
| M14 a 4th `context` whose `dimension` dispatch falls through | 0 → **1** |

M9's first fix was itself vacuous and the mutation caught it: `local_store_copy_bad_width()`
calls `DBI::dbDisconnect()` on its own, so a counter armed before the fixture was built sat at 1
however the cleanup behaved. M14 is only meaningful as the *pair* — the derived roster goes red
on a 4th context, the roster round 1 hardcoded stays green.

M2, M4 and M5 first reported **0** — three broken probes, not three test gaps. M2 and M5 used
`perl -0`, where `^` anchors to the start of the *file*, and bash expanded the `$` in
`meta$size`; redone in Python they fire. M4 was a real gap: the collision test rebuilt the
expected id from a literal, so changing the code's id could not fail it. Fixed by extracting
`.crd_store_probe_id()` and adding the behavioural test — connect warns, then the search on the
same store must still warn.
