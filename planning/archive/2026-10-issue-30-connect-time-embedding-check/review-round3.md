# Review round 3 — branch `30-no-connect-time-embedding-model-check-cr`

Reviewer: subagent code review, read-only. Read in full: the branch diff (11 files),
`R/store.R`, `tests/testthat/test-store-embed-check.R`,
`tests/testthat/test-store-fallback.R`, `tests/testthat/helper-store.R`,
`DESCRIPTION`, `CLAUDE.md`, `planning/active/review-round1.md`,
`planning/active/review-round2.md`, `planning/active/task_plan.md`, and the
`/code-check` checklist.

Every probe ran in a throwaway copy at `…/scratchpad/rev3/cred`. The working tree was
never modified (`git status --short` empty before and after, confirmed both sides).

**Control, in the copy, branch as committed:** `devtools::test(filter = "store")` →
`FAIL 0 | WARN 0 | SKIP 0 | PASS 479`.

---

## Mechanism

**Every defect in rounds 1–3 is a check whose reference was *restated* rather than
*derived*, over one axis of a fact that has more than one axis — and the restated axis
agreed with the code at the moment it was typed.** The agreement is a coincidence, so the
check is green by construction and stays green when the code moves along the axis the
check does not see: `reason` while the dispatch is `reason × context` (round 1b); the
`context` roster typed as a literal while `match.arg()` owns it (round 2a); the *return
sites* of `crd_store_connect()` while what matters is the *arguments* those sites forward
(new, finding 2); one of three `.frequency_id` schemes (finding 5); and — the version that
needs no second axis at all — an assertion of **absence**, where rlang's once-per-session
muffling supplies the absence for free (round 2b, and the parent's own first fix for round
2c).

The second half of the mechanism is why it keeps recurring: **each round's fix is itself
written from reading, not from a mutation.** Round 1's fix contained round 2's defect;
round 2's own fix for finding 3 was vacuous on its first draft; and this round found
round 2's finding-5 fix (N3) and round 1's `context` ungating (N1, at the fallthrough
rather than at `dimension`) both landed with no mutation proving them. `task_plan.md`'s
table has grown M1–M14 and still introduces itself as "restore the defect and prove each
guard fires" while six decision points have no mutation.

---

## Enumeration (with its size, and how I computed it)

### A. Every decision point in the new/changed code that decides **not** to act

