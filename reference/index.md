# Package index

## All functions

- [`crd_aud_eval_inline()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_eval_inline.md)
  : Fill quote and verified for NA rows using Zotero abstract text

- [`crd_aud_fill_src()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_fill_src.md)
  : Fill audit CSV quote and location columns from a source document

- [`crd_aud_fmt_xlsx()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_fmt_xlsx.md)
  : Format an audit CSV as a readable Excel workbook

- [`crd_aud_review()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_review.md)
  : Launch an interactive review app for the citation audit CSV

- [`crd_aud_score()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_score.md)
  : Score audit rows by review priority

- [`crd_aud_scr_risk()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_scr_risk.md)
  : Auto-score citation rows by hallucination risk

- [`crd_aud_summary()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_summary.md)
  : Summarise an audit CSV by verification status

- [`crd_aud_upd()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_upd.md)
  : Update an existing audit CSV preserving manual columns

- [`crd_aud_verify_abstract()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_abstract.md)
  :

  queries the local Zotero database for the abstract of each cited item
  and scores it against the `paraphrase` using token overlap. Rows that
  score at or above `min_score` receive `verified = "abstract_match"`
  and the abstract text as their `quote`.

- [`crd_aud_verify_all()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_verify_all.md)
  : Verify all citation keys in an audit CSV against their source
  documents

- [`crd_aud_write()`](https://newgraphenvironment.github.io/cred/reference/crd_aud_write.md)
  : Write a citation audit CSV scaffold from a directory of Rmd files

- [`crd_chnk_strip()`](https://newgraphenvironment.github.io/cred/reference/crd_chnk_strip.md)
  : Strip fenced code chunks from a character vector of lines

- [`crd_cit_ext_rmd()`](https://newgraphenvironment.github.io/cred/reference/crd_cit_ext_rmd.md)
  : Extract citations with paraphrase context from an Rmd file

- [`crd_docx_ext_txt()`](https://newgraphenvironment.github.io/cred/reference/crd_docx_ext_txt.md)
  : Extract text from a Word document as a tidy tibble

- [`crd_docx_srch_clm()`](https://newgraphenvironment.github.io/cred/reference/crd_docx_srch_clm.md)
  : Search a Word document for the best-matching passage to a paraphrase

- [`crd_inl_rend()`](https://newgraphenvironment.github.io/cred/reference/crd_inl_rend.md)
  : Replace scalar inline R expressions in a string

- [`crd_pdf_ext_txt()`](https://newgraphenvironment.github.io/cred/reference/crd_pdf_ext_txt.md)
  : Extract text from a PDF as a tidy tibble

- [`crd_pdf_srch_clm()`](https://newgraphenvironment.github.io/cred/reference/crd_pdf_srch_clm.md)
  : Search a PDF for the best-matching passage to a paraphrase

- [`crd_search()`](https://newgraphenvironment.github.io/cred/reference/crd_search.md)
  : Search a ragnar evidence store for passages supporting a claim

- [`crd_sent_ext_key()`](https://newgraphenvironment.github.io/cred/reference/crd_sent_ext_key.md)
  : Extract the sentence(s) containing a specific citation key

- [`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md)
  : Build a ragnar evidence store from Zotero PDFs

- [`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md)
  : Connect to a ragnar evidence store, pulling and verifying it if
  needed

- [`crd_zot_abstract_lookup()`](https://newgraphenvironment.github.io/cred/reference/crd_zot_abstract_lookup.md)
  : Retrieve Zotero abstracts for a vector of citation keys

- [`crd_zot_src_lookup()`](https://newgraphenvironment.github.io/cred/reference/crd_zot_src_lookup.md)
  : Resolve citation keys to source file paths via Zotero SQLite
