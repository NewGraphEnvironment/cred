# Code-check round 3 for the dev-ragnar fix (c0fd677), #35

Reviewed 2026-10-31 against ragnar 0.3.0 (default library) and ragnar 0.3.1.9000 at
`06f7c3e` (scratch `devlib`). All runs were in copies of the repo; nothing in the tree was
changed apart from this file.

## Checklist read

- **code-check-r.md**: read in full: "Tests that silently do not run"; "A `skip_if_not()` skips only its own `test_that()` block"; "Reproducibility"; "Under `R CMD check`, tests run from a temp dir against the INSTALLED package"; "A library call that dispatches on a global option is not a pure function"; "Two repos pinning the same remote at different tags is an unsolvable install"; "Never name a durable artifact by a hash the library reserves the right to change"; "`tryCatch(warning = )` DISCARDS the value the expression produced"; "Do not abort inside a handler for a warning raised from C++; note it and abort after the call returns"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"; "`cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation"; "`[[` on a named ATOMIC vector with an absent key is an error, not `NULL`"; "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared"; "duckdb in R: the query that autoloads `icu` binds unreliably, so `LOAD icu` before it"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one". 16 read, 99 not read (index only).
- **code-check-shell.md**: 0 read in full. The diff contains no shell. 70 not read (index only).
- **code-check-spatial.md**: 0 read in full. The diff contains no spatial code. 93 not read (index only).
- **code-check.md**: all 14 `## Mechanisms` H3s read in prose; also "Documentation Staleness" and "An assertion that matches an interpolated value cannot see the claim around it". 16 read, 21 not read.

## The mechanism

A claim about how a dependency behaves gets written from the one version installed on the
author's machine, or from memory, instead of being measured against every version the code
runs under. The fixtures and the local library all share one ragnar, so the suite cannot
reach the axis the claim depends on ("A fixture that cannot reach the failure mode": the
fixtures share the one property the bug depends on). A rule about a third party's behaviour
then works as a literal reasoned from that party's behaviour ("A guard's scope, escape
hatches, and remedies": read it from the artifact). The CI failure on PR #42 is one
instance: the handler matched ragnar 0.3.0's `warning(cond)` and CI ran 0.3.1.9000.

## Every ragnar behaviour the ingest path depends on, checked against both versions

Method: I serialised every object in both ragnar namespaces and diffed them. 27 functions
changed and 13 exist only in dev. Each one the ingest reaches is listed below. I also ran
`test-store-build.R` under both versions, and under ragnar 0.3.0 with mirai 2.7.3:
19/19 blocks passed in each, 0 failed, 0 errors.

| Dependency | 0.3.0 | 0.3.1.9000 | Verdict |
|---|---|---|---|
| How a failed worker is reported | `warning(cond)` with `class(cond) <- cond$condition.class`, so the error class is kept | `rlang::warn(class = "ragnar_ingest_worker_error", path = task$path)`, so the class is lost | Both handled. Mutation: with the new handler removed, the dev run of test 14 fails (1) and test 15 fails (2), and both pass with it. |
| The `condition.class` path under a newer mirai | mirai 2.6.1 | mirai 2.7.3 | ragnar 0.3.0 with mirai 2.7.3 passes 19/19, so the 0.3.0 branch does not depend on the mirai pin. |
| How `prepare`'s result is consumed | checked in the main process; a non-`MarkdownDocumentChunks` result `stop()`s | checked in the worker; a bad result becomes a worker-error warning | `prepare` returns `MarkdownDocumentChunks` or raises, so no difference reaches cred. |
| `fetch_last_modified` | absent | `file.mtime(origin)` in the worker, and NA when origin is not `path` | `origin == path` on every route (`read_as_markdown` is identical in both versions; the pdftools route sets `origin = path`). It only fills `documents.last_modified`. |
| Skipping unchanged content by hash | absent | `rlang::hash(as.character(document))` compared with the stored hash | A fresh store (overwrite or a new file) has no stored hash, so nothing is skipped in a `crd_store_build()`. Re-ingesting an existing store is #43. |
| `ingest_summary` | absent | an attribute on the returned store | cred ignores it; the `documents` table decides. Not a defect. |
| `ragnar_store_update_v2` with an `embedding` column | skips the main-process embed; `select(any_of(fields))` | same | Identical. Dev adds an early return that needs `is_unchanged` and inserts a document with zero chunks, but `prepare` never returns zero rows: it skips at zero, and `markdown_chunk` gives at least one row for 1-character and markup-only inputs in both versions. |
| `documents` columns cred queries | `doc_id, origin, text` | adds `last_modified, content_hash, ingested_at` | cred reads only `origin`. The `chunks` view is unchanged. |
| Worker retry options | workers set `ragnar.embed.req_retry = FALSE`; main process `max(3 * n_workers, 20)`, 180 s | same; `embed_req_retry` and `embed_ollama` are unchanged | `prepare`'s override works in both, and "the floor of 20" holds in both. |
| Default worker count | `max(min(max(cores, 4), n %/% 4, 8), 2)` | `max(2, min(cores or 4, n %/% 4, 8))` | These differ only on a machine with fewer than 4 cores. The minimum is 2 in both, and no cred claim depends on the count. |
| `build_index` default | TRUE | TRUE | Same. |
| `SET preserve_insertion_order = false` (dev create and connect) | no | yes | cred's ingest queries are order-free (`%in%`, `setdiff`, `setequal`). |
| `?::TIMESTAMPTZ` write (dev only) | no | yes, once per document | Works without icu loaded on duckdb 1.5.6, so it is not the icu autoload trap. |
| The `R_LIBS` claim in CLAUDE.md | | | Measured: a mirai daemon started under `R_LIBS=<devlib>` reports ragnar 0.3.1.9000. |

The prose added in this diff (the CLAUDE.md paragraph, the `.crd_store_ingest` roxygen and
the research file) agrees with the two sources and the measurements above.

## Findings

- **[severity: fragile]** R/store.R:1954 and R/store.R:2065 (outside the c0fd677 diff, but
  on the ingest path it reaches; the same in both ragnar versions). The roxygen says "One PDF
  never costs the build", but a PDF whose path contains `{...}` costs all of it.
  `crd_store_build()` calls `.crd_store_ingest()` with its default `progress = TRUE`. Both
  ragnar 0.3.0 and 0.3.1.9000 then run `cli::cli_alert_info(paste("ingested:", origin))`
  after storing each document. cli reads the braces as an expression, so `The {BC}
  report.txt` raises `Could not evaluate cli {} expression: BC`. That error ends
  `ragnar_store_ingest()`, and `crd_store_build()`'s `on.exit` then deletes the store.
  Reproduced end to end through `.crd_store_ingest(progress = TRUE)` under both versions
  (`ERROR: ! Could not evaluate cli {} expression: BC`). Exposure measured on this machine:
  0 of 2,547 PDFs under `~/Zotero/storage` have a brace in the filename. This is an upstream
  ragnar defect, so per `agent-operations.md` §4 it should be surfaced upstream, not
  silently worked around. Drafting a ragnar issue and correcting the roxygen claim (or
  naming the exception) are both available. `progress = FALSE` would avoid it, but it is a
  workaround.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a quantified
    claim, "never", not executed over its population)

Nothing else found. The fix itself (the `ragnar_ingest_worker_error` handler, the
`worker_errors` lookup for paths with no note, and test 15) is correct under both ragnar
versions and both mirai versions, and the mutation above shows it is needed.
