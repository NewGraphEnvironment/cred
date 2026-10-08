# store.R — ragnar evidence-store resolution, verification and connection

#' Require a suggested package
#'
#' Mirrors the guard used in [crd_zot_src_lookup()] for `RSQLite`. The ragnar
#' stack (`ragnar`, `DBI`, `duckdb`) lives in `Suggests` rather than `Imports`
#' so that users who only run the audit workflow do not pay for a DuckDB
#' install.
#'
#' @param pkg `character` vector of package names.
#' @return `NULL`, invisibly. Called for its side effect of erroring.
#' @noRd
.crd_need <- function(pkg) {
  missing <- pkg[!vapply(pkg, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing) > 0L) {
    stop("Package(s) required but not installed: ", paste(missing, collapse = ", "),
         "\n  Install with: pak::pak(c(", paste0("'", missing, "'", collapse = ", "), "))",
         call. = FALSE)
  }
  invisible(NULL)
}

#' Resolve the evidence-store source location
#'
#' Reads `getOption("cred.store_source")`, falling back to the
#' `CRED_STORE_SOURCE` environment variable. There is deliberately **no
#' default** — `cred` is a public package and must not carry a bucket address.
#'
#' @param source `character(1)` or `NULL`.
#' @return `character(1)` source URI with a single trailing slash.
#' @noRd
.crd_store_source <- function(source = getOption("cred.store_source")) {
  # nzchar(NA) is TRUE, so an NA source would sail past the guard below and
  # surface much later as the literal S3 URI "NAlog.json".
  if (!is.null(source) && length(source) != 1L) {
    stop("The evidence-store source must be a single string, not length ",
         length(source), ".", call. = FALSE)
  }
  if (is.null(source) || is.na(source) || !nzchar(source)) {
    source <- Sys.getenv("CRED_STORE_SOURCE")
  }
  if (is.na(source) || !nzchar(source)) {
    stop("No evidence-store source configured.\n",
         "  Set one of:\n",
         "    options(cred.store_source = \"s3://<bucket>/<prefix>/\")\n",
         "    Sys.setenv(CRED_STORE_SOURCE = \"s3://<bucket>/<prefix>/\")\n",
         "  Ask a maintainer for the value. To open a local store without\n",
         "  verifying it against the manifest, pass verify = FALSE.",
         call. = FALSE)
  }
  sub("/*$", "/", source)
}

#' Run an AWS CLI command
#'
#' Arguments are shell-quoted individually: [system2()] quotes the command but
#' pastes its arguments into a shell command line unquoted, so a path with a
#' space silently splits into several arguments and a `;` in a store name would
#' execute.
#'
#' The exit status is returned rather than discarded. `aws s3 cp` reports a
#' missing key and a nonexistent bucket identically — both exit 1 with
#' `404 ... Key "..." does not exist` — so callers that need to tell "no
#' manifest here" from "wrong bucket" must branch on status from the `s3api`
#' probes instead of parsing `cp` output.
#'
#' `clean_stdout = TRUE` routes stderr to a file instead of merging it into
#' stdout. Callers that *parse* the output must use it: `aws` writes warnings to
#' stderr while still exiting 0 (the urllib3/LibreSSL notice on macOS, IMDS
#' credential retries), and a merged stream welds those onto the value being
#' read. Such a run passes every test until the day a warning appears.
#'
#' @param args `character` vector of arguments passed to `aws`.
#' @param profile `character(1)` AWS profile name, or `""` to omit.
#' @param clean_stdout `logical(1)` keep stderr out of `out`. Default `FALSE`.
#' @return A `list` with `out` (stdout lines, plus stderr unless
#'   `clean_stdout`), `err` (stderr lines when separated) and `status`
#'   (integer exit code, `0` on success).
#' @noRd
.crd_aws <- function(args, profile = Sys.getenv("AWS_PROFILE"), clean_stdout = FALSE) {
  if (!nzchar(Sys.which("aws"))) {
    stop("The AWS CLI ('aws') was not found on PATH.\n",
         "  Install it, or supply an already-downloaded store and use verify = FALSE.",
         call. = FALSE)
  }
  if (nzchar(profile)) args <- c(args, "--profile", profile)
  args <- vapply(args, shQuote, character(1L), USE.NAMES = FALSE)

  err <- character()
  if (clean_stdout) {
    err_file <- tempfile("cred-aws-err-")
    on.exit(unlink(err_file), add = TRUE)
    out <- suppressWarnings(system2("aws", args, stdout = TRUE, stderr = err_file))
    if (file.exists(err_file)) err <- readLines(err_file, warn = FALSE)
  } else {
    out <- suppressWarnings(system2("aws", args, stdout = TRUE, stderr = TRUE))
  }
  status <- attr(out, "status")
  list(out = as.character(out), err = err,
       status = if (is.null(status)) 0L else as.integer(status))
}

#' Read the evidence-store provenance manifest
#'
#' Fetches `log.json` from the configured source. The manifest is written
#' merge-on-write: every store the bucket holds is described in the single
#' file, so a push that replaces it orphans the stores it did not push.
#'
#' @param source `character(1)` source URI, as returned by `.crd_store_source()`.
#' @param profile `character(1)` AWS profile name.
#' @return A named `list` with elements `date_updated` and `stores`.
#' @noRd
.crd_manifest_read <- function(source, profile = Sys.getenv("AWS_PROFILE")) {
  dest <- file.path(tempdir(), paste0("cred-log-", Sys.getpid(), ".json"))
  on.exit(unlink(dest), add = TRUE)

  res <- .crd_aws(c("s3", "cp", paste0(source, "log.json"), dest), profile = profile)
  if (!file.exists(dest)) {
    stop("Could not fetch the store manifest from ", source, "log.json\n  ",
         paste(res$out, collapse = "\n  "), call. = FALSE)
  }

  jsonlite::fromJSON(dest, simplifyVector = FALSE)
}

#' Extract one store's entry from a manifest
#'
#' `built_by` is inconsistently typed across existing manifest entries — a
#' bare string for some stores, an array for others — so it is normalised to a
#' character vector here rather than at every call site.
#'
#' @param manifest `list` as returned by `.crd_manifest_read()`.
#' @param name `character(1)` store name (no extension).
#' @return A named `list` describing the store.
#' @noRd
.crd_manifest_entry <- function(manifest, name) {
  entry <- manifest$stores[[name]]
  if (is.null(entry)) {
    stop("Store '", name, "' is not described in the manifest.\n",
         "  Stores available: ", paste(names(manifest$stores), collapse = ", "),
         call. = FALSE)
  }
  if (!is.null(entry$built_by)) entry$built_by <- unlist(entry$built_by, use.names = FALSE)

  # Without an md5 there is nothing to verify against, and the caller would
  # otherwise download, compare against NULL, and fail after having already
  # replaced a good local store.
  if (is.null(entry$md5) || !nzchar(entry$md5)) {
    stop("Manifest entry for '", name, "' carries no md5 — it cannot be verified.\n",
         "  Ask whoever pushed the store to repair the manifest, or pass verify = FALSE.",
         call. = FALSE)
  }
  entry$md5 <- tolower(entry$md5)
  entry
}

#' How wide is the vector an embedder returned?
#'
#' [ragnar::embed_ollama()] returns a matrix with one row per input, so `ncol()`
#' is the width. Nothing obliges a custom embedder to do the same, and `ncol()`
#' on a bare vector is `NULL` — which the comparison downstream would then error
#' on, turning a check that is supposed to degrade quietly into a hard failure
#' at connect.
#'
#' @param x whatever an embedder returned.
#' @return `integer(1)` width, or `NA_integer_` when none can be read.
#' @noRd
.crd_embed_width <- function(x) {
  if (is.null(x)) return(NA_integer_)
  n <- if (!is.null(ncol(x))) {
    ncol(x)
  } else if (is.atomic(x)) {
    length(x)
  } else {
    NA_integer_
  }
  n <- suppressWarnings(as.integer(n))
  # A zero-width result is not a width. It is what an embedder returns when it
  # has failed without raising, and comparing it would report a mismatch whose
  # remedy ("re-pull the model") has nothing to do with the cause.
  if (length(n) != 1L || is.na(n) || n < 1L) return(NA_integer_)
  n
}

#' Where a store lives, for keying a once-per-session warning
#'
#' The `location`, not the `name`: `ragnar_store_connect()` falls back to
#' `unique_store_name()` when a store records no name, and that is a per-session
#' counter (`store_001`), so two different stores can carry one name while two
#' copies of one store at different paths cannot share a path.
#'
#' @param store a connected ragnar store, or anything at all.
#' @return `character(1)`.
#' @noRd
.crd_store_loc <- function(store = NULL) {
  loc <- tryCatch(as.character(store@location), error = function(e) NA_character_)
  # `.crd_have()` rather than `nzchar()` directly: nzchar(NA) is TRUE, so the
  # obvious non-empty test waves an NA straight through.
  if (!.crd_have(loc)) "unknown-store" else loc
}

#' Frequency key for the connect-time "could not check" warning
#'
#' A **separate** scheme from [.crd_retrieval_fallback_id()], and that is the
#' whole point. Keyed the same way, a "could not check (connection)" emitted by
#' [crd_store_connect()] would consume the once-per-session slot that
#' [crd_search()]'s fallback warning needs for the same reason on the same
#' store — so the search would then degrade to BM25 silently, which is the
#' diagnosis loss #29 exists to end, arriving from the other side.
#'
#' It lives in a function rather than inline so a test can ask the code what
#' key it uses instead of restating it. A test that rebuilds the expected key
#' from a literal cannot fail when the code's key changes — measured: it did
#' not.
#'
#' @param reason `character(1)` from [.crd_retrieval_failure()].
#' @param store the store being checked, or `NULL`.
#' @return `character(1)` id for `rlang::warn(.frequency_id = )`.
#' @noRd
.crd_store_probe_id <- function(reason, store = NULL) {
  paste0("cred_store_probe_", reason, "_", .crd_store_loc(store))
}

