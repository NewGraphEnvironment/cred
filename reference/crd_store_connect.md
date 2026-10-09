# Connect to a ragnar evidence store, pulling and verifying it if needed

Resolves a store by name, using the local copy when its MD5 matches the
shared manifest and downloading it from `source` otherwise. Verification
is the point: a store that is present is not thereby trustworthy, and a
silent local rebuild produces an artefact that looks perfectly healthy.

## Usage

``` r
crd_store_connect(
  store,
  source = getOption("cred.store_source"),
  dir = "data/rag",
  profile = Sys.getenv("AWS_PROFILE"),
  read_only = TRUE,
  verify = TRUE,
  check_model = TRUE
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
  supported way to work without the bucket. It does **not** by itself
  make the call fully offline: `check_model` still probes the embedding
  service, which for an Ollama-built store is localhost. Pass
  `check_model = FALSE` as well for a call that touches nothing.

- check_model:

  `logical(1)` compare the store's embeddings against what its recorded
  embedder now returns, and its model label against the manifest.
  Default `TRUE`. A confirmed width mismatch is an **error**; pass
  `FALSE` to open such a store anyway, which is a reasonable thing to
  want — BM25 retrieval needs no embedding and is unaffected by the
  mismatch.

## Value

A `ragnar` store object, as returned by
[`ragnar::ragnar_store_connect()`](https://ragnar.tidyverse.org/reference/ragnar_store_create.html).

## Details

**Two independent checks, because one cannot do both jobs.**

The **MD5 compare** answers "is this the file the manifest describes" —
a stale copy, a truncated download, a local rebuild nobody pushed. It is
structurally unable to see a store whose *embedding model* has moved
underneath it, because that store's bytes are exactly the ones the
manifest recorded.

The **embedding check** (`check_model`) is what sees that. It runs the
store's own recorded embedder — ragnar unserialises it out of the store
— and compares the width it returns against the width the store holds. A
disagreement is an error: semantic retrieval against such a store would
answer differently while looking healthy. It also compares the
manifest's `embedding_model` label against the store's own record, which
is a warning, the label being the weaker of the two.

**What neither sees** is a model whose weights changed while its
dimension stayed the same. No check in this package can detect that.

A mismatch that arises *after* a successful connect — the model
re-pulled mid-session, or `@embed` replaced on the store object — is
outside both, and still surfaces downstream as a
`cred_retrieval_fallback_dimension` warning from
[`crd_search()`](https://newgraphenvironment.github.io/cred/reference/crd_search.md);
see "Diagnosing a fallback" there. So does any mismatch on a store
opened with `check_model = FALSE`, or one whose probe could not run. The
two layers are complementary, not redundant
(NewGraphEnvironment/cred#30).

**The embedding check executes code recorded in the store.**
`embed_func` is deserialised and called. On the `verify = TRUE` paths
the manifest's MD5 vouches for those bytes; under `verify = FALSE`
nothing does. And ragnar pins only the *model* into that function, not
`base_url`, so for a store built against Ollama the probe never leaves
the machine — while a store built with
[`ragnar::embed_openai()`](https://ragnar.tidyverse.org/reference/embed_ollama.html)
or an explicit remote `base_url` makes a billed third-party request on
every connect. `check_model = FALSE` is the opt-out.

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
