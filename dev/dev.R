# Package setup tracking
# Run these interactively — they are NOT idempotent

# 1. Package scaffold
usethis::create_package(".")
usethis::use_mit_license("New Graph Environment Ltd.")

# 2. Testing
usethis::use_testthat(edition = 3)

# 3. Documentation site
usethis::use_pkgdown()
usethis::use_github_action("pkgdown")

# 4. Dev and data-raw directories
usethis::use_directory("dev")
usethis::use_directory("data-raw")

# 5. Hex sticker (reads package name from DESCRIPTION — zero edits needed)
source("data-raw/make_hexsticker.R")

# 6. Toy Zotero data for vignette and examples
source("data-raw/make_toy_zotero.R")

# 7. Dependencies
usethis::use_package("chk")
usethis::use_package("dplyr")
usethis::use_package("officer")
usethis::use_package("pdftools")
usethis::use_package("readr")
usethis::use_package("RSQLite")
usethis::use_package("stringr")
usethis::use_package("knitr",    type = "Suggests")
usethis::use_package("rbbt",     type = "Suggests")
usethis::use_package("rmarkdown", type = "Suggests")
usethis::use_package("testthat", type = "Suggests")

# 8. Tests
usethis::use_test("audit")
usethis::use_test("docx")
usethis::use_test("pdf")
usethis::use_test("zotero")

# 9. Build
devtools::document()
devtools::test()
devtools::check()
