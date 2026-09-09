# Tests for plugins/flow/bin/flow-quality-ledger.sh — the per-session quality
# ledger behind the TaskCompleted gate.
#
# Contract under test (from the helper header):
#   - `path` prints ${FLOW_STATE_DIR}/sessions/<id>/quality-ledger.jsonl
#   - `append` writes one compact JSON line per call; rejects non-objects,
#     unsafe session ids, and symlinked ledgers
#   - `status` folds the ledger into STATE=empty|clean|dirty with
#     LAST_PASSING_RUN / LAST_RUN_EXIT / CHANGED_SINCE / CHANGED_FILE lines
#   - --ignore-prefix hides bookkeeping paths; malformed lines are skipped
#   - python3 missing -> STATE=unavailable, exit 0

HELPER="$REPO_ROOT/plugins/flow/bin/flow-quality-ledger.sh"

QL_CLEANUP=()
_ql_cleanup() { local p; for p in "${QL_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _ql_cleanup EXIT

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

# Fresh FLOW_STATE_DIR per test so ledgers never leak between cases.
_ql_state() {
  local d; d=$(mktemp -d -t flow-quality-ledger.XXXXXX 2>/dev/null)
  if [ -z "$d" ] || [ ! -d "$d" ]; then
    echo "flow-quality-ledger.test.sh: mktemp failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  QL_CLEANUP+=("$d"); printf '%s' "$d"
}
_ql() { FLOW_STATE_DIR="$STATE" "$HELPER" "$@"; }
_change() { _ql append --session "$1" --json "{\"at\":\"$2\",\"type\":\"file_change\",\"tool\":\"Edit\",\"path\":\"$3\"}"; }
_run() { _ql append --session "$1" --json "{\"at\":\"$2\",\"type\":\"quality_run\",\"command\":\"npm test\",\"exit_code\":$3,\"kind\":\"test\"}"; }

# --- path
_flow_test_begin "path: prints ledger under FLOW_STATE_DIR/sessions/<id>"
STATE=$(_ql_state)
OUT=$(_ql path --session abc-123); EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_equal "$STATE/sessions/abc-123/quality-ledger.jsonl" "$OUT" "path shape"

# --- empty
_flow_test_begin "status: no ledger -> STATE=empty"
STATE=$(_ql_state)
OUT=$(_ql status --session s1); EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_contains "STATE=empty" "$OUT" "empty state"
assert_contains "LAST_PASSING_RUN=none" "$OUT" "no passing run"
assert_contains "LAST_RUN_EXIT=none" "$OUT" "no run"
assert_contains "CHANGED_SINCE=0" "$OUT" "zero changed"

# --- append then status
_flow_test_begin "append: writes one compact line; change without run -> dirty"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js; EXIT=$?
assert_exit 0 "$EXIT" "append exit 0"
LEDGER=$(_ql path --session s1)
assert_file_exists "$LEDGER" "ledger created"
assert_equal "1" "$(wc -l <"$LEDGER" | tr -d ' ')" "one line"
assert_equal "file_change" "$(jq -r '.type' "$LEDGER")" "line is valid JSON with type"
OUT=$(_ql status --session s1)
assert_contains "STATE=dirty" "$OUT" "dirty without any run"
assert_contains "CHANGED_SINCE=1" "$OUT" "one changed"
assert_contains "CHANGED_FILE=/work/src/a.js" "$OUT" "names the file"

_flow_test_begin "change then passing run -> clean"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
_run s1 2026-09-09T10:01:00Z 0
OUT=$(_ql status --session s1)
assert_contains "STATE=clean" "$OUT" "clean"
assert_contains "LAST_PASSING_RUN=2026-09-09T10:01:00Z" "$OUT" "passing run time"
assert_contains "LAST_RUN_EXIT=0" "$OUT" "last exit 0"
assert_contains "CHANGED_SINCE=0" "$OUT" "nothing changed since"
assert_not_contains "CHANGED_FILE=" "$OUT" "no CHANGED_FILE lines"

_flow_test_begin "change after passing run -> dirty with CHANGED_FILE"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
_run s1 2026-09-09T10:01:00Z 0
_change s1 2026-09-09T10:02:00Z /work/src/b.js
_change s1 2026-09-09T10:02:30Z /work/src/b.js
OUT=$(_ql status --session s1)
assert_contains "STATE=dirty" "$OUT" "dirty"
assert_contains "LAST_PASSING_RUN=2026-09-09T10:01:00Z" "$OUT" "passing run retained"
assert_contains "CHANGED_SINCE=1" "$OUT" "same file twice counts once"
assert_contains "CHANGED_FILE=/work/src/b.js" "$OUT" "names b.js"
assert_not_contains "CHANGED_FILE=/work/src/a.js" "$OUT" "a.js (before the run) not listed"

_flow_test_begin "failing run after change -> still dirty; LAST_RUN_EXIT reports failure"
STATE=$(_ql_state)
_run s1 2026-09-09T10:00:00Z 0
_change s1 2026-09-09T10:01:00Z /work/src/a.js
_run s1 2026-09-09T10:02:00Z 1
OUT=$(_ql status --session s1)
assert_contains "STATE=dirty" "$OUT" "dirty"
assert_contains "LAST_PASSING_RUN=2026-09-09T10:00:00Z" "$OUT" "earlier passing run"
assert_contains "LAST_RUN_EXIT=1" "$OUT" "last run exit 1"
assert_contains "CHANGED_FILE=/work/src/a.js" "$OUT" "file listed"

_flow_test_begin "run with null exit_code never counts as passing"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
_run s1 2026-09-09T10:01:00Z null
OUT=$(_ql status --session s1)
assert_contains "STATE=dirty" "$OUT" "dirty"
assert_contains "LAST_PASSING_RUN=none" "$OUT" "no passing run"
assert_contains "LAST_RUN_EXIT=null" "$OUT" "null exit reported"

_flow_test_begin "CHANGED_FILE capped at five; CHANGED_SINCE counts all"
STATE=$(_ql_state)
for i in 1 2 3 4 5 6 7; do _change s1 "2026-09-09T10:00:0${i}Z" "/work/src/f$i.js"; done
OUT=$(_ql status --session s1)
assert_contains "CHANGED_SINCE=7" "$OUT" "seven distinct"
assert_equal "5" "$(printf '%s\n' "$OUT" | grep -c '^CHANGED_FILE=')" "five listed"
assert_contains "CHANGED_FILE=/work/src/f1.js" "$OUT" "first-change order"

# --- ignore prefixes
_flow_test_begin "ignore prefixes: journal, .flow, .screenshots hidden; relative prefix resolved against cwd"
STATE=$(_ql_state)
WORK=$(_ql_state)
_change s1 2026-09-09T10:00:00Z "$WORK/.decisions/issue-7.md"
_change s1 2026-09-09T10:00:01Z "$WORK/.flow/runs/x/events.jsonl"
_change s1 2026-09-09T10:00:02Z "$WORK/.screenshots/a.png"
OUT=$(cd "$WORK" && _ql status --session s1 --ignore-prefix .decisions --ignore-prefix "$WORK/.flow" --ignore-prefix .screenshots)
assert_contains "STATE=clean" "$OUT" "only ignored paths -> clean"
assert_contains "CHANGED_SINCE=0" "$OUT" "zero counted"
_change s1 2026-09-09T10:00:03Z "$WORK/.decisions-not-journal/x.md"
_change s1 2026-09-09T10:00:04Z "$WORK/src/real.js"
OUT=$(cd "$WORK" && _ql status --session s1 --ignore-prefix .decisions --ignore-prefix .flow --ignore-prefix .screenshots)
assert_contains "STATE=dirty" "$OUT" "real change -> dirty"
assert_contains "CHANGED_SINCE=2" "$OUT" "prefix match is path-component-wise (.decisions-not-journal counts)"
assert_contains "CHANGED_FILE=$WORK/src/real.js" "$OUT" "real file listed"
assert_not_contains ".decisions/issue-7.md" "$OUT" "journal hidden"

# --- malformed lines
_flow_test_begin "malformed lines skipped (partial JSON, non-object, missing path)"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
LEDGER=$(_ql path --session s1)
printf '%s\n' '{"at":"2026-09-09T10:00:01Z","type":"quality_run","command":"npm te' >> "$LEDGER"
printf '%s\n' '"just a string"' >> "$LEDGER"
printf '%s\n' '{"type":"file_change","at":"2026-09-09T10:00:02Z"}' >> "$LEDGER"
printf '%s\n' '' >> "$LEDGER"
OUT=$(_ql status --session s1); EXIT=$?
assert_exit 0 "$EXIT" "exit 0 despite garbage"
assert_contains "STATE=dirty" "$OUT" "valid entry still counted"
assert_contains "CHANGED_SINCE=1" "$OUT" "garbage not counted"
assert_contains "LAST_RUN_EXIT=none" "$OUT" "truncated run line ignored"

# --- input validation
_flow_test_begin "append rejects non-object JSON and unsafe session ids"
STATE=$(_ql_state)
ERR=$(_ql append --session s1 --json '[1,2]' 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "array rejected"
assert_contains "not a JSON object" "$ERR" "explains array rejection"
ERR=$(_ql append --session '../escape' --json '{}' 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "traversal id rejected"
ERR=$(_ql append --session 'a/b' --json '{}' 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "slash id rejected"
ERR=$(_ql append --session '' --json '{}' 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "empty id rejected"
assert_equal "0" "$(find "$STATE" -name quality-ledger.jsonl 2>/dev/null | wc -l | tr -d ' ')" "nothing written"
ERR=$(_ql bogus --session s1 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "unknown subcommand exit 1"

_flow_test_begin "append refuses a symlinked ledger"
STATE=$(_ql_state)
TARGET=$(_ql_state)
mkdir -p "$STATE/sessions/s1"
: > "$TARGET/victim"
ln -s "$TARGET/victim" "$STATE/sessions/s1/quality-ledger.jsonl"
ERR=$(_change s1 2026-09-09T10:00:00Z /work/src/a.js 2>&1 >/dev/null); EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "symlink" "$ERR" "names the symlink"
assert_equal "0" "$(wc -c <"$TARGET/victim" | tr -d ' ')" "target untouched"

# --- python3 missing
_flow_test_begin "status: python3 missing -> STATE=unavailable, exit 0"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
BASH_BIN=$(command -v bash)
OUT=$(cd "$STATE" && PATH=/nonexistent FLOW_STATE_DIR="$STATE" "$BASH_BIN" "$HELPER" status --session s1 2>/dev/null); EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_equal "STATE=unavailable" "$OUT" "unavailable"
