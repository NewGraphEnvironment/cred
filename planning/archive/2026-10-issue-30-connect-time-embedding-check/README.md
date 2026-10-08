# #30 — No connect-time embedding-model check

`crd_store_connect()` verified a store by comparing its md5 against the shared manifest, and
that compare cannot see the failure it was being credited with: a store whose embedding model
moved underneath it has **exactly** the bytes the manifest recorded, so a search against it
answers differently while looking healthy. This added a connect-time check whose load-bearing
half is a probe of the store's **own recorded embedder** — ragnar unserialises `embed_func` out
of the store, so `ncol(store@embed("probe"))` against the store's `embedding_size` is the real
condition rather than a model name rebuilt from a string. A confirmed width difference errors
(`check_model = FALSE` escapes, and the message says BM25 is unaffected); a manifest label
disagreement warns; a probe that could not run is classified and reported once per session; no
embedder or no readable size is skipped in silence. Two sibling defects from the same review
went with it: `.crd_ollama_check()` printed `ollama serve` *and* `ollama pull` for every error,
so `crd_search()` and `crd_store_build()` gave different accounts of one dead port; and
`crd_search(method = "vss")` raised a bare `Binder Error: array_cosine_distance(...)` with no
diagnosis. Released as **0.4.0**. Closing commit `164e0a0`; see the PR for the merge ref.

## Measurement

**Phase 1's refactor was proven byte-identical, not argued.** Both message builders compared
across 5 reasons x 4 causes x 2 stores against `HEAD:R/store.R` — identical on all 40,
including a hostile `model "with ; semicolon"` cause. That is what made it safe to move the
branches that three callers now share.

**25 mutations, each verified to go red against a green control** (M1–M14, N1–N7,
M-A/M-B/P2/P5). The table taught three things about itself, each of which changed how the rest
of the work was checked:

- **Three mutations first reported 0 failures and were broken probes, not test gaps.** `perl -0`
  anchors `^` to the start of the *file*, and bash expanded the `$` in `meta$size`. The probe is
  broken before the world is.
- **One fix was vacuous and its own mutation caught it.** `local_store_copy_bad_width()` calls
  `DBI::dbDisconnect()` itself, so a counter armed before the fixture was built sat at 1 however
  the cleanup behaved.
- **A mutation applied to N sites at once certifies coverage of exactly one of them.** Dropping
  `entry` from both `verify = TRUE` return sites at once went red and was recorded as covered —
  while a `stop()` at the top of the download branch was *silent*, meaning no test had ever
  executed the branch a first-time user takes. This is the one lesson general enough to leave
  the repo; it belongs in `soul/conventions/code-check.md` beside "Restore the bug and prove the
  guard fires", and is drafted but not filed, because a soul convention edit is its own change.

**`devtools::check()` is 0 errors / 3 warnings / 4 notes, measured identical on a worktree of
`origin/main`** — so all pre-existing, filed as cred#32 rather than fixed here. The one new
non-ASCII string literal this branch introduced was fixed, so the count is unchanged by it.
Final suite: 639 pass, 0 fail, 2 pre-existing skips, 0 lints.

**Five `/code-check` rounds, and the count is the finding.** Rounds 1–4 each found real defects
and every round from 2 on found at least one *inside the previous round's fix*, so the loop was
terminated by a computed enumeration rather than a quiet round: 43 code decision points (32
covered by mutation, 3 behaviour-preserving, 5 unreachable, 3 cosmetic, 0 uncovered and
consequential) and 50 test-side absence assertions, closed by running both changed test files
twice in one session. The mechanism the rounds converged on — **a check whose reference was
restated rather than derived, over one axis of a fact that has more than one axis** — is
recorded in `task_plan.md` with the five instances it produced.

## Wrong turns worth keeping

- **The plan's fixture could not reach its own failure.** Setting `@embed` on a copy of the
  cached store shares its duckdb connection, so the new failure cleanup closed the *shared* one
  and every later test file lost retrieval. The hazard `helper-store.R` records, met from the
  other direction. Replaced by a throwaway `file.copy()` with the recorded `embedding_size`
  edited — no mocks, real unserialise path.
- **The plan said to reverse two `expect_no_match(msg, "crd_store_connect")` assertions. That
  was wrong**, and the review caught it: they pair with the "md5 *can* see a stale file" block,
  and reversing one collapses a discriminating pair into two tests asserting the same thing. The
  remedy already prescribed gathers the same evidence as the new probe, more cheaply, and covers
  an in-session embedder swap no reconnect can see. Comments rewritten; assertions untouched.
- **One predicted consequence did not reproduce.** The review argued a leaked connection would
  make the documented `check_model = FALSE` retry fail under a different `read_only`. Measured:
  read-write then read-only on one file both succeed on ragnar 0.3.0. The leak was real and was
  closed; the consequence was not, and saying so mattered because the "obvious" discriminator
  for the cleanup test is exactly that reconnect, which cannot tell a closed handle from a
  leaked one.
- **`NEWS.md` for 0.3.2 contradicted itself eighteen lines apart** — md5 verification "exists to
  catch" a width mismatch, then md5 "is structurally unable to see" one. Not a dated claim but
  an inconsistency that shipped, corrected in place with a note.

## Evidence

- `planning/archive/2026-10-issue-30-connect-time-embedding-check/review-round*.md` — five
  review rounds verbatim, each with the mutations it ran and their results
- `task_plan.md` — the full mutation table and the mechanism
- `findings.md` — the "Errors Encountered" ledger, including the three broken probes
