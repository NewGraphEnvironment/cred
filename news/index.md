# Changelog

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
