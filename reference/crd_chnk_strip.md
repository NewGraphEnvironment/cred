# Strip fenced code chunks from a character vector of lines

Replaces every line inside a ```` ``` ````...```` ``` ```` fenced block
(including the fence lines themselves) with an empty string, so that
citation-key patterns inside code are not matched.

## Usage

``` r
crd_chnk_strip(lines)
```

## Arguments

- lines:

  `character` vector of lines from an Rmd file.

## Value

`character` vector the same length as `lines`, with code-chunk lines
replaced by `""`.

## Examples

``` r
lines <- c("text", "```r", "@key", "```", "more text")
crd_chnk_strip(lines)
#> [1] "text"      ""          ""          ""          "more text"
```
