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
#   - a masked (`|| true`) or failed (PostToolUseFailure) run never passes
#   - append dedupes on tool_use_id
#   - `digest --cwd` hashes the git worktree; `status --cwd` reports
#     WORKTREE=changed + git-status paths when the last passing run's digest
#     no longer matches (edits made outside Edit/Write, checkouts); the
#     digest hashes contents, so a commit of already-tested edits keeps it
#   - `prune` removes idle session dirs only under sessions/, never symlinks;
#     session-end-state.sh calls it once per day
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

# --- masked / failed runs ----------------------------------------------------
_run_full() { _ql append --session "$1" --json "{\"at\":\"$2\",\"type\":\"quality_run\",\"command\":\"npm test || true\",\"exit_code\":$3,\"kind\":\"test\",\"masked\":$4,\"failed\":$5}"; }

_flow_test_begin "masked run (exit 0, masked:true) never counts as passing"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
_run_full s1 2026-09-09T10:01:00Z 0 true false
OUT=$(_ql status --session s1)
assert_contains "STATE=dirty" "$OUT" "still dirty"
assert_contains "LAST_PASSING_RUN=none" "$OUT" "no passing run"
assert_contains "LAST_RUN_EXIT=0" "$OUT" "exit 0 reported"
assert_contains "LAST_RUN_MASKED=true" "$OUT" "masked flagged"
assert_not_contains "LAST_RUN_FAILED=" "$OUT" "not failed"
_run_full s1 2026-09-09T10:02:00Z 0 false false
OUT=$(_ql status --session s1)
assert_contains "STATE=clean" "$OUT" "unmasked passing run clears it"
assert_not_contains "LAST_RUN_MASKED=" "$OUT" "masked line absent for an unmasked run"

_flow_test_begin "failed run (failed:true) never counts as passing, even with exit_code 0"
STATE=$(_ql_state)
_change s1 2026-09-09T10:00:00Z /work/src/a.js
_run_full s1 2026-09-09T10:01:00Z 0 false true
OUT=$(_ql status --session s1)
assert_contains "STATE=dirty" "$OUT" "dirty"
assert_contains "LAST_PASSING_RUN=none" "$OUT" "no passing run"
assert_contains "LAST_RUN_FAILED=true" "$OUT" "failed flagged"
_run_full s1 2026-09-09T10:02:00Z null false true
OUT=$(_ql status --session s1)
assert_contains "LAST_RUN_EXIT=null" "$OUT" "null exit on a failed run"
assert_contains "LAST_RUN_FAILED=true" "$OUT" "still failed"

# --- tool_use_id dedupe ------------------------------------------------------
_flow_test_begin "append: second entry with the same tool_use_id is skipped; distinct ids and id-less entries append"
STATE=$(_ql_state)
_ql append --session s1 --json '{"at":"2026-09-09T10:00:00Z","type":"quality_run","command":"npm test","exit_code":1,"kind":"test","failed":true,"tool_use_id":"toolu_01"}'; EXIT=$?
assert_exit 0 "$EXIT" "first append ok"
_ql append --session s1 --json '{"at":"2026-09-09T10:00:01Z","type":"quality_run","command":"npm test","exit_code":0,"kind":"test","tool_use_id":"toolu_01"}'; EXIT=$?
assert_exit 0 "$EXIT" "duplicate append exits 0"
LEDGER=$(_ql path --session s1)
assert_equal "1" "$(wc -l <"$LEDGER" | tr -d ' ')" "duplicate not written"
assert_equal "1" "$(jq -r '.exit_code' "$LEDGER")" "first entry kept (exit 1), not the later exit 0"
_ql append --session s1 --json '{"at":"2026-09-09T10:00:02Z","type":"quality_run","command":"npm test","exit_code":0,"kind":"test","tool_use_id":"toolu_02"}'
_ql append --session s1 --json '{"at":"2026-09-09T10:00:03Z","type":"quality_run","command":"npm test","exit_code":0,"kind":"test"}'
_ql append --session s1 --json '{"at":"2026-09-09T10:00:04Z","type":"quality_run","command":"npm test","exit_code":0,"kind":"test"}'
assert_equal "4" "$(wc -l <"$LEDGER" | tr -d ' ')" "distinct id and two id-less entries appended"
OUT=$(_ql status --session s1)
assert_contains "STATE=clean" "$OUT" "later passing run counts"

