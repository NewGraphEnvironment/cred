# Progress — No connect-time embedding-model check (#30)

## Session 2026-10-08

- Plan-mode exploration of `R/store.R` (1766 lines), `helper-store.R`, `test-store*.R`
- Two forks put to the user at the plan gate, both answered: error on a confirmed width
  mismatch (with `check_model = FALSE` escape), live probe on by default
- Created branch `30-no-connect-time-embedding-model-check-cr` off main
- Scaffolded PWF baseline from issue #30 with approved phases
- Next: Phase 1 — factor the per-reason remedy out of the fallback message

### Phase 1 — shared remedy builder

- `.crd_embed_remedy(reason, cond, store)` now holds the per-reason body;
  `.crd_retrieval_fallback_msg()` is head + remedy
- Purity measured, not assumed: sourced `HEAD:R/store.R` into an env parented on the loaded
  namespace and compared both builders across 5 reasons x 4 causes x 2 stores (NULL and a real
  16-wide ragnar store) = 40 combinations. **IDENTICAL** on all 40, including a hostile
  `model "with ; semicolon"` cause
- `test-store-fallback.R:634` drift guard retargeted at `.crd_embed_remedy` — it parses the
  function holding the branches, so moving them moved its subject. Gained an assertion that the
  wrapper still routes through the shared builder, so retargeting cannot keep the guard green
  while the message grows a private copy of the branches
- Next: Phase 2 — `.crd_ollama_check()` on the shared remedy
