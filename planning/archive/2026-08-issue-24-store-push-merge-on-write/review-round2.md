# Review round 2 — `crd_store_push()` (R/store.R, tests/testthat/test-store-push.R)

Re-review of the working tree after the ten round-1 fixes. Reviewed against
`soul/conventions/code-check.md` (infra sections skipped — no Terraform / cloud-init /
docker-compose in this diff).

Everything below was executed, not reasoned about. Environment used for verification:
aws-cli **2.34.34** (Python 3.14.5, Darwin arm64), jsonlite 2.x, ragnar installed, and a
**real** ragnar store at
`/Users/airvine/Projects/repo/restoration_wedzin_kwa_2024/data/rag/vca_refs.duckdb`.

Suite state at review time: `store-push` 58 pass, `store` 49 pass, `lintr::lint_package()`
0 lints, `planning/` is in `.Rbuildignore` (`^planning$`) so these notes cannot leak into
a build.

---

## Verdict on the ten round-1 fixes

| # | Fix | Verdict |
|---|-----|---------|
| 1 | `clean_stdout` / ETag by shape | **Correct** |
| 2 | `confirmed_absent`, retry aborts | **Correct** |
| 3 | `--if-none-match "*"` on create | **Correct** |
| 4 | `na = "null"` on write | **Correct** |
| 5 | Anchored precondition regex | **Correct** (but see F3 — the *sibling* regex was not anchored) |
| 6 | `s3 cp` for the body | **Correct** |
| 7 | Documented pre-manifest binary window | **Correct** (all three post-upload exits carry `stale_warning`) |
| 8 | Model guard cross-checks `embedding_size` | **INCOMPLETE — see F1** |
| 9 | `git init` fixture instead of cwd | **Correct** |
| 10 | `null="null"` on the dry-run preview | **Correct** |

Detail on the ones that needed proving:

**#1 — `system2(stdout = TRUE, stderr = <file>)` behaves as assumed.** Executed:

```
out: OUTLINE          status attr: 3     errfile: ERRLINE
out2: "abc123"        status: NULL       err2: warn
```

stdout is captured clean, stderr lands in the file, and the `status` attribute survives —
so `.crd_aws()`'s `attr(out, "status")` read is sound in both branches. The temp file is
cleaned: `on.exit(unlink(err_file), add = TRUE)` is registered inside a *function* frame
(not at a script top level, which is the `on.exit()` trap in `code-check.md`), and the only
`stop()` in `.crd_aws()` fires before the file is created. The contents are read back into
`err` and returned, so the "carry the CONTENTS onward, not the path" corollary is honoured.

The ETag-by-shape match is right for the real CLI: `--query ETag --output text` emits the
S3 ETag *including* its literal quotes (`"d41d8..."`), so `^"[^"]*"$` matches, and it also
matches the multipart form (`"abc-3"`).

**#2 — the retry cannot write unconditionally.** Exactly one of `if_match` /
`if_none_match` is always populated (`if (existed)` / `if (!existed)`), and the only way
`existed` is `TRUE` with an unusable `etag` is blocked twice: at entry
(`head$exists && is.na(head$etag)` → `stop`) and in the loop
(`!head$exists || is.na(head$etag)` → `stop`). A matched ETag is always ≥ 2 chars, so
`nzchar()` cannot fail either. Not reachable today — but see **F4** for why the helper
still deserves a hard stop.

**#3 — the flags exist.** `aws s3api put-object help` on the installed CLI lists both
`--if-match` and `--if-none-match`. `.crd_aws()`'s per-argument `shQuote()` keeps `*` from
being glob-expanded by the shell `system2()` builds, and keeps the ETag's embedded quotes
intact.

