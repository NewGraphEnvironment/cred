# Tests for #29 — what crd_search() says when hybrid retrieval fails.
#
# Before #29 the hybrid branch caught every error and prescribed one remedy:
# start Ollama. That is right for one of the four ways retrieval fails, wrong
# for the others, and actively misleading for an embedding-dimension mismatch —
# which means the store was built against a different model than the one
# answering queries, the exact condition crd_store_connect()'s md5 verification
# exists to catch.
#
# Each fixture here reaches its branch through the real ragnar_retrieve() call
# (see helper-store.R), so these are not assertions about a mocked error object.
# Nothing below needs Ollama except the one block that says so.

# --- premise: the fixtures reach the branches they claim to ----------------
# Classification is only as good as the shapes it dispatches on, and those
# shapes come from ragnar and httr2, not from this package. If an upstream
# change moves them, these tests fail naming the cause rather than letting the
# behaviour tests below pass for the wrong reason.

test_that("the connection fixture raises an httr2_failure through ragnar_retrieve()", {
  store <- local_ragnar_store_failing("connection")
  cnd <- tryCatch(
    ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = 3L),
    error = function(e) e
  )
  expect_s3_class(cnd, "error")
  # The class, not the message. This is the whole basis for dispatching on
  # class rather than regex-matching curl's wording.
  expect_s3_class(cnd, "httr2_failure")
  expect_false(inherits(cnd, "httr2_http"))
})

test_that("the dimension fixture raises a bare error naming array_cosine_distance", {
  store <- local_ragnar_store_failing("dimension")
  cnd <- tryCatch(
    ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = 3L),
    error = function(e) e
  )
  expect_s3_class(cnd, "error")
  # This is the one branch with no distinguishing class — it is a duckdb binder
  # error — so the regex is load-bearing and the text it matches is pinned here.
  expect_false(inherits(cnd, "httr2_error"))
  expect_match(conditionMessage(cnd), "array_cosine_distance")
  expect_match(conditionMessage(cnd), "same size")
})

test_that("the unknown fixture raises an error carrying none of the known shapes", {
  store <- local_ragnar_store_failing("unknown")
  cnd <- tryCatch(
    ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = 3L),
    error = function(e) e
  )
  expect_s3_class(cnd, "error")
  expect_false(inherits(cnd, "httr2_error"))
  expect_no_match(conditionMessage(cnd), "array_cosine_distance")
})

test_that("the model fixture raises an httr2_http error when Ollama is running", {
  # The only shape that needs a live server: it has to answer in order to
  # answer 404. Skipped rather than mocked, because a mocked 404 would not
  # confirm that httr2's class reaches us through ragnar.
  skip_if_not(.crd_ollama_reachable(), "no local Ollama answering")
  store <- local_ragnar_store_failing("model")
  cnd <- tryCatch(
    ragnar::ragnar_retrieve(store, .crd_test_query(), top_k = 3L),
    error = function(e) e
  )
  expect_s3_class(cnd, "httr2_http")
  # Reachable but refusing — so it must NOT be classified as a connection
  # failure, which is the distinction the old catch-all could not make.
  expect_false(inherits(cnd, "httr2_failure"))
})

# --- the classifier, both directions --------------------------------------
# Hand-built conditions here, deliberately. The premise tests above pin the
# real shapes; these pin the dispatch, including the branches a real fixture
# cannot reach on a machine with no Ollama.

test_that(".crd_retrieval_failure separates a connection failure from everything else", {
  conn <- rlang::error_cnd(
    class = c("httr2_failure", "httr2_error", "rlang_error"),
    message = "Failed to perform HTTP request."
  )
  expect_identical(.crd_retrieval_failure(conn), "connection")

  # A provider that is not httr2-based still has to classify, so the message
  # patterns are a second route to the same answer, not the primary one.
  expect_identical(
    .crd_retrieval_failure(simpleError("Failed to connect to localhost port 11434: Connection refused")),
    "connection"
  )
  expect_identical(
    .crd_retrieval_failure(simpleError("Could not resolve host: localhost")),
    "connection"
  )
  expect_identical(
    .crd_retrieval_failure(simpleError("Timeout was reached: Operation timed out")),
    "connection"
  )
})

