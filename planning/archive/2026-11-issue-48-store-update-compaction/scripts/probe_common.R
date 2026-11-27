# Run from the cred repo root at the commit this archive closed with. Shared setup for
# the #48 probes: loads the package and the update test's helpers (local_update_world(),
# build(), update(), contents()), and defines dbsize() and inventory().
suppressMessages(devtools::load_all(".", quiet = TRUE))
library(testthat)
ex <- parse("tests/testthat/test-store-update.R")
for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-"))) eval(e, globalenv())
dbsize <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  d <- DBI::dbGetQuery(con, "PRAGMA database_size")
  c(file = file.size(path), block = d$block_size, total = d$total_blocks, used = d$used_blocks, free = d$free_blocks)
}
inventory <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  try(DBI::dbExecute(con, "LOAD vss; LOAD fts"), silent = TRUE)
  q <- function(s) DBI::dbGetQuery(con, s)
  list(
    schemas = q("SELECT schema_name FROM duckdb_schemas() WHERE database_name = current_database() AND NOT internal ORDER BY 1")[[1]],
    tables = q("SELECT schema_name || '.' || table_name FROM duckdb_tables() WHERE database_name = current_database() ORDER BY 1")[[1]],
    views = q("SELECT schema_name || '.' || view_name FROM duckdb_views() WHERE database_name = current_database() AND NOT internal ORDER BY 1")[[1]],
    seqs = q("SELECT schema_name || '.' || sequence_name FROM duckdb_sequences() WHERE database_name = current_database() ORDER BY 1")[[1]],
    macros = q("SELECT DISTINCT schema_name || '.' || function_name FROM duckdb_functions() WHERE database_name = current_database() AND NOT internal ORDER BY 1")[[1]],
    indexes = q("SELECT index_name || ' :: ' || coalesce(sql, '') FROM duckdb_indexes() WHERE database_name = current_database() ORDER BY 1")[[1]]
  )
}
