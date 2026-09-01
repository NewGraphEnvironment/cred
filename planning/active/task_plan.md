# Task: `crd_store_push()` — merge-on-write manifest updates (#24)

## Context

`crd_store_connect()` (v0.2.0) reads and verifies a shared store against the `log.json` manifest.
Nothing in cred writes that manifest, and **no committed implementation writes it correctly
anywhere**. The only working merge-on-write push was a one-off script, deliberately never committed
because it carried the bucket path. The committed implementation,
`fish_passage_template_reporting/scripts/04_planning/0157-rag-sync.R`, rebuilds the manifest from
the current run alone and overwrites the remote copy — so pushing store B silently drops store A,
and `pull` then reports `skip A (not in log.json)` for a file sitting in the bucket.

This issue exists partly to break a deferral loop: cred#22 scoped push out to rtj#194, which named
cred#22 as the durable home. Both bodies were corrected on 2026-08-31 — cred owns the manifest
read/write code, rtj#194 owns bucket, IAM and field access.

An unreadable manifest is worse than no manifest, because the artifacts still look present.

## Constraints (settled with the user)

| Decision | Choice |
|---|---|
| Manifest confirmed absent | **Refuse**; `create_manifest = TRUE` opts in |
| Concurrent push | **ETag compare-and-swap** via `--if-match`; 412 → re-read, re-merge, retry |
| Embedding-model mismatch | **Warn**; `allow_model_mismatch = TRUE` overrides |

## Findings that shape the work — all verified from R against the live bucket

1. **`aws s3 cp` cannot distinguish "no manifest" from "wrong bucket".** A missing key and a
   nonexistent bucket both return exit 1 and the identical text
   `fatal error: An error occurred (404) ... Key "..." does not exist`. Inferring absence from `cp`
   would let a typo in `cred.store_source` look like a legitimate first push.
2. **A two-step probe does discriminate.** `s3api head-bucket` → exit 0 reachable / 254 not;
   `s3api head-object` → exit 0 present / 254 absent. *Bucket reachable AND object absent* is a
   confirmed absence. Prefixes are not objects in S3, so there is nothing else to validate — which
   is exactly why `create_manifest` stays an explicit flag.
3. **`.crd_aws()` currently discards the exit status** (`R/store.R:65`) — it returns
   `system2(..., stdout = TRUE)` without the `status` attribute reaching callers by contract.
   Verified that `attr(result, "status")` does carry it (254 on a missing key) and that the
   stderr text is captured (2 lines, containing `404 ... Not Found`). Round 1 of the #22 review
   flagged this as "not load-bearing here" — it becomes load-bearing now.
4. **Conditional writes are available.** `aws-cli 2.34.34` supports `put-object --if-match`, and
   `head-object --query ETag` returns `"461c47ccbc3f666a883af61e214d5f91"` (quotes included, pass
   verbatim). So the lost-update race is genuinely closeable rather than merely documentable.
5. **The manifest is inconsistently typed** — `built_by` is a bare string for `vca_refs`, an array
   for `fraser`. `.crd_manifest_entry()` already normalises on read; the writer must not regress
   entries it did not touch.
6. **Provenance is already per-store** in the live manifest (`repo`, `branch`, `head_sha`,
   `built_by`, `date_completed` inside each entry). The top-level `generating_script` still says
   `"cred#22 pending"` and should become this function.
7. `jsonlite` is already in `Imports`; no new dependency is needed.

## Phase 1 — Exit-status plumbing and S3 probes

- [ ] Change `.crd_aws()` to return a list `list(out =, status =)` rather than a bare character
      vector, so callers can branch on the exit code. Update its two existing callers
      (`.crd_manifest_read()`, `crd_store_connect()`) — they only `paste()` the output into error
      messages, so the change is mechanical
