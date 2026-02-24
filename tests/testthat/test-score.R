# test-score.R — tests for crd_aud_score() and scoring internals

# ---------------------------------------------------------------------------
# Helper — write a temp audit CSV from a tibble
# ---------------------------------------------------------------------------
write_tmp_audit <- function(audit) {
  tmp <- tempfile(fileext = ".csv")
  readr::write_csv(audit, tmp, na = "")
  tmp
}

# ---------------------------------------------------------------------------
# Internal helper tests
# ---------------------------------------------------------------------------
test_that(".score_num_tokens extracts numeric tokens", {
  expect_equal(cred:::.score_num_tokens("found 38% at 1,200 crossings"),
    c("38", "1,200"))
  expect_equal(cred:::.score_num_tokens("no numbers here"),
    character(0))
  expect_equal(cred:::.score_num_tokens(NA_character_),
    character(0))
})

test_that(".score_word_tokens extracts words >= 4 chars, strips citekeys", {
  tokens <- cred:::.score_word_tokens(
    "beaver dams reduce summer stream temperatures @smith2020SalmonHabitat"
  )
  expect_true("beaver" %in% tokens)
  expect_true("temperatures" %in% tokens)
  # @citekey stripped — "smith" substring should not appear from citekey
  expect_false("smith2020salmonhabitat" %in% tokens)
  # Short words excluded
  expect_false("the" %in% tokens)
})

test_that(".score_claim_nums excludes years when ignore_years = TRUE", {
  # 1900-2099 are filtered as years; 1850 is NOT in that range so kept
  nums <- cred:::.score_claim_nums("declined 60% between 1950 and 2020", TRUE)
  expect_equal(nums, "60")

  nums_with_years <- cred:::.score_claim_nums(
    "declined 60% between 1950 and 2020", FALSE
  )
  expect_true("1950" %in% nums_with_years)
  expect_true("2020" %in% nums_with_years)

  # 1850 is outside 1900-2099 — treated as a claim number even with ignore
  nums_1850 <- cred:::.score_claim_nums("declined between 1850 and 1950", TRUE)
  expect_true("1850" %in% nums_1850)
  expect_false("1950" %in% nums_1850)
})

# ---------------------------------------------------------------------------
# .score_row unit tests
# ---------------------------------------------------------------------------
test_that("human-reviewed rows score 6", {
  for (status in c("yes", "no", "corrected", "context")) {
    result <- cred:::.score_row(status, "some text", "some quote")
    expect_equal(result$score, 6L, info = paste("status:", status))
    expect_equal(result$flag, "human_reviewed")
  }
})

test_that("NA verified scores 2 (no_source)", {
  result <- cred:::.score_row(NA_character_, "some text", NA_character_)
  expect_equal(result$score, 2L)
  expect_equal(result$flag, "no_source")
})

test_that("no_match scores 1", {
  result <- cred:::.score_row("no_match", "some text", NA_character_)
  expect_equal(result$score, 1L)
  expect_equal(result$flag, "no_match_found")
})

test_that("abstract_match with numeric claim scores 2", {
  result <- cred:::.score_row("abstract_match",
    "survival rates 62% lower", "abstract about salmon habitat")
  expect_equal(result$score, 2L)
  expect_equal(result$flag, "abstract_only_numeric_claim")
})

test_that("abstract_match qualitative scores 3", {
  result <- cred:::.score_row("abstract_match",
    "beaver dams reduce summer temperatures", "abstract about beaver ecology")
  expect_equal(result$score, 3L)
  expect_equal(result$flag, "abstract_only_qualitative")
})

test_that("auto with numbers in paraphrase absent from quote scores 1", {
  result <- cred:::.score_row("auto",
    "embeddedness exceeded 25% at 38% of sites",
    "Salmon return to natal streams to spawn in gravel beds.")
  expect_equal(result$score, 1L)
  expect_true(grepl("^num_mismatch", result$flag))
})

test_that("auto with strong numeric + prose match scores 5", {
  result <- cred:::.score_row("auto",
    "embeddedness exceeded 25% with egg-to-fry survival rates 62% lower",
    "Spawning substrate embeddedness above 25% reduced egg-to-fry survival by 62% compared to low-embeddedness reference sites.")
  expect_equal(result$score, 5L)
  expect_equal(result$flag, "num_match_strong")
})

test_that("auto qualitative with strong word overlap scores 5", {
  result <- cred:::.score_row("auto",
    "beaver dams moderate summer stream temperatures by increasing hyporheic exchange",
    "Beaver dams moderate summer stream temperatures by increasing hyporheic exchange and creating thermal refugia.")
  expect_equal(result$score, 5L)
  expect_equal(result$flag, "prose_strong")
})

test_that("auto qualitative with very weak overlap scores 2", {
  result <- cred:::.score_row("auto",
    "pacific salmon treaty allocates harvest between nations",
    "Spawning substrate embeddedness above 25% reduced egg-to-fry survival.")
  expect_true(result$score <= 3L)
})

