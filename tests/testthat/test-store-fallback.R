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
  # Pinned against the pattern the classifier actually uses, not a fragment of
  # it. Asserting "same size" matched 9 characters of a 40-character pattern, so
  # an upstream reword that broke classification left THIS test — the one whose
  # whole job is to fail naming the cause — green.
  expect_match(conditionMessage(cnd), .crd_dim_patterns)
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

test_that("every connection pattern classifies on its own", {
  # These patterns are the ONLY classification route for a provider that is not
  # httr2-based — there is no class check behind them. Tested as a set, 7 of the
  # 10 could be deleted with the suite still green, because an earlier string
  # happened to match two of them at once ("Failed to connect" won the
  # alternation in a string written to exercise "Connection refused").
  #
  # So each alternative gets its own string, taken from the wording its own
  # source actually emits.
  for (msg in c("Failed to connect to localhost port 11434",
                "Could not connect to server [127.0.0.1]",
                "Couldn't connect to server",
                "connect: Connection refused",
                "recv failure: Connection reset by peer",
                "Connection timed out after 2000 milliseconds",
                "Could not resolve host: ollama.local",
                "Timeout was reached: Operation too slow",
                "Operation timed out after 5000 milliseconds",
                "Empty reply from server")) {
    expect_identical(.crd_retrieval_failure(simpleError(msg)), "connection",
                     info = msg)
  }
})

