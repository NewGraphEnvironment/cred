# audit.R — audit CSV creation, updating, and risk scoring

#' Write a citation audit CSV scaffold from a directory of Rmd files
#'
#' Scans all chapter Rmd files (those beginning with four digits), extracts
#' every inline citation with paraphrase context, and writes a CSV with blank
#' columns for manual verification.
#'
#' @param rmd_dir `character(1)` directory containing Rmd files.
#'   Default `"."`.
#' @param out_file `character(1)` path for the output CSV.
#'   Default `"citation_audit.csv"`.
#' @param pattern `character(1)` regex to select Rmd files.
#'   Default `"^[0-9]{4}-.*\\.Rmd$"`.
#' @param exclude `character(1)` regex for files to skip.
#'   Default skips references, session-info, and change-log chapters.
#' @return Invisibly returns the written [tibble][tibble::tibble].
#' @export
#' @examples
#' \dontrun{
#' crd_aud_write(rmd_dir = ".", out_file = "background/citation_audit.csv")
#' }
crd_aud_write <- function(
    rmd_dir  = ".",
    out_file = "citation_audit.csv",
    pattern  = "^[0-9]{4}-.*\\.Rmd$",
    exclude  = "(references|session-info|report-change-log)") {

  chk::chk_dir(rmd_dir)
  chk::chk_string(out_file)
  chk::chk_string(pattern)
  chk::chk_string(exclude)

  rmd_files <- list.files(rmd_dir, pattern = pattern, full.names = TRUE)
  rmd_files <- rmd_files[!grepl(exclude, rmd_files)]
  rmd_files <- rmd_files[order(.chapter_order(rmd_files))]

  if (length(rmd_files) == 0L) {
    warning("No Rmd files matched in ", rmd_dir)
    return(invisible(NULL))
  }

  all_rows <- lapply(rmd_files, function(f) {
    message("Scanning: ", basename(f))
    rows <- crd_cit_ext_rmd(f)
    if (nrow(rows) == 0L) return(NULL)
    dplyr::mutate(rows,
      section       = .section_name(f),
      chapter_order = .chapter_order(f),
      .before       = 1L
    )
  })

  result <- dplyr::bind_rows(all_rows) |>
    dplyr::arrange(.data$chapter_order, .data$line_num) |>
    dplyr::distinct(.data$section, .data$citation_key, .data$paraphrase) |>
    dplyr::select("section", "citation_key", "paraphrase") |>
    dplyr::mutate(
      quote           = NA_character_,
      claim_type      = NA_character_,
      page_or_section = NA_character_,
      verified        = NA_character_,
      notes           = NA_character_
    )

  readr::write_excel_csv(result, out_file, na = "")
  message("Wrote ", nrow(result), " rows to ", out_file)
  invisible(result)
}

#' Update an existing audit CSV preserving manual columns
#'
#' Re-extracts citations from Rmd files and merges with an existing audit CSV,
#' preserving any manually filled `quote`, `claim_type`, `page_or_section`,
#' `verified`, and `notes` values. New rows are appended with blank manual
#' columns; rows no longer present in the Rmd are retained but flagged.
#'
#' @param out_file `character(1)` path to the existing audit CSV.
#' @param rmd_dir `character(1)` directory containing Rmd files.
#'   Default `"."`.
#' @inheritParams crd_aud_write
#' @return Invisibly returns the updated [tibble][tibble::tibble].
#' @export
#' @examples
#' \dontrun{
#' crd_aud_upd("background/citation_audit.csv")
#' }
crd_aud_upd <- function(
    out_file = "citation_audit.csv",
    rmd_dir  = ".",
    pattern  = "^[0-9]{4}-.*\\.Rmd$",
    exclude  = "(references|session-info|report-change-log)") {

  chk::chk_file(out_file)
  chk::chk_dir(rmd_dir)

  existing <- readr::read_csv(out_file, show_col_types = FALSE)
  manual_cols <- c("quote", "claim_type", "page_or_section", "verified", "notes")

  fresh <- crd_aud_write(
    rmd_dir  = rmd_dir,
    out_file = tempfile(fileext = ".csv"),
    pattern  = pattern,
    exclude  = exclude
  )

  merged <- dplyr::left_join(
    fresh,
    dplyr::select(existing, "section", "citation_key", "paraphrase",
                  dplyr::any_of(manual_cols)),
    by = c("section", "citation_key", "paraphrase")
  )

  readr::write_excel_csv(merged, out_file, na = "")
  n_new <- nrow(merged) - sum(!is.na(existing$verified))
  message("Updated ", out_file, " — ", nrow(merged), " rows (", n_new, " new/unverified)")
  invisible(merged)
}

#' Auto-score citation rows by hallucination risk
#'
#' Populates the `claim_type` column where it is blank based on simple
#' heuristics applied to the `paraphrase` text:
#' - `"statistic"` — contains a number, percentage, year (4-digit), or
#'   species name pattern.
#' - `"finding"` — contains words like "documented", "found", "showed",
#'   "demonstrated", "confirmed".
#' - `"context"` — everything else.
#'
#' Existing non-blank `claim_type` values are never overwritten.
#'
#' @param audit `data.frame` with at least `paraphrase` and `claim_type`
#'   columns, as produced by [crd_aud_write()].
#' @return The input `audit` with `claim_type` filled for blank rows.
#' @export
#' @examples
#' \dontrun{
#' d <- readr::read_csv("background/citation_audit.csv")
#' d <- crd_aud_scr_risk(d)
#' }
crd_aud_scr_risk <- function(audit) {
  chk::chk_data(audit)
  chk::chk_has_name(audit, "paraphrase")
  chk::chk_has_name(audit, "claim_type")

  blank <- is.na(audit$claim_type) | audit$claim_type == ""
  p <- audit$paraphrase

  statistic_pat <- "[0-9]+|%|\\b(19|20)[0-9]{2}\\b|chinook|sockeye|coho|pink|chum"
  finding_pat   <- "\\b(document|found|show|demonstrat|confirm|report|estimat|measur)\\w*\\b"

  audit$claim_type[blank & grepl(statistic_pat, p, ignore.case = TRUE)] <- "statistic"
  blank2 <- is.na(audit$claim_type) | audit$claim_type == ""
  audit$claim_type[blank2 & grepl(finding_pat, p, ignore.case = TRUE)] <- "finding"
  blank3 <- is.na(audit$claim_type) | audit$claim_type == ""
  audit$claim_type[blank3] <- "context"

  audit
}

# --- internal helpers --------------------------------------------------------

.section_name <- function(f) {
  sub("^[0-9]+-(.+)\\.Rmd$", "\\1", basename(f))
}

.chapter_order <- function(f) {
  as.integer(sub("^([0-9]+)-.*\\.Rmd$", "\\1", basename(f)))
}