#' Check a connected store's embeddings against the service and the manifest
#'
#' The check [crd_store_connect()]'s md5 compare cannot perform. That compare
#' answers "is this the file the manifest describes" — stale, truncated, locally
#' rebuilt — and is structurally unable to see a store whose embedding model
#' moved underneath it, because such a store has **exactly** the bytes the
#' manifest recorded (NewGraphEnvironment/cred#30).
#'
#' The probe is the load-bearing half, and it uses the store's **own** recorded
#' embedder: `ragnar_store_connect()` does
#' `embed <- unserialize(metadata$embed_func[[1L]])`, so this is not a model
#' name reconstructed from a string, it is the function that will actually embed
#' queries against this store. Comparing its width against the store's own
#' `embedding_size` is exactly the condition that otherwise surfaces downstream
#' as a `cred_retrieval_fallback_dimension` warning from [crd_search()].
#'
#' **Width is the detectable part.** A model whose weights changed while its
#' dimension stayed the same is invisible here, and to every other check in this
#' package. The remedy text does not imply otherwise.
#'
#' Severity tracks the evidence, which is why only one tier errors:
#'
#' * **Probe ran, widths differ** — error. Semantic retrieval against this store
#'   is structurally broken, which is the same "do not trust results" severity
#'   the md5 mismatch already errors on.
#' * **Manifest label disagrees with the store's own record** — warning. The
#'   manifest's `embedding_model` comes from the pusher's environment:
#'   [.crd_store_describe()] falls back to `CRED_EMBED_MODEL` when it cannot
#'   read the store's `embed_func`. It is a label, and the weaker half of the
#'   pair.
#' * **Probe could not run** — not a mismatch at all, and not grounds to refuse
#'   a store. A dead Ollama says nothing about this file, and BM25 retrieval
#'   needs no embedding. Classified by [.crd_retrieval_failure()] and reported
#'   once per session per reason and store.
#' * **No embedder recorded, or `embedding_size` unreadable** — skipped in
#'   silence. There is nothing to compare, and the push side already warns about
#'   an unreadable size, so repeating it on every connect is noise.
#'
#' @param store a connected ragnar store.
#' @param entry `list` manifest entry for this store, or `NULL` on the
#'   `verify = FALSE` path where no manifest was read.
#' @param name `character(1)` store name, for the message.
#' @return `NULL`, invisibly. Errors on a confirmed width mismatch.
#' @noRd
.crd_check_store_embedding <- function(store, entry = NULL, name = NULL) {
  if (!.crd_have(name)) name <- basename(.crd_store_loc(store))
  meta <- .crd_store_meta_brief(store)

  # Tier 2 first, because it is the one that does not need the size.
  if (!is.null(entry) && .crd_have(entry$embedding_model) &&
        .crd_is_model_name(meta$model) &&
        !identical(.crd_model_norm(entry$embedding_model[1]),
                   .crd_model_norm(meta$model))) {
    rlang::warn(
      paste0(
        "The manifest and the store disagree about which model embedded '", name, "'.\n",
        "  the store records:  ", meta$model, "\n",
        "  the manifest says:  ", entry$embedding_model[1], "\n",
        "  The store's own record is the stronger of the two: the manifest's label\n",
        "  comes from whoever pushed it, and crd_store_push() falls back to\n",
        "  CRED_EMBED_MODEL when it cannot read the store. Results are still\n",
        "  self-consistent; what is wrong is one of the two labels."
      ),
      class = c("cred_store_model_label_mismatch", "cred_store_embedding_check"),
      .frequency = "once",
      .frequency_id = paste0("cred_store_model_label_", .crd_store_loc(store))
    )
  }

  if (!.crd_have(meta$size)) return(invisible(NULL))

  embed <- tryCatch(store@embed, error = function(e) NULL)
  if (!is.function(embed)) return(invisible(NULL))

  probe <- tryCatch(embed("cred embedding width probe"), error = function(e) e)

  if (inherits(probe, "condition")) {
    reason <- .crd_retrieval_failure(probe)
    rlang::warn(
      paste0(
        "Could not check the embedding model for '", name, "' -- the probe failed.\n",
        "  This is not evidence about the store. BM25 retrieval needs no embedding\n",
        "  and is unaffected; semantic retrieval will not work until this does.\n",
        "  Cause: ", .crd_indent_cause(conditionMessage(probe)), "\n",
        .crd_embed_remedy(reason, probe, store = store, context = "connect")
      ),
      class = c(paste0("cred_store_probe_failed_", reason),
                "cred_store_probe_failed", "cred_store_embedding_check"),
      .frequency = "once",
      .frequency_id = .crd_store_probe_id(reason, store)
    )
    return(invisible(NULL))
  }

  got <- .crd_embed_width(probe)
  if (!.crd_have(got) || identical(got, as.integer(meta$size))) return(invisible(NULL))

  model_part <- if (.crd_is_model_name(meta$model)) meta$model else "unknown"
  rlang::abort(
    paste0(
      "Embedding width mismatch for '", name, "'.\n",
      "  this store holds:                  ", meta$size, "-wide embeddings",
      if (.crd_is_model_name(meta$model)) paste0(", model ", meta$model) else "", "\n",
      "  its recorded embedder now returns: ", got, "-wide\n",
      "  A connected store embeds queries with the embedder recorded inside it, so\n",
      "  the model that name resolves to on this machine is no longer the model the\n",
      "  store was built with. Semantic retrieval would answer differently while\n",
      "  looking healthy, and the md5 compare cannot see it: this store has exactly\n",
      "  the bytes the manifest recorded.\n",
      "    ollama pull ", .crd_fallback_model(store = store), "\n",
      "  or rebuild with crd_store_build(). BM25 retrieval needs no embedding and is\n",
      "  unaffected, so pass check_model = FALSE to open the store anyway."
    ),
    class = c("cred_store_embedding_mismatch", "cred_store_embedding_check"),
    store_size = as.integer(meta$size),
    embed_width = got,
    store_model = meta$model
  )
}


#' Open a store and run the connect-time checks on it
#'
#' One tail for every path out of [crd_store_connect()]. It had three separate
#' `return(ragnar::ragnar_store_connect(...))` sites, and a check wired into two
#' of them would leave the third — the `verify = FALSE` offline route — silently
#' unprotected while every unit test passed. A guard that one caller of a shared
#' harness misses is its own entry in `code-check.md`.
#'
#' @param local_path `character(1)` path to the `.duckdb` store.
#' @param read_only `logical(1)` passed through to ragnar.
#' @param entry `list` manifest entry, or `NULL` when none was read.
#' @param name `character(1)` store name, for messages.
#' @param check_model `logical(1)` run [.crd_check_store_embedding()].
#' @return A connected ragnar store.
#' @noRd
.crd_store_open <- function(local_path, read_only, entry = NULL, name = NULL,
                            check_model = TRUE) {
  store <- ragnar::ragnar_store_connect(local_path, read_only = read_only)
  if (!isTRUE(check_model)) return(store)

  # Until #30 nothing could fail after the connect returned, so there was
  # nothing to clean up. The check needs `store@con` and `store@embed`, so it
  # has to run after, and a mismatch now errors with a live duckdb connection
  # open and unreferenced. Same `complete <- FALSE` shape crd_store_build()
  # uses. (The predicted follow-on -- that a retry under a different
  # `read_only` would then be refused -- does NOT reproduce on ragnar 0.3.0:
  # read-write then read-only on one file both succeed, measured. The leak is
  # worth closing on its own.)
  ok <- FALSE
  on.exit(
    if (!ok) try(DBI::dbDisconnect(store@con, shutdown = TRUE), silent = TRUE),
    add = TRUE
  )
  .crd_check_store_embedding(store, entry = entry, name = name)
  ok <- TRUE
  store
}

#' Connect to a ragnar evidence store, pulling and verifying it if needed
#'
#' Resolves a store by name, using the local copy when its MD5 matches the
#' shared manifest and downloading it from `source` otherwise. Verification is
#' the point: a store that is present is not thereby trustworthy, and a silent
#' local rebuild produces an artefact that looks perfectly healthy.
#'
#' **Two independent checks, because one cannot do both jobs.**
#'
#' The **MD5 compare** answers "is this the file the manifest describes" — a
#' stale copy, a truncated download, a local rebuild nobody pushed. It is
#' structurally unable to see a store whose *embedding model* has moved
#' underneath it, because that store's bytes are exactly the ones the manifest
#' recorded.
#'
#' The **embedding check** (`check_model`) is what sees that. It runs the
#' store's own recorded embedder — ragnar unserialises it out of the store — and
#' compares the width it returns against the width the store holds. A
#' disagreement is an error: semantic retrieval against such a store would
#' answer differently while looking healthy. It also compares the manifest's
#' `embedding_model` label against the store's own record, which is a warning,
#' the label being the weaker of the two.
#'
#' **What neither sees** is a model whose weights changed while its dimension
#' stayed the same. No check in this package can detect that.
#'
#' A mismatch that arises *after* a successful connect — the model re-pulled
#' mid-session, or `@embed` replaced on the store object — is outside both, and
#' still surfaces downstream as a `cred_retrieval_fallback_dimension` warning
#' from [crd_search()]; see "Diagnosing a fallback" there. So does any mismatch
#' on a store opened with `check_model = FALSE`, or one whose probe could not
#' run. The two layers are complementary, not redundant
#' (NewGraphEnvironment/cred#30).
#'
#' **The embedding check executes code recorded in the store.** `embed_func` is
#' deserialised and called. On the `verify = TRUE` paths the manifest's MD5
#' vouches for those bytes; under `verify = FALSE` nothing does. And ragnar
#' pins only the *model* into that function, not `base_url`, so for a store
#' built against Ollama the probe never leaves the machine — while a store built
#' with [ragnar::embed_openai()] or an explicit remote `base_url` makes a
#' billed third-party request on every connect. `check_model = FALSE` is the
#' opt-out.
#'
#' `source` has **no default value**. Configure it with
#' `options(cred.store_source = )` or the `CRED_STORE_SOURCE` environment
#' variable, in the shape `s3://<bucket>/<prefix>/`. Pushing a store is out of
#' scope for this package — it is a build-side operation performed rarely by
#' whoever built the store.
#'
#' @param store `character(1)` store name (e.g. `"vca_refs"`), or a path to an
#'   existing `.duckdb` file.
#' @param source `character(1)` source URI holding the stores and `log.json`.
#'   Defaults to `getOption("cred.store_source")`, then `CRED_STORE_SOURCE`.
#' @param dir `character(1)` local directory holding stores.
#'   Default `"data/rag"`. Ignored when `store` is itself a path.
#' @param profile `character(1)` AWS profile. Default `AWS_PROFILE`.
#' @param read_only `logical(1)` open the store read-only. Default `TRUE`.
#' @param verify `logical(1)` check the local MD5 against the manifest.
#'   Default `TRUE`. `FALSE` opens a local store without contacting `source` —
#'   the only supported way to work without the bucket. It does **not** by
#'   itself make the call fully offline: `check_model` still probes the
#'   embedding service, which for an Ollama-built store is localhost. Pass
#'   `check_model = FALSE` as well for a call that touches nothing.
#' @param check_model `logical(1)` compare the store's embeddings against what
#'   its recorded embedder now returns, and its model label against the
#'   manifest. Default `TRUE`. A confirmed width mismatch is an **error**; pass
#'   `FALSE` to open such a store anyway, which is a reasonable thing to want —
#'   BM25 retrieval needs no embedding and is unaffected by the mismatch.
#' @return A `ragnar` store object, as returned by
#'   [ragnar::ragnar_store_connect()].
#' @export
#' @examples
#' \dontrun{
#' options(cred.store_source = "s3://<bucket>/<prefix>/")
#' store <- crd_store_connect("vca_refs")
#' crd_search(store, "bankfull width regression")
#'
#' # Offline, against a store already on disk
#' crd_store_connect("vca_refs", verify = FALSE)
#' }
crd_store_connect <- function(store,
                              source = getOption("cred.store_source"),
                              dir = "data/rag",
                              profile = Sys.getenv("AWS_PROFILE"),
                              read_only = TRUE,
                              verify = TRUE,
                              check_model = TRUE) {
  chk::chk_string(store)
  chk::chk_string(dir)
  chk::chk_flag(read_only)
  chk::chk_flag(verify)
  chk::chk_flag(check_model)
  .crd_need(c("ragnar", "DBI", "duckdb"))

  if (grepl("[.]duckdb$", store)) {
    local_path <- path.expand(store)
    name <- sub("[.]duckdb$", "", basename(local_path))
  } else {
    name <- store
    local_path <- file.path(path.expand(dir), paste0(name, ".duckdb"))
  }

  if (!verify) {
    if (!file.exists(local_path)) {
      stop("Store not found locally: ", local_path,
           "\n  verify = FALSE cannot download it. Configure a source and retry.",
           call. = FALSE)
    }
    message("Opening ", local_path, " unverified (verify = FALSE).")
    # No manifest was read, so there is no entry to compare a label against --
    # but the probe does not need one, and this is the path a user reaches by
    # default when no source is configured.
    return(.crd_store_open(local_path, read_only, name = name,
                           check_model = check_model))
  }

  source <- .crd_store_source(source)
  entry <- .crd_manifest_entry(.crd_manifest_read(source, profile = profile), name)

  if (file.exists(local_path) &&
        identical(tolower(unname(tools::md5sum(local_path))), entry$md5)) {
    message("Using local ", local_path, " (md5 matches manifest; ",
            entry$documents, " docs, ", entry$chunks, " chunks).")
    return(.crd_store_open(local_path, read_only, entry = entry, name = name,
                           check_model = check_model))
  }

  if (file.exists(local_path)) {
    message("Local ", basename(local_path), " does not match the manifest — re-downloading.")
  }

  dir.create(dirname(local_path), recursive = TRUE, showWarnings = FALSE)

  # Download to a sibling temp file and only move it into place once it
  # verifies. Writing straight to local_path would destroy a store that is
  # merely unpushed, and an interrupted transfer would leave a truncated file
  # that a later verify = FALSE call opens as though it were complete.
  part <- paste0(local_path, ".part-", Sys.getpid())
  on.exit(unlink(part), add = TRUE)

  res <- .crd_aws(c("s3", "cp", paste0(source, name, ".duckdb"), part), profile = profile)
  if (!file.exists(part)) {
    stop("Download failed for store '", name, "'.\n  ", paste(res$out, collapse = "\n  "),
         call. = FALSE)
  }

  got <- tolower(unname(tools::md5sum(part)))
  if (!identical(got, entry$md5)) {
    stop("MD5 mismatch after download for '", name, "'.\n",
         "  manifest: ", entry$md5, "\n  download: ", got, "\n",
         "  The store may be mid-push or the manifest stale — do not trust results.\n",
         "  Any existing local store was left untouched.",
         call. = FALSE)
  }

  if (!file.rename(part, local_path)) {
    stop("Verified download could not be moved into place: ", local_path, call. = FALSE)
  }

  message("Downloaded ", name, " (", entry$documents, " docs, ", entry$chunks,
          " chunks, embedded with ", entry$embedding_model, ").")
  .crd_store_open(local_path, read_only, entry = entry, name = name,
                  check_model = check_model)
}

