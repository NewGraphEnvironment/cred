# Embedding checks: the build-time probe, the vss error, and the connect-time
# model check (#30).
#
# What ties the three together is that they all have to say something about an
# embedding failure, and before #30 they said three different things about the
# same one. `.crd_embed_remedy()` is the shared mapping; these tests are about
# each caller composing it correctly, not about the remedy text itself, which
# test-store-fallback.R pins.
#
# Everything here runs offline. The `connection` tier goes through the REAL
# `ragnar::embed_ollama()` against loopback port 1, refused by the kernel with
# no timeout to wait out; the tiers that need a server to answer use a
# hand-built condition carrying the class httr2 would have put on it.

# A reply from a service that answered and refused. Built rather than provoked:
# only a running server can answer 500, and what the classifier dispatches on is
# the class, which is the part a fixture can supply faithfully.
cnd_http <- function(status, message) {
  rlang::error_cnd(
    class = c(paste0("httr2_http_", status), "httr2_http", "httr2_error"),
    message = message
  )
}

# --- Phase 2: .crd_ollama_check() -----------------------------------------

test_that("a dead port reaches the connection branch through the real embed_ollama", {
  skip_if_not_installed("ragnar")
  # The premise. If ragnar or httr2 changes shape this fails naming the cause,
  # rather than letting the behaviour tests below pass for the wrong reason.
  cond <- tryCatch(
    ragnar::embed_ollama("probe", model = "nomic-embed-text",
                         base_url = "http://127.0.0.1:1/"),
    error = function(e) e
  )
  expect_s3_class(cond, "condition")
  expect_identical(.crd_retrieval_failure(cond), "connection")
})

test_that(".crd_ollama_check reports a dead port as a dead port", {
  skip_if_not_installed("ragnar")
  msg <- tryCatch(
    .crd_ollama_check("nomic-embed-text", base_url = "http://127.0.0.1:1/"),
    error = conditionMessage
  )

  expect_match(msg, "Could not embed with Ollama model", fixed = TRUE)
  expect_match(msg, "did not answer", fixed = TRUE)
  # The cause, verbatim. The pre-#30 version reported it too; that was the one
  # thing it got right and it must survive.
  expect_match(msg, "(?i)cause", perl = TRUE)
})

test_that(".crd_ollama_check names the model the CALLER asked for, not the package default", {
  skip_if_not_installed("ragnar")
  # `.crd_fallback_model()`'s last resort is the hardcoded "nomic-embed-text".
  # A connection failure names no model and there is no store, so without a
  # requested-model tier the remedy tells the user to pull a model they never
  # asked about -- a wrong paste-me command, which is the class of defect #29
  # and #30 both exist to remove.
  msg <- tryCatch(
    .crd_ollama_check("mxbai-embed-large", base_url = "http://127.0.0.1:1/"),
    error = conditionMessage
  )

  expect_match(msg, "mxbai-embed-large", fixed = TRUE)
  expect_no_match(msg, "nomic-embed-text", fixed = TRUE)
})

test_that(".crd_ollama_check does not say 'ollama serve' to a server that answered", {
  skip_if_not_installed("ragnar")
  local_mocked_bindings(
    embed_ollama = function(...) stop(cnd_http(500, "HTTP 500 Internal Server Error.")),
    .package = "ragnar"
  )
  msg <- tryCatch(.crd_ollama_check("nomic-embed-text"), error = conditionMessage)

  # This is the defect. The pre-#30 message printed `ollama serve` and
  # `ollama pull` for every error, so a 500 from a running server was reported
  # as something starting it would fix.
  expect_no_match(msg, "ollama serve", fixed = TRUE)
  expect_no_match(msg, "ollama pull", fixed = TRUE)
  expect_match(msg, "so it is running", fixed = TRUE)
})

test_that(".crd_ollama_check prescribes the pull, and only the pull, for an absent model", {
  skip_if_not_installed("ragnar")
  local_mocked_bindings(
    embed_ollama = function(...) {
      stop(cnd_http(
        404,
        'HTTP 404 Not Found.\nmodel "cred-absent-30" not found, try pulling it first'
      ))
    },
    .package = "ragnar"
  )
  msg <- tryCatch(.crd_ollama_check("nomic-embed-text"), error = conditionMessage)

  expect_match(msg, "ollama pull cred-absent-30", fixed = TRUE)
  expect_no_match(msg, "ollama serve", fixed = TRUE)
  # The model the SERVICE named beats the model the caller requested: it is the
  # more specific evidence, and the requested-model tier must not displace it.
  expect_no_match(msg, "ollama pull nomic-embed-text", fixed = TRUE)
})