_flow_test_begin "append without jq still dedupes on tool_use_id"
STATE=$(_ql_state)
BASH_BIN=$(command -v bash)
JQLESS=$(_ql_state)
ln -s "$(command -v grep)" "$JQLESS/grep"; ln -s "$(command -v sed)" "$JQLESS/sed"; ln -s "$(command -v head)" "$JQLESS/head"
ln -s "$(command -v mkdir)" "$JQLESS/mkdir"; ln -s "$(command -v cut)" "$JQLESS/cut"
_nojq() { PATH="$JQLESS" FLOW_STATE_DIR="$STATE" "$BASH_BIN" "$HELPER" "$@"; }
_nojq append --session s1 --json '{"at":"2026-09-09T10:00:00Z","type":"quality_run","exit_code":1,"kind":"test","tool_use_id":"toolu_09"}'; EXIT=$?
assert_exit 0 "$EXIT" "append without jq ok"
_nojq append --session s1 --json '{"at":"2026-09-09T10:00:01Z","type":"quality_run","exit_code":0,"kind":"test","tool_use_id":"toolu_09"}'
assert_equal "1" "$(wc -l <"$(_ql path --session s1)" | tr -d ' ')" "duplicate skipped without jq"

# --- worktree digest ---------------------------------------------------------
# A throwaway git repo with one committed file; commits are made with an
# explicit identity so the runner's git config never matters.
_git() { git -c user.name=flow-test -c user.email=flow-test@example.invalid -c commit.gpgsign=false "$@"; }
_ql_repo() {
  local d; d=$(_ql_state)
  _git -C "$d" init -q >/dev/null 2>&1
  printf 'one\n' > "$d/a.txt"
  _git -C "$d" add a.txt
  _git -C "$d" commit -q -m init >/dev/null 2>&1
  printf '%s' "$d"
}
_run_digest() { _ql append --session "$1" --json "{\"at\":\"$2\",\"type\":\"quality_run\",\"command\":\"npm test\",\"exit_code\":0,\"kind\":\"test\",\"worktree_digest\":\"$3\"}"; }

