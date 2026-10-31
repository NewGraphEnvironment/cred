# Retrieve Zotero abstracts for a vector of citation keys

Queries the local Zotero SQLite database for the `abstractNote` field of
each supplied citation key. Returns a tibble with one row per key —
including keys with no abstract (`abstract = NA`).

## Usage

``` r
crd_zot_abstract_lookup(
  citation_keys,
  zotero_dir = "~/Zotero",
  library = getOption("cred.zotero_library")
)
```

## Arguments

- citation_keys:

  `character` vector of BBT citation keys. `NA` values are silently
  dropped.

- zotero_dir:

  `character(1)` path to the Zotero data directory. Default
  `"~/Zotero"`.

- library:

  The Zotero library to resolve keys in: `"user"` for My Library, or a
  group's name or groupID (as in its URL,
  `zotero.org/groups/<groupID>`). Zotero's internal `libraryID` is not
  accepted: it differs between machines. Default
  `getOption("cred.zotero_library")`; `NULL` searches every library.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns:

- `citation_key` (`character`) — the input key.

- `abstract` (`character`) — abstract text, `NA` if not in database.

Attribute `unresolved`: the keys left `NA` because they matched more
than one item or only another library, as distinct from keys with no
abstract.

## Details

Keys resolve as in
[`crd_zot_src_lookup()`](https://newgraphenvironment.github.io/cred/reference/crd_zot_src_lookup.md):
within `library`, never to a trashed item, and a key matching more than
one item is `NA` with a warning saying so.

## Examples

``` r
toy <- system.file("extdata", package = "cred")
crd_zot_abstract_lookup("doe2021NoFile", zotero_dir = toy, library = "user")
#> # A tibble: 1 × 2
#>   citation_key  abstract                                                        
#>   <chr>         <chr>                                                           
#> 1 doe2021NoFile Stream temperature governs the spatial distribution of salmonid…
```
