# shellcheck shell=bash
# End-to-end: autonomous mode is enforced by a hook, not left to the model's
# memory of a setting (#339).
#
# The hook scenarios feed hooks/scripts/ask-policy.sh the PreToolUse payload
# Claude Code sends for an AskUserQuestion call; the preflight scenarios run
# ASK_POLICY_BLOCK from each pipeline command and from /flow:merge, /flow:setup,
# /flow:goal and /flow:resume; the tag scan reads every place
# in commands/ and skills/ that names AskUserQuestion. The artifact for each
# scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   A1 with autonomous: true, a question that declares no class reaches the
#      person
#   A2 with autonomous: true, a decision or permission question is denied
#   A3 with autonomous: false (attended), any question is denied
#   A4 settings that cannot be read deny a question (nobody is told, and a
#      person who is there cannot answer)
#   A5 the hook reads the settings of the directory it was started in, not
#      the repository the session works in, so a session in a subdirectory
#      is attended whatever the repository says
#   A6 a pipeline preflight, or the preflight of /flow:merge, /flow:setup,
#      /flow:goal or /flow:resume, does not print the policy, or prints the
#      wrong one
#   A7 a place in commands/ or skills/ that tells the agent to ask carries no
#      class, so nobody can tell whether autonomous mode may drop it
#   A8 the default-taken record the reference names cannot be written
#   A9 a decision or permission place outside the six preflight commands does
#      not say which metadata.source to pass, so under autonomous: true the
#      hook denies it as a default (a terminal goal transition taken for the
#      person)

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

HOOK=hooks/scripts/ask-policy.sh
DENY='"permissionDecision":"deny"'

# _q <source or ""> — an AskUserQuestion payload, with metadata.source when given.
_q() {
  jq -cn --arg s "$1" --arg cwd "${2:-$E2E_REPO}" '{session_id:"e2e-339",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"AskUserQuestion",
    tool_input:({questions:[{question:"Include the two cleanup files?",header:"Files",multiSelect:false,
      options:[{label:"Include (Recommended)",description:"commit them as improve:"},{label:"Exclude",description:"leave them unstaged"}]}]}
      + (if $s == "" then {} else {metadata:{source:$s}} end))}'
}

# _policy_repo <true|false|unset> — the scratch repository, with autonomous set
# in its committed settings unless "unset".
_policy_repo() {
  e2e_repo feature/issue-339-e2e
  if [ "$1" != unset ]; then
    mkdir -p "$E2E_REPO/.claude"
    printf '{"autonomous":%s}\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
  fi
}

# _hook_case <name> <autonomous> <source> <deny|allow> <purpose>
_hook_case() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$5"
  _policy_repo "$2"
  e2e_run_hook "$HOOK" "$(_q "$3")"
  e2e_expect_equal 0 "$E2E_RC" "the hook's exit status"
  case "$4" in
    deny)
      e2e_expect_out "$DENY"
      e2e_expect_out "Take your recommended option"
      e2e_expect_out "--type default-taken" ;;
    allow) e2e_expect_no_out "$DENY" ;;
  esac
  e2e_expect_clean_edges
}

_hook_case ask-auto-default true "" deny "autonomous: true, a question that declares no class (a default): denied, with what to do instead (A1)"
_hook_case ask-auto-other-source true "other:thing" deny "autonomous: true, a source that is not flow's two classes: denied (A1)"
_hook_case ask-auto-decision true flow:decision allow "autonomous: true, a decision question: allowed (A2)"
_hook_case ask-auto-permission true flow:permission allow "autonomous: true, a permission question: allowed (A2)"
_hook_case ask-attended-default false "" allow "autonomous: false, a question that declares no class: allowed (A3)"
_hook_case ask-attended-unset unset "" allow "autonomous not set anywhere (attended by default): allowed (A3)"
_hook_case ask-attended-decision false flow:decision allow "autonomous: false, a decision question: allowed (A3)"

_flow_test_begin "ask-unreadable-settings"
e2e_new ask-unreadable-settings
e2e_describe "autonomous: true, but the policy helper cannot read the settings (cascade-resolve.sh removed from a plugin copy): the question is allowed (A4)"
_policy_repo true
E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
cp -R "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" && rm -f "$E2E_ACTIVE_PLUGIN/bin/cascade-resolve.sh"
printf 'plugin for this scenario: a copy without bin/cascade-resolve.sh\n' | _e2e_art
e2e_run_hook "$HOOK" "$(_q "")"
e2e_expect_equal 0 "$E2E_RC" "the hook's exit status"
e2e_expect_no_out "$DENY"
e2e_expect_clean_edges

_flow_test_begin "ask-auto-subdir"
e2e_new ask-auto-subdir
e2e_describe "autonomous: true in the repository; the session works in sub/deeper (the payload's cwd): a default question is still denied (A5)"
_policy_repo true
mkdir -p "$E2E_REPO/sub/deeper"
e2e_run_hook "$HOOK" "$(_q "" "$E2E_REPO/sub/deeper")"
e2e_expect_out "$DENY"
e2e_expect_clean_edges

