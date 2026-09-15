---
issue: 200
title: "claim-scan's substring match silently approves an unscoped claim inside a scoped approved wording"
branch: fix/issue-200-claim-scan-substring-match-bypass
created: '2026-09-15T17:51:45Z'
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T17:51:45Z'
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
---
# Issue #200 — claim-scan's substring match silently approves an unscoped claim

## Specification

_Captured manually (no flow skills registered in this repo) on 2026-09-15,
before writing the regression test. Source: the issue body plus a read of
`dossier-claim-scan.sh`'s registration-check section and
`disclosure-gate.test.sh`'s `md-claim`/`md-emph`/`dotted`/`qualification`
fixtures._

### The bug, precisely

`scan_text()` matches a normalized document sentence against the approved
pool with `grep -qF "$norm" "$APPROVED_FILE"` — fixed-string (no regex) but
**unanchored**: `grep -F` still checks "does this line CONTAIN the pattern
anywhere", not "does this line EQUAL the pattern". A short, unscoped document
sentence that happens to be a literal run of characters inside a longer,
differently-scoped approved wording therefore reads as registered, even
though it asserts something the register never approved (dropped scope,
dropped qualifier, widened claim).

### Why the obvious fix (`grep -qFx`) breaks 6 tests

Swapping to `grep -qFx` (exact whole-line match) alone was tested directly
and fails `md-claim`, `md-emph`, `dotted`, `qualification`, `twosent`, and
`qual-scope`. The root cause is that the two sides of the comparison are
built asymmetrically, in two independent ways:

1. **Trailing punctuation.** A document sentence reaches the match already
   split out of its source line by `tr '.' '\n'` (inside `scan_text`,
   after code spans are stripped) — the terminating `.` is consumed as the
   split delimiter and is gone from the fragment. An approved wording, by
   contrast, was read as ONE unsplit string straight from the register row's
   proposed-wording column and only lowercased/whitespace-collapsed by
   `normalize()` — which never strips a trailing `.`. So a correctly
   registered claim's approved text keeps a full stop the matching document
   sentence structurally cannot have. `grep -qF` (substring) tolerated this
   because "sentence" is always a prefix of "sentence." — `grep -qFx` does
   not.
2. **Multi-sentence register rows.** A single approved row's proposed
   wording can itself contain more than one sentence (the `qualification`
   fixture's qualification cell is one full sentence; a document line
   containing two claims, per the `twosent` fixture, produces two document
   sentences from one line). The register loader never split a row's wording
   into per-sentence fragments before this fix — it normalized the whole
   cell as a single string. An exact match against a whole multi-sentence
   cell can never equal a single split-out document sentence, even when
   that sentence is validly one half of an approved row.

Both problems are instances of the same thing: the document side goes
through `split → normalize`, and the register side only ever went through
`normalize` on the *whole, unsplit* cell. Exact matching after asymmetric
preprocessing is meaningless — the two strings were never going to line up
even for a genuinely-approved claim.

### The fix

Give both sides the identical `split → normalize` pipeline before comparing,
then make the comparison exact.

