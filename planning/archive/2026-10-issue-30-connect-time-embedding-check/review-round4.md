# Review round 4 — branch `30-no-connect-time-embedding-model-check-cr`

Reviewer: subagent code review, read-only. Read in full: the branch diff (15 files),
`R/store.R`, `tests/testthat/test-store-embed-check.R`,
`tests/testthat/test-store-fallback.R`, `tests/testthat/helper-store.R`,
`DESCRIPTION`, `CLAUDE.md`, `planning/active/review-round1.md`, `review-round2.md`,
`review-round3.md`, `planning/active/task_plan.md`, and the `/code-check` checklist.

Every probe ran in a throwaway copy at
`…/scratchpad/rev4/cred` (`cp -r`). The real working tree was
`git status --short` empty before and after, confirmed both sides; only this file was
written to it.

**Control, in the copy, branch as committed (`566adee`):**
`devtools::test(filter = "store")` → `FAIL 0 | WARN 0 | SKIP 0 | PASS 496`;
full `devtools::test()` → `FAIL 0 | WARN 0 | SKIP 2 | PASS 628`; `lintr::lint_package()` → 0.
`test-store-embed-check.R` alone: 110 assertions, **SKIP 0** — the two new `verify = TRUE`
blocks genuinely run on this machine, and they also run against the **installed** package
(`R CMD INSTALL` to a temp lib, then `test_dir(load_package = "installed")`) → 110 passes,
so `local_mocked_bindings()` reaching cred's namespace is not a `load_all()` artefact.

---

## Enumeration

### A. Code-side decision points in the changed code

