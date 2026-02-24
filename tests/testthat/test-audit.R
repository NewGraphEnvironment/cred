test_that("crd_aud_fill_src fills quote and page_or_section for docx source", {
  # Build a minimal audit CSV
  tmp_csv <- tempfile(fileext = ".csv")
  audit <- tibble::tibble(
    section         = "intro",
    citation_key    = "mock2024",
    paraphrase      = "beaver dams reduce summer stream temperatures",
    quote           = NA_character_,
    claim_type      = NA_character_,
    page_or_section = NA_character_,
    verified        = NA_character_,
    notes           = NA_character_
  )
  readr::write_excel_csv(audit, tmp_csv, na = "")

  # Build a minimal docx-like source tibble
  mock_src <- tibble::tibble(
    doc_index    = 1L:3L,
    content_type = "paragraph",
    style_name   = "Normal",
    text         = c(
      "Beaver dams moderate summer stream temperatures by increasing hyporheic exchange.",
      "Road density is a common metric of watershed disturbance.",
      "Salmon return to their natal streams to spawn."
    ),
    level        = NA_integer_
  )

  result <- crd_aud_fill_src(tmp_csv, mock_src, citation_key = "mock2024")

  expect_equal(result$verified[1L], "auto")
  expect_equal(result$page_or_section[1L], "1")
  expect_true(nchar(result$quote[1L]) > 0L)
  unlink(tmp_csv)
})

test_that("crd_aud_fill_src sets no_match when score below threshold", {
  tmp_csv <- tempfile(fileext = ".csv")
  audit <- tibble::tibble(
    section         = "intro",
    citation_key    = "mock2024",
    paraphrase      = "xyzzy frobble snorkel wubble unrelated",
    quote           = NA_character_,
    claim_type      = NA_character_,
    page_or_section = NA_character_,
    verified        = NA_character_,
    notes           = NA_character_
  )
  readr::write_excel_csv(audit, tmp_csv, na = "")

  mock_src <- tibble::tibble(
    doc_index    = 1L,
    content_type = "paragraph",
    style_name   = "Normal",
    text         = "Salmon return to their natal streams to spawn.",
    level        = NA_integer_
  )

  result <- crd_aud_fill_src(tmp_csv, mock_src, citation_key = "mock2024",
                              min_score = 0.9)
  expect_equal(result$verified[1L], "no_match")
  unlink(tmp_csv)
})

test_that("crd_aud_fill_src skips already-verified rows", {
  tmp_csv <- tempfile(fileext = ".csv")
  audit <- tibble::tibble(
    section         = "intro",
    citation_key    = "mock2024",
    paraphrase      = "beaver dams reduce summer stream temperatures",
    quote           = "Already reviewed text.",
    claim_type      = NA_character_,
    page_or_section = "99",
    verified        = "yes",
    notes           = NA_character_
  )
  readr::write_excel_csv(audit, tmp_csv, na = "")

  mock_src <- tibble::tibble(
    doc_index    = 1L,
    content_type = "paragraph",
    style_name   = "Normal",
    text         = "Beaver dams moderate summer stream temperatures.",
    level        = NA_integer_
  )

  result <- crd_aud_fill_src(tmp_csv, mock_src, citation_key = "mock2024")

  # Should not have been overwritten
  expect_equal(result$verified[1L], "yes")
  expect_equal(result$quote[1L], "Already reviewed text.")
  unlink(tmp_csv)
})

test_that("crd_aud_fill_src type checks", {
  expect_error(crd_aud_fill_src(123, tibble::tibble(), "key"))
  expect_error(crd_aud_fill_src("nonexistent.csv", tibble::tibble(), "key"))
  tmp_csv <- tempfile(fileext = ".csv")
  readr::write_excel_csv(tibble::tibble(citation_key = "x"), tmp_csv)
  expect_error(crd_aud_fill_src(tmp_csv, tibble::tibble(x = 1L), "key"))
  unlink(tmp_csv)
})
