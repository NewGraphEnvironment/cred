# Changing a built ragnar store: what an update relies on

**Verified:** 2026-10-31 · **Issues:** #44 · **Produced by:** ragnar 0.3.1 and 0.3.1.9000 internals
(`ragnar_store_ingest`, `prepare_ingest_paths`, `do_ingest_remote_work`, `ragnar_store_update_v2`,
`ragnar_store_create_v2`), duckdb 1.5.2 on macOS, and `tests/testthat/test-store-update.R`. Run record:
`planning/archive/2026-10-issue-44-store-update/`.

## ragnar's own skip does not save cred the work

`prepare_ingest_paths()` marks each path `is_new_origin` by a join on `documents.origin`, and
`do_ingest_remote_work()` embeds in the worker only for a new origin. But cred's `prepare`
(`.crd_ingest_prepare()`) reads, chunks **and embeds** inside `prepare` itself, so an existing origin is
converted and embedded in full before `ragnar_store_update_v2()` anti-joins its chunks and returns.
On 0.3.1 that anti-join is also a no-op when every new chunk already exists (a PDF that lost pages
keeps its old text); 0.3.1.9000 adds a text check and skips by mtime before `prepare`. So cred
decides what to hand ragnar, and hands it only origins the store does not hold.

## Deleting a document

- ragnar exports no delete. A document is two deletes by `doc_id`: `embeddings`, then `documents`;
  the `chunks` view joins them.
- **0.3.1's schema has `embeddings.doc_id ... REFERENCES documents(doc_id)`, and duckdb refuses the
  parent delete in the transaction that deleted the children** (`Violates foreign key constraint
  because key "doc_id: 1" is still referenced`). Two autocommit statements work. 0.3.1.9000 dropped
  the key, so a transactional delete passes there and CI (which installs it) cannot catch the defect.
- `embeddings` carries HNSW indexes, so deletes go through a connection with `vss` loaded
  (`ragnar_store_connect()` loads it).

## The index after a change

- `ragnar_store_ingest()` rebuilds the FTS and VSS indexes at the end whenever it was given a path,
  whether or not any was ingested.
- BM25 results come through the `chunks` view, so a removed document disappears from results even
  from a stale index. What a stale index keeps is the removed document's share of the term
  statistics: BM25 scores differ from a fresh build's until the index is rebuilt. Test a rebuild by
  comparing scores, not by looking for the removed document.

## The file

- duckdb closes and checkpoints a database only when its last connection goes (`shutdown = TRUE` in
  `dbDisconnect()` is ignored); `CHECKPOINT` before disconnecting makes a copy complete.
- A process killed after writing leaves `<store>.wal`. A read-only connect and disconnect leaves it;
  a plain read-write open and close (`DBI::dbConnect(duckdb::duckdb(), path)`, no `vss`) replays it
  and removes it, even when it holds HNSW changes (probed 2026-10-31).
- `tools::md5sum()` answers `NA` for a file that exists but cannot be read.
