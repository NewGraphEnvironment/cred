# Fill quote and verified for NA rows using Zotero abstract text

For rows where `verified` is `NA` (no source file attached in Zotero),
Evaluate inline R expressions in audit paraphrases

## Usage

``` r
crd_aud_eval_inline(audit_file, env = parent.frame(), overwrite = FALSE)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV.

- env:

  `environment` in which to evaluate inline R expressions. Default
  [`parent.frame()`](https://rdrr.io/r/base/sys.parent.html) — call from
  a session where project variables are defined and they will be found
  automatically.

- overwrite:

  `logical(1)` if `TRUE`, re-evaluate rows that already have
  `paraphrase_eval`. Default `FALSE`.

## Value

The updated audit data frame, invisibly. Writes to `audit_file`.

## Details

Paraphrases extracted from Rmd source often contain unevaluated inline R
expressions such as `` `r format(optimum_morice, big.mark = ",")` ``.
These make paraphrase vs quote comparison difficult in the review app,
and prevent
[`crd_aud_score()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_score.md)
from detecting numeric mismatches.

`crd_aud_eval_inline()` evaluates each expression in `env` and stores
the result in a `paraphrase_eval` column. On evaluation failure the
expression is left as-is and a warning is issued. `paraphrase` is never
modified — `paraphrase_eval` is display-only.

## Examples

``` r
if (FALSE) { # \dontrun{
# In a session where project variables are loaded:
optimum_morice <- 18175
crd_aud_eval_inline("background/citation_audit.csv")
} # }
```
