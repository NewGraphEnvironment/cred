# #29 — crd_search() hybrid fallback blames Ollama for every failure

**Closed by** [PR #31](https://github.com/NewGraphEnvironment/cred/pull/31) · cred 0.3.2 ·
**Spawned** [#30](https://github.com/NewGraphEnvironment/cred/issues/30)

`crd_search(method = "hybrid")` caught every semantic-retrieval failure and prescribed one
remedy: start Ollama. The cause was reported, so the warning was recoverable, but the advice
was wrong for anything that was not a connection failure — and for an embedding-width
mismatch it told you to restart a service that was fine while the store itself was the
problem. The fallback now classifies the condition into five reasons, says something different
for each, and warns once per session per reason **and** store. Every failure still falls back
to BM25 and the `method` column still reports `"bm25"`, so nothing that worked before behaves
differently; only what is *said* about a degraded search changed.

The issue proposed matching message text. Measurement replaced that with condition-class
dispatch, and turned up a failure shape the issue did not name (HTTP 404, model never pulled —
where the old message was *half* right).

## What this issue is actually a record of

Nine defects were found **inside this fix**, across three review rounds, and they were one
defect: *a classification or remedy asserted on evidence that is consistent with it rather
than evidence that establishes it, where the establishing evidence is already in the process
one function away.* Round 2 named that mechanism; the instances were a regex matching a
function name instead of a size complaint, a remedy pointing at an md5 check that cannot see a
model change, a body claim made from an HTTP status, and a guard that existed and was not
consulted on the sibling branch — then on a third site when the test was widened.

The lesson is not "review more". It is that this class of defect reproduces *through its own
fix*, because the fix is written under the assumption that produced it. What ended the loop was
enumeration, not a quiet round.

## Measurement

Four failure shapes probed against a live ragnar 0.3.0 store before any code was written.
Three carry a condition class that survives `ragnar_retrieve()` unwrapped (`httr2_failure`,
`httr2_http_404`, `httr2_http`); the embedding-width mismatch carries none and is a duckdb
binder error. That measurement is why the implementation dispatches on class rather than on
the message text the issue proposed, and `code-check-r.md`-style traps found along the way:

- `embed_ollama()` sets `req_error(body = \(resp) resp_body_json(resp)$error)`, so an HTTP
  error whose body is **not JSON** loses its status class entirely and arrives bare.
- `ragnar_store_connect()` does `embed <- unserialize(metadata$embed_func[[1L]])`, so a
  connected store embeds queries with its **own** recorded embedder — a width mismatch cannot
  mean the caller chose a different model.
- Setting `@embed` on a copy of a connected store does not reach the original (plain S7
  property, copy-on-modify) even though both share one duckdb connection. That is what makes
  every failure shape reachable offline with no mocked bindings.
- `testthat::teardown_env()` is **run**-scoped, not file-scoped, so the shared connection
  carries no cross-file teardown hazard.
- `crd_store_connect()`'s verification is md5 only; `.crd_check_model()` compares model and
  width and runs on **push**. The repo's own `?crd_store_connect` claimed otherwise and was
  corrected — see #30.

**29 mutations, 29 caught.** Four survived when first written and were only found by running
the battery rather than reasoning about coverage: the store half of the frequency key, the
store-model lookup, the store-recorded model tier, and 7 of the 10 connection patterns
(`Connection refused` only *looked* covered — `Failed to connect` won the alternation in the
string written to exercise it).

`devtools::test()` 504 passing, 2 skipped. `devtools::check()` 0 errors and 3 warnings, all
three pre-existing on `main` and verified line for line.

## Evidence

- `planning/archive/2026-10-issue-29-hybrid-fallback-classify/review-round1.md`,
  `review-round2.md` — the two code-review rounds, as returned
- `findings.md` — the four measured failure shapes with their classes and messages
- `progress.md` — the phase-by-phase record, including the wrong turns
- `tests/testthat/test-store-fallback.R` — every shape reached through the real
  `ragnar_retrieve()`; `helper-store.R` carries the fixtures and the reasons they are shaped
  as they are
