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

  readr::write_csv(result, out_file, na = "")
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
#' @param min_similarity `numeric(1)` minimum token-overlap score (0–1) for
#'   fuzzy matching when a paraphrase changes between updates. Rows that fail
#'   the exact join are matched to existing rows with the same
#'   `(section, citation_key)` by token similarity. Set to `1` to disable
#'   fuzzy matching. Default `0.4`.
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
    exclude  = "(references|session-info|report-change-log)",
    min_similarity = 0.4) {

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

  # Drop manual columns from fresh so existing values take precedence on join
  fresh_keys <- dplyr::select(fresh, "section", "citation_key", "paraphrase",
                              "sort_index")

  manual_cols_all <- c(manual_cols, "sort_index")
  merged <- dplyr::left_join(
    fresh_keys,
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
  # Ensure all manual columns exist (NA for new rows)
  for (col in manual_cols) {
    if (!col %in% names(merged)) merged[[col]] <- NA_character_
  }


  # --- Fuzzy fallback for unmatched rows ---
  # Rows that failed the exact join have all manual columns as NA.
  # Try to recover manual work from existing rows with the same

  # (section, citation_key) by token similarity on the paraphrase text.
  unmatched_idx <- which(
    is.na(merged$verified) & is.na(merged$quote) & is.na(merged$notes)
  )
  n_fuzzy <- 0L
  if (length(unmatched_idx) > 0L && min_similarity < 1) {
    # Build lookup of existing rows that have any manual work
    has_manual <- !is.na(existing$verified) | !is.na(existing$quote) |
      !is.na(existing$notes)
    existing_manual <- existing[has_manual, , drop = FALSE]

    for (i in unmatched_idx) {
      sec <- merged$section[i]
      key <- merged$citation_key[i]
      # Candidates: same section + citation_key in existing manual rows
      cand <- existing_manual[
        !is.na(existing_manual$section) & existing_manual$section == sec &
          !is.na(existing_manual$citation_key) &
          existing_manual$citation_key == key, ,
        drop = FALSE
      ]
      if (nrow(cand) == 0L) next

      tokens <- .paraphrase_tokens(merged$paraphrase[i])
      if (length(tokens) == 0L) next

      scores <- vapply(cand$paraphrase, function(p) {
        if (is.na(p)) return(0)
        .token_score(p, tokens)
      }, numeric(1L))

      best <- which.max(scores)
      if (scores[best] >= min_similarity) {
        for (col in manual_cols) {
          merged[[col]][i] <- cand[[col]][best]
        }
        n_fuzzy <- n_fuzzy + 1L
      }
    }
  }

  readr::write_csv(merged, out_file, na = "")
  n_new <- sum(is.na(merged$verified))
  parts <- paste0(nrow(merged), " rows (", n_new, " new/unverified")
  if (n_fuzzy > 0L) parts <- paste0(parts, ", ", n_fuzzy, " fuzzy-matched")
  message("Updated ", out_file, " \u2014 ", parts, ")")
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

  # Human-reviewed statuses are never overwritten regardless of overwrite_verified
  human_reviewed <- c("yes", "no", "corrected", "context")
  target_rows <- audit$citation_key == citation_key & !is.na(audit$citation_key) &
    !(audit$verified %in% human_reviewed)
  if (!overwrite_verified) {
    already_machine <- !is.na(audit$verified) & audit$verified != "" &
      !(audit$verified %in% human_reviewed)
    target_rows <- target_rows & !already_machine
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

  readr::write_csv(audit, audit_file, na = "")
  n_filled   <- sum(audit$verified[idx] == "auto",   na.rm = TRUE)
  n_nomatch  <- sum(audit$verified[idx] == "no_match", na.rm = TRUE)
  message("Done — ", n_filled, " filled, ", n_nomatch, " no_match")
  invisible(audit)
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

#' Fill quote and verified for NA rows using Zotero abstract text
#'
#' For rows where `verified` is `NA` (no source file attached in Zotero),
#' Evaluate inline R expressions in audit paraphrases
#'
#' Paraphrases extracted from Rmd source often contain unevaluated inline R
#' expressions such as `` `r format(optimum_morice, big.mark = ",")` ``.
#' These make paraphrase vs quote comparison difficult in the review app, and
#' prevent [crd_aud_score()] from detecting numeric mismatches.
#'
#' `crd_aud_eval_inline()` evaluates each expression in `env` and stores the
#' result in a `paraphrase_eval` column. On evaluation failure the expression
#' is left as-is and a warning is issued. `paraphrase` is never modified —
#' `paraphrase_eval` is display-only.
#'
#' @param audit_file `character(1)` path to the audit CSV.
#' @param env `environment` in which to evaluate inline R expressions.
#'   Default `parent.frame()` — call from a session where project variables
#'   are defined and they will be found automatically.
#' @param overwrite `logical(1)` if `TRUE`, re-evaluate rows that already have
#'   `paraphrase_eval`. Default `FALSE`.
#' @return The updated audit data frame, invisibly. Writes to `audit_file`.
#' @export
#' @examples
#' \dontrun{
#' # In a session where project variables are loaded:
#' optimum_morice <- 18175
#' crd_aud_eval_inline("background/citation_audit.csv")
#' }
crd_aud_eval_inline <- function(audit_file,
                                env       = parent.frame(),
                                overwrite = FALSE) {
  chk::chk_file(audit_file)
  chk::chk_flag(overwrite)

  d <- readr::read_csv(audit_file, show_col_types = FALSE)

  if (!"paraphrase_eval" %in% names(d)) {
    d$paraphrase_eval <- NA_character_
  }

  needs_eval <- is.na(d$paraphrase_eval) | overwrite
  needs_eval <- needs_eval & stringr::str_detect(
    d$paraphrase, stringr::fixed("`r ")
  )
  needs_eval[is.na(d$paraphrase)] <- FALSE

  n_target <- sum(needs_eval, na.rm = TRUE)
  if (n_target == 0L) {
    message("No rows with inline R expressions to evaluate.")
    return(invisible(d))
  }

  eval_one <- function(text) {
    if (is.na(text) || !stringr::str_detect(text, stringr::fixed("`r "))) return(text)
    spans <- stringr::str_extract_all(text, "`r [^`]+`")[[1]]
    for (span in spans) {
      expr <- stringr::str_remove_all(span, "^`r |`$")
      val  <- tryCatch(
        as.character(eval(parse(text = expr), envir = env)),
        error = function(e) {
          warning("Could not evaluate: ", expr, " — ", conditionMessage(e),
                  call. = FALSE)
          span
        }
      )
      text <- stringr::str_replace_all(text, stringr::fixed(span), val)
    }
    text
  }

  d$paraphrase_eval[needs_eval] <- vapply(
    d$paraphrase[needs_eval], eval_one, character(1L)
  )

  # Rows without inline R get paraphrase_eval = paraphrase
  no_inline <- !stringr::str_detect(d$paraphrase, stringr::fixed("`r ")) & is.na(d$paraphrase_eval)
  no_inline[is.na(d$paraphrase)] <- FALSE
  d$paraphrase_eval[no_inline] <- d$paraphrase[no_inline]

  n_ok   <- sum(needs_eval & !stringr::str_detect(d$paraphrase_eval, stringr::fixed("`r ")), na.rm = TRUE)
  n_fail <- n_target - n_ok
  message(
    "Evaluated inline R in ", n_ok, " row(s)",
    if (n_fail > 0L) paste0(" (", n_fail, " expression(s) could not be resolved)") else ""
  )

  readr::write_csv(d, audit_file, na = "")
  invisible(d)
}

# ---------------------------------------------------------------------------

#' Score audit rows by review priority
#'
#' Adds `review_score` (1--6) and `review_flag` columns to the audit CSV.
#' Lower scores indicate higher review priority (more likely hallucinated or
#' unsupported). Rows already scored are skipped unless `overwrite = TRUE`.
#'
#' If `paraphrase_eval` is not yet populated and paraphrases contain inline R
#' expressions, [crd_aud_eval_inline()] is called automatically with `env`.
#'
#' @section Score meanings:
#' \describe{
#'   \item{1}{`no_match`, or `auto` with numeric claim absent from quote}
#'   \item{2}{`NA` (no source), abstract with numeric claim, auto with no
#'     quote, or very weak prose overlap}
#'   \item{3}{`abstract_match` qualitative, weak prose overlap, or no tokens}
#'   \item{4}{`auto` numeric partial match or moderate prose overlap}
#'   \item{5}{`auto` strong numeric + prose match}
#'   \item{6}{Human-reviewed (`yes`, `no`, `corrected`, `context`)}
#' }
#'
#' @param audit_file `character(1)` path to the audit CSV.
#' @param env `environment` in which to evaluate inline R expressions,
#'   passed to [crd_aud_eval_inline()] when needed. Default
#'   `parent.frame()`.
#' @param ignore_years `logical(1)` if `TRUE` (default), exclude standalone
#'   4-digit years (1900--2099) from numeric claim detection. Years like
#'   "since 2020" are date references, not statistics.
#' @param overwrite `logical(1)` if `TRUE`, rescore rows that already have
#'   `review_score`. Default `FALSE`.
#' @return The updated audit data frame, invisibly. Writes to `audit_file`.
#' @export
#' @examples
#' \dontrun{
#' # After verify_all and verify_abstract:
#' crd_aud_score("background/citation_audit.csv")
#'
#' # With project variables for inline R evaluation:
#' optimum_morice <- 18175
#' crd_aud_score("background/citation_audit.csv")
#' }
crd_aud_score <- function(audit_file,
                          env          = parent.frame(),
                          ignore_years = TRUE,
                          overwrite    = FALSE) {
  chk::chk_file(audit_file)
  chk::chk_flag(ignore_years)
  chk::chk_flag(overwrite)

  d <- readr::read_csv(audit_file, show_col_types = FALSE)

  # Ensure paraphrase_eval is populated when inline R is present
  has_eval <- "paraphrase_eval" %in% names(d) &&
    any(!is.na(d$paraphrase_eval))
  has_inline_r <- any(
    stringr::str_detect(d$paraphrase, "`r "),
    na.rm = TRUE
  )

  if (!has_eval && has_inline_r) {
    message("Evaluating inline R expressions ...")
    d <- crd_aud_eval_inline(audit_file, env = env)
  }

  # Use paraphrase_eval if available, fall back to paraphrase
  para_col <- if ("paraphrase_eval" %in% names(d)) {
    dplyr::coalesce(d$paraphrase_eval, d$paraphrase)
  } else {
    d$paraphrase
  }

  if (!"review_score" %in% names(d)) {
    d$review_score <- NA_integer_
    d$review_flag  <- NA_character_
  }

  needs_score <- is.na(d$review_score) | overwrite
  n_target <- sum(needs_score, na.rm = TRUE)

  if (n_target == 0L) {
    message("No rows to score.")
    return(invisible(d))
  }

  for (i in which(needs_score)) {
    result <- .score_row(
      verified     = d$verified[i],
      paraphrase   = para_col[i],
      quote_text   = d$quote[i],
      ignore_years = ignore_years
    )
    d$review_score[i] <- result$score
    d$review_flag[i]  <- result$flag
  }

  readr::write_csv(d, audit_file, na = "")

  score_tbl <- table(d$review_score[needs_score])
  message(
    "Scored ", n_target, " rows: ",
    paste(names(score_tbl), score_tbl, sep = "=", collapse = ", ")
  )

  invisible(d)
}

# --- scoring internals ------------------------------------------------------

#' Score a single audit row
#' @noRd
.score_row <- function(verified, paraphrase, quote_text, ignore_years = TRUE) {
  human <- c("yes", "no", "corrected", "context")

  if (!is.na(verified) && verified %in% human)
    return(list(score = 6L, flag = "human_reviewed"))

  if (is.na(verified))
    return(list(score = 2L, flag = "no_source"))

  if (verified == "no_match")
    return(list(score = 1L, flag = "no_match_found"))

  if (verified == "abstract_match") {
    p_nums <- .score_claim_nums(paraphrase, ignore_years)
    if (length(p_nums) > 0L)
      return(list(score = 2L, flag = "abstract_only_numeric_claim"))
    return(list(score = 3L, flag = "abstract_only_qualitative"))
  }

  if (verified == "auto") {
    if (is.na(quote_text) || quote_text == "")
      return(list(score = 2L, flag = "auto_no_quote"))

    p_nums <- .score_claim_nums(paraphrase, ignore_years)
    q_nums <- .score_num_tokens(quote_text)

    if (length(p_nums) > 0L) {
      matched <- sum(p_nums %in% q_nums)
      frac    <- matched / length(p_nums)

      if (frac == 0) {
        return(list(
          score = 1L,
          flag  = paste0("num_mismatch(", paste(p_nums, collapse = ","), ")")
        ))
      }
      if (frac < 0.5) {
        return(list(
          score = 2L,
          flag  = paste0("num_partial(", matched, "/", length(p_nums), ")")
        ))
      }
      # Full or majority numeric match — check prose reinforcement
      p_words <- .score_word_tokens(paraphrase)
      q_words <- .score_word_tokens(quote_text)
      if (length(p_words) > 0L &&
            sum(p_words %in% q_words) / length(p_words) >= 0.3)
        return(list(score = 5L, flag = "num_match_strong"))
      return(list(score = 4L, flag = "num_match"))
    }

    # Qualitative: word overlap only
    p_words <- .score_word_tokens(paraphrase)
    q_words <- .score_word_tokens(quote_text)
    if (length(p_words) == 0L) return(list(score = 3L, flag = "no_tokens"))
    overlap <- sum(p_words %in% q_words) / length(p_words)

    if (overlap >= 0.4)  return(list(score = 5L, flag = "prose_strong"))
    if (overlap >= 0.25) return(list(score = 4L, flag = "prose_moderate"))
    if (overlap >= 0.1)  return(list(score = 3L, flag = "prose_weak"))
    return(list(score = 2L, flag = "prose_very_weak"))
  }

  list(score = 3L, flag = "unknown")
}

#' Extract numeric tokens from text
#' @noRd
.score_num_tokens <- function(text) {
  if (is.na(text) || text == "") return(character(0L))
  stringr::str_extract_all(text, "[0-9]+(?:[.,][0-9]+)*")[[1L]]
}

#' Extract word tokens (>= 4 chars) from text, stripping citekeys and R inline
#' @noRd
.score_word_tokens <- function(text) {
  if (is.na(text) || text == "") return(character(0L))
  clean <- stringr::str_remove_all(text, "`r[^`]*`")
  clean <- stringr::str_remove_all(clean, "@[A-Za-z][A-Za-z0-9_:./-]+")
  clean <- stringr::str_remove_all(clean, "\\\\@ref\\([^)]*\\)")
  stringr::str_extract_all(tolower(clean), "[a-z]{4,}")[[1L]]
}

#' Extract numeric tokens that represent claims (not years)
#' @noRd
.score_claim_nums <- function(text, ignore_years = TRUE) {
  toks <- .score_num_tokens(text)
  if (ignore_years) {
    toks <- toks[!grepl("^(19|20)[0-9]{2}$", toks)]
  }
  toks
}

# ---------------------------------------------------------------------------

#' queries the local Zotero database for the abstract of each cited item and
#' scores it against the `paraphrase` using token overlap. Rows that score at
#' or above `min_score` receive `verified = "abstract_match"` and the abstract
#' text as their `quote`.
#'
#' Abstract matching confirms the citation is plausibly in the right domain
#' but cannot verify a specific quote from the body of the paper. A hit means
#' the cited source covers the general topic of the claim; a miss does not
#' mean the citation is wrong — the claim may simply not appear in the abstract.
#'
#' @param audit_file `character(1)` path to the audit CSV.
#' @param zotero_dir `character(1)` path to the Zotero data directory.
#'   Default `"~/Zotero"`.
#' @param min_score `numeric(1)` token overlap threshold. Default `0.2`.
#' @param overwrite_verified `logical(1)` if `TRUE`, reprocess existing
#'   `"abstract_match"` rows. Never overwrites human-reviewed rows
#'   (`yes`, `no`, `corrected`, `context`). Default `FALSE`.
#' @return The updated audit data frame, invisibly. Writes to `audit_file`.
#' @export
#' @examples
#' \dontrun{
#' crd_aud_verify_abstract("background/citation_audit.csv")
#' }
crd_aud_verify_abstract <- function(audit_file,
                                    zotero_dir        = "~/Zotero",
                                    min_score         = 0.2,
                                    overwrite_verified = FALSE) {
  chk::chk_file(audit_file)
  chk::chk_string(zotero_dir)
  chk::chk_number(min_score)
  chk::chk_flag(overwrite_verified)

  audit <- readr::read_csv(audit_file, show_col_types = FALSE)

  human_reviewed <- c("yes", "no", "corrected", "context")

  target_rows <- (is.na(audit$verified) |
    (overwrite_verified & !is.na(audit$verified) & audit$verified == "abstract_match")) &
    !(audit$verified %in% human_reviewed | is.na(audit$citation_key))

  if (!any(target_rows, na.rm = TRUE)) {
    message("No NA rows to process.")
    return(invisible(audit))
  }

  target_keys <- unique(audit$citation_key[target_rows])
  abstracts   <- suppressWarnings(
    crd_zot_abstract_lookup(target_keys, zotero_dir = zotero_dir)
  )

  n_matched    <- 0L
  n_no_abstract <- 0L

  for (key in target_keys) {
    abs_row <- abstracts[abstracts$citation_key == key, , drop = FALSE]
    if (nrow(abs_row) == 0L || is.na(abs_row$abstract)) {
      n_no_abstract <- n_no_abstract + 1L
      next
    }
    abstract_text <- abs_row$abstract

    row_idx <- which(target_rows & !is.na(audit$citation_key) &
                       audit$citation_key == key)
    for (i in row_idx) {
      tokens <- .paraphrase_tokens(audit$paraphrase[i])
      if (length(tokens) == 0L) next
      score <- .token_score(abstract_text, tokens)
      if (score >= min_score) {
        audit$quote[i]           <- abstract_text
        audit$page_or_section[i] <- "abstract"
        audit$verified[i]        <- "abstract_match"
        n_matched <- n_matched + 1L
      }
    }
  }

  readr::write_csv(audit, audit_file, na = "")
  message(
    "Abstract matching: ", n_matched, " matched, ",
    n_no_abstract, " keys with no abstract in Zotero."
  )

  invisible(audit)
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
