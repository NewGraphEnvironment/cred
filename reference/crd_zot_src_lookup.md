# Resolve citation keys to source file paths via Zotero SQLite

Queries the local Zotero SQLite database to find PDF or Word document
attachments for a vector of Better BibTeX citation keys. Returns a
tibble suitable for passing to
[`crd_aud_verify_all()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_all.md).

## Usage

``` r
crd_zot_src_lookup(citation_keys, zotero_dir = "~/Zotero")
```

## Arguments

- citation_keys:

  `character` vector of BBT citation keys to resolve. `NA` values are
  silently dropped.

- zotero_dir:

  `character(1)` path to the Zotero data directory. Default
  `"~/Zotero"`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns:

- `citation_key` (`character`) — the input key.

- `src_path` (`character`) — absolute path to the attachment file.

- `src_type` (`character`) — `"docx"` or `"pdf"`.

Only rows where an attachment was found and the file exists on disk are
returned. A warning is issued for keys with no resolvable attachment.

## Details

The database is copied to a temp file before querying to avoid locking
conflicts with a running Zotero process.

## Examples

``` r
if (FALSE) { # \dontrun{
keys <- c("price_etal2026rebuildinggiis", "winther_etal2024assessmentskeena")
crd_zot_src_lookup(keys)
} # }
```
