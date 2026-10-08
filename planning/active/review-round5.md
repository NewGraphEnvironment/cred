# Review round 5 — branch `30-no-connect-time-embedding-model-check-cr`

Reviewer: subagent code review, read-only. Round 5 exists for one purpose: round 4 returned
"NOT closed — 3 of 43 rows uncovered and consequential", named a fix for each measured in both
directions, and said a fifth round only has to confirm they land. This round re-computes both
enumerations against `06185f7` and verifies the three rows by mutation.

Read in full: the branch diff (16 files), `R/store.R`, `tests/testthat/test-store-embed-check.R`,
`tests/testthat/test-store-fallback.R`, `tests/testthat/helper-store.R`, `DESCRIPTION`,
`CLAUDE.md`, `planning/active/review-round1.md` – `review-round4.md`,
`planning/active/task_plan.md`, and the `/code-check` checklist.

Every probe ran in a throwaway copy at
`…/scratchpad/rev5/cred` (`cp -r`). Both trees `git status --short` empty before
and after every run, confirmed; only this file was written to the real working tree.

**Control, in the copy, branch as committed (`06185f7`):**
`devtools::test(filter = "store")` → `FAIL 0 | WARN 0 | SKIP 0 | PASS 507`;
full `devtools::test()` → `FAIL 0 | WARN 0 | SKIP 2 | PASS 639`; `lintr::lint_package()` → 0.
`test-store-embed-check.R` alone: **121 assertions, SKIP 0**, and 121 passes against the
**installed** package (`R CMD INSTALL` to a temp lib, `test_dir(load_package = "installed")`) —
so neither the new `.crd_aws` mock nor the namespace walk is a `load_all()` artefact.

---

## Enumeration

### A. Code-side decision points in the changed code

**`R/` is byte-identical to round 4's commit** — `git diff 566adee HEAD -- R/` is empty; the
landing commit touched only `tests/` and `planning/`. So the candidate set is the same set, and
the question is purely one of coverage. Re-derived rather than carried forward anyway, by round
4's stated method: changed/added lines of `R/store.R` from `git diff origin/main...HEAD -U0`
(**569** changed lines, 502 added), comments dropped, matched
`return(|if (|tryCatch|\|\||&&|!is|!\.|!isTRUE|match.arg` on changed lines only → **38 raw
hits**, reproducing round 4's 38 exactly. Plus the nine hand-added forwarding/emitter rows
(three `.crd_store_open()` sites × `name`/`check_model`, two × `entry`, and the emitter-id row),
of which five were new in round 4 → **43**.

| # | site | row | status this round |
|---|---|---|---|
| 1–32, 38 | — | rounds 1–3's rows, `R/` unchanged | 24 covered, 3 behaviour-preserving (#1, #10, #19), 5 unreachable (#4, #7, #8, #9, #15) |
| 11 | `:290` | `.crd_have(entry$embedding_model)` | covered — **N5 → `FAIL 1`** (re-measured) |
| 28 | `:1153` | `identical(context, "connect")` fallthrough | covered — **N1 → `FAIL 2`** (re-measured) |
| 33 | `:523` | forwards `entry = entry` (md5-match site) | covered — **N2a′ → `FAIL 2`** (re-measured) |
| 34 | `:524` | forwards `check_model = check_model` (md5-match) | covered — **N2b′ → `FAIL 1`**, **M-C → `FAIL 3`** |
| **35** | `:561` | forwards `entry = entry` (**download** site) | **NOW COVERED — M-A → `FAIL 2`** (was `FAIL 0`) |
| **36** | `:562` | forwards `check_model = check_model` (**download**) | **NOW COVERED — M-B → `FAIL 1`** (was `FAIL 0`) |
| 37 | `:1219` | round-2's vss-contradiction wording | covered — N3 (round 4, `FAIL 1`); `R/` and the asserting test both unchanged |
| 39–41 | `:512`/`:523`/`:561` | forwards `name = name` | uncovered, **cosmetic only** — P6-dl → `FAIL 0`, re-measured at the download site |
| 42 | `:513` | forwards `check_model` (verify = FALSE site) | covered — **P7 → `FAIL 1`** (re-measured) |
| **43** | `:306` | label warning's `.frequency_id` vs the helper's roster | **NOW COVERED — P5 → `FAIL 1`** (was `FAIL 0`) |

Two structural probes, both inverted since round 4:

- **P2** — `stop("DOWNLOAD BRANCH REACHED")` immediately before the download branch:
  round 4 **`FAIL 0`** (no test had ever executed those lines) → round 5 **`FAIL 2`**. The
  download branch is now executed, and by the new tests specifically.
- **M-D** — hardcode `check_model = FALSE` at the download site: **`FAIL 3`**. The
  `expect_error` half of the new download test earns its place; the block is not passing merely
  because the check never runs on that route.

