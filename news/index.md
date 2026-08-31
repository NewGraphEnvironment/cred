# Changelog

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