if command -v git >/dev/null 2>&1; then
  _flow_test_begin "digest --cwd: stable for an unchanged tree, 64 hex chars, changes on edit/untracked/mode, not on commit, empty outside git"
  STATE=$(_ql_state)
  WORK=$(_ql_repo)
  D0=$(_ql digest --cwd "$WORK"); EXIT=$?
  assert_exit 0 "$EXIT" "exit 0 inside a repo"
  assert_match '^[0-9a-f]{64}$' "$D0" "sha256 hex"
  assert_equal "$D0" "$(_ql digest --cwd "$WORK")" "deterministic"
  printf 'two\n' >> "$WORK/a.txt"
  D1=$(_ql digest --cwd "$WORK")
  [ "$D0" != "$D1" ] && _flow_assert_pass "tracked edit changes the digest" || _flow_assert_fail "tracked edit did not change the digest"
  _git -C "$WORK" checkout -q -- a.txt
  assert_equal "$D0" "$(_ql digest --cwd "$WORK")" "revert restores the digest"
  printf 'x\n' > "$WORK/untracked.txt"
  D2=$(_ql digest --cwd "$WORK")
  [ "$D0" != "$D2" ] && _flow_assert_pass "new untracked file changes the digest" || _flow_assert_fail "untracked file did not change the digest"
  printf 'y\n' > "$WORK/untracked.txt"
  D3=$(_ql digest --cwd "$WORK")
  [ "$D2" != "$D3" ] && _flow_assert_pass "untracked content edit changes the digest" || _flow_assert_fail "untracked content edit did not change the digest"
  rm -f "$WORK/untracked.txt"
  _git -C "$WORK" commit -q --allow-empty -m empty >/dev/null 2>&1
  D4=$(_ql digest --cwd "$WORK")
  assert_equal "$D0" "$D4" "a commit that leaves the contents alone leaves the digest alone (HEAD is not hashed)"
  printf 'two\n' >> "$WORK/a.txt"
  D5=$(_ql digest --cwd "$WORK")
  _git -C "$WORK" commit -q -am edit >/dev/null 2>&1
  assert_equal "$D5" "$(_ql digest --cwd "$WORK")" "committing an edit keeps the digest the edit produced"
  [ "$D0" != "$D5" ] && _flow_assert_pass "the committed edit still differs from the original tree" || _flow_assert_fail "committed edit not reflected"
  if [ "$(_git -C "$WORK" config --get core.filemode)" = "true" ]; then
    chmod +x "$WORK/a.txt"
    D6=$(_ql digest --cwd "$WORK")
    [ "$D5" != "$D6" ] && _flow_assert_pass "a mode change (chmod +x) changes the digest" || _flow_assert_fail "mode change did not change the digest"
    chmod -x "$WORK/a.txt"
    D4="$D5"
  fi
  mkdir -p "$WORK/sub"
  assert_equal "$D4" "$(_ql digest --cwd "$WORK/sub")" "subdirectory cwd resolves to the same repo digest"
  PLAIN=$(_ql_state)
  OUT=$(_ql digest --cwd "$PLAIN" 2>/dev/null); EXIT=$?
  assert_exit 1 "$EXIT" "exit 1 outside a git repo"
  assert_equal "" "$OUT" "prints nothing outside a git repo"
  assert_equal "" "$(_git -C "$WORK" status --porcelain)" "digest left the repo untouched"
  printf 'staged\n' > "$WORK/a.txt"
  _git -C "$WORK" add a.txt
  printf 'unstaged\n' > "$WORK/a.txt"
  _ql digest --cwd "$WORK" >/dev/null
  assert_equal "staged" "$(_git -C "$WORK" show :a.txt | tr -d '\n')" "digest never rewrites the real index"
  assert_equal "unstaged" "$(tr -d '\n' < "$WORK/a.txt")" "digest never rewrites the working tree"

  _flow_test_begin "status --cwd: sed -i edit with no hook -> dirty with the git-status path; revert -> clean"
  STATE=$(_ql_state)
  WORK=$(_ql_repo)
  D0=$(_ql digest --cwd "$WORK")
  _run_digest s1 2026-09-09T10:00:00Z "$D0"
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=clean" "$OUT" "clean right after the run"
  assert_contains "WORKTREE=unchanged" "$OUT" "worktree unchanged"
  sed -i.bak 's/one/uno/' "$WORK/a.txt" && rm -f "$WORK/a.txt.bak"
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=dirty" "$OUT" "dirty after sed -i (no file_change entry exists)"
  assert_contains "WORKTREE=changed" "$OUT" "worktree changed"
  assert_contains "CHANGED_SINCE=1" "$OUT" "one path from git status"
  assert_contains "CHANGED_FILE=$WORK/a.txt" "$OUT" "absolute path from git status"
  _git -C "$WORK" checkout -q -- a.txt
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=clean" "$OUT" "revert -> clean again"
  assert_contains "WORKTREE=unchanged" "$OUT" "worktree unchanged after revert"

  _flow_test_begin "status --cwd: committing untested edits stays dirty (no files listed); committing tested edits stays clean"
  STATE=$(_ql_state)
  WORK=$(_ql_repo)
  _run_digest s1 2026-09-09T10:00:00Z "$(_ql digest --cwd "$WORK")"
  printf 'edited\n' > "$WORK/a.txt"
  _git -C "$WORK" commit -q -am edit >/dev/null 2>&1
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=dirty" "$OUT" "committing untested edits does not clear the gate"
  assert_contains "WORKTREE=changed" "$OUT" "worktree changed"
  assert_contains "CHANGED_SINCE=0" "$OUT" "git status lists nothing after the commit"
  _run_digest s1 2026-09-09T10:01:00Z "$(_ql digest --cwd "$WORK")"
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=clean" "$OUT" "new passing run on the committed tree -> clean"
  printf 'tested\n' > "$WORK/a.txt"
  _run_digest s1 2026-09-09T10:02:00Z "$(_ql digest --cwd "$WORK")"
  _git -C "$WORK" commit -q -am tested >/dev/null 2>&1
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=clean" "$OUT" "a commit of edits the passing run already tested stays clean"
  assert_contains "WORKTREE=unchanged" "$OUT" "contents unchanged by the commit"
  _git -C "$WORK" checkout -q HEAD~1 -- a.txt
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "STATE=dirty" "$OUT" "checking out different contents -> dirty"

  _flow_test_begin "digest/status --ignore-prefix: bookkeeping writes under ignored prefixes move neither the digest nor the state"
  STATE=$(_ql_state)
  WORK=$(_ql_repo)
  mkdir -p "$WORK/.decisions"
  printf 'old\n' > "$WORK/.decisions/issue-0.md"
  _git -C "$WORK" add .decisions
  _git -C "$WORK" commit -q -m journal >/dev/null 2>&1
  D0=$(cd "$WORK" && _ql digest --cwd "$WORK" --ignore-prefix .decisions --ignore-prefix "$WORK/.flow")
  assert_match '^[0-9a-f]{64}$' "$D0" "digest with excludes"
  _run_digest s1 2026-09-09T10:00:00Z "$D0"
  mkdir -p "$WORK/.flow"
  printf 'edited\n' > "$WORK/.decisions/issue-0.md"
  printf 'j\n' > "$WORK/.decisions/issue-1.md"
  printf 'f\n' > "$WORK/.flow/x"
  assert_equal "$D0" "$(cd "$WORK" && _ql digest --cwd "$WORK" --ignore-prefix .decisions --ignore-prefix "$WORK/.flow")" "tracked edit + new files under ignored prefixes: digest unchanged"
  [ "$D0" != "$(_ql digest --cwd "$WORK")" ] && _flow_assert_pass "without excludes the same tree digests differently" || _flow_assert_fail "excludes had no effect"
  OUT=$(cd "$WORK" && _ql status --session s1 --cwd "$WORK" --ignore-prefix .decisions --ignore-prefix .flow)
  assert_contains "STATE=clean" "$OUT" "bookkeeping-only changes -> clean"
  assert_contains "WORKTREE=unchanged" "$OUT" "worktree unchanged"
  printf 'b\n' > "$WORK/b.txt"
  _change s1 2026-09-09T10:00:01Z "$WORK/b.txt"
  OUT=$(cd "$WORK" && _ql status --session s1 --cwd "$WORK" --ignore-prefix .decisions --ignore-prefix .flow)
  assert_contains "STATE=dirty" "$OUT" "real change -> dirty"
  assert_contains "WORKTREE=changed" "$OUT" "worktree changed"
  assert_contains "CHANGED_SINCE=1" "$OUT" "b.txt counted once (file_change + git status); ignored paths not counted"
  assert_contains "CHANGED_FILE=$WORK/b.txt" "$OUT" "b.txt listed"
  assert_not_contains "issue-1.md" "$OUT" "journal path hidden"
  OUT=$(_ql digest --cwd "$WORK" --ignore-prefix /somewhere/else 2>/dev/null); EXIT=$?
  assert_exit 0 "$EXIT" "a prefix outside the repo is ignored, not an error"

  _flow_test_begin "status without --cwd, or with a run lacking a digest, reports WORKTREE=unknown and uses ledger logic only"
  STATE=$(_ql_state)
  WORK=$(_ql_repo)
  _run_digest s1 2026-09-09T10:00:00Z "$(_ql digest --cwd "$WORK")"
  printf 'edited\n' > "$WORK/a.txt"
  OUT=$(_ql status --session s1)
  assert_contains "STATE=clean" "$OUT" "no --cwd: digest not compared"
  assert_contains "WORKTREE=unknown" "$OUT" "unknown without --cwd"
  _run s1 2026-09-09T10:01:00Z 0
  OUT=$(_ql status --session s1 --cwd "$WORK")
  assert_contains "WORKTREE=unknown" "$OUT" "unknown when the last passing run carries no digest"
  assert_contains "STATE=clean" "$OUT" "ledger logic alone -> clean"
  PLAIN=$(_ql_state)
  OUT=$(_ql status --session s1 --cwd "$PLAIN")
  assert_contains "WORKTREE=unknown" "$OUT" "unknown when --cwd is not a git repo"
