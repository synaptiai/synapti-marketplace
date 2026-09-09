# Tests for the TaskCompleted quality gate and its ledger writers:
#   hooks/scripts/verify-task-completion.sh  (gate)
#   hooks/scripts/record-quality-run.sh      (quality_run writer, PostToolUse Bash)
#   hooks/scripts/log-file-changes.sh        (file_change writer, PostToolUse Edit|Write)
#
# Contract:
#   - block mode (default) + dirty ledger -> exit 2, stderr names the changed file
#   - warn mode + dirty -> exit 0, stderr prefixed "WARNING (stop allowed)"
#   - off -> exit 0 without evaluating
#   - clean / empty ledger -> exit 0 and empty stderr
#   - legacy .task.subject payload still read
#   - no session_id -> exit 0 (teammates)
#   - testing.taskCompletionGate resolved through the cascade (project
#     .claude/settings.flow.json with the hook run from inside that repo)
#   - record-quality-run.sh classifies commands (built-in + project patterns)
#     and captures exit_code / interrupted
#
# Every case uses its own FLOW_STATE_DIR and HOME so real user state never
# leaks in; CLAUDE_PLUGIN_ROOT points at the real plugin so the cascade's
# plugin-default tier is the shipped settings.json.

GATE="$REPO_ROOT/plugins/flow/hooks/scripts/verify-task-completion.sh"
RECORD="$REPO_ROOT/plugins/flow/hooks/scripts/record-quality-run.sh"
LOG_CHANGES="$REPO_ROOT/plugins/flow/hooks/scripts/log-file-changes.sh"
LEDGER_HELPER="$REPO_ROOT/plugins/flow/bin/flow-quality-ledger.sh"
PLUGIN="$REPO_ROOT/plugins/flow"

