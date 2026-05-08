---
issue: 101
title: 'flow(review): Path A paired-reviewer gate unreachable due to plugin-settings
  path resolution'
branch: feature/issue-101-plugin-settings-resolution
artifacts:
- type: specification
  captured_at: '2026-05-08T15:46:09Z'
  by: manual-orchestrator
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: stranger-test
  captured_at: '2026-05-08T15:47:15Z'
  result: PASS
  task_count: 6
created: '2026-05-08T15:46:09Z'
---

# Issue #101 — Path A gate plugin-settings path resolution

## Specification

### Non-goals

- Do NOT change `agentTeams` default (`false`); paired-reviewer mode must remain opt-in.
- Do NOT change `merge.markerTrust.allowedAssociations` defaults.
- Do NOT relax the two-key threat model: enabling Path A still requires BOTH a trusted-source `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var.
- Do NOT add project-tier (`.claude/settings.flow.json` / `.claude/settings.flow.local.json`) as a trusted source for `agentTeams` or `merge.markerTrust`. Hostile fork PRs must remain unable to escalate either gate via `gh pr checkout`.
- Do NOT modify the boolean-coercion logic (the `case` arm that handles `true|false|*` once a value is read) — only the source-resolution layer changes.
- Do NOT alter the env-var name (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) or its check semantics.
- Do NOT introduce a `userConfig` field for `agentTeams` in `plugin.json` (substitution behavior in slash-command bash subshells is undocumented; would not address the parallel `merge.markerTrust` bug either).

### Failure modes

- **Project-tier bypass** — a fork PR commits `.claude/settings.flow.json` with `agentTeams: true`, the gate honors it, and Path A becomes reachable through the repo. Mitigation: the loop reads ONLY `$HOME/.claude/settings.flow.json` and `${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json`; project-tier paths never appear in the source list.
- **Cascade-order regression** — plugin tier wrongly overrides $HOME, so a user who set `agentTeams: true` in $HOME never reaches Path A because the plugin default `false` wins. Mitigation: $HOME is checked first; first non-empty value wins; loop breaks on a definitive value.
- **Diagnostic regression** — existing WARN messages disappear or merge into a single ambiguous "settings not found", making it impossible for a user to tell whether the plugin is uninstalled, installed-but-env-unset, or installed-but-misconfigured. Mitigation: three-state diagnostic that names the exact file paths checked and current `CLAUDE_PLUGIN_ROOT` value.
- **JSON parse error in $HOME** — user typo'd their override file; old behavior would have silently fallen back to plugin tier (since plugin tier was the only source). New behavior must still fall through to plugin tier when $HOME is malformed AND emit a per-source WARN naming the failing file.
- **`jq` not installed** — current behavior emits WARN and uses Path B. Must preserve.
- **Both files missing** — gate emits the three-state diagnostic and uses Path B. No crash, no silent enable.
- **`agentTeams: false` in $HOME with `agentTeams: true` in plugin tier** — $HOME wins (`false`), Path A is skipped. This is by design: $HOME is the user's authoritative override and includes opt-OUT semantics.
- **Symmetric application missed** — if only `review.md` is fixed and `merge.md` is left with the broken `${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json`-only resolution for `merge.markerTrust`, the marker-trust gate stays unreachable for marketplace users. Mitigation: same source-resolution pattern applied symmetrically to `merge.md` in this PR.

### Interface contracts

**Trusted source list (ordered, override-first)** — applies to both `agentTeams` (in `review.md`) and `merge.markerTrust.allowedAssociations` (in `merge.md`):

1. `$HOME/.claude/settings.flow.json` — user-tier override; outside repo, not affected by `gh pr checkout`.
2. `${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json` — plugin default.

**Excluded sources** — `.claude/settings.flow.json`, `.claude/settings.flow.local.json` (project-tier; same exclusion as the existing `journal.dir` / `learning.proposalDir` / `conventions.commitTypes` trimmed cascade documented in `references/gate-configuration.md:171`).

**Per-key reading semantics:**

- `agentTeams` (boolean) — first non-empty value across the source list wins; legal values are JSON `true` / `false`. Any other value triggers the "non-canonical value" WARN and treats as `false`.
- `merge.markerTrust.allowedAssociations` (array of strings) — same first-non-empty-value-wins rule; legal value is a non-empty JSON array of strings. Empty array or non-array triggers the existing FINDING_LEDGER_BLOCK and uses `markerTrust.fallbackToCommitter` if configured.

**Output contracts (unchanged):**

- `review.md` Path A gate: sets shell variable `USE_PATH_A` to `0` or `1`. WARN messages on stderr; informational `"Path A skipped: ..."` on stdout.
- `merge.md` markerTrust gate: sets shell variable `TRUST_LIST` (JSON array string) or sets `FINDING_LEDGER_BLOCK` for invalid configurations.

**Diagnostic contract (NEW for AC4):** when neither source resolves a value, the WARN emitted on stderr distinguishes three states:

- (a) `CLAUDE_PLUGIN_ROOT` unset AND `plugins/flow/settings.json` (fallback path) absent — likely "flow plugin not installed in this CWD"
- (b) `CLAUDE_PLUGIN_ROOT` set to a path that doesn't contain `settings.json` — likely "plugin install corrupted or env var pointing wrong place"
- (c) Both files exist but neither sets the key — "plugin shipped a default that doesn't include the key; override in $HOME to opt in"

Each variant names the exact paths checked and includes the current `CLAUDE_PLUGIN_ROOT` value (when set) so the user can diagnose without re-running with debug instrumentation.

## Spec Validation Gate

| # | Acceptance Criterion | Verification Command | Gate Status |
|---|---------------------|----------------------|-------------|
| 1 | Fresh marketplace install can locate plugin-tier settings without manual creation of `plugins/flow/settings.json` in repo | `bash tests/agentteams-gate/test.sh` — scenario "marketplace-installed-no-cwd-plugin-dir": $HOME has `agentTeams: true`, no `plugins/flow/` in CWD; assert `USE_PATH_A=1` and no "settings not found" WARN | PASS |
| 2 | Opt-in survives plugin upgrades | `bash tests/agentteams-gate/test.sh` — scenario "upgrade-survival": run gate twice, replacing the plugin-tier settings.json file between runs; with $HOME `agentTeams: true` set throughout, both runs must produce `USE_PATH_A=1` | PASS |
| 3 | Two-key gate preserved: project-tier alone cannot enable Path A | `bash tests/agentteams-gate/test.sh` — scenario "project-tier-bypass-attempt": project-tier `.claude/settings.flow.json` has `agentTeams: true`, $HOME and plugin tier do NOT; assert `USE_PATH_A=0` and project-tier path NOT in any diagnostic message | PASS |
| 4 | Diagnostic distinguishes "plugin not installed" from "env var missing" | `bash tests/agentteams-gate/test.sh` — three sub-scenarios: (a) no $HOME, no plugin tier, `CLAUDE_PLUGIN_ROOT` unset → assert WARN contains "may not be installed"; (b) `CLAUDE_PLUGIN_ROOT` set to missing path → assert WARN names that path; (c) both files exist but neither sets key → assert WARN points at $HOME for opt-in | PASS |
| 5 | Documentation describes supported persistent opt-in path | `grep -q "agentTeams" plugins/flow/references/gate-configuration.md && grep -q '\$HOME/.claude/settings.flow.json' plugins/flow/references/gate-configuration.md` (in the agentTeams section, not just the existing trimmed-cascade table) | PASS |

All criteria PASS. Workflow proceeds to PLAN.

## Stranger Test

PASS — 6 tasks reviewed. Each task contains: explicit file paths (with line ranges where relevant), explicit scenario lists or step-by-step actions, the exact verification command, and named "preserve" / "do not change" surfaces. A zero-context agent could execute each task using the issue body + this journal + the task description without further interpretation.

<!-- auto-log: 2026-05-08 17:46 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-101.md -->

<!-- auto-log: 2026-05-08 17:47 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-101.md -->

<!-- auto-log: 2026-05-08 17:49 Write /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:50 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:52 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:53 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:53 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:53 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:53 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:54 Write /Users/danielbentes/synapti-marketplace/tests/markertrust-gate/test.sh -->

<!-- auto-log: 2026-05-08 17:55 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-08 17:56 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/gate-configuration.md -->

<!-- auto-log: 2026-05-08 17:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/CHANGELOG.md -->

<!-- auto-log: 2026-05-08 17:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/.claude-plugin/plugin.json -->

<!-- auto-log: 2026-05-08 17:59 Edit /Users/danielbentes/synapti-marketplace/.claude-plugin/marketplace.json -->

<!-- auto-log: 2026-05-08 18:01 commit "fix(flow): resolve plugin-settings path for marketplace installs (#101)" -->

<!-- auto-log: 2026-05-08 18:12 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/status.md -->

<!-- auto-log: 2026-05-08 18:12 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-08 18:12 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-05-08 18:12 Edit /Users/danielbentes/synapti-marketplace/tests/agentteams-gate/test.sh -->

<!-- auto-log: 2026-05-08 18:12 Edit /Users/danielbentes/synapti-marketplace/tests/markertrust-gate/test.sh -->

<!-- auto-log: 2026-05-08 18:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/setup.md -->

<!-- auto-log: 2026-05-08 18:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/setup.md -->

<!-- auto-log: 2026-05-08 18:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/setup.md -->

<!-- auto-log: 2026-05-08 18:17 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/CHANGELOG.md -->
