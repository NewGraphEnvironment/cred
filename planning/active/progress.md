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
