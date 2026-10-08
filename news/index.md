# Changelog

## cred 0.3.2

`crd_search(method = "hybrid")` caught every semantic-retrieval failure
and prescribed one remedy: start Ollama. The cause was reported, so the
warning was recoverable, but the advice was wrong for anything that was
not a connection failure — and actively misleading for the one case that
matters most.

An embedding-width mismatch means the store was built against a
different embedding model than the one answering queries. That is the
“answers differently while looking healthy” condition
[`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)’s
md5 verification exists to catch. Reached through the fallback it
produced a warning telling you to start a service that was already
running, and then returned results, with nothing saying the store was
suspect.

- The failure is classified by condition **class** wherever one exists,
  which is stable in a way httr2’s wording, curl’s wording and the
  session locale are not. `httr2_failure` is a request that got no
  answer; `httr2_http` is a service that answered and refused — so it is
  running, and only the `ollama pull` half of the old advice applies.
  Both reach
  [`crd_search()`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
  unwrapped. Only the width mismatch needs message matching, and the
  text it matches is a duckdb binder error, not an Ollama one
- A width mismatch names the width and model the store itself records,
  says to treat the store as unverified, and prescribes the comparison
  that can actually see the condition — what the store records against
  what the service now returns, then a re-pull or
  [`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md).
  It deliberately does **not** send you to
  [`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md):
  that verification is an md5 compare against the manifest, and a store
  whose embedding model moved underneath it has exactly the bytes the
  manifest recorded, so the compare is structurally unable to see it.
  Prescribing it would have been a remedy that cannot detect the
  condition, which is the defect this release fixes.
  [`?crd_store_connect`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
  no longer claims otherwise, and the missing connect-time check is
  [\#30](https://github.com/NewGraphEnvironment/cred/issues/30)
- The diagnosis is also stated more narrowly than the issue framed it. A
  connected store embeds queries with the embedder ragnar unserialises
  out of the store itself, so a mismatch is not “you queried with a
  different model” — it is that the model that name resolves to on this
  machine is no longer the one the store was built with
- A reply from the service is classified by status **and body**. Only a
  404 *whose body names a model* means the model is absent — a 404 is
  also what a wrong path prefix returns, from a server holding every
  model you asked for — so `cred_retrieval_fallback_service` carries
  every other reply and prescribes nothing. An HTTP error that arrives
  with **no status class on it** lands there too:
  [`ragnar::embed_ollama()`](https://ragnar.tidyverse.org/reference/embed_ollama.html)
  parses the error body as JSON inside httr2’s own error handler, so an
  HTML 502 from a reverse proxy loses the class, and without that route
  it would have been reported as a possibly-corrupt store and sent the
  user to re-download it
- Any model name that reaches a suggested command is checked against
  Ollama’s own grammar first. Both candidates are untrusted: the name in
  a 404 body is remote text, and so is the one a store records, because
  stores are downloaded from a shared bucket
- A remedy names the model that was actually refused — the service names
  it in its own 404 body — falling back to the one the store records,
  and only then to the package default. The connection branch no longer
  hardcodes `nomic-embed-text` either
- An unrecognised failure reports its cause verbatim and prescribes no
  remedy beyond confirming the file is the one the manifest describes,
  which is the one thing md5 *can* answer
- Warnings are subclassed `cred_retrieval_fallback_<reason>`, all
  inheriting `cred_retrieval_fallback`, so a caller can act on the
  reason without grepping a message.
  [`?crd_search`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
  lists them
- They fire once per session per reason **and** per store. Keyed on the
  store alone a mismatch met after a connection failure would be
  swallowed as a repeat, which is the same diagnosis loss arriving by
  another route

Every failure still falls back to BM25 and the `method` column still
reports `"bm25"`, so no search that worked before this release behaves
differently — only what is said about one that degrades. Adds `rlang` to
Imports for the frequency guard, and raises the `testthat` floor to
3.1.8, which the suite already required.

Out of scope, filed as
[\#30](https://github.com/NewGraphEnvironment/cred/issues/30): the
build-side probe `.crd_ollama_check()` still conflates starting the
server with pulling the model, and `method = "vss"` raises its condition
unclassified.

## cred 0.3.1

[`crd_search()`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
errored on every store built with ragnar 0.3.0. Hybrid retrieval merges
adjacent retrieved chunks into one row and returns the per-chunk values
as **list** columns; `.crd_retrieval_score()` coerced them with
[`as.numeric()`](https://rdrr.io/r/base/numeric.html), which errors on a
multi-element cell. The
[`suppressWarnings()`](https://rdrr.io/r/base/warning.html) around it
read as a guard but could never have helped — coercing a list raises an
error, not a warning.

The misleading part was that the store itself was fine:
[`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
pulled and verified normally, so the failure looked like a store problem
to each consumer that hit it.

- Retrieval columns are reduced by an internal helper rather than
  coerced directly. A merged passage is scored by the **best** of its
  constituent chunks — highest for `bm25`, lowest for `cosine_distance`
  — so a row is never scored on a chunk that metric never retrieved, nor
  attributed to the wrong metric because the leading chunk happened to
  be unscored. Both retrieval shapes read one direction table, so they
  cannot disagree about which way a distance improves
- `chunk_id`, `start`, `end`, `origin` and `text` take the same path.
  `origin` matters beyond tidiness: `.crd_zot_key_from_path()` calls
  [`dirname()`](https://rdrr.io/r/base/basename.html), which errors on a
  list rather than degrading to `NA`
- A column absent from the frame — `bm25` is missing entirely when
  nothing matched lexically — yields typed `NA`s rather than a
  zero-length column
- **[`crd_search()`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
  never returned rows best-match first**, and now says so.
  `ragnar_retrieve()` does not re-sort after merging, so rows arrive in
  document order; under `hybrid`, neighbouring rows can carry different
  metrics whose scores are not comparable, so no single ranking exists
  to return. The documentation previously promised otherwise, which made
  [`head()`](https://rdrr.io/r/utils/head.html) a silent wrong answer.
  [`?crd_search`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
  now shows how to rank within one metric
- A coercion that discards data warns instead of being silenced. The
  only such warning reachable is `NAs introduced by coercion`, which
  means a score column holds non-numeric data — suppressing it produced
  an all-`NA` `score`, the same silent failure this release is about

## cred 0.3.0

Writing the shared manifest.
[`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
could read and verify it; nothing could write it, and no committed
implementation wrote it correctly anywhere — the prior art rebuilt the
manifest from the current run alone and overwrote the remote copy,
silently orphaning every other store.

- [`crd_store_push()`](https://newgraphenvironment.github.io/cred/reference/crd_store_push.md)
  — upload a store and **merge** its entry into the shared manifest.
  Three refusals guard the ways it gets corrupted: an unreadable
  manifest aborts the push; every write is conditional (ETag on update,
  `--if-none-match "*"` on create, so two simultaneous first pushes
  cannot overwrite one another); and a store whose embedding differs
  from the corpus is refused
- The embedding model is read from the store’s own serialized
  `embed_func`, so it describes the artifact rather than the machine
  doing the pushing
- Absence is established with `s3api head-bucket` + `head-object` rather
  than inferred from `aws s3 cp`, which reports a missing key and a
  nonexistent bucket identically — a wrong prefix would otherwise look
  like a first push
- Provenance records the repository that built the store, read from the
  store’s own directory
- `.crd_aws()` returns the exit status, and keeps stderr out of stdout
  for probes whose output is parsed

## cred 0.2.0

Corpus-wide evidence retrieval. Token-overlap search answers whether
*one* known source supports a claim; this release adds a second tier
that searches an entire indexed corpus and returns citable passages.

- [`crd_search()`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
  — retrieve passages from a ragnar store, labelled with the Zotero
  citation key rather than a machine-local file path. Falls back from
  hybrid to BM25 with a warning when Ollama is unreachable
- [`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
  — resolve a store by name, verifying its md5 against the shared
  manifest before opening and downloading atomically when it does not
  match
- [`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
  — build a store from a Zotero collection or an explicit set of
  citation keys, always pinning the embedding model
- The ragnar stack (`ragnar`, `DBI`, `duckdb`) is in `Suggests` and
  guarded at call time, so the audit workflow does not require a DuckDB
  install
- The store source is read from `getOption("cred.store_source")` or
  `CRED_STORE_SOURCE`, with no default and no bucket address in the
  package
- `planning/`, `CLAUDE.md` and `.claude/` no longer ship in the built
  tarball

## cred 0.1.0

First stable release. Core citation audit pipeline for detecting
hallucinated or misattributed citations in LLM-assisted bookdown
reports.

- Extract citations and surrounding sentences from Rmd files
- Verify claims against PDF and docx source documents via token overlap
- Resolve inline R expressions before matching
- Abstract fallback for sources without full text
- Risk scoring and claim type classification
- Top-N candidate passages stored as JSON for review
- Interactive Shiny review app with collapsible candidate panel
- Incremental CSV updates with fuzzy join to preserve human edits
