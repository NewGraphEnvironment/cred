# Extract citations with paraphrase context from an Rmd file

Reads an Rmd file, strips code chunks, then finds every `@citekey`
occurrence and returns the surrounding sentence as a paraphrase. Each
unique (line, key) combination produces one row; duplicate (key,
paraphrase) pairs within a file are dropped.

## Usage

``` r
crd_cit_ext_rmd(rmd_file, min_key_chars = 8L)
```

## Arguments

- rmd_file:

  `character(1)` path to an `.Rmd` file.

- min_key_chars:

  `integer(1)` minimum citation key length to keep. Shorter matches are
  likely false positives (e.g. stray `@r`). Default `8L`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns `line_num` (`integer`), `citation_key` (`character`),
`paraphrase` (`character`).

## Examples

``` r
if (FALSE) { # \dontrun{
crd_cit_ext_rmd("0300-exploitation.Rmd")
} # }
```
