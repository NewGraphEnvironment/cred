# Review — fresh eyes on #29's hybrid-fallback classification

**Reviewed:** committed `origin/main...HEAD`, re-verified against the working tree as it
moved under me. Measurements were taken at three points and each is dated below by the
commit it ran against:

| commit | what I measured there |
|---|---|
| `822abe9` Guard the model name taken from a 404 body | 10-mutation battery, `lintr` (0 lints), full suite `[FAIL 0 \| SKIP 2 \| PASS 474]` |
| uncommitted tree between `822abe9` and `2be5761` | 5-mutation battery, `lintr` (1 lint, since fixed) |
| `2be5761` Fold in review round 2 | headline finding re-confirmed, dim-reword probe, `lintr` (0 lints) |

Everything ran in copies under `/private/tmp/credrev*`; the repo working tree was not
touched.

Two findings. One is a test that cannot fail, proven by mutation; the other is a premise
test that is narrower than the comment above it claims. Nothing in the production code
misbehaves.

---

## Findings

### 1. [fragile] `tests/testthat/test-store-fallback.R:372-383` + `tests/testthat/helper-store.R:224` — the test that claims `.crd_fallback_model()` reads the store's recorded model cannot fail

`.crd_test_embed_named()` is defined with

```r
.crd_test_embed_named <- function(x, model = "nomic-embed-text") {   # helper-store.R:224
```

and `.crd_fallback_model()`'s last-resort constant is the **same literal**
(`R/store.R:670`). So

```r
expect_match(msg, "ollama pull nomic-embed-text", fixed = TRUE)      # :382
```

passes whether the function consulted the store or fell straight through to the hardcoded
default — which is precisely the distinction the block's own title ("…**not a hardcoded
one**") asserts.

**Measured.** Deleting the whole recorded tier from `.crd_fallback_model()`:

```r
  recorded <- .crd_store_meta_brief(store)$model     # R/store.R:668-669
  if (.crd_is_model_name(recorded)) return(recorded) # both lines deleted
```

| tree | result with the tier deleted |
|---|---|
| `822abe9`, fallback file | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 130 ]` |
| pre-`2be5761` tree, fallback file | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 158 ]` |
| pre-`2be5761` tree, **whole suite** | `[ FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 502 ]` |
| `2be5761`, fallback file | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 158 ]` |

**It is the fixture, not the assertion.** Changing one string in `helper-store.R` to
`model = "mxbai-embed-large"` (plus the three assertions that quote the name) and
re-applying the same mutation gives:

```
FAILURE: 'test-store-fallback.R:292:3'
Expected `msg` to match string "ollama pull mxbai-embed-large".
Actual text:
  |     ollama serve && ollama pull nomic-embed-text
[ FAIL 1 | WARN 0 | SKIP 0 | PASS 129 ]
```

So the block becomes discriminating for the cost of one literal.

**Round 2's new block does not close it.** `test-store-fallback.R:344` ("the model name
the STORE records is guarded too") mocks `.crd_store_meta_brief()` to return a *rejected*
name and asserts `expect_match(msg, "nomic-embed-text")`. That is also exactly what a
**deleted** tier produces, so it adds no signal on this tier either. It does pin the
`.crd_is_model_name(recorded)` guard — mutating that back to `.crd_have(recorded)` is
caught by 4 assertions.

**Why it matters.** `NEWS.md` 0.3.2 states: *"A remedy names the model that was actually
refused … falling back to the one the store records, and only then to the package default.
The connection branch no longer hardcodes `nomic-embed-text` either."* The first half (the
condition-derived name) is pinned by the `mxbai-embed-large` block at `:325`. The second
half has no test that can fail. If it regresses, a store built with
`crd_store_build(model = "mxbai-embed-large")` prints `ollama pull nomic-embed-text` and
`embed_ollama('probe', model = 'nomic-embed-text')` — the "names a model nothing ever asked
for" failure the function exists to prevent, with a green suite and a release note
asserting the opposite.

This is `code-check.md`'s *"A fixture that cannot reach the failure mode"* and
*"An assertion that matches an interpolated value cannot see the claim around it"* in one
place: the interpolated value and the fallback constant are the same string.

### 2. [fragile] `tests/testthat/test-store-fallback.R:44` — the premise test pins 9 characters of the 40-character string the dimension regex depends on

The comment two lines above it:

```r
  # This is the one branch with no distinguishing class — it is a duckdb binder
  # error — so the regex is load-bearing and the text it matches is pinned here.
  expect_match(conditionMessage(cnd), "same size")                   # :44
