# Citation Audit Workflow

## The problem

When a report is drafted with LLM assistance, a specific failure mode
arises: the citation key is real, the prose sounds authoritative, but
the cited source does not actually support the specific claim made. A
percentage gets transposed, a finding from one paper gets attributed to
another, or a result gets quietly generalised.

`cred` addresses this systematically. For every `@citekey` in a bookdown
report it locates the source document, finds the best-matching passage,
and surfaces it alongside the original claim so a human can make the
call.

## Workflow at a glance

    Rmd files  ──►  audit CSV  ──►  Zotero lookup  ──►  auto-fill quotes
                                                               │
                                                  ┌────────────┼──────────────┐
                                             auto-match   abstract-match   no match
                                             (review)     (review)       (manual check)

| Step | Function                                                                                                       | What it does                                                                    |
|------|----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------|
| 1    | [`crd_aud_write()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_write.md)                     | Scan Rmd files → extract citations with paraphrase context → write CSV scaffold |
| 2    | [`crd_aud_verify_all()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_all.md)           | Look up Zotero attachments → search each source → fill `quote` and `verified`   |
| 2b   | [`crd_aud_verify_abstract()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_abstract.md) | For remaining NA rows, score against Zotero abstract text                       |
| 3    | [`crd_aud_sort()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_sort.md)                       | Sort `auto` rows first so reviewable rows are at the top                        |
| 4    | [`crd_aud_summary()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_summary.md)                 | Print status snapshot and PDF attachment priority list                          |
| 5    | [`crd_aud_review()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_review.md)                   | Launch interactive Shiny app — paraphrase vs quote side by side                 |

------------------------------------------------------------------------

## Walkthrough with toy data

`cred` ships realistic toy source documents and a minimal Zotero SQLite
in `inst/extdata/`:

    inst/extdata/
    ├── zotero.sqlite              # 3 items: smith2020, jones2019, doe2021
    └── storage/
        ├── TOYPDF1/salmon_habitat.pdf      # Smith et al. 2020 — 4 paragraphs
        └── TOYDOC1/beaver_ecology.docx     # Jones 2019 — 4 paragraphs

`doe2021NoFile` has metadata and an abstract in Zotero but no attached
file — the common case for references added by DOI lookup without
downloading the PDF.

``` r
library(cred)

toy_zotero_dir <- system.file("extdata", package = "cred")
```

------------------------------------------------------------------------

### Step 1 — Write the audit CSV

[`crd_aud_write()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_write.md)
scans chapter Rmd files, extracts every `@citekey` with the surrounding
sentence as `paraphrase`, and writes a CSV scaffold.

The toy Rmd files demonstrate three paraphrase patterns:

1.  **Numeric claims** — statistics cited closely from the source (“62%
    lower”, “38% were barriers”). Numbers are the most discriminative
    tokens so these tend to score highest.
2.  **Qualitative paraphrases** — same finding, different words, no
    numbers. These test whether prose overlap alone is enough to find
    the right passage.
3.  **Wrong-paper citation** — a Pacific Salmon Treaty claim cites
    `smith2020SalmonHabitat`, a freshwater habitat quality paper. No
    passage covers harvest allocation → `verified = "no_match"`.

``` r
rmd_dir    <- tempfile("rmd_")
audit_file <- tempfile("audit_", fileext = ".csv")
dir.create(rmd_dir)

# Chapter 1 — habitat quality
# smith2020 has a PDF; doe2021 has metadata + abstract only (no file)
writeLines(c(
  "# Habitat Quality {#habitat}",
  "",
  "Reaches where spawning substrate embeddedness exceeded 25% had egg-to-fry survival rates 62% lower than adjacent low-embeddedness sites [@smith2020SalmonHabitat].",
  "",
  "Fish passage assessments at 1,200 road-stream crossings found that 38% were rated as full or partial barriers to adult chinook migration [@smith2020SalmonHabitat].",
  "",
  "Loss of streamside forest cover eliminates the shade that keeps summer water temperatures within the thermal tolerance of juvenile chinook, degrading rearing conditions in harvested riparian zones [@smith2020SalmonHabitat].",
  "",
  "The Pacific Salmon Treaty allocates harvest between Canada and the United States based on abundance indicators and conservation thresholds negotiated through the Pacific Salmon Commission [@smith2020SalmonHabitat].",
  "",
  "Stream temperature governs the spatial distribution of juvenile salmon and limits rearing area during summer low flows [@doe2021NoFile]."
), file.path(rmd_dir, "0100-habitat.Rmd"))

# Chapter 2 — beaver ecology (jones2019 docx)
writeLines(c(
  "# Beaver Ecology {#beaver}",
  "",
  "Electrofishing surveys recorded juvenile salmonid densities 3.4 times higher in beaver pond habitat than in adjacent free-flowing reaches [@jones2019BeaverEcology].",
  "",
  "Archival records indicate that beaver pond habitat declined by approximately 60% between 1850 and 1950 due to commercial trapping pressure [@jones2019BeaverEcology].",
  "",
  "Beaver dams create ponded habitat with stable thermal regimes that substantially increase overwinter survival of juvenile salmonids by providing shelter from winter spates [@jones2019BeaverEcology].",
  "",
  "Beaver-mediated floodplain connectivity allows juvenile chinook to access off-channel rearing areas during high flows, where growth rates substantially exceed those of fish confined to the mainstem channel [@jones2019BeaverEcology]."
), file.path(rmd_dir, "0200-beaver.Rmd"))

crd_aud_write(rmd_dir = rmd_dir, out_file = audit_file)
#> Scanning: 0100-habitat.Rmd
#> Scanning: 0200-beaver.Rmd
#> Wrote 9 rows to /tmp/RtmplieagU/audit_1d7069b6f1bd.csv
```

Nine rows across two chapters. The `verified` column is blank — no
matching has run yet.

------------------------------------------------------------------------

### Step 2 — Look up Zotero source paths and auto-fill quotes

[`crd_zot_src_lookup()`](https://newgraphenvironment.github.io/cred/reference/crd_zot_src_lookup.md)
queries the Zotero SQLite for attached PDFs and Word documents.

``` r
keys    <- unique(d$citation_key)
sources <- crd_zot_src_lookup(keys, zotero_dir = toy_zotero_dir)
sources[, c("citation_key", "src_type")]
#> # A tibble: 2 × 2
#>   citation_key           src_type
#>   <chr>                  <chr>   
#> 1 jones2019BeaverEcology docx    
#> 2 smith2020SalmonHabitat pdf
```

`doe2021NoFile` has no attachment — the warning is expected.
[`crd_aud_verify_all()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_all.md)
then scores each source against its unverified rows:

