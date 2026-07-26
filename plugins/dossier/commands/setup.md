---
description: "Wire the post-merge documentation refresh into this repository. Preflights the GitHub settings that silently break it, renders the three-job workflow, creates labels, and lists the manual steps setup cannot perform."
argument-hint: [--ci github-actions|flow-trigger|none] [--dry-run]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, AskUserQuestion
---

# Set Up Documentation Automation: $ARGUMENTS

Scaffolds the job that regenerates the documentation package after a pull request merges and opens a documentation PR against this same repository.

## Required Skills

- `engagement-scoping` — resolve the output root and confirm the package exists before wiring automation to it

## References

- [`config-resolution.md`](../references/config-resolution.md)
- [`change-triggers-and-blast-radius.md`](../references/change-triggers-and-blast-radius.md)

## Phase 0 — Preflight

Read-only, run with the user's own `gh` credentials — which carry the admin scope CI does not have. Emits `KEY=value` and exits 0 on failure rather than degrading silently.

```!
_RAW="$ARGUMENTS"
echo "### Setup Arguments"
echo "ARGS=$_RAW"

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-managed-file.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-managed-file.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Plugin"
if [ ! -x "$__dr/bin/dossier-managed-file.sh" ]; then
  echo "SETUP_STATE=blocked"
  echo "SETUP_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi
echo "DOSSIER_ROOT=$__dr"
echo "PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$__dr/.claude-plugin/plugin.json" 2>/dev/null)"

echo "### Repo"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || {
  echo "SETUP_STATE=blocked"
  echo "SETUP_ERROR=gh not authenticated — run 'gh auth login'"
  true; exit 0
}
echo "REPO=$REPO"
DB=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
echo "DEFAULT_BRANCH=$DB"
echo "PRIVATE=$(gh repo view --json isPrivate --jq .isPrivate 2>/dev/null)"
echo "HAS_GITHUB_DIR=$([ -d .github ] && echo true || echo false)"
echo "HAS_GITLAB_CI=$([ -f .gitlab-ci.yml ] && echo true || echo false)"

echo "### The gotcha checks"
# GITHUB_TOKEN cannot open a PR unless this is enabled. Without it the branch
# pushes cleanly and `gh pr create` refuses — a successful push and no PR.
CAN_PR=$(gh api "repos/$REPO/actions/permissions/workflow" --jq '.can_approve_pull_request_reviews' 2>/dev/null) || CAN_PR="unknown"
echo "ACTIONS_CAN_CREATE_PRS=$CAN_PR"
echo "DEFAULT_WORKFLOW_PERMISSIONS=$(gh api "repos/$REPO/actions/permissions/workflow" --jq '.default_workflow_permissions' 2>/dev/null || echo unknown)"

ORG="${REPO%%/*}"
if gh api "orgs/$ORG" >/dev/null 2>&1; then
  echo "ORG_ACTIONS_CAN_CREATE_PRS=$(gh api "orgs/$ORG/actions/permissions/workflow" --jq '.can_approve_pull_request_reviews' 2>/dev/null || echo unknown)"
else
  echo "ORG_ACTIONS_CAN_CREATE_PRS=n/a"
fi

# Required checks make a GITHUB_TOKEN-created docs PR permanently unmergeable.
CHECKS=$(gh api "repos/$REPO/branches/$DB/protection" --jq '.required_status_checks.contexts | join(",")' 2>/dev/null) || CHECKS=""
echo "REQUIRED_CHECKS=${CHECKS:-none}"

echo "### Existing state"
echo "SECRETS=$(gh secret list --repo "$REPO" --json name --jq '[.[].name] | join(",")' 2>/dev/null || echo unreadable)"
echo "EXISTING_WORKFLOW=$([ -f .github/workflows/dossier-docs-refresh.yml ] && echo true || echo false)"
if [ -f .github/workflows/dossier-docs-refresh.yml ]; then
  "$__dr/bin/dossier-managed-file.sh" --verify .github/workflows/dossier-docs-refresh.yml 2>/dev/null || echo "MANAGED=unknown"
fi
OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "PACKAGE_EXISTS=$([ -d "$OUTPUT_ROOT/00-control" ] && echo true || echo false)"
echo "FLOW_INSTALLED=$([ -f .claude/settings.flow.json ] && echo true || echo false)"
echo "MARKETPLACE_REF=$(gh api repos/synaptiai/synapti-marketplace/releases/latest --jq .tag_name 2>/dev/null || echo main)"

echo "### Merge cadence (for the cost conversation)"
echo "MERGES_LAST_4W=$(git log --merges --since='4 weeks ago' --oneline 2>/dev/null | wc -l | tr -d ' ')"
true
```

