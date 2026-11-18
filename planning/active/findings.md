# Findings — ragnar's development branch changes ingest errors and the v2 store format; CI tests it, users may run 0.3.0 (#43)

## Issue context

**If done:** cred states which ragnar it supports, its CI tests that one, and a store built by one ragnar is either readable by the other or refused with a message naming the version gap. **If never:** CI tests ragnar's development branch while users may run 0.3.0, and a store built under one may not open under the other, with nothing in cred saying why.

## Problem

`DESCRIPTION` carries `Remotes: tidyverse/ragnar` with no ref, so `R CMD check` in CI installs ragnar's development branch (0.3.1.9000 at `06f7c3e` on 2026-10-31), while a machine that installed the release has 0.3.0. Two consequences were found while landing #35:

1. **Behaviour differs between the two.** 0.3.0 re-raises a worker's error with `warning(cond)`, keeping its class. The development version raises a `ragnar_ingest_worker_error` warning with a `path` field instead, and drops the worker's class. #35's ingest handled only the first, passed every local test, and failed CI's. #35 now handles both, but nothing pins which ragnar the package is tested against.
2. **The store format changes.** ragnar's development NEWS: *"`ragnar_store_ingest()` now skips unchanged sources using modification times or a hash of the prepared Markdown … Recreate existing v2 stores to use the new format; stores are not migrated automatically (#200, #201)."* Shared stores are built and pushed by `crd_store_build()` / `crd_store_push()`, and `crd_store_connect()` opens them. A store built under one ragnar and opened under the other has not been tested in either direction.

## Proposed

- Decide the supported ragnar: pin `Remotes:` to a tag or SHA, or require a minimum version in `Suggests`, so CI and users run the same one.
- Measure: open a store built with 0.3.0 under the development version, and the reverse, then retrieve and ingest. Record what happens.
- If they are incompatible, have `crd_store_connect()` refuse with a message naming the ragnar versions, and record the building ragnar version in the manifest beside the embedding model.



## Found since

- ragnar 0.4.0 is on CRAN (`tidyverse/ragnar` v0.4.0). It fixes a `markdown_chunk()` failure that 0.3.1 hits on a line-numbered manuscript PDF (`snap_nearest()` → `findInterval()`, "'vec' must be sorted non-decreasingly"). That failure skipped one document in NewGraphEnvironment/knowledge#223, which waits on this issue to rebuild under 0.4.0.

## Phase 1: store compatibility across ragnar versions (2026-11-18)

