# Task: Add ragnar-powered retrieval for evidence search (#22)

## Context

cred's retrieval today is token overlap (`crd_pdf_srch_clm()`, `crd_docx_srch_clm()` via
`.paraphrase_tokens()`/`.token_score()`). That is the right tool for post-hoc auditing of a
paraphrase against one known source, but it cannot answer "which of these 25 PDFs states the
bankfull regression coefficient, and what exactly does it say?" — it has no cross-corpus index and
no notion of a chunk.

The same ragnar-based fix has now been written **six times** — five scripts (448 lines across
`fresh`, `restoration_wedzin_kwa_2024`, `fish_passage_template_reporting`) plus the prose copy in
soul's `lit-search` skill. The copies have already diverged into a defect: `0157-rag-sync.R`
*replaces* `log.json` instead of merging, silently orphaning any store not in the current push.

The live consumer is **flooded#48**: does the Hall 2007 bankfull regression take km²/cm or ha/mm?
An 8.2× difference in predicted channel width, currently unresolved because doc and code disagree.

**Verified during planning** — this is a retrieval problem cred can solve today:

- `vca_refs.duckdb` (15 docs, 2,464 chunks) is on disk locally, and `md5` matches the S3 manifest
  exactly (`34ff806c…`).
- `ragnar_retrieve_bm25(store, "bankfull width regression drainage area precipitation")` returns
  chunks 2386–2388 of `hall_et_al._2007-predicting_river_flo.pdf` — the right paper, first hit.
- That worked with **Ollama down** (port 11434 refused). BM25 needs no embedding; only VSS does.

Outcome: three exported functions in cred, so the retrieval is implemented and tested once.

## Constraints (settled)

| Decision | Choice |
|---|---|
| Dependencies | `ragnar`, `DBI`, `duckdb` → **Suggests**, guarded at call time |
| `crd_store_build()` input | **Both** `collection=` (Zotero collection name) and `citation_keys=` |
| S3 pull | **`aws` CLI shell-out**, same mechanism as `0157-rag-sync.R` |

Guard with the `requireNamespace(..., quietly = TRUE)` + `stop()` pattern **already used in
`R/zotero.R:44`** — not `rlang::check_installed()`, which would add rlang to Imports for no gain.

## Findings that shape the work

1. **`origin` is an absolute, machine-local path** (`/Users/airvine/Zotero/storage/W6LD4RRG/…`).
   Useless as a citation. The durable part is the attachment key, and a reverse
   attachment-key → `citationKey` SQL join **is verified working**
   (`W6LD4RRG` → `hall_etal2007Predictingriver`). Turning origins into citation keys is the single
   thing that makes cred's wrapper worth more than calling ragnar directly.
2. **`embed_ollama()` bare defaults to `embeddinggemma:300m`, not nomic-embed-text.** A store built
   with the wrong model looks fine and answers differently. Must always pass
   `embed = \(x) embed_ollama(x, model = "nomic-embed-text")`.
3. **Store v2 has `chunks` *and* `documents`/`embeddings`.** `chunks` (2,464 rows) carries
   `origin`, `text`, `start`, `end`; `documents` is 15 rows. The soul `lit-search` skill asserts
   `chunks` does not exist — it does. Count docs from `documents`, chunks from `chunks`.
4. **Reading an embedding column needs `dbConnect(..., array = "matrix")`** or duckdb errors.
5. **The manifest is inconsistently typed**: `built_by` is a string for `vca_refs`, an array for
   `fraser`. Parse defensively.
6. The manifest already names this issue as owner — `"generating_script": "cred#22 pending"` — and
   carries the contract: `"Push must merge into this file, never replace it."`
7. `tibble::tibble()` is used throughout `R/` but **tibble is not in Imports** (works transitively
   via dplyr). Pre-existing; noted, not fixed here.

## Phase 1 — Store resolution (`crd_store_connect`)

- [x] Add `ragnar`, `DBI`, `duckdb` to `Suggests` in `DESCRIPTION`
- [x] New `R/store.R`; internal `.crd_need(pkg)` mirroring the `R/zotero.R:44` guard
- [x] `.crd_manifest_read(source)` — pull `log.json` via `aws s3 cp`, parse with `jsonlite`
      (already an Import); tolerate string-or-array `built_by`
