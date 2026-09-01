# Findings — crd_store_push(): merge-on-write manifest updates (#24)

## Verified during plan-mode exploration (2026-08-31)

All checks run from R against the live bucket, aws-cli 2.34.34.

| # | Finding | Evidence |
|---|---------|----------|
| 1 | `aws s3 cp` cannot tell a missing key from a nonexistent bucket — both exit 1 with identical `404 ... Key "..." does not exist` text | probed both cases |
| 2 | `s3api head-bucket` + `head-object` DO discriminate: exit 0 vs 254 | reachable bucket + absent key = confirmed absence |
| 3 | `.crd_aws()` discards the exit status (`R/store.R:65`); `attr(r, "status")` does carry it | 254 on missing key, stderr text captured |
| 4 | `put-object --if-match` is supported; `head-object --query ETag` returns the ETag with quotes | `"461c47ccbc3f666a883af61e214d5f91"` |
| 5 | Manifest `built_by` is a string for one store, an array for another | writer must not regress untouched entries |
| 6 | Provenance is already per-store in the live manifest; top-level `generating_script` still says `"cred#22 pending"` | should become `cred::crd_store_push()` |
| 7 | `jsonlite` already in Imports — no new dependency | `DESCRIPTION` |

## Decisions taken (user-approved)

- **Manifest confirmed absent → refuse**, `create_manifest = TRUE` opts in. A wrong prefix in
  `cred.store_source` produces the same 404 as a genuine first push, and prefixes are not objects
  in S3 so there is nothing else to validate.
- **Concurrent push → ETag compare-and-swap** with `--if-match`; a 412 triggers re-read, re-merge
  and a bounded retry.
- **Embedding-model mismatch → warn**, `allow_model_mismatch = TRUE` overrides. A deliberate model
  migration must stay possible.

## Ownership context

cred#22 scoped push out to rtj#194; rtj#194 named cred#22 as the durable home. Neither owned it.
Both bodies corrected 2026-08-31: cred owns the manifest read/write code (this issue), rtj#194 owns
bucket, IAM and field access. The defect in `0157-rag-sync.R` is live until this lands.

## Issue context

## Problem

`crd_store_connect()` (v0.2.0) reads and verifies a shared store against the `log.json` manifest.
Nothing in cred writes that manifest, and **no committed implementation writes it correctly anywhere.**

The only working merge-on-write push was a one-off script, deliberately not committed because it
carried the bucket path. The committed implementation —
`fish_passage_template_reporting/scripts/04_planning/0157-rag-sync.R` — has a live defect:

```r
log <- list(..., stores = entries)   # entries = THIS RUN ONLY
aws("s3 cp", shQuote(lp), paste0(BUCKET, "/log.json"))   # replaces the remote manifest
```

Pushing store B silently drops store A's entry. `pull` then reports `skip A (not in log.json)` for a
file sitting in the bucket. Observed in practice when the second store was added.

An unreadable manifest is worse than no manifest, because the artifacts still look present.

### Ownership — this issue exists to break a deferral loop

cred#22 scoped push out, deferring to NewGraphEnvironment/rtj#194. rtj#194 names cred#22 as the
durable home. Both are now settled: **cred owns the manifest read/write code; rtj#194 owns the
bucket, IAM, field access and the runbook.** This issue is cred's half.

## The contract

The manifest is a single file describing **every** store in the bucket. Therefore:

1. **Read-merge-write.** Fetch the existing manifest, merge this run's entries into it, write the
   union back. Never construct the manifest from the current run alone.
2. **Abort if the existing manifest cannot be read.** Fail toward not-clobbering. A network blip
   must not be indistinguishable from an empty bucket. The only case where writing a fresh manifest
   is legitimate is a confirmed 404, and even then it should require an explicit flag.
3. **Provenance per store, not per file.** `repo`, `branch`, `head_sha`, `built_by`,
   `date_completed`, `md5`, `bytes`, `documents`, `chunks` live *inside* each entry — a top-level
   `repo` becomes false the moment the manifest holds a store built elsewhere. The remote manifest
   is already in this shape.
4. **Tolerate the shapes already out there.** `built_by` is a bare string for one store and an array
   for another. `cred:::.crd_manifest_entry()` already normalises this; the writer must not
   regress entries it did not touch.
5. **Never write a store the reader would reject.** The pushed entry's md5 must be computed from
   the uploaded file, and `crd_store_connect()` must accept it immediately afterward.

## What already exists

Shipped in v0.2.0 and directly reusable — the read half is done and tested:

- `.crd_manifest_read(source, profile)` — fetch + parse, `simplifyVector = FALSE`
- `.crd_manifest_entry(manifest, name)` — per-store extraction, `built_by` normalisation,
  missing-md5 guard, md5 lowercasing
- `.crd_aws(args, profile)` — `aws` CLI shell-out with every argument `shQuote()`d
- `.crd_store_source(source)` — option/env resolution, no default, rejects `NA` and non-scalars

## Proposed scope

- `crd_store_push(store_path, source, ..., profile, dry_run = FALSE)`
- `.crd_manifest_merge(existing, entries)` — pure, unit-testable, the piece worth testing hardest
- `.crd_store_describe(store_path)` — counts, embedding model/size, bytes, md5, git provenance
- `dry_run` prints the merged manifest without uploading

Out of scope: bucket policy, IAM, retention, the field runbook — all rtj#194.

## Acceptance

- [ ] Pushing store B into a manifest holding store A yields a manifest with **both**
- [ ] A manifest that cannot be read aborts the push, and the remote is left untouched
- [ ] `built_by` as string and as array both survive a round trip untouched when not the push target
- [ ] `crd_store_connect()` accepts the just-pushed store without a re-download
- [ ] Unit tests cover the merge with no network, S3 or Ollama
- [ ] No bucket address in source, docs or tests — shape `s3://<bucket>/<prefix>/` only

## Related

- Relates to NewGraphEnvironment/rtj#194 (bucket, IAM, field access, runbook)
- Follows #22 (build + store resolution, shipped in v0.2.0)
- The defect lives in `fish_passage_template_reporting/scripts/04_planning/0157-rag-sync.R`,
  which this should retire

