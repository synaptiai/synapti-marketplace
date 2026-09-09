# Tests for hooks/scripts/ask-issue-create.sh (PreToolUse, matcher Bash).
#
# Contract under test: when the command runs `gh issue create` in command
# position AND minimalScope is false AND an active FlowGoal owns the current
# branch, the hook prints {"hookSpecificOutput":{..."permissionDecision":"ask"
# ...}} whose reason names the goal id, and exits 0. In every other case it
# exits 0 with empty stdout (a one-line stderr note when the goal helper
# cannot decide). It never denies.
#
# Each scenario runs the hook from inside a purpose-built git repo carrying
# .flow/goals/<id>.goal.yaml, with HOME pointed at an empty directory so a
# user-global settings.flow.json cannot leak into the cascade, and
# CLAUDE_PLUGIN_ROOT pointed at the plugin so its default settings.json
# (minimalScope: false) is the bottom of the cascade.
#
# Prereqs: jq, git, python3 + PyYAML (flow-active-goal.sh). SKIPS otherwise.

for tool in jq git python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    _flow_test_begin "$tool prerequisite"; _flow_assert_pass "SKIP: $tool not installed"; return 0
  fi
done
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"; _flow_assert_pass "SKIP: PyYAML not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/ask-issue-create.sh"
PLUGIN="$REPO_ROOT/plugins/flow"
FIXTURE="$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml"
BASH_BIN=$(command -v bash)

