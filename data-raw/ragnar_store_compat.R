# Can a ragnar store built by one ragnar release be used by another? (#43)
#
# Builds an offline store under each ragnar given, then opens a copy of each
# under every ragnar: read-only (connect, md5, hybrid and BM25 retrieve, the
# store's own embedder), and read-write (the schema afterwards, an insert, an
# ingest through a worker `prepare`, cred's two-statement delete, an index
# rebuild, and a read-only reopen). Each step runs in its own Rscript with
# `R_LIBS` set to one library holding one ragnar, so ragnar's mirai workers load
# that same ragnar.
#
# Usage, from the repo root:
#
#   Rscript data-raw/ragnar_store_compat.R <out_dir> <label=lib> [<label=lib> ...]
#
# Each `lib` is a library holding exactly one ragnar. Every other package comes
# from the default libraries, so duckdb is the same for every step. Results go
# to <out_dir>/results.tsv, one row per (builder, opener, mode, check).

args <- commandArgs(trailingOnly = TRUE)

# --- worker mode: called by the driver below, once per step ---------------

if (length(args) >= 1L && args[[1]] %in% c("build", "open")) {
  suppressPackageStartupMessages({
    library(ragnar)
    library(DBI)
  })
  embed <- function(x) {
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
  vocab <- c("culvert", "barrier", "fish", "passage", "stream", "salmon",
             "habitat", "riparian", "bankfull", "width", "drainage", "beaver",
             "wetland", "coho", "steelhead", "crossing", "migration", "channel")
  body_text <- function(seed) {
    set.seed(seed)
    paste(sample(vocab, 400L, replace = TRUE), collapse = " ")
  }
  out <- character()
  rec <- function(check, value) {
    out[[length(out) + 1L]] <<- paste(check, gsub("[\t\n]", " ", as.character(value)), sep = "\t")
  }
  try_rec <- function(check, expr) {
    v <- tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e)))
    rec(check, v)
    invisible(v)
  }
  schema <- function(con) {
    cols <- paste(DBI::dbListFields(con, "documents"), collapse = ",")
    fk <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM duckdb_constraints()
                                WHERE table_name = 'embeddings' AND constraint_type = 'FOREIGN KEY'")$n
    hnsw <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM duckdb_indexes()
                                  WHERE table_name = 'embeddings' AND sql ILIKE '%USING HNSW%'")$n
    sprintf("documents=[%s] fk=%d hnsw=%d", cols, fk, hnsw)
  }
  rec("ragnar", as.character(packageVersion("ragnar")))

  if (args[[1]] == "build") {
    path <- args[[2]]
    store <- ragnar_store_create(path, embed = embed, version = 2)
    for (i in 1:6) {
      doc <- MarkdownDocument(body_text(i), origin = sprintf("/x/storage/KEY0000%d/doc.pdf", i))
      ragnar_store_insert(store, markdown_chunk(doc))
    }
    ragnar_store_build_index(store)
    # cred's own table, as crd_store_build() writes it, to see it survive an upgrade.
    DBI::dbExecute(store@con, "CREATE TABLE cred_sources (origin_id VARCHAR PRIMARY KEY, md5 VARCHAR)")
    DBI::dbExecute(store@con, "INSERT INTO cred_sources VALUES ('storage/KEY00001/doc.pdf', 'abc')")
    rec("schema", schema(store@con))
    DBI::dbExecute(store@con, "CHECKPOINT")
    DBI::dbDisconnect(store@con, shutdown = TRUE)
  } else {
    path <- args[[2]]
    mode <- args[[3]]
    md5_before <- unname(tools::md5sum(path))
    store <- NULL
    connected <- try_rec("connect", {
      store <- ragnar_store_connect(path, read_only = mode == "ro")
      "ok"
    })
    if (identical(connected, "ok")) {
      rec("schema_after_connect", schema(store@con))
      try_rec("embed_width", ncol(store@embed("probe text")))
      try_rec("retrieve_hybrid_rows", nrow(ragnar_retrieve(store, "culvert fish passage", top_k = 5)))
      try_rec("retrieve_bm25_rows", nrow(ragnar_retrieve_bm25(store, "culvert fish passage", top_k = 5)))
      try_rec("cred_sources_rows", DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM cred_sources")$n)
      if (mode == "rw") {
        try_rec("insert", {
          doc <- MarkdownDocument(body_text(101), origin = "/x/storage/KEY00101/doc.pdf")
          ragnar_store_insert(store, markdown_chunk(doc))
          "ok"
        })
        try_rec("ingest", {
          f <- file.path(tempdir(), "KEY00102.md")
          writeLines(body_text(102), f)
          prepare <- function(path) {
            doc <- ragnar::MarkdownDocument(paste(readLines(path), collapse = "\n"), origin = path)
            ragnar::markdown_chunk(doc)
          }
          ragnar_store_ingest(store, f, prepare = prepare, progress = FALSE)
          "ok"
        })
        try_rec("delete_two_statements", {
          id <- DBI::dbGetQuery(store@con, "SELECT doc_id FROM documents ORDER BY doc_id LIMIT 1")$doc_id
          DBI::dbExecute(store@con, "DELETE FROM embeddings WHERE doc_id = ?", params = list(id))
          DBI::dbExecute(store@con, "DELETE FROM documents WHERE doc_id = ?", params = list(id))
          "ok"
        })
        try_rec("delete_one_transaction", {
          id <- DBI::dbGetQuery(store@con, "SELECT doc_id FROM documents ORDER BY doc_id LIMIT 1")$doc_id
          DBI::dbWithTransaction(store@con, {
            DBI::dbExecute(store@con, "DELETE FROM embeddings WHERE doc_id = ?", params = list(id))
            DBI::dbExecute(store@con, "DELETE FROM documents WHERE doc_id = ?", params = list(id))
          })
          "ok"
        })
        try_rec("build_index", {
          ragnar_store_build_index(store)
          "ok"
        })
        try_rec("retrieve_hybrid_after", nrow(ragnar_retrieve(store, "culvert fish passage", top_k = 5)))
        rec("schema_after_writes", schema(store@con))
        try_rec("documents_after", DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM documents")$n)
        DBI::dbExecute(store@con, "CHECKPOINT")
      }
      DBI::dbDisconnect(store@con, shutdown = TRUE)
      rec("md5_unchanged", identical(unname(tools::md5sum(path)), md5_before))
      if (mode == "rw") {
        try_rec("reopen_ro", {
          s <- ragnar_store_connect(path, read_only = TRUE)
          n <- nrow(ragnar_retrieve(s, "culvert fish passage", top_k = 5))
          DBI::dbDisconnect(s@con, shutdown = TRUE)
          n
        })
      }
    }
  }
  writeLines(out)
  quit(save = "no")
}

# --- driver ----------------------------------------------------------------

stopifnot(length(args) >= 2L)
out_dir <- args[[1]]
libs <- args[-1]
labels <- sub("=.*$", "", libs)
libs <- stats::setNames(sub("^[^=]*=", "", libs), labels)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
self <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))

