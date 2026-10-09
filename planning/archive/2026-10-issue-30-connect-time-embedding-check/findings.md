# Findings — No connect-time embedding-model check (#30)

## Issue context

## Problem

`crd_store_connect()`'s `@details` claimed that verification catches a store "built against a
different embedding model". It does not. The MD5 compare answers *"is this the file the manifest
describes"* — a stale copy, a truncated download, a local rebuild nobody pushed. A store whose
embedding model has moved underneath it has **exactly the bytes the manifest recorded**, so the
compare is structurally unable to see it.

The manifest already carries `embedding_model` and `embedding_size`, and `.crd_check_model()`
(`R/store.R`) already knows how to compare them — but it runs on **push** only, never on connect.

This was found while fixing #29, whose first draft of the dimension-mismatch warning sent users
to `crd_store_connect()` to verify a model mismatch. That would have been a remedy that cannot
detect the condition, which is the defect #29 itself is. The docs claim has been corrected and
the warning now prescribes a check that can see it; the missing check is this issue.

## Proposed

A connect-time comparison of the store's recorded `embedding_size` / `embedding_model` against
the manifest entry, and optionally against what the local embedding service returns for that
model name. Decide deliberately whether a mismatch warns or errors — `crd_store_push()` has
`allow_model_mismatch` as precedent.

## Also in scope, both found by the same review

- **`.crd_ollama_check()`** (`R/store.R`) still conflates the two remedies for every error:
  `"Start the server and pull the model: ollama serve / ollama pull <model>"`. #29 built
  `.crd_retrieval_failure()`, which separates a transport failure (`httr2_failure`) from a
  service that answered and refused (`httr2_http`), and a 404 from any other status. As it
  stands `crd_search()` and `crd_store_build()` give different accounts of the same dead port.
  Deliberately left out of #29's scope rather than overlooked.
- **`crd_search(method = "vss")`** raises the raw condition unclassified. A user who explicitly
  asks for vss against a width-mismatched store gets `Binder Error: array_cosine_distance...`
  and no diagnosis. Erroring is correct there — no fallback exists for vss — but the message
  could be enriched with `.crd_retrieval_fallback_msg()`.

## Versions

cred 0.3.2, ragnar 0.3.0, R 4.5.2, macOS arm64.


## Established by reading, before implementation

### The probe mechanism

A connected store carries its own embedder: `ragnar_store_connect()` does
`embed <- unserialize(metadata$embed_func[[1L]])`. So `ncol(store@embed("probe"))` against
`SELECT embedding_size FROM metadata` tests the real condition — not a model name
reconstructed from a string.

### What the manifest compare can and cannot add

`.crd_store_describe()` (`R/store.R:1422`) reads `embedding_size` from the store itself, so a
manifest whose md5 matches must agree about size. Its `embedding_model`, though, falls back to
`Sys.getenv("CRED_EMBED_MODEL", "nomic-embed-text")` with a warning when the store's
`embed_func` is unreadable. So the manifest's **label** can genuinely disagree with the store's
own record while the bytes match. That is the only thing the manifest compare adds — a label
check, and the weaker half of the pair.

### Reusable helpers already present

| helper | what it gives |
|---|---|
| `.crd_retrieval_failure()` (`:559`) | classifies a condition into connection/model/service/dimension/unknown by class first |
| `.crd_store_meta_brief()` (`:608`) | tolerant read of `embedding_size` + recorded model; all-`NA` on `NULL` |
| `.crd_have()` (`:635`) | the non-empty test that does not trip on `nzchar(NA) == TRUE` |
| `.crd_model_norm()` (`:1523`) | strips `" (ollama)"` so a provider suffix is not a mismatch |
| `.crd_is_model_name()` (`:683`) | whitelist, so a store-recorded string never lands in a paste-me command |
| `.crd_indent_cause()` (`:696`) | indents a chained condition's continuation lines |
| `.crd_retrieval_fallback_id()` (`:826`) | frequency key on reason **and** store `location` |

### Offline fixture route

`helper-store.R:126-186` records three measured facts from #29: `@embed` is settable on an S7
copy and does not reach the original; the condition from `embed` propagates out of
`ragnar_retrieve()` unwrapped; and the `baseenv()` constraint binds only an `embed` serialised
in at create time. The cached fixture is 16-wide (`.crd_test_embed`) and
`.crd_test_embed_narrow` is 8-wide — so a confirmed width mismatch is reachable with no Ollama
and no network.

The one tier that needs a live server is `model`: only a running Ollama can answer 404. It
keeps the existing `.crd_ollama_reachable()` skip.

### The stale-claim surface

`grep` for the sentence rather than the quoted instance. Eight sites outside
`planning/archive/`:

```
R/store.R:169-170          @details — "no connect-time comparison exists yet"
R/store.R:790-793          dimension remedy comment — "the connect-time model check does not exist"
R/store.R:905              roxygen — "whose MD5 compare cannot see a model change"
man/crd_search.Rd:106      generated from the above
man/crd_store_connect.Rd:50-51  generated from the above
NEWS.md:28, :61            historical, correct as of 0.3.2 — NOT rewritten
CLAUDE.md:202-206          design decision bullet
tests/testthat/test-store-fallback.R:294, :504  two assertions that deliberately reverse
```

`NEWS.md` is history and stays as written; the 0.4.0 entry says what changed.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `test-store-fallback.R:650` premise `expect_gt(length(from_msg), 1L)` went red after the Phase 1 refactor | Not a text change — the guard parses the function holding the `identical(reason, ...)` branches, and they moved to `.crd_embed_remedy()`. Retargeted the grep; added an assertion that the wrapper still calls the shared builder, so the retarget cannot hide a future private copy |
| `.crd_store_open()`'s failure cleanup closed the cached fixture's connection; every later test file lost retrieval | The mock-based wiring test returned a copy of the cached store, which **shares** its duckdb connection, so the cleanup closed a connection it did not own. Replaced the mock with a throwaway `file.copy()` of the store whose recorded `embedding_size` is edited — the hazard `helper-store.R:144-146` records, met from the other direction |
| Mutations M2 and M5 reported 0 failures | Broken probe, not a test gap: `perl -0` anchors `^` to the start of the file, and bash expanded the `$` in `meta$size`. Redone in Python, both fire |
| Mutation M4 reported 0 failures | A real gap. The collision test rebuilt the expected frequency id from a literal, so it could not fail when the code's id changed. Extracted `.crd_store_probe_id()` so the test asks the code, and added the behavioural test that actually carries the property |
