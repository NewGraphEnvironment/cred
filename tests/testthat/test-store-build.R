# Tests for #35 — a store build that finishes past an unreadable PDF and a
# chunk the embedding model will not take.
#
# Two failures, both measured on real PDFs against Ollama 0.24.0 and
# `nomic-embed-text` (see research/ollama-embedding-context.md):
#
# - A run of `•` glyphs costs 2 tokens a character, and Ollama answers 400
#   ("the input length exceeds the context length") instead of truncating it.
#   ragnar re-embeds a worker's failed chunks in the main process with no
#   handler, so one such chunk ended the whole build.
# - markitdown's text for some PDFs carries a NUL, which R cannot hold, so
#   `read_as_markdown()` errors and the paper was dropped.
#
# The unit tests call `prepare` in this process with a plain-text reader, so
# they need neither markitdown nor Ollama. The end-to-end tests go through the
# real `ragnar_store_ingest()`, whose mirai workers receive `prepare` serialised:
# that is the only place a closure over a cred helper fails.

# A 400 shaped as `ragnar::embed_ollama()` raises it (class measured against a
# live Ollama: httr2_http_400 / httr2_http / httr2_error / rlang_error / error).
# Built from base R only, so it can be inlined into a worker-bound embed.
.crd_test_http_400 <- function() {
  structure(
    class = c("httr2_http_400", "httr2_http", "httr2_error", "rlang_error", "error", "condition"),
    list(message = "HTTP 400 Bad Request.\nthe input length exceeds the context length", call = NULL)
  )
}

# An embed that refuses any input longer than `limit` characters, as Ollama
# refuses an over-long glyph run, and otherwise embeds as `.crd_test_embed`.
# Built in baseenv() with the limit inlined, because ragnar re-parents a
# store's embed to baseenv() and the workers receive it serialised.
.crd_test_embed_limited <- function(limit) {
  eval(bquote(function(x) {
    if (any(nchar(x) > .(limit))) {
      stop(structure(
        class = c("httr2_http_400", "httr2_http", "httr2_error", "rlang_error", "error", "condition"),
        list(message = "HTTP 400 Bad Request.\nthe input length exceeds the context length",
             call = NULL)
      ))
    }
    dim_n <- 16L
    t(vapply(x, function(s) {
      v <- numeric(dim_n)
      for (cp in utf8ToInt(tolower(as.character(s)))) {
        v[(cp %% dim_n) + 1L] <- v[(cp %% dim_n) + 1L] + 1
      }
      v <- v + 1e-6
      v / sqrt(sum(v^2))
    }, numeric(dim_n)))
  }), baseenv())
}

# Reads a text file as a MarkdownDocument without markitdown, so the tests need
# no Python. Base R and ragnar only, for the same reason as the embed above.
.crd_test_read_text <- eval(quote(function(path) {
  ragnar::MarkdownDocument(paste(readLines(path, warn = FALSE), collapse = "\n"),
                           origin = path)
}), baseenv())

.crd_test_doc <- function(text, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  path <- tempfile(tmpdir = dir, fileext = ".md")
  writeLines(text, path)
  path
}

.crd_test_prose <- function(n = 300L, seed = 1L) {
  vocab <- c("culvert", "barrier", "fish", "passage", "stream", "salmon", "habitat",
             "riparian", "bankfull", "width", "beaver", "wetland", "coho", "channel")
  withr::with_seed(seed, paste(sample(vocab, n, replace = TRUE), collapse = " "))
}

# The notes directory `prepare` writes each document's notes file into.
.crd_test_log <- function(env = parent.frame()) {
  withr::local_tempdir(.local_envir = env)
}

.crd_test_notes <- function(log) .crd_ingest_notes(log)

# Every character any chunk covered before is covered after, and every row's
# text is exactly its range of the document: ragnar's v2 store rejects a chunk
# whose `text` differs from `stri_sub(document, start, end)`.
expect_chunks_consistent <- function(chunks) {
  doc <- as.character(chunks@document)
  expect_identical(chunks$text, substring(doc, chunks$start, chunks$end))
}

covered <- function(chunks) {
  sort(unique(unlist(Map(seq.int, chunks$start, chunks$end))))
}

test_that("prepare is self-contained, so a mirai worker can run it without cred", {
  skip_if_not_installed("ragnar", "0.3.0")
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(5000L), .crd_test_log())

  # A closure whose environment chains to the cred namespace is serialised as a
  # reference to it, and a worker resolves that by loading the INSTALLED cred,
  # which under devtools::test() is not the code under test.
  expect_identical(topenv(environment(prepare)), baseenv())
  fns <- Filter(is.function, as.list(environment(prepare)))
  expect_gt(length(fns), 0L)
  for (f in fns) expect_identical(topenv(environment(f)), baseenv())
})

