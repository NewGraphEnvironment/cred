# Citation Audit Workflow

## The problem

When a report is drafted with LLM assistance, a specific failure mode
arises: the citation key is real, the prose sounds authoritative, but
the cited source does not actually support the specific claim made. A
percentage gets transposed, a finding from one paper gets attributed to
another, or an experimental result gets quietly generalised.

`cred` addresses this systematically. For every `@citekey` in a bookdown
report it locates the source document, finds the best-matching passage,
and surfaces it alongside the original claim so a human can make the
call.

## Workflow at a glance

    Rmd files  ──►  audit CSV  ──►  Zotero lookup  ──►  auto-fill quotes
                                                               │
                                                  ┌────────────┴─────────────┐
                                             auto-match                  no match
                                             (review)                 (manual check)
                                                  │
                                             Review app  ──►  yes / no / corrected

| Step | Function                                                     | What it does                                                                                |
|------|--------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| 1    | [`crd_aud_write()`](../reference/crd_aud_write.md)           | Scan Rmd files → extract citations with paraphrase context → write CSV scaffold             |
| 2    | [`crd_aud_verify_all()`](../reference/crd_aud_verify_all.md) | Look up Zotero attachments → search each source → fill `quote` and `verified`               |
| 3    | [`crd_aud_sort()`](../reference/crd_aud_sort.md)             | Sort `auto` rows first so reviewable rows are at the top                                    |
| 4    | [`crd_aud_summary()`](../reference/crd_aud_summary.md)       | Print status snapshot and PDF attachment priority list                                      |
| 5    | [`crd_aud_review()`](../reference/crd_aud_review.md)         | Launch interactive Shiny app — paraphrase vs quote side by side, dropdown to set `verified` |

------------------------------------------------------------------------

## Walkthrough with toy data

`cred` ships realistic toy source documents and a minimal Zotero SQLite
in `inst/extdata/`:

    inst/extdata/
    ├── zotero.sqlite              # 3 items: smith2020, jones2019, doe2021 (no attachment)
    └── storage/
        ├── TOYPDF1/salmon_habitat.pdf      # Smith et al. 2020 — 4 paragraphs
        └── TOYDOC1/beaver_ecology.docx     # Jones 2019 — 4 paragraphs

``` r
library(cred)

toy_zotero_dir <- system.file("extdata", package = "cred")
```

------------------------------------------------------------------------

### Step 1 — Write the audit CSV

[`crd_aud_write()`](../reference/crd_aud_write.md) scans all chapter Rmd
files (names beginning with four digits), extracts every `@citekey` with
the surrounding sentence as `paraphrase`, and writes a CSV scaffold with
blank `verified`, `quote`, and `notes` columns.

The toy Rmd files below reflect common patterns in scientific reports:
specific statistics, methodological findings, and one claim the source
does not support (the floodplain growth claim in the habitat chapter is
not covered by `smith2020SalmonHabitat` — its paragraph 4 covers large
woody debris, not floodplain rearing). This is deliberate: we want to
see the `no_match` outcome.

``` r
rmd_dir    <- tempfile("rmd_")
audit_file <- tempfile("audit_", fileext = ".csv")
dir.create(rmd_dir)

# Chapter 1 — habitat quality: 4 claims, 3 citation keys
# smith2020 has a PDF attachment; doe2021 has metadata only (no PDF)
writeLines(c(
  "# Habitat Quality {#habitat}",
  "",
  "Spawning substrate embeddedness exceeding 25% reduces egg-to-fry",
  "survival by more than half compared to low-embeddedness sites",
  "[@smith2020SalmonHabitat].",
  "",
  "Removal of riparian conifers within 30 m of the channel raises",
  "maximum summer stream temperatures by 3 to 7 degrees Celsius",
  "[@smith2020SalmonHabitat].",
  "",
  "Of 1,200 road crossings assessed in the watershed, 38% were rated",
  "as full or partial barriers to adult chinook migration",
  "[@smith2020SalmonHabitat].",
  "",
  "Floodplain rearing habitat supports juvenile growth rates substantially",
  "higher than mainstem conditions [@smith2020SalmonHabitat].",
  "",
  "Stream temperature governs the spatial distribution of juvenile salmon",
  "and limits rearing area during summer low flows [@doe2021NoFile]."
), file.path(rmd_dir, "0100-habitat.Rmd"))

# Chapter 2 — beaver ecology: 4 claims, all jones2019 (docx attachment)
writeLines(c(
  "# Beaver Ecology {#beaver}",
  "",
  "Beaver ponds support juvenile salmonid densities more than three times",
  "higher than adjacent free-flowing reaches during winter",
  "[@jones2019BeaverEcology].",
  "",
  "Beaver reintroduction reduced peak flows by approximately 30% and",
  "extended summer baseflow duration by five weeks in experimental reaches",
  "[@jones2019BeaverEcology].",
  "",
  "Commercial trapping reduced beaver pond habitat by approximately 60%",
  "between 1850 and 1950, with lasting consequences for overwinter",
  "juvenile survival [@jones2019BeaverEcology].",
  "",
  "Juvenile chinook using floodplain side channels during high-flow events",
  "grew 40% faster than fish remaining in the mainstem",
  "[@jones2019BeaverEcology]."
), file.path(rmd_dir, "0200-beaver.Rmd"))

crd_aud_write(rmd_dir = rmd_dir, out_file = audit_file)
#> Scanning: 0100-habitat.Rmd
#> Scanning: 0200-beaver.Rmd
#> Wrote 5 rows to /tmp/RtmpjKexm6/audit_1cf35eec27d5.csv
```

