# test-matching.R
# End-to-end tests that exercise the full cred pipeline on the package's own
# toy data (inst/extdata/). These tests confirm that the token-overlap matching
# algorithm correctly identifies supporting passages, flags unsupported claims
# as no_match, and leaves metadata-only entries as NA.
#
# Toy data layout (see data-raw/make_toy_zotero.R):
#   smith2020SalmonHabitat  — PDF, 4 paragraphs:
#     p1  spawning embeddedness / egg-to-fry survival
#     p2  riparian shade / stream temperature
#     p3  road crossings / fish passage (38%)
#     p4  large woody debris          ← deliberately off-topic
#   jones2019BeaverEcology  — docx, 4 paragraphs:
#     §1  beaver ponds / overwinter density (3.4×)
#     §2  peak-flow reduction (31%) / baseflow extension
#     §3  historical trapping / 60% habitat loss
#     §4  floodplain side channels / growth rates (40%)
#   doe2021NoFile           — metadata only, no attachment

toy_dir <- system.file("extdata", package = "cred")

skip_toy <- function() {
  skip_if(toy_dir == "", "toy extdata not found — package not installed")
  skip_if(
    !file.exists(file.path(toy_dir, "zotero.sqlite")),
    "toy zotero.sqlite missing"
  )
}

# ---------------------------------------------------------------------------
# Helper — build a temp audit CSV from toy Rmd content and run verify_all
# ---------------------------------------------------------------------------
build_toy_audit <- function(rmd_lines_ch1, rmd_lines_ch2) {
  rmd_dir    <- tempfile("rmd_")
  audit_file <- tempfile("audit_", fileext = ".csv")
  dir.create(rmd_dir)

  writeLines(c("# Habitat {#habitat}", "", rmd_lines_ch1),
             file.path(rmd_dir, "0100-habitat.Rmd"))
  writeLines(c("# Beaver {#beaver}", "", rmd_lines_ch2),
             file.path(rmd_dir, "0200-beaver.Rmd"))

  suppressMessages(crd_aud_write(rmd_dir = rmd_dir, out_file = audit_file))

  sources <- suppressWarnings(
    crd_zot_src_lookup(
      c("smith2020SalmonHabitat", "jones2019BeaverEcology", "doe2021NoFile"),
      zotero_dir = toy_dir
    )
  )

  suppressMessages(
    crd_aud_verify_all(audit_file, sources = sources, min_score = 0.2)
  )

  readr::read_csv(audit_file, show_col_types = FALSE)
}

# ---------------------------------------------------------------------------
# 1. Numeric paraphrases — exact statistics from source
# ---------------------------------------------------------------------------
test_that("numeric paraphrases match correct PDF passages", {
  skip_toy()

  result <- build_toy_audit(
    rmd_lines_ch1 = c(
      "Reaches where spawning substrate embeddedness exceeded 25% had egg-to-fry survival rates 62% lower than adjacent low-embeddedness sites [@smith2020SalmonHabitat].",
      "Fish passage assessments at 1,200 road-stream crossings found that 38% were rated as full or partial barriers to adult chinook migration [@smith2020SalmonHabitat]."
    ),
    rmd_lines_ch2 = c(
      "Electrofishing surveys recorded juvenile salmonid densities 3.4 times higher in beaver pond habitat than in adjacent free-flowing reaches [@jones2019BeaverEcology].",
      "Archival records indicate that beaver pond habitat declined by approximately 60% between 1850 and 1950 due to commercial trapping pressure [@jones2019BeaverEcology]."
    )
  )

  smith_rows <- result[result$citation_key == "smith2020SalmonHabitat" &
                         !is.na(result$citation_key), ]
  jones_rows <- result[result$citation_key == "jones2019BeaverEcology" &
                         !is.na(result$citation_key), ]

  # All four numeric claims should auto-match
  expect_true(all(smith_rows$verified == "auto"),
    info = paste("smith verified:", paste(smith_rows$verified, collapse = ", ")))
  expect_true(all(jones_rows$verified == "auto"),
    info = paste("jones verified:", paste(jones_rows$verified, collapse = ", ")))

  # Quotes should mention the key numbers
  expect_true(any(grepl("62|embeddedness|egg-to-fry", smith_rows$quote, ignore.case = TRUE)),
    info = "Expected embeddedness passage in smith quote")
  expect_true(any(grepl("38|crossing|barrier", smith_rows$quote, ignore.case = TRUE)),
    info = "Expected road crossing passage in smith quote")
  expect_true(any(grepl("3\\.4|beaver pond|steelhead|coho", jones_rows$quote, ignore.case = TRUE)),
    info = "Expected beaver density passage in jones quote")
  expect_true(any(grepl("60|trapping|1850|1950", jones_rows$quote, ignore.case = TRUE)),
    info = "Expected historical trapping passage in jones quote")
})

