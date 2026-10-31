# Plan review — #35 (Plan agent, delivered 2026-10-31)

Read-only Plan subagent, briefed with the plan, the issue and the ragnar 0.3.0 internals. It
returned the review as reply text; this is the record, condensed. Disposition of each finding
is in `findings.md`, "Plan review disposition".

## Blocker
- **B1** Split ranges of adjacent refused chunks collide; ragnar's v2 `chunks` table has
  `PRIMARY KEY (doc_id, start, "end")`, so `ragnar_store_update()` fails in the main process
  and the ingest aborts. Repro: prose + 4,000 `•` + prose, embed refusing > 700 characters.
- **B2** The plan says the per-document skips are muffled "warnings"; they arrive error-classed
  (ragnar `warning(cond)` keeps the class), so only an `error =` calling handler sees them.
  The code is right; the plan text is not.

## Gaps
- **G1** Plan does not say a refused input is found within its batch of ten by bisection.
- **G2** Worker retries are off (`ragnar.embed.req_retry = FALSE`): a 429/503 there returns
  unsplit chunks, the main re-embed then meets the 400 and aborts.
- **G3** Every 400 is treated as the input's: an unrelated 400 splits every chunk to the floor.
- **G4** Notes from earlier batches stay in the log when a later batch hits a non-400 error and
  `prepare` returns the unsplit chunks; buffer and write on the success path.
- **G5** A crashed worker loses a document with a plain warning, no `cred_ingest_skip`; the
  `documents` table as ground truth (`unsaid`) catches it — say so.
- **G6** Plan signatures lag the code (`read`, `progress`; default reader re-parented).
- **G7** `table(split$origin)` counts halvings, not chunks; `who()` names only the first key
  when one file sits under two keys.

## Assumptions / scope / acceptance
- **A2** With markitdown missing, every document falls back to pdftools silently: say so when
  all were.
- **AC1** The e2e test cannot prove `prepare` is free of cred: under R CMD check the workers
  load the code under test. The structure test is the guard; an explicit `cred:::` would pass it.
- **AC2** `embeddings` count == `chunks` count always holds (`chunks` is a view on it).
- **AC3** The floor test's marker can be cut by halving; refuse a single rare glyph instead.
- **AC4** No timing baseline for the live build.
- R CMD check: mirai daemons start under check because testthat sets `R_TESTS = ""`.
