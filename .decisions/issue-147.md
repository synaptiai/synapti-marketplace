---
issue: 147
created: '2026-08-03T16:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-08-03T16:00:11Z'
  by: direct-interview
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: goal-created
  captured_at: '2026-08-03T16:00:11Z'
  goal_id: issue-147
  source: github_issue:147
- type: workflow-run
  captured_at: '2026-08-03T16:00:33Z'
  workflow: start-issue
  run_id: 2026-08-03T160000Z-issue-147
  status: active
- type: verdict
  captured_at: '2026-08-03T17:30:05Z'
  result: PASS
- type: goal-evaluation
  captured_at: '2026-08-03T17:30:22Z'
  goal_id: issue-147
  result: achieved
  evidence_bundle: verdict-judge-inline
  failures: none
- type: workflow-run
  captured_at: '2026-08-03T17:30:38Z'
  workflow: start-issue
  run_id: 2026-08-03T160000Z-issue-147
  status: completed
---
# Issue #147 — dossier-rotation-check.sh: git network calls are silently inert on private repos

**Title**: dossier: policy job's persist-credentials: false makes rotation-check (and any git network op) silently inert on private repos
**Labels**: bug, plugin

## Specification

_Captured directly from a pre-implementation interview with the user (three rounds, six
sub-decisions total), each grounded in direct codebase verification rather than the issue
body's claims alone. See below for what was verified._

### Non-goals

- Not changing `persist-credentials: false` on the `policy` job's checkout step, and not
  flipping it to `true` for the whole job. The fix is scoped to authenticating three specific
  git invocations inside `dossier-rotation-check.sh`, not broadening the job's credential
  footprint.
- Not using `gh auth setup-git` — confirmed during the interview that this would install a
  persistent git credential helper for the rest of that step's process, a broader footprint
  than the 2-3 calls that actually need authentication, and one that would need independent
  duplication at any future call site rather than being self-contained to this script.
- Not treating an empty/absent `GH_TOKEN` as a hard configuration error. The script must remain
  usable in contexts where `GH_TOKEN` is legitimately unset (local runs, a future caller that
  doesn't export it, public repos where it was never needed) — falling back to today's
  unauthenticated behavior, never regressing the working public-repo case.
- Not building new test infrastructure (an HTTP server, a git daemon) to exercise the
  authenticated request end-to-end. The existing `rotation-check.test.sh` harness uses a local
  filesystem bare-repo remote, against which an HTTP-only `extraheader` is inert (git ignores
  `http.*` config for non-HTTP transports) — verified this is harmless, not a blocker, and
  scoped testing to argv-inspection instead (see Interface contracts).

### Failure modes

- **Timeouts** — none — no new network call is introduced; the existing `git ls-remote`/
  `git fetch` calls are the same calls, now carrying an additional header when authenticated.
- **Partial failures** — none — the fix is confined to how the git commands are invoked
  (an added `-c` flag), not a multi-step operation that could partially complete.
- **Invalid input** — `GH_TOKEN` containing shell metacharacters must never be interpolated into
  a command string that reaches a shell (matching the script's existing documented principle,
  header line 15: "GH_TOKEN passed through to `gh`, never interpolated into a command"). **Note
  on the shipped shape**: the original plan below (a `-c http.extraheader=...` argv value) was
  superseded during self-review by `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0`
  environment variables instead (process-listing exposure, see Self-review fix-forward below) —
  the "never reaches a shell" property holds identically either way, since env vars set via the
  `VAR=val cmd` prefix form are not shell-interpolated any more than an argv entry is.
- **Missing context** — `GH_TOKEN` empty or absent: falls back to today's unauthenticated
  behavior (see Non-goals above) rather than failing loudly, since a public-repo caller that
  never needed a token must not regress.

### Interface contracts

- **Superseded during self-review** (final shipped shape — see below): `dossier-rotation-check.sh`'s
  `git_auth()` wrapper conditionally sets `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic base64(x-access-token:$GH_TOKEN)"` (not the `-c
  ...bearer...` form originally planned here) before every `git ls-remote --exit-code --heads
  origin "$DOCS_BRANCH"` (line 223) and `git fetch --no-tags [--prune] origin ...` call (lines
  267, 269), added only when `GH_TOKEN` is non-empty.
- No change to the script's `--github-output`/`--summary` output contract, its documented exit
  codes, or any of its 8 emitted fields (`would_rotate`/`reason`/`age_days`/`age_source`/
  `accumulated_files`/`accumulated_lines`/`docs_branch`/`rotation_policy`).
- No change to `dossier-docs-refresh.yml` — `GH_TOKEN: ${{ github.token }}` is already present
  in the "Check whether the documentation branch would rotate" step's `env:` block
  (confirmed: line 239), so no new wiring is needed there.
- Test additions land in `plugins/dossier/tests/rotation-check.test.sh`, using a PATH-stub `git`
  wrapper that logs its own argv to a file then execs the real `git` binary found via
  `command -v` before the stub is placed on `PATH` — preserving the existing bare-repo
  fixture's real git behavior while making the constructed command line assertable. Scoped
  narrowly: the stub sits ahead of real `git` on `PATH` only for the invocation of
  `dossier-rotation-check.sh` under test, not for the surrounding fixture-setup code (which
  needs real git to build the bare repo and push branches).
- The script's usage header (currently line 15: "GH_TOKEN passed through to `gh`, never
  interpolated into a command") is revised to state GH_TOKEN now also authenticates the
  script's own `git` network calls, not just `gh`.

## Decision on approach

Of the three options the issue itself named:

1. Authenticate via the existing `GH_TOKEN` — **selected**.
2. Better diagnostics only (name "private repo, no credentials" instead of a generic transport
   failure), leaving the feature permanently inert on private repos — rejected: doesn't fix the
   underlying gap, only its symptom.
3. Accept and document the limitation — rejected: leaves a real functional gap for exactly the
   private/proprietary codebases dossier's investor-grade documentation use case most likely
   targets.

Confirmed before deciding: `GH_TOKEN` is already threaded into the exact workflow step that
invokes this script, unused for git's own network calls (only used implicitly for the script's
existing `gh pr list` call, which already works correctly because `gh` auto-detects `GH_TOKEN`
from the environment). The `policy` job's declared permissions (`contents: read`,
`pull-requests: read`) are already minimal, so reusing that same token for read-only git
`ls-remote`/`fetch` introduces no privilege escalation.

