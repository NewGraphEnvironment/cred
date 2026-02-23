test_that("crd_docx_ext_txt returns expected columns", {
  skip_if_not_installed("officer")
  path <- system.file("doc", "example.docx", package = "officer")
  skip_if(path == "", "officer example docx not found")

  result <- crd_docx_ext_txt(path)
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("doc_index", "content_type", "style_name", "text") %in% names(result)))
})

test_that("crd_docx_srch_clm returns scored tibble", {
  skip_if_not_installed("officer")
  path <- system.file("doc", "example.docx", package = "officer")
  skip_if(path == "", "officer example docx not found")

  doc <- crd_docx_ext_txt(path)
  result <- crd_docx_srch_clm(doc, "document example text paragraph")
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("doc_index", "style_name", "text", "score") %in% names(result)))
  if (nrow(result) > 0L) {
    expect_true(all(result$score >= 0.2))
    expect_true(result$score[1L] >= result$score[nrow(result)])
  }
})

test_that("crd_docx_srch_clm returns empty tibble when no match", {
  mock_doc <- tibble::tibble(
    doc_index    = 1L,
    content_type = "paragraph",
    style_name   = "Normal",
    text         = "Completely unrelated text about something else.",
    level        = NA_integer_
  )
  result <- crd_docx_srch_clm(mock_doc, "xyzzy frobble wubble snorkel", min_score = 0.9)
  expect_equal(nrow(result), 0L)
})

test_that("crd_docx_ext_txt type checks", {
  expect_error(crd_docx_ext_txt(123))
  expect_error(crd_docx_ext_txt("nonexistent_file.docx"))
})
