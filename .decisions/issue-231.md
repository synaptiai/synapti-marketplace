---
issue: 231
title: "block-unregistered-claim.sh's credential patterns drifted from dossier-claim-scan.sh (never synced with #198/#210)"
branch: fix/issue-231-block-unregistered-claim-pattern-drift
created: '2026-09-16T08:00:00Z'
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-16T08:00:00Z'
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
---
# Issue #231 — block-unregistered-claim.sh credential-pattern drift

_Captured manually (no flow skills registered in this repo) on 2026-09-16, following the same manual-orchestrator pattern used for issues #101, #199-221, etc._

## Specification

### Non-goals

- Do NOT change any of the other five credential classes (`anthropic-key`, `github-token`, `slack-token`, `secret-assignment`) — they were never touched by #198/#210 and are not drifted.
- Do NOT change the non-credential checks in this hook (`internal-register-id`, `internal-path`, `internal-hostname`, `private-ip`) — out of scope for this issue.
- Do NOT change `dossier-claim-scan.sh` itself — it is the source of truth here; this issue brings the hook back into sync with it, not the other way around.
- Do NOT re-derive the interrupt-tolerant patterns from scratch. Copy them verbatim from `CRED_PATTERNS` so there is exactly one place the tolerance technique is designed and reviewed.

### Failure modes

- **Silent leading-dash option parsing** — `private-key-block`'s fixed pattern starts with a literal `-----`. The hook's `check()` helper called `grep -qE "$2"` without `--`, so once the pattern gains its `-----` prefix, `grep` would parse it as an (unrecognized) option, exit 2, and `check()`'s `if grep -qE ...; then` would read that as "no match" — silently disabling private-key-block detection entirely, the opposite of the fix's intent. Mitigation: added `--` to the `grep -qE` call, mirroring `dossier-claim-scan.sh`'s own `cred_match_class()`, which documents the identical hazard.
- **Pattern re-derivation drift** — hand-writing a "similar" interrupt-tolerant pattern instead of copying `CRED_PATTERNS` verbatim risks a subtly different regex that passes ad-hoc testing but diverges from the scanner's on an edge case, recreating the exact "two paths disagree" bug class this issue exists to close. Mitigation: copied the three regex strings character-for-character from `dossier-claim-scan.sh`, and added a mechanical regression test (`grep -qF` on the literal pattern string) asserting both files contain the identical string, not just that both implement "a" version of the class.
- **False-positive regression** — the connection-string bound is deliberately narrow (tolerates exactly one interrupting character, not two-or-more) specifically to avoid flagging a bare scheme mention with no credential (`postgres://db:5432/app, ops@corp`, a comma+space pair). Copying the pattern verbatim (rather than loosening it further) preserves this guard; a dedicated test reproduces the false-positive case directly against the hook.
- **Missed sibling drift (bearer-token)** — while comparing the two files pattern-by-pattern, found `bearer-token` was also drifted (case-sensitive-only in the hook, `(Bearer|bearer)` in the scanner) — the exact case the scanner's own header comment cites as "a real bug found in review." Fixed in the same pass since it's the identical defect class and touches the same lines; not filed as a separate issue.

### Interface contracts

- `check()`'s signature (`check <class-name> <ERE-pattern>`) is unchanged — only the `grep` invocation inside it gains `--`, and only three (four, including bearer-token) of the `check` call sites' pattern arguments change.
- The hook's exit-code contract (0 = permit, 2 = block) is unchanged; these are detection-pattern fixes, not behavior-shape changes.
- `HITS`, the block message, and the "matched value never echoed" guarantee are all unchanged — only which content triggers a match.

## Fix

Copied `aws-access-key`, `private-key-block`, `connection-string`, and `bearer-token` verbatim from `dossier-claim-scan.sh`'s `CRED_PATTERNS` array into `block-unregistered-claim.sh`'s `check` calls. Added `--` to `check()`'s `grep -qE` invocation (required once `private-key-block` carries its `-----` prefix).

**Noted in passing, not a regression**: the old hook pattern (`BEGIN [A-Z ]*PRIVATE KEY`, no armor-dash anchors) would technically match bare prose mentioning "BEGIN ... PRIVATE KEY" with no real PEM armor around it — broader, and more false-positive-prone, than the scanner's own anchored `-----BEGIN...-----` pattern. The synced version requires the full armor, which every real PEM block always has; this is a strict correctness improvement (removes a theoretical false-positive class, adds no false negative for real keys), not a narrowing of real detection coverage. Already reasoned through and shipped in #198 for the scanner side; this brings the hook to the same, already-reviewed shape.

## Testing

- New tests in `plugins/dossier/tests/hooks.test.sh`:
  - Interrupted AWS key (`AKIAIOSFOD NN7EXAMPLE`) → blocked (exit 2), class named, fragment never echoed.
  - Interrupted PEM header (`-----BEGIN RSA PRIVATE KEY,-----`) → blocked (exit 2), class named.
  - Interrupted connection-string password (`Sup3rSecret Pass@dbhost`) → blocked (exit 2), class named, fragment never echoed.
  - The false-positive guard (`postgres://db:5432/app, ops@corp`) → NOT blocked (exit 0).
  - A mechanical drift guard: for each of the three synced classes, asserts the *exact* regex string appears verbatim in both `block-unregistered-claim.sh` and `dossier-claim-scan.sh` (parallel bash arrays, not a delimited string — the patterns themselves contain literal `|` characters that would corrupt a single-character-delimited split).
- `bash plugins/dossier/tests/run.sh hooks.test.sh`: 131 pass, 0 fail (was 108 pass before these additions; no existing assertion changed shape).
- `bash plugins/dossier/tests/run.sh` (full suite): 2205 pass, 5 fail — the same 2 pre-existing, unrelated failure files as every prior PR in this batch (`bin-scripts.test.sh`: chmod-as-root permission simulation doesn't bind when running as root; `rotation-check.test.sh`: `GIT_CONFIG_*`/auth-header environment assumptions), neither of which touches `block-unregistered-claim.sh` or credential patterns. No regressions.
- `shellcheck` not installable in this local sandbox (network-restricted, consistent with every prior PR in this batch); `bash -n` syntax check clean on both changed files. CI runs `shellcheck -S warning` on all changed scripts.
- Verified byte-for-byte, via direct `grep -F --` against both source files, that the three copied pattern strings are identical before writing the mechanical test assertion (not just eyeballing them).
