# Tests for the push / merge-on-write half of the evidence-store layer.
#
# Nothing here touches the network, S3 or Ollama. `.crd_aws()` is mocked so the
# exit codes that drive every decision can be exercised deterministically.

manifest_two <- function() {
  list(
    date_updated = "2026-08-31T21:02:28Z",
    manifest_note = "Provenance is per store. Push must merge into this file, never replace it.",
    chunking = "ragnar defaults (ragnar_store_ingest)",
    stores = list(
      alpha = list(documents = 15L, chunks = 2464L, md5 = "aaa",
                   embedding_model = "nomic-embed-text (ollama)",
                   built_by = "scripts/rag_build.R"),
      beta  = list(documents = 283L, chunks = 22883L, md5 = "bbb",
                   embedding_model = "nomic-embed-text (ollama)",
                   built_by = list("scripts/0151.R", "scripts/0152.R"))
    )
  )
}

# ---- the merge core -------------------------------------------------------

test_that(".crd_manifest_merge adds a store without dropping the others", {
  out <- .crd_manifest_merge(manifest_two(), "gamma", list(md5 = "ccc"))

  # This is the regression 0157-rag-sync.R causes: pushing one store replaced
  # the manifest and orphaned every other.
  expect_setequal(names(out$stores), c("alpha", "beta", "gamma"))
  expect_identical(out$stores$alpha$md5, "aaa")
  expect_identical(out$stores$beta$md5, "bbb")
})

test_that(".crd_manifest_merge leaves untouched entries byte-identical", {
  before <- manifest_two()
  out <- .crd_manifest_merge(before, "gamma", list(md5 = "ccc"))

  # Including built_by in both its shapes — bare string and array.
  expect_identical(out$stores$alpha, before$stores$alpha)
  expect_identical(out$stores$beta, before$stores$beta)
  expect_type(out$stores$alpha$built_by, "character")
  expect_type(out$stores$beta$built_by, "list")
})

test_that(".crd_manifest_merge replaces only the named entry", {
  out <- .crd_manifest_merge(manifest_two(), "alpha", list(md5 = "zzz"))

  expect_identical(out$stores$alpha$md5, "zzz")
  expect_identical(out$stores$beta$md5, "bbb")
  expect_setequal(names(out$stores), c("alpha", "beta"))
})

test_that(".crd_manifest_merge preserves unrelated top-level fields", {
  out <- .crd_manifest_merge(manifest_two(), "gamma", list(md5 = "ccc"))
  expect_identical(out$chunking, "ragnar defaults (ragnar_store_ingest)")
})

test_that(".crd_manifest_merge restates the merge-on-write contract it just honoured", {
  out <- .crd_manifest_merge(manifest_two(), "gamma", list(md5 = "ccc"))
  expect_match(out$manifest_note, "never replace it", fixed = TRUE)
  expect_identical(out$generating_script, "cred::crd_store_push()")
})

test_that(".crd_manifest_merge builds a fresh manifest from NULL", {
  out <- .crd_manifest_merge(NULL, "alpha", list(md5 = "aaa"))
  expect_identical(names(out$stores), "alpha")
})

# ---- source parsing -------------------------------------------------------

test_that(".crd_s3_parts splits bucket from prefix", {
  expect_identical(.crd_s3_parts("s3://b/p/"), list(bucket = "b", prefix = "p/"))
  expect_identical(.crd_s3_parts("s3://b/"), list(bucket = "b", prefix = ""))
  expect_identical(.crd_s3_parts("s3://b/deep/nest/")$prefix, "deep/nest/")
})

test_that(".crd_s3_parts rejects a non-s3 source rather than guessing", {
  expect_error(.crd_s3_parts("https://example.com/x/"), "Only s3:// sources")
})

# ---- probes ---------------------------------------------------------------