Computed, not recalled: a Python pass over `R/store.R` restricted to the line ranges of
the functions this branch added or changed (`.crd_embed_width`, `.crd_store_loc`,
`.crd_store_probe_id`, `.crd_check_store_embedding`, `.crd_store_open`,
`crd_store_connect`, `.crd_fallback_model`, `.crd_embed_remedy`, `.crd_retrieval_abort`,
`.crd_ollama_check`, the `crd_search` method `switch`), matching
`return(|if (|tryCatch|\|\||&&|!is|!\.|!isTRUE|match.arg` with comment lines dropped — 58
raw hits, reduced to **38 distinct decision points** after removing the positive branches
and splitting compound conditions into their conjuncts. The argument-forwarding rows
(#33–36) are added by hand because they are not conditionals; they belong in the set
because they are the axis round 1's structural guard was written over and does not see.

| # | site | guard | status |
|---|---|---|---|
| 1 | `:169` | `is.null(x)` → NA | behaviour-preserving if removed (`ncol(NULL)` NULL, `is.atomic(NULL)` TRUE, `length 0 < 1`) |
| 2 | `:170` | `!is.null(ncol(x))` | covered — `:205`–`:208` |
| 3 | `:172` | `is.atomic(x)` | covered — `:207` vs `:211` |
| 4 | `:181` | `length(n) != 1L` | unreachable (`ncol`/`length` are length 1) |
| 5 | `:181` | `is.na(n)` | covered — `:211` |
| 6 | `:181` | `n < 1L` | covered — `:212` |
| 7 | `:196` | `tryCatch(store@location)` | **uncovered**, unreachable in production |
| 8 | `:199` | `!.crd_have(loc)` → `"unknown-store"` | **uncovered**, unreachable in production |
| 9 | `:269` | `!.crd_have(name)` | **uncovered**, unreachable (`.crd_store_open` always forwards a name) |
| 10 | `:273` | `!is.null(entry)` | behaviour-preserving if removed (`NULL$x` is `NULL`) |
| 11 | `:273` | `.crd_have(entry$embedding_model)` | **UNCOVERED and production-reachable** — N5, finding 3 |
| 12 | `:274` | `.crd_is_model_name(meta$model)` | covered — M11 / `:566` |
| 13 | `:275` | `!identical(.crd_model_norm(…), …)` | covered — M10 / `:312` (armed) |
| 14 | `:293` | `!.crd_have(meta$size)` | covered — `:274` |
| 15 | `:295` | `tryCatch(store@embed)` | **uncovered**, unreachable (an S7 property read does not raise) |
| 16 | `:296` | `!is.function(embed)` | covered — **N6, FAIL 1** |
| 17 | `:298` | `tryCatch(embed(…))` | covered — `:251` |
| 18 | `:300` | `inherits(probe, "condition")` | covered — `:251` |
| 19 | `:315` | `return()` after the probe warning | behaviour-preserving if removed **only because #20a exists** (see note) |
| 20a | `:319` | `!.crd_have(got)` | covered — M13 / `:551` |
| 20b | `:319` | `identical(got, as.integer(meta$size))` | covered — `:246`, `:443` |
| 21 | `:363` | `!isTRUE(check_model)` | covered — `:369` |
| 22 | `:375`/`:379` | `if (!ok)` / `ok <- TRUE` | covered — M7 / `:494` |
| 23 | `:374-377` | the `on.exit` handler itself | covered — M9 / `:517` |
| 24 | `:936` | `!is.null(cond)` | covered — the abort path passes no `cond` (`:225`, `:443`) |
| 25 | `:950` | `.crd_is_model_name(requested)` | covered — `:54`, `:86` |
| 26 | `:1064` | `identical(context, "build")` inside `dimension` | covered — M14 / derived product guard |
| 27 | `:1130` | `identical(context, "build")` in the fallthrough | covered — **N4, FAIL 2** |
| 28 | `:1137` | `identical(context, "connect")` in the fallthrough | **UNCOVERED** — N1, finding 1 |
| 29 | `:1507` | `!is.null(base_url)` | covered |
| 30 | `:1514` | `is.null(cond)` → return | covered — `:127` |
| 31 | `crd_search` | `bm25` deliberately **not** wrapped | covered — `:174` |
| 32 | `crd_search` | `vss` `tryCatch` | covered — M6 |
| 33 | `:506` | forwards `entry = entry` (md5-match path) | **UNCOVERED** — N2a, finding 2 |
| 34 | `:506` | forwards `check_model = check_model` (md5-match path) | **UNCOVERED** — N2b, finding 2 |
| 35 | `:544` | forwards `entry = entry` (download path) | **UNCOVERED** — no test reaches the branch at all |
| 36 | `:544` | forwards `check_model = check_model` (download path) | **UNCOVERED** — same |
| 37 | `:1203` | round-2 finding 5's reworded clause | **UNCOVERED** — N3, finding 4 |
| 38 | `:1024` | `match.arg(context)` | covered — the derived roster at `test-store-fallback.R:693` |

**Size: 38.** Covered by a measured mutation: **24**. Behaviour-preserving if removed:
**3** (#1, #10, #19). Structurally unreachable, defensive only: **5** (#4, #7, #8, #9,
#15). **Uncovered and reachable: 6** (#11, #28, #33/34, #35/36, #37) → four distinct
findings.

Note on #19: deleting the `return(invisible(NULL))` after the probe-failed warning is
currently harmless, because `.crd_embed_width(<condition>)` is `NA` and #20a then returns
`NULL`. The two are therefore *coupled*: if #20a is ever relaxed, #19's absence turns a
dead-Ollama connect into an `abort("its recorded embedder now returns: NA-wide")`. That is
one fact guarded twice with nothing saying so — worth a comment, not a change.

### B. Every absence/warning assertion in the two changed test files

Computed by brace-matching `test_that()` blocks and matching
`expect_(silent|no_error|no_match|no_warning|no_condition|warning)`, then intersecting the
assertion's expression with the three frequency-guarded emitters
(`.crd_check_store_embedding`, `crd_search`, `crd_store_connect`).

- **47** absence/warning assertions in total.
- **29** cannot be affected by rlang's warning state at all — they match a *string*
  returned by `.crd_embed_remedy()` / `.crd_retrieval_fallback_msg()` /
  `.crd_ollama_check()`, with no condition in the loop.
- **18** pass through a frequency-guarded emitter. **13 of those are isolated** (12 by
  `local_fallback_warnings_always()`, which I verified against `rlang:::needs_signal` does
  **not** consume the sentinel — the `verbosity == "verbose"` branch returns before
  `env_poke()`, measured: fires twice under verbose, then once more with the guard back
  on; plus `test-store-embed-check.R:470`, which re-arms both ids inline).
- **The 5 unisolated ones are each immune for a reason I checked rather than assumed:**

| site | why it cannot pass vacuously |
|---|---|
| `embed-check.R:248` | the only defect it rejects **aborts** (healthy-width compare); `entry = NULL`, so no warning tier is reachable |
| `embed-check.R:283` | dropping `:293` **aborts** (`as.integer(NA)` compare) |
| `embed-check.R:291` | **measured** — N6 → `FAIL 1`, the mutant aborts |
| `embed-check.R:299` | a *positive* assertion (`expect_s3_class(cnd, …)`), so a spent slot makes it **fail**, not pass |
| `fallback.R:579` | pre-existing, not in this diff; its slot is fresh because `:470` resets on exit and the blocks between it use verbose |

**Enumeration B is clean.** Round 2's finding-1 class is closed, and `:312`, `:551` and
`:566` each carry a comment saying why the arming line is load-bearing. One residual
order-dependency worth a comment but not a change: `embed-check.R:294`/`:312` remain a
pair whose first member must run first, and `:294` is the one that fails if it does not.

---

## Findings

- **[fragile]** `R/store.R:1137` — the `connect` context's fallthrough branch has no
  test, and deleting it is silent. **N1** (delete the whole
  `if (identical(context, "connect")) { … }` block, so `connect` falls through to the
  searcher's text) → **`FAIL 0 | PASS 479`**, unchanged from control. The mutant's output,
  printed verbatim from the copy:

  ```
    cred does not recognise this failure, so no remedy is prescribed. Semantic
    retrieval is unavailable and the store itself may be at fault - confirm it is
    the file the manifest describes with crd_store_connect().
  ```

  That is `crd_store_connect()` telling the reader to run `crd_store_connect()`, and
  "the store itself may be at fault" for a probe failure that is not evidence about the
  store — which is exactly what `:304`–`:306` has just said it is not. This is round 1's
  finding 2 one branch over: there the recognised `dimension` reason served the
  unrecognised-failure text for two of three contexts; here the `unknown` reason serves
  the *wrong caller's* text for one of three. The asymmetry is measured, not argued:
  **N4** (same deletion applied to the `build` branch at `:1130`) → **`FAIL 2`**, because
  `test-store-embed-check.R:399` pins the build text explicitly. `connect` has no such
  block. The derived product guard at `test-store-fallback.R:693` cannot see it: it uses
  each context's fallthrough only as a *reference value*, and never asserts anything
  about the reference itself.

  Fix: the complement of `:399` and `:418`, three lines —
  ```r
  test_that("the connect-time unknown remedy does not send the user back to connect", {
    msg <- .crd_embed_remedy("unknown", simpleError("odd"), context = "connect")
    expect_no_match(msg, "crd_store_connect", fixed = TRUE)
    expect_match(msg, "BM25 needs no embedding", fixed = TRUE)
  })
  ```

- **[fragile]** `R/store.R:506` and `R/store.R:544` — **no test in the suite exercises
  `crd_store_connect()`'s `verify = TRUE` paths**, so neither site's `entry` nor its
  `check_model` forwarding is constrained. Grepped: all nine
  `crd_store_connect(` calls in `tests/` pass `verify = FALSE` (or test the missing-file
  guard). Two consequences, each measured on the md5-match site alone with
  `filter = "store"`:

  | mutation | result |
  |---|---|
  | **N2a** — drop `entry = entry` from `:506` (and `:544`) | **`FAIL 0 \| PASS 479`** |
  | **N2b** — drop `check_model = check_model` from `:506` (and `:544`) | **`FAIL 0 \| PASS 479`** |

  N2a matters because **the label tier is reachable in production by no other route**:
  `verify = FALSE` passes `entry = NULL` by design, so the entire tier-2 warning can be
  disconnected from every real connect and only the direct unit tests — which hand-build
  their own `entry` — keep passing. N2b is the user-facing half: `check_model = FALSE` is
  the documented escape for a mismatched store, and on the normal bucket-configured path
  nothing says it is honoured.

  This is round 1's `.crd_store_open()` finding at the next level in. The structural guard
  at `test-store-embed-check.R:385` computes "no site calls `ragnar::ragnar_store_connect`
  directly and more than one calls `.crd_store_open`" — it enumerates **sites**, and the
  axis that now carries the behaviour is **arguments**. A fourth path, or a site that
  forgets one keyword, passes it.

  Fix, and I proved it in both directions in the copy — the md5-match branch is reachable
  entirely offline by mocking `.crd_manifest_read` to return an entry whose `md5` is
  `tools::md5sum()` of a throwaway copy:

  | probe | control | N2a | N2b |
  |---|---|---|---|
  | label warning fires through a real `crd_store_connect(source = "s3://x/y/")` | **pass** | **FAIL** (`cnd` is `NULL`) | pass |
  | `check_model = FALSE` on the same path returns a usable store | **pass** | pass | **FAIL** (aborts `cred_store_embedding_mismatch`) |

  Both blocks are in the copy at `tests/testthat/test-store-embed-check.R:599` and `:625`
  if you want them verbatim; they need no new helper and no network.

- **[fragile]** `R/store.R:273` — `.crd_have(entry$embedding_model)` is the third
  tolerance guard in the label tier with no mutation, and it is **production-reachable**.
  **N5** (drop the conjunct) → **`FAIL 0 | PASS 479`**. The reachable shape is a manifest
  entry with no `embedding_model` key, which `.crd_manifest_merge()` explicitly produces —
  CLAUDE.md's own bullet says it "passes untouched entries through verbatim, including
  shapes this version does not recognise". Measured on the mutant:
  `entry$embedding_model[1]` is `NULL`, `.crd_model_norm(NULL)` is `character(0)`,
  `identical()` against the store's normalised model is `FALSE`, so every connect against
  such an entry warns with an empty line:

  ```
    the store records:  mxbai-embed-large
    the manifest says:
  ```

  Same class as M11 and M13, which round 2 found; the enumeration that produced those two
  stopped at the two guards it had noticed rather than walking the tier's four conjuncts.

- **[fragile]** `R/store.R:1203-1204` — round 2's finding 5 was fixed and the fix has no
  test. **N3** (restore the exact removed wording, `'Both other methods still work on
  this store: "hybrid" would have / degraded to BM25 with a warning, and "bm25" needs no
  embedding at all.'`) → **`FAIL 0 | PASS 479`**. `test-store-embed-check.R:139` asserts
  only that `"hybrid"` and `"bm25"` appear in the message, which both wordings satisfy, so
  the self-contradiction round 2 measured is reintroducible in silence. The property, not
  the text, is the assertion to add: on the `unknown` reason the message must not claim
  anything about the store — `expect_no_match(msg, "still work on this store")` paired
  with the existing `expect_match(msg, "may be at fault")` on the same string.

- **[fragile]** `tests/testthat/helper-store.R:314` — `local_reset_fallback_warnings()`
  loops `.crd_fallback_reasons()` against **one** of the three `.frequency_id` schemes this
  branch now has (`.crd_retrieval_fallback_id`), and nothing in its name or its roxygen
  says so. The other two are `.crd_store_probe_id()` and the still-inlined
  `paste0("cred_store_model_label_", .crd_store_loc(store))` at `R/store.R:289`. Latent
  today — I checked the callers, and all three (`test-store-fallback.R:590`, `:612`,
  `:628`/`:629`) are blocks about the search-fallback channel only — but it is the exact
  shape that produced round 2's finding 1, pre-positioned for the next block that needs to
  re-arm a probe or label warning. The tell is already in the tree:
  `test-store-embed-check.R:480-483` hand-rolls its own two-scheme re-arm instead of calling
  the helper. Either widen the helper to loop over the schemes
  (`list(.crd_retrieval_fallback_id, .crd_store_probe_id)` plus an extracted label id) or
  rename it to say which channel it covers.

### Also worth a line, not findings

- `task_plan.md`'s mutation table still reads as a completeness claim. Round 2 asked for a
  line saying which guards are covered by inspection only; the table instead grew M9–M14,
  and six more decision points (#11, #28, #33–36, #37) have no row. Enumeration A above is
  the form that terminates: it is computed from the file and states its own size.
- `.crd_store_loc()` (`:195`) was extracted so a test could ask the code for its key, but
  `.crd_retrieval_fallback_id()` (`:1230-1233`) still carries a hand-copied duplicate of the
  same four lines, with the same comment. One fact, two implementations; the tested one is
  the copy (`test-store-fallback.R:739`, `:742`) and the extracted one is untested (#7, #8).
  Pointing `.crd_retrieval_fallback_id()` at `.crd_store_loc()` removes the duplicate and
  covers both.

---

## Mutations run (all in the copy; control `FAIL 0 | WARN 0 | SKIP 0 | PASS 479`)

| mutation | result |
|---|---|
| **N1** — delete `.crd_embed_remedy()`'s `context == "connect"` fallthrough branch | **0 failures** — finding 1 |
| **N2a** — drop `entry = entry` from both `verify = TRUE` `.crd_store_open()` sites | **0 failures** — finding 2 |
| **N2b** — drop `check_model = check_model` from both `verify = TRUE` sites | **0 failures** — finding 2 |
| **N3** — restore round-2 finding 5's contradicting vss wording | **0 failures** — finding 4 |
| **N4** — delete the `context == "build"` fallthrough branch (instrument control) | **2 failures** — the instrument works; `build` is covered and `connect` is not |
| **N5** — drop `.crd_have(entry$embedding_model)` from the label tier | **0 failures** — finding 3 |
| **N6** — drop `!is.function(embed)` from `.crd_check_store_embedding()` | **1 failure** — covered |
| proposed md5-path label probe, on control / on N2a | **pass / FAIL** — guard proven both directions |
| proposed md5-path `check_model = FALSE` probe, on control / on N2b | **pass / FAIL** — guard proven both directions |
| `rlang:::needs_signal` under `rlib_warning_verbosity = "verbose"` | fires twice, sentinel unconsumed — `local_fallback_warnings_always()` leaks no state |

---

## Verdict

**Not fully covered.** Computed, not asserted: the candidate set is 38 decision points
(method in Enumeration A); 24 are covered by a measured mutation, 3 are
behaviour-preserving if removed, 5 are structurally unreachable, and **6 are reachable with
no mutation** — four distinct defects, each measured above at `FAIL 0` against the shipped
suite.

The **test-side** enumeration (B) **is** complete: 47 absence/warning assertions, 18
exposed to rlang's frequency state, 13 isolated and the remaining 5 immune for a reason I
checked individually. Round 2's finding-1 class is closed.

What is not closed is the **code-side** axis, and the reason the loop should not stop here
is that two of this round's four findings sit *inside* earlier rounds' fixes — N1 is round
1's `context` ungating examined at the fallthrough instead of at `dimension`, and N3 is
round 2's finding-5 remedy. That is the same "defect inside the previous fix" signature
that justified rounds 2 and 3. A fourth round is warranted **after** these four fixes land,
scoped to the fixes themselves and bounded by Enumeration A: terminate when every row of
that table reads covered, unreachable, or behaviour-preserving, with the mutation that says
so — not when a round reports nothing.
