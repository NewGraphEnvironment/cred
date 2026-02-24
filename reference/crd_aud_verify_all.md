# Verify all citation keys in an audit CSV against their source documents

Convenience wrapper around
[`crd_zot_src_lookup()`](crd_zot_src_lookup.md) and
[`crd_aud_fill_src()`](crd_aud_fill_src.md). For each citation key in
the audit CSV that has a resolvable Zotero attachment, loads the source
document once and fills `quote`, `page_or_section`, and `verified`
columns for all matching rows.

## Usage

``` r
crd_aud_verify_all(
  audit_file,
  sources = NULL,
  zotero_dir = "~/Zotero",
  min_score = 0.2,
  overwrite_verified = FALSE
)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV.

- sources:

  `data.frame` as returned by
  [`crd_zot_src_lookup()`](crd_zot_src_lookup.md), with columns
  `citation_key`, `src_path`, `src_type`. If `NULL` (default), all
  unique keys in `audit_file` are looked up automatically via
  [`crd_zot_src_lookup()`](crd_zot_src_lookup.md).

- zotero_dir:

  `character(1)` Zotero data directory, passed to
  [`crd_zot_src_lookup()`](crd_zot_src_lookup.md) when `sources` is
  `NULL`. Default `"~/Zotero"`.

- min_score:

  `numeric(1)` passed to [`crd_aud_fill_src()`](crd_aud_fill_src.md).
  Default `0.2`.

- overwrite_verified:

  `logical(1)` passed to [`crd_aud_fill_src()`](crd_aud_fill_src.md).
  Default `FALSE`.

## Value

Invisibly returns the final audit
[tibble](https://tibble.tidyverse.org/reference/tibble.html).

## Details

Keys with no Zotero attachment are skipped with a warning. Keys already
fully verified are skipped unless `overwrite_verified = TRUE`.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_verify_all("background/citation_audit.csv")
} # }
```