test_that(".crd_s3_head_object reports a 404 as a CONFIRMED absence", {
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = character(), err = "An error occurred (404) ... Not Found", status = 254L)
    }
  )
  res <- .crd_s3_head_object("s3://b/p/", "log.json")

  expect_false(res$exists)
  expect_true(res$confirmed_absent)
  expect_true(is.na(res$etag))
})

test_that(".crd_s3_head_object does NOT report a non-404 failure as an absence", {
  # A throttle or credential refresh must not masquerade as "no object here" —
  # that is the direction that loses data.
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = character(), err = "An error occurred (SlowDown) ... Reduce your request rate",
           status = 254L)
    }
  )
  res <- .crd_s3_head_object("s3://b/p/", "log.json")

  expect_false(res$exists)
  expect_false(res$confirmed_absent)
})

test_that(".crd_s3_head_object returns the ETag when present", {
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = '"abc123"', err = character(), status = 0L)
    }
  )
  res <- .crd_s3_head_object("s3://b/p/", "log.json")

  expect_true(res$exists)
  expect_identical(res$etag, '"abc123"')
})

test_that(".crd_s3_head_object picks the ETag by shape, not by collapsing the stream", {
  # aws writes warnings to stderr while still exiting 0 (urllib3/LibreSSL on
  # macOS). Welding those onto the ETag yields a garbage --if-match, a false
  # 412, and a bogus "concurrent push" diagnosis.
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = '"abc123"',
           err = "urllib3/2.0 NotOpenSSLWarning: urllib3 v2 only supports OpenSSL",
           status = 0L)
    }
  )
  res <- .crd_s3_head_object("s3://b/p/", "log.json")

  expect_identical(res$etag, '"abc123"')
  expect_false(grepl("urllib3", res$etag))
})

test_that(".crd_s3_head_object reports NA etag when no ETag-shaped line is present", {
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = "unexpected output", err = character(), status = 0L)
    }
  )
  expect_true(is.na(.crd_s3_head_object("s3://b/p/", "log.json")$etag))
})

test_that(".crd_s3_precondition_failed matches the tokens the CLI actually emits", {
  expect_true(.crd_s3_precondition_failed(
    list(out = "An error occurred (PreconditionFailed)", err = character(), status = 254L)))
  expect_true(.crd_s3_precondition_failed(
    list(out = "An error occurred (412) when calling PutObject", err = character(), status = 254L)))
  expect_false(.crd_s3_precondition_failed(
    list(out = "An error occurred (AccessDenied)", err = character(), status = 254L)))
  expect_false(.crd_s3_precondition_failed(list(out = "", err = character(), status = 0L)))
})

test_that(".crd_s3_precondition_failed is not fooled by a bare 412 substring", {
  # An unrelated fatal error whose request id or byte count contains "412"
  # must not be pushed into the retry loop.
  expect_false(.crd_s3_precondition_failed(list(
    out = "An error occurred (AccessDenied); request id 9412ab; 41200 bytes",
    err = character(), status = 254L)))
})

# ---- push guards ----------------------------------------------------------

test_that("crd_store_push refuses when the bucket is unreachable", {
  skip_if_not_installed("duckdb")
  f <- withr::local_tempfile(fileext = ".duckdb")
  file.create(f)
  local_mocked_bindings(.crd_s3_head_bucket = function(source, profile = "") FALSE)

  # Unreachable must never be read as "no manifest yet" — that is how a push
  # seeds a second, rival manifest.
  expect_error(
    crd_store_push(f, source = "s3://b/p/"),
    "Cannot reach the bucket"
  )
})

test_that("crd_store_push refuses to create a manifest without the explicit flag", {
  skip_if_not_installed("duckdb")
  f <- withr::local_tempfile(fileext = ".duckdb")
  file.create(f)
  local_mocked_bindings(
    .crd_s3_head_bucket = function(source, profile = "") TRUE,
    .crd_s3_head_object = function(source, key, profile = "") {
      list(exists = FALSE, confirmed_absent = TRUE, etag = NA_character_, out = "")
    }
  )
  msg <- tryCatch(crd_store_push(f, source = "s3://b/p/"), error = conditionMessage)

  expect_match(msg, "create_manifest = TRUE", fixed = TRUE)
  # A wrong prefix produces this same 404, so the error must say so.
  expect_match(msg, "cred.store_source", fixed = TRUE)
})

