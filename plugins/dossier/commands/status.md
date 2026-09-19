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
[ -x "$__dr/bin/dossier-resolve-config.sh" ] || __dr=$({ printf '%s\n' plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; printf '%s\n' "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-resolve-config.sh" ] && { printf '%s\n' "${__p%/}"; break; }; done)

printf '%s\n' "### Mode"
printf '%s\n' "STATUS_MODE=$MODE"

printf '%s\n' "### Plugin"
if [ ! -x "$__dr/bin/dossier-resolve-config.sh" ] || [ ! -x "$__dr/bin/dossier-staleness-check.sh" ]; then
  printf '%s\n' "STATUS_STATE=blocked"
  printf '%s\n' "STATUS_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi
R="$__dr/bin/dossier-resolve-config.sh"
printf '%s\n' "PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$__dr/.claude-plugin/plugin.json" 2>/dev/null)"

printf '%s\n' "### Package"
OUTPUT_ROOT=$("$R" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
printf '%s\n' "OUTPUT_ROOT=$OUTPUT_ROOT"
if [ ! -d "$OUTPUT_ROOT/00-control" ]; then
  printf '%s\n' "PACKAGE_STATE=absent"
  printf '%s\n' "PACKAGE_HINT=run /dossier:init to scaffold, then /dossier:baseline to draft"
  true; exit 0
fi
printf '%s\n' "PACKAGE_STATE=present"
printf '%s\n' "PROJECT_NAME=$("$R" --default '(unset)' dossier.project.name 2>/dev/null)"
printf '%s\n' "DELIVERY_MODE=$("$R" --default full dossier.engagement.deliveryMode 2>/dev/null)"
printf '%s\n' "DISCLOSURE_POLICY=$("$R" --default internal-only dossier.disclosure.policy 2>/dev/null)"

printf '%s\n' "### Coverage"
EXPECTED=23
FOUND=$(find "$OUTPUT_ROOT" -mindepth 2 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
printf '%s\n' "CANONICAL_EXPECTED=$EXPECTED"
printf '%s\n' "CANONICAL_FOUND=$FOUND"
for d in 00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification; do
  printf '%s\n' "DIR_${d}=$(find "$OUTPUT_ROOT/$d" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
done

printf '%s\n' "### Document status"
for s in verified "partially verified" draft "N/A"; do
  n=$(grep -rl "^status: $s" "$OUTPUT_ROOT" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
  printf '%s\n' "STATUS_$(printf '%s' "$s" | tr ' ' '_')=$n"
done

printf '%s\n' "### Registers"
C="$OUTPUT_ROOT/00-control"
printf '%s\n' "EVIDENCE_ROWS=$(grep -c '^| EV-' "$C/evidence-ledger.md" 2>/dev/null || printf '%s\n' 0)"
for st in V C R I U; do
  printf '%s\n' "EVIDENCE_STATE_${st}=$(awk -F'|' '/^\| EV-/{gsub(/ /,"",$4); if($4=="'"$st"'") n++} END{print n+0}' "$C/evidence-ledger.md" 2>/dev/null || printf '%s\n' 0)"
done
printf '%s\n' "OPEN_QUESTIONS=$(grep -c '^| AQ-' "$C/assumptions-questions-and-contradictions.md" 2>/dev/null || printf '%s\n' 0)"
printf '%s\n' "CONTRADICTIONS=$(grep -c '^| CT-' "$C/assumptions-questions-and-contradictions.md" 2>/dev/null || printf '%s\n' 0)"
printf '%s\n' "NEEDS_OWNER=$(grep -c 'needs-owner' "$C/assumptions-questions-and-contradictions.md" 2>/dev/null || printf '%s\n' 0)"
printf '%s\n' "CLAIMS_TOTAL=$(grep -c '^| CL-' "$C/claim-and-disclosure-register.md" 2>/dev/null || printf '%s\n' 0)"
printf '%s\n' "CLAIMS_PENDING=$(grep -c '^| CL-.*| *pending *|' "$C/claim-and-disclosure-register.md" 2>/dev/null || printf '%s\n' 0)"
printf '%s\n' "TERMS=$(grep -c '^| TM-' "$C/terminology-and-ownership.md" 2>/dev/null || printf '%s\n' 0)"
printf '%s\n' "UNASSIGNED_OWNERS=$(grep -c 'unassigned' "$C/terminology-and-ownership.md" 2>/dev/null || printf '%s\n' 0)"

printf '%s\n' "### Staleness"
if [ -x "$__dr/bin/dossier-staleness-check.sh" ]; then
  "$__dr/bin/dossier-staleness-check.sh" --output-root "$OUTPUT_ROOT" \
    | grep -E '^(STALENESS_THRESHOLD_DAYS|DOCUMENTS_STALE|DOCUMENTS_UNDATED|OLDEST_VERIFICATION)='
else
  printf '%s\n' "STALENESS_THRESHOLD_DAYS=unknown"
  printf '%s\n' "DOCUMENTS_STALE=unknown"
  printf '%s\n' "DOCUMENTS_UNDATED=unknown"
  printf '%s\n' "OLDEST_VERIFICATION=unknown"
fi

printf '%s\n' "### Verification"
VR="$OUTPUT_ROOT/07-verification/documentation-verification-report.md"
if [ -f "$VR" ]; then
  # A verification report exists, so this package has been through the
  # verification path at least once. Whether the machine-readable markers are
  # present is a separate question: a report written before those markers
  # existed, or by hand, carries its rounds and its gate result in prose only.
  # Reporting 0 and never-run for such a report is a FALSE NEGATIVE — it was
  # doing exactly that for a package whose report records three rounds and a
  # gate result of FAIL, which reads as "nothing has gone wrong yet" when the
  # opposite is true. Unparsed is reported as unknown, never as zero.
  VR_ROUNDS=$(grep -c '<!-- DOSSIER_AUDIT' "$VR" 2>/dev/null || printf '%s\n' 0)
  if [ "${VR_ROUNDS:-0}" -gt 0 ] 2>/dev/null; then
    printf '%s\n' "AUDIT_ROUNDS=$VR_ROUNDS"
  else
    printf '%s\n' "AUDIT_ROUNDS=unknown"
    printf '%s\n' "AUDIT_ROUNDS_REASON=report present but carries no DOSSIER_AUDIT markers"
  fi
  printf '%s\n' "FINDINGS_OPEN=$(grep -cE '\bOpen\b' "$VR" 2>/dev/null || printf '%s\n' 0)"
  VR_VERDICT=$(grep -m1 'GATE_VERDICT=' "$VR" 2>/dev/null | cut -d= -f2)
  printf '%s\n' "LAST_GATE_VERDICT=${VR_VERDICT:-unknown}"
else
  printf '%s\n' "AUDIT_ROUNDS=0"
  printf '%s\n' "FINDINGS_OPEN=0"
  printf '%s\n' "LAST_GATE_VERDICT=never-run"
fi

printf '%s\n' "### Refresh cursor"
ST="$OUTPUT_ROOT/.dossier-state.json"
if [ -f "$ST" ]; then
  CURSOR=$(jq -r '.last_documented_sha // empty' "$ST" 2>/dev/null)
  printf '%s\n' "CURSOR=${CURSOR:-none}"
  if [ -n "$CURSOR" ] && git cat-file -e "${CURSOR}^{commit}" 2>/dev/null; then
    printf '%s\n' "COMMITS_BEHIND=$(git rev-list --count "${CURSOR}..HEAD" 2>/dev/null || printf '%s\n' unknown)"
  else
    printf '%s\n' "COMMITS_BEHIND=unknown"
  fi
else
  printf '%s\n' "CURSOR=none"
fi

printf '%s\n' "### Automation"
WF=.github/workflows/dossier-docs-refresh.yml
printf '%s\n' "CI_ENABLED=$("$R" --default true dossier.ci.enabled 2>/dev/null)"
printf '%s\n' "WORKFLOW_PRESENT=$([ -f "$WF" ] && printf '%s\n' true || printf '%s\n' false)"
if [ -f "$WF" ] && [ -x "$__dr/bin/dossier-managed-file.sh" ]; then
  "$__dr/bin/dossier-managed-file.sh" --verify "$WF" 2>/dev/null || printf '%s\n' "MANAGED=unknown"
  printf '%s\n' "WORKFLOW_EXPECTED_VERSION=$("$R" --default unknown dossier.ci.expectedPluginVersion 2>/dev/null)"
fi
printf '%s\n' "TRIGGER_POLICY=$("$R" --default path-filtered dossier.ci.triggerPolicy 2>/dev/null)"
printf '%s\n' "ROLLING_BRANCH=$("$R" --default docs/dossier dossier.ci.rollingBranch 2>/dev/null)"
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
- **`AUDIT_ROUNDS=unknown` or `LAST_GATE_VERDICT=unknown`** — a verification report exists but carries no machine-readable marker, so this command cannot say how many rounds ran or how the gate ruled. Say "unknown", never "never audited": the report may record a FAILED gate, and reporting that as never-run inverts its meaning. Point the reader at the report itself.
- **`MANAGED=dirty`** — the workflow was hand-edited after setup generated it, so re-running `/dossier:setup` will ask before overwriting. Say which file, so the user is not surprised later.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read package files, registers, and settings | 1 | Autonomous, read-only |
| Read git cursor state (`rev-list`, `cat-file`) | 1 | Autonomous, read-only |
| Verify the workflow's managed-file stamp | 1 | Autonomous, read-only |
| Any write | — | **Never.** This command is read-only by construction |
