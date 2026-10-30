# Code-check round 3: #40 (branch `40-crd-zot-src-lookup-a-key-resolves-across`, HEAD 8b43b8c)

## Checklist read

- `index_code-check.md`, `index_code-check-r.md`, `index_code-check-shell.md`, `index_code-check-spatial.md`: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with table rows skipped. The other 23 headings (standalone rules, Security, Spreadsheets/PDFs) were read at index level only.
- `code-check-r.md`: 8 sections read in full: "A database driver's value is not a base R type — and it fails twice"; "A library call that dispatches on a global option is not a pure function"; "Cross-function consistency for label/string normalization"; "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are"; "`data.frame()` recycles a scalar against a zero-length column"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"; "`expect_message(expr, regexp)` checks only the FIRST condition, so a progress line hides the message under test"; "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent". The other ~107 were read at index level only.
- `code-check-shell.md`: index only (0 sections read in full). The diff has no shell.
- `code-check-spatial.md`: index only (0 sections read in full). The diff has no spatial code.

All probes ran in a copy (`scratchpad/rv3/repo`) through `pkgload::load_all()` against `zot_fixture()`. `~/Zotero/zotero.sqlite` was not opened.

## Findings

- **[severity: fragile]** R/zotero.R:160-161 (`.crd_zot_resolve_keys`, the `cred_zot_ambiguous` warning). One remedy is printed for every ambiguity: "Pass `library`, or set options(cred.zotero_library = )". It is the right remedy only for a key found in more than one library. For a key shared by two live items **within** one library, it is a remedy that cannot work. The loop just above it already tells the two cases apart ("in more than one library" vs "on N items in <lib>"), but the header does not. Following the advice changes nothing, because the duplicate is in the Zotero data and has to be fixed there (the key re-generated, or the duplicate items merged).
  - This always happens on the collection path that R2's fix added: `.crd_zot_collection_pdfs` calls the resolver with `hits$library_id`, which is never NULL, so every ambiguity it can raise is a within-library one.
  - Probe: `crd_zot_src_lookup("R-base", library = "user")` and `.crd_zot_collection_pdfs("rpkgs", library = NULL)` both print `Pass \`library\`, or set options(...)` above `R-base: on 2 items in My Library`. The caller had already passed a library in the first, and the library was pinned to the collection's in the second.
  - Untested: replacing the remedy line with `XXX` leaves `test-zotero.R` at 0 failures of 34. The tests assert only `"R-base.*2 items"`, the interpolated part.
  - Fix: give the within-library case its own remedy (fix the key in Zotero), and print "Pass `library`…" only when some listed key spans libraries.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "An assertion that matches an interpolated value cannot see the claim around it"

- **[severity: fragile]** R/audit.R:900-929 (`crd_aud_verify_abstract`). The summary message counts every key whose abstract came back `NA` as "keys with no abstract in Zotero". Since this branch, `NA` also means "left unresolved" (ambiguous, or only in another library). `crd_zot_abstract_lookup()` keeps the two apart on purpose (R/zotero.R:395, `setdiff(..., resolved$unresolved)`), and this caller merges them back together.
  - Probe: `hagen2019Trend` has an abstract in both My Library and Central. `crd_aud_verify_abstract(library = NULL)` prints the ambiguity warning and then `Abstract matching: 0 matched, 1 keys with no abstract in Zotero.` That states something false about the user's Zotero for the key that most needs attention.
  - On main this could not arise, because no key was ever unresolved.
  - Fix: count unresolved keys apart from keys with no abstract (the lookup can return or attribute them), or word the count as "no abstract found or key unresolved".
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" ; code-check.md "One fact derived twice"

- **[severity: fragile]** R/store.R:1677-1686 (`crd_store_build` roxygen, which becomes `man/crd_store_build.Rd`). Two statements of the left-out policy were not updated when R2 added a reason.
  1. "lists every item it leaves out and why (trashed, a note, a standalone attachment, no citation key, no live PDF)". The code can now also give "citation key shared by several items" on the collection path, and "not found in Zotero" or "unresolved (see warning)" on the key path. "Every … and why" followed by a closed list is a quantified claim, and the list is short by three.
  2. "A key found in more than one library is left out with a warning". It omits the within-library duplicate, which is the case R2 added to the collection path, and a key found only in another library than the one asked for.
  - This is R2's prose finding again, one function over: the pick-rule prose was updated in every place it is stated, but the reason set has a fourth home that the enumeration did not list.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "Documentation Staleness"

## Mechanism and enumeration

**Mechanism.** One rule is defined in one place, and a second place restates it. The restatement agrees with the definition only on the cases its author had in front of them. Every finding so far is this shape. They come in two variants.

1. **Restating an external rule through a proxy** that the hand-built fixture happened to make true. "Has no `groups` row" stood in for "is My Library", because the fixture had no feed. "`= purl.value`" stood in for Zotero's `getField('url')`, because the fixture's URL-less parents had URL-less attachments. "Declared TEXT" stood in for "comes back character", because the fixture typed a column Zotero leaves untyped. "Every collection has members" held because the fixture never had an empty one.
2. **Restating this package's own policy in a second consumer**, which did not follow when the policy gained a case. The policy decided once in `.crd_zot_resolve_keys` is: one live item per key per library, refuse otherwise, and keep "unresolved" apart from "absent". Its other consumers are the collection path (R2), the prose (R1, R2), a test leaning on a global option (R2), and, this round, the warning's remedy, `verify_abstract`'s count, and `crd_store_build`'s reason list.

