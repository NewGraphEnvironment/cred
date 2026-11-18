# Task: ragnar's development branch changes ingest errors and the v2 store format; CI tests it, users may run 0.3.0 (#43)

`DESCRIPTION` carries `Remotes: tidyverse/ragnar` with no ref, so `R CMD check` in CI installs ragnar's development branch (0.3.1.9000 at `06f7c3e` on 2026-10-31), while a machine that installed the release has 0.3.0. Two consequences were found while landing #35:

1. **Behaviour differs between the two.** 0.3.0 re-raises a worker's error with `warning(cond)`, keeping its class. The development version raises a `ragnar_ingest_worker_error` warning with a `path` field instead, and drops the worker's class. #35's ingest handled only the first, passed every local test, and failed CI's. #35 now handles both, but nothing pins which ragnar the package is tested against.
2. **The store format changes.** ragnar's development NEWS: *"`ragnar_store_ingest()` now skips unchanged sources using modification times or a hash of the prepared Markdown … Recreate existing v2 stores to use the new format; stores are not migrated automatically (#200, #201)."* Shared stores are built and pushed by `crd_store_build()` / `crd_store_push()`, and `crd_store_connect()` opens them. A store built under one ragnar and opened under the other has not been tested in either direction.

## Context

`DESCRIPTION` has `Remotes: tidyverse/ragnar` with no ref, so CI installs ragnar's main branch
(0.4.0.9000 at `fcde7b9` today). This machine has a dev snapshot, 0.3.0.9000 at `013253d`
(2026-03-17). #35's ingest broke on the gap between them. ragnar 0.4.0 went to CRAN on 2026-11-10,
and knowledge#223 is waiting on cred to support it before rebuilding.

What exploration found (ragnar 0.4.0 source and NEWS, read from the `v0.4.0` tag):

- **Opening a pre-0.4.0 v2 store with `read_only = FALSE` upgrades it on disk** (`upgrade_v2_store()`
  in `R/store-v2.R`): `documents` gains `last_modified`, `content_hash` and `ingested_at`, and
  `embeddings` is rebuilt without its foreign key, keeping `chunk_id` and recreating the HNSW indexes.
  A read-only open leaves the file as it is. `crd_store_update()` opens its copy read-write
  (`R/store.R:2464`), so under 0.4.0 an update upgrades the store it pushes.
- 0.4.0 reports a failed worker as `ragnar_ingest_worker_error` with `path`. That is the branch
  `.crd_store_ingest()` already handles (`R/store.R:1909`). The 0.3.0 branch (`error =` muffling
  `cred_ingest_skip`) cannot be reached under a 0.4.0 floor.
- 0.4.0 needs duckdb >= 1.5.0 (1.5.6 is installed here). `embed_ollama()`'s default model changed,
  which does not affect cred because `crd_store_build()` always passes the model.
- No other NGE repo pins `tidyverse/ragnar` (org code search), so changing the pin cannot cause an
  install conflict.

## Decided at the gate (owner, 2026-11-18)

- **Supported ragnar: CRAN, `ragnar (>= 0.4.0)` in Suggests.** Drop `tidyverse/ragnar` from
  `Remotes:`. cred refuses an older ragnar at call time with a message giving the installed and
  required versions. The 0.3.0-only handler branch is removed.
- **The manifest always records `ragnar_version`**, next to `embedding_model`, in every entry
  `crd_store_push()` writes. `.crd_manifest_merge()` keeps older entries as they are.

## Phase 1: Measure store compatibility (before any code change, on main's code)

- [ ] Set up scratch libraries for ragnar 0.3.0 (CRAN archive), 0.3.1 (tag) and 0.4.0 (CRAN), each
      reached through `R_LIBS`, so mirai workers load the same version. Upgrade the main library's
      ragnar to 0.4.0, which the floor in Phase 2 requires for local tests.
- [ ] Write `data-raw/ragnar_store_compat.R`. It builds a store with each ragnar using the offline
      embedder pattern from `tests/testthat/helper-store.R`, on documents long enough to produce
      several chunks. It then opens each store under each other version: read-only connect,
      `ragnar_retrieve()` (hybrid) and BM25, an ingest of one new document, and cred's
      two-statement delete. It records the schema before and after (`documents` columns, the
      foreign key, the HNSW indexes) and the md5 after a read-only open.
