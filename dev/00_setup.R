# dev/00_setup.R
# Run once to set up the package. Not part of the package itself.

# usethis::create_package("cred")               # already done
# usethis::use_testthat()                        # already done
# usethis::use_mit_license("New Graph Environment Ltd.")
# usethis::use_news_md()
# usethis::use_readme_rmd()

# Add functions files
usethis::use_r("rmd")        # rmd_chunks_strip, crd_cit_ext_rmd, crd_inl_rend
usethis::use_r("sentence")   # crd_sent_ext_key
usethis::use_r("audit")      # crd_aud_write, crd_aud_upd, crd_aud_scr_risk
usethis::use_r("pdf")        # crd_pdf_ext_txt, crd_pdf_srch_clm, crd_pdf_find_quote
usethis::use_r("docx")       # crd_docx_ext_txt, crd_docx_srch_clm
usethis::use_r("zotero")     # crd_zot_fetch_abst, crd_zot_res_key

# Add test files
usethis::use_test("rmd")
usethis::use_test("sentence")
usethis::use_test("audit")
usethis::use_test("pdf")
usethis::use_test("docx")

# pkgdown
# usethis::use_pkgdown()

# git
# usethis::use_git()
# usethis::use_github()
