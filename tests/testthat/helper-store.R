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
  # A version floor, not decoration: the fixture uses v2-only API
  # (`MarkdownDocument`, `markdown_chunk`, `version = 2`) and DESCRIPTION carries
  # an unpinned `Remotes: tidyverse/ragnar`, so an older install would ERROR
  # every test here rather than skip them.
  skip_if_not_installed("ragnar", "0.3.0")
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

# top_k for the regression tests.
#
# Any value from 3 upward produces a merged, multi-element cell on this fixture
# — the shape the bug needs. Measured multi-element rows by top_k:
# 3->1, 5->2, 6->4, 8->4, 10->5, 12->6, 20->8. 10 is chosen for the margin, not
# because it is a floor: if the premise assertion in test-store-search.R ever
# goes red, raising this is papering over an upstream change, not a fix.
.crd_test_top_k <- function() 10L

# --- Failure-shape fixtures for #29 ---------------------------------------
#
# `crd_search(method = "hybrid")` falls back to BM25 when semantic retrieval
# fails, and the point of #29 is that the four ways it can fail need four
# different things said about them. Each fixture below reaches one of those
# ways through the REAL `ragnar_retrieve()` call — no mocked bindings, no
# hand-built conditions — by replacing the store's `embed` function.
#
# Three facts make this work, all measured (see planning findings for #29):
#
# 1. `ragnar_store_connect()` returns an S7 object whose `embed` property is
#    settable, and setting it on a copy does NOT reach the original (the
#    property is plain -- no getter, setter or validator -- so it is
#    copy-on-modify). Verified: after a copy's `embed` is broken, the original
#    still retrieves on the same connection.
#
#    The duckdb connection, though, is the one thing that IS shared, because
#    `.crd_store_cache` holds the connected object rather than a path to
#    reconnect from. A copy's `@embed` cannot corrupt the cached store; closing
#    a copy's `@con` would kill retrieval for every later block in the run, in
#    whatever file reaches it next. Do not disconnect a failure copy.
#
# 2. The condition raised by `embed` propagates out of `ragnar_retrieve()` with
#    its class intact — ragnar does not catch and re-wrap it. That is what lets
#    the classifier dispatch on `httr2_failure` rather than on message text.
#
# 3. The `baseenv()` constraint documented at the top of this file does NOT
#    apply here. It binds `embed` functions passed to `ragnar_store_create()`,
#    which ragnar serialises into the store; an `embed` assigned onto an
#    already-connected store lives only in this session.
#
# `reason` names the branch the fixture is meant to reach, and the premise test
# in test-store-fallback.R asserts that it actually reaches it. If ragnar or
# httr2 changes shape, that test fails naming the cause rather than letting a
# behaviour test pass for the wrong reason.
local_ragnar_store_failing <- function(reason = c("connection", "model",
                                                  "dimension", "unknown")) {
  reason <- match.arg(reason)
  store <- local_ragnar_store()

  broken <- switch(
    reason,
    # Loopback port 1: refused immediately by the kernel. This is not a network
    # test — nothing leaves the machine and there is no timeout to wait out.
    connection = ragnar::embed_ollama(model = "nomic-embed-text",
                                      base_url = "http://127.0.0.1:1/"),
    # The one shape that CANNOT be reached without a running Ollama: the server
    # has to answer in order to answer 404. Its test skips accordingly.
    model = ragnar::embed_ollama(model = "cred-no-such-model-29"),
    # A different width than the store was built with, which is what a store
    # built against one embedding model and queried through another amounts to.
    # duckdb rejects it in the binder, as a plain error with no useful class.
    dimension = .crd_test_embed_narrow,
    # Stands in for everything else: a corrupt index, a duckdb catalog problem,
    # a provider raising something unforeseen.
    unknown = function(x) stop("Catalog Error: Index 'vss_idx' does not exist")
  )

  store@embed <- broken
  store
}

# Half the width of `.crd_test_embed`, and otherwise identical. The store is
# built at 16; querying it at 8 is the dimension mismatch.
#
# The mismatch has to be induced on an already-built store, not by an embedder
# whose width varies with its input: `ragnar_store_create()` fixes the embedding
# column at `ncol(embed("foo"))`, so a varying embedder fails at INSERT with a
# cast error instead, which is a different condition in a different place.
.crd_test_embed_narrow <- function(x) {
  dim_n <- 8L
  t(vapply(x, function(s) {
    v <- numeric(dim_n)
    for (cp in utf8ToInt(tolower(as.character(s)))) {
      v[(cp %% dim_n) + 1L] <- v[(cp %% dim_n) + 1L] + 1
    }
    v <- v + 1e-6
    v / sqrt(sum(v^2))
  }, numeric(dim_n)))
}

