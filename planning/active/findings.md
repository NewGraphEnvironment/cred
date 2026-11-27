# Findings — crd_store_update() leaves freed blocks in the store: 32 to 76 % of an updated file is free space (#48)

## Issue context

## Problem

`crd_store_update()` leaves the space it frees inside the duckdb file, so an updated store carries 32 to 76 % free blocks (three stores measured) and
everyone who pulls it downloads that space.

Measured with cred 0.7.0, ragnar 0.3.0.9000 and duckdb 1.5.6 (`pragma database_size`, 256 KiB blocks), on three stores
updated in place by downstream work:

| store | documents before → after | file | used blocks | free blocks |
|---|---|---|---|---|
| bull_trout | 171 → 173 | 541 MiB | 1,465 (366 MiB) | 699 (32 %) |
| bull_trout_grayling | 35 → 197 | 1.3 GiB | 1,667 (417 MiB) | 4,026 (71 %) |
| habitat_modelling | 266 → 414 | 3.6 GiB | 3,584 (896 MiB) | 11,312 (76 %) |

A fresh `crd_store_build()` of the same keys runs about 13–17 KiB per chunk; these ran 20–56 KiB per chunk. Even
adding 2 documents to a 171-document store (the first row) grew the file by about 44 %, so it looks like the update
rewrites the store's tables or indexes, not only the new rows. duckdb reuses free blocks but never shrinks the file, and
`crd_store_push()` uploads the whole file.

## Options

- Have `crd_store_update()` write a compacted copy when it finishes, for example by building into a new file, or
  `ATTACH` + `COPY FROM DATABASE`, checking that the FTS and vector indexes come through, then swap it in.
- Or have `crd_store_push()` report free blocks from `pragma database_size` and refuse, or warn, above some share.
- In the meantime, a `crd_store_build(overwrite = TRUE)` over the same keys gives a compact file. That downstream work does
  this before pushing.

## Repro

Update a built store with `crd_store_update()` (any change in its keys), then compare `pragma database_size` with
the file's size before and after.


## Found since (2026-11-18, #43)

- **ragnar 0.4.0 adds growth of its own.** Its read-write connect upgrades a pre-0.4.0 store by rebuilding `embeddings` with `CREATE TABLE ... AS`, and duckdb keeps the freed space: a read-write open that wrote nothing took two real stores from 28.6 to 52.7 MB and 94.6 to 175.4 MB (about 1.85x), under duckdb 1.5.6 and 2.0.0 alike. `crd_store_update()` opens its copy read-write, so the first update of every pre-0.4.0 store that changes anything carries this on top of the growth above (`research/ragnar-versions.md`).
- **`COPY FROM DATABASE` works as the compaction.** `ATTACH` the upgraded file read-only and `COPY FROM DATABASE` into a fresh one: 52.7 MB back to 27.8 MB (smaller than the original 28.6 MB), with all three HNSW indexes present, and the copy retrieves. The probe is in cred's `planning/archive/2026-11-issue-43-ragnar-versions/findings.md`. Still to check before relying on it: the FTS index, `cred_sources` and `cred_ragnar` come through, and the HNSW indexes keep their metric.

## Errors Encountered

| Error | Resolution |
|-------|------------|