VT_CLEANUP=()
_vt_cleanup() { local p; for p in "${VT_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _vt_cleanup EXIT

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi

_vt_dir() {
  local d; d=$(mktemp -d -t verify-task-completion.XXXXXX 2>/dev/null)
  if [ -z "$d" ] || [ ! -d "$d" ]; then
    echo "verify-task-completion.test.sh: mktemp failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  VT_CLEANUP+=("$d"); printf '%s' "$d"
}

# _case: fresh REPO (temp project dir with .claude/), STATE (FLOW_STATE_DIR),
# and HOME so the user-global cascade tier is empty.
_case() {
  REPO=$(_vt_dir); mkdir -p "$REPO/.claude"
  STATE=$(_vt_dir)
  FAKE_HOME=$(_vt_dir)
  SID="sess-$RANDOM"
}
# Run a hook from inside $REPO with the given stdin payload. stdout -> $OUT,
# stderr -> $ERR, exit -> $EXIT.
_hook() {
  local script="$1" payload="$2" errf
  errf=$(mktemp -t vt-err.XXXXXX); VT_CLEANUP+=("$errf")
  OUT=$(cd "$REPO" && printf '%s' "$payload" | \
    FLOW_STATE_DIR="$STATE" HOME="$FAKE_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN" "$script" 2>"$errf")
  EXIT=$?
  ERR=$(cat "$errf")
}
_ledger_change() { FLOW_STATE_DIR="$STATE" "$LEDGER_HELPER" append --session "$SID" --json "{\"at\":\"$1\",\"type\":\"file_change\",\"tool\":\"Edit\",\"path\":\"$2\"}"; }
_ledger_run()    { FLOW_STATE_DIR="$STATE" "$LEDGER_HELPER" append --session "$SID" --json "{\"at\":\"$1\",\"type\":\"quality_run\",\"command\":\"npm test\",\"exit_code\":$2,\"kind\":\"test\"}"; }
_ledger_file()   { FLOW_STATE_DIR="$STATE" "$LEDGER_HELPER" path --session "$SID"; }
_payload() { printf '{"session_id":"%s","cwd":"%s","task_id":"t1","task_subject":"%s","task_description":"Must pass tests"}' "$SID" "$REPO" "$1"; }

# --- gate: block (default) ---------------------------------------------------
_flow_test_begin "block mode (plugin default): dirty ledger -> exit 2, stderr names file"
_case
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/widget.js"
_hook "$GATE" "$(_payload "Add widget")"
assert_exit 2 "$EXIT" "exit 2 blocks completion"
assert_contains "Task 'Add widget' cannot be completed" "$ERR" "names the task"
assert_contains "1 file(s) changed since the last passing quality run" "$ERR" "counts changes"
assert_contains "no quality command has run this session" "$ERR" "explains no run"
assert_contains "$REPO/src/widget.js" "$ERR" "names the changed file"
assert_contains "Set testing.taskCompletionGate to warn or off" "$ERR" "names the setting"
assert_equal "" "$OUT" "nothing on stdout"

_flow_test_begin "block mode: change after failing run -> exit 2 citing the failed exit"
_case
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_ledger_run 2026-09-09T10:01:00Z 1
_hook "$GATE" "$(_payload "Fix a")"
assert_exit 2 "$EXIT" "exit 2"
assert_contains "the last quality run exited 1" "$ERR" "cites failed exit"

_flow_test_begin "block mode explicit via project settings.flow.json"
_case
echo '{"testing":{"taskCompletionGate":"block"}}' > "$REPO/.claude/settings.flow.json"
_ledger_run 2026-09-09T10:00:00Z 0
_ledger_change 2026-09-09T10:01:00Z "$REPO/src/a.js"
_hook "$GATE" "$(_payload "After run")"
assert_exit 2 "$EXIT" "exit 2"
assert_contains "last passing run at 2026-09-09T10:00:00Z" "$ERR" "cites passing run time"

# --- gate: warn / off ---------------------------------------------------------
_flow_test_begin "warn mode via project settings.flow.json: dirty -> exit 0 with WARNING"
_case
echo '{"testing":{"taskCompletionGate":"warn"}}' > "$REPO/.claude/settings.flow.json"
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_hook "$GATE" "$(_payload "Warned task")"
assert_exit 0 "$EXIT" "exit 0"
assert_match "^WARNING \(stop allowed\): Task 'Warned task' cannot be completed" "$ERR" "WARNING prefix"
assert_contains "$REPO/src/a.js" "$ERR" "names file"

_flow_test_begin "local settings.flow.local.json beats project: warn overrides block"
_case
echo '{"testing":{"taskCompletionGate":"block"}}' > "$REPO/.claude/settings.flow.json"
echo '{"testing":{"taskCompletionGate":"warn"}}' > "$REPO/.claude/settings.flow.local.json"
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_hook "$GATE" "$(_payload "Local wins")"
assert_exit 0 "$EXIT" "exit 0 (warn)"
assert_contains "WARNING (stop allowed)" "$ERR" "warn text"

_flow_test_begin "off: dirty ledger -> exit 0, silent"
_case
echo '{"testing":{"taskCompletionGate":"off"}}' > "$REPO/.claude/settings.flow.json"
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_hook "$GATE" "$(_payload "Off task")"
assert_exit 0 "$EXIT" "exit 0"
assert_equal "" "$ERR" "empty stderr"

_flow_test_begin "unknown mode value falls back to block"
_case
echo '{"testing":{"taskCompletionGate":"strict"}}' > "$REPO/.claude/settings.flow.json"
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_hook "$GATE" "$(_payload "Unknown mode")"
assert_exit 2 "$EXIT" "exit 2"

# --- gate: clean / empty / pass-through ---------------------------------------
_flow_test_begin "clean ledger (change then passing run) -> exit 0, empty stderr"
_case
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_ledger_run 2026-09-09T10:01:00Z 0
_hook "$GATE" "$(_payload "Clean task")"
assert_exit 0 "$EXIT" "exit 0"
assert_equal "" "$ERR" "empty stderr"
assert_equal "" "$OUT" "empty stdout"

_flow_test_begin "empty ledger (nothing recorded) -> exit 0, empty stderr"
_case
_hook "$GATE" "$(_payload "Fresh task")"
assert_exit 0 "$EXIT" "exit 0"
assert_equal "" "$ERR" "empty stderr"

_flow_test_begin "only journal/.flow/.screenshots changes -> clean (ignore prefixes)"
_case
_ledger_change 2026-09-09T10:00:00Z "$REPO/.decisions/issue-3.md"
_ledger_change 2026-09-09T10:00:01Z "$REPO/.flow/goals/g.goal.yaml"
_ledger_change 2026-09-09T10:00:02Z "$REPO/.screenshots/s.png"
_hook "$GATE" "$(_payload "Bookkeeping")"
assert_exit 0 "$EXIT" "exit 0"
assert_equal "" "$ERR" "empty stderr"

_flow_test_begin "custom journal.dir is honoured as an ignore prefix"
_case
echo '{"journal":{"dir":"docs/decisions"}}' > "$REPO/.claude/settings.flow.json"
_ledger_change 2026-09-09T10:00:00Z "$REPO/docs/decisions/issue-3.md"
_hook "$GATE" "$(_payload "Custom journal")"
assert_exit 0 "$EXIT" "exit 0"
_ledger_change 2026-09-09T10:00:01Z "$REPO/.decisions/issue-3.md"
_hook "$GATE" "$(_payload "Custom journal")"
assert_exit 2 "$EXIT" "default .decisions no longer ignored once journal.dir moved"

_flow_test_begin "legacy .task.subject payload still gated"
_case
_ledger_change 2026-09-09T10:00:00Z "$REPO/src/a.js"
_hook "$GATE" "$(printf '{"session_id":"%s","cwd":"%s","task":{"subject":"Legacy subject","description":"x"}}' "$SID" "$REPO")"
assert_exit 2 "$EXIT" "exit 2"
assert_contains "Task 'Legacy subject' cannot be completed" "$ERR" "legacy subject read"

_flow_test_begin "payload without session_id -> exit 0 (teammate pass-through)"
_case
_hook "$GATE" '{"task_subject":"Teammate task","teammate_name":"worker-1"}'
assert_exit 0 "$EXIT" "exit 0"
assert_equal "" "$ERR" "silent"

_flow_test_begin "changed-file list capped at five with remainder count"
_case
for i in 1 2 3 4 5 6 7; do _ledger_change "2026-09-09T10:00:0${i}Z" "$REPO/src/f$i.js"; done
_hook "$GATE" "$(_payload "Many files")"
assert_exit 2 "$EXIT" "exit 2"
assert_contains "7 file(s) changed" "$ERR" "total count"
assert_contains "and 2 more" "$ERR" "remainder"
assert_not_contains "f7.js" "$ERR" "sixth+ file not listed"

# --- log-file-changes.sh -> file_change entry ---------------------------------
_flow_test_begin "log-file-changes.sh appends a file_change entry (journal logic untouched)"
_case
_hook "$LOG_CHANGES" "$(printf '{"session_id":"%s","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/src/new.ts","content":"x"}}' "$SID" "$REPO" "$REPO")"
assert_exit 0 "$EXIT" "hook exit 0"
LEDGER=$(_ledger_file)
assert_file_exists "$LEDGER" "ledger written"
assert_equal "file_change" "$(jq -r '.type' "$LEDGER")" "type"
assert_equal "Write" "$(jq -r '.tool' "$LEDGER")" "tool"
assert_equal "$REPO/src/new.ts" "$(jq -r '.path' "$LEDGER")" "absolute path"
assert_match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(jq -r '.at' "$LEDGER")" "ISO-8601 UTC"
assert_equal "0" "$(find "$REPO" -name '*.md' | wc -l | tr -d ' ')" "no journal file created when none exists"
_hook "$GATE" "$(_payload "After edit")"
assert_exit 2 "$EXIT" "gate now blocks"

_flow_test_begin "log-file-changes.sh resolves a relative file_path against cwd"
_case
_hook "$LOG_CHANGES" "$(printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"src/rel.ts"}}' "$SID" "$REPO")"
assert_equal "$REPO/src/rel.ts" "$(jq -r '.path' "$(_ledger_file)")" "absolute path from cwd"

_flow_test_begin "log-file-changes.sh without session_id writes no ledger and still exits 0"
_case
_hook "$LOG_CHANGES" "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/a.ts"}}' "$REPO")"
assert_exit 0 "$EXIT" "exit 0"
assert_equal "0" "$(find "$STATE" -name quality-ledger.jsonl | wc -l | tr -d ' ')" "no ledger"

