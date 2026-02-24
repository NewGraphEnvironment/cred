# Write a citation audit CSV scaffold from a directory of Rmd files

Scans all chapter Rmd files (those beginning with four digits), extracts
every inline citation with paraphrase context, and writes a CSV with
blank columns for manual verification.

## Usage

``` r
crd_aud_write(
  rmd_dir = ".",
  out_file = "citation_audit.csv",
  pattern = "^[0-9]{4}-.*\\.Rmd$",
  exclude = "(references|session-info|report-change-log)"
)
```

## Arguments

- rmd_dir:

  `character(1)` directory containing Rmd files. Default `"."`.

- out_file:

  `character(1)` path for the output CSV. Default
  `"citation_audit.csv"`.

- pattern:

  `character(1)` regex to select Rmd files. Default
  `"^[0-9]{4}-.*\\.Rmd$"`.

- exclude:

  `character(1)` regex for files to skip. Default skips references,
  session-info, and change-log chapters.

## Value

Invisibly returns the written
[tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_write(rmd_dir = ".", out_file = "background/citation_audit.csv")
} # }
```