**#4 / #10 — measured.** `toJSON(list(a=NA_integer_, b=5L, c=NA_character_, d=NULL,
e=NA_real_), auto_unbox=TRUE, null="null", na="null")` →
`{"a":null,"b":5,"c":null,"d":null,"e":null}`. `write_json()` forwards to `toJSON()` with
identical defaults, and both call sites now pass the same four arguments, so the dry-run
preview is byte-faithful to what gets written.

**#8's `field()` helper is mechanically correct.** `vapply(others, f, cast(NA))` gets a
valid `FUN.VALUE` for both casts (`as.character(NA)` → `NA_character_`,
`as.integer(NA)` → `NA_integer_`), and an empty `others` returns a zero-length vector of
the right type (verified: `vapply(list(), …, as.integer(NA))` → `integer(0)`), so
`length(sizes) > 0L` short-circuits cleanly. `manifest$stores` being `NULL` also yields an
empty `others` without erroring. The problem with #8 is upstream of this helper — F1.

**`res$err` is never read off a list that lacks it.** Every `.crd_aws()` return path
populates `err` (`character()` when `clean_stdout = FALSE`). `$err` is read in exactly two
places — `.crd_s3_precondition_failed()` and the manifest-write `stop()` — both fed from
`.crd_s3_put()` → `.crd_aws()`. The test mocks of `.crd_aws` all return `err`; the test
mocks of `.crd_s3_head_object` omit it, but no caller reads `$err` off a head-object
result (only `$exists`, `$confirmed_absent`, `$etag`, `$out`).

---

## Findings

### F1. **[bug]** `R/store.R:785` (+ `:848`) — the fix for round-1 #8 cannot fire in the case it was written for, and the ground truth it needs is sitting one column away

`embedding_size` was added as a cross-check on the theory that it is "read from the store
itself" and therefore catches a mislabelled model. Two measurements say it does not:

1. **The two candidate models are the same dimension.** `crd_store_build()` defaults to
   `nomic-embed-text`; `R/store.R:479-482` documents that a bare `ragnar::embed_ollama()`
   "silently defaults to `embeddinggemma`". Both produce **768-dimensional** embeddings.
   So for the exact scenario round-1 #8 described — a store genuinely built with
   embeddinggemma by someone who never set `CRED_EMBED_MODEL` — `size_conflict` is
   `768 %in% 768` → FALSE, `model_conflict` is
   `"nomic-embed-text (ollama)" %in% "nomic-embed-text (ollama)"` → FALSE, and the guard
   returns silently while writing `"embedding_model": "nomic-embed-text (ollama)"` into
   the shared manifest. The dimension check only catches a swap that changes width
   (e.g. 768 → 3072), which is not the failure mode the codebase warns about.

2. **The store already records the real model, and the push ignores it.** Read from the
   live `vca_refs.duckdb`, the `metadata` table has columns
   `embedding_size`, **`embed_func`**, `name`. `embed_func` is a serialized closure;
   unserializing it yields verbatim:

   ```
   function (x)
   ragnar::embed_ollama(x = x, model = "nomic-embed-text")
   ```

   That is the artifact-derived value the guard was asked for. Instead `:785` reads
   `Sys.getenv("CRED_EMBED_MODEL", "nomic-embed-text (ollama)")` — and **nothing in this
   package ever sets `CRED_EMBED_MODEL`**: `crd_store_build()` takes `model` as a function
   argument and never exports it. `grep -rn CRED_EMBED_MODEL R/ tests/ vignettes/` finds
   only the one read site. So the label is, in practice, always the hardcoded default,
   and `.crd_check_model()` is comparing a constant against the corpus.

This is still `code-check.md`'s *"A proxy assertion does not guard the thing it stands
for"*: the fix replaced one proxy (an env var) with a second proxy (a dimension that
collides between the two models in play) while the direct measurement went unused.

Fix: read `embed_func` in `.crd_store_describe()` and pull the model out of it, e.g.

```r
model_from_store <- function(blob) {
  f <- tryCatch(unserialize(as.raw(blob)), error = function(e) NULL)
  if (is.null(f)) return(NA_character_)
  m <- tryCatch(as.list(body(f))$model, error = function(e) NULL)
  if (is.null(m)) NA_character_ else as.character(m)
}
```

and fall back to `CRED_EMBED_MODEL` only when that returns `NA`. Keep the dimension check —
it is still worth having — but it must not be the only artifact-derived signal.

### F2. **[fragile]** `R/store.R:776-786` — one query fetches two independent fields, so any schema drift silently disables the dimension guard

```r
meta <- tryCatch(DBI::dbGetQuery(con, "SELECT embedding_size, name FROM metadata"),
                 error = function(e) NULL)