``` r
crd_aud_verify_all(
  audit_file = audit_file,
  sources    = sources
)
#> [1/2] Loading source for jones2019BeaverEcology (docx) ...
#> Filling 4 rows for jones2019BeaverEcology ...
#> Done — 4 filled, 0 no_match
#> [2/2] Loading source for smith2020SalmonHabitat (pdf) ...
#> Filling 4 rows for smith2020SalmonHabitat ...
#> Done — 3 filled, 1 no_match
```

**Reading the results:**

- **`auto`** (yellow) — passage found, score ≥ threshold. Read
  paraphrase vs quote to judge.
- **`no_match`** (light green) — source exists but no paragraph scored
  above the threshold. Notice the Pacific Salmon Treaty row:
  `smith2020SalmonHabitat` is a freshwater habitat paper with nothing
  about harvest negotiations. This is the core failure mode `cred`
  surfaces — real key, plausible prose, wrong source.
- **`NA`** (grey) — no source file in Zotero. The `doe2021NoFile` row
  has nowhere to search.

The qualitative paraphrases (rows 3 and 7–8) matched without any numbers
— the shared prose vocabulary (“streamside”, “thermal tolerance”,
“rearing”, “ponded habitat”, “overwinter survival”) was enough to locate
the right paragraphs.

------------------------------------------------------------------------

### Step 2b — Abstract matching for NA rows

