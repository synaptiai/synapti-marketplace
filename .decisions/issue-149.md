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

## Second-order finding (PR #150 review, fix-forwarded before merge)

The first-pass fix (direct call-site conversion) left one gap: `setup_fixture()`/`no_gh_path()` in `rotation-check.test.sh` and `setup_fixture()` in `staleness-trigger.test.sh` called the new guard correctly *internally*, but were themselves invoked via `$(...)` at ~24 call sites — reopening the exact swallowed-exit bug one level up, since command substitution forks a subshell around the whole function body too. Found independently by three `/flow:pr` review agents (error-handling, security, code-quality) from three different angles. Fixed by converting both functions to the same out-parameter convention as the guard itself (`printf -v` into a caller-named variable, called as a plain statement), updating every call site, and hardening the guard's own final `printf -v` line to match. A repo-wide re-audit (every `$(...)`-invoked function name cross-checked against every function body containing the guard, across all 10 test files) confirmed zero remaining instances of this pattern.

A reviewer's suggested prerequisite (`local _dir` in `_dossier_safe_mktemp_dir`, to prevent a claimed loop-variable clobber in `no_gh_path`) was investigated and empirically disproven at the time — the guard's own internal `$(_dossier_safe_mktemp_dir ...)` call already forks its own subshell, which isolates `_dir` regardless of whether the outer helper is itself wrapped in `$(...)`. Not applied in that round. It was independently re-raised by two more reviewers during `/flow:review` (see below) with a different framing — not "this is a live bug" (it isn't, under the current call graph) but "the file's own docstring actively directs future contributors toward a refactor that would make it live" — and applied in round 3 as cheap proactive hardening, not a live-bug fix. Both framings are consistent; the decision changed because the second framing is the stronger argument for a one-word, zero-behavior-change addition.

Also checked: converting `setup_fixture`/`no_gh_path` from subshell-isolated to plain-statement execution means their previously-unscoped internal variables (`_bare`, `_clone`, `_out`, `_dir`, `_entry`, `_base`, `OLD_IFS`) now persist in the caller's real shell instead of dying with a subshell. Grepped for reads of all seven names outside their three defining functions (`no_gh_path`, `setup_fixture`, `push_docs_branch_commit`) in `rotation-check.test.sh` — zero external reads found, so the newly-persistent globals were inert either way — but `local`-scoped them anyway in round 3 (below) for consistency with `staleness-trigger.test.sh`'s sibling `setup_fixture`, which already scoped everything correctly.

## Third-order findings (`/flow:review` on PR #150, fix-forwarded before merge)

The Path A paired-reviewer round (10 agents, 5 facets × skeptic/verifier) re-reviewed the full PR at its round-2 HEAD and converged, across 4 independent reviewers, on:

1. **`no_gh_path`/`setup_fixture` (rotation-check.test.sh) internal variables should be `local`** — applied (`OLD_IFS _out _dir _entry _base` in `no_gh_path`; `_bare _clone` in `setup_fixture`), matching `staleness-trigger.test.sh`'s already-correct sibling.
2. **The wrapper functions' own final `printf -v` (the out-parameter handoff `no_gh_path`/`setup_fixture` introduced in round 2) was itself unguarded** — the exact ERR-3/SEC-2 class fixed in `_dossier_require_mktemp_dir` in round 2 had been reintroduced one level up, in new code from round 2 itself. Fixed by extracting a shared `_dossier_assign_outvar <varname> <value>` helper (guarded `printf -v`, matching the FATAL+exit-2 pattern) and having both `_dossier_require_mktemp_dir` and all three wrapper functions delegate to it — DRY, so the guard can't be dropped on a future copy-paste of the out-parameter pattern.
3. **No durable, CI-enforced guard against a future helper reintroducing this exact class** — `mktemp-guard.test.sh` scenario 4 only regression-tested the *pattern* generically via synthetic stand-ins, not the real files. Fixed by adding scenario 6: a static lint (pure awk/grep, no python dependency) that scans every `plugins/dossier/tests/*.test.sh` file for any function that calls the guard internally and is also invoked via `$(...)`/backticks anywhere in that file — verified it correctly flags a deliberately-introduced violation before trusting it as a regression guard.
4. **`local _dir` in `_dossier_safe_mktemp_dir`** — re-raised (see above), applied.
5. Scenario 3's `.git`-absence assertion was found to be proven vacuously (`local-merge-hook.test.sh` has two guarded call sites; the first always aborts before the second, behind which the actual `git init` sits, is ever reached) — relabeled the assertions to accurately describe what's proven (the first guard's abort) rather than implying the second guard was independently isolated.

## Verification

- Full suite: `bash plugins/dossier/tests/run.sh` — 1852/1852 (1798 pre-change → 1844 after round 1 → 1848 after round 2 → 1852 after round 3's new scenarios 5 and 6)
- `shellcheck -S warning -x plugins/dossier/tests/*.sh` (exact CI invocation) — clean, exit 0
- `bash -n` on every modified file — clean
- Regression test (`mktemp-guard.test.sh` scenario 3) reproduced RED against the pre-fix `local-merge-hook.test.sh` (confirmed a `.git` directory materializes in an isolated scratch fixture when the guard doesn't fire), then confirmed GREEN after the fix
- Regression test (`mktemp-guard.test.sh` scenario 4) regression-tests the second-order pattern generically (stdout-returning wrapper vs. out-parameter wrapper), independent of any specific file
- Regression test (`mktemp-guard.test.sh` scenario 5) proves `_dossier_assign_outvar` itself hard-aborts on an invalid target identifier, rather than letting a bare `printf -v` fail silently
- Static lint (`mktemp-guard.test.sh` scenario 6) proves, and will keep proving on every future run, that no `*.test.sh` file defines a guard-consuming function that's also invoked via `$(...)`/backticks — verified it actually catches a deliberately-introduced violation before trusting it
- Repo-wide audit: 0 remaining `VAR=$(_dossier_safe_mktemp_dir ...)` direct call sites without a guard (116 total direct call sites found; 116 guarded)
- Repo-wide re-audit (second-order): 0 remaining functions that call the guard internally and are invoked via `$(...)` by their own callers (now continuously enforced by scenario 6, not just a one-time audit)
- CI on PR #150: 4/4 checks green (`test`, `CodeQL`, `Analyze (actions)`, `Analyze (python)`), independently re-checked via `gh pr checks` per this project's own memory of prior local-green/CI-red divergence on this exact plugin

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

<!-- auto-log: 2026-08-03 12:41 commit "fix(dossier): close second-order guard-swallow in setup_fixture/no_gh_path" -->

<!-- auto-log: 2026-08-03 12:42 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr149-body.md -->

<!-- auto-log: 2026-08-03 12:46 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-149.md -->

<!-- auto-log: 2026-08-03 12:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/lib/assert.sh -->

<!-- auto-log: 2026-08-03 12:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 12:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 12:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/staleness-trigger.test.sh -->

<!-- auto-log: 2026-08-03 12:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/mktemp-guard.test.sh -->

<!-- auto-log: 2026-08-03 12:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 12:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 12:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/mktemp-guard.test.sh -->

<!-- auto-log: 2026-08-03 12:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/mktemp-guard.test.sh -->

<!-- auto-log: 2026-08-03 13:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/lib/assert.sh -->

<!-- auto-log: 2026-08-03 13:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/mktemp-guard.test.sh -->

<!-- auto-log: 2026-08-03 13:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/mktemp-guard.test.sh -->

<!-- auto-log: 2026-08-03 13:12 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-149.md -->