# A store whose recorded embedder names a model.
#
# `.crd_store_model_from_meta()` unserialises `metadata.embed_func` and regexes
# `model = "..."` out of its DEPARSED text, so a fixture reaches that path with
# no Ollama and no network as long as the literal appears in the function body.
# Without this, every message that names the store's model falls through to the
# hardcoded default and a mutation stubbing the lookup out stays green.
#
# The literal must NOT be `nomic-embed-text`, which is `.crd_fallback_model()`'s
# hardcoded last-resort default. With the two the same, every assertion that the
# store's recorded model reaches a message passes identically whether the lookup
# works or has been deleted — measured: removing the store-recorded tier
# entirely left the whole suite green at 502 passes. The fixture, not the
# assertion, was the thing that could not fail.
#
# The literal has to appear as `model = "..."`, which means a defaulted formal
# rather than a `model <- "..."` in the body: the regex wants `=`, and R's
# deparser preserves `<-` as `<-`. A defaulted formal is also the shape
# `ragnar::embed_ollama()` itself has, so the fixture matches what it stands in
# for. `deparse()` on a FUNCTION includes its signature — unlike
# `deparse(body(f))`, which would not.
#
# `embed` is serialised into the store by `ragnar_store_create()`, so this must
# reference nothing outside base R (see property 3 at the top of this file).
.crd_test_embed_named <- function(x, model = "mxbai-embed-large") {
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

# A small store built with that embedder, for the messages that quote what the
# store records. Separate from the main fixture so the #27 regression tests keep
# the store they were measured against.
.crd_named_cache <- new.env(parent = emptyenv())

local_ragnar_store_named <- function() {
  skip_if_not_installed("ragnar", "0.3.0")
  skip_if_not_installed("duckdb")
  if (!is.null(.crd_named_cache$store)) return(.crd_named_cache$store)

  path <- tempfile(fileext = ".duckdb")
  store <- ragnar::ragnar_store_create(path, embed = .crd_test_embed_named,
                                       version = 2)
  withr::with_seed(2L, {
    for (i in 1:4) {
      body <- paste(sample(c("culvert", "barrier", "fish", "passage", "stream",
                             "habitat", "bankfull", "width"),
                           400L, replace = TRUE), collapse = " ")
      ragnar::ragnar_store_insert(store, ragnar::markdown_chunk(
        ragnar::MarkdownDocument(body,
          origin = file.path(tempdir(), "named", sprintf("NAMEKY%02d", i), "doc.pdf"))
      ))
    }
  })
  ragnar::ragnar_store_build_index(store)
  DBI::dbDisconnect(store@con, shutdown = TRUE)

  con <- ragnar::ragnar_store_connect(path, read_only = TRUE)
  withr::defer({
    try(DBI::dbDisconnect(con@con, shutdown = TRUE), silent = TRUE)
    unlink(path)
  }, envir = testthat::teardown_env())

  .crd_named_cache$store <- con
  con
}

# Is a local Ollama answering? Only the "model" fixture needs one.
#
# `skip_on_cran()` would be wrong here and `skip_if_offline()` insufficient:
# the first does not skip under `devtools::test()` or on GitHub Actions, and the
# second reports whether the network is up, not whether this service is.
.crd_ollama_reachable <- function(base_url = "http://127.0.0.1:11434") {
  isTRUE(tryCatch({
    con <- url(file.path(base_url, "api", "tags"), open = "rb")
    on.exit(close(con), add = TRUE)
    length(readBin(con, "raw", 1L)) > 0L
  }, error = function(e) FALSE, warning = function(w) FALSE))
}

# For a block that must SEE the warning: turn the frequency guard off for the
# duration, rather than resetting state around it.
#
# `rlang:::needs_signal()` returns TRUE under verbosity "verbose" BEFORE it
# pokes the once-per-session sentinel, so this is complete isolation with no
# state to leak -- and it does not couple the test to the key scheme it is
# supposed to be policing. The sentinel environment is package-level and
# helpers are sourced once per run, so leakage otherwise crosses test FILES.
#
# The option is `rlib_warning_verbosity`, not `rlang_warning_verbosity`.
local_fallback_warnings_always <- function(env = parent.frame()) {
  withr::local_options(rlib_warning_verbosity = "verbose", .local_envir = env)
}

# For the two blocks that are ABOUT the frequency guard, which therefore cannot
# switch it off: re-arm the ids before and after, so the block is independent of
# whatever ran before it.
#
# `rlang::reset_warning_verbosity()` takes a required id -- it calls
# `check_string(id, allow_empty = FALSE)` -- so there is no "reset everything"
# call and the ids have to be derived.
local_reset_fallback_warnings <- function(store, env = parent.frame()) {
  for (r in .crd_fallback_reasons()) {
    rlang::reset_warning_verbosity(.crd_retrieval_fallback_id(r, store))
  }
  withr::defer({
    for (r in .crd_fallback_reasons()) {
      rlang::reset_warning_verbosity(.crd_retrieval_fallback_id(r, store))
    }
  }, envir = env)
}

# Every reason the classifier can return, so a helper that loops over them
# cannot drift from the classifier by one branch.
.crd_fallback_reasons <- function() {
  c("connection", "model", "service", "dimension", "unknown")
}