test_that("prepare embeds every chunk when the model takes them all", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  path <- .crd_test_doc(.crd_test_prose(1200L))
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(5000L), log,
                                 read = .crd_test_read_text)

  chunks <- prepare(path)
  expect_s3_class(chunks, "ragnar::MarkdownDocumentChunks")
  expect_gt(nrow(chunks), 1L)
  expect_identical(nrow(chunks$embedding), nrow(chunks))
  expect_chunks_consistent(chunks)
  expect_identical(nrow(.crd_test_notes(log)), 0L)
})

test_that("prepare reads with pdftools when the markdown reader fails, and says so", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  pdf <- system.file("extdata", "storage", "TOYPDF1", "salmon_habitat.pdf", package = "cred")
  expect_true(nzchar(pdf))
  nul <- eval(quote(function(path) stop("Embedded NUL in string.")), baseenv())
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(5000L), log, read = nul)

  chunks <- prepare(pdf)
  doc <- as.character(chunks@document)
  expect_identical(doc, paste(pdftools::pdf_text(pdf), collapse = "\n\n"))
  expect_identical(chunks@document@origin, pdf)
  expect_identical(nrow(chunks$embedding), nrow(chunks))

  notes <- .crd_test_notes(log)
  expect_identical(notes$kind, "read_pdftools")
  expect_identical(notes$origin, pdf)
  expect_match(notes$detail, "Embedded NUL", fixed = TRUE)
})

test_that("prepare splits a chunk the model refuses until each part embeds", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  # A glyph run inside prose, as the dot-plot figure sat inside ESL's text.
  text <- paste(.crd_test_prose(200L), "\n\n", strrep("•", 1500L), "\n\n",
                .crd_test_prose(200L, seed = 2L))
  path <- .crd_test_doc(text)
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(700L), log,
                                 read = .crd_test_read_text)
  whole <- ragnar::markdown_chunk(.crd_test_read_text(path))
  expect_true(any(nchar(paste0(whole$context, "\n", whole$text)) > 700L))

  chunks <- prepare(path)
  expect_chunks_consistent(chunks)
  expect_identical(nrow(chunks$embedding), nrow(chunks))
  expect_gt(nrow(chunks), nrow(whole))
  expect_identical(covered(chunks), covered(whole))

  notes <- .crd_test_notes(log)
  expect_true(all(notes$kind == "chunk_split"))
  expect_true(all(notes$origin == path))
  # One note per refused chunk, however many halvings it took.
  refused <- sum(nchar(ifelse(nzchar(whole$context), paste0(whole$context, "\n", whole$text),
                              whole$text)) > 700L)
  expect_gt(refused, 0L)
  expect_identical(nrow(notes), refused)
})

test_that("each document's notes go to a file of their own", {
  skip_if_not_installed("ragnar", "0.3.0")
  # Parallel workers appending to one shared file splice each other's lines
  # once a document's notes pass 4 KB (more than one write()).
  dir <- .crd_test_log()
  glyphs <- paste(.crd_test_prose(100L), "\n\n", strrep("\u2022", 1500L), "\n\n", .crd_test_prose(100L, 2L))
  paths <- c(.crd_test_doc(glyphs), .crd_test_doc(glyphs))
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(700L), dir, read = .crd_test_read_text)
  for (p in paths) prepare(p)

  files <- list.files(dir, full.names = TRUE)
  expect_length(files, 2L)
  per_file <- vapply(files, function(f) length(unique(sub("\t.*$", "", readLines(f)))), integer(1L))
  expect_true(all(per_file == 1L))
  expect_setequal(.crd_test_notes(dir)$origin, paths)
})

test_that("prepare keeps a range once when halves of neighbouring chunks coincide", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  log <- .crd_test_log()
  # A glyph run several chunks long: markdown_chunk() finds no boundary to snap
  # to inside it, so neighbouring chunks overlap at fixed strides and their
  # halves can repeat a range, which ragnar's v2 store refuses as a duplicate
  # (doc_id, start, end) key on its embeddings table.
  text <- paste(.crd_test_prose(150L), "\n\n", strrep("\u2022", 4000L), "\n\n",
                .crd_test_prose(150L, seed = 2L))
  path <- .crd_test_doc(text)
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(700L), log,
                                 read = .crd_test_read_text)

  chunks <- prepare(path)
  expect_identical(anyDuplicated(data.frame(chunks$start, chunks$end)), 0L)
  store <- ragnar::ragnar_store_create(embed = .crd_test_embed_limited(700L), version = 2)
  withr::defer(DBI::dbDisconnect(store@con, shutdown = TRUE))
  expect_no_error(ragnar::ragnar_store_update(store, chunks))
})