**Size 43. Covered by a measured mutation: 32. Behaviour-preserving if removed: 3.
Structurally unreachable: 5. Uncovered but cosmetic-only: 3 (#39–41, accepted).
Uncovered and consequential: 0.**

### B. Test-side absence/warning assertions

Re-computed by round 4's method — `expect_(silent|no_error|no_match|no_warning|no_condition|warning)(`
over the two changed test files, comments dropped: **50** (22 in `test-store-embed-check.R`,
28 in `test-store-fallback.R`), **unchanged**. The landing commit added none of that family; its
three blocks assert with `expect_error`, `expect_true/false`, `expect_match`, `expect_s3_class`
and `expect_gte`.

B was closed in round 4 by derivation and is re-closed here the same way, this round over both
files and twice each in **one** session — the once-per-session sentinel is session-scoped, so any
assertion green only because its slot was fresh must break on the second pass:

```
pass1 store-embed-check  pass=121 fail=0 warn=0 skip=0
pass1 store-fallback     pass=174 fail=0 warn=0 skip=0
pass2 store-embed-check  pass=121 fail=0 warn=0 skip=0
pass2 store-fallback     pass=174 fail=0 warn=0 skip=0
```

The two new premise assertions are each validated by a mutation rather than by reading:

- `expect_false(file.exists(target))` (`:779`) — the premise that makes the download branch the
  only way through. Validated *by its consequence*: M-A and M-B fire from inside these blocks,
  which they could not if the md5-match return were being taken, and P2 is now red.
- `expect_gte(length(used), 3L)` (`:868`) — the vacuity premise for the namespace walk. Measured:
  the walk returns exactly `.crd_store_label_id`, `.crd_store_probe_id`,
  `.crd_retrieval_fallback_id` under both `load_all()` and the installed package. Converting any
  existing emitter from the call form to a variable drops `used` to 2 and fails the premise, so
  the degenerate-absence direction is closed, not merely asserted.

---

## The four probes the prompt asked for, answered

- **Do the two download tests take the download branch?** Yes. P2 `FAIL 0 → FAIL 2`. Not the
  md5-match return: the destination is a fresh `withr::local_tempdir()` with
  `expect_false(file.exists(target))` ahead of the call, and `expect_true(file.exists(target))`
  after it — the file can only exist because the branch ran `file.rename(part, local_path)`.
- **Does the mocked `.crd_aws` signature match every way the real one is called on that path?**
  Yes, and there is only **one** such call. The two `.crd_aws` calls on a `verify = TRUE`
  connect are `:117` (inside `.crd_manifest_read`) and `:540` (the store `cp`); the manifest read
  is itself mocked, so `:540` is the only call the `.crd_aws` mock serves, and it is
  `.crd_aws(c("s3","cp",src,part), profile = profile)` — named, two formals, which the mock's
  `function(args, profile = "", clean_stdout = FALSE)` accepts. A future third formal that
  `crd_store_connect` passed would fail the mock with `unused argument`, which is the safe
  direction (`code-check-r.md`, "A `function(...)` mock hides arguments the real callee no
  longer accepts" — this mock is the prescribed named shape, not `...`).
- **Does `args[[4]]` hold what the test assumes?** Yes — `args` is literally
  `c("s3", "cp", paste0(source, name, ".duckdb"), part)` at `R/store.R:540`, so `args[[4]]` is
  the `.part-<pid>` destination. Proven behaviourally too: had the copy landed anywhere else,
  `!file.exists(part)` would raise "Download failed" and the `expect_error(class =
  "cred_store_embedding_mismatch")` would be red.
- **Is the namespace walk's regex capable of matching nothing, and does the premise prevent it?**
  It matched exactly 3; `expect_gte(length(used), 3L)` is what stops a broken regex passing
  vacuously, and it fires in that direction (converting an emitter to a non-call form → 2 →
  red). A *literal/variable* `.frequency_id` on a **new fourth** emitter is the one shape the
  regex cannot see — bounded in the notes below, with the measurement.
- **Are the new mutations single-site, per round 4's own corollary?** Yes, and that is the whole
  point: M-A and M-B were applied at `:561`/`:562` **alone** and are red, while N2a′/N2b′ at
  `:523`/`:524` **alone** remain red. Both sites are now independently certified, which is
  exactly what round 3's paired mutation could not establish.
- **Do the new tests leak connections, temp files, or perturb the cached fixture store?** No.
  After `test_local(filter = "store-embed-check")`: **0** `*.duckdb` and **0** `.part-` files
  left under `tempdir()`; `getOption("cred.store_source")` is `NULL`; `cred:::.crd_manifest_read`
  and `cred:::.crd_aws` are the real functions again. Neither new block writes to a cached path —
  the first goes through `local_store_copy_bad_width()` (copy-then-mutate since round 2), the
  second `file.copy()`s `local_ragnar_store_named()@location`, which is flushed and
  disconnected before the cached read-only connect is opened, so the copy is a complete file.
  Both blocks disconnect what they open, and the error path is covered by `.crd_store_open()`'s
  own `on.exit` cleanup.

---

## Findings

**None.**

The three rows round 4 left open are closed by mutation, each on the site it names, and the
fixes introduced nothing this round could find: `R/` did not change, so there is no new
production decision point, and the three new test blocks are each proven load-bearing by a
mutation that fires from inside them (M-A `FAIL 2`, M-B `FAIL 1`, M-D `FAIL 3`, P5 `FAIL 1`).

For the first time in five rounds the search for "a defect inside the previous round's fix"
came back empty, and that is a computed result rather than an impression — the two axes the
previous four fixes each failed on were probed directly:

- the **argument** axis of the forwarding fix (not just the call sites) — M-A/M-B/M-D/N2a′/N2b′/P7, one site at a time;
- the **emitter** axis of the frequency-id fix (not just the id functions) — P5, plus the
  reason axis, which is already derived: `test-store-fallback.R:686` asserts
  `sort(.crd_fallback_reasons())` equals the set parsed out of `.crd_retrieval_failure()`'s own
  source, and `:697` derives the context roster from `formals(.crd_embed_remedy)$context`. So
  `.crd_all_warning_ids()`'s loop over reasons × the three id functions is derived on every axis
  it has.

### Checked and clear — not findings

- **Does the walk survive byte-compilation?** Yes, and for a reason worth recording:
  `deparse()` on a closure does **not** include `useSource` in its default `control`, so comments
  are dropped under `load_all()` exactly as under the installed package. Measured both ways —
  121 passes each, and the walk returns the same three names. Had `useSource` been in effect, the
  three roxygen `@return … rlang::warn(.frequency_id = )` lines would still not match (the regex
  needs an identifier before `(`, and those have `)`), but the parity would have been accidental.
- **Could an inline `paste0()` emitter escape the walk?** No — `paste0(` matches the regex, so
  `used` gains `paste0`, which is absent from `deparse(.crd_all_warning_ids)` and the loop goes
  red. The inline-construction shape round 3's finding 5 was actually about is caught.
- **Prefix containment in `expect_match(reset_src, u, fixed = TRUE)`.** A helper calling a
  *superstring* of the emitter's id function (`.crd_store_label_id_x`) would satisfy the
  substring match — but round 3's roster test independently calls
  `.crd_store_label_id(store)` and asserts membership in `.crd_all_warning_ids(store)`, which
  would then fail. The two guards cover each other on this axis.
- **`.crd_aws` mock swallowing a non-`cp` call.** Round 4's proposal carried
  `stopifnot(identical(args[[2]], "cp"))` and the landed version dropped it. Harmless here:
  grepped, `:540` is the only `.crd_aws` call reachable on this path once `.crd_manifest_read`
  is mocked, and the download-path `s3api` probes live in `crd_store_push()`, which these tests
  do not call.
- **`res$status` from the mock.** The real code branches on `file.exists(part)`, never on
  `status`, so the mock's `0L` asserts nothing and hides nothing.

---

## Mutations and probes run (all in the copy; control `FAIL 0 | WARN 0 | SKIP 0 | PASS 507`)

| id | mutation / probe | round 4 | round 5 |
|---|---|---|---|
| **M-A** | drop `entry = entry` at the **download** site `:561` only | `FAIL 0` | **`FAIL 2`** ✔ |
| **M-B** | hardcode `check_model = TRUE` at the **download** site `:562` only | `FAIL 0` | **`FAIL 1`** ✔ |
| **P5** | label warning emits an id outside the helper's roster (`.crd_store_label_v2`) | `FAIL 0` | **`FAIL 1`** ✔ (reports `.crd_store_label_v2`) |
| **P2** | `stop()` immediately before the download branch | `FAIL 0` | **`FAIL 2`** ✔ |
| **M-D** | hardcode `check_model = FALSE` at the download site `:562` | — | **`FAIL 3`** |
| **N2a′** | drop `entry = entry` at the md5-match site `:523` only | `FAIL 2` | `FAIL 2` |
| **N2b′** | hardcode `check_model = TRUE` at the md5-match site `:524` | `FAIL 1` | `FAIL 1` |
| **P7** | hardcode `check_model = TRUE` on the `verify = FALSE` site `:513` | `FAIL 1` | `FAIL 1` |
| **N1** | delete `.crd_embed_remedy()`'s `context == "connect"` fallthrough | `FAIL 2` | `FAIL 2` |
| **N5** | drop `.crd_have(entry$embedding_model)` from the label tier | `FAIL 1` | `FAIL 1` |
| **P6-dl** | drop `name = name` at the download site `:561` | `FAIL 0` | `FAIL 0` — cosmetic, accepted |
| **P8** | a **fourth** emitter whose `.frequency_id` is a local variable | — | `FAIL 1` (caught by a sibling silence assertion, not by the walk — see note) |
| **walk** | enumerate `.frequency_id = <fn>(` across the namespace | — | exactly 3, identical under `load_all()` and installed |
| **hygiene** | leftover `*.duckdb` / `.part-` files; mock and option leakage | — | 0 / 0 / none |
| **installed** | `R CMD INSTALL` to temp lib, `test_dir(load_package = "installed")` | 110 pass | **121 pass, 0 fail, 0 skip** |
| **double-run** | both changed files twice in one session | identical | identical (121/174 both passes) |

---

## Notes that are not findings

- **The walk's regex requires a call form, and the one shape it cannot see is a brand-new fourth
  emitter passing a bare variable or string literal.** Measured rather than reasoned: **P8**,
  which adds exactly that emitter on the "no readable size" path, goes **`FAIL 1`** — but by the
  sibling assertion that path is silent, not by the walk, so it does not prove the gap closed.
  Three facts bound it. Removing or converting one of the three existing emitters is caught by
  `expect_gte(length(used), 3L)`. An inline `paste0()` is caught incidentally. And round 4's own
  proposed guard shared this exact limitation, so this is not a regression introduced by the fix
  — it is a latency contingent on production code that does not exist. Worth a sentence in
  `helper-store.R` next to `.crd_all_warning_ids()` if anyone adds a fourth scheme; not worth a
  sixth round.
- **`local_mocked_download_of()`'s `model` and `size` formals are dead.** Round 4's proposal
  built the manifest mock inside the helper and consumed both; the landed version moved the
  manifest mock inline into each test and left the formals unread, so
  `local_mocked_download_of(fixture, size = 16L)` at `test-store-embed-check.R:820` reads as
  though it sets the manifest's `embedding_size` and does not — the inline mock three lines below
  supplies the 16. No behavioural consequence today (the two values agree, and the manifest's
  size is deliberately not compared anyway), but it is a reference that *looks* load-bearing and
  is not, which is the family this whole review has been chasing. Deleting the two formals, or
  having the helper take and use them, costs nothing.
- `task_plan.md:181-182` still records N2a/N2b as applying to "the verified **sites**", which
  round 4 flagged as true-of-the-mutation and false-as-a-coverage-claim. It is now immediately
  followed by the round-4 table and the paragraph that names that over-claim explicitly, so the
  document no longer misleads a later reader. No change needed.
- Rounds 3 and 4's standing residuals are unchanged and still not findings:
  `.crd_retrieval_fallback_id()` (`:1246-1249`) carries a hand-copied duplicate of
  `.crd_store_loc()`'s four lines (pointing it at `.crd_store_loc()` would remove one fact with
  two implementations and incidentally cover rows #7 and #8), and row #19's `return()` after the
  probe warning is harmless only because row #20a exists, still uncommented in the source.

---

## Verdict

**Closed.** Computed, not asserted.

Enumeration **A** is **43** decision points, re-derived by round 4's own method (569 changed
lines of `R/store.R`, 38 raw hits on changed non-comment lines — reproducing 38 exactly — plus
the nine forwarding/emitter rows). `R/` is byte-identical to round 4's commit, so the set is the
same set. **32 rows are covered by a measured mutation** (up from 29), 3 are behaviour-preserving
if removed, 5 are structurally unreachable, 3 are uncovered but cosmetic-only (#39–41, accepted),
and **0 are uncovered and consequential**. The three rows round 4 named — #35, #36, #43 — each
go from `FAIL 0` to red on a mutation applied to that site alone, and the structural probe that
proved the download branch had never executed (P2) now fires.

Enumeration **B** is **50** absence/warning assertions, unchanged, and closed mechanically for
the second round running: both changed files run twice in one session with identical results, so
no assertion in either is green because of rlang's once-per-session state in either direction.
The two premise assertions the new blocks added are each validated by a mutation rather than by
reading.

The termination criterion round 4 set is met: **every row of Enumeration A reads covered,
unreachable, behaviour-preserving or cosmetic, with the mutation that says so** — and for the
first time the loop's own signature, a defect inside the previous round's fix, does not appear.
That absence was looked for on the two axes the previous fixes each failed on (the arguments
behind the call sites; the emitters behind the id functions) and on a third that turned out to be
derived already (the reason and context rosters). A sixth round has nothing computed to go after.

Residual confidence, stated plainly so it is not mistaken for completeness: `FAIL 0 | PASS 639`,
0 lints, 121 passes against the installed package, no leaked connections, temp files, mocks or
options. The accepted tradeoffs in the brief were not re-argued.
