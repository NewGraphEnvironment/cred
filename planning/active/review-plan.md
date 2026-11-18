# Plan review for #43 (Plan agent, spawned 2026-11-18T16:16Z, delivered by 16:23Z)

The reviewer read the plan, the issue, `R/store.R`, the store tests, the research notes, `CLAUDE.md`
and the ragnar 0.3.0 / 0.3.1 / 0.4.0 sources. Findings with verdicts. A verdict is "confirmed" only
where a probe reproduced it; probes are in `findings.md`.

## Blockers

- **B1. Phase 4's "an update's result has a new md5 even when only the upgrade changed" is false.**
  `crd_store_update()` returns before copying when there is nothing to do (`R/store.R:2445-2448`)
  and discards the copy when nothing changed (2497-2504), so an old store stays un-upgraded until an
  update makes a real change. **Confirmed by reading; folded:** Phase 4 doc text rewritten, and
  research/ragnar-versions.md already says this.
- **B2. `crd_store_connect(read_only = FALSE)` verifies the file and then changes it.** The upgrade
  rewrites the verified local copy, so the next verified connect downloads it again, and a
  read-write open upgrades it again. **Confirmed by probe:** under ragnar 0.3.0.9000 a read-write
  open that writes nothing leaves the md5 unchanged. Under 0.4.0 the first one upgrades the file
  (md5 changes, size about 1.85x), and opens after that are stable. **Decision for the owner**
  (refuse or warn); the check goes in `.crd_store_open()`, before `ragnar_store_connect()`, through a
  plain DBI read-only peek that is disconnected first.

## Assumptions

- **A0. `ragnar_version` taken from the pushing session describes the pusher, not the store.** This
  goes against the package's rule that manifest values come from the store (`R/store.R:2715-2723`,
  2776). It also crashes a push on a machine without ragnar (`crd_store_push()` needs only
  DBI/duckdb). **Confirmed by reading; decision for the owner:** stamp the version into the store at
  build and update (a cred-owned table), read it in `.crd_store_describe()`, record a store-derived
  format, and fall back to the session's version with a warning (NA when ragnar is absent).
- **A1. duckdb is held fixed, and real shared stores are not in the matrix.** **Folded:** 0.3.0.9000
  was already a builder in the run. Two real old-format stores (28.6 MB and 94.6 MB, built under
  0.3.x / duckdb 1.5.x) were probed under 0.4.0. Varying duckdb is out of scope: ragnar 0.4.0
  requires duckdb >= 1.5.0, and every store here was written by 1.5.x.
- **A2. The offline embedder cannot test a stored `embed_func`.** **Folded:** the real stores' stored
  embedder (`ragnar::embed_ollama(x = x, model = "nomic-embed-text")`) runs under 0.4.0 against live
  Ollama, width 768.
- **A3. The script never reopens the index the upgrade recreated.** **Folded:** a read-write open
  with no writes and no CHECKPOINT on a real store, then a read-only reopen, gives the same hybrid
  chunks and the same BM25 chunks and scores. No `.wal` is left. Toy stores are too small for HNSW
  recall loss to show; the real stores are not.
- **A4. Old cred with ragnar 0.3.x fails ingest on a store once it has been upgraded.** **Confirmed
  by the matrix** (`Binder Error ... "excluded" has 3 columns available but 6`). **Folded:** NEWS
  entry and an "Owed" item to announce it before the first upgraded store is pushed.
- **A5. Check cred's own read paths read-only on an old store.** **Folded** into Phase 4's
  regression cases.

## Gaps

- **G1.** `test-store-update.R:72`, `:105` also carry the 0.3.0 guard. **Folded.**
- **G2.** Phase 5's grep is too narrow (`R/store.R:387`, `:796`, `2471-2475`, roxygen at 1696 and
  1868-1880, `research/README.md`, `research/ollama-embedding-context.md`). **Folded:** grep
  `0\.3\.[01]` and "development".
- **G3.** The two-statement delete still works on an upgraded store, and under the floor the copy is
  always upgraded before the deletes. **Folded:** keep it, and rewrite the rationale.
- **G4.** The first update of an old store rebuilds the HNSW indexes twice and grows the file.
  **Confirmed by probe:** 1.85x after the upgrade alone. `COPY FROM DATABASE` into a fresh file brings
  it back to 27.8 MB with its 3 HNSW indexes, and it retrieves. **Not folded:** compaction is new
  behaviour, so it is filed as a follow-up issue.
- **G5.** A format refusal would also be needed in `crd_store_update()`. **Moot:** Phase 1 found no
  format a 0.4.0 ragnar cannot use. B2 is handled in `.crd_store_open()`; the update works on a copy.
- **G6.** A recipe for a hand-built pre-0.4.0 fixture (the foreign key recreated verbatim, all three
  columns absent, a premise test, never cached). **Folded.**
- **G7.** With the 0.3.0 branch gone, `cred_ingest_skip` has no handler consumer, and the 0.4.0 path
  muffles every worker error that carries a path. **Folded:** keep the class (`prepare`'s tests
  assert it, and its note carries the reason), and document the muffling in the roxygen.
- **G8.** Check the floor with `getNamespaceVersion()` after `requireNamespace()`, through a cred-side
  version-reader seam that tests mock. **Folded.**

## Ordering, acceptance, scope

- **O1.** Phase 3's source for the field waits on A0. **Folded:** Phase 3 runs after the answer.
- **O2.** Comment on knowledge#223 after the tagged release. **Folded.**
- **AC1.** Restoring the 0.3.0 branch cannot fail a test under the floor. **Folded:** dropped; the
  floor mutation uses a hard-coded version below the floor.
- **AC2.** Spell out the regression cases. **Folded** into Phase 4.
- **AC3.** Say in the PR that the call-time refusal is what meets "refused with a message naming the
  version gap". **Folded** into Validation.
- **S1.** `ingest_summary` could replace the `worker_errors` bookkeeping. **Not folded:** follow-up.
- **S2.** A refusal message naming the installed ragnar version is moot under the floor. **Moot**
  (G5).

## Files the plan names

DESCRIPTION
R/store.R
tests/testthat/helper-store.R
tests/testthat/test-store-build.R
tests/testthat/test-store-update.R
tests/testthat/test-store-push.R
tests/testthat/test-store-embed-check.R
tests/testthat/test-store.R
data-raw/ragnar_store_compat.R
research/ragnar-versions.md
research/ragnar-store-update.md
research/ollama-embedding-context.md
research/README.md
CLAUDE.md
NEWS.md
