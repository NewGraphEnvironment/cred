# Review round 1 — `crd_store_push()` (R/store.R, test-store-push.R)

Reviewed against `soul/conventions/code-check.md`. Working tree at review time: 41 tests pass in
`test-store-push.R`, full suite green. Every claim below was executed, not reasoned about; the
verification command is given where it matters.

## Findings

### 1. **[bug]** `R/store.R:627` — the ETag is parsed out of a stream with stderr merged into it

`.crd_aws()` runs `system2(stdout = TRUE, stderr = TRUE)`, and `.crd_s3_head_object()` then does:

```r
etag <- trimws(paste(res$out, collapse = ""))
```

Every line of the combined stream is welded together and used as the ETag. Anything `aws` writes on
stderr while still exiting 0 — the urllib3/LibreSSL `NotOpenSSLWarning` that is routine on macOS,
IMDS credential-retry notices, the aws-cli v1 deprecation banner — is concatenated onto the value.

The consequence chain is the bad one: `--if-match "<etag><warning text>"` → PutObject returns
`PreconditionFailed` → `.crd_s3_precondition_failed()` is TRUE → three retries, each re-reading the
same poisoned value from the same probe → the run dies with *"Another process is pushing
concurrently"*, which is a false diagnosis, **after** the store binary has already overwritten the
live one (see #7). The guard reports a race that is not happening and hides a parse bug.

This is verbatim the `code-check.md` entry *"Merging stderr into stdout corrupts the stdout you are
parsing"*, including its note that it only shows up once the stream gets chatty — so it will pass
every test and every hand-run until the day a warning appears.

Fix: for probes whose stdout is parsed, send stderr to a file and keep stdout clean
(`err <- tempfile(); system2(cmd, args, stdout = TRUE, stderr = err)`), reading the file back only
to report a failure. Failing that, extract the ETag by shape (`grep('^"[^"]+"$', res$out)`) rather
than collapsing the whole stream.

### 2. **[bug]** `R/store.R:943-944` — the retry can silently downgrade the conditional write to an unconditional one

`.crd_s3_head_object()` returns `exists = FALSE` for **any** non-zero exit, not only a 404. At the
top of `crd_store_push()` that conflation is mitigated (head-bucket first, then `create_manifest`
required). Inside the retry loop nothing mitigates it:

```r
head <- .crd_s3_head_object(source, "log.json", profile = profile)
etag <- head$etag
...
res <- .crd_s3_put(tmp, source, "log.json", profile = profile,
                   if_match = if (head$exists) etag else NULL)   # NULL == unconditional
```

A transient head-object failure on the re-probe — throttle, 5xx, a credential refresh landing
mid-run — sets `head$exists <- FALSE`, and the *next* iteration writes `log.json` with no
precondition, clobbering exactly the concurrent manifest the compare-and-swap exists to protect.
The guard fails toward performing the dangerous action, which is the first rule in `code-check.md`.

Note also that `head` is reassigned in the loop, so once a re-probe fails, the write stays
unconditional for every remaining attempt.

Fix: separate "confirmed 404" from "probe failed". Branch on the error text / `--output json` error
code, and abort rather than write when the re-probe is not a confirmed 404. An object that existed
on entry must never be written unconditionally.

### 3. **[bug]** `R/store.R:891-897, 927` — the create path has no precondition at all

When `head$exists` is FALSE and `create_manifest = TRUE`, `if_match` is `NULL` and the manifest is
written unconditionally. Two consequences:

- Two concurrent first pushes: the second silently overwrites the first and orphans its store —
  the precise bug this PR exists to fix, reachable through the create path.
- Combined with #2's conflation: a `create_manifest = TRUE` left behind in a build script will
  replace a **populated** manifest with a one-entry one the first time head-object fails for a
  non-404 reason. The flag is documented as a deliberate one-time seed, but nothing stops it being
  pasted into a script, and at that point it is a live footgun with the CAS switched off.

Fix: `--if-none-match "*"` on the create path, treating its 412 as "someone else created it —
re-read and merge" rather than as a failure.

### 4. **[bug]** `R/store.R:725-727` + `:925` — `NA_integer_` serializes into the manifest as the *string* `"NA"`

Measured against the jsonlite in this library (2.0.0):

```
toJSON(list(documents = NA_integer_, chunks = 5L, repo = NA_character_),
       auto_unbox = TRUE, null = "null")
#> {"documents":"NA","chunks":5,"repo":null}
```

`NA_character_` and logical `NA` do become `null`; **only the numeric types are corrupted**, and
they are corrupted into a different JSON type rather than into `null`. `.crd_store_describe()`
produces `NA_integer_` for `documents`, `chunks` (a failed `COUNT(*)`) and `embedding_size` (no
`metadata` table — an older ragnar store), so such a store lands in the shared manifest as
`"documents": "NA"` where every other entry holds an integer. It then round-trips through every
subsequent `.crd_manifest_merge()` unchanged and is permanent.

To be explicit about the rest of the round-trip, since it was in scope: a one-element `built_by`
array stays an array under `auto_unbox = TRUE`, `{}` stays `{}`, and large `bytes` doubles print in
full — those are all fine. This is the one type that breaks.

Fix: `jsonlite::write_json(..., na = "null")` (verified: `{"documents":null,...}`), or drop NA
numerics to NULL before writing.

### 5. **[fragile]** `R/store.R:661` — `grepl("412|...")` matches a bare substring anywhere in the output

```r
any(grepl("412|PreconditionFailed", res$out, ignore.case = TRUE))
```

`412` as an unanchored substring matches any request id, byte count, key name or timestamp
containing those three digits. An unrelated fatal error (AccessDenied, a KMS failure, a quota
error) whose output happens to contain `412` is then misread as a precondition failure and pushed
into the retry loop — where, per #2, it can end in an unconditional write. Anchor on the token the
CLI actually emits: `An error occurred (PreconditionFailed)` / `(412)`.

### 6. **[fragile]** `R/store.R:915` — the store binary goes up via `s3api put-object`: single PUT, 5 GB cap, no multipart

`put-object` is a single PUT with a hard 5 GB object limit and no multipart or resume. The pull side
(`.crd_aws(c("s3", "cp", ...))`, `R/store.R:229`) uses `aws s3 cp`, which multiparts in both
directions. Nothing about the binary upload needs `s3api` — there is no conditional write on it —
so this trades the working tool for a capped one. A store past the cap fails after however long the
upload ran. Use `s3 cp` for the body and keep `s3api` for `log.json`, where `--if-match` is needed.

### 7. **[fragile]** `R/store.R:914-948` — the binary overwrites the live key before the manifest describes it

The store is PUT over `<name>.duckdb` first; `log.json` is written after. During that window — and
permanently if the manifest write fails (AccessDenied on `log.json`, retries exhausted, process
killed, or #1's false 412) — the manifest still names the *old* md5 while the *new* binary sits at
the key. Every `crd_store_connect(name)` in the org then hard-fails at `R/store.R:236` with
"MD5 mismatch after download", and the previous good binary has been destroyed, so there is nothing
to roll back to.

The `stop()` at `:950` says the binary uploaded and to re-run, which is the right advice, but it
does not say the store is unreadable for everyone until that happens. Uploading to a content-keyed
name (`<name>-<md5>.duckdb`) and pointing the manifest at it removes the window entirely; at
minimum, both failure messages should state that pulls of this store will fail until the push is
re-run.

### 8. **[fragile]** `R/store.R:728` — the model-mismatch guard compares an environment default, not the store

```r
embedding_model = Sys.getenv("CRED_EMBED_MODEL", "nomic-embed-text (ollama)")
```

The value comes from the pusher's shell, not from the artifact. So `.crd_check_model()` — the third
of the three advertised refusals — compares a *default string* against the corpus, and the exact
case it exists for (a store genuinely built with `embeddinggemma` by someone who never set the env
var) sails through the guard **and** is recorded in the shared manifest as `nomic-embed-text`. The
manifest is then wrong in a way no later check can detect.

`code-check.md`: *"A proxy assertion does not guard the thing it stands for"* and *"A value nothing
reads is wrong silently — get it from the consumer"*.

The store's own `metadata` row is already being read two lines above and carries `embedding_size`,
which *is* derived from the artifact (768 vs 3072 vs …). Cross-checking that against the other
entries' `embedding_size` would make the guard real; the model string can stay as a label.

### 9. **[fragile]** `tests/testthat/test-store-push.R:804-805` — asserts the test process's cwd is a git worktree

```r
here <- .crd_git_provenance(".")
expect_match(here$repo, "^[^/]+/[^/]+$")
```

This asserts a fact about wherever the test runner happens to be, not about the function. It passes
from the source tree. It fails under `devtools::check()` — the command CLAUDE.md documents — because
`check_dir` defaults to `NULL`, i.e. a temp directory, so the tests execute from
`<tmp>/cred.Rcheck/tests/testthat`, `git -C .` fails, `repo` is `NA_character_`, and the expectation
errors. Verified both halves:

```
repo url in tempdir: NA
FAIL: Expected NA_character_ to match regexp "^[^/]+/[^/]+$". Actual text: <NA>
```

Same for a tarball check, an installed-tests run, or CRAN. (`R CMD check` from the repo root happens
to pass, because `cred.Rcheck/` lands inside the worktree — which is what makes this
environment-dependent rather than always-red.)

The preceding assertion (tempdir → all NA) is the one that actually tests the documented behaviour.
Either skip the `.` half when `.crd_git_provenance(".")$repo` is NA, or have the test `git init` a
fixture repo with a known remote and read that — which also makes the `repo` regex assertion mean
something.

### 10. **[fragile]** `R/store.R:910` — the dry run does not preview what gets written

`cat(jsonlite::toJSON(merged, auto_unbox = TRUE, pretty = TRUE))` omits `null = "null"`, whose
default is `null = "list"`, while the real write at `:925` passes it. Measured:

```
preview: {"a":{},"b":"NA"}
written: {"a":null,"b":"NA"}
```

So NULL fields render as `{}` in the preview and `null` in the file. Given `dry_run` is documented
as "always do this first" and is the only chance to eyeball the merge before it lands, the preview
should be byte-faithful. One-word fix: add `null = "null"`.

## Checked and clean

Recording these because they were the specific questions asked:

- **`.crd_manifest_merge()` cannot drop or mutate an existing entry.** `merged$stores[[name]] <-
  entry` is exact-match assignment on a named list; every other key passes through by reference.
  `built_by` survives in both shapes (bare string and array), and the tests pin that.
- **The retry loop's `merged`/`entry` state is correct.** `entry` is computed once, before the
  binary upload, and re-merged onto the freshly-read manifest each iteration — so the entry is never
  lost and never stale relative to what was uploaded. The loop's defect is the `if_match` selection
  (#2), not the merge state.
- **`--if-match` construction and quoting are sound.** `.crd_aws()` `shQuote`s every argument
  individually, so the `"..."` in the ETag survives; the `!is.null && !is.na && nzchar` gate keeps a
  missing ETag from producing a bare `--if-match` flag with the next argument as its value.
- **The `.crd_aws()` return-shape change is complete.** Both pre-existing callers
  (`.crd_manifest_read` `:99`, `crd_store_connect` `:229`) were updated to `res$out`; no other
  caller exists in `R/`, `tests/` or the vignettes, and the one `.crd_aws` test in `test-store.R`
  exercises `shQuote` directly rather than the return value. `as.character()` drops the `status`
  attribute cleanly, and a NULL status correctly becomes `0L`.
- **`dry_run` returns before the first write**, not merely before the slow one — the `code-check.md`
  preview-flag trap does not apply here.
- **The WAL guard** checks `<store>.wal`, which is the name duckdb actually uses.
