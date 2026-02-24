# Update an existing audit CSV preserving manual columns

Re-extracts citations from Rmd files and merges with an existing audit
CSV, preserving any manually filled `quote`, `claim_type`,
`page_or_section`, `verified`, and `notes` values. New rows are appended
with blank manual columns; rows no longer present in the Rmd are
retained but flagged.

## Usage

``` r
crd_aud_upd(
  out_file = "citation_audit.csv",
  rmd_dir = ".",
  pattern = "^[0-9]{4}-.*\\.Rmd$",
  exclude = "(references|session-info|report-change-log)",
  min_similarity = 0.4
)
```

## Arguments

- out_file:

  `character(1)` path to the existing audit CSV.

- rmd_dir:

  `character(1)` directory containing Rmd files. Default `"."`.

- pattern:

  `character(1)` regex to select Rmd files. Default
  `"^[0-9]{4}-.*\\.Rmd$"`.

- exclude:

  `character(1)` regex for files to skip. Default skips references,
  session-info, and change-log chapters.

- min_similarity:

  `numeric(1)` minimum token-overlap score (0–1) for fuzzy matching when
  a paraphrase changes between updates. Rows that fail the exact join
  are matched to existing rows with the same `(section, citation_key)`
  by token similarity. Set to `1` to disable fuzzy matching. Default
  `0.4`.

## Value

Invisibly returns the updated
[tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_upd("background/citation_audit.csv")
} # }
```