test_that(".crd_retrieval_failure classifies an HTTP response as a service refusal", {
  # The service answered. Whatever is wrong, it is not that Ollama is down, so
  # this must not land in "connection".
  http <- rlang::error_cnd(
    class = c("httr2_http_404", "httr2_http", "httr2_error", "rlang_error"),
    message = 'HTTP 404 Not Found.\nmodel "nomic-embed-text" not found, try pulling it first'
  )
  expect_identical(.crd_retrieval_failure(http), "model")

  # Not only 404 — any status means reachable-but-refused.
  expect_identical(
    .crd_retrieval_failure(rlang::error_cnd(
      class = c("httr2_http_500", "httr2_http", "httr2_error", "rlang_error"),
      message = "HTTP 500 Internal Server Error."
    )),
    "model"
  )
})

test_that(".crd_retrieval_failure classifies an embedding-width mismatch", {
  expect_identical(
    .crd_retrieval_failure(simpleError(
      "Binder Error: array_cosine_distance: Array arguments must be of the same size"
    )),
    "dimension"
  )
  # The same mismatch seen from the write side, which is the message a store
  # whose embedding column disagrees with its embedder produces on insert.
  expect_identical(
    .crd_retrieval_failure(simpleError(
      "Conversion Error: Cannot cast array of size 16 to array of size 8 when casting from source column embedding"
    )),
    "dimension"
  )
})

test_that(".crd_retrieval_failure falls through to 'unknown' rather than guessing", {
  expect_identical(
    .crd_retrieval_failure(simpleError("Catalog Error: Index 'vss_idx' does not exist")),
    "unknown"
  )
  expect_identical(.crd_retrieval_failure(simpleError("")), "unknown")
})

test_that("a dimension mismatch is not misread as a connection failure", {
  # The regression that matters most, stated as its own assertion rather than
  # inferred from the positive cases: before #29 every one of these answered
  # "the connection is down, start Ollama".
  for (msg in c("Binder Error: array_cosine_distance: Array arguments must be of the same size",
                "Catalog Error: Index 'vss_idx' does not exist",
                "HTTP 404 Not Found.")) {
    expect_false(.crd_retrieval_failure(simpleError(msg)) == "connection")
  }
})

# --- the message says the right thing, and not the wrong thing ------------

test_that("only a connection failure is told to start Ollama", {
  conn <- .crd_retrieval_fallback_msg("connection", simpleError("Connection refused"))
  expect_match(conn, "ollama serve")

  # The claim of #29, as an assertion. A message that prescribes starting a
  # service that is already running is worse than one that prescribes nothing.
  for (reason in c("dimension", "unknown")) {
    msg <- .crd_retrieval_fallback_msg(reason, simpleError("something went wrong"))
    expect_no_match(msg, "ollama serve")
    expect_no_match(msg, "(?i)start ollama", perl = TRUE)
  }
})

test_that("a dimension mismatch points at store verification, not at Ollama", {
  msg <- .crd_retrieval_fallback_msg(
    "dimension",
    simpleError("Binder Error: array_cosine_distance: Array arguments must be of the same size")
  )
  expect_match(msg, "crd_store_connect")
  # Says what is actually wrong, in the words this package already uses for it.
  expect_match(msg, "(?i)embedding model", perl = TRUE)
  expect_no_match(msg, "ollama serve")
})

test_that("a service refusal names the pull, not the start", {
  msg <- .crd_retrieval_fallback_msg(
    "model",
    simpleError('HTTP 404 Not Found.\nmodel "nomic-embed-text" not found, try pulling it first')
  )
  expect_match(msg, "ollama pull")
  # Ollama answered, so telling the user to start it is the wrong half of the
  # old advice.
  expect_no_match(msg, "ollama serve")
})

test_that("every message reports the underlying condition verbatim", {
  # The old message did get this right, and the fix must not lose it: the
  # condition text is the only thing that can diagnose an unrecognised failure.
  for (reason in c("connection", "model", "dimension", "unknown")) {
    msg <- .crd_retrieval_fallback_msg(reason, simpleError("a very distinctive cause"))
    expect_match(msg, "a very distinctive cause", fixed = TRUE)
  }
})

test_that("the dimension message reports the store's own recorded width", {
  # Naming what the store was built at is the difference between "something is
  # mismatched" and "this store is 16-wide and your model is not".
  store <- local_ragnar_store()
  msg <- .crd_retrieval_fallback_msg(
    "dimension",
    simpleError("Binder Error: array_cosine_distance: Array arguments must be of the same size"),
    store = store
  )
  expect_match(msg, "16")
})

