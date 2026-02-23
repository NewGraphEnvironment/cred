# pdf.R — PDF text extraction and claim search

#' Extract text from a PDF as a tidy tibble
#'
#' Wraps [pdftools::pdf_text()] and returns one row per page.
#'
#' @param pdf_path `character(1)` path to a PDF file.
#' @return A [tibble][tibble::tibble] with columns `page` (`integer`)
#'   and `text` (`character`).
#' @export
#' @examples
#' \dontrun{
#' txt <- crd_pdf_ext_txt("background/source.pdf")
#' }
crd_pdf_ext_txt <- function(pdf_path) {
  chk::chk_file(pdf_path)

  pages <- pdftools::pdf_text(pdf_path)
  tibble::tibble(
    page = seq_along(pages),
    text = pages
  )
}

#' Search a PDF for the best-matching passage to a paraphrase
#'
#' Uses the same token-scoring approach as [crd_docx_srch_clm()], applied
#' to paragraph-split page text. Returns top matching passages with page
#' numbers.
#'
#' @param pdf_txt `data.frame` as returned by [crd_pdf_ext_txt()].
#' @param paraphrase `character(1)` paraphrase text from the audit CSV.
#' @param n_results `integer(1)` number of top matches to return.
#'   Default `3L`.
#' @param min_score `numeric(1)` minimum token-match proportion.
#'   Default `0.2`.
#' @return A [tibble][tibble::tibble] with columns `page`, `passage`,
#'   `score`, ordered by descending score.
#' @export
#' @examples
#' \dontrun{
#' txt <- crd_pdf_ext_txt("background/source.pdf")
#' crd_pdf_srch_clm(txt, "beaver dams moderate summer stream temperatures")
#' }
crd_pdf_srch_clm <- function(pdf_txt, paraphrase, n_results = 3L, min_score = 0.2) {
  chk::chk_data(pdf_txt)
  chk::chk_string(paraphrase)
  chk::chk_whole_number(n_results)
  chk::chk_number(min_score)

  tokens <- .paraphrase_tokens(paraphrase)
  if (length(tokens) == 0L) {
    return(tibble::tibble(page = integer(), passage = character(), score = numeric()))
  }

  # Split each page into paragraphs (double newline or 3+ spaces)
  rows <- lapply(seq_len(nrow(pdf_txt)), function(i) {
    paras <- unlist(strsplit(pdf_txt$text[i], "\n{2,}|[ ]{3,}"))
    paras <- stringr::str_trim(paras)
    paras <- paras[nchar(paras) > 20L]
    tibble::tibble(page = pdf_txt$page[i], passage = paras)
  })
  all_paras <- dplyr::bind_rows(rows)
  if (nrow(all_paras) == 0L) {
    return(tibble::tibble(page = integer(), passage = character(), score = numeric()))
  }

  all_paras$score <- vapply(all_paras$passage, function(txt) {
    .token_score(txt, tokens)
  }, numeric(1L))

  dplyr::filter(all_paras, .data$score >= min_score) |>
    dplyr::arrange(dplyr::desc(.data$score)) |>
    dplyr::slice_head(n = n_results)
}