Nine rows across two chapters. The `verified` column is blank — no
matching has happened yet.

------------------------------------------------------------------------

### Step 2 — Look up Zotero source paths

[`crd_zot_src_lookup()`](../reference/crd_zot_src_lookup.md) queries the
Zotero SQLite database (read-only, immutable URI — safe to run while
Zotero is open) and returns file paths for any attached PDFs or Word
documents.

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

`doe2021NoFile` has no attachment — it was added to Zotero by DOI lookup
(metadata only, no PDF downloaded). The warning is expected; the row
will remain `NA` in the audit.
[`crd_aud_summary()`](../reference/crd_aud_summary.md) will flag it as a
priority to attach.

------------------------------------------------------------------------

### Step 3 — Auto-fill quotes

[`crd_aud_verify_all()`](../reference/crd_aud_verify_all.md) loads each
source document once, then for every unverified row matching that key it
scores paragraphs/pages against the `paraphrase` using token overlap. It
fills:

- **`quote`** — the best-matching passage from the source
- **`page_or_section`** — paragraph index (docx) or page number (pdf)
- **`verified`** — `"auto"` if score ≥ `min_score`; `"no_match"` if
  below threshold

``` r
crd_aud_verify_all(
  audit_file = audit_file,
  sources    = sources
)
#> [1/2] Loading source for jones2019BeaverEcology (docx) ...
#> Filling 2 rows for jones2019BeaverEcology ...
#> Done — 1 filled, 1 no_match
#> [2/2] Loading source for smith2020SalmonHabitat (pdf) ...
#> Filling 2 rows for smith2020SalmonHabitat ...
#> Done — 1 filled, 1 no_match
```

**Reading the outcomes:**

- **`auto`** (yellow) — a passage was found in the source scoring above
  the threshold. The `quote` column shows what the source actually says.
  Your job: read both, decide if they match.
- **`no_match`** (light green) — the source file exists, but no
  paragraph scored above the threshold. This happens when the report’s
  phrasing is too different from the source text. It needs manual
  verification.
- **`NA`** (grey) — no source file is attached in Zotero. Nothing to
  match against.

Notice row 4: the floodplain growth claim
(`"Floodplain rearing habitat supports juvenile growth rates..."`) cites
`smith2020SalmonHabitat`, but that PDF covers large woody debris in
paragraph 4 — not floodplain rearing. The source simply doesn’t contain
the claim. This is exactly the kind of mismatch `cred` is designed to
surface.

------------------------------------------------------------------------

### Step 4 — Sort for review

[`crd_aud_sort()`](../reference/crd_aud_sort.md) rearranges rows so the
most actionable are at the top. The `"status"` order is:

`auto` → `no_match` → `corrected` → `no` → `context` → `yes` → `NA`

``` r
crd_aud_sort(audit_file, by = "status")
#> Sorted by 'status' and wrote 5 rows to /tmp/RtmpjKexm6/audit_1cf35eec27d5.csv
```

`sort_index` is assigned at write time and never changes, so
`crd_aud_sort(by = "report")` always restores the original chapter
order.

------------------------------------------------------------------------

### Step 5 — Summary

[`crd_aud_summary()`](../reference/crd_aud_summary.md) prints a live
status snapshot and — crucially — tells you which PDFs to attach in
Zotero to unlock the most NA rows.

``` r
crd_aud_summary(audit_file)
#> === Citation Audit Summary ===
#> File: /tmp/RtmpjKexm6/audit_1cf35eec27d5.csv 
#> Total rows: 5 
#> 
#> -- Status breakdown --
#> # A tibble: 3 × 2
#>   status       n
#>   <chr>    <int>
#> 1 auto         2
#> 2 no_match     2
#> 3 (NA)         1
#> 
#> -- NA sources (no Zotero attachment) ranked by claim count --
#>    Attach PDFs for these to unlock auto-verification.
#> # A tibble: 1 × 2
#>   citation_key      n
#>   <chr>         <int>
#> 1 doe2021NoFile     1
#> 
#> -- no_match sources ranked by claim count --
#>    Attachment found but paraphrase did not score above threshold.
#> # A tibble: 2 × 2
#>   citation_key               n
#>   <chr>                  <int>
#> 1 jones2019BeaverEcology     1
#> 2 smith2020SalmonHabitat     1
```

