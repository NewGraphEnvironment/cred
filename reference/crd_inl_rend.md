# Replace scalar inline R expressions in a string

Searches for `` `r <expr>` `` patterns where `<expr>` is a simple
`format(var, ...)` or bare variable name, looks up `var` from scalar
assignments (`var <- value`) in the same file, and substitutes the
formatted value. Non-scalar or unresolvable expressions are left
unchanged.

## Usage

``` r
crd_inl_rend(text, rmd_file)
```

## Arguments

- text:

  `character(1)` string potentially containing inline R.

- rmd_file:

  `character(1)` path to the Rmd file to scan for scalar assignments.

## Value

`character(1)` with resolvable inline expressions substituted.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_inl_rend(
  "optimum was `r format(optimum_lower, big.mark = \",\")`",
  "0100-intro.Rmd"
)
} # }
```
