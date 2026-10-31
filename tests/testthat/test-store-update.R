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

# --- crd_store_update(), end to end ---------------------------------------
#
# Zotero and Ollama are replaced; the ingest is real: ragnar's mirai workers
# run cred's `prepare` with a text reader and the offline embed, so what an
# update writes is what a build writes. Files sit under `<zotero>/storage/<KEY>/`
# so their origin ids are the ones a real library gives.

local_update_world <- function(env = parent.frame()) {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("mirai")
  world <- new.env()
  world$root <- withr::local_tempdir(.local_envir = env)
  world$keys <- c(keyA = "AAAA1111", keyB = "BBBB2222", keyC = "CCCC3333")
  world$paths <- file.path(world$root, "zotero", "storage", world$keys,
                           paste0(names(world$keys), ".md"))
  names(world$paths) <- names(world$keys)
  for (i in seq_along(world$paths)) {
    dir.create(dirname(world$paths[i]), recursive = TRUE)
    # A word only this document holds, so BM25 can say whether it is in the store.
    writeLines(paste(.crd_test_prose(800L, i), paste0("zzzonly", names(world$keys)[i])),
               world$paths[i])
  }
  world$ingested <- list()

  real_ingest <- .crd_store_ingest
  local_mocked_bindings(
    .crd_zot_key_pdfs = function(citation_keys, ...) {
      list(sources = tibble::tibble(citation_key = citation_keys,
                                    src_path = unname(world$paths[citation_keys])),
           left_out = tibble::tibble(citation_key = character(), item = character(),
                                     title = character(), reason = character()))
    },
    .crd_ollama_check = function(...) invisible(NULL),
    .crd_store_ingest = function(store, paths, read = NULL, progress = FALSE) {
      world$ingested[[length(world$ingested) + 1L]] <- paths
      real_ingest(store, paths, read = .crd_test_read_text, progress = progress)
    },
    .env = env
  )
  create <- ragnar::ragnar_store_create
  local_mocked_bindings(
    ragnar_store_create = function(location, embed, overwrite) {
      create(location, embed = .crd_test_embed, overwrite = overwrite, version = 2)
    },
    .package = "ragnar", .env = env
  )
  world
}

build <- function(world, keys, name = "store.duckdb") {
  path <- file.path(world$root, name)
  suppressMessages(crd_store_build(path, citation_keys = keys, overwrite = TRUE))
  path
}

update <- function(path, keys) {
  msgs <- character()
  out <- withCallingHandlers(
    crd_store_update(path, citation_keys = keys),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  list(out = out, msgs = paste(msgs, collapse = ""))
}

contents <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  origins <- DBI::dbGetQuery(con, "SELECT origin FROM documents")$origin
  rec <- .crd_sources_read(con)
  list(
    ids = sort(.crd_origin_id(origins)),
    rec = if (!is.null(rec)) sort(paste(rec$origin_id, rec$md5)),
    chunks = DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM chunks")$n,
    # The `chunks` view hides an embedding whose document is gone.
    embeddings = DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM embeddings")$n,
    orphans = DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM embeddings
                                    WHERE doc_id NOT IN (SELECT doc_id FROM documents)")$n,
    texts = sort(DBI::dbGetQuery(con, "SELECT text FROM documents")$text)
  )
}

bm25_hits <- function(path, word) {
  store <- ragnar::ragnar_store_connect(path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(store@con, shutdown = TRUE))
  nrow(ragnar::ragnar_retrieve_bm25(store, word, top_k = 50L))
}

test_that("an update holds what a fresh build from the same arguments holds", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  res <- update(path, c("keyB", "keyC"))
  fresh <- build(world, c("keyB", "keyC"), name = "fresh.duckdb")

  expect_identical(contents(path), contents(fresh))
  expect_identical(res$out$citation_key, c("keyB", "keyC"))
  expect_match(res$msgs, "added: 1 | replaced: 0 | removed: 1 | kept: 1", fixed = TRUE)
  # Only the new paper was read and embedded.
  expect_identical(world$ingested[[length(world$ingested) - 1L]], unname(world$paths["keyC"]))
  # The index answers for the added paper and no longer for the removed one.
  expect_gt(bm25_hits(path, "zzzonlykeyC"), 0L)
  expect_identical(bm25_hits(path, "zzzonlykeyA"), 0L)
  expect_false(any(grepl("[.]updating-", list.files(world$root))))
})

