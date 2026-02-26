test_that("crd_aud_eval_inline resolves inline R from environment", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  d <- tibble::tibble(
    section      = "results",
    citation_key = c("smith2020SalmonHabitat", "jones2019BeaverEcology"),
    paraphrase   = c(
      "Fertilizer represents `r fert_pct`% of annual phosphorus input",
      "Beaver dams increased pool habitat by 35%"
    ),
    quote           = NA_character_,
    claim_type      = NA_character_,
    verified        = NA_character_,
    page_or_section = NA_character_,
    notes           = NA_character_
  )
  readr::write_csv(d, tmp)

  # Create an environment with the variable
  e <- new.env(parent = emptyenv())
  e$fert_pct <- 42

  result <- crd_aud_eval_inline(tmp, env = e)

  # Row 1: inline R resolved

  expect_equal(result$paraphrase_eval[1],
               "Fertilizer represents 42% of annual phosphorus input")
  # Row 2: no inline R, paraphrase copied as-is
  expect_equal(result$paraphrase_eval[2],
               "Beaver dams increased pool habitat by 35%")
  # paraphrase column unchanged
  expect_true(grepl("`r fert_pct`", result$paraphrase[1], fixed = TRUE))
})

test_that("crd_aud_eval_inline warns on unresolvable expressions", {

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  d <- tibble::tibble(
    section      = "results",
    citation_key = "smith2020SalmonHabitat",
    paraphrase   = "Temperature was `r mystery_var` degrees",
    quote           = NA_character_,
    claim_type      = NA_character_,
    verified        = NA_character_,
    page_or_section = NA_character_,
    notes           = NA_character_
  )
  readr::write_csv(d, tmp)

  # Empty environment — variable doesn't exist
  e <- new.env(parent = emptyenv())

  expect_warning(
    crd_aud_eval_inline(tmp, env = e),
    "Could not evaluate"
  )
})

test_that("crd_aud_eval_inline respects overwrite = FALSE", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  d <- tibble::tibble(
    section      = "results",
    citation_key = "smith2020SalmonHabitat",
    paraphrase   = "Value was `r my_val` units",
    paraphrase_eval = "Value was 10 units",
    quote           = NA_character_,
    claim_type      = NA_character_,
    verified        = NA_character_,
    page_or_section = NA_character_,
    notes           = NA_character_
  )
  readr::write_csv(d, tmp)

  e <- new.env(parent = emptyenv())
  e$my_val <- 99

  result <- crd_aud_eval_inline(tmp, env = e, overwrite = FALSE)
  # Should keep existing value, not re-evaluate
  expect_equal(result$paraphrase_eval[1], "Value was 10 units")

  result2 <- crd_aud_eval_inline(tmp, env = e, overwrite = TRUE)
  expect_equal(result2$paraphrase_eval[1], "Value was 99 units")
})

test_that("crd_aud_eval_inline handles regex metacharacters in paraphrase", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)

  # Real-world case: paraphrases contain \. and other regex chars
  d <- tibble::tibble(
    section      = "results",
    citation_key = "perrin1997PhosphorusBudget",
    paraphrase   = "Loading was `r load_val` kg/yr (see Fig. 2.1)",
    quote           = NA_character_,
    claim_type      = NA_character_,
    verified        = NA_character_,
    page_or_section = NA_character_,
    notes           = NA_character_
  )
  readr::write_csv(d, tmp)

  e <- new.env(parent = emptyenv())
  e$load_val <- 1250

  # Should not crash on "Fig. 2.1" which contains regex metacharacters
  result <- crd_aud_eval_inline(tmp, env = e)
  expect_equal(result$paraphrase_eval[1],
               "Loading was 1250 kg/yr (see Fig. 2.1)")
})