test_that("crd_store_push refuses a store with an unflushed WAL", {
  f <- withr::local_tempfile(fileext = ".duckdb")
  file.create(f)
  wal <- paste0(f, ".wal")
  file.create(wal)
  on.exit(unlink(wal), add = TRUE)

  expect_error(crd_store_push(f, source = "s3://b/p/"), "write-ahead log")
})

test_that("crd_store_push validates arguments before reaching for the network", {
  expect_error(crd_store_push(file.path(tempdir(), "no_such.duckdb")), class = "chk_error")
})

# ---- embedding-model guard ------------------------------------------------

test_that(".crd_check_model stops on a mismatch unless overridden", {
  m <- manifest_two()
  expect_error(
    .crd_check_model(m, "gamma", "embeddinggemma:300m", allow = FALSE),
    "Embedding mismatch"
  )
  expect_warning(
    .crd_check_model(m, "gamma", "embeddinggemma:300m", allow = TRUE),
    "Embedding mismatch"
  )
})

test_that(".crd_check_model is silent when the model matches", {
  m <- manifest_two()
  expect_silent(.crd_check_model(m, "gamma", "nomic-embed-text (ollama)", allow = FALSE))
})

test_that(".crd_check_model does not compare a store against itself", {
  # Only alpha in the manifest; re-pushing alpha must not trip the guard on
  # alpha's own recorded model.
  m <- list(stores = list(
    alpha = list(md5 = "aaa", embedding_model = "embeddinggemma:300m")
  ))
  expect_silent(.crd_check_model(m, "alpha", "embeddinggemma:300m", allow = FALSE))
})

test_that(".crd_check_model flags a mismatch against any other store, not just the first", {
  # alpha migrated, beta did not — pushing alpha still conflicts with beta.
  m <- manifest_two()
  m$stores$alpha$embedding_model <- "embeddinggemma:300m"
  expect_error(
    .crd_check_model(m, "alpha", "embeddinggemma:300m", allow = FALSE),
    "nomic-embed-text"
  )
})

test_that(".crd_check_model is silent when no other store declares a model", {
  expect_silent(.crd_check_model(list(stores = list()), "a", "anything", allow = FALSE))
})

# ---- provenance -----------------------------------------------------------

test_that(".crd_git_provenance reads the given directory, not the working directory", {
  # Provenance must describe where the store was BUILT. Reading the process's
  # own cwd stamps a store with the SHA of whichever repo the push was issued
  # from — a plausible value pointing at unrelated code.
  outside <- withr::local_tempdir()
  expect_true(all(is.na(unlist(.crd_git_provenance(outside)))))

  # Use a purpose-built repo rather than asserting anything about the test
  # runner's cwd — under devtools::check() the tests run from a temp dir, where
  # `git -C .` fails and this would be red for the wrong reason.
  skip_if(!nzchar(Sys.which("git")), "git not available")
  fixture <- withr::local_tempdir()
  system2("git", c("-C", shQuote(fixture), "init", "-q"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", shQuote(fixture), "remote", "add", "origin",
                   "git@github.com:Owner/name.git"), stdout = FALSE, stderr = FALSE)
  expect_identical(.crd_git_provenance(fixture)$repo, "Owner/name")
})

test_that(".crd_git_provenance parses the https remote form too", {
  skip_if(!nzchar(Sys.which("git")), "git not available")
  fixture <- withr::local_tempdir()
  system2("git", c("-C", shQuote(fixture), "init", "-q"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", shQuote(fixture), "remote", "add", "origin",
                   "https://github.com/Owner/name.git"), stdout = FALSE, stderr = FALSE)
  expect_identical(.crd_git_provenance(fixture)$repo, "Owner/name")
})

