---
issue: 221
title: "claim-scan's CRLF strip is superlinear on very long lines (bash 3.2)"
branch: fix/issue-221-claim-scan-crlf-strip-superlinear
created: '2026-09-15T19:45:15Z'
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T19:45:15Z'
  elements:
  - environment-scope
  - correctness-comparison
  - performance-comparison
  - interface-contracts
---
# Issue #221 — claim-scan's CRLF strip is superlinear on very long lines (bash 3.2)

## Environment scope — what could and couldn't be verified directly

**This environment runs bash 5.2.21, not bash 3.2.57.** Checked first, per the
issue's own instruction:

```
$BASH_VERSION → 5.2.21(1)-release
```

This matches the issue's own prediction exactly ("you will probably NOT be
able to reproduce the superlinear behavior directly in your own sandbox").
Consequences, stated plainly rather than glossed over:

- **The original superlinear behavior could NOT be reproduced directly.**
  Bash 3.2.57 is macOS's stock `/bin/bash`; bash ≥4 rewrote the affected
  pattern-matching internals and is not known to carry the same multibyte
  `fnmatch`/pattern-removal cost-class bug. Measured directly below (see
  Performance): this environment's own `${line%$'\r'}` is already linear, not
  quadratic, at every size tested up to 11.7MB.
- **This does not make the fix unnecessary or unverifiable.** The issue's own
  scope section is explicit that the fix must be "correct on its own merits"
  — a linear-time external tool, verified for byte-for-byte behavioral
  equivalence against the original bash-native strip — not that the
  superlinear symptom must be reproduced first. That equivalence IS verified
  directly below, on real input, independent of which bash version is
  running it.
- Everything in this entry that depends on bash 3.2's specific cost class
  (the 15.9s/37.7s/98.1s figures) is taken from the issue report as given,
  not re-measured. Everything about correctness and this environment's own
  performance is measured directly, in this repo, in this session.

## The fix — what changed, precisely

One occurrence of the pattern in `dossier-claim-scan.sh`: the main per-file
line loop (`for f in $TARGETS; do ... while IFS= read -r line ...; done < "$f"
... done`, starting ~line 765 pre-fix). Grepped the whole file for `\$'\r'`
and `\br\b`-adjacent patterns first — this is the only site; nothing else in
the file strips CRLF (the newer credential-detection code the issue names as
"not implicated" — `scan_text()`'s whole-line pre-check, `cred_match_class()`
— both delegate to `grep`, confirmed by inspection, untouched by this fix).

- Removed the per-line `line=${line%$'\r'}` (was line ~811).
- Changed the loop's input redirection from `done < "$f"` to
  `done < <(sed $'s/\r$//' < "$f")` — `sed` runs **once per file**, not once
  per line, stripping a trailing `\r` from every line before `read` ever
  sees it.
- Process substitution (`<(...)`), not a `| sed ...` pipe feeding the `while`
  directly: piping would make the `while` the last stage of a pipeline,
  which bash runs in a subshell, and every counter/flag the loop sets
  (`CANDIDATES_EXAMINED`, `LN`, `IN_HEADER`, `IN_FENCE`, the `TABLE_*`
  state) would then vanish at loop exit instead of surviving into the rest
  of that `for f` iteration — the same hazard the file's own pre-existing
  comment already calls out for `done < "$f"` (line ~615). Confirmed this
  matters in practice: an earlier draft using a plain pipe made
  `CANDIDATES_EXAMINED` and `LN` reset to stale values after the loop, and
  `flush_held_table_row` (which reads `TABLE_HELD_LINE` right after the
  loop) silently saw pre-loop state. Caught by re-running the full suite
  against that draft (multiple table/truncation-cap assertions failed);
  switched to process substitution and re-ran clean.

## Correctness — `sed $'s/\r$//'` vs. `tr -d '\r'`, verified, not assumed

The issue's suggested resolution names `tr -d '\r'` as "e.g." one option.
**This fix does NOT use `tr -d '\r'`.** `tr` deletes every `\r` byte
anywhere in its input; the original `${line%$'\r'}` only ever strips ONE
trailing `\r`, immediately before the line's terminating `\n` — an embedded
`\r` elsewhere in the line (not at the very end) was always left untouched
by the pre-fix code. Checked whether that's a realistic input rather than a
paper concern: yes — a pasted terminal transcript with progress-bar `\r`s
(inside a fenced code block, or copied into prose) is exactly the kind of
content a public markdown doc can plausibly contain, and it produces a `\r`
that `read -r` places in the MIDDLE of `$line`, not at its end.

Verified empirically (not assumed) with a single probe script exercising five
cases side by side — the original per-line bash strip, `sed $'s/\r$//'`, and
`tr -d '\r'` — against one input containing all of them: a normal trailing
CRLF, a line with no `\r` at all, a `\r` embedded mid-line (not at the end), a
doubled trailing `\r\r`, and a final line with no trailing newline.

