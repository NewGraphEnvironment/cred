# Search a PDF for the best-matching passage to a paraphrase

Uses the same token-scoring approach as
[`crd_docx_srch_clm()`](crd_docx_srch_clm.md), applied to
paragraph-split page text. Returns top matching passages with page
numbers.

## Usage

``` r
crd_pdf_srch_clm(pdf_txt, paraphrase, n_results = 3L, min_score = 0.2)
```

## Arguments

- pdf_txt:

  `data.frame` as returned by [`crd_pdf_ext_txt()`](crd_pdf_ext_txt.md).

- paraphrase:

  `character(1)` paraphrase text from the audit CSV.

- n_results:

  `integer(1)` number of top matches to return. Default `3L`.

- min_score:

  `numeric(1)` minimum token-match proportion. Default `0.2`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns `page`, `passage`, `score`, ordered by descending score.

## Examples

``` r
if (FALSE) { # \dontrun{
txt <- crd_pdf_ext_txt("background/source.pdf")
crd_pdf_srch_clm(txt, "beaver dams moderate summer stream temperatures")
} # }
```
