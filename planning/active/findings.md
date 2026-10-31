# Findings — crd_store_build(): an oversize chunk aborts the build; a NUL byte skips a paper (#35)

## Issue context

**If done:** `crd_store_build()` builds a store from a collection that holds a long book or a PDF whose text carries a NUL byte, embedding what it can and naming what it could not. **If never:** one oversize chunk aborts the whole build and leaves no store, so a collection with a textbook in it cannot be searched at all.

## Problem

Building a four-paper collection (cred 0.3.0, ragnar 0.3.0, Ollama `nomic-embed-text`):

```r
cred::crd_store_build("data/rag/model_selection.duckdb", collection = "model_selection")
```

1. **A long book aborts the build.** *The Elements of Statistical Learning* (2nd ed., 764 pages) yields a chunk longer than the embedding model's context, and Ollama answers `HTTP 400 Bad Request. the input length exceeds the context length`. `ragnar_store_ingest()` stops and no store file is written, so the two papers already ingested are lost too.
2. **A NUL byte skips a paper.** The arXiv PDF of Bates, Hastie & Tibshirani, "Cross-validation: what does it estimate and how well does it do it?" (2104.00673v4) fails in ragnar's `prepare()` with `Embedded NUL in string`. It is skipped with only a warning.

`crd_store_build()` calls `ragnar_store_ingest(store, src$src_path)` with ragnar's default chunking and no cap on chunk length (`deparse(cred::crd_store_build)`).

## Proposed

- Cap each chunk below the embedding model's context (chunk the markdown to a token budget, or split any chunk over it) so no single page can abort a build.
- Ingest document by document: a document that fails to read or embed is skipped, the build finishes, and the summary names each skipped document and why.
- Strip NUL bytes from extracted text before chunking.

## Context

Found while checking the statistics citations of a package article: the citations were verified against the PDFs' text directly, but the shared store for the collection could not be built.


## Plan-time measurements (2026-10-31)

Summarised in `task_plan.md`. Probes ran against the PDFs named in the issue, a local
Ollama 0.24.0 and ragnar 0.3.0; scripts were throwaway and are not committed.

- ESL: 1,923,671 markdown characters, 2,404 chunks (default `markdown_chunk()`, target 1,600).
  Chunk text median 1,600 / p99 1,933 / max 2,072 characters; heading context at most 13.
- Token counts per chunk (Ollama `prompt_eval_count`, one input per call): median 434,
  p99 1,510, max 2,039. Two chunks (indices 2274, 2275) return 400; both start
  `# Values Type\\n••••…` at 1,887 and 1,706 characters.
- `•` = 2 tokens per character: 1,000 → 2,002 tokens OK; 1,800 → 400.
- Prose (`"salmon "` repeated) at 16,000 and 20,000 characters → 2,048 tokens, OK (truncated).
  `中` x3000 → 2,048, OK. `truncate: false` on 20,000 prose characters → the same 400.
- Bates et al. (arXiv 2104.00673v4): `read_as_markdown()` → `Embedded NUL in string` via
  reticulate; with `options(ragnar.markitdown.use_reticulate = FALSE)` the CLI route fails too
  (`embedded nul in string`). `pdftools::pdf_text()` → 43 pages, 204,561 characters.
- Upstream: ollama/ollama#14186 (open, 2026-02-10): truncate ignored since 0.13.5. On 0.24.0
  truncation works for prose, so the `•` case is a narrower residue of it.

## Errors Encountered

| Error | Resolution |
|-------|------------|
