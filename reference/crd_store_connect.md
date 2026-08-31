# Connect to a ragnar evidence store, pulling and verifying it if needed

Resolves a store by name, using the local copy when its MD5 matches the
shared manifest and downloading it from `source` otherwise. Verification
is the point: a store built against a different embedding model answers
differently while looking perfectly healthy, so a silent local rebuild
produces an artefact that is present but not trustworthy.

## Usage

``` r
crd_store_connect(
  store,
  source = getOption("cred.store_source"),
  dir = "data/rag",
  profile = Sys.getenv("AWS_PROFILE"),
  read_only = TRUE,
  verify = TRUE
)
```

## Arguments

- store:

  `character(1)` store name (e.g. `"vca_refs"`), or a path to an
  existing `.duckdb` file.

- source:

  `character(1)` source URI holding the stores and `log.json`. Defaults
  to `getOption("cred.store_source")`, then `CRED_STORE_SOURCE`.

- dir:

  `character(1)` local directory holding stores. Default `"data/rag"`.
  Ignored when `store` is itself a path.

- profile:

  `character(1)` AWS profile. Default `AWS_PROFILE`.

- read_only:

  `logical(1)` open the store read-only. Default `TRUE`.

- verify:

  `logical(1)` check the local MD5 against the manifest. Default `TRUE`.
  `FALSE` opens a local store without contacting `source` — the only
  supported way to work fully offline.

## Value

A `ragnar` store object, as returned by
[`ragnar::ragnar_store_connect()`](https://ragnar.tidyverse.org/reference/ragnar_store_create.html).

## Details

`source` has **no default value**. Configure it with
`options(cred.store_source = )` or the `CRED_STORE_SOURCE` environment
variable, in the shape `s3://<bucket>/<prefix>/`. Pushing a store is out
of scope for this package — it is a build-side operation performed
rarely by whoever built the store.

## Examples

``` r
if (FALSE) { # \dontrun{
options(cred.store_source = "s3://<bucket>/<prefix>/")
store <- crd_store_connect("vca_refs")
crd_search(store, "bankfull width regression")

# Offline, against a store already on disk
crd_store_connect("vca_refs", verify = FALSE)
} # }
```
