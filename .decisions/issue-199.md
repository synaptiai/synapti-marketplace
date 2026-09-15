---
issue: 199
title: "claim-scan's per-cell subprocess cost is unbounded on a pathological table row"
branch: fix/issue-199-claim-scan-unbounded-subprocess-cost
created: '2026-09-15T19:12:55Z'
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T19:12:55Z'
  elements:
  - ci-investigation
  - non-goals
  - failure-modes
  - interface-contracts
---
# Issue #199 — claim-scan's per-cell subprocess cost is unbounded on a pathological table row

## CI fail-open/closed investigation

_This is the load-bearing part of this entry — the issue explicitly makes it_
_step 1, and it changes AC2 from "closing an active bypass" to "defense in_
_depth." Read fully before the fix section below._

**Finding: `dossier-claim-scan.sh` is not wired into any GitHub Actions
workflow in this repository as a live gate on real documents at all — so
there is no in-repo CI wrapper to be fail-open or fail-closed about. The
fail-open/closed question is real, but it applies to `dossier-gate.sh`'s
own internal handling of this script's exit code, not to any workflow YAML
this repository ships.**

### What was checked

- `.github/workflows/*.yml` (all six): grepped for `claim-scan` and
  `dossier-gate` directly. Only `dossier-tests.yml` even mentions `dossier`,
  and it does so once, to scope its `paths:` triggers — it never invokes
  either script by name.
- `dossier-tests.yml` itself: its one relevant step is `Run dossier tests`,
  which runs `plugins/dossier/tests/run.sh` — the plugin's own test suite,
  which exercises `dossier-claim-scan.sh` as a **unit under test** (calling
  it directly, with synthetic fixtures, to assert its behavior), not as a
  **gate scanning a real document** for actual leakage before something
  ships. The job carries `timeout-minutes: 10` (job-level, not a per-step
  `timeout` wrapper around any individual script). If the test suite were to
  hang, GitHub Actions kills the whole job at 10 minutes and reports the
  workflow run as failed/timed-out — that IS fail-closed, but it gates the
  test suite's own health, not a document's disclosure safety.
- `plugins/dossier/bin/dossier-gate.sh`: this is the actual orchestrator that
  calls `dossier-claim-scan.sh` as part of its G06 condition ("no secret,
  credential, personal data, or prohibited disclosure present"). Read in
  full. No `timeout` wrapper appears anywhere in this script — grepped for
  `timeout` across the whole file and confirmed none of the seven external
  script invocations (`dossier-claim-scan.sh`, `dossier-package-check.sh`,
  `dossier-ledger-lint.sh`, etc.) are time-bounded internally.
- `plugins/dossier/commands/gate.md`: this is the `/dossier:gate` slash
  command, which runs `dossier-gate.sh` from inside an interactive Claude
  Code session — not a GitHub Actions job. It documents `--strict` as the
  flag to use "in any automated context," implying the *intended* deployment
  is a **downstream project's own CI**, wiring this plugin's scripts into
  *their* pipeline to gate *their* documentation releases. That downstream
  wiring does not exist in this repository and cannot be inspected here.
- Every other caller of `dossier-claim-scan.sh` in this repo
  (`commands/reconcile.md`, `commands/baseline.md`, `commands/claim.md`,
  `commands/refresh.md`) is likewise a Claude Code slash command — run
  interactively, not by GitHub Actions.
- `plugins/dossier/templates/ci/dossier-docs-refresh.yml`: the one template
  this plugin ships for a *consuming* project's own CI. Grepped for `gate`,
  `claim-scan`, and `G06` — it runs `dossier-scan-security.sh` /
  `dossier-scan-quality.sh` (vulnerability/quality scanning, each with their
  own internally-implemented `timeout`, unrelated to this issue) and a docs
  refresh pipeline. It does **not** invoke `dossier-gate.sh` or
  `dossier-claim-scan.sh` at all.

### What this means for AC1 ("confirm fail-open or fail-closed")

There is no CI wrapper *in this repository* to characterize as fail-open or
fail-closed, because there is no CI invocation of this script in this
repository, full stop. The one caller whose behavior actually matters is
`dossier-gate.sh`'s own G06 condition, read directly (`bin/dossier-gate.sh`
lines ~132–147):