run_step <- function(lib, ...) {
  res <- system2("Rscript", c("--vanilla", shQuote(self), ...), stdout = TRUE, stderr = FALSE,
                 env = paste0("R_LIBS=", lib))
  status <- attr(res, "status")
  if (!is.null(status)) res <- c(res, paste0("exit\t", status))
  res
}

rows <- list()
add <- function(builder, opener, mode, lines) {
  kv <- strsplit(lines[grepl("\t", lines)], "\t", fixed = TRUE)
  rows[[length(rows) + 1L]] <<- data.frame(
    builder = builder, opener = opener, mode = mode,
    check = vapply(kv, `[`, "", 1L), value = vapply(kv, function(x) paste(x[-1], collapse = " "), "")
  )
}

built <- character()
for (b in labels) {
  p <- file.path(out_dir, paste0("built_", b, ".duckdb"))
  unlink(p)
  add(b, "-", "build", run_step(libs[[b]], "build", shQuote(p)))
  built[[b]] <- p
}
for (b in labels) {
  for (o in labels) {
    for (mode in c("ro", "rw")) {
      cp <- file.path(out_dir, sprintf("open_%s_by_%s_%s.duckdb", b, o, mode))
      file.copy(built[[b]], cp, overwrite = TRUE)
      add(b, o, mode, run_step(libs[[o]], "open", shQuote(cp), mode))
      unlink(c(cp, paste0(cp, ".wal")))
    }
  }
}
res <- do.call(rbind, rows)
utils::write.table(res, file.path(out_dir, "results.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("wrote", nrow(res), "rows to", file.path(out_dir, "results.tsv"), "\n")
