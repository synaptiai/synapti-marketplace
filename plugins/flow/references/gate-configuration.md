# Gate Configuration

Configuration reference for flow's safety gates and tier settings.

## Settings File Locations

Settings cascade — highest precedence first; first non-empty value wins:

1. `.claude/settings.flow.local.json` — project-local; gitignored (your machine-local pin for this repo)
2. `.claude/settings.flow.json` — project-shared; committed (team defaults)
3. `~/.claude/settings.flow.json` — user-global; cross-project default
4. `${CLAUDE_PLUGIN_ROOT}/settings.json` — plugin default; bundled with flow

See [Settings Cascade](#settings-cascade) below for the full precedence rules and worked examples.

## Tier Settings

```json
{
  "tiers": {
    "push": "journal",
    "prCreate": "journal",
    "issueAssign": "journal",
    "issueCreate": "journal",
    "merge": "confirm",
    "release": "confirm"
  }
}
```

The schema accepts `autonomous`, `journal` or `confirm` for each key. Tier 2 actions push, PR creation, issue creation and issue assignment follow `tiers.push`, `tiers.prCreate`, `tiers.issueCreate`, `tiers.issueAssign` (default journal: run and write one breadcrumb to the git-ignored auto-log trail; autonomous runs; confirm asks). Merge, release and pushing or deleting a tag are always confirm.

| Value | Behavior |
|-------|----------|
| `autonomous` | Execute without any user interaction |
| `journal` | Execute, and write one breadcrumb (UTC time, setting, command) to the git-ignored auto-log trail: `<journal dir>/auto-log/issue-{N}.{YYYY-MM}.md` on a branch naming issue N, `auto-log/session-{YYYY-MM-DD}.md` otherwise. Nothing is written in a repository with no journal directory, and the tracked journal is not touched. |
| `confirm` | Ask first: a permission prompt that names the action, its setting and the command. In `claude -p` it is a refusal. |

The `tier-gate.sh` PreToolUse hook applies these values to every Bash command that runs one of the actions below, and flow's `git` and `gh` wrappers check them again when the program starts. See [`three-tier-safety.md`](three-tier-safety.md) for how each reads a command and what neither covers.

### Actions

| Key | Default | Allowed values | Action |
|-----|---------|----------------|--------|
| `push` | journal | autonomous, journal, confirm | `git push` of branches to a remote |
| `prCreate` | journal | autonomous, journal, confirm | `gh pr create` (`gh pr new`); `gh api` POST to `.../pulls`; GraphQL `createPullRequest` |
| `issueAssign` | journal | autonomous, journal, confirm | `gh issue edit --add-assignee`; `gh api` POST to `.../issues/{n}/assignees`, PATCH or PUT on `.../issues/{n}` with an assignee field; GraphQL `addAssigneesToAssignable` |
| `issueCreate` | journal | autonomous, journal, confirm | `gh issue create` (`gh issue new`); `gh api` POST to `.../issues`; GraphQL `createIssue` |
| `merge` | confirm | confirm (floor) | `gh pr merge`; `gh api` PUT or POST to `.../pulls/{n}/merge` or `.../merges`; GraphQL `mergePullRequest`, `enablePullRequestAutoMerge`, `enqueuePullRequest`, and any mutation whose name holds Merge |
| `release` | confirm | confirm (floor) | `gh release create` (`gh release new`), journaled with `--verify-tag` when the tag is already on origin (below); `gh release edit`, `delete`, `upload`, `delete-asset`; `gh api` POST to `.../releases` or `.../releases/{id}/assets`, PATCH on `.../releases/{id}`, DELETE on `.../releases/{id}` or `.../releases/assets/{id}`; GraphQL `createRelease`, `updateRelease`, and any mutation whose name holds Release or Ref; pushing a tag (below) |

Pushing a tag is the `release` tier, not `push`: `git push` with `--tags`, `--follow-tags`, `--mirror` or `-c push.followTags=true`, or any push in a repository whose git configuration sets `push.followTags` to true (a `-c` on the command line overrides it); `git push <remote> tag <name>`; a refspec with `refs/tags/` on either side (`HEAD:refs/tags/v1`); a refspec whose source or destination is a tag that exists in the repository (`git push origin v1.2.0`, while a branch named `v1-fix` stays `push`), or a `tags/<name>` source; a push to a remote whose configuration sets `remote.<name>.mirror`, or whose `remote.<name>.push` refspecs send tags when the command names no refspec; and `gh api` POST to `.../git/refs` with a `refs/tags/` ref. Options are read as git reads them, so an abbreviation git accepts (`--tag`, `--mirr`, `--follow-tag`, `--del`) or a bundle of short options (`-qd`) counts. Deleting a tag is `release` too: `git push <remote> :<tag>`, `--delete`/`-d <tag>`, and `gh api` DELETE or PATCH on `.../git/refs/tags/<tag>`; deleting a name that is neither a tag nor a known branch (local, or remote-tracking on that remote) asks, since it may be a tag on the remote. A command that pushes a branch and a tag is `release`. A push whose source is not a local branch may push a tag, so it asks too: a name that does not exist yet (`git tag v7 && git push origin v7`), a glob (`refs/*:refs/*`), a commit, or a variable (`git push origin "$TAG"`). So does setting a remote's `mirror` or `push` for one command (`-c`, `--config-env`, `GIT_CONFIG_*`). `git -C <dir>`, `--git-dir`, `--work-tree`, and `GIT_DIR=` or `GIT_WORK_TREE=` before git name the repository the push acts on: its tags, its `push.followTags`, its remotes' configuration and its auto-log trail are used. When that repository cannot be found, the push asks.

`gh release create <tag> --verify-tag` is journaled instead of asked when gh creates the release in origin's repository and `git ls-remote --tags origin` finds the tag there within 5 seconds: that tag's push was already confirmed. The repository gh uses is `-R`/`--repo`, else `GH_REPO`, else the remote `gh repo set-default` chose or the only remote, and it must be origin's. Without `--verify-tag`, with the tag missing from origin, when the check fails or times out, when the repository cannot be confirmed to be origin's, with `GH_HOST` set, or after a `cd` or a `GH_REPO` setting earlier in the same command, it asks.

`gh release edit` (which publishes a draft with `--draft=false`), `gh release delete`, `gh release upload` and `gh release delete-asset` are `release`: each changes a release, or the files people download from it. `gh api` also counts for these: PATCH on `.../releases/{id}`, DELETE on `.../releases/{id}` or `.../releases/assets/{id}`, and POST to `.../releases/{id}/assets` are `release`; PATCH or PUT on `.../issues/{n}` with an `assignee` or `assignees` field is `issueAssign`; and a GraphQL mutation named `mergePullRequest` or `enablePullRequestAutoMerge` (`merge`), `createRelease` or `updateRelease` (`release`), `createPullRequest` (`prCreate`), `createIssue` (`issueCreate`) or `addAssigneesToAssignable` (`issueAssign`), read from `-f`/`-F query=...`, `query=@file` or `--input file`. Any other mutation field whose name holds Merge, in any case, or is `enqueuePullRequest`, is `merge`, and one whose name holds Release or Ref (`createRef`, `updateRef`, `deleteRef`, `deleteRelease`) is `release`. A GraphQL query that cannot be read (a variable, stdin, a missing file) asks, since it may merge or release.

`merge` and `release` cannot be lowered: a value below `confirm` is ignored with one warning on stderr naming the setting, and the action still asks. A value outside the three for the other keys, or a setting the cascade cannot read, lets the action run with one warning.

## Timeout Settings

```json
{
  "timeouts": {
    "devServerStartup": 30,
    "e2eTest": 120,
    "qualityCheckMaxIterations": 3,
    "teammateTimeout": 300
  }
}
```

| Key | Default | Unit | Purpose |
|-----|---------|------|---------|
| `devServerStartup` | 30 | seconds | Max wait for dev server |
| `e2eTest` | 120 | seconds | Max E2E test suite time |
| `qualityCheckMaxIterations` | 3 | count | Max fix-and-retry loops |
| `teammateTimeout` | 300 | seconds | How long a Path A review variant may take before its facet falls back to the other variant (guidance the agent applies; no script reads it) |

## Convention Settings

```json
{
  "conventions": {
    "commitTypes": ["feat", "fix", "docs", "..."],
    "branchPatterns": {
      "feature": "feature/issue-{N}-{desc}",
      "fix": "fix/issue-{N}-{desc}",
      "docs": "docs/issue-{N}-{desc}"
    }
  }
}
```

`/flow:release` names its release branch with `conventions.branchPatterns.release`, `{version}` replaced by the version; when the key is not set it uses `chore/release-{version}`.

## Journal Settings

```json
{
  "journal": {
    "dir": ".decisions"
  }
}
```

## Learning Settings

```json
{
  "learning": {
    "enabled": true,
    "proposalDir": "~/.claude/flow-proposals"
  }
}
```

`learning.proposalDir` and `learning.transcriptDir` are read from your user settings file (`~/.claude/settings.flow.json`, or `FLOW_USER_SETTINGS`) and the plugin default only. A value in the project files is not used, and neither is a value that is not an absolute path (or one starting with `~`).

## Settings Reference

One row per setting. The default is the value in the plugin's `settings.json` (or the schema default where `settings.json` does not set the key). "What reads it" names the script that resolves the value, or the command, skill or agent whose instructions tell the agent to apply it.

| Key | Default | What reads it |
|-----|---------|---------------|
| `agentTeams` | `false` | `/flow:review` Phase 3 Path A gate |
| `agentTeamModel` | `sonnet` | `/flow:review` Path A dispatch |
| `tiers.push`, `tiers.prCreate`, `tiers.issueAssign`, `tiers.issueCreate` | `journal` | `hooks/scripts/tier-gate.sh` and the `git`/`gh` wrappers (`hooks/scripts/lib/tier-runtime.sh`) |
| `tiers.merge`, `tiers.release` | `confirm` (floor) | same; a lower value is ignored with a warning |
| `timeouts.devServerStartup` | `30` | `integration-verifier` agent, `runtime-verification` skill |
| `timeouts.e2eTest` | `120` | `integration-verifier` agent, `runtime-verification` skill |
| `timeouts.qualityCheckMaxIterations` | `3` | `/flow:start` Phase 3 quality loop (agent instruction) |
| `timeouts.teammateTimeout` | `300` | `team-coordination` skill (agent instruction; no script reads it) |
| `conventions.commitTypes` | `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`, `revert`, `improve` | `convention-checker` agent, `convention-enforcement` skill, `/flow:setup` |
| `conventions.branchPatterns` | `feature`, `fix`, `docs` patterns (`{type}/issue-{N}-{desc}`) | `convention-enforcement` and `branch-and-task-management` skills, `/flow:setup` |
| `conventions.branchPatterns.release` | not set; `/flow:release` uses `chore/release-{version}` | `/flow:release` Phase 2 |
| `merge.strategy` | `squash` | `/flow:merge` |
| `merge.deleteBranch` | `true` | `/flow:merge` |
| `merge.markerTrust.allowedAssociations` | `["OWNER","MEMBER","COLLABORATOR"]` | `/flow:merge`, `/flow:status` (finding-ledger marker filter) |
| `conflictResolution.autoResolveTrivial` | `true` | `/flow:resolve`, `merge-conflict-resolution` skill |
| `conflictResolution.maxConflictFiles` | `20` | `/flow:resolve`, `merge-conflict-resolution` skill |
| `release.tagPrefix` | `v` | `/flow:release` Phase 2 |
| `learning.enabled` | `true` | `hooks/scripts/session-end-learn.sh` |
| `learning.proposalDir` | `~/.claude/flow-proposals` | `/flow:learn` (user settings and plugin default only) |
| `learning.sources` | `["journal","transcripts"]` | `/flow:learn`, `session-end-learn.sh` |
| `learning.transcriptDir` | `""` (Claude Code's transcript directory) | `/flow:learn`, `session-end-learn.sh` (user settings and plugin default only) |
| `journal.dir` | `.decisions` | `bin/journal-dir.sh`, and every command and hook that writes the journal through it |
| `specFirst.requireAcceptanceCriteria` | `true` | `/flow:start` Phase 1 |
| `specFirst.allowSpecFreeLabels` | `["documentation","chore"]` | `/flow:start` Phase 1 |
| `specFirst.riskMap` | `true` | `/flow:start`, `specification-capture` skill |
| `verdict.enabled` | `true` | `/flow:start` Phase 4 step 6 |
| `verdict.requireAllPass` | `true` | `/flow:start` Phase 4 (NEEDS-HUMAN-REVIEW handling) |
| `verdict.model` | `""` (no `--model`; the claude CLI's default) | `bin/flow-judge.sh --judge verdict`; allowed `haiku`, `sonnet`, `opus` |
| `verdict.timeoutSeconds` | `300` | `bin/flow-judge.sh --judge verdict`; a whole number from 5 to 600, otherwise the default |
| `review.groundingCritic` | `off` | `/flow:review` (Path B), `/flow:pr` (user settings and plugin default only) |
| `systemOne.provider`, `baseUrl`, `model`, `apiKeyEnv`, `timeoutMs`, `stateTokenCap` | `none`, `""`, `""`, `""`, `3000`, `0` | `bin/_flow_s1.py`, `bin/flow-s1-mode.sh` (user settings and plugin default only); see [System One](system-one.md#configure-it) |
| `systemOne.batch` | `off` | `bin/flow-s1.sh` (user settings and plugin default only) |
| `systemOne.uses.<site>` | `off` for every site | `bin/flow-s1-mode.sh`, `hooks/scripts/lib/s1-guard.sh`; a repository can only lower your mode |
| `testing.tddMode` | `enforce` | `/flow:start` Phase 3, `/flow:address`, `tdd-patterns` skill |
| `testing.tddModeOptOut` | `false` | `/flow:start` Phase 3, `tdd-patterns` skill (`suggest` only with this set to `true`) |
| `testing.taskCompletionGate` | `block` | `hooks/scripts/verify-task-completion.sh` |
| `testing.qualityCommandPatterns` | `[]` | `hooks/scripts/record-quality-run.sh` |
| `debugging.maxHypotheses` | `3` | `debugging-patterns` skill |
| `reviewCycleLimit` | `10` | `/flow:address`, `llm-operator-principles` skill |
| `fixForwardMaxIterations` | `10` | `/flow:start`, `/flow:pr`, `/flow:review`, `/flow:address` fix loops |
| `autonomous` | `false` | `llm-operator-principles` skill, `/flow:setup`; merge and release still ask |
| `minimalScope` | `false` | `hooks/scripts/ask-issue-create.sh`, `/flow:review`, `/flow:address` |
| `closedLoop.maxBuildIterations` | `5` | `/flow:start` Phase 3, `/flow:resolve`, `runtime-verification` skill |
| `closedLoop.maxServerRetries` | `3` | `/flow:start`, `runtime-verification` skill |
| `closedLoop.maxDebugIterations` | `5` | `/flow:start` Phase 3, `debugging-patterns` skill |
| `lsp.enabled` | `true` | `capability-discovery` and `runtime-verification` skills |
| `lsp.timeout` | `5000` (ms) | `capability-discovery` and `runtime-verification` skills |
| `lsp.diagnosticsAsQuality` | `true` | `runtime-verification` and `autonomous-workflow` skills |
| `visualVerification.viewports` | desktop 1280×720, tablet 768×1024, mobile 375×812 | `visual-verification` skill |
| `visualVerification.maxIterations` | `3` | `integration-verifier` agent |
| `visualVerification.requireVisualVerification` | `false` | `/flow:pr` Phase 4 |
| `visualVerification.flows` | `on` | `visual-verification` skill |
| `visualVerification.maxFlowSteps` | `8` | `visual-verification` skill |
| `visualVerification.screenshotDir` | `.screenshots` | [`visual-verification-output.md`](visual-verification-output.md) (agent instruction) |
| `duplication.enabled`, `minLines`, `minTokens`, `excludePaths` | `true`, `5`, `20`, test, vendor, build, journal and `.flow` paths | `bin/flow-clone-scan.sh`, run by `/flow:pr` and `/flow:review` |
| `flow.runtime.enabled` | `true` | every command that creates a FlowRun, `hooks/scripts/session-end-state.sh` |
| `flow.runtime.runRetentionDays` | `30` | `hooks/scripts/session-end-state.sh`: removes runs that ended (completed or cancelled) and whose `run.yaml` was last written more than this many days ago |
| `flow.goals.enabled` | `true` | `/flow:goal`, `/flow:start`, `/flow:pr`, `/flow:merge`, `/flow:status`, `/flow:learn` |
| `flow.goals.goalCreation` | `auto` | `/flow:start`, `/flow:pr`, `/flow:merge`, `/flow:setup` |
| `flow.goals.requireGoalForStart` | not set (deprecated) | read only to map onto `goalCreation` (`bin/flow-migrate-settings.sh`, `/flow:start`) |
| `flow.goals.stopHookEnforcement` | `warn` | `hooks/scripts/flow-goal-stop.sh` |
| `flow.goals.failAfterStuckTurns` | `3` | `flow-goal-stop.sh`, `flow-goal-evaluator.sh` |
| `flow.goals.executeVerificationCommands` | `false` | `hooks/scripts/flow-run-deterministic-checks.sh` |
| `flow.goals.judge.model` | `haiku` | `bin/flow-judge.sh --judge goal`; allowed `haiku`, `sonnet`, `opus` |
| `flow.goals.judge.timeoutSeconds` | `60` | `bin/flow-judge.sh --judge goal`; a whole number from 5 to 600, otherwise the default |
| `flow.workflows.enabled` | `true` | `/flow:workflow` |
| `flow.triggers.enabled` | `true` | `/flow:trigger`, `/flow:watch`, `/flow:run`, `/flow:status` |
| `flow.triggers.allowedTypes` | `["manual","hook","loop_prompt"]` | `/flow:trigger`, `trigger-policy` skill |
| `flow.triggers.maxActiveTriggers` | `5` | `trigger-policy` skill |
| `replyStyle.enabled`, `constructions`, `extraPatterns` | `false`, not set, not set | `hooks/scripts/reply-style-check.sh` |

Settings that nothing reads (setting them changes nothing): `closedLoop.enabled`, `closedLoop.requireRuntimeVerification`, `visualVerification.enabled`, `flow.runtime.stateDir` (the runtime directory is always `.flow`), `flow.triggers.allowAutonomousMerge`, `flow.triggers.allowTriggerCreationFromTriggeredRun`, `flow.triggers.defaultConcurrency`.

## Quality Gates

Flow enforces twelve quality gates across the workflow lifecycle. Gates are structural -- they block progression until satisfied.

### 1. Spec Validation Gate (EXPLORE phase)

Validates that every acceptance criterion has a concrete, automated verification command before the workflow transitions to PLAN. Rejects vague criteria (e.g., "works correctly") and requires specification of non-goals, failure modes, and interface contracts.

**Blocks:** EXPLORE -> PLAN transition
**Override:** None for an issue with acceptance criteria: fix the spec. An issue with no acceptance criteria may proceed without a spec when `specFirst.requireAcceptanceCriteria` is `false`, or when the issue carries a label listed in `specFirst.allowSpecFreeLabels` (default `documentation`, `chore`) and the user chooses the spec-free option, which is logged to the decision journal.

### 2. Stranger Test Gate (end of PLAN)

Ensures the plan is executable by someone with zero prior context. Every task must have explicit inputs, expected outputs, and verification steps. Implicit assumptions, undefined references, and "you know what I mean" instructions fail the gate.

**Blocks:** PLAN -> CODE transition
**Override:** None. Rewrite until zero-context executable.

### 3. Per-Task Verification Gate (CODE phase)

Tests must pass and evidence must be captured before `TaskUpdate(completed)` is accepted. When `tddMode: "enforce"`, tests must exist before the implementation is written.

**Blocks:** Individual task completion
**Override:** Set `testing.tddMode: "suggest"` and `testing.tddModeOptOut: true`

### 4. Runtime Verification Whitelist (VERIFY phase)

Runtime verification (dev server startup, API smoke tests, E2E tests, browser checks) is mandatory for every change. The only permitted skips are three enumerated categories: `markdown-only`, `config-only`, and `dependency-bump-only`. Any skip outside this whitelist requires a Proactive-Autonomy escalation. Diagnostics from LSP servers are treated as quality signals (errors -> P1, warnings -> P2) when `lsp.diagnosticsAsQuality` is true.

**Blocks:** VERIFY phase completion
**Configuration:** `lsp.diagnosticsAsQuality`. Skip categories are enumerated in `runtime-verification/SKILL.md` (not user-configurable).

### 5. Evidence Completeness (VERIFY phase)

Every criterion's evidence bundle must include a non-blank `### Does NOT promise` subsection (the criterion's non-goals; `none` counts as present) and five completeness subsections: "What was NOT tested," "Known limitations," "Negative/adversarial cases," "Test inputs and expected values" (with the source of each expected value), and "Risk map coverage." The verdict-judge FAILs any criterion whose evidence is missing these subsections, whose expected values are self-referential (copied from the implementation), or whose risk-map rows have no discriminating test. A `ui` criterion must additionally carry `### Visual analysis` (one `Viewport:` / `Screenshot:` / `Result:` / `Observed:` block per configured viewport copied from the visual-verification result). When the criterion describes an action a user performs, it must also carry the `Step:` blocks of the driven flow, or a `Flows: none — {reason}` line saying why no flow ran. The verdict-judge has no file tools and judges the `Observed:` sentences, never the image.

**Blocks:** PASS verdict on the affected criterion (judge-side, not pre-submission)
**Override:** None. Add the missing subsections.

### 6. Missing-Criterion Scan (verdict-judge)

Step 1 of verdict evaluation checks that every acceptance criterion from the issue has a corresponding evidence entry. Criteria without evidence are flagged as `FAIL` before any evaluation begins, and any `FAIL` sends `/flow:start` into its fix loop.

**Blocks:** Verdict evaluation
**Override:** None for a missing criterion. `verdict.requireAllPass` decides how a `NEEDS-HUMAN-REVIEW` verdict is handled: `true` (default) treats it as `FAIL`; `false` shows the verdict table and asks the user to approve or reject.

### 7. Holdout Validation (VERIFY + review + address phases)

Cross-references agent self-review claims against actual file state. Runs inline during verification, code review, and feedback resolution. Detects claims that are not grounded in the codebase (e.g., "all edge cases handled" when error paths are uncovered).

**Blocks:** Self-review acceptance
**Override:** None. Fix the claims or fix the code.

### 8. Finding-Ledger Merge Gate (merge)

Reads the `FLOW_REVIEW_CYCLE` and `FLOW_RESOLUTION_CYCLE` markers from the pull request's review bodies and comments. Blocks merge when the markers contain unresolved or escalated items. An item that is not fixed carries the status "ESCALATED": deferral without a structured escalation is not permitted.

**Blocks:** `gh pr merge` / `/flow:merge`
**Override:** Resolve all findings or complete Proactive Autonomy escalation for each.

**Marker trust filter:** Both `/flow:merge` and `/flow:status` filter markers by GitHub `author_association` before honoring them — see the Trust Boundary section of [`finding-ledger-parser.md`](finding-ledger-parser.md) for the threat model.

| Setting | Default | Notes |
|---------|---------|-------|
| `merge.markerTrust.allowedAssociations` | `["OWNER","MEMBER","COLLABORATOR"]` | Read from the standard cascade (see "Settings Cascade" below). Used by `commands/merge.md` and `commands/status.md` to filter forgeable `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE` markers by GitHub `author_association`. |

### 9. Task-Completion Quality Ledger (every session)

`hooks/scripts/verify-task-completion.sh` (TaskCompleted) refuses to mark a task complete while the working tree changed in this session after the last PASSING quality-command run. The per-session ledger under `<state dir>/sessions/<session_id>/quality-ledger.jsonl` (the per-user state directory: `~/.claude/flow-state`, or a `FLOW_STATE_DIR` you set; see [README: Per-user locations](../README.md#per-user-locations)) is written by `log-file-changes.sh` (PostToolUse `Edit|Write|NotebookEdit`) and `record-quality-run.sh` (PostToolUse **and** PostToolUseFailure `Bash`: test/lint/typecheck/build commands matched at command position only, with their exit code, a `masked` flag for `|| true`, a `failed` flag for the failure event, and a sha256 digest of the git working tree). A run passes only when it exited 0, unmasked, and did not fail, and System One did not find that no test ran or every test was skipped (the `quality.tests-ran` decision point, off by default; see [System One](system-one.md#qualitytests-ran)). The digest is a git tree id of the working tree contents (HEAD excluded), recomputed by the gate, so edits made through Bash (`sed -i`, heredocs, `git apply`) and checkouts after the last passing run block too, while committing the edits that run already tested does not. Journal, `.flow/`, and `.screenshots/` writes never dirty the gate (they are excluded from the digest as well). `session-end-state.sh` prunes session ledgers idle for 14 days once per day. This is the one gate that runs with or without a FlowGoal.

**Blocks:** `TaskUpdate(completed)` (exit 2, the changed paths named on stderr)
**Configuration:** `testing.taskCompletionGate` = `block` (default) / `warn` / `off`; `testing.qualityCommandPatterns` adds project-specific ERE patterns.

### 10. Issue-Create Ask Gate (active FlowGoal)

`hooks/scripts/ask-issue-create.sh` (PreToolUse, Bash) turns `gh issue create` into a permission prompt while a FlowGoal is active, naming the goal and the operator rule (findings are fixed in this PR, not filed as follow-ups). Approve for a genuine product decision or work outside the goal's scope; deny and fix it here otherwise.

**Blocks:** nothing on its own; it asks. Never fires when `minimalScope: true` or when no goal is active.
**Override:** `minimalScope: true`.

### 11. Unchecked-Merge Gate (every session)

`hooks/scripts/block-unchecked-merge.sh` (PreToolUse, Bash) refuses a merge while any of its checks is queued, running or failed, and refuses `--auto` on a base branch that requires no checks, because auto-merge then merges at once. It applies to merges typed into Bash, not only to `/flow:merge`.

A pull request with no checks is merged when the base branch requires none. To know that, it asks GitHub for the base branch's protection and rulesets. A 404, or the 403 GitHub gives a private repository on the free plan ("Upgrade to GitHub Pro or make this repository public"), means nothing is required. When neither answer is definite, the refusal lists each lookup's HTTP status, GitHub's message and the kind of failure (permission, network or rate limit, other), and says whether a retry can change it. Every refusal ends with a `Next:` line: a command the agent can run, or the exact command the user must type, such as `! gh pr merge 58 --repo owner/name --squash` (`!` runs it without hooks).

It reads the command as text, so it checks a merge in one shape only: `gh pr merge <number> --repo owner/name --squash|--merge|--rebase`, with gh as the first word, long options, and literal values. `--repo` is required because it outranks `GH_REPO`, `GH_HOST`, the working directory and `gh repo set-default`, none of which the hook can see. Any other merge is refused with the shape to use, and a variable or substitution in the pull request or repository is named. A merge inside a command whose quotes do not balance is refused, because where it ends cannot be read. `gh api` is refused on a merge endpoint or merge mutation, when its whole endpoint is a variable, and for a GraphQL query read from a file.

It is not a defence against deliberate evasion (an alias, a command held in a variable, a script piped into a shell, curl to the REST API). Required status checks on the base branch are.

**Blocks:** `gh pr merge` in Bash, `gh api` merge calls
**Override:** None in settings. Merge a pull request whose checks have finished, in the shape above.

### 12. Tier Gate (every session)

`hooks/scripts/tier-gate.sh` (PreToolUse, Bash) applies the tier settings to every Bash command, whether a flow command or the agent wrote it. Tier 2 actions push, PR creation, issue creation and issue assignment follow `tiers.push`, `tiers.prCreate`, `tiers.issueCreate`, `tiers.issueAssign` (default journal: run and write one breadcrumb to the git-ignored auto-log trail; autonomous runs; confirm asks). Merge, release and pushing or deleting a tag are always confirm. `hooks/scripts/tier-session-start.sh` (SessionStart) puts flow's `git` and `gh` wrappers (`hooks/shims/`) first on PATH, and each wrapper refuses a `confirm` action that `tier-gate.sh` did not ask about in the same Bash call. The actions each tier covers are in [Actions](#actions) above; how the hook and the wrappers read a command, and what neither covers, is in [`three-tier-safety.md`](three-tier-safety.md).

**Blocks:** nothing on its own; it asks (a refusal in `claude -p`) before a merge, a release, a tag push and any action set to `confirm`.
**Override:** `tiers.push`, `tiers.prCreate`, `tiers.issueCreate`, `tiers.issueAssign`. `tiers.merge` and `tiers.release` cannot go below `confirm`.

### Stop hook posture (FlowGoal evidence)

`hooks/scripts/flow-goal-stop.sh` ships in `warn` mode and says so: the reason starts with `FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)` and is echoed to stderr. `block` is opt-in (`flow.goals.stopHookEnforcement: block`). In block mode, verification commands execute only for goals recorded in the user-local trust ledger (`bin/flow-goal-trust.sh`, written automatically when flow creates the goal) or when `flow.goals.executeVerificationCommands` is true; consecutive blocks are capped by `flow.goals.failAfterStuckTurns`. See [`stop-hook-goal-enforcement.md`](stop-hook-goal-enforcement.md).

### Settings Cascade

Flow follows the standard Claude Code settings precedence (highest first):

1. `.claude/settings.flow.local.json` — project-local; gitignored. Personal pins for this project that should not be shared with the team.
2. `.claude/settings.flow.json` — project-shared; committed. Team-wide defaults.
3. the user settings file (`~/.claude/settings.flow.json`, or `FLOW_USER_SETTINGS`; see the README's Per-user locations) — user-global; cross-project defaults across all repositories.
4. `${CLAUDE_PLUGIN_ROOT}/settings.json` — plugin default; bundled with the plugin.

**First non-empty value wins.** A user setting `agentTeams: true` in `.claude/settings.flow.local.json` overrides the same key in `.claude/settings.flow.json`, which overrides the user settings file, which overrides the plugin default.

Most settings follow this order. A few are read only from the user settings file and the plugin default, because a repository must not choose them: the System One provider settings and whether a System One site is `on`, `review.groundingCritic` during a review, and `learning.proposalDir` and `learning.transcriptDir` (where `/flow:learn` writes proposals and which transcripts it reads). For the rest, the threat model relies on Claude Code's standard review surface: changes to `.claude/settings.flow.json` appear in the PR diff like any other repo file, and reviewers can spot a permissive `merge.markerTrust.allowedAssociations` or a flipped `agentTeams: true` in normal review.

#### Persistent personal opt-in

To enable a setting just for yourself (not committed to the team's project file), write it to either:

- `.claude/settings.flow.local.json` — applies only to this repository, gitignored
- `~/.claude/settings.flow.json` (or `FLOW_USER_SETTINGS`) — applies across all your projects

Example: enabling Path A paired-reviewer mode for yourself in this project only:

```json
// .claude/settings.flow.local.json (gitignored)
{
  "agentTeams": true
}
```

(Note: `agentTeams: true` also requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set in your shell environment — the env var is the user-side opt-in for the experimental feature.)

**Path A review model (`agentTeamModel`).** Path A dispatches ~20 review agents (paired skeptic/verifier × 5 facets + a challenge round), all of which would otherwise inherit the session model. To avoid running an Opus session's rate across that fan-out, the model is configurable via the top-level `agentTeamModel` key (enum `haiku|sonnet|opus|fable|inherit`, default `sonnet`), resolved through this same cascade. An invalid value is rejected with a WARN and falls back to `sonnet`. Use `inherit` to run Path A agents on the session model. This is scoped to Path A only — Path B (single-session) agents always inherit the session model.

```json
// .claude/settings.flow.local.json (gitignored) — pin a higher model for a hard review
{
  "agentTeams": true,
  "agentTeamModel": "opus"
}
```

#### Team-wide opt-in

To enable a setting for the whole team via the committed project-shared file:

```json
// .claude/settings.flow.json (committed)
{
  "agentTeams": true,
  "merge": {
    "markerTrust": {
      "allowedAssociations": ["OWNER", "MEMBER", "COLLABORATOR", "CONTRIBUTOR"]
    }
  }
}
```

Reviewers will see the change in the PR diff. Anyone can override with their own `.claude/settings.flow.local.json` or `$HOME` setting if they don't want the team-wide value.

## Gate Summary

| # | Gate | Phase | Blocks |
|---|------|-------|--------|
| 1 | Spec Validation | EXPLORE | PLAN transition |
| 2 | Stranger Test | PLAN | CODE transition |
| 3 | Per-Task Verification | CODE | Task completion |
| 4 | Runtime Verification | VERIFY | Phase completion |
| 5 | Evidence Completeness | VERIFY | PASS verdict (judge-side) |
| 6 | Missing-Criterion Scan | Verdict | Verdict evaluation |
| 7 | Holdout Validation | VERIFY/review/address | Self-review acceptance |
| 8 | Finding-Ledger Merge | Merge | PR merge |
| 9 | Task-Completion Quality Ledger | Every session | Task completion |
| 10 | Issue-Create Ask Gate | Active goal | Asks before `gh issue create` |
| 11 | Unchecked-Merge Gate | Every session | `gh pr merge` with unfinished checks, or in another shape |
| 12 | Tier Gate | Every session | Asks before merge, release, tag push and any action set to `confirm` |

## Hook Override

Hook scripts always run. These settings change what a hook does: `tiers.*` (`tier-gate.sh` and the `git`/`gh` wrappers), `testing.taskCompletionGate` (`verify-task-completion.sh`), `testing.qualityCommandPatterns` (`record-quality-run.sh`), `minimalScope` (`ask-issue-create.sh`), `flow.goals.stopHookEnforcement`, `flow.goals.failAfterStuckTurns` and `flow.goals.executeVerificationCommands` (the Stop hook scripts), `flow.runtime.enabled` and `flow.runtime.runRetentionDays` (`session-end-state.sh`), `learning.enabled`, `learning.sources` and `learning.transcriptDir` (`session-end-learn.sh`), `replyStyle.*` (`reply-style-check.sh`), and `systemOne.uses` for the `quality.tests-ran`, `guard.planted-instructions`, `goal.judge` and `goal.warn-evidence` sites (`record-quality-run.sh`, `s1-screen-text.sh`, the Stop hook scripts). To change anything else, edit the script in `plugins/flow/hooks/scripts/`.
