---
description: "Read-only overview of documentation package health — canonical coverage, register counts, open material gaps, staleness against the freshness threshold, the last gate verdict, and whether the post-merge automation is wired and current."
argument-hint: [--json] [--path <package-root>]
allowed-tools: Bash, Read
---

# Documentation Status

Read-only observation. No skills, no agents, no writes.

## Required Skills

_None — read-only status command. No skill invocations._

## References

- [`release-gate-conditions.md`](../references/release-gate-conditions.md)
- [`change-triggers-and-blast-radius.md`](../references/change-triggers-and-blast-radius.md)

## Gather State

```!
_RAW="$ARGUMENTS"
ARG1="${_RAW%% *}"
case "$ARG1" in
  --json) MODE=json ;;
  *)      MODE=compact ;;
esac

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-resolve-config.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-resolve-config.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Mode"
echo "STATUS_MODE=$MODE"

echo "### Plugin"
if [ ! -x "$__dr/bin/dossier-resolve-config.sh" ] || [ ! -x "$__dr/bin/dossier-staleness-check.sh" ]; then
  echo "STATUS_STATE=blocked"
  echo "STATUS_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi
R="$__dr/bin/dossier-resolve-config.sh"
echo "PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$__dr/.claude-plugin/plugin.json" 2>/dev/null)"

echo "### Package"
OUTPUT_ROOT=$("$R" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
if [ ! -d "$OUTPUT_ROOT/00-control" ]; then
  echo "PACKAGE_STATE=absent"
  echo "PACKAGE_HINT=run /dossier:init to scaffold, then /dossier:baseline to draft"
  true; exit 0
fi
echo "PACKAGE_STATE=present"
echo "PROJECT_NAME=$("$R" --default '(unset)' dossier.project.name 2>/dev/null)"
echo "DELIVERY_MODE=$("$R" --default full dossier.engagement.deliveryMode 2>/dev/null)"
echo "DISCLOSURE_POLICY=$("$R" --default internal-only dossier.disclosure.policy 2>/dev/null)"

echo "### Coverage"
EXPECTED=23
FOUND=$(find "$OUTPUT_ROOT" -mindepth 2 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
echo "CANONICAL_EXPECTED=$EXPECTED"
echo "CANONICAL_FOUND=$FOUND"
for d in 00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification; do
  echo "DIR_${d}=$(find "$OUTPUT_ROOT/$d" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
done

echo "### Document status"
for s in verified "partially verified" draft "N/A"; do
  n=$(grep -rl "^status: $s" "$OUTPUT_ROOT" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
  echo "STATUS_$(printf '%s' "$s" | tr ' ' '_')=$n"
done

echo "### Registers"
C="$OUTPUT_ROOT/00-control"
echo "EVIDENCE_ROWS=$(grep -c '^| EV-' "$C/evidence-ledger.md" 2>/dev/null || echo 0)"
for st in V C R I U; do
  echo "EVIDENCE_STATE_${st}=$(awk -F'|' '/^\| EV-/{gsub(/ /,"",$4); if($4=="'"$st"'") n++} END{print n+0}' "$C/evidence-ledger.md" 2>/dev/null || echo 0)"
done
echo "OPEN_QUESTIONS=$(grep -c '^| AQ-' "$C/assumptions-questions-and-contradictions.md" 2>/dev/null || echo 0)"
echo "CONTRADICTIONS=$(grep -c '^| CT-' "$C/assumptions-questions-and-contradictions.md" 2>/dev/null || echo 0)"
echo "NEEDS_OWNER=$(grep -c 'needs-owner' "$C/assumptions-questions-and-contradictions.md" 2>/dev/null || echo 0)"
echo "CLAIMS_TOTAL=$(grep -c '^| CL-' "$C/claim-and-disclosure-register.md" 2>/dev/null || echo 0)"
echo "CLAIMS_PENDING=$(grep -c '^| CL-.*| *pending *|' "$C/claim-and-disclosure-register.md" 2>/dev/null || echo 0)"
echo "TERMS=$(grep -c '^| TM-' "$C/terminology-and-ownership.md" 2>/dev/null || echo 0)"
echo "UNASSIGNED_OWNERS=$(grep -c 'unassigned' "$C/terminology-and-ownership.md" 2>/dev/null || echo 0)"

echo "### Staleness"
if [ -x "$__dr/bin/dossier-staleness-check.sh" ]; then
  "$__dr/bin/dossier-staleness-check.sh" --output-root "$OUTPUT_ROOT" \
    | grep -E '^(STALENESS_THRESHOLD_DAYS|DOCUMENTS_STALE|DOCUMENTS_UNDATED|OLDEST_VERIFICATION)='
else
  echo "STALENESS_THRESHOLD_DAYS=unknown"
  echo "DOCUMENTS_STALE=unknown"
  echo "DOCUMENTS_UNDATED=unknown"
  echo "OLDEST_VERIFICATION=unknown"
fi

echo "### Verification"
VR="$OUTPUT_ROOT/07-verification/documentation-verification-report.md"
if [ -f "$VR" ]; then
  echo "AUDIT_ROUNDS=$(grep -c '<!-- DOSSIER_AUDIT' "$VR" 2>/dev/null || echo 0)"
  echo "FINDINGS_OPEN=$(grep -cE '\bOpen\b' "$VR" 2>/dev/null || echo 0)"
  echo "LAST_GATE_VERDICT=$(grep -m1 'GATE_VERDICT=' "$VR" 2>/dev/null | cut -d= -f2 || echo none)"
else
  echo "AUDIT_ROUNDS=0"
  echo "LAST_GATE_VERDICT=never-run"
fi

echo "### Refresh cursor"
ST="$OUTPUT_ROOT/.dossier-state.json"
if [ -f "$ST" ]; then
  CURSOR=$(jq -r '.last_documented_sha // empty' "$ST" 2>/dev/null)
  echo "CURSOR=${CURSOR:-none}"
  if [ -n "$CURSOR" ] && git cat-file -e "${CURSOR}^{commit}" 2>/dev/null; then
    echo "COMMITS_BEHIND=$(git rev-list --count "${CURSOR}..HEAD" 2>/dev/null || echo unknown)"
  else
    echo "COMMITS_BEHIND=unknown"
  fi
else
  echo "CURSOR=none"
fi

echo "### Automation"
WF=.github/workflows/dossier-docs-refresh.yml
echo "CI_ENABLED=$("$R" --default true dossier.ci.enabled 2>/dev/null)"
echo "WORKFLOW_PRESENT=$([ -f "$WF" ] && echo true || echo false)"
if [ -f "$WF" ] && [ -x "$__dr/bin/dossier-managed-file.sh" ]; then
  "$__dr/bin/dossier-managed-file.sh" --verify "$WF" 2>/dev/null || echo "MANAGED=unknown"
  echo "WORKFLOW_EXPECTED_VERSION=$("$R" --default unknown dossier.ci.expectedPluginVersion 2>/dev/null)"
fi
echo "TRIGGER_POLICY=$("$R" --default path-filtered dossier.ci.triggerPolicy 2>/dev/null)"
echo "ROLLING_BRANCH=$("$R" --default docs/dossier dossier.ci.rollingBranch 2>/dev/null)"
true
```