- [x] `crd_store_connect(store, source = getOption("cred.store_source"), profile, read_only = TRUE)`
      - resolve local path; if present, `tools::md5sum()` vs manifest → open on match
      - on mismatch or absence, pull from `source`, re-verify, then open
      - `source` **has no default value**; when unset, error naming both
        `options(cred.store_source=)` and `CRED_STORE_SOURCE`, documenting the *shape*
        `s3://<bucket>/<prefix>/` and never a real bucket. Precedent: `drift::dft_map_interactive()`
        `titiler_url = getOption("drift.titiler_url")` (`drift/R/dft_map_interactive.R:79`)
- [x] Roxygen: no bucket value anywhere (cf. `flooded` v0.3.2 stripping an internal path)
- [x] Push stays **out of scope** — build-side, belongs with rtj#194

## Phase 2 — Search (`crd_search`)

- [x] `.crd_zot_key_from_path(paths, zotero_dir)` in `R/zotero.R` — reverse attachment-key join,
      complementing the existing forward `crd_zot_src_lookup()`
- [x] `crd_search(store, query, top_k = 5, method = c("hybrid","bm25","vss"), zotero_dir = "~/Zotero")`
- [x] **Degrade, don't fail**: `method = "hybrid"` probes Ollama; if unreachable, fall back to
      `ragnar_retrieve_bm25()` with a warning naming the fallback. Verified this path returns the
      correct Hall 2007 chunks with Ollama down
- [x] Return tibble: `citation_key`, `origin`, `chunk_id`, `start`, `end`, `text`, `score`, `method`
      (`citation_key` `NA` where the origin is not a resolvable Zotero attachment)

## Phase 3 — Build (`crd_store_build`)

- [x] `.crd_zot_collection_pdfs(collection, zotero_dir)` — `collections` → `collectionItems` →
      attachments (`collections` table confirmed present)
- [x] `crd_store_build(store_path, collection = NULL, citation_keys = NULL, model = "nomic-embed-text", overwrite = FALSE)`
      - exactly one of `collection`/`citation_keys`; `citation_keys` reuses `crd_zot_src_lookup()`
      - preflight Ollama with an actionable error (`ollama serve` / `ollama pull`) — it is
        **down right now**, so this is the first thing a user will hit
      - always pin the embed model per finding 2; `ragnar_store_ingest()` builds the index by
        default (`build_index = TRUE`), so no separate `ragnar_store_build_index()` call
- [x] Report docs/chunks from the correct tables (finding 3)

## Phase 4 — Tests, docs, hygiene

- [x] `tests/testthat/test-store.R` — no network, no Ollama, no S3:
      - manifest parse incl. string-vs-array `built_by`
      - `crd_store_connect()` errors clearly when `source` unset
      - md5 verify accept/reject against a fixture
      - `.crd_zot_key_from_path()` on a fixture path set
      - `skip_if_not_installed("ragnar")` / `skip_on_cran()` on anything touching a real store
- [x] `crd_store_build()`/`crd_search()` examples wrapped in `\dontrun{}` (repo convention)
- [x] Add `data/rag/` to `.gitignore` (absent today)
- [x] `devtools::document()`; `lintr::lint_package()` must be 0
- [x] Update `CLAUDE.md` architecture block above the soul marker with `R/store.R` and a
      `crd_store_*` naming entry

## Explicitly out of scope

- **Push / manifest merge** — issue defers to rtj#194
- **`crd_aud_verify_all()` and `crd_zot_pull_quotes()` integration** — issue says "could
  optionally"; `crd_zot_pull_quotes()` does not exist yet (issue #2). Speculative, deferred
- **Retiring the five scripts and folding soul's `lit-search` skill onto these functions** —
  follow-ups in their own repos once this lands
- **The inline Zotero attachment keys in public `restoration_wedzin_kwa_2024/scripts/rag_build.R`**
  — flagged in the issue, fix belongs in that repo

## Validation

- [x] `devtools::test()` passes
- [x] `/code-check` clean on each commit
- [x] `lintr::lint_package()` reports 0 lints
- [x] PWF checkboxes match landed work
- [x] End-to-end: `crd_search()` names `hall_etal2007Predictingriver` as top hit for the
      bankfull query with Ollama down (BM25 fallback)
- [ ] `/planning-archive` on completion
