# Code review — round 2 (ragnar evidence store, #22)

Reviewed the **working tree** (matches `/tmp/cred22-diff.txt`) against the full
`soul/conventions/code-check.md`. Infra checks skipped — no Terraform/cloud-init/compose here.

Evidence gathered this round:

- `devtools::test(filter = "store")` — **FAIL 0 | WARN 0 | SKIP 0 | PASS 49**
- `lintr::lint_package()` — **0 lints**
- `R CMD build` + `R CMD check --no-tests --no-vignettes` on the built tarball
- Empirical probes for `file.rename`, orphan DuckDB `.wal` replay, `basename(dirname(NA))`,
  `system2` quoting, and NA-row data.frame subsetting

---

## Findings

### 1. [security] `planning/active/findings.md:105` — a real bucket address is committed to this public repo

```
chunks) at `s3://<bucket>/<prefix>/`, built by `restoration_wedzin_kwa_2024/scripts/rag_build.R`.
```

`gh repo view` confirms `"isPrivate": false, "visibility": "PUBLIC"`, and `planning/` is
tracked (`git ls-files` lists `planning/active/findings.md`).

This contradicts the change's own stated design decision, added in this same diff to
`CLAUDE.md`:

> **No bucket address in the source** — `cred` is public; the store source comes from
> `getOption("cred.store_source")` / `CRED_STORE_SOURCE` with no default.

The R code holds that line perfectly — every occurrence in `R/`, `man/` and
`tests/testthat/` is the `s3://<bucket>/<prefix>/` placeholder. The planning file does not.

Two aggravating details:

- **It is already in `HEAD`** (`git show HEAD:planning/active/findings.md | grep <bucket>`
  hits line 105), not merely staged. Scrubbing the working tree removes it from the tip but
  not from history; a real purge means history rewrite or accepting it as disclosed.
- **Round 1 explicitly cleared this and was wrong.** `planning/active/review-round1.md:171-173`
  claims `git grep -Ei 's3://[a-z0-9]|amazonaws\.com|AKIA[0-9A-Z]{16}'` "returns only the shape
  placeholders". That pattern matches `s3://<bucket>` — so the check was either not run or its
  output was not read. A clean grep result you did not verify is the "empty result set is not a
  pass" entry in `code-check.md`, one level up.

`.Rbuildignore ^planning$` (fix 5) does keep it out of the tarball — verified below — but that
is orthogonal: the exposure is GitHub, not CRAN.

