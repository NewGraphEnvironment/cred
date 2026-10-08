# Search a ragnar evidence store for passages supporting a claim

Retrieves the passages most relevant to `query` and labels each with the
citation key of the paper it came from, so a result can be cited
directly rather than chased back through a file path.

## Usage

``` r
crd_search(
  store,
  query,
  top_k = 5L,
  method = c("hybrid", "bm25", "vss"),
  zotero_dir = "~/Zotero"
)
```

## Arguments

- store:

  a ragnar store, from
  [`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
  or
  [`ragnar::ragnar_store_connect()`](https://ragnar.tidyverse.org/reference/ragnar_store_create.html).

- query:

  `character(1)` search text.

- top_k:

  `integer(1)` passages to retrieve **per method**. Default `5L`. Under
  `method = "hybrid"` the vector and lexical result sets are unioned and
  then adjacent chunks are merged, so the number of rows returned is
  neither `top_k` nor `2 * top_k` — expect somewhere between the two.

- method:

  `character(1)` one of `"hybrid"`, `"bm25"`, `"vss"`.

- zotero_dir:

  `character(1)` Zotero data directory used to resolve citation keys.
  Default `"~/Zotero"`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with one
row per retrieved passage, with columns as below.

**Rows are returned in document order (`origin`, then position), not
best-match first.** `ragnar_retrieve()` does not re-sort after merging
overlapping chunks, and under `method = "hybrid"` neighbouring rows can
carry different metrics, whose scores are not comparable — so there is
no single ranking to return. To take the best passages, sort within one
metric:

    res <- crd_search(store, "bankfull width regression")
    dplyr::arrange(dplyr::filter(res, metric == "bm25"), dplyr::desc(score))

- `citation_key` (`character`) — BBT key, `NA` if unresolvable.

- `origin` (`character`) — source path recorded in the store.

- `chunk_id`, `start`, `end` (`integer`) — location within the document.
  A returned passage may be several adjacent chunks merged into one, in
  which case `chunk_id` is the first of them and `start`/`end` span them
  all.

- `text` (`character`) — the retrieved passage, verbatim.

- `score` (`numeric`) — retrieval metric value. Where a passage merges
  several chunks this is the best score among them: highest for `bm25`,
  lowest for `cosine_distance`.

- `metric` (`character`) — which metric produced `score` (`"bm25"` or
  `"cosine_distance"`). Scores are comparable only within a metric.

- `method` (`character`) — the method actually used, which differs from
  the request when a fallback occurred.

## Details

Unlike the token-overlap search in
[`crd_pdf_srch_clm()`](https://newgraphenvironment.github.io/cred/reference/crd_pdf_srch_clm.md),
which scores one known source against one paraphrase, this searches an
entire indexed corpus.

`method = "hybrid"` combines semantic (vector) and lexical (BM25)
retrieval and needs a running Ollama instance to embed the query. When
semantic retrieval fails **for any reason** the search falls back to
BM25 with a warning rather than failing: lexical retrieval needs no
embedding and remains effective for the numeric and parameter-level
claims this package exists to check. The `method` column reports
`"bm25"` when that happens, so a caller can always tell the search
degraded.

## Diagnosing a fallback

The warning is subclassed by what went wrong, so a caller can act on the
reason rather than grep the message. All inherit
`cred_retrieval_fallback`:

- `cred_retrieval_fallback_connection`:

  The embedding service could not be reached — start Ollama.

- `cred_retrieval_fallback_model`:

  HTTP 404 **whose body names a model** — the service answered, so it
  *is* running, and it says it does not have that model. The body
  matters: a 404 is also what a wrong path prefix returns, from a server
  holding every model you asked for.

- `cred_retrieval_fallback_service`:

  Any other reply from the service. It is running and erroring; the
  status is all cred knows, so no remedy is prescribed. Kept separate
  from the above precisely because pulling a model is unrelated to a 500
  or a 503. This also catches an HTTP error that arrived with no status
  class on it, which happens when the error body is not JSON —
  [`ragnar::embed_ollama()`](https://ragnar.tidyverse.org/reference/embed_ollama.html)
  parses it as JSON inside httr2's own error handler, so an HTML 502
  from a reverse proxy loses the class.

- `cred_retrieval_fallback_dimension`:

  The query embedding is a different width than the store's embeddings.
  A connected store embeds queries with the embedder recorded *inside
  it*, so this is not "you queried with a different model" — it is that
  the model that name resolves to on this machine is no longer the model
  the store was built with. **Treat the store as unverified**: a search
  that did succeed would answer differently while looking healthy.
  Compare what the store records against what the service now returns,
  then re-pull or rebuild with
  [`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md).
  Restarting Ollama cannot help, and neither can
  [`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md),
  whose MD5 compare cannot see a model change.

- `cred_retrieval_fallback_unknown`:

  Unrecognised. The cause is reported verbatim and no remedy is
  prescribed.

Each fires once per session per reason and per store, so a machine
without Ollama does not emit the same four lines on every call.

## Examples

``` r
if (FALSE) { # \dontrun{
store <- crd_store_connect("vca_refs")
crd_search(store, "bankfull width regression drainage area precipitation")
} # }
```
