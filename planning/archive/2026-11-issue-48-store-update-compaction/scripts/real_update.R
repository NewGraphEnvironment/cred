# Phase 4 measurement (#48): Rscript real_update.R <cred checkout> <store.duckdb> <out.duckdb>
# Copies the store, runs crd_store_update() with sources mocked to the store's own origins
# minus its first document (a removal: no embedder needed), and prints file size, block
# accounting and wall time before and after. BM25 top 20 is saved beside <out> for comparison.
args <- commandArgs(TRUE); code <- args[1]; src <- args[2]; out <- args[3]
suppressMessages(devtools::load_all(code, quiet = TRUE))
file.copy(src, out, overwrite = TRUE)
dbsize <- function(path) { con <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  d <- DBI::dbGetQuery(con, "PRAGMA database_size"); sprintf("file %.1f MB | blocks %d total, %d used, %d free (%.0f%%)", file.size(path)/2^20, d$total_blocks, d$used_blocks, d$free_blocks, 100*d$free_blocks/d$total_blocks) }
con <- DBI::dbConnect(duckdb::duckdb(), out, read_only = TRUE)
docs <- DBI::dbGetQuery(con, "SELECT doc_id, origin FROM documents ORDER BY doc_id")
schema <- "content_hash" %in% DBI::dbListFields(con, "documents")
DBI::dbDisconnect(con, shutdown = TRUE)
cat("before:", dbsize(out), "| docs", nrow(docs), "| 0.4.0 schema:", schema, "\n")
keep <- docs$origin[-1]
src_tbl <- tibble::tibble(citation_key = sprintf("k%04d", seq_along(keep)), src_path = keep)
t <- system.time(testthat::with_mocked_bindings(
  .crd_store_sources = function(...) src_tbl,
  suppressWarnings(crd_store_update(out, citation_keys = "x")),
  .package = "cred"))[["elapsed"]]
cat("update secs:", round(t, 1), "\nafter:", dbsize(out), "\n")
st <- ragnar::ragnar_store_connect(out, read_only = TRUE)
r <- ragnar::ragnar_retrieve_bm25(st, "culvert fish passage", top_k = 20L)
saveRDS(list(chunk = r$chunk_id, score = r$metric_value), paste0(out, ".bm25.rds"))
DBI::dbDisconnect(st@con, shutdown = TRUE)