- Factored the existing inline "strip code spans, then split on `.`" logic
  out of `scan_text()` into a shared `split_candidate_sentences()` function.
  It takes raw text and emits one RAW (not yet `normalize()`'d) sentence
  fragment per line — exactly what `scan_text()`'s inline
  `printf '%s\n' "$SPLITTABLE" | tr '.' '\n'` already produced, just named
  and reusable.
- `scan_text()` now calls this shared function instead of inlining the same
  two operations; its behavior is unchanged (same code-span strip, same `.`
  split, same per-fragment `normalize()` call afterward).
- The register loader (both the main approved-claims block and the
  `## Required qualifications` block) now runs each row's proposed-wording
  cell through `split_candidate_sentences()` too, `normalize()`s each
  resulting fragment individually, drops empty fragments (mirroring the
  document side's `[ -z "$norm" ] && continue`), and writes one normalized
  sentence per line to `APPROVED_FILE` instead of one normalized *row* per
  line.
- The lookup becomes `grep -qFx "$norm" "$APPROVED_FILE"` — exact whole-line
  match against the now-symmetrically-split, normalized pool.

This directly fixes the issue's reproduction: the approved wording "the api
supports oauth 20 device flow **for enterprise customers only in the us
region**" and the document sentence "the api supports oauth 20 device flow"
are no longer compared as substring-vs-superstring; they are compared as two
complete, independently normalized strings, and they are not equal, so the
unscoped sentence is correctly reported `unregistered`.

It also repairs the 6 tests the naive swap broke, because the register side
now loses its trailing period at the same split step the document side
already loses it, and a multi-sentence register cell now contributes one
pool entry per sentence instead of one unsplittable blob.

### Non-goals

- Not changing anything about which lines are fed into `scan_text()`
  (bullets, blockquotes, table cells, paragraphs — issue #176's scope).
  This fix only changes how the registration comparison itself is computed,
  not what content reaches it.
- Not adding fuzzy/semantic matching. The fix keeps the check literal and
  deterministic — it changes *substring* to *exact-per-sentence*, not
  "approximately similar."
- Not changing `normalize()`'s markdown-stripping or casing behavior. Both
  sides still go through the same `normalize()` this issue leaves untouched;
  only *what gets fed into it* (a whole row vs. one split sentence) changes.
- Not attempting Unicode-aware case folding. `normalize()`'s
  `tr '[:upper:]' '[:lower:]'` only folds ASCII in the C/POSIX locale, same
  as before this fix; an accented character in either the register or the
  document is unaffected by this change specifically and was never affected
  by the substring-vs-exact distinction either.
- Not changing the claim register file format, the `## Required
  qualifications` handling, or the `## Rejected and withdrawn claims`
  exclusion logic (issue #176 territory) — only which text those existing
  sections' cells contribute to the approved pool.
- Not fixing bare (non-code-span) decimal-number sentence splitting.
  `split_candidate_sentences()` only protects a period inside backtick-code
  spans (`` `3.2.2` ``, `` `SKILL.md` ``) from being read as a sentence
  boundary — a bare decimal like `99.9% uptime` still splits at the decimal
  point on BOTH sides now, same as the document side alone did before this
  fix. Confirmed empirically this does not create a new bypass: the pre-fix
  substring match already happened to pass an equivalent fixture for the
  same underlying reason (the split-off fragment was already a substring of
  the old unsplit approved text), so this fix changes nothing about that
  pre-existing, orthogonal gap — it is not part of issue #200's scope and is
  called out here only so it is not mistaken for something this fix
  introduced.

### Failure modes

- **Empty approved wording cell** — `split_candidate_sentences("")` yields a
  single empty fragment; `normalize()` of that is empty; the loader's
  `[ -z "$norm" ] && continue` drops it before it ever reaches
  `APPROVED_FILE`. No crash, no spurious blank-line pool entry (a strict
  improvement over the pre-fix loader, which had no such guard and could
  write an empty line — harmless in practice since a document-side `$norm`
  can also never be empty at the match site, but now guarded explicitly on
  both sides for the same reason).
- **Approved row that is only punctuation** (e.g. a wording cell of `...`)
  — splits into several empty fragments (three `.` characters produce four
  empty segments), every one dropped by the same empty-fragment guard. Under
  the OLD substring match this was already inert: a normalized *document*
  sentence can never itself contain a literal `.` (it was always split out
  on `.` before normalization), so a raw `...` pool entry could never be a
  substring match target for anything real. Not a regression; slightly
  cleaner (no dead pool entries) as a side effect.
- **Register file present but contributes zero approved sentences after
  splitting** (e.g. every row is in the Rejected/Withdrawn section, or every
  row's wording normalizes to empty) — `APPROVED_FILE` stays empty,
  `[ -s "$APPROVED_FILE" ]` is false, and the existing "register present but
  nothing approved" path is unchanged: every document sentence reports
  unregistered. Same as before this fix.
- **A document sentence that legitimately needs to span what looks like two
  approved sentences** (e.g. "X. Y." approved as one wording that a document
  writes as one combined sentence "X and Y.") — out of scope; this fix does
  not add cross-sentence combination, only symmetric per-sentence splitting.
  Not reported as newly broken by any existing fixture; flagged here as a
  known limitation, not silently glossed over.

### Interface contracts

- CLI contract unchanged: `dossier-claim-scan.sh [--file <path>] [--json]
  [--output-root <dir>]`, exit codes unchanged (0 clean / 1 findings /
  2 leak / 3 missing dir).
- `CLAIM_SCAN_UNREGISTERED_SENTENCES` and all other `CLAIM_SCAN_*` summary
  fields keep their existing meaning and format; only which sentences count
  as registered changes (narrower, correctly so).
- `HITS_FILE` row shape (`unregistered\t<file>\t<line>\t<redacted-excerpt>`)
  is unchanged.
- New internal function `split_candidate_sentences()` is not part of the
  script's CLI surface (the script is not designed to be sourced as a
  library, per the existing `redact()` header comment) — it is an
  implementation-sharing refactor between `scan_text()` and the register
  loader, not a new public contract.
- No change to the claim-and-disclosure-register.md file format or column
  layout.