test_that(".crd_retrieval_failure separates a missing model from any other HTTP status", {
  # The service answered. Whatever is wrong, it is not that Ollama is down, so
  # neither of these may land in "connection".
  http404 <- rlang::error_cnd(
    class = c("httr2_http_404", "httr2_http", "httr2_error", "rlang_error"),
    message = 'HTTP 404 Not Found.\nmodel "nomic-embed-text" not found, try pulling it first'
  )
  expect_identical(.crd_retrieval_failure(http404), "model")

  # A 404 whose body does NOT name a model is a wrong path, not a missing
  # model — the server may hold every model that was asked for. Classifying it
  # as "model" would assert "not installed" from the status alone and then
  # prescribe pulling something nothing asked for.
  path404 <- rlang::error_cnd(
    class = c("httr2_http_404", "httr2_http", "httr2_error", "rlang_error"),
    message = "HTTP 404 Not Found.\n404 page not found"
  )
  expect_identical(.crd_retrieval_failure(path404), "service")

  # And only 404 means the model is absent. A 500, 503 or 401 has nothing to do
  # with pulling a model, so classifying them together would reinstate the
  # wrong-half-of-the-advice error this issue is about, one level down.
  for (status in c(401L, 403L, 500L, 503L)) {
    cnd <- rlang::error_cnd(
      class = c(paste0("httr2_http_", status), "httr2_http", "httr2_error",
                "rlang_error"),
      message = paste0("HTTP ", status, ".")
    )
    expect_identical(.crd_retrieval_failure(cnd), "service")
  }
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

test_that("an HTTP error that lost its status class is still a service reply", {
  # ragnar::embed_ollama() builds its request with
  # `req_error(body = \(resp) resp_body_json(resp)$error)`, so an error body that
  # is not JSON — an HTML 502 from a reverse proxy — throws inside httr2's own
  # error handler and the condition arrives as a bare rlang_error with no status
  # class on it.
  #
  # Without a message route it lands in "unknown", whose prescription is to
  # confirm the store against the manifest, i.e. re-download it. A wrong and
  # expensive remedy for a proxy hiccup is exactly the defect being fixed.
  expect_identical(
    .crd_retrieval_failure(simpleError("HTTP 502 Bad Gateway.")),
    "service"
  )
  expect_identical(
    .crd_retrieval_failure(simpleError("HTTP 503 Service Unavailable")),
    "service"
  )
  # And a classless 404 naming a model is still a missing model.
  expect_identical(
    .crd_retrieval_failure(simpleError('HTTP 404.\nmodel "nomic-embed-text" not found')),
    "model"
  )
})

test_that("a duckdb error merely NAMING the distance function is not a mismatch", {
  # The pattern set deliberately excludes the bare function name. duckdb raises
  # this when an embedder returns the wrong TYPE or a zero-length vector, which
  # is not a store problem — and the dimension remedy ("treat this store as
  # unverified", "rebuild") is expensive and wrong for it. Matching a substring
  # of a function name to prescribe a rebuild is the same remedy-from-a-guess
  # that #29 exists to remove.
  expect_identical(
    .crd_retrieval_failure(simpleError(paste(
      "Binder Error: No function matches the given name and argument types",
      "'array_cosine_distance(FLOAT[2], INTEGER_LITERAL)'.",
      "You might need to add explicit type casts."
    ))),
    "unknown"
  )

  # And the size phrase classifies without the function name present, so
  # dropping the name costs no coverage. ragnar's other metrics raise the same
  # phrase from a differently-named function.
  expect_identical(
    .crd_retrieval_failure(simpleError(
      "Binder Error: array_distance: Array arguments must be of the same size"
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
  # A timeout is deliberately classified as a connection failure, and for one
  # "it is not running" is only half the story — it can be up and loading.
  expect_match(conn, "(?i)loading a model", perl = TRUE)

  # The claim of #29, as an assertion. A message that prescribes starting a
  # service that is already running is worse than one that prescribes nothing.
  for (reason in c("service", "dimension", "unknown")) {
    msg <- .crd_retrieval_fallback_msg(reason, simpleError("something went wrong"))
    expect_no_match(msg, "ollama serve")
    expect_no_match(msg, "(?i)start ollama", perl = TRUE)
  }
})

test_that("a dimension mismatch prescribes a check that can actually see it", {
  msg <- .crd_retrieval_fallback_msg(
    "dimension",
    simpleError("Binder Error: array_cosine_distance: Array arguments must be of the same size")
  )
  # THE assertion of this block, and the one that nearly went the other way.
  # crd_store_connect() verifies md5 against the manifest: it answers "is this
  # the file the manifest describes" and is structurally unable to see a model
  # change, because such a store's bytes are exactly the recorded ones. Sending
  # the user there would be a remedy that cannot detect the condition — which
  # is the defect #29 *is*, reintroduced inside its own fix.
  expect_no_match(msg, "crd_store_connect")
  expect_match(msg, "crd_store_build", fixed = TRUE)
  expect_match(msg, "embed_ollama", fixed = TRUE)

  # Says what is actually wrong, narrowly. A connected store embeds queries with
  # its own recorded embedder, so the claim is about the model that name
  # resolves to, not about the caller having chosen a different one.
  expect_match(msg, "(?i)no longer the model the", perl = TRUE)
  expect_no_match(msg, "ollama serve")
})

test_that("the unknown message may point at crd_store_connect, because md5 CAN see that", {
  # The complement of the test above, and the reason the two are not
  # interchangeable. For an unrecognised failure the file itself is a live
  # suspect — stale, truncated, locally rebuilt — and that is exactly what an
  # md5 compare against the manifest detects.
  msg <- .crd_retrieval_fallback_msg("unknown", simpleError("something odd"))
  expect_match(msg, "crd_store_connect", fixed = TRUE)
  expect_match(msg, "(?i)the file the manifest describes", perl = TRUE)
})

test_that("a missing model names the pull, not the start", {
  msg <- .crd_retrieval_fallback_msg(
    "model",
    simpleError('HTTP 404 Not Found.\nmodel "nomic-embed-text" not found, try pulling it first')
  )
  expect_match(msg, "ollama pull")
  # Ollama answered, so telling the user to start it is the wrong half of the
  # old advice.
  expect_no_match(msg, "ollama serve")
})

test_that("a remedy names the model that was actually refused, not a default", {
  # Telling someone to pull a model nothing ever asked for sends them to fix
  # something that is not broken. The service names the model in its own 404
  # body, so that is the most authoritative source available.
  msg <- .crd_retrieval_fallback_msg(
    "model",
    simpleError('HTTP 404 Not Found.\nmodel "mxbai-embed-large" not found, try pulling it first')
  )
  expect_match(msg, "ollama pull mxbai-embed-large", fixed = TRUE)
  expect_no_match(msg, "nomic-embed-text")
})

test_that("a model name from the service is accepted only if it looks like one", {
  # The name arrives in a remote 404 body and goes into a line the message
  # invites the reader to paste. It is printed, never executed, so this is not
  # about what a hostile string would *do* — it is that a suggested command has
  # to read as the command it is. Measured without the guard:
  # `model "with ' quote" not found` produced `ollama pull with ' quote`.
  expect_true(.crd_is_model_name("nomic-embed-text"))
  expect_true(.crd_is_model_name("library/nomic-embed-text:latest"))
  expect_true(.crd_is_model_name("mxbai-embed-large"))

  expect_false(.crd_is_model_name("with ' quote"))
  expect_false(.crd_is_model_name("a; rm -rf /"))
  expect_false(.crd_is_model_name("$(whoami)"))
  expect_false(.crd_is_model_name("two words"))
  expect_false(.crd_is_model_name("-leading-dash"))
  expect_false(.crd_is_model_name(strrep("x", 200L)))

  # And the composed message falls back rather than quoting it.
  msg <- .crd_retrieval_fallback_msg(
    "model", simpleError('HTTP 404.\nmodel "with \' quote" not found')
  )
  expect_match(msg, "ollama pull nomic-embed-text", fixed = TRUE)
  expect_no_match(msg, "ollama pull with", fixed = TRUE)
})

test_that("the model name the STORE records is guarded too, not only the remote one", {
  # The first version of this guard checked the 404 body and trusted the store,
  # on the reasoning that the store is local and this package wrote it. Both
  # halves are wrong: crd_store_connect() downloads stores from a shared bucket,
  # so "local" describes where the file sits, not who wrote it. The guard existed
  # and sat one branch of the same `if` away, unconsulted.
  bad <- "with ' quote and; semicolon"
  expect_false(.crd_is_model_name(bad))

  fake <- structure(list(model = bad), class = "not_a_store")
  local_mocked_bindings(.crd_store_meta_brief = function(store) {
    list(size = 16L, model = bad)
  })
  for (reason in c("connection", "dimension")) {
    msg <- .crd_retrieval_fallback_msg(reason, simpleError("cause"), store = fake)
    # Nowhere at all, command line or prose. Writing the assertion this wide
    # found a THIRD site: the dimension message's descriptive "records model"
    # line reads the metadata directly rather than through the guarded path.
    expect_no_match(msg, bad, fixed = TRUE)
    expect_match(msg, "nomic-embed-text", fixed = TRUE)
  }

  # And the prose says what it found rather than silently substituting the
  # default, which would misreport what the store actually records.
  msg <- .crd_retrieval_fallback_msg("dimension", simpleError("cause"), store = fake)
  expect_match(msg, "records model a value that is not a model name", fixed = TRUE)
})

test_that("a connection remedy names the store's recorded model, not a hardcoded one", {
  # The branch that kept the old inaccuracy: crd_store_build(model = ) is
  # parameterised and the store records what it used, so naming a constant here
  # would be wrong for any store not built with the default.
  store <- local_ragnar_store_named()
  # Deliberately NOT the package default: with the two literals the same, this
  # block passed whether the store-recorded tier was read or deleted.
  expect_identical(.crd_store_meta_brief(store)$model, "mxbai-embed-large")

  msg <- .crd_retrieval_fallback_msg("connection",
                                     simpleError("Connection refused"),
                                     store = store)
  expect_match(msg, "ollama pull mxbai-embed-large", fixed = TRUE)
  expect_no_match(msg, "nomic-embed-text", fixed = TRUE)
})

test_that("a service error prescribes nothing, because the status is all we know", {
  msg <- .crd_retrieval_fallback_msg("service",
                                     simpleError("HTTP 503 Service Unavailable."))
  expect_no_match(msg, "ollama serve")
  expect_no_match(msg, "ollama pull")
  expect_match(msg, "(?i)running", perl = TRUE)
  expect_match(msg, "HTTP 503 Service Unavailable.", fixed = TRUE)
})

test_that("every message reports the underlying condition verbatim", {
  # The old message did get this right, and the fix must not lose it: the
  # condition text is the only thing that can diagnose an unrecognised failure.
  for (reason in c("connection", "model", "dimension", "unknown")) {
    msg <- .crd_retrieval_fallback_msg(reason, simpleError("a very distinctive cause"))
    expect_match(msg, "a very distinctive cause", fixed = TRUE)
  }
})

test_that("the dimension message reports the width AND model the store records", {
  # Naming what the store was built at is the difference between "something is
  # mismatched" and "this store holds 16-wide embeddings from mxbai-embed-large".
  #
  # The model half needs a store whose serialised embedder actually contains a
  # `model = "..."` literal, because that is what .crd_store_model_from_meta()
  # regexes out of the deparsed function. Asserting only the width let a
  # mutation stubbing the model lookup to NA pass.
  store <- local_ragnar_store_named()
  msg <- .crd_retrieval_fallback_msg(
    "dimension",
    simpleError("Binder Error: array_cosine_distance: Array arguments must be of the same size"),
    store = store
  )
  expect_match(msg, "16-wide", fixed = TRUE)
  expect_match(msg, "records model mxbai-embed-large", fixed = TRUE)
  expect_no_match(msg, "nomic-embed-text", fixed = TRUE)
})

test_that("every message degrades rather than failing when metadata is unreadable", {
  # A store whose metadata cannot be read must still produce a warning. An
  # error raised while BUILDING a warning would convert a recoverable fallback
  # into a hard failure — strictly worse than the bug being fixed, and the
  # stated invariant of .crd_store_meta_brief().
  for (reason in .crd_fallback_reasons()) {
    expect_no_error(
      msg <- .crd_retrieval_fallback_msg(reason, simpleError("mismatch"),
                                         store = "not a store at all")
    )
    expect_match(msg, "mismatch", fixed = TRUE)
  }
})

test_that("a zero-length metadata read does not error inside the message builder", {
  # The specific shape: a metadata table without the column yields NULL, and
  # as.integer(NULL) is integer(0), on which `if (is.na(x))` errors with
  # "argument is of length zero" rather than returning FALSE. The guard has to
  # be a length check, not an is.na() check.
  expect_false(.crd_have(integer(0)))
  expect_false(.crd_have(character(0)))
  expect_false(.crd_have(NA_integer_))
  expect_false(.crd_have(""))
  expect_false(.crd_have(c(1L, 2L)))
  expect_true(.crd_have(16L))
  expect_true(.crd_have("nomic-embed-text"))
})

test_that("a multi-line cause is indented so the remedy does not read as part of it", {
  # httr2 chains its cause across several lines and the later ones arrive flush
  # left. Dropped into an indented message the remedy then reads as more cause,
  # which defeats the separation the message is built around.
  msg <- .crd_retrieval_fallback_msg("connection", simpleError(
    "Failed to perform HTTP request.\nCaused by error:\n! Could not connect"
  ))
  lines <- strsplit(msg, "\n", fixed = TRUE)[[1]]
  cause_at <- grep("Caused by error:", lines, fixed = TRUE)
  expect_length(cause_at, 1L)
  expect_match(lines[cause_at], "^ +", perl = TRUE)
  expect_match(lines[cause_at + 1L], "^ +! Could not connect", perl = TRUE)
})

# --- crd_search(), end to end on each failure shape -----------------------

test_that("crd_search() warns with a reason-specific class and still returns BM25 rows", {
  store <- local_ragnar_store_failing("connection")
  local_fallback_warnings_always()

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
  local_fallback_warnings_always()

  cnd <- NULL
  out <- withCallingHandlers(
    crd_search(store, .crd_test_query(), top_k = 3L),
    cred_retrieval_fallback = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(cnd, "cred_retrieval_fallback_dimension")
  # Not crd_store_connect(): its md5 compare cannot see a model change, so
  # sending the user there is a remedy that cannot detect the condition.
  expect_no_match(conditionMessage(cnd), "crd_store_connect")
  expect_match(conditionMessage(cnd), "crd_store_build", fixed = TRUE)
  expect_no_match(conditionMessage(cnd), "ollama serve")
  expect_gt(nrow(out), 0L)
  expect_identical(unique(out$method), "bm25")
})

test_that("crd_search() falls back on an unrecognised failure without prescribing a remedy", {
  store <- local_ragnar_store_failing("unknown")
  local_fallback_warnings_always()

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

test_that("crd_search() reports a missing model as its own reason, end to end", {
  # The branch with no offline route: the server has to answer in order to
  # answer 404. Skipped rather than dropped — Phase 1 claimed all four branches
  # were covered end to end, and three of four is not four.
  skip_if_not(.crd_ollama_reachable(), "no local Ollama answering")
  store <- local_ragnar_store_failing("model")
  local_fallback_warnings_always()

  cnd <- NULL
  out <- withCallingHandlers(
    crd_search(store, .crd_test_query(), top_k = 3L),
    cred_retrieval_fallback = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(cnd, "cred_retrieval_fallback_model")
  expect_match(conditionMessage(cnd), "ollama pull")
  expect_no_match(conditionMessage(cnd), "ollama serve")
  # The model named is the one that was refused, not the package default.
  expect_match(conditionMessage(cnd), "cred-no-such-model-29", fixed = TRUE)
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
  # Both are copies of ONE cached store, so they share a `location`. That is
  # what makes this block discriminating: the ids can only differ by reason.
  expect_identical(conn@location, dim_store@location)
  local_reset_fallback_warnings(conn)

  expect_warning(crd_search(conn, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_connection")
  expect_warning(crd_search(dim_store, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_dimension")
})

test_that("one unreachable store does not silence another", {
  # The other half of the key, and the half a mutation could remove unnoticed:
  # dropping `location` from the id left every test in this file green.
  a <- local_ragnar_store_failing("connection")
  b <- local_ragnar_store_failing("connection")
  b@location <- paste0(a@location, "-second-store")
  expect_false(identical(a@location, b@location))

  local_reset_fallback_warnings(a)
  local_reset_fallback_warnings(b)

  expect_warning(crd_search(a, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_connection")
  # Same reason, different store, so it has not been said yet.
  expect_warning(crd_search(b, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_connection")
})

test_that("the classifier, the message builder and the test helper agree on the reasons", {
  # THE terminating check for this issue, and the one that is computed rather
  # than recalled. Two of the defects fixed here came from lists that happened
  # to agree until one moved: a reason the classifier can return with no branch
  # in the message builder silently gets the "unknown" text, and a helper that
  # loops over four reasons when there are five resets four frequency ids.
  #
  # Derived by parsing the functions, so adding a reason without wiring it
  # everywhere fails HERE rather than in whichever consumer notices first.
  cls <- deparse(.crd_retrieval_failure)
  from_classifier <- sort(unique(
    gsub('.*return\\("([a-z]+)"\\).*', "\\1", grep('return\\("', cls, value = TRUE))
  ))

  msg <- deparse(.crd_retrieval_fallback_msg)
  from_msg <- sort(unique(
    gsub('.*identical\\(reason, "([a-z]+)"\\).*', "\\1",
         grep('identical\\(reason, "', msg, value = TRUE))
  ))

  # The classifier's last reason is a bare literal rather than a return() call,
  # so derive it as such instead of assuming it — this assertion is what makes
  # the set below complete, and it fails if the fallthrough is ever changed.
  tail_expr <- trimws(utils::tail(cls[nzchar(trimws(cls)) & trimws(cls) != "}"], 1L))
  expect_identical(tail_expr, '"unknown"')
  from_classifier <- sort(unique(c(from_classifier, gsub('"', "", tail_expr))))

  # The premise: the parse found something. A regex that silently matched
  # nothing would make every assertion below vacuously true.
  expect_gt(length(from_classifier), 2L)
  expect_gt(length(from_msg), 1L)

  # "unknown" is the message builder's fallthrough, so it has no branch of its
  # own by design.
  expect_identical(setdiff(from_classifier, c(from_msg, "unknown")), character(0))
  expect_identical(setdiff(from_msg, from_classifier), character(0))
  expect_identical(sort(.crd_fallback_reasons()), from_classifier)
})

test_that("every reason produces a message that is not the fallthrough", {
  # The other half: agreement on NAMES does not prove each branch emits its own
  # text. A branch whose body was lost would still be named in the source.
  texts <- vapply(.crd_fallback_reasons(), function(r) {
    .crd_retrieval_fallback_msg(r, simpleError("a cause"))
  }, character(1))
  expect_length(unique(texts), length(.crd_fallback_reasons()))
})

test_that("the frequency id varies with the reason and with the store", {
  store <- local_ragnar_store()
  reasons <- .crd_fallback_reasons()
  ids <- vapply(reasons, function(r) .crd_retrieval_fallback_id(r, store),
                character(1))
  expect_length(unique(ids), length(reasons))

  # Varying the STORE, which the reason loop above cannot see. Replacing the id
  # with paste0(prefix, reason) — dropping the store half entirely — passed
  # every other test in this file.
  other <- store
  other@location <- paste0(store@location, "-elsewhere")
  expect_false(identical(
    .crd_retrieval_fallback_id("connection", store),
    .crd_retrieval_fallback_id("connection", other)
  ))

  # And a store with no readable location still yields a usable id rather than
  # erroring inside the warning path.
  expect_no_error(id <- .crd_retrieval_fallback_id("connection", NULL))
  expect_type(id, "character")
  expect_length(id, 1L)
  expect_no_error(.crd_retrieval_fallback_id("connection", "not a store"))
})
