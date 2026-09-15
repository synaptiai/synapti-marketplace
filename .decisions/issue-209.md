---
issue: 209
title: 'fix(dossier): pipefail/SIGPIPE race in package-check-findings.test.sh''s expect_code()'
branch: fix/issue-209-pipefail-sigpipe-race
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T00:00:00Z'
created: '2026-09-15T00:00:00Z'
---
# Issue #209 — pipefail/SIGPIPE race in package-check-findings.test.sh's expect_code()

## Specification

_No flow skills are registered in this repo; this journal was written by hand
following an earlier entry's front-matter/section shape (see issue-176.md)._

`plugins/dossier/tests/package-check-findings.test.sh` runs under
`plugins/dossier/tests/run.sh`'s `set -uo pipefail`. Two call sites pipe a
captured variable through `printf '%s' "$VAR" | grep -q "..."`. When `grep -q`
matches, it exits immediately and closes its end of the pipe; `printf` can
then be killed by SIGPIPE (exit 141) before finishing its write, and under
`pipefail` the pipeline's exit status becomes non-zero even though `grep`
itself matched. `assert.sh`'s `assert_match` already documents and fixes this
exact shape with a here-string (`grep -qE "$pattern" <<<"$actual"`), which has
no pipeline for SIGPIPE to corrupt. The fix here is the same substitution at
the two remaining call sites.

### Non-goals

- Not touching `assert_match` itself — it is already the reference-correct
  pattern this fix copies.
- Not converting every `producer | grep -q` shape in `plugins/dossier/tests/`.
  The mandated sweep (`grep -rn "printf.*| grep -q"` across
  `plugins/dossier/tests/*.test.sh`) turned up roughly two dozen further
  instances of the identical `printf '%s' "$VAR" | grep -q ...` shape across
  nine other files (`bin-scripts.test.sh`, `config-schema.test.sh`,
  `ledger-lint.test.sh`, `package-contract.test.sh`, `prose-lint.test.sh`,
  `references-integrity.test.sh`, `rotation-check.test.sh`,
  `staleness-check.test.sh`, `workflow-template.test.sh`), all under the same
  `set -uo pipefail` runner and theoretically exposed to the same race. None
  of them has an empirically observed failure (the issue's reproduction was
  specific to this file), and each would need its own read-in-full and its
  own stress-test verification pass to convert responsibly — that is a
  larger, separately-scoped cleanup, not a drive-by mechanical rewrite bundled
  into a two-call-site bugfix. Flagged here and in the PR description as a
  follow-up rather than silently expanded scope.
- Not changing `dossier-package-check.sh` itself or any finding-code
  semantics — this is a test-harness-only fix.
- Not adding `-e` to the test runner's `set` flags, or otherwise changing
  `run.sh`'s error-handling model.

### Failure modes

- **Race reproduction** — governed by pipe-buffer fill speed vs. `grep`'s
  early exit; only surfaces under CPU contention. The fix removes the
  pipeline entirely (here-string), so there is no longer a producer process
  that can receive SIGPIPE from an early-exiting `grep -q` — closing the race
  by construction, not by making it merely less likely.
- **Behavioral drift from the rewrite** — a here-string appends a trailing
  newline that `printf '%s'` does not. This cannot change either call site's
  outcome: `grep` matches per-line regardless of a trailing newline, and
  neither pattern (`"FINDING $1"`, `"LEAKED-FIELD.*'$FIELD'"`) anchors on
  end-of-string with `$`, so the extra newline is inert here.
- **Unbound variable under `set -u`** — `$CK_OUT` is always assigned by
  `check()` before either call site runs, so the here-string substitution
  introduces no new unbound-variable risk.

### Interface contracts

- `expect_code()`'s external contract (arguments, PASS/FAIL emission via
  `_dossier_assert_pass`/`_dossier_assert_fail`, `CK_RC` exit-code check) is
  unchanged — only the internal match mechanism changes from a pipe to a
  here-string.
- The inline `LEAKED-FIELD` check's PASS/FAIL behavior and message text are
  unchanged.
- No change to `dossier-package-check.sh`'s CLI, exit codes, or finding-code
  output shape.

### Verification note

The issue's AC asked for 10+ back-to-back runs under artificial CPU load
(e.g. concurrent `yes > /dev/null`). That was started and reached 7 clean
runs (0 Broken pipe, 0 FAIL) under real contention (load average 8-12 on a
4-core box) before being stopped: this worktree runs inside a shared
environment where other agents run concurrently, and sustained heavy
artificial load risked starving that shared environment rather than just
this test. Verification was completed instead with 3 plain (unloaded)
back-to-back runs — all 33/33 PASS, 0 FAIL, 0 Broken pipe — combined with
the structural argument that a here-string has no pipeline for SIGPIPE to
corrupt, so the fix closes the race by construction rather than by making
it statistically less likely to reproduce.
