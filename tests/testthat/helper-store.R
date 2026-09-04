# A real ragnar store, built offline.
#
# Three properties this fixture must have, the first two learned the hard way
# while fixing #27:
#
# 1. It must be retrieved through `ragnar_retrieve()`. Only the hybrid path
#    pivots its metric columns into list columns; `ragnar_retrieve_bm25()`
#    returns atomic long-form columns and is structurally incapable of reaching
#    the failure.
#
# 2. Its documents must be long enough to chunk several times over.
#    `ragnar_retrieve()` defaults to `deoverlap = TRUE`, and it is that merge of
#    adjacent retrieved chunks which puts more than one value in a cell.
#    `as.numeric()` on a list of length-1 scalars works fine — only the
#    multi-element cell throws "'list' object cannot be coerced to type
#    'double'". A fixture of short single-chunk documents yields only length-1
#    cells and passes against the very bug it was written to catch.
#
# 3. `embed` must reference nothing but base R. ragnar sets
#    `environment(embed) <- baseenv()` before serialising it into the store, so
#    a closure over a helper defined in this file resolves at *retrieve* time
#    with "could not find function", in a different test than the one that
#    broke it.
#
# Hybrid retrieval normally means a running Ollama. `ragnar_store_create()`
# accepts any function for `embed`, so a deterministic local one takes the
# identical code path with no network and no model.

# A deterministic stand-in for a real embedding model.
#
# Bins characters by codepoint into a fixed-width vector and normalises. It is
# not a good embedding and is not meant to be — its only jobs are to be the
# right shape, to be stable across runs, and to need nothing beyond base R.
# Similarity rankings from it are meaningless, so the tests assert on column
# types and on how merged rows reduce, never on which passage ranked first.
.crd_test_embed <- function(x) {
  dim_n <- 16L
  t(vapply(x, function(s) {
    v <- numeric(dim_n)
    for (cp in utf8ToInt(tolower(as.character(s)))) {
      v[(cp %% dim_n) + 1L] <- v[(cp %% dim_n) + 1L] + 1
    }
    v <- v + 1e-6
    v / sqrt(sum(v^2))
  }, numeric(dim_n)))
}

# One store per test file. Building it creates a duckdb database, inserts the
# documents and builds both the FTS and VSS indexes, which is far too much to
# repeat once per `test_that()` block.
.crd_store_cache <- new.env(parent = emptyenv())

# Build (or return) the fixture store.
#
# Documents are drawn from a small fish-passage vocabulary at a length that
# reliably chunks into three or more pieces, so retrieval merges some of them
# and the result carries multi-element cells.
#
# `origin` is set through `MarkdownDocument(text, origin = )`; assigning an
# `origin` column on the chunks object instead is silently dropped by ragnar and
# the column comes back all `NA`. The attachment keys are 8 characters so they
# satisfy `.crd_zot_key_from_path()`'s `^[A-Z0-9]{8}$` — note that resolution
# still returns `NA` here, because there is no `zotero.sqlite` under
# `tempdir()`. That is deliberate: these tests cover the retrieval frame, not
# Zotero lookup.
local_ragnar_store <- function() {
  skip_if_not_installed("ragnar")
  skip_if_not_installed("duckdb")

  if (!is.null(.crd_store_cache$store)) return(.crd_store_cache$store)

  vocab <- c("culvert", "barrier", "fish", "passage", "stream", "salmon",
             "habitat", "riparian", "bankfull", "width", "drainage",
             "precipitation", "beaver", "wetland", "coho", "steelhead",
             "crossing", "assessment", "migration", "temperature", "shade",
             "channel")

  path <- tempfile(fileext = ".duckdb")
  store <- ragnar::ragnar_store_create(path, embed = .crd_test_embed, version = 2)

  withr::with_seed(1L, {
    for (i in 1:12) {
      body <- paste(sample(vocab, 400L, replace = TRUE), collapse = " ")
      doc <- ragnar::MarkdownDocument(
        body,
        origin = file.path(tempdir(), "storage", sprintf("TOYKEY%02d", i), "doc.pdf")
      )
      ragnar::ragnar_store_insert(store, ragnar::markdown_chunk(doc))
    }
  })
  ragnar::ragnar_store_build_index(store)

  # Close the writer before opening a reader on the same file: two duckdb
  # instances on one database with differing configuration is the pattern
  # `crd_store_build()` avoids at R/store.R:563, and leaving it open leaks the
  # connection and can block the tempfile being removed.
  DBI::dbDisconnect(store@con, shutdown = TRUE)

  con <- ragnar::ragnar_store_connect(path, read_only = TRUE)
  withr::defer({
    try(DBI::dbDisconnect(con@con, shutdown = TRUE), silent = TRUE)
    unlink(path)
  }, envir = testthat::teardown_env())

  .crd_store_cache$store <- con
  con
}

# The query the regression tests share, so the premise test and the behaviour
# test are provably asking the store the same thing.
.crd_test_query <- function() "culvert fish passage barrier"

# top_k for the regression tests. Chosen because it is the smallest value at
# which this fixture produces a merged, multi-element cell — the shape the bug
# needs. `.crd_test_multi_row()` asserts that rather than trusting it.
.crd_test_top_k <- function() 10L