test_that("an update ingests a changed file again, and an unchanged one never", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  cat("zzzrevised\n", file = world$paths["keyB"], append = TRUE)
  n <- length(world$ingested)

  res <- update(path, c("keyA", "keyB"))
  expect_identical(world$ingested[[n + 1L]], unname(world$paths["keyB"]))
  expect_match(res$msgs, "added: 0 | replaced: 1 | removed: 0 | kept: 1", fixed = TRUE)
  got <- contents(path)
  expect_length(got$ids, 2L)
  expect_true(any(grepl("zzzrevised", got$texts)))
  expect_identical(got$rec, sort(paste(.crd_origin_id(world$paths[c("keyA", "keyB")]),
                                       unname(tools::md5sum(world$paths[c("keyA", "keyB")])))))
})

test_that("an update with nothing to do leaves the store file untouched", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  before <- tools::md5sum(path)
  mtime <- file.mtime(path)
  n <- length(world$ingested)

  res <- update(path, c("keyA", "keyB"))
  expect_match(res$msgs, "Store is current", fixed = TRUE)
  expect_identical(length(world$ingested), n)
  expect_identical(tools::md5sum(path), before)
  expect_identical(file.mtime(path), mtime)
  expect_identical(res$out$citation_key, c("keyA", "keyB"))
})

test_that("a store built where Zotero lives elsewhere updates without re-ingesting", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  moved <- file.path(world$root, "elsewhere", "Zotero")
  dir.create(moved, recursive = TRUE)
  file.copy(file.path(world$root, "zotero", "storage"), moved, recursive = TRUE)
  world$paths[] <- file.path(moved, "storage", world$keys, paste0(names(world$keys), ".md"))
  n <- length(world$ingested)

  res <- update(path, c("keyA", "keyB"))
  expect_match(res$msgs, "Store is current", fixed = TRUE)
  expect_identical(length(world$ingested), n)

  # And a paper added there joins the documents from here, with nothing removed.
  res <- update(path, c("keyA", "keyB", "keyC"))
  expect_match(res$msgs, "added: 1 | replaced: 0 | removed: 0 | kept: 2", fixed = TRUE)
  expect_length(contents(path)$ids, 3L)
})

test_that("a changed file in a store built elsewhere replaces its old document", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  moved <- file.path(world$root, "elsewhere", "Zotero")
  dir.create(moved, recursive = TRUE)
  file.copy(file.path(world$root, "zotero", "storage"), moved, recursive = TRUE)
  world$paths[] <- file.path(moved, "storage", world$keys, paste0(names(world$keys), ".md"))
  cat("zzzrevised\n", file = world$paths["keyB"], append = TRUE)

  res <- update(path, c("keyA", "keyB"))
  expect_match(res$msgs, "replaced: 1", fixed = TRUE)
  got <- contents(path)
  # One document for keyB, not the old one beside the new.
  expect_identical(got$ids, sort(.crd_origin_id(unname(world$paths[c("keyA", "keyB")]))))
  expect_length(got$texts, 2L)
  expect_true(any(grepl("zzzrevised", got$texts)))
})

test_that("an update that fails part way leaves the store exactly as it was", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  before <- tools::md5sum(path)
  local_mocked_bindings(.crd_store_ingest = function(...) stop("embedding service died"))

  # keyA's removal is made on the copy before the ingest fails.
  expect_error(suppressMessages(crd_store_update(path, citation_keys = c("keyB", "keyC"))),
               "embedding service died")
  expect_identical(tools::md5sum(path), before)
  expect_identical(list.files(world$root), c("store.duckdb", "zotero"))
})

test_that("a store built before records gets one, and says what it cannot vouch for", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  con <- DBI::dbConnect(duckdb::duckdb(), path)
  DBI::dbExecute(con, "DROP TABLE cred_sources")
  DBI::dbDisconnect(con, shutdown = TRUE)
  n <- length(world$ingested)

  res <- update(path, c("keyA", "keyB"))
  expect_match(res$msgs, "Recording the md5 of 2 stored file(s)", fixed = TRUE)
  expect_identical(length(world$ingested), n)
  expect_length(contents(path)$rec, 2L)
  expect_match(update(path, c("keyA", "keyB"))$msgs, "Store is current", fixed = TRUE)
})

