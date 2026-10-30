# Code-check round 1: branch diff a83681c...HEAD (#40)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms` in full, with table rows skipped. The other 23 H3s (Rules that stand alone, Security, Spreadsheets and PDFs) were read at index level only.
- **code-check-r.md**: 28 of 115 sections read in full: Regenerated binaries churn git; Tests that silently do not run; testthat counts an uncaught error under `error`; `$` on a list partial-matches; A database driver's value is not a base R type; Inserting a helper between a roxygen block and its function; open_dataset / duckdb dedup (both incidental to the range I read); `nzchar(NA)`; `paste()` with a zero-length argument; Under `R CMD check`, tests run from a temp dir; `dbConnect(SQLite(), path)` CREATES the file; `sort()`/`order()` collate by `LC_COLLATE`; `tryCatch(warning = )` DISCARDS the value; Do not abort inside a handler for a C++ warning; `match()` treats NA as a matchable VALUE; `expect_message(expr, regexp)` checks only the FIRST condition; `unlist()` prefixes a `split()` group's name; `[[` on a named ATOMIC vector; `data.frame()` recycles a scalar against a zero-length column; A `pkg::` call in a test; testthat 3e `expect_message()` returns the condition; `c()` dispatches on its first argument; `bind_rows()` of all-`NULL`; A `function(...)` mock; `expect_message(regexp = "...$")`; `ifelse()` with an all-NA test; `sub()` takes one replacement. The other 87 were read at index level only.
- **code-check-shell.md**: index only, because the diff has no shell. 0 of 70 sections read in full.
- **code-check-spatial.md**: index only, because the diff has no spatial code. 0 of 93 sections read in full.

All probes ran in a copy of the repo (scratchpad `rv1/repo`) through `pkgload::load_all()`, using the `zot_fixture()` from `helper-zotero.R` with one change made per probe. The only access to `~/Zotero/zotero.sqlite` was a read-only `immutable=1` open.

## Findings

- **[severity: bug]** R/zotero.R:503 (`.crd_zot_library`), with the effect landing at R/zotero.R:557,567 and R/store.R:1476 (`hit & colls$library_id == lib_id`). `library = "user"` resolves to `libs$library_id[is.na(libs$group_id)]`, which means "every library with no `groups` row". Zotero's `libraries` table also holds **feed** libraries (`type = 'feed'`, one row per RSS subscription), and feeds have no `groups` row. So for anyone with a feed subscription, `lib_id` comes back with length > 1. The `hits$library_id == lib_id` and `colls$library_id == lib_id` comparisons then recycle position by position, so whether a row is kept depends on its position, not on its library.
  - Reproduced by adding one `INSERT INTO libraries VALUES (2, 'feed')` to the fixture. `crd_zot_src_lookup(c("hagen2019Trend", "R-base"), library = "user")` returned **one R-base item, with no warning**: the two live R-base items fell on alternating TRUE/FALSE positions, so the ambiguity guard never saw two. That silent pick is the exact failure #40 exists to stop.
  - In the same setup, `.crd_zot_collection_pdfs("species", library = "user")` errored `No Zotero collection 'species' in My Library in My Library.` for a collection that exists. The feed is also labelled "My Library" in every message.
  - The user's own database has a `feeds` table but no feed rows today, which is why nothing has shown it. Neither fixture has a feed row, so the tests cannot reach this.
  - Fix: select on what the library is, not on whether a group row is missing. Either `libs$library_id[libs$type == "user"]` with `l.type` selected, or `WHERE l.type IN ('user', 'group')` in `.crd_zot_libraries`. Assert that the result has length 1.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A fixture that cannot reach the failure mode"