**Method, re-computed rather than carried forward.** Derived the changed/added line set of
`R/store.R` from `git diff origin/main...HEAD -U0` (522 lines), found the top-level functions
containing at least one of them (**13**: `.crd_embed_width`, `.crd_store_loc`,
`.crd_store_label_id`, `.crd_store_probe_id`, `.crd_check_store_embedding`,
`.crd_store_open`, `crd_store_connect`, `.crd_fallback_model`, `.crd_embed_remedy`,
`.crd_retrieval_fallback_msg`, `.crd_retrieval_abort`, `crd_search`, `.crd_ollama_check` —
round 3's twelve plus the `.crd_store_label_id` its own fix added), then matched
`return(|if (|tryCatch|\|\||&&|!is|!\.|!isTRUE|match.arg` on **changed lines only**, comments
dropped → **38 raw hits**. Splitting compound conditions into conjuncts, dropping
positive-branch `return(paste0(` lines, and adding the argument-forwarding rows at each
`.crd_store_open()` call site (not conditionals, but the axis the structural guard does not
see) gives the candidate set.

**Size: 43** — round 3's 38, plus five rows round 3's table did not carry:

| # | site | row | status this round |
|---|---|---|---|
| 1–32, 38 | — | round 3's rows, unchanged by this commit | **24 covered**, 3 behaviour-preserving (#1, #10, #19), 5 unreachable (#4, #7, #8, #9, #15) |
| 11 | `:290` | `.crd_have(entry$embedding_model)` | **now covered** — N5 → `FAIL 1` |
| 28 | `:1154` | `identical(context, "connect")` fallthrough | **now covered** — N1 → `FAIL 2` |
| 33 | `:523` | forwards `entry = entry` (md5-match site) | **now covered** — N2a′ → `FAIL 2` |
| 34 | `:524` | forwards `check_model = check_model` (md5-match site) | **now covered** — N2b′ → `FAIL 1`; M-C → `FAIL 3` |
| 35 | `:561` | forwards `entry = entry` (**download** site) | **UNCOVERED and reachable** — M-A → `FAIL 0` |
| 36 | `:562` | forwards `check_model = check_model` (**download** site) | **UNCOVERED and reachable** — M-B → `FAIL 0` |
| 37 | `:1220` | round-2's vss-contradiction wording | **now covered** — N3 → `FAIL 1` |
| 39 | `:512` | forwards `name = name` (verify = FALSE site) | uncovered, **cosmetic only** — P6 → `FAIL 0` |
| 40 | `:523` | forwards `name = name` (md5-match site) | uncovered, **cosmetic only** — P6 → `FAIL 0` |
| 41 | `:561` | forwards `name = name` (download site) | uncovered, **cosmetic only** — P6 → `FAIL 0` |
| 42 | `:513` | forwards `check_model = check_model` (verify = FALSE site) | covered — P7 → `FAIL 1` |
| 43 | `:306` | the label warning's `.frequency_id` vs the helper's roster | **UNCOVERED** — P5 → `FAIL 0`; new row, created by round 3's own fix |

**Size 43. Covered by a measured mutation: 29. Behaviour-preserving if removed: 3.
Structurally unreachable: 5. Uncovered but cosmetic-only: 3 (#39–41). Uncovered and
consequential: 3 (#35, #36, #43)** → two findings.

### B. Test-side absence/warning assertions

**Method.** Brace-matched `test_that()` blocks in the two changed test files and matched
`expect_(silent|no_error|no_match|no_warning|no_condition|warning)`, comments dropped.

- **50** assertions (round 3's 47 plus the three this commit added: `embed-check.R:602`,
  `:620`, `:634`).
- **20** pass through a frequency-guarded emitter (round 3's 18 plus `:634`, plus
  `fallback.R:449`). The other 30 match a string returned by `.crd_embed_remedy()` /
  `.crd_retrieval_fallback_msg()` / `.crd_ollama_check()`, or — for `:620` — the
  `.crd_retrieval_abort()` error path, which carries no frequency guard.
- **Each of the three new ones is proven non-vacuous by a mutation**, not by reading:
  `:602` → N1 `FAIL 2`; `:620` → N3 `FAIL 1`; `:634` → N5 `FAIL 1`.

**B is closed, and this round closed it by derivation rather than by per-site reasoning.**
Round 3 argued its five unisolated assertions immune one at a time. The mechanical form is
to run both changed files **twice in one session**: the once-per-session sentinel is
session-scoped, so any assertion green only because its slot was fresh must break on the
second pass. Measured — pass 1 and pass 2 identical, 110 + 178 assertions, zero failures,
zero warnings. No assertion in either file depends on fresh *or* spent frequency state.

The broadened `local_reset_fallback_warnings()` (now 11 ids, was 5) cannot have introduced a
vacuous pass in the other direction either: it only ever *re-arms*, so it can make more
warnings fire, never fewer, and the double-run confirms nothing depended on a spent probe or
label slot.

---

## The mechanism, one axis over

Round 3 named it: a check whose reference is **restated rather than derived**, over one axis
of a fact that has more than one axis. This round's residue is that mechanism moved onto the
**instrument**:

> **A mutation applied to N sites at once certifies coverage of exactly one of them.**

Round 3's N2a/N2b dropped `entry` and `check_model` from *both* verified `.crd_store_open()`
sites simultaneously, and `task_plan.md:181-182` records them as "drop … forwarding on the
verified **sites**". Both rows are literally true — dropping from both goes red — and both
read as a claim that both sites are covered. One test on the md5-match site is enough to turn
that mutation red, so the fix written from it stops there. Measured: dropping either argument
from the **download** site alone leaves the suite at `FAIL 0`.

Same family as `code-check.md`'s *"A fix lands in one of two callers that share a harness"*,
arriving through the mutation rather than through the fix — and it is the same shape as the
defect round 1 found in `.crd_store_open()` itself (a check wired into two of three return
sites), two levels in.

Row #43 is the second half of the signature the loop has shown every round: **a defect inside
the previous round's fix.** Round 3's finding 5 was that the reset helper restated one of
three `.frequency_id` schemes. The fix extracted `.crd_store_label_id()`, derived
`.crd_all_warning_ids()` from the three id **functions**, and added a test whose comment says
"Derived, not counted" above a literal list of those three functions and an
`expect_length(…, 3L)`. The axis the helper must track is the set of ids the **emitters**
actually pass, which is not the same axis.

---

## Findings

- **[fragile]** `R/store.R:561-562` — **the download return site's `entry` and `check_model`
  forwarding is unconstrained.** Round 3's finding 2 was fixed on the md5-match site only;
  no test reaches the download branch at all. Measured in the copy, each mutation applied to
  `:561`/`:562` **alone**:

  | mutation | result |
  |---|---|
  | **M-A** — drop `entry = entry` from the download site | **`FAIL 0 \| PASS 496`** |
  | **M-B** — hardcode `check_model = TRUE` at the download site | **`FAIL 0 \| PASS 496`** |
  | **N2a′** — same drop at the md5-match site `:523` (instrument control) | `FAIL 2` |
  | **N2b′** — same hardcode at the md5-match site `:524` (instrument control) | `FAIL 1` |

  The asymmetry is the whole finding: the instrument works, and it is pointed at one of the
  two sites. Confirmed structurally too — **P2**, inserting `stop("DOWNLOAD BRANCH REACHED")`
  immediately before the download branch, leaves the suite at `FAIL 0 | PASS 496`, so no test
  in the package has ever executed those two lines.

  Why it matters in production rather than only in the table. `:561` is the branch taken when
  `verify = TRUE` (the default) **and** the local file is absent or its md5 differs — which is
  the *first* connect any new user makes, and every connect after the store is re-pushed.

  - Without `entry`, the manifest-label tier never fires on a freshly downloaded store. That
    is the route where a label disagreement is most likely to be real — you have just pulled
    somebody else's artefact — and `verify = FALSE` passes `entry = NULL` by design, so after
    this regression the tier would be unreachable from any real connect while all nine of its
    unit tests, which hand-build their own `entry`, stayed green.
  - Without `check_model`, `crd_store_connect(store, check_model = FALSE)` **errors** on a
    freshly downloaded width-mismatched store. The documented escape fails in exactly the
    situation where the user has no local copy to fall back to, and the message tells them to
    pass the flag they just passed.

  The structural guard at `test-store-embed-check.R:385` cannot see this — it greps
  `deparse(crd_store_connect)` for *call sites* (`ragnar::ragnar_store_connect` absent,
  `.crd_store_open` more than once) and asserts nothing about arguments. Grepped: no test in
  the package uses `deparse()` on `crd_store_connect` for anything else.

  **Fix, proven in both directions in the copy.** The download branch is reachable entirely
  offline by mocking `.crd_aws` alongside `.crd_manifest_read` — `.crd_aws` is the only other
  function on that path that touches the network, and the fixture supplies the bytes `aws s3
  cp` would have written:

  ```r
  local_mocked_download_of <- function(fixture, model = "nomic-embed-text (ollama)",
                                       size = 8L, env = parent.frame()) {
    dest_dir <- withr::local_tempdir(.local_envir = env)
    nm <- "downloaded"
    md5 <- tolower(unname(tools::md5sum(fixture)))
    testthat::local_mocked_bindings(
      .crd_manifest_read = function(source, profile = "") {
        list(stores = stats::setNames(
          list(list(documents = 12L, chunks = 99L, md5 = md5,
                    embedding_size = size, embedding_model = model)), nm))
      },
      .crd_aws = function(args, profile = Sys.getenv("AWS_PROFILE"),
                          clean_stdout = FALSE) {
        stopifnot(identical(args[[2]], "cp"))
        file.copy(fixture, args[[4]], overwrite = TRUE)
        list(out = character(), err = character(), status = 0L)
      },
      .env = env
    )
    withr::local_options(cred.store_source = "s3://bucket/prefix/", .local_envir = env)
    list(name = nm, dir = dest_dir)
  }
  ```

  with the two blocks being the complements of `:668` and `:694` (entry forwarded → label
  tier fires; `check_model = FALSE` honoured, and refused with it on). Measured:

  | probe | control | M-A | M-B |
  |---|---|---|---|
  | label warning fires through a real download | **pass** | **FAIL** (`cnd` not the condition) | pass |
  | `check_model = FALSE` returns a usable store on the download path | **pass** | pass | **FAIL** (aborts `cred_store_embedding_mismatch`) |

  Control with both blocks added: `FAIL 0 | PASS 499`. The md5 is taken from the fixture at
  test time and `dir` is a fresh `withr::local_tempdir()`, so the download branch is entered
  for the right reason — the file genuinely is not there.

  A derived alternative, which would also catch a *fourth* call site rather than only these
  two, is to extend the `:385` guard onto the argument axis — parse the `.crd_store_open(`
  calls out of `deparse(crd_store_connect)` and assert every one carries
  `check_model = check_model` and that exactly the two verified ones carry `entry = entry`.
  **I did not test that variant**; the behavioural pair above is the one measured in both
  directions, and it is the one I would land.

- **[fragile]** `tests/testthat/helper-store.R:322-328` and
  `test-store-embed-check.R:712-737` — **`.crd_all_warning_ids()` is a restated roster of the
  three id *functions*, and the test that polices it is restated the same way, so the axis
  that actually matters — which ids the *emitters* pass — is unguarded.** Round 3's finding 5,
  inside its own fix.

  **P5**, measured: add `.crd_store_label_id2()` and point the label warning's
  `.frequency_id` at it, leaving `.crd_store_label_id()` defined and unused →
  **`FAIL 0 | PASS 496`**. `local_reset_fallback_warnings()` then re-arms an id nothing emits
  and leaves the live label warning muffled, which is precisely the state round 3's finding 5
  described, and the test named *"the warning-reset helper covers every frequency scheme cred
  emits"* passes because `.crd_store_label_id(store)` is still in `ids` — the roster and the
  assertion agree with each other rather than with the code.

  `expect_length(unique(unlist(schemes)), 3L)` pins the count at three from a literal, so a
  fourth scheme escapes both the helper and its test. Today the emitter set *is* exactly the
  three — derived: `grep '\.frequency_id' R/` returns three call sites (`:306`, `:330`,
  `:1276`) against three id functions (`:215`, `:237`, `:1246`), all three in the helper — so
  this is latent, not live. It is the same latency round 3 recorded, which is why it is worth
  closing by derivation rather than by a fourth literal.

  **Fix, proven in both directions.** Derive the expected set from the emitters by walking the
  namespace, not from a list of function names:

  ```r
  test_that("the reset helper covers every frequency id cred actually EMITS", {
    store <- local_ragnar_store()
    ids <- .crd_all_warning_ids(store)
    ns <- asNamespace("cred")
    emitted <- character()
    for (nm in ls(ns, all.names = TRUE)) {
      f <- tryCatch(get(nm, envir = ns), error = function(e) NULL)
      if (!is.function(f)) next
      txt <- paste(deparse(f), collapse = " ")
      hits <- regmatches(txt, gregexpr("\\.frequency_id = [.A-Za-z0-9_]+\\(", txt))[[1]]
      for (h in hits) {
        fn <- sub("\\($", "", sub("^\\.frequency_id = ", "", h))
        g <- get(fn, envir = ns)
        for (r in .crd_fallback_reasons()) {
          emitted <- c(emitted, if (length(formals(g)) > 1L) g(r, store) else g(store))
        }
      }
    }
    expect_gt(length(emitted), 0L)
    expect_true(all(emitted %in% ids), info = paste(setdiff(emitted, ids), collapse = ", "))
  })
  ```

  | probe | result |
  |---|---|
  | derived guard on control | **`FAIL 0 \| PASS 498`** |
  | derived guard under **P5** | **`FAIL 1`**, reporting `cred_store_label_v2_<path>` |

  `expect_gt(length(emitted), 0L)` is load-bearing: without it the assertion is
  `all(character(0) %in% ids)`, which is `TRUE`, and a regex that stops matching makes the
  guard pass vacuously — the degenerate absence form this review keeps meeting.

### Checked and clear — not findings

Each of these was a plausible instance of the mechanism and each was probed rather than
reasoned about.

- **Does `local_mocked_manifest_for()`'s mock reach the real call site?** Yes. **P1**:
  inserting `stop("REAL .crd_manifest_read REACHED")` as the first line of the real
  `.crd_manifest_read()` leaves the suite at `FAIL 0 | PASS 496`, so no test in the package
  ever reaches it. The `.env` / `.local_envir` plumbing applies too: `.crd_store_source()` has
  no default and aborts when the option is unset, so the md5 branch could not have been
  reached at all without `withr::local_options()` taking effect in the calling block.
- **Does the fixture's md5 make "md5 matches" the branch taken, rather than the download
  branch?** Yes — **P2** above, `stop()` before the download branch is never hit. (That same
  probe is what establishes finding 1.)
- **Do the mocks or the option leak past their blocks?** No. **P3**: a probe block appended to
  the end of the file asserting `getOption("cred.store_source")` is `NULL` and that
  `cred:::.crd_manifest_read` is not the mock → passes.
- **Does the second half of the `check_model = FALSE` test constrain anything the first half
  does not?** Yes. **M-C**, hardcoding `check_model = FALSE` at the md5-match site, leaves the
  first half green and takes the suite to **`FAIL 3`** — the `expect_error` is what rules out
  "the check never runs on this route".
- **Do the two new `verify = TRUE` blocks leak a connection or a temp file, or perturb the
  cached fixture store that every other file shares?** No. Measured: zero `*.duckdb` files
  remain under `tempdir()` after `test_local(filter = "store-embed-check")`, and
  `on.exit(unlink(copy), add = TRUE)` inside a `test_that()` block does fire (probed directly
  — testthat evaluates the block from a frame, unlike the script-top-level case in
  `karpathy.md` §5). Neither block writes to a cached path: `:668` copies
  `local_ragnar_store_named()@location` and opens only the copy; `:694` goes through
  `local_store_copy_bad_width()`, which has copied-then-mutated a throwaway since round 2. The
  full `filter = "store"` run passes with the three later store files reading the cached
  stores afterwards, and the double-run in Enumeration B passes twice in one session.
- **`:694` emits no stray warning.** Worth saying because it looks like it should: its
  manifest label is `nomic-embed-text (ollama)` against a store built with `.crd_test_embed`,
  which carries no `model =` formal, so `.crd_is_model_name(meta$model)` is `FALSE` and the
  label tier is skipped. `WARN 0` is correct, not suppressed.
- **`entry$embedding_model` and `$` partial matching.** Safe: the only sibling key is
  `embedding_size`, and `embedding_model` is not a prefix of it. And `#11`'s
  production-reachability claim holds — `.crd_manifest_entry()` validates only `md5`, so an
  entry with no `embedding_model` passes straight through.
- **`expect_true(id %in% ids, info = id)`** at `:724` — `expect_true()` does accept `info`;
  the `code-check-r.md` prohibition is on the comparison expectations (`expect_gt` and
  friends), none of which is passed one here.
- **Rows #39–41, `name = name` forwarding.** Uncovered at all three sites (**P6**, `FAIL 0`
  each) and deliberately not raised: dropping it falls back to
  `basename(.crd_store_loc(store))`, so the only consequence is a message naming
  `'foo.duckdb'` instead of `'foo'`. Listed in the table for completeness.

---

## Mutations and probes run (all in the copy; control `FAIL 0 | WARN 0 | SKIP 0 | PASS 496`)

| id | mutation / probe | result |
|---|---|---|
| **M-A** | drop `entry = entry` at the **download** site `:561` only | **0 failures** — finding 1 |
| **M-B** | hardcode `check_model = TRUE` at the **download** site `:562` only | **0 failures** — finding 1 |
| **M-C** | hardcode `check_model = FALSE` at the md5-match site `:524` | 3 failures — the `expect_error` half earns its place |
| **N1** | delete `.crd_embed_remedy()`'s `context == "connect"` fallthrough | 2 failures — round 3 finding 1 **closed** |
| **N2a′** | drop `entry = entry` at the md5-match site `:523` only | 2 failures — **closed** |
| **N2b′** | hardcode `check_model = TRUE` at the md5-match site `:524` | 1 failure — **closed** |
| **N3** | restore round 2's contradicting vss wording | 1 failure — **closed** |
| **N5** | drop `.crd_have(entry$embedding_model)` from the label tier | 1 failure — **closed** |
| **P1** | real `.crd_manifest_read()` raises | 0 failures — the mock reaches; no test hits the real one |
| **P2** | `stop()` immediately before the download branch | 0 failures — md5-match is the branch taken; download is never executed |
| **P3** | post-file assertions that the mock and the option are gone | pass — no leakage |
| **P5** | label warning emits an id outside the helper's roster | **0 failures** — finding 2 |
| **P6** | drop `name = name` at `:512` / `:523` / `:561` | 0 failures each — cosmetic only |
| **P7** | hardcode `check_model = TRUE` on the `verify = FALSE` site `:513` | 1 failure — covered |
| **R4-dl** | proposed download-path blocks, on control / M-A / M-B | **pass / FAIL / FAIL** — guard proven both directions |
| **R4-emit** | proposed derived emitter-axis guard, on control / P5 | **pass / FAIL** — guard proven both directions |
| **B-derivation** | both changed test files run **twice in one session** | identical, 0 failures — no assertion depends on frequency state |
| **installed** | `R CMD INSTALL` to a temp lib, `test_dir(load_package = "installed")` | 110 passes — the mocks are not a `load_all()` artefact |

---

## Notes that are not findings

- `task_plan.md:181-182` records N2a/N2b as applying to "the verified **sites**", which is
  true of the mutation and false as a coverage claim. Worth rewording to name the md5-match
  site specifically, and adding the download-site rows — the table is the artefact a later
  reader uses to decide whether the axis is closed, and it currently reads as though it is.
- Round 3's residual note stands: `.crd_retrieval_fallback_id()` (`:1246-1249`) still carries
  a hand-copied duplicate of `.crd_store_loc()`'s four lines. Pointing it at
  `.crd_store_loc()` would remove one fact with two implementations and incidentally cover
  rows #7 and #8.
- Round 3's note on row #19 (the `return()` after the probe warning being harmless only
  because row #20a exists) is still accurate and still uncommented in the source.

---

## Verdict

**Not closed.** Computed, not asserted.

The candidate set is **43** decision points (method in Enumeration A — 13 changed functions,
38 raw hits on changed lines, conjuncts split, five forwarding/emitter rows added by hand).
**29 are covered by a measured mutation**, 3 are behaviour-preserving if removed, 5 are
structurally unreachable, 3 are uncovered but cosmetic-only, and **3 are uncovered and
consequential**: `#35` and `#36` (the download return site's `entry` and `check_model`
forwarding — M-A and M-B, `FAIL 0` each) and `#43` (the label warning's frequency id against
the helper's roster — P5, `FAIL 0`).

The **test-side** enumeration (B) **is** closed, and this round closed it mechanically rather
than by argument: 50 absence/warning assertions, 20 exposed to rlang's once-per-session state,
and both changed files run twice in one session with identical results, so no assertion is
green because of frequency state in either direction. Round 3's four fixes are each proven by
a mutation that now fires (N1 `FAIL 2`, N3 `FAIL 1`, N5 `FAIL 1`, N2a′ `FAIL 2`, N2b′
`FAIL 1`).

Both residual rows carry a fix **measured in both directions**, so a fifth round is not
needed to design one — it is needed only to confirm the two land. The termination criterion is
unchanged and now nearly met: every row of Enumeration A reads covered, unreachable,
behaviour-preserving or cosmetic, with the mutation that says so. Two rows short, and both
sit inside round 3's own fixes — which is the signature that has justified every round so
far, and the reason to run the confirmation rather than take the table's word for it.
