# test-eval-html.R — tests for crd_aud_eval_html() and HTML evaluation helpers

# ---------------------------------------------------------------------------
# Helper — create a temp HTML file with <p> paragraphs
# ---------------------------------------------------------------------------
write_tmp_html <- function(paragraphs, dir = tempfile("html_")) {
  dir.create(dir, showWarnings = FALSE)
  html <- paste0(
    "<html><body>",
    paste0("<p>", paragraphs, "</p>", collapse = "\n"),
    "</body></html>"
  )
  writeLines(html, file.path(dir, "chapter.html"))
  dir
}

write_tmp_audit <- function(audit) {
  tmp <- tempfile(fileext = ".csv")
  readr::write_csv(audit, tmp, na = "")
  tmp
}

# ---------------------------------------------------------------------------
# Internal helper tests
# ---------------------------------------------------------------------------
test_that(".frame_parts splits paraphrase around inline R", {
  parts <- cred:::.frame_parts(
    "fertilizer represents `r kln_fert_pct_tdp`% of annual dissolved phosphorus"
  )
  expect_true(any(grepl("fertilizer represents", parts)))
  expect_true(any(grepl("of annual dissolved phosphorus", parts)))
  # The inline R itself should not appear
  expect_false(any(grepl("kln_fert_pct_tdp", parts)))
})

test_that(".frame_parts strips citekeys and markdown", {
  parts <- cred:::.frame_parts(
    "beaver dams reduce **summer** temperatures [@jones2019] by `r pct`% overall"
  )
  expect_false(any(grepl("jones2019", parts)))
  expect_false(any(grepl("\\*", parts)))
})

test_that(".match_frame_to_html finds matching paragraph", {
  html_texts <- c(
    "This is about fish habitat and spawning.",
    "fertilizer represents 24% of annual dissolved phosphorus input.",
    "Kokanee stocks declined in the 1980s."
  )
  parts <- c("fertilizer represents", "of annual dissolved phosphorus")
  result <- cred:::.match_frame_to_html(parts, html_texts)
  expect_equal(result, html_texts[2])
})

test_that(".match_frame_to_html returns NA when no match", {
  html_texts <- c("This is about fish habitat.")
  parts <- c("fertilizer represents", "dissolved phosphorus")
  result <- cred:::.match_frame_to_html(parts, html_texts)
  expect_true(is.na(result))
})

# ---------------------------------------------------------------------------
# crd_aud_eval_html integration tests
# ---------------------------------------------------------------------------
test_that("crd_aud_eval_html resolves single inline R expression", {
  audit <- tibble::tibble(
    section      = "discussion",
    citation_key = "smith2020",
    paraphrase   = "fertilizer represents `r kln_pct`% of annual TDP input",
    quote        = "Some quote from source.",
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L
  )
  tmp_csv <- write_tmp_audit(audit)
  html_dir <- write_tmp_html(c(
    "fertilizer represents 24% of annual TDP input to the north arm"
  ))

  result <- suppressWarnings(suppressMessages(
    crd_aud_eval_html(tmp_csv, html_dir)
  ))

  expect_true("paraphrase_eval" %in% names(result))
  expect_true(grepl("24", result$paraphrase_eval[1]))
  expect_false(grepl("`r ", result$paraphrase_eval[1]))

  unlink(tmp_csv)
  unlink(html_dir, recursive = TRUE)
})

test_that("crd_aud_eval_html resolves multiple inline R expressions", {
  audit <- tibble::tibble(
    section      = "results",
    citation_key = "doe2021HabitatStudy",
    paraphrase   = "ranged from `r val_low` to `r val_high` mg/L across sites",
    quote        = "Concentrations ranged from 0.8 to 1.2 mg/L.",
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L
  )
  tmp_csv <- write_tmp_audit(audit)
  html_dir <- write_tmp_html(c(
    "ranged from 0.8 to 1.2 mg/L across sites in the study area"
  ))

  result <- suppressWarnings(suppressMessages(
    crd_aud_eval_html(tmp_csv, html_dir)
  ))

  expect_true(grepl("0.8", result$paraphrase_eval[1]))
  expect_true(grepl("1.2", result$paraphrase_eval[1]))
  expect_false(grepl("`r ", result$paraphrase_eval[1]))

  unlink(tmp_csv)
  unlink(html_dir, recursive = TRUE)
})

test_that("crd_aud_eval_html skips rows without inline R", {
  audit <- tibble::tibble(
    section      = "intro",
    citation_key = "smith2020",
    paraphrase   = "beaver dams reduce stream temperatures",
    quote        = NA_character_,
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L
  )
  tmp_csv <- write_tmp_audit(audit)
  html_dir <- write_tmp_html("beaver dams reduce stream temperatures")

  result <- suppressMessages(crd_aud_eval_html(tmp_csv, html_dir))

  # No inline R → early return, paraphrase_eval stays NA
  expect_true(is.na(result$paraphrase_eval[1]) ||
    result$paraphrase_eval[1] == result$paraphrase[1])

  unlink(tmp_csv)
  unlink(html_dir, recursive = TRUE)
})

test_that("crd_aud_eval_html respects overwrite = FALSE", {
  audit <- tibble::tibble(
    section        = "discussion",
    citation_key   = "smith2020",
    paraphrase     = "value was `r some_var`% of total",
    paraphrase_eval = "value was 99% of total",
    quote          = NA_character_,
    claim_type     = NA_character_,
    page_or_section = NA_character_,
    verified       = "auto",
    notes          = NA_character_,
    sort_index     = 1L
  )
  tmp_csv <- write_tmp_audit(audit)
  html_dir <- write_tmp_html("value was 42% of total input")

  result <- suppressMessages(crd_aud_eval_html(tmp_csv, html_dir,
                                                overwrite = FALSE))

  expect_equal(result$paraphrase_eval[1], "value was 99% of total")

  unlink(tmp_csv)
  unlink(html_dir, recursive = TRUE)
})

test_that("crd_aud_eval_html warns on no HTML match", {
  audit <- tibble::tibble(
    section      = "discussion",
    citation_key = "smith2020",
    paraphrase   = "completely unrelated `r some_var` text here",
    quote        = NA_character_,
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L
  )
  tmp_csv <- write_tmp_audit(audit)
  html_dir <- write_tmp_html("this paragraph is about fish habitat")

  expect_warning(
    suppressMessages(crd_aud_eval_html(tmp_csv, html_dir)),
    "No HTML match"
  )

  unlink(tmp_csv)
  unlink(html_dir, recursive = TRUE)
})