Verdict and tables: `research/ragnar-versions.md`. Raw rows:
`data-raw/logs/ragnar_store_compat/20261118_results.tsv` (4 builders x 4 openers x ro/rw), from
`Rscript --vanilla data-raw/ragnar_store_compat.R <out> v0.3.0=<lib> v0.3.0.9000=<lib> v0.3.1=<lib> v0.4.0=<lib>`,
each `<lib>` holding one ragnar installed with `R CMD INSTALL --library=<lib>` from the CRAN tarball
(0.3.0.9000: a copy of this machine's installed `013253d` snapshot).

### Real-store probes (review A1-A3, G4, B2)

Copies of knowledge-stats' `pine.duckdb` (28.6 MB, mtime 2026-09-02) and `statistics.duckdb`
(94.6 MB, 2026-11-10), run with `R_LIBS=<0.4.0 lib> Rscript --vanilla <probe> <copy>`.

The read-only / read-write / retrieval probe:

```r
suppressPackageStartupMessages({library(ragnar); library(DBI)})
f <- commandArgs(TRUE)[1]
q <- "temperature effects on fish growth"
schema <- function(con) sprintf("cols=%s fk=%d hnsw=%d",
  paste(dbListFields(con, "documents"), collapse=","),
  dbGetQuery(con, "SELECT COUNT(*) n FROM duckdb_constraints() WHERE table_name='embeddings' AND constraint_type='FOREIGN KEY'")$n,
  dbGetQuery(con, "SELECT COUNT(*) n FROM duckdb_indexes() WHERE table_name='embeddings' AND sql ILIKE '%HNSW%'")$n)
sig <- function(r) paste(vapply(seq_len(nrow(r)), function(i) paste(unlist(r$chunk_id[i]), collapse="+"), ""), collapse=" ")
cat("ragnar", as.character(packageVersion("ragnar")), "duckdb", as.character(packageVersion("duckdb")), "\n")
m0 <- unname(tools::md5sum(f)); s0 <- file.size(f)
s <- ragnar_store_connect(f, read_only = TRUE)
cat("RO schema:", schema(s@con), "\n")
cat("embed_func:", gsub("\\s+", " ", paste(deparse(s@embed), collapse=" ")), "\n")
cat("embed width:", tryCatch(ncol(s@embed("probe")), error=function(e) conditionMessage(e)), "\n")
r1 <- ragnar_retrieve(s, q, top_k = 8); b1 <- ragnar_retrieve_bm25(s, q, top_k = 8)
cat("RO hybrid rows", nrow(r1), "bm25 rows", nrow(b1), "\n")
dbDisconnect(s@con, shutdown = TRUE)
cat("RO md5 unchanged:", identical(unname(tools::md5sum(f)), m0), "\n")
t <- system.time(s <- ragnar_store_connect(f, read_only = FALSE))[["elapsed"]]
cat("RW connect secs:", t, " schema:", schema(s@con), "\n")
dbDisconnect(s@con, shutdown = TRUE)
cat("after RW no-op: md5 unchanged:", identical(unname(tools::md5sum(f)), m0), " size", s0, "->", file.size(f), " wal:", file.exists(paste0(f, ".wal")), "\n")
s <- ragnar_store_connect(f, read_only = TRUE)
r2 <- ragnar_retrieve(s, q, top_k = 8); b2 <- ragnar_retrieve_bm25(s, q, top_k = 8)
cat("hybrid same chunks:", identical(sig(r1), sig(r2)), " bm25 same chunks+scores:", identical(b1$chunk_id, b2$chunk_id) && isTRUE(all.equal(b1$metric_value, b2$metric_value)), "\n")
dbDisconnect(s@con, shutdown = TRUE)
```

The no-op read-write open, run under 0.3.0.9000 on a fresh copy (md5 and size unchanged) and under
0.4.0 on an already-upgraded copy (unchanged):

```r
suppressPackageStartupMessages(library(ragnar)); f <- commandArgs(TRUE)[1]
m0 <- unname(tools::md5sum(f)); s0 <- file.size(f)
s <- ragnar_store_connect(f, read_only = FALSE); DBI::dbDisconnect(s@con, shutdown = TRUE)
cat(as.character(packageVersion("ragnar")), "RW no-op md5 unchanged:", identical(unname(tools::md5sum(f)), m0), "size", s0, "->", file.size(f), "\n")
```

Compaction (52.7 MB upgraded copy to 27.8 MB, 3 HNSW indexes, retrieves 7 rows):

```r
suppressPackageStartupMessages(library(DBI))
src <- commandArgs(TRUE)[1]; dst <- commandArgs(TRUE)[2]
con <- dbConnect(duckdb::duckdb(), dst)
dbExecute(con, "INSTALL vss; INSTALL fts; LOAD vss; LOAD fts; SET hnsw_enable_experimental_persistence = true")
dbExecute(con, sprintf("ATTACH '%s' AS old (READ_ONLY)", src))
r <- tryCatch({dbExecute(con, sprintf("COPY FROM DATABASE old TO %s", sub("\\.duckdb$", "", basename(dst)))); "ok"}, error = function(e) conditionMessage(e))
cat("copy:", r, "\n"); dbExecute(con, "DETACH old"); dbExecute(con, "CHECKPOINT")
cat("hnsw in copy:", dbGetQuery(con, "SELECT COUNT(*) n FROM duckdb_indexes() WHERE sql ILIKE '%HNSW%'")$n, "\n")
dbDisconnect(con, shutdown = TRUE)
cat("size", file.size(src), "->", file.size(dst), "\n")
```

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Matrix wrote 40 rows, every open step `exit 1` | The script assigned the connected store inside `try_rec()` and then overwrote it with the step's `"ok"`; bind the store in the worker's own frame |
| `IO Error: Extension ".../vss.duckdb_extension" not found` in a bare DBI connection | `INSTALL vss; INSTALL fts;` before `LOAD`, which `ragnar_store_connect()` does for itself |