- **[severity: bug]** R/zotero.R:632 (`.crd_zot_attachments` ORDER BY `aurl.value = purl.value DESC`). This is not Zotero's `getBestAttachments` order whenever the parent item has no URL. Zotero binds `this.getField('url')`, and `getField` returns `''` for an unset field: `value = (value !== null && value !== false) ? value : ''` in item.js, current `main`. So in Zotero, `value = ''` is `0` for an attachment that has a URL and `NULL` for one without. `DESC` then puts every attachment with a URL ahead of every attachment without one. cred compares against `purl.value`, which is `NULL` for such a parent, so every attachment ties and the oldest wins.
  - Reproduced with parent 300 (no URL), PDF 301 (older, no URL) and PDF 302 (newer, with a URL). Zotero's own SQL, run against the fixture with `''` bound, returns `302 301`. `crd_zot_src_lookup()` took `f301.pdf`.
  - This is the common shape: a PDF saved by the connector carries its download URL, while a manually added PDF and many parents carry none. The audit therefore picks a different file from the one Zotero opens.
  - The roxygen ("then the attachment whose URL is the item's own, then the oldest") and the CLAUDE.md bullet describe the reimplementation, not Zotero. The fixtures cannot see the difference: every case whose parent lacks a URL (`dup2018Copies`, `tie2021Same`, `martins2022Spatial`) also has attachments with no URL.
  - Fix: `aurl.value = COALESCE(purl.value, '') DESC`.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode" ; code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: bug]** R/store.R:1523 (`members$reason <- NA_character_` in `.crd_zot_collection_pdfs`). A collection that exists but has no direct members makes `members` a 0-row frame. Assigning a length-1 value to it then errors `replacement has 1 row, data has 0`, inside the helper and before the `left_out` report or the `No PDF attachments resolved to ingest.` stop can run.
  - The non-recursive design makes this the likely case: a parent collection whose items all sit in subcollections. Reproduced: `collections` rows `project` and `project/refs`, with the one item in `refs`. Both `.crd_zot_collection_pdfs("project", ...)` and `crd_store_build(collection = "project", ...)` fail with that message, while `"project/refs"` works.
  - Main gave `No PDF attachments found in Zotero collection 'project'. Check the collection name...`.
  - Fix: `members$reason <- rep(NA_character_, nrow(members))`, or return early on `nrow(members) == 0L` with a message saying that subcollections are not included.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things" ; code-check-r.md "`data.frame()` recycles a scalar against a zero-length column"

- **[severity: fragile]** R/zotero.R:850-855 and R/zotero.R:932-947. Exported return types degrade to logical on the empty or no-value paths, where main returned typed columns.
  1. `src_type = ifelse(best$content_type == .crd_zot_pdf, "pdf", "docx")` is `logical(0)` whenever nothing resolves on disk. The zero-length test selects neither branch. Main returned the typed `empty` tibble for this case.
  2. On a real Zotero database, `itemDataValues.value` is declared with **no type** (`value UNIQUE`, confirmed read-only on `~/Zotero/zotero.sqlite`). RSQLite therefore types a 0-row `idv.value AS citation_key` as logical, and `citation_key` comes back as `logical(0)` when no key resolves.
  3. `crd_zot_abstract_lookup()`'s `abstract` column is replaced wholesale by `raw$abstract[...]`, which is logical when no resolved item has an abstract. Main assigned `NA_character_` in that case.
  - Reproduced with the fixture's `itemDataValues` declared untyped: `crd_zot_abstract_lookup("martins2022Spatial", library = "Central")$abstract` is `logi NA`, and `crd_zot_src_lookup("nosuch", library = "Central")` has `citation_key: logi(0)` and `src_type: logi(0)`. Even on the typed toy database, `src_type` is `logi(0)`.
  - The package's own callers survive: `verify_all` returns early on 0 rows, and `verify_abstract` only tests `is.na`. A user's `dplyr::left_join(audit, sources, by = "citation_key")` fails with `Can't join ... incompatible types`, and `bind_rows()` across runs fails `Can't combine <logical> and <character>`.
  - The fixtures declare `value TEXT NOT NULL`, so the tests cannot reach the untyped column.
  - Fix: return the typed `empty` tibble when `nrow(best) == 0L`, and assign `as.character(...)` to `abstract` and `citation_key`.
  - **Rule:** code-check-r.md "A database driver's value is not a base R type — and it fails twice" ; code-check-r.md "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are" ; code-check.md "A fixture that cannot reach the failure mode"

- **[severity: fragile]** CLAUDE.md (architecture tree, zotero.R line): "the shared resolver (.crd_zot_library, .crd_zot_resolve_keys, .crd_zot_attachments) every Zotero path goes through". This is false for `.crd_zot_key_from_path()` (R/zotero.R:403, used by `crd_search()` to label every hit). It opens its own connection and maps attachment key to citation key with no library scoping and no trash exclusion. It does no harm today, because attachment keys are effectively unique and the store only ingests live files. But the sentence is instructions for agents, and the "every" in it will be relied on the next time someone changes resolution policy.
  - Fix: name the exception, or drop "every".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

## Checked and not reported

- **Empty-input paths**: `.crd_zot_key_pdfs(character())`, `.crd_zot_attachments` with no ids, a 0-row `att` through md5, `ifelse` and dedup, and `table()` of empty `src` all behave.
- **`match()` with NA**: every left side is a non-NA item id.
- **Partial matching**: no `$` lookup has a prefix-sibling risk on frames whose columns the code builds itself.
- **Roxygen blocks**: each sits directly above its function.
- **Performance**: the url derived-table joins run in 0.1 s for 2,352 parents on the real database. Resolving 3,000 keys takes 0.03 s.
- **Undeclared test packages**: `tibble::` in tests is undeclared (`tools:::.check_packages_used_in_tests`), but main had it already (test-audit.R), so it is not introduced here.
- **Vignette**: the `options(cred.zotero_library = ...)` line sits in an unevaluated ```` ```r ```` block.