| input line | original `${line%$'\r'}` | `sed $'s/\r$//'` | `tr -d '\r'` |
|---|---|---|---|
| `trailing\r` (+ `\n`) | `trailing` | `trailing` | `trailing` |
| `no-cr` (+ `\n`) | `no-cr` | `no-cr` | `no-cr` |
| `embedded\rmid` (+ `\n`) | `embedded␍mid` (kept) | `embedded␍mid` (kept) | `embeddedmid` (**deleted**) |
| `cr-cr\r\r` (+ `\n`) | `cr-cr␍` (one kept) | `cr-cr␍` (one kept) | `cr-cr` (**both deleted**) |
| `last-no-nl\r` (no trailing `\n`) | `last-no-nl` | `last-no-nl` | `last-no-nl` |

`sed $'s/\r$//'` reproduces the original bash-native strip byte-for-byte on
every case, including the two where `tr -d '\r'` diverges. That divergence is
not cosmetic: `normalize()` (`sed -e '...' -e 's/[[:space:]]\{1,\}/ /g' ...`)
treats `\r` as whitespace (POSIX `[[:space:]]` includes it) and collapses it
to a single space. So under the ORIGINAL code and under this fix, an embedded
`\r` between two words becomes a space-separated pair after `normalize()`
("two words"); under `tr -d '\r'` it would have been deleted before
`normalize()` ever ran, gluing the words together ("twowords") — silently
changing which sentences match an approved register row. This is exactly the
kind of untested assumption the issue's own AC calls out ("if that's even a
realistic input — check"): checked, confirmed realistic, and confirmed that
`tr -d '\r'` would have been a real, silent correctness regression, not just
a style choice. `sed $'s/\r$//'` avoids it entirely by staying anchored to
"trailing only," same as the code it replaces.

This comparison is now also a permanent regression test (see Testing below,
`embedded-mid-line-cr` case) — not just a one-off probe.

## Performance — measured on bash 5.2.21, honestly, including where it's worse

Single foreground run, this session's own hardware, comparing the OLD
per-line `${line%$'\r'}` loop against the NEW `sed $'s/\r$//'` +
process-substitution loop, on one very long single line (matching the
issue's own repro shape) at four sizes:

| line size | old (bash native) | new (`sed`, one fork per file) |
|---|---|---|
| 183,000 B | 0.006s | 0.038s |
| 732,000 B | 0.023s | 0.141s |
| 2,928,000 B | 0.076s | 0.565s |
| 11,712,000 B | 0.299s | 2.243s |

Two honest findings, not glossed over:

1. **This environment's bash is already linear, not quadratic.** Old-approach
   timings scale close to linearly with size (≈4× size → ≈4× time), which is
   exactly what the issue's own scope section predicts for bash ≥4 and is
   consistent with not being able to reproduce the superlinear behavior here.
2. **On this bash version, the new approach is slower in relative terms —
   roughly 6-8× — not faster.** Isolated why: reran with `awk` and `tr` in
   place of `sed` (same fork-once-per-file shape) and all three land within a
   few ms of each other at both sizes tested, and a control run of `sed`
   against `/dev/null` (fixed fork+pipe-setup cost alone) measured 0.004s —
   so the gap is not `sed`'s own regex engine being slow, it's the inherent
   cost of moving the data through an OS pipe and re-buffering it in `read`,
   which any external-filter approach pays and pure in-process bash string
   manipulation does not. There is no faster *correct* external-tool
   substitute available among the ones checked.

Why this is still the right trade-off, not a regression to worry about:

- The absolute added cost is small in every case tested — worst case
  measured (11.7MB, far past any real single line this scanner is likely to
  see) is ~2.2s; at the issue's own largest reproduction size (732,000
  bytes) the added cost is ~120ms. This is once per FILE, not per line, and
  is dwarfed by the multiple *seconds* `scan_text()` itself already spends
  forking a dozen subprocesses per candidate sentence elsewhere in this same
  script (see `.decisions/issue-199.md`).
- The fix's entire purpose is bounding bash 3.2's cost, not bash 5's. On the
  actual target (bash 3.2.57), the old approach measured 98.1s at 732,000
  bytes (per the issue); the new approach's cost is external-tool-driven and
  not tied to the calling shell's own pattern-matching implementation, so
  there is no reason to expect it to inherit bash 3.2's quadratic behavior —
  it should cost approximately what it costs here (order ~100ms at that
  size), not ~100s. That specific claim (new approach's absolute cost on
  bash 3.2 itself) could not be verified directly, for the same reason the
  original superlinear behavior couldn't be reproduced directly: no bash 3.2
  binary was available in this environment. It rests on `sed` being a
  separate compiled binary whose own performance does not depend on which
  shell invokes it — a structural argument, not a measurement, and flagged
  as such.