If `PACKAGE_EXISTS=false`, wiring automation to a package that does not exist produces a first run that regenerates everything. Say so, and recommend `/dossier:init` and `/dossier:baseline` first.

## Phase 1 — The managed-file contract

Setup writes into `.github/`, so every file it owns carries a first-line stamp:

```
# dossier:managed v1 sha256=<sha256 of the body below the stamp>
```

| `--verify` result | Behavior | Tier |
|---|---|---|
| `absent` | Write it | 1 |
| `clean` | Setup wrote it and nobody edited it — regenerate silently | 1 |
| `dirty` | A human edited it — **`AskUserQuestion`**, never overwrite | 2 |
| `foreign` | No stamp; someone else's file with our name — **`AskUserQuestion`**, default to a different filename | 2 |

For `dirty`/`foreign`, offer: keep mine and write `.new` alongside (recommended) · show the diff first · overwrite · skip the workflow entirely.

## Phase 2 — Decisions

Use `AskUserQuestion` for each, with a stated recommendation and the failure mode of each option.

`--ci github-actions|flow-trigger|none` answers question 1 up front and skips it. `--dry-run` prints what every phase would write and stops before writing anything, including the remote label creation.

1. **CI wiring** — GitHub Actions (recommended when `.github/` exists) · local flow trigger only · settings only, wire later · skip. Offer a GitLab template when `HAS_GITLAB_CI=true` rather than assuming GitHub.
2. **Trigger policy** — path-filtered merge plus a weekly sweep (recommended) · every merge · weekly sweep only · label-gated. Show `MERGES_LAST_4W` so the cost conversation happens with numbers. Label-gated is offered but not recommended: its failure mode is quietly stale documentation that looks current.
3. **Branch strategy** — rolling `docs/dossier` with one accumulating PR (recommended) · per-source-PR · rolling with weekly rotation. State that per-PR branching guarantees pairwise conflicts across the same 23 files.
4. **Fork PRs** — no, this repo does not take them (recommended; uses `pull_request`) · yes, refresh immediately (uses `pull_request_target`; we never check out PR head, and the code is already merged into the base branch by the time the job runs) · yes, but let the sweep cover them.
5. **Token identity** — asked **only when `REQUIRED_CHECKS != none`**, because that is the only case where `GITHUB_TOKEN` is actually broken rather than merely limited. GitHub App (recommended) · fine-grained PAT · `GITHUB_TOKEN` anyway, accepting that the docs PR will never receive those checks.
6. **Action pinning** — `@v1` (recommended, gets fixes) · a commit SHA (supply-chain hardening; Dependabot bumps it).
7. **Instruction source** — plugin install via `plugin_marketplaces` (recommended) · vendored. Say plainly that `plugin_marketplaces` accepts no ref, so CI always runs the skill text from marketplace `main` even when the helper scripts are pinned. Vendored is the complete fix and the right answer for a private marketplace.

   Choosing vendored changes what Phase 3 writes and what the workflow runs: setup emits `.claude/dossier/refresh-instructions.md`, drops the `plugin_marketplaces` and `plugins` inputs from the rendered workflow, and points the `prompt` at the vendored file instead of `/dossier:refresh`. The trade is explicit — fully pinned instructions, at the cost of re-running `/dossier:setup` to pick up plugin updates. Say that when the user picks it.
