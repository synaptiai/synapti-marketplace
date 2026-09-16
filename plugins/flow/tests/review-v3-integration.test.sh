# Tests for the v3 runtime integration — FlowRun wiring in commands/review.md.
#
# Contract under test:
#   - review.md wires a FlowRun at the end of Phase 1 (FLOW_RUN_STATE block,
#     gated by flow.runtime.enabled), invokes Skill(run-state-management),
#     records activities at the consolidate/report boundaries, and transitions
#     the run to a terminal state at the end of the report phase.
#   - review is FlowRun-only (no FlowGoal) — a review session is bounded by the
#     PR and the PR's own review-thread state is the durable record.
#   - The entry block (between FLOW_RUN_BLOCK_BEGIN/END) is runnable: it emits
#     FLOW_RUN_STATE=create with RUN_ID + WORKFLOW=review-pr when runtime is
#     enabled, and FLOW_RUN_STATE=skip when flow.runtime.enabled is false.
#
# Prereq: jq (cascade-resolve.sh dependency). SKIPS gracefully if absent.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
REVIEW_MD="$PLUGIN_DIR/commands/review.md"
CASCADE="$PLUGIN_DIR/bin/cascade-resolve.sh"

REV_CLEANUP=()
_rev_cleanup() { local p; for p in "${REV_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _rev_cleanup EXIT

CONTENT=$(cat "$REVIEW_MD")

# --- source-presence: FlowRun wiring
_flow_test_begin "review.md wires a FlowRun at entry"
assert_contains "FLOW_RUN_BLOCK_BEGIN" "$CONTENT" "extractable FlowRun block markers present"
assert_contains "FLOW_RUN_STATE=create" "$CONTENT" "emits create state"
assert_contains "WORKFLOW=review-pr" "$CONTENT" "names the review-pr workflow"
assert_contains "flow.runtime.enabled" "$CONTENT" "gated behind runtime.enabled"
assert_contains "run-state-management" "$CONTENT" "delegates to run-state-management skill"

_flow_test_begin "review.md records activities at phase boundaries"
assert_contains "FlowActivity writes" "$CONTENT" "activity-write step documented"
assert_match 'preflight . fan-out . consolidate . report' "$CONTENT" "documents the review phase order"

_flow_test_begin "review.md transitions the FlowRun to terminal state"
assert_contains "FlowRun terminal transition" "$CONTENT" "terminal-transition step documented"
assert_contains "state.status: completed" "$CONTENT" "completes the run on success"
assert_contains "cancelled" "$CONTENT" "cancels the run on failure (not left resumable)"

_flow_test_begin "review is FlowRun-only (no FlowGoal)"
assert_not_contains "goal-contract-capture" "$CONTENT" "review does not create a FlowGoal"
assert_contains "creates NO FlowGoal" "$CONTENT" "documents review creates no goal"

# --- functional: extract the entry block and run it under controlled settings
_extract_run_block() {
  awk '/FLOW_RUN_BLOCK_BEGIN/{f=1;next} /FLOW_RUN_BLOCK_END/{f=0} f' "$REVIEW_MD"
}

_flow_test_begin "entry block emits FLOW_RUN_STATE=create when runtime enabled (default)"
WORK=$(mktemp -d -t flow-rev.XXXXXX); REV_CLEANUP+=("$WORK")
_extract_run_block > "$WORK/block.sh"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=create" "$OUT" "default runtime → create"
assert_contains "WORKFLOW=review-pr" "$OUT" "workflow id emitted"
RUN_ID=$(printf '%s\n' "$OUT" | grep '^RUN_ID=' | cut -d= -f2-)
SCHEMA_PAT=$(jq -r '.properties.metadata.properties.id.pattern' "$PLUGIN_DIR/schemas/v1/run.schema.json")
if printf '%s' "$RUN_ID" | grep -qE "$SCHEMA_PAT"; then _flow_assert_pass "RUN_ID '$RUN_ID' conforms to run.schema"; else _flow_assert_fail "RUN_ID '$RUN_ID' violates /$SCHEMA_PAT/"; fi
assert_contains "review" "$RUN_ID" "RUN_ID carries the review slug"

_flow_test_begin "entry block emits FLOW_RUN_STATE=skip when runtime disabled (v2 mode)"
WORK2=$(mktemp -d -t flow-rev2.XXXXXX); REV_CLEANUP+=("$WORK2")
mkdir -p "$WORK2/.claude"
printf '%s\n' '{"flow":{"runtime":{"enabled":false}}}' > "$WORK2/.claude/settings.flow.json"
_extract_run_block > "$WORK2/block.sh"
OUT2=$(cd "$WORK2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash block.sh 2>/dev/null)
assert_contains "FLOW_RUN_STATE=skip" "$OUT2" "runtime disabled → skip (no-op for v2 projects)"
assert_not_contains "FLOW_RUN_STATE=create" "$OUT2" "does not create when disabled"

# --- #213 AC1: Phase 1 reads the FlowGoal -------------------------------------

RG_TMP=$(mktemp -d -t flow-rev213.XXXXXX); REV_CLEANUP+=("$RG_TMP")

_flow_test_begin "review.md Phase 1 carries a runnable FlowGoal block"
RG_MD="$REPO_ROOT/plugins/flow/commands/review.md"
_rg_block() {
  awk -v b="# FLOWGOAL_BLOCK_BEGIN" -v e="# FLOWGOAL_BLOCK_END" '
    { t = $0; sub(/^[ \t]+/, "", t) }
    t == b { f = 1; next }
    t == e { f = 0 }
    f' "$RG_MD"
}
_rg_block > "$RG_TMP/flowgoal.sh"
assert_match '[^[:space:]]' "$(cat "$RG_TMP/flowgoal.sh")" "FlowGoal block extracted"

# The goal arrives with the checkout, so every value in it is the author's data.
# Nothing in the block may hand a goal value to a shell.
RG_SRC=$(cat "$RG_TMP/flowgoal.sh")
assert_not_contains 'eval' "$RG_SRC" "no eval anywhere in the block"
assert_not_contains 'bash -c' "$RG_SRC" "no bash -c"
assert_not_contains 'sh -c' "$RG_SRC" "no sh -c"
# The python reader names the field because it reads it; what must never happen
# is a SHELL line touching a goal value, so assert on the shell half only.
awk '/<<.FLOW_GOAL_READ./ { skip = 1; next } /^FLOW_GOAL_READ$/ { skip = 0; next } !skip' \
  "$RG_TMP/flowgoal.sh" > "$RG_TMP/flowgoal-shell.sh"
assert_match '[^[:space:]]' "$(cat "$RG_TMP/flowgoal-shell.sh")" "shell half extracted"
assert_equal "0" "$(grep -c 'verification_command' "$RG_TMP/flowgoal-shell.sh" | tr -d ' ')" \
  "no shell line touches a verification_command value"
assert_equal "0" "$(grep -cE '\$\(.*(AC|GOAL_STATUS|RISK_MAP|verification)' "$RG_TMP/flowgoal-shell.sh" | tr -d ' ')" \
  "no command substitution over a goal value"

# _rg_run <dir> <LINKED> — runs the block in <dir>; sets RG_OUT, RG_CODE.
# The directory matters: a correct block reads the pull request head over the
# API and does not care what is in the tree it runs in.
_rg_run() {
  RG_OUT=$(cd "$1" && PATH="$RG_STUB:$PATH" LINKED="$2" PR_NUM=7 REPO=o/r \
    bash "$RG_TMP/flowgoal.sh" 2>"$RG_TMP/rg.err")
  RG_CODE=$?
}

mkdir -p "$RG_TMP/stub"
RG_STUB="$RG_TMP/stub"
# The stub answers the three calls the block makes, matched on the request path
# rather than on argument position, because `gh api --paginate` shifts them.
# The 404 shape is the one observed from real gh: the error body on stdout, the
# message on stderr, exit 1 — which is what makes "branch on the exit status,
# never on the output" a claim a test can fail.
cat > "$RG_STUB/gh" <<'STUB'
#!/usr/bin/env bash
ARGS="$*"
case "$ARGS" in
  *"pr view"*headRefOid*)
    [ -n "${STUB_HEAD_SHA-}" ] || { echo "gh: no head" >&2; exit 1; }
    printf '%s\n' "$STUB_HEAD_SHA"; exit 0 ;;
  *contents/*)
    # `gh api -i` answers with the status line, the headers, a blank line and
    # the body — the shape the block reads the HTTP status out of.
    case "${STUB_CONTENT_MODE:-ok}" in
      404)  printf 'HTTP/2.0 404 Not Found\r\nContent-Type: application/json\r\n\r\n'
            printf '%s\n' '{"message":"Not Found","status":"404"}'
            echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      fail) echo "gh: could not connect to api.github.com" >&2; exit 4 ;;
      403)  printf 'HTTP/2.0 403 Forbidden\r\nContent-Type: application/json\r\n\r\n'
            printf '%s\n' '{"message":"API rate limit exceeded"}'
            echo "gh: Forbidden (HTTP 403)" >&2; exit 1 ;;
      empty) printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
            printf '%s\n' '{"content":""}'; exit 0 ;;
      *)    [ -f "${STUB_GOAL_FILE-}" ] || { echo "stub: STUB_GOAL_FILE unset" >&2; exit 9; }
            printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
            printf '{"content":"%s"}\n' "$(base64 < "$STUB_GOAL_FILE" | tr -d '\n')"; exit 0 ;;
    esac ;;
  *pulls/*files*)
    [ "${STUB_FILES_EXIT:-0}" = "0" ] || { echo "gh: api error" >&2; exit "${STUB_FILES_EXIT}"; }
    # Reproduce the server-side select: the caller passes the path it cares
    # about inside the jq filter, and gets a status back only for that path.
    case "$ARGS" in
      *"${STUB_CHANGED_FILE:-__none__}"*) [ -n "${STUB_FILE_STATUS-}" ] && printf '%s\n' "$STUB_FILE_STATUS" ;;
    esac
    exit 0 ;;
esac
echo "gh: unstubbed call: $ARGS" >&2
exit 1
STUB
chmod +x "$RG_STUB/gh"

# Defaults every case inherits: a head commit exists, the goal file is served
# from it, and the pull request does not touch the goal.
export STUB_HEAD_SHA=abc123def456
export STUB_GOAL_FILE="$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml"
export STUB_FILE_STATUS=""
export STUB_CHANGED_FILE=".flow/goals/issue-42.goal.yaml"
export STUB_CONTENT_MODE=ok
export STUB_FILES_EXIT=0

_flow_test_begin "FlowGoal: the goal read is the one at the pull request head, not the one in the tree"
# The `!` fence runs at command load, BEFORE the inline `gh pr checkout`, so the
# working tree is whatever branch the reviewer happened to be on. Reviewing from
# a tree with no .flow/ at all must still read the goal the pull request carries.
RG_BARE="$RG_TMP/bare-tree"
mkdir -p "$RG_BARE"
_rg_run "$RG_BARE" 42
assert_exit 0 "$RG_CODE" "block ran: $(cat "$RG_TMP/rg.err")"
assert_contains "STATE=ok" "$RG_OUT" "a tree with no .flow/ still reads the head goal"
assert_contains "GOAL_REF=abc123def456" "$RG_OUT" "and names the revision it read"
assert_contains "GOAL_PATH=.flow/goals/issue-42.goal.yaml" "$RG_OUT" "names the path it read"
assert_contains "GOAL_STATUS=" "$RG_OUT" "reports the lifecycle status"
assert_match 'AC=AC1\|' "$RG_OUT" "one AC line per criterion, id first"
assert_contains "NON_GOAL=" "$RG_OUT" "non-goals are handed over"
assert_contains "CONTRACT=" "$RG_OUT" "interface contracts are handed over"
assert_match 'RISK_MAP=.*\|goal$' "$RG_OUT" "a row from the goal is labelled as coming from the goal"
assert_contains "RISK_MAP_SOURCE=goal" "$RG_OUT" "and the source is stated"
# A stale goal sitting in the reviewer tree must not be what gets read.
RG_STALE="$RG_TMP/stale-tree"
mkdir -p "$RG_STALE/.flow/goals"
printf 'lifecycle: {status: STALE-TREE-COPY}\n' > "$RG_STALE/.flow/goals/issue-42.goal.yaml"
_rg_run "$RG_STALE" 42
assert_not_contains "STALE-TREE-COPY" "$RG_OUT" "the working-tree copy is never the one read"

_flow_test_begin "FlowGoal: reading a goal cannot execute code the pull request ships"
# `gh pr checkout` leaves the pull request in the tree, so an interpreter that
# puts the working directory on its import path would import a module the author
# wrote. PYTHONSAFEPATH covers this only on Python 3.11 and newer, so the reader
# scrubs sys.path as well and this case holds on any interpreter.
RG_HOSTILE="$RG_TMP/hostile-import"
RG_MARKER="$RG_TMP/hostile-import-ran"
mkdir -p "$RG_HOSTILE"
cat > "$RG_HOSTILE/yaml.py" <<PYEVIL
import os
open("$RG_MARKER", "w").write("executed")
def safe_load(*a, **k):
    return {"lifecycle": {"status": "FORGED"}}
PYEVIL
_rg_run "$RG_HOSTILE" 42
if [ -e "$RG_MARKER" ]; then
  _flow_assert_fail "a yaml.py shipped by the pull request executed: $RG_MARKER exists"
else
  _flow_assert_pass "a yaml.py in the checked-out tree is never imported"
fi
assert_not_contains "FORGED" "$RG_OUT" "and cannot forge the section the reviewer reads"

# PYTHONSAFEPATH is honoured from Python 3.11. On anything older it is ignored
# and the import path is whatever the interpreter built, so the scrub inside the
# reader is the half that has to hold on its own. This stub is an interpreter
# that ignores the variable, which is what an older python3 is.
mkdir -p "$RG_TMP/oldpy"
RG_REAL_PY=$(command -v python3)
cat > "$RG_TMP/oldpy/python3" <<OLDPY
#!/usr/bin/env bash
exec env -u PYTHONSAFEPATH "$RG_REAL_PY" "\$@"
OLDPY
chmod +x "$RG_TMP/oldpy/python3"
RG_MARKER_OLD="$RG_TMP/hostile-import-ran-old"
cat > "$RG_HOSTILE/yaml.py" <<PYEVIL
import os
open("$RG_MARKER_OLD", "w").write("executed")
def safe_load(*a, **k):
    return {"lifecycle": {"status": "FORGED"}}
PYEVIL
RG_OUT=$(cd "$RG_HOSTILE" && PATH="$RG_TMP/oldpy:$RG_STUB:$PATH" LINKED=42 PR_NUM=7 REPO=o/r   bash "$RG_TMP/flowgoal.sh" 2>/dev/null)
if [ -e "$RG_MARKER_OLD" ]; then
  _flow_assert_fail "on an interpreter that ignores PYTHONSAFEPATH the shipped yaml.py ran"
else
  _flow_assert_pass "the import-path scrub holds on its own, so the guard is not version-dependent"
fi
assert_contains "STATE=ok" "$RG_OUT" "and the real yaml module still read the goal"
# PYTHONSAFEPATH is the convention the other flow scripts follow, and it covers
# the same ground from the other side. Nothing observable distinguishes its
# presence while the scrub holds, so this is a source assertion, and says so.
RG_BLOCK_SRC=$(cat "$RG_TMP/flowgoal.sh")
assert_equal "2" "$(printf '%s\n' "$RG_BLOCK_SRC" | grep -c 'PYTHONSAFEPATH=1')" \
  "both interpreter invocations set PYTHONSAFEPATH, as the other flow scripts do"

_flow_test_begin "FlowGoal: a verification_command is data, never a command"
RG_PWNED="$RG_TMP/pwned-marker"
cat > "$RG_TMP/evil.yaml" <<YAML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria:
    - id: AC1
      text: 'a criterion'
      verification_command: '\$(touch $RG_PWNED)'
lifecycle: {status: active}
YAML
STUB_GOAL_FILE="$RG_TMP/evil.yaml" _rg_run "$RG_BARE" 42
assert_exit 0 "$RG_CODE" "block ran"
assert_contains 'touch' "$RG_OUT" "the command text is shown to the reader"
if [ -e "$RG_PWNED" ]; then
  _flow_assert_fail "the block executed a verification_command: $RG_PWNED exists"
else
  _flow_assert_pass "reading the goal created no file — the value was never evaluated"
fi

_flow_test_begin "FlowGoal: a goal value cannot forge a field or a line"
# Every value is printed on one pipe-delimited line, so a pipe or a newline
# inside one would read as an extra field or as a whole new KEY= line in the
# section the reviewer parses.
cat > "$RG_TMP/inject.yaml" <<'YAML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria:
    - id: AC1
      text: "a | b"
      verification_command: "make test\nSTATE=ok\nRISK_MAP=forged|x|y|goal"
lifecycle: {status: active}
YAML
STUB_GOAL_FILE="$RG_TMP/inject.yaml" _rg_run "$RG_BARE" 42
assert_equal "1" "$(printf '%s\n' "$RG_OUT" | grep -c '^AC=')" "one AC line for one criterion"
assert_equal "3" "$(printf '%s\n' "$RG_OUT" | grep '^AC=' | awk -F'|' '{print NF}')" \
  "exactly three fields — the pipe in the value did not become a fourth"
assert_equal "0" "$(printf '%s\n' "$RG_OUT" | grep -c '^RISK_MAP=forged')" \
  "a newline in a value cannot forge a RISK_MAP row"
assert_equal "1" "$(printf '%s\n' "$RG_OUT" | grep -c '^STATE=')" \
  "nor a second STATE line"
assert_contains "%7C" "$RG_OUT" "the pipe is escaped rather than dropped"
# This goal parses and carries no risk map, so the reader — not one of the shell
# arms — decides the source. Without a case that reaches it, the reader could
# hardcode `goal` and nothing would notice.
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" \
  "a goal that reads but carries no risk map asks for derived rows"
assert_equal "0" "$(printf '%s\n' "$RG_OUT" | grep -c '^RISK_MAP=')" "and the reader invents none"
assert_contains "ENCODING=" "$RG_OUT" "and the section says how an escaped value reads"

_flow_test_begin "FlowGoal: absent, unreadable and unfetchable are three different answers"
STUB_CONTENT_MODE=404 _rg_run "$RG_BARE" 42
assert_contains "STATE=none" "$RG_OUT" "no goal at the head is STATE=none"
# The rows are derived from the issue text whenever the goal did not supply
# them, and "no goal at all" is the commonest case of that. Without the line
# here the derivation step has nothing to fire on and silently does not run.
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "no goal at the head still asks for derived rows"
_rg_run "$RG_BARE" none
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "and so does a pull request with no linked issue"
STUB_CONTENT_MODE=fail _rg_run "$RG_BARE" 42
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "and so does a goal that could not be read"
STUB_HEAD_SHA="" _rg_run "$RG_BARE" 42
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "and so does an unresolvable head commit"
RG_SRC_NOW=$(cat "$RG_TMP/flowgoal.sh")
assert_equal "0" "$(printf '%s\n' "$RG_SRC_NOW" | grep -c 'RISK_MAP_SOURCE=none')" \
  "there is no fourth answer: the rows come from the goal or from the issue text"

STUB_CONTENT_MODE=403 _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "a refusal is unavailable, not an absent goal"
assert_not_contains "STATE=none" "$RG_OUT" "and is never read as absent"
assert_contains "403" "$RG_OUT" "and the reason names the status"
STUB_CONTENT_MODE=fail _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "a failed fetch is unavailable, not absent"
assert_not_contains "STATE=none" "$RG_OUT" "never reported as no goal"
assert_contains "REASON=" "$RG_OUT" "and says why"
STUB_CONTENT_MODE=empty _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "empty content (a goal over 1MB) is unavailable"
# Without its own arm this lands on the parser and reports a parse failure, which
# sends a reader looking for a syntax error in a file that is fine.
# An empty file and a file too large to serve both arrive as empty content, so
# the reason names both rather than sending a reader to look for a 1MB file that
# is zero bytes.
assert_match 'REASON=.*(empty|no content)' "$RG_OUT" "and the reason names what the API actually did"
assert_not_contains "did not read as a goal:" "$RG_OUT" "rather than blaming the goal text"
STUB_HEAD_SHA="" _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "no resolvable head commit is unavailable"
assert_not_contains "STATE=none" "$RG_OUT" "and not reported as no goal"
_rg_run "$RG_BARE" none
assert_contains "STATE=none" "$RG_OUT" "no linked issue is STATE=none"
# `unavailable` is what the linked-issue helper returns when the LOOKUP failed —
# no repository resolved, helper missing, or gh could not read the pull request.
# Answering that with "the pull request links no issue" asserts a fact that was
# never established, and drops the goal silently.
_rg_run "$RG_BARE" unavailable
assert_contains "STATE=unavailable" "$RG_OUT" "a failed linked-issue lookup is unavailable"
assert_not_contains "STATE=none" "$RG_OUT" "never the claim that no issue is linked"
assert_contains "GOAL_EDITED=unavailable" "$RG_OUT" "and what the pull request does to its goal is unknown too"
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "while the derivation step still has its trigger"
printf ': not: yaml:\n  - [\n' > "$RG_TMP/bad.yaml"
STUB_GOAL_FILE="$RG_TMP/bad.yaml" _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "a goal that does not parse is unavailable"
assert_not_contains "STATE=ok" "$RG_OUT" "and is never announced as read"

_flow_test_begin "FlowGoal: a goal cannot make the section unbounded"
# yaml.safe_load shares alias nodes, so the load is cheap; str() on the result
# is not. Six levels of ten aliases in a few hundred bytes expands to megabytes
# on one line, and each further level multiplies it.
{
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowGoal\nmetadata: {id: issue-42}\n'
  printf 'x0: &a0 [zzzzzzzzzz, zzzzzzzzzz, zzzzzzzzzz, zzzzzzzzzz, zzzzzzzzzz]\n'
  for BOMB_I in 1 2 3 4 5 6; do
    printf 'x%s: &a%s [*a%s, *a%s, *a%s, *a%s, *a%s, *a%s, *a%s, *a%s, *a%s, *a%s]\n' \
      "$BOMB_I" "$BOMB_I" $(($BOMB_I - 1)) $(($BOMB_I - 1)) $(($BOMB_I - 1)) $(($BOMB_I - 1)) \
      $(($BOMB_I - 1)) $(($BOMB_I - 1)) $(($BOMB_I - 1)) $(($BOMB_I - 1)) $(($BOMB_I - 1)) $(($BOMB_I - 1))
  done
  printf 'objective:\n  outcome: x\n  acceptance_criteria:\n    - id: AC1\n      text: *a6\n'
  printf '      verification_command: make test\nlifecycle: {status: active}\n'
} > "$RG_TMP/bomb.yaml"
STUB_GOAL_FILE="$RG_TMP/bomb.yaml" _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "a goal built out of aliases does not read"
assert_not_contains "STATE=ok" "$RG_OUT" "and is never announced as read"
BOMB_BYTES=$(printf '%s' "$RG_OUT" | wc -c | tr -d ' ')
if [ "$BOMB_BYTES" -lt 16384 ]; then
  _flow_assert_pass "the section stays bounded ($BOMB_BYTES bytes)"
else
  _flow_assert_fail "the section expanded to $BOMB_BYTES bytes"
fi
# A single enormous scalar is the other way to flood the section.
{
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowGoal\nmetadata: {id: issue-42}\n'
  printf 'objective:\n  outcome: x\n  acceptance_criteria:\n    - id: AC1\n      text: "'
  BOMB_PAD=$(awk 'BEGIN { while (i++ < 4000) printf "wide " }')
  printf '%s' "$BOMB_PAD"
  printf '"\n      verification_command: make test\nlifecycle: {status: active}\n'
} > "$RG_TMP/wide.yaml"
STUB_GOAL_FILE="$RG_TMP/wide.yaml" _rg_run "$RG_BARE" 42
WIDE_LINE=$(printf '%s\n' "$RG_OUT" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
if [ "$WIDE_LINE" -lt 4096 ]; then
  _flow_assert_pass "one value cannot make one line unbounded ($WIDE_LINE chars)"
else
  _flow_assert_fail "a single value printed $WIDE_LINE characters on one line"
fi

_flow_test_begin "FlowGoal: a criterion of the wrong shape is not silently dropped"
# Announcing STATE=ok with no AC= line says "this goal names no criteria",
# which is what an empty list means. A goal whose criteria are strings named
# two, and the review would be told it named none.
cat > "$RG_TMP/acstrings.yaml" <<'YAML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria:
    - 'do the thing'
    - 'and the other'
lifecycle: {status: active}
YAML
STUB_GOAL_FILE="$RG_TMP/acstrings.yaml" _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "criteria of the wrong shape make the goal unreadable"
assert_not_contains "STATE=ok" "$RG_OUT" "rather than a goal that names none"

_flow_test_begin "FlowGoal: a reader that dies says so"
# The reader is a child process. If it is killed — out of memory, a crash — and
# prints nothing, the section would end after GOAL_REF= with no STATE= line at
# all, and every rule keyed on those lines silently does not fire.
mkdir -p "$RG_TMP/deadpy"
cat > "$RG_TMP/deadpy/python3" <<'DEADPY'
#!/usr/bin/env bash
# The import probe succeeds; the reader (fed a script on stdin) dies mutely.
case "$*" in
  *"import yaml"*) exit 0 ;;
esac
cat >/dev/null
exit 137
DEADPY
chmod +x "$RG_TMP/deadpy/python3"
RG_OUT=$(cd "$RG_BARE" && PATH="$RG_TMP/deadpy:$RG_STUB:$PATH" LINKED=42 PR_NUM=7 REPO=o/r   bash "$RG_TMP/flowgoal.sh" 2>/dev/null)
assert_contains "STATE=unavailable" "$RG_OUT" "a reader that dies is unavailable"
assert_equal "1" "$(printf '%s\n' "$RG_OUT" | grep -c '^STATE=')" "exactly one STATE line, always"
assert_contains "RISK_MAP_SOURCE=issue-text" "$RG_OUT" "and the derivation step still has its trigger"

_flow_test_begin "FlowGoal: valid YAML of the wrong shape is unavailable, not ok"
# A hand-edited goal can be valid YAML and still not be a goal. Announcing
# STATE=ok and then failing mid-extraction reads exactly like a goal with no
# criteria, so the review proceeds believing it read the specification.
printf 'lifecycle: active\n' > "$RG_TMP/shape1.yaml"
STUB_GOAL_FILE="$RG_TMP/shape1.yaml" _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "a scalar where a mapping belongs is unavailable"
assert_not_contains "STATE=ok" "$RG_OUT" "never announced as read"
printf 'objective: not-a-mapping\nlifecycle: {status: active}\n' > "$RG_TMP/shape2.yaml"
STUB_GOAL_FILE="$RG_TMP/shape2.yaml" _rg_run "$RG_BARE" 42
assert_contains "STATE=unavailable" "$RG_OUT" "an objective that is not a mapping is unavailable"
assert_equal "0" "$(printf '%s\n' "$RG_OUT" | grep -c '^STATE=ok')" "no STATE=ok was printed first"
printf 'specification:\n  non_goals: a string\nlifecycle: {status: active}\n' > "$RG_TMP/shape3.yaml"
STUB_GOAL_FILE="$RG_TMP/shape3.yaml" _rg_run "$RG_BARE" 42
assert_equal "0" "$(printf '%s\n' "$RG_OUT" | grep -c '^NON_GOAL=.$')" \
  "a string is not iterated one character per non-goal"

_flow_test_begin "FlowGoal: a goal written in prose still reads on an ascii stdout"
# Goal text is written by people and carries em dashes, quotes and accents. When
# the interpreter resolves stdout to ascii — a C locale with the PEP 538
# coercion turned off, which is a shape CI runners come in — printing such a
# value raises, and it raises AFTER the section has said it read the goal.
cat > "$RG_TMP/prose.yaml" <<'YAML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria:
    - id: AC1
      text: 'the fence runs before the checkout — so the tree is not the pull request'
      verification_command: 'make test'
specification:
  non_goals: ['no cross-repository consumers — flow has no linked-repository model']
lifecycle: {status: active}
YAML
RG_OUT=$(cd "$RG_BARE" && PATH="$RG_STUB:$PATH" LINKED=42 PR_NUM=7 REPO=o/r   STUB_GOAL_FILE="$RG_TMP/prose.yaml"   PYTHONCOERCECLOCALE=0 PYTHONUTF8=0 LC_ALL=C LANG=C   bash "$RG_TMP/flowgoal.sh" 2>"$RG_TMP/rg.err")
assert_equal "1" "$(printf '%s\n' "$RG_OUT" | grep -c '^AC=')" \
  "the criterion is printed, not lost to an encoding error"
assert_contains "STATE=ok" "$RG_OUT" "and the goal reads"
assert_equal "0" "$(grep -c 'UnicodeEncodeError' "$RG_TMP/rg.err")" "with no encoding error"
assert_contains "NON_GOAL=" "$RG_OUT" "and extraction continues past the criterion"

_flow_test_begin "FlowGoal: a goal that names no criteria is a goal, not an unreadable file"
# The specification calls zero acceptance criteria valid input: the review falls
# back to the issue text. Reporting it as unreadable would say the goal is
# broken when it is merely empty.
cat > "$RG_TMP/nocrit.yaml" <<'YAML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: issue-42}
objective:
  outcome: x
  acceptance_criteria: []
specification:
  non_goals: ['one non-goal']
lifecycle: {status: active}
YAML
STUB_GOAL_FILE="$RG_TMP/nocrit.yaml" _rg_run "$RG_BARE" 42
assert_contains "STATE=ok" "$RG_OUT" "a goal with no criteria still reads"
assert_equal "0" "$(printf '%s\n' "$RG_OUT" | grep -c '^AC=')" "and prints no criteria"
assert_contains "NON_GOAL=one non-goal" "$RG_OUT" "while the rest of the specification is still handed over"

_flow_test_begin "FlowGoal: the block is inert without python3 or PyYAML"
mkdir -p "$RG_TMP/nopy"
cat > "$RG_TMP/nopy/python3" <<'NOPY'
#!/usr/bin/env bash
exit 127
NOPY
chmod +x "$RG_TMP/nopy/python3"
RG_OUT=$(cd "$RG_BARE" && PATH="$RG_TMP/nopy:$RG_STUB:$PATH" LINKED=42 PR_NUM=7 REPO=o/r \
  bash "$RG_TMP/flowgoal.sh" 2>/dev/null)
assert_contains "STATE=unavailable" "$RG_OUT" "no usable python3 is unavailable"
assert_not_contains "STATE=ok" "$RG_OUT" "and nothing is claimed to have been read"

_flow_test_begin "FlowGoal: creating a goal and weakening one are different answers"
# A spec-first pull request creates its own goal; that is the normal flow and
# says nothing about weakening. Only a change to a goal that already existed on
# the base is the trust signal the decision asked for.
STUB_FILE_STATUS=added _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=created" "$RG_OUT" "adding the goal in this pull request is not an edit"
STUB_FILE_STATUS=modified _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=modified" "$RG_OUT" "changing an existing goal is"
# A deleted goal is not fetchable at the head, so this is the only shape the
# removed case can arrive in: the content 404s and the file list says removed.
STUB_FILE_STATUS=removed STUB_CONTENT_MODE=404 _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=removed" "$RG_OUT" "so is deleting it"
assert_contains "STATE=none" "$RG_OUT" "and the goal is correctly absent at the head"
STUB_FILE_STATUS="" _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=no" "$RG_OUT" "a pull request that leaves it alone is not"
# The probe must answer for THIS goal. A path test that matched the directory
# let any goal in the pull request set the flag for the goal under review.
STUB_CHANGED_FILE=".flow/goals/issue-999.goal.yaml" STUB_FILE_STATUS=modified _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=no" "$RG_OUT" "a different issue goal in the same pull request does not set the flag"
STUB_CONTENT_MODE=404 STUB_FILE_STATUS="" _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=no" "$RG_OUT" "the flag is reported even when there is no goal to read"
STUB_HEAD_SHA="" STUB_FILE_STATUS=modified _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=modified" "$RG_OUT" "and even when the head commit cannot be resolved"
STUB_FILES_EXIT=4 _rg_run "$RG_BARE" 42
assert_contains "GOAL_EDITED=unavailable" "$RG_OUT" "a failed file-list call is unavailable"
assert_not_contains "GOAL_EDITED=no" "$RG_OUT" \
  "never 'no' — that is the answer meaning this pull request does not weaken its goal"

unset STUB_HEAD_SHA STUB_GOAL_FILE STUB_FILE_STATUS STUB_CHANGED_FILE \
      STUB_CONTENT_MODE STUB_FILES_EXIT

# --- #213 AC2: the risk map reaches the two places that can check it ----------

_flow_test_begin "holdout-validation is handed risk-map coverage, and the reviewer is handed the rows"
RG_REVIEW=$(cat "$RG_MD")
# Every holdout dispatch — both Path A lenses and Path B — must offer the
# coverage list, or the skill's risk-map step has nothing to read and skips.
RG_DISPATCHES=$(printf '%s\n' "$RG_REVIEW" | grep -c 'Evidence bundle draft:')
assert_equal "3" "$RG_DISPATCHES" "three dispatches: two Path A lenses and Path B"
RG_WITH_COVERAGE=$(printf '%s\n' "$RG_REVIEW" | grep -c 'Evidence bundle draft:.*Risk map coverage')
assert_equal "3" "$RG_WITH_COVERAGE" "each one hands over the coverage list"
# Gating the list on "Phase 1 reported one" omits it on every pull request whose
# rows were derived, and the skill's coverage step then silently skips.
assert_equal "3" "$(printf '%s\n' "$RG_REVIEW" | grep -c 'Risk map coverage.*derivation step above produced them')" \
  "and offers it for derived rows as well as goal rows"
assert_contains 'area> → <test file:line' "$RG_REVIEW" "the shape of a coverage row is stated"
assert_contains 'RISK_MAP_SOURCE' "$RG_REVIEW" "and the reviewer is told where the rows came from"

RG_REVIEWER=$(cat "$REPO_ROOT/plugins/flow/agents/code-reviewer.md")
assert_match 'Risk areas:' "$RG_REVIEWER" "the reviewer names Risk areas"
# A line the agent is required to emit needs a slot in the template it copies,
# or the requirement has nowhere to land.
RG_SUMMARY=$(printf '%s\n' "$RG_REVIEWER" | awk '/^### Summary/ { f = 1; next } f && /^#{1,3} / { f = 0 } f')
assert_contains 'callers examined:' "$RG_SUMMARY" "the Summary template carries the caller-count line"
assert_contains 'Inputs' "$RG_REVIEWER" "Step 4 states its inputs"
# The rule at Step 4 already consumes `Risk areas:` rows; the gap was that
# nothing handed them over, so the rule could never fire.
RG_STEP4=$(printf '%s\n' "$RG_REVIEWER" | awk '/^### Step 4/ { f = 1 } f && /^### Step 5/ { f = 0 } f')
assert_contains 'Risk areas:' "$RG_STEP4" "Step 4 names the input"
assert_contains 'source' "$RG_STEP4" "and says a derived row is marked as derived"

_flow_test_begin "every reviewer that can check the risk map is handed it"
# Path B was handed the rows; the two Path A code-reviewer variants were not, so
# on the agent-teams path — the one this project reviews itself with — the
# reviewer's Inputs block read "no goal" even when Phase 1 had printed one.
RG_CR_DISPATCH=$(printf '%s\n' "$RG_REVIEW" | grep -c '^Agent(code-reviewer')
assert_equal "3" "$RG_CR_DISPATCH" "three code-reviewer dispatches: two Path A lenses and Path B"
RG_CR_WITH_RISK=$(printf '%s\n' "$RG_REVIEW" | awk '
  /^Agent\(code-reviewer/ { n++; have[n] = 0 }
  n && /Risk areas:/ { have[n] = 1 }
  END { c = 0; for (i = 1; i <= n; i++) c += have[i]; print c }')
assert_equal "3" "$RG_CR_WITH_RISK" "each one is handed the risk areas"
# A dispatch that says `none` when Phase 1 reported no goal excludes exactly the
# rows the derivation step exists to produce, which is the commonest case.
RG_CR_DERIVED=$(printf '%s\n' "$RG_REVIEW" | awk '
  /^Agent\(code-reviewer/ { n++; have[n] = 0 }
  n && /derived from the issue text by the step above/ { have[n] = 1 }
  END { c = 0; for (i = 1; i <= n; i++) c += have[i]; print c }')
assert_equal "3" "$RG_CR_DERIVED" "and each one counts the derived rows as rows"
assert_equal "0" "$(printf '%s\n' "$RG_REVIEW" | grep -c '`none` when Phase 1 reported no goal')" \
  "no dispatch tells the reviewer there are no rows when the derivation step makes some"
RG_CR_WITH_NG=$(printf '%s\n' "$RG_REVIEW" | awk '
  /^Agent\(code-reviewer/ { n++; have[n] = 0 }
  n && /Non-goals:/ { have[n] = 1 }
  END { c = 0; for (i = 1; i <= n; i++) c += have[i]; print c }')
assert_equal "3" "$RG_CR_WITH_NG" "and the non-goals"
RG_CR_WITH_CT=$(printf '%s\n' "$RG_REVIEW" | awk '
  /^Agent\(code-reviewer/ { n++; have[n] = 0 }
  n && /Interface contracts:/ { have[n] = 1 }
  END { c = 0; for (i = 1; i <= n; i++) c += have[i]; print c }')
assert_equal "3" "$RG_CR_WITH_CT" "and the interface contracts"

_flow_test_begin "an empty risk-map coverage list says why it is empty"
# holdout-validation step 5 treats a bare `none` as a coverage gap, and
# references/evidence-bundle-format.md accepts only `none — {reason}`.
RG_BARE_NONE=$(printf '%s\n' "$RG_REVIEW" | grep -c "discriminating check, or \`none\`\.")
assert_equal "0" "$RG_BARE_NONE" "no dispatch offers a bare none"
RG_REASONED_NONE=$(printf '%s\n' "$RG_REVIEW" | grep -c 'none — ')
assert_equal "3" "$RG_REASONED_NONE" "all three dispatches ask for a reason with it"

_flow_test_begin "with no risk map in the goal, a step derives the rows from the issue text"
# The user decision is that the rows are derived from the issue text rather than
# reported as absent. The block cannot derive them — it emits the scalar
# RISK_MAP_SOURCE=issue-text — so a step has to, and every row it renders has to
# carry the label that keeps a derived row from reading as specification.
RG_DERIVE=$(printf '%s\n' "$RG_REVIEW" | awk '/^### Deriving the risk map/ { f = 1; next } f && /^#{1,3} / { f = 0 } f')
assert_match '[^[:space:]]' "$RG_DERIVE" "the derivation step exists"
assert_contains 'RISK_MAP_SOURCE=issue-text' "$RG_DERIVE" "it fires on the state the block reports"
assert_contains 'gh issue view' "$RG_DERIVE" "it reads the issue body, which Phase 1 does not fetch"
assert_contains '|issue-text' "$RG_DERIVE" "every row it renders is labelled as derived"
assert_match 'RISK_MAP=<area>' "$RG_DERIVE" "in the same shape the goal rows use"
assert_contains 'plausible' "$RG_DERIVE" "a row names the plausible wrong version"
assert_contains 'discriminating' "$RG_DERIVE" "and the input that tells right from wrong"
assert_contains 'RISK_MAP_SOURCE=goal' "$RG_DERIVE" "and it does not fire when the goal carried rows"
# The derived rows have to reach the same two consumers the goal rows reach, or
# deriving them changes nothing.
assert_contains 'issue-text' "$RG_REVIEW" "the label travels to the dispatches"

_flow_test_begin "the review never tells anyone to run a gh call that gh rejects"
# `gh pr diff <N> -- <path>` is "accepts at most 1 arg(s), received 2". The goal
# hunk comes from the file list the section already reads.
assert_equal "0" "$(printf '%s\n' "$RG_REVIEW" | grep -c 'gh pr diff[^|]*--[[:space:]]\+[^-]')" \
  "no instruction passes a pathspec to gh pr diff"

_flow_test_begin "a pull request that changes its own goal raises a finding"
# GOAL_EDITED was printed and never read: no phase, dispatch or template
# mentioned it, so the trust decision stopped at the flag.
RG_CONSUME=$(printf '%s\n' "$RG_REVIEW" | grep -c 'GOAL_EDITED')
assert_match '^[2-9]|^[0-9][0-9]' "$RG_CONSUME" "GOAL_EDITED is read somewhere, not only printed"
RG_TRUST=$(printf '%s\n' "$RG_REVIEW" | awk '/^### When the pull request changes its own goal/ { f = 1; next } f && /^#{1,3} / { f = 0 } f')
assert_match '[^[:space:]]' "$RG_TRUST" "a named step reads the flag"
assert_contains 'modified' "$RG_TRUST" "and keys on the modified state"
assert_contains 'finding' "$RG_TRUST" "and raises a finding"
assert_contains 'GOAL_PATH' "$RG_TRUST" "naming the goal file"
assert_contains 'created' "$RG_TRUST" "while creating a goal is not a finding"
assert_contains 'unavailable' "$RG_TRUST" "and an unreadable file list is not silence"
assert_contains 'renamed' "$RG_TRUST" "and a rename is read together with the goal state"
assert_contains 'removed or weakened' "$RG_TRUST" "a modification earns a finding only if it weakens something"
# gh pr diff takes no pathspec; the hunk comes from the file list.
assert_equal "0" "$(printf '%s\n' "$RG_TRUST" | grep -c 'gh pr diff.*--')" \
  "and the hunk is not asked of a command that cannot filter"
RG_REQ_STATE=$(printf '%s\n' "$RG_REVIEW" | grep -c 'STATE=unavailable.*could not be read\|goal could not be read')
assert_match '^[1-9]' "$RG_REQ_STATE" "an unreadable goal is recorded in the requirements map, not passed over"

_flow_test_begin "the requirements step is pointed at the criteria Phase 1 read"
RG_REQ=$(printf '%s\n' "$RG_REVIEW" | grep -c 'AC=` lines\|`AC=` lines')
assert_match '^[1-9]' "$RG_REQ" "the requirements step names the AC= lines as its source"

_flow_test_begin "nothing in the review runs a value the goal carried"
# The goal is fetched from the pull request head, so a verification_command is
# author-controlled text. The block never executes one; neither may any step
# that reads the section, and `allowed-tools: Bash` means an instruction to run
# one would be obeyed without a prompt.
assert_equal "0" "$(printf '%s\n' "$RG_REVIEW" | grep -ci 'run each .verification_command\|execute the verification_command\|run the goal.s verification')" \
  "no step is told to run a verification_command"
assert_contains 'read, never run' "$RG_REVIEW" "and the requirements step says so where it uses them"
RG_NONGOAL_EXEC=$(printf '%s\n' "$RG_REVIEW" | grep -c 'no value from it is run, expanded or substituted')
assert_match '^[1-9]' "$RG_NONGOAL_EXEC" "the block still states the same rule for itself"

# --- #213 AC4: one true statement about which commands create goals ----------

_flow_test_begin "the references do not claim review or address creates a goal"
# commands/review.md and commands/address.md both say they are FlowRun-only and
# create no FlowGoal; flow-goals.md said the opposite, and a reader had no way
# to tell which was true.
RG_REFS=$(grep -rl '' "$REPO_ROOT/plugins/flow/references/" | wc -l | tr -d ' ')
assert_match '^[1-9]' "$RG_REFS" "the references directory was examined"
assert_equal "0" "$(grep -rc 'pr-<N>-review\.goal\.yaml' "$REPO_ROOT/plugins/flow/references/" 2>/dev/null | awk -F: '{t+=$2} END {print t+0}')" \
  "no reference claims review creates a goal"
assert_equal "0" "$(grep -rc 'pr-<N>-address\.goal\.yaml' "$REPO_ROOT/plugins/flow/references/" 2>/dev/null | awk -F: '{t+=$2} END {print t+0}')" \
  "no reference claims address creates a goal"
RG_GOALS_DOC=$(cat "$REPO_ROOT/plugins/flow/references/flow-goals.md")
assert_contains 'FlowRun-only' "$RG_GOALS_DOC" "and it states what they do instead"

# --- #213 AC5: the review workflow declares the goal it may read -------------

_flow_test_begin "review-pr.workflow.yaml documents the optional goal input"
RG_WF="$REPO_ROOT/plugins/flow/workflows/review-pr.workflow.yaml"
assert_file_exists "$RG_WF" "the workflow exists"
RG_WF_TXT=$(cat "$RG_WF")
assert_contains 'goal' "$RG_WF_TXT" "the goal input is declared"
assert_match 'required: false' "$RG_WF_TXT" "and is optional — a pull request without a goal still reviews"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  RG_WF_INPUTS=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('$RG_WF'))
i = (d.get('inputs') or {})
print('goal_path' in i, (i.get('goal_path') or {}).get('required'))
")
  assert_equal "True False" "$RG_WF_INPUTS" "goal_path is declared and not required"
else
  _flow_assert_pass "SKIP: PyYAML unavailable"
fi