test_that("prepare drops and names a part the model still refuses at the floor", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  text <- paste(.crd_test_prose(300L), "\n\n\u2603\n\n", .crd_test_prose(300L, seed = 2L))
  path <- .crd_test_doc(text)
  # Refuses anything holding one character, which no halving can cut in two,
  # so the part around it is refused all the way down to the floor.
  refuse <- eval(quote(function(x) {
    if (any(grepl("\u2603", x, fixed = TRUE))) {
      stop(structure(class = c("httr2_http_400", "httr2_http", "httr2_error", "error", "condition"),
                     list(message = "HTTP 400 Bad Request.\nthe input length exceeds the context length",
                          call = NULL)))
    }
    matrix(1, nrow = length(x), ncol = 4L)
  }), baseenv())
  prepare <- .crd_ingest_prepare(refuse, log, read = .crd_test_read_text)

  chunks <- prepare(path)
  expect_chunks_consistent(chunks)
  expect_false(any(grepl("\u2603", chunks$text, fixed = TRUE)))
  expect_gt(nrow(chunks), 0L)

  notes <- .crd_test_notes(log)
  expect_true("chunk_dropped" %in% notes$kind)
  dropped <- notes$detail[notes$kind == "chunk_dropped"]
  expect_match(dropped, "characters [0-9]+-[0-9]+")
})

test_that("prepare leaves the chunks unembedded on a failure that is not the input's", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  path <- .crd_test_doc(.crd_test_prose(600L))
  # Connection refused: Ollama is down, which no split can fix. ragnar then
  # re-embeds in the main process with retries and, if that fails too, the
  # build aborts and deletes the store rather than finishing short.
  down <- eval(quote(function(x) {
    stop(structure(class = c("httr2_failure", "httr2_error", "rlang_error", "error", "condition"),
                   list(message = "Failed to perform HTTP request.", call = NULL)))
  }), baseenv())
  prepare <- .crd_ingest_prepare(down, log, read = .crd_test_read_text)

  chunks <- prepare(path)
  expect_false("embedding" %in% names(chunks))
  expect_gt(nrow(chunks), 0L)
  expect_identical(nrow(.crd_test_notes(log)), 0L)
})

test_that("prepare retries a busy server itself, as ragnar's workers do not", {
  skip_if_not_installed("ragnar", "0.3.0")
  # ragnar sets this in every worker; without a retry there, a 429 or 503 hands
  # the chunks back unsplit to a main-process embed that meets the 400.
  withr::local_options(ragnar.embed.req_retry = FALSE)
  log <- .crd_test_log()
  path <- .crd_test_doc(.crd_test_prose(300L))
  needs_retry <- eval(quote(function(x) {
    if (!is.list(getOption("ragnar.embed.req_retry"))) stop("retries are off")
    matrix(1, nrow = length(x), ncol = 4L)
  }), baseenv())
  chunks <- .crd_ingest_prepare(needs_retry, log, read = .crd_test_read_text)(path)
  expect_true("embedding" %in% names(chunks))
  expect_false(getOption("ragnar.embed.req_retry"))
})

test_that("prepare does not split for a 400 that is not about the context length", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  path <- .crd_test_doc(.crd_test_prose(600L))
  # A malformed request or another provider's refusal: splitting every chunk
  # to the floor would cost thousands of requests and fix nothing.
  bad_request <- eval(quote(function(x) {
    stop(structure(class = c("httr2_http_400", "httr2_http", "httr2_error", "error", "condition"),
                   list(message = "HTTP 400 Bad Request.\ninvalid input type", call = NULL)))
  }), baseenv())
  chunks <- .crd_ingest_prepare(bad_request, log, read = .crd_test_read_text)(path)
  expect_false("embedding" %in% names(chunks))
  expect_identical(nrow(.crd_test_notes(log)), 0L)
})

