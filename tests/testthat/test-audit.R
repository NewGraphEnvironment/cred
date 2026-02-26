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

# ---------------------------------------------------------------------------
# crd_aud_upd tests
# ---------------------------------------------------------------------------

# Helper — write toy Rmd files and an initial audit CSV
setup_upd_test <- function() {
  rmd_dir <- tempfile("rmd_")
  dir.create(rmd_dir)

  writeLines(c(
    "# Intro {#intro}",
    "",
    "Beaver dams reduce stream temperatures [@jones2019].",
    "",
    "Embeddedness exceeded 25% at most sites [@smith2020]."
  ), file.path(rmd_dir, "0100-intro.Rmd"))

  audit_file <- tempfile("audit_", fileext = ".csv")
  suppressMessages(crd_aud_write(rmd_dir = rmd_dir, out_file = audit_file))

  list(rmd_dir = rmd_dir, audit_file = audit_file)
}

test_that("crd_aud_upd preserves manual columns for unchanged rows", {
  env <- setup_upd_test()

  # Simulate manual review on the existing CSV
  d <- readr::read_csv(env$audit_file, show_col_types = FALSE)
  d$verified[1] <- "yes"
  d$notes[1] <- "confirmed manually"
  d$quote[1] <- "Beaver dams moderate summer stream temperatures."
  readr::write_csv(d, env$audit_file, na = "")

  # Re-run update — Rmd unchanged, so paraphrases match exactly
  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir)
  )

  row1 <- result[result$citation_key == "jones2019", ]
  expect_equal(row1$verified, "yes")
  expect_equal(row1$notes, "confirmed manually")
  expect_equal(row1$quote, "Beaver dams moderate summer stream temperatures.")

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

test_that("crd_aud_upd adds new rows with blank manual columns", {
  env <- setup_upd_test()

  # Add a new citation to the Rmd
  writeLines(c(
    "# Intro {#intro}",
    "",
    "Beaver dams reduce stream temperatures [@jones2019].",
    "",
    "Embeddedness exceeded 25% at most sites [@smith2020].",
    "",
    "Road density correlates with habitat degradation [@doe2021HabitatLoss]."
  ), file.path(env$rmd_dir, "0100-intro.Rmd"))

  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir)
  )

  expect_equal(nrow(result), 3L)
  new_row <- result[result$citation_key == "doe2021HabitatLoss", ]
  expect_true(is.na(new_row$verified))
  expect_true(is.na(new_row$quote))

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

test_that("crd_aud_upd drops rows for deleted citations", {
  env <- setup_upd_test()

  # Remove one citation from the Rmd
  writeLines(c(
    "# Intro {#intro}",
    "",
    "Beaver dams reduce stream temperatures [@jones2019]."
  ), file.path(env$rmd_dir, "0100-intro.Rmd"))

  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir)
  )

  expect_equal(nrow(result), 1L)
  expect_equal(result$citation_key, "jones2019")

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

test_that("crd_aud_upd fuzzy match preserves review for minor rewording", {
  env <- setup_upd_test()

  # Mark first row as reviewed
  d <- readr::read_csv(env$audit_file, show_col_types = FALSE)
  d$verified[1] <- "yes"
  d$notes[1] <- "reviewed"
  d$quote[1] <- "Beaver dams moderate summer stream temperatures."
  readr::write_csv(d, env$audit_file, na = "")

  # Change the paraphrase text slightly — most tokens still overlap
  writeLines(c(
    "# Intro {#intro}",
    "",
    "Beaver dams moderate summer water temperatures [@jones2019].",
    "",
    "Embeddedness exceeded 25% at most sites [@smith2020]."
  ), file.path(env$rmd_dir, "0100-intro.Rmd"))

  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir)
  )

  jones_row <- result[result$citation_key == "jones2019", ]
  expect_equal(jones_row$verified, "yes")
  expect_equal(jones_row$notes, "reviewed")
  expect_equal(jones_row$quote, "Beaver dams moderate summer stream temperatures.")
  # Paraphrase text should be updated to the new wording
  expect_true(grepl("water", jones_row$paraphrase))

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

