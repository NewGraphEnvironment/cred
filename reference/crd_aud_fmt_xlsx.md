# Format an audit CSV as a readable Excel workbook

Writes a `.xlsx` version of the audit CSV with formatting optimised for
manual review: fixed row height (so rows don't expand to full paragraph
height), wide columns for `paraphrase` and `quote`, frozen header row,
auto-filter, and colour-coded `verified` status cells.

## Usage

``` r
crd_aud_fmt_xlsx(audit_file, out_file = NULL)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV produced by
  [`crd_aud_write()`](crd_aud_write.md).

- out_file:

  `character(1)` output `.xlsx` path. Default replaces the `.csv`
  extension with `.xlsx` in the same directory.

## Value

Invisibly returns `out_file`.

## Details

Open the `.xlsx` in Excel or Numbers. Click any `paraphrase` or `quote`
cell to read the full text in the formula bar. Set `verified` to `yes` /
`no` / `corrected` directly in the workbook, then save and re-import
edits to the CSV manually, or continue editing the CSV directly.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_fmt_xlsx("background/citation_audit.csv")
} # }
```
