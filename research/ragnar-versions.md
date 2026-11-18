# ragnar versions: which one cred supports, and whether a store crosses between them

**Verified:** 2026-11-18 · **Issues:** #43 (from #35, #44) · **Produced by:**
`data-raw/ragnar_store_compat.R`, results in `data-raw/logs/ragnar_store_compat/20261118_*`; ragnar
0.3.0, 0.3.1 and 0.4.0 from CRAN and a 0.3.0.9000 development install (`013253d`), each in its own
library; duckdb 1.5.6, R 4.5.2, macOS; ragnar 0.4.0's `R/store.R` and `R/store-v2.R`; copies of two
real stores built before 0.4.0 (28.6 MB and 94.6 MB, `nomic-embed-text`), probed under 0.4.0 by hand
(the commands are in the #43 archive's `findings.md`).

## Supported: CRAN ragnar >= 0.4.0

cred took ragnar from `Remotes: tidyverse/ragnar` with no ref, so CI tested ragnar's main branch while
a machine could have any release or development snapshot. #35's ingest handled one release's worker
errors, passed every local test, and failed in CI. ragnar 0.4.0 reached CRAN on 2026-11-10, so cred
requires `ragnar (>= 0.4.0)` and CI and users install the same release.

## Reading a store works in every direction

Each ragnar built an offline store (six multi-chunk documents, FTS and HNSW indexes, plus cred's
`cred_sources` table). A copy of each was then opened by each ragnar: 4 builders x 4 openers.

- **Read-only, all 16 pairs:** connect, hybrid and BM25 retrieval, the store's own recorded embedder
  (width 16), and `cred_sources` all work. The file's md5 is unchanged afterwards.
- **What separates the two formats is what 0.4.0 does on a read-write open.** A store built before
  0.4.0 has `documents (doc_id, origin, text)` and a foreign key from `embeddings` to `documents`.
  ragnar 0.4.0's `ragnar_store_connect(read_only = FALSE)` runs `upgrade_v2_store()`: `documents`
  gains `last_modified`, `content_hash` and `ingested_at`, and `embeddings` is rebuilt without the
  key. The three HNSW indexes and `cred_sources` survive. 0.4.0 says nothing about the upgrade.

## On real stores

Two stores built by ragnar 0.3.x with `nomic-embed-text` were copied and opened under 0.4.0:

- Read-only: the stored embedder (`ragnar::embed_ollama(x = x, model = "nomic-embed-text")`) runs
  against a live Ollama (width 768), hybrid and BM25 retrieval work, and the md5 is unchanged.
- **A read-write open that writes nothing still upgrades the store.** It changes the md5 and makes
  the file about 1.85x larger (28.6 to 52.7 MB, 94.6 to 175.4 MB), because duckdb does not give back
  the space the rebuilt `embeddings` table leaves. It took 0.3 s and 2.1 s. No `.wal` is left. The
  same open under 0.3.0.9000 left md5 and size unchanged, and a second read-write open of an
  upgraded store under 0.4.0 changes nothing again.
- Retrieval after the upgrade returns the same hybrid chunks, and the same BM25 chunks and scores, as
  before it. HNSW recall loss would show here rather than on toy stores, and none did.
- **The upgrade leaves only the L2 HNSW index usable.** `upgrade_v2_store()` recreates the indexes
  from `duckdb_indexes().sql`, which omits each index's `WITH (metric = ...)`, so all three come back
  as L2 indexes under their old names. Before the upgrade, `EXPLAIN` of an `ORDER BY` on
  `array_cosine_distance`, `array_negative_inner_product` and `array_distance` against a constant
  vector uses an HNSW scan for all three; after it, only for `array_distance`. Cosine and
  inner-product queries, cosine being ragnar's default, fall back to a full scan: the same answers,
  more slowly on a large store. `ragnar_store_build_index()` restores all three. This is a ragnar
  defect, not a cred one.
- `COPY FROM DATABASE` into a fresh file brings an upgraded store back to 27.8 MB (smaller than the
  original), with its three HNSW indexes, and the copy retrieves.

## Writing: 0.4.0 can write to any store, 0.3.x cannot ingest into an upgraded one

| store format | opened read-write by | insert | `ragnar_store_ingest()` | two-statement delete | delete in one transaction |
|---|---|---|---|---|---|
| pre-0.4.0 | 0.3.x | ok | ok | ok | refused (foreign key) |
| pre-0.4.0 | 0.4.0 (upgraded on open) | ok | ok | ok | ok |
| 0.4.0 | 0.3.x | ok | **fails** | ok | ok |
| 0.4.0 | 0.4.0 | ok | ok | ok | ok |

0.3.x's ingest fails on a 0.4.0-format store with `Binder Error: table "excluded" has 3 columns
available but 6 columns specified`, the upsert in its `ragnar_store_update_v2()`. Under cred's 0.4.0
floor a 0.3.x install is refused before any store is opened, so this cannot happen through current
cred. It can happen through **cred 0.7.0 or older** with ragnar 0.3.x, once a shared store has been
rebuilt under 0.4.0, or upgraded by `crd_store_update()` and pushed. The remedy is to update cred
and ragnar, not the store.

## What this means for cred's own operations

- `crd_store_connect()` opens read-only by default, so it never upgrades a pulled store.
  `read_only = FALSE` does, even when the caller writes nothing, and then the local file no longer
  matches the manifest's md5: the next verified connect downloads the store again. Under 0.3.x the
  same open left the file as it was, so this is new with 0.4.0.
- `crd_store_update()` opens its working copy read-write, so a pre-0.4.0 store comes out of an update
  in 0.4.0 format. Every update that changes something rebuilds the index, so it also restores the
  HNSW metrics the upgrade loses. A bare `crd_store_connect(read_only = FALSE)` does not. When the update changes nothing, the copy is discarded and the store keeps its
  old format.
- cred's two-statement delete works under both formats. Under the 0.4.0 floor the working copy is
  always upgraded before the deletes run, so one transaction would work too, and no test can tell
  the two apart any more. cred keeps two statements because they are correct under either schema.
- 0.4.0's ingest records freshness for documents it ingests. cred passes ragnar only origins the
  store does not already hold (`research/ragnar-store-update.md`), so ragnar's "unknown freshness,
  reprocessed on next ingest" rule for upgraded documents never applies to cred.
