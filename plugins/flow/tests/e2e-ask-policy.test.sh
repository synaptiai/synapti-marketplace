# shellcheck shell=bash
# End-to-end: autonomous mode is enforced by a hook, not left to the model's
# memory of a setting (#339).
#
# The hook scenarios feed hooks/scripts/ask-policy.sh the PreToolUse payload
# Claude Code sends for an AskUserQuestion call; the preflight scenarios run
# ASK_POLICY_BLOCK from each pipeline command and from /flow:merge, /flow:setup,
# /flow:goal and /flow:resume; the tag scan reads every place in commands/ and
# skills/ that names AskUserQuestion, asks the user or escalates; the store
# scenario runs the skill-loading fence of each command that escalates. The
# artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
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
#      class, so nobody can tell whether autonomous mode may drop it; or the
#      scan sees only lines that name AskUserQuestion, so a place that says
#      "escalate" or "ask the user" without naming the tool (the terminal-goal
#      escalation of /flow:start, whose recommendation is git rm of an
#      achieved goal) goes untagged and is denied as a default
#   A8 the default-taken record the reference names cannot be written
#   A9 a decision or permission place outside the six preflight commands does
#      not say which metadata.source to pass, so under autonomous: true the
#      hook denies it as a default (a terminal goal transition taken for the
#      person)
#   A10 a command that escalates never tells the agent to store the question
#      (bin/flow-question.sh add before asking, answer after), so storing
#      rests on the model choosing to read references/escalation-format.md
#      and /flow:status and /flow:resume show nothing for a run that waits

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
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" && rm -f "$E2E_ACTIVE_PLUGIN/bin/cascade-resolve.sh"
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

