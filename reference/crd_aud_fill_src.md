# Fill audit CSV quote and location columns from a source document

For each unverified row matching `citation_key`, searches `src` (a
tibble from [`crd_docx_ext_txt()`](crd_docx_ext_txt.md) or
[`crd_pdf_ext_txt()`](crd_pdf_ext_txt.md)) for the best-matching passage
using the `paraphrase` column as the query. Fills:

- `quote` — best-matching passage text

- `page_or_section` — `doc_index` (docx) or `page` (pdf) of the match

- `verified` — `"auto"` when a match meets `min_score`; `"no_match"`
  otherwise

## Usage

``` r
crd_aud_fill_src(
  audit_file,
  src,
  citation_key,
  n_results = 1L,
  min_score = 0.2,
  overwrite_verified = FALSE
)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV produced by
  [`crd_aud_write()`](crd_aud_write.md).

- src:

  `data.frame` as returned by
  [`crd_docx_ext_txt()`](crd_docx_ext_txt.md) or
  [`crd_pdf_ext_txt()`](crd_pdf_ext_txt.md). Source type is inferred
  from column names (`doc_index` = docx, `page` = pdf).

- citation_key:

  `character(1)` citation key to process. Rows whose `citation_key`
  column equals this value are searched.

- n_results:

  `integer(1)` number of top passages to consider per row. Only the
  top-scoring passage is written to `quote`. Default `1L`.

- min_score:

  `numeric(1)` minimum token-match score to accept as a match. Default
  `0.2`.

- overwrite_verified:

  `logical(1)` if `TRUE`, re-fill rows even if `verified` is already
  set. Default `FALSE`.

## Value

Invisibly returns the updated audit
[tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Details

Rows where `verified` is already non-blank are skipped unless
`overwrite_verified = TRUE`. The updated CSV is written back to
`audit_file`.

## Examples

``` r
if (FALSE) { # \dontrun{
doc <- crd_docx_ext_txt("background/price_etal2026.docx")
crd_aud_fill_src("background/citation_audit.csv", doc,
                 citation_key = "price_etal2026rebuildinggiis")
} # }
```
