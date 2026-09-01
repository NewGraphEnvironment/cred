# Push a ragnar evidence store and merge it into the shared manifest

Uploads a built store and records it in the bucket's single `log.json`
manifest, **merging** rather than replacing. The manifest describes
every store in the bucket, so a push built from the current run alone
silently orphans the others — the pull side then reports "not in
log.json" for a file plainly present. That failure has been observed in
practice.

## Usage

``` r
crd_store_push(
  store_path,
  source = getOption("cred.store_source"),
  name = NULL,
  profile = Sys.getenv("AWS_PROFILE"),
  built_by = "cred::crd_store_push()",
  dry_run = FALSE,
  create_manifest = FALSE,
  allow_model_mismatch = FALSE,
  max_retries = 3L
)
```

## Arguments

- store_path:

  `character(1)` path to the `.duckdb` store to upload.

- source:

  `character(1)` destination URI holding the stores and `log.json`.
  Defaults to `getOption("cred.store_source")`, then
  `CRED_STORE_SOURCE`. Shape `s3://<bucket>/<prefix>/`.

- name:

  `character(1)` store name in the manifest. Defaults to the file name
  without its extension.

- profile:

  `character(1)` AWS profile. Default `AWS_PROFILE`.

- built_by:

  `character` what produced the store, recorded in the entry.

- dry_run:

  `logical(1)` print the merged manifest and upload nothing. Default
  `FALSE`.

- create_manifest:

  `logical(1)` allow writing a manifest where none exists. Default
  `FALSE`. The create path is still conditional (`--if-none-match "*"`),
  so two simultaneous first pushes cannot silently overwrite one
  another.

- allow_model_mismatch:

  `logical(1)` push despite a differing embedding model. Default
  `FALSE`.

- max_retries:

  `integer(1)` conditional-write retries before giving up. Default `3L`.

## Value

Invisibly, the merged manifest as a `list`.

## Details

Three deliberate refusals, each guarding a way the manifest can be
corrupted:

- **An unreadable manifest aborts the push.** Only a *confirmed* absence
  — bucket reachable, object missing — is treated as "no manifest yet",
  and even then `create_manifest = TRUE` is required. A wrong prefix in
  `cred.store_source` produces exactly the same 404 as a genuine first
  push.

- **A concurrent push cannot clobber this one.** The manifest is written
  conditional on the ETag read at the start; a competing write fails the
  precondition, and the merge is retried against the newer manifest.

- **A store with an unflushed WAL is refused**, since its md5 does not
  describe what a puller would open.

The store binary is uploaded before the manifest that describes it, so a
failed manifest write leaves the new binary in place under the old md5
and pulls of that store fail until the push is re-run. Both failure
messages say so. Removing the window entirely means content-addressed
keys (`<name>-<md5>.duckdb`), which is a change to the shared bucket
layout and belongs with the infrastructure rather than here.

Building the store is
[`crd_store_build()`](https://newgraphenvironment.github.io/cred/reference/crd_store_build.md);
reading it back is
[`crd_store_connect()`](https://newgraphenvironment.github.io/cred/reference/crd_store_connect.md).
Bucket policy, IAM and retention are infrastructure concerns and
deliberately live outside this package.

## Examples

``` r
if (FALSE) { # \dontrun{
options(cred.store_source = "s3://<bucket>/<prefix>/")

# Always dry-run first — prints the merged manifest, uploads nothing.
crd_store_push("data/rag/vca_refs.duckdb", dry_run = TRUE)

crd_store_push("data/rag/vca_refs.duckdb")
} # }
```
