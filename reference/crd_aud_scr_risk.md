# Auto-score citation rows by hallucination risk

Populates the `claim_type` column where it is blank, based on simple
heuristics applied to the `paraphrase` text:

## Usage

``` r
crd_aud_scr_risk(audit, statistic_extra = NULL)
```

## Arguments

- audit:

  `data.frame` with at least `paraphrase` and `claim_type` columns, as
  produced by
  [`crd_aud_write()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_write.md).

- statistic_extra:

  `character(1)` optional additional regex pattern ORed into the
  statistic detector. Use this to flag domain-specific terms as
  statistics — e.g. `"chinook|sockeye|coho"` for salmonid reports, or
  `"glucose|insulin"` for medical papers. Default `NULL` (no extras).

## Value

The input `audit` with `claim_type` filled for blank rows.

## Details

- `"statistic"` — contains a number, percentage, or 4-digit year
  (highest hallucination risk — verify these first).

- `"finding"` — contains words like "documented", "found", "showed",
  "demonstrated", "confirmed".

- `"context"` — everything else (lowest risk).

Existing non-blank `claim_type` values are never overwritten.

## Examples

``` r
d <- data.frame(
  paraphrase = c("Embeddedness exceeded 25% at 38% of sites.",
                 "The study demonstrated reduced survival.",
                 "See also the watershed context."),
  claim_type = NA_character_
)
crd_aud_scr_risk(d)
#>                                   paraphrase claim_type
#> 1 Embeddedness exceeded 25% at 38% of sites.  statistic
#> 2   The study demonstrated reduced survival.    finding
#> 3            See also the watershed context.    context

# Flag species names as statistics for a salmonid report
crd_aud_scr_risk(d, statistic_extra = "chinook|sockeye|coho|pink|chum")
#>                                   paraphrase claim_type
#> 1 Embeddedness exceeded 25% at 38% of sites.  statistic
#> 2   The study demonstrated reduced survival.    finding
#> 3            See also the watershed context.    context
```
