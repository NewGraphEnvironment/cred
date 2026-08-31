# Code review — round 1 (ragnar evidence store, #22)

Reviewed against `soul/conventions/code-check.md` (full file), on the **working tree**, not
`/tmp/cred22-diff.txt`. The diff supplied was stale: the tree has since gained
`.crd_retrieval_score()` (R/store.R:224) and a `metric` column on `crd_search()`, with `man/`
regenerated to match. `devtools::test(filter = "store")` — **FAIL 0 | PASS 43**.

Line numbers below refer to the current working tree.

## Findings

### 1. [security] `R/store.R:54-61` — `.crd_aws()` passes unquoted arguments through a shell

`system2()` quotes only the *command*, never the args:

```r
command <- paste(c(env, shQuote(command), args), collapse = " ")   # base::system2
```

Confirmed empirically on this machine:

```
system2("ls",   c("-d", "/tmp/.../a dir with spaces"))  ->  4 separate "cannot access" errors
system2("echo", c("first; echo INJECTED"))              ->  "first" | "INJECTED"
```

Every argument `.crd_aws()` builds is caller- or environment-derived and none is quoted:

- `store` / `name` — `crd_store_connect("x; touch /tmp/pwned")` produces
  `aws s3 cp s3://b/x; touch /tmp/pwned.duckdb data/rag/x; touch /tmp/pwned.duckdb`.
  The `;` runs.
- `source` — from `getOption("cred.store_source")` or the `CRED_STORE_SOURCE` env var.
- `profile` — from the `AWS_PROFILE` env var (R/store.R:60).
- `local_path` / `dest` — a `dir` or `tempdir()` containing a space silently splits into
  several args, so `aws` either errors confusingly or writes to a truncated path.