# Which end of each retrieval metric counts as "better", and the roster of
# metrics cred knows. Single source of truth for BOTH facts: an earlier version
# was authoritative about direction while each branch decided membership its own
# way, and the two then disagreed about the same column — the pivoted path
# dropping an unrecognised metric entirely, the long-form path scoring it in the
# wrong direction.
#
# The three distances are ragnar's full alternative set, read from
# `ragnar:::method_to_info()`, which maps every one of `cosine_distance`,
# `euclidean_distance` and `negative_inner_product` to `"ASC"`.
.crd_metric_dirs <- c(
  bm25                   = "max",
  cosine_distance        = "min",
  euclidean_distance     = "min",
  negative_inner_product = "min"
)

# Columns of a retrieval frame that are not scores. Used to spot a metric column
# cred does not know, so an unrecognised metric is still scored rather than
# silently dropped.
.crd_non_metric_cols <- c("origin", "doc_id", "chunk_id", "start", "end",
                          "context", "text", "embedding", "metric_name",
                          "metric_value")

# Direction for one metric.
#
# Unknown names default to "min", not "max": every metric ragnar offers besides
# BM25 is a distance, and all three are ASC. An unknown name is therefore far
# likelier to be another distance than a new similarity — the opposite of what
# is intuitive, which is why the evidence is recorded here rather than the
# guess.
#
# Direction only matters for a cell holding several chunks. Long-form
# `metric_value` arrives atomic, so an unrecognised metric there is scored
# correctly regardless of what this returns.
.crd_metric_direction <- function(metric) {
  if (!is.na(metric) && metric %in% names(.crd_metric_dirs)) {
    unname(.crd_metric_dirs[[metric]])
  } else {
    "min"
  }
}

#' Reduce a possibly-list retrieval column to an atomic vector
#'
#' `ragnar_retrieve()` defaults to `deoverlap = TRUE`: adjacent retrieved chunks
#' of one document are merged into a single row, and every column except
#' `origin`, `doc_id`, `start`, `end`, `context` and `text` becomes a list
#' holding one value per constituent chunk. So a cell is not a wrapper around a
#' scalar — it is a genuine per-chunk vector, and on a real corpus roughly a
#' quarter of rows carry more than one value.
#'
#' `as.numeric()` copes with a list of length-1 scalars and **errors** on a
#' multi-element one, which is why the failure looked intermittent and why a
#' `suppressWarnings()` around it could never have helped.
#'
#' `reduce` therefore has to follow the metric's own direction rather than take
#' whatever came first: the score that retrieved a merged passage is the best
#' one among its chunks. `NA` marks a chunk that this metric did not retrieve,
#' so it is dropped before reducing — taking the first element would score a row
#' on a constituent that never matched, and would report `cosine_distance` for a
#' row that does have a `bm25` score.
#'
#' No warning is emitted for a multi-element cell: it is ragnar's ordinary
#' output, and warning on it would fire on most searches.
#'
#' @param x a column from a `ragnar_retrieve*()` frame — list or atomic, or
#'   `NULL` when the column is absent.
#' @param type `character(1)` one of `"numeric"`, `"integer"`, `"character"`.
#'   Always supplied by the call site and never inferred from the data, so one
#'   character cell cannot promote a numeric column.
#' @param reduce `character(1)` how to collapse a multi-element cell:
#'   `"first"`, `"max"` or `"min"`.
#' @param n `integer(1)` or `NULL`. When given, an absent column is returned as
#'   `n` typed `NA`s instead of a zero-length vector. Retrieval frames do not
#'   carry a fixed column set — a query BM25 matches nothing on comes back with
#'   no `bm25` column at all — and a zero-length column is a tibble recycling
#'   error rather than the missing value it should be.
#' @return An atomic vector of `type`, of length `length(x)` (or `n`), with a
#'   typed `NA` wherever a cell was empty or entirely `NA`.
#' @noRd
.crd_flat <- function(x, type = c("numeric", "integer", "character"),
                      reduce = c("first", "max", "min"), n = NULL) {
  type <- match.arg(type)
  reduce <- match.arg(reduce)
  coerce <- switch(type,
                   numeric   = as.numeric,
                   integer   = as.integer,
                   character = as.character)
  na <- switch(type,
               numeric   = NA_real_,
               integer   = NA_integer_,
               character = NA_character_)

  if (is.null(x)) return(if (is.null(n)) coerce(NULL) else rep(na, n))
  # The common case: the bm25 path returns atomic columns and needs nothing.
  if (!is.list(x)) return(coerce(x))

  # Coerce ONCE over the whole column rather than once per cell. Not a
  # micro-optimisation: coercion is not suppressed here (see below), and
  # per-cell coercion would emit one "NAs introduced by coercion" warning per
  # row, where the atomic branch above emits exactly one for the vector. Making
  # the two branches differ in how loudly they report the same problem is how a
  # contract drifts.
  #
  # Warnings are deliberately NOT suppressed. The only one reachable is "NAs
  # introduced by coercion", meaning a score column holds non-numeric data —
  # and silencing it yields an all-NA `score`, precisely the silent failure
  # this function exists to end.
  cells <- lapply(x, function(cell) unlist(cell, use.names = FALSE))
  flat <- coerce(unlist(cells, use.names = FALSE))
  groups <- split(flat, rep(seq_along(cells), lengths(cells)))

  vals <- lapply(seq_along(cells), function(i) {
    v <- groups[[as.character(i)]]
    v <- v[!is.na(v)]
    # An empty cell, or one this metric never scored, is NA — not a dropped
    # row, which would shorten the column and misalign every other one, and not
    # `-Inf` from `max(numeric(0))`.
    if (length(v) == 0L) return(na)
    switch(reduce, first = v[[1L]], max = max(v), min = min(v))
  })
  coerce(unlist(vals, use.names = FALSE))
}

#' Extract a comparable score and its metric name from ragnar results
#'
#' Single-method retrieval returns long-form `metric_name`/`metric_value`
#' columns. Hybrid retrieval pivots those wider, yielding one column per metric
#' (`bm25`, `cosine_distance`) and no `metric_value` at all — so reading
#' `metric_value` unconditionally silently produces an all-`NA` score on the
#' default code path.
#'
#' The pivoted columns are **list** columns, one value per chunk merged into the
#' row, and are reduced by `.crd_flat()` in the direction that metric improves:
#' `bm25` higher is better, `cosine_distance` lower is better.
#'
#' Scores are only comparable within a metric, which is why the metric that
#' produced each score is returned alongside it rather than being discarded.
#'
#' @param res `data.frame` returned by a `ragnar_retrieve*()` function.
#' @return A `list` with numeric `score` and character `metric`, both of length
#'   `nrow(res)`.
#' @noRd
.crd_retrieval_score <- function(res) {
  n <- nrow(res)
  if ("metric_value" %in% names(res)) {
    metric <- if ("metric_name" %in% names(res)) {
      .crd_flat(res$metric_name, "character", "first")
    } else {
      rep(NA_character_, n)
    }
    # Reduce each metric in its own direction rather than assuming "max". The
    # long-form shape is what `method = "vss"` returns, and its metric is
    # `cosine_distance`, where *lower* is better — a fixed "max" would pick the
    # worst constituent, silently and with the right type. Unreachable today
    # (neither `ragnar_retrieve_bm25()` nor `_vss()` takes `deoverlap`, so
    # `metric_value` arrives atomic and `.crd_flat()` returns before consulting
    # `reduce`), which is exactly why it needs to be right now rather than when
    # it stops being dead.
    # Group by metric so each reduces in its own direction. Rows whose
    # `metric_name` is absent or NA are grouped under "" and still scored:
    # gating the loop on the metric resolving is how `metric_value` gets
    # discarded and an all-NA `score` comes back, which is the failure this
    # function exists to end rather than to reintroduce on another shape.
    score <- rep(NA_real_, n)
    for (idx in split(seq_len(n), ifelse(is.na(metric), "", metric))) {
      m <- metric[idx[[1L]]]
      score[idx] <- .crd_flat(res$metric_value[idx], "numeric",
                              .crd_metric_direction(m))
    }
    return(list(score = score, metric = metric))
  }

  # Enumerate the score columns actually present rather than only the ones in
  # the table, so a metric cred does not recognise is scored here exactly as the
  # long-form branch scores it. Membership by table alone is what let the two
  # branches answer differently for the same column.
  #
  # The type guard is the real safety net: it does not depend on
  # `.crd_non_metric_cols` being complete, so a new *character* column added
  # upstream cannot be mistaken for a score.
  cand <- setdiff(names(res), .crd_non_metric_cols)
  cand <- cand[vapply(cand, function(m) is.numeric(res[[m]]) || is.list(res[[m]]),
                      logical(1))]
  # Known metrics first, in table order, so a row scored by BM25 keeps that
  # score rather than being overwritten by a distance.
  cand <- c(intersect(names(.crd_metric_dirs), cand),
            setdiff(cand, names(.crd_metric_dirs)))

  score <- rep(NA_real_, n)
  metric <- rep(NA_character_, n)
  for (m in cand) {
    v <- .crd_flat(res[[m]], "numeric", .crd_metric_direction(m))
    take <- is.na(score) & !is.na(v)
    score[take] <- v[take]
    metric[take] <- m
  }
  list(score = score, metric = metric)
}

# Message fragments that identify a failure to reach the embedding service.
#
# Secondary to the class check in `.crd_retrieval_failure()`, not a substitute
# for it: httr2 chains the curl error's text into `conditionMessage()`, so these
# also match a wrapped condition, and they are the only route for an embedding
# provider that is not httr2-based.
.crd_conn_patterns <- paste(
  c("Failed to connect", "Could not connect", "Couldn't connect",
    "Connection refused", "Connection reset", "Connection timed out",
    "Could not resolve host", "Timeout was reached", "Operation timed out",
    "Empty reply from server"),
  collapse = "|"
)

# Message fragments that identify an embedding-width mismatch.
#
# This is the one failure with no distinguishing condition class — duckdb raises
# a plain error from its binder — so unlike the patterns above, the regex here
# is load-bearing.
#
# Both patterns describe a *size* disagreement, and neither names a function.
# `array_cosine_distance` on its own is NOT a pattern here, deliberately: duckdb
# also raises "No function matches the given name and argument types
# 'array_cosine_distance(FLOAT[2], INTEGER_LITERAL)'" when an embedder returns
# the wrong *type* or a zero-length vector, which is not a store problem at all.
# Matching the function name would prescribe "rebuild the store" off a substring
# — the same remedy-from-a-guess that #29 exists to remove. The size phrase is
# metric-agnostic in the same way (`array_distance` raises it verbatim), so
# dropping the name costs no coverage.
#
# Measured against ragnar 0.3.0 / duckdb; the premise tests in
# test-store-fallback.R pin the text so an upstream rewording fails there.
# Message fragments that identify a reply from the service, when the class that
# would have said so is gone.
#
# It can be gone: `ragnar::embed_ollama()` builds its request with
# `req_error(body = \(resp) resp_body_json(resp)$error)`, so an HTTP error whose
# body is **not JSON** — anything behind an nginx or an ALB that emits an HTML
# 502 — throws inside httr2's own error handler and arrives as a bare
# `rlang_error` with no status class left on it.
#
# Without this route such a failure lands in `unknown`, whose prescription is to
# re-download the store. That is a wrong and expensive remedy for a proxy
# hiccup, and it is the shape of defect this whole change exists to remove.
.crd_http_patterns <- "HTTP[[:space:]]+[0-9]{3}"

# The phrase Ollama's 404 body uses when a model genuinely is not installed.
#
# The STATUS says the request was refused; only the BODY says why. A 404 is also
# what a wrong path prefix returns ("404 page not found"), from a server that has
# every model you asked for — so claiming "the model is not installed" from the
# status alone asserts one boundary past the evidence.
.crd_model_absent_pattern <- 'model[[:space:]]+"[^"]+"'

.crd_dim_patterns <- paste(
  c("Array arguments must be of the same size",
    "Cannot cast array of size"),
  collapse = "|"
)

