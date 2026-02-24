# Extract the sentence(s) containing a specific citation key

Splits a line of Rmd prose into sentence fragments and returns the
fragment(s) that contain `@key`. Falls back to the full trimmed line
when the extracted fragment is too short or starts mid-sentence
(lowercase first character).

## Usage

``` r
crd_sent_ext_key(line, key, min_chars = 40L)
```

## Arguments

- line:

  `character(1)` a single line of Rmd prose.

- key:

  `character(1)` BBT citation key (without leading `@`).

- min_chars:

  `integer(1)` minimum fragment length before falling back to the full
  line. Default `40L`.

## Value

`character(1)` trimmed sentence fragment, or full line when the fragment
is uninformative.

## Details

**Split rules** (applied outside `[...]` citation bracket groups):

- `. [Capital]` — period followed by a capital letter, excluding common
  abbreviations (`et al.`, `Dr.`, `Mr.`, `St.`).

- `. @key` — period followed by a narrative citation, so that sentences
  of the form `@author documented...` are correctly isolated.

The lookahead `(?![^[]*\])` prevents splitting inside `[@k1; @k2]` by
checking that a `]` is not reachable without first crossing a `[`.

## Examples

``` r
line <- paste(
  "@smith2020 documented X; @jones2021 confirmed Y.",
  "@brown2022 extended the finding."
)
crd_sent_ext_key(line, "jones2021")
#> [1] "@smith2020 documented X; @jones2021 confirmed Y."
crd_sent_ext_key(line, "brown2022")
#> [1] "@smith2020 documented X; @jones2021 confirmed Y. @brown2022 extended the finding."
```