In a real report with 200+ citations, the NA sources table is your
action list: attach the top-ranked PDF, re-run
[`crd_aud_verify_all()`](../reference/crd_aud_verify_all.md), and unlock
several rows at once.

------------------------------------------------------------------------

### Step 6 — Interactive review

[`crd_aud_review()`](../reference/crd_aud_review.md) launches a local
Shiny app in your browser. It is the recommended interface for working
through `auto` rows.

``` r
crd_aud_review("background/citation_audit.csv")
```

The app opens filtered to `auto` rows. For each row:

1.  Click the row — full `paraphrase` and `quote` appear side by side
    below the table
2.  Read both — does the source support the claim?
3.  Set `verified` in the dropdown: `yes`, `no`, or `corrected`
4.  Add a `notes` entry if the claim needs correction or context
5.  Click **Update row**, move to the next
6.  Click **Save to CSV** when done — the plain-text CSV is updated, git
    history preserved

The app also shows a live progress counter: *N reviewed · N auto · N
total*.

------------------------------------------------------------------------

## The three outcomes explained

| Outcome    | What it means                                     | What to do                                                                                  |
|------------|---------------------------------------------------|---------------------------------------------------------------------------------------------|
| `auto`     | Source file found; passage scored above threshold | Open review app, read quote vs paraphrase, set yes/no/corrected                             |
| `no_match` | Source file found but no paragraph matched        | Check source manually; if claim is valid, set `context` or `yes`; if wrong, set `corrected` |
| `NA`       | No source file attached in Zotero                 | Attach PDF in Zotero → re-run [`crd_aud_verify_all()`](../reference/crd_aud_verify_all.md)  |

**`no_match` is not an error.** It occurs when:

- The report’s phrasing diverges substantially from the source (a sign
  the claim may have been paraphrased beyond what the source says —
  worth checking)
- The source provides context rather than a direct quotable finding
- Multiple sources are cited together (`[@a; @b]`) and the paraphrase
  blends both

------------------------------------------------------------------------

## Claim type screening

[`crd_aud_scr_risk()`](../reference/crd_aud_scr_risk.md) populates the
`claim_type` column to prioritise your review effort. Statistics
(numbers, percentages, years) carry the highest hallucination risk;
context citations the lowest.

``` r
d3 <- readr::read_csv(audit_file, show_col_types = FALSE)
d3 <- crd_aud_scr_risk(d3)
table(d3$claim_type)
#> 
#> statistic 
#>         5
```

For domain-specific terms, pass an extra pattern:

``` r
# Flag species names as statistics for a salmonid report
d3 <- crd_aud_scr_risk(d3, statistic_extra = "chinook|sockeye|coho|pink|chum")
```

Review `statistic` rows first.

------------------------------------------------------------------------

## Working with your real report

``` r
library(cred)

# ── One-time setup ──────────────────────────────────────────────────────────
# Generate the audit CSV from project root (chapter Rmd files only)
crd_aud_write(rmd_dir = ".", out_file = "background/citation_audit.csv")

# ── After adding new Rmd content ────────────────────────────────────────────
# Merge new citations without losing manual edits
crd_aud_upd("background/citation_audit.csv")

# ── Auto-fill from Zotero ───────────────────────────────────────────────────
# Zotero must be open for BBT citation keys; not needed for the SQLite lookup
crd_aud_verify_all("background/citation_audit.csv")

# ── Check progress ──────────────────────────────────────────────────────────
crd_aud_summary("background/citation_audit.csv")

# ── Review session ──────────────────────────────────────────────────────────
# Sort auto rows to the top, open the review app
crd_aud_sort("background/citation_audit.csv", by = "status")
crd_aud_review("background/citation_audit.csv")

# ── Restore report order when done ─────────────────────────────────────────
crd_aud_sort("background/citation_audit.csv", by = "report")
```

### Attaching missing PDFs

[`crd_aud_summary()`](../reference/crd_aud_summary.md) lists NA sources
ranked by claim count — one attachment can unlock many rows. In Zotero:

1.  Find the item (use the `citation_key` to search)
2.  Right-click → **Add Attachment → Attach File**
3.  Re-run [`crd_aud_verify_all()`](../reference/crd_aud_verify_all.md)
    — newly attached files are picked up automatically

### How source matching works

The token scoring approach is simple and fast:

1.  Strip `@citekey` markers and markdown punctuation from the
    `paraphrase`
2.  Split into tokens (≥ 4 characters)
3.  Score each paragraph/page: proportion of query tokens found in the
    passage
4.  Accept the top-scoring passage if score ≥ `min_score` (default 0.2)

Lower `min_score` to cast a wider net at the cost of weaker matches;
raise it to require stricter agreement. The default 0.2 (20% token
overlap) works well for specific factual claims with numbers and key
terms.
