
<!-- README.md is generated from README.Rmd. Please edit that file -->

# cred — Citation Review and Evidence Documentation

`cred` catches a specific failure mode in LLM-assisted scientific
writing: a real citation key attached to a claim the source does not
actually make. It automates the tedious part — finding the right passage
in a PDF or Word doc — so a human can focus on the judgment call.

## Installation

``` r
pak::pak("NewGraphEnvironment/cred")
```

## The workflow in five steps

    Rmd files  →  audit CSV  →  Zotero lookup  →  auto-fill quotes  →  sort  →  review

**1. Generate the audit CSV** — one row per citation, with the
surrounding sentence as `paraphrase`:

``` r
crd_aud_write(rmd_dir = ".", out_file = "background/citation_audit.csv")
```

**2. Auto-fill quotes from source documents** — queries your local
Zotero database for PDF/docx attachments, searches each one for the
best-matching passage, fills `quote`, `page_or_section`, and
`verified = "auto"`:

``` r
crd_aud_verify_all("background/citation_audit.csv")
```

**3. Check progress** — see status breakdown and which PDFs to attach in
Zotero to unlock more rows:

``` r
crd_aud_summary("background/citation_audit.csv")
```

**4. Sort for your review session** — `auto` rows (quotes ready to
check) first, `NA` rows (no source file) last:

``` r
crd_aud_sort("background/citation_audit.csv", by = "status")
```

**5. Open the CSV in Excel**, read `quote` vs `paraphrase`, set
`verified` to `yes` / `no` / `corrected`.

When done reviewing, restore report order:

``` r
crd_aud_sort("background/citation_audit.csv", by = "report")
```

## What each `verified` value means

| Value       | Meaning                                                    |
|-------------|------------------------------------------------------------|
| `auto`      | Machine-matched — awaiting your review                     |
| `yes`       | Reviewed and confirmed accurate                            |
| `no`        | Claim not supported by source                              |
| `corrected` | Claim was wrong; you fixed it in the Rmd                   |
| `no_match`  | Source exists but paraphrase did not score above threshold |
| `context`   | Citation provides context, not a direct factual claim      |
| `NA`        | No source file in Zotero — attach a PDF to unblock         |

## Keeping the CSV up to date

After adding new content to your Rmd files:

``` r
# Merge new citations into existing CSV without losing manual edits
crd_aud_upd("background/citation_audit.csv")
```

## Zotero integration

`cred` queries the local Zotero SQLite database directly — no Zotero API
key needed, no network call. It uses an immutable read-only URI so the
query never blocks a running Zotero process.

Attachments must be stored locally (not just cloud-linked). If a
citation key has no attachment, the row gets `verified = NA`.
`crd_aud_summary()` lists these ranked by claim count — attach the
highest-impact PDFs first.

## Learn more

``` r
vignette("citation-audit", package = "cred")
```

The vignette walks through the full workflow with toy source files
(PDF + docx) and a minimal Zotero SQLite database that ship with the
package.