# --- record-quality-run.sh classification ------------------------------------
# _classify <command> [exit_code_json] -> prints "<kind>|<exit_code>" or "none"
_classify() {
  local cmd="$1" resp="${2:-{\"exit_code\":0\}}"
  _case
  _hook "$RECORD" "$(jq -cn --arg sid "$SID" --arg cwd "$REPO" --arg cmd "$cmd" --argjson resp "$resp" \
    '{session_id:$sid,cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd},tool_response:$resp}')"
  local ledger; ledger=$(_ledger_file)
  if [ -f "$ledger" ]; then
    jq -r '"\(.kind)|\(.exit_code)"' "$ledger"
  else
    echo "none"
  fi
}

_flow_test_begin "record-quality-run.sh: built-in positives"
assert_equal "test|0"      "$(_classify 'npm test')"                          "npm test -> test"
assert_equal "test|0"      "$(_classify 'cd app && pnpm run tests -- --ci')"   "pnpm run tests after && -> test"
assert_equal "lint|0"      "$(_classify 'npm run lint')"                       "npm run lint -> lint"
assert_equal "typecheck|0" "$(_classify 'yarn run typecheck')"                 "yarn run typecheck -> typecheck"
assert_equal "build|0"     "$(_classify 'bun run build')"                      "bun run build -> build"
assert_equal "test|0"      "$(_classify 'npx vitest run src/')"                "npx vitest -> test"
assert_equal "test|0"      "$(_classify 'python3 -m pytest -q tests/')"        "python3 -m pytest -> test"
assert_equal "test|0"      "$(_classify 'python3 -m unittest tests.test_allocate -v')" "python3 -m unittest -> test (surfaced by the 2026-09-09 eval)"
assert_equal "test|0"      "$(_classify 'python -m unittest discover')"        "python -m unittest -> test"
assert_equal "lint|0"      "$(_classify 'ruff check .')"                       "ruff -> lint"
assert_equal "typecheck|0" "$(_classify 'mypy src')"                           "mypy -> typecheck"
assert_equal "typecheck|0" "$(_classify 'npx tsc --noEmit')"                   "tsc -> typecheck"
assert_equal "lint|0"      "$(_classify 'prettier --check .')"                 "prettier --check -> lint"
assert_equal "lint|0"      "$(_classify 'cargo clippy -- -D warnings')"        "cargo clippy -> lint"
assert_equal "test|0"      "$(_classify 'go test ./...')"                      "go test -> test"
assert_equal "build|0"     "$(_classify 'make build')"                         "make build -> build"
assert_equal "test|0"      "$(_classify 'bundle exec rspec spec/')"            "bundle exec rspec -> test"
assert_equal "lint|0"      "$(_classify 'shellcheck hooks/*.sh')"              "shellcheck -> lint"
assert_equal "test|0"      "$(_classify 'plugins/flow/tests/run.sh')"          "tests/run.sh -> test"
assert_equal "project|0"   "$(_classify './scripts/verify.sh --all')"          "scripts/verify.sh -> project"
assert_equal "test|0"      "$(_classify 'git stash; ./test.sh')"               "./test.sh after ; -> test"

