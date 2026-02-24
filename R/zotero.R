# zotero.R — Zotero SQLite lookup helpers

#' Resolve citation keys to source file paths via Zotero SQLite
#'
#' Queries the local Zotero SQLite database to find PDF or Word document
#' attachments for a vector of Better BibTeX citation keys. Returns a tibble
#' suitable for passing to [crd_aud_verify_all()].
#'
#' The database is copied to a temp file before querying to avoid locking
#' conflicts with a running Zotero process.
#'
#' @param citation_keys `character` vector of BBT citation keys to resolve.
#'   `NA` values are silently dropped.
#' @param zotero_dir `character(1)` path to the Zotero data directory.
#'   Default `"~/Zotero"`.
#' @return A [tibble][tibble::tibble] with columns:
#'   - `citation_key` (`character`) — the input key.
#'   - `src_path` (`character`) — absolute path to the attachment file.
#'   - `src_type` (`character`) — `"docx"` or `"pdf"`.
#'
#'   Only rows where an attachment was found and the file exists on disk are
#'   returned. A warning is issued for keys with no resolvable attachment.
#' @export
#' @examples
#' \dontrun{
#' keys <- c("price_etal2026rebuildinggiis", "winther_etal2024assessmentskeena")
#' crd_zot_src_lookup(keys)
#' }
crd_zot_src_lookup <- function(citation_keys, zotero_dir = "~/Zotero") {
  chk::chk_character(citation_keys)
  chk::chk_string(zotero_dir)

  zotero_dir <- path.expand(zotero_dir)
  if (!dir.exists(zotero_dir)) {
    stop("Zotero directory not found: ", zotero_dir)
  }

  db_path <- file.path(zotero_dir, "zotero.sqlite")
  if (!file.exists(db_path)) {
    stop("zotero.sqlite not found in: ", zotero_dir)
  }

  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Package 'RSQLite' is required. Install with: pak::pak('RSQLite')")
  }

  # Use immutable URI to avoid locking the live DB (per zotero-lookup skill)
  db_uri <- paste0("file:", db_path, "?mode=ro&immutable=1")

  keys <- unique(citation_keys[!is.na(citation_keys)])

  con <- RSQLite::dbConnect(RSQLite::SQLite(), db_uri)
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)

  placeholders <- paste(rep("?", length(keys)), collapse = ", ")
  sql <- sprintf("
    SELECT idv.value AS citation_key,
           ia.path        AS attachment_path,
           ia.contentType AS content_type,
           att.key        AS attachment_key
    FROM items i
    JOIN itemData       id  ON i.itemID         = id.itemID
    JOIN itemDataValues idv ON id.valueID        = idv.valueID
    JOIN fields         f   ON id.fieldID        = f.fieldID
    JOIN itemAttachments ia  ON ia.parentItemID  = i.itemID
    JOIN items          att ON att.itemID        = ia.itemID
    WHERE f.fieldName   = 'citationKey'
    AND   idv.value IN (%s)
    AND   ia.contentType IN (
            'application/pdf',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          )
    ORDER BY idv.value, ia.itemID DESC
  ", placeholders)

  raw <- RSQLite::dbGetQuery(con, sql, params = as.list(keys))

  if (nrow(raw) == 0L) {
    warning("No attachments found for any of the supplied citation keys.")
    return(tibble::tibble(citation_key = character(), src_path = character(),
                          src_type = character()))
  }

  # Keep first (most recent) attachment per key
  raw <- raw[!duplicated(raw$citation_key), ]

  # Resolve storage paths: "storage:FILENAME" -> ~/Zotero/storage/{attachment_key}/FILENAME
  storage_dir <- file.path(zotero_dir, "storage")
  raw$src_path <- vapply(seq_len(nrow(raw)), function(i) {
    p <- raw$attachment_path[i]
    if (is.na(p)) return(NA_character_)
    if (startsWith(p, "storage:")) {
      filename <- sub("^storage:", "", p)
      file.path(storage_dir, raw$attachment_key[i], filename)
    } else {
      path.expand(p)
    }
  }, character(1L))

  raw$src_type <- ifelse(
    raw$content_type == "application/pdf", "pdf", "docx"
  )

  result <- tibble::tibble(
    citation_key = raw$citation_key,
    src_path     = raw$src_path,
    src_type     = raw$src_type
  )

  # Filter to files that actually exist
  exists_flag <- file.exists(result$src_path)
  missing <- result$citation_key[!exists_flag]
  if (length(missing) > 0L) {
    warning("Attachment file not found on disk for: ",
            paste(missing, collapse = ", "))
  }
  result <- result[exists_flag, ]

  # Warn for keys that never appeared in DB at all
  found <- result$citation_key
  not_found <- setdiff(keys, found)
  if (length(not_found) > 0L) {
    warning("No attachment found in Zotero for: ",
            paste(not_found, collapse = ", "))
  }

  result
}