test_that(".crd_ollama_check gives a dead port and a refusing server DIFFERENT accounts", {
  skip_if_not_installed("ragnar")
  # The regression, stated as the property rather than as two texts. The
  # pre-#30 function produced the same remedy for both, so this assertion is
  # the one that cannot pass against it.
  dead <- tryCatch(.crd_ollama_check("nomic-embed-text",
                                     base_url = "http://127.0.0.1:1/"),
                   error = conditionMessage)
  refused <- local({
    local_mocked_bindings(
      embed_ollama = function(...) stop(cnd_http(503, "HTTP 503 Service Unavailable.")),
      .package = "ragnar"
    )
    tryCatch(.crd_ollama_check("nomic-embed-text"), error = conditionMessage)
  })

  expect_false(identical(dead, refused))
  expect_match(dead, "ollama serve", fixed = TRUE)
  expect_no_match(refused, "ollama serve", fixed = TRUE)
})

test_that(".crd_ollama_check is silent and returns NULL when embedding works", {
  skip_if_not_installed("ragnar")
  local_mocked_bindings(
    embed_ollama = function(...) matrix(0, nrow = 1L, ncol = 768L),
    .package = "ragnar"
  )
  expect_silent(out <- .crd_ollama_check("nomic-embed-text"))
  expect_null(out)
})

# --- Phase 3: crd_search(method = "vss") ----------------------------------

test_that('method = "vss" errors rather than falling back, and says why', {
  store <- local_ragnar_store_failing("dimension")

  cnd <- tryCatch(crd_search(store, .crd_test_query(), top_k = 3L, method = "vss"),
                  error = function(e) e)

  # Erroring is correct: no fallback exists for vss, and silently returning
  # nothing would be worse than saying so.
  expect_s3_class(cnd, "cred_retrieval_error")
  expect_s3_class(cnd, "cred_retrieval_error_dimension")
  expect_match(conditionMessage(cnd), "no fallback", fixed = TRUE)
  # The two methods that DO work here are named, because that is the remedy a
  # user can act on in this session.
  expect_match(conditionMessage(cnd), "hybrid", fixed = TRUE)
  expect_match(conditionMessage(cnd), "bm25", fixed = TRUE)
})

test_that("a vss failure carries the raw condition and the diagnosis", {
  store <- local_ragnar_store_failing("dimension")

  cnd <- tryCatch(crd_search(store, .crd_test_query(), top_k = 3L, method = "vss"),
                  error = function(e) e)

  # The pre-#30 behaviour was this condition raised bare: a duckdb binder error
  # and no diagnosis. It is still reachable, as an rlang parent.
  expect_false(is.null(cnd$parent))
  expect_match(conditionMessage(cnd$parent), "(?i)array|size|cast", perl = TRUE)

  # And `conditionMessage()` on the outer condition is self-sufficient: rlang
  # folds a parent's message into it, so `tryCatch(error = conditionMessage)`
  # sees both the cause and the remedy. Measured, not assumed.
  expect_match(conditionMessage(cnd), "Caused by error", fixed = TRUE)
  expect_match(conditionMessage(cnd), "crd_store_build", fixed = TRUE)
})

test_that('method = "bm25" is not wrapped — it needs no embedding at all', {
  store <- local_ragnar_store_failing("dimension")

  # The whole point of the fallback is that lexical retrieval is unaffected by a
  # broken embedder. A vss wrapper that also caught bm25 would turn a working
  # search into an error.
  out <- crd_search(store, .crd_test_query(), top_k = 3L, method = "bm25")
  expect_gt(nrow(out), 0L)
  expect_identical(unique(out$method), "bm25")
})

test_that("a vss failure that is NOT a dimension problem is classified as its own reason", {
  store <- local_ragnar_store()
  broken <- store
  broken@embed <- ragnar::embed_ollama(model = "nomic-embed-text",
                                       base_url = "http://127.0.0.1:1/")

  cnd <- tryCatch(crd_search(broken, .crd_test_query(), top_k = 3L, method = "vss"),
                  error = function(e) e)

  expect_s3_class(cnd, "cred_retrieval_error_connection")
  expect_match(conditionMessage(cnd), "did not answer", fixed = TRUE)
})

