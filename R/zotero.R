# zotero.R — Zotero SQLite lookup helpers

# Content types cred can read a source from.
.crd_zot_pdf  <- "application/pdf"
.crd_zot_docx <- "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

#' Open the Zotero database read-only
#'
#' Uses the `immutable=1` URI so a running Zotero is never locked out.
#'
#' @param zotero_dir `character(1)` Zotero data directory.
#' @return A DBI connection. The caller disconnects it.
#' @noRd
.crd_zot_connect <- function(zotero_dir) {
  zotero_dir <- path.expand(zotero_dir)
  if (!dir.exists(zotero_dir)) {
    stop("Zotero directory not found: ", zotero_dir, call. = FALSE)
  }
  db_path <- file.path(zotero_dir, "zotero.sqlite")
  if (!file.exists(db_path)) {
    stop("zotero.sqlite not found in: ", zotero_dir, call. = FALSE)
  }
  .crd_need("RSQLite")
  RSQLite::dbConnect(RSQLite::SQLite(), paste0("file:", db_path, "?mode=ro&immutable=1"))
}

#' The libraries in a Zotero database, labelled for messages
#'
#' @param con A connection from [.crd_zot_connect()].
#' @return A `data.frame` with `library_id` (Zotero's internal, machine-local
#'   id), `group_id` (`NA` for My Library), `name` and `label`.
#' @noRd
.crd_zot_libraries <- function(con) {
  libs <- RSQLite::dbGetQuery(con, "
    SELECT l.libraryID AS library_id, g.groupID AS group_id, g.name AS name
    FROM libraries l
    LEFT JOIN groups g ON g.libraryID = l.libraryID
    ORDER BY g.groupID IS NOT NULL, g.name, g.groupID
  ")
  libs$label <- ifelse(is.na(libs$group_id), "My Library",
                       paste0(libs$name, " (", libs$group_id, ")"))
  libs
}

#' Resolve a `library` argument to Zotero's internal library id
#'
#' A caller names a library the way it is named on every machine: `"user"` for
#' My Library, or a group by its name or its groupID. Zotero's own `libraryID`
#' is a row number in one machine's database, so it is refused rather than
#' guessed at — a number that is only a `libraryID` here would name a different
#' library, or none, somewhere else.
#'
#' @param con A connection from [.crd_zot_connect()].
#' @param library `NULL`, `"user"`, a group name, or a groupID (number or
#'   string of digits).
#' @return `NULL` for every library, otherwise one internal library id.
#' @noRd
.crd_zot_library <- function(con, library) {
  if (is.null(library)) return(NULL)
  libs <- .crd_zot_libraries(con)
  bad <- function(why) {
    stop("Zotero library ", why, ".\n",
         "  Pass `library` as \"user\" (My Library), a group name, or a groupID. Groups here: ",
         paste(libs$label[!is.na(libs$group_id)], collapse = ", "), call. = FALSE)
  }
  if (length(library) != 1L || is.na(library) ||
      !(is.character(library) || is.numeric(library))) {
    bad("must be a single name or number")
  }
  if (identical(library, "user")) return(libs$library_id[is.na(libs$group_id)])

  if (is.numeric(library) || grepl("^[0-9]+$", library)) {
    id <- libs$library_id[libs$group_id %in% as.numeric(library)]
    if (length(id) == 1L) return(id)
    if (as.numeric(library) %in% libs$library_id) {
      bad(paste0(library, " is not a groupID; it is Zotero's internal libraryID here, ",
                 "which differs between machines"))
    }
    bad(paste0("with groupID ", library, " not found"))
  }

  id <- libs$library_id[libs$name %in% library]
  if (length(id) > 1L) bad(paste0("name \"", library, "\" is shared by ", length(id),
                                  " groups; pass the groupID"))
  if (length(id) == 0L) bad(paste0("\"", library, "\" not found"))
  id
}

#' The live items carrying each citation key, one item per resolvable key
#'
#' A citation key is unique within a library, not across them, and even within
#' one library two items can share a key that was set by hand. Rather than pick
#' one, a key matching more than one live item is left unresolved and named in
#' a warning; so is a key that exists only outside the library asked for.
#' Trashed items are never matched.
#'
#' @param con A connection from [.crd_zot_connect()].
#' @param keys `character` citation keys, non-empty.
#' @param lib_id Internal library id from [.crd_zot_library()], or `NULL`.
#' @return A `list`: `items` (`citation_key`, `item_id`, `item_key`, one row
#'   per resolved key) and `unresolved` (the keys warned about).
#' @noRd
.crd_zot_resolve_keys <- function(con, keys, lib_id) {
  hits <- RSQLite::dbGetQuery(con, sprintf("
    SELECT idv.value AS citation_key, i.itemID AS item_id, i.key AS item_key,
           i.libraryID AS library_id
    FROM items i
    JOIN itemData       id  ON id.itemID  = i.itemID
    JOIN itemDataValues idv ON idv.valueID = id.valueID
    JOIN fields         f   ON f.fieldID  = id.fieldID
    WHERE f.fieldName = 'citationKey'
    AND   idv.value IN (%s)
    AND   i.itemID NOT IN (SELECT itemID FROM deletedItems)
    ORDER BY idv.value, i.itemID
  ", paste(rep("?", length(keys)), collapse = ", ")), params = as.list(keys))

  libs <- .crd_zot_libraries(con)
  label <- function(ids) {
    paste(libs$label[match(sort(unique(ids)), libs$library_id)], collapse = ", ")
  }

  elsewhere <- character()
  if (!is.null(lib_id)) {
    elsewhere <- setdiff(hits$citation_key, hits$citation_key[hits$library_id == lib_id])
    if (length(elsewhere) > 0L) {
      lines <- vapply(elsewhere, function(k) {
        paste0("  ", k, ": in ", label(hits$library_id[hits$citation_key == k]))
      }, character(1L))
      rlang::warn(paste0("Not in Zotero library ", label(lib_id),
                         ", only in another, so left unresolved:\n",
                         paste(lines, collapse = "\n")),
                  class = "cred_zot_elsewhere")
    }
    hits <- hits[hits$library_id == lib_id, , drop = FALSE]
  }

  n <- table(hits$citation_key)
  ambiguous <- names(n)[n > 1L]
  if (length(ambiguous) > 0L) {
    lines <- vapply(ambiguous, function(k) {
      ids <- hits$library_id[hits$citation_key == k]
      where <- if (length(unique(ids)) > 1L) {
        paste0("in more than one library (", label(ids), ")")
      } else {
        paste0("on ", length(ids), " items in ", label(ids))
      }
      paste0("  ", k, ": ", where)
    }, character(1L))
    rlang::warn(paste0("Left unresolved, because each matches more than one Zotero item.\n",
                       "  Pass `library`, or set options(cred.zotero_library = ):\n",
                       paste(lines, collapse = "\n")),
                class = "cred_zot_ambiguous")
  }

  items <- hits[!hits$citation_key %in% ambiguous, c("citation_key", "item_id", "item_key")]
  list(items = items, unresolved = c(elsewhere, ambiguous))
}

#' Every live attachment of some items, in Zotero's own order of preference
#'
#' The order is Zotero's "best attachment" rule
#' (`Zotero.Item.prototype.getBestAttachments`): PDF first, then an attachment
#' whose URL is the item's own URL, then the oldest — and, since `dateAdded`
#' ties are common on bulk imports, the lowest itemID last so the pick is
#' deterministic. Trashed attachments and linked URLs, which are not files, are
#' excluded as Zotero excludes them.
#'
#' @param con A connection from [.crd_zot_connect()].
#' @param item_ids `integer` parent item ids.
#' @param content_types `character` content types to keep.
#' @param zotero_dir `character(1)` Zotero data directory, for `src_path`.
#' @return A `data.frame`, one row per attachment: `item_id`,
#'   `attachment_key`, `content_type`, `src_path`, `exists`.
#' @noRd
.crd_zot_attachments <- function(con, item_ids, content_types, zotero_dir) {
  if (length(item_ids) == 0L) {
    return(data.frame(item_id = integer(), attachment_key = character(),
                      content_type = character(), src_path = character(),
                      exists = logical()))
  }
  url <- "(SELECT d.itemID, v.value FROM itemData d
           JOIN itemDataValues v ON v.valueID = d.valueID
           JOIN fields ff ON ff.fieldID = d.fieldID WHERE ff.fieldName = 'url')"
  att <- RSQLite::dbGetQuery(con, sprintf("
    SELECT ia.parentItemID AS item_id,
           att.key         AS attachment_key,
           ia.contentType  AS content_type,
           ia.path         AS attachment_path
    FROM itemAttachments ia
    JOIN items att ON att.itemID = ia.itemID
    LEFT JOIN %s aurl ON aurl.itemID = ia.itemID
    LEFT JOIN %s purl ON purl.itemID = ia.parentItemID
    WHERE ia.parentItemID IN (%s)
    AND   ia.itemID NOT IN (SELECT itemID FROM deletedItems)
    AND   (ia.linkMode IS NULL OR ia.linkMode <> 3)
    AND   ia.contentType IN (%s)
    ORDER BY ia.parentItemID,
             ia.contentType = 'application/pdf' DESC,
             aurl.value = purl.value DESC,
             att.dateAdded ASC,
             att.itemID ASC
  ", url, url, paste(rep("?", length(item_ids)), collapse = ", "),
     paste(rep("?", length(content_types)), collapse = ", ")),
  params = c(as.list(item_ids), as.list(content_types)))

  att$src_path <- .crd_zot_src_path(att$attachment_path, att$attachment_key, zotero_dir)
  att$exists <- !is.na(att$src_path) & file.exists(att$src_path)
  att[, c("item_id", "attachment_key", "content_type", "src_path", "exists")]
}

#' Turn a Zotero attachment path into a file path
#'
#' `storage:FILE` is a file Zotero holds under `storage/<attachment key>/`.
#' Anything else is a linked file, taken as a path on this machine.
#'
#' @noRd
.crd_zot_src_path <- function(path, attachment_key, zotero_dir) {
  storage_dir <- file.path(path.expand(zotero_dir), "storage")
  out <- rep(NA_character_, length(path))
  stored <- !is.na(path) & startsWith(path, "storage:")
  out[stored] <- file.path(storage_dir, attachment_key[stored], sub("^storage:", "", path[stored]))
  linked <- !is.na(path) & !stored
  out[linked] <- path.expand(path[linked])
  out
}

#' Resolve citation keys to source file paths via Zotero SQLite
#'
#' Queries the local Zotero SQLite database to find a PDF or Word document
#' attachment for each of a vector of Better BibTeX citation keys. Returns a
#' tibble suitable for passing to [crd_aud_verify_all()].
#'
#' A citation key is unique within a Zotero library, not across libraries, so
#' the same key can name different works in My Library and a group library.
#' Name the library with `library`, or once per session with
#' `options(cred.zotero_library = )`. With neither, every library is searched,
#' and a key found in more than one is left unresolved with a warning rather
#' than taken from whichever happens to come first. A key shared by two live
#' items within one library is treated the same way.
#'
#' Trashed items and trashed attachments are never used.
#'
#' When an item has several attachments, the one taken is the one Zotero itself
#' opens: a PDF before a Word document, then the attachment whose URL is the
#' item's own, then the oldest. If that file is not on disk the next one is
#' taken. A message names the file taken and the ones left out.
#'
#' The database is opened read-only and `immutable`, so a running Zotero is
#' never locked.
#'
#' @param citation_keys `character` vector of BBT citation keys to resolve.
#'   `NA` values are silently dropped.
#' @param zotero_dir `character(1)` path to the Zotero data directory.
#'   Default `"~/Zotero"`.
#' @param library The Zotero library to resolve keys in: `"user"` for My
#'   Library, or a group's name or groupID (as in its URL,
#'   `zotero.org/groups/<groupID>`). Zotero's internal `libraryID` is not
#'   accepted: it differs between machines. Default
#'   `getOption("cred.zotero_library")`; `NULL` searches every library.
#' @return A [tibble][tibble::tibble] with columns:
#'   - `citation_key` (`character`) — the input key.
#'   - `src_path` (`character`) — absolute path to the attachment file.
#'   - `src_type` (`character`) — `"docx"` or `"pdf"`.
#'
#'   Only rows where an attachment was found and the file exists on disk are
#'   returned. A warning is issued for keys with no resolvable attachment.
#' @export
#' @examples
#' # The toy library shipped with cred holds its items in My Library
#' toy <- system.file("extdata", package = "cred")
#' crd_zot_src_lookup(
#'   c("smith2020SalmonHabitat", "jones2019BeaverEcology"),
#'   zotero_dir = toy, library = "user"
#' )
crd_zot_src_lookup <- function(citation_keys, zotero_dir = "~/Zotero",
                               library = getOption("cred.zotero_library")) {
  chk::chk_character(citation_keys)
  chk::chk_string(zotero_dir)

  con <- .crd_zot_connect(zotero_dir)
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)
  lib_id <- .crd_zot_library(con, library)

  empty <- tibble::tibble(citation_key = character(), src_path = character(),
                          src_type = character())
  keys <- unique(citation_keys[!is.na(citation_keys)])
  if (length(keys) == 0L) return(empty)

  resolved <- .crd_zot_resolve_keys(con, keys, lib_id)
  items <- resolved$items
  att <- .crd_zot_attachments(con, items$item_id, c(.crd_zot_pdf, .crd_zot_docx), zotero_dir)
  att$citation_key <- items$citation_key[match(att$item_id, items$item_id)]

  # Zotero's order, skipping a file that is not on disk
  on_disk <- att[att$exists, , drop = FALSE]
  best <- on_disk[!duplicated(on_disk$item_id), , drop = FALSE]

  others <- att[att$item_id %in% best$item_id & !att$src_path %in% best$src_path, , drop = FALSE]
  if (nrow(others) > 0L) {
    others$label <- ifelse(others$exists, basename(others$src_path),
                           paste0(basename(others$src_path), " (not on disk)"))
    groups <- split(others$label, others$citation_key)
    lines <- vapply(names(groups), function(k) {
      paste0("  ", k, ": took ", basename(best$src_path[best$citation_key == k]),
             "; left out ", paste(groups[[k]], collapse = ", "))
    }, character(1L))
    message("Several attachments on one item; took Zotero's own choice ",
            "(PDF, URL matching the item, oldest) of the files on disk:\n",
            paste(lines, collapse = "\n"))
  }

  missing <- setdiff(unique(att$citation_key), best$citation_key)
  if (length(missing) > 0L) {
    warning("Attachment file not found on disk for: ", paste(missing, collapse = ", "),
            call. = FALSE)
  }
  not_found <- setdiff(keys, c(best$citation_key, missing, resolved$unresolved))
  if (length(not_found) > 0L) {
    warning("No attachment found in Zotero for: ", paste(not_found, collapse = ", "),
            call. = FALSE)
  }

  best <- best[order(best$citation_key), , drop = FALSE]
  tibble::tibble(
    citation_key = best$citation_key,
    src_path     = best$src_path,
    src_type     = ifelse(best$content_type == .crd_zot_pdf, "pdf", "docx")
  )
}

#' Retrieve Zotero abstracts for a vector of citation keys
#'
#' Queries the local Zotero SQLite database for the `abstractNote` field of
#' each supplied citation key. Returns a tibble with one row per key —
#' including keys with no abstract (`abstract = NA`).
#'
#' Keys resolve as in [crd_zot_src_lookup()]: within `library`, never to a
#' trashed item, and a key matching more than one item is `NA` with a warning
#' saying so.
#'
#' @inheritParams crd_zot_src_lookup
#' @param citation_keys `character` vector of BBT citation keys.
#'   `NA` values are silently dropped.
#' @return A [tibble][tibble::tibble] with columns:
#'   - `citation_key` (`character`) — the input key.
#'   - `abstract` (`character`) — abstract text, `NA` if not in database.
#' @export
#' @examples
#' toy <- system.file("extdata", package = "cred")
#' crd_zot_abstract_lookup("doe2021NoFile", zotero_dir = toy, library = "user")
crd_zot_abstract_lookup <- function(citation_keys, zotero_dir = "~/Zotero",
                                    library = getOption("cred.zotero_library")) {
  chk::chk_character(citation_keys)
  chk::chk_string(zotero_dir)

  con <- .crd_zot_connect(zotero_dir)
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)
  lib_id <- .crd_zot_library(con, library)

  keys <- sort(unique(citation_keys[!is.na(citation_keys)]))
  result <- tibble::tibble(citation_key = keys, abstract = rep(NA_character_, length(keys)))
  if (length(keys) == 0L) return(result)

  resolved <- .crd_zot_resolve_keys(con, keys, lib_id)
  items <- resolved$items
  if (nrow(items) > 0L) {
    raw <- RSQLite::dbGetQuery(con, sprintf("
      SELECT id.itemID AS item_id, idv.value AS abstract
      FROM itemData id
      JOIN itemDataValues idv ON idv.valueID = id.valueID
      JOIN fields         f   ON f.fieldID  = id.fieldID
      WHERE f.fieldName = 'abstractNote'
      AND   id.itemID IN (%s)
    ", paste(rep("?", nrow(items)), collapse = ", ")), params = as.list(items$item_id))
    abstract <- raw$abstract[match(items$item_id, raw$item_id)]
    result$abstract <- abstract[match(result$citation_key, items$citation_key)]
  }

  no_abstract <- setdiff(result$citation_key[is.na(result$abstract)], resolved$unresolved)
  if (length(no_abstract) > 0L) {
    rlang::warn(paste0("No abstract found in Zotero for: ", paste(no_abstract, collapse = ", ")),
                class = "cred_zot_no_abstract")
  }

  result
}

#' Map Zotero attachment paths back to citation keys
#'
#' The inverse of [crd_zot_src_lookup()]. A ragnar store records each chunk's
#' `origin` as the absolute path the PDF had on the machine that built it —
#' provenance, but not something you can cite. The durable identifier inside
#' that path is the Zotero attachment key (the parent directory name), which
#' resolves back to a Better BibTeX citation key.
#'
#' @param paths `character` vector of attachment paths of the form
#'   `.../storage/{attachment_key}/{filename}`.
#' @param zotero_dir `character(1)` path to the Zotero data directory.
#'   Default `"~/Zotero"`.
#' @return `character` vector of citation keys, parallel to `paths`, with `NA`
#'   where the path carries no resolvable attachment key.
#' @noRd
.crd_zot_key_from_path <- function(paths, zotero_dir = "~/Zotero") {
  out <- rep(NA_character_, length(paths))
  att_keys <- basename(dirname(paths))
  # Zotero attachment keys are 8 uppercase alphanumeric characters
  valid <- !is.na(att_keys) & grepl("^[A-Z0-9]{8}$", att_keys)
  if (!any(valid)) return(out)

  db_path <- file.path(path.expand(zotero_dir), "zotero.sqlite")
  if (!file.exists(db_path)) return(out)
  if (!requireNamespace("RSQLite", quietly = TRUE)) return(out)

  keys <- unique(att_keys[valid])
  con <- RSQLite::dbConnect(RSQLite::SQLite(),
                            paste0("file:", db_path, "?mode=ro&immutable=1"))
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)

  sql <- sprintf("
    SELECT att.key   AS attachment_key,
           idv.value AS citation_key
    FROM items att
    JOIN itemAttachments ia  ON ia.itemID   = att.itemID
    JOIN items           i   ON i.itemID    = ia.parentItemID
    JOIN itemData        id  ON id.itemID   = i.itemID
    JOIN itemDataValues  idv ON id.valueID  = idv.valueID
    JOIN fields          f   ON id.fieldID  = f.fieldID
    WHERE f.fieldName = 'citationKey'
    AND   att.key IN (%s)
  ", paste(rep("?", length(keys)), collapse = ", "))

  raw <- RSQLite::dbGetQuery(con, sql, params = as.list(keys))
  if (nrow(raw) == 0L) return(out)

  out[valid] <- raw$citation_key[match(att_keys[valid], raw$attachment_key)]
  out
}
