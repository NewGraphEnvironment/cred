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