In both variants, two lists agree only by coincidence: the fixture's data and Zotero's, or the resolver's outcomes and each consumer's vocabulary for them.

**Enumeration, per candidate set:**

(a) Every query that binds a citation key to an item:
- `.crd_zot_resolve_keys`: **holds**. It is live-only, library-scoped, refuses ambiguity and casts.
- The collection member query, now routed through the resolver: **holds**. Mutation check: removing the `"citation key shared by several items"` assignment fails exactly one test, "a collection leaves out a member whose key another live item shares".
- `crd_zot_abstract_lookup`'s abstract query binds by the resolver's `item_id`: **holds**.
- `.crd_zot_attachments` binds by parent `item_id`, not by key: **holds**.
- `.crd_zot_key_from_path`: accepted as out of scope. It holds in practice now that every ingested parent's key is unique in its library.

(b) Every statement of the pick rule: zotero.R:172-179 (internal roxygen), zotero.R:257-261 (exported roxygen), zotero.R:323 (message), man/crd_zot_src_lookup.Rd:55 (regenerated, matches), CLAUDE.md:107-108. **All hold**, and so does the comment in the helper-zotero.R fixture.

(c) **Added: every statement of the resolution/left-out policy.** These are the consumers of the resolver's outcomes:
- Resolver roxygen; `crd_zot_src_lookup` and `crd_zot_abstract_lookup` roxygen; `.crd_zot_collection_pdfs` roxygen; CLAUDE.md:97-103: **hold**.
- The `crd_aud_verify_abstract` `@param library` text ("more than one library … left NA") is narrower than the code but true: **holds**.
- `crd_zot_src_lookup`'s "No attachment found" warning excludes unresolved keys: **holds**.
- `crd_store_build`'s "Leaving out" message reads the reason per row: **holds**.
- The resolver's remedy line: **does not hold** (finding 1).
- `verify_abstract`'s summary count: **does not hold** (finding 2).
- `crd_store_build`'s roxygen reason list and "Which library" sentence: **do not hold** (finding 3).

(d) **Added: every place a library is identified or labelled.**
- `.crd_zot_library`: "user" by `type` with a length-1 assertion; groupID numerically; name with refusal on 0 or more than one match. **Holds**.
- `.crd_zot_libraries` labels: `user` → "My Library", group → "name (groupID)", a feed → "feed <id>". **Holds**.
- `bad()` lists groups only. **Holds**.
- The resolver's `label()` and the collection path's `where()` both go through `libs$label`. **Holds**.
- The roxygen `@param library` ("groupID … as in its URL"). **Holds**.

`lib_id` is length 1 on every non-NULL return, so the R1 recycling cannot recur.

(e) **Added: every exported function's empty-result and NA types.**
- `crd_zot_src_lookup`: typed `empty`, casts. **Holds**.
- `crd_zot_abstract_lookup`: `NA_character_` start, cast. **Holds**.
- `crd_store_build` stops when nothing resolves. Its `left_out` and `sources` stay typed when empty: the key-path `row()` builds at full length, the collection path casts. **Holds**.
- `crd_search`'s `citation_key`, through `.crd_zot_key_from_path`, returns early on 0 rows. **Holds**.
- `tools::md5sum(character(0))` is a named `chr(0)`, so the dedup over an empty `att` is safe. **Holds**.

(f) **Added: every test or example that depends on `cred.zotero_library`.**
- test-zotero.R has 7 calls that omit `library` (lines 22, 32, 200, 213, 305, 339, 350), and every one sits in a block that pins the option.
- test-matching.R passes `library = "user"`.
- test-store.R's `crd_store_build` calls stop before library resolution.
- The vignette's evaluated chunk passes `library = "user"` and `sources =`.
- The exported Zotero examples pass `library = "user"`, and the audit examples are `\dontrun`.
- **Holds.**

(g) **Added: every reimplementation of a Zotero rule, against Zotero.**
- `libraries.type` values: **hold**.
- `COALESCE(purl.value, '')` against `getField('')`: **holds**.
- Attachment `dateAdded` (Zotero's `NATURAL JOIN items` is the attachment's row): **holds**.
- Trashed parent, attachment, collection and member: **hold**.
- `(linkMode IS NULL OR linkMode <> 3)` against Zotero's `linkMode NOT IN (3)`: these differ only for a NULL `linkMode`, which Zotero never writes. **Holds in practice.**
- Non-recursive collections: by design.

## Checked and not raised

- `suppressWarnings(classes = )` (R/audit.R:894) needs R >= 4.0.0, and DESCRIPTION declares no `Depends: R`. The current Imports already pull R >= 3.6 or newer in practice, so this is not raised.
- Most messages show a feed's internal `libraryID` ("feed 9"). This is cosmetic: a feed holds no citation keys, so it never resolves.
- A standalone attachment that carries an attachment note has an `itemNotes` row, so it is labelled "note" rather than "standalone attachment". This is cosmetic, and either way the item is left out.
- In `crd_zot_src_lookup`'s "left out" message, an attachment with a NULL path prints as "NA (not on disk)". This is cosmetic.
- The test name "a parent/child path picks one of several same-named collections" (test-zotero.R:308) tests library separation, not a path, but the comment inside says so. The `project/sub` test covers the path itself.