test_that("a stored document whose file is not on this machine is kept, and named", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  unlink(world$paths["keyB"])

  res <- update(path, c("keyA", "keyB"))
  expect_match(res$msgs, "Keeping 1 stored document(s) whose file cannot be read on this machine:\n  keyB (keyB.md)",
               fixed = TRUE)
  expect_match(res$msgs, "Store is current", fixed = TRUE)
  expect_length(contents(path)$ids, 2L)
})

test_that("a removal needs no embedder, and an addition stops when it cannot embed", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  connect <- ragnar::ragnar_store_connect
  local_mocked_bindings(
    ragnar_store_connect = function(...) {
      store <- connect(...)
      store@embed <- function(x) stop("Failed to perform HTTP request.")
      store
    },
    .package = "ragnar"
  )
  before <- tools::md5sum(path)
  expect_error(suppressMessages(crd_store_update(path, citation_keys = c("keyA", "keyB", "keyC"))),
               "could not embed, so nothing can be added")
  expect_identical(tools::md5sum(path), before)

  res <- update(path, "keyA")
  expect_match(res$msgs, "removed: 1", fixed = TRUE)
  expect_identical(contents(path)$ids, .crd_origin_id(unname(world$paths["keyA"])))
  # Nothing was ingested, so the index is rebuilt by the update itself.
  expect_identical(bm25_hits(path, "zzzonlykeyB"), 0L)
  expect_gt(bm25_hits(path, "zzzonlykeyA"), 0L)
})

test_that("crd_store_update() refuses a missing store and one with a write-ahead log", {
  skip_if_not_installed("ragnar")
  skip_if_not_installed("duckdb")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "store.duckdb")
  expect_error(crd_store_update(path, citation_keys = "keyA"), "crd_store_build\\(\\) creates one")
  file.create(path, paste0(path, ".wal"))
  err <- expect_error(crd_store_update(path, citation_keys = "keyA"), "write-ahead log")
  # A log left by a process that stopped cannot be closed; the message says how to replay it.
  expect_match(conditionMessage(err), "DBI::dbDisconnect(DBI::dbConnect(duckdb::duckdb(),", fixed = TRUE)
  expect_error(crd_store_update(path), "exactly one of")
})

test_that("a changed file that can no longer be read leaves the store as a build would, and is tried again", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  writeLines(character(), world$paths["keyB"])

  expect_warning(res <- update(path, c("keyA", "keyB")), "Skipped 1 PDF")
  expect_match(res$msgs, "added: 0 | replaced: 0 | removed: 1 | kept: 1", fixed = TRUE)
  fresh <- suppressWarnings(build(world, c("keyA", "keyB"), name = "fresh.duckdb"))
  expect_identical(contents(path), contents(fresh))
  # No md5 is recorded for it, so the next update reads it again.
  n <- length(world$ingested)
  before <- tools::md5sum(path)
  expect_warning(res <- update(path, c("keyA", "keyB")), "Skipped 1 PDF")
  expect_identical(world$ingested[[n + 1L]], unname(world$paths["keyB"]))
  # And finding it still unreadable changes nothing, so the store is not rewritten.
  expect_match(res$msgs, "Store is current", fixed = TRUE)
  expect_identical(tools::md5sum(path), before)
})

test_that("an update refuses to leave the store with no documents", {
  world <- local_update_world()
  path <- build(world, "keyA")
  before <- tools::md5sum(path)
  writeLines(character(), world$paths["keyB"])
  expect_error(suppressWarnings(suppressMessages(crd_store_update(path, citation_keys = "keyB"))),
               "would leave the store with no documents")
  expect_identical(tools::md5sum(path), before)
})

test_that("an updated store that cannot be moved into place leaves the store and no copy", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  before <- tools::md5sum(path)
  local_mocked_bindings(file.rename = function(...) FALSE, .package = "base")
  expect_error(suppressMessages(crd_store_update(path, citation_keys = "keyA")),
               "the store is unchanged")
  expect_identical(tools::md5sum(path), before)
  expect_identical(list.files(world$root), c("store.duckdb", "zotero"))
})