```

`.crd_dim_patterns` is `"Array arguments must be of the same size"`. `"same size"` is a
substring of it, so an upstream reword that keeps those nine characters and moves the rest
— `"Array arguments must **have** the same size"` is the obvious one — leaves this test
green while `.crd_retrieval_failure()` silently drops the real condition to `"unknown"`.

**Measured** (simulating the reword by editing the pattern on `2be5761`):

```
FAILURE: ':159:3'  ':219:3'  ':495:3'  ':498:3'  ':499:3'  ':590:3'
[ FAIL 6 | WARN 1 | SKIP 0 | PASS 152 ]
```

Line 44 is not among them. The reword **is** caught — by the end-to-end dimension block at
`:495`, which reports "expected `cred_retrieval_fallback_dimension`, got
`cred_retrieval_fallback_unknown`". So this is not a coverage hole; it is that the premise
test does not do the one job its header paragraph gives it ("these tests fail **naming the
cause** rather than letting the behaviour tests below pass for the wrong reason"). Lower
severity than #1 for that reason.

Cheapest fix that makes the comment true: assert the pattern itself rather than a substring
of it — `expect_match(conditionMessage(cnd), cred:::.crd_dim_patterns)` — which also keeps
the test and the regex from drifting apart.

---

## Closed while I was reviewing — not open, recorded so they are not re-found

- **`R/store.R:482-493` at `822abe9`: a 6-line comment block committed twice verbatim**
  ("Message fragments that identify a failure to reach the embedding service…"). Deleted in
  `2be5761`. Flagging only in case the branch is ever squashed from an earlier commit.
- **Asymmetric trust in `.crd_fallback_model()`**: at `822abe9` the 404-body name went
  through `.crd_is_model_name()` and the store-recorded name went through `.crd_have()`,
  with the rationale "the store's own record is trusted; it is local, and the package wrote
  it" — which `crd_store_connect()` contradicts, since it downloads stores from a shared
  bucket. Fixed in `2be5761`, and the roxygen now says so.
- **One new `lintr` lint** (`quotes_linter`, single-quoted string with no embedded `"`) in
  the uncommitted tree before `2be5761`. `lintr::lint_package()` is **0** on `822abe9` and
  **0** on `2be5761`.

---

## Probed and clean

Stated so that the absence of a finding is evidence rather than a gap.

**`.crd_retrieval_failure()` ordering and reachability** (the latest, `2be5761`, shape).
`httr2_failure`/`curl_error` → `answered` (class or `HTTP ddd` in the text) → 404-with-a-
`model "…"`-body → `service` → conn patterns → dim patterns → `unknown`. No branch is
shadowed or unreachable, and the discriminating ones are each pinned:

| mutation | caught by |
|---|---|
| 404 → `model` on status alone, ignoring the body | `:143` |
| drop the classless-HTTP text route (`.crd_http_patterns`) | `:185 :189 :194` |
| drop the 404/other-status split entirely | 4 assertions at `:120` |
| drop `"Cannot cast array of size"` from the dim patterns | `:133` |
| re-add the bare `array_cosine_distance` name to the dim patterns | `:148 :160` |
| `.crd_is_model_name()` accepts anything | 8 assertions |
| frequency id drops the reason | `:500 :527` |
| `.crd_indent_cause()` → identity | `:369 :370` |
| `.crd_have()` → first-element / `length >= 1` | `:354` |

One ordering consequence worth naming without claiming it as a defect: because
`.crd_http_patterns` (`"HTTP[[:space:]]+[0-9]{3}"`, case-insensitive, matched against the
*whole* message) returns unconditionally, it now shadows **both** the connection-pattern
and dimension-pattern routes for any message carrying an HTTP status. I could not construct
a reachable case — httr2's transport message is `"Failed to perform HTTP request."` (no
digits, and class-caught first anyway), a request URL has no whitespace before its port, and
a duckdb binder error cannot carry a status because the embed and the SQL fail at different
points. Noted only because the mutation that moves the conn-pattern check ahead of the class
checks also survives the suite, so the "class first" invariant the roxygen argues for is not
itself pinned. Neither is a live bug.

**`.crd_have()` edge cases** (measured): `NULL`, `integer(0)`, `character(0)`,
`NA_integer_`, `NaN`, `""`, `c(1L, 2L)`, `factor("")` → all `FALSE`; `16L`,
`"nomic-embed-text"`, `TRUE`, `"NA"` → `TRUE`. `list(NULL)` and `list("a")` return `TRUE`
(via `as.character()`), but no caller can supply a list: `.crd_store_meta_brief()` returns
an integer and a character, and `.crd_retrieval_fallback_id()` passes
`as.character(store@location)`.

