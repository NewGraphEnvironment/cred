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
#' @param args `character` vector of arguments passed to `aws`.
#' @param profile `character(1)` AWS profile name, or `""` to omit.
#' @return `character` vector of the combined stdout and stderr lines.
#' @noRd
.crd_aws <- function(args, profile = Sys.getenv("AWS_PROFILE")) {
  if (!nzchar(Sys.which("aws"))) {
    stop("The AWS CLI ('aws') was not found on PATH.\n",
         "  Install it, or supply an already-downloaded store and use verify = FALSE.",
         call. = FALSE)
  }
  if (nzchar(profile)) args <- c(args, "--profile", profile)
  args <- vapply(args, shQuote, character(1L), USE.NAMES = FALSE)
  suppressWarnings(system2("aws", args, stdout = TRUE, stderr = TRUE))
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

  out <- .crd_aws(c("s3", "cp", paste0(source, "log.json"), dest), profile = profile)
  if (!file.exists(dest)) {
    stop("Could not fetch the store manifest from ", source, "log.json\n  ",
         paste(out, collapse = "\n  "), call. = FALSE)
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

  out <- .crd_aws(c("s3", "cp", paste0(source, name, ".duckdb"), part), profile = profile)
  if (!file.exists(part)) {
    stop("Download failed for store '", name, "'.\n  ", paste(out, collapse = "\n  "),
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

#' Extract a comparable score and its metric name from ragnar results
#'
#' Single-method retrieval returns long-form `metric_name`/`metric_value`
#' columns. Hybrid retrieval pivots those wider, yielding one column per metric
#' (`bm25`, `cosine_distance`) and no `metric_value` at all — so reading
#' `metric_value` unconditionally silently produces an all-`NA` score on the
#' default code path.
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
    return(list(
      score  = as.numeric(res$metric_value),
      metric = if ("metric_name" %in% names(res)) {
        as.character(res$metric_name)
      } else {
        rep(NA_character_, n)
      }
    ))
  }

  cand <- intersect(c("bm25", "cosine_distance"), names(res))
  score <- rep(NA_real_, n)
  metric <- rep(NA_character_, n)
  for (m in cand) {
    v <- suppressWarnings(as.numeric(res[[m]]))
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
#' @param top_k `integer(1)` number of passages to return. Default `5L`.
#' @param method `character(1)` one of `"hybrid"`, `"bm25"`, `"vss"`.
#' @param zotero_dir `character(1)` Zotero data directory used to resolve
#'   citation keys. Default `"~/Zotero"`.
#' @return A [tibble][tibble::tibble] ordered best-match first, with columns:
#'   - `citation_key` (`character`) — BBT key, `NA` if unresolvable.
#'   - `origin` (`character`) — source path recorded in the store.
#'   - `chunk_id`, `start`, `end` (`integer`) — location within the document.
#'   - `text` (`character`) — the retrieved passage, verbatim.
#'   - `score` (`numeric`) — retrieval metric value.
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

  origin <- if ("origin" %in% names(res)) as.character(res$origin) else NA_character_
  scored <- .crd_retrieval_score(res)

  tibble::tibble(
    citation_key = .crd_zot_key_from_path(origin, zotero_dir = zotero_dir),
    origin       = origin,
    chunk_id     = if ("chunk_id" %in% names(res)) as.integer(res$chunk_id) else NA_integer_,
    start        = if ("start" %in% names(res)) as.integer(res$start) else NA_integer_,
    end          = if ("end" %in% names(res)) as.integer(res$end) else NA_integer_,
    text         = as.character(res$text),
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
