# test-zotero.R — resolving citation keys and collections in one library (cred#40)

src_file <- function(res, key) basename(res$src_path[res$citation_key == key])

# ---------------------------------------------------------------------------
# crd_zot_src_lookup(): the three defects in the issue
# ---------------------------------------------------------------------------

test_that("a key in two libraries resolves to the library asked for", {
  dir <- zot_fixture()
  res <- crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = "Central")
  expect_identical(src_file(res, "hagen2019Trend"), "hagen_central.pdf")

  res <- crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = "user")
  expect_identical(src_file(res, "hagen2019Trend"), "hagen_personal.pdf")
})

test_that("with no library, a key in two libraries is left unresolved and named", {
  dir <- zot_fixture()
  withr::local_options(cred.zotero_library = NULL)
  expect_warning(
    res <- crd_zot_src_lookup(c("hagen2019Trend", "martins2022Spatial"), zotero_dir = dir),
    "hagen2019Trend.*more than one library.*Central.*My Library|hagen2019Trend.*more than one library.*My Library.*Central"
  )
  expect_false("hagen2019Trend" %in% res$citation_key)
  expect_true("martins2022Spatial" %in% res$citation_key)
})

test_that("the cred.zotero_library option supplies the default library", {
  dir <- zot_fixture()
  withr::local_options(cred.zotero_library = "Central")
  res <- crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir)
  expect_identical(src_file(res, "hagen2019Trend"), "hagen_central.pdf")
})

test_that("a trashed attachment is never taken, however new", {
  dir <- zot_fixture()
  res <- crd_zot_src_lookup("martins2022Spatial", zotero_dir = dir, library = "Central")
  expect_identical(src_file(res, "martins2022Spatial"), "martins_live.pdf")
})

test_that("a trashed parent does not resolve", {
  dir <- zot_fixture()
  expect_warning(
    res <- crd_zot_src_lookup("gone2020Trashed", zotero_dir = dir, library = "Central"),
    "gone2020Trashed"
  )
  expect_identical(nrow(res), 0L)
})

test_that("of several PDFs, Zotero's best attachment is taken and the rest are named", {
  dir <- zot_fixture()
  expect_message(
    res <- crd_zot_src_lookup("bottoms2023Critical", zotero_dir = dir, library = "Central"),
    "bottoms2023Critical.*bottoms_report\\.pdf.*bottoms_appendix1\\.pdf"
  )
  expect_identical(src_file(res, "bottoms2023Critical"), "bottoms_report.pdf")
})

test_that("with no URL match, the oldest PDF is taken", {
  dir <- zot_fixture()
  res <- suppressMessages(
    crd_zot_src_lookup("dup2018Copies", zotero_dir = dir, library = "Central")
  )
  expect_identical(src_file(res, "dup2018Copies"), "dup_a.pdf")
})

test_that("two live parents sharing a key in one library are left unresolved", {
  dir <- zot_fixture()
  expect_warning(
    res <- crd_zot_src_lookup("R-base", zotero_dir = dir, library = "user"),
    "R-base.*2 items"
  )
  expect_identical(nrow(res), 0L)
})

test_that("a linked URL is not a source file", {
  dir <- zot_fixture()
  expect_warning(
    res <- crd_zot_src_lookup("web2021Link", zotero_dir = dir, library = "Central"),
    "web2021Link"
  )
  expect_identical(nrow(res), 0L)
})

test_that("the returned columns are unchanged", {
  dir <- zot_fixture()
  res <- crd_zot_src_lookup("martins2022Spatial", zotero_dir = dir, library = "Central")
  expect_named(res, c("citation_key", "src_path", "src_type"))
  expect_identical(res$src_type, "pdf")
})

# ---------------------------------------------------------------------------
# Naming a library
# ---------------------------------------------------------------------------

test_that("a numeric library is a groupID, never Zotero's machine-local libraryID", {
  dir <- zot_fixture()
  # Satellite's groupID is 5, which is also Central's libraryID. Satellite holds
  # no hagen, so resolving 5 as a libraryID would find Central's copy.
  expect_warning(
    res <- crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = 5),
    "hagen2019Trend"
  )
  expect_identical(nrow(res), 0L)

  res <- crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = 4733734)
  expect_identical(src_file(res, "hagen2019Trend"), "hagen_central.pdf")
})