- [ ] Check both directions explicitly: pre-0.4.0 store → 0.4.0, read-only and read-write (the
      upgrade). Then 0.4.0-built or upgraded store → 0.3.x, read-only and ingest.
- [ ] Record the verdict in a new `research/ragnar-versions.md` (header naming the script and the
      versions used) and add a row to `research/README.md`. Also revise the foreign-key paragraph
      in `research/ragnar-store-update.md`: the key is gone once 0.4.0 has upgraded a store.

## Phase 2: Pin the supported ragnar

- [ ] `DESCRIPTION`: remove `tidyverse/ragnar` from `Remotes:`, change `ragnar` to
      `ragnar (>= 0.4.0)` in `Suggests`.
- [ ] Test first: calling a store function when the installed ragnar is older than the floor is
      refused with a message giving both versions (mock `utils::packageVersion` or the version
      reader).
- [ ] Give `.crd_need()` (`R/store.R:13`) an optional minimum version and use it for ragnar
      wherever the store functions guard it. Keep a single constant holding the floor, so the
      check and the message cannot disagree with each other.
- [ ] Remove the 0.3.0 `error =` branch from `.crd_store_ingest()` and rewrite its roxygen. The
      worker-error tests now go through 0.4.0's `ragnar_ingest_worker_error` path only.
- [ ] Raise the `skip_if_not_installed("ragnar", "0.3.0")` guards in `helper-store.R` and
      `test-store-build.R` to `"0.4.0"`.

## Phase 3: Record ragnar_version in the manifest

- [ ] Test first: `.crd_store_describe()` returns `ragnar_version` (the ragnar installed in the
      session that describes the store for push). A merge keeps an older entry that lacks the
      field exactly as it was.
- [ ] Add the field in `.crd_store_describe()` (`R/store.R:2752`), and document it in
      `crd_store_push()`'s description of a manifest entry. Its docs say it is the ragnar of the
      pushing session; when `crd_store_build()` and the push run in one session, that is the
      ragnar that built the store.

## Phase 4: Act on Phase 1's verdict

- [ ] **If the versions are compatible both ways:** no refusal. Document in
      `?crd_store_connect` and `?crd_store_update` that 0.4.0 upgrades a pre-0.4.0 store's schema
      on a read-write open, which is why an update's result has a new md5 even when only the
      upgrade changed.
- [ ] **If a direction is broken:** `crd_store_connect()` refuses that store, with a message that
      gives the store's format (the presence of `content_hash`) and the installed ragnar version,
      and a test covers the refusal. (Under the 0.4.0 floor, the direction that matters is a
      pre-0.4.0 store opened by 0.4.0.)
- [ ] Add a regression test for whichever behaviour is measured: build a store with the
      pre-0.4.0 schema (created by hand, offline), open it with 0.4.0 through
      `crd_store_connect()` and `crd_store_update()`, and assert the outcome.

## Phase 5: Docs

- [ ] `CLAUDE.md`: rewrite the ragnar-version paragraph under "One unreadable PDF…" (CI and users
      both run CRAN 0.4.0, one handler) and the 0.3.1 foreign-key note under "An update chooses…".
      Then grep the sentence `Remotes: tidyverse/ragnar` and every "0.3.1.9000" claim across
      `R/`, tests, `research/` and `CLAUDE.md`.
- [ ] `NEWS.md` entry: supported ragnar, the call-time refusal, the manifest field, and the
      measured store behaviour.

## Owed at the end (reported, done after merge)

- [ ] Comment on knowledge#223 that cred now supports ragnar 0.4.0.
- [ ] File a follow-up cred issue: 0.4.0's NEWS says ingest "now prints document origins
      literally in progress messages". Check whether that is the fix that lets cred turn
      `progress` back on.

## Validation

- [ ] Tests pass under ragnar 0.4.0 (`devtools::test()`), with no store-test skips caused by the
      ragnar version.
- [ ] Mutation check: put the 0.3.0 handler branch back, and lower the floor constant, and the new
      tests fail.
- [ ] `lintr::lint_package()` clean; `devtools::document()`; `devtools::check()` locally.
- [ ] CI on the PR installs ragnar 0.4.0 from CRAN (confirmed in the setup log) and passes.
- [ ] `/code-check branch` clean.
- [ ] PWF checkboxes match landed work; `/planning-archive`.

