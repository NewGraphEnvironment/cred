# docx.R — Word document text extraction and claim search

#' Extract text from a Word document as a tidy tibble
#'
#' Reads a `.docx` file using [officer::read_docx()] and returns the full
#' document content as a tidy [tibble][tibble::tibble]. Each row is one
#' paragraph or table cell, with the heading style preserved so callers
#' can filter by section.
#'
#' @param docx_path `character(1)` path to a `.docx` file.
#' @return A [tibble][tibble::tibble] with columns:
#'   - `doc_index` (`integer`) — paragraph index in the document.
#'   - `content_type` (`character`) — `"paragraph"`, `"table cell"`, etc.
#'   - `style_name` (`character`) — Word style (e.g. `"Heading 1"`,
#'     `"Normal"`).
#'   - `text` (`character`) — paragraph text.
#'   - `level` (`integer`) — heading level (`NA` for body text).
#' @export
#' @examples
#' \dontrun{
#' doc <- crd_docx_ext_txt("background/price_etal2026.docx")
#' dplyr::filter(doc, style_name == "Heading 1")
#' }
crd_docx_ext_txt <- function(docx_path) {
  chk::chk_file(docx_path)
  chk::chk_string(docx_path)

  doc <- officer::read_docx(docx_path)
  raw <- officer::docx_summary(doc)

  tibble::tibble(
    doc_index    = as.integer(raw$doc_index),
    content_type = as.character(raw$content_type),
    style_name   = as.character(raw$style_name),
    text         = as.character(raw$text),
    level        = if ("level" %in% names(raw)) as.integer(raw$level) else NA_integer_
  )
}

#' Search a Word document for the best-matching passage to a paraphrase
#'
#' Converts a paraphrase to search tokens (stripping citation keys and
#' markdown), then scores each paragraph in the document by the proportion
#' of tokens found. Returns the top `n_results` matching paragraphs with
#' their document index and style.
#'
#' @param docx_txt `data.frame` as returned by [crd_docx_ext_txt()].
#' @param paraphrase `character(1)` paraphrase text from the audit CSV.
#' @param n_results `integer(1)` number of top matches to return.
#'   Default `3L`.
#' @param min_score `numeric(1)` minimum token-match proportion to
#'   include. Default `0.2`.
#' @return A [tibble][tibble::tibble] with columns `doc_index`,
#'   `style_name`, `text`, `score`, ordered by descending score.
#'   Returns zero rows if no match exceeds `min_score`.
#' @export
#' @examples
#' \dontrun{
#' doc <- crd_docx_ext_txt("background/price_etal2026.docx")
#' crd_docx_srch_clm(doc, "beaver dams moderate summer stream temperatures")
#' }
crd_docx_srch_clm <- function(docx_txt, paraphrase, n_results = 3L, min_score = 0.2) {
  chk::chk_data(docx_txt)
  chk::chk_string(paraphrase)
  chk::chk_whole_number(n_results)
  chk::chk_number(min_score)

  tokens <- .paraphrase_tokens(paraphrase)
  if (length(tokens) == 0L) return(.empty_srch_result())

  body <- dplyr::filter(docx_txt, .data$content_type == "paragraph",
                        nchar(.data$text) > 10L)

  scores <- vapply(body$text, function(txt) {
    .token_score(txt, tokens)
  }, numeric(1L))

  body$score <- scores
  result <- dplyr::filter(body, .data$score >= min_score) |>
    dplyr::arrange(dplyr::desc(.data$score)) |>
    dplyr::slice_head(n = n_results) |>
    dplyr::select("doc_index", "style_name", "text", "score")

  result
}

# --- internal helpers --------------------------------------------------------

.paraphrase_tokens <- function(paraphrase) {
  # Strip @citekeys, markdown syntax, numbers-only tokens, short words
  clean <- gsub("@[A-Za-z][A-Za-z0-9_:./-]+", "", paraphrase)
  clean <- gsub("[*_`#\\[\\]()]", "", clean)
  tokens <- unlist(strsplit(tolower(clean), "[^a-z]+"))
  tokens <- tokens[nchar(tokens) >= 4L]
  unique(tokens)
}

.token_score <- function(text, tokens) {
  txt_lower <- tolower(text)
  mean(vapply(tokens, function(tok) as.numeric(grepl(tok, txt_lower, fixed = TRUE)), numeric(1L)))
}

.empty_srch_result <- function() {
  tibble::tibble(
    doc_index  = integer(),
    style_name = character(),
    text       = character(),
    score      = numeric()
  )
}
