# Plan review for #58 (Plan agent, run beside Phase 1-2, returned 2026-11-27)

Each finding has a verdict. "Folded" means the plan now carries it.

## Blocker

- **B1.** #47 named the wrong class. `.crd_retrieval_abort()` raises
  `c("cred_retrieval_error_<reason>", "cred_retrieval_error")` (R/store.R ~1316), and
  `cred_retrieval_fallback_*` is the **warning** class. **Confirmed** by reading the code.
  Folded: the hybrid abort uses the `cred_retrieval_error_*` pair, so one handler covers vss and
  hybrid. The plan and #58's Decisions are corrected.
- **B2.** `.crd_retrieval_abort()` hardcodes `method = "vss" has no fallback` and
  `"hybrid" degrades to BM25 with a warning`. Both are wrong once hybrid errors.
  **Confirmed.** Folded: it takes a `method` argument and a reworded tail, keeping the
  substrings "needs no" and "BM25 needs no embedding" that test-store-embed-check.R asserts.
- **B3.** The crashed-worker mock returns no `ingest_summary`. **Confirmed**, because the mock
  returns a bare `invisible(store)`. Folded: the mock builds the summary as ragnar does.

## Assumption

- **A1.** The summary is on the return value only (copy-on-modify). The probe agrees, and the
  code now assigns the result.
- **A2.** Every worker failure has status "error" and a message. Agreed; uses `match()`.
- **A3.** Path normalisation is not a risk. Agreed.
- **A4.** `rlang::is_interactive()` is a reasonable default. Agreed. The probe ran
  (findings.md).
- **A5.** `fallback = "error"` breaks downstream callers without an embedding service.
  Folded: NEWS names the break, and Phase 4 greps the org for `crd_search(` callers.

## Gap

- **G1.** The plan did not name the #47 test files, and missed test-store-embed-check.R:490.
  Folded into Phase 4 by file and line.
- **G2.** No reason for a path that is missing but was not reported as an error. Folded: the
  fallback reason names ragnar's status instead of "see ragnar's warning".
- **G3.** The #51 docs went stale (roxygen and the CLAUDE.md "keeps it by path" bullet). Folded.
- **G4.** The #47 docs went stale: `crd_search` details, a code comment, the "once per session"
  text, `.crd_retrieval_failure`, `.crd_store_probe_id`, the `crd_store_connect` roxygen and its
  `check_model = FALSE` advice, helper-store.R:127, and CLAUDE.md's "hybrid is the right default"
  and once-per-session bullets. Neither the vignette nor README calls `crd_search()`. Folded as a
  sentence grep.
- **G5.** What `fallback` means under vss or bm25 was unstated. Folded: it is ignored there, and
  documented as ignored.
- **G6.** The end-to-end `{.strong x}` test would hit testthat's first-message trap. Folded:
  collect every message.
- **G7.** The plan did not name the tests to replace, or say what `.crd_store_ingest()`'s own
  default does. Folded: `.crd_store_ingest()` keeps `FALSE`. Test-store-build.R:426 and the
  :482 mock change deliberately.
- **G8.** The #26 merge would crash on an atomic entry, `""` was ambiguous, and the docs went
  stale. Folded: an `is.list()` guard, `notes = ""` writes `""`, and the roxygen and CLAUDE.md
  are updated.

## Ordering

- **O1.** Do #51 before #49 mocks. Folded: both land in one commit to the post-#51 contract.
- **O2.** Merging #55 cuts a release, so Phase 5's `git merge origin/main` will conflict on
  NEWS. Expected and resolved there.

## Acceptance

- **AC1.** The #51 test must tell the two sources apart. Folded: the crashed path's summary
  message differs from any warning text, and no warning is raised for it.
- **AC2.** The named entry must still be replaced field by field apart from `notes`. Folded as
  a test (`built_by` does not survive, `notes` does).
- **AC3.** The dry-run test checks a preserved note. Folded.
- **AC4.** Validation lists the sentences changed for #47. Folded.

## Scope

None.