# --- Phase 4: the connect-time check --------------------------------------

test_that(".crd_embed_width reads a width from every shape an embedder returns", {
  # `ragnar::embed_ollama()` returns a matrix, one row per input, so `ncol()` is
  # the width. Nothing guarantees a custom embedder does the same, and `ncol()`
  # on a bare vector is NULL -- which `if (x != size)` would then error on,
  # turning a tolerant check into a hard failure at connect.
  expect_identical(.crd_embed_width(matrix(0, nrow = 1L, ncol = 16L)), 16L)
  expect_identical(.crd_embed_width(matrix(0, nrow = 4L, ncol = 768L)), 768L)
  expect_identical(.crd_embed_width(numeric(16L)), 16L)
  expect_identical(.crd_embed_width(data.frame(a = 1, b = 2)), 2L)

  expect_true(is.na(.crd_embed_width(NULL)))
  expect_true(is.na(.crd_embed_width(list(1, 2))))
  expect_true(is.na(.crd_embed_width(numeric(0))))
})

test_that("the fixture store is internally consistent — the premise for everything below", {
  store <- local_ragnar_store()

  # Measured, not assumed. If these two ever disagree, every "no mismatch" test
  # below would be asserting the wrong thing and every "mismatch" test could
  # pass for the wrong reason.
  expect_identical(.crd_store_meta_brief(store)$size, 16L)
  expect_identical(.crd_embed_width(store@embed("probe")), 16L)
})

test_that("a confirmed width mismatch is an error naming both widths", {
  store <- local_ragnar_store()
  broken <- store
  broken@embed <- .crd_test_embed_narrow

  # The premise for this specific test: the two widths genuinely differ, so the
  # error below cannot be passing because the check was SKIPPED.
  expect_identical(.crd_embed_width(broken@embed("probe")), 8L)

  cnd <- tryCatch(.crd_check_store_embedding(broken, name = "fixture"),
                  error = function(e) e)

  expect_s3_class(cnd, "cred_store_embedding_mismatch")
  msg <- conditionMessage(cnd)
  expect_match(msg, "16", fixed = TRUE)
  expect_match(msg, "8", fixed = TRUE)
  expect_match(msg, "fixture", fixed = TRUE)
  # Says what to do, and names the escape so a bm25-only workflow is not stuck.
  expect_match(msg, "check_model = FALSE", fixed = TRUE)
})

test_that("a consistent store passes the check silently", {
  store <- local_ragnar_store()
  expect_silent(expect_null(.crd_check_store_embedding(store, name = "fixture")))
})

test_that("a probe that cannot run is not reported as a mismatch", {
  store <- local_ragnar_store()
  broken <- store
  broken@embed <- ragnar::embed_ollama(model = "nomic-embed-text",
                                       base_url = "http://127.0.0.1:1/")
  local_fallback_warnings_always()

  cnd <- NULL
  expect_no_error(withCallingHandlers(
    .crd_check_store_embedding(broken, name = "fixture"),
    cred_store_probe_failed = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  ))

  # A dead Ollama is not evidence about the store, and connect must not refuse
  # one over it -- bm25 search is unaffected and needs no embedding at all.
  expect_s3_class(cnd, "cred_store_probe_failed_connection")
  expect_match(conditionMessage(cnd), "did not answer", fixed = TRUE)
  expect_match(conditionMessage(cnd), "(?i)could not check", perl = TRUE)
})

test_that("an unreadable embedding_size skips the check silently", {
  store <- local_ragnar_store()
  local_mocked_bindings(
    .crd_store_meta_brief = function(store) {
      list(size = NA_integer_, model = NA_character_)
    }
  )
  # Nothing to compare the probe against. The push side already warns about an
  # unreadable size, so saying it again on every connect is noise.
  expect_silent(expect_null(.crd_check_store_embedding(store, name = "fixture")))
})

test_that("a store that records no embedder skips the check silently", {
  store <- local_ragnar_store()
  noembed <- store
  noembed@embed <- NULL

  expect_silent(expect_null(.crd_check_store_embedding(noembed, name = "fixture")))
})

test_that("a manifest model label that disagrees with the store warns, and does not error", {
  store <- local_ragnar_store_named()   # records model "mxbai-embed-large"
  entry <- list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 16L)

  cnd <- NULL
  expect_no_error(withCallingHandlers(
    .crd_check_store_embedding(store, entry = entry, name = "named"),
    cred_store_model_label_mismatch = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  ))

  expect_s3_class(cnd, "cred_store_model_label_mismatch")
  expect_match(conditionMessage(cnd), "mxbai-embed-large", fixed = TRUE)
  expect_match(conditionMessage(cnd), "nomic-embed-text", fixed = TRUE)
})