test_that("crd_aud_upd fuzzy match does not match completely different text", {
  env <- setup_upd_test()

  # Mark first row as reviewed
  d <- readr::read_csv(env$audit_file, show_col_types = FALSE)
  d$verified[1] <- "yes"
  d$notes[1] <- "reviewed"
  readr::write_csv(d, env$audit_file, na = "")

  # Replace with completely unrelated text
  writeLines(c(
    "# Intro {#intro}",
    "",
    "Pacific salmon treaty allocates harvest between nations [@jones2019].",
    "",
    "Embeddedness exceeded 25% at most sites [@smith2020]."
  ), file.path(env$rmd_dir, "0100-intro.Rmd"))

  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir)
  )

  jones_row <- result[result$citation_key == "jones2019", ]
  expect_true(is.na(jones_row$verified),
    info = "Completely different paraphrase should not fuzzy match")

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

test_that("crd_aud_upd fuzzy match respects min_similarity threshold", {
  env <- setup_upd_test()

  # Mark first row as reviewed
  d <- readr::read_csv(env$audit_file, show_col_types = FALSE)
  d$verified[1] <- "yes"
  d$notes[1] <- "reviewed"
  readr::write_csv(d, env$audit_file, na = "")

  # Minor change — would normally fuzzy-match
  writeLines(c(
    "# Intro {#intro}",
    "",
    "Beaver dams moderate summer water temperatures [@jones2019].",
    "",
    "Embeddedness exceeded 25% at most sites [@smith2020]."
  ), file.path(env$rmd_dir, "0100-intro.Rmd"))

  # Set min_similarity = 1 to disable fuzzy matching
  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir, min_similarity = 1)
  )

  jones_row <- result[result$citation_key == "jones2019", ]
  expect_true(is.na(jones_row$verified),
    info = "min_similarity=1 should disable fuzzy matching")

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

# ---------------------------------------------------------------------------
# crd_aud_fill_src candidate_quotes tests
# ---------------------------------------------------------------------------

test_that("crd_aud_fill_src stores candidate_quotes as valid JSON", {
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

  expect_true("candidate_quotes" %in% names(result))
  expect_false(is.na(result$candidate_quotes[1L]))

  cands <- jsonlite::fromJSON(result$candidate_quotes[1L])
  expect_true(all(c("rank", "score", "location", "text") %in% names(cands)))
  expect_true(nrow(cands) >= 1L)
  expect_equal(cands$rank[1L], 1L)

  unlink(tmp_csv)
})

test_that("crd_aud_fill_src candidate_quotes is NA for no_match rows", {
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
  expect_true(is.na(result$candidate_quotes[1L]))
  unlink(tmp_csv)
})

test_that("crd_aud_upd preserves candidate_quotes through fuzzy join", {
  env <- setup_upd_test()

  # Simulate a fill_src result with candidate_quotes
  d <- readr::read_csv(env$audit_file, show_col_types = FALSE)
  d$verified[1] <- "auto"
  d$quote[1] <- "Beaver dams moderate summer stream temperatures."
  d$candidate_quotes <- NA_character_
  d$candidate_quotes[1] <- jsonlite::toJSON(
    data.frame(rank = 1L, score = 0.8, location = "1", text = "Beaver dams text",
               stringsAsFactors = FALSE),
    auto_unbox = TRUE
  )
  readr::write_csv(d, env$audit_file, na = "")

  # Minor paraphrase change to trigger fuzzy match
  writeLines(c(
    "# Intro {#intro}",
    "",
    "Beaver dams moderate summer water temperatures [@jones2019].",
    "",
    "Embeddedness exceeded 25% at most sites [@smith2020]."
  ), file.path(env$rmd_dir, "0100-intro.Rmd"))

  result <- suppressMessages(
    crd_aud_upd(env$audit_file, rmd_dir = env$rmd_dir)
  )

  jones_row <- result[result$citation_key == "jones2019", ]
  expect_equal(jones_row$verified, "auto")
  expect_false(is.na(jones_row$candidate_quotes))

  unlink(env$rmd_dir, recursive = TRUE)
  unlink(env$audit_file)
})

# ---------------------------------------------------------------------------
# crd_aud_fill_src tests (existing)
# ---------------------------------------------------------------------------

test_that("crd_aud_fill_src type checks", {
  expect_error(crd_aud_fill_src(123, tibble::tibble(), "key"))
  expect_error(crd_aud_fill_src("nonexistent.csv", tibble::tibble(), "key"))
  tmp_csv <- tempfile(fileext = ".csv")
  readr::write_excel_csv(tibble::tibble(citation_key = "x"), tmp_csv)
  expect_error(crd_aud_fill_src(tmp_csv, tibble::tibble(x = 1L), "key"))
  unlink(tmp_csv)
})
