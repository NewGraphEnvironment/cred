# Search a Word document for the best-matching passage to a paraphrase

Converts a paraphrase to search tokens (stripping citation keys and
markdown), then scores each paragraph in the document by the proportion
of tokens found. Returns the top `n_results` matching paragraphs with
their document index and style.

## Usage

``` r
crd_docx_srch_clm(docx_txt, paraphrase, n_results = 3L, min_score = 0.2)
```

## Arguments

- docx_txt:

  `data.frame` as returned by
  [`crd_docx_ext_txt()`](https://newgraphenvironment.github.io/cred/reference/crd_docx_ext_txt.md).

- paraphrase:

  `character(1)` paraphrase text from the audit CSV.

- n_results:

  `integer(1)` number of top matches to return. Default `3L`.

- min_score:

  `numeric(1)` minimum token-match proportion to include. Default `0.2`.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns `doc_index`, `style_name`, `text`, `score`, ordered by
descending score. Returns zero rows if no match exceeds `min_score`.

## Examples

``` r
if (FALSE) { # \dontrun{
doc <- crd_docx_ext_txt("background/price_etal2026.docx")
crd_docx_srch_clm(doc, "beaver dams moderate summer stream temperatures")
} # }
```