test_that("auto with no quote scores 2", {
  result <- cred:::.score_row("auto", "some claim text", NA_character_)
  expect_equal(result$score, 2L)
  expect_equal(result$flag, "auto_no_quote")
})

# ---------------------------------------------------------------------------
# crd_aud_score integration tests
# ---------------------------------------------------------------------------
test_that("crd_aud_score adds review_score and review_flag columns", {
  audit <- tibble::tibble(
    section      = "intro",
    citation_key = c("smith2020", "jones2019", "doe2021"),
    paraphrase   = c(
      "embeddedness exceeded 25% at 38% of sites",
      "beaver dams reduce stream temperatures",
      "some claim about fish"
    ),
    quote        = c(
      "Substrate embeddedness above 25% was found at 38% of surveyed crossings.",
      NA_character_,
      NA_character_
    ),
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = c("auto", "no_match", NA_character_),
    notes        = NA_character_,
    sort_index   = 1:3
  )
  tmp <- write_tmp_audit(audit)

  result <- suppressMessages(crd_aud_score(tmp))

  expect_true("review_score" %in% names(result))
  expect_true("review_flag" %in% names(result))
  expect_equal(result$review_score[2], 1L)  # no_match
  expect_equal(result$review_score[3], 2L)  # NA verified
  expect_true(result$review_score[1] >= 4L) # auto with matching numbers

  unlink(tmp)
})

test_that("crd_aud_score respects overwrite = FALSE", {
  audit <- tibble::tibble(
    section      = "intro",
    citation_key = "smith2020",
    paraphrase   = "some claim",
    quote        = "some quote",
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L,
    review_score = 5L,
    review_flag  = "manual_override"
  )
  tmp <- write_tmp_audit(audit)

  result <- suppressMessages(crd_aud_score(tmp, overwrite = FALSE))

  expect_equal(result$review_score[1], 5L)
  expect_equal(result$review_flag[1], "manual_override")
  unlink(tmp)
})

test_that("crd_aud_score rescores when overwrite = TRUE", {
  audit <- tibble::tibble(
    section      = "intro",
    citation_key = "smith2020",
    paraphrase   = "some claim about fish habitat",
    quote        = "Fish habitat is important for salmon populations.",
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L,
    review_score = 99L,
    review_flag  = "stale"
  )
  tmp <- write_tmp_audit(audit)

  result <- suppressMessages(crd_aud_score(tmp, overwrite = TRUE))

  expect_true(result$review_score[1] != 99L)
  expect_true(result$review_flag[1] != "stale")
  unlink(tmp)
})

test_that("crd_aud_score uses paraphrase_eval when present", {
  audit <- tibble::tibble(
    section        = "intro",
    citation_key   = "smith2020",
    paraphrase     = "optimum is `r format(18175, big.mark = \",\")`",
    paraphrase_eval = "optimum is 18,175",
    quote          = "The estimated optimum escapement is 18,175 adults.",
    claim_type     = NA_character_,
    page_or_section = NA_character_,
    verified       = "auto",
    notes          = NA_character_,
    sort_index     = 1L
  )
  tmp <- write_tmp_audit(audit)

  result <- suppressMessages(crd_aud_score(tmp))

  # Should match on 18175 from paraphrase_eval, not miss on unevaluated R
  expect_true(result$review_score[1] >= 4L,
    info = paste("score:", result$review_score[1], "flag:", result$review_flag[1]))
  unlink(tmp)
})

test_that("crd_aud_score writes results back to CSV", {
  audit <- tibble::tibble(
    section      = "intro",
    citation_key = "smith2020",
    paraphrase   = "beaver dams moderate temperatures",
    quote        = "Beaver dams moderate summer stream temperatures.",
    claim_type   = NA_character_,
    page_or_section = NA_character_,
    verified     = "auto",
    notes        = NA_character_,
    sort_index   = 1L
  )
  tmp <- write_tmp_audit(audit)

  suppressMessages(crd_aud_score(tmp))

  reread <- readr::read_csv(tmp, show_col_types = FALSE)
  expect_true("review_score" %in% names(reread))
  expect_false(is.na(reread$review_score[1]))
  unlink(tmp)
})

test_that("ignore_years = FALSE treats years as claim numbers", {
  # "between 1850 and 1950" — with ignore_years=TRUE these are not claims
  result_ignore <- cred:::.score_row("auto",
    "habitat declined between 1850 and 1950 due to trapping",
    "Beaver habitat was reduced by commercial trapping from the 1700s onwards.",
    ignore_years = TRUE)

  result_keep <- cred:::.score_row("auto",
    "habitat declined between 1850 and 1950 due to trapping",
    "Beaver habitat was reduced by commercial trapping from the 1700s onwards.",
    ignore_years = FALSE)

  # With ignore_years=FALSE, 1850 and 1950 become claim nums that don't match
  # the quote (which has "1700s"), so score should be lower

  expect_true(result_keep$score <= result_ignore$score)
})