```

`embedding_size` (the guard's input) and `name` (a cosmetic label) are coupled into one
statement inside one `tryCatch`. A ragnar version that renames or drops `name`, or a
store predating the `metadata` table, makes the whole call error → `meta <- NULL` →
`embedding_size = NA_integer_` → `size_conflict` is `!is.na(size) && …` → **FALSE, always,
with no message**. The push proceeds and the manifest records `"embedding_size": null`.

That is `code-check.md`'s first rule — *"A guard must not fail toward 'skip'"*: the
schema-drift path and the no-conflict path are indistinguishable from outside. Query the
guard's input separately from the cosmetic one, and say something (a `message()` at least)
when the dimension could not be read.

While there: on the real store, `metadata.name` is ragnar's internal **`"store_001"`**, not
the store's name. Every entry `crd_store_push()` writes will therefore carry
`"store_name": "store_001"` into the shared, permanent manifest — a value that reads like a
real name and is not one. Either drop the field or source it from `name`/`basename()`.

### F3. **[fragile]** `R/store.R:657` — the absence probe is still an unanchored substring match

```r
absent <- any(grepl("404|Not Found|NoSuchKey", c(res$out, res$err), ignore.case = TRUE))
```

Round-1 #5 was fixed for `412` and the identical pattern one function away was left as is.
A bare `404` matches any request id, byte count, timestamp or key containing those digits —
so an unrelated failure (throttle, KMS, AccessDenied) whose `x-amz-request-id` happens to
contain `404` is promoted from "probe failed" to **confirmed absent**.

The blast radius is bounded by fix #3 (the create path is `--if-none-match "*"`, so a
mistaken "absent" cannot overwrite a live manifest — it 412s and re-merges). The cost is a
wrong diagnosis at exactly the moment the operator needs a right one: they are told
*"this prefix has no manifest yet … pass create_manifest = TRUE"* for what is actually a
credentials or permissions failure, and `create_manifest = TRUE` is precisely the flag the
docstring warns about leaving in a script. Anchor it the same way the 412 matcher is:
`\\(404\\)|\\(NoSuchKey\\)`.

**Related, worth knowing rather than fixing:** S3 returns **403 Forbidden**, not 404, for
`HeadObject` on a *missing* key when the caller lacks `s3:ListBucket` on the bucket. Such a
principal can never produce `confirmed_absent = TRUE` and therefore can never make a first
push — it will always hit the *"This is not a 404 — refusing to push rather than guess"*
abort. The direction is safe, but it is an operational dead end that the error message does
not hint at, and it interacts with the "Public bucket ≠ listable: GetObject vs ListBucket"
entry in `code-check.md`. One sentence in that `stop()` naming `s3:ListBucket` would save
the debugging session.

### F4. **[fragile]** `R/store.R:682-687` — `.crd_s3_put()` silently degrades to an unconditional write on unusable input

```r
if (!is.null(if_match) && !is.na(if_match) && nzchar(if_match)) {
  args <- c(args, "--if-match", if_match)
}
```

An `if_match` that is supplied but `NA` or `""` drops the precondition and performs a plain
overwrite. **This is not reachable from `crd_store_push()` today** — both `is.na(head$etag)`
aborts cover it, and I traced every path. But the helper's contract is now "given a broken
ETag, clobber", which is structurally the same defect as round-1 #2 and is one edit away
from being live again: any future call site that forgets a guard gets an unconditional
write and no signal.

The guard belongs in the helper, not only in its caller:

```r
if (!is.null(if_match)) {
  if (is.na(if_match) || !nzchar(if_match)) {
    stop("if_match was supplied but is unusable — refusing an unconditional write.",
         call. = FALSE)
  }
  args <- c(args, "--if-match", if_match)
}
```

### F5. **[fragile]** `R/store.R:713-720` — `409 ConditionalRequestConflict` is not treated as retryable

S3 conditional writes return `412 PreconditionFailed` when the precondition is definitively
unmet, but return **`409 ConditionalRequestConflict`** when a concurrent conditional write
to the same key is in flight — the documented guidance for which is *retry*.
`.crd_s3_precondition_failed()` matches only `(PreconditionFailed)` / `(412)`, so a 409
falls through to the `stop("Manifest write failed …")` branch.

The direction is safe (no clobber) and the message carries `stale_warning`, so the operator
is told to re-run — which is the correct remedy. But it converts a case the retry loop was
built to absorb into a hard failure that has already uploaded the binary, i.e. it leaves the
bucket in the inconsistent state fix #7 documents, for a condition that would have resolved
on the next attempt. Add `\\(ConditionalRequestConflict\\)|\\(409\\)` to the matcher.

---

## Checked and clean

Recorded because they were the specific questions asked, or because they are the places a
fix like this usually breaks something else:

- **`clean_stdout` cleanup and status propagation** — verified empirically (above); the
  temp file is removed on every exit path, and `as.character(out)` drops the `status`
  attribute after it has been read.
- **The retry loop cannot write unconditionally** — traced; exactly one precondition is
  always set, and `existed = TRUE` implies a non-NA, non-empty ETag by two prior aborts.
- **`--if-none-match "*"` semantics** — flag present in the installed CLI, `*` is
  shell-quoted, and its 412 is handled coherently: re-probe, require a clean read, flip
  `existed` to TRUE, re-merge against the newly-read manifest, retry under `--if-match`.
- **`field()` / `vapply` FUN.VALUE** — correct for both casts and for empty `others`
  (measured), and safe when `manifest$stores` is `NULL`.
- **`res$err` availability** — audited every call site; no access to an absent element in
  real code or in mocks.
- **`.crd_git_provenance()` remote parsing** — traced the regex by hand for both fixture
  forms. `git@github.com:Owner/name.git` → greedy `.*` cannot advance past the `:` because
  `name.git` contains no `/`, so the group is `Owner/name.git` → `Owner/name`;
  `https://github.com/Owner/name.git` resolves the same way. Both fixture tests pass.
