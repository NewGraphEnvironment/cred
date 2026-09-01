# Progress — crd_store_push(): merge-on-write manifest updates (#24)

## Session 2026-08-31

- Plan-mode exploration — 7 findings recorded in `findings.md`, phases approved by user
- Three design decisions settled: refuse on absent manifest, ETag compare-and-swap, warn on
  embedding-model mismatch
- Created branch `24-crd-store-push-merge-on-write-manifest-u` off main
- Scaffolded PWF baseline from issue #24 with approved phases
- Next: Phase 1 — exit-status plumbing and S3 probes
