# helper-zotero.R — a temporary Zotero database in the real schema
#
# The shipped toy database (inst/extdata/zotero.sqlite) holds three items in
# one library, which cannot reach any of the failures in cred#40: a key in two
# libraries, a trashed attachment or parent, several PDFs on one item, a
# collection name shared across libraries. This builds one that can.
#
# Columns are the subset of Zotero's own tables that cred reads, with Zotero's
# names. `zot_schema` is also what the shipped toy database is checked against
# (test-zotero.R), so the two cannot drift apart unnoticed.

zot_schema <- c(
  libraries = "CREATE TABLE libraries (libraryID INTEGER PRIMARY KEY, type TEXT NOT NULL)",
  groups = "CREATE TABLE groups (groupID INTEGER PRIMARY KEY, libraryID INT NOT NULL UNIQUE,
            name TEXT NOT NULL)",
  items = "CREATE TABLE items (itemID INTEGER PRIMARY KEY, itemTypeID INTEGER,
           dateAdded TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, libraryID INTEGER,
           key TEXT NOT NULL)",
  fields = "CREATE TABLE fields (fieldID INTEGER PRIMARY KEY, fieldName TEXT NOT NULL)",
  itemData = "CREATE TABLE itemData (itemID INTEGER, fieldID INTEGER, valueID INTEGER)",
  itemDataValues = "CREATE TABLE itemDataValues (valueID INTEGER PRIMARY KEY, value TEXT NOT NULL)",
  itemAttachments = "CREATE TABLE itemAttachments (itemID INTEGER PRIMARY KEY, parentItemID INT,
                     linkMode INT, contentType TEXT, path TEXT)",
  itemNotes = "CREATE TABLE itemNotes (itemID INTEGER PRIMARY KEY, parentItemID INT, note TEXT)",
  deletedItems = "CREATE TABLE deletedItems (itemID INTEGER PRIMARY KEY,
                  dateDeleted DEFAULT CURRENT_TIMESTAMP NOT NULL)",
  collections = "CREATE TABLE collections (collectionID INTEGER PRIMARY KEY,
                 collectionName TEXT NOT NULL, parentCollectionID INT DEFAULT NULL,
                 libraryID INT NOT NULL, key TEXT NOT NULL)",
  collectionItems = "CREATE TABLE collectionItems (collectionID INT NOT NULL, itemID INT NOT NULL,
                     orderIndex INT NOT NULL DEFAULT 0)",
  deletedCollections = "CREATE TABLE deletedCollections (collectionID INTEGER PRIMARY KEY,
                        dateDeleted DEFAULT CURRENT_TIMESTAMP NOT NULL)"
)

zot_pdf <- "application/pdf"

