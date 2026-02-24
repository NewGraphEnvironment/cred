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

#' Fill audit CSV quote and location columns from a source document
#'
#' For each unverified row matching `citation_key`, searches `src` (a tibble
#' from [crd_docx_ext_txt()] or [crd_pdf_ext_txt()]) for the best-matching
#' passage using the `paraphrase` column as the query. Fills:
#' - `quote` — best-matching passage text
#' - `page_or_section` — `doc_index` (docx) or `page` (pdf) of the match
#' - `verified` — `"auto"` when a match meets `min_score`; `"no_match"` otherwise
#'
#' Rows where `verified` is already non-blank are skipped unless
#' `overwrite_verified = TRUE`. The updated CSV is written back to `audit_file`.
#'
#' @param audit_file `character(1)` path to the audit CSV produced by
#'   [crd_aud_write()].
#' @param src `data.frame` as returned by [crd_docx_ext_txt()] or
#'   [crd_pdf_ext_txt()]. Source type is inferred from column names
#'   (`doc_index` = docx, `page` = pdf).
#' @param citation_key `character(1)` citation key to process. Rows whose
#'   `citation_key` column equals this value are searched.
#' @param n_results `integer(1)` number of top passages to consider per row.
#'   Only the top-scoring passage is written to `quote`. Default `1L`.
#' @param min_score `numeric(1)` minimum token-match score to accept as a
#'   match. Default `0.2`.
#' @param overwrite_verified `logical(1)` if `TRUE`, re-fill rows even if
#'   `verified` is already set. Default `FALSE`.
#' @return Invisibly returns the updated audit [tibble][tibble::tibble].
#' @export
#' @examples
#' \dontrun{
#' doc <- crd_docx_ext_txt("background/price_etal2026.docx")
#' crd_aud_fill_src("background/citation_audit.csv", doc,
#'                  citation_key = "price_etal2026rebuildinggiis")
#' }
crd_aud_fill_src <- function(
    audit_file,
    src,
    citation_key,
    n_results           = 1L,
    min_score           = 0.2,
    overwrite_verified  = FALSE) {

  chk::chk_file(audit_file)
  chk::chk_data(src)
  chk::chk_string(citation_key)
  chk::chk_whole_number(n_results)
  chk::chk_number(min_score)
  chk::chk_flag(overwrite_verified)

  # Detect source type
  if ("doc_index" %in% names(src)) {
    src_type <- "docx"
    loc_col  <- "doc_index"
  } else if ("page" %in% names(src)) {
    src_type <- "pdf"
    loc_col  <- "page"
  } else {
    stop("`src` must have a `doc_index` (docx) or `page` (pdf) column.")
  }

  audit <- readr::read_csv(audit_file, show_col_types = FALSE)

  target_rows <- audit$citation_key == citation_key & !is.na(audit$citation_key)
  if (!overwrite_verified) {
    already_done <- !is.na(audit$verified) & audit$verified != ""
    target_rows  <- target_rows & !already_done
  }

  n_target <- sum(target_rows)
  if (n_target == 0L) {
    message("No unverified rows found for citation_key = ", citation_key)
    return(invisible(audit))
  }

  message("Filling ", n_target, " rows for ", citation_key, " ...")

  idx <- which(target_rows)
  for (i in idx) {
    para <- audit$paraphrase[i]
    if (is.na(para) || para == "") {
      audit$verified[i] <- "no_match"
      next
    }

    res <- if (src_type == "docx") {
      crd_docx_srch_clm(src, para, n_results = n_results, min_score = min_score)
    } else {
      crd_pdf_srch_clm(src, para, n_results = n_results, min_score = min_score)
    }

    if (nrow(res) == 0L) {
      audit$verified[i]        <- "no_match"
    } else {
      audit$quote[i]           <- res[[if (src_type == "docx") "text" else "passage"]][1L]
      audit$page_or_section[i] <- as.character(res[[loc_col]][1L])
      audit$verified[i]        <- "auto"
    }
  }

  readr::write_excel_csv(audit, audit_file, na = "")
  n_filled   <- sum(audit$verified[idx] == "auto",   na.rm = TRUE)
  n_nomatch  <- sum(audit$verified[idx] == "no_match", na.rm = TRUE)
  message("Done — ", n_filled, " filled, ", n_nomatch, " no_match")
  invisible(audit)
}

# --- internal helpers --------------------------------------------------------

.section_name <- function(f) {
  sub("^[0-9]+-(.+)\\.Rmd$", "\\1", basename(f))
}

.chapter_order <- function(f) {
  as.integer(sub("^([0-9]+)-.*\\.Rmd$", "\\1", basename(f)))
}
