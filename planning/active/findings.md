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

## Errors Encountered

| Error | Resolution |
|-------|------------|