#' Build the cred#40 fixture
#'
#' Libraries: 1 is "My Library"; 5 is the group "Central" (groupID 4733734);
#' 7 is the group "Satellite" (groupID 5). Satellite's groupID equals Central's
#' libraryID on purpose, so `library = 5` resolving by libraryID instead of
#' groupID picks the wrong library.
#'
#' @return Path to a Zotero data directory holding `zotero.sqlite` and
#'   `storage/`, removed when the calling test ends.
zot_fixture <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  storage <- file.path(dir, "storage")
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(dir, "zotero.sqlite"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  for (ddl in zot_schema) DBI::dbExecute(con, ddl)
  run <- function(sql, ...) {
    params <- list(...)
    if (length(params)) DBI::dbExecute(con, sql, params = params) else DBI::dbExecute(con, sql)
  }

  fields <- c("citationKey", "title", "abstractNote", "url")
  for (i in seq_along(fields)) run("INSERT INTO fields VALUES (?, ?)", i, fields[i])
  run("INSERT INTO libraries VALUES (1, 'user'), (5, 'group'), (7, 'group')")
  run("INSERT INTO groups VALUES (4733734, 5, 'Central'), (5, 7, 'Satellite')")

  value_id <- 0L
  set_field <- function(item_id, field, value) {
    if (is.null(value)) return(invisible())
    value_id <<- value_id + 1L
    run("INSERT INTO itemDataValues VALUES (?, ?)", value_id, value)
    run("INSERT INTO itemData VALUES (?, ?, ?)", item_id, match(field, fields), value_id)
  }
  item <- function(id, lib, key = NULL, title = NULL, url = NULL, abstract = NULL,
                   added = "2020-01-01 00:00:00") {
    run("INSERT INTO items (itemID, itemTypeID, dateAdded, libraryID, key) VALUES (?, 2, ?, ?, ?)",
        id, added, lib, sprintf("ITEM%04d", id))
    set_field(id, "citationKey", key)
    set_field(id, "title", title)
    set_field(id, "url", url)
    set_field(id, "abstractNote", abstract)
  }
  # `bytes` is the file content; two attachments given the same bytes are
  # byte-identical copies. `parent = NA` is a standalone attachment.
  attach <- function(id, parent, lib, file, added = "2020-01-01 00:00:00", url = NULL,
                     content_type = zot_pdf, bytes = file, link_mode = 1L) {
    att_key <- sprintf("ATT%05d", id)
    run("INSERT INTO items (itemID, itemTypeID, dateAdded, libraryID, key) VALUES (?, 3, ?, ?, ?)",
        id, added, lib, att_key)
    run("INSERT INTO itemAttachments VALUES (?, ?, ?, ?, ?)",
        id, parent, link_mode, content_type, paste0("storage:", file))
    set_field(id, "url", url)
    dir.create(file.path(storage, att_key), recursive = TRUE, showWarnings = FALSE)
    writeLines(bytes, file.path(storage, att_key, file))
  }
  trash <- function(id) run("INSERT INTO deletedItems (itemID) VALUES (?)", id)

  # One key in two libraries. The personal attachment has the higher itemID,
  # so newest-itemID-wins takes it (the issue's hagen case).
  item(100, 1, "hagen2019Trend", abstract = "Personal copy abstract.")
  attach(151, 100, 1, "hagen_personal.pdf")
  item(110, 5, "hagen2019Trend", abstract = "Central copy abstract.")
  attach(111, 110, 5, "hagen_central.pdf")

  # The newest attachment is trashed (the issue's martins case).
  item(120, 5, "martins2022Spatial")
  attach(121, 120, 5, "martins_live.pdf", added = "2022-01-01 00:00:00")
  attach(129, 120, 5, "martins_trashed.pdf", added = "2023-01-01 00:00:00")
  trash(129)

  # Report and a newer appendix; the report's URL matches its parent's (the
  # issue's bottoms case).
  item(130, 5, "bottoms2023Critical", url = "https://example.org/report.pdf")
  attach(131, 130, 5, "bottoms_report.pdf", added = "2024-05-23 17:04:05",
         url = "https://example.org/report.pdf")
  attach(132, 130, 5, "bottoms_appendix1.pdf", added = "2024-05-23 17:06:18",
         url = "https://example.org/appendix1.pdf")

  # A trashed parent with a live attachment.
  item(140, 5, "gone2020Trashed")
  attach(141, 140, 5, "gone.pdf")
  trash(140)

  # Two byte-identical copies on one item.
  item(160, 5, "dup2018Copies")
  attach(161, 160, 5, "dup_a.pdf", bytes = "same bytes")
  attach(162, 160, 5, "dup_b.pdf", bytes = "same bytes", added = "2020-02-01 00:00:00")

  # Two live parents sharing one key inside one library.
  item(170, 1, "R-base")
  attach(171, 170, 1, "rbase_a.pdf")
  item(172, 1, "R-base")
  attach(173, 172, 1, "rbase_b.pdf")

  # Collection members that cannot be ingested.
  item(180, 5, title = "No citation key")
  attach(181, 180, 5, "nokey.pdf")
  item(190, 5, "nopdf2019Meta", title = "Metadata only")
  attach(195, NA, 5, "standalone.pdf")
  run("INSERT INTO items (itemID, itemTypeID, libraryID, key) VALUES (197, 28, 5, 'NOTE0197')")
  run("INSERT INTO itemNotes VALUES (197, NULL, 'a note')")

  # A linked URL is never a file, whatever its content type says.
  item(200, 5, "web2021Link")
  attach(201, 200, 5, "web.pdf", link_mode = 3L)

  # "species" exists in two libraries; "old" is trashed.
  run("INSERT INTO collections VALUES (1, 'species', NULL, 5, 'COLL0001'),
                                     (2, 'species', NULL, 1, 'COLL0002'),
                                     (3, 'old', NULL, 5, 'COLL0003')")
  for (id in c(110, 120, 130, 140, 160, 180, 190, 195, 197, 200)) {
    run("INSERT INTO collectionItems (collectionID, itemID) VALUES (1, ?)", id)
  }
  run("INSERT INTO collectionItems (collectionID, itemID) VALUES (2, 100)")
  run("INSERT INTO collectionItems (collectionID, itemID) VALUES (3, 120)")
  run("INSERT INTO deletedCollections (collectionID) VALUES (3)")

  dir
}

#' Storage path of a fixture attachment
zot_att_path <- function(dir, id, file) {
  file.path(dir, "storage", sprintf("ATT%05d", id), file)
}