#' Classify a failure of semantic retrieval
#'
#' `crd_search(method = "hybrid")` falls back to BM25 when semantic retrieval
#' raises, and the ways it can fail need different things said about them.
#' Guessing costs more than it looks: an embedding-width mismatch means the
#' store's own recorded embedder no longer produces vectors of the width the
#' store holds, so the store is not answering the questions it appears to be —
#' reported as a connection problem that reads as nothing at all.
#'
#' Classification is by condition **class** wherever one exists, because httr2's
#' classes are stable in a way its message wording, curl's wording and the
#' user's locale are not. Only the dimension branch needs message matching.
#'
#' @param cond a condition caught from `ragnar::ragnar_retrieve()`.
#' @return `character(1)`, one of `"connection"`, `"model"`, `"service"`,
#'   `"dimension"`, `"unknown"`.
#' @noRd
.crd_retrieval_failure <- function(cond) {
  msg <- paste(conditionMessage(cond), collapse = "\n")

  # Class first. `httr2_failure` is a transport failure — the request never got
  # an answer — while `httr2_http` means the service answered and refused. They
  # are disjoint, and conflating them is how "start Ollama" ends up printed at
  # someone whose Ollama is running.
  if (inherits(cond, c("httr2_failure", "curl_error"))) return("connection")

  # Within "answered and refused", the status narrows it and the body settles
  # it. A 500, 503 or 401 has nothing to do with pulling a model; and a 404 is
  # returned both by a server missing the model and by one answering a wrong
  # path, so only the body's `model "..."` phrase establishes "not installed".
  # Classifying on the status alone would assert one boundary past the evidence
  # — the same half-step the old catch-all took.
  answered <- inherits(cond, "httr2_http") ||
    grepl(.crd_http_patterns, msg, ignore.case = TRUE)
  if (answered) {
    names_a_model <- grepl(.crd_model_absent_pattern, msg)
    if (inherits(cond, "httr2_http_404") && names_a_model) return("model")
    if (grepl("HTTP[[:space:]]+404", msg, ignore.case = TRUE) && names_a_model) {
      return("model")
    }
    return("service")
  }

  if (grepl(.crd_conn_patterns, msg, ignore.case = TRUE)) return("connection")
  if (grepl(.crd_dim_patterns, msg, ignore.case = TRUE)) return("dimension")

  # Deliberately not a guess. An unrecognised failure gets its cause reported
  # and no remedy prescribed.
  "unknown"
}

#' What a store records about its own embeddings
#'
#' Read from the store rather than from the environment, so a message can say
#' what this store actually is rather than what it ought to be.
#'
#' Every read is tolerant, and every result is length-checked by the caller:
#' this runs while a warning is being *built*, and an error raised here would
#' turn a recoverable fallback into a hard failure — strictly worse than the bug
#' being fixed. A `metadata` table without the column yields `NULL`, and
#' `as.integer(NULL)` is `integer(0)`, on which `if (is.na(x))` errors with
#' "argument is of length zero".
#'
#' @param store a connected ragnar store, or anything at all.
#' @return `list(size = , model = )`, each either a length-1 value or `NA`.
#' @noRd
.crd_store_meta_brief <- function(store) {
  out <- list(size = NA_integer_, model = NA_character_)
  if (is.null(store) || !requireNamespace("DBI", quietly = TRUE)) return(out)

  con <- tryCatch(store@con, error = function(e) NULL)
  if (is.null(con)) return(out)

  size <- tryCatch(
    as.integer(DBI::dbGetQuery(con, "SELECT embedding_size FROM metadata")$embedding_size[1]),
    error = function(e) NA_integer_
  )
  model <- tryCatch(.crd_store_model_from_meta(con), error = function(e) NA_character_)

  if (length(size) == 1L) out$size <- size
  if (length(model) == 1L) out$model <- model
  out
}

#' Is a value usable in a message?
#'
#' One place to ask "did that read give me something to print", so no branch of
#' the message builder has to remember that `is.na()` on a zero-length value
#' errors rather than returning `FALSE`.
#'
#' @param x any value.
#' @return `TRUE` when `x` is a single non-missing, non-empty value.
#' @noRd
.crd_have <- function(x) {
  length(x) == 1L && !is.na(x) && nzchar(as.character(x))
}

#' The model name to name in a remedy
#'
#' In order of how much it is actually known: the model the service itself said
#' it could not find, then the one the store records, then the package default.
#' Naming a model nothing ever asked for is how a user ends up pulling something
#' irrelevant.
#'
#' **Both** candidates are untrusted, and the first version of this guard said
#' otherwise. The name from the condition is remote text. The name the store
#' records is *also* remote text: [crd_store_connect()] downloads stores from a
#' shared bucket, so "it is local" describes where the file sits, not who wrote
#' it — and a store recording `with ' quote and; semicolon` emitted exactly that
#' into two suggested commands while the guard sat one branch away, unconsulted.
#'
#' Either way the name goes into a command the message invites the reader to
#' paste, so both go through [.crd_is_model_name()].
#'
#' @param cond the condition that was caught, or `NULL` where there is none —
#'   [.crd_check_store_embedding()]'s mismatch path has no caught condition,
#'   because the probe it is reporting on SUCCEEDED. The first tier simply has
#'   no evidence to offer then.
#' @param store the store being searched.
#' @param requested `character(1)` the model the caller explicitly asked for, or
#'   `NULL`. Sits above the hardcoded default and below both pieces of
#'   failure-specific evidence: [.crd_ollama_check()] knows which model it was
#'   told to probe, which beats guessing, and never beats the model the service
#'   itself named or the one the store records.
#' @return `character(1)`.
#' @noRd
.crd_fallback_model <- function(cond = NULL, store = NULL, requested = NULL) {
  if (!is.null(cond)) {
    msg <- paste(conditionMessage(cond), collapse = "\n")
    # Ollama's 404 body: model "nomic-embed-text" not found, try pulling it first
    hit <- regmatches(msg, regexpr('model[[:space:]]+"[^"]+"', msg))
    if (length(hit) == 1L) {
      named <- sub('^model[[:space:]]+"([^"]+)"$', "\\1", hit)
      if (.crd_have(named) && .crd_is_model_name(named)) return(named)
    }
  }
  recorded <- .crd_store_meta_brief(store)$model
  if (.crd_is_model_name(recorded)) return(recorded)
  # Validated like the other two even though it came from this session's own
  # call: the value lands in a line the message invites the reader to paste, and
  # that is a property of the line, not of how much the source is trusted.
  if (.crd_is_model_name(requested)) return(requested)
  "nomic-embed-text"
}

#' Does this look like a model name, and nothing else?
#'
#' Deliberately a whitelist. The point is not to predict what a hostile string
#' would do — the message is printed, never executed — but that a line offered
#' as "paste this" must read as the command it is. Anything carrying a quote,
#' a space or a shell metacharacter fails that regardless of intent.
#'
#' @param x `character(1)`.
#' @return `TRUE` when `x` is plausibly a model name.
#' @noRd
.crd_is_model_name <- function(x) {
  .crd_have(x) && grepl("^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$", x)
}

#' Indent the continuation lines of a caught condition's message
#'
#' httr2 and rlang chain a cause across several lines, and the later ones arrive
#' flush left. Dropped into a message whose own lines are indented, the remedy
#' then reads as part of the cause — which defeats the point of separating them.
#'
#' @param cause `character(1)`, possibly multi-line.
#' @return `character(1)` with every line after the first indented.
#' @noRd
.crd_indent_cause <- function(cause) {
  lines <- strsplit(paste(cause, collapse = "\n"), "\n", fixed = TRUE)[[1]]
  if (length(lines) <= 1L) return(paste(lines, collapse = "\n"))
  paste(c(lines[1], paste0("         ", lines[-1])), collapse = "\n")
}

#' What to say about one embedding failure, independent of who is asking
#'
#' The remedy for a dead port does not depend on whether the caller was
#' [crd_search()] falling back, [crd_store_build()] refusing to start, or
#' [crd_store_connect()] unable to probe. Before this was shared,
#' `.crd_ollama_check()` printed `ollama serve` **and** `ollama pull` for every
#' error while `crd_search()` separated them — two accounts of the same dead
#' port, which is the thing #29 set out to remove and #30 finished.
#'
#' Each caller supplies its own opening line and appends this. The reason-to-
#' remedy mapping lives here once, so the remedies stay visible next to the
#' others they must not be confused with.
#'
#' `store` is genuinely optional: `.crd_ollama_check()` has no store, and
#' [.crd_store_meta_brief()] returns all-`NA` for `NULL`, which the `dimension`
#' branch already handles by omitting the "this store holds" line. That branch
#' is not reachable from a bare `embed_ollama()` probe anyway — the patterns it
#' matches are duckdb binder errors raised while querying a store — so no
#' caller without a store can land there in practice.
#'
#' @param reason `character(1)` from [.crd_retrieval_failure()].
#' @param cond the condition that was caught.
#' @param store the store being searched, used only to report what it records.
#' @param model `character(1)` the model the caller asked for, or `NULL`. Only
#'   used to name a model in a remedy when neither the condition nor the store
#'   names one -- see [.crd_fallback_model()].
#' @param context `character(1)` which caller is asking. Only the two
#'   store-flavoured branches read it, and only to avoid prescribing something
#'   that cannot apply: the `unknown` remedy sends a searcher to
#'   [crd_store_connect()] to rule the file out, which is nonsense said to
#'   [crd_store_build()] -- the store does not exist yet -- and circular said
#'   from inside connect itself.
#'
#'   `store`-absence would be the obvious discriminator and is the wrong one:
#'   `store` is optional for every caller and the existing tests pass none while
#'   still expecting the searcher's text, so absence means "not supplied here",
#'   not "there is no store".
#' @return `character(1)` the remedy, with no trailing newline.
#' @noRd
.crd_embed_remedy <- function(reason, cond, store = NULL, model = NULL,
                              context = c("search", "build", "connect")) {
  context <- match.arg(context)
  if (identical(reason, "connection")) {
    return(paste0(
      "  The embedding service did not answer. If it is not running, start it; a\n",
      "  timeout can also mean it is up and loading a model, in which case retry.\n",
      "    ollama serve && ollama pull ",
      .crd_fallback_model(cond, store, requested = model)
    ))
  }

  if (identical(reason, "model")) {
    return(paste0(
      "  The embedding service answered and refused the request, so it is running,\n",
      "  and it named the model it does not have:\n",
      "    ollama pull ", .crd_fallback_model(cond, store, requested = model)
    ))
  }

  if (identical(reason, "service")) {
    # Reachable, refusing, and not a missing model. Nothing here identifies a
    # remedy, so none is offered — the status it returned is the diagnosis.
    #
    # "it returned" rather than "above" on purpose: this text is shared with
    # `.crd_ollama_check()` and with `crd_search(method = "vss")`, and the
    # latter reports the cause as an rlang `parent`, which renders BELOW the
    # message. A deictic reference to the layout is wrong in one of the three
    # channels whichever way it points.
    return(paste0(
      "  The embedding service answered with an error, so it is running and this is\n",
      "  not a connection problem. The status it returned is all cred knows; pulling\n",
      "  a model or restarting the server may be unrelated to it."
    ))
  }

  if (identical(reason, "dimension")) {
    # A size error reached from a bare embedder probe is not a store mismatch --
    # there is no store yet -- so saying so would assert more than is known. But
    # falling through to the fallthrough was worse: it opens "cred does not
    # recognise this failure", which is false for a reason the classifier did
    # recognise.
    if (identical(context, "build")) {
      return(paste0(
        "  The embedding service reported a vector-size error. There is no store to\n",
        "  compare against yet, so this is the embedder or the model rather than a\n",
        "  store mismatch. Check what width the model returns:\n",
        "    ncol(ragnar::embed_ollama('probe', model = '",
        .crd_fallback_model(cond, store, requested = model), "'))"
      ))
    }
    meta <- .crd_store_meta_brief(store)
    # The recorded model is echoed only if it looks like one. This line is prose
    # rather than a command, so the paste hazard is not the issue here -- but the
    # value is still text out of a store pulled from a shared bucket, and
    # "records model <arbitrary string>" is both ugly and less informative than
    # saying the recorded value is not a model name, which is itself the finding.
    model_part <- if (.crd_is_model_name(meta$model)) {
      meta$model
    } else if (.crd_have(meta$model)) {
      "a value that is not a model name"
    } else {
      "unknown"
    }
    records <- if (!.crd_have(meta$size) && !.crd_have(meta$model)) {
      ""
    } else {
      paste0("  This store holds ",
             if (.crd_have(meta$size)) paste0(meta$size, "-wide") else "unknown-width",
             " embeddings and records model ", model_part, ".\n")
    }
    return(paste0(
      # The mechanism, stated as narrowly as it can be established. A connected
      # store embeds queries with its OWN recorded embedder -- ragnar
      # unserialises it out of the store -- so this is not "you queried with a
      # different model". It is that the embedder no longer returns the width
      # the store holds: the model that name resolves to on this machine is not
      # the model the store was built with, or the embedder was replaced in
      # this session.
      "  The query embedding is a different width than this store's embeddings. A\n",
      "  connected store embeds queries with the embedder recorded inside it, so\n",
      "  the model that name resolves to on this machine is no longer the model the\n",
      "  store was built with - or that embedder was replaced in this session.\n",
      "  Treat this store as unverified: a search that did\n",
      "  succeed would answer differently while looking healthy. Not a service\n",
      "  problem, and not something restarting Ollama can fix.\n",
      records,
      # Still NOT crd_store_connect(), and #30 did not change that -- it is
      # worth saying why, since #30 added a connect-time check that CAN see a
      # width mismatch.
      #
      # Three reasons the text stays as it is. The md5 half remains structurally
      # unable to see a model change, so "re-verify the file" is still the wrong
      # advice. The one-liner below gathers exactly the evidence #30's probe
      # gathers, for one HTTP call instead of a reconnect. And reaching this
      # warning at all means connect either was not asked to check or already
      # passed -- in which case the mismatch arose after it, from the
      # in-session embedder swap named two lines up, which no reconnect can
      # see. A remedy that is more expensive and covers less is not an upgrade.
      "  Compare what the store records against what the service now returns, then\n",
      "  re-pull the model or rebuild with crd_store_build():\n",
      "    ncol(ragnar::embed_ollama('probe', model = '",
      .crd_fallback_model(cond, store, requested = model), "'))"
    ))
  }

  # The fallthrough, and the one branch whose remedy is about the STORE rather
  # than the service -- so it is the one that has to know who is asking.
  if (identical(context, "build")) {
    return(paste0(
      "  cred does not recognise this failure, so no remedy is prescribed. The store\n",
      "  cannot be built without embeddings, and nothing here says why this model\n",
      "  could not produce one."
    ))
  }
  if (identical(context, "connect")) {
    return(paste0(
      "  cred does not recognise this failure, so no remedy is prescribed. Semantic\n",
      "  retrieval will not work until it does; BM25 needs no embedding and is\n",
      "  unaffected."
    ))
  }
  paste0(
    "  cred does not recognise this failure, so no remedy is prescribed. Semantic\n",
    "  retrieval is unavailable and the store itself may be at fault - confirm it is\n",
    "  the file the manifest describes with crd_store_connect()."
  )
}