test_that("a provider suffix in the manifest label is not a mismatch", {
  store <- local_ragnar_store_named()
  # Without this the block CANNOT FAIL. The label warning is
  # `.frequency = "once"` keyed on the store's location, and the block above
  # already spent that slot on the same cached store -- so rlang muffles this
  # one whatever the code does. Measured: removing .crd_model_norm() from the
  # compare, which is the exact defect this test rejects, left the suite green.
  local_fallback_warnings_always()
  entry <- list(embedding_model = "mxbai-embed-large (ollama)", embedding_size = 16L)

  # `.crd_model_norm()` exists because every existing manifest entry records the
  # provider inline while a store's own record is bare. A guard that cried wolf
  # on all of them would get switched off for the case that matters.
  expect_silent(expect_null(
    .crd_check_store_embedding(store, entry = entry, name = "named")
  ))
})

# A throwaway copy of the fixture store whose RECORDED width is wrong.
#
# Mocking `ragnar::ragnar_store_connect()` to return a narrow copy of the cached
# fixture was the first attempt and is actively unsafe: the copy shares the
# cached store's duckdb connection, so `.crd_store_open()`'s cleanup -- which
# correctly closes a connection it opened and then failed behind -- closed the
# SHARED one, and every later test file lost retrieval. `helper-store.R` records
# that hazard; this is it, met from the other direction.
#
# A copy on disk has no such entanglement, needs no mocked bindings, and runs
# the real `ragnar_store_connect()` unserialise path. `read_only = FALSE` is
# safe here only because the path is fresh -- never the cached file.
local_store_copy_bad_width <- function(env = parent.frame()) {
  skip_if_not_installed("duckdb")
  src <- as.character(local_ragnar_store()@location)
  copy <- tempfile(fileext = ".duckdb")
  stopifnot(file.copy(src, copy))
  withr::defer(unlink(copy), envir = env)

  con <- DBI::dbConnect(duckdb::duckdb(), copy, read_only = FALSE)
  DBI::dbExecute(con, "UPDATE metadata SET embedding_size = 8")
  DBI::dbDisconnect(con, shutdown = TRUE)
  copy
}

test_that("crd_store_connect runs the check on the verify = FALSE path", {
  skip_if_not_installed("ragnar")
  # The wiring test, and the reason the three return sites were collapsed into
  # one tail: a check added to the two verified paths and missed on this one
  # would leave the offline route -- the one a user reaches by default when the
  # bucket is unconfigured -- unprotected, with every logic test above green.
  copy <- local_store_copy_bad_width()

  expect_error(
    suppressMessages(crd_store_connect(copy, verify = FALSE)),
    class = "cred_store_embedding_mismatch"
  )
})

test_that("crd_store_connect(check_model = FALSE) opens a mismatched store anyway", {
  skip_if_not_installed("ragnar")
  copy <- local_store_copy_bad_width()

  # The escape has to actually work: bm25 retrieval on this store is unaffected,
  # and refusing to hand it back would break a workflow that was never broken.
  out <- suppressMessages(
    crd_store_connect(copy, verify = FALSE, check_model = FALSE)
  )
  # Usable, not merely returned -- a bm25 search on it is the workflow the
  # escape exists to preserve. (No class assertion: ragnar's store is S7, which
  # reports as S3, so `expect_s4_class()` is the wrong instrument.)
  res <- crd_search(out, .crd_test_query(), top_k = 3L, method = "bm25")
  expect_gt(nrow(res), 0L)
})

test_that("every crd_store_connect return path goes through the checked tail", {
  # Computed rather than recalled, in the shape of the drift guard in
  # test-store-fallback.R. `crd_store_connect()` had three separate
  # `return(ragnar::ragnar_store_connect(...))` sites; a fourth added later must
  # not be able to bypass the check.
  src <- deparse(crd_store_connect)
  direct <- grep("ragnar::ragnar_store_connect", src, value = TRUE)

  expect_identical(direct, character(0))
  expect_gt(length(grep(".crd_store_open", src)), 1L)
})

# --- Review follow-ups ------------------------------------------------------