- [ ] `.crd_s3_head_bucket(source, profile)` → logical; distinguishes reachable from not
- [ ] `.crd_s3_head_object(source, key, profile)` → `list(exists =, etag =)`
- [ ] `.crd_s3_put(path, source, key, profile, if_match = NULL)` → wraps
      `s3api put-object`, returning status so a 412 is detectable
- [ ] Tests: exit-status propagation and 404-vs-unreachable classification, using a stub command
      rather than the network

## Phase 2 — Describe and merge (the pure core)

- [ ] `.crd_store_describe(store_path, model)` — `documents`/`chunks` counts (from the correct
      tables per #22 finding 3), `embedding_size`, `embedding_model`, `store_name`, `bytes`,
      `md5` (lowercased), plus git provenance: `repo` parsed from `git remote get-url origin`,
      `branch`, `head_sha`, `built_by`, `date_completed`
- [ ] `.crd_manifest_merge(existing, name, entry)` — **pure, no I/O; the piece to test hardest.**
      Returns the union with `entry` replacing only `stores[[name]]`, every other entry byte-identical
- [ ] Tests: merging B into a manifest holding A yields both; a string `built_by` and an array
      `built_by` both survive untouched when they are not the target; replacing an existing entry
      updates only that key; top-level fields other than `stores` and `date_updated` are preserved

## Phase 3 — `crd_store_push()`

- [ ] `crd_store_push(store_path, source = getOption("cred.store_source"), name = NULL, profile, dry_run = FALSE, create_manifest = FALSE, allow_model_mismatch = FALSE, max_retries = 3L)`
- [ ] Order of operations, chosen so nothing destructive happens before every check has passed:
      1. Resolve source (`.crd_store_source()`), guard packages (`.crd_need()`)
      2. `head-bucket` — unreachable is a hard stop, never treated as absence
      3. `head-object` on `log.json` — capture ETag; absent + no `create_manifest` → refuse,
         naming both the option and the possibility of a wrong prefix
      4. Describe the local store; compare `embedding_model` against existing entries → warn or
         stop per `allow_model_mismatch`
      5. `dry_run` → print the merged manifest and the intended keys, upload nothing, return early
      6. Upload the `.duckdb`, then re-read + re-merge + `put-object --if-match <etag>`
      7. On 412, re-read and retry up to `max_retries`, then fail naming the concurrent writer
- [ ] Set the manifest's top-level `generating_script` to `cred::crd_store_push()`
- [ ] Refuse to push when a sibling `.wal` exists — a store with an unflushed WAL has an md5 that
      does not describe what a puller will open
- [ ] Verify the pushed entry is one `crd_store_connect()` accepts, without a re-download

## Phase 4 — Tests, docs, hygiene

- [ ] All new tests offline: no network, no S3, no Ollama. Stub `.crd_aws()` with
      `testthat::local_mocked_bindings()` to drive the status codes
- [ ] `\dontrun{}` examples per repo convention; no bucket address in source, docs or tests —
      shape `s3://<bucket>/<prefix>/` only
- [ ] `devtools::document()`; `lintr::lint_package()` must be 0
- [ ] `CLAUDE.md`: add `crd_store_push()` to the `R/store.R` architecture line, and a design
      decision recording read-merge-write plus fail-toward-not-clobbering
- [ ] `NEWS.md` + version bump handled at merge by `/gh-pr-merge`

## Explicitly out of scope

- **Bucket policy, IAM, retention, the field runbook** — rtj#194
- **Retiring `0157-rag-sync.R`** — lives in `fish_passage_template_reporting`; follow-up there
  once this ships
- **Pruning manifest entries for deleted stores** — deletion is not push's job

## Validation

- [ ] `devtools::test()` passes
- [ ] `/code-check` clean on each commit
- [ ] `lintr::lint_package()` reports 0 lints
- [ ] PWF checkboxes match landed work
- [ ] Acceptance: pushing `vca_refs` leaves `fraser` intact in the manifest — the exact
      regression `0157-rag-sync.R` causes
- [ ] `/planning-archive` on completion
