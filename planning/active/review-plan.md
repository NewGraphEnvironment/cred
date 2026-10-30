# Plan review — #40 (Plan agent, delivered 2026-10-30)

Written here by the parent session because the Plan agent cannot write files.
Each finding was probed before it was folded in; the verdict follows each one.

1. **Blocker:** setting `cred.zotero_library` in an R profile breaks the toy-fixture tests and vignette, because the toy DB has no such group. **Verdict: holds.** The tests and the vignette pin `library = NULL` / `local_options`.
2. **Blocker:** `crd_aud_verify_abstract()` wraps the abstract lookup in `suppressWarnings()`, so an ambiguity warning would be swallowed and counted as "no abstract". A cross-library key also returns 2 rows, and `nrow(x) == 0L || is.na(x$abstract)` errors on R >= 4.3. **Verdict: reproduced** on R 4.5.2: `'length = 2' in coercion to 'logical(1)'`. Fix: suppress only the no-abstract class.
3. **Gap:** the same collection name appears several times within one library. **Verdict: measured.** Library 9 has `archived` ×10 and `ITT` ×8; library 1 has `ITT` ×7. Fix: error on any multiple match, listing each match's parent path, and accept a `parent/child` path to choose one.
4. **Gap:** subcollections. `bull_trout` and `grayling` are children of `species`. **Verdict: holds.** Decision: non-recursive, as before, and documented.
5. **Gap:** ties on `dateAdded`. **Verdict: holds.** Final sort key is attachment itemID ASC.
6. **Gap:** linked files (linkMode 2: 177 PDFs, Windows paths and `attachments:` paths). Take the first candidate whose file exists, as Zotero's attachment state does, and name the rest in the message.
7. **Gap:** the fixture needs real files. Already done in Phase 1.
8. **Gap:** `itemNotes`, and classify by table rather than itemTypeID. Already done in Phase 1.
9. **Gap:** md5 dedupe should run within one parent only, never on NA hashes, and `tools` must go in Imports. Adopted.
10. **Gap:** exclude ambiguous keys from "No attachment found"; name the library a key lives in when it is absent from the requested one; guard against empty keys. Adopted.
11. **Gap:** `library` edge cases: a digit string is a groupID; a number that is only an internal libraryID gets an error saying so; a duplicate group name errors. Adopted.
12. **Gap:** two schema builders, and binary churn from the data-raw script. Kept two builders: the drift test in `test-zotero.R` is the guard. Churn handled by restoring the PDF and docx after regenerating.
13. **Ordering:** Phase 1 tests fail on main as "unused argument". **Verdict: true for the API tests.** The fixture was run against main's code without `library`, and every defect reproduced (findings.md). Not rewritten.
14. **Assumptions** confirmed by the reviewer against the real DB. Behaviour change for NEWS: one item with docx + PDF now yields the PDF.
15. **Acceptance:** the bull_trout/grayling breakdown in findings.md does not add up. **Verdict: holds.** Recount with the function itself in verification.
