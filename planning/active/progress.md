# Progress — crd_store_update() leaves freed blocks in the store: 32 to 76 % of an updated file is free space (#48)

## Session 2026-11-26

- Plan-mode exploration — phases approved by user
- Created branch `48-crd-store-update-leaves-freed-blocks-in` off origin/main
- Scaffolded PWF baseline from issue #48 with approved phases
- Next: start Phase 1

## Phases 1-3, 2026-11-26 (Vancouver) / 2026-11-27 UTC

- Phase 1: toy fixture separates (updated 27 blocks / 8 free vs fresh 19 / 0); drop + `COPY FROM DATABASE` +
  `build_index` reproduces the fresh build exactly (findings).
- Plan review returned; 11 of 13 findings folded into the plan, 1 not applicable, 1 disproved by Phase 1
  (`review-plan.md`).
- Phase 2: tests for free-space parity, object parity, sequences surviving, and failed compaction. Red on
  main: the free-space test (2 failures) and the pre-0.4.0 free-space assertion.
- Phase 3: `.crd_store_drop_indexes()` before ragnar's read-write connect, ingest with `build_index = FALSE`,
  `.crd_store_compact()`, renamed into place. A mock of `ragnar_store_ingest` in `test-store-build.R` lacked
  `build_index`; it now takes it and asserts its arguments against the real function's. Full suite: 324,
  0 failed, 2 skipped; 0 lints.
- Commits: fe9259c (tests), and the Phase 3 commit.
- Next: Phase 4, a real-store measurement.
