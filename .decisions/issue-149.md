---
issue: 149
created: '2026-08-03T10:03:20Z'
---
# Issue #149 — mktemp-dir guard: exit-code check reopens the `cd ""` corruption risk

**Title**: dossier tests: local-merge-hook.test.sh doesn't check `_dossier_safe_mktemp_dir`'s exit code, reopening the `cd ""` corruption risk the helper was hardened against
**Labels**: bug, plugin

## Specification

### Non-goals

- Not touching the two real, already-corrected corruption incidents from earlier this session (stray local branches, misattributed commit authors) — those are already repaired; this issue is about closing the mechanism that caused them, not re-litigating the incident.
- Not changing `_dossier_safe_mktemp_dir`'s own internal behavior (its `exit 2`-on-failure contract is correct and intentional) — the fix is entirely at the call-site layer.

### Failure modes

- **Partial failures** — `_dossier_safe_mktemp_dir` hitting any of its internal `exit 2` paths (unset `RUN_TMPDIR`, failed `mktemp -d`, unusable returned path) inside a bare `VAR=$(...)` call site only kills the command-substitution subshell; the caller proceeds with `VAR=""`, and `cd ""` returns 0 in bash — a silent no-op, not an abort.
- **Scale of the gap** — a repo-wide audit (Python scan of every `plugins/dossier/tests/*.test.sh`) found 108 more unguarded call sites across 8 additional files beyond `local-merge-hook.test.sh`, none with any existing exit-code or emptiness guard. All converted in this PR, not just the two the issue named.

### Interface contracts

- New helper `_dossier_require_mktemp_dir <varname> <prefix>` in `plugins/dossier/tests/lib/assert.sh` — captures `_dossier_safe_mktemp_dir`'s output, checks `|| exit 2` AND emptiness/directory-existence, then assigns into the caller's named variable via `printf -v`. Implemented as a plain function call (never itself wrapped in `$(...)`), so an internal `exit 2` propagates through the caller's real shell instead of being swallowed by another subshell layer.

## Acceptance Criteria (as validated)

1. `local-merge-hook.test.sh`'s two call sites (`FLOWLESS_ROOT`, `REPO`) use the guarded helper. Verification: `bash plugins/dossier/tests/run.sh local-merge-hook.test.sh`
2. The same unguarded pattern is fixed everywhere else it appears in `plugins/dossier/tests/*.test.sh`. Verification: repo-wide audit script (0 remaining unguarded call sites) + `bash plugins/dossier/tests/run.sh`
3. A regression test proves the exact corruption mechanism (git init/config/checkout running against a real-looking directory instead of aborting) is closed, not just that the helper exists. Verification: `bash plugins/dossier/tests/run.sh mktemp-guard.test.sh`
4. The full dossier test suite passes. Verification: `bash plugins/dossier/tests/run.sh`

## Stranger Test

PASS — 3 tasks reviewed. Task "add guarded helper" specifies the exact function signature, its two internal guards, and the printf -v assignment mechanism. Task "fix local-merge-hook.test.sh" names the exact two call sites (file:line) and the exact verification command. Task "repo-wide conversion" specifies the exact audit method (Python scan, zero pre-existing guards confirmed) and the two conversion shapes (simple swap; two-line split for the 7 path-suffix sites in rotation-check.test.sh).

## Verification

- Full suite: `bash plugins/dossier/tests/run.sh` — 1844/1844 (up from 1798 pre-change)
- `shellcheck -S warning -x plugins/dossier/tests/*.sh` (exact CI invocation) — clean, exit 0
- `bash -n` on every modified file — clean
- Regression test (`mktemp-guard.test.sh` scenario 3) reproduced RED against the pre-fix `local-merge-hook.test.sh` (confirmed a `.git` directory materializes in an isolated scratch fixture when the guard doesn't fire), then confirmed GREEN after the fix
- Repo-wide audit: 0 remaining `VAR=$(_dossier_safe_mktemp_dir ...)` call sites without a guard (116 total call sites found; 116 now guarded)

<!-- auto-log: 2026-08-03 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-149.md -->

<!-- auto-log: 2026-08-03 12:21 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-149.md -->

<!-- auto-log: 2026-08-03 12:32 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_dossier_mktemp_guard_wrapper_composition_gap.md -->

<!-- auto-log: 2026-08-03 12:32 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-08-03 12:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/mktemp-guard.test.sh -->

<!-- auto-log: 2026-08-03 12:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 12:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 12:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-08-03 12:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-08-03 12:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/lib/assert.sh -->

<!-- auto-log: 2026-08-03 12:39 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/lib/assert.sh -->
