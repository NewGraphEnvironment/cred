# Tests for crd_store_update() and the source record it keeps.
#
# A store records each document's `origin` as the absolute path it had on the
# machine that built it, so the update compares origins by an id that drops the
# machine's own prefix, and detects a changed file by the md5 recorded for it
# in the store's `cred_sources` table (#44).

# --- origin id ------------------------------------------------------------

test_that(".crd_origin_id() names a Zotero storage file by its key and file name", {
  here <- "/Users/a/Zotero/storage/ABCD1234/paper.pdf"
  there <- "/home/b/data/zotero/storage/ABCD1234/paper.pdf"
  expect_identical(.crd_origin_id(here), "storage/ABCD1234/paper.pdf")
  expect_identical(.crd_origin_id(there), .crd_origin_id(here))
})

test_that(".crd_origin_id() keeps a linked file's whole path", {
  linked <- "/Users/a/papers/ABCD1234/paper.pdf"
  expect_identical(.crd_origin_id(linked), linked)
  # The key alone is not enough: a folder named like a key outside `storage/`
  # is a linked file, and two such files elsewhere must not collide.
  expect_false(identical(.crd_origin_id(linked), .crd_origin_id("/x/papers/ABCD1234/paper.pdf")))
  expect_identical(.crd_origin_id("/Users/a/Zotero/storage/notakey/paper.pdf"),
                   "/Users/a/Zotero/storage/notakey/paper.pdf")
})

test_that(".crd_origin_id() keeps the same file name under two keys apart", {
  ids <- .crd_origin_id(c("/z/storage/AAAA1111/report.pdf", "/z/storage/BBBB2222/report.pdf"))
  expect_identical(anyDuplicated(ids), 0L)
  expect_identical(.crd_origin_id(character()), character())
})

# --- the source record -----------------------------------------------------

local_duckdb <- function(env = parent.frame()) {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), withr::local_tempfile(fileext = ".duckdb", .local_envir = env))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  con
}

test_that("a store with no source record reads as NULL, not as an empty record", {
  con <- local_duckdb()
  expect_null(.crd_sources_read(con))
})

test_that("the source record round-trips, and a write replaces it whole", {
  con <- local_duckdb()
  .crd_sources_write(con, c("storage/AAAA1111/a.pdf", "/linked/b.pdf"), c("m1", "m2"))
  rec <- .crd_sources_read(con)
  expect_identical(rec$origin_id[order(rec$origin_id)], c("/linked/b.pdf", "storage/AAAA1111/a.pdf"))
  expect_identical(rec$md5[match("storage/AAAA1111/a.pdf", rec$origin_id)], "m1")

  .crd_sources_write(con, "storage/CCCC3333/c.pdf", "m3")
  expect_identical(.crd_sources_read(con)$origin_id, "storage/CCCC3333/c.pdf")

  # An empty record is a record: it says the store holds nothing recorded,
  # which is not the same as a store built before records existed.
  .crd_sources_write(con, character(), character())
  rec <- .crd_sources_read(con)
  expect_false(is.null(rec))
  expect_identical(nrow(rec), 0L)
})

test_that("the source record refuses ids and md5s that do not pair up", {
  con <- local_duckdb()
  expect_error(.crd_sources_write(con, c("a", "b"), "m1"), "one md5 per origin")
  expect_error(.crd_sources_write(con, c("a", "a"), c("m1", "m2")), "once")
})

test_that("a store carrying the source record still connects, searches, indexes and describes", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  src <- as.character(local_ragnar_store()@location)
  copy <- withr::local_tempfile(fileext = ".duckdb")
  stopifnot(file.copy(src, copy))
  con <- DBI::dbConnect(duckdb::duckdb(), copy)
  .crd_sources_write(con, "storage/TOYKEY01/doc.pdf", "m1")
  DBI::dbDisconnect(con, shutdown = TRUE)

  before <- suppressWarnings(.crd_store_describe(src))
  after <- suppressWarnings(.crd_store_describe(copy))
  expect_identical(after[c("documents", "chunks", "embedding_size", "embedding_model")],
                   before[c("documents", "chunks", "embedding_size", "embedding_model")])

  store <- ragnar::ragnar_store_connect(copy, read_only = FALSE)
  ragnar::ragnar_store_build_index(store)
  DBI::dbDisconnect(store@con, shutdown = TRUE)

  store <- suppressMessages(crd_store_connect(copy, verify = FALSE))
  on.exit(DBI::dbDisconnect(store@con, shutdown = TRUE), add = TRUE)
  hits <- crd_search(store, .crd_test_query(), top_k = 3L)
  expect_gt(nrow(hits), 0L)
  expect_identical(.crd_sources_read(store@con)$origin_id, "storage/TOYKEY01/doc.pdf")
})
