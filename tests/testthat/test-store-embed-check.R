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
    embed_ollama = function(...) stop(cnd_http(
      404, 'HTTP 404 Not Found.\nmodel "cred-absent-30" not found, try pulling it first'
    )),
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

test_that('a vss failure carries the raw condition and the diagnosis', {
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

test_that('a vss failure that is NOT a dimension problem is classified as its own reason', {
  store <- local_ragnar_store()
  broken <- store
  broken@embed <- ragnar::embed_ollama(model = "nomic-embed-text",
                                       base_url = "http://127.0.0.1:1/")

  cnd <- tryCatch(crd_search(broken, .crd_test_query(), top_k = 3L, method = "vss"),
                  error = function(e) e)

  expect_s3_class(cnd, "cred_retrieval_error_connection")
  expect_match(conditionMessage(cnd), "did not answer", fixed = TRUE)
})
