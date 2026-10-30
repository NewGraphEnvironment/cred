# Task: crd_zot_src_lookup(): a key resolves across libraries, to trashed attachments, and to the newest of several PDFs (#40)

## Problem

`crd_zot_src_lookup()` (`R/zotero.R`, cred 0.4.0 and `main`) selects attachments by citation key and keeps the first row per key:

```sql
... WHERE f.fieldName = 'citationKey' AND idv.value IN (...)
    AND ia.contentType IN ('application/pdf', '...docx')
    ORDER BY idv.value, ia.itemID DESC
```

then `raw[!duplicated(raw$citation_key), ]`. Three consequences, each measured on a Zotero database with a personal library and a group library (2026-10-30):

1. **No library filter.** Citation keys are unique within a library, not across them. `hagen_etal2019TrendAbundance` exists in both; the personal copy's attachment has the higher itemID, so it is taken although the build was asked for the group collection. (Here the bytes happen to match; in general the same key names different works in different libraries.)
2. **No trash filter.** Neither the parent nor the attachment is checked against `deletedItems`. For `martins_etal2022SpatialEcology` the newest attachment is a trashed copy, so it is the one ingested.
3. **Newest of several PDFs wins.** `bottoms_etal2023Criticalhabitats` has the report (3.4 MB) and its Appendix 1 (11.4 MB). The appendix is newer, so the store holds the appendix and not the report.

`crd_store_build(collection = ...)` resolves the collection inside one library, so a caller that asks for a group collection reasonably expects every document to come from that library.

## Exploration that shaped the plan


`crd_zot_src_lookup()` and the collection resolver `.crd_zot_collection_pdfs()` (`R/store.R:1450`) join attachments with no library filter and no trash filter. They then keep the first row per key: newest itemID in the lookup, arbitrary order in the resolver. Measured 2026-10-30 on a copy of the live `zotero.sqlite` (quick_check ok):

- The issue's three keys reproduce exactly: hagen (copies in libraries 1 and 9, personal copy taken), martins (trashed attachment 4697 taken), bottoms (Appendix 1, 4689, taken over the report, 4687).
- 331 citation keys exist in more than one library. Personal library 1 also holds 52 keys shared by two live parents each (all `R-*`).
- Collection names repeat across libraries (10 or more), so `collection =` is ambiguous too. `deletedCollections` exists and is ignored.
- Live items with more than one PDF: 11 in library 1, 1 in library 2, 25 in library 9 (up to 10 on one item). Their shapes: report + appendix, 5-part report, report + 9 map sheets, byte-identical copies.
- `bull_trout` (18 members) and `grayling` (30 members): 11 and 7 members respectively have no live PDF and are dropped without a word.
- Zotero's own "best attachment" (`Zotero.Item.prototype.getBestAttachments`, zotero/zotero `item.js`) excludes `deletedItems` and linked URLs and orders by `contentType='application/pdf' DESC, attachment url = parent url DESC, dateAdded ASC`. On bottoms it picks the report.
- `.crd_zot_key_from_path()` maps attachment key → parent → citation key, so ingesting several PDFs per item needs **no naming change**. The issue's worry that it would is unfounded for the current code.
- The toy fixture `inst/extdata/zotero.sqlite` has no `libraries`, `groups`, `deletedItems`, `collections` or `dateAdded`, so the new queries must ship with a regenerated fixture.

## Decided at the gate (user, 2026-10-30)

1. **Library named by group name, groupID, or `"user"`**: new arg `library`, default `getOption("cred.zotero_library")`. These identifiers are portable; internal libraryID is never accepted or persisted.
2. **Ambiguity with no library given**: `crd_store_build(collection=)` **errors** and lists the libraries holding that name. A key found in more than one library, or on more than one live parent in one library, is **left unresolved with a warning** naming the libraries.
3. **Several PDFs**: `crd_store_build()` ingests **every live PDF** of an item, skipping byte-identical copies (md5). `crd_zot_src_lookup()` keeps **one per key by Zotero's rule** and names the files it left out.
4. **`crd_zot_abstract_lookup()` is in scope**, with the same `library` and trash filters. `crd_aud_verify_all()` and `crd_aud_verify_abstract()` pass `library` through.
5. Follow-ups (user): clean up the Zotero mess through issues rather than code workarounds. Library consolidation already has an internal issue, so edit its body with these measurements rather than file a duplicate. File a new internal issue for multi-PDF items (merge appendices into the report, drop identical copies, decide on multi-part reports). This repo is public, so its text names neither by number.

