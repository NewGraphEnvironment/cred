# sentence.R — sentence extraction around a citation key

#' Extract the sentence(s) containing a specific citation key
#'
#' Splits a line of Rmd prose into sentence fragments and returns the
#' fragment(s) that contain `@key`. Falls back to the full trimmed line
#' when the extracted fragment is too short or starts mid-sentence
#' (lowercase first character).
#'
#' **Split rules** (applied outside `[...]` citation bracket groups):
#' - `. [Capital]` — period followed by a capital letter, excluding
#'   common abbreviations (`et al.`, `Dr.`, `Mr.`, `St.`).
#' - `. @key` — period followed by a narrative citation, so that
#'   sentences of the form `@author documented...` are correctly
#'   isolated.
#'
#' The lookahead `(?![^[]*\])` prevents splitting inside `[@k1; @k2]`
#' by checking that a `]` is not reachable without first crossing a `[`.
#'
#' @param line `character(1)` a single line of Rmd prose.
#' @param key `character(1)` BBT citation key (without leading `@`).
#' @param min_chars `integer(1)` minimum fragment length before falling
#'   back to the full line. Default `40L`.
#' @return `character(1)` trimmed sentence fragment, or full line when
#'   the fragment is uninformative.
#' @export
#' @examples
#' line <- paste(
#'   "@smith2020 documented X; @jones2021 confirmed Y.",
#'   "@brown2022 extended the finding."
#' )
#' crd_sent_ext_key(line, "jones2021")
#' crd_sent_ext_key(line, "brown2022")
crd_sent_ext_key <- function(line, key, min_chars = 40L) {
  chk::chk_string(line)
  chk::chk_string(key)
  chk::chk_whole_number(min_chars)

  pat_split <- paste0(
    # Rule 1: period + Capital, excluding common abbreviations
    "(?<! al)",           # not "et al."
    "(?<![A-Z][a-z])",    # not "Dr.", "Mr.", "St."
    "(?<=[a-z0-9\\]])",   # preceded by lowercase, digit, or ]
    "\\. +",
    "(?=[A-Z][a-zA-Z])",  # followed by Capital + letter
    "(?![^[]*\\])",       # not inside [...]
    "|",
    # Rule 2: period + @key (narrative citation starts sentence)
    "(?<=\\.) +(?=@[A-Za-z])(?![^[]*\\])"
  )

  frags <- unlist(strsplit(line, pat_split, perl = TRUE))
  frags <- frags[nzchar(frags)]

  if (length(frags) == 0L) return(stringr::str_trim(line))

  pat_key <- paste0("@", key, "(?:[^A-Za-z0-9_]|$)")
  has_key <- grepl(pat_key, frags, perl = TRUE)

  if (!any(has_key)) return(stringr::str_trim(line))

  out <- stringr::str_trim(paste(frags[has_key], collapse = " "))

  if (nchar(out) < min_chars || grepl("^[a-z*_`\\-]", out)) {
    stringr::str_trim(line)
  } else {
    out
  }
}
