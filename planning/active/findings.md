# Findings — crd_zot_src_lookup(): a key resolves across libraries, to trashed attachments, and to the newest of several PDFs (#40)

## Issue context

**If done:** `crd_store_build()` ingests, for each citation key, the PDF of the item in the library it was asked about, never a trashed file, and says which file it took when an item has several. **If never:** a store can silently hold another library's copy, a file the user deleted, or an appendix in place of the report, and nothing in the build output says so.

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

## Reprex

```r
keys <- c("hagen_etal2019TrendAbundance", "martins_etal2022SpatialEcology",
          "bottoms_etal2023Criticalhabitats")
cred::crd_zot_src_lookup(keys)
# src_path for each: the personal-library copy, the trashed copy, the appendix
```

## Options as we see them

- Take a `library_id` (or group id) and restrict the lookup to it; `crd_store_build(collection = )` passes the library its collection resolved in.
- Exclude `deletedItems` for both the parent item and the attachment.
- For several live PDFs on one item, either ingest each as its own document (named `<key>` plus a suffix) or pick by a stated rule and **report** the ones left out. Ingesting all keeps appendices searchable; the choice changes document naming, so it is a design call.
- Related, possibly the same change: `crd_store_build()` could report every collection member it leaves out and why (no citation key, no PDF, a standalone attachment). Today a caller learns of a missing paper only by searching for it.

Found while preparing a bull trout and Arctic grayling store from two group collections.


## Measurements (2026-10-30, copy of live zotero.sqlite, quick_check ok)

| measure | value |
|---|---|
| citation keys in more than one library | 331 |
| live keys on 2+ parents within one library | 52, all library 1 (`R-*` package refs) |
| collection names in 2+ libraries | 10 or more |
| live items with >1 PDF | lib 1: 11 (max 5), lib 2: 1, lib 6: 0, lib 9: 25 (max 10) |
| `bull_trout` members / left out | 18 / 12: 3 trashed, 1 standalone, 8 keyed with no live PDF (reviewer recount; first count did not add up) |
| `grayling` members / left out | 30 / 13: 5 trashed, 3 standalone, 5 keyed with no live PDF (reviewer recount) |

Issue's three keys, rows ordered as the current SQL orders them (itemID DESC):

- hagen: lib 1 att 4064 (taken), lib 9 att 3702.
- martins: lib 9 att 4697 **trashed** (taken), 3496 live.
- bottoms: lib 9 att 4689 Appendix 1 (taken, newer), 4687 the report (URL matches the parent).

## Zotero's best-attachment rule

`Zotero.Item.prototype.getBestAttachments`, zotero/zotero `chrome/content/zotero/xpcom/data/item.js` (main at 661843b03f):

```sql
SELECT IA.itemID FROM itemAttachments IA NATURAL JOIN items I
LEFT JOIN itemData ID ON (IA.itemID=ID.itemID AND fieldID=<url>)
LEFT JOIN itemDataValues IDV ON (ID.valueID=IDV.valueID)
WHERE parentItemID=? AND linkMode NOT IN (<LINKED_URL = 3>)
AND IA.itemID NOT IN (SELECT itemID FROM deletedItems)
ORDER BY contentType='application/pdf' DESC, value=? DESC, dateAdded ASC
```

On the multi-PDF items in lib 9 it picks the main document in most cases. A known miss is
`finsconsultingltd_2001Reconnaissance1`, whose map sheets were attached 19 s before the report.
So the store ingests every live PDF and the audit takes the single best one.

## Naming does not change when several PDFs are ingested

`.crd_zot_key_from_path()` resolves origin → attachment key (directory name) → parent →
citationKey, so every PDF of one item comes back as the same citation key. The issue's
"the choice changes document naming" does not hold for the current code.

## Related work (internal, described rather than linked: this repo is public)

- An internal issue on consolidating the libraries into one. Its body gains the measurements above.
- Internal work on keying the store corpus by parent item key and library. This change does not conflict with it, because it keeps the attachment-key origins.

## Phase 1: the fixture reaches each defect on main

On `main`, `crd_zot_src_lookup()` run against `zot_fixture()` with no `library` takes:
`martins_trashed.pdf`, `bottoms_appendix1.pdf`, `gone.pdf` (trashed parent), `web.pdf`
(linked URL) and `rbase_b.pdf` (one of two parents sharing a key). Each is the defect its
test asserts against. The new tests error on `main` mostly as `unused argument (library =)`,
because the API is new. The fixture is what shows that they reach the failure.

## Errors Encountered

| Error | Resolution |
|-------|------------|
