# Plan review — #44 (Plan agent, spawned 2026-10-31T22:36Z, delivered ~22:44Z)

Read-only reviewer; its report was returned as reply text and is recorded here by the parent session.
Verdicts on each finding are in findings.md ("Plan review: what each finding came to").

## Blocker
1. `drop_docs()` in one transaction fails on ragnar 0.3.1 stores: `embeddings.doc_id` has a FOREIGN KEY on
   `documents`, and duckdb 1.5.2 rejects the parent delete in the transaction that deleted the children.
   Dev ragnar (0.3.1.9000) dropped the FK, so CI would pass the transactional form. Fix: two autocommit statements.
2. A same-origin replacement the worker skips (unreadable) still has a row in `documents`, so `.crd_store_ingest()`
   reports it ingested and the new md5 is recorded; it is never retried. Also 0.3.1's `ragnar_store_update_v2`
   is a no-op when every new chunk already exists (e.g. a PDF that lost pages): old text, new md5.
   Fix: delete replaced docs before ingest (the plan's design), or exclude skipped origins and confirm the change.

## Gap
3. Checkpoint before disconnect, and refuse the rename if `<work>.wal` exists (duckdb ignores `shutdown`, the db
   closes only with its last connection).
4. A session holding the original open keeps a cached instance on the replaced file; `crd_store_connect(verify = TRUE)`
   will overwrite the unpushed update with the remote copy. Say so: push, or `verify = FALSE`, and reconnect.
5. A permanently unreadable source counts as added on every update: copy, ingest, index rebuild, rename, new md5.
   Leave the original alone when nothing was ingested or removed and the record is unchanged.
6. Nothing refuses a zero-document result; consider a removal-fraction guard too.
7. State the per-document unrecorded rule, not a whole-store legacy rule.
8. The WAL-refusal remedy (`ragnar_store_connect(read_only = FALSE)`) may fail to replay HNSW changes before
   `LOAD vss` (unverified).

## Ordering
9. Probe and connect read-only on the original before copying; build the index once.

## Assumption
10. 0.3.1.9000 refuses 0.3.1 stores (missing `last_modified`, `content_hash`, `ingested_at`) and 0.3.1 cannot insert
    into a 0.3.1.9000 store. 0.3.1.9000 skips an existing origin by mtime before `prepare`.
11. Deletes need a connection with vss loaded (HNSW indexes on `embeddings`); `ragnar_store_connect()` provides it.
12. Origin-id rule holds; linked files re-ingest when a store changes machine; a renamed attachment re-embeds.

## Acceptance
13. Phrase parity as conditional on every file being present; test the kept-missing divergence on its own.
14. Compare `embeddings` count and orphan `doc_id`s, not only the `chunks` view; BM25 shows an addition indexed.
15. Missing tests: unreadable same-origin replacement, permanently unreadable source untouched, rename FALSE,
    leftover work WAL, zero-document refusal, removal under 0.3.1. No mutation table yet in findings.md.

## Scope
16. Record file size beside the owed timing; warn on leftover `<store>.updating-*` copies; update the plan text
    to match the draft's choices.