8. **`CLAUDE.md`** — append the dossier section?

## Phase 3 — Write

| Path | Action | Idempotency | Tier |
|---|---|---|---|
| `.claude/settings.dossier.json` | write/merge | Reads `$HOME/.claude/settings.dossier.json` first and **skips any key the user already set there** — project-shared beats user-global, and silently overriding a global preference is a surprise that makes people distrust setup. `AskUserQuestion` per conflict | 1 |
| `.github/workflows/dossier-docs-refresh.yml` | render | Managed-file contract above | 1 clean / 2 dirty |
| `.gitignore` | append | `grep -qxF "$L" .gitignore \|\| echo "$L" >> .gitignore` for `.dossier/`, `.claude/settings.dossier.local.json`, `.claude/*.lock` | 1 |
| `<outputRoot>/.dossier-state.json` | seed | Only if absent. Empty `last_documented_sha` means cold start | 1 |
| `CLAUDE.md` | append | Only after consent; `grep -qF '## Dossier Documentation'` guards re-append | 2 |
| `.github/dependabot.yml` | create/merge | Only after consent. Adds a `github-actions` entry so the pinned action does not silently rot. Merges, never replaces | 2 |
| `.claude/dossier/refresh-instructions.md` | copy | **Only when `ci.instructionSource: vendored`.** Concatenates `commands/refresh.md` with the references it cites, resolved to a single self-contained file with no `plugins/dossier/...` paths left in it | 1 |
| `.flow/triggers/docs-refresh.trigger.yaml` | copy | Only on the non-GHA path. Validate with flow's `trigger-policy` skill before writing — it hard-fails a trigger that does not forbid `merge` and `release` | 2 |
| Repo labels | `gh label create` | Remote mutation. Existence-checked and idempotent | 2 |

Render-time substitutions into the workflow template: `{{DOSSIER_MARKETPLACE_URL}}`, `{{DOSSIER_MARKETPLACE_REPO}}`, `{{DOSSIER_REF}}`, `{{DOSSIER_PLUGIN_VERSION}}`, `{{DOSSIER_DOCS_DIR}}`, `{{DOSSIER_ROLLING_BRANCH}}`, `{{DOSSIER_PATH_FILTERS}}`, `{{DOSSIER_SCHEDULE_CRON}}`, `{{DOSSIER_TRIGGER_EVENT}}`, `{{DOSSIER_LABEL_GENERATED}}`, `{{DOSSIER_LABEL_SKIP}}`, `{{DOSSIER_LABEL_OVERSIZED}}`.

Then stamp it:

```bash
bin/dossier-managed-file.sh --stamp .github/workflows/dossier-docs-refresh.yml --comment hash
```

Verify no placeholder survived — an unsubstituted `{{...}}` is a workflow that fails at parse time:

```bash
grep -n '{{[A-Z_]*}}' .github/workflows/dossier-docs-refresh.yml && echo "UNSUBSTITUTED PLACEHOLDERS — do not commit" || echo "render clean"
```

With `--dry-run`, print what would be written and stop.

## Phase 4 — The manual steps

Setup cannot do these and must not pretend otherwise. Emit each as a checkbox with the exact command and the exact symptom of skipping it.

