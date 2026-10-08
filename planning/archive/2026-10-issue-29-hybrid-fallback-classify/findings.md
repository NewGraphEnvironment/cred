# Findings — crd_search() hybrid fallback blames Ollama for every failure (#29)

## Measured: the four failure shapes

Probed 2026-10-07 against ragnar 0.3.0, duckdb, R 4.5.2, macOS arm64, using an offline
store built the way `tests/testthat/helper-store.R` builds one (`ragnar_store_create()`
accepts any function for `embed`).

### 1. Ollama unreachable — `embed_ollama(base_url = "http://127.0.0.1:1/")`

```
CLASS: httr2_failure / httr2_error / rlang_error / error / condition
PARENT CLASS: curl_error_couldnt_connect / curl_error / error / condition
MESSAGE: Failed to perform HTTP request.
         Caused by error in `curl::curl_fetch_memory()`:
         ! Could not connect to server [127.0.0.1]: ...
CALL: req_perform(req)
```

**The class survives intact through `ragnar_retrieve()`** — ragnar does not catch and
re-wrap it. So `inherits(cond, "httr2_failure")` is available to `crd_search()`.

### 2. Model never pulled — Ollama **up**, `embed_ollama(model = "no-such-model-xyz")`

```
CLASS: httr2_http_404 / httr2_http / httr2_error / rlang_error / rlang_error / error / condition
MESSAGE: HTTP 404 Not Found.
         ℹ model "no-such-model-xyz" not found, try pulling it first
```

Not in the issue, and the second-likeliest real failure. It is the case where the current
message is **half** right: `ollama pull` is the remedy, `ollama serve` is not — the service
answered.

### 3. Embedding width mismatch — store 16-dim, query embedder 8-dim

```
CLASS: rlang_error / error / condition
MESSAGE: Binder Error: array_cosine_distance: Array arguments must be of the same size
         ℹ Context: rapi_prepare
         ℹ Error type: BINDER
```

A duckdb **binder** error, not an Ollama one. Identical through `ragnar_retrieve()` and
`ragnar_retrieve_vss()`. No distinguishing condition class, so this is the one branch that
needs a message regex. The insert-time variant of the same mismatch reads
`Conversion Error: Cannot cast array of size 16 to array of size 8 when casting from
source column embedding` — matched too, since it is the same condition seen from the other
side.

### 4. Anything else

No class and no matching message. Report verbatim, prescribe nothing.

## Why class beats regex

The issue proposes matching `Connection refused`, `Failed to connect`, `Timeout`, curl's
codes. Three of the four shapes above carry a **class** that says the same thing and does
not move with locale, curl version, or httr2's message wording. Only shape 3 needs text
matching, and the text to match is not the text the issue proposes.

## How to induce each shape offline, with no mocking

`ragnar_store_connect()` returns an S7 object whose `embed` property is **settable**
(verified). So a copy of the fixture store with `@embed` replaced reaches each branch
through the real `ragnar_retrieve()` call:

| shape | `@embed` replacement |
|---|---|
| connection | `ragnar::embed_ollama(base_url = "http://127.0.0.1:1/")` |
| missing model | `ragnar::embed_ollama(model = "<nonexistent>")` — needs Ollama up, so `skip` off a live server |
| width mismatch | a deterministic embedder of a different width than the store |
| unknown | `function(x) stop("Catalog Error: Index 'vss_idx' does not exist")` |

This removes the need for `local_mocked_bindings(.package = "ragnar")`, and therefore the
need to bump `testthat (>= 3.0.0)` to `(>= 3.2.0)`.

Caveat on the missing-model fixture: it is the one shape that **cannot** be reached without
a running Ollama, so its test must skip when the server is absent — `skip_on_ci()` plus a
reachability check, never `skip_on_cran()` (which does not skip under `devtools::test()` or
on GitHub Actions). The classification of that shape is still covered unconditionally by a
hand-built condition in the unit tests.

## Existing machinery to reuse

- `.crd_store_model_from_meta(con)` (`R/store.R:973`) — unserialises `metadata.embed_func`
  and regex-extracts `model = "..."`. Takes a DBI connection; `store@con` supplies one.
- `SELECT embedding_size FROM metadata` — the read `.crd_store_describe()` already uses
  (`R/store.R:1010`), with its own precedent for warning when the read fails rather than
  silently disabling the check.
- `rlang` 1.3.0 is installed (via dplyr) and exports both `warn` and
  `reset_warning_verbosity`. It is **not** in `Imports` and must be added.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| First mismatch probe died at **insert** (`Cannot cast array of size 16 to array of size 8`), not at retrieve | `ragnar_store_create()` fixes the embedding column width from `ncol(embed("foo"))`, so an embedder whose width varies by input fails on insert. Induce the mismatch *after* the store is built, by overriding `@embed` on the connected store |
| `Rscript -e` with `\\(` inside a single-quoted regex → `'\(' is an unrecognized escape` | Write probes to a file in the scratchpad and `Rscript` the file |