- **Fix #9 removed the cwd assumption entirely** — no assertion in the file now reads the
  runner's working directory; the two provenance tests build their own `git init` fixtures
  under `withr::local_tempdir()` and `skip_if()` when git is absent.
- **`dry_run` returns before the first write**, not merely before the slow one — the
  `code-check.md` preview-flag trap does not apply. (It does still require network and
  credentials, since the head probes and manifest read precede it; that is intended, as the
  preview is of the *merged* manifest.)
- **Round-1 #7's documentation is complete** — `stale_warning` is appended to all three
  post-upload failure exits (`Manifest write failed`, `Lost track of the manifest`,
  `Gave up after N`). The pre-upload `Store upload failed` exit correctly omits it.
- **TOCTOU between the ETag read and the manifest body read** is benign in both directions:
  a write landing in that window changes the ETag, so the conditional PUT 412s and the loop
  re-reads. No lost update is possible.
- **Shell safety** — `.crd_aws()` `shQuote()`s every argument individually, including the
  ETag's embedded quotes, `*`, and the tempfile path; `.crd_git_provenance()` quotes `dir`.
- **`.crd_manifest_merge()` purity** — unchanged since round 1 and still exact-match
  assignment on a named list; the tests pin both `built_by` shapes.
- **Repo hygiene** — `lintr::lint_package()` reports 0 lints; `planning/` is `.Rbuildignore`d
  so these review notes cannot trip `R CMD check`'s non-standard-top-level NOTE.