#' Compose the fallback warning for one failure reason
#'
#' Split from the warning call so the text can be tested without catching a
#' condition. The per-reason body is [.crd_embed_remedy()], shared with the two
#' other callers that have to say something about an embedding failure; only
#' the opening two lines are specific to a `crd_search()` fallback.
#'
#' Every branch reports the underlying condition verbatim. That was the one
#' thing the pre-#29 message got right, and it is the only thing that can
#' diagnose a failure cred does not recognise.
#'
#' @param reason `character(1)` from [.crd_retrieval_failure()].
#' @param cond the condition that was caught.
#' @param store the store being searched, used only to report what it records.
#' @return `character(1)` the warning message.
#' @noRd
.crd_retrieval_fallback_msg <- function(reason, cond, store = NULL) {
  paste0(
    "Semantic retrieval failed, so crd_search() fell back to BM25.\n",
    "  Cause: ", .crd_indent_cause(conditionMessage(cond)), "\n",
    .crd_embed_remedy(reason, cond, store = store)
  )
}

#' Raise a classified error for a retrieval that has nowhere to fall back to
#'
#' `method = "vss"` is semantic retrieval and nothing else, so a failure there
#' is terminal — unlike `"hybrid"`, which degrades to BM25 with a warning.
#' Erroring is right; raising the condition **unclassified** was not. A
#' width-mismatched store produced a bare
#' `Binder Error: array_cosine_distance(...)` and no diagnosis at all
#' (NewGraphEnvironment/cred#30).
#'
#' The original condition is attached as an rlang `parent`, which both keeps it
#' reachable programmatically as `cnd$parent` and folds its message into
#' `conditionMessage()` of the outer condition — measured on rlang, so
#' `tryCatch(error = conditionMessage)` sees the cause and the remedy together
#' without this function restating it.
#'
#' @param cond the condition caught from the retrieval call.
#' @param store the store being searched.
#' @return Never returns; raises a `cred_retrieval_error` condition.
#' @noRd
.crd_retrieval_abort <- function(cond, store = NULL) {
  reason <- .crd_retrieval_failure(cond)
  rlang::abort(
    paste0(
      'Semantic retrieval failed, and method = "vss" has no fallback.\n',
      .crd_embed_remedy(reason, cond, store = store), "\n",
      '  Both other methods still work on this store: "hybrid" would have\n',
      '  degraded to BM25 with a warning, and "bm25" needs no embedding at all.'
    ),
    # Subclassed by reason, in the same scheme as the fallback warning, so a
    # caller can branch on the two channels identically.
    class = c(paste0("cred_retrieval_error_", reason), "cred_retrieval_error"),
    parent = cond
  )
}

#' Frequency key for the fallback warning
#'
#' Keyed on reason **and** store. Keyed on the store alone, a dimension
#' mismatch met after a connection failure would be swallowed as a repeat —
#' the diagnosis loss of #29 arriving by another route. Keyed on the reason
#' alone, one unreachable store would silence a second one.
#'
#' The store half is its `location`, not its `name`. `ragnar_store_connect()`
#' falls back to `unique_store_name()` when the store records no name, and that
#' is a per-session counter (`store_001`), so two different stores can carry one
#' name while two copies of one store at different paths cannot share a path.
#'
#' @param reason `character(1)` from [.crd_retrieval_failure()].
#' @param store the store being searched, or `NULL`.
#' @return `character(1)` id for `rlang::warn(.frequency_id = )`.
#' @noRd
.crd_retrieval_fallback_id <- function(reason, store = NULL) {
  loc <- tryCatch(as.character(store@location), error = function(e) NA_character_)
  # `.crd_have()` rather than `nzchar()` directly: nzchar(NA) is TRUE, so the
  # obvious non-empty test waves an NA straight through.
  if (!.crd_have(loc)) loc <- "unknown-store"
  paste0("cred_retrieval_fallback_", reason, "_", loc)
}

#' Warn that semantic retrieval failed, once per session per reason and store
#'
#' @param cond the condition caught from `ragnar::ragnar_retrieve()`.
#' @param store the store being searched.
#' @return `invisible(reason)`.
#' @noRd
.crd_retrieval_fallback_warn <- function(cond, store = NULL) {
  reason <- .crd_retrieval_failure(cond)
  # The message is composed even on a call whose warning the frequency guard
  # will suppress, which costs two metadata reads on an already-open connection
  # for the dimension branch. `rlang:::needs_signal()` is not exported, so there
  # is no supported way to ask first; the reads are local and cheap enough that
  # restructuring for it would buy less than it complicates.
  rlang::warn(
    .crd_retrieval_fallback_msg(reason, cond, store = store),
    # Subclassed so a caller can act on the reason programmatically instead of
    # grepping the message, and so a test can assert which branch fired.
    class = c(paste0("cred_retrieval_fallback_", reason), "cred_retrieval_fallback"),
    # Without this the warning repeats on every call. Noise is how a warning
    # stops being read, and this is the same channel that has to carry the
    # store-mismatch case.
    .frequency = "once",
    .frequency_id = .crd_retrieval_fallback_id(reason, store)
  )
  invisible(reason)
}

#' Search a ragnar evidence store for passages supporting a claim
#'
#' Retrieves the passages most relevant to `query` and labels each with the
#' citation key of the paper it came from, so a result can be cited directly
#' rather than chased back through a file path.
#'
#' Unlike the token-overlap search in [crd_pdf_srch_clm()], which scores one
#' known source against one paraphrase, this searches an entire indexed corpus.
#'
#' `method = "hybrid"` combines semantic (vector) and lexical (BM25) retrieval
#' and needs a running Ollama instance to embed the query. When semantic
#' retrieval fails **for any reason** the search falls back to BM25 with a
#' warning rather than failing: lexical retrieval needs no embedding and remains
#' effective for the numeric and parameter-level claims this package exists to
#' check. The `method` column reports `"bm25"` when that happens, so a caller
#' can always tell the search degraded.
#'
#' @section Diagnosing a fallback:
#' The warning is subclassed by what went wrong, so a caller can act on the
#' reason rather than grep the message. All inherit `cred_retrieval_fallback`:
#'
#' \describe{
#'   \item{`cred_retrieval_fallback_connection`}{The embedding service could not
#'     be reached — start Ollama.}
#'   \item{`cred_retrieval_fallback_model`}{HTTP 404 **whose body names a
#'     model** — the service answered, so it *is* running, and it says it does
#'     not have that model. The body matters: a 404 is also what a wrong path
#'     prefix returns, from a server holding every model you asked for.}
#'   \item{`cred_retrieval_fallback_service`}{Any other reply from the service.
#'     It is running and erroring; the status is all cred knows, so no remedy is
#'     prescribed. Kept separate from the above precisely because pulling a model
#'     is unrelated to a 500 or a 503. This also catches an HTTP error that
#'     arrived with no status class on it, which happens when the error body is
#'     not JSON — `ragnar::embed_ollama()` parses it as JSON inside httr2's own
#'     error handler, so an HTML 502 from a reverse proxy loses the class.}
#'   \item{`cred_retrieval_fallback_dimension`}{The query embedding is a
#'     different width than the store's embeddings. A connected store embeds
#'     queries with the embedder recorded *inside it*, so this is not "you
#'     queried with a different model" — it is that the model that name resolves
#'     to on this machine is no longer the model the store was built with.
#'     **Treat the store as unverified**: a search that did succeed would answer
#'     differently while looking healthy. Compare what the store records against
#'     what the service now returns, then re-pull or rebuild with
#'     [crd_store_build()]. Restarting Ollama cannot help. Neither does
#'     reconnecting: [crd_store_connect()]'s MD5 compare cannot see a model
#'     change, and while its `check_model` probe can, reaching this warning
#'     means that probe either was not run or already passed — so the mismatch
#'     arose after the connect, and the one-line comparison the warning
#'     prescribes is both cheaper and the only one that sees it.}
#'   \item{`cred_retrieval_fallback_unknown`}{Unrecognised. The cause is
#'     reported verbatim and no remedy is prescribed.}
#' }
#'
#' Each fires once per session per reason and per store, so a machine without
#' Ollama does not emit the same four lines on every call.
#'
#' @param store a ragnar store, from [crd_store_connect()] or
#'   [ragnar::ragnar_store_connect()].
#' @param query `character(1)` search text.
#' @param top_k `integer(1)` passages to retrieve **per method**. Default `5L`.
#'   Under `method = "hybrid"` the vector and lexical result sets are unioned and
#'   then adjacent chunks are merged, so the number of rows returned is neither
#'   `top_k` nor `2 * top_k` — expect somewhere between the two.
#' @param method `character(1)` one of `"hybrid"`, `"bm25"`, `"vss"`.
#' @param zotero_dir `character(1)` Zotero data directory used to resolve
#'   citation keys. Default `"~/Zotero"`.
#' @return A [tibble][tibble::tibble] with one row per retrieved passage, with
#'   columns as below.
#'
#'   **Rows are returned in document order (`origin`, then position), not
#'   best-match first.** `ragnar_retrieve()` does not re-sort after merging
#'   overlapping chunks, and under `method = "hybrid"` neighbouring rows can
#'   carry different metrics, whose scores are not comparable — so there is no
#'   single ranking to return. To take the best passages, sort within one
#'   metric:
#'
#'   ```r
#'   res <- crd_search(store, "bankfull width regression")
#'   dplyr::arrange(dplyr::filter(res, metric == "bm25"), dplyr::desc(score))
#'   ```
#'   - `citation_key` (`character`) — BBT key, `NA` if unresolvable.
#'   - `origin` (`character`) — source path recorded in the store.
#'   - `chunk_id`, `start`, `end` (`integer`) — location within the document.
#'     A returned passage may be several adjacent chunks merged into one, in
#'     which case `chunk_id` is the first of them and `start`/`end` span them all.
#'   - `text` (`character`) — the retrieved passage, verbatim.
#'   - `score` (`numeric`) — retrieval metric value. Where a passage merges
#'     several chunks this is the best score among them: highest for `bm25`,
#'     lowest for `cosine_distance`.
#'   - `metric` (`character`) — which metric produced `score` (`"bm25"` or
#'     `"cosine_distance"`). Scores are comparable only within a metric.
#'   - `method` (`character`) — the method actually used, which differs from
#'     the request when a fallback occurred.
#' @export
#' @examples
#' \dontrun{
#' store <- crd_store_connect("vca_refs")
#' crd_search(store, "bankfull width regression drainage area precipitation")
#' }
crd_search <- function(store, query, top_k = 5L,
                       method = c("hybrid", "bm25", "vss"),
                       zotero_dir = "~/Zotero") {
  chk::chk_string(query)
  chk::chk_whole_number(top_k)
  chk::chk_string(zotero_dir)
  method <- match.arg(method)
  .crd_need("ragnar")

  used <- method
  res <- switch(
    method,
    # Not wrapped, deliberately: BM25 needs no embedding, so the failures this
    # change is about cannot reach it, and catching here would convert a search
    # that works on a broken-embedder store into an error.
    bm25 = ragnar::ragnar_retrieve_bm25(store, query, top_k = top_k),
    # Wrapped to classify, not to fall back — there is nothing to fall back to.
    vss = tryCatch(
      ragnar::ragnar_retrieve_vss(store, query, top_k = top_k),
      error = function(e) .crd_retrieval_abort(e, store = store)
    ),
    hybrid = tryCatch(
      ragnar::ragnar_retrieve(store, query, top_k = top_k),
      error = function(e) {
        # Every failure still falls back — erroring here would break searches
        # that work today, and the `method` column already tells a caller the
        # search degraded. What the warning *says* is what #29 changed.
        .crd_retrieval_fallback_warn(e, store = store)
        used <<- "bm25"
        ragnar::ragnar_retrieve_bm25(store, query, top_k = top_k)
      }
    )
  )

  if (is.null(res) || nrow(res) == 0L) {
    return(tibble::tibble(citation_key = character(), origin = character(),
                          chunk_id = integer(), start = integer(), end = integer(),
                          text = character(), score = numeric(),
                          metric = character(), method = character()))
  }

  # Every column is routed through .crd_flat() rather than coerced directly.
  # `chunk_id` is a list column under hybrid retrieval and throws exactly as the
  # score columns do. `origin` is not observed as a list, but flattening it is
  # not merely defensive: .crd_zot_key_from_path() calls dirname(), which errors
  # on a list rather than degrading to NA.
  origin <- .crd_flat(res$origin, "character", "first", n = nrow(res))
  scored <- .crd_retrieval_score(res)

  # `chunk_id` takes the first constituent, matching ragnar's own
  # `start = first(start)` when it merges chunks into one row.
  tibble::tibble(
    citation_key = .crd_zot_key_from_path(origin, zotero_dir = zotero_dir),
    origin       = origin,
    chunk_id     = .crd_flat(res$chunk_id, "integer", "first", n = nrow(res)),
    start        = .crd_flat(res$start, "integer", "first", n = nrow(res)),
    end          = .crd_flat(res$end, "integer", "max", n = nrow(res)),
    text         = .crd_flat(res$text, "character", "first", n = nrow(res)),
    score        = scored$score,
    metric       = scored$metric,
    method       = used
  )
}

