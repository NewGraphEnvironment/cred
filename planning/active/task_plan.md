# Task: No connect-time embedding-model check: crd_store_connect() verifies md5, which cannot see a model change (#30)

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
detect the condition, which is the defect #29 itself is.

## Decisions taken at the plan gate

| fork | decision |
|---|---|
| confirmed width mismatch at connect | **error**, with `check_model = FALSE` escape — matches the md5 path and `crd_store_push(allow_model_mismatch = FALSE)` |
| live probe | **on by default**; skipped silently when unprobe-able; `verify = FALSE` keeps the offline path offline |

## Design

**The probe is the whole point.** `ncol(store@embed("<probe>"))` against
`SELECT embedding_size FROM metadata` is the *exact* condition that produces #29's `dimension`
fallback, and it uses the store's **own recorded embedder** — ragnar does
`embed <- unserialize(metadata$embed_func[[1L]])`, so this is not "a model name reconstructed
from a string", it is the thing that will actually embed queries.

**Width is the detectable part, and this must not over-claim.** A model that changed weights
while keeping its width is invisible to any check here. The docs say so.

**Severity tracks the evidence**, four tiers:

| evidence | outcome |
|---|---|
| probe ran, widths differ | **error** (escape: `check_model = FALSE`) |
| manifest label disagrees with the store's own record | **warning** — the manifest's model is the pusher's env label (`.crd_store_describe()` falls back to `CRED_EMBED_MODEL`), so it is the weaker half |
| probe could not run (no Ollama) | **not a mismatch** — classified via `.crd_retrieval_failure()`, reported once per session as "could not check" |
| store records no embedder, or `embedding_size` unreadable | skipped silently |

## Phase 1: Factor the per-reason remedy out of the fallback message

Enabling change for 2, 3 and 4, and the fix for "two accounts of one dead port".

- [x] `.crd_embed_remedy(reason, cond, store = NULL)` carries the per-reason body
- [x] `.crd_retrieval_fallback_msg()` becomes `head + remedy`, keeping its exact current text
- [x] `tests/testthat/test-store-fallback.R` stays green — the text is byte-identical across 40
      reason x cause x store combinations (verified against `HEAD:R/store.R`). The one edit is
      the structural drift guard at `:634`, which parses the function holding the branches and
      so had to follow them; it gained an assertion that the wrapper still routes through
      `.crd_embed_remedy()`
- [x] `store = NULL` stays safe in the `dimension` branch (`.crd_store_meta_brief(NULL)` is all-`NA`)

## Phase 2: `.crd_ollama_check()` on the shared remedy

- [x] Replace the fixed `ollama serve` + `ollama pull` remedy with `.crd_embed_remedy()` under an
      error-shaped head (`R/store.R:1072`, called from `crd_store_build()` at `:1162`)
- [x] Test: a `connection` failure does not lead with `ollama pull`
- [x] Test: a `service` failure does not print `ollama serve`

## Phase 3: `crd_search(method = "vss")` classified error

- [x] Wrap the `vss` branch, classify, re-raise with `rlang::abort(parent = e, class = c("cred_retrieval_error_<reason>", "cred_retrieval_error"))`
- [x] Message says no fallback exists for vss
- [x] Leave `bm25` unwrapped — it needs no embedding
- [x] Test via `local_ragnar_store_failing("dimension")` + `method = "vss"`

## Phase 4: The connect-time check

- [ ] `.crd_embed_width(x)` — `ncol()` on a matrix, `length()` on a vector, `NA` otherwise
- [ ] `.crd_check_store_embedding(store, entry = NULL, name)` — the four tiers, every read
      tolerant; reuse `.crd_model_norm()`. **Not** `.crd_check_model()`, which compares against
      *other* stores
- [ ] `crd_store_connect()` gains `check_model = TRUE`; its three
      `return(ragnar_store_connect(...))` sites collapse into one tail helper so the check cannot
      be added to two paths and missed on the third
- [ ] "Could not check" uses `rlang::warn(.frequency = "once")`, keyed on reason **and** store
      location
- [ ] Offline fixtures: fixture store is 16-wide, `.crd_test_embed_narrow` is 8-wide; `@embed` on
      a **copy** reaches neither the original nor the shared duckdb connection
- [ ] Mutation table: restore the defect and prove each guard fires

## Phase 5: The stale-claim sweep, docs, NEWS, version

#29's correct statement that connect *cannot* see a model change becomes half-true: still true
of **md5**, false of connect as a whole. Grep the sentence, not the one instance.

- [ ] `R/store.R:169-170` (`@details`) and `:790-793` (dimension remedy comment)
- [ ] `R/store.R:905` / `man/crd_search.Rd:106` — the `cred_retrieval_fallback_dimension` entry
- [ ] `man/crd_store_connect.Rd:50-51`
- [ ] `CLAUDE.md:202-206`
- [ ] `tests/testthat/test-store-fallback.R:294, 504` — two `expect_no_match(msg,
      "crd_store_connect")` assertions deliberately reverse; rewrite the comments to say why
- [ ] `devtools::document()`, `NEWS.md`, version bump to 0.4.0 as the final commit
- [ ] CLAUDE.md design-decision bullet

## Validation

- [ ] `devtools::test()` passes
- [ ] `lintr::lint_package()` is 0 lints
- [ ] `/code-check` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope

Detecting a model whose **weights** changed at constant width — no local signal exists for it.
The docs say so rather than implying the check is complete.
