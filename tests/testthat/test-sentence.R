test_that("crd_sent_ext_key isolates narrative citation sentence", {
  line <- paste(
    "@smith2020 documented that beaver dams reduce temperatures.",
    "@jones2021 confirmed the effect with analogues."
  )
  expect_match(crd_sent_ext_key(line, "smith2020"), "beaver dams")
  expect_no_match(crd_sent_ext_key(line, "smith2020"), "analogues")

  expect_match(crd_sent_ext_key(line, "jones2021"), "analogues")
  expect_no_match(crd_sent_ext_key(line, "jones2021"), "beaver dams")
})

test_that("crd_sent_ext_key handles parenthetical citation at end of sentence", {
  line <- "Temperatures were 2 degrees lower in restored reaches [@smith2020]."
  result <- crd_sent_ext_key(line, "smith2020")
  expect_match(result, "Temperatures were 2 degrees lower")
})

test_that("crd_sent_ext_key does not split inside compound brackets", {
  line <- "Restoration improves habitat [@smith2020; @jones2021]. Other effects noted."
  result_s <- crd_sent_ext_key(line, "smith2020")
  result_j <- crd_sent_ext_key(line, "jones2021")
  expect_match(result_s, "Restoration improves habitat")
  expect_match(result_j, "Restoration improves habitat")
  expect_no_match(result_s, "Other effects")
})

test_that("crd_sent_ext_key does not split on et al.", {
  line <- paste(
    "The Price et al. State of Knowledge Report [@price2026] is the primary source.",
    "Other sources were also consulted."
  )
  result <- crd_sent_ext_key(line, "price2026")
  expect_match(result, "State of Knowledge Report")
  expect_match(result, "primary source")
})

test_that("crd_sent_ext_key falls back to full line for short fragment", {
  line <- "See [@smith2020]."
  result <- crd_sent_ext_key(line, "smith2020")
  expect_equal(result, "See [@smith2020].")
})

test_that("crd_sent_ext_key falls back to full line for lowercase-start fragment", {
  line <- "Rearing success was low; stream temperatures exceeded tolerance [@smith2020]."
  result <- crd_sent_ext_key(line, "smith2020")
  # fragment would start with "stream" (lowercase after ;) — should get full line
  expect_match(result, "Rearing success was low")
})

test_that("crd_sent_ext_key type checks", {
  expect_error(crd_sent_ext_key(123, "key"))
  expect_error(crd_sent_ext_key("line", 123))
})
