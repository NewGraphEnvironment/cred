# Bring an existing evidence store up to date with Zotero

Resolves sources exactly as
[`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
does, then changes only what differs: PDFs new to the store are
ingested, PDFs whose bytes changed are ingested again, and documents
whose source no longer resolves (an item trashed, an attachment
replaced, a member taken out of the collection) are removed. Everything
else is kept as it is, without being read or embedded again. The result
holds the documents a fresh build from the same arguments would hold, at
the cost of the changes alone.

## Usage

``` r
crd_store_update(
  store_path,
  collection = NULL,
  citation_keys = NULL,
  zotero_dir = "~/Zotero",
  library = getOption("cred.zotero_library")
)
```

## Arguments

- store_path:

  `character(1)` path to an existing `.duckdb` store.

- collection:

  `character(1)` Zotero collection name, or a `parent/child` path when
  the name alone matches more than one. Supply exactly one of
  `collection` or `citation_keys`.

- citation_keys:

  `character` vector of Better BibTeX citation keys.

- zotero_dir:

  `character(1)` Zotero data directory. Default `"~/Zotero"`.

- library:

  The Zotero library to resolve keys in: `"user"` for My Library, or a
  group's name or groupID (as in its URL,
  `zotero.org/groups/<groupID>`). Zotero's internal `libraryID` is not
  accepted: it differs between machines. Default
  `getOption("cred.zotero_library")`; `NULL` searches every library.

## Value

Invisibly, a
[tibble](https://tibble.tidyverse.org/reference/tibble.html) with one
row per resolved file the store now holds (`citation_key`, `src_path`),
as
[`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
returns. Prints how many documents were added, replaced, removed and
kept.

## Details

**How a document is matched.** A store records each document by the path
its PDF had on the machine that built it. A file Zotero holds is matched
by its `storage/<attachment key>/<file name>` instead, so a store built
on a machine whose Zotero data directory is elsewhere updates cleanly. A
linked file is matched by its whole path, so it is read again on a
machine where it lies elsewhere, and so is an attachment whose file
Zotero renamed.

**How a changed file is seen.**
[`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
and this function record each ingested file's md5 in the store. A stored
file with no record, as in every store built before stores carried one,
is recorded as it is now, and the update says so, because a change made
to it before then cannot be seen. A changed file that can no longer be
read loses its document, as a build would leave it out, and is tried
again by the next update.

**What is kept that a build would leave out.** A PDF that resolves in
Zotero but cannot be read on this machine, because it is not there or
not readable, keeps its stored document, and is named. A partly synced
Zotero `storage/` directory would otherwise strip the store of every
file it has not downloaded.

**What it embeds with.** The store's own recorded embedder, which is the
one
[`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
pinned, so there is no `model` argument. Before anything is ingested
that embedder is probed: an embedding service that does not answer, or a
model that now returns a different width than the store holds, stops the
update.

**What a failure costs.** The update works on a copy beside the store
and replaces the store with it only when it has finished. An update that
stops part way, for whatever reason, leaves the store exactly as it was,
and so does one that would leave it with no documents. When the update
would ingest nothing, drop nothing and record nothing new, the store is
not written at all, so a new PDF that cannot be read does not rewrite
it. Close any connection to the store before updating it.

**After an update.** The store's md5 no longer matches the manifest, so
[`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
would replace it with the copy the manifest describes. Push it with
[`crd_store_push()`](https://newgraphenvironment.github.io/cred/reference/crd_store_push.md),
or open it with `crd_store_connect(verify = FALSE)` until then.

## See also

[`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
to build a store from scratch.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_store_build("data/rag/vca_refs.duckdb", collection = "vca",
                library = "NewGraphEnvironment")
# ... a paper is added to the collection in Zotero, another is trashed ...
crd_store_update("data/rag/vca_refs.duckdb", collection = "vca",
                 library = "NewGraphEnvironment")
} # }
```