#' Resolve a Zotero collection to PDF attachment paths
#'
#' @param collection `character(1)` collection name as shown in Zotero.
#' @param zotero_dir `character(1)` Zotero data directory.
#' @return A [tibble][tibble::tibble] with `citation_key`, `src_path`.
#' @noRd
.crd_zot_collection_pdfs <- function(collection, zotero_dir = "~/Zotero") {
  .crd_need("RSQLite")
  zotero_dir <- path.expand(zotero_dir)
  db_path <- file.path(zotero_dir, "zotero.sqlite")
  if (!file.exists(db_path)) stop("zotero.sqlite not found in: ", zotero_dir, call. = FALSE)

  con <- RSQLite::dbConnect(RSQLite::SQLite(),
                            paste0("file:", db_path, "?mode=ro&immutable=1"))
  on.exit(RSQLite::dbDisconnect(con), add = TRUE)

  raw <- RSQLite::dbGetQuery(con, "
    SELECT idv.value AS citation_key,
           att.key   AS attachment_key,
           ia.path   AS attachment_path
    FROM collections c
    JOIN collectionItems ci ON ci.collectionID  = c.collectionID
    JOIN items           i  ON i.itemID         = ci.itemID
    JOIN itemData        id ON id.itemID        = i.itemID
    JOIN itemDataValues idv ON id.valueID       = idv.valueID
    JOIN fields          f  ON id.fieldID       = f.fieldID
    JOIN itemAttachments ia ON ia.parentItemID  = i.itemID
    JOIN items          att ON att.itemID       = ia.itemID
    WHERE f.fieldName = 'citationKey'
    AND   c.collectionName = ?
    AND   ia.contentType   = 'application/pdf'
    ORDER BY idv.value
  ", params = list(collection))

  if (nrow(raw) == 0L) {
    stop("No PDF attachments found in Zotero collection '", collection, "'.\n",
         "  Check the collection name, or pass citation_keys instead.", call. = FALSE)
  }

  raw <- raw[!duplicated(raw$citation_key), ]
  storage_dir <- file.path(zotero_dir, "storage")
  raw$src_path <- vapply(seq_len(nrow(raw)), function(i) {
    p <- raw$attachment_path[i]
    if (is.na(p)) return(NA_character_)
    if (startsWith(p, "storage:")) {
      file.path(storage_dir, raw$attachment_key[i], sub("^storage:", "", p))
    } else {
      path.expand(p)
    }
  }, character(1L))

  tibble::tibble(citation_key = raw$citation_key, src_path = raw$src_path)
}

#' Check that Ollama can embed with the requested model
#'
#' Errors, rather than warning: [crd_store_build()] cannot produce a store
#' without embeddings, so there is nothing to degrade to.
#'
#' The remedy comes from [.crd_embed_remedy()], shared with [crd_search()]. It
#' used to be two fixed lines — `ollama serve` **and** `ollama pull` — printed
#' for every error, so a 500 from a running server was reported as something
#' starting it would fix, and the same dead port got two different accounts
#' depending on which function met it (NewGraphEnvironment/cred#30).
#'
#' The condition is kept, not just its message: `.crd_retrieval_failure()`
#' dispatches on condition **class**, and the previous version reduced the
#' error to `conditionMessage()` at the point of catching it, discarding the
#' only stable evidence there is.
#'
#' @param model `character(1)` embedding model name.
#' @param base_url `character(1)` embedding service, or `NULL` to take
#'   `ragnar::embed_ollama()`'s own default. A seam for the tests, which reach
#'   the connection branch through the real call against a refused port rather
#'   than by mocking it; duplicating ragnar's default literal here would be one
#'   more thing to drift.
#' @return `NULL`, invisibly. Errors with actionable guidance otherwise.
#' @noRd
.crd_ollama_check <- function(model, base_url = NULL) {
  args <- list("cred connectivity probe", model = model)
  if (!is.null(base_url)) args$base_url <- base_url

  cond <- tryCatch({
    do.call(ragnar::embed_ollama, args)
    NULL
  }, error = function(e) e)

  if (is.null(cond)) return(invisible(NULL))

  stop("Could not embed with Ollama model '", model, "'.\n",
       "  Cause: ", .crd_indent_cause(conditionMessage(cond)), "\n",
       .crd_embed_remedy(.crd_retrieval_failure(cond), cond, model = model,
                         context = "build"),
       call. = FALSE)
}

#' Build a ragnar evidence store from Zotero PDFs
#'
#' Ingests the PDFs attached to a Zotero collection — or to an explicit set of
#' citation keys — into a ragnar DuckDB store, chunked, embedded and indexed
#' for both semantic and BM25 retrieval.
#'
#' The embedding model is pinned explicitly on every build. This matters more
#' than it looks: [ragnar::embed_ollama()] defaults to `embeddinggemma`, so a
#' store built without pinning is silently incomparable with every other store
#' in the shared corpus while appearing entirely healthy.
#'
#' Building is expensive and machine-local. Sharing a built store is done out
#' of band; see [crd_store_connect()] for the retrieval side.
#'
#' @param store_path `character(1)` path for the `.duckdb` store to create.
#' @param collection `character(1)` Zotero collection name. Supply exactly one
#'   of `collection` or `citation_keys`.
#' @param citation_keys `character` vector of Better BibTeX citation keys.
#' @param model `character(1)` Ollama embedding model.
#'   Default `"nomic-embed-text"` — the model the shared stores are built with.
#' @param zotero_dir `character(1)` Zotero data directory. Default `"~/Zotero"`.
#' @param overwrite `logical(1)` replace an existing store. Default `FALSE`.
#' @return Invisibly, a [tibble][tibble::tibble] with one row per ingested
#'   source (`citation_key`, `src_path`). Prints document and chunk counts.
#' @export
#' @examples
#' \dontrun{
#' crd_store_build("data/rag/vca_refs.duckdb", collection = "vca")
#'
#' crd_store_build(
#'   "data/rag/adhoc.duckdb",
#'   citation_keys = c("hall_etal2007Predictingriver", "beechie_etal2005ClassificationHabitat")
#' )
#' }
crd_store_build <- function(store_path,
                            collection = NULL,
                            citation_keys = NULL,
                            model = "nomic-embed-text",
                            zotero_dir = "~/Zotero",
                            overwrite = FALSE) {
  chk::chk_string(store_path)
  chk::chk_string(model)
  chk::chk_flag(overwrite)

  # Cheap argument validation before the dependency check, so a caller who got
  # the arguments wrong is told that rather than being sent to install DuckDB.
  if (is.null(collection) == is.null(citation_keys)) {
    stop("Supply exactly one of `collection` or `citation_keys`.", call. = FALSE)
  }
  .crd_need(c("ragnar", "DBI", "duckdb"))
  if (file.exists(store_path) && !overwrite) {
    stop("Store already exists: ", store_path, "\n  Pass overwrite = TRUE to rebuild.",
         call. = FALSE)
  }

  src <- if (!is.null(collection)) {
    chk::chk_string(collection)
    .crd_zot_collection_pdfs(collection, zotero_dir = zotero_dir)
  } else {
    chk::chk_character(citation_keys)
    found <- crd_zot_src_lookup(citation_keys, zotero_dir = zotero_dir)
    found <- found[found$src_type == "pdf", c("citation_key", "src_path")]
    if (nrow(found) == 0L) stop("No PDF attachments resolved for the supplied keys.",
                                call. = FALSE)
    found
  }

  exists_flag <- file.exists(src$src_path)
  if (any(!exists_flag)) {
    warning("Skipping ", sum(!exists_flag), " missing file(s): ",
            paste(src$citation_key[!exists_flag], collapse = ", "), call. = FALSE)
    src <- src[exists_flag, ]
  }
  if (nrow(src) == 0L) stop("No source PDFs available to ingest.", call. = FALSE)

  .crd_ollama_check(model)

  dir.create(dirname(store_path), recursive = TRUE, showWarnings = FALSE)
  store <- ragnar::ragnar_store_create(
    location = store_path,
    embed = function(x) ragnar::embed_ollama(x, model = model),
    overwrite = overwrite
  )

  # Ingest is the long call that fails — an unreadable PDF, Ollama dying part
  # way through, an interrupt. A half-ingested store left on disk is worse than
  # none: the retry is refused as "already exists", and the short store answers
  # queries from a fraction of the corpus without saying so.
  complete <- FALSE
  on.exit({
    try(DBI::dbDisconnect(store@con, shutdown = TRUE), silent = TRUE)
    if (!complete) unlink(store_path)
  }, add = TRUE)

  message("Ingesting ", nrow(src), " PDF(s) into ", store_path)
  ragnar::ragnar_store_ingest(store, src$src_path, progress = TRUE)

  # The store is complete the moment ingest returns. Anything after this point
  # only produces a progress message, and must never be able to delete an
  # embedding run that can take hours.
  complete <- TRUE

  count_rows <- function(table) {
    tryCatch(DBI::dbGetQuery(store@con, paste0("SELECT COUNT(*) AS n FROM ", table))$n,
             error = function(e) NA_integer_)
  }
  n_docs <- count_rows("documents")
  n_chunks <- count_rows("chunks")

  message("Store built: ", store_path, " | docs: ", n_docs, " | chunks: ", n_chunks,
          " | model: ", model)
  invisible(src)
}

#' Split a store source URI into bucket and key prefix
#'
#' @param source `character(1)` `s3://bucket/prefix/` URI.
#' @return A `list` with `bucket` and `prefix` (prefix may be `""`).
#' @noRd
.crd_s3_parts <- function(source) {
  if (!grepl("^s3://", source)) {
    stop("Only s3:// sources are supported for this operation, got: ", source,
         call. = FALSE)
  }
  rest <- sub("^s3://", "", source)
  bucket <- sub("/.*$", "", rest)
  prefix <- sub("^[^/]*/?", "", rest)
  if (!nzchar(bucket)) {
    stop("Could not parse a bucket from the store source: ", source, call. = FALSE)
  }
  list(bucket = bucket, prefix = prefix)
}

#' Is the bucket reachable with the current credentials?
#'
#' Distinguishing "reachable but empty" from "cannot reach" is the whole point:
#' treating an unreachable bucket as an absent manifest is how a push seeds a
#' second, rival manifest.
#'
#' @param source `character(1)` store source URI.
#' @param profile `character(1)` AWS profile name.
#' @return `TRUE` when the bucket responds, `FALSE` otherwise.
#' @noRd
.crd_s3_head_bucket <- function(source, profile = Sys.getenv("AWS_PROFILE")) {
  parts <- .crd_s3_parts(source)
  res <- .crd_aws(c("s3api", "head-bucket", "--bucket", parts$bucket), profile = profile)
  identical(res$status, 0L)
}

#' Does an object exist, and what is its ETag?
#'
#' The ETag is captured so a later write can be made conditional on the object
#' not having changed in between.
#'
#' A failed probe and a confirmed absence are reported separately. Collapsing
#' them lets a throttle or a credential refresh masquerade as "no object here",
#' which is the direction that loses data.
#'
#' @param source `character(1)` store source URI.
#' @param key `character(1)` object name relative to the source prefix.
#' @param profile `character(1)` AWS profile name.
#' @return A `list` with `exists` (`logical`), `confirmed_absent` (`logical` —
#'   only `TRUE` for a genuine 404), `etag` (`character` or `NA`) and `out`.
#' @noRd
.crd_s3_head_object <- function(source, key, profile = Sys.getenv("AWS_PROFILE")) {
  parts <- .crd_s3_parts(source)
  res <- .crd_aws(
    c("s3api", "head-object",
      "--bucket", parts$bucket,
      "--key", paste0(parts$prefix, key),
      "--query", "ETag", "--output", "text"),
    profile = profile, clean_stdout = TRUE
  )
  if (identical(res$status, 0L)) {
    # Match the ETag by shape rather than collapsing the stream, so a stray
    # line can never be welded onto the value.
    etag <- grep('^"[^"]*"$', trimws(res$out), value = TRUE)
    if (length(etag) != 1L) {
      return(list(exists = TRUE, confirmed_absent = FALSE, etag = NA_character_,
                  out = c(res$out, res$err)))
    }
    return(list(exists = TRUE, confirmed_absent = FALSE, etag = etag[1],
                out = c(res$out, res$err)))
  }
  # Anchored on the tokens the CLI emits — a bare "404" matches any request id.
  # Note 403 is deliberately NOT an absence: HeadObject returns 403 rather than
  # 404 for a missing key when the caller lacks s3:ListBucket, so treating it as
  # "no object here" would let a permissions problem read as a first push.
  txt <- c(res$out, res$err)
  absent <- any(grepl("\\(404\\)|NoSuchKey|error occurred \\(404", txt, ignore.case = TRUE)) ||
    any(grepl("Not Found", txt, fixed = TRUE))
  list(exists = FALSE, confirmed_absent = absent, etag = NA_character_,
       out = c(res$out, res$err))
}

#' Upload a file, optionally only if the remote copy is unchanged
#'
#' @param path `character(1)` local file to upload.
#' @param source `character(1)` store source URI.
#' @param key `character(1)` object name relative to the source prefix.
#' @param profile `character(1)` AWS profile name.
#' @param if_match `character(1)` ETag the remote object must still have, or
#'   `NULL`.
#' @param if_none_match `character(1)` pass `"*"` to write only when no object
#'   exists, or `NULL`.
#' @return A `list` with `status` and `out`. A precondition failure means the
#'   remote object changed under us.
#' @noRd
.crd_s3_put <- function(path, source, key, profile = Sys.getenv("AWS_PROFILE"),
                        if_match = NULL, if_none_match = NULL) {
  parts <- .crd_s3_parts(source)
  args <- c("s3api", "put-object",
            "--bucket", parts$bucket,
            "--key", paste0(parts$prefix, key),
            "--body", path)
  if (!is.null(if_match)) {
    # Silently dropping an unusable precondition turns a conditional write into
    # an unconditional one — the exact failure this helper exists to prevent.
    if (is.na(if_match) || !nzchar(if_match)) {
      stop("A precondition was requested but the ETag is missing.\n",
           "  Refusing to fall back to an unconditional write.", call. = FALSE)
    }
    args <- c(args, "--if-match", if_match)
  }
  if (!is.null(if_none_match) && nzchar(if_none_match)) {
    args <- c(args, "--if-none-match", if_none_match)
  }
  .crd_aws(args, profile = profile)
}

#' Upload a large object with `aws s3 cp`
#'
#' `s3api put-object` is a single PUT with a hard 5 GB limit and no multipart or
#' resume; `s3 cp` multiparts. Conditional writes are only needed for the
#' manifest, so the store binary has nothing to gain from `s3api` and a size
#' ceiling to lose.
#'
#' @param path `character(1)` local file.
#' @param source `character(1)` store source URI.
#' @param key `character(1)` object name relative to the source prefix.
#' @param profile `character(1)` AWS profile name.
#' @return A `list` with `status` and `out`.
#' @noRd
.crd_s3_cp_up <- function(path, source, key, profile = Sys.getenv("AWS_PROFILE")) {
  .crd_aws(c("s3", "cp", path, paste0(source, key)), profile = profile)
}

#' Did a conditional write fail in a way worth retrying?
#'
#' Covers both a precondition failure (the object changed under us) and S3's
#' `ConditionalRequestConflict`, which it returns for a conditional write
#' racing another in-flight one and documents as retryable. Not matching the
#' latter would hard-fail after the binary had already uploaded.
#'
#' @param res `list` as returned by `.crd_s3_put()`.
#' @return `TRUE` when the write should be re-merged and retried.
#' @noRd
.crd_s3_precondition_failed <- function(res) {
  # Anchored on what the CLI actually emits. A bare "412" substring matches any
  # request id, byte count or key containing those digits, which would push an
  # unrelated fatal error into the retry loop.
  !identical(res$status, 0L) &&
    any(grepl(paste0("\\(PreconditionFailed\\)|\\(412\\)|error occurred \\(412",
                     "|\\(ConditionalRequestConflict\\)|\\(409\\)"),
              c(res$out, res$err), ignore.case = TRUE))
}

#' Read git provenance for the repository containing a path
#'
#' Provenance must describe where the *store* was built, not where R happens to
#' be running. Reading the current working directory would stamp a store built
#' in one repo with the SHA of whichever repo the push was issued from — a
#' plausible-looking value that points at unrelated code.
#'
#' @param dir `character(1)` directory to read provenance for. Default `"."`.
#' @return A `list` with `repo`, `branch`, `head_sha`; elements are `NA` when
#'   the directory is not a git repository.
#' @noRd
.crd_git_provenance <- function(dir = ".") {
  run <- function(args) {
    out <- suppressWarnings(
      system2("git", c("-C", shQuote(dir), args), stdout = TRUE, stderr = FALSE)
    )
    if (!is.null(attr(out, "status")) || length(out) == 0L) NA_character_ else out[1]
  }
  url <- run(c("remote", "get-url", "origin"))
  repo <- if (is.na(url)) {
    NA_character_
  } else {
    # git@github.com:Owner/name.git and https://github.com/Owner/name.git
    sub("[.]git$", "", sub("^.*[:/]([^/]+/[^/]+?)$", "\\1", url))
  }
  list(
    repo     = repo,
    branch   = run(c("rev-parse", "--abbrev-ref", "HEAD")),
    head_sha = run(c("rev-parse", "HEAD"))
  )
}

#' Recover the embedding model from a store's own metadata
#'
#' ragnar serialises the embedding closure into `metadata.embed_func`, which
#' deparses to e.g. `function(x) ragnar::embed_ollama(x = x, model =
#' "nomic-embed-text")`. That is the artifact's own record of how it was built —
#' unlike an environment variable, which describes the machine doing the
#' pushing. The distinction is the difference between a guard and a decoration:
#' nothing in this package ever sets `CRED_EMBED_MODEL`, so a guard reading it
#' compares a default against itself.
#'
#' @param con open DBI connection to the store.
#' @return `character(1)` model name, or `NA_character_` when unreadable.
#' @noRd
.crd_store_model_from_meta <- function(con) {
  raw <- tryCatch(DBI::dbGetQuery(con, "SELECT embed_func FROM metadata")$embed_func,
                  error = function(e) NULL)
  if (is.null(raw) || length(raw) == 0L) return(NA_character_)

  fn <- tryCatch(unserialize(raw[[1]]), error = function(e) NULL)
  if (is.null(fn)) return(NA_character_)

  txt <- paste(deparse(fn), collapse = " ")
  hit <- regmatches(txt, regexpr('model[[:space:]]*=[[:space:]]*"[^"]+"', txt))
  if (length(hit) == 0L) return(NA_character_)
  sub('^model[[:space:]]*=[[:space:]]*"([^"]+)"$', "\\1", hit[1])
}

#' Describe a local store for the manifest
#'
#' Counts come from `documents` and `chunks` — store v2 carries both, and they
#' answer different questions (papers vs passages).
#'
#' @param store_path `character(1)` path to a `.duckdb` store.
#' @param built_by `character` script or function that produced the store.
#' @return A named `list` shaped like a manifest entry.
#' @noRd
.crd_store_describe <- function(store_path, built_by = "cred::crd_store_push()") {
  .crd_need(c("DBI", "duckdb"))
  chk::chk_file(store_path)

  con <- DBI::dbConnect(duckdb::duckdb(), store_path, read_only = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  count_rows <- function(table) {
    tryCatch(
      as.integer(DBI::dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", table))$n),
      error = function(e) NA_integer_
    )
  }
  # Read separately from the cosmetic label: bundling them means any schema
  # drift returns NULL and silently disables the dimension guard.
  size <- tryCatch(as.integer(DBI::dbGetQuery(con, "SELECT embedding_size FROM metadata")$embedding_size[1]),
                   error = function(e) NA_integer_)
  if (is.na(size)) {
    warning("Could not read embedding_size from ", basename(store_path),
            " — the embedding-dimension check will be skipped for this push.",
            call. = FALSE)
  }
  label <- tryCatch(as.character(DBI::dbGetQuery(con, "SELECT name FROM metadata")$name[1]),
                    error = function(e) NA_character_)

  # Prefer the store's own record over the environment; fall back loudly.
  model <- .crd_store_model_from_meta(con)
  if (is.na(model)) {
    model <- Sys.getenv("CRED_EMBED_MODEL", "nomic-embed-text")
    warning("Could not read the embedding model from ", basename(store_path),
            " — recording '", model, "' from the environment instead. ",
            "The model recorded in the manifest may not be the one used.",
            call. = FALSE)
  }

  git <- .crd_git_provenance(dirname(store_path))

  list(
    documents       = count_rows("documents"),
    chunks          = count_rows("chunks"),
    embedding_size  = size,
    embedding_model = model,
    store_name      = label,
    bytes           = unname(file.size(store_path)),
    md5             = tolower(unname(tools::md5sum(store_path))),
    repo            = git$repo,
    branch          = git$branch,
    head_sha        = git$head_sha,
    built_by        = built_by,
    date_completed  = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  )
}

#' Merge one store entry into an existing manifest
#'
#' The manifest describes **every** store in the bucket, so a push that
#' rebuilds it from the current run alone orphans the stores it did not push —
#' the pull side then reports "not in log.json" for a file plainly sitting in
#' the bucket. This function is the guarantee against that: it is pure, and
#' every entry other than `name` comes through untouched, including entries
#' whose shape this version of cred does not recognise.
#'
#' @param existing `list` parsed manifest, or `NULL` for a fresh one.
#' @param name `character(1)` store name to add or replace.
#' @param entry `list` manifest entry for `name`.
#' @return The merged manifest as a `list`.
#' @noRd
.crd_manifest_merge <- function(existing, name, entry) {
  chk::chk_string(name)
  if (is.null(existing)) existing <- list()
  if (is.null(existing$stores)) existing$stores <- list()

  merged <- existing
  merged$stores[[name]] <- entry
  merged$date_updated <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  merged$manifest_note <-
    "Provenance is per store. Push must merge into this file, never replace it."
  merged$generating_script <- "cred::crd_store_push()"
  merged
}

#' Warn when a store's embedding model differs from the rest of the corpus
#'
#' @param manifest `list` existing manifest.
#' @param name `character(1)` store being pushed.
#' @param model `character(1)` this store's embedding model.
#' @param allow `logical(1)` proceed despite a mismatch.
#' @return `NULL`, invisibly.
#' @noRd
#' Normalise an embedding-model label for comparison
#'
#' Existing manifest entries record the provider inline
#' (`"nomic-embed-text (ollama)"`) while the model read out of a store's own
#' `embed_func` is bare (`"nomic-embed-text"`). Comparing the raw strings would
#' flag every push against the existing corpus as a mismatch — a guard that
#' cries wolf gets `allow_model_mismatch = TRUE` pasted into a script, which
#' disables it for the case that matters.
#'
#' @param x `character` model labels.
#' @return `character` normalised labels.
#' @noRd
.crd_model_norm <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- sub("[[:space:]]*\\([^)]*\\)[[:space:]]*$", "", x)  # drop " (ollama)"
  trimws(x)
}

.crd_check_model <- function(manifest, name, model, allow, size = NA_integer_) {
  others <- manifest$stores[names(manifest$stores) != name]
  field <- function(key, cast) {
    v <- vapply(others, function(e) {
      if (is.null(e[[key]])) cast(NA) else cast(e[[key]][1])
    }, cast(NA))
    unique(v[!is.na(v)])
  }
  models <- field("embedding_model", as.character)
  sizes <- field("embedding_size", as.integer)

  # embedding_size is read out of the store's own metadata table, so it is a
  # property of the artifact. The model string comes from the pusher's
  # environment and is only a label — checking it alone would let the exact
  # case this guard exists for pass, while recording the wrong model.
  size_conflict <- !is.na(size) && length(sizes) > 0L && !(size %in% sizes)
  model_conflict <- length(models) > 0L &&
    !(.crd_model_norm(model) %in% .crd_model_norm(models))
  if (!size_conflict && !model_conflict) return(invisible(NULL))

  msg <- paste0(
    "Embedding mismatch for '", name, "'.\n",
    "  this store: ", model, " (dimension ", if (is.na(size)) "unknown" else size, ")\n",
    "  already in the manifest: ", paste(models, collapse = ", "),
    " (dimension ", paste(sizes, collapse = ", "), ")\n",
    if (size_conflict) {
      "  The embedding DIMENSION differs, which is read from the store itself — this is a real
  incompatibility, not just a label mismatch.\n"
    } else {
      ""
    },
    "  Results are not comparable across stores embedded with different models."
  )
  if (!allow) {
    stop(msg, "\n  Pass allow_model_mismatch = TRUE if this is a deliberate migration.",
         call. = FALSE)
  }
  warning(msg, call. = FALSE)
  invisible(NULL)
}

#' Push a ragnar evidence store and merge it into the shared manifest
#'
#' Uploads a built store and records it in the bucket's single `log.json`
#' manifest, **merging** rather than replacing. The manifest describes every
#' store in the bucket, so a push built from the current run alone silently
#' orphans the others — the pull side then reports "not in log.json" for a file
#' plainly present. That failure has been observed in practice.
#'
#' Three deliberate refusals, each guarding a way the manifest can be corrupted:
#'
#' * **An unreadable manifest aborts the push.** Only a *confirmed* absence —
#'   bucket reachable, object missing — is treated as "no manifest yet", and
#'   even then `create_manifest = TRUE` is required. A wrong prefix in
#'   `cred.store_source` produces exactly the same 404 as a genuine first push.
#' * **A concurrent push cannot clobber this one.** The manifest is written
#'   conditional on the ETag read at the start; a competing write fails the
#'   precondition, and the merge is retried against the newer manifest.
#' * **A store with an unflushed WAL is refused**, since its md5 does not
#'   describe what a puller would open.
#'
#' The store binary is uploaded before the manifest that describes it, so a
#' failed manifest write leaves the new binary in place under the old md5 and
#' pulls of that store fail until the push is re-run. Both failure messages say
#' so. Removing the window entirely means content-addressed keys
#' (`<name>-<md5>.duckdb`), which is a change to the shared bucket layout and
#' belongs with the infrastructure rather than here.
#'
#' Building the store is [crd_store_build()]; reading it back is
#' [crd_store_connect()]. Bucket policy, IAM and retention are infrastructure
#' concerns and deliberately live outside this package.
#'
#' @param store_path `character(1)` path to the `.duckdb` store to upload.
#' @param source `character(1)` destination URI holding the stores and
#'   `log.json`. Defaults to `getOption("cred.store_source")`, then
#'   `CRED_STORE_SOURCE`. Shape `s3://<bucket>/<prefix>/`.
#' @param name `character(1)` store name in the manifest. Defaults to the file
#'   name without its extension.
#' @param profile `character(1)` AWS profile. Default `AWS_PROFILE`.
#' @param built_by `character` what produced the store, recorded in the entry.
#' @param dry_run `logical(1)` print the merged manifest and upload nothing.
#'   Default `FALSE`.
#' @param create_manifest `logical(1)` allow writing a manifest where none
#'   exists. Default `FALSE`. The create path is still conditional
#'   (`--if-none-match "*"`), so two simultaneous first pushes cannot silently
#'   overwrite one another.
#' @param allow_model_mismatch `logical(1)` push despite a differing embedding
#'   model. Default `FALSE`.
#' @param max_retries `integer(1)` conditional-write retries before giving up.
#'   Default `3L`.
#' @return Invisibly, the merged manifest as a `list`.
#' @export
#' @examples
#' \dontrun{
#' options(cred.store_source = "s3://<bucket>/<prefix>/")
#'
#' # Always dry-run first — prints the merged manifest, uploads nothing.
#' crd_store_push("data/rag/vca_refs.duckdb", dry_run = TRUE)
#'
#' crd_store_push("data/rag/vca_refs.duckdb")
#' }
crd_store_push <- function(store_path,
                           source = getOption("cred.store_source"),
                           name = NULL,
                           profile = Sys.getenv("AWS_PROFILE"),
                           built_by = "cred::crd_store_push()",
                           dry_run = FALSE,
                           create_manifest = FALSE,
                           allow_model_mismatch = FALSE,
                           max_retries = 3L) {
  chk::chk_string(store_path)
  chk::chk_flag(dry_run)
  chk::chk_flag(create_manifest)
  chk::chk_flag(allow_model_mismatch)
  chk::chk_whole_number(max_retries)
  chk::chk_file(store_path)

  store_path <- path.expand(store_path)
  if (is.null(name)) name <- sub("[.]duckdb$", "", basename(store_path))
  chk::chk_string(name)

  # An unflushed WAL means the file's md5 does not describe what a puller opens.
  wal <- paste0(store_path, ".wal")
  if (file.exists(wal)) {
    stop("Refusing to push '", name, "': a write-ahead log is present at\n  ", wal,
         "\n  Open and cleanly disconnect the store first so the WAL is flushed.",
         call. = FALSE)
  }

  .crd_need(c("DBI", "duckdb"))
  source <- .crd_store_source(source)

  # Unreachable must never be mistaken for empty.
  if (!.crd_s3_head_bucket(source, profile = profile)) {
    stop("Cannot reach the bucket behind ", source, "\n",
         "  Check credentials, profile (", if (nzchar(profile)) profile else "<none>",
         ") and network. Refusing to push rather than risk writing a rival manifest.",
         call. = FALSE)
  }

  head <- .crd_s3_head_object(source, "log.json", profile = profile)
  if (!head$exists && !head$confirmed_absent) {
    stop("Could not determine whether a manifest exists at ", source, "log.json\n  ",
         paste(head$out, collapse = "\n  "),
         "\n  This is not a 404 — refusing to push rather than guess.", call. = FALSE)
  }
  if (head$exists && is.na(head$etag)) {
    stop("Read the manifest at ", source, "log.json but could not obtain its ETag.\n",
         "  Refusing to push: without it a concurrent write cannot be detected.",
         call. = FALSE)
  }
  if (!head$exists && !create_manifest) {
    stop("No manifest at ", source, "log.json\n",
         "  The bucket is reachable, so this prefix has no manifest yet.\n",
         "  If that is intended, pass create_manifest = TRUE.\n",
         "  If not, check getOption(\"cred.store_source\") — a wrong prefix looks",
         " exactly like this.", call. = FALSE)
  }

  existing <- if (head$exists) .crd_manifest_read(source, profile = profile) else NULL
  entry <- .crd_store_describe(store_path, built_by = built_by)
  if (!is.null(existing)) {
    .crd_check_model(existing, name, entry$embedding_model, allow_model_mismatch,
                     size = entry$embedding_size)
  }
  merged <- .crd_manifest_merge(existing, name, entry)

  if (dry_run) {
    message("[dry run] would upload ", store_path, " -> ", source, name, ".duckdb")
    message("[dry run] merged manifest would hold: ",
            paste(names(merged$stores), collapse = ", "))
    cat(jsonlite::toJSON(merged, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null"), "\n")
    return(invisible(merged))
  }

  message("Uploading ", name, ".duckdb (", round(entry$bytes / 1048576), " MB)")
  up <- .crd_s3_cp_up(store_path, source, paste0(name, ".duckdb"), profile = profile)
  if (!identical(up$status, 0L)) {
    stop("Store upload failed for '", name, "'.\n  ", paste(up$out, collapse = "\n  "),
         call. = FALSE)
  }

  # Every write is conditional. When the manifest existed on entry the write is
  # gated on its ETag; when it did not, `--if-none-match *` means a concurrent
  # first push loses the race rather than silently replacing the winner.
  stale_warning <- paste0(
    "\n  The store binary uploaded, but the manifest still describes the previous one,",
    "\n  so crd_store_connect(\"", name, "\") will fail on md5 for everyone until this",
    "\n  push is re-run. Re-run it."
  )
  etag <- head$etag
  existed <- head$exists

  for (attempt in seq_len(max(1L, max_retries))) {
    tmp <- file.path(tempdir(), paste0("cred-log-out-", Sys.getpid(), ".json"))
    # na = "null" matters: jsonlite renders NA_integer_ as the STRING "NA",
    # which would land a wrong-typed value in the shared manifest for good.
    jsonlite::write_json(merged, tmp, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
    res <- .crd_s3_put(tmp, source, "log.json", profile = profile,
                       if_match = if (existed) etag else NULL,
                       if_none_match = if (!existed) "*" else NULL)
    unlink(tmp)

    if (identical(res$status, 0L)) {
      message("Manifest updated — now holds: ",
              paste(names(merged$stores), collapse = ", "))
      return(invisible(merged))
    }
    if (!.crd_s3_precondition_failed(res)) {
      stop("Manifest write failed for '", name, "'.\n  ",
           paste(c(res$out, res$err), collapse = "\n  "), stale_warning, call. = FALSE)
    }

    message("Manifest changed under us — re-merging (attempt ", attempt, ")")
    head <- .crd_s3_head_object(source, "log.json", profile = profile)

    # A re-probe that is not a clean read must abort. Treating it as absence
    # would drop the precondition and clobber the very manifest the retry
    # exists to protect.
    if (!head$exists || is.na(head$etag)) {
      stop("Lost track of the manifest at ", source, "log.json while retrying.\n  ",
           paste(head$out, collapse = "\n  "),
           "\n  Refusing to write without a precondition.", stale_warning,
           call. = FALSE)
    }
    etag <- head$etag
    existed <- TRUE
    merged <- .crd_manifest_merge(
      .crd_manifest_read(source, profile = profile), name, entry
    )
  }

  stop("Gave up after ", max_retries, " conditional-write attempts on ", source,
       "log.json\n  Another process is pushing concurrently.", stale_warning,
       call. = FALSE)
}