```markdown
### Manual steps — the workflow FAILS LOUDLY until these are done

- [ ] **Add the Anthropic credential.** Setup cannot: secrets are write-only via
      the API, and you should paste your own key.
        gh secret set ANTHROPIC_API_KEY --repo {REPO}
        # or, for a Claude subscription:
        gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo {REPO}
      Symptom if skipped: the refresh job fails on its first step with an explicit
      error. It does NOT silently skip — stale documentation must never look current.

{when ACTIONS_CAN_CREATE_PRS != true:}
- [ ] **Enable "Allow GitHub Actions to create and approve pull requests".**
        {REPO} → Settings → Actions → General → Workflow permissions
        gh api -X PUT repos/{REPO}/actions/permissions/workflow \
          -F default_workflow_permissions=write -F can_approve_pull_request_reviews=true
      THIS IS THE #1 SETUP FAILURE. Without it the docs branch pushes fine and
      `gh pr create` returns "GitHub Actions is not permitted to create or approve
      pull requests" — a successful push and no PR.

{when ORG_ACTIONS_CAN_CREATE_PRS == false:}
- [ ] **Enable it at the ORGANISATION level first** — {ORG} → Settings → Actions →
      General. While the org setting is off the repo checkbox is greyed out and the
      API call above returns 200 with no effect. Requires an org owner.

{when REQUIRED_CHECKS != none:}
- [ ] **Required checks on {DEFAULT_BRANCH}: {REQUIRED_CHECKS}.** PRs created by
      GITHUB_TOKEN do not trigger workflows, so the docs PR receives none of these
      and is unmergeable forever. Pick one:
        a) GitHub App (recommended):
             gh secret set DOSSIER_APP_ID --repo {REPO}
             gh secret set DOSSIER_APP_PRIVATE_KEY --repo {REPO}
        b) Fine-grained PAT with contents:write + pull-requests:write:
             gh secret set DOSSIER_GITHUB_TOKEN --repo {REPO}
        c) Exempt {OUTPUT_ROOT}/** from those checks' path filters.

- [ ] **Commit and push the workflow and settings.** Scheduled workflows only run
      from the default branch — the sweep will not fire until this is on
      {DEFAULT_BRANCH}.

- [ ] **Dry run:**  gh workflow run dossier-docs-refresh.yml -f force=true
```

## Phase 5 — Report

```markdown
### Setup complete

CI_MODE={github-actions|flow-trigger|none}
TRIGGER_POLICY={policy}  BRANCH_STRATEGY={strategy}  TRIGGER_EVENT={event}
FILES_WRITTEN={n}  LABELS_CREATED={n}
MANUAL_STEPS_REMAINING={n}
BLOCKING_GOTCHAS={list, or none}
```

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| `gh api` reads for repo, branch, secrets, protection, Actions permissions | 1 | Autonomous, read-only; loud-fail `KEY=value`, exit 0 |
| Read `$HOME/.claude/settings.dossier.json` for cascade-conflict detection | 1 | Autonomous, read-only |
| `mkdir -p .claude .github/workflows` | 1 | Autonomous |
| Write `.claude/settings.dossier.json` | 1 | Autonomous, project file |
| Skip a key the user already set in user-global settings | 2 | `AskUserQuestion`; default preserves the user's preference |
| Append `.gitignore` entries (idempotent) | 1 | Autonomous |
| Seed `<outputRoot>/.dossier-state.json` when absent | 1 | Autonomous |
| Write the workflow when `absent` or `MANAGED=clean` | 1 | Autonomous; stamped managed file |
| Overwrite when `MANAGED=dirty` or `foreign` | 2 | `AskUserQuestion`; default writes `.new` and never destroys hand edits |
| Choose trigger policy, branch strategy, fork trigger, token identity, pinning | 2 | `AskUserQuestion`; each option states its cost and failure mode |
| Append the dossier section to `CLAUDE.md` | 2 | `AskUserQuestion`; idempotent heading guard |
| Create or merge `.github/dependabot.yml` | 2 | `AskUserQuestion`; merges, never replaces |
| Copy the flow trigger (non-GHA path) | 2 | `AskUserQuestion`; validated by flow's `trigger-policy` skill before writing |
| `gh label create` (remote mutation) | 2 | `AskUserQuestion`; existence-checked, idempotent |
| Set `ANTHROPIC_API_KEY` / OAuth token | 3 | **Never automated.** Instructions only — the user pastes their own credential |
| Change repo or org Actions permissions | 3 | **Never automated.** The exact `gh api` command is emitted; the user runs it |
| Commit or push anything setup wrote | 3 | **Never automated.** The user reviews the diff and commits |
| Enable or disable the workflow | 3 | **Never automated.** Command emitted only |
