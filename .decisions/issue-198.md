---
issue: 198
created: '2026-09-15T11:03:06Z'
artifacts:
- type: specification
  captured_at: '2026-09-15T11:03:06Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-15T11:03:36Z'
  goal_id: issue-198
  ac_count: 3
- type: workflow-run
  captured_at: '2026-09-15T11:03:37Z'
  workflow: start-issue
  run_id: 2026-09-15T110500Z-issue-198
  status: active
- type: goal-amendment
  captured_at: '2026-09-15T15:35:00Z'
  reason: sentence_split_non_goal_reversed_by_review_findings
  by: self-review-fix-forward
- type: user-decision
  captured_at: '2026-09-15T16:10:00Z'
  question: exact_format_pattern_disposition_and_locator_scope
  decisions:
  - 'F1 (exact-format lone-interrupted gap): fix aws-access-key and private-key-block
    now; defer connection-string to issue #210 (real false-positive tradeoff, no
    tolerance level picked unilaterally)'
  - 'Locator scope (issue title vs body mismatch): the 4 locator classes stay out
    of #198''s scope -- the issue body''s own acceptance criteria never asked for
    excerpt-redaction of locators, only for the credential-interruption fix'
- type: holdout-validation
  captured_at: '2026-09-15T17:30:00Z'
  result: PASS
  finding_fixed_during_check: stale AKIA literal-pattern reference in a comment,
    dossier-claim-scan.sh:432
---
# Issue #198 — claim-scan's redact() leaves fragments past an interrupting character

## Specification

### Non-goals

- Does NOT change section A's `scan_class ... leak` detection path (`dossier-claim-scan.sh:108-127`) — that path already never prints the matched value (it only increments a `LEAKS` counter for the exit-code decision) and is unaffected by this bug; confirmed by reading it, not assumed.
- Does NOT add new credential classes beyond the 8 already defined in `redact()` — out of scope; this issue is about the redaction *mechanism* (inline character-class substitution vs. whole-excerpt replacement), not the pattern list's coverage.
- Does NOT change `scan_text()`'s code-span stripping or its 4-word minimum for what counts as a reportable claim — those exist to judge claim-drafting quality (a fragment or a heading is not a claim), not credential safety, and are out of scope for this issue.
  - **Revised 2026-09-15, mid-review**: the `.`-based sentence split itself is now IN scope, reversing this non-goal's original text ("Does NOT change the `scan_text()`/sentence-splitting logic ... only what `redact()` does with a sentence that matches is in scope"). Both self-review agents independently found that the split — run *before* `redact()` ever sees the text — is the actual leak mechanism for any credential whose matched span contains a literal `.` (a JWT's two internal periods; a connection-string's dotted hostname): the split lands part of the credential on each side, and `redact()` can only discard the one fragment it's given, never reassemble the line to see the whole credential. That is squarely the same bug class this issue exists to close, discovered mid-fix rather than at spec time — not a new, separate concern. See risk map row 5 below for the fix and its discriminating check.
- Does NOT preserve the `\1\2` prefix-context capture (key name + separator) the old `secret-assignment` pattern kept before its redacted value — no existing test asserts that prefix survives, and keeping any part of the original text raises exactly the "how much survives" question this issue exists to close. The whole sentence becomes the placeholder.

### Failure modes

- Timeout / partial failure: none — pure text-processing change, no network or long-running I/O.
- Invalid input: a sentence containing a credential-shaped pattern immediately adjacent to markdown syntax already stripped upstream (code spans, by `scan_text`) — not this function's concern, arrives pre-stripped.
- Missing context: none — self-contained within `redact()` and its one call site in `scan_text()`.
- Two different credential classes both matching within the same sentence: `redact()` picks the first match in the existing pattern-priority order (same order as the current `sed` chain) and replaces the whole sentence with that one class's tag — the second class's own tag is not also appended. Not a leak (the whole sentence, including any second credential, is still fully replaced), just a naming choice; no test in this issue's acceptance criteria requires multi-class tagging.

### Interface contracts