- A fully bash-native alternative that might avoid both the external-fork
  cost AND (if it worked) bash 3.2's bug — e.g. length-indexed
  `${line: -1}` / `${line:0:...}` instead of pattern-matching suffix removal
  — was considered and deliberately NOT taken. There is no way to verify from
  this environment whether bash 3.2's known cost-class problem is scoped
  narrowly to `fnmatch`-based pattern operators specifically, or more
  broadly to its string-handling internals in that release; guessing wrong
  on the one platform this issue is actually about would violate this
  project's own "No Assumption-Driven Decisions" boundary. The issue's own
  suggested resolution names an external tool for exactly this reason (it
  doesn't matter what bash 3.2's internals do at all), and this fix follows
  that, not a scheme that would need bash-3.2-specific verification this
  session cannot perform.

## Testing

- New tests in `plugins/dossier/tests/disclosure-gate.test.sh` (issue #221
  section, after the two pre-existing CRLF fixtures for #199/#210-era
  header/table symptoms):
  - `registered-crlf` — a CRLF-terminated plain declarative sentence that
    exactly matches an approved register row still passes (exit 0).
  - `unregistered-crlf` — the same sentence with no register row still
    exits 1 and is still labelled `UNREGISTERED`, not silently dropped.
  - `embedded-mid-line-cr` — a `\r` embedded mid-sentence (not a line
    terminator) is preserved and collapsed to a space by `normalize()`,
    matching a register row phrased with a real space in that position —
    the direct regression guard for the `sed` vs. `tr -d '\r'` divergence
    documented above.
  - The two pre-existing CRLF fixtures (frontmatter-closer, table-separator)
    were left as-is; both still pass, confirming the refactor didn't
    reintroduce either symptom.
- **TDD sequencing, as instructed**: all three new assertions were run
  against the PRE-FIX script first (temporarily restoring
  `git show HEAD:...` — the tip of `main` — over the working file, then
  restoring the fixed version afterward) and passed there too, 197/197 in
  `disclosure-gate.test.sh`. This is expected and intentional, not a bug in
  the tests: pre-fix code is correct, only slow on bash 3.2, so these are
  regression guards for the refactor, not a red/green cycle for a
  correctness bug. Confirmed the fixed version also passes the same
  197/197 afterward.
- `bash plugins/dossier/tests/run.sh disclosure-gate.test.sh`: 197 pass, 0
  fail (post-fix).
- `bash plugins/dossier/tests/run.sh` (full suite): 2193 pass, 5 fail — all
  5 pre-existing and confirmed unrelated to this change:
  - `bin-scripts.test.sh` (2 failures): both about a simulated
    permission-denied temp-file/copy failure not actually failing, because
    this session runs as root (chmod-based write-denial simulations don't
    bind on root). Neither assertion touches `dossier-claim-scan.sh`.
  - `rotation-check.test.sh` (3 failures): all about `GIT_CONFIG_*`
    auth-header environment variables not being set/unset as the test
    expects, unrelated to markdown scanning or CRLF handling entirely.
  - Re-ran both files in isolation to capture exact assertion names/line
    numbers and confirm neither is new: `bin-scripts.test.sh:689`,
    `bin-scripts.test.sh:768`, `rotation-check.test.sh:740/757/760` — same
    shape the issue's own Process section names in advance
    ("chmod-as-root in bin-scripts.test.sh, git-auth-header in
    rotation-check.test.sh").

## Interface contracts

- No change to the script's CLI, exit codes, or any `CLAIM_SCAN_*` output
  field. This is a pure internal-implementation refactor of one line-ending
  normalization step.
- `LN` (reported line numbers) is unaffected: `sed $'s/\r$//'` never adds,
  removes, or reorders lines, only strips a trailing `\r` byte per line —
  confirmed by the full test suite's line-number-specific assertions (e.g.
  `technical-partner-guide.md:1 ...` / `:2 ...`) still passing unchanged.
- No new external-tool dependency: `sed` is already relied on elsewhere in
  this same file (`normalize()`, `split_candidate_sentences()`) and is a
  base-system utility on both this environment (GNU sed, Linux) and the
  issue's target (BSD sed, macOS). The specific idiom used —
  `$'s/\r$//'`, a literal CR byte via bash ANSI-C quoting rather than a
  `\r` regex escape — was chosen deliberately for BSD-sed portability: GNU
  sed accepts `\r` as an escape, BSD sed's regex engine is not guaranteed
  to, but both accept a literal control-character byte in the pattern
  identically, since it isn't an escape at all. This specific portability
  claim about BSD sed could not be executed directly (no macOS/BSD sed
  available in this environment) — flagged, not silently assumed, same as
  the bash-3.2 timing claim above.
