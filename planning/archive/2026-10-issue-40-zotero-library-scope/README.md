## Outcome

Zotero lookups now resolve within one library, never to the trash, and pick attachments by a
stated rule.

- **Library.** `crd_zot_src_lookup()`, `crd_zot_abstract_lookup()`, `crd_store_build()` and the
  two audit verifiers take `library` (`"user"`, a group name or a groupID; default
  `getOption("cred.zotero_library")`).
- **Ambiguity.** A key matching more than one live item, or found only in another library, is
  left unresolved with a warning that carries a remedy for its case. A collection name matching
  several collections is an error listing their paths.
- **Attachments.** The audit takes the attachment Zotero itself opens. A store takes every
  live PDF of an item and lists each member it leaves out, with the reason.

What was learned: almost every defect after the first commit had the same shape. A rule is
defined once and restated somewhere else, and the restatement is checked only against the
cases its author had in front of them. The plan review and three code-check rounds found 11
such restatements: the trash and feed proxies, the URL comparison, the empty-result types, and
consumers of the resolver's policy that did not follow when it grew. The loop ended on an
enumeration of every set that mechanism reaches (`findings.md`). The settled facts about
Zotero's schema are in [`research/zotero-sqlite.md`](../../../research/zotero-sqlite.md).

## Measurement

Measured on a copy of a live `zotero.sqlite`, 2026-10-30:

- **Key scatter.** 331 citation keys sit in more than one library, and 52 are shared by two
  live items within one library. One collection name matches 15 collections across two
  libraries.
- **Several PDFs.** 36 items in the two main libraries have more than one live PDF (93 PDFs in
  all). None is byte-identical to another.
- **Verification on that database.** The issue's three keys now resolve to the group copy, the
  untrashed PDF and the report rather than the appendix. A 20-member collection yields 10 PDFs,
  with the 10 members it leaves out listed by reason.
- **No change elsewhere.**
  - The vignette's verification statuses are identical to `main`'s (10 auto, 4 abstract_match,
    5 no_match).
  - `R CMD check` findings are identical to `main`'s.
  - 720 tests pass.
  - 15 of 15 guard mutations were caught.

## Owed

- Set `options(cred.zotero_library = "NewGraphEnvironment")` in each build machine's R profile. This changes the machines, so it is the user's step.
- Release bookkeeping (NEWS, version bump) by `/gh-pr-merge`.

Closed by: PR (opened next) for #40
