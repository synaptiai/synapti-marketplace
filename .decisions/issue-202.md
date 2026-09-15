---
issue: 202
title: "claim-scan only recognizes backtick fences, not the full CommonMark fence grammar (~~~)"
branch: fix/issue-202-claim-scan-tilde-fence-grammar
created: '2026-09-15T19:15:00Z'
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T19:15:00Z'
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
---
# Issue #202 — claim-scan doesn't recognize `~~~` fences

## Specification

_Captured manually (no flow skills registered in this repo) on 2026-09-15,
before writing the regression test. Source: the issue body plus a read of
`dossier-claim-scan.sh`'s fence-toggle case block (main scan loop) and
`disclosure-gate.test.sh`'s `heading-fence-exempt` fixture._

### The bug, precisely

The fence-toggle is a single `case "$line" in '```'*) ... esac` arm that
flips a boolean `IN_FENCE` on any line starting with three-or-more
backticks. It has no branch at all for `~~~`, so a `~~~`-delimited block's
contents never set `IN_FENCE=1` and fall straight into the ordinary
prose/table path, where claim-shaped text inside it gets flagged as an
unregistered sentence. Per the issue, this fails in the safe direction
(over-reporting), never suppresses a genuine finding — but it's still a
correctness gap a drafter has to triage for no reason.

### Does fence-character matching matter here, or is the toggle model safe to extend as-is?

It matters, and I verified this empirically before choosing a design, rather
than assuming either way.

CommonMark's actual rule: a fence's closer must use the *same character* as
its opener (and be at least as long — length-matching is not pursued here,
see Non-goals). This script's existing backtick-only model never had to
care about character-matching, because there was only one recognized fence
character; the moment a second one (`~~~`) is added to the *same* boolean
toggle, character-matching becomes load-bearing, not cosmetic.

I simulated the naive extension — `case "$line" in '```'*|'~~~'*) IN_FENCE=$((1
- IN_FENCE)) ;; esac`, i.e. one shared toggle, no memory of which character
opened the fence — against a backtick-fenced block containing a decoy `~~~`
line (e.g. a code comment that happens to start with tildes) followed by
genuine prose after the real closing ` ``` `. Result, run for real (not
predicted): the decoy line toggles `IN_FENCE` off early, so:

1. The remaining *actual code content* between the decoy and the real
   closer gets exposed as prose (the same safe-direction over-reporting
   the issue itself describes — tolerable).
2. The real closing ` ``` ` then toggles `IN_FENCE` back *on*, so the
   genuine prose paragraph that follows the fence in the document is
   silently treated as "still inside a fence" and skipped entirely —
   never reaching the registration check.

(2) is the dangerous direction this scanner's whole design (see the
script's own header comment: "the cost of a false negative here is an
unretractable public claim") exists to avoid. So the toggle model is *not*
safe to extend by simply adding a second pattern to the same arm — it needs
to track which character opened the current fence and only close on a
match of that same character. It does **not** need to track fence *length*
(e.g. a 4-backtick opener requiring a 4-backtick closer) — the existing
backtick-only model already ignores length (any run of 3+ backticks toggles
regardless of count), and extending that same simplification to tildes is
consistent, not a new gap; only the *character* dimension is new because
only the character dimension is what a second fence type introduces.

### The fix

- A new `FENCE_CHAR` state variable (reset to `""` alongside `IN_FENCE=0` at
  the top of each file's scan) records which character opened the
  currently-open fence.
- The fence-toggle `case` gets two arms, one per character, each with the
  same open/close shape: entering a fence (`IN_FENCE=0`) always opens and
  records `FENCE_CHAR`; a line of the *other* character while already
  inside a fence matches its own case arm (so it's still consumed/skipped
  as fence syntax, not fed to the prose scanner) but does **not** toggle,
  because `FENCE_CHAR` doesn't match. Only a same-character line while
  `IN_FENCE=1` closes the fence.
- Per the issue's suggested resolution, the fence-detection match also
  tolerates 0-3 leading spaces (CommonMark's fence-indentation rule) before
  the fence marker. This is a bounded, capped tolerance — 4+ leading spaces
  is a different, unimplemented CommonMark construct (an indented code
  block) and must NOT be recognized as a fence, so the probe strips at most
  3 leading spaces and then requires the fence characters immediately after
  what was stripped; a 4th leading space survives the strip and correctly
  fails the match. This is deliberately a narrower, capped operation than
  the *unconditional* leading-whitespace strip applied later in the loop
  (line ~772, for classifying bullets/tables/blockquotes) — that strip is
  unbounded and happens only after the in-fence `continue` already fired,
  so it never reaches fence detection; conflating the two would silently
  turn a 4-space *indented code block* into a recognized fence, which is
  not what CommonMark specifies and not what this fix claims to add.

### Non-goals

- Not implementing CommonMark's fence-*length* matching (closer must be
  `>=` opener's backtick/tilde count). The existing backtick model never
  had this either; adding it now would be a bigger, unrelated behavior
  change and no fixture in this repo depends on it.
- Not implementing 4-space indented code blocks (a distinct CommonMark
  construct, already called out as unimplemented in the surrounding code
  comment before this fix, and still true after it — only 0-3 leading
  spaces before a `` ``` `` /`~~~` marker are now tolerated, not raw
  4-space-indented prose).
- Not touching the table-state-across-fence logic (`flush_held_table_row`,
  `TABLE_ROWS_SEEN` reset) added for issue #176 — the fence-toggle arms
  still call it on every genuine open/close transition, unchanged in
  behavior, just now duplicated across the two fence-character arms.
- Not changing anything about the registration/leakage checks themselves —
  this is purely about which lines are classified as "inside a fence" and
  therefore exempt.

### Failure modes

- **A `~~~` fence never closed before EOF** — same behavior as an unclosed
  backtick fence today: `IN_FENCE` stays 1 for the rest of the file, so the
  remainder of the document is (silently) treated as fenced. Pre-existing
  shape, unchanged by this fix, not attempted here.
- **Mismatched fence characters (backtick inside tilde fence, or vice
  versa)** — the primary risk this fix's design addresses; verified above
  that the naive extension mis-toggles and silently drops real prose after
  the genuine closer. The character-tracking design closes this: a
  same-character close only recognized after a same-character open.
- **4+ leading spaces before a fence marker** — deliberately NOT recognized
  as a fence (falls through to ordinary prose handling, an existing,
  unrelated, pre-existing gap for indented code blocks generally).

### Interface contracts

- CLI contract unchanged: `dossier-claim-scan.sh [--file <path>] [--json]
  [--output-root <dir>]`, exit codes unchanged (0 clean / 1 findings /
  2 leak / 3 missing dir).
- `CLAIM_SCAN_UNREGISTERED_SENTENCES` and the other `CLAIM_SCAN_*` summary
  fields keep their existing meaning; only which lines count as "inside a
  fence" (and are therefore exempt) changes.
- `LINE_CLASSES_EXAMINED` is unchanged — fenced code was, and remains,
  structurally exempt, not one of the examined classes.
- No new CLI flags, no change to the claim register file format.
