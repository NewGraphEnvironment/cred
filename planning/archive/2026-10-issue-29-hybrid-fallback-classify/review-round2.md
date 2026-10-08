# Review round 2 — #29 — the MECHANISM axis

Reviewed at `822abe9` (the branch moved under me mid-review; one commit, "Guard the
model name taken from a 404 body", landed after my first read and is included).
Everything below was measured against ragnar 0.3.0 / httr2 1.3.0 / duckdb 1.5.2 in
`/private/tmp/credprobe/`, not reasoned from the source. The repo working tree was
not touched.

---

## 1. The mechanism

> **A classification or a remedy asserted on evidence that is *consistent* with it
> rather than evidence that *establishes* it — where the establishing evidence is
> usually already in hand, one function away.**

That is not a restatement of "three accidents". In all three of round 1's findings, and
in all three live instances below, the discriminating fact was already inside the
process:

| instance | evidence used | evidence that establishes it | where it already was |
|---|---|---|---|
| r1#1 regex on `array_cosine_distance` | function name | the size phrase | same message |
| r1#2 remedy `crd_store_connect()` | "it verifies stores" | md5 vs model/width | `.crd_check_model()`, 1 screen away |
| r1#3 all statuses → "pull the model" | "it's HTTP" | the status integer | the condition's class vector |
| **#3 below** 404 → "the model is not installed" | the status integer | `model "..." not found` in the body | `.crd_fallback_model()`, 10 lines away |
| **#2 below** store-recorded model trusted unsanitised | "it is local" | the store is an S3 download | `crd_store_connect()`, same file |
| **#1 below** `unknown` → "the store may be at fault" | "we don't recognise it" | httr2's own body-parse error text | the message being printed |

The habit is **stopping at the boundary the type system draws instead of the boundary
the evidence draws.** A class vector, an HTTP status and a file's locality are each a
*cheap* boundary that is *adjacent* to the real one; the diff repeatedly refines to the
cheap boundary (and documents the refinement proudly) and then asserts past it. Round 1's
fix for #3 is the clearest case: it correctly split 404 from 500/503 — a status boundary —
and then wrote "the model it was asked for is not installed", which is a *body* claim.
One boundary short, in the same sentence that fixed the previous boundary.

So the thing to look for is not more regexes. It is **every sentence of the form "X, so
Y"** where X is a type/class/status/location and Y is a fact about the world.

---

## 2. The enumeration

### (a) Every predicate in the new code — 14 items, complete

`R/store.R`. Verdict = does what it matches establish what the code concludes?

| # | line | predicate | concludes | verdict |
|---|---|---|---|---|
| a1 | 550 | `inherits(cond, c("httr2_failure","curl_error"))` | `"connection"`, message "could not be reached" | **over-broad** — see F4. Covers every curl failure incl. SSL and timeout; a timeout is a reachable-but-busy server |
| a2 | 556 | `inherits(cond, "httr2_http_404")` | `"model"`, *"the model it was asked for is not installed"* | **NO — F3**. A 404 is a status; "that model is absent" is a body claim |
| a3 | 557 | `inherits(cond, "httr2_http")` | `"service"`, "it is running" | OK for the service, but see F1: this class is **absent** whenever the error body is not JSON |
| a4 | 559 | `grepl(.crd_conn_patterns, msg, ignore.case)` | `"connection"` | OK; 7 of its 10 alternatives are untested (c2) |
| a5 | 560 | `grepl(.crd_dim_patterns, msg, ignore.case)` | `"dimension"` | OK. Both alternatives are size complaints, both metric-agnostic, both pinned by premise tests. Round 1's fix holds |
| a6 | 564 | fall-through | `"unknown"` + a store-directed remedy | **NO — F1**. "Unrecognised" does not establish "the store may be at fault" |
| a7 | 595 | `length(size) == 1L` | the read is usable | OK (the `is.na()`-on-length-0 trap is correctly a length check) |
| a8 | 596 | `length(model) == 1L` | ditto | OK |
| a9 | 611 | `.crd_have()` = `length==1 && !is.na && nzchar(as.character(x))` | printable | OK. `nzchar(NA)` trap handled by ordering |
| a10 | 634–635 | `regexpr('model[[:space:]]+"[^"]+"')` then `length(hit)==1L` | this is the model to name | OK as a *name* source; its **absence** is the fact a2 should have used |
| a11 | 638 | `.crd_is_model_name(named)` | safe to paste | OK, and correct |
| a12 | 640–641 | `.crd_have(recorded)` — **no** `.crd_is_model_name()` | safe to paste | **NO — F2**. Measured broken output |
| a13 | 656 | `grepl("^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$", x)` | looks like an Ollama model ref | OK. Rejects leading `-`, quotes, spaces, `;`, `$()` |
| a14 | 700/707/716/728 | `identical(reason, ...)` ×4 | branch select | OK — `reason` is `character(1)` from a closed set |

### (b) Every user-facing claim — 24 items

**Messages** (`.crd_retrieval_fallback_msg`): 2 shared lines + 4 branch bodies + 1
fallthrough. **Roxygen**: 5 `\describe` items in `?crd_search`, 1 paragraph in
`?crd_store_connect`. **CLAUDE.md**: 5 new bullets. **NEWS.md**: 8 bullets + 2 paragraphs.

Verified established (spot-checked against the libraries, not against the diff's own prose):

- *"A connected store embeds queries with the embedder recorded inside it"* — **true**.
  `ragnar:::ragnar_store_connect` does literally `embed <- unserialize(metadata$embed_func[[1L]])`
  and calls `check_dots_empty()`, so a caller cannot pass `embed =`. CLAUDE.md quotes the
  line correctly.
- *"All survive `ragnar_retrieve()` unwrapped"* — **true, and structurally so**:
  `ragnar_retrieve` → `ragnar_retrieve_vss_and_bm25` has no `tryCatch`, so this holds for
  every class, not just the one the premise test measures. Stronger than claimed.
- *"no connect-time comparison exists yet"* (`?crd_store_connect`) — **true**.
  `.crd_check_model()` (R/store.R:1484) has exactly one caller, R/store.R:1646, inside
  `crd_store_push()`. Round 1's fix #2 is correct and its new prose is accurate.
- *"the service names it in its own 404 body"* — **true**. `ragnar::embed_ollama` sets
  `req_error(body = function(resp) resp_body_json(resp)$error)`, so Ollama's
  `model "x" not found` reaches `conditionMessage()`. Measured: a JSON 404 yields
  `ollama pull mxbai-embed-large`.
- Frequency-key claims, "Match a size complaint never a function name", the `@embed`-on-a-copy
  claim — all consistent with the code and pinned by tests.

Not established — F1, F2, F3, F4 below, plus:

- *"raises the `testthat` floor to 3.1.8, which the suite already required"* (NEWS):
  defensible but not established. Measured from testthat's own NEWS: `expect_no_match()`
  is 3.0.3, `expect_no_error`/`expect_no_condition` and their `class =` argument are 3.1.5.
  The only 3.1.8 item the suite leans on is base-class enforcement inside
  `expect_warning(class =)`. Not worth changing; worth not repeating as "required".

### (c) Mutations the suite cannot fail — 11 enumerated, 5 survive

Walked every branch and every composite-key component. The 8 the session ran are caught;
these are the ones it did not try.

| # | mutation | survives? | teeth |
|---|---|---|---|
| c1 | drop `"curl_error"` from a1's vector | **yes** | low — no test supplies a bare `curl_error`; the message patterns cover most of it |
| c2 | delete any of 7 of 10 `.crd_conn_patterns` alternatives | **yes** | **moderate** — see below |
| c3 | `ignore.case = TRUE` → `FALSE` on either `grepl` | **yes** | low |
| c4 | `"unknown-width"` → `""` (dimension branch) | **yes** | cosmetic — no fixture has size `NA` with model present |
| c5 | `length(size) == 1L` → `>= 1L` | **yes** | cosmetic |
| c6 | `.crd_fallback_model`'s third-tier `"nomic-embed-text"` | no | pinned by the new model-name-guard test |
| c7 | `store = store` → `NULL` in the `crd_search` handler | no | caught by "one unreachable store does not silence another" |
| c8 | drop `.frequency = "once"` | no | caught |
| c9 | drop either half of the frequency id | no | caught (both halves have a dedicated block) |
| c10 | swap a2/a3 order | no | caught by the 404 test |
| c11 | swap a4/a5 order | **yes** | none — the pattern sets are disjoint |

**c2 is the one with teeth.** Only `Failed to connect`, `Could not resolve host` and
`Timeout was reached` are independently pinned. `Connection refused` *appears* in a test
string — `"Failed to connect to localhost port 11434: Connection refused"` — but
`Failed to connect` matches first in the alternation, so deleting `Connection refused`
leaves the suite green. Unpinned and deletable: `Could not connect`, `Couldn't connect`,
`Connection refused`, `Connection reset`, `Connection timed out`, `Operation timed out`,
`Empty reply from server`. These patterns exist for exactly one stated purpose — *"the only
route for an embedding provider that is not httr2-based"* (R/store.R:484) — i.e. the route
with no class check behind it, so a silent deletion costs the whole classification for that
provider. One `for (msg in ...)` loop over the ten literals fixes it.

---

## 3. Findings

### F1 — MODERATE. An HTTP error with a non-JSON body loses its class, lands in `unknown`, and is told to go look at the store

**Measured.** `R/store.R:557` and `R/store.R:763`.

`ragnar::embed_ollama` installs `req_error(body = function(resp) resp_body_json(resp)$error)`.
When the error body is **not JSON**, that callback raises, httr2 never constructs its HTTP
condition, and what propagates is a bare `rlang_error` — no `httr2_http`, no
`httr2_http_NNN`, and no `resp` field to recover the status from (checked `names(cnd)`:
`message, parent, rlang, call, use_cli_format`; `cnd$resp` is `NULL`).

Measured against a local server returning `500 text/html`:

```
classes: rlang_error, error, condition        reason: unknown

Semantic retrieval failed, so crd_search() fell back to BM25.
  Cause: Failed to parse error body with method defined in `req_error()`.
         Caused by error in `resp_body_json()`:
         ! Unexpected content type "text/html".
  cred does not recognise this failure, so no remedy is prescribed. Semantic
  retrieval is unavailable and the store itself may be at fault - confirm it is
  the file the manifest describes with crd_store_connect().
```

Two things wrong, both the mechanism:

1. **The remedy points at the store for a condition that is unambiguously the service.**
   The cause text names `req_error()` and `resp_body_json()` — httr2's own literals, in
   hand, free. The `unknown` branch's justification (and its test, "the unknown message may
   point at crd_store_connect, because md5 CAN see that") rests on *"for an unrecognised
   failure the file itself is a live suspect"* — an assertion about the contents of a bucket
   defined as "everything we didn't classify". Measured, that bucket contains a whole family
   of pure-service failures. `crd_store_connect()` on a mismatch **re-downloads the store**,
   so this is not a free misdirection.
2. **`?crd_search` says `cred_retrieval_fallback_service` is "Any other HTTP status."**
   It is not: it is any other HTTP status *whose error body parses as JSON*. CLAUDE.md's
   *"`httr2_http` means it answered and refused"* inherits the same boundary.

Reachable with no exotic setup: nginx/Caddy/ALB in front of a model server returns an HTML
`502`/`504`; `base_url` pointing at something that is not Ollama; Ollama behind an ingress.
Ollama answering directly always returns JSON, which is why the suite never sees it.

**Fix** (cheap, and it uses evidence already present): add a pattern for httr2's body-parse
failure — `"Failed to parse error body with method defined in .req_error"` — classifying to
`"service"`; and reword the `unknown` branch so the store is offered as *one* possibility
rather than the only named one. Both are one line.

### F2 — MODERATE. The new model-name guard is applied to the condition's name and not to the store's, on a provenance claim the file contradicts

**Measured.** `R/store.R:638` vs `R/store.R:640–641`; `.crd_is_model_name` at 655.

`822abe9` correctly guards the name lifted from the 404 body. Its roxygen justifies not
guarding the other source:

> The store's own record is trusted; it is local, and the package wrote it.

Neither half holds. `.crd_store_model_from_meta()` regexes a `model = "..."` literal out of
a function **unserialised from the store file**, and `crd_store_connect()` *downloads that
file from a shared S3 bucket*; the md5 compare proves it matches what somebody pushed, not
that cred wrote it. The whole point of the push-side manifest is that stores come from
other people.

Built a store whose recorded embedder names `with ' quote and; semicolon` and composed the
messages (no network, no Ollama):

```
  The embedding service could not be reached. Start Ollama for hybrid search:
    ollama serve && ollama pull with ' quote and; semicolon

  This store holds 16-wide embeddings and records model with ' quote and; semicolon.
  ...
    ncol(ragnar::embed_ollama('probe', model = 'with ' quote and; semicolon'))
```

`.crd_is_model_name()` on that value returns `FALSE` — the guard exists, computes the right
answer, and is not consulted. The second line is a shell command with an injected `;`; the
third is syntactically invalid R. This is precisely the defect `822abe9` was written to fix,
surviving in the sibling branch of the same `if`, which is round 1's finding-inside-the-fix
shape for the fourth time.

**Fix:** `if (.crd_have(recorded) && .crd_is_model_name(recorded)) return(recorded)` at 640,
and gate the `"records model "` interpolation at 730 the same way (fall back to `"unknown"`,
which that branch already renders). The one existing test on this path
("a connection remedy names the store's recorded model") uses a benign name, so it is a
fixture that cannot reach the failure mode — add the quote case.

### F3 — MINOR/MODERATE. 404 asserts "the model is not installed" from the status, while the body phrase that would establish it is parsed ten lines away

**Measured.** `R/store.R:556`, message at `R/store.R:705–708`, `?crd_search`'s
`cred_retrieval_fallback_model` item.

Round 1's #3 split 404 from 500/503. Correct, and one boundary short: *"only a 404 means the
model is absent"* is true of Ollama's model-not-found 404 and false of every other 404 the
endpoint can return. Measured against a server returning `404 application/json`
`{"error":"404 page not found"}` — which is what an Ollama predating `/api/embed`, or a
gateway with a wrong path prefix, returns:

```
classes: httr2_http_404, httr2_http, httr2_error, ...     reason: model

  The embedding service answered and refused the request, so it is running.
  The model it was asked for is not installed:
    ollama pull nomic-embed-text
```

A flat false assertion, and a `pull` for a model nothing asked for and that is very likely
already installed — the "fix something that is not broken" failure that
`.crd_fallback_model`'s own roxygen names as its reason for existing.

The discriminator is already computed: `.crd_fallback_model()` looks for
`model[[:space:]]+"[^"]+"` and, here, does not find it. That *absence* is the evidence a2
needs and discards.

**Fix:** in `.crd_retrieval_failure`, return `"model"` for a 404 only when the message
carries the model phrase (or Ollama's `try pulling it first`), and `"service"` otherwise —
whose branch already prescribes nothing, which is the right answer for an unexplained 404.
Keep the hand-built-condition tests; add a 404 whose body names no model and assert
`"service"`.

### F4 — MINOR. Two residual assertions in the message text

Not worth a round of their own, but both are the same mechanism and both are one-line edits.

- **`R/store.R:702`** — *"The embedding service could not be reached."* for a1. `httr2_failure`
  / `curl_error` covers every curl failure, and `.crd_conn_patterns` deliberately includes
  `Timeout was reached` and `Operation timed out`. A timeout is a server that *was* reached
  and did not finish in time — a large model loading is the ordinary cause — so this prints
  "could not be reached. Start Ollama" at someone whose Ollama is running. Softening to
  "could not be reached, or did not answer in time" costs nothing and is true of the whole class.
- **`R/store.R:721–727`** — the dimension branch states *"the model that name resolves to on
  this machine is no longer the model the store was built with"* as the sole mechanism. The
  comment immediately above it states the real disjunction ("…**or** the embedder was replaced
  in this session"), and the package's own fixtures reach this branch by exactly that second
  route (`store@embed <- .crd_test_embed_narrow`). The comment is right; the emitted sentence
  dropped a disjunct. Say "or the embedder was replaced in this session" in the message too.

### Housekeeping (non-blocking)

`R/store.R:482–487` and `488–493` are the **same 6-line comment block, twice** — a copy-paste
survivor of the fix pass. Delete one.

---

## 4. What held up

Round 1's five fixes all verify, and three of them verify *more strongly* than the diff
claims: the `ragnar_store_connect` unserialise claim is quoted verbatim and correct, the
"unwrapped" claim is structural rather than measured-once, and `.crd_check_model()` really
does have exactly one caller and it is in `crd_store_push()`. The dimension pattern set is
the right abstraction level (size complaint, metric-agnostic, both alternatives premise-tested).
The frequency key is correctly composite and both halves have a test that fails if either is
dropped. `.crd_have()` handles `nzchar(NA)` and the zero-length `is.na()` trap correctly. No
data-loss or security defect found; `crd_search()`'s fallback contract and the `method` column
are intact on every path I exercised.
