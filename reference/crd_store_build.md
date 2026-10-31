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
  overwrite = FALSE,
  library = getOption("cred.zotero_library")
)
```

## Arguments

- store_path:

  `character(1)` path for the `.duckdb` store to create.

- collection:

  `character(1)` Zotero collection name, or a `parent/child` path when
  the name alone matches more than one. Supply exactly one of
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

- library:

  The Zotero library to resolve keys in: `"user"` for My Library, or a
  group's name or groupID (as in its URL,
  `zotero.org/groups/<groupID>`). Zotero's internal `libraryID` is not
  accepted: it differs between machines. Default
  `getOption("cred.zotero_library")`; `NULL` searches every library.

## Value

Invisibly, a
[tibble](https://tibble.tidyverse.org/reference/tibble.html) with one
row per ingested file (`citation_key`, `src_path`), so a key with
several PDFs has several rows; a skipped PDF has none. Prints document
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

**What is ingested.** Every live PDF of each item: an appendix, or the
other parts of a multi-part report, are searchable too, and each still
answers to its item's citation key. Byte-identical copies on one item
are ingested once. Trashed items, trashed attachments and trashed
collections are never used. Before ingesting, the build lists every item
it leaves out and why (trashed, a note, a standalone attachment, no
citation key, a citation key shared by several items, no live PDF; for
`citation_keys`, also not found or unresolved), and the items it takes
several PDFs from.

**Which library.** Citation keys and collection names are unique within
a Zotero library at best, so both resolve in `library`. A key found in
more than one library, on two live items in one, or only in a library
other than `library`, is left out with a warning. A collection name that
matches more than one collection is an error listing each, with its
`parent/child` path. A collection's subcollections are not included.

**What cannot be read or embedded.** One PDF that cannot be read or
embedded does not cost the build. A PDF that markitdown cannot read,
such as one whose text carries a NUL byte, is read with
[`pdftools::pdf_text()`](https://docs.ropensci.org/pdftools//reference/pdftools.html)
instead, without markdown headings. A PDF neither can read is skipped,
and a warning names it and why. A chunk the embedding model refuses
whole, such as a long run of figure glyphs, is split until each part
embeds; a part still refused at 64 characters is left out of the
embeddings. Both are reported. A failure of the embedding service itself
still stops the build and leaves no store: it would cost every PDF still
to come, silently, rather than one that is named.

ragnar's own progress output is off, because it does not handle every
file name safely. The build says what it will ingest before it starts,
and what it ingested, read differently, split or skipped when it ends.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_store_build("data/rag/vca_refs.duckdb", collection = "vca",
                library = "NewGraphEnvironment")

crd_store_build(
  "data/rag/adhoc.duckdb",
  citation_keys = c("hall_etal2007Predictingriver", "beechie_etal2005ClassificationHabitat")
)
} # }
```
