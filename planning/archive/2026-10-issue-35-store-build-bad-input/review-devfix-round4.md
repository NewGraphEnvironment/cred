# Code-check round 4: qualifying "One PDF never costs the build" (8e89bfd, #35)

**Redacted.** This round found that the behaviour round 3 reported in ragnar's progress output
is more serious than an aborted build. The details were reported to ragnar privately, so this
public record keeps the findings' shape and their disposition, not the reproduction.

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, and "Documentation
  Staleness"; 22 not read.
- **code-check-r.md**: "`cli` reads `{.name}` as a STYLE, not a variable, and a fold can
  swallow an interpolation", in full; the rest from the index.
- **code-check-shell.md**, **code-check-spatial.md**: none read; no shell or spatial code.

## Findings

- **[severity: bug]** findings.md, the drafted ragnar issue: its second proposed fix
  re-interpolated already-formatted text, so it reproduced the defect it was meant to fix.
  - **Rule:** code-check-r.md "`cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation"
- **[severity: fragile]** R/store.R, man/crd_store_build.Rd, CLAUDE.md: the sentence
  describing which file names are affected was both too wide and too narrow, and understated
  the consequence.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"
- **[severity: fragile]** README.md pointed at a findings section that did not hold the new
  draft.
  - **Rule:** code-check.md "Documentation Staleness"

## Disposition

Asked of the user, who chose: close it in cred, and report it to ragnar privately. ragnar's
progress output is now off in `crd_store_build()` (and by default in `.crd_store_ingest()`),
with a regression test that fails if it is turned back on; the public drafted ragnar issue
about it was withdrawn in favour of the private report; the affected sentences were reworded.