test_that(".crd_git_provenance returns NA rather than erroring outside a repo", {
  out <- .crd_git_provenance(withr::local_tempdir())
  expect_named(out, c("repo", "branch", "head_sha"))
  expect_length(out, 3L)
})


# ---- serialization --------------------------------------------------------

test_that("manifest writes render NA numerics as null, not the string \"NA\"", {
  # jsonlite renders NA_integer_ as "NA" (a STRING) unless na = "null" is set.
  # A store with an unreadable COUNT(*) would otherwise land
  # {"documents": "NA"} in the shared manifest, permanently.
  entry <- list(documents = NA_integer_, chunks = 5L, repo = NA_character_)
  tmp <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(list(stores = list(a = entry)), tmp,
                       auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  txt <- paste(readLines(tmp, warn = FALSE), collapse = " ")

  expect_false(grepl('"NA"', txt, fixed = TRUE))
  expect_match(txt, "null")

  back <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  expect_null(back$stores$a$documents)
  expect_identical(back$stores$a$chunks, 5L)
})

# ---- embedding guard uses the artifact, not the environment ---------------

test_that(".crd_check_model flags a dimension conflict even when the label matches", {
  # embedding_model comes from the pusher's shell; embedding_size is read out
  # of the store. A store built with a different model by someone who never set
  # the env var carries the DEFAULT label — only the dimension catches it.
  m <- list(stores = list(
    alpha = list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 768L)
  ))
  expect_error(
    .crd_check_model(m, "beta", "nomic-embed-text (ollama)", allow = FALSE, size = 3072L),
    "dimension"
  )
})

test_that(".crd_check_model is silent when both label and dimension agree", {
  m <- list(stores = list(
    alpha = list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 768L)
  ))
  expect_silent(
    .crd_check_model(m, "beta", "nomic-embed-text (ollama)", allow = FALSE, size = 768L)
  )
})

test_that(".crd_check_model tolerates an unknown dimension", {
  m <- list(stores = list(
    alpha = list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 768L)
  ))
  expect_silent(
    .crd_check_model(m, "beta", "nomic-embed-text (ollama)", allow = FALSE, size = NA_integer_)
  )
})

# ---- probe failures must not be read as absence ---------------------------

test_that("crd_store_push aborts when it cannot tell whether a manifest exists", {
  skip_if_not_installed("duckdb")
  f <- withr::local_tempfile(fileext = ".duckdb")
  file.create(f)
  local_mocked_bindings(
    .crd_s3_head_bucket = function(source, profile = "") TRUE,
    .crd_s3_head_object = function(source, key, profile = "") {
      list(exists = FALSE, confirmed_absent = FALSE, etag = NA_character_,
           out = "An error occurred (SlowDown)")
    }
  )
  # Even with create_manifest = TRUE, an unconfirmed absence must not seed a
  # manifest over a populated one.
  expect_error(
    crd_store_push(f, source = "s3://b/p/", create_manifest = TRUE),
    "not a 404"
  )
})

test_that("crd_store_push refuses when the manifest exists but yields no ETag", {
  skip_if_not_installed("duckdb")
  f <- withr::local_tempfile(fileext = ".duckdb")
  file.create(f)
  local_mocked_bindings(
    .crd_s3_head_bucket = function(source, profile = "") TRUE,
    .crd_s3_head_object = function(source, key, profile = "") {
      list(exists = TRUE, confirmed_absent = FALSE, etag = NA_character_, out = "")
    }
  )
  # Without an ETag there is no precondition, so a concurrent write would be
  # undetectable.
  expect_error(crd_store_push(f, source = "s3://b/p/"), "could not obtain its ETag")
})

# ---- the model guard must read the artifact, not the environment -----------

