# shellcheck shell=bash
# End-to-end: shell commands that skills hand to the session, run the way the
# session runs them, in a scratch repository with flow installed outside it.
#
# Some of these commands are bash fences; others are written inline in a step
# (`[ -f ... ]`, a grep). Both are code, so each is extracted from the shipped
# skill and run. Each scenario runs under zsh (when installed) and bash, and
# writes one artifact to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways each part can be wrong, written down before the scenarios:
#
# Paths into the plugin (workflow-validation steps 2-3, trigger-policy steps
# 1 and 7, capability-discovery's plugin rows)
#   R1 the command names a repository-relative plugins/flow path, which exists
#      only in the marketplace repository, so in a project every skill, agent
#      and workflow reads as missing, or the trigger schema cannot be opened
#   R2 the command finds a name that the plugin does not ship
#   R3 the trigger schema check exits 0 because no schema was read
#
# grep --include (brainstorming step 2, architecture-patterns coupling check)
#   G1 one --include holding a brace list, which grep does not expand, so no
#      file matches and the search reports nothing
#   G2 the search lists files of other types

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

SKILLS_DIR="$E2E_PLUGIN_DIR/skills"

# _install_flow — the plugin under test installed as a marketplace cache entry
# under the scenario's HOME, the way Claude Code installs it in a project.
# Sets FLOW_INSTALL to the root the resolver should find.
_install_flow() {
  FLOW_INSTALL="$E2E_HOME/.claude/plugins/cache/synapti-marketplace/flow/9.9.9"
  mkdir -p "$(dirname "$FLOW_INSTALL")"
  ln -s "$E2E_ACTIVE_PLUGIN" "$FLOW_INSTALL"
}

# _run_text <label> <shell text> [NAME=value ...] — run text taken from a skill
# as the harness runs a fence: in the scratch repository, under each shell.
_run_text() {
  local label="$1"
  printf '%s\n' "$2" > "$E2E_DIR/fence.sh.raw"
  shift 2
  _e2e_run_code "$label" "" "$@"
}

# _inline <file> <python regex with one group> — the first match of the group
# in the file: a command written inline in a skill step.
_inline() {
  python3 -c '
import re, sys
m = re.search(sys.argv[2], open(sys.argv[1], encoding="utf-8").read())
sys.stdout.write(m.group(1) if m else "")
' "$1" "$2"
}

# The run sees no CLAUDE_PLUGIN_ROOT: the session that follows a skill runs the
# command through its own Bash tool, where it is not set.
NO_ROOT="CLAUDE_PLUGIN_ROOT="

_flow_test_begin "workflow-validation: required skills and agents are checked in the installed plugin (R1, R2)"
e2e_new workflow-validation-refs
e2e_describe "a project with no plugins/flow directory; flow is installed under HOME. A skill and an agent the plugin ships are found; names it does not ship are not"
e2e_repo feature/e2e
_install_flow
SKILL_CHECK=$(_inline "$SKILLS_DIR/workflow-validation/SKILL.md" '2\. \*\*Required skills\*\*[^\n]*?`(\[ -f "[^`]*/skills/\$\{skill_name\}/SKILL\.md" \])`')
AGENT_CHECK=$(_inline "$SKILLS_DIR/workflow-validation/SKILL.md" '3\. \*\*Required agents\*\*[^\n]*?`(\[ -f "[^`]*/agents/\$\{agent_name\}\.md" \])`')
e2e_expect_equal yes "$([ -n "$SKILL_CHECK" ] && [ -n "$AGENT_CHECK" ] && echo yes || echo no)" "whether both checks were extracted"
_run_text "skills/workflow-validation/SKILL.md (steps 2 and 3)" "$(cat <<EOF
for skill_name in tdd-patterns no-such-skill; do
  if $SKILL_CHECK; then printf 'SKILL %s=found\n' "\$skill_name"; else printf 'SKILL %s=missing\n' "\$skill_name"; fi
done
for agent_name in code-reviewer no-such-agent; do
  if $AGENT_CHECK; then printf 'AGENT %s=found\n' "\$agent_name"; else printf 'AGENT %s=missing\n' "\$agent_name"; fi
done
EOF
)" "$NO_ROOT" "HOME=$E2E_HOME"
e2e_expect_line "SKILL tdd-patterns=found"
e2e_expect_line "SKILL no-such-skill=missing"
e2e_expect_line "AGENT code-reviewer=found"
e2e_expect_line "AGENT no-such-agent=missing"
e2e_expect_clean_edges

_flow_test_begin "trigger-policy step 7: a target workflow the plugin ships is found in the installed plugin (R1, R2)"
e2e_new trigger-policy-target-workflow
e2e_describe "a project with no plugins/flow directory; flow is installed under HOME. address-pr ships with the plugin; no-such-workflow does not"
e2e_repo feature/e2e
_install_flow
PLUGIN_PATH_SET=$(_inline "$SKILLS_DIR/trigger-policy/SKILL.md" '`(PLUGIN_PATH="[^`]*/workflows/\$\{WF\}\.workflow\.yaml")`')
e2e_expect_equal yes "$([ -n "$PLUGIN_PATH_SET" ] && echo yes || echo no)" "whether PLUGIN_PATH was extracted"
_run_text "skills/trigger-policy/SKILL.md (step 7)" "$(cat <<EOF
for WF in address-pr no-such-workflow; do
  $PLUGIN_PATH_SET
  if [ -f "\$PLUGIN_PATH" ]; then printf '%s=found\n' "\$WF"; else printf '%s=missing\n' "\$WF"; fi