For rows that remain `NA`,
[`crd_aud_verify_abstract()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_abstract.md)
queries the Zotero abstract field and runs the same token scoring. An
abstract match confirms the citation is plausibly in the right domain,
without requiring a local file.

``` r
crd_aud_verify_abstract(audit_file, zotero_dir = toy_zotero_dir)
#> Abstract matching: 1 matched, 0 keys with no abstract in Zotero.
```

The `doe2021NoFile` row is now `abstract_match` (blue). The quote column
shows the Zotero abstract — the claim about stream temperature and
salmon distribution is consistent with the abstract’s content.
`page_or_section` is set to `"abstract"` so the source is unambiguous.

**`abstract_match` is not the same as `auto`.** The abstract confirms
the source is in the right domain. It cannot confirm the specific
statistic or quote from the body of the paper. Review these rows with
that in mind: if the claim is general enough to be substantiated by the
abstract alone, set `context`; if it cites a specific number or result,
you still need the PDF.

------------------------------------------------------------------------

### Step 3 — Sort for review

``` r
crd_aud_sort(audit_file, by = "status")
#> Sorted by 'status' and wrote 9 rows to /tmp/RtmplieagU/audit_1d7069b6f1bd.csv
```

------------------------------------------------------------------------

### Step 4 — Summary

``` r
crd_aud_summary(audit_file)
#> === Citation Audit Summary ===
#> File: /tmp/RtmplieagU/audit_1d7069b6f1bd.csv 
#> Total rows: 9 
#> 
#> -- Status breakdown --
#> # A tibble: 3 × 2
#>   status             n
#>   <chr>          <int>
#> 1 auto               7
#> 2 abstract_match     1
#> 3 no_match           1
#> 
#> -- NA sources (no Zotero attachment) ranked by claim count --
#>    Attach PDFs for these to unlock auto-verification.
#>   (none)
#> 
#> -- no_match sources ranked by claim count --
#>    Attachment found but paraphrase did not score above threshold.
#> # A tibble: 1 × 2
#>   citation_key               n
#>   <chr>                  <int>
#> 1 smith2020SalmonHabitat     1
```

------------------------------------------------------------------------

### Step 5 — Interactive review

``` r
crd_aud_review("background/citation_audit.csv")
```

The app opens filtered to `auto` rows. Click a row to see paraphrase and
quote side by side. Set `verified` to `yes`, `no`, or `corrected`, add
notes, click **Update row**, then **Save to CSV**.

------------------------------------------------------------------------

## The verified values

| Value            | Meaning                                                | Next action                                             |
|------------------|--------------------------------------------------------|---------------------------------------------------------|
| `auto`           | Source matched above threshold                         | Read quote vs paraphrase; set yes/no/corrected          |
| `abstract_match` | Zotero abstract matched — no full text                 | Judge if abstract is sufficient; set context or get PDF |
| `no_match`       | Source exists, no paragraph matched                    | Check source manually; may be a wrong citation          |
| `yes`            | Reviewed and confirmed accurate                        | Done                                                    |
| `no`             | Claim not supported by source                          | Fix the claim in the Rmd                                |
| `corrected`      | Claim was wrong; you fixed it                          | Done                                                    |
| `context`        | Source provides background, not a direct factual claim | Done                                                    |
| `NA`             | No source file and no abstract in Zotero               | Attach PDF to unlock                                    |

------------------------------------------------------------------------

## Claim type screening

[`crd_aud_scr_risk()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_scr_risk.md)
populates `claim_type` to prioritise your review effort. Numeric claims
carry the highest hallucination risk.

``` r
d4 <- readr::read_csv(audit_file, show_col_types = FALSE)
d4 <- crd_aud_scr_risk(d4)
table(d4$claim_type)
#> 
#> statistic 
#>         9
```

------------------------------------------------------------------------

## Working with your real report

``` r
library(cred)

# ── One-time setup ──────────────────────────────────────────────────────────
crd_aud_write(rmd_dir = ".", out_file = "background/citation_audit.csv")

# ── After adding new Rmd content ────────────────────────────────────────────
crd_aud_upd("background/citation_audit.csv")

# ── Auto-fill from source files ─────────────────────────────────────────────
crd_aud_verify_all("background/citation_audit.csv")

# ── Abstract fallback for remaining NA rows ──────────────────────────────────
crd_aud_verify_abstract("background/citation_audit.csv")

# ── Check progress ──────────────────────────────────────────────────────────
crd_aud_summary("background/citation_audit.csv")

# ── Review session ──────────────────────────────────────────────────────────
crd_aud_sort("background/citation_audit.csv", by = "status")
crd_aud_review("background/citation_audit.csv")

# ── Restore report order when done ──────────────────────────────────────────
crd_aud_sort("background/citation_audit.csv", by = "report")
```

### How source matching works

Both PDF/docx matching and abstract matching use the same token overlap
algorithm:

1.  Strip R inline expressions, `@citekeys`, and markdown punctuation
    from `paraphrase`
2.  Extract word tokens (≥ 4 characters) and numeric tokens separately —
    numbers are the most discriminative signals
3.  Score each paragraph: proportion of query tokens found in the
    passage
4.  Accept the top-scoring passage if score ≥ `min_score` (default 0.2)

**What 0.2 means:** 1 in 5 query tokens must appear in the passage. With
a 15-token query, 3 tokens need to match. Deliberately permissive — a
false positive costs seconds of review; a false negative means searching
the PDF yourself.

| Situation                                           | Suggested `min_score` |
|-----------------------------------------------------|-----------------------|
| Short or generic paraphrases — many false positives | 0.3 – 0.4             |
| Default — specific factual claims                   | 0.2                   |
| Long dense sources where good matches score low     | 0.1 – 0.15            |

``` r
crd_aud_verify_all("citation_audit.csv", min_score = 0.2)       # default
crd_aud_verify_abstract("citation_audit.csv", min_score = 0.2)  # same threshold
```

Re-run with `overwrite_verified = TRUE` to reprocess machine-assigned
rows without touching human-reviewed ones.