`code-check.md` names this exact case ("`system2()` shell-quotes the command but not the
arguments") and prescribes `shQuote()` on every path or user-derived arg. Fix:

```r
if (nzchar(profile)) args <- c(args, "--profile", profile)
suppressWarnings(system2("aws", vapply(args, shQuote, character(1)), stdout = TRUE, stderr = TRUE))
```

Same entry also notes `stdout = TRUE` discards the exit status. Not load-bearing here (the
output is only pasted into an error message, never parsed), but the roxygen at R/store.R:52
claims a `"status"` attribute that nothing sets or reads.

---

### 2. [bug] `R/store.R:184-202` — the download overwrites the local store in place, non-atomically

`aws s3 cp` writes directly to `local_path`, the same file the local store occupies. Two
consequences, both destructive.

**a. A locally built store is silently replaced.** `crd_store_build()`'s documented output
path is `data/rag/<name>.duckdb` (R/store.R examples) and `crd_store_connect()`'s default
`dir` is `"data/rag"` — so the file a user just spent hours embedding is exactly the file at
the path. With `verify = TRUE` (the default), *any* md5 difference reaches R/store.R:185
("does not match the manifest — re-downloading") and clobbers it. The triggers are not
exotic:

- a store built locally and never pushed;
- a manifest entry with no `md5` field — `identical(character(1), NULL)` is `FALSE`, so it
  downloads, then fails the post-download check at R/store.R:197 with an empty
  `manifest: ` line (`stop()` drops `NULL`), i.e. it destroys the local copy and then
  refuses the replacement, every time;
- a manifest recording uppercase hex (`tools::md5sum()` returns lowercase).

**b. An interrupted download leaves a truncated file where the good one was.** The md5 check
at R/store.R:196-202 catches it *loudly*, which is right — but the original is already gone,
and the truncated file remains on disk. A subsequent `crd_store_connect(..., verify = FALSE)`
opens it as if complete: nothing distinguishes a partial store from a whole one.
`code-check.md`: "`cmd > file` truncates before `cmd` runs — a failed command leaves a
poisoned empty file."

Fix: download to a sibling temp path, md5-verify *there*, then `file.rename()` into place —
so a failed pull lands nothing and the existing store survives.

---

### 3. [fragile] `R/store.R:489-500` — DuckDB connection is not closed on the error path, and a partial store is left on disk

```r
store <- ragnar::ragnar_store_create(location = store_path, ...)
ragnar::ragnar_store_ingest(store, src$src_path, progress = TRUE)   # <- can throw
n_docs   <- DBI::dbGetQuery(store@con, ...)
DBI::dbDisconnect(store@con, shutdown = TRUE)
```

No `on.exit`. `ragnar_store_ingest()` over a set of PDFs is exactly the call that throws — an
unparseable PDF, Ollama dying partway through an hour of embedding, a user interrupt. When it
does:

- the connection leaks for the rest of the session and `shutdown = TRUE` never runs;
- **a partially ingested `.duckdb` is left at `store_path`**. The next `crd_store_build()`
  refuses it at R/store.R:465 ("Store already exists"), so the natural retry fails; and
  `crd_store_connect(..., verify = FALSE)` will open it and answer queries from a fraction of
  the corpus with no signal that anything is missing. Given the package exists to make
  citation evidence trustworthy, a silently-short store is the failure that matters.

Fix: register cleanup immediately after `ragnar_store_create()`, and unlink the store when
ingest did not complete:

```r
store <- ragnar::ragnar_store_create(...)
ok <- FALSE
on.exit({
  try(DBI::dbDisconnect(store@con, shutdown = TRUE), silent = TRUE)
  if (!ok) unlink(store_path)
}, add = TRUE)
```

Verified against installed ragnar that the happy path is correct: the store is
`ragnar::DuckDBRagnarStore`, `@con` resolves, and `documents` / `chunks` are both real tables.

---

### 4. [fragile] `R/store.R:32-46` — `nzchar(NA)` is `TRUE`, so an `NA` source passes the "is it configured" guard

`code-check.md` carries this one by name. Measured here:

```
.crd_store_source(NA_character_)          ->  NA          (no error raised)
paste0(NA, "log.json")                    ->  "NAlog.json" (what reaches `aws s3 cp`)
.crd_store_source(c("s3://a/", "s3://b/")) ->  Error: 'length = 2' in coercion to 'logical(1)'
```

So `options(cred.store_source = NA)` slips past the carefully written "no source configured"
error and fails much later with a nonsense S3 URI, and a length-2 value dies with a message
that names neither the option nor the function. `source` is the only argument of
`crd_store_connect()` with no `chk::` check (cf. `store`, `dir`, `read_only`, `verify` at
R/store.R:151-154).

Fix: `if (is.null(source) || is.na(source) || !nzchar(source))` at R/store.R:33 and 36, plus
`chk::chk_string(source)` on the resolved value.

---

### 5. [fragile] `.Rbuildignore` does not exclude `planning/`, `CLAUDE.md` or `.claude/` — pre-existing, but this change grows what ships

`.Rbuildignore` currently lists only `LICENSE.md`, `README.Rmd`, `_pkgdown.yml`, `docs`,
`pkgdown`, `.github`, `*.Rproj`, `.Rproj.user`, `doc`, `Meta`. `R CMD build` ships every other
top-level directory, and `.gitignore` does not cover this. Tracked and shipping today:
`planning/README.md`, `planning/active/{findings,progress,task_plan}.md`, `.claude/visibility`,
`CLAUDE.md`.

Not introduced by this change, but relevant on two counts: the repo was flipped public one
commit ago (`aeef3f1`), and this change adds internal coordination content to
`planning/active/findings.md` and `task_plan.md`. `code-check.md`: "a public-flipped package
that ships it leaks exactly what the flip was meant to purge." Verify against the tarball, not
the config:

```bash
R CMD build . >/dev/null && tar tzf cred_*.tar.gz | grep -c '^cred/planning/'   # expect 0
```

Worth adding `^planning$`, `^CLAUDE\.md$`, `^\.claude$` — and, per the same convention,
`^\.git$` if anyone builds from a `git worktree`.

---

## Checked and clean

- **SQL injection** — both new queries are properly parameterised. `.crd_zot_collection_pdfs()`
  (R/store.R:346) passes the collection name via `params = list(collection)`; the `sprintf()`
  in `.crd_zot_key_from_path()` (R/zotero.R:233-244) interpolates only the *count* of `?`
  placeholders, with the values in `params = as.list(keys)`. Same shape as the existing
  `crd_zot_src_lookup()`. `keys` cannot be empty there — the `if (!any(valid))` early return at
  R/zotero.R:222 guarantees at least one.
- **No bucket address leaks.** `git grep -Ei 's3://[a-z0-9]|amazonaws\.com|AKIA[0-9A-Z]{16}'`
  over all tracked files returns only the shape placeholders (`s3://<bucket>/<prefix>/`) in
  roxygen and error text, and `s3://bucket/prefix` in the test fixture. The `.crd_store_source()`
  error message is asserted against `<bucket>` by a test.
- **The `<<-` in the `crd_search()` fallback is correct.** The `tryCatch` handler is defined in
  `crd_search()`'s evaluation frame, so `used <<- "bm25"` starts its search in that frame,
  finds `used`, and assigns there — the returned `method` column does reflect the fallback.
- **`.crd_zot_key_from_path()` is NA-safe and length-preserving.** Verified: `character(0)` in
  → `character(0)` out; `NA_character_` → `NA`; a non-key parent directory → `NA`;
  `match()` yields `NA` for a key absent from the DB rather than dropping the row.
- **RSQLite connections are safe on error paths.** Every `dbConnect()` in R/store.R and
  R/zotero.R is followed immediately by `on.exit(dbDisconnect(con), add = TRUE)`, before any
  call that can throw. Read-only immutable URIs used throughout, per the repo convention.
- **`.crd_retrieval_score()`** (added since the supplied diff) correctly handles both the
  long-form `metric_name`/`metric_value` shape and the pivoted hybrid shape, and returns the
  metric name alongside the score rather than silently mixing incomparable scales. The
  all-`NA`-score bug it fixes was real.
