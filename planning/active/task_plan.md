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

- **After the plan review (owner, 2026-11-18):** `ragnar_version` is **stamped into the store** at
  build and update, in a cred-owned table. `crd_store_push()` reads it from there and also records
  the store's format. An unstamped store falls back to the session's version with a warning, or null
  when ragnar is not installed (review A0). `crd_store_connect(read_only = FALSE)` on an old-format
  store **warns, then opens**: the schema is peeked read-only first, and the warning is classed
  (review B2).

## Phase 1: Measure store compatibility (before any code change, on main's code)

- [x] Set up scratch libraries for ragnar 0.3.0 (CRAN archive), 0.3.1 (CRAN archive), the
      0.3.0.9000 snapshot this machine had, and 0.4.0 (CRAN), each reached through `R_LIBS`, so
      mirai workers load the same version. Upgrade the main library's ragnar to 0.4.0, which the
      floor in Phase 2 requires for local tests.
- [x] Write `data-raw/ragnar_store_compat.R`: builds an offline store with each ragnar, opens a copy
      of each under every ragnar, read-only and read-write, and records schema, retrieval, insert,
      ingest, both delete styles, index rebuild, md5 and a read-only reopen.
- [x] Check both directions explicitly. Result: every pair reads. 0.4.0 upgrades an old store on a
      read-write open and can write to it. 0.3.x cannot ingest into a 0.4.0-format store.
- [x] (review A1-A3, G4) Probe two real old-format stores under 0.4.0: the stored embedder runs
      against live Ollama, retrieval is unchanged after an upgrade, the first read-write open grows
      the file about 1.85x and changes the md5 (0.3.x left both unchanged), and
      `COPY FROM DATABASE` compacts it back with its HNSW indexes.
- [x] Record the verdict in a new `research/ragnar-versions.md` (header naming the script and the
      versions used) and add a row to `research/README.md`. Also revise the foreign-key paragraph
      in `research/ragnar-store-update.md`: the key is gone once 0.4.0 has upgraded a store.

## Phase 2: Pin the supported ragnar

- [x] `DESCRIPTION`: remove `tidyverse/ragnar` from `Remotes:`, change `ragnar` to
      `ragnar (>= 0.4.0)` in `Suggests`.
- [x] Test first: calling a store function when the installed ragnar is older than the floor is
      refused with a message giving both versions. The test mocks a cred-side version-reader seam
      (review G8) and hard-codes a version below the floor (AC1).
- [x] Give `.crd_need()` (`R/store.R:13`) an optional minimum version and use it for ragnar
      wherever the store functions guard it. Read the version with `getNamespaceVersion()` after
      `requireNamespace()`, not `packageVersion()` (G8). Keep a single constant holding the floor.
- [x] Remove the 0.3.0 `error =` branch from `.crd_store_ingest()` and rewrite its roxygen. Say that
      0.4.0's path muffles every worker error that carries a path, and that each one surfaces in the
      report's skipped list (G7). Keep the `cred_ingest_skip` class, which `prepare` and its tests
      use. Rewrite the comment on the crashed-worker test (`test-store-build.R` near 363).
- [x] Raise the `skip_if_not_installed("ragnar", "0.3.0")` guards in `helper-store.R`,
      `test-store-build.R` and `test-store-update.R` (G1) to `"0.4.0"`.

## Phase 3: Record ragnar_version in the manifest, stamped in the store

- [x] Test first: a store built by `crd_store_build()` carries the stamp, and an update refreshes it;
      `.crd_store_describe()` returns `ragnar_version` from the stamp and `store_format` from the
      schema; an unstamped store falls back to the session's ragnar with a warning, and to NA with no
      error when ragnar is absent; a merge keeps an older entry that lacks the fields exactly as it
      was.
- [x] Implement the stamp (a cred-owned table, written beside `cred_sources`), the read in
      `.crd_store_describe()` (`R/store.R:2752`), and document both fields in `crd_store_push()`.

## Phase 4: Act on Phase 1's verdict (compatible for 0.4.0; no format refusal)

- [x] Document in `?crd_store_update` that under 0.4.0 an update that changes something also upgrades
      a pre-0.4.0 store (new columns, foreign key dropped, file about 1.85x larger), and that an
      update that changes nothing leaves it as it was (review B1).
- [x] B2: `.crd_store_open()` peeks the schema read-only through DBI, disconnecting before ragnar
      opens the file, and gives a classed warning when `read_only = FALSE` would upgrade it, then
      opens. Document it in `?crd_store_connect`.
- [x] Regression tests on a hand-built pre-0.4.0 fixture (review G6: `embeddings` recreated with
      0.3.0's foreign key verbatim, all three new columns absent, a premise test, never cached).
      Cases (AC2): (1) read-only connect plus `crd_search()` leaves the md5 unchanged and the schema
      old; (2) an update with nothing to do leaves the file byte-identical; (3) an update whose only
      new file cannot be read discards the copy and the store stays old; (4) an update with a real
      change gives an upgraded store with `cred_sources` intact, no orphans, BM25 scores equal to a
      fresh build, and working hybrid retrieval; (5) the B2 behaviour.

## Phase 5: Docs

- [x] `CLAUDE.md`: rewrite the ragnar-version paragraph under "One unreadable PDF…" (CI and users
      both run CRAN 0.4.0, one handler), the 0.3.1 foreign-key note under "An update chooses…"
      (keep the two statements, with the new rationale, G3), and the `progress` note. Then grep
      `0\.3\.[01]`, "development" and `Remotes: tidyverse/ragnar` across `R/`, tests, `research/`
      and `CLAUDE.md` (G2).
- [x] `NEWS.md` entry: supported ragnar, the call-time refusal, the manifest field, the measured store
      behaviour, and the warning that cred 0.7.0 or older with ragnar 0.3.x cannot ingest into a
      store once it has been upgraded or rebuilt under 0.4.0 (A4).

## Owed at the end (reported, done after merge)

- [ ] After the tagged release, comment on knowledge#223 that cred supports ragnar 0.4.0, and that
      anyone on cred 0.7.0 or older must update before the first upgraded or rebuilt store is
      pushed (O2, A4).
- [ ] File a follow-up cred issue: 0.4.0's NEWS says ingest "now prints document origins
      literally in progress messages". Check whether that is the fix that lets cred turn
      `progress` back on.
- [ ] File a follow-up cred issue: compact a store after an upgrading update (G4; probe in
      `findings.md`).
- [ ] Show the owner the upstream draft (findings.md, "HNSW metrics lost"): ragnar 0.4.0's upgrade
      drops the HNSW metrics. Fork issue first; nothing is posted without the owner's word.
- [ ] File a follow-up cred issue: use 0.4.0's `ingest_summary` in place of the `worker_errors`
      bookkeeping (S1).

## Validation

- [ ] Tests pass under ragnar 0.4.0 (`devtools::test()`), with no store-test skips caused by the
      ragnar version.
- [ ] Mutation check: lower the floor constant, or remove the version check, and the floor test
      fails; remove B2's peek and its test fails.
- [ ] `lintr::lint_package()` clean; `devtools::document()`; `devtools::check()` locally.
- [ ] CI on the PR installs ragnar 0.4.0 from CRAN (confirmed in the setup log) and passes.
- [ ] `/code-check branch` clean.
- [ ] PR body says the call-time refusal is what meets the issue's "refused with a message naming the
      version gap" for an old ragnar (AC3).
- [ ] PWF checkboxes match landed work; `/planning-archive`.
