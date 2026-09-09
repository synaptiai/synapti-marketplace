# Tests for plugins/flow/bin/flow-goal-trust.sh — the per-user trust ledger
# that lets the Stop hook execute a goal's verification commands without the
# global flow.goals.executeVerificationCommands opt-in.
#
# Contract:
#   - `record --goal-file` appends {recorded_at, repo, goal_id, commands_sha256,
#     session_id} to ${FLOW_STATE_DIR}/goal-trust.jsonl
#   - `check --goal-file` prints TRUSTED=yes (exit 0) only when an entry matches
#     repo AND goal_id AND the sha256 over the goal's AC ids + commands;
#     TRUSTED=no (exit 1) otherwise
#   - editing a verification_command changes the hash → untrusted until re-recorded
#   - AC order does not affect the hash (canonical form sorts by id)
#   - `list` prints one JSON line per entry
#   - a symlinked ledger is refused (exit 2) for both record and check
#   - infra/input errors: exit 2 / exit 1 with a stderr message

TRUST="$REPO_ROOT/plugins/flow/bin/flow-goal-trust.sh"

FGT_CLEANUP_PATHS=()
_fgt_cleanup() {
  local p
  for p in "${FGT_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fgt_cleanup EXIT

_fgt_mktemp_dir() {
  local out
  out=$(mktemp -d -t flow-goal-trust.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-goal-trust.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FGT_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Write a goal with two ACs: AC1 has a command, AC2 is fuzzy. $2 overrides
# AC1's command (default 'true'); $3 reverses AC order when set to "reversed".
_fgt_write_goal() {
  local path="$1" cmd="${2:-true}" order="${3:-normal}"
  local ac1="    - {id: AC1, text: has a command, status: pending, verification_command: '${cmd}'}"
  local ac2="    - {id: AC2, text: fuzzy, status: pending}"
  {
    cat <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: trust-goal
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: test/test, branch: test}
objective:
  outcome: trust ledger test
  acceptance_criteria:
YML
    if [ "$order" = "reversed" ]; then
      printf '%s\n%s\n' "$ac2" "$ac1"
    else
      printf '%s\n%s\n' "$ac1" "$ac2"
    fi
    cat <<'YML'
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
  } > "$path"
}

# _run_trust <dir> <subcommand> [args...] — runs from <dir> with an isolated
# FLOW_STATE_DIR under it. Stdout is returned; stderr goes to $FGT_ERRFILE,
# read with $(_fgt_err). (A variable set inside the function would be lost —
# callers run it in a $(...) subshell.)
FGT_ERRFILE=$(mktemp -t flow-goal-trust.err.XXXXXX)
FGT_CLEANUP_PATHS+=("$FGT_ERRFILE")
_run_trust() {
  local dir="$1"; shift
  (cd "$dir" && FLOW_STATE_DIR="$dir/state" "$TRUST" "$@" 2>"$FGT_ERRFILE")
}
_fgt_err() { cat "$FGT_ERRFILE"; }

# Prerequisites.
if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi
if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

# --- Test 1: check before any record → TRUSTED=no, exit 1
_flow_test_begin "check with no ledger → TRUSTED=no (exit 1)"
DIR=$(_fgt_mktemp_dir)
_fgt_write_goal "$DIR/goal.yaml"
OUT=$(_run_trust "$DIR" check --goal-file goal.yaml); RC=$?
assert_exit 1 "$RC" "untrusted goal exits 1"
assert_equal "TRUSTED=no" "$OUT" "prints TRUSTED=no"

# --- Test 2: record → ledger entry with the five fields; check → TRUSTED=yes
_flow_test_begin "record then check → TRUSTED=yes, ledger entry has all fields"
OUT=$(cd "$DIR" && FLOW_STATE_DIR="$DIR/state" CLAUDE_SESSION_ID="sess-abc" "$TRUST" record --goal-file goal.yaml 2>&1); RC=$?
assert_exit 0 "$RC" "record exits 0"
assert_contains "recorded trust-goal" "$OUT" "stderr names the recorded goal"
assert_file_exists "$DIR/state/goal-trust.jsonl" "ledger created under FLOW_STATE_DIR"
ENTRY=$(tail -1 "$DIR/state/goal-trust.jsonl")
assert_equal "trust-goal" "$(echo "$ENTRY" | jq -r '.goal_id')" "entry.goal_id"
assert_equal "$(cd "$DIR" && pwd -P)" "$(echo "$ENTRY" | jq -r '.repo')" "entry.repo is the physical cwd (not a git repo)"
assert_match '^[0-9a-f]{64}$' "$(echo "$ENTRY" | jq -r '.commands_sha256')" "entry.commands_sha256 is a sha256 hex digest"
assert_equal "sess-abc" "$(echo "$ENTRY" | jq -r '.session_id')" "entry.session_id from CLAUDE_SESSION_ID"
assert_match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(echo "$ENTRY" | jq -r '.recorded_at')" "entry.recorded_at is ISO-8601 UTC"
OUT=$(_run_trust "$DIR" check --goal-file goal.yaml); RC=$?
assert_exit 0 "$RC" "trusted goal exits 0"
assert_equal "TRUSTED=yes" "$OUT" "prints TRUSTED=yes"

# --- Test 3: hash is the sha256 of the canonical JSON sorted by AC id
_flow_test_begin "commands_sha256 matches the documented canonical form"
EXPECTED=$(printf '%s' '[{"id":"AC1","verification_command":"true"},{"id":"AC2","verification_command":null}]' | sha256sum | cut -d' ' -f1)
assert_equal "$EXPECTED" "$(echo "$ENTRY" | jq -r '.commands_sha256')" "sha256 over [{id, verification_command}] sorted by id, compact separators"

# --- Test 4: editing a verification command → hash mismatch → untrusted
_flow_test_begin "editing a verification_command → TRUSTED=no until re-recorded"
_fgt_write_goal "$DIR/goal.yaml" "false"
OUT=$(_run_trust "$DIR" check --goal-file goal.yaml); RC=$?
assert_exit 1 "$RC" "edited command is untrusted"
assert_equal "TRUSTED=no" "$OUT" "prints TRUSTED=no after edit"
_run_trust "$DIR" record --goal-file goal.yaml >/dev/null
OUT=$(_run_trust "$DIR" check --goal-file goal.yaml); RC=$?
assert_exit 0 "$RC" "re-recording trusts the edited command"
assert_equal "2" "$(wc -l < "$DIR/state/goal-trust.jsonl" | tr -d ' ')" "ledger is append-only (two entries)"

# --- Test 5: AC order does not change the hash
_flow_test_begin "AC order does not affect trust (canonical form sorts by id)"
_fgt_write_goal "$DIR/goal.yaml" "false" reversed
OUT=$(_run_trust "$DIR" check --goal-file goal.yaml); RC=$?
assert_exit 0 "$RC" "reordered ACs still trusted"

# --- Test 6: same goal, different repo (cwd) → untrusted
_flow_test_begin "same goal id + hash from another repo → TRUSTED=no"
OTHER=$(_fgt_mktemp_dir)
_fgt_write_goal "$OTHER/goal.yaml" "false"
cp -r "$DIR/state" "$OTHER/state"
OUT=$(_run_trust "$OTHER" check --goal-file goal.yaml); RC=$?
assert_exit 1 "$RC" "entry recorded for another repo does not match"
assert_equal "TRUSTED=no" "$OUT" "prints TRUSTED=no for the other repo"

# --- Test 7: list prints one JSON line per entry
_flow_test_begin "list prints every entry as JSON"
OUT=$(_run_trust "$DIR" list); RC=$?
assert_exit 0 "$RC" "list exits 0"
assert_equal "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "two lines for two entries"
assert_equal "trust-goal" "$(printf '%s\n' "$OUT" | head -1 | jq -r '.goal_id')" "each line is a JSON entry"
EMPTY=$(_fgt_mktemp_dir)
OUT=$(_run_trust "$EMPTY" list); RC=$?
assert_exit 0 "$RC" "list with no ledger exits 0"
assert_equal "" "$OUT" "list with no ledger prints nothing on stdout"
assert_contains "no entries" "$(_fgt_err)" "stderr notes the empty ledger"

# --- Test 8: symlinked ledger is refused by record and check
_flow_test_begin "symlinked ledger → refused (exit 2) for record and check"
SYM=$(_fgt_mktemp_dir)
_fgt_write_goal "$SYM/goal.yaml"
mkdir -p "$SYM/state"
: > "$SYM/real.jsonl"
ln -s "$SYM/real.jsonl" "$SYM/state/goal-trust.jsonl"
OUT=$(_run_trust "$SYM" record --goal-file goal.yaml); RC=$?
assert_exit 2 "$RC" "record refuses the symlinked ledger"
assert_contains "symlink" "$(_fgt_err)" "record stderr names the symlink"
assert_equal "0" "$(wc -c < "$SYM/real.jsonl" | tr -d ' ')" "nothing was written through the symlink"
OUT=$(_run_trust "$SYM" check --goal-file goal.yaml); RC=$?
assert_exit 2 "$RC" "check refuses the symlinked ledger"
assert_contains "symlink" "$(_fgt_err)" "check stderr names the symlink"

# --- Test 9: malformed ledger lines are skipped, valid ones still match
_flow_test_begin "malformed ledger lines are skipped"
printf '%s\n' 'not json' >> "$DIR/state/goal-trust.jsonl"
OUT=$(_run_trust "$DIR" check --goal-file goal.yaml); RC=$?
assert_exit 0 "$RC" "valid entry still matches after a garbage line"

# --- Test 10: argument errors
_flow_test_begin "argument errors exit 1 with a message"
OUT=$(_run_trust "$DIR" check); RC=$?
assert_exit 1 "$RC" "check without --goal-file exits 1"
assert_contains "--goal-file is required" "$(_fgt_err)" "stderr names the missing flag"
OUT=$(_run_trust "$DIR" check --goal-file missing.yaml); RC=$?
assert_exit 1 "$RC" "missing goal file exits 1"
assert_contains "does not exist" "$(_fgt_err)" "stderr names the missing file"
OUT=$(_run_trust "$DIR" bogus); RC=$?
assert_exit 1 "$RC" "unknown subcommand exits 1"
assert_contains "unknown subcommand" "$(_fgt_err)" "stderr names the unknown subcommand"
OUT=$(_run_trust "$DIR" record --goal-file goal.yaml --nope); RC=$?
assert_exit 1 "$RC" "unknown argument exits 1"

# --- Test 11: goal without a valid metadata.id is refused
_flow_test_begin "goal with path-traversal id is refused"
cat > "$DIR/bad.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: '../escape', created_at: '2026-05-20T14:30:00Z'}
scope: {repo: test/test, branch: test}
objective:
  outcome: t
  acceptance_criteria:
    - {id: AC1, text: t, status: pending}
evaluator: {type: deterministic}
lifecycle: {status: active}
YML
OUT=$(_run_trust "$DIR" record --goal-file bad.yaml); RC=$?
assert_exit 1 "$RC" "traversal id exits 1"
assert_contains "metadata.id" "$(_fgt_err)" "stderr names metadata.id"

# --- Test 12: hostile AC id with quote characters cannot inject (argv passing)
_flow_test_begin "hostile AC id with quote characters is hashed, not executed"
cat > "$DIR/hostile.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: hostile, created_at: '2026-05-20T14:30:00Z'}
scope: {repo: test/test, branch: test}
objective:
  outcome: t
  acceptance_criteria:
    - id: "AC1'''; __import__('os').system('touch /tmp/flow-trust-pwn'); '''"
      text: t
      status: pending
      verification_command: "echo hi"
evaluator: {type: deterministic}
lifecycle: {status: active}
YML
rm -f /tmp/flow-trust-pwn 2>/dev/null
OUT=$(_run_trust "$DIR" record --goal-file hostile.yaml); RC=$?
assert_exit 0 "$RC" "record survives a hostile AC id"
if [ -e /tmp/flow-trust-pwn ]; then
  _flow_assert_fail "RCE via hostile AC id — /tmp/flow-trust-pwn was created"
  rm -f /tmp/flow-trust-pwn
else
  _flow_assert_pass "no RCE via hostile AC id"
fi