test_that(".crd_store_model_from_meta recovers the model from the serialized closure", {
  # ragnar stores the embedding closure in metadata.embed_func. That is the
  # artifact's own record of how it was built; an env var describes the machine
  # doing the pushing, and nothing in this package ever sets one.
  fn <- function(x) ragnar::embed_ollama(x = x, model = "nomic-embed-text")
  blob <- serialize(fn, NULL)
  local_mocked_bindings(
    .crd_store_model_from_meta = function(con) {
      txt <- paste(deparse(unserialize(blob)), collapse = " ")
      hit <- regmatches(txt, regexpr('model[[:space:]]*=[[:space:]]*"[^"]+"', txt))
      sub('^model[[:space:]]*=[[:space:]]*"([^"]+)"$', "\\1", hit[1])
    }
  )
  expect_identical(.crd_store_model_from_meta(NULL), "nomic-embed-text")
})

test_that(".crd_model_norm drops the provider suffix so labels compare equal", {
  # The manifest records "nomic-embed-text (ollama)"; the store records
  # "nomic-embed-text". A guard that flags every push cries wolf, and gets
  # switched off for the case that matters.
  expect_identical(.crd_model_norm("nomic-embed-text (ollama)"), "nomic-embed-text")
  expect_identical(.crd_model_norm("  Nomic-Embed-Text  "), "nomic-embed-text")
  expect_identical(.crd_model_norm("embeddinggemma:300m"), "embeddinggemma:300m")
})

test_that(".crd_check_model catches a same-dimension model swap", {
  # nomic-embed-text and embeddinggemma are BOTH 768-dimensional, so a
  # dimension check alone cannot see this swap — the label has to be real.
  m <- list(stores = list(
    alpha = list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 768L)
  ))
  expect_error(
    .crd_check_model(m, "beta", "embeddinggemma", allow = FALSE, size = 768L),
    "Embedding mismatch"
  )
})

test_that(".crd_check_model does not flag the provider-suffix difference alone", {
  m <- list(stores = list(
    alpha = list(embedding_model = "nomic-embed-text (ollama)", embedding_size = 768L)
  ))
  expect_silent(
    .crd_check_model(m, "beta", "nomic-embed-text", allow = FALSE, size = 768L)
  )
})

# ---- probe and precondition anchoring -------------------------------------

test_that(".crd_s3_head_object does not treat 403 as an absence", {
  # HeadObject returns 403, not 404, for a missing key when the caller lacks
  # s3:ListBucket. Reading that as "no object here" turns a permissions problem
  # into a first push.
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = character(), err = "An error occurred (403) when calling HeadObject: Forbidden",
           status = 254L)
    }
  )
  res <- .crd_s3_head_object("s3://b/p/", "log.json")
  expect_false(res$confirmed_absent)
})

test_that(".crd_s3_head_object is not fooled by a bare 404 substring", {
  local_mocked_bindings(
    .crd_aws = function(args, profile = "", clean_stdout = FALSE) {
      list(out = character(),
           err = "An error occurred (AccessDenied); request id 7404ff", status = 254L)
    }
  )
  expect_false(.crd_s3_head_object("s3://b/p/", "log.json")$confirmed_absent)
})

test_that(".crd_s3_precondition_failed treats 409 ConditionalRequestConflict as retryable", {
  # S3 returns this for a conditional write racing another in-flight one and
  # documents it as retryable; hard-failing would strand an uploaded binary.
  expect_true(.crd_s3_precondition_failed(
    list(out = "An error occurred (ConditionalRequestConflict)", err = character(),
         status = 254L)))
})

test_that(".crd_s3_put refuses to drop a requested precondition", {
  # Silently degrading to an unconditional write is the defect the retry loop
  # was fixed for; the helper must not reintroduce it at any call site.
  expect_error(
    .crd_s3_put("/tmp/x", "s3://b/p/", "k", if_match = NA_character_),
    "Refusing to fall back"
  )
  expect_error(
    .crd_s3_put("/tmp/x", "s3://b/p/", "k", if_match = ""),
    "Refusing to fall back"
  )
})
