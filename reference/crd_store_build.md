# Build a ragnar evidence store from Zotero PDFs

Ingests the PDFs attached to a Zotero collection — or to an explicit set
of citation keys — into a ragnar DuckDB store, chunked, embedded and
indexed for both semantic and BM25 retrieval.

## Usage

``` r
crd_store_build(
  store_path,
  collection = NULL,
  citation_keys = NULL,
  model = "nomic-embed-text",
  zotero_dir = "~/Zotero",
  overwrite = FALSE
)
```

## Arguments

- store_path:

  `character(1)` path for the `.duckdb` store to create.

- collection:

  `character(1)` Zotero collection name. Supply exactly one of
  `collection` or `citation_keys`.

- citation_keys:

  `character` vector of Better BibTeX citation keys.

- model:

  `character(1)` Ollama embedding model. Default `"nomic-embed-text"` —
  the model the shared stores are built with.

- zotero_dir:

  `character(1)` Zotero data directory. Default `"~/Zotero"`.

- overwrite:

  `logical(1)` replace an existing store. Default `FALSE`.

## Value

Invisibly, a
[tibble](https://tibble.tidyverse.org/reference/tibble.html) with one
row per ingested source (`citation_key`, `src_path`). Prints document
and chunk counts.

## Details

The embedding model is pinned explicitly on every build. This matters
more than it looks:
[`ragnar::embed_ollama()`](https://ragnar.tidyverse.org/reference/embed_ollama.html)
defaults to `embeddinggemma`, so a store built without pinning is
silently incomparable with every other store in the shared corpus while
appearing entirely healthy.

Building is expensive and machine-local. Sharing a built store is done
out of band; see
[`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
for the retrieval side.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_store_build("data/rag/vca_refs.duckdb", collection = "vca")

crd_store_build(
  "data/rag/adhoc.duckdb",
  citation_keys = c("hall_etal2007Predictingriver", "beechie_etal2005ClassificationHabitat")
)
} # }
```