# --- the preflight of each pipeline command (A6) ------------------------------
for cmd in start pr address review commit resolve merge setup goal resume; do
  for v in true false; do
    want=attended; [ "$v" = true ] && want=autonomous
    _flow_test_begin "ask-preflight-$cmd-$want"
    e2e_new "ask-preflight-$cmd-$want"
    e2e_describe "/flow:$cmd preflight with autonomous: $v prints ASK_POLICY=$want (A6)"
    _policy_repo "$v"
    e2e_run_block "commands/$cmd.md" ASK_POLICY_BLOCK
    e2e_expect_line "### Ask Policy"
    e2e_expect_line "ASK_POLICY=$want"
    e2e_expect_clean_edges
  done
done

# --- every place that names AskUserQuestion carries its class (A7) -----------
# A frontmatter allowed-tools line, a table row and a heading are not places
# that tell the agent to ask; every other line must carry one of the tags.
_untagged() {
  ( cd "$1" && grep -n "AskUserQuestion" commands/*.md skills/*/SKILL.md ) |
    grep -v "allowed-tools:" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*\|' | grep -vE '^[^:]+:[0-9]+:#' |
    grep -vE '\[ask: (decision|permission|default|none)\]' || true
}
_flow_test_begin "ask-tags"
e2e_new ask-tags
e2e_describe "every line in commands/ and skills/ that names AskUserQuestion carries [ask: decision|permission|default|none] (A7)"
e2e_repo feature/issue-339-e2e
e2e_expect_equal "" "$(_untagged "$E2E_PLUGIN_DIR")" "untagged places"
# The scan can fail: a copy with one tag removed is reported.
e2e_plugin_copy commands/explain.md "$(sed 's/\[ask: decision\] //' "$E2E_PLUGIN_DIR/commands/explain.md")"
e2e_expect_equal 1 "$(_untagged "$E2E_ACTIVE_PLUGIN" | grep -c 'commands/explain.md')" "untagged places in a copy with the explain.md tag removed"
# Every default place says what to do under the autonomous policy.
e2e_expect_equal "" "$(cd "$E2E_PLUGIN_DIR" && grep -n '\[ask: default\]' commands/*.md skills/*/SKILL.md | grep -v '\[ask: none\]' | grep -v 'ASK_POLICY=autonomous' | grep -v '^commands/[a-z]*.md:[0-9]*:Which questions reach the person' || true)" "default places without their autonomous instruction"
e2e_expect_clean_edges

# --- every decision and permission place names its metadata.source (A9) -----
# A line whose first tag is [ask: decision] names flow:decision, one whose
# first tag is [ask: permission] names flow:permission, unless its file has the
# preflight paragraph that names both for every place below it.
_unsourced() {
  ( cd "$1" && grep -n '\[ask: \(decision\|permission\)\]' commands/*.md skills/*/SKILL.md ) |
    while IFS= read -r hit; do
      file=${hit%%:*}; text=${hit#*:}; text=${text#*:}
      class=$(printf '%s' "$text" | grep -o '\[ask: [a-z]*\]' | head -1 | sed 's/\[ask: \(.*\)\]/\1/')
      case "$class" in decision|permission) ;; *) continue ;; esac
      printf '%s' "$text" | grep -q "flow:$class" && continue
      grep -q '^Which questions reach the person .*{"source": "flow:decision"}.*{"source": "flow:permission"}' "$1/$file" && continue
      printf '%s\n' "$hit"
    done
}
_flow_test_begin "ask-sources"
e2e_new ask-sources
e2e_describe "every [ask: decision] and [ask: permission] place in commands/ and skills/ names the metadata.source to pass, on its line or in its command's preflight paragraph (A9)"
e2e_repo feature/issue-339-e2e
e2e_expect_equal "" "$(_unsourced "$E2E_PLUGIN_DIR")" "decision and permission places without their metadata.source"
# The scan can fail: a copy of goal.md without its sources, and a copy of
# start.md without its preflight paragraph, are reported.
e2e_plugin_copy commands/goal.md "$(sed 's/flow:permission/flow:other/g; s/flow:decision/flow:other/g' "$E2E_PLUGIN_DIR/commands/goal.md")"
e2e_expect_equal 1 "$([ "$(_unsourced "$E2E_ACTIVE_PLUGIN" | grep -c '^commands/goal.md:')" -ge 4 ] && echo 1 || echo 0)" "goal.md places reported in a copy without their sources"
grep -v '^Which questions reach the person' "$E2E_PLUGIN_DIR/commands/start.md" > "$E2E_ACTIVE_PLUGIN/commands/start.md"
printf 'and commands/start.md without its "Which questions reach the person" paragraph\n' | _e2e_art
e2e_expect_equal 1 "$([ "$(_unsourced "$E2E_ACTIVE_PLUGIN" | grep -c '^commands/start.md:')" -ge 4 ] && echo 1 || echo 0)" "start.md places reported in a copy without its preflight paragraph"
e2e_expect_clean_edges

# --- the default-taken record (A8) -------------------------------------------
_flow_test_begin "ask-default-taken-record"
e2e_new ask-default-taken-record
e2e_describe "the journal record references/ask-policy.md names is written"
_policy_repo true
e2e_run_bin bin/journal-record.sh --issue 339 --type default-taken \
  --metadata site="commit: Phase 2" --metadata question="Include the two cleanup files?" --metadata choice="Include"
e2e_expect_equal 0 "$E2E_RC" "journal-record.sh exit status"
e2e_expect_file_has .decisions/issue-339.md "type: default-taken"
e2e_expect_file_has .decisions/issue-339.md "choice: Include"
e2e_expect_clean_edges