Decide deliberately: either the bucket name is acceptable to disclose (it is a name, not a
credential, and the bucket's own IAM is what actually gates access), or it gets scrubbed. What
is not acceptable is a design decision asserting one thing while the repo does the other.

---

### 2. [bug] `R/store.R:534-545` — the new `complete` guard destroys a *fully built* store if the cheap epilogue fails

```r
complete <- FALSE
on.exit({
  try(DBI::dbDisconnect(store@con, shutdown = TRUE), silent = TRUE)
  if (!complete) unlink(store_path)
}, add = TRUE)

message("Ingesting ", nrow(src), " PDF(s) into ", store_path)
ragnar::ragnar_store_ingest(store, src$src_path, progress = TRUE)   # <- hours

n_docs   <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM documents")$n
n_chunks <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM chunks")$n
complete <- TRUE                                                   # <- too late
```

The guard is the right idea and the ordering inside `on.exit` (disconnect, *then* unlink) is
correct. The flag is set two statements too late.

`ragnar_store_ingest()` is the expensive, irreversible work — 25 PDFs embedded through Ollama,
the operation the docstring calls "expensive and machine-local". The two `COUNT(*)` queries are
a cosmetic epilogue that exists only to populate a `message()`. As written, **anything that
throws or interrupts between the ingest returning and line 545 unlinks the completed store**:

- a `Ctrl-C` landing in that window (`on.exit` runs on interrupt — that is the whole point of
  the fix, and it cuts both ways);
- a `dbGetQuery` failure — a ragnar/duckdb upgrade renaming `documents` or `chunks`, a
  transient DuckDB error. Confirmed both tables exist in the installed ragnar 0.3.0, so this is
  a forward-compatibility risk rather than a present one, but the failure mode is total and
  unrecoverable: hours of embedding deleted, and the user sees only the underlying error, with
  no hint that their finished store was thrown away with it.

This is the same class of loss the rest of the change works to prevent (fix 2 goes to real
trouble to never destroy an unpushed store), landing in the function that has the most to lose.

Fix — one line moved:

```r
ragnar::ragnar_store_ingest(store, src$src_path, progress = TRUE)
complete <- TRUE                     # the artifact is now whole

n_docs   <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM documents")$n
n_chunks <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM chunks")$n
```

Minor, same block: `unlink()`'s return value is not checked. If the unlink fails, the retry is
refused by the `file.exists(store_path) && !overwrite` guard at R/store.R:496 and the user is
told the store "already exists" when what is actually there is the wreckage. `if (!complete &&
unlink(store_path) != 0L) warning(...)` closes it.

---

## Verification of the five round-1 fixes

### Fix 1 — `.crd_aws()` shell-quoting (R/store.R:65-74) — CORRECT

`args <- vapply(args, shQuote, character(1L), USE.NAMES = FALSE)` after the `--profile` append,
so the profile value is quoted too. Confirmed on this machine that the unquoted form executes:

```
system2("echo", c("first; echo INJECTED"))   ->  "first" | "INJECTED"   (two lines)
system2("echo", shQuote("first; echo INJECTED")) ->  one literal line
```

`test-store.R:223` asserts exactly this. `vapply` over `character(0)` returns `character(0)`,
so an empty `args` is safe. `shQuote()`'s default type is platform-derived, so this is correct
on Windows too. No new defect.

Note (not a finding): `system2(stdout = TRUE, stderr = TRUE)` merges the streams, which
`code-check.md` warns corrupts parsed stdout. Not load-bearing here — `out` is only pasted into
error text, never parsed — and the merge is what makes the `aws` diagnostic visible in the
`stop()` message, which is the right trade.

### Fix 2 — atomic `.part` download (R/store.R:211-241) — CORRECT

Traced every failure path:

| failure | outcome |
|---|---|
| manifest entry has no md5 | errors at R/store.R:121, **before** any download — nothing touched |
| `aws s3 cp` fails, no file | `!file.exists(part)` → stop; `on.exit(unlink(part))`; local store intact |
| transfer truncated | md5 mismatch → stop; part unlinked; local store intact |
| md5 matches | `file.rename` into place, then connect |
| rename fails | stop with the path named; part unlinked |

The specific concerns raised:

- **on.exit interaction** — `crd_store_connect` registers no other `on.exit`, and both early
  `return()`s (verify = FALSE, md5-already-matches) happen before registration. Clean.
- **unlink of the wrong path** — `part` is `paste0(local_path, ".part-", Sys.getpid())`,
  derived from `local_path`, never from user input independently. After a successful rename the
  `unlink(part)` is a no-op.
- **cross-filesystem rename** — `part` is a sibling of `local_path` in the same directory, and
  `dir.create(dirname(local_path))` runs first, so `rename(2)` never crosses a mount.
  Confirmed `file.rename` over an existing target succeeds and replaces atomically.
- **concurrent `.part` collision** — PID-suffixed, so two processes get distinct part files and
  both rename onto `local_path`; last writer wins, and a reader that already opened the old
  inode keeps it (rename is atomic). No corruption.
- **md5 case** — `tolower()` on both sides (R/store.R:126, 201, 226), `test-store.R:217` covers
  it.

I also checked the DuckDB `.wal` sibling, since replacing a `.duckdb` under a stale WAL would be
a silent corruption path. Probed it: a fresh open with an orphaned WAL from a *different*
database does not replay it (`Catalog Error: Table with name t does not exist`). Benign here.

### Fix 3 — `crd_store_build` cleanup — CORRECT IN SHAPE, see finding 2 for the flag placement

Ordering, registration point (after `ragnar_store_create`, so a create failure cannot unlink a
pre-existing file), and the `try()` around `dbDisconnect` are all right. `on.exit` expressions
evaluate in the function frame at exit, so `complete` is read at its final value — the mechanism
works; only its timing is wrong.

### Fix 4 — `.crd_store_source()` NA / non-scalar rejection (R/store.R:32-52) — CORRECT

Length check precedes the NA check, so a length-2 source gets a message naming the problem
rather than `'length = 2' in coercion to 'logical(1)'`. `is.na()` short-circuits behind
`is.null()`, and the second guard can only see a non-NA value or `Sys.getenv()`'s `""`.
`test-store.R:200` and `:205` cover both. No new defect.

### Fix 5 — `.Rbuildignore` — CORRECT, verified by building

`R CMD build --no-build-vignettes` produces a tarball whose top level is:

```
.lintr  data-raw  DESCRIPTION  dev  inst  LICENSE  man  NAMESPACE  NEWS.md  R
README.html  README.md  tests  vignettes
```

`planning`, `CLAUDE.md`, `.claude`, `.git` and `data` are all excluded as intended.

---

## Checked and clean

- **`R CMD check` dependencies** — the new `tools::md5sum()` needs no DESCRIPTION entry (base
  priority, exempt). The `'::' imports not declared from: 'openxlsx' 'tibble'` WARNING is
  **pre-existing** (`tibble::` in `zotero.R`, `openxlsx` in `audit.R`); store.R adds no new
  undeclared dependency. `DBI`/`duckdb`/`ragnar`/`withr` are correctly in Suggests, and
  `Remotes: tidyverse/ragnar` matches.
- **`.crd_zot_key_from_path()`** — length-preserving on `character(0)`, `NA` and unresolvable
  paths (`basename(dirname(NA))` is `NA`, confirmed); degrades to all-`NA` when
  `zotero.sqlite` or RSQLite is absent rather than erroring. Parameterised SQL with only the
  `?` count interpolated, and `length(keys) <= top_k` so the SQLite variable limit is never
  approached.
- **NA-row subsetting** — `crd_store_build`'s `found[found$src_type == "pdf", ]` cannot produce
  the classic all-NA phantom row: `crd_zot_src_lookup()` derives `src_type` from a non-null
  `contentType` and pre-filters to files that exist, so the logical index carries no `NA`.
  `.crd_zot_collection_pdfs()` can emit an `NA` `src_path`, but `file.exists(NA)` is `FALSE`
  (confirmed) and the row is dropped with a warning naming the key.
- **`.crd_retrieval_score()`** — handles both the long-form and pivoted-hybrid shapes and
  returns correctly-lengthed `NA` when neither is present; four tests cover it.
- **`crd_search()` empty-result path** — returns a zero-row tibble with the full documented
  column set and types, so a caller binding results never meets a shape change.
- **`used <<- "bm25"`** in the fallback closure — correct as previously reviewed; `method` is
  reported as what actually ran, not what was asked for.

---

## Verdict

Fixes 1, 2, 4 and 5 are correct and complete, and introduce no new defect. Fix 3 is correct in
mechanism but its `complete` flag is set two statements too late, converting a cheap epilogue
failure into total loss of an expensive artifact — finding 2, one line to move. Finding 1 is a
disclosure question about a file this branch touches, and needs a decision rather than a code
change.