# --- every place that asks or escalates carries its class (A7) ---------------
# A place is a line that names AskUserQuestion, tells the agent to ask the
# user (ask the user, ask whether, explicit confirmation) or to escalate
# (escalate, a six-field or Proactive-Autonomy escalation): many of them never
# name the tool, and an untagged one is denied under autonomous: true like a
# default. The frontmatter, a fenced code block, a table row, a heading and an
# entry of a References or Required Skills list are not places; every other
# such line must carry one of the tags.
_untagged() {
  ( cd "$1" && awk '
    FNR == 1 { fence = 0; fm = 0 }
    FNR == 1 && /^---$/ { fm = 1; next }
    fm == 1 { if (/^---$/) fm = 0; next }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^[ \t]*\|/ || /^#/ { next }
    /^[ \t]*- (\[`|`)(references\/|[a-z0-9-]+`)/ { next }
    /\[ask: (decision|permission|default|none)\]/ { next }
    /AskUserQuestion|[Aa]sks? the user|[Aa]sk whether|explicit confirmation|[Ee]scalate([^a-z]|$)|six-field escalation|Proactive-Autonomy escalation/ {
      print FILENAME ":" FNR ":" $0 }' commands/*.md skills/*/SKILL.md ) || true
}
_flow_test_begin "ask-tags"
e2e_new ask-tags
e2e_describe "every line in commands/ and skills/ that names AskUserQuestion, asks the user or escalates carries [ask: decision|permission|default|none] (A7)"
e2e_repo feature/issue-339-e2e
e2e_expect_equal "" "$(_untagged "$E2E_PLUGIN_DIR")" "untagged places"
# The scan can fail: a copy with one tag removed is reported.
e2e_plugin_copy commands/explain.md "$(sed 's/\[ask: decision\] //' "$E2E_PLUGIN_DIR/commands/explain.md")"
e2e_expect_equal 1 "$(_untagged "$E2E_ACTIVE_PLUGIN" | grep -c 'commands/explain.md')" "untagged places in a copy with the explain.md tag removed"
# It also reports places that never name the tool: the terminal-goal
# escalation of /flow:start, the escalation of a finding /flow:review cannot
# settle, and a skill line that says to ask the user.
sed 's/^- \[ask: permission\] \*\*`terminal`\*\*/- **`terminal`**/' "$E2E_PLUGIN_DIR/commands/start.md" > "$E2E_ACTIVE_PLUGIN/commands/start.md"
sed 's/^   - \[ask: decision\] No test or command can reproduce/   - No test or command can reproduce/' "$E2E_PLUGIN_DIR/commands/review.md" > "$E2E_ACTIVE_PLUGIN/commands/review.md"
sed 's/^\[ask: decision\] No agents/No agents/' "$E2E_PLUGIN_DIR/skills/capability-discovery/SKILL.md" > "$E2E_ACTIVE_PLUGIN/skills/capability-discovery/SKILL.md"
printf 'and, in the same copy, the tags removed from the terminal-goal line of commands/start.md, the unsettled-finding line of commands/review.md and the "No agents" line of skills/capability-discovery/SKILL.md\n' | _e2e_art
e2e_expect_equal 1 "$(_untagged "$E2E_ACTIVE_PLUGIN" | grep -c '^commands/start.md:[0-9]*:- \*\*`terminal`\*\*')" "the terminal-goal escalation reported in a copy without its tag"
e2e_expect_equal 1 "$(_untagged "$E2E_ACTIVE_PLUGIN" | grep -c '^commands/review.md:[0-9]*:   - No test or command can reproduce')" "the unsettled-finding escalation reported in a copy without its tag"
e2e_expect_equal 1 "$(_untagged "$E2E_ACTIVE_PLUGIN" | grep -c '^skills/capability-discovery/SKILL.md:[0-9]*:No agents')" "the skill line that asks the user reported in a copy without its tag"
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

# --- every command that escalates says to store the question (A10) -----------
# A command escalates when its prose, outside fenced code, names
# references/escalation-format.md. What it tells the agent is its body plus
# what its skill-loading fence prints (the skills it inlines, where the shared
# rule lives); both together must name the store before the question and the
# answer after.
# _store_missing — set STORE_MISSING to each escalating command of the active
# plugin that does not.
_store_missing() {
  local md text
  STORE_MISSING=""
  for md in $(cd "$E2E_ACTIVE_PLUGIN" && for f in commands/*.md; do
      # awk decides alone: grep -q would close the pipe early, and under
      # pipefail the SIGPIPE awk then gets would drop a long command.
      awk '/^[ \t]*```/ { f = !f; next } !f && /escalation-format\.md/ { hit = 1 } END { exit !hit }' "$f" &&
        printf '%s\n' "$f"
    done); do
    text=$(cat "$E2E_ACTIVE_PLUGIN/$md")
    if grep -q 'flow-load-skills.sh' "$E2E_ACTIVE_PLUGIN/$md"; then
      e2e_run_fence "$E2E_ACTIVE_PLUGIN/$md" 'flow-load-skills.sh'
      text="$text$E2E_OUT"
    fi
    case "$text" in
      *'flow-question.sh add --journal --class'*'answer <id> --choice'*) ;;
      *) STORE_MISSING="$STORE_MISSING$md " ;;
    esac
  done
}
_flow_test_begin "ask-store-instruction"
e2e_new ask-store-instruction
e2e_describe "every command whose prose names references/escalation-format.md tells the agent, in its body or the skills its fence inlines, to store the question with flow-question.sh add before asking and record the answer after (A10)"
e2e_repo feature/issue-340-e2e
_store_missing
e2e_expect_equal "" "$STORE_MISSING" "escalating commands that never say to store the question"
# The check can fail: with the rule taken out of llm-operator-principles, the
# commands that inline it are reported.
e2e_plugin_copy skills/llm-operator-principles/SKILL.md "$(grep -v 'Every escalation is stored' "$E2E_PLUGIN_DIR/skills/llm-operator-principles/SKILL.md")"
_store_missing
for md in start pr address review commit merge; do  # the six that inline llm-operator-principles
  e2e_expect_equal 1 "$(printf '%s\n' $STORE_MISSING | grep -c "^commands/$md.md$")" "commands/$md.md reported without the rule"
done
e2e_expect_clean_edges
