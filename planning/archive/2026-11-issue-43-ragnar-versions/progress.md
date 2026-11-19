# Progress — ragnar's development branch changes ingest errors and the v2 store format; CI tests it, users may run 0.3.0 (#43)

## Session 2026-11-18

- Plan-mode exploration — phases approved by user
- Created branch `43-ragnar-s-development-branch-changes-inge` off origin/main
- Scaffolded PWF baseline from issue #43 with approved phases
- Next: start Phase 1
- Plan review (Plan agent, spawned 16:16Z) delivered; findings and verdicts in `review-plan.md`,
  folded into `task_plan.md`. Owner answered A0 (stamp `ragnar_version` in the store) and B2 (warn,
  then open).
- Phase 1 done: scratch libraries for ragnar 0.3.0, 0.3.0.9000, 0.3.1 and 0.4.0; the
  4 x 4 x ro/rw matrix (`data-raw/ragnar_store_compat.R`); probes on two real stores. ragnar 0.4.0
  installed in the main (user) library. Verdict: `research/ragnar-versions.md`.
- Phase 2 done: `ragnar (>= 0.4.0)` in Suggests, Remote dropped; `.crd_need()` refuses an older
  ragnar (`cred_ragnar_too_old`) through `.crd_ragnar_version()`; the 0.3.0 handler branch removed.
  test-store.R 57 pass, test-store-build.R 80 pass. Mutations: lowering the floor constant and
  removing the check each fail one test (patching both the namespace and `package:cred`, since
  `load_all()` attaches copies the tests resolve against).
- Phase 3 done: `cred_ragnar` stamp written by build and update; `.crd_store_describe()` records
  `ragnar_version` (stamp, else session with a warning, else NA) and `store_schema`. Pre-0.4.0
  fixture `local_pre040_store()` added to helper-store.R. push 82, update 95, store 57 pass;
  a no-op stamp write fails 3 tests.
- Found while building the fixture: ragnar 0.4.0's upgrade recreates the HNSW indexes without
  their metric, so cosine and inner-product queries lose the index until
  `ragnar_store_build_index()`. Recorded in research and findings, with an upstream draft (not
  posted).
- Phase 4 done: `.crd_warn_upgrade()` warns (`cred_store_upgrade`) before a read-write open of a
  pre-0.4.0 store; `?crd_store_connect` and `?crd_store_update` say what the upgrade does. AC2's
  five cases tested on the hand-built fixture (store 69, update 110, push 82 pass); removing the
  warning fails its test. Two fixture defects found and fixed on the way: indexes recreated from
  `duckdb_indexes().sql` had no metric, and renaming a table that holds a foreign key leaves
  duckdb's reverse reference on the old name.
- Phase 5 done: CLAUDE.md (ingest handler paragraph, update skip and delete rationale, a new
  ragnar-version bullet), store.R delete comment, research notes swept for `0\.3\.[01]` and
  "development"; measured claims that name their release (store.R near 425 and 878, CLAUDE.md
  page and fallback bullets) kept as they are. NEWS under `# cred (development version)`, which
  /gh-pr-merge promotes. `devtools::document()` rewrote three man pages; lintr 0.
- `/code-check branch`, three rounds (reviewer files `review-round1..3.md`):
  | Round | Findings | Fixed | Accepted | Inside previous fix? |
  |---|---|---|---|---|
  | 1 | 2 (record-only update kept an upgraded copy without an index rebuild; CLAUDE.md bullet below the sync marker) | 2 | 0 | n/a |
  | 2 | 2 (fallback credited a pre-0.4.0 store to a 0.4.0 session; research put the hash skip before `prepare`) | 2 | 0 | n |
  | 3 | 2 (round 2's fix checked one direction only; a stamp test lacked a duckdb skip) | 2 | 0 | **y** |
  Ended on enumeration: `.crd_store_describe()` over every stamp x schema x session combination
  (12 cases, a table-driven test that fails against round 2's version), and `crd_store_update()`'s
  kept-copy paths: the three rebuild branches (`to_ingest > 0` via ragnar's `finish_ingest()`,
  checked in 0.4.0's source; `dropped > 0`; neither) cover every kept copy.
- Upstream: the HNSW metric draft is fork issue NewGraphEnvironment/ragnar#3 (`upstream-draft`,
  `upstream-held`); nothing sent. Follow-ups filed: cred#49 (progress), #50 (compaction),
  #51 (`ingest_summary`).
- Final run on 4b296eb: devtools::test() 965 pass, 0 fail, 2 skips (officer docx, pre-existing); R CMD check 0 errors, the 3 pre-existing WARNINGs, and a NOTE for an unreachable time server; lintr 0.
