# Resolve citation keys to source file paths via Zotero SQLite

Queries the local Zotero SQLite database to find a PDF or Word document
attachment for each of a vector of Better BibTeX citation keys. Returns
a tibble suitable for passing to
[`crd_aud_verify_all()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_all.md).

## Usage

``` r
crd_zot_src_lookup(
  citation_keys,
  zotero_dir = "~/Zotero",
  library = getOption("cred.zotero_library")
)
```

## Arguments

- citation_keys:

  `character` vector of BBT citation keys to resolve. `NA` values are
  silently dropped.

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

- `src_path` (`character`) — absolute path to the attachment file.

- `src_type` (`character`) — `"docx"` or `"pdf"`.

Only rows where an attachment was found and the file exists on disk are
returned. A warning is issued for keys with no resolvable attachment.

## Details

A citation key is unique within a Zotero library, not across libraries,
so the same key can name different works in My Library and a group
library. Name the library with `library`, or once per session with
`options(cred.zotero_library = )`. With neither, every library is
searched, and a key found in more than one is left unresolved with a
warning rather than taken from whichever happens to come first. A key
shared by two live items within one library is treated the same way.

Trashed items and trashed attachments are never used.

When an item has several attachments, the one taken is the one Zotero
itself opens: a PDF before a Word document, then by URL (the attachment
whose URL is the item's own, then one with any URL, then one with none),
then the oldest. If that file is not on disk the next one is taken. A
message names the file taken and the ones left out.

The database is opened read-only and `immutable`, so a running Zotero is
never locked.

## Examples

``` r
# The toy library shipped with cred holds its items in My Library
toy <- system.file("extdata", package = "cred")
crd_zot_src_lookup(
  c("smith2020SalmonHabitat", "jones2019BeaverEcology"),
  zotero_dir = toy, library = "user"
)
#> # A tibble: 2 × 3
#>   citation_key           src_path                                       src_type
#>   <chr>                  <chr>                                          <chr>   
#> 1 jones2019BeaverEcology /home/runner/work/_temp/Library/cred/extdata/… docx    
#> 2 smith2020SalmonHabitat /home/runner/work/_temp/Library/cred/extdata/… pdf     
```