else
  _flow_test_begin "git prerequisite for digest tests"
  _flow_assert_pass "SKIP: git not installed"
fi

# --- prune ---------------------------------------------------------------------
_flow_test_begin "prune: removes session dirs idle longer than --max-age-days, keeps fresh ones, skips symlinks"
STATE=$(_ql_state)
mkdir -p "$STATE/sessions/old-a" "$STATE/sessions/old-b/nested" "$STATE/sessions/fresh" "$STATE/sessions/old-but-recent-file"
: > "$STATE/sessions/old-a/quality-ledger.jsonl"
: > "$STATE/sessions/old-b/nested/x"
: > "$STATE/sessions/old-but-recent-file/quality-ledger.jsonl"
touch -d '-20 days' "$STATE/sessions/old-a/quality-ledger.jsonl" "$STATE/sessions/old-a" \
  "$STATE/sessions/old-b/nested/x" "$STATE/sessions/old-b/nested" "$STATE/sessions/old-b" \
  "$STATE/sessions/old-but-recent-file"
OUTSIDE=$(_ql_state)
: > "$OUTSIDE/victim"
ln -s "$OUTSIDE" "$STATE/sessions/link-to-outside"
touch -h -d '-20 days' "$STATE/sessions/link-to-outside" 2>/dev/null || true
OUT=$(_ql prune); EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_equal "PRUNED=2" "$OUT" "two idle dirs pruned"
[ ! -e "$STATE/sessions/old-a" ] && _flow_assert_pass "old-a removed" || _flow_assert_fail "old-a still present"
[ ! -e "$STATE/sessions/old-b" ] && _flow_assert_pass "old-b (nested) removed" || _flow_assert_fail "old-b still present"
[ -d "$STATE/sessions/fresh" ] && _flow_assert_pass "fresh kept" || _flow_assert_fail "fresh removed"
[ -d "$STATE/sessions/old-but-recent-file" ] && _flow_assert_pass "dir with a recent file kept" || _flow_assert_fail "dir with recent file removed"
[ -L "$STATE/sessions/link-to-outside" ] && _flow_assert_pass "symlink entry left alone" || _flow_assert_fail "symlink entry removed"
assert_file_exists "$OUTSIDE/victim" "symlink target untouched"
OUT=$(_ql prune --max-age-days 1)
assert_equal "PRUNED=0" "$OUT" "nothing older than 1 day left"
touch -d '-3 days' "$STATE/sessions/fresh"
OUT=$(_ql prune --max-age-days 2)
assert_equal "PRUNED=1" "$OUT" "custom window prunes the 3-day-old dir"

