## Outcome

Added `crd_store_push()` — the write half of the shared-manifest contract, closing a deferral loop
in which cred#22 pointed at rtj#194 for this code and rtj#194 pointed back at cred#22, so neither
owned it. The defect it fixes was live: the only committed push rebuilt `log.json` from the current
run alone and overwrote the remote copy, silently orphaning every other store.

Three refusals, each closing a distinct way the manifest gets corrupted: an unreadable manifest
aborts the push; every write is conditional (ETag on update, `--if-none-match "*"` on create); and a
store whose embedding differs from the corpus is refused.

What the work turned up that the issue did not anticipate:

- **`aws s3 cp` cannot distinguish a missing key from a nonexistent bucket** — identical exit code
  and message. Absence has to be established with `s3api head-bucket` + `head-object`, and even
  then `create_manifest` stays an explicit flag, because a wrong prefix produces the same 404.
- **`jsonlite` renders `NA_integer_` as the string `"NA"`, not `null`** — only the numeric types,
  and into a different JSON type. A store with an unreadable `COUNT(*)` would have lodged
  `"documents": "NA"` in the shared manifest permanently.
- **The embedding model was being read from the environment.** Round 2 showed the guard could not
  fire in the case it was written for: nomic-embed-text and embeddinggemma are both 768-dimensional,
  and nothing in the package ever sets `CRED_EMBED_MODEL`, so it compared a default against itself.
  The ground truth was one column away — `metadata.embed_func` unserializes to the closure that
  built the store. Fixing that then introduced a false positive against the live manifest
  (`nomic-embed-text` vs `nomic-embed-text (ollama)`), caught by running against real data.

Two review rounds found seventeen issues, all real. The pattern worth remembering: the most
dangerous ones were not wrong logic but **wrong failure direction** — a probe failure read as
absence, a dropped precondition, a guard that silently skipped. Each looked correct and passed
every test.

Deliberately out of scope: bucket policy, IAM, retention and the field runbook (rtj#194);
content-addressed store keys, which would remove the binary/manifest window but change the shared
bucket layout; retiring `0157-rag-sync.R`, which lives in `fish_passage_template_reporting`.

**No live push was performed** — the dry run and unit tests prove the merge, but writing to the
shared bucket is an infrastructure change left for a human to trigger.

Closed by: PR for issue #24
