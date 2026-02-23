# rmd.R — functions for reading and processing R Markdown files

#' Strip fenced code chunks from a character vector of lines
#'
#' Replaces every line inside a ```` ``` ````...```` ``` ```` fenced block
#' (including the fence lines themselves) with an empty string, so that
#' citation-key patterns inside code are not matched.
#'
#' @param lines `character` vector of lines from an Rmd file.
#' @return `character` vector the same length as `lines`, with code-chunk
#'   lines replaced by `""`.
#' @export
#' @examples
#' lines <- c("text", "```r", "@key", "```", "more text")
#' crd_chnk_strip(lines)
crd_chnk_strip <- function(lines) {
  chk::chk_character(lines)
  in_chunk <- FALSE
  for (i in seq_along(lines)) {
    if (grepl("^```", lines[i])) {
      in_chunk <- !in_chunk
      lines[i] <- ""
    } else if (in_chunk) {
      lines[i] <- ""
    }
  }
  lines
}

#' Extract citations with paraphrase context from an Rmd file
#'
#' Reads an Rmd file, strips code chunks, then finds every `@citekey`
#' occurrence and returns the surrounding sentence as a paraphrase.
#' Each unique (line, key) combination produces one row; duplicate
#' (key, paraphrase) pairs within a file are dropped.
#'
#' @param rmd_file `character(1)` path to an `.Rmd` file.
#' @param min_key_chars `integer(1)` minimum citation key length to keep.
#'   Shorter matches are likely false positives (e.g. stray `@r`).
#'   Default `8L`.
#' @return A [tibble][tibble::tibble] with columns `line_num`
#'   (`integer`), `citation_key` (`character`), `paraphrase`
#'   (`character`).
#' @export
#' @examples
#' \dontrun{
#' crd_cit_ext_rmd("0300-exploitation.Rmd")
#' }
crd_cit_ext_rmd <- function(rmd_file, min_key_chars = 8L) {
  chk::chk_file(rmd_file)
  chk::chk_whole_number(min_key_chars)
  chk::chk_gt(min_key_chars, 0L)

  lines <- readLines(rmd_file, warn = FALSE, encoding = "UTF-8")
  lines <- crd_chnk_strip(lines)

  key_pat <- "@([A-Za-z][A-Za-z0-9_:./-]+)"
  rows <- list()

  for (i in seq_along(lines)) {
    line <- lines[i]
    m <- stringr::str_match_all(line, key_pat)[[1]]
    if (nrow(m) == 0L) next

    keys <- m[, 2L]
    keys <- gsub("[.,:;!?]+$", "", keys)
    keys <- keys[nchar(keys) >= min_key_chars]
    if (length(keys) == 0L) next

    for (key in unique(keys)) {
      rows[[length(rows) + 1L]] <- tibble::tibble(
        line_num     = i,
        citation_key = key,
        paraphrase   = crd_sent_ext_key(line, key)
      )
    }
  }

  if (length(rows) == 0L) {
    return(tibble::tibble(
      line_num     = integer(),
      citation_key = character(),
      paraphrase   = character()
    ))
  }
  dplyr::bind_rows(rows)
}

#' Replace scalar inline R expressions in a string
#'
#' Searches for `` `r <expr>` `` patterns where `<expr>` is a simple
#' `format(var, ...)` or bare variable name, looks up `var` from
#' scalar assignments (`var <- value`) in the same file, and substitutes
#' the formatted value. Non-scalar or unresolvable expressions are left
#' unchanged.
#'
#' @param text `character(1)` string potentially containing inline R.
#' @param rmd_file `character(1)` path to the Rmd file to scan for
#'   scalar assignments.
#' @return `character(1)` with resolvable inline expressions substituted.
#' @export
#' @examples
#' \dontrun{
#' crd_inl_rend(
#'   "optimum was `r format(optimum_lower, big.mark = \",\")`",
#'   "0100-intro.Rmd"
#' )
#' }
crd_inl_rend <- function(text, rmd_file) {
  chk::chk_string(text)
  chk::chk_file(rmd_file)

  lines <- readLines(rmd_file, warn = FALSE, encoding = "UTF-8")

  # Build lookup of scalar assignments: var <- number
  scalars <- list()
  assign_pat <- "^\\s*([A-Za-z][A-Za-z0-9_.]*) <- ([0-9]+(?:\\.[0-9]+)?)\\s*$"
  for (ln in lines) {
    m <- regmatches(ln, regexec(assign_pat, ln))[[1]]
    if (length(m) == 4L) scalars[[m[2L]]] <- as.numeric(m[3L])
  }

  # Replace `r format(var, big.mark = ",")` and `r var`
  inline_pat <- "`r ([^`]+)`"
  gsub(inline_pat, function(expr_raw) {
    expr <- sub("`r ([^`]+)`", "\\1", expr_raw)
    # bare variable
    if (expr %in% names(scalars)) {
      return(format(scalars[[expr]], big.mark = ","))
    }
    # format(var, big.mark = ",") style
    m <- regmatches(expr, regexec("^format\\(([A-Za-z][A-Za-z0-9_.]*)", expr))[[1]]
    if (length(m) == 2L && m[2L] %in% names(scalars)) {
      return(format(scalars[[m[2L]]], big.mark = ","))
    }
    expr_raw  # leave unchanged
  }, text, perl = TRUE)
}
