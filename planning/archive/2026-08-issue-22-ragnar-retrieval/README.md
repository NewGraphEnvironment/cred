## Outcome

Added a corpus-wide retrieval tier to cred — `crd_store_connect()`, `crd_search()` and
`crd_store_build()` in `R/store.R` — replacing five divergent copies of the same ragnar build
script plus the prose copy in soul's `lit-search` skill. Token-overlap search answers "does *this*
source support the claim"; this answers "which of these 25 PDFs does, and where".

What the work turned up, beyond the issue's own framing:

- The store's `origin` is an absolute machine-local path and is useless as a citation. Mapping it
  back through the Zotero attachment key to a BBT citation key is the single thing that makes a
  cred wrapper worth more than calling ragnar directly.
- A bare `embed_ollama()` defaults to `embeddinggemma`, not nomic-embed-text. A store built
  without pinning the model is silently incomparable with every other store while looking healthy.
  Pinning is now unconditional, and `crd_store_connect()` verifies md5 against the shared manifest.
- BM25 needs no embeddings, so retrieval degrades to lexical search with a warning when Ollama is
  down rather than failing. This is not a consolation prize: the BM25-only path is what answered
  the motivating question.
- `ragnar_retrieve()` pivots `metric_name`/`metric_value` wider, so reading `metric_value` on the
  default hybrid path yields an all-`NA` score. Caught only by reading ragnar's source — the
  end-to-end test missed it because Ollama was down and always fell back to BM25.

The first consumer question is answered: `hall_etal2007Predictingriver` and `nagel_etal2014` both
state the bankfull regression takes drainage area in **km²** and precipitation in **cm/yr**, not
ha/mm — the 8.2x discrepancy in flooded#48.

Two `/code-check` rounds found seven real defects, all fixed and verified empirically rather than
by inspection: shell injection through unquoted `system2()` arguments, a non-atomic download that
destroyed unpushed local stores, a missing `on.exit` that left partially-ingested stores on disk,
a `complete <- TRUE` set late enough that a failed reporting query would delete a finished
embedding run, an `nzchar(NA)` guard hole, and `.Rbuildignore` shipping `planning/`, `CLAUDE.md`
and `.claude/` in the tarball one commit after the repo was flipped public.

Deliberately out of scope: push and manifest merge (rtj#194), integration with
`crd_aud_verify_all()` / `crd_zot_pull_quotes()` (#2), and retiring the five source scripts.

Closed by: PR for issue #22
