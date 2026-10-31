# Zotero's SQLite database: what cred relies on

**Verified:** 2026-10-30 · **Issues:** #40 · **Produced by:** read-only queries on a copy of a
live `zotero.sqlite` (7 libraries), and Zotero's source (`chrome/content/zotero/xpcom/data/item.js`, main at
`661843b03f`).

## Libraries

- `libraries.type` is `user`, `group` or `feed`. A feed has no `groups` row, the same as My
  Library, so "has no group" does not mean My Library; select `type = 'user'`.
- `libraryID` is a row number in one machine's database. A group's portable identity is
  `groups.groupID` (the number in `zotero.org/groups/<groupID>`) or its name. `groups.name` has
  no UNIQUE constraint.

## Keys, values and the trash

- Better BibTeX stores citation keys as the `citationKey` field. A key is unique within a library
  at best. In the measured database, 331 keys sat in more than one library, and 52 were shared by two
  live items within one library.
- `itemDataValues.value` has no declared type (`value UNIQUE`), so through RSQLite an empty
  or all-NULL result comes back logical. Each distinct value is stored once and its `valueID`
  is shared.
- The trash is `deletedItems` (items and attachments, independently) and `deletedCollections`.
  A trashed parent can keep a live attachment, and the reverse.
- Collection names repeat within a library as well as across libraries. `parentCollectionID`
  gives the path. A collection's subcollection members are not its members.

## Which attachment Zotero opens

`Zotero.Item.prototype.getBestAttachments`:

```sql
SELECT IA.itemID FROM itemAttachments IA NATURAL JOIN items I
LEFT JOIN itemData ID ON (IA.itemID=ID.itemID AND fieldID=<url>)
LEFT JOIN itemDataValues IDV ON (ID.valueID=IDV.valueID)
WHERE parentItemID=? AND linkMode NOT IN (3)            -- 3 = linked URL
AND IA.itemID NOT IN (SELECT itemID FROM deletedItems)
ORDER BY contentType='application/pdf' DESC, value=? DESC, dateAdded ASC
```

The `?` in the ORDER BY is the item's `getField('url')`, which is `''` when unset. Combined with
SQLite sorting NULL last under DESC, the URL step ranks the item's own URL first, then any other
URL, then no URL. `dateAdded` ties are common on bulk imports, so cred adds itemID as a final key.

`linkMode`: 0 imported file, 1 imported from URL, 2 linked file (path absolute, or
`attachments:` relative to a base directory held in `prefs.js`, not in the database), 3 linked URL.
