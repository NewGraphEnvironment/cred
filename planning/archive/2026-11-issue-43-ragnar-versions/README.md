# #43: cred supports CRAN ragnar >= 0.4.0, and what 0.4.0 does to an older store

## Outcome

cred took ragnar from an unpinned `Remotes: tidyverse/ragnar`, so CI tested ragnar's main branch while
users ran a release. It now requires CRAN `ragnar (>= 0.4.0)`, and `.crd_need()` refuses an older
loaded ragnar, naming both versions. Measuring stores across versions showed that every ragnar reads
every store. ragnar 0.4.0, though, upgrades a pre-0.4.0 store in place on any read-write connect, and
0.3.x cannot ingest into an upgraded store. So `crd_store_connect(read_only = FALSE)` now warns first,
`crd_store_update()` rebuilds the index on every copy it keeps, and the manifest records
`ragnar_version` (stamped into the store's own `cred_ragnar` table by build and update) and
`store_schema`. The durable verdict is `research/ragnar-versions.md`. Three things were learned on the
way. The upgrade drops the HNSW index metrics, a ragnar defect, drafted for upstream in
NewGraphEnvironment/ragnar#3 and not sent. A hand-built old-schema fixture needs its indexes created
with their metric, and its foreign-key table created under its final name. And the code review's
three rounds each found a case one direction or one path short of the whole set, so the review ended
on an enumeration (a 12-case table test for the manifest fallback, and the branches that rebuild the
index on a kept copy).

## Measurement

- **Matrix** (4 builders: 0.3.0, 0.3.0.9000, 0.3.1, 0.4.0; 4 openers; read-only and read-write; duckdb
  1.5.6): all 32 opens connect and retrieve, and a read-only open keeps the md5. A read-write open by
  0.4.0 of a pre-0.4.0 store upgrades it (3 columns added, the foreign key dropped, 3 HNSW indexes
  kept), and insert, ingest and both delete styles work. 0.3.x ingesting into a 0.4.0-format store
  fails (`Binder Error ... "excluded" has 3 columns available but 6`). Before the upgrade, a
  one-transaction delete is refused by the foreign key.
- **Real stores** (pine 28.6 MB, statistics 94.6 MB, built under 0.3.x, `nomic-embed-text`): the stored
  embedder runs under 0.4.0 (width 768). A read-write open that writes nothing grows the files to
  52.7 MB and 175.4 MB (about 1.85x) in 0.3 s and 2.1 s, and changes the md5. Under 0.3.0.9000 the
  same open changed neither. Retrieval before and after returns the same chunks and BM25 scores.
  `COPY FROM DATABASE` compacts the upgraded pine copy to 27.8 MB, keeping its 3 HNSW indexes (#50).
- **HNSW metrics:** an `EXPLAIN` of a top-k query against a constant vector uses an HNSW scan for
  cosine, inner product and L2 before the upgrade, only for L2 after it, and for all three after
  `ragnar_store_build_index()`. A first probe that ordered by a subquery could not use any index, so
  it told nothing apart; the constant-vector probe replaced it.
- **Validation** on `4b296eb`: 965 tests pass, 0 fail, 2 pre-existing docx skips. `R CMD check` shows 0
  errors and the three WARNINGs that predate the branch. lintr reports 0.

These numbers changed the design. The size growth and the md5 change are why the read-write connect
warns rather than staying silent (the owner's choice over refusing). The lost metrics are why every
kept update copy rebuilds its index.

## Evidence

`data-raw/logs/ragnar_store_compat/20261118_*` (produced by `data-raw/ragnar_store_compat.R`). The
real-store probe scripts are inline in `findings.md`.

## Owed

- After the tagged release, comment on knowledge#223 that cred supports ragnar 0.4.0, and that
  anyone on cred 0.7.0 or older must update before the first upgraded or rebuilt store is pushed.
- Show the owner the upstream draft (findings.md, "HNSW metrics lost"): ragnar 0.4.0's upgrade
  drops the HNSW metrics. It goes through a fork issue first (filed: NewGraphEnvironment/ragnar#3);
  nothing is posted without the owner's word.

Closed by: PR (opened from branch `43-ragnar-s-development-branch-changes-inge`)