```sh
if [ -x "$SELF_DIR/dossier-claim-scan.sh" ]; then
  SCAN_OUT=$("$SELF_DIR/dossier-claim-scan.sh" --output-root "$OUTPUT_ROOT" --quiet 2>&1)
  SCAN_RC=$?
  case "$SCAN_RC" in
    2) record G06 mechanical FAIL script "dossier-claim-scan.sh detected leakage" ;;
    3) SCAN_WHY=...; record G06 mechanical INCONCLUSIVE script "..." ;;
    *) record G06 mechanical PASS script "no leakage patterns matched" ;;
  esac
```

Two things follow directly from this `case`, independent of any external
`timeout`:

1. **No internal timeout exists.** `dossier-gate.sh` calls
   `dossier-claim-scan.sh` with no `timeout` wrapper of its own. If a
   pathological document made the scan run for minutes, `dossier-gate.sh`
   would simply block for minutes too — nothing inside this repository's own
   code would kill it. The only thing that could ever interrupt it is an
   *external* timeout: a downstream CI's own `timeout dossier-gate.sh …`
   wrapper, or the CI platform's own job/step timeout killing the whole
   process tree. Neither exists inside this repository.
2. **The `case` statement's default arm is the actual bypass shape, and it
   already exists independent of any timeout.** `*)` — everything that is
   not exactly 2 or 3 — reads as PASS ("no leakage patterns matched"). That
   default arm already covers exit 0 (genuinely clean) AND exit 1
   (registration gaps, no leak) identically: G06 is scoped to leakage only,
   not registration (registration is G04, a *judgment* condition evaluated
   separately via the scorer verdict). So *before this fix*, if the scan
   were ever killed by an external `timeout` in a way that let bash's `$()`
   command substitution capture a **non-2, non-3** exit code — most notably
   exit 0 from a process that happened to complete just before a boundary,
   or any exit code an external wrapper coerced into something other than
   2/3/124/137 — G06 would read PASS. This is real, but it is a property of
   `dossier-gate.sh`'s own case-statement design (a narrow allowlist of
   codes that mean "not PASS"), not evidence of any specific fail-open CI
   wrapper — because no such wrapper exists in this repo to observe.

### Conclusion and what this makes AC2

Given no in-repo CI wrapper exists to characterize, and `dossier-gate.sh`'s
own G06 switch already treats every code except {2, 3} as PASS, the risk
this issue's AC2 addresses is **real but latent, not an active, exploitable
bypass in this repository today**: nothing in `synapti-marketplace`'s own
CI currently depends on `dossier-claim-scan.sh` finishing in time. It
matters for any downstream project that wires `dossier-gate.sh --strict`
into its own pipeline (exactly the deployment `gate.md` documents and
recommends), where an external timeout killing the scan mid-run is a
realistic operational event this repository cannot observe or control.

**This makes AC2's fix defense-in-depth, not closure of an active bypass in
this repo** — implemented anyway, per the issue's own suggested resolution,
because a bounded and reported scan is strictly better than an unbounded one
regardless of which CI wrapper eventually calls it, and because it is the
right fix for the performance problem (AC1) on its own merits even before
considering G06 at all.

**A second, more direct property came out of implementing the fix**: making
a truncated-but-otherwise-clean scan exit **3** (not a new code, not exit 1)
is what actually changes `dossier-gate.sh`'s behavior, because exit 3 is the
*only* code besides 2 that the existing `case` statement already treats as
something other than PASS. Reusing 3 turns "the scan didn't finish examining
everything" into "G06 is INCONCLUSIVE," which `dossier-gate.sh`'s own
verdict logic (`elif [ "$INCONC_COUNT" -gt 0 ]` → `RESULT="INCONCLUSIVE"`,
never PASS) already refuses to let through as release-ready — with zero
changes to `dossier-gate.sh` itself. Confirmed by live reproduction (see
Testing below): a single-row pathological table that clears the cap with
zero leaks and zero registration gaps now produces `GATE_RESULT=FAIL` /
`G06 mechanical INCONCLUSIVE` from `dossier-gate.sh`, where before this fix
the same scan (once it eventually finished) would have produced
`GATE_RESULT=PASS`-eligible G06 output.

## The bug, precisely

