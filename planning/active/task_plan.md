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

**Every branch except one reaches a real condition in tests with no Ollama and no mocking** —
so no `local_mocked_bindings(.package=)`: override `@embed` on a copy of the fixture store
(S7 property set, verified settable) with (a) `embed_ollama()` on a dead loopback port,
(b) a different-width embedder, (c) a bare `stop()`. The exception is a **missing model**,
which needs a live server in order to answer 404; its end-to-end test skips, and its
classification is covered unconditionally by a hand-built condition.

The `testthat` floor does still move, for an unrelated reason the plan had wrong: the suite
already used `local_mocked_bindings()` (3.1.8) under a `(>= 3.0.0)` pin, and this change adds
`expect_no_condition(class = )` (3.1.5). Raised to `(>= 3.1.8)`.

Issue item 4 is settled in the issue body — still fall back, warn much more loudly. An
error would break searches that work today.

## Phase 1: Tests first, red

- [x] Add failure-shape fixtures to `tests/testthat/helper-store.R`: a store copy whose
      `@embed` is swapped for a dead-port `embed_ollama()`, a different-width embedder, and
      a bare `stop()` — each producing a *real* condition through `ragnar_retrieve()`
- [x] `tests/testthat/test-store-fallback.R` (a new file — `test-store-search.R` is the #27
      regression file and stays that): premise test that each fixture reaches its
      intended branch (assert the condition class/message actually raised, so a future
      ragnar change fails here naming the cause)
- [x] Classification tests on the new internal, both directions: a connection error **must**
      get the Ollama message; a mismatch error **must not** mention Ollama and **must**
      name `crd_store_connect()`
- [x] Assert on the warning's **condition class**, not interpolated message text
- [x] `method` column is `"bm25"` and rows are still returned, on all four branches
- [x] Frequency tests: a second identical call is silent; a *different* reason still warns
      (ids must not collapse). `rlang::reset_warning_verbosity()` takes a **required** id,
      so there is no reset-everything call; blocks that merely need to see the warning use
      `withr::local_options(rlib_warning_verbosity = "verbose")` instead, which is stateless

## Phase 2: Classify the failure

- [x] `.crd_retrieval_failure(cond)` in `R/store.R` — pure, returns reason + remedy text.
      Class checks first, mismatch regex last, `"unknown"` as the default
- [x] For the mismatch branch, name the store's own recorded model and width by reusing the
      existing `.crd_store_model_from_meta()` (`R/store.R:973`) and the
      `SELECT embedding_size FROM metadata` read already used by `.crd_store_describe()`,
      guarded so a metadata read failure degrades to the generic message
- [x] Wire into `crd_search()`'s `hybrid` branch, replacing the catch-all `warning()`
- [x] Phase 1 tests green

## Phase 3: Frequency guard and condition classes

- [x] Add `rlang` to `Imports` (already installed transitively via dplyr; needed for
      `.frequency`)
- [x] `rlang::warn(..., class = c("cred_retrieval_fallback_<reason>",
      "cred_retrieval_fallback"), .frequency = "once", .frequency_id = <store>_<reason>)`
      — per store **and** reason, so two different failures do not collapse into one
- [x] Frequency tests green

## Phase 4: Docs, NEWS, version

- [x] `crd_search()` `@details` currently says the fallback is about Ollama being
      unreachable (`R/store.R:480-486`) — broaden it and document the condition classes
- [x] `devtools::document()`, `lintr::lint_package()` (must be 0), `devtools::test()`,
      `pkgdown::check_pkgdown()`
- [x] NEWS.md entry; version `0.3.1` → `0.3.2` as the final commit
- [x] Update the CLAUDE.md design-decision bullet that currently ends "That fallback
      currently blames Ollama for every failure, including a store/model mismatch (#29)"

## Validation

- [x] Tests pass
- [x] Guard proven in both directions — the mutation that reintroduces the catch-all must
      turn a test red
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

## Phase 5: Fold in the plan review

The Plan subagent returned 1060s after spawning, mid-Phase-4, with 3 blockers and 9 gaps. It
verified its claims empirically rather than reasoning about them, and three of its findings
were defects **inside this issue's own fix** — the same class the issue is about:

- [x] **B1** `.crd_dim_patterns` matched the bare name `array_cosine_distance`, which duckdb
      also raises for a wrong-*type* embedder (`No function matches the given name and
      argument types ...`). That prescribed an expensive rebuild off a substring. Dropped;
      the size phrase is specific and metric-agnostic
- [x] **B2** the dimension branch prescribed `crd_store_connect()`, whose verification is an
      md5 compare and is structurally unable to see a model change. A remedy that cannot
      detect the condition — #29's own defect, reintroduced inside its fix. Also corrected
      the same false claim in `?crd_store_connect`, and filed
      [#30](https://github.com/NewGraphEnvironment/cred/issues/30) for the missing check
- [x] **B2b** the mechanism was overstated: `ragnar_store_connect()` unserialises the store's
      *own* embedder, so a mismatch cannot mean "you queried with a different model".
      Restated as the model that name resolves to having moved
- [x] **B3** all of `httr2_http` mapped to "pull the model". Split: 404 → `model`, any other
      status → a new `service` reason that prescribes nothing
- [x] **G1, G3** two mutations survived the suite — dropping `location` from the frequency id,
      and stubbing the store-model lookup to `NA`. Both now caught
- [x] **G2** the `model` branch had no end-to-end test; added, skipped without Ollama
- [x] **G4, G5** a remedy named a hardcoded model rather than the one actually refused
- [x] **G6** `is.na()` on a possibly zero-length metadata read, inside the warning builder,
      against that function's own stated invariant. `.crd_have()` length-guards it
- [x] **AC1** blocks that must see the warning now use
      `withr::local_options(rlib_warning_verbosity = "verbose")` — stateless, and not coupled
      to the key scheme they police. Reset is kept only for the two frequency blocks
- [x] **AC3** the chained cause ran flush-left into the remedy; continuation lines indented
- [x] **A1, G9, O2** plan text corrected above
- [x] **S1, S2, S3** out of scope, named in #30 and in NEWS rather than left to read as
      oversights

## Phase 6: Own-probe finding — the model name is remote text

- [x] `.crd_fallback_model()` parsed a model name out of the service's 404 body and
      interpolated it into `ollama pull <name>` with no guard. Probed:
      `model "with ' quote" not found` produced `ollama pull with ' quote`, an unbalanced
      quote in a line the message invites the reader to paste. The message is printed and
      never executed, so this is not about what a hostile string would *do* — it is that a
      suggested command has to read as the command it is
- [x] `.crd_is_model_name()` whitelists Ollama's own grammar (namespace and tag), and the
      composed message falls back to the store's record rather than quoting a rejected name.
      The store's own record is trusted: it is local and this package wrote it
- [x] Mutation (accept any non-empty name) caught by 8 assertions — 13 for 13 overall
