# Launch an interactive review app for the citation audit CSV

Opens a local Shiny app in your browser. Click any row to see the full
`paraphrase` and `quote` side by side, set `verified` from a dropdown,
add `notes`, and save changes back to the CSV. The CSV remains the
source of truth — git history is preserved.

## Usage

``` r
crd_aud_review(audit_file, launch.browser = TRUE)
```

## Arguments

- audit_file:

  `character(1)` path to the audit CSV produced by
  [`crd_aud_write()`](crd_aud_write.md).

- launch.browser:

  `logical(1)` open the app in the system browser. Default `TRUE`.

## Value

Called for side effects. Writes to `audit_file` on Save.

## Workflow

1.  Filter to `"auto"` rows (default on open).

2.  Click a row — full paraphrase and quote appear below.

3.  Read both, set `verified` to `yes` / `no` / `corrected` / `context`.

4.  Add a `notes` entry if the claim needs correction or explanation.

5.  Click **Update row** to apply, then **Save to CSV** when done.

## Examples

``` r
if (FALSE) { # \dontrun{
crd_aud_review("background/citation_audit.csv")
} # }
```
