# Summarise an audit CSV by verification status

Prints a three-part snapshot to the console:

1.  Overall row counts by `verified` status.

2.  Sources with `NA` status (no Zotero attachment) ranked by claim
    count — your PDF attachment priority list.

3.  Sources with `"no_match"` status (attachment exists but paraphrase
    did not match) ranked by claim count.

## Usage

``` r
crd_aud_summary(audit_file)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV produced by
  [`crd_aud_write()`](crd_aud_write.md).

## Value

Invisibly returns a named list with tibbles `status`, `na_sources`, and
`no_match_sources`.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_summary("background/citation_audit.csv")
} # }
```
