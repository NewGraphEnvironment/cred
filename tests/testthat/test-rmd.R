test_that("crd_chnk_strip blanks code chunk lines", {
  lines <- c("prose", "```r", "@key inside chunk", "```", "more prose")
  result <- crd_chnk_strip(lines)
  expect_equal(result, c("prose", "", "", "", "more prose"))
})

test_that("crd_chnk_strip handles consecutive chunks", {
  lines <- c("```r", "x <- 1", "```", "text", "```", "y <- 2", "```")
  result <- crd_chnk_strip(lines)
  expect_equal(result[4L], "text")
  expect_equal(result[c(1L, 2L, 3L, 5L, 6L, 7L)], rep("", 6L))
})

test_that("crd_chnk_strip returns unchanged when no chunks", {
  lines <- c("line one", "line two @key here")
  expect_equal(crd_chnk_strip(lines), lines)
})

test_that("crd_chnk_strip type checks", {
  expect_error(crd_chnk_strip(1:3))
})

test_that("crd_cit_ext_rmd extracts keys from a temp Rmd", {
  tmp <- tempfile(fileext = ".Rmd")
  writeLines(c(
    "# Chapter",
    "@smith2020 documented that flows were reduced.",
    "Temperatures were high [@jones2021; @brown2022]."
  ), tmp)
  result <- crd_cit_ext_rmd(tmp)
  expect_s3_class(result, "tbl_df")
  expect_true("smith2020" %in% result$citation_key)
  expect_true("jones2021" %in% result$citation_key)
  expect_true("brown2022" %in% result$citation_key)
  unlink(tmp)
})

test_that("crd_cit_ext_rmd ignores keys inside code chunks", {
  tmp <- tempfile(fileext = ".Rmd")
  writeLines(c(
    "```r",
    "# @fakecitation inside chunk",
    "```",
    "@smith2020 documented the effect."
  ), tmp)
  result <- crd_cit_ext_rmd(tmp)
  expect_false("fakecitation" %in% result$citation_key)
  expect_true("smith2020" %in% result$citation_key)
  unlink(tmp)
})

test_that("crd_cit_ext_rmd strips trailing punctuation from keys", {
  tmp <- tempfile(fileext = ".Rmd")
  writeLines("See @smith2020.", tmp)
  result <- crd_cit_ext_rmd(tmp)
  expect_equal(result$citation_key, "smith2020")
  unlink(tmp)
})

test_that("crd_cit_ext_rmd returns empty tibble for file with no citations", {
  tmp <- tempfile(fileext = ".Rmd")
  writeLines("No citations here.", tmp)
  result <- crd_cit_ext_rmd(tmp)
  expect_equal(nrow(result), 0L)
  unlink(tmp)
})
