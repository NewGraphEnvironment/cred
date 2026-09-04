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

#' Connect to a ragnar evidence store, pulling and verifying it if needed
#'
#' Resolves a store by name, using the local copy when its MD5 matches the
#' shared manifest and downloading it from `source` otherwise. Verification is
#' the point: a store built against a different embedding model answers
#' differently while looking perfectly healthy, so a silent local rebuild
#' produces an artefact that is present but not trustworthy.
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
#'   the only supported way to work fully offline.
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
                              verify = TRUE) {
  chk::chk_string(store)
  chk::chk_string(dir)
  chk::chk_flag(read_only)
  chk::chk_flag(verify)
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
    return(ragnar::ragnar_store_connect(local_path, read_only = read_only))
  }

  source <- .crd_store_source(source)
  entry <- .crd_manifest_entry(.crd_manifest_read(source, profile = profile), name)

  if (file.exists(local_path) &&
        identical(tolower(unname(tools::md5sum(local_path))), entry$md5)) {
    message("Using local ", local_path, " (md5 matches manifest; ",
            entry$documents, " docs, ", entry$chunks, " chunks).")
    return(ragnar::ragnar_store_connect(local_path, read_only = read_only))
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
  ragnar::ragnar_store_connect(local_path, read_only = read_only)
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
#' and needs a running Ollama instance to embed the query. When Ollama is
#' unreachable the search **falls back to BM25 with a warning** rather than
#' failing: lexical retrieval needs no embedding and remains effective for the
#' numeric and parameter-level claims this package exists to check.
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
    bm25 = ragnar::ragnar_retrieve_bm25(store, query, top_k = top_k),
    vss  = ragnar::ragnar_retrieve_vss(store, query, top_k = top_k),
    hybrid = tryCatch(
      ragnar::ragnar_retrieve(store, query, top_k = top_k),
      error = function(e) {
        warning("Semantic retrieval failed (", conditionMessage(e), ").\n",
                "  Falling back to BM25. Start Ollama for hybrid search:\n",
                "    ollama serve && ollama pull nomic-embed-text",
                call. = FALSE)
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
#' @param model `character(1)` embedding model name.
#' @return `NULL`, invisibly. Errors with actionable guidance otherwise.
#' @noRd
.crd_ollama_check <- function(model) {
  ok <- tryCatch({
    ragnar::embed_ollama("cred connectivity probe", model = model)
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(ok)) {
    stop("Could not embed with Ollama model '", model, "'.\n  ", ok, "\n",
         "  Start the server and pull the model:\n",
         "    ollama serve\n",
         "    ollama pull ", model, call. = FALSE)
  }
  invisible(NULL)
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
