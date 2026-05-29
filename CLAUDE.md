# cred — Citation Review and Evidence Documentation

R package for detecting hallucinated or misattributed citations in LLM-assisted bookdown reports.
The core failure mode: citation key is real, the source exists, but the source does not support
the specific claim made.

## Repository Context

**Repository:** NewGraphEnvironment/cred
**Primary Language:** R (package)
**GitHub:** https://github.com/NewGraphEnvironment/cred
**Site:** https://newgraphenvironment.github.io/cred/

## Architecture

```
R/
├── audit.R      — CSV lifecycle: crd_aud_write, crd_aud_verify_all, crd_aud_verify_abstract,
│                  crd_aud_upd (fuzzy join), crd_aud_eval_inline (inline R → paraphrase_eval),
│                  crd_aud_score, crd_aud_summary, crd_aud_scr_risk, crd_aud_fmt_xlsx
├── zotero.R     — SQLite helpers: crd_zot_src_lookup, crd_zot_abstract_lookup
├── review.R     — Shiny review app: crd_aud_review (launch_browser param, not launch.browser)
│                  text filters for paraphrase/quote search, collapsible candidate passages panel
├── rmd.R        — crd_aud_write internals: parse @citekey + surrounding sentence
├── sentence.R   — sentence extraction helpers
├── pdf.R        — PDF text extraction + paragraph splitting (pdftools)
└── docx.R       — Word doc extraction (officer) + .paraphrase_tokens(), .token_score()
                   (internal matching functions reused by abstract matching)

tests/testthat/
├── test-audit.R     — crd_aud_fill_src, crd_aud_upd (exact + fuzzy join)
├── test-docx.R
├── test-matching.R
├── test-rmd.R
├── test-score.R     — crd_aud_score, .score_row, scoring internals
└── test-sentence.R

inst/extdata/              — toy data for vignette
├── zotero.sqlite          — 3 items: smith2020SalmonHabitat, jones2019BeaverEcology, doe2021NoFile
└── storage/
    ├── TOYPDF1/salmon_habitat.pdf
    └── TOYDOC1/beaver_ecology.docx

vignettes/citation-audit.Rmd   — full walkthrough with toy data
data-raw/make_toy_zotero.R      — regenerates inst/extdata/zotero.sqlite
```

## The `verified` Status Taxonomy

This is the core data model. Every function respects it.

| Value | Meaning | Set by |
|-------|---------|--------|
| `auto` | Passage found in source file, score ≥ threshold | `crd_aud_verify_all()` |
| `abstract_match` | Zotero abstract matched — no full text available | `crd_aud_verify_abstract()` |
| `no_match` | Source exists, no paragraph scored above threshold | `crd_aud_verify_all()` |
| `yes` | Human: reviewed and confirmed accurate | human |
| `no` | Human: claim not supported by source | human |
| `corrected` | Human: claim was wrong, fixed in Rmd | human |
| `context` | Human: citation provides background, not a direct claim | human |
| `NA` | No source file and no abstract in Zotero | — |

**Protected statuses** — never overwritten by any automated function:
`yes`, `no`, `corrected`, `context`

## Matching Algorithm

`docx.R` contains the internal matching functions used by all verification paths:

- `.paraphrase_tokens(text)` — strips R expressions, `@citekeys`, markdown punctuation; extracts word tokens (≥4 chars) + numeric tokens separately
- `.token_score(query_tokens, paragraph)` — proportion of query tokens found in paragraph
- Default `min_score = 0.2` (1 in 5 tokens must match)
- `crd_aud_fill_src()` stores top-3 candidates as JSON in `candidate_quotes` column
- `overwrite_verified = FALSE` by default — never reprocesses human-reviewed rows
- These same functions are reused by `crd_aud_upd()` for fuzzy join fallback (`min_similarity = 0.4` threshold on paraphrase-to-paraphrase matching)

## Zotero Integration

- Queries local Zotero SQLite directly — no API key, no network
- Uses `file:path?mode=ro&immutable=1` URI to avoid locking conflicts with running Zotero
- BBT citation keys stored as `citationKey` field in `zotero.sqlite` (not old `better-bibtex.sqlite`)
- `crd_zot_src_lookup()` — resolves citation keys to attached PDF/docx paths
- `crd_zot_abstract_lookup()` — retrieves `abstractNote` field for keys without attachments

## Build and Test

```r
devtools::test()          # run tests
devtools::document()      # rebuild man/ from roxygen
devtools::check()         # full R CMD check
lintr::lint_package()     # must be 0 lints before commit
```

Build the vignette / pkgdown site:

```r
devtools::build_vignettes()
pkgdown::build_site()
```

## lintr Config

`.lintr` suppresses `object_usage_linter` (tidy eval `.data` pronoun false positives),
`line_length_linter`, `indentation_linter`, `commented_code_linter`.
Enforces snake_case via `object_name_linter`. Excludes `renv` and `data-raw`.

## Naming

Function prefixes follow the package domain:

- `crd_aud_*` — audit CSV lifecycle (write, verify, score, review, etc.)
- `crd_zot_*` — Zotero database access
- Internal helpers use a leading dot (`.paraphrase_tokens`, `.token_score`, `.score_row`)

## Open Issues

- [#2](https://github.com/NewGraphEnvironment/cred/issues/2) — `crd_zot_pull_quotes()`: pre-draft passage retrieval (RAG pattern)
- [#3](https://github.com/NewGraphEnvironment/cred/issues/3) — `crd_hook_install()`: git pre-commit hook
- [#9](https://github.com/NewGraphEnvironment/cred/issues/9) — Abstract fallback for no_match rows
- [#21](https://github.com/NewGraphEnvironment/cred/issues/21) — Multi-citation claim grouping
- [#22](https://github.com/NewGraphEnvironment/cred/issues/22) — Ragnar-powered evidence search for large corpora

## Key Design Decisions

- **Token overlap, not semantic search** — appropriate for factual/numeric claims; avoids embedding dependency and keeps results explainable.
- **Abstract matching is a second tier, not a replacement for full-text** — confirms domain plausibility only; `abstract_match` ≠ `auto`.
- **Deliberately permissive default threshold (0.2)** — false positive (wrong paragraph shown) costs seconds of review; false negative (right paragraph missed) costs manual PDF search.
- **`crd_aud_upd()` for incremental updates** — exact join on `(section, citation_key, paraphrase)` with fuzzy fallback (`min_similarity = 0.4`) when text changes; preserves human edits.
- **`crd_aud_score()` adds `review_score` (1-6) and `review_flag`** — lower = more suspect.
- **CSV is current state, git history is the audit trail.**
