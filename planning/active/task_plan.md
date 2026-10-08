# Task: crd_search() hybrid fallback blames Ollama for every failure, including a store/model mismatch (#29)

## Problem

`crd_search(method = "hybrid")` — the default — wraps semantic retrieval in a `tryCatch`
that treats **every** error as "Ollama is not running", and silently continues with BM25
(`R/store.R:544-554`). The real reason is interpolated into the message, so it is
recoverable — but the **prescribed remedy is wrong for anything that is not a connection
failure**, and the search quietly degrades either way.

A dimension mismatch means the store was built with a different embedding model than the
one answering queries — the exact condition `crd_store_connect()`'s md5 verification exists
to catch. Reached through this path it produces a warning telling you to start a service
that is already running, and then returns results.

Secondary: no frequency guard, so the four-line warning fires on every call.

Nothing is broken today — BM25 results still come back and the `method` column correctly
reports `"bm25"`. This is about diagnosis, not correctness.

## What exploration changed about the approach

The issue proposes regex-matching message text (`Connection refused`, `Failed to connect`,
…). Measured against ragnar 0.3.0 and a real offline store, **three of the four failure
shapes are separable by condition _class_**, which is stable across locales and curl
versions in a way message text is not:

| failure | discriminator (measured) | right remedy |
|---|---|---|
| Ollama unreachable | `httr2_failure`, parent `curl_error_couldnt_connect` | `ollama serve` |
| model never pulled | `httr2_http_404` / `httr2_http` — **Ollama is up** | `ollama pull <model>`; `ollama serve` is wrong |
| embedding width mismatch | msg `array_cosine_distance: Array arguments must be of the same size` (duckdb Binder Error); class is bare `rlang_error` | the store/model mismatch — `crd_store_connect()` verification, not Ollama |
| anything else | none of the above | report verbatim, prescribe nothing |

The class survives intact through `ragnar_retrieve()` — verified, it is not re-wrapped.
The **missing-model case is not in the issue** and is the second-likeliest real failure; it
is the one where the current message is *half* right, which is the worst kind. Only the
mismatch branch needs a message regex, and its text is a duckdb binder error, not an
Ollama one.

**Every branch reaches a real condition in tests with no Ollama and no mocking** — so no
`local_mocked_bindings(.package=)` and therefore no `testthat` pin bump: override `@embed`
on a copy of the fixture store (S7 property set, verified settable) with (a) `embed_ollama()`
on a dead loopback port, (b) a different-width embedder, (c) a bare `stop()`.

Issue item 4 is settled in the issue body — still fall back, warn much more loudly. An
error would break searches that work today.

## Phase 1: Tests first, red

- [ ] Add failure-shape fixtures to `tests/testthat/helper-store.R`: a store copy whose
      `@embed` is swapped for a dead-port `embed_ollama()`, a different-width embedder, and
      a bare `stop()` — each producing a *real* condition through `ragnar_retrieve()`
- [ ] `tests/testthat/test-store-search.R`: premise test that each fixture reaches its
      intended branch (assert the condition class/message actually raised, so a future
      ragnar change fails here naming the cause)
- [ ] Classification tests on the new internal, both directions: a connection error **must**
      get the Ollama message; a mismatch error **must not** mention Ollama and **must**
      name `crd_store_connect()`
- [ ] Assert on the warning's **condition class**, not interpolated message text
- [ ] `method` column is `"bm25"` and rows are still returned, on all four branches
- [ ] Frequency tests: a second identical call is silent; a *different* reason still warns
      (ids must not collapse); `rlang::reset_warning_verbosity()` between blocks

## Phase 2: Classify the failure

- [ ] `.crd_retrieval_failure(cond)` in `R/store.R` — pure, returns reason + remedy text.
      Class checks first, mismatch regex last, `"unknown"` as the default
- [ ] For the mismatch branch, name the store's own recorded model and width by reusing the
      existing `.crd_store_model_from_meta()` (`R/store.R:973`) and the
      `SELECT embedding_size FROM metadata` read already used by `.crd_store_describe()`,
      guarded so a metadata read failure degrades to the generic message
- [ ] Wire into `crd_search()`'s `hybrid` branch, replacing the catch-all `warning()`
- [ ] Phase 1 tests green

## Phase 3: Frequency guard and condition classes

- [ ] Add `rlang` to `Imports` (already installed transitively via dplyr; needed for
      `.frequency`)
- [ ] `rlang::warn(..., class = c("cred_retrieval_fallback_<reason>",
      "cred_retrieval_fallback"), .frequency = "once", .frequency_id = <store>_<reason>)`
      — per store **and** reason, so two different failures do not collapse into one
- [ ] Frequency tests green

## Phase 4: Docs, NEWS, version

- [ ] `crd_search()` `@details` currently says the fallback is about Ollama being
      unreachable (`R/store.R:480-486`) — broaden it and document the condition classes
- [ ] `devtools::document()`, `lintr::lint_package()` (must be 0), `devtools::test()`,
      `pkgdown::check_pkgdown()`
- [ ] NEWS.md entry; version `0.3.1` → `0.3.2` as the final commit
- [ ] Update the CLAUDE.md design-decision bullet that currently ends "That fallback
      currently blames Ollama for every failure, including a store/model mismatch (#29)"

## Validation

- [ ] Tests pass
- [ ] Guard proven in both directions — the mutation that reintroduces the catch-all must
      turn a test red
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
