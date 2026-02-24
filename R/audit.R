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
      notes           = NA_character_,
      sort_index      = seq_len(dplyr::n())
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

  manual_cols_all <- c(manual_cols, "sort_index")
  merged <- dplyr::left_join(
    fresh,
    dplyr::select(existing, "section", "citation_key", "paraphrase",
                  dplyr::any_of(manual_cols_all)),
    by = c("section", "citation_key", "paraphrase")
  )
  # Restore sort_index from existing where present; new rows keep their fresh value
  if ("sort_index.x" %in% names(merged)) {
    merged$sort_index <- dplyr::coalesce(merged$sort_index.y, merged$sort_index.x)
    merged$sort_index.x <- NULL
    merged$sort_index.y <- NULL
  }

  readr::write_excel_csv(merged, out_file, na = "")
  n_new <- nrow(merged) - sum(!is.na(existing$verified))
  message("Updated ", out_file, " — ", nrow(merged), " rows (", n_new, " new/unverified)")
  invisible(merged)
}

#' Auto-score citation rows by hallucination risk
#'
#' Populates the `claim_type` column where it is blank, based on simple
#' heuristics applied to the `paraphrase` text:
#'
#' - `"statistic"` — contains a number, percentage, or 4-digit year
#'   (highest hallucination risk — verify these first).
#' - `"finding"` — contains words like "documented", "found", "showed",
#'   "demonstrated", "confirmed".
#' - `"context"` — everything else (lowest risk).
#'
#' Existing non-blank `claim_type` values are never overwritten.
#'
#' @param audit `data.frame` with at least `paraphrase` and `claim_type`
#'   columns, as produced by [crd_aud_write()].
#' @param statistic_extra `character(1)` optional additional regex pattern
#'   ORed into the statistic detector. Use this to flag domain-specific terms
#'   as statistics — e.g. `"chinook|sockeye|coho"` for salmonid reports, or
#'   `"glucose|insulin"` for medical papers. Default `NULL` (no extras).
#' @return The input `audit` with `claim_type` filled for blank rows.
#' @export
#' @examples
#' d <- data.frame(
#'   paraphrase = c("Embeddedness exceeded 25% at 38% of sites.",
#'                  "The study demonstrated reduced survival.",
#'                  "See also the watershed context."),
#'   claim_type = NA_character_
#' )
#' crd_aud_scr_risk(d)
#'
#' # Flag species names as statistics for a salmonid report
#' crd_aud_scr_risk(d, statistic_extra = "chinook|sockeye|coho|pink|chum")
crd_aud_scr_risk <- function(audit, statistic_extra = NULL) {
  chk::chk_data(audit)
  chk::check_names(audit, c("paraphrase", "claim_type"))
  if (!is.null(statistic_extra)) chk::chk_string(statistic_extra)

  blank <- is.na(audit$claim_type) | audit$claim_type == ""
  p <- audit$paraphrase

  base_stat_pat <- "[0-9]+|%|\\b(19|20)[0-9]{2}\\b"
  statistic_pat <- if (!is.null(statistic_extra)) {
    paste0(base_stat_pat, "|", statistic_extra)
  } else {
    base_stat_pat
  }
  finding_pat <- "\\b(document|found|show|demonstrat|confirm|report|estimat|measur)\\w*\\b"

  audit$claim_type[blank & grepl(statistic_pat, p, ignore.case = TRUE)] <- "statistic"
  blank2 <- is.na(audit$claim_type) | audit$claim_type == ""
  audit$claim_type[blank2 & grepl(finding_pat, p, ignore.case = TRUE)] <- "finding"
  blank3 <- is.na(audit$claim_type) | audit$claim_type == ""
  audit$claim_type[blank3] <- "context"

  audit
}

