# cred 0.1.0

First stable release. Core citation audit pipeline for detecting hallucinated
or misattributed citations in LLM-assisted bookdown reports.

* Extract citations and surrounding sentences from Rmd files
* Verify claims against PDF and docx source documents via token overlap
* Resolve inline R expressions before matching
* Abstract fallback for sources without full text
* Risk scoring and claim type classification
* Top-N candidate passages stored as JSON for review
* Interactive Shiny review app with collapsible candidate panel
* Incremental CSV updates with fuzzy join to preserve human edits