## Phase 1: Fixture and failing tests
- [x] `data-raw/make_toy_zotero.R`: add the real Zotero tables the new queries read: `libraries`, `groups`, `deletedItems`, `deletedCollections`, `collections`, `collectionItems`, `items.dateAdded`, `itemAttachments.linkMode`, and a `url` field. Keep the three existing items in library 1 with unchanged keys and paths, so the vignette and `test-matching.R` are unaffected. Regenerate `inst/extdata/zotero.sqlite`.
- [x] `tests/testthat/helper-zotero.R`: builder for a temp DB in that schema, with cases for:
  - one key in personal and group libraries
  - a trashed attachment that is newest
  - a trashed parent
  - report + newer appendix, with the URL matching the report
  - two byte-identical PDFs
  - a duplicate collection name across libraries
  - a trashed collection
  - members with no key, no PDF, or a standalone attachment
  - two live parents sharing one key
- [x] `tests/testthat/test-zotero.R`: the issue's three defects, ambiguity warnings, library resolution (name, groupID, `"user"`, unknown name errors with the available list), and abstract lookup returning one row per key. Run against `main`'s code and confirm each goes red for the right reason.

## Phase 2: One shared attachment query
- [ ] `R/zotero.R`: `.crd_zot_library(con, library)` → libraryID(s). NULL means all libraries; `"user"` → `libraries.type = 'user'`; numeric → `groups.groupID`; character → `groups.name`; anything else errors and lists the available groups.
- [ ] `R/zotero.R`: `.crd_zot_live_attachments(con, keys = , collection_ids = , lib_ids)` returns every live candidate row with:
  - parent and attachment trash both excluded, linked URLs excluded
  - columns `library`, `parent_key`, `citation_key`, `attachment_key`, `content_type`, `path`, `date_added`, `url_match`
  - Zotero's order, plus the storage path resolution already duplicated in both functions (now one helper).

## Phase 3: `crd_zot_src_lookup()`
- [ ] Add `library = getOption("cred.zotero_library")`. Use Phase 2's query.
- [ ] Ambiguous keys (more than one library, or more than one live parent) are dropped with one warning naming each key's libraries.
- [ ] Keep the first row per key in Zotero order. When an item had other live attachments, one message per key names the file taken and the ones left out.
- [ ] Roxygen: the library arg, the option, and the pick rule.

## Phase 4: `crd_store_build()` and the collection resolver
- [ ] `.crd_zot_collection_pdfs()` gains `library`:
  - errors when the name matches collections in more than one library (lists them) or none
  - excludes `deletedCollections`
  - returns every live PDF per member
  - drops byte-identical copies by `tools::md5sum`
  - returns a left-out table with columns `item`, `title`, `reason`: trashed, no citation key, no live PDF, standalone attachment, note
- [ ] `crd_store_build()` gains `library`. The `citation_keys` path uses the all-PDFs query, not `crd_zot_src_lookup()`'s single pick, and applies the same ambiguity rule and md5 dedupe.
  - Prints the left-out members and the multi-PDF items before ingest.
  - Return value: one row per ingested file, documented as such.
- [ ] Tests on the resolver, offline, in the fixture DB. Ingest is untouched.

## Phase 5: Abstracts and the audit callers
- [ ] `crd_zot_abstract_lookup()`: `library` arg, trash filter, the same ambiguity rule, and one row per key guaranteed.
- [ ] `crd_aud_verify_all()` and `crd_aud_verify_abstract()` gain `library` and pass it through. `devtools::document()`.

## Phase 6: Docs
- [ ] `CLAUDE.md`: the Zotero Integration section (library scoping, trash, pick rule, store ingests all live PDFs) and the architecture lines.
- [ ] Vignette: one sentence on `cred.zotero_library` where the lookup is introduced. Confirm it still builds against the regenerated fixture.

## Phase 7: Follow-up issues (internal repo)
- [ ] Edit the internal library-consolidation issue's body with: 331 cross-library keys, 52 two-parent keys in the personal library, duplicate collection names, and the `cred.zotero_library` option that works around them until consolidation.
- [ ] File an internal issue for the 37 multi-PDF items, with the per-library table and shapes, proposing merge / drop-duplicate / keep-parts verdicts per item.

## Owed at the end (reported, done after merge)
- [ ] Set `options(cred.zotero_library = "NewGraphEnvironment")` in each build machine's R profile. This changes the machines, so it is the user's step.
- [ ] Release bookkeeping (NEWS, version bump) by `/gh-pr-merge`.

## Validation
- [ ] Tests pass (`devtools::test()`), 0 lints, `devtools::check()` with no new WARNING/NOTE
- [ ] `/code-check branch` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

**Verification:**
- The Phase 1 tests are red on `main` and green after.
- Live check against a copy of `zotero.sqlite`: the issue's reprex with `library = "NewGraphEnvironment"` returns the group copy of hagen, the untrashed martins PDF, and the bottoms report, with a message naming the appendix. With `library = NULL`, hagen is warned about and left out.
- `.crd_zot_collection_pdfs("bull_trout", library = "NewGraphEnvironment")` lists the 11 members it leaves out, with reasons.
- `devtools::build_vignettes()` passes on the regenerated fixture.

