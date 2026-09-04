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
Ollama is unreachable the search **falls back to BM25 with a warning**
rather than failing: lexical retrieval needs no embedding and remains
effective for the numeric and parameter-level claims this package exists
to check.

## Examples

``` r
if (FALSE) { # \dontrun{
store <- crd_store_connect("vca_refs")
crd_search(store, "bankfull width regression drainage area precipitation")
} # }
```
