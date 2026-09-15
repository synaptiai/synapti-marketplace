---
issue: 210
title: "claim-scan's connection-string pattern misses an interrupted lone occurrence entirely"
branch: fix/issue-210-connection-string-credential-leak
created: '2026-09-15T18:30:00Z'
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T18:30:00Z'
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - tradeoff
---
# Issue #210 — claim-scan's connection-string pattern misses an interrupted lone occurrence

## Specification

_Captured manually (no flow skills registered in this repo) on 2026-09-15,
before writing the regression tests. Source: the issue body, `.decisions/issue-198.md`
(which deferred this exact class to this issue), and a read of
`dossier-claim-scan.sh`'s `CRED_PATTERNS`/`scan_class` sections._

### The bug, precisely

`connection-string`'s pattern requires an unbroken `user:password@` span:

```
(postgres|postgresql|mysql|mongodb\+srv|redis|amqp)://[^[:space:]/]+:[^[:space:]@]+@
```

Like `aws-access-key` and `private-key-block` (fixed in #198), this is an
exact-format pattern, not an open-ended `{N,}` character class: it requires
reaching a literal trailing `@`. The other 5 credential classes still match a
*truncated prefix* when interrupted by a stray character (something survives,
so redaction still fires); this one requires the password segment to run
unbroken all the way to `@`, so a single interrupting character anywhere
inside that segment makes the *entire* pattern fail to match — not a
fragment leak, a full non-detection. The raw value then passes straight
through the excerpt, unredacted, and `LEAKS` never increments (exit 1, not 2).

### Why this wasn't fixed alongside aws-access-key/private-key-block in #198

#198's own risk map already found this class and explicitly deferred it
(user-confirmed decision, `.decisions/issue-198.md` row "Exact-format
pattern, lone interrupted occurrence"): naively applying the same
`[interrupt]?` loosening to the *entire* password charset creates a real
false positive, because the password class has no fixed length to bound
it (unlike AKIA's fixed 16 characters or the PEM header's fixed literal
text). An unbounded "any run up to the next `@`" loosening lets the pattern
bridge straight past unrelated punctuation and an unrelated `@` elsewhere in
the sentence:

```
"Connect via postgres://db:5432/app, ops@corp for support."
```

— wrongly flagged as a connection-string leak, because a loosened password
class can span from the `:` after `db` all the way to the `@` in `ops@corp`.

### Decision (already made by the repo owner — not re-litigated here)

Implement the **conservative, tightly-bounded** option: tolerate exactly ONE
interrupting character (space, `|`, or `,`) within the password segment,
mirroring #198's own bound for `aws-access-key`/`private-key-block` — not the
naive "any run up to the next `@`" loosening.

### The fix

Mirror #198's technique exactly, adapted for a variable-length body instead
of AKIA's fixed 16-character count. #198's pattern for AKIA is:

```
AKIA[ |,]?([0-9A-Z][ |,]?){16}
```

— prefix, then a fixed count of (real-char, optional single interrupter)
pairs. `connection-string`'s password has no fixed length, so the fixed
`{16}` becomes an open-ended `+` over the same (real-char, optional single
interrupter) unit, and the real-char class itself is narrowed to exclude the
three interrupter characters (space, `|`, `,`) so they can only appear in the
designated single-interrupter slot, never as an ordinary password character
run into the next slot:

```
[^[:space:]/]+:[ |,]?([^[:space:]@|,][ |,]?)+@
```

- `[^[:space:]/]+:` — host segment, unchanged from the original pattern.
- `[ |,]?` — tolerates a single interrupter right at the host/password
  boundary (the colon), mirroring #198 round 3's finding that the
  prefix/body boundary is a distinct position from the interior and needs
  its own tolerance slot.
- `([^[:space:]@|,][ |,]?)+` — one or more real password characters, each
  optionally followed by exactly one interrupter. Because the interrupter
  slot is *attached to* a preceding real character rather than being an
  independent repeatable unit, two interrupters in a row (e.g. `, ` — a
  comma directly followed by a space) can never both be consumed: the first
  is consumed as the trailing interrupter of the prior real character, and
  the second cannot start a new iteration (it isn't a real-char) and isn't
  itself eligible to fill the *same* iteration's interrupter slot again.
  This is what keeps the false-positive guard case rejected — see Tradeoff
  below.
- `@` — unchanged, still a required literal terminator.

Applied identically to both copies of the pattern that must stay in sync
(documented at `CRED_CLASSES`'s header comment): `CRED_PATTERNS[5]` (used by
`redact()`/`cred_match_class()`/`scan_text()`'s pre-check) and section A's
`scan_class ... "connection-string"` call (the hand-maintained third copy
that runs before `CRED_PATTERNS` exists in load order).

### Tradeoff (the important part of this entry)

**What it catches:** a password interrupted by exactly one stray character
at any single position within the segment — a line-wrap, a copy-paste
artifact inserting one space/pipe/comma, or several *separate* single-
character interruptions at different positions in the same password (each
position gets its own independent interrupter slot, same as #198's AKIA
fix tolerates multiple separate single-char interruptions across the 16
body positions). This is judged the realistic case: an accidental reflow or
paste error introduces one stray character at one spot, not a cluster.

**What it still misses:** two-or-more interrupting characters *consecutively
at the same position* (e.g. two spaces, or a comma immediately followed by a
space, wedged into the middle of an otherwise-real password run). Verified
directly: `Sup3rSecret  Pass@host` (two spaces) and `Sup3rSecret, Pass@host`
(comma+space) do **not** match the new pattern, same as they didn't match
the old one.

**Why this residual gap is acceptable:** it is the exact same gap the
false-positive guard case depends on being closed. The reproduction from the
issue body that this fix must NOT flag —
`postgres://db:5432/app, ops@corp for support.` — contains precisely a
comma-then-space pair (`, `) between `app` and `ops`, i.e. two consecutive
interrupting characters at one position, immediately before an unrelated
`@`. Widening the bound to tolerate 2+ consecutive interrupters would
re-open that exact false positive: the password class could then bridge
`5432/app` + `, ` + `ops` all the way to the unrelated `@` in `ops@corp` and
wrongly flag a sentence that merely mentions a scheme with no embedded
credential at all. A single stray character is judged realistic (line-wrap,
paste artifact); two-or-more consecutive stray characters bridging into
unrelated prose is exactly the shape a false positive takes. Accepting the
narrower miss (a password mangled by two-or-more consecutive interruptions
goes undetected) over the wider false-positive surface (innocent scheme
mentions get flagged as leaks) is the same tradeoff #198 already made for
`aws-access-key`/`private-key-block`, applied here with the added
justification that, unlike those two classes, this one has a documented,
concrete false-positive reproduction to weigh against — not a hypothetical.

### Non-goals

- Does not change the host segment (`[^[:space:]/]+`) — the issue and the
  false-positive reproduction are both about the *password* segment
  specifically; the host segment's existing behavior (already tolerant of
  colons, since backtracking finds the right split point) is untouched.
- Does not touch `aws-access-key` or `private-key-block` — already fixed in
  #198; unrelated to this change beyond supplying the technique to mirror.
- Does not widen the false-positive surface by loosening to "any run up to
  the next `@`" — the option explicitly rejected by #198's own decision and
  reaffirmed by the repo owner's product triage on this issue.
- Does not add a general "N interruptions tolerated" configuration knob —
  out of scope; the bound is fixed at exactly one, matching #198's own fixed
  bound for the other two exact-format classes.

### Failure modes

- A password with zero interruptions — pattern behaves identically to the
  original (the interrupter slots are all optional, `?`), no behavior change
  for already-passing connection strings.
- A password entirely absent (bare `scheme://host/path` with no `user:pass@`
  at all) — no `:` immediately followed by a password-shaped run and a
  literal `@`, so the pattern does not match, same as before this fix.
- Multiple `@` characters in the same string (e.g. a password containing a
  literal `@`, or an unrelated second `@` later in the sentence) — unchanged
  pre-existing behavior, not addressed by or regressed by this fix: the
  password class still stops at the *first* `@` it reaches, same as the
  original pattern. Confirmed empirically on `main` before this change.
- Uppercase/mixed-case scheme (`POSTGRES://...`) — unchanged pre-existing
  behavior: schemes are matched case-sensitively (lowercase only), same as
  before this fix; out of scope for this issue.

### Interface contracts

- CLI contract unchanged: exit codes (0 clean / 1 registration gaps / 2
  leakage / 3 infra error) unchanged.
- The `connection-string` class name and its `[REDACTED:connection-string]`
  tag are unchanged.
- `CRED_PATTERNS`, `CRED_CLASSES`, `CRED_UNION_PATTERN`, and
  `cred_match_class()`'s contracts are unchanged — only `CRED_PATTERNS[5]`'s
  pattern text changes, plus its hand-maintained twin in section A's
  `scan_class` call.
