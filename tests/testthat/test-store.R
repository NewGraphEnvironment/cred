# Tests for the ragnar evidence-store layer.
#
# Nothing here touches the network, S3, or Ollama. The store functions are
# thin over ragnar; what is worth testing is the resolution, verification and
# validation logic cred adds around it.

# A manifest fixture exercising the shape actually observed in the wild —
# `built_by` is a bare string for one store and an array for another.
manifest_fixture <- function() {
  jsonlite::fromJSON(simplifyVector = FALSE, txt = '{
    "date_updated": "2026-08-31T21:02:28Z",
    "manifest_note": "Push must merge into this file, never replace it.",
    "stores": {
      "alpha": {
        "documents": 15, "chunks": 2464, "embedding_size": 768,
        "embedding_model": "nomic-embed-text (ollama)",
        "md5": "34ff806cd9a55b18a25b9fadce294592",
        "built_by": "scripts/rag_build.R"
      },
      "beta": {
        "documents": 283, "chunks": 22883, "embedding_size": 768,
        "embedding_model": "nomic-embed-text (ollama)",
        "md5": "642d874e42b3f7a07dd8b202ec0ecfb5",
        "built_by": ["scripts/0151-build.R", "scripts/0152-add.R"]
      }
    }
  }')
}

test_that(".crd_store_source reads the option, then the env var", {
  withr::local_options(cred.store_source = "s3://bucket/prefix")
  expect_identical(.crd_store_source(), "s3://bucket/prefix/")

  withr::local_options(cred.store_source = NULL)
  withr::local_envvar(CRED_STORE_SOURCE = "s3://other/place/")
  expect_identical(.crd_store_source(), "s3://other/place/")
})

test_that(".crd_store_source normalises trailing slashes", {
  expect_identical(.crd_store_source("s3://b/p"), "s3://b/p/")
  expect_identical(.crd_store_source("s3://b/p/"), "s3://b/p/")
  expect_identical(.crd_store_source("s3://b/p///"), "s3://b/p/")
})

test_that(".crd_store_source errors with actionable guidance when unset", {
  withr::local_options(cred.store_source = NULL)
  withr::local_envvar(CRED_STORE_SOURCE = "")

  expect_error(.crd_store_source(), "No evidence-store source configured")
  # The error must name both configuration routes and the escape hatch, and it
  # must NOT leak a real bucket address — cred is a public package.
  msg <- tryCatch(.crd_store_source(), error = conditionMessage)
  expect_match(msg, "cred.store_source", fixed = TRUE)
  expect_match(msg, "CRED_STORE_SOURCE", fixed = TRUE)
  expect_match(msg, "verify = FALSE", fixed = TRUE)
  expect_match(msg, "<bucket>", fixed = TRUE)
})

test_that(".crd_manifest_entry normalises built_by whether string or array", {
  m <- manifest_fixture()

  alpha <- .crd_manifest_entry(m, "alpha")
  expect_type(alpha$built_by, "character")
  expect_length(alpha$built_by, 1L)

  beta <- .crd_manifest_entry(m, "beta")
  expect_type(beta$built_by, "character")
  expect_length(beta$built_by, 2L)
})

test_that(".crd_manifest_entry carries the fields verification depends on", {
  alpha <- .crd_manifest_entry(manifest_fixture(), "alpha")
  expect_identical(alpha$md5, "34ff806cd9a55b18a25b9fadce294592")
  expect_identical(alpha$documents, 15L)
  expect_identical(alpha$chunks, 2464L)
})

test_that(".crd_manifest_entry lists the available stores when one is missing", {
  expect_error(
    .crd_manifest_entry(manifest_fixture(), "nonexistent"),
    "not described in the manifest"
  )
  msg <- tryCatch(.crd_manifest_entry(manifest_fixture(), "nonexistent"),
                  error = conditionMessage)
  expect_match(msg, "alpha, beta", fixed = TRUE)
})

test_that(".crd_need names every missing package and how to install it", {
  expect_null(.crd_need("stats"))

  msg <- tryCatch(.crd_need(c("stats", "definitelyNotAPackage")),
                  error = conditionMessage)
  expect_match(msg, "definitelyNotAPackage", fixed = TRUE)
  expect_match(msg, "pak::pak", fixed = TRUE)
  # An installed package must not be reported as missing.
  expect_false(grepl("stats", sub(".*pak::pak", "", msg), fixed = TRUE))
})

test_that("crd_store_connect(verify = FALSE) refuses to invent a missing store", {
  skip_if_not_installed("ragnar")
  skip_if_not_installed("duckdb")

  expect_error(
    crd_store_connect(file.path(tempdir(), "no_such_store.duckdb"), verify = FALSE),
    "Store not found locally"
  )
})

