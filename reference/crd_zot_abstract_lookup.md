# Retrieve Zotero abstracts for a vector of citation keys

Queries the local Zotero SQLite database for the `abstractNote` field of
each supplied citation key. Returns a tibble with one row per key —
including keys with no abstract (`abstract = NA`).

## Usage

``` r
crd_zot_abstract_lookup(citation_keys, zotero_dir = "~/Zotero")
```

## Arguments

- citation_keys:

  `character` vector of BBT citation keys. `NA` values are silently
  dropped.

- zotero_dir:

  `character(1)` path to the Zotero data directory. Default
  `"~/Zotero"`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns:

- `citation_key` (`character`) — the input key.

- `abstract` (`character`) — abstract text, `NA` if not in database.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_zot_abstract_lookup(c("price_etal2026rebuildinggiis", "doe2021NoFile"))
} # }
```