test_that("prepare reports no split when it hands the chunks back unsplit", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  # A refused glyph run first, then, more than ten chunks on, a chunk the
  # service fails on: the split happened in a batch whose result is discarded.
  text <- paste(strrep("\u2022", 1500L), "\n\n", .crd_test_prose(4000L), "\n\nZZDOWN\n\n",
                .crd_test_prose(100L, seed = 2L))
  path <- .crd_test_doc(text)
  embed <- eval(quote(function(x) {
    if (any(grepl("ZZDOWN", x, fixed = TRUE))) {
      stop(structure(class = c("httr2_failure", "httr2_error", "error", "condition"),
                     list(message = "Failed to perform HTTP request.", call = NULL)))
    }
    if (any(nchar(x) > 700L)) {
      stop(structure(class = c("httr2_http_400", "httr2_http", "httr2_error", "error", "condition"),
                     list(message = "HTTP 400 Bad Request.\nthe input length exceeds the context length",
                          call = NULL)))
    }
    matrix(1, nrow = length(x), ncol = 4L)
  }), baseenv())
  whole <- ragnar::markdown_chunk(.crd_test_read_text(path))
  hit <- which(grepl("ZZDOWN", whole$text, fixed = TRUE))
  expect_gt(min(hit), 10L)

  chunks <- .crd_ingest_prepare(embed, log, read = .crd_test_read_text)(path)
  expect_false("embedding" %in% names(chunks))
  expect_identical(nrow(.crd_test_notes(log)), 0L)
})

test_that("prepare skips, with its own class and a note, a document no reader can read", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  bad <- withr::local_tempfile(fileext = ".pdf")
  writeLines("not a pdf", bad)
  nul <- eval(quote(function(path) stop("Embedded NUL in string.")), baseenv())
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(5000L), log, read = nul)

  err <- expect_error(prepare(bad), class = "cred_ingest_skip")
  expect_match(conditionMessage(err), "Embedded NUL", fixed = TRUE)
  notes <- .crd_test_notes(log)
  expect_identical(notes$kind, "skipped")
  expect_identical(notes$origin, bad)
  expect_match(notes$detail, "pdftools", fixed = TRUE)
})

test_that("prepare skips a document with no text rather than storing an empty one", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  path <- .crd_test_doc("   ")
  prepare <- .crd_ingest_prepare(.crd_test_embed_limited(5000L), log,
                                 read = .crd_test_read_text)
  expect_error(prepare(path), class = "cred_ingest_skip")
  expect_identical(.crd_test_notes(log)$kind, "skipped")
})

# --- End to end, through ragnar's mirai workers ------------------------------

local_build_store <- function(embed, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".duckdb", .local_envir = env)
  store <- ragnar::ragnar_store_create(path, embed = embed, version = 2)
  withr::defer(try(DBI::dbDisconnect(store@con, shutdown = TRUE), silent = TRUE), envir = env)
  store
}

test_that("an ingest finishes past an unreadable document and names it", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("mirai")
  dir <- withr::local_tempdir()
  good <- c(.crd_test_doc(.crd_test_prose(800L), dir), .crd_test_doc(.crd_test_prose(800L, 2L), dir))
  bad <- file.path(dir, "unreadable.pdf")
  writeLines("not a pdf", bad)
  reader <- eval(quote(function(path) {
    if (grepl("[.]pdf$", path)) stop("Embedded NUL in string.")
    ragnar::MarkdownDocument(paste(readLines(path, warn = FALSE), collapse = "\n"), origin = path)
  }), baseenv())
  store <- local_build_store(.crd_test_embed_limited(5000L))

  res <- expect_no_warning(
    .crd_store_ingest(store, c(good, bad), read = reader, progress = FALSE)
  )
  expect_setequal(res$ingested, good)
  expect_identical(res$skipped$origin, bad)
  expect_match(res$skipped$reason, "pdftools", fixed = TRUE)
  docs <- DBI::dbGetQuery(store@con, "SELECT origin FROM documents")$origin
  expect_setequal(docs, good)
})

test_that("an ingest finishes past a chunk the model refuses whole", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("mirai")
  dir <- withr::local_tempdir()
  glyphs <- .crd_test_doc(paste(.crd_test_prose(200L), "\n\n", strrep("•", 1500L), "\n\n",
                                .crd_test_prose(200L, 2L)), dir)
  plain <- .crd_test_doc(.crd_test_prose(800L, 3L), dir)
  # The store's own embed refuses the run, as nomic-embed-text does: before #35
  # this ended ragnar_store_ingest() and lost the other document with it.
  store <- local_build_store(.crd_test_embed_limited(700L))

  res <- .crd_store_ingest(store, c(glyphs, plain), read = .crd_test_read_text, progress = FALSE)
  expect_setequal(res$ingested, c(glyphs, plain))
  expect_identical(nrow(res$skipped), 0L)
  expect_true(any(res$notes$kind == "chunk_split" & res$notes$origin == glyphs))

  stored <- DBI::dbGetQuery(store@con, "SELECT origin, start, \"end\" FROM chunks")
  whole <- ragnar::markdown_chunk(.crd_test_read_text(glyphs))
  expect_gt(sum(stored$origin == glyphs), nrow(whole))
})

