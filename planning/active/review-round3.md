# Code-check round 3 — #43 branch (HEAD 22aff4c)

## Checklist read

- **code-check.md**: read the prose of all 14 H3s under `## Mechanisms` (tables skipped). Not read: 24 (the standalone, security and spreadsheet rules; nothing in the diff is in their area).
- **code-check-r.md**: read 10 — "duckdb refuses a parent delete in the transaction that deleted its children"; "`package_version()` errors on a pre-release version string"; "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising…"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package"; "`tryCatch()` nests its handlers…"; "`dbConnect(SQLite(), path)` CREATES the file…"; "`identical()` on two reader results tests the reader, not the file"; "A `data-raw/` script must load the source tree, not the installed package"; "`Rscript -e` supplies `--args` itself…". Not read: 112.
- **code-check-shell.md**: read 0, not read 72 (the diff has no shell code; data-raw's `system2()` is covered by the R entry).
- **code-check-spatial.md**: read 0, not read 94 (no spatial code).

## Findings

- **[severity: bug]** R/store.R:2945-2950 (`.crd_store_describe()`): the round-2 fix checks the schema against the session in one direction only. An unstamped store in the **0.4.0** schema, pushed from a session whose ragnar is **older than 0.4.0**, is recorded with that older version. A ragnar before 0.4.0 can't write that schema, so the recorded version is known to be wrong. It is the mirror of round-2 finding 3, and push is the one entry point built to run there: `crd_store_push()` calls `.crd_need(c("DBI", "duckdb"))` only, and test-store.R says push "must work on a machine with an old ragnar".
  - Reachable: a pre-0.4.0 store opened with `crd_store_connect(read_only = FALSE)` under 0.4.0 is upgraded but never stamped (only build and update stamp). It can also be built by cred 0.7.0 under a 0.4.0-era ragnar. Either store, pushed from a machine with ragnar 0.3.x, gets the wrong version.
  - Reproduced with `load_all()`: an unstamped store built by ragnar 0.4.0, with `.crd_ragnar_session_version` mocked to `"0.3.1"`, gives `store_schema: 0.4.0  ragnar_version: 0.3.1`. The warning reads "recording this session's ragnar 0.3.1, which may not be the one that built it", where in fact it cannot be.
  - Not covered: the test file mocks only `"9.9.9"` and `NA` against an unstamped 0.4.0 store, and runs the real 0.4.0 session against the pre-0.4.0 store. The case of a session older than 0.4.0 is never tried, so the suite stays green.
  - Suggested fix: record the session only when it agrees with the schema (pre-0.4.0 with a session < 0.4.0; 0.4.0 with a session >= 0.4.0), otherwise NA, with a message for each case. NEWS.md:119-120, `?crd_store_push` and the inline comment describe only the one direction and would need the same change. Caveat: a development ragnar labelled 0.3.1.9000 built after the freshness columns landed also writes the 0.4.0 schema. That argues for NA (unknown) over a guess, not for keeping the session.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "A fixture that cannot reach the failure mode"

- **[severity: fragile]** tests/testthat/test-store-push.R:490-497 ("the ragnar stamp reads NA on a store that has none…"): this test calls `DBI::dbConnect(duckdb::duckdb(), …)` with no `skip_if_not_installed("duckdb")`. Every other duckdb test in the file skips (lines 170, 184, 348, 367, 480). duckdb is in Suggests, so a check run without Suggests errors here instead of skipping.
  - **Rule:** none

## Mechanism and enumeration

**The mechanism.** A property that belongs to an *outcome* gets attached to the *cause* the fixtures happen to produce. So each fix covers the cell of the case grid that the fixtures reach, and nothing more.

- Round-2 finding 1: "the index must be rebuilt" belongs to *a copy opened read-write is kept*. It was attached to *work was done* (ingest or drop), so the record-only path was missed.
- Round-2 finding 3: the version recorded must agree with what the schema allows. That rule has two directions. The pre-0.4.0 fixture under the installed 0.4.0 ragnar reaches only "pre-0.4.0 schema × newer session", so that is the only direction coded. Under the 0.4.0 floor, the other cell (0.4.0 schema × older session) cannot be produced by any real test setup; only a mock reaches it. That cell is the finding above.
- Round-2 findings 2 and 4 are the same shape in prose. Each sentence was right for the case its author had in mind: a CLAUDE.md edit in the place an edit normally goes; "skips before `prepare`", which is true of the mtime skip and was applied to the hash skip too.

Where the mechanism reaches in this diff:

| Place | Outcome-keyed? | Holds? |
|---|---|---|
| `crd_store_update()` index rebuild | yes, every kept copy (table below) | holds |
| `crd_store_update()` stamp write | written on every kept copy (2660), before the rename | holds |
| `crd_store_build()` stamp | written after a complete ingest, in tryCatch | holds |
| `.crd_store_describe()` version fallback | keyed to one direction of the schema-vs-session rule | **does not hold** (finding) |
| `.crd_warn_upgrade()` | keyed to schema "pre-0.4.0" only; a session older than 0.4.0 can't reach it (`.crd_need` in `crd_store_connect` runs first); NA schema (unreadable, or a v1 store with no `documents`) leads to no warning and no upgrade by ragnar (v1 is never upgraded) | holds |
| Which read-write connects warn | `.crd_store_open` is the only read-write connect besides update's working copy (2609), which documents the upgrade in its help instead of warning | holds |
| The floor in three places (`.crd_ragnar_min`, `Suggests: ragnar (>= 0.4.0)`, `skip_if_not_installed("ragnar", "0.4.0")`) | all three say 0.4.0 today; test-store.R pins the constant to the literal | holds |
| The schema-boundary literal `"0.4.0"` (in `.crd_store_schema` and describe's `>= "0.4.0"`) | a fixed fact about ragnar (when `content_hash` arrived), separate from the floor, and correct to hardcode | holds |
| Doc claims on rebuilds (NEWS, CLAUDE.md, roxygen, research/ragnar-versions.md: "every update that changes something rebuilds the index", "upgrades only when it changes it") | checked against the path table below | hold |
| research/ragnar-store-update.md (mtime skip before `prepare`, hash compared after) | checked against 0.4.0 `prepare_ingest_paths()` (mtime, main process) and `do_ingest_remote_work()` (hash after `prepare`) | holds |

### Paths through `crd_store_update()`, from the read-write connect of the copy (R/store.R:2609) to return or rename

Facts from ragnar 0.4.0's source:
- `ragnar_store_connect(read_only = FALSE)` upgrades a pre-0.4.0 copy: `upgrade_v2_store`, which recreates the HNSW indexes without their metric.
- `ragnar_store_ingest()` with a non-empty `paths` always reaches `finish_ingest()`, which calls `ragnar_store_build_index()`. That holds when every worker fails, and when everything is skipped as unchanged.
- An error in the main-process embed or `ragnar_store_update()` raises before `finish_ingest()`.

| # | Path | Copy kept? | Index rebuilt on the kept copy? |
|---|---|---|---|
| 1 | dropped > 0, to_ingest > 0, ≥1 ingested, n_docs > 0 | kept, renamed | yes (finish_ingest) |
| 2 | dropped ≥ 0, to_ingest > 0, ingest raises (service down) | no: error, on.exit disconnects then unlinks the copy | n/a |
| 3 | dropped = 0, to_ingest > 0, 0 ingested, record unchanged (`same_rec(final)`) | no: discarded at 2644 ("Store is current") | n/a (it was rebuilt, then thrown away) |
| 4 | dropped = 0, to_ingest > 0, 0 ingested, record changed | kept | yes (finish_ingest runs even when every worker failed) |
| 5 | dropped > 0, to_ingest > 0, 0 ingested, n_docs > 0 | kept | yes (finish_ingest) |
| 6 | dropped > 0, to_ingest = 0, n_docs > 0 | kept | yes (2635) |
| 7 | dropped = 0, to_ingest = 0 (record only; reaching here implies `!same_rec`, so the 2644 discard can't fire) | kept | yes (the new block at 2656) |
| 8 | any path with n_docs = 0 after the changes | no: stop at 2641, copy unlinked | n/a |
| 9 | error in `.crd_sources_write`, `.crd_ragnar_stamp_write` or CHECKPOINT | no: error, copy unlinked, store unchanged | n/a |
| 10 | a `.wal` beside the copy after disconnect, or `file.rename()` FALSE | no: stop at 2669, copy unlinked | n/a |

(Before the copy: the early return at 2590 and every refusal in the read-only phase leave the store unopened read-write, so it is never upgraded.)

Every kept copy leaves with a rebuilt index.

### `.crd_store_describe()`: stamp × schema × session ragnar

"Session" is `.crd_ragnar_session_version()`: NA if ragnar isn't installed or won't load; otherwise the loaded namespace's version. A session older than 0.4.0 is reachable here, because push does not apply the floor.

| Stamp | Schema | Session ragnar | Records | Warns | Correct? |
|---|---|---|---|---|---|
| present | any | any | the stamp | no | yes. The stamp is written only by build/update under the floor, so it always pairs with the 0.4.0 schema |
| absent | 0.4.0 | not installed | NA | "none, since ragnar is not installed here" | yes |
| absent | 0.4.0 | ≥ 0.4.0 | the session's version | "may not be the one that built it" | plausible (it could have built or upgraded it) |
| absent | 0.4.0 | < 0.4.0 | **the session's version (e.g. 0.3.1)** | "may not be the one that built it" | **no**: that version can't produce this schema (finding) |
| absent | pre-0.4.0 | not installed | NA | "not installed" | yes |
| absent | pre-0.4.0 | ≥ 0.4.0 | NA | "older than 0.4.0 wrote it" | yes (round-2 fix) |
| absent | pre-0.4.0 | < 0.4.0 | the session's version | "may not be the one that built it" | plausible |
| absent | NA (no `documents`; a v1 store or not a ragnar store) | not installed / any version | NA / the session's version | "not installed" / "may not be" | no store cred builds can be here; not a defect of this branch |
