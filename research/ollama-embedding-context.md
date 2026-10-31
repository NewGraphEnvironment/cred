# Building a store: what Ollama and ragnar do with input they cannot take

**Verified:** 2026-10-31 · **Issues:** #35 · **Produced by:** probes of a local Ollama 0.24.0
`/api/embed` with `nomic-embed-text`, per-chunk token counts for the chunks ragnar 0.3.0 makes
from a 764-page textbook, and reading ragnar 0.3.0's ingest code (`ragnar_store_ingest`,
`do_ingest_remote_work`, `do_embed`, `ragnar_store_update_v2`, `embed_req_retry`). The numbers
are in the #35 archive's `findings.md`.

## The embedding model's limit is tokens, and characters do not predict it

- `nomic-embed-text` reports a context of 2,048 tokens (`nomic-bert.context_length`), although its
  Modelfile sets `num_ctx 8192`.
- With `markdown_chunk()`'s defaults (target 1,600 characters), the textbook's 2,404 chunks
  ranged up to 2,073 characters. Their token counts had a median of 434, a p99 of 1,510 and a
  maximum of 2,039.
- `•` costs 2 tokens a character. The two chunks the model refused were runs of `•` (a dot-plot
  figure) at 1,887 and 1,706 characters, while prose chunks of up to 2,073 characters embedded.
  So a cap on characters would not have caught them. The only reliable test of a chunk is
  whether the model accepts it.

## Ollama truncates some over-length input and refuses other input

`/api/embed` defaults `truncate` to true. On 0.24.0:

| input | result |
|---|---|
| 20,000 characters of prose | 2,048 tokens, embedded (truncated) |
| 3,000 × `中` | 2,048 tokens, embedded (truncated) |
| 1,000 × `•` | 2,002 tokens, embedded |
| 1,800 × `•` | **400** `the input length exceeds the context length` |
| 20,000 characters of prose, `truncate: false` | **400**, the same message |

So the 400 a default request meets is a truncation failure for particular input. It is a narrower
version of the open upstream issue ollama/ollama#14186 (truncate ignored since 0.13.5). Prose
longer than the limit is still embedded from its leading 2,048 tokens, without any warning.

`ragnar::embed_ollama()` raises the 400 as `httr2_http_400` (then `httr2_http`, `httr2_error`,
`rlang_error`), with Ollama's text in the message. Connection refused is `httr2_failure`. It
sends 10 inputs per request, so one refused input fails the whole request.

## Where ragnar's ingest turns one bad input into a lost build

- `prepare` runs in mirai workers. A worker's *read* error comes back as an error value. ragnar
  re-raises it with `warning(cond)` but keeps the error class, so it reaches `error =` calling
  handlers and never `warning =` ones. The document is skipped.
- A worker's *embed* error is swallowed (`tryCatch(..., error = function(e) NULL)`). The chunks
  return unembedded, and `ragnar_store_update_v2()` embeds them again in the main process with
  no handler. One refused chunk therefore ends `ragnar_store_ingest()`.
- If `prepare` returns chunks that already have an `embedding` column, both embeds are skipped.
- Workers run with `ragnar.embed.req_retry = FALSE`, so they do not retry a 429 or 503. The main
  process retries up to 20 times within 180 s.
- The v2 `chunks` table is keyed on `(doc_id, start, end)`, and `text` must equal
  `stri_sub(document, start, end)`.

cred's response, in `crd_store_build()`: cred's own `prepare` embeds in the worker and splits
a chunk only on a 400 that names the context length. It keeps each range once, and falls back
to `pdftools` for a document markitdown cannot read.

## markitdown text can carry a NUL

markitdown's output for an arXiv PDF contained a NUL byte. `read_as_markdown()` fails with
`Embedded NUL in string` through both its reticulate route and its CLI route (`stri_read_lines`).
`pdftools::pdf_text()` reads the same PDF cleanly.
