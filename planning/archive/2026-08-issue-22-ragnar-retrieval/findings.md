# Findings — Add ragnar-powered retrieval for evidence search (#22)

## Verified during plan-mode exploration (2026-08-31)

| # | Finding | Evidence |
|---|---------|----------|
| 1 | `origin` is an absolute machine-local path, useless as a citation. Reverse attachment-key → `citationKey` join works. | `W6LD4RRG` → `hall_etal2007Predictingriver` |
| 2 | Bare `embed_ollama()` defaults to `embeddinggemma:300m`, NOT nomic-embed-text | `args(ragnar::embed_ollama)` |
| 3 | Store v2 has `chunks` AND `documents`/`embeddings`; soul `lit-search` skill wrongly says `chunks` is absent | `chunks`=2464, `embeddings`=2464, `documents`=15 |
| 4 | Reading an embedding column needs `dbConnect(..., array = "matrix")` | duckdb_r_allocate error otherwise |
| 5 | Manifest `built_by` is a string for `vca_refs`, an array for `fraser` | `s3://<bucket>/<prefix>/log.json` |
| 6 | Manifest names this issue as owner and states the merge contract | `"generating_script": "cred#22 pending"` |
| 7 | `tibble::tibble()` used across `R/` but tibble is not in Imports (transitive via dplyr) | `DESCRIPTION` |
| 8 | BM25 retrieval works with Ollama down; only VSS needs embeddings | port 11434 refused, bm25 returned Hall 2007 chunks 2386-2388 |
| 9 | Local `vca_refs.duckdb` md5 matches the manifest exactly | `34ff806cd9a55b18a25b9fadce294592` |
| 10 | `ragnar_store_ingest(build_index = TRUE)` by default — no separate index call needed | `args(ragnar::ragnar_store_ingest)` |

Environment at plan time: ragnar 0.3.0, Ollama **not running** (connection refused on 11434).

## Decisions taken (user-approved)

- `ragnar`, `DBI`, `duckdb` → **Suggests**, guarded with the `requireNamespace()` + `stop()`
  pattern already in `R/zotero.R:44` (not `rlang::check_installed()` — avoids adding rlang).
- `crd_store_build()` accepts **both** `collection=` and `citation_keys=`.
- S3 pull via **`aws` CLI shell-out**, matching `0157-rag-sync.R`.

## Prior art absorbed (448 lines, 5 scripts + 1 skill)

- `fresh/dev/rag_build.R` (35) — single PDF, queries `chunks`
- `restoration_wedzin_kwa_2024/scripts/rag_build.R` (98) — 15 PDFs by attachment key, **public repo, keys inline**
- `fish_passage_template_reporting/scripts/04_planning/0151-rag-build-from-zotero.R` (131) — Zotero Web API + collections
- `.../0152-rag-add-harvest.R` (66) — dedup by reportId
- `.../0157-rag-sync.R` (118) — push/pull; **replaces log.json instead of merging** (the defect)
- soul `skills/lit-search/SKILL.md` — the prose sixth copy

## Issue context

> Redacted below: the concrete store URI from the issue body is written as
> `s3://<bucket>/<prefix>/`, matching the shape-not-value rule this work adopts.
> The value remains readable in issue #22 itself.


## Problem

cred's current retrieval uses token-overlap scoring (`crd_pdf_srch_clm()`, `crd_zot_src_lookup()`). This works for post-hoc auditing but breaks down when searching for specific numbers, equations, and parameter values across heterogeneous PDFs. The Zotero MCP fulltext approach is also fragile (unstructured JSON, no page context).

Real-world failure: verifying VCA parameters for flooded#28 led to fabricated abstracts in shared Zotero library because the retrieval couldn't surface the actual quotes.

## Proposed Solution

Import `ragnar` (tidyverse/ragnar) as the retrieval engine:

### New functions
- `crd_store_build(collection, store_path)` — ingest PDFs from a Zotero collection into a ragnar DuckDB store (chunked, embedded via Ollama nomic-embed-text)
- `crd_search(store, query, top_k)` — BM25 + semantic search returning exact quotes with source paper and chunk location
- `crd_store_connect(store, source = getOption("cred.store_source"))` — resolve and open a store:
  use the local copy if present and its md5 matches the manifest, otherwise pull from `source` first

### Store sharing — added 2026-08-31

Built stores are expensive and machine-local, so they are already being shared out of band. Scope
this as **resolving** a store, not owning bucket policy:

- **No hardcoded bucket. `cred` is a PUBLIC package.** Read `getOption("cred.store_source")` /
  `CRED_STORE_SOURCE` with **no default**, and error clearly when unset. Document the *shape*
  (`s3://<bucket>/<prefix>/`), never the value. Precedent for the pattern:
  `drift::dft_map_interactive()` uses `getOption("drift.titiler_url")` the same way. Precedent for
  getting it wrong: `flooded` v0.3.2 had to strip an internal doc path out of published roxygen.
- **Pull, verify, then use.** Compare local md5 against the manifest before opening — a store built
  against a different embedding model answers differently while looking fine.
- **Push is out of scope here.** It is a build-side operation done rarely by whoever built the store,
  and belongs with the bucket infrastructure in NewGraphEnvironment/rtj#194.
- **The manifest contract is merge-on-write**, defined in rtj#194. A replace-semantics push has
  already been observed to orphan a store; if `cred` ever gains a push, it inherits that requirement.

### Integration with existing cred
- `crd_aud_verify_all()` could optionally use ragnar store instead of raw PDF text extraction
- `crd_zot_pull_quotes()` could delegate to `crd_search()` for better retrieval quality
- Existing audit/review workflow unchanged

### Dependencies
- ragnar (DuckDB backend, chunking, retrieval)
- Ollama nomic-embed-text (local embeddings, no API costs, offline)
- S3 client in **Suggests**, not Imports — a user working from a local store should not pay for it

## What this retires — 448 lines across 3 repos

The same job is currently implemented five times:

```
 35  fresh/dev/rag_build.R
 98  restoration_wedzin_kwa_2024/scripts/rag_build.R
131  fish_passage_template_reporting/scripts/04_planning/0151-rag-build-from-zotero.R
 66  fish_passage_template_reporting/scripts/04_planning/0152-rag-add-harvest.R
118  fish_passage_template_reporting/scripts/04_planning/0157-rag-sync.R
```

The copies have already diverged into a defect — `0157` replaces the shared manifest instead of
merging, silently orphaning any store it did not push (detail in rtj#194). That is the argument for
package functions: a manifest merge implemented once and tested once, rather than per repo.

Note `restoration_wedzin_kwa_2024` is **public** and its `rag_build.R` carries Zotero attachment keys
inline. Not secrets, but internal identifiers worth reviewing when that script is absorbed.

## First use case

Build store from ~25 VCA/hydrology/floodplain PDFs, verify parameter values (flood_factor, slope_threshold, bankfull regression coefficients) for flooded#28.

**Status 2026-08-31:** that store exists and is now shared — `vca_refs.duckdb` (15 docs, 2,464
chunks) at `s3://<bucket>/<prefix>/`, built by `restoration_wedzin_kwa_2024/scripts/rag_build.R`. It backs
`flooded/inst/research/vca_parameter_rationale.md`.

The live follow-on consumer is **NewGraphEnvironment/flooded#48**, which needs the Hall 2007 PDF to
settle whether the bankfull regression takes km2/cm or ha/mm — an 8.2x difference in predicted
channel width, currently unresolved because the doc and the code disagree. `hall_etal2007` is
already embedded in that store, so this is a retrieval problem, which is exactly what this issue is
for.

Relates to NewGraphEnvironment/sred-2025-2026#14
Relates to NewGraphEnvironment/flooded#28
Relates to NewGraphEnvironment/restoration_wedzin_kwa_2024#123
Relates to NewGraphEnvironment/rtj#194 (bucket, manifest contract, field access)
Relates to NewGraphEnvironment/flooded#48 (first consumer of the shared store)
Relates to NewGraphEnvironment/soul#23 (convention + cite-audit skill)



## Result — flooded#48 answered (2026-08-31)

`crd_search()` against `vca_refs`, BM25 fallback (Ollama down), settles the km²/cm vs ha/mm
question with two independent sources in the corpus:

- **`hall_etal2007Predictingriver`** (chunk 2386-2388): *"we estimated bankfull channel widths
  based on drainage area (km2) and mean annual precipitation (cm⁄yr)"*
- **`nagel_etal2014`** (VCA documentation): *"Bankfull depth (hbf, m) is empirically predicted by
  the VCA as a function of drainage area (A, km2) and average annual precipitation (cm/yr)"*

**The regression takes km² and cm/yr — not ha/mm.** Fixing the doc/code disagreement is
flooded#48's business, not this PR's.