test_that("a missing file no longer resolved is removed, though a resolved one is kept", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  unlink(world$paths["keyB"])
  res <- update(path, "keyA")
  expect_match(res$msgs, "removed: 1", fixed = TRUE)
  expect_identical(contents(path)$ids, .crd_origin_id(unname(world$paths["keyA"])))
})

test_that("after a removal the index scores as a fresh build's does", {
  # A removed document drops out of BM25 results even from a stale index, since
  # results come through the `chunks` view. What a stale index keeps is the
  # removed document's share of the term statistics, so its scores differ.
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB", "keyC"))
  update(path, c("keyA", "keyB"))
  fresh <- build(world, c("keyA", "keyB"), name = "fresh.duckdb")
  scores <- function(p) {
    store <- ragnar::ragnar_store_connect(p, read_only = TRUE)
    on.exit(DBI::dbDisconnect(store@con, shutdown = TRUE))
    res <- ragnar::ragnar_retrieve_bm25(store, "culvert salmon", top_k = 50L)
    sort(round(.crd_flat(res$metric_value, "numeric"), 8))
  }
  expect_identical(scores(path), scores(fresh))
})

test_that("a stored file this machine cannot read is kept like a missing one, recorded or not", {
  skip_on_os("windows")
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  Sys.chmod(world$paths["keyB"], "000")
  withr::defer(Sys.chmod(world$paths["keyB"], "644"))
  if (file.access(world$paths["keyB"], 4L) == 0L) skip("an unreadable file is readable here (root?)")

  res <- update(path, c("keyA", "keyB", "keyC"))
  expect_match(res$msgs, "Keeping 1 stored document(s) whose file cannot be read on this machine:\n  keyB (keyB.md)",
               fixed = TRUE)
  expect_match(res$msgs, "added: 1 | replaced: 0 | removed: 0 | kept: 2", fixed = TRUE)
  expect_length(contents(path)$ids, 3L)

  # A store with no record cannot vouch for it either, and must not record NA.
  con <- DBI::dbConnect(duckdb::duckdb(), path)
  DBI::dbExecute(con, "DROP TABLE cred_sources")
  DBI::dbDisconnect(con, shutdown = TRUE)
  res <- update(path, c("keyA", "keyB", "keyC"))
  expect_match(res$msgs, "Recording the md5 of 2 stored file(s)", fixed = TRUE)
  expect_length(contents(path)$rec, 2L)
})

test_that("an embedder that changed width stops the update with advice that applies to it", {
  world <- local_update_world()
  path <- build(world, c("keyA", "keyB"))
  connect <- ragnar::ragnar_store_connect
  local_mocked_bindings(
    ragnar_store_connect = function(...) {
      store <- connect(...)
      store@embed <- .crd_test_embed_narrow
      store
    },
    .package = "ragnar"
  )
  before <- tools::md5sum(path)
  cnd <- expect_error(suppressMessages(crd_store_update(path, citation_keys = c("keyA", "keyB", "keyC"))),
                      class = "cred_store_embedding_mismatch")
  msg <- conditionMessage(cnd)
  expect_match(msg, "nothing can be added", fixed = TRUE)
  # Connect's advice: neither argument nor manifest belongs to an update.
  expect_no_match(msg, "check_model")
  expect_no_match(msg, "manifest")
  expect_identical(tools::md5sum(path), before)
})

test_that("the remedy for an unrecognised embedder failure fits an update", {
  cond <- simpleError("something odd")
  txt <- .crd_embed_remedy("unknown", cond, context = "update")
  expect_match(txt, "Nothing can\\s+be added")
  expect_no_match(txt, "BM25")
  expect_no_match(txt, "crd_store_connect")
})

test_that("the update probes its embedder once, and never through connect's check", {
  # A second probe can fail where the first succeeded, and connect's check
  # would then warn in connect's words, let the update carry on, and spend
  # connect's once-per-session warning for that store.
  world <- local_update_world()
  path <- build(world, "keyA")
  local_mocked_bindings(.crd_check_store_embedding = function(...) stop("connect's check was called"))
  res <- update(path, c("keyA", "keyB"))
  expect_match(res$msgs, "added: 1", fixed = TRUE)
})
