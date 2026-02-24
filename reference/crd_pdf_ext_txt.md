# Extract text from a PDF as a tidy tibble

Wraps
[`pdftools::pdf_text()`](https://docs.ropensci.org/pdftools//reference/pdftools.html)
and returns one row per page.

## Usage

``` r
crd_pdf_ext_txt(pdf_path)
```

## Arguments

- pdf_path:

  `character(1)` path to a PDF file.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns `page` (`integer`) and `text` (`character`).

## Examples

``` r
if (FALSE) { # \dontrun{
txt <- crd_pdf_ext_txt("background/source.pdf")
} # }
```