#' Retrieve Zotero abstracts for a vector of citation keys
#'
#' Queries the local Zotero SQLite database for the `abstractNote` field of
#' each supplied citation key. Returns a tibble with one row per key —
#' including keys with no abstract (`abstract = NA`).
#'
#' @param citation_keys `character` vector of BBT citation keys.
#'   `NA` values are silently dropped.
#' @param zotero_dir `character(1)` path to the Zotero data directory.
#'   Default `"~/Zotero"`.
#' @return A [tibble][tibble::tibble] with columns:
#'   - `citation_key` (`character`) — the input key.
#'   - `abstract` (`character`) — abstract text, `NA` if not in database.
#' @export
#' @examples
#' \dontrun{
#' crd_zot_abstract_lookup(c("price_etal2026rebuildinggiis", "doe2021NoFile"))
#' }
crd_zot_abstract_lookup <- function(citation_keys, zotero_dir = "~/Zotero") {
  chk::chk_character(citation_keys)
  chk::chk_string(zotero_dir)

  zotero_dir <- path.expand(zotero_dir)
  if (!dir.exists(zotero_dir)) stop("Zotero directory not found: ", zotero_dir)

  db_path <- file.path(zotero_dir, "zotero.sqlite")
  if (!file.exists(db_path)) stop("zotero.sqlite not found in: ", zotero_dir)

  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Package 'RSQLite' is required. Install with: pak::pak('RSQLite')")
  }

  db_uri <- paste0("file:", db_path, "?mode=ro&immutable=1")
  keys <- unique(citation_keys[!is.na(citation_keys)])

  con <- RSQLite::dbConnect(RSQLite::SQLite(), db_uri)
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)

  placeholders <- paste(rep("?", length(keys)), collapse = ", ")
  sql <- sprintf("
    SELECT idv_key.value AS citation_key,
           idv_abs.value AS abstract
    FROM items i
    JOIN itemData       id_key  ON i.itemID       = id_key.itemID
    JOIN itemDataValues idv_key ON id_key.valueID = idv_key.valueID
    JOIN fields         f_key   ON id_key.fieldID = f_key.fieldID
    JOIN itemData       id_abs  ON i.itemID       = id_abs.itemID
    JOIN itemDataValues idv_abs ON id_abs.valueID = idv_abs.valueID
    JOIN fields         f_abs   ON id_abs.fieldID = f_abs.fieldID
    WHERE f_key.fieldName = 'citationKey'
    AND   f_abs.fieldName = 'abstractNote'
    AND   idv_key.value   IN (%s)
  ", placeholders)

  raw <- RSQLite::dbGetQuery(con, sql, params = as.list(keys))

  # Return all requested keys, NA for those not in DB
  result <- tibble::tibble(citation_key = keys)
  if (nrow(raw) > 0L) {
    result <- tibble::as_tibble(merge(result, raw, by = "citation_key", all.x = TRUE))
  } else {
    result$abstract <- NA_character_
  }

  no_abstract <- result$citation_key[is.na(result$abstract)]
  if (length(no_abstract) > 0L) {
    warning("No abstract found in Zotero for: ", paste(no_abstract, collapse = ", "))
  }

  result
}
