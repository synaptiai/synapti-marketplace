---
description: "Inspect and validate FlowWorkflow YAMLs at plugins/flow/workflows/. Subcommands: list, inspect <id>, validate <id>, graph <id>. Use /flow:workflow <subcommand>."
allowed-tools: Bash, Read, Skill
---

# /flow:workflow — FlowWorkflow inspection and validation

Each `/flow:*` command has a machine-readable process contract at `plugins/flow/workflows/<id>.workflow.yaml` (and optionally a project-local override at `.flow/workflows/<id>.workflow.yaml`). This command lets you list available workflows, inspect their phase structure, validate their integrity, and render a textual graph.

The command markdown remains Claude's execution manual; this YAML is the inspectable contract that CI can validate.

## Required Skills

- `workflow-validation` — schema + cross-reference checks (used by `validate` subcommand).

## Pre-flight

```bash
ENABLED=$("${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh" \
  --default "false" '.flow.workflows.enabled // empty')
if [ "$ENABLED" != "true" ]; then
  echo "flow.workflows.enabled is false — /flow:workflow is opt-in." >&2
  echo "Enable in .claude/settings.flow.local.json: { \"flow\": { \"workflows\": { \"enabled\": true } } }"
  exit 0
fi
```

## Subcommands

### `/flow:workflow list`

List all plugin-shipped workflows + any project-local overrides:

```bash
echo "Plugin-shipped workflows:"
for f in "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/workflows/"*.workflow.yaml; do
  ID=$(basename "$f" .workflow.yaml)
  CMD=$(python3 -c "import yaml; print(yaml.safe_load(open('$f'))['metadata']['command'])" 2>/dev/null)
  DESC=$(python3 -c "import yaml; print(yaml.safe_load(open('$f'))['metadata']['description'])" 2>/dev/null)
  printf '  %-15s %-20s %s\n' "$ID" "$CMD" "$DESC"
done

if [ -d .flow/workflows ]; then
  echo
  echo "Project-local overrides:"
  for f in .flow/workflows/*.workflow.yaml; do
    [ -f "$f" ] || continue
    ID=$(basename "$f" .workflow.yaml)
    echo "  $ID (overrides plugin default)"
  done
fi
```

### `/flow:workflow inspect <id>`

Dump the workflow's frontmatter + phase structure:

```bash
ID="${ARGUMENTS}"
WF_PATH="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/workflows/${ID}.workflow.yaml"
[ -f ".flow/workflows/${ID}.workflow.yaml" ] && WF_PATH=".flow/workflows/${ID}.workflow.yaml"

if [ ! -f "$WF_PATH" ]; then
  echo "Workflow not found: $ID" >&2
  exit 1
fi

cat "$WF_PATH"
```

### `/flow:workflow validate <id>`

Invoke `Skill(workflow-validation)` with the workflow id. The skill performs:
- Schema validation
- Required-skills + required-agents existence checks
- Activity-level skill/agent existence checks
- Tier 3 confirm-gating verification
- No-native-slash check
- Completion gate dependency check

Print the structured JSON report; exit per the skill's exit code convention.

### `/flow:workflow graph <id>`

Render a textual graph of the workflow's phase structure:

```bash
ID="${ARGUMENTS}"
WF_PATH="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/workflows/${ID}.workflow.yaml"
[ -f ".flow/workflows/${ID}.workflow.yaml" ] && WF_PATH=".flow/workflows/${ID}.workflow.yaml"

python3 - "$WF_PATH" <<'PYEOF'
import sys, yaml
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    wf = yaml.safe_load(f)

print(f"Workflow: {wf['metadata']['id']}")
print(f"Command:  {wf['metadata']['command']}")
print(f"Version:  {wf['metadata']['version']}")
print()
print("PHASES")
print("------")
for i, phase in enumerate(wf['phases'], start=1):
    phase_id = phase['id']
    phase_type = phase['type']
    gate = phase.get('gate', '')
    gate_marker = f" [{gate}]" if gate else ""
    print(f"  {i}. {phase_id} ({phase_type}){gate_marker}")
    for j, act in enumerate(phase['activities'], start=1):
        act_id = act['id']
        act_type = act.get('type', 'task')
        skill = f" skill={act['skill']}" if 'skill' in act else ""
        agent = f" agent={act['agent']}" if 'agent' in act else ""
        cmd = f" cmd={act['command']}" if 'command' in act else ""
        print(f"     {i}.{j} {act_id} ({act_type}{skill}{agent}{cmd})")
print()
print("COMPLETION GATE")
print("---------------")
for req in wf['completion_gate']['requires']:
    print(f"  - {req}")
print()
print("TIER CLASSIFICATION")
print("-------------------")
for action, tier in wf.get('tier_classification', {}).items():
    print(f"  {action:25s} {tier}")
PYEOF
```

## Architectural notes

- **Workflows are data, not code.** They describe the structure of the `/flow:*` commands; the commands themselves remain Claude's execution manuals. Changing a workflow YAML changes the contract validation but does NOT change command behavior.
- **Project-local overrides** under `.flow/workflows/` are committed by default (per the gitignore policy in `references/flow-runtime-state.md`). Teams that want truly local overrides can rename to `*.local.workflow.yaml` and add to their personal gitignore.
- **No native-slash dependencies allowed.** `/flow:workflow validate` rejects workflows that reference `/goal`, `/loop`, `/schedule`, or `/routine` as invoked commands. This is non-negotiable per the v3 non-goals.

## Critical references

- `plugins/flow/skills/workflow-validation/SKILL.md` — schema + cross-reference checks.
- `plugins/flow/schemas/v1/workflow.schema.json` — workflow document schema.
- `plugins/flow/workflows/*.workflow.yaml` — plugin-shipped workflow definitions.
- `plugins/flow/references/flow-workflows.md` — user-facing workflows documentation.