#' Verify all citation keys in an audit CSV against their source documents
#'
#' Convenience wrapper around [crd_zot_src_lookup()] and [crd_aud_fill_src()].
#' For each citation key in the audit CSV that has a resolvable Zotero
#' attachment, loads the source document once and fills `quote`,
#' `page_or_section`, and `verified` columns for all matching rows.
#'
#' Keys with no Zotero attachment are skipped with a warning. Keys already
#' fully verified are skipped unless `overwrite_verified = TRUE`.
#'
#' @param audit_file `character(1)` path to the audit CSV.
#' @param sources `data.frame` as returned by [crd_zot_src_lookup()], with
#'   columns `citation_key`, `src_path`, `src_type`. If `NULL` (default),
#'   all unique keys in `audit_file` are looked up automatically via
#'   [crd_zot_src_lookup()].
#' @param zotero_dir `character(1)` Zotero data directory, passed to
#'   [crd_zot_src_lookup()] when `sources` is `NULL`. Default `"~/Zotero"`.
#' @param min_score `numeric(1)` passed to [crd_aud_fill_src()].
#'   Default `0.2`.
#' @param overwrite_verified `logical(1)` passed to [crd_aud_fill_src()].
#'   Default `FALSE`.
#' @return Invisibly returns the final audit [tibble][tibble::tibble].
#' @export
#' @examples
#' \dontrun{
#' crd_aud_verify_all("background/citation_audit.csv")
#' }
crd_aud_verify_all <- function(
    audit_file,
    sources            = NULL,
    zotero_dir         = "~/Zotero",
    min_score          = 0.2,
    overwrite_verified = FALSE) {

  chk::chk_file(audit_file)
  chk::chk_string(zotero_dir)
  chk::chk_number(min_score)
  chk::chk_flag(overwrite_verified)

  audit <- readr::read_csv(audit_file, show_col_types = FALSE)
  all_keys <- unique(audit$citation_key[!is.na(audit$citation_key)])

  if (is.null(sources)) {
    message("Looking up ", length(all_keys), " citation keys in Zotero ...")
    sources <- crd_zot_src_lookup(all_keys, zotero_dir = zotero_dir)
  } else {
    chk::chk_data(sources)
    chk::check_names(sources, c("citation_key", "src_path", "src_type"))
  }

  if (nrow(sources) == 0L) {
    message("No sources resolved — nothing to do.")
    return(invisible(audit))
  }

  for (i in seq_len(nrow(sources))) {
    key      <- sources$citation_key[i]
    path     <- sources$src_path[i]
    src_type <- sources$src_type[i]

    message(sprintf("[%d/%d] Loading source for %s (%s) ...",
                    i, nrow(sources), key, src_type))

    src <- tryCatch(
      if (src_type == "docx") crd_docx_ext_txt(path) else crd_pdf_ext_txt(path),
      error = function(e) {
        warning("Failed to load source for ", key, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(src)) next

    crd_aud_fill_src(
      audit_file         = audit_file,
      src                = src,
      citation_key       = key,
      min_score          = min_score,
      overwrite_verified = overwrite_verified
    )
  }

  invisible(readr::read_csv(audit_file, show_col_types = FALSE))
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

#' Sort an audit CSV for review and write it back
#'
#' Rearranges the rows of an audit CSV to support different review workflows,
#' then writes the result back to the same file. The `sort_index` column
#' (set at write time) always allows restoration to report order.
#'
#' @section Verified status order for `by = "status"`:
#' Rows are grouped: `NA` (unseen) → `"no_match"` → `"auto"` →
#' `"corrected"` → `"no"` → `"context"` → `"yes"`. Within each group,
#' rows are ordered by `sort_index`. This puts the most-needing-review
#' rows first.
#'
#' @param audit_file `character(1)` path to the audit CSV.
#' @param by `character(1)` sort strategy. One of:
#'   - `"report"` — restore to original report order (`sort_index`).
#'   - `"status"` — group by verification status, worst-first, then
#'     `sort_index` within each group.
#'   - `"key"` — alphabetical by `citation_key`, then `sort_index`.
#' @return Invisibly returns the sorted [tibble][tibble::tibble].
#' @export
#' @examples
#' \dontrun{
#' # Group unverified rows first for review
#' crd_aud_sort("background/citation_audit.csv", by = "status")
#'
#' # Restore report order when done
#' crd_aud_sort("background/citation_audit.csv", by = "report")
#' }
crd_aud_sort <- function(audit_file, by = c("report", "status", "key")) {
  chk::chk_file(audit_file)
  by <- match.arg(by)

  d <- readr::read_csv(audit_file, show_col_types = FALSE)

  if (!"sort_index" %in% names(d)) {
    stop("`sort_index` column not found. Re-generate the audit CSV with ",
         "crd_aud_write() to add it.")
  }

  # auto first — has quotes to check; NA last — nothing to review without source
  status_levels <- c("auto", "no_match", "corrected", "no", "context", "yes", NA)

  d <- switch(by,
    report = dplyr::arrange(d, .data$sort_index),
    status = {
      d$status_order <- match(d$verified, status_levels[!is.na(status_levels)])
      d$status_order <- ifelse(is.na(d$verified), 0L, d$status_order)
      dplyr::arrange(d, .data$status_order, .data$sort_index) |>
        dplyr::select(-"status_order")
    },
    key = dplyr::arrange(d, .data$citation_key, .data$sort_index)
  )

  readr::write_excel_csv(d, audit_file, na = "")
  message("Sorted by '", by, "' and wrote ", nrow(d), " rows to ", audit_file)
  invisible(d)
}

#' Summarise an audit CSV by verification status
#'
#' Prints a three-part snapshot to the console:
#' 1. Overall row counts by `verified` status.
#' 2. Sources with `NA` status (no Zotero attachment) ranked by claim count —
#'    your PDF attachment priority list.
#' 3. Sources with `"no_match"` status (attachment exists but paraphrase did
#'    not match) ranked by claim count.
#'
#' @param audit_file `character(1)` path to the audit CSV produced by
#'   [crd_aud_write()].
#' @return Invisibly returns a named list with tibbles `status`,
#'   `na_sources`, and `no_match_sources`.
#' @export
#' @examples
#' \dontrun{
#' crd_aud_summary("background/citation_audit.csv")
#' }
crd_aud_summary <- function(audit_file) {
  chk::chk_file(audit_file)

  d <- readr::read_csv(audit_file, show_col_types = FALSE)

  status_counts <- d |>
    dplyr::mutate(status = ifelse(is.na(.data$verified), "(NA)", .data$verified)) |>
    dplyr::count(.data$status) |>
    dplyr::arrange(dplyr::desc(.data$n))

  na_sources <- d |>
    dplyr::filter(is.na(.data$verified)) |>
    dplyr::count(.data$citation_key, sort = TRUE)

  no_match_sources <- d |>
    dplyr::filter(!is.na(.data$verified), .data$verified == "no_match") |>
    dplyr::count(.data$citation_key, sort = TRUE)

  cat("=== Citation Audit Summary ===\n")
  cat("File:", audit_file, "\n")
  cat("Total rows:", nrow(d), "\n\n")

  cat("-- Status breakdown --\n")
  print(status_counts, n = Inf)

  cat("\n-- NA sources (no Zotero attachment) ranked by claim count --\n")
  cat("   Attach PDFs for these to unlock auto-verification.\n")
  if (nrow(na_sources) == 0L) {
    cat("  (none)\n")
  } else {
    print(na_sources, n = Inf)
  }

  cat("\n-- no_match sources ranked by claim count --\n")
  cat("   Attachment found but paraphrase did not score above threshold.\n")
  if (nrow(no_match_sources) == 0L) {
    cat("  (none)\n")
  } else {
    print(no_match_sources, n = Inf)
  }

  invisible(list(
    status           = status_counts,
    na_sources       = na_sources,
    no_match_sources = no_match_sources
  ))
}

#' Format an audit CSV as a readable Excel workbook
#'
#' Writes a `.xlsx` version of the audit CSV with formatting optimised for
#' manual review: fixed row height (so rows don't expand to full paragraph
#' height), wide columns for `paraphrase` and `quote`, frozen header row,
#' auto-filter, and colour-coded `verified` status cells.
#'
#' Open the `.xlsx` in Excel or Numbers. Click any `paraphrase` or `quote`
#' cell to read the full text in the formula bar. Set `verified` to
#' `yes` / `no` / `corrected` directly in the workbook, then save and
#' re-import edits to the CSV manually, or continue editing the CSV directly.
#'
#' @param audit_file `character(1)` path to the audit CSV produced by
#'   [crd_aud_write()].
#' @param out_file `character(1)` output `.xlsx` path. Default replaces
#'   the `.csv` extension with `.xlsx` in the same directory.
#' @return Invisibly returns `out_file`.
#' @export
#' @examples
#' \dontrun{
#' crd_aud_fmt_xlsx("background/citation_audit.csv")
#' }
crd_aud_fmt_xlsx <- function(audit_file, out_file = NULL) {
  chk::chk_file(audit_file)

  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package 'openxlsx' is required. Install with: pak::pak('openxlsx')")
  }

  if (is.null(out_file)) {
    out_file <- sub("\\.csv$", ".xlsx", audit_file)
  }

  d <- readr::read_csv(audit_file, show_col_types = FALSE)

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "citation_audit")

  # --- column widths (Excel units ≈ chars) ---
  col_widths <- c(
    section         = 14,
    citation_key    = 28,
    paraphrase      = 52,
    quote           = 52,
    claim_type      = 12,
    page_or_section = 14,
    verified        = 11,
    notes           = 30,
    sort_index      =  9
  )
  # Apply in column order of d
  widths <- vapply(names(d), function(n) {
    if (n %in% names(col_widths)) col_widths[[n]] else 14
  }, numeric(1))
  openxlsx::setColWidths(wb, 1, cols = seq_along(d), widths = widths)

  # --- styles ---
  header_style <- openxlsx::createStyle(
    fontName   = "Aptos Narrow",
    fontSize   = 11,
    fontColour = "white",
    fgFill     = "#1a1a1a",
    halign     = "left",
    textDecoration = "bold",
    wrapText   = TRUE
  )
  wrap_style <- openxlsx::createStyle(
    fontName = "Aptos Narrow",
    fontSize = 10,
    wrapText = TRUE,
    valign   = "top"
  )
  # verified colour map
  status_colours <- c(
    "auto"      = "#FFF2CC",  # yellow  — awaiting review
    "yes"       = "#D9EAD3",  # green   — confirmed
    "no"        = "#F4CCCC",  # red     — not supported
    "corrected" = "#FCE5CD",  # orange  — fixed in Rmd
    "no_match"  = "#E2EFDA",  # light green — no match found
    "context"   = "#CFE2F3"   # blue    — context citation
  )

  # --- write data ---
  openxlsx::writeData(wb, 1, d, headerStyle = header_style)

  # body wrap style for all cells
  openxlsx::addStyle(wb, 1, wrap_style,
    rows = seq(2, nrow(d) + 1), cols = seq_along(d), gridExpand = TRUE
  )

  # colour verified column
  verified_col <- which(names(d) == "verified")
  for (status in names(status_colours)) {
    rows_match <- which(d$verified == status) + 1L  # +1 for header
    if (length(rows_match) == 0L) next
    cell_style <- openxlsx::createStyle(
      fontName = "Aptos Narrow",
      fontSize = 10,
      fgFill   = status_colours[[status]],
      wrapText = TRUE,
      valign   = "top"
    )
    openxlsx::addStyle(wb, 1, cell_style,
      rows = rows_match, cols = verified_col, gridExpand = FALSE
    )
  }

  # --- fixed row height (prevents auto-expand to paragraph height) ---
  # Header taller; data rows fixed at 42pt — readable without being huge
  openxlsx::setRowHeights(wb, 1, rows = 1L, heights = 22)
  openxlsx::setRowHeights(wb, 1, rows = seq(2, nrow(d) + 1), heights = 42)

  # --- freeze header + auto-filter ---
  openxlsx::freezePane(wb, 1, firstRow = TRUE)
  openxlsx::addFilter(wb, 1, row = 1, cols = seq_along(d))

  openxlsx::saveWorkbook(wb, out_file, overwrite = TRUE)
  message("Wrote formatted workbook to ", out_file)
  invisible(out_file)
}

# --- internal helpers --------------------------------------------------------

.section_name <- function(f) {
  sub("^[0-9]+-(.+)\\.Rmd$", "\\1", basename(f))
}

.chapter_order <- function(f) {
  as.integer(sub("^([0-9]+)-.*\\.Rmd$", "\\1", basename(f)))
}
