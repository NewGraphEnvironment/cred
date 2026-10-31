# #35 — crd_store_build(): an oversize chunk aborts the build; a NUL byte skips a paper

## Outcome

`crd_store_build()` now finishes past a PDF it cannot read and a chunk the embedding model
refuses, and names both. It gives `ragnar_store_ingest()` its own worker `prepare`, which
reads, chunks and embeds per document:

- A PDF markitdown cannot read (a NUL in its text) is read with `pdftools`.
- A chunk refused with a 400 that names the context length is halved by character range
  until it embeds, each range kept once. A part still refused at 64 characters is dropped and
  named.
- Any other embed failure still stops the build and deletes the store.

The issue's proposed fix, capping chunks below the model's context, was disproved by
measurement before any code was written. The limit is tokens, and characters do not predict
a refusal. That is recorded in [`research/ollama-embedding-context.md`](../../../research/ollama-embedding-context.md).
The plan review found the one defect that mattered (B1): halves of neighbouring chunks
inside one glyph run repeat a `(start, end)` range, which ragnar's `embeddings` primary key
refuses in the main process. That would have reintroduced the original abort. The live
ESL build happened not to hit it.

## Measurement

- ESL (764 pages): 2,404 chunks, median 434 tokens, maximum 2,039. **2** refused, both runs of
  `•` (2 tokens a character) at 1,887 and 1,706 characters, while 2,073-character prose
  embedded. Ollama 0.24.0 truncated 20,000 characters of prose to 2,048 tokens but returned a
  400 for 1,800 `•`. This turned the issue's assumption, a chunk too long in characters, into
  a measured cause: a truncation failure for particular input.
- The issue's four-paper collection: previously aborted with no store. It now builds in
  **4.25 min**: 4 documents, 2,838 chunks, 2 chunks split, 1 PDF read with pdftools.
  `crd_search()` returns Bates et al. passages.
- Cost of embedding inside `prepare`: main 10.6 s and 10.4 s, branch 10.5 s and 10.6 s, on two
  papers both can build (177 chunks each). No measurable cost.
- Plan review: 2 blockers (1 reproduced and fixed, 1 a wrong plan sentence), 7 gaps, 4
  acceptance findings. Code-check: round 1 had 2 findings (a shared notes log splices past
  4 KB, measured; two wrong claims about ragnar), and rounds 2 and 3 were clean. There were
  14 mutations across the guards, and each turned its test red.

## Owed

- Post the two upstream drafts — only on the user's word for each

The drafts (a comment for ollama/ollama#14186 and a tidyverse/ragnar issue) are in
`findings.md`, "Upstream drafts". Nothing has been posted.

Closed by: PR for branch `35-crd-store-build-an-oversize-chunk-aborts`
