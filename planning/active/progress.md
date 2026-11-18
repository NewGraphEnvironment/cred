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