_flow_test_begin "record-quality-run.sh: negatives leave no ledger"
assert_equal "none" "$(_classify 'git status')"                   "git status"
assert_equal "none" "$(_classify 'echo "npm test"')"              "quoted mention"
assert_equal "none" "$(_classify 'npm install')"                  "npm install"
assert_equal "none" "$(_classify 'go mod tidy')"                  "go mod tidy"
assert_equal "none" "$(_classify 'grep -rn testing src/')"        "grep with testing"
assert_equal "none" "$(_classify 'cargo tests-helper')"           "cargo tests-helper (no boundary)"
assert_equal "none" "$(_classify 'ls tests/')"                    "ls tests/"
assert_equal "none" "$(_classify 'cat tests/run.sh.bak')"         "tests/run.sh.bak (suffix)"
assert_equal "none" "$(_classify 'pytest-watch src')"             "pytest-watch (no boundary)"

_flow_test_begin "record-quality-run.sh: exit_code captured; interrupted -> 130; absent -> null"
assert_equal "test|1"   "$(_classify 'npm test' '{"exit_code":1,"stdout":"","stderr":"fail"}')" "exit 1 captured"
assert_equal "test|130" "$(_classify 'npm test' '{"exit_code":0,"interrupted":true}')"          "interrupted beats exit_code"
assert_equal "test|null" "$(_classify 'npm test' '{"stdout":"ok"}')"                            "missing exit_code -> null"
assert_equal "test|null" "$(_classify 'npm test' '{"exit_code":"0"}')"                          "non-numeric exit_code -> null"

