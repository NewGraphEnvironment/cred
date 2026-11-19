# Review: CI fix round 1 (commit 9c6f403)

## Checklist read

- code-check.md, `## Mechanisms`: the prose of "A guard that fails toward pass", "A fixture that cannot reach the failure mode" (and its table), "Verification that reads its own output" and "Restore the bug and prove the guard fires".
- code-check-r.md: the index lines on testthat, duckdb and DBI (nothing in this diff matches a tool-specific trap beyond those).
- code-check-shell.md and code-check-spatial.md: nothing in this diff uses a tool they cover.

## What was measured

All runs used `pkgload::load_all()` of the commit and the shipped helpers. The probe script is `rv/t.R` in the session scratchpad.

1. **How each duckdb records the index SQL.** I created an HNSW index `WITH (metric = 'cosine')` under each version and read `duckdb_indexes().sql`:
   - created under 1.5.6, read under 1.5.6: no clause;
   - created under 1.5.6, read under 2.0.0: no clause;
   - created under 2.0.0: `WITH (metric = 'cosine' )`.
   So the record is fixed when the index is created, as the docs now say.
2. **Can the new assertion still catch the defect?** I ran the new test body on `local_pre040_store()`, once as shipped and once with a simulated ragnar fix (`ragnar_store_build_index()` after the read-write connect):
   - duckdb 1.5.6, as shipped: recorded FALSE, cosine afterwards FALSE, **PASS**.
   - duckdb 1.5.6, simulated fix: recorded FALSE, cosine afterwards TRUE, **FAIL**. The assertion still fires on the defect where the fixture can reach it.
   - duckdb 2.0.0, as shipped: recorded TRUE, cosine afterwards TRUE, PASS.
   - duckdb 2.0.0, simulated fix: TRUE, TRUE, PASS. The defect cannot be reached here, as the comment says.

   It is not a tautology on 2.0. The expected value comes from the SQL recorded before the upgrade, and the actual value from an EXPLAIN plan after it. An upgrade that dropped or broke the cosine index would still turn it red.
3. **Which duckdb wrote the real stores.** The headers of the real stores (knowledge-stats `pine.duckdb` and `statistics.duckdb`) read `v1.4.3`, not 1.5.x.

Every other changed sentence is true on both duckdb versions: the NEWS line, the warning text, the `crd_store_connect` read_only docs, the store.R roxygen ("as in every such store measured"), the `crd_store_update()` comment, and the research paragraph ("every store ... that we hold").

## Findings

- **[severity: fragile]** CLAUDE.md:356 ("(every real pre-0.4.0 store)") and tests/testthat/test-store.R:289-290 and :298 ("A real pre-0.4.0 store's indexes were made under duckdb 1.5.x"; "as in every real old store"). These are absolutes about stores nobody measured. Two real stores were measured.
  - Dates from the installed packages: duckdb 2.0.0 was published 2026-10-23 and ragnar 0.4.0 on 2026-11-10. In that window, ragnar 0.3.x on duckdb 2.0.0 writes a pre-0.4.0 store whose index SQL records its metric. ragnar 0.4.0 declares `duckdb (>= 1.5.0)` with no upper bound. I did not verify 0.3.x's bound because no 0.3.x install was at hand.
  - ragnar 0.4.0's upgrade would keep the metric on such a store. "Every real pre-0.4.0 store" is therefore not established.
  - The test comment's "made under duckdb 1.5.x" is also wrong for the stores it generalizes from: their headers say v1.4.3. The 1.5.x measurement came from the fixture and the probe, not from a real store.
  - Why it matters: CLAUDE.md is read as authoritative in this repo ("Grep the sentence, not the instance"). The user-facing text is already hedged ("can", "may", "as in every such store measured"), so only these sentences overstate. Fix: write "every pre-0.4.0 store measured (duckdb 1.4.3)", or drop the parenthetical. The "before 2.0" boundary itself rests on 1.4.3 (real stores) and 1.5.6 (measured); 1.0-1.3 are untested.
  - **Rule:** code-check.md, "A fixture that cannot reach the failure mode" (a fixture's or sample's behaviour stated as a fact about the population); none more specific.

- **[severity: fragile]** research/ragnar-versions.md:3-8. The provenance line still says "duckdb 1.5.6", but the file now reports a duckdb 2.0.0 measurement (the pine copy upgraded under 2.0.0, and the fixture under 2.0.0). It also does not say which duckdb built the real stores (1.4.3), which is the fact the "before 2.0" claim rests on. A reader re-deriving the claim from the header would not know a second duckdb was involved.
  - **Rule:** none (planning.md, "The header is the provenance, in prose", is the nearest convention, but it is not in the checklist files).

No bug in the code or the assertion: the test discriminates on duckdb 1.5.x and is not vacuous on 2.0.