# ---------------------------------------------------------------------------
# 2. Qualitative paraphrases — same finding, different words, no numbers
# ---------------------------------------------------------------------------
test_that("qualitative paraphrases (no numbers) still match correct passages", {
  skip_toy()

  result <- build_toy_audit(
    rmd_lines_ch1 = c(
      # Paraphrase of riparian temperature paragraph — no numbers
      "Loss of streamside forest cover eliminates the shade that keeps summer water temperatures within the thermal tolerance of juvenile chinook, degrading rearing conditions in harvested riparian zones [@smith2020SalmonHabitat]."
    ),
    rmd_lines_ch2 = c(
      # Paraphrase of floodplain side-channel paragraph — no numbers
      "Beaver-mediated floodplain connectivity allows juvenile chinook to access off-channel rearing areas during high flows, where growth rates substantially exceed those of fish confined to the mainstem channel [@jones2019BeaverEcology]."
    )
  )

  smith_row <- result[result$citation_key == "smith2020SalmonHabitat" &
                        !is.na(result$citation_key), ]
  jones_row <- result[result$citation_key == "jones2019BeaverEcology" &
                        !is.na(result$citation_key), ]

  expect_equal(smith_row$verified, "auto",
    info = paste("Qualitative riparian paraphrase got:", smith_row$verified))
  expect_equal(jones_row$verified, "auto",
    info = paste("Qualitative floodplain paraphrase got:", jones_row$verified))

  # Quote should come from the temperature paragraph, not an unrelated one
  expect_true(
    grepl("temperature|thermal|canopy|riparian|shade|conifer", smith_row$quote,
          ignore.case = TRUE),
    info = paste("Expected temperature passage; got:", substr(smith_row$quote, 1, 120))
  )
  expect_true(
    grepl("floodplain|side channel|mainstem|growth", jones_row$quote,
          ignore.case = TRUE),
    info = paste("Expected floodplain passage; got:", substr(jones_row$quote, 1, 120))
  )
})

# ---------------------------------------------------------------------------
# 3. Unsupported claim → no_match
# ---------------------------------------------------------------------------
test_that("claim not covered by source produces no_match", {
  skip_toy()

  # Harvest allocation claim — smith2020 is a freshwater habitat quality paper.
  # It contains nothing about Pacific Salmon Treaty harvest negotiations or
  # abundance indicators. The claim shares no content tokens with any of the
  # four paragraphs (spawning substrate, riparian temperature, road crossings,
  # large woody debris), so no passage scores above the threshold.
  result <- build_toy_audit(
    rmd_lines_ch1 = c(
      "The Pacific Salmon Treaty allocates harvest between Canada and the United States based on abundance indicators and conservation thresholds negotiated through the Pacific Salmon Commission [@smith2020SalmonHabitat]."
    ),
    rmd_lines_ch2 = character(0)
  )

  smith_row <- result[result$citation_key == "smith2020SalmonHabitat" &
                        !is.na(result$citation_key), ]
  expect_equal(smith_row$verified, "no_match",
    info = paste("Unsupported floodplain claim got:", smith_row$verified,
                 "\nQuote:", smith_row$quote))
})

# ---------------------------------------------------------------------------
# 4. No attachment in Zotero → verified stays NA
# ---------------------------------------------------------------------------
test_that("citation key with no Zotero attachment stays NA", {
  skip_toy()

  result <- build_toy_audit(
    rmd_lines_ch1 = c(
      "Stream temperature governs the spatial distribution of juvenile salmon and limits rearing area during summer low flows [@doe2021NoFile]."
    ),
    rmd_lines_ch2 = character(0)
  )

  doe_row <- result[result$citation_key == "doe2021NoFile" &
                      !is.na(result$citation_key), ]
  expect_true(is.na(doe_row$verified),
    info = paste("doe2021NoFile (no attachment) should be NA; got:", doe_row$verified))
})