test_that("crd_store_build demands exactly one of collection or citation_keys", {
  target <- file.path(tempdir(), "unused.duckdb")

  expect_error(crd_store_build(target), "exactly one of")
  expect_error(
    crd_store_build(target, collection = "vca", citation_keys = "smith2020"),
    "exactly one of"
  )
})

test_that("crd_store_build refuses to clobber an existing store by default", {
  skip_if_not_installed("ragnar")
  skip_if_not_installed("duckdb")

  target <- file.path(tempdir(), "already_here.duckdb")
  file.create(target)
  on.exit(unlink(target), add = TRUE)

  expect_error(
    crd_store_build(target, collection = "vca"),
    "Store already exists"
  )
})

test_that(".crd_zot_key_from_path returns NA for paths carrying no attachment key", {
  # Parallel output, NA where the parent directory is not an 8-character
  # Zotero attachment key.
  paths <- c("/tmp/not_a_store/file.pdf", "/some/where/lowercase/file.pdf")
  out <- .crd_zot_key_from_path(paths)

  expect_length(out, length(paths))
  expect_true(all(is.na(out)))
})

test_that(".crd_zot_key_from_path is NA-safe and length-preserving on empty input", {
  expect_length(.crd_zot_key_from_path(character()), 0L)
  expect_true(is.na(.crd_zot_key_from_path(NA_character_)))
})

test_that(".crd_zot_key_from_path degrades to NA when Zotero is absent", {
  paths <- "/nowhere/storage/W6LD4RRG/paper.pdf"
  out <- .crd_zot_key_from_path(paths, zotero_dir = tempfile())

  expect_length(out, 1L)
  expect_true(is.na(out))
})

test_that(".crd_retrieval_score reads long-form metric_name/metric_value", {
  res <- data.frame(
    metric_name  = c("bm25", "bm25"),
    metric_value = c(10.9, 9.59),
    stringsAsFactors = FALSE
  )
  out <- .crd_retrieval_score(res)

  expect_identical(out$score, c(10.9, 9.59))
  expect_identical(out$metric, c("bm25", "bm25"))
})

test_that(".crd_retrieval_score handles the pivoted hybrid shape", {
  # ragnar_retrieve() pivots metric_name wider, so there is no metric_value
  # column at all — reading it unconditionally yields an all-NA score.
  res <- data.frame(
    bm25            = c(10.9, NA),
    cosine_distance = c(NA, 0.31),
    stringsAsFactors = FALSE
  )
  out <- .crd_retrieval_score(res)

  expect_identical(out$score, c(10.9, 0.31))
  expect_identical(out$metric, c("bm25", "cosine_distance"))
  expect_false(any(is.na(out$score)))
})

test_that(".crd_retrieval_score prefers bm25 when a row carries both metrics", {
  res <- data.frame(bm25 = 8.2, cosine_distance = 0.4, stringsAsFactors = FALSE)
  out <- .crd_retrieval_score(res)

  expect_identical(out$score, 8.2)
  expect_identical(out$metric, "bm25")
})

test_that(".crd_retrieval_score returns NA of the right length when no metric is present", {
  res <- data.frame(text = c("a", "b"), stringsAsFactors = FALSE)
  out <- .crd_retrieval_score(res)

  expect_length(out$score, 2L)
  expect_length(out$metric, 2L)
  expect_true(all(is.na(out$score)))
})

test_that(".crd_store_source rejects NA — nzchar(NA) is TRUE and would pass the guard", {
  withr::local_envvar(CRED_STORE_SOURCE = "")
  expect_error(.crd_store_source(NA_character_), "No evidence-store source configured")
})

test_that(".crd_store_source rejects a non-scalar source with a message that says so", {
  expect_error(
    .crd_store_source(c("s3://a/", "s3://b/")),
    "must be a single string"
  )
})

test_that(".crd_manifest_entry refuses an entry with no md5 to verify against", {
  m <- list(stores = list(x = list(documents = 1L)))
  expect_error(.crd_manifest_entry(m, "x"), "no md5")
})

test_that(".crd_manifest_entry lowercases md5 so case cannot cause a false mismatch", {
  m <- list(stores = list(x = list(md5 = "34FF806CD9A55B18A25B9FADCE294592")))
  expect_identical(.crd_manifest_entry(m, "x")$md5,
                   "34ff806cd9a55b18a25b9fadce294592")
})

test_that(".crd_aws shell-quotes its arguments", {
  # system2() quotes the command but not the arguments, so an unquoted `;`
  # would execute. Assert the quoting helper neutralises it.
  payload <- "first; echo INJECTED"
  quoted <- vapply(payload, shQuote, character(1L), USE.NAMES = FALSE)
  out <- suppressWarnings(system2("echo", quoted, stdout = TRUE))

  # Unquoted, the shell runs both commands and returns two lines
  # ("first", "INJECTED"). Quoted, it echoes one literal argument.
  expect_length(out, 1L)
  expect_identical(out, payload)
})