`scan_table_row()` (added by issue #176) splits a markdown table row into
cells and calls `scan_text()` once per non-empty cell. Before #176, a table
row was skipped entirely — zero `scan_text()` calls. After #176, a row with
N cells produces exactly N calls, and nothing bounds N: a markdown table row
is one physical line, so its cell count is bounded only by the document's
byte size, not by anything resembling the document's line count or a
document author's realistic authoring effort.

Each `scan_text()` call is expensive independent of this issue — it forks
roughly a dozen subprocesses across code-span stripping, the whole-line
credential pre-check, sentence splitting, normalization, word counting, the
approved-pool lookup, and (on the unregistered path) redaction. That cost
per call is not new and not itself a bug; every one of those subprocess
forks exists to fix a real, previously-reported correctness bug in this same
file (see the surrounding comments for #198/#200/#210). What #176 changed is
the multiplier: a single line can now trigger that whole chain thousands of
times, where before #176 the worst case was "once per line in the document."

Confirmed empirically (single foreground run, this repository's own
hardware, not part of the test suite): a synthetic single-row table with 300
cells (~12KB) took **7.0s** real time end-to-end through the unmodified
scanner — about 23ms/cell. This is the same order of magnitude as the
issue's own reproduction (~17.6ms/cell at 5000 cells, ~88s), confirming the
mechanism and giving an independent rate to size the fix against.

## The fix

A **per-file cap on `scan_text()` invocations** (`MAX_CANDIDATES_PER_FILE`,
set to 500), checked at the top of `scan_text()` itself before any
subprocess work runs.

### Why calls-to-`scan_text()`, not cells-per-row specifically

The issue's own suggested resolution offered either "cap cells-per-row" or
"cap total candidate sentences per file." `scan_text()` is called once per
paragraph line, per bullet, per blockquote line, AND per table cell — it is
the single choke point every one of those four line classes already funnels
through (see `LINE_CLASSES_EXAMINED`). Capping calls to this one function:

- Directly bounds the exact cost the issue measures (the issue's own
  language is "N cells... N `scan_text` calls").
- Requires touching exactly one place, not four (one per line class), and
  cannot be bypassed by a future line class that reuses `scan_text()` the
  way blockquotes and bullets already do.
- Generalizes for free to any *other* future amplification vector that
  funnels through `scan_text()` — not just table rows — without needing a
  second, differently-shaped cap.

The table-cell splitting itself (`scan_table_row()`'s array split, code-span
stripping) is deliberately left unbounded: the issue's own reproduction
measured it at ~0.06s for 5000 cells, and confirmed directly here that nothing
about it — as opposed to `scan_text()`'s body — is the cost.

### Why 500

23ms/candidate (measured above) × 500 ≈ 11.5s worst case for a single
pathological file — down from unbounded (minutes, per the issue's own 88s
reproduction at 5000 cells, and confirmed independently: an 800-cell
single-row fixture built during this fix's own testing exceeded 500 in
CANDIDATES_EXAMINED and completed in ~9–13s wall time regardless of exactly
how far past 500 the row's total cell count went, since every candidate past
the cap is now free). 500 is comfortably above the candidate count of any
real, human-authored public document this plugin's own `06-public/` packages
contain — a legitimate technical guide's total count of declarative
sentences, bullets, and table cells combined is not close to 500 in one
file — so the cap is not expected to be reachable by ordinary authoring, only
by a pathological or hostile document.

### The truncation contract (AC2)

- `CLAIM_SCAN_TRUNCATED=0|1` — always printed (plain-text and `--json`),
  even when 0, so its absence is never mistaken for "not applicable."
- `CLAIM_SCAN_TRUNCATED_FILES=<comma-separated paths>` — printed only when
  truncation occurred, naming exactly which file(s) hit the cap.
- `CLAIM_SCAN_ERROR=<reason>` — printed **unconditionally** (ignores
  `--quiet` and `--json`) exactly when a file hit the cap, mirroring the
  pre-existing "no public directory" exit-3 path's own convention (that path
  already prints `CLAIM_SCAN_ERROR=` unconditionally too — this fix follows
  an existing pattern, not inventing a new one). This is required, not
  cosmetic: `dossier-gate.sh`'s G06 branch calls
  `dossier-claim-scan.sh --quiet` and extracts its INCONCLUSIVE reason with
  `sed -n 's/^CLAIM_SCAN_ERROR=//p'` — if this field were gated behind
  `[ "$QUIET" -eq 0 ]` the way the rest of the report is, the one real
  caller in this codebase would see an empty reason.
- Exit code: reuses **3** ("infra error" in this script's existing
  contract), not a new code and not 1. Checked last in the exit cascade —
  after leak (2), unregistered (1), and prohibited-vocabulary (1) — so a
  genuine finding made *before* the cap was reached still reports its own,
  more specific exit code even on a file that was also truncated. Only a
  file that is BOTH truncated AND reports nothing else wrong exits 3 instead
  of 0. See the CI investigation section above for why 3 (not 1, not a new
  4th code) is the choice that actually changes `dossier-gate.sh`'s G06
  outcome without modifying `dossier-gate.sh` itself.

### Per-file, not global

The counter and cap are reset per file (`CANDIDATES_EXAMINED=0` at the top
of the `for f in $TARGETS` loop), so one pathological file cannot spend a
budget sized for the whole run and truncate every *other*, possibly entirely
ordinary, file in the same scan to zero.

## Non-goals

- Not making the cap configurable via `dossier-resolve-config.sh`. No other
  hardcoded structural constant in this file (the four-word floor, the
  credential pattern set) is resolver-configurable either; adding
  configurability here would be new surface this issue does not ask for and
  the existing file has no precedent for.
- Not bounding `scan_table_row()`'s cell-splitting itself, or `scan_class()`
  (Section A's whole-file leak grep, run once per pattern per file
  regardless of table structure) — both already measured as cheap and
  outside this issue's own stated scope ("the new table-cell splitting
  itself... completes in ~0.06s").
- Not adding a `timeout` wrapper inside `dossier-gate.sh` around its
  external script calls (`dossier-claim-scan.sh` or any of the other six).
  That would be a reasonable, separate hardening step for a script this
  issue's own investigation found has no internal time bound at all, but it
  is out of this issue's scope (which is `dossier-claim-scan.sh`'s own
  unbounded cost, not `dossier-gate.sh`'s orchestration) and changes a
  different file's contract for callers this issue did not audit.
- Not changing `dossier-gate.sh` at all. Exit 3 was deliberately chosen
  *because* it requires no change there — see the CI investigation section.
- Not touching anything about which line classes are examined, credential
  patterns, or the registration/exact-match logic (issues #176/#198/#200/
  #210/#202 territory) — this fix only bounds how many candidates
  `scan_text()` is allowed to spend its existing logic on per file.

## Failure modes

- **A leak in a cell reached before the cap.** Reported at its own severity
  (exit 2) regardless of whether the same file is also truncated elsewhere —
  confirmed directly: a fixture with a genuine credential in cell 1 of a
  521-cell row still exits 2, not 3, even though the remaining cells past
  the cap are never examined.
- **Exactly `MAX_CANDIDATES_PER_FILE` candidates, no more.** The cap check
  is `-gt`, so a file with precisely 500 qualifying calls is fully examined
  and reports `CLAIM_SCAN_TRUNCATED=0` — the 501st call is what first trips
  truncation, not the 500th.
- **Multiple files, only one pathological.** Each file gets its own
  candidate budget (reset per file); an ordinary file scanned alongside a
  pathological one is unaffected and is not listed in
  `CLAIM_SCAN_TRUNCATED_FILES`.
- **`--json` with no truncation.** `TRUNCATED_FILES` is empty, and the
  now-guarded `TRUNCATED_FILES_JSON` construction explicitly emits `"[]"`
  rather than relying on `awk` over a zero-byte, non-newline-terminated
  input (which produces no record at all, not an empty one) — found live via
  this fix's own test suite run: the *existing* `--json` fixtures in
  `disclosure-gate.test.sh` (for a genuinely clean file) broke against a
  first draft of this fix that let `awk` silently see no input, corrupting
  every non-truncated `--json` invocation with a bare comma where
  `"truncated_files"`'s value belongs. Fixed with an explicit
  `[ -n "$TRUNCATED_FILES" ]` guard before the string reaches `awk` at all.
- **A file that is truncated AND otherwise clean.** Exits 3, never 0 — this
  is the exact case AC2 exists to prevent from reading as a genuinely clean,
  fully-scanned result. Confirmed directly (see Testing).

## Interface contracts

- CLI contract unchanged: `dossier-claim-scan.sh [--output-root <path>]
  [--file <path>] [--json] [--quiet]`.
- Exit codes 0/1/2 keep their existing meaning exactly. Exit 3's meaning is
  **widened**, not redefined: it already meant "infra error, could not
  certify"; it now also covers "truncated, could not certify completeness,"
  which is the same category of claim (`dossier-gate.sh`'s own INCONCLUSIVE
  handling already treats exit 3 as one undifferentiated "could not
  evaluate" state, so this is consistent with how the one real caller
  already consumes it). `dossier-gate.sh`'s G06 case statement required no
  change.
- `CLAIM_SCAN_LEAKS`, `CLAIM_SCAN_PROHIBITED_VOCABULARY`,
  `CLAIM_SCAN_UNREGISTERED_SENTENCES`, `CLAIM_SCAN_REGISTER_PRESENT`,
  `CLAIM_SCAN_LINE_CLASSES_EXAMINED` keep their existing meaning and format.
  Their values, on a truncated file, reflect only the candidates actually
  examined — never padded, estimated, or extrapolated to imply full
  coverage.
- New fields, additive only: `CLAIM_SCAN_TRUNCATED` (plain-text and
  `--json`, always printed), `CLAIM_SCAN_TRUNCATED_FILES` (plain-text,
  printed only when truncated), `truncated` / `truncated_files` (`--json`
  keys, always printed). `CLAIM_SCAN_ERROR` gains a second producing
  condition (truncation) alongside its pre-existing "no public directory"
  one; its field name and unconditional-print convention are unchanged.
- `HITS_FILE` row shape unchanged; a truncated candidate never reaches
  `HITS_FILE` at all (it is skipped before any hit could be recorded), so
  `hits[]` continues to mean exactly "findings among what was examined,"
  same as before this fix.

## Testing

- New tests in `plugins/dossier/tests/disclosure-gate.test.sh`:
  - An ordinary registered document explicitly reports
    `CLAIM_SCAN_TRUNCATED=0` and never prints `CLAIM_SCAN_TRUNCATED_FILES=`
    — the cap must be invisible to any document nowhere near it.
  - A 520-cell single-row table (each cell 2 words, below the 4-word floor,
    so none can ever register as an unregistered sentence) exits **3**, not
    0; reports `CLAIM_SCAN_TRUNCATED=1`, `CLAIM_SCAN_TRUNCATED_FILES=`
    naming the file, and `CLAIM_SCAN_UNREGISTERED_SENTENCES=0` — proving the
    exact AC2 property: truncated-but-nothing-found is NOT the same result
    as genuinely clean.
  - The same fixture under `--quiet`: still exits 3, and `CLAIM_SCAN_ERROR=`
    still prints despite `--quiet` — the property `dossier-gate.sh`'s G06
    depends on.
  - The same fixture under `--json` (when `jq` is available): `"truncated":
    true` and the file name present in `truncated_files`.
  - A 521-cell row with a genuine credential in cell 1 still exits 2, not 3
    — a real finding outranks the truncation signal.
- `bash plugins/dossier/tests/run.sh disclosure-gate.test.sh`: 193 pass, 0
  fail (was 190/2 against the first draft, which had the `--json` empty-array
  bug above; fixed and re-run clean).
- `bash plugins/dossier/tests/run.sh` (full suite): 2189 pass, 5 fail — all 5
  in `bin-scripts.test.sh` (chmod-as-root) and `rotation-check.test.sh`
  (git-auth-header), confirmed pre-existing and unrelated to this change
  (neither file references `dossier-claim-scan.sh`).
- Direct `dossier-gate.sh` reproduction: ran `dossier-gate.sh --output-root
  docs/dossier` against the 800-cell-truncated-and-clean fixture directly
  (not through the test suite). Result: `G06   mechanical  INCONCLUSIVE
  script   disclosure scan could not run: scan truncated: ...` and
  `GATE_RESULT=FAIL` overall — confirming the exit-3 reuse actually changes
  `dossier-gate.sh`'s real behavior, not just this script's own exit code in
  isolation.
- Performance, foreground, single runs (no repeated/backgrounded load):
  - Baseline (unmodified logic path, cap not yet reached): 300-cell row,
    7.0s real / ~23ms per cell.
  - Post-fix: 800-cell row (300 cells past the cap): 9.4s–12.8s real,
    reporting exactly 500 examined candidates and `CLAIM_SCAN_TRUNCATED=1`
    — confirming the cap, not the document's actual cell count, now bounds
    wall time. Extrapolated to the issue's literal 5000-cell/~88s
    reproduction: capped cost is ~11.5s regardless of total cell count, a
    reduction from unbounded/minutes to low double-digit seconds.