AIC_CLEANUP=()
_aic_cleanup() { local p; for p in "${AIC_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _aic_cleanup EXIT

# Fresh git repo on branch `main` with one commit, an empty HOME, and a goal
# file derived from the valid fixture. Args: <status> [<branch-in-goal>].
# scope.branch defaults to the repo's current branch. Prints the repo path.
_new_goal_repo() {
  local status="$1" goal_branch="${2:-}" d cur
  d=$(mktemp -d -t flow-aic.XXXXXX); AIC_CLEANUP+=("$d")
  ( cd "$d" \
    && git init -q -b main \
    && git config user.email t@t.test && git config user.name tester \
    && echo base > base.txt && git add base.txt && git commit -qm m0 ) >/dev/null 2>&1
  mkdir -p "$d/home" "$d/.flow/goals"
  cur=$(cd "$d" && git branch --show-current)
  [ -z "$goal_branch" ] && goal_branch="$cur"
  sed -E \
    -e "s|^  branch: .*|  branch: ${goal_branch}|" \
    -e "s|^  status: active$|  status: ${status}|" \
    "$FIXTURE" > "$d/.flow/goals/issue-42.goal.yaml"
  printf '%s' "$d"
}

# Run the hook from inside <repo> with <command>. Sets AIC_OUT (stdout),
# AIC_ERR (stderr), AIC_RC. Extra env assignments may follow as VAR=value.
_run_hook() {
  local repo="$1" cmd="$2" json errf; shift 2
  json=$(printf '%s' "$cmd" | jq -Rs .)
  errf=$(mktemp -t flow-aic-err.XXXXXX); AIC_CLEANUP+=("$errf")
  AIC_OUT=$( cd "$repo" && export HOME="$repo/home" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    && printf '{"tool_input":{"command":%s}}' "$json" | env "$@" "$BASH_BIN" "$HOOK" 2>"$errf" )
  AIC_RC=$?
  AIC_ERR=$(cat "$errf")
}

# (a) active goal on this branch + gh issue create → ask, reason names the goal
_flow_test_begin "gh issue create during an active goal asks and names the goal"
R=$(_new_goal_repo active)
_run_hook "$R" "gh issue create --title x"
assert_exit 0 "$AIC_RC" "hook exits 0 (decision is carried in JSON, not the exit code)"
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "permissionDecision is ask"
assert_equal "PreToolUse" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.hookEventName')" "hookEventName is PreToolUse"
REASON=$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
assert_contains "issue-42" "$REASON" "reason names the goal id"
assert_contains "active FlowGoal" "$REASON" "reason says a FlowGoal is active"
assert_contains "fix findings in this PR rather than file follow-up issues" "$REASON" "reason states flow's rule"
assert_contains "genuine product decision" "$REASON" "reason gives the approve condition"
assert_contains "deny and fix it here" "$REASON" "reason gives the deny instruction"
assert_contains "minimalScope: true" "$REASON" "reason says how to stop the prompt"
assert_equal "" "$AIC_ERR" "no stderr on the happy path"

# compound: gh issue create after && / ; / | is still command position
_flow_test_begin "gh issue create in a compound command asks"
_run_hook "$R" "cd /tmp && gh issue create -t x"
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "after && asks"
_run_hook "$R" "git push; gh issue create -t x"
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "after ; asks"
_run_hook "$R" 'GH_TOKEN=x gh issue create -t x'
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "after a VAR=value prefix asks"
_run_hook "$R" '/usr/bin/gh issue create -t x'
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "path-qualified gh asks"

# (b) other gh commands → silent
_flow_test_begin "other gh commands are not prompted"
_run_hook "$R" "gh issue list"
assert_exit 0 "$AIC_RC" "gh issue list exits 0"
assert_equal "" "$AIC_OUT" "gh issue list has no stdout"
_run_hook "$R" "gh pr create --title x"
assert_equal "" "$AIC_OUT" "gh pr create has no stdout"
_run_hook "$R" "gh issue comment 1 --body x"
assert_equal "" "$AIC_OUT" "gh issue comment has no stdout"

# (c) the words in a non-command position → silent (documented decision:
# `echo gh issue create` prints text; it does not file an issue)
_flow_test_begin "gh issue create outside command position is not prompted"
_run_hook "$R" "echo gh issue create"
assert_exit 0 "$AIC_RC" "echo ... exits 0"
assert_equal "" "$AIC_OUT" "echo gh issue create has no stdout"
_run_hook "$R" "npm run gh issue create"
assert_equal "" "$AIC_OUT" "argument to another command has no stdout"

# (f) inside quotes → silent (a quoted string cannot be in command position).
# Quoted spans are stripped BEFORE the split on `;`/`|`/`&`, so a separator
# inside quotes never opens a fresh "command position" (PR #163 review: the
# old order turned `-m "fix; gh issue create later"` into a prompting segment).
_flow_test_begin "gh issue create inside a quoted argument is not prompted"
_run_hook "$R" 'git commit -m "gh issue create later"'
assert_exit 0 "$AIC_RC" "git commit exits 0"
assert_equal "" "$AIC_OUT" "quoted text has no stdout"
_run_hook "$R" 'git commit -m "fix; gh issue create later"'
assert_exit 0 "$AIC_RC" "git commit with a ; inside the quoted message exits 0"
assert_equal "" "$AIC_OUT" "a ; inside quotes does not create command position"
_run_hook "$R" 'echo "gh issue create"'
assert_equal "" "$AIC_OUT" "double-quoted echo argument has no stdout"
_run_hook "$R" "echo 'gh issue create'"
assert_equal "" "$AIC_OUT" "single-quoted echo argument has no stdout"
_run_hook "$R" "git commit -m \"it's; gh issue create\""
assert_equal "" "$AIC_OUT" "an apostrophe inside double quotes does not break the strip"

# a comment is not a command
_flow_test_begin "gh issue create in a comment is not prompted"
_run_hook "$R" '# gh issue create'
assert_exit 0 "$AIC_RC" "comment-only command exits 0"
assert_equal "" "$AIC_OUT" "comment-only command has no stdout"
_run_hook "$R" 'echo done # gh issue create'
assert_equal "" "$AIC_OUT" "trailing comment has no stdout"

# a genuine gh issue create keeps prompting after its quoted arguments are stripped
_flow_test_begin "gh issue create with a quoted argument containing a separator still asks"
_run_hook "$R" 'gh issue create --title "fix; later"'
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "quoted ; in --title still asks"
_run_hook "$R" "gh issue create --title 'a | b' --body \"c && d\""
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "quoted | and && in arguments still asks"
_run_hook "$R" 'echo "#"; gh issue create -t x'
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "a quoted # is not a comment; the following gh issue create asks"

# (d) no active goal → silent
_flow_test_begin "no active goal (status achieved) is not prompted"
R2=$(_new_goal_repo achieved)
_run_hook "$R2" "gh issue create --title x"
assert_exit 0 "$AIC_RC" "exits 0"
assert_equal "" "$AIC_OUT" "empty stdout"
assert_equal "" "$AIC_ERR" "empty stderr (exit 1 from the helper is the normal no-goal case)"

# goal active but owned by another branch → silent (--branch-strict)
_flow_test_begin "active goal on another branch is not prompted"
R3=$(_new_goal_repo active "feature/somewhere-else")
_run_hook "$R3" "gh issue create --title x"
assert_exit 0 "$AIC_RC" "exits 0"
assert_equal "" "$AIC_OUT" "empty stdout"

# (e) minimalScope true via project settings → silent
_flow_test_begin "minimalScope true in .claude/settings.flow.json disables the prompt"
R4=$(_new_goal_repo active)
mkdir -p "$R4/.claude"
printf '{"minimalScope": true}\n' > "$R4/.claude/settings.flow.json"
_run_hook "$R4" "gh issue create --title x"
assert_exit 0 "$AIC_RC" "exits 0"
assert_equal "" "$AIC_OUT" "empty stdout"
# and an explicit project false beats a user-global true
_flow_test_begin "explicit project minimalScope false overrides a user-global true"
R5=$(_new_goal_repo active)
mkdir -p "$R5/.claude" "$R5/home/.claude"
printf '{"minimalScope": true}\n' > "$R5/home/.claude/settings.flow.json"
printf '{"minimalScope": false}\n' > "$R5/.claude/settings.flow.json"
_run_hook "$R5" "gh issue create --title x"
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "project false wins → ask"

# helper cannot determine (symlinked .flow/goals → exit 2) → allow, stderr note
_flow_test_begin "undeterminable goal state allows with a stderr note"
R6=$(_new_goal_repo active)
mv "$R6/.flow/goals" "$R6/.flow/goals-real" && ln -s goals-real "$R6/.flow/goals"
_run_hook "$R6" "gh issue create --title x"
assert_exit 0 "$AIC_RC" "exits 0"
assert_equal "" "$AIC_OUT" "empty stdout (no prompt, no deny)"
assert_contains "cannot determine the active FlowGoal" "$AIC_ERR" "stderr carries a one-line note"

# degenerate: two active goals on the current branch (helper exit 3) → same
_flow_test_begin "degenerate goal state (exit 3) allows with a stderr note"
R7=$(_new_goal_repo active)
sed -E 's/^  id: issue-42$/  id: issue-43/' "$R7/.flow/goals/issue-42.goal.yaml" > "$R7/.flow/goals/issue-43.goal.yaml"
_run_hook "$R7" "gh issue create --title x"
assert_equal "" "$AIC_OUT" "empty stdout"
assert_contains "exit 3" "$AIC_ERR" "stderr names the helper exit code"

# CLAUDE_PLUGIN_ROOT unset → the SCRIPT_DIR/../.. fallback still finds the helpers
_flow_test_begin "CLAUDE_PLUGIN_ROOT fallback resolves the plugin root"
R8=$(_new_goal_repo active)
_run_hook "$R8" "gh issue create --title x" -u CLAUDE_PLUGIN_ROOT
assert_equal "ask" "$(printf '%s' "$AIC_OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "asks without CLAUDE_PLUGIN_ROOT"

# jq missing → silent exit 0 (bash builtins need no PATH; jq cannot be found)
_flow_test_begin "missing jq degrades to a silent allow"
_run_hook "$R8" "gh issue create --title x" PATH=/nonexistent
assert_exit 0 "$AIC_RC" "exits 0 without jq"
assert_equal "" "$AIC_OUT" "empty stdout without jq"

# malformed payload → silent
_flow_test_begin "payload without tool_input.command is ignored"
OUT=$( cd "$R8" && export HOME="$R8/home" CLAUDE_PLUGIN_ROOT="$PLUGIN" && printf '{}' | "$BASH_BIN" "$HOOK" 2>/dev/null ); RC=$?
assert_exit 0 "$RC" "exits 0 on empty payload"
assert_equal "" "$OUT" "no stdout on empty payload"
