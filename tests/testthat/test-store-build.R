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

.crd_test_log <- function(env = parent.frame()) {
  log <- withr::local_tempfile(fileext = ".tsv", .local_envir = env)
  file.create(log)
  log
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
  expect_gt(nrow(notes), 0L)
  expect_true(all(notes$kind == "chunk_split"))
  expect_true(all(notes$origin == path))
})

test_that("prepare drops and names a part the model still refuses at the floor", {
  skip_if_not_installed("ragnar", "0.3.0")
  log <- .crd_test_log()
  text <- paste(.crd_test_prose(300L), "\n\nGLYPHRUN\n\n", .crd_test_prose(300L, seed = 2L))
  path <- .crd_test_doc(text)
  # Refuses anything carrying the marker, however short: no split can help.
  refuse <- eval(quote(function(x) {
    if (any(grepl("GLYPHRUN", x, fixed = TRUE))) {
      stop(structure(class = c("httr2_http_400", "httr2_http", "httr2_error", "error", "condition"),
                     list(message = "HTTP 400 Bad Request.", call = NULL)))
    }
    matrix(1, nrow = length(x), ncol = 4L)
  }), baseenv())
  prepare <- .crd_ingest_prepare(refuse, log, read = .crd_test_read_text)

  chunks <- prepare(path)
  expect_chunks_consistent(chunks)
  expect_false(any(grepl("GLYPHRUN", chunks$text, fixed = TRUE)))
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

  n_emb <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM embeddings")$n
  n_chunks <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM chunks")$n
  expect_identical(n_emb, n_chunks)
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