done
EOF
)" "$NO_ROOT" "HOME=$E2E_HOME"
e2e_expect_line "address-pr=found"
e2e_expect_line "no-such-workflow=missing"
e2e_expect_clean_edges

if python3 -c 'import yaml, jsonschema' >/dev/null 2>&1; then
  # The step 1 fence is indented under its list item: take it out and dedent.
  _trigger_schema_fence() {
    awk '/^   ```bash$/{f=1;next} f&&/^   ```$/{exit} f{sub(/^   /,""); print}' "$SKILLS_DIR/trigger-policy/SKILL.md"
  }

  _flow_test_begin "trigger-policy step 1: the trigger schema is read from the installed plugin (R1, R3)"
  e2e_new trigger-policy-schema
  e2e_describe "a project with no plugins/flow directory; flow is installed under HOME. A valid trigger passes the schema check; one missing its required fields fails it"
  e2e_repo feature/e2e
  _install_flow
  cp "$REPO_ROOT/plugins/flow/tests/fixtures/trigger/valid.yaml" "$E2E_REPO/valid.trigger.yaml"
  cp "$REPO_ROOT/plugins/flow/tests/fixtures/trigger/missing-required.yaml" "$E2E_REPO/bad.trigger.yaml"
  e2e_expect_equal yes "$(_trigger_schema_fence | grep -q 'trigger.schema.json' && echo yes || echo no)" "whether the schema fence was extracted"
  _run_text "skills/trigger-policy/SKILL.md (step 1 fence)" "$(_trigger_schema_fence)" "$NO_ROOT" "HOME=$E2E_HOME" "TRIGGER_YAML=valid.trigger.yaml"
  e2e_expect_equal 0 "$E2E_RC" "the exit status for a valid trigger"
  e2e_expect_no_out "SCHEMA_ERROR"
  _run_text "skills/trigger-policy/SKILL.md (step 1 fence)" "$(_trigger_schema_fence)" "$NO_ROOT" "HOME=$E2E_HOME" "TRIGGER_YAML=bad.trigger.yaml"
  e2e_expect_equal 2 "$E2E_RC" "the exit status for a trigger missing required fields"
  e2e_expect_out "SCHEMA_ERROR="
  e2e_expect_clean_edges
else
  _flow_test_begin "trigger-policy step 1: the trigger schema is read from the installed plugin (R1, R3)"
  _flow_assert_pass "SKIP: PyYAML or jsonschema not installed"
fi

_flow_test_begin "capability-discovery: the plugin root is the installed plugin (R1)"
e2e_new capability-discovery-root
e2e_describe "a project with no plugins/ directory; flow is installed under HOME. The block prints that install as FLOW_ROOT"
e2e_repo feature/e2e
_install_flow
e2e_run_fence "$NO_ROOT" "HOME=$E2E_HOME" "$SKILLS_DIR/capability-discovery/SKILL.md" 'FLOW_ROOT='
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "FLOW_ROOT=$FLOW_INSTALL"
e2e_expect_equal yes "$([ -f "$FLOW_INSTALL/agents/code-reviewer.md" ] && echo yes || echo no)" "whether the plugin's agents are under that root"
e2e_expect_clean_edges

# _grep_tree — a TypeScript and a Python file that match, and a Markdown file
# that matches too but is not source.
_grep_tree() {
  mkdir -p "$E2E_REPO/src" "$E2E_REPO/docs"
  printf 'import { a } from "./a";\n// relevant_pattern\n' > "$E2E_REPO/src/search.ts"
  printf 'import os\n# relevant_pattern\n' > "$E2E_REPO/src/tool.py"
  printf 'import notes and relevant_pattern\n' > "$E2E_REPO/docs/notes.md"
}

_flow_test_begin "brainstorming step 2: the pattern search lists matching source files (G1, G2)"
e2e_new brainstorming-grep
e2e_describe "src/search.ts and src/tool.py contain relevant_pattern; docs/notes.md does too but is not source"
e2e_repo feature/e2e
_grep_tree
e2e_run_fence "$SKILLS_DIR/brainstorming/SKILL.md" 'relevant_pattern'
e2e_expect_line "./src/search.ts"
e2e_expect_line "./src/tool.py"
e2e_expect_no_out "notes.md"
e2e_expect_clean_edges

_flow_test_begin "architecture-patterns: the import search lists the source files that import (G1, G2)"
e2e_new architecture-patterns-grep
e2e_describe "src/search.ts and src/tool.py import; docs/notes.md says import but is not source"
e2e_repo feature/e2e
_grep_tree
IMPORT_GREP=$(_inline "$SKILLS_DIR/architecture-patterns/SKILL.md" 'Check actual imports \(`(grep [^`]*)`')
e2e_expect_equal yes "$([ -n "$IMPORT_GREP" ] && echo yes || echo no)" "whether the import search was extracted"
_run_text "skills/architecture-patterns/SKILL.md (coupling check)" "$IMPORT_GREP"
e2e_expect_line "./src/search.ts"
e2e_expect_line "./src/tool.py"
e2e_expect_no_out "notes.md"
e2e_expect_clean_edges
