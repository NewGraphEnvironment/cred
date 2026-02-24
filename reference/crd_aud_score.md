# Score audit rows by review priority

Adds `review_score` (1–6) and `review_flag` columns to the audit CSV.
Lower scores indicate higher review priority (more likely hallucinated
or unsupported). Rows already scored are skipped unless
`overwrite = TRUE`.

## Usage

``` r
crd_aud_score(
  audit_file,
  env = parent.frame(),
  ignore_years = TRUE,
  overwrite = FALSE
)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV.

- env:

  `environment` in which to evaluate inline R expressions, passed to
  [`crd_aud_eval_inline()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_eval_inline.md)
  when needed. Default
  [`parent.frame()`](https://rdrr.io/r/base/sys.parent.html).

- ignore_years:

  `logical(1)` if `TRUE` (default), exclude standalone 4-digit years
  (1900–2099) from numeric claim detection. Years like "since 2020" are
  date references, not statistics.

- overwrite:

  `logical(1)` if `TRUE`, rescore rows that already have `review_score`.
  Default `FALSE`.

## Value

The updated audit data frame, invisibly. Writes to `audit_file`.

## Details

If `paraphrase_eval` is not yet populated and paraphrases contain inline
R expressions,
[`crd_aud_eval_inline()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_eval_inline.md)
is called automatically with `env`.

## Score meanings

- 1:

  `no_match`, or `auto` with numeric claim absent from quote

- 2:

  `NA` (no source), abstract with numeric claim, auto with no quote, or
  very weak prose overlap

- 3:

  `abstract_match` qualitative, weak prose overlap, or no tokens

- 4:

  `auto` numeric partial match or moderate prose overlap

- 5:

  `auto` strong numeric + prose match

- 6:

  Human-reviewed (`yes`, `no`, `corrected`, `context`)

## Examples

``` r
if (FALSE) { # \dontrun{
# After verify_all and verify_abstract:
crd_aud_score("background/citation_audit.csv")

# With project variables for inline R evaluation:
optimum_morice <- 18175
crd_aud_score("background/citation_audit.csv")
} # }
```