test_that("the build-time remedy never prescribes a store that does not exist yet", {
  skip_if_not_installed("ragnar")
  # Plan review, BLOCKER: the shared `unknown` fallthrough sends a searcher to
  # crd_store_connect() to rule the file out, and `.crd_ollama_check()` runs
  # inside crd_store_build() BEFORE the store exists -- so the user was told to
  # verify a file they were in the middle of creating. Reachable by any
  # embed_ollama() failure that is neither httr2-classed nor matches the
  # connection or HTTP patterns.
  local_mocked_bindings(
    embed_ollama = function(...) stop("lexical error at position 3"),
    .package = "ragnar"
  )
  msg <- tryCatch(.crd_ollama_check("nomic-embed-text"), error = conditionMessage)

  expect_match(msg, "does not recognise this failure", fixed = TRUE)
  expect_no_match(msg, "crd_store_connect", fixed = TRUE)
  expect_no_match(msg, "the file the manifest describes", fixed = TRUE)
})

test_that("the searcher's unknown remedy still DOES prescribe crd_store_connect", {
  # The complement, and the reason `context` exists rather than a test for
  # `is.null(store)`: for a search the file itself is a live suspect, and an md5
  # compare is exactly what rules it out.
  msg <- .crd_embed_remedy("unknown", simpleError("something odd"))
  expect_match(msg, "crd_store_connect", fixed = TRUE)
})

test_that("the connect-time and search-time frequency ids cannot collide", {
  store <- local_ragnar_store()
  # Plan review, BLOCKER: keyed in the same scheme, a "could not check
  # (connection)" at connect would silence the SEARCH warning for the same
  # reason on the same store -- the user then gets BM25 results with nothing
  # saying the search degraded, which is the diagnosis loss #29 exists to end,
  # arriving from the other side.
  # Both sides asked of the CODE, never rebuilt from a literal here. Measured:
  # with the expected key restated in this test, pointing the probe warning at
  # .crd_retrieval_fallback_id() left the whole suite green -- the test could
  # not fail against the defect it was written for.
  for (r in .crd_fallback_reasons()) {
    expect_false(identical(.crd_retrieval_fallback_id(r, store),
                           .crd_store_probe_id(r, store)))
  }
})

test_that("an on-disk width disagreement is caught through the real ragnar_store_connect", {
  skip_if_not_installed("ragnar")
  skip_if_not_installed("duckdb")
  copy <- local_store_copy_bad_width()

  cnd <- tryCatch(suppressMessages(crd_store_connect(copy, verify = FALSE)),
                  error = function(e) e)

  expect_s3_class(cnd, "cred_store_embedding_mismatch")
  # Fired for the RIGHT reason: the recorded width, not a missing file or a
  # duckdb configuration conflict, both of which also error on this call.
  expect_identical(cnd$store_size, 8L)
  expect_identical(cnd$embed_width, 16L)
})

test_that("a vss dimension failure really is classified dimension, not unknown", {
  store <- local_ragnar_store_failing("dimension")
  # The premise for the vss tests above. test-store-fallback.R pins this for
  # ragnar_retrieve(); ragnar_retrieve_vss() is a different call and could word
  # it differently, in which case the reason is "unknown" and a test asserting
  # only the base class would pass vacuously.
  cond <- tryCatch(ragnar::ragnar_retrieve_vss(store, .crd_test_query(), top_k = 3L),
                   error = function(e) e)
  expect_s3_class(cond, "condition")
  expect_identical(.crd_retrieval_failure(cond), "dimension")
})

test_that("a connect-time probe warning does not silence the later search warning", {
  store <- local_ragnar_store_failing("connection")

  # The behavioural form of the test above, and the only one that can fail: the
  # scheme comparison asks whether the two id FUNCTIONS differ, while what
  # matters is which one the warning is emitted under. Measured -- pointing the
  # probe warning at .crd_retrieval_fallback_id() left the scheme test green.
  #
  # The frequency guard must be ON for this, so the ids are re-armed either side
  # rather than switched off.
  ids <- c(.crd_store_probe_id("connection", store),
           .crd_retrieval_fallback_id("connection", store))
  for (id in ids) rlang::reset_warning_verbosity(id)
  withr::defer(for (id in ids) rlang::reset_warning_verbosity(id))

  expect_warning(.crd_check_store_embedding(store, name = "fixture"),
                 class = "cred_store_probe_failed_connection")

  # Same reason, same store, different channel. If the two shared one key the
  # user would get BM25 results here with nothing saying the search degraded.
  expect_warning(crd_search(store, .crd_test_query(), top_k = 3L),
                 class = "cred_retrieval_fallback_connection")
})