**`.crd_indent_cause()` edge cases** (measured): `character(0)` → `""`, `NA_character_` →
`"NA"`, `c("a","b")` → collapsed and indented, `"a\nb\n"` → trailing empty field dropped
(`strsplit()` behaviour per `code-check-r.md`), `"a\r\nb"` → leaves a stray `\r`. All
cosmetic, and unreachable in practice: the only caller passes `conditionMessage()`, which is
always a length-1 string.

**`.crd_fallback_model()` against odd message text** (measured): `regexpr()` takes the first
match only (`model "first-one" … model "second-one"` → `first-one`); `models "a"` does not
match (the pattern requires whitespace immediately after `model`); `model = "x"` does not
match, so a deparsed call in a message cannot be mistaken for a 404 body; the anchored
`sub()` round-trips correctly even when `[^"]+` spans a newline; and names carrying `'`,
`;`, a space or >128 characters are rejected by `.crd_is_model_name()` and fall through.

**`rlang::warn()` applies no cli formatting here.** `cnd_message_info(use_cli_format = NULL)`
resolves against the calling package, and `cred` never calls `local_use_cli()`, so
`use_cli_format` is `FALSE`. Verified by pushing a cause containing
`{.val foo} {bar} 100% {` through `.crd_retrieval_fallback_warn()`: braces, a lone `{` and
`%s`/`%d`/`%%` all survive verbatim and the message's own indentation is preserved. A duckdb
or httr2 message containing braces can neither abort the warning nor be mangled — worth
having checked, given `code-check.md`'s cli-brace rule.

**Teardown and ordering across test FILES.** `testthat::teardown_env()` is **run-scoped**,
not file-scoped: `local_teardown_env(frame)` is called from `test_files_setup_state()`,
which `test_files_serial()` invokes once for the whole run (testthat 3.3.2). So both cached
stores' `withr::defer(DBI::dbDisconnect(…, shutdown = TRUE))` fire at the end of the suite,
not at the end of `test-store-fallback.R` — the hazard of a second file receiving a closed
connection does not exist. Confirmed behaviourally: files run alphabetically, so
`test-store-fallback.R` builds the cache and `test-store-search.R` reuses it, and the full
suite is green (`PASS 502`). `store@embed <- broken` is copy-on-modify and does not reach
`.crd_store_cache$store`; the "a successful hybrid search warns about nothing" block at
`:553` is the canary for that and passes.

**`rlib_warning_verbosity` vs `reset_warning_verbosity` — no interference, no leak.**
Verified in rlang 1.3.0's `needs_signal()`:

```r
switch(peek_verbosity(opt), verbose = return(TRUE), quiet = return(FALSE), default = NULL)
...
if (is_null(sentinel)) { env_poke(env, id, Sys.time()); return(TRUE) }
```

The `verbose` return happens **before** `env_poke()`, so `local_fallback_warnings_always()`
leaves no sentinel behind and cannot silence a later block — the helper's comment is
accurate. `withr::local_options(.local_envir = parent.frame())` restores the option at block
exit, and the two frequency blocks re-arm their ids both before and after, so they are
independent of execution order. The one residual sensitivity: a developer with
`options(rlib_warning_verbosity = "verbose")` set globally would fail the two frequency
blocks, because testthat does not reset that option. Not worth guarding unless it bites.

**Declared dependencies.** The `testthat (>= 3.1.8)` floor is justified —
`local_mocked_bindings()` 3.1.7/3.1.8, `expect_no_condition(class = )` 3.1.5,
`expect_no_match()` 3.0.3. Every `pkg::` the new tests reach is declared: `rlang` (now
Imports), `ragnar`/`DBI`/`duckdb`/`withr`/`testthat` (Suggests). `rlang` is used only via
`rlang::`, so no NAMESPACE import is needed.

**Degradation paths in the message builder.** `.crd_store_meta_brief()` returns the `NA`
pair for `NULL`, a non-S7 object, a missing `con`, a missing `metadata` table and a missing
column, and every caller length-guards through `.crd_have()`. The `length(size) == 1L` /
`length(model) == 1L` guards inside it are redundant given `.crd_have()` — removing them
leaves the suite green — but they are correct, cheap and documented, so that survival is
belt-and-braces rather than a hole.

---

## Reproduction

```bash
rm -rf /private/tmp/credrev3 && mkdir -p /private/tmp/credrev3
cp -R /Users/airvine/Projects/repo/cred/. /private/tmp/credrev3/
cd /private/tmp/credrev3
# finding 1: delete R/store.R:668-669 (the recorded-model tier), then
Rscript -e 'suppressMessages(pkgload::load_all(".", quiet = TRUE)); testthat::test_file("tests/testthat/test-store-fallback.R", package = "cred")'
# finding 2: change .crd_dim_patterns to "Array arguments must be of the exact same size", then rerun
```