test_that("an unknown library errors and lists the libraries there are", {
  dir <- zot_fixture()
  expect_error(
    crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = "Nope"),
    "Nope.*\"user\".*Central \\(4733734\\).*Satellite \\(5\\)"
  )
  expect_error(
    crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = 999),
    "999"
  )
  expect_error(
    crd_zot_src_lookup("hagen2019Trend", zotero_dir = dir, library = c("Central", "user"))
  )
})

# ---------------------------------------------------------------------------
# crd_zot_abstract_lookup()
# ---------------------------------------------------------------------------

test_that("abstract lookup returns one row per key, from the library asked for", {
  dir <- zot_fixture()
  res <- crd_zot_abstract_lookup("hagen2019Trend", zotero_dir = dir, library = "Central")
  expect_identical(nrow(res), 1L)
  expect_identical(res$abstract, "Central copy abstract.")
})

test_that("with no library, an abstract for a key in two libraries is NA, not two rows", {
  dir <- zot_fixture()
  withr::local_options(cred.zotero_library = NULL)
  res <- suppressWarnings(crd_zot_abstract_lookup("hagen2019Trend", zotero_dir = dir))
  expect_identical(nrow(res), 1L)
  expect_identical(res$abstract, NA_character_)
})

# ---------------------------------------------------------------------------
# Collections, for crd_store_build()
# ---------------------------------------------------------------------------

test_that("a collection name in two libraries errors with no library given", {
  dir <- zot_fixture()
  withr::local_options(cred.zotero_library = NULL)
  expect_error(
    .crd_zot_collection_pdfs("species", zotero_dir = dir),
    "species.*more than one library.*Central.*My Library|species.*more than one library.*My Library.*Central"
  )
})

test_that("a collection ingests every live PDF of its members, once per file content", {
  dir <- zot_fixture()
  res <- .crd_zot_collection_pdfs("species", zotero_dir = dir, library = "Central")
  got <- res$sources
  expect_setequal(
    basename(got$src_path),
    c("hagen_central.pdf", "martins_live.pdf", "bottoms_report.pdf",
      "bottoms_appendix1.pdf", "dup_a.pdf")
  )
  expect_identical(sum(got$citation_key == "bottoms2023Critical"), 2L)
})

test_that("a collection reports every member it leaves out, and why", {
  dir <- zot_fixture()
  res <- .crd_zot_collection_pdfs("species", zotero_dir = dir, library = "Central")
  out <- res$left_out
  reason <- stats::setNames(out$reason, out$item)
  expect_identical(reason[["ITEM0140"]], "trashed")
  expect_identical(reason[["ITEM0180"]], "no citation key")
  expect_identical(reason[["ITEM0190"]], "no live PDF")
  expect_identical(reason[["ITEM0200"]], "no live PDF")
  expect_identical(reason[["ATT00195"]], "standalone attachment")
  expect_identical(reason[["NOTE0197"]], "note")
  expect_identical(nrow(out), 6L)
})

test_that("a trashed collection is not found", {
  dir <- zot_fixture()
  expect_error(
    .crd_zot_collection_pdfs("old", zotero_dir = dir, library = "Central"),
    "old"
  )
})

test_that("citation keys for a store take every live PDF, once per file content", {
  dir <- zot_fixture()
  res <- .crd_zot_key_pdfs(c("bottoms2023Critical", "dup2018Copies", "martins2022Spatial"),
                           zotero_dir = dir, library = "Central")
  expect_setequal(
    basename(res$src_path),
    c("bottoms_report.pdf", "bottoms_appendix1.pdf", "dup_a.pdf", "martins_live.pdf")
  )
})

# ---------------------------------------------------------------------------
# The shipped toy database keeps up with the schema cred reads
# ---------------------------------------------------------------------------

test_that("the toy database has every table and column the queries read", {
  toy <- system.file("extdata", "zotero.sqlite", package = "cred")
  skip_if(toy == "", "toy extdata not found")
  con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", toy, "?mode=ro&immutable=1"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  ref <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(ref), add = TRUE)
  for (ddl in zot_schema) DBI::dbExecute(ref, ddl)

  for (tbl in names(zot_schema)) {
    want <- DBI::dbGetQuery(ref, sprintf("PRAGMA table_info(%s)", tbl))$name
    have <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tbl))$name
    expect_true(all(want %in% have), info = paste(tbl, ":", setdiff(want, have)))
  }
})
