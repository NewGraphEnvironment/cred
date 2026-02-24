# Sort an audit CSV for review and write it back

Rearranges the rows of an audit CSV to support different review
workflows, then writes the result back to the same file. The
`sort_index` column (set at write time) always allows restoration to
report order.

## Usage

``` r
crd_aud_sort(audit_file, by = c("report", "status", "key"))
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV.

- by:

  `character(1)` sort strategy. One of:

  - `"report"` — restore to original report order (`sort_index`).

  - `"status"` — group by verification status, worst-first, then
    `sort_index` within each group.

  - `"key"` — alphabetical by `citation_key`, then `sort_index`.

## Value

Invisibly returns the sorted
[tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Verified status order for `by = "status"`

Rows are grouped: `NA` (unseen) → `"no_match"` → `"auto"` →
`"corrected"` → `"no"` → `"context"` → `"yes"`. Within each group, rows
are ordered by `sort_index`. This puts the most-needing-review rows
first.

## Examples

``` r
if (FALSE) { # \dontrun{
# Group unverified rows first for review
crd_aud_sort("background/citation_audit.csv", by = "status")

# Restore report order when done
crd_aud_sort("background/citation_audit.csv", by = "report")
} # }
```