test_that("an ingest still fails whole when the embedding service is down", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("mirai")
  dir <- withr::local_tempdir()
  docs <- c(.crd_test_doc(.crd_test_prose(800L), dir), .crd_test_doc(.crd_test_prose(800L, 2L), dir))
  # Works for ragnar_store_create()'s width probe, then refuses every request:
  # a server that went away mid-build. Finishing short would hand back a store
  # answering from a fraction of the corpus without saying so.
  flag <- withr::local_tempfile()
  down_after_create <- eval(bquote(function(x) {
    if (file.exists(.(flag))) {
      stop(structure(class = c("httr2_failure", "httr2_error", "rlang_error", "error", "condition"),
                     list(message = "Failed to perform HTTP request.", call = NULL)))
    }
    matrix(1, nrow = length(x), ncol = 4L)
  }), baseenv())
  store <- local_build_store(down_after_create)
  file.create(flag)

  expect_error(
    .crd_store_ingest(store, docs, read = .crd_test_read_text, progress = FALSE),
    class = "httr2_failure"
  )
})

# --- crd_store_build()'s report ----------------------------------------------
#
# Zotero, Ollama and the ingest are replaced: the tests above cover the ingest,
# and these cover only what crd_store_build() says about its result and what it
# leaves on disk.

local_build_mocks <- function(ingest, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  paths <- file.path(dir, c("a.pdf", "b.pdf", "c.pdf"))
  file.create(paths)
  # keyD cites the same file as keyA: one document, two citations.
  create <- ragnar::ragnar_store_create
  local_mocked_bindings(
    .crd_zot_key_pdfs = function(...) {
      list(
        sources = tibble::tibble(citation_key = c("keyA", "keyB", "keyC", "keyD"),
                                 src_path = paths[c(1, 2, 3, 1)]),
        left_out = tibble::tibble(citation_key = character(), item = character(),
                                  title = character(), reason = character())
      )
    },
    .crd_ollama_check = function(...) invisible(NULL),
    .crd_store_ingest = function(store, paths, ...) ingest(unique(paths)),
    .env = env
  )
  local_mocked_bindings(
    ragnar_store_create = function(location, embed, overwrite) {
      create(location, embed = function(x) matrix(1, nrow = length(x), ncol = 4L), version = 2)
    },
    .package = "ragnar", .env = env
  )
  paths
}

no_notes <- function() tibble::tibble(origin = character(), kind = character(), detail = character())

test_that("crd_store_build() names a skipped PDF by key and returns only what it ingested", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  ingest <- function(paths) {
    list(
      ingested = paths[1:2],
      skipped = tibble::tibble(origin = paths[3], reason = "markdown reader: x; pdftools: y"),
      notes = tibble::tibble(origin = paths[c(1, 2, 2)],
                             kind = c("read_pdftools", "chunk_split", "chunk_split"),
                             detail = c("Embedded NUL in string.", "characters 1-900", "characters 901-1800"))
    )
  }
  paths <- local_build_mocks(ingest)
  target <- withr::local_tempfile(fileext = ".duckdb")

  msgs <- character()
  w <- expect_warning(
    withCallingHandlers(
      out <- crd_store_build(target, citation_keys = c("keyA", "keyB", "keyC")),
      message = function(m) {
        msgs <<- c(msgs, conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    ),
    "Skipped 1 PDF"
  )
  expect_match(conditionMessage(w), "keyC (c.pdf): markdown reader: x; pdftools: y", fixed = TRUE)
  expect_identical(out$citation_key, c("keyA", "keyB", "keyD"))
  expect_true(any(grepl("Read with pdftools.*keyA/keyD \\(a.pdf\\): Embedded NUL", msgs)))
  expect_true(any(grepl("Split chunks.*keyB \\(b.pdf\\) \\(2\\)", msgs)))
  expect_true(file.exists(target))
})

test_that("crd_store_build() stops and leaves no store when no PDF could be ingested", {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  ingest <- function(paths) {
    list(
      ingested = character(),
      skipped = tibble::tibble(origin = paths, reason = "no text"),
      notes = no_notes()
    )
  }
  local_build_mocks(ingest)
  target <- withr::local_tempfile(fileext = ".duckdb")

  expect_error(
    suppressMessages(crd_store_build(target, citation_keys = c("keyA", "keyB", "keyC"))),
    "No PDF could be ingested:\n  keyA/keyD (a.pdf): no text", fixed = TRUE
  )
  expect_false(file.exists(target))
})
