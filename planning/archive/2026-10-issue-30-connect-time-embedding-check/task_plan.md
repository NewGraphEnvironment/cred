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

Seven more after round 3, which computed the candidate set rather than recalling it — 38 code
decision points, 6 reachable with no mutation:

| mutation | failures |
|---|---|
| N1 delete the `connect`-context fallthrough | 0 → **2** |
| N2a drop `entry` forwarding on the verified sites | 0 → **2** |
| N2b drop `check_model` forwarding on the verified sites | 0 → **1** |
| N3 restore the vss self-contradiction | 0 → **1** |
| N5 drop `.crd_have(entry$embedding_model)` | 0 → **1** |
| N6 reset helper bypasses the derived id set | 0 → **1** |
| N7 `.crd_all_warning_ids()` drops two of three schemes | 0 → **2** |

N6 took two attempts for the reason the whole review keeps finding: the first assertion pinned
`.crd_all_warning_ids()`, which the mutation did not touch — it rebuilt a narrower list inside
the helper. Pinning the *wrapper's* route through the derived set is what closes it, the same
shape as Phase 1's assertion that `.crd_retrieval_fallback_msg()` still calls
`.crd_embed_remedy()`.

Four more after round 4, which re-computed the enumeration (43 code decision points, 50 test
assertions) rather than carrying round 3's numbers forward:

| mutation | failures |
|---|---|
| M-A drop `entry` at the **download** site only | 0 → **2** |
| M-B hardcode `check_model = TRUE` at the download site | 0 → **1** |
| P2 `stop()` before the download branch | 0 → **2** |
| P5 an emitter passes a 4th id function outside the reset set | 0 → **1** |

**The lesson from M-A/M-B is general and worth carrying out of this issue:** round 3's N2a/N2b
dropped the arguments from *both* verified return sites at once, so a single test on the
md5-match site turned them red — while the download site had never been executed by any test at
all (P2 was silent). **A mutation applied to N sites at once certifies coverage of exactly one of
them.** Mutate one site at a time, or the table over-claims in exactly the direction it exists
to prevent.

P5 is round 3's finding 5 reproduced inside its own fix, one axis over: the fix made
`.crd_all_warning_ids()` derive from the three id *functions*, and its test restated the same
three — so pointing an emitter's `.frequency_id` at a fourth function escaped both while leaving
`.crd_store_label_id()` defined, unused and apparently covered. The axis that matters is which
ids the **emitters** pass, so the guard now walks the namespace for them.

## The mechanism, as round 3 named it

Every defect across the three rounds is **a check whose reference was restated rather than
derived, over one axis of a fact that has more than one axis** — and the restated axis happened
to agree with the code when it was typed:

| restated | actual axis |
|---|---|
| `reason` | `reason × context` |
| the `context` roster as a literal | `match.arg()`'s list |
| `crd_store_connect()`'s *return sites* | the *arguments* those sites forward |
| one `.frequency_id` scheme | three |

Plus the degenerate form needing no second axis: an assertion of **absence**, where rlang's
once-per-session muffling supplies the absence for free. Second half of the mechanism: each
round's fix was written from reading rather than from a mutation, which is why two of round 3's
findings sat inside earlier rounds' fixes — and why mine did too.

M2, M4 and M5 first reported **0** — three broken probes, not three test gaps. M2 and M5 used
`perl -0`, where `^` anchors to the start of the *file*, and bash expanded the `$` in
`meta$size`; redone in Python they fire. M4 was a real gap: the collision test rebuilt the
expected id from a literal, so changing the code's id could not fail it. Fixed by extracting
`.crd_store_probe_id()` and adding the behavioural test — connect warns, then the search on the
same store must still warn.

## Review loop outcome

Five rounds. Rounds 1-4 each found real defects, and **every round from 2 on found at least one
inside the previous round's fix** — which is the one condition that keeps the loop open, so it
was terminated by a computed enumeration rather than by a quiet round.

Round 5: **closed, computed.** 43 code decision points — 32 covered by a measured mutation, 3
behaviour-preserving, 5 unreachable, 3 cosmetic-and-accepted, **0 uncovered and consequential**.
50 test-side absence assertions, closed mechanically by running both changed test files twice in
one session and getting identical results, so nothing is green because of rlang frequency state
in either direction. For the first time the loop's signature does not appear, and it was looked
for on both axes earlier fixes failed on.

### Known limits, recorded rather than chased

- The namespace walk that checks every `.frequency_id` an emitter passes **cannot see a
  brand-new emitter that passes a bare variable** rather than a call. Round 5 reports that gap as
  *unproven-closed* rather than open — a mutation of that shape goes red, but via a sibling
  assertion, so the walk is not what caught it. Recorded here rather than papered over.
- Three decision points are uncovered by choice, all cosmetic (no user-visible consequence
  established by any round).

### One lesson that belongs outside this issue

**A mutation applied to N sites at once certifies coverage of exactly one of them**, and the
cheap guard is to prove a branch runs at all — a `stop()` at the top of it must turn something
red — before trusting any mutation on it. That is general, not about cred, and belongs in
`soul/conventions/code-check.md` beside "Restore the bug and prove the guard fires". Drafted, not
yet filed: a soul convention edit is its own change.