_flow_test_begin "record-quality-run.sh: entry shape and command truncation"
LONG="npm test -- $(printf 'x%.0s' $(seq 1 300))"
_classify "$LONG" >/dev/null
LEDGER=$(_ledger_file)
assert_equal "quality_run" "$(jq -r '.type' "$LEDGER")" "type"
assert_equal "200" "$(jq -r '.command | length' "$LEDGER")" "command truncated to 200 chars"
assert_match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(jq -r '.at' "$LEDGER")" "ISO-8601 UTC"
assert_equal "1" "$(wc -l <"$LEDGER" | tr -d ' ')" "exactly one line"

_flow_test_begin "record-quality-run.sh: project pattern from testing.qualityCommandPatterns -> kind project"
_case
echo '{"testing":{"qualityCommandPatterns":["^just[[:space:]]+ci", "(["]}}' > "$REPO/.claude/settings.flow.json"
_hook "$RECORD" "$(jq -cn --arg sid "$SID" --arg cwd "$REPO" '{session_id:$sid,cwd:$cwd,tool_name:"Bash",tool_input:{command:"just ci --fast"},tool_response:{exit_code:0}}')"
assert_exit 0 "$EXIT" "exit 0 despite one invalid regex in the list"
assert_equal "project|0" "$(jq -r '"\(.kind)|\(.exit_code)"' "$(_ledger_file)")" "custom pattern -> project"
_hook "$RECORD" "$(jq -cn --arg sid "$SID" --arg cwd "$REPO" '{session_id:$sid,cwd:$cwd,tool_name:"Bash",tool_input:{command:"just fmt"},tool_response:{exit_code:0}}')"
assert_equal "1" "$(wc -l <"$(_ledger_file)" | tr -d ' ')" "non-matching command not recorded"

_flow_test_begin "record-quality-run.sh: no session_id -> no side effects"
_case
_hook "$RECORD" '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"exit_code":0}}'
assert_exit 0 "$EXIT" "exit 0"
assert_equal "0" "$(find "$STATE" -name quality-ledger.jsonl | wc -l | tr -d ' ')" "no ledger"

# --- full loop: edit -> failing run -> blocked -> passing run -> allowed ------
_flow_test_begin "end-to-end: edit, failing run blocks, passing run unblocks, new edit blocks again"
_case
_edit() { _hook "$LOG_CHANGES" "$(printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$SID" "$REPO" "$1")"; }
_bash() { _hook "$RECORD" "$(jq -cn --arg sid "$SID" --arg cwd "$REPO" --arg cmd "$1" --argjson ec "$2" '{session_id:$sid,cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd},tool_response:{exit_code:$ec}}')"; }
_edit "$REPO/src/a.js"
_bash "npm test" 1
_hook "$GATE" "$(_payload "Loop")"; assert_exit 2 "$EXIT" "blocked after failing run"
_bash "npm test" 0
_hook "$GATE" "$(_payload "Loop")"; assert_exit 0 "$EXIT" "allowed after passing run"
_edit "$REPO/src/b.js"
_hook "$GATE" "$(_payload "Loop")"; assert_exit 2 "$EXIT" "blocked again after new edit"
assert_contains "$REPO/src/b.js" "$ERR" "names only the new file"
assert_not_contains "$REPO/src/a.js" "$ERR" "earlier file not named"