- `redact()`'s contract changes from "stream filter: substitute each matched span in place, pass everything else through unchanged" to "detector: if ANY of the 8 patterns matches anywhere in the input, discard the entire input and emit exactly one fixed placeholder `[REDACTED:<class>]` for the first-matching class; otherwise pass the input through unchanged." Still reads all of stdin and writes to stdout, still called the same way (`printf '%s' "$sentence" | redact | normalize | cut -c1-80`) — no call-site change. This guarantee holds only within the candidate sentence `redact()` is given; it does not by itself protect a credential whose matched span crosses the `.`-based split that produces that candidate sentence. See the next point.
- **Added mid-review**: `scan_text()` gets a second, higher-level check with the same contract, run against the whole unsplit line before the `.`-based split: if ANY of the 8 patterns matches, the entire line is redacted as one unit and reported as a single `unregistered` hit, and the per-sentence loop (word-count minimum, register lookup) never runs on that line — deliberately: credential safety is not a claim-drafting concern, so a credential in an otherwise-approved/registered line's wording is still redacted and still reported (tested by `frag-registered`). `redact()` and this pre-check share one array (`CRED_PATTERNS`/`CRED_CLASSES` in `dossier-claim-scan.sh`) as their pattern source, so the two layers cannot drift apart the way the old fast-path/slow-path pair could (risk map row 3).
- **Consequence of the above, noted for the reviewer**: because the pre-check runs an unanchored match against the whole line and every candidate sentence is a substring of that line, `redact()`'s own redaction branch (its `CRED_UNION_PATTERN` match succeeding) is currently unreachable from its one call site — if the pre-check found nothing, no substring of the line can match either. `redact()` is kept anyway as a second, currently-dormant layer (documented as such in its own header comment) rather than removed, matching this file's existing fail-toward-redaction stance for the `[REDACTED:unknown]` fallback: it is what protects a credential if `scan_text()` ever gains a second call path to `redact()` that bypasses the pre-check.
- The 8 placeholder tags (`anthropic-key`, `github-token`, `aws-access-key`, `slack-token`, `bearer-token`, `connection-string`, `secret-assignment`, `private-key-block`) and their exact regex patterns are unchanged — only what happens to the surrounding sentence (or, for the new pre-check, the surrounding line) on a match changes.
- Performance: a fast-path single combined-alternation `grep -qE` (the union of all 8 patterns) runs first; the 8 individual checks (to identify which class) only run when that combined check already matched. The common case (no credential in the sentence) still costs one process fork, matching the current single-`sed`-invocation cost class rather than paying for 8 forks per sentence unconditionally. The new pre-check adds one more such fork per *line* (not per sentence) in `scan_text()`, on the same cost-class reasoning.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Interrupted token, per class | The fix only closes the specific `\|`-interruption shape from the issue's reproduction, not the general "any out-of-class character" case, or only fixes some of the 8 classes | Fixture: one interrupted-token sentence per credential class (8 total), each broken by a *different* non-token character (`\|`, comma, space, newline-equivalent) → excerpt contains neither the pre-break nor the post-break fragment, only the class tag |
| Multi-match sentence | A sentence containing two different credential-shaped substrings only gets the first one silently discarded, leaking the second in the clear | Fixture: one sentence containing both an AWS key and a Slack token → excerpt contains neither raw value, only a `[REDACTED:...]` tag (whichever class matched first) |
| Fast-path/slow-path pattern drift | The fast-path combined-alternation regex and the 8 individual slow-path patterns are maintained as two separate copies and drift apart, so a class matches individually but not in the combined check (or vice versa) — the "unreachable" fallback becomes reachable | Fixture: every one of the 8 individual patterns' matching input also trips the combined fast-path check (i.e., the fast path never wrongly takes the pass-through branch for a real credential) |
| Non-credential sentence, unaffected | The rewrite accidentally starts flagging/discarding ordinary prose that merely resembles one of the 8 patterns loosely, or stops passing through genuinely clean sentences unchanged | Fixture: a sentence with no credential-shaped substring → output is byte-identical to the input (pass-through still works) |
| Credential span crossing the `.`-based split | A credential whose matched span (or, for connection-string, its adjacent context) contains a literal `.` — a JWT's two internal periods (`bearer-token`'s charset explicitly permits `.`), a connection string's dotted hostname between scheme and `@` — has part of itself on each side of `scan_text()`'s pre-existing `tr '.' '\n'` split; `redact()` only ever sees one post-split fragment at a time, so it discards the fragment it's given but cannot reassemble the whole line to see the credential the split broke apart, and the fragment without the class-identifying prefix (e.g. a JWT's payload/signature segments, which lose the leading `Bearer `) passes through unredacted. Found independently by both self-review agents (SEC-1, F1), not anticipated at spec time — see the revised non-goal above. | Fixture: a JWT-shaped bearer token (`Bearer eyJ....eyJ....SflK...`, two literal periods) → no segment (header, payload, or signature) reaches the excerpt, only the class tag. Fixture: `frag-conn`'s two connection-string occurrences separated by a dotted hostname → neither password (matched or corrupted) reaches the excerpt, including its lowercased form. Both closed by `scan_text()` checking the whole unsplit line against `CRED_PATTERNS` before the split runs, redacting the whole line as one unit on a match. |
| Exact-format pattern, lone interrupted occurrence (found in round 2 review) | `aws-access-key`, `private-key-block`, and `connection-string` are exact-format (a fixed `{16}` count, a literal multi-char suffix, or a required trailing `@`), not an open-ended character class — unlike the other 5 classes, a SINGLE interrupting character anywhere inside an otherwise-exact, UNPAIRED occurrence (no valid partner on the same line) makes the whole pattern fail to match, so neither the union fast-path nor `cred_match_class` ever fires: not a fragment leak, a full non-detection, with the raw value printed verbatim and `LEAKS=0`/exit 1 instead of exit 2. Found independently by both self-review agents (code-reviewer's F1, live-reproduced by both reviewers and by the implementer). Product decision (user-confirmed via AskUserQuestion): fix `aws-access-key` and `private-key-block` now — both rewritten to tolerate exactly one interrupting character (space, `\|`, or `,`) after any position while still requiring the same number of real characters, verified with no false-positive found. `connection-string` is deliberately NOT fixed here — the equivalent loosening of its password charset creates a real false positive (a bare scheme mention with no credential at all, e.g. `postgres://db:5432/app, ops@corp`, would wrongly match) — tracked as issue #210 instead. **Refined in round 3**: the first draft of both rewritten patterns only tolerated the interrupt BETWEEN body characters, missing the anchor/body boundary (right after the literal `AKIA` prefix) and, for `private-key-block`, the boundary before the trailing dashes and the armor-type region between `BEGIN` and `PRIVATE` — found live by security-reviewer re-testing the fix's own stated scope ("after any position") rather than trusting the round-2 fixtures, which happened not to cover a boundary position. Both patterns now tolerate the interrupt at every position, boundaries included. **Refined again, same round**: the mandatory space between "PRIVATE" and "KEY" only had an interrupter slot after it, not before — a fourth boundary, found by code-reviewer re-testing after the first three landed. Fixed by making that tolerance symmetric around the mandatory separator. Also found: every lone-occurrence fixture used only space or comma, never `|` — narrowing either pattern's interrupter class to drop `|` support left the suite green, so a regression could have shipped undetected. Both closed in the same commit. | Fixture: a LONE, unpaired, space-interrupted `AKIA...` key (`frag-aws-lone`) and a lone interrupted PEM header (`frag-pem-lone`) → both exit 2 (leakage, not just a registration gap) and no fragment reaches the excerpt. Boundary-position fixtures: `frag-aws-lone-prefix`, `frag-pem-lone-tail`, `frag-pem-lone-armor`, `frag-pem-lone-wordgap` → all exit 2, no fragment. Pipe-interrupter fixtures: `frag-aws-lone-pipe`, `frag-pem-lone-pipe` → same. `frag-conn` (paired-occurrence case) continues to pass; the lone-occurrence connection-string case is explicitly NOT covered by a passing fixture in this PR — see #210. |
| Severity/exit-code drift between `scan_class` (section A) and `CRED_PATTERNS` (found in round 2 review) | Section A's `scan_class` calls are a third, hand-maintained copy of the credential patterns (by necessity — they run before `CRED_PATTERNS` exists in load order, and never print a matched value so don't share its redaction contract) that can silently drift from `CRED_PATTERNS`: a credential `scan_text()`'s pre-check correctly redacts in the excerpt can still fail to increment `LEAKS`, so the scan exits 1 (registration gap) instead of 2 (leakage) for an actual credential. Found independently by both self-review agents (security-reviewer's SEC-1, code-reviewer's F2): `scan_class`'s `bearer-token` pattern was case-sensitive-only (`Bearer`) while `CRED_PATTERNS`' was not (`Bearer\|bearer`). Fixed by making `scan_class`'s `bearer-token`, `aws-access-key`, and `private-key-block` patterns text-identical to their `CRED_PATTERNS` counterparts (kept as separate literals, not a shared array — see the header comment above `CRED_CLASSES` in `dossier-claim-scan.sh` for why iterating one array from both places is a bigger change than this issue's scope). | Fixture: a lowercase-only `bearer TOKEN...` credential (`frag-bearer-lowercase-leak`) → exit 2, not 1. |

<!-- auto-log: 2026-09-15 13:03 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 13:07 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 13:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 13:12 commit "fix(dossier): claim-scan's redact() discards the whole sentence on a match" -->

<!-- auto-log: 2026-09-15 13:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 13:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 13:21 commit "fix(dossier): claim-scan's redact() discards the whole sentence on a match" -->

<!-- auto-log: 2026-09-15 14:15 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_redact_tr_split_fragment_leak.md -->

<!-- auto-log: 2026-09-15 14:15 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-15 14:23 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_dossier_claim_scan_scope_gaps.md -->

<!-- auto-log: 2026-09-15 14:23 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-15 14:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 14:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 14:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 14:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 15:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 15:27 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 15:27 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 15:27 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 15:28 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 15:28 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-198.goal.yaml -->

<!-- auto-log: 2026-09-15 15:28 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-198.goal.yaml -->

<!-- auto-log: 2026-09-15 15:29 commit "fix(dossier): close credential-fragment leak across scan_text's sentence split" -->

<!-- auto-log: 2026-09-15 15:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 15:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 15:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 15:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 15:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 15:38 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 15:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 15:40 commit "fix(dossier): restore -- guard lost in the redact() pattern-array refactor" -->

<!-- auto-log: 2026-09-15 15:52 Write /Users/danielbentes/.claude-work/projects/-Users-danielbentes-synapti-marketplace/memory/project_issue_queue_reorder_207_release.md -->

<!-- auto-log: 2026-09-15 15:54 commit "fix(dossier): restore -- guard lost in the redact() pattern-array refactor" -->

<!-- auto-log: 2026-09-15 15:58 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_redact_tr_split_fragment_leak.md -->

<!-- auto-log: 2026-09-15 15:59 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_dossier_claim_scan_scope_gaps.md -->

<!-- auto-log: 2026-09-15 15:59 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_redact_tr_split_fragment_leak.md -->

<!-- auto-log: 2026-09-15 15:59 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_bearer_pattern_third_copy_drift.md -->

<!-- auto-log: 2026-09-15 15:59 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-15 16:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 16:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 16:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 16:22 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 16:23 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 16:23 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-198.goal.yaml -->

<!-- auto-log: 2026-09-15 16:24 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-198.goal.yaml -->

<!-- auto-log: 2026-09-15 16:25 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 16:26 commit "fix(dossier): close AWS-key and PEM-header exact-format detection gap" -->

<!-- auto-log: 2026-09-15 16:37 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_bearer_pattern_third_copy_drift.md -->

<!-- auto-log: 2026-09-15 16:38 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_boundary_position_gap_akia_pem.md -->

<!-- auto-log: 2026-09-15 16:38 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-15 16:40 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:41 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 16:41 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 16:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 16:45 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 16:46 commit "fix(dossier): tolerate an interrupt at the AKIA/PEM anchor boundaries too" -->

<!-- auto-log: 2026-09-15 16:47 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_dossier_claim_scan_scope_gaps.md -->

<!-- auto-log: 2026-09-15 16:47 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_dossier_claim_scan_scope_gaps.md -->

<!-- auto-log: 2026-09-15 17:05 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 17:07 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/disclosure-gate.test.sh -->

<!-- auto-log: 2026-09-15 17:18 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->

<!-- auto-log: 2026-09-15 17:18 commit "fix(dossier): tolerate an interrupt before the PRIVATE/KEY space too" -->

<!-- auto-log: 2026-09-15 17:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-claim-scan.sh -->

<!-- auto-log: 2026-09-15 17:25 commit "docs(dossier): fix stale literal-pattern reference in scan_text's comment" -->

<!-- auto-log: 2026-09-15 17:28 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-198.md -->
