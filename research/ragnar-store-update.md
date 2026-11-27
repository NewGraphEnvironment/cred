# Changing a built ragnar store: what an update relies on

**Verified:** 2026-10-31, deletes and skip rules revised for ragnar 0.4.0 on 2026-11-18, the index and compaction on 2026-11-27 · **Issues:** #44, #43, #48 · **Produced by:** ragnar 0.3.1 and 0.3.1.9000 internals
(`ragnar_store_ingest`, `prepare_ingest_paths`, `do_ingest_remote_work`, `ragnar_store_update_v2`,
`ragnar_store_create_v2`), duckdb 1.5.2 on macOS, and `tests/testthat/test-store-update.R`. Run record:
`planning/archive/2026-10-issue-44-store-update/`.

## ragnar's own skip does not save cred the work

`prepare_ingest_paths()` marks each path `is_new_origin` by a join on `documents.origin`, and
`do_ingest_remote_work()` embeds in the worker only for a new origin. But cred's `prepare`
(`.crd_ingest_prepare()`) reads, chunks **and embeds** inside `prepare` itself, so an existing origin is
converted and embedded in full before `ragnar_store_update_v2()` anti-joins its chunks and returns.
On 0.3.1 that anti-join is also a no-op when every new chunk already exists (a PDF that lost pages
keeps its old text); 0.3.1.9000 and 0.4.0 skip by mtime before `prepare`, and compare a hash of the prepared Markdown only after `prepare` has returned. So cred
decides what to hand ragnar, and hands it only origins the store does not hold.

## Deleting a document

- ragnar exports no delete. A document is two deletes by `doc_id`: `embeddings`, then `documents`;
  the `chunks` view joins them.
- **A store built before ragnar 0.4.0 has `embeddings.doc_id ... REFERENCES documents(doc_id)`, and
  duckdb refuses the parent delete in the transaction that deleted the children** (`Violates foreign
  key constraint because key "doc_id: 1" is still referenced`). Two autocommit statements work.
  ragnar 0.4.0 drops the key when it opens such a store read-write, so under cred's 0.4.0 floor the
  update's copy has no key by the time it deletes. The two statements stay because they are correct
  either way (`research/ragnar-versions.md`, 2026-11-18).
- `embeddings` carries HNSW indexes, so deletes go through a connection with `vss` loaded
  (`ragnar_store_connect()` loads it).

## The index after a change

- `ragnar_store_ingest()` rebuilds the FTS and VSS indexes at the end whenever it was given a path,
  whether or not any was ingested, unless `build_index = FALSE`.
- A rebuild drops the old indexes inside the file, and duckdb keeps their space: updated stores
  carried 32 to 76 % free blocks, every block downloaded by each reader. So the update builds no
  index in its working copy (indexes dropped before ragnar opens it, ingest with
  `build_index = FALSE`), copies it into a fresh file with `COPY FROM DATABASE`, and builds the
  indexes there once (#48). The copy carries sequences, the `chunks` view, `metadata` (the
  serialised embedder) and cred's own tables; a fresh build and an updated store hold the same
  objects and the same blocks on the toy fixture (19, none free).
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
