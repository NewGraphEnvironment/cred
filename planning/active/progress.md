# Progress — crd_store_push(): merge-on-write manifest updates (#24)

## Session 2026-08-31

- Plan-mode exploration — 7 findings recorded in `findings.md`, phases approved by user
- Three design decisions settled: refuse on absent manifest, ETag compare-and-swap, warn on
  embedding-model mismatch
- Created branch `24-crd-store-push-merge-on-write-manifest-u` off main
- Scaffolded PWF baseline from issue #24 with approved phases
- Next: Phase 1 — exit-status plumbing and S3 probes
- Implemented all four phases; `crd_store_push()` exported
- `/code-check` round 1 — 10 findings, all real (4 bugs): ETag parsed from a stderr-merged stream;
  retry could downgrade to an unconditional write; create path had no precondition; jsonlite
  rendered `NA_integer_` as the string `"NA"`; unanchored 412; 5 GB single-PUT cap; binary/manifest
  window; model guard read the environment; a test asserted the runner's cwd is a git worktree;
  dry-run preview not byte-faithful. All fixed and verified
- `/code-check` round 2 — the sharpest finding of the session: fix #8 *could not fire*.
  nomic-embed-text and embeddinggemma are both 768-dimensional, and nothing in the package ever
  sets `CRED_EMBED_MODEL`, so the guard compared a default against itself. Ground truth was one
  column away in `metadata.embed_func`, a serialized closure. Now read from the artifact
- Self-caught while verifying that fix: it introduced a false positive, since the manifest records
  `nomic-embed-text (ollama)` and the store records `nomic-embed-text`. Normalised the comparison
- 250 tests passing, 0 lints; dry run against the live manifest keeps `fraser` intact
