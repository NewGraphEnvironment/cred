# Progress — crd_store_build(): an oversize chunk aborts the build; a NUL byte skips a paper (#35)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user
- Created branch `35-crd-store-build-an-oversize-chunk-aborts` off origin/main
- Scaffolded PWF baseline from issue #35 with approved phases
- Phase 1: 11 failing tests committed (bb33a35)
- Phase 2: prepare factory, ingest wrapper, crd_store_build() report (19f82ac); 9-row mutation table
- Plan review (Plan agent, spawned 16:07 UTC) returned B1: duplicate split ranges violate ragnar's
  chunks primary key; reproduced and fixed with G2/G3/G4/G7/A2/AC2/AC3 (6c4e5a5); 5-row mutation table
- Full suite after Phase 2: FAIL 0 | SKIP 2 | PASS 777
- Phase 3: live collection build 4.25 min, 4 docs, 2,838 chunks; timing parity with main (10.5 s)
- Next: Phase 4 docs and record