## Self-review fix-forward

A self-review pass (Agent(code-reviewer)) on the initial implementation found 1 P1 and 2 P2
findings, all fixed before commit:

- **P1**: the script's `--help` flag prints `sed -n '2,24p' "$0"`, a range sized for the
  pre-diff header comment. This diff grew the `GH_TOKEN` doc line from 1 line to 5, pushing the
  `# Exit:` section past line 24 — `--help` silently dropped the exit-code documentation.
  Fixed: range corrected to `2,28p`, verified by running `--help` directly.
- **P2, security**: the original implementation passed the auth header via `git -c
  http.extraheader=...`, visible in process listings (`ps aux`, `/proc/<pid>/cmdline`) for the
  life of the subprocess — a real exposure `actions/checkout` itself deliberately avoids (it
  writes a placeholder via `-c`, then patches the real credential into the on-disk git config).
  Fixed: switched to `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` (git >= 2.31),
  scoped to the one subprocess via the `VAR=val cmd` prefix form, never exported globally.
- **P2, no live verification**: the reviewer correctly noted that `rotation-check.test.sh`'s
  fixture uses a local filesystem remote, against which `http.*` config is inert (git ignores it
  for non-HTTP transports) — so unit tests alone cannot prove the header format actually
  authenticates against real GitHub. See below: this manual verification caught a genuine bug
  the unit tests could not have found.
- **P3, defense-in-depth**: `GH_TOKEN` is untrusted input per this script's own header, but the
  original implementation embedded it into the header value with no control-character stripping,
  unlike `sanitize_md()`/`emit()` elsewhere in the same file. Fixed: stripped via the same `tr`
  idiom before use.

## Manual verification against a real private repo (P2 finding, caught a real bug)

Per the self-review's P2 finding, ran `git_auth`'s exact mechanism directly against a real
private repository (`danielbentes/epic`, read-only `git ls-remote`, non-mutating) before
considering this issue done — not the local bare-repo fixture, which cannot exercise HTTP auth
at all.

**Baseline** (no auth, credential helper disabled): `git -c credential.helper= ls-remote --heads
https://github.com/danielbentes/epic.git` → `fatal: could not read Username for
'https://github.com': Device not configured`, exit 128. Confirms no ambient credential on this
machine masks the test, and reproduces the original bug's exact symptom.