test_that("the dimension message degrades rather than failing when metadata is unreadable", {
  # A store whose metadata cannot be read must still produce a warning. An
  # error raised while BUILDING a warning would convert a recoverable fallback
  # into a hard failure — strictly worse than the bug being fixed.
  expect_no_error(
    msg <- .crd_retrieval_fallback_msg("dimension", simpleError("mismatch"),
                                       store = "not a store at all")
  )
  expect_match(msg, "crd_store_connect")
})

# --- crd_search(), end to end on each failure shape -----------------------

test_that("crd_search() warns with a reason-specific class and still returns BM25 rows", {
  store <- local_ragnar_store_failing("connection")
  local_reset_fallback_warnings(store)

  # Assert on the class, not the text. A test that greps an interpolated
  # message cannot see the claim around it, and the class is the part a caller
  # can act on programmatically.
  expect_warning(
    out <- crd_search(store, .crd_test_query(), top_k = 3L),
    class = "cred_retrieval_fallback_connection"
  )
  expect_s3_class(out, "tbl_df")
  expect_gt(nrow(out), 0L)
  # The fallback is reported, so a caller can tell the search degraded.
  expect_identical(unique(out$method), "bm25")
  expect_identical(unique(out$metric), "bm25")
})

test_that("crd_search() reports a dimension mismatch as its own reason", {
  store <- local_ragnar_store_failing("dimension")
  local_reset_fallback_warnings(store)

  cnd <- NULL
  out <- withCallingHandlers(
    crd_search(store, .crd_test_query(), top_k = 3L),
    cred_retrieval_fallback = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(cnd, "cred_retrieval_fallback_dimension")
  expect_match(conditionMessage(cnd), "crd_store_connect")
  expect_no_match(conditionMessage(cnd), "ollama serve")
  expect_gt(nrow(out), 0L)
  expect_identical(unique(out$method), "bm25")
})

test_that("crd_search() falls back on an unrecognised failure without prescribing a remedy", {
  store <- local_ragnar_store_failing("unknown")
  local_reset_fallback_warnings(store)

  cnd <- NULL
  out <- withCallingHandlers(
    crd_search(store, .crd_test_query(), top_k = 3L),
    cred_retrieval_fallback = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(cnd, "cred_retrieval_fallback_unknown")
  expect_no_match(conditionMessage(cnd), "ollama serve")
  expect_match(conditionMessage(cnd), "vss_idx")
  expect_gt(nrow(out), 0L)
  expect_identical(unique(out$method), "bm25")
})

test_that("a successful hybrid search warns about nothing", {
  # The control. A fallback warning that fires on a healthy store would be the
  # noise problem of #29 made permanent.
  store <- local_ragnar_store()
  expect_no_condition(
    out <- crd_search(store, .crd_test_query(), top_k = .crd_test_top_k()),
    class = "cred_retrieval_fallback"
  )
  expect_identical(unique(out$method), "hybrid")
})

# --- the frequency guard ---------------------------------------------------

test_that("the fallback warning fires once per session, not once per call", {
  store <- local_ragnar_store_failing("connection")
  local_reset_fallback_warnings(store)

  expect_warning(crd_search(store, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_connection")
  # Second identical call: same store, same reason, so nothing new to say.
  # Without a frequency guard this four-line warning repeats on every search.
  expect_no_condition(out <- crd_search(store, .crd_test_query(), top_k = 3L),
                      class = "cred_retrieval_fallback")
  # Silence is the only thing suppressed — the result still reports the fallback.
  expect_identical(unique(out$method), "bm25")
})

test_that("two different failures do not collapse into one warning", {
  # The guard has to be keyed per reason as well as per store. Keyed on the
  # store alone, a dimension mismatch encountered after a connection failure
  # would be silently swallowed — which is the diagnosis loss of #29 arriving
  # by a different route.
  conn <- local_ragnar_store_failing("connection")
  dim_store <- local_ragnar_store_failing("dimension")
  local_reset_fallback_warnings(conn)

  expect_warning(crd_search(conn, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_connection")
  expect_warning(crd_search(dim_store, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_dimension")
})

test_that("the frequency id varies with the reason and with the store", {
  store <- local_ragnar_store()
  ids <- vapply(c("connection", "model", "dimension", "unknown"),
                function(r) .crd_retrieval_fallback_id(r, store), character(1))
  expect_length(unique(ids), 4L)

  # And a store with no readable location still yields a usable id rather than
  # erroring inside the warning path.
  expect_no_error(id <- .crd_retrieval_fallback_id("connection", NULL))
  expect_type(id, "character")
  expect_length(id, 1L)
})
