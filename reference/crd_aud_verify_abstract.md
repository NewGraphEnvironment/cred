# queries the local Zotero database for the abstract of each cited item and scores it against the `paraphrase` using token overlap. Rows that score at or above `min_score` receive `verified = "abstract_match"` and the abstract text as their `quote`.

Abstract matching confirms the citation is plausibly in the right domain
but cannot verify a specific quote from the body of the paper. A hit
means the cited source covers the general topic of the claim; a miss
does not mean the citation is wrong — the claim may simply not appear in
the abstract.

## Usage

``` r
crd_aud_verify_abstract(
  audit_file,
  zotero_dir = "~/Zotero",
  min_score = 0.2,
  overwrite_verified = FALSE
)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV.

- zotero_dir:

  `character(1)` path to the Zotero data directory. Default
  `"~/Zotero"`.

- min_score:

  `numeric(1)` token overlap threshold. Default `0.2`.

- overwrite_verified:

  `logical(1)` if `TRUE`, reprocess existing `"abstract_match"` rows.
  Never overwrites human-reviewed rows (`yes`, `no`, `corrected`,
  `context`). Default `FALSE`.

## Value

The updated audit data frame, invisibly. Writes to `audit_file`.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_verify_abstract("background/citation_audit.csv")
} # }
```