**First attempt — Bearer, matching the issue's own suggested syntax** (`AUTHORIZATION: bearer
$GH_TOKEN`, the exact format from the issue body's "Options to consider" section and the
original implementation): **REJECTED** — identical `fatal: could not read Username` failure as
the unauthenticated baseline. The issue's own suggested header format does not work with a
personal access token.

**Fix — Basic auth** (`AUTHORIZATION: basic base64(x-access-token:$GH_TOKEN)`, the same
credential shape `actions/checkout` constructs internally): **SUCCEEDED** — real branch refs
returned, exit 0. Reproduced twice for confidence. `git_auth()` was corrected to this format
before commit; the corrected version was re-verified against the same repo with the exact
production code path (not a manual replica), succeeding identically.

This means the original implementation (matching the issue's own suggested Bearer syntax) would
have shipped completely non-functional — the exact "looks fixed, still silently degrades to
age_source=unknown" failure mode this issue exists to close, just relocated one layer deeper.
Caught only because the self-review's P2 finding was taken seriously enough to verify against a
real private repo rather than accepting the local fixture's structural inability to test HTTP
auth as sufficient coverage.

**Residual limitation, accepted**: this verification used a personal access token
(`gh auth token`), not GitHub Actions' `github.token` (an ephemeral, differently-scoped
installation token) — the actual credential this script receives in production. Both are
documented to authenticate via the same `x-access-token` Basic-auth convention GitHub's git
servers accept, and this is the same mechanism `actions/checkout` itself uses for `github.token`
specifically, so there is no reason to expect divergent behavior — but this was not verified
against a live GitHub Actions run with a real `github.token`, since that token only exists for
the duration of an actual job. If a future CI run of `dossier-docs-refresh.yml` against a real
private repo shows a different result, that is the next signal to act on.

## Parallel review fix-forward (P1 + P2s, fixed before merge)

The `/flow:pr` review pass (5 agents: code-quality, convention, security, error-handling,
test-runner) converged on one confirmed P1 and several P2/P3 findings, all fixed:

- **P1 (code-reviewer, live-reproduced)**: `GIT_CONFIG_KEY_0=http.extraheader` was unscoped —
  it applies to every HTTPS request the `git` invocation makes, not just requests to `origin`.
  Verified live: an unscoped key sent the Basic-auth header to an unrelated third-party host
  (gitlab.com) when the script's origin was github.com. The security-reviewer initially
  dismissed a similar-sounding concern citing CVE-2020-11008 (git no longer resends
  `extraheader` across a mid-request host-changing redirect, fixed in git >= 2.26) — but that
  citation addresses a different threat model (redirect-following within one HTTP transaction),
  not static config-key scoping across separate git invocations, which is what the code-reviewer
  actually reproduced. Fixed: `git_auth()` now derives `origin`'s own scheme+host via
  `git remote get-url origin` and scopes the key to
  `http.<scheme>://<host>/.extraheader`, matching `actions/checkout`'s own narrower scoping (not
  just its header-value shape, which was already matched). Non-HTTP(S) origins (ssh://,
  `git@host:path`, `git://`) fall through unauthenticated entirely, since Basic-over-HTTP
  doesn't apply to those transports and there's no host to scope to. Re-verified against the
  real private repo with the exact corrected function (not a hand-written replica): still
  authenticates correctly against origin, and — new — confirmed the same credential no longer
  reaches an explicitly-targeted different host (gitlab.com) in the same test session.
- **P2 (error-handler-inspector)**: the base64-encoding pipeline's exit status was never
  checked; a broken/missing `base64` would silently produce an empty credential, sent as
  `AUTHORIZATION: basic ` — rejected by the remote, which is worse than no credential at all for
  a public repo. Fixed: falls through unauthenticated if the encoding pipeline produces an empty
  result.
- **P2 (error-handler-inspector)**: `GIT_CONFIG_COUNT=1` unconditionally claims the whole
  `GIT_CONFIG_*` namespace for the subprocess, silently overriding any ambient
  `GIT_CONFIG_COUNT`/`KEY_N`/`VALUE_N` a caller might have set (nothing in this repo does today
  — confirmed via grep — but noted as a latent gap). Documented explicitly in `git_auth()`'s own
  comment as an intentional exclusive claim, not fixed with speculative append-logic for a
  scenario with no current reachable caller.
- **P2 (docs, code-reviewer + security-reviewer, independently)**: `.flow/goals/issue-147.goal.yaml`
  still described the superseded `-c http.extraheader=...bearer...` design in AC1's text and
  `interface_contracts`, and AC3's verification command spuriously still passed against the
  shipped code (the substring `http.extraheader` survives incidentally as a config key-name
  fragment). Fixed: goal file text updated to describe the shipped mechanism.