## Display

Render the gathered state as a compact dashboard. `--json` emits the same fields as one object. `--path <package-root>` overrides the resolved `project.outputRoot`, reporting on a package other than the one this repository's config points at.

```markdown
## Documentation Status — {PROJECT_NAME}

| | |
|---|---|
| Package | {CANONICAL_FOUND}/23 files · {STATUS_verified} verified, {STATUS_partially_verified} partial, {STATUS_draft} draft |
| Evidence | {EVIDENCE_ROWS} rows · V:{n} C:{n} R:{n} I:{n} U:{n} |
| Open | {OPEN_QUESTIONS} questions · {CONTRADICTIONS} contradictions · {NEEDS_OWNER} need an owner |
| Claims | {CLAIMS_TOTAL} registered · {CLAIMS_PENDING} pending approval |
| Ownership | {UNASSIGNED_OWNERS} unassigned |
| Freshness | {DOCUMENTS_STALE} stale (>{STALENESS_THRESHOLD_DAYS}d) · {DOCUMENTS_UNDATED} undated · oldest {OLDEST_VERIFICATION} |
| Verification | {AUDIT_ROUNDS} rounds · {FINDINGS_OPEN} findings open · gate: {LAST_GATE_VERDICT} |
| Refresh | cursor {CURSOR} · {COMMITS_BEHIND} commits behind |
| Automation | workflow {WORKFLOW_PRESENT} ({MANAGED}) · policy {TRIGGER_POLICY} |

### What to do next
```

Derive the next action from state rather than listing every command. Highest-value first: package absent → `/dossier:init`. Drafts outstanding → `/dossier:baseline`. Never audited → `/dossier:audit`. Findings open → `/dossier:reconcile`. Gate never run → `/dossier:gate`. Commits behind → `/dossier:refresh`. Automation unwired → `/dossier:setup`.

Two signals deserve explicit callouts because they are quiet failures rather than loud ones:

- **`DOCUMENTS_UNDATED > 0`** — a document with no verification date cannot be checked for staleness, so it will never appear in the stale count. It is invisible, not fresh.
- **`MANAGED=dirty`** — the workflow was hand-edited after setup generated it, so re-running `/dossier:setup` will ask before overwriting. Say which file, so the user is not surprised later.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read package files, registers, and settings | 1 | Autonomous, read-only |
| Read git cursor state (`rev-list`, `cat-file`) | 1 | Autonomous, read-only |
| Verify the workflow's managed-file stamp | 1 | Autonomous, read-only |
| Any write | — | **Never.** This command is read-only by construction |
