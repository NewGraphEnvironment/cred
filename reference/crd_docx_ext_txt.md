# Extract text from a Word document as a tidy tibble

Reads a `.docx` file using
[`officer::read_docx()`](https://davidgohel.github.io/officer/reference/read_docx.html)
and returns the full document content as a tidy
[tibble](https://tibble.tidyverse.org/reference/tibble.html). Each row
is one paragraph or table cell, with the heading style preserved so
callers can filter by section.

## Usage

``` r
crd_docx_ext_txt(docx_path)
```

## Arguments

- docx_path:

  `character(1)` path to a `.docx` file.

## Value

A [tibble](https://tibble.tidyverse.org/reference/tibble.html) with
columns:

- `doc_index` (`integer`) — paragraph index in the document.

- `content_type` (`character`) — `"paragraph"`, `"table cell"`, etc.

- `style_name` (`character`) — Word style (e.g. `"Heading 1"`,
  `"Normal"`).

- `text` (`character`) — paragraph text.

- `level` (`integer`) — heading level (`NA` for body text).

## Examples

``` r
if (FALSE) { # \dontrun{
doc <- crd_docx_ext_txt("background/price_etal2026.docx")
dplyr::filter(doc, style_name == "Heading 1")
} # }
```