- **P3 (security-reviewer + error-handler-inspector, independently)**: `_clean_token`/
  `_b64_creds` were plain global assignments, not `local`, unnecessarily widening the
  credential's exposure window in the shell's namespace after `git_auth` returns. Fixed: added
  `local`.
- **P3 (security-reviewer)**: `git_auth()`'s docstring didn't state the caller contract that
  makes its own credential-transform safe (every call site must redirect stdout+stderr, since
  the base64-transformed credential is not GitHub's literal secret string and Actions' log
  masking would not catch it). Fixed: added to the docstring.
- **P3 (error-handler-inspector)**: the transport-failure `note()` text at both sites didn't
  record whether `GH_TOKEN` was set, so an operator couldn't distinguish "no token, private
  repo, expected" from "token set and rejected." Fixed: both notes now include `GH_TOKEN set:
  yes/no`.
- **P2 (convention-checker, test-integrity)**: scenario 22's `DIRTY_TOKEN` was built as
  `"...$(printf '\r\n')"` — a `$(...)` substitution strips all of its own trailing newlines
  regardless of where the result is later concatenated, so the token only ever carried a
  trailing `\r`, never a surviving embedded `\n`, contradicting the test's own comment and the
  commit message that introduced it. Fixed: rebuilt via ANSI-C quoting (`$'...\r\n...'`), which
  embeds real control characters with no such stripping.

Test suite grew from 93 to 96 assertions (new scenario 21C: non-HTTP(S) origin falls through
unauthenticated; two new scoping assertions in 21A). Final: `bash plugins/dossier/tests/run.sh
rotation-check.test.sh` — 96/96. `shellcheck -S warning -x` — clean.

<!-- auto-log: 2026-08-03 17:58 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-147.md -->

<!-- auto-log: 2026-08-03 17:58 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-147.goal.yaml -->

<!-- auto-log: 2026-08-03 17:59 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-147.goal.yaml -->

<!-- auto-log: 2026-08-03 17:59 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-147-lifecycle-active.yaml -->

<!-- auto-log: 2026-08-03 18:00 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-147-lifecycle-active.yaml -->

<!-- auto-log: 2026-08-03 18:00 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-08-03T160000Z-issue-147/run.yaml -->

<!-- auto-log: 2026-08-03 18:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:04 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:04 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:06 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:11 commit "fix(dossier): authenticate rotation-check's git network calls via GH_TOKEN" -->

<!-- auto-log: 2026-08-03 18:28 commit "fix(dossier): authenticate rotation-check's git network calls via GH_TOKEN" -->

<!-- auto-log: 2026-08-03 18:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:31 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 18:33 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 18:36 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-147.md -->

<!-- auto-log: 2026-08-03 18:39 commit "fix(dossier): self-review fix-forward on rotation-check's git_auth" -->

<!-- auto-log: 2026-08-03 18:39 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-147.md -->

<!-- auto-log: 2026-08-03 18:39 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-147.md -->

<!-- auto-log: 2026-08-03 19:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 19:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 19:20 commit "test(dossier): cover git_auth's control-character stripping and base64 line-wrap collapse" -->

<!-- auto-log: 2026-08-03 19:30 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-147-lifecycle-achieved.yaml -->

<!-- auto-log: 2026-08-03 19:30 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-08-03T160000Z-issue-147/run.yaml -->

<!-- auto-log: 2026-08-03 19:34 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/test_redir.sh -->

<!-- auto-log: 2026-08-03 19:34 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/propagation_test.sh -->

<!-- auto-log: 2026-08-03 19:39 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/gitconfig_clobber_test.sh -->

<!-- auto-log: 2026-08-03 19:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 19:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 19:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-rotation-check.sh -->

<!-- auto-log: 2026-08-03 19:46 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 19:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 19:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 19:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/rotation-check.test.sh -->

<!-- auto-log: 2026-08-03 19:51 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-147.md -->

<!-- auto-log: 2026-08-03 19:51 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-147.goal.yaml -->

<!-- auto-log: 2026-08-03 19:51 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-147.goal.yaml -->

<!-- auto-log: 2026-08-03 19:53 commit "fix(dossier): scope git_auth's credential to origin's own host, fix silent-failure edge cases" -->

<!-- auto-log: 2026-08-03 19:54 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr-147-body.md -->
