# Findings — crd_store_build(): no way to add or drop a few documents without rebuilding the whole store (#44)

## Issue context

## Problem

`crd_store_build()` only builds from scratch. On an existing store it stops unless `overwrite = TRUE`, and then it creates an empty store and converts and embeds every PDF again. Adding one paper to a store costs as much as building it.

Measured with cred 0.5.0 and ragnar 0.3.1 (2026-10-31): a 263-document store (46,600 chunks, 633 MB) took 26 min to rebuild. The next day one paper's PDF reached the library through a duplicate merge. Getting that one document into the store means another 26-minute rebuild.

## What ragnar already does

- `ragnar_store_ingest()` works on an existing store. Its per-document update step (`ragnar_store_update()`, v2 stores) compares a document's chunks with those stored under the same `origin` and returns without embedding when nothing changed. A changed document has its embeddings replaced.
- Given only the new paths, it converts and embeds only those PDFs.
- ragnar exports no function to delete a document. A removal is a delete from `documents` and `embeddings` by `origin` (`doc_id`).

## Proposal

An update mode for `crd_store_build()` (`update = TRUE`), or a separate `crd_store_update()` taking the same `collection` / `citation_keys` / `library` arguments:

1. Resolve sources exactly as a build does (`.crd_zot_collection_pdfs()` / `.crd_zot_key_pdfs()`), with the same left-out and missing-file reporting.
2. Compare the resolved `src_path`s with the store's `documents.origin`.
3. Ingest only paths that are new or whose file changed (a recorded md5 or mtime, or just let ragnar's update skip the unchanged ones).
4. Delete documents whose origin is no longer resolved: an item trashed, a PDF replaced, a member removed from the collection.
5. Report added / replaced / removed counts, and rebuild the index if ingest does not.

The result should hold the same documents a full build from the same arguments would. A test can check that: build A, update with one paper added and one removed, then compare the origins with a fresh build of B.

## Notes

- Pushing still uploads the whole file (`crd_store_push()`), which is minutes rather than a rebuild.
- An origin is an absolute local path, so an update on a machine whose Zotero data directory is elsewhere would see every document as removed and every source as new. Compare origins relative to `zotero_dir` (or by attachment key, the `storage/<KEY>/` folder name) rather than as full paths.


## Exploration (2026-10-31, ragnar 0.3.1 installed)

- `ragnar_store_ingest()` → `prepare_ingest_paths()` marks each path `is_new_origin` by a LEFT JOIN on
  `documents.origin`, and `do_ingest_remote_work()` embeds in the worker only when `embed = is_new_origin`.
  But cred's `.crd_ingest_prepare()` embeds inside `prepare` itself, unconditionally. So an existing,
  unchanged origin handed to ingest is read **and embedded** in full before `ragnar_store_update_v2()`
  anti-joins its chunks against the stored ones and returns. ragnar's skip saves the DB write only.
- `ragnar_store_update_v2()` deletes `embeddings` by `doc_id` and upserts `documents` in one transaction
  per document; `ragnar_store_build_index()` runs once, at the end of ingest (`build_index = TRUE`).
- ragnar exports no delete. A removal is `DELETE FROM embeddings WHERE doc_id IN (...)` and the same on
  `documents`; the `chunks` view joins them.
- `.crd_zot_key_from_path()` already reads the attachment key as `basename(dirname(path))` matching
  `^[A-Z0-9]{8}$`; the origin id uses the same rule on the path text.

## Errors Encountered

| Error | Resolution |
|-------|------------|