_flow_test_begin "prune: refuses a symlinked sessions dir / state dir, rejects bad --max-age-days, tolerates a missing sessions dir"
STATE=$(_ql_state)
OUTSIDE=$(_ql_state)
mkdir -p "$OUTSIDE/somewhere"
ln -s "$OUTSIDE" "$STATE/sessions"
ERR=$(_ql prune 2>&1 >/dev/null); EXIT=$?
assert_exit 2 "$EXIT" "symlinked sessions dir -> exit 2"
assert_contains "symlink" "$ERR" "names the symlink"
[ -d "$OUTSIDE/somewhere" ] && _flow_assert_pass "target untouched" || _flow_assert_fail "target removed"
STATE=$(_ql_state)
ERR=$(_ql prune --max-age-days 0 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "0 days rejected"
ERR=$(_ql prune --max-age-days abc 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "non-numeric rejected"
OUT=$(_ql prune); EXIT=$?
assert_exit 0 "$EXIT" "no sessions dir -> exit 0"
assert_equal "PRUNED=0" "$OUT" "PRUNED=0 without a sessions dir"

_flow_test_begin "session-end-state.sh sweeps once per day via .prune-stamp"
SESSION_END="$REPO_ROOT/plugins/flow/hooks/scripts/session-end-state.sh"
STATE=$(_ql_state)
WORK=$(_ql_state)
mkdir -p "$STATE/sessions/stale"
: > "$STATE/sessions/stale/quality-ledger.jsonl"
touch -d '-20 days' "$STATE/sessions/stale/quality-ledger.jsonl" "$STATE/sessions/stale"
OUT=$(cd "$WORK" && printf '{"session_id":"x","reason":"other"}' | FLOW_STATE_DIR="$STATE" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$SESSION_END" 2>&1); EXIT=$?
assert_exit 0 "$EXIT" "hook exit 0"
[ ! -e "$STATE/sessions/stale" ] && _flow_assert_pass "stale session pruned at session end" || _flow_assert_fail "stale session still present"
assert_file_exists "$STATE/.prune-stamp" "sentinel written"
assert_equal "$(date -u +%Y-%m-%d)" "$(cat "$STATE/.prune-stamp")" "sentinel holds today's UTC date"
mkdir -p "$STATE/sessions/stale2"
touch -d '-20 days' "$STATE/sessions/stale2"
(cd "$WORK" && printf '{}' | FLOW_STATE_DIR="$STATE" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$SESSION_END" >/dev/null 2>&1)
[ -d "$STATE/sessions/stale2" ] && _flow_assert_pass "second run the same day does not sweep" || _flow_assert_fail "swept twice in one day"
printf '2000-01-01\n' > "$STATE/.prune-stamp"
(cd "$WORK" && printf '{}' | FLOW_STATE_DIR="$STATE" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$SESSION_END" >/dev/null 2>&1)
[ ! -e "$STATE/sessions/stale2" ] && _flow_assert_pass "stale sentinel -> sweep runs again" || _flow_assert_fail "did not sweep with a stale sentinel"
STATE=$(_ql_state)
OUT=$(cd "$WORK" && printf '{}' | FLOW_STATE_DIR="$STATE" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$SESSION_END" 2>&1); EXIT=$?
assert_exit 0 "$EXIT" "no sessions dir -> exit 0"
[ ! -e "$STATE/.prune-stamp" ] && _flow_assert_pass "no sentinel written when there is nothing to sweep" || _flow_assert_fail "sentinel written without a sessions dir"
