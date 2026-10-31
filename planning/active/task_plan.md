# Task: crd_store_build(): an oversize chunk aborts the build; a NUL byte skips a paper (#35)

**If done:** `crd_store_build()` builds a store from a collection that holds a long book or a PDF whose text carries a NUL byte, embedding what it can and naming what it could not. **If never:** one oversize chunk aborts the whole build and leaves no store, so a collection with a textbook in it cannot be searched at all.

## What exploration measured (ragnar 0.3.0, Ollama 0.24.0, `nomic-embed-text`, context 2048 tokens)

- **The abort is in the main process, not the worker.** In a worker, `do_ingest_remote_work()`
  swallows an embed error and returns the chunks with no embedding. The main process then
  re-embeds in `ragnar_store_update_v2()` (`store@embed(...)`) with no handler, so a single 400
  ends `ragnar_store_ingest()`. A *read* error in a worker is already turned into a `warning()`
  and skipped. That is the reported NUL behaviour.
- **The problem is token count, not chunk length, so the issue's proposed "cap each chunk" does
  not fix it.** ESL gives 2,404 chunks: median 434 tokens, p99 1,510, max 2,039. **Two**
  of them fail with `400 the input length exceeds the context length`. Both are runs of `•`
  glyphs (a dot-plot figure) at 1,887 and 1,706 characters, while 2,073-character prose chunks
  pass. `•` costs 2 tokens per character.
- **Ollama truncates most over-length input, but not this one.** With the default
  `truncate`, 20,000 characters of prose and 3,000 `中` are cut to 2,048 tokens and succeed.
  1,800 `•` gives a 400. This is a variant of the open upstream issue ollama/ollama#14186
  (truncate ignored since 0.13.5).
- **The NUL comes from markitdown's output.** `read_as_markdown()` fails with `Embedded NUL in
  string` through reticulate, and through the markitdown CLI route too (`stri_read_lines`).
  `pdftools::pdf_text()` (already in Imports) reads the same PDF cleanly: 43 pages, 204,561
  characters.
- `ragnar_store_ingest(prepare = )` runs `prepare` in mirai workers. If `prepare` returns chunks
  that already carry an `embedding` column, both `do_embed()` and the main-process re-embed
  skip. So cred can own reading, chunking and embedding per document and still keep ragnar's
  parallel workers. `prepare` is serialised to the workers, so it must reference only base R
  and `pkg::` calls. That is the same `baseenv()` constraint as `helper-store.R`. Otherwise a
  worker loads the *installed* cred.

## Decided at the gate

Approved by the user at the plan gate, 2026-10-31 (recommendations accepted as written).

1. **Unreadable document (NUL or any markitdown failure) → fall back to `pdftools` text** for
   that document, then name it in the summary. A document both readers fail on is skipped and
   named. *Alternative:* skip and name only, and wait for a ragnar fix. The fallback loses
   markdown headings (chunk `context`) for that document only.
2. **A chunk Ollama will not embed → split it in half by character range until each part
   embeds**. Each part keeps `text == substr(document, start, end)`, as ragnar's v2 store
   requires. A part that still fails at a floor of 64 characters is dropped and named. Any
   *non-400* embed failure (connection, 404, 500) is not input-specific. It returns the chunks
   unembedded, so the main-process re-embed fails as it does today, and the store is deleted
   rather than left short. *Alternative:* drop the whole chunk.
3. **Mechanism (mine):** keep ragnar's parallel ingest and pass it a cred `prepare`. The other
   option was a serial in-process loop, which would cost build time on large collections.
4. **Upstream: drafts only, nothing posted.** A comment for ollama/ollama#14186 with the `•`
   repro, and a tidyverse/ragnar issue: `read_as_markdown()` fails on a NUL in markitdown
   output, and a single main-process embed error aborts `ragnar_store_ingest()`.

## Phase 1: Failing tests (`tests/testthat/test-store-build.R`)
- [x] `prepare` falls back to `pdftools` when the reader errors (inject a reader that raises
      `Embedded NUL in string` on the toy `inst/extdata/storage/TOYPDF1/salmon_habitat.pdf`),
      and records the fallback
- [x] `prepare` splits a chunk whose embed raises a constructed `httr2_http_400`, and every
      resulting row satisfies `text == substr(document, start, end)`, with full coverage of the
      original range
- [x] `prepare` drops and records a chunk that still 400s at the floor
- [x] `prepare` returns the chunks unembedded on a non-400 failure (`httr2_failure`)
- [x] End to end through the real `ragnar_store_ingest()` on an offline store (the
      `.crd_test_embed` pattern, mirai workers): one doc that both readers reject plus good
      docs. The ingest finishes, the store holds the good docs, and the result names the
      skipped doc and its reason. Run it with the worker `prepare` serialised, which proves the
      `baseenv()` closure works in a worker.
- [ ] Restore each defect (no split, no fallback, `prepare` closing over a cred helper) and
      confirm the matching test goes red

## Phase 2: Implement (`R/store.R`)
- [ ] `.crd_ingest_prepare(embed, log, read = <read_as_markdown>)` is a factory. It returns
      `function(path)` with `environment = list2env(..., parent = baseenv())`: read → fallback →
      `markdown_chunk()` → embed with split-on-400 → return chunks with `embedding`. It appends
      one tab-separated line per note (origin, kind, detail) to `log`, which workers can append
      to (local daemons, short single-line writes).
- [ ] `.crd_store_ingest(store, paths)` builds `prepare` from `store@embed` (the store's own
      recorded embedder, so vectors cannot come from a different model). It runs
      `ragnar_store_ingest(prepare = )` under `withCallingHandlers()`, recording and muffling
      ragnar's per-document warnings. It returns `list(ingested, skipped, notes)`, with
      `ingested` read back from the `documents` table.
- [ ] Wire into `crd_store_build()`. Message the notes (fallback reads, split or dropped chunks).
      Raise one `warning()` naming each skipped document and why. If zero documents were
      ingested, stop and give the reasons, which still deletes the store. Return only ingested
      files, as the roxygen already promises (today it returns every attempted file).
- [ ] Roxygen: a **What cannot be read or embedded** paragraph in `?crd_store_build`.
      `devtools::document()`, `lintr::lint_package()` with 0 lints.

## Phase 3: Live verification (local; nothing committed that names local paths or the collection)
- [ ] Build the four-paper collection from the issue. It completes; ESL is ingested and its two
      `•` chunks are reported split; Bates et al. is reported read with pdftools. Record the
      time, plus doc and chunk counts.
- [ ] `crd_search()` on the built store returns a Bates et al. passage for a cross-validation
      query

## Phase 4: Docs and record
- [ ] `CLAUDE.md`: a Key Design Decisions bullet (token count, not characters; the main-process
      abort; why `prepare` is `baseenv()`), and add `test-store-build.R` to the architecture
      list
- [ ] `research/ollama-embedding-context.md` gets the measured truncation behaviour and the `•`
      case, plus a README row
- [ ] Edit the #35 body: the cause is token count, so "cap each chunk" is replaced by the
      measured mechanism. Link the research file.
- [ ] Upstream drafts in `findings.md`

## Owed at the end (reported, done after merge)
- [ ] Post the two upstream drafts — only on the user's word for each

## Validation
- [ ] Tests pass (`devtools::test()`; the e2e test also under `R CMD check`, since workers run
      against the installed package)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the Phase 1 tests and their restored-defect runs prove each mechanism offline. The
Phase 3 build proves the reported case on the real PDFs, against a live Ollama.