test_that("a default connect returns a store whose connection is still usable", {
  skip_if_not_installed("ragnar")
  # Round 1 of /code-check, measured: deleting `ok <- TRUE` from
  # .crd_store_open() left the whole suite green at 587 passes while every
  # default-path connect returned a store whose duckdb connection had been shut
  # down -- dbIsValid() FALSE, any search "Invalid connection". The cleanup's
  # error branch had a test; its success branch did not, and the two tests that
  # do reach the tail take the other routes (one expects the mismatch error, the
  # other passes check_model = FALSE and returns before the on.exit is even
  # registered).
  src <- as.character(local_ragnar_store()@location)
  copy <- tempfile(fileext = ".duckdb")
  expect_true(file.copy(src, copy))
  on.exit(unlink(copy), add = TRUE)

  out <- suppressMessages(crd_store_connect(copy, verify = FALSE))

  expect_true(DBI::dbIsValid(out@con))
  res <- crd_search(out, .crd_test_query(), top_k = 3L, method = "bm25")
  expect_gt(nrow(res), 0L)
  try(DBI::dbDisconnect(out@con, shutdown = TRUE), silent = TRUE)
})

test_that("a failed connect closes the connection it opened", {
  skip_if_not_installed("ragnar")
  # /code-check round 2: the round-1 fix guarded `ok <- TRUE` -- the cleanup's
  # SUCCESS branch -- and left the handler itself uncovered. Deleting the whole
  # `ok <- FALSE` / on.exit pair kept the suite green at 602, which is the
  # connection leak this branch exists to have closed.
  #
  # The intuitive discriminator does not work and should not be reached for:
  # after an aborted connect, reopening the same file read-write succeeds on
  # this duckdb, so "can I reconnect" cannot tell a closed handle from a leaked
  # one. Observing the call the cleanup makes can.
  # Build the fixture BEFORE arming the counter. local_store_copy_bad_width()
  # calls DBI::dbDisconnect() itself to close the connection it used for the
  # UPDATE, so counting from before it leaves the counter at 1 whatever the
  # cleanup does -- measured: the first version of this test passed against a
  # mutant with the whole on.exit block deleted. Same vacuity mechanism this
  # round was reporting, reproduced inside its own fix.
  copy <- local_store_copy_bad_width()

  real <- DBI::dbDisconnect
  closed <- 0L
  local_mocked_bindings(
    dbDisconnect = function(conn, ...) {
      closed <<- closed + 1L
      real(conn, ...)
    },
    .package = "DBI"
  )

  expect_error(suppressMessages(crd_store_connect(copy, verify = FALSE)),
               class = "cred_store_embedding_mismatch")
  expect_gt(closed, 0L)
})

test_that("an unreadable probe result is not reported as a width mismatch", {
  store <- local_ragnar_store()
  odd <- store
  # `.crd_embed_width()` reads this as NA, and the tier that compares widths is
  # the one that ERRORS. Without the `!.crd_have(got)` guard a connect aborts
  # with "its recorded embedder now returns: NA-wide" -- a hard failure on a
  # store that is fine, from the check whose own roxygen promises to degrade
  # quietly. Measured: dropping that guard left the suite green.
  odd@embed <- function(x) list(1, 2)
  local_fallback_warnings_always()

  expect_true(is.na(.crd_embed_width(odd@embed("probe"))))
  expect_silent(expect_null(.crd_check_store_embedding(odd, name = "fixture")))
})

test_that("a store recording no model name does not warn about the manifest label", {
  store <- local_ragnar_store()
  # `.crd_store_model_from_meta()` returns NA whenever a store's embed_func
  # carries no `model = "..."` literal — any store not built by
  # crd_store_build(). Without the `.crd_is_model_name(meta$model)` guard, every
  # such store warns `the store records: NA` against the manifest's label on
  # EVERY connect. Reachable in production, and measured green without the
  # guard.
  #
  # local_fallback_warnings_always() matters here as much as the assertion: the
  # label warning is frequency-guarded, so without it a muffled warning and an
  # absent one are the same observation.
  local_fallback_warnings_always()
  expect_true(is.na(.crd_store_meta_brief(store)$model))

  expect_silent(expect_null(.crd_check_store_embedding(
    store,
    entry = list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 16L),
    name = "fixture"
  )))
})
