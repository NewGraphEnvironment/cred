# Auto-score citation rows by hallucination risk

Populates the `claim_type` column where it is blank based on simple
heuristics applied to the `paraphrase` text:

- `"statistic"` — contains a number, percentage, year (4-digit), or
  species name pattern.

- `"finding"` — contains words like "documented", "found", "showed",
  "demonstrated", "confirmed".

- `"context"` — everything else.

## Usage

``` r
crd_aud_scr_risk(audit)
```

## Arguments

- audit:

  `data.frame` with at least `paraphrase` and `claim_type` columns, as
  produced by [`crd_aud_write()`](crd_aud_write.md).

## Value

The input `audit` with `claim_type` filled for blank rows.

## Details

Existing non-blank `claim_type` values are never overwritten.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- readr::read_csv("background/citation_audit.csv")
d <- crd_aud_scr_risk(d)
} # }
```
