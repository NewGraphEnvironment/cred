# Progress — crd_search() hybrid fallback blames Ollama for every failure (#29)

## Session 2026-10-07

- Plan-mode exploration — measured all four failure shapes against a real offline ragnar
  store before planning; the measurement changed the approach from the issue's proposed
  message regex to condition-class dispatch, and surfaced a fourth shape (model never
  pulled) the issue does not mention
- Phases approved by user; instruction: all phases to PR
- Created branch `29-crd-search-hybrid-fallback-blames-ollama` off main
- Scaffolded PWF baseline from issue #29 with approved phases
- Next: Phase 1 — failure-shape fixtures and red tests
- Phase 1 — failure-shape fixtures and red tests committed. Measured before writing:
  setting `@embed` on a copy of the cached fixture store does **not** reach the original
  (S7 value semantics) even though both share one duckdb connection, so the fixtures are
  free and cannot corrupt the store the #27 tests retrieve from. Red run:
  `[ FAIL 18 | WARN 0 | SKIP 0 | PASS 14 ]` — the 14 passing are the premise tests, which
  is the result wanted: every fixture reaches the branch it claims, and nothing else exists yet
- Phases 2 and 3 — classifier, messages and frequency guard. Landed as one commit because
  the frequency guard lives inside the same function that emits the classified warning;
  splitting them would have meant writing code to be replaced in the next commit
- Guard proven in both directions by three mutations, each caught by exactly the assertion
  written for it: restoring the pre-#29 catch-all -> 8 failures; dropping `.frequency` ->
  the once-per-session test only; keying `.frequency_id` on the store without the reason ->
  the collapse test and the id test only. All run in a temp copy of the tree
- `devtools::test()` `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 412 ]`; `lintr::lint_package()` clean
- Phase 4 — docs, NEWS, version 0.3.1 -> 0.3.2. `crd_search()` gains a
  "Diagnosing a fallback" section listing the four condition classes; the CLAUDE.md
  design-decision bullet that recorded #29 as open is replaced by two that record what was
  settled (classify by class not text; a failure shape is reachable offline by replacing a
  connected store's `embed`)
- `devtools::check()`: 0 errors, 3 warnings, 4 notes — **all pre-existing on origin/main**,
  verified line for line: non-ASCII em dashes in `R/audit.R` and `R/store.R` comments (55
  such lines on main before this branch), and undeclared `tibble` / `openxlsx` used via
  `::`. The repo has no R-CMD-check workflow, so none of them reddens CI. Not touched —
  out of scope for #29, worth their own issue
- One non-ASCII em dash I had added inside a user-facing **string** was replaced with an
  ASCII hyphen; the ten remaining are comments, matching the file's existing style
- `pkgdown::check_pkgdown()` clean; `lintr::lint_package()` clean;
  `devtools::test()` `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 412 ]`
- Phase 5 — folded in the plan review (returned mid-Phase-4, 3 blockers / 9 gaps, claims
  verified empirically on its side). Three findings were defects **inside this issue's own
  fix**: a regex matching a function name rather than a size complaint; a remedy pointing at
  a verification that cannot detect the condition; and all HTTP statuses collapsed into
  "pull the model". The second is #29's defect reintroduced by its fix, and it was also
  already asserted in `?crd_store_connect` — corrected there too, with
  [#30](https://github.com/NewGraphEnvironment/cred/issues/30) filed for the missing
  connect-time check
- Two mutations had survived the suite (dropping `location` from the frequency id, stubbing
  the store-model lookup to NA). Both now caught; the model-lookup gap was a fixture bug of
  mine — `model <- "x"` in the body, where the regex wants `model = "x"`, so a defaulted
  formal is the right shape and matches what `embed_ollama()` actually looks like
- Mutation battery after the fixes, 8 for 8 caught: G1 id key, G3 model lookup, B1 pattern,
  B2 remedy, B3 status split, G6 length guard, AC3 indentation, G4 model naming
- `devtools::test()` `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 463 ]`; lintr clean;
  `pkgdown::check_pkgdown()` clean
- Phase 6 — own probe of the regex edge cases found that the model name in a remedy comes
  from the service's 404 body unguarded, and lands in a line the message tells the reader to
  paste. Whitelisted to Ollama's grammar. Full battery now 13 for 13
- Two fresh code-review agents were spawned on the cumulative diff (one general, one scoped
  to the *mechanism* behind the three defects the plan review found inside this fix). Work
  continued rather than waiting on them, per the convention; findings land as follow-up
  commits on this branch
- Phase 7 — folded in code-review round 2, which was scoped to the mechanism rather than to
  more instances and named it: a remedy asserted on evidence consistent with it rather than
  evidence that establishes it, with the establishing evidence already in the process one
  function away. Four more defects, two of them the same class a third and fourth time:
  the model-name guard was not consulted on the store-recorded branch, nor on the dimension
  message's descriptive line; a 404 asserted "not installed" from the status while the body
  phrase that establishes it was computed ten lines away and discarded; and an HTTP error
  with a non-JSON body loses its status class and landed in `unknown`, whose remedy is to
  re-download the store
- Round 2 also found 7 of 10 connection patterns were deletable with the suite green —
  `Connection refused` only looked covered because `Failed to connect` won the alternation
- Terminated by enumeration, not by a quiet round: 26 predicates listed with verdicts, 4
  name-interpolation sites all guarded, the three reason lists computed to agree (now a
  test), and 27 of 27 mutations caught
- `devtools::test()` `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 502 ]`; lintr and check_pkgdown clean
- Phase 8 — folded in code-review round 1 (ran concurrently with round 2; verified at
  2be5761). It found two defects the mechanism round did not, both the "fixture that cannot
  reach the failure mode" shape and both mine: a block asserting the store's recorded model
  is used could not fail, because the fixture recorded the same literal as the hardcoded
  default (measured — deleting that whole tier left the suite green at 502); and the
  dimension premise test pinned 9 characters of a 40-character pattern, so an upstream
  reword left green the one test whose job is to fail naming the cause
- Battery now 29 for 29. Round 1 also probed clean, with evidence, several things that were
  assumptions until it checked: `testthat::teardown_env()` is run-scoped not file-scoped, so
  the fixtures' shared duckdb connection carries no cross-file hazard; `rlang::warn()`
  applies no cli formatting in this package, so a brace-laden duckdb cause survives verbatim
- `devtools::test()` `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 504 ]`; lintr clean
