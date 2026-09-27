# Tests that the read-only display commands tell an ABSENT input apart from one
# that is PRESENT BUT UNREADABLE.
#
# Scope is four command files, because the same defect sat in all four:
#
#   commands/goal.md      — /flow:goal status scans .flow/goals/*.goal.yaml
#   commands/resume.md    — /flow:resume scans .flow/runs/*/run.yaml
#   commands/status.md    — /flow:status Recent Runs + Active Triggers
#   commands/workflow.md  — /flow:workflow list
#
# In every one of them a file that could not be parsed produced exactly the
# output of a file that was not there: "No active FlowGoal. Use /flow:goal
# create to start one." over a directory that may hold one, "All runs are in
# terminal status." over a run nobody read, a registered trigger absent from
# the Active Triggers list under STATE=ok, `verdict=` for a verdict file jq
# choked on, and a workflow row with two blank columns for a workflow the
# reader never opened.
#
# The rule each block now follows is the one commands/review.md § FlowGoal
# already applies: absent is a real answer and keeps the empty default;
# present-but-unreadable emits a visible line that names the file. These are
# display paths, so an unreadable input is reported, never fatal and never
# silent.
#
# Prereq: python3 with PyYAML (four of the five readers), jq (the verdict one).
# SKIPS gracefully when either is absent.

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "python3 + PyYAML prerequisite"
  _flow_assert_pass "SKIP: python3 with PyYAML not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
CMD_DIR="$PLUGIN_DIR/commands"

SDU_CLEANUP=()
_sdu_cleanup() { local p; for p in "${SDU_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _sdu_cleanup EXIT

SDU_TMP=$(mktemp -d -t flow-sdu.XXXXXX); SDU_CLEANUP+=("$SDU_TMP")

# _sdu_extract <command-file> <marker-stem> — writes the block bounded by
# `# <stem>_BEGIN` / `# <stem>_END` to $SDU_TMP/<stem>.sh and prints its path.
# Marker-bounded, not heading-bounded, so the extraction survives line drift.
_sdu_extract() {
  local file="$1" stem="$2" out="$SDU_TMP/$2.sh"
  awk -v b="# ${stem}_BEGIN" -v e="# ${stem}_END" '
    { t = $0; sub(/^[ \t]+/, "", t) }
    t == b { f = 1; next }
    t == e { f = 0 }
    f' "$file" > "$out"
  printf '%s\n' "$out"
}

# A python3 that always fails, for the case where the reader itself cannot run
# (PyYAML missing, interpreter killed). Only python3 is shadowed; the rest of
# PATH is intact, so the shell half of each block runs normally.
SDU_STUB="$SDU_TMP/stub"
mkdir -p "$SDU_STUB"
printf '#!/bin/sh\nexit 1\n' > "$SDU_STUB/python3"
chmod +x "$SDU_STUB/python3"

# _sdu_workdir — a fresh directory to run a block in; registered for cleanup.
_sdu_workdir() {
  local d
  d=$(mktemp -d -t flow-sdu-w.XXXXXX)
  SDU_CLEANUP+=("$d")
  printf '%s\n' "$d"
}

# --- commands/goal.md — the /flow:goal status scan -----------------------------

GOAL_BLOCK=$(_sdu_extract "$CMD_DIR/goal.md" "GOAL_SCAN_BLOCK")

_flow_test_begin "goal.md carries a runnable goal-scan block"
assert_match '[^[:space:]]' "$(cat "$GOAL_BLOCK")" "goal-scan block extracted"
if bash -n "$GOAL_BLOCK" 2>/dev/null; then
  _flow_assert_pass "goal-scan block parses"
else
  _flow_assert_fail "goal-scan block does not parse"
fi

_flow_test_begin "goal.md: an empty goals directory is answered STATE=none"
GW1=$(_sdu_workdir); mkdir -p "$GW1/.flow/goals"
GOUT1=$(cd "$GW1" && bash "$GOAL_BLOCK" 2>/dev/null)
assert_contains "STATE=none" "$GOUT1" "no goal files → none (absent stays the empty default)"
assert_not_contains "GOAL_UNREADABLE=" "$GOUT1" "nothing is reported unreadable when nothing is there"
assert_not_contains "STATE=unavailable" "$GOUT1" "absent is not reported as unknown"

_flow_test_begin "goal.md: an unreadable goal is named, not answered as no goal"
GW2=$(_sdu_workdir); mkdir -p "$GW2/.flow/goals"
printf 'lifecycle: [unclosed\n' > "$GW2/.flow/goals/issue-1.goal.yaml"
GOUT2=$(cd "$GW2" && bash "$GOAL_BLOCK" 2>/dev/null)
assert_contains "GOAL_UNREADABLE=.flow/goals/issue-1.goal.yaml" "$GOUT2" "the file that could not be read is named"
assert_contains "STATE=unavailable" "$GOUT2" "whether a goal is active is reported unknown"
assert_not_contains "STATE=none" "$GOUT2" "an unreadable goal is NOT reported as no goal — that invites creating the one on disk"

_flow_test_begin "goal.md: a wrong-shaped lifecycle is unreadable, a null one is not"
GW3=$(_sdu_workdir); mkdir -p "$GW3/.flow/goals"
# `lifecycle: active` writes a string where a mapping belongs. Reading .get on
# it raised, and the raise was swallowed as "this goal is not active".
printf 'lifecycle: active\n' > "$GW3/.flow/goals/issue-2.goal.yaml"
# `lifecycle:` with nothing under it is a goal that declares no status — a real
# answer, and the one shape a .get default does NOT cover.
printf 'lifecycle:\n' > "$GW3/.flow/goals/issue-3.goal.yaml"
GOUT3=$(cd "$GW3" && bash "$GOAL_BLOCK" 2>/dev/null)
assert_contains "GOAL_UNREADABLE=.flow/goals/issue-2.goal.yaml" "$GOUT3" "a lifecycle that is not a mapping is named unreadable"
assert_not_contains "GOAL_UNREADABLE=.flow/goals/issue-3.goal.yaml" "$GOUT3" "a null lifecycle is a goal with no status, not an unreadable file"
assert_contains "STATE=unavailable" "$GOUT3" "the wrong-shaped goal leaves the active question unanswered"

_flow_test_begin "goal.md: an active goal is still found, and the unreadable one still shows"
GW4=$(_sdu_workdir); mkdir -p "$GW4/.flow/goals"
printf 'lifecycle: [unclosed\n' > "$GW4/.flow/goals/issue-1.goal.yaml"
printf 'lifecycle:\n  status: active\nobjective:\n  outcome: ship it\n' > "$GW4/.flow/goals/issue-9.goal.yaml"
GOUT4=$(cd "$GW4" && bash "$GOAL_BLOCK" 2>/dev/null)
assert_contains "STATE=ok" "$GOUT4" "the active goal is found"
assert_contains "ACTIVE_GOAL=.flow/goals/issue-9.goal.yaml" "$GOUT4" "and named"
# The scan reads every file rather than stopping at the first active one, so
# which unreadable goals get reported does not depend on filename order.
assert_contains "GOAL_UNREADABLE=.flow/goals/issue-1.goal.yaml" "$GOUT4" "an unreadable goal is reported alongside an active one"

_flow_test_begin "goal.md: a scan that cannot run at all says so"
GW5=$(_sdu_workdir); mkdir -p "$GW5/.flow/goals"
printf 'lifecycle:\n  status: active\n' > "$GW5/.flow/goals/issue-9.goal.yaml"
GOUT5=$(cd "$GW5" && PATH="$SDU_STUB:$PATH" bash "$GOAL_BLOCK" 2>/dev/null)
assert_contains "STATE=unavailable" "$GOUT5" "a reader that cannot run leaves the active question unanswered"
assert_contains "did not complete" "$GOUT5" "and says the scan itself was what failed"
assert_not_contains "STATE=none" "$GOUT5" "a dead reader is not reported as no goal"
assert_not_contains "STATE=ok" "$GOUT5" "nor as a goal that was read"

# --- commands/resume.md — the FlowRun scan ------------------------------------

RESUME_BLOCK=$(_sdu_extract "$CMD_DIR/resume.md" "RESUME_SCAN_BLOCK")

_flow_test_begin "resume.md carries a runnable run-scan block"
assert_match '[^[:space:]]' "$(cat "$RESUME_BLOCK")" "run-scan block extracted"
if bash -n "$RESUME_BLOCK" 2>/dev/null; then
  _flow_assert_pass "run-scan block parses"
else
  _flow_assert_fail "run-scan block does not parse"
fi

_flow_test_begin "resume.md: runs that all read and all finished keep the terminal sentence"
RW1=$(_sdu_workdir); mkdir -p "$RW1/.flow/runs/a"
printf 'metadata:\n  id: 2026-01-01-done\nstate:\n  status: completed\n' > "$RW1/.flow/runs/a/run.yaml"
ROUT1=$(cd "$RW1" && bash "$RESUME_BLOCK" 2>/dev/null)
assert_contains "STATE=none" "$ROUT1" "every run read, none resumable → none"
assert_contains "All runs are in terminal status." "$ROUT1" "the terminal claim is kept when it was established"
assert_not_contains "RUN_UNREADABLE=" "$ROUT1" "nothing is reported unreadable"

_flow_test_begin "resume.md: an unreadable run withdraws the terminal claim"
RW2=$(_sdu_workdir); mkdir -p "$RW2/.flow/runs/b"
printf 'state: [unclosed\n' > "$RW2/.flow/runs/b/run.yaml"
ROUT2=$(cd "$RW2" && bash "$RESUME_BLOCK" 2>/dev/null)
assert_contains "RUN_UNREADABLE=.flow/runs/b/run.yaml" "$ROUT2" "the run that could not be read is named"
assert_contains "STATE=unavailable" "$ROUT2" "the scan reports it does not know"
assert_not_contains "All runs are in terminal status." "$ROUT2" "the command no longer asserts what it did not determine"

_flow_test_begin "resume.md: an active run with no id is unreadable, a null state is not"
RW3=$(_sdu_workdir); mkdir -p "$RW3/.flow/runs/c" "$RW3/.flow/runs/d"
# Active, but nothing to resume by name. Appended as a blank candidate this
# emptied RUN_ID and the caller announced that every run had finished.
printf 'metadata:\nstate:\n  status: active\n' > "$RW3/.flow/runs/c/run.yaml"
# `state:` with nothing under it is a run that declares no status — a real
# answer, and not resumable.
printf 'metadata:\n  id: 2026-01-02-nostate\nstate:\n' > "$RW3/.flow/runs/d/run.yaml"
ROUT3=$(cd "$RW3" && bash "$RESUME_BLOCK" 2>/dev/null)
assert_contains "RUN_UNREADABLE=.flow/runs/c/run.yaml" "$ROUT3" "an active run with no metadata.id is named"
assert_not_contains "RUN_UNREADABLE=.flow/runs/d/run.yaml" "$ROUT3" "a null state is a run with no status, not an unreadable file"
assert_not_contains "All runs are in terminal status." "$ROUT3" "the terminal claim is withheld"

_flow_test_begin "resume.md: a readable active run is still picked, newest first"
RW4=$(_sdu_workdir); mkdir -p "$RW4/.flow/runs/e" "$RW4/.flow/runs/f"
printf 'state: [unclosed\n' > "$RW4/.flow/runs/e/run.yaml"
printf 'metadata:\n  id: 2026-02-02-live\nstate:\n  status: active\n' > "$RW4/.flow/runs/f/run.yaml"
ROUT4=$(cd "$RW4" && bash "$RESUME_BLOCK" 2>/dev/null)
assert_contains "STATE=ok" "$ROUT4" "the active run is found"
assert_contains "RUN_ID=2026-02-02-live" "$ROUT4" "and named"
assert_contains "RUN_UNREADABLE=.flow/runs/e/run.yaml" "$ROUT4" "the unreadable run is reported alongside it"

_flow_test_begin "resume.md: a scan that cannot run at all says so"
RW5=$(_sdu_workdir); mkdir -p "$RW5/.flow/runs/g"
printf 'metadata:\n  id: 2026-03-03-live\nstate:\n  status: active\n' > "$RW5/.flow/runs/g/run.yaml"
ROUT5=$(cd "$RW5" && PATH="$SDU_STUB:$PATH" bash "$RESUME_BLOCK" 2>/dev/null)
assert_contains "STATE=unavailable" "$ROUT5" "a reader that cannot run leaves the terminal question unanswered"
assert_contains "did not complete" "$ROUT5" "and says the scan itself was what failed"
assert_not_contains "All runs are in terminal status." "$ROUT5" "a dead reader never produces the terminal claim"

# --- commands/status.md — Recent Runs verdict ---------------------------------

if command -v jq >/dev/null 2>&1; then
  RUNS_BLOCK=$(_sdu_extract "$CMD_DIR/status.md" "RECENT_RUNS_BLOCK")

  _flow_test_begin "status.md carries a runnable Recent Runs block"
  assert_match '[^[:space:]]' "$(cat "$RUNS_BLOCK")" "Recent Runs block extracted"
  if bash -n "$RUNS_BLOCK" 2>/dev/null; then
    _flow_assert_pass "Recent Runs block parses"
  else
    _flow_assert_fail "Recent Runs block does not parse"
  fi

  # Exactly three runs: the section lists the three most recent, so a fourth
  # would push one out and the assertions below would read as a pass.
  _flow_test_begin "status.md: a verdict file that cannot be read says so"
  VW1=$(_sdu_workdir); mkdir -p "$VW1/.flow/runs/r-nokey" "$VW1/.flow/runs/r-empty" "$VW1/.flow/runs/r-bad"
  printf '{"result":"achieved"}\n' > "$VW1/.flow/runs/r-nokey/last-verdict.json"
  : > "$VW1/.flow/runs/r-empty/last-verdict.json"
  printf '{"verdict": ' > "$VW1/.flow/runs/r-bad/last-verdict.json"
  VOUT1=$(cd "$VW1" && bash "$RUNS_BLOCK" 2>/dev/null)
  assert_match 'RUN=id=r-bad verdict=unreadable' "$VOUT1" "unparseable JSON renders unreadable"
  assert_match 'RUN=id=r-empty verdict=unreadable' "$VOUT1" "an empty verdict file renders unreadable"
  assert_match 'RUN=id=r-nokey verdict=-' "$VOUT1" "valid JSON with no verdict key keeps the empty default"
  assert_not_contains "verdict= " "$VOUT1" "no run leaks a bare-empty verdict"

  _flow_test_begin "status.md: a run with no verdict file, and one with a verdict, are unchanged"
  VW2=$(_sdu_workdir); mkdir -p "$VW2/.flow/runs/r-none" "$VW2/.flow/runs/r-ok"
  printf '{"verdict":"achieved"}\n' > "$VW2/.flow/runs/r-ok/last-verdict.json"
  VOUT2=$(cd "$VW2" && bash "$RUNS_BLOCK" 2>/dev/null)
  assert_match 'RUN=id=r-none verdict=-' "$VOUT2" "no verdict file at all keeps the empty default"
  assert_match 'RUN=id=r-ok verdict=achieved' "$VOUT2" "a readable verdict is rendered verbatim"
  assert_not_contains "unreadable" "$VOUT2" "nothing readable is reported unreadable"
else
  _flow_test_begin "jq prerequisite for the Recent Runs verdict"
  _flow_assert_pass "SKIP: jq not installed"
fi

# --- commands/status.md — Active Triggers -------------------------------------

TRIG_BLOCK=$(_sdu_extract "$CMD_DIR/status.md" "TRIGGERS_BLOCK")

_flow_test_begin "status.md carries a runnable Active Triggers block"
assert_match '[^[:space:]]' "$(cat "$TRIG_BLOCK")" "Active Triggers block extracted"
if bash -n "$TRIG_BLOCK" 2>/dev/null; then
  _flow_assert_pass "Active Triggers block parses"
else
  _flow_assert_fail "Active Triggers block does not parse"
fi

_flow_test_begin "status.md: an unparseable trigger stays visible in the list"
TW1=$(_sdu_workdir); mkdir -p "$TW1/.flow/triggers" "$TW1/.claude"
printf '%s\n' '{"flow":{"triggers":{"enabled":true}}}' > "$TW1/.claude/settings.flow.json"
printf 'metadata:\n  id: nightly\n  enabled: true\ntrigger:\n  type: schedule\n' > "$TW1/.flow/triggers/a-good.trigger.yaml"
printf 'metadata: [unclosed\n' > "$TW1/.flow/triggers/b-bad.trigger.yaml"
printf -- '- one\n- two\n' > "$TW1/.flow/triggers/c-list.trigger.yaml"
TOUT1=$(cd "$TW1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$TRIG_BLOCK" 2>/dev/null)
assert_contains "STATE=ok" "$TOUT1" "the section reports ok"
assert_contains "TRIGGER=id=nightly type=schedule" "$TOUT1" "the readable trigger is listed"
assert_contains "TRIGGER=skipped (unreadable): .flow/triggers/b-bad.trigger.yaml" "$TOUT1" "the unparseable trigger is named, in the same shape as the symlink refusal"
assert_contains "TRIGGER=skipped (unreadable): .flow/triggers/c-list.trigger.yaml" "$TOUT1" "a trigger that is not a mapping is named too"
# The strongest statement the section can make: three files registered, three
# lines out. A registered trigger that produces no line reads as one that is
# not registered.
TRIG_LINES=$(printf '%s\n' "$TOUT1" | grep -c '^TRIGGER=' || true)
assert_equal "3" "$TRIG_LINES" "every registered trigger produces exactly one line"

_flow_test_begin "status.md: no triggers at all is still empty, not unreadable"
TW2=$(_sdu_workdir); mkdir -p "$TW2/.flow/triggers" "$TW2/.claude"
printf '%s\n' '{"flow":{"triggers":{"enabled":true}}}' > "$TW2/.claude/settings.flow.json"
TOUT2=$(cd "$TW2" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$TRIG_BLOCK" 2>/dev/null)
assert_contains "STATE=empty" "$TOUT2" "an empty triggers directory is empty"
assert_not_contains "unreadable" "$TOUT2" "and nothing is reported unreadable"

# --- commands/workflow.md — the list subcommand -------------------------------

WF_BLOCK=$(_sdu_extract "$CMD_DIR/workflow.md" "WORKFLOW_LIST_BLOCK")

_flow_test_begin "workflow.md carries a runnable list block"
assert_match '[^[:space:]]' "$(cat "$WF_BLOCK")" "list block extracted"
if bash -n "$WF_BLOCK" 2>/dev/null; then
  _flow_assert_pass "list block parses"
else
  _flow_assert_fail "list block does not parse"
fi

_flow_test_begin "workflow.md: an unreadable workflow is named, a bare one keeps blank columns"
WW1=$(_sdu_workdir)
# A fake plugin root: the block keeps CLAUDE_PLUGIN_ROOT when it holds an
# executable bin/cascade-resolve.sh, so the workflows read are the ones below.
mkdir -p "$WW1/fakeplugin/bin" "$WW1/fakeplugin/workflows" "$WW1/repo"
printf '#!/bin/sh\nexit 0\n' > "$WW1/fakeplugin/bin/cascade-resolve.sh"
chmod +x "$WW1/fakeplugin/bin/cascade-resolve.sh"
printf 'metadata:\n  id: start-issue\n  command: /flow:start\n  description: Start work on an issue\n' > "$WW1/fakeplugin/workflows/start-issue.workflow.yaml"
printf 'metadata: [unclosed\n' > "$WW1/fakeplugin/workflows/broken.workflow.yaml"
printf 'metadata:\n  id: bare\n' > "$WW1/fakeplugin/workflows/bare.workflow.yaml"
printf 'metadata:\n  id: null-cmd\n  command:\n  description:\n' > "$WW1/fakeplugin/workflows/null-cmd.workflow.yaml"
WOUT1=$(cd "$WW1/repo" && CLAUDE_PLUGIN_ROOT="$WW1/fakeplugin" bash "$WF_BLOCK" 2>/dev/null)
assert_match 'start-issue +/flow:start +Start work on an issue' "$WOUT1" "a readable workflow renders all three columns"
assert_match 'broken +\(could not be read' "$WOUT1" "the unreadable workflow says so instead of showing two blank columns"
assert_match '^ +bare *$' "$WOUT1" "a workflow that declares neither field keeps its blank columns"
assert_match '^ +null-cmd *$' "$WOUT1" "a workflow whose fields are present and null keeps them blank, not the string None"
assert_not_contains "None" "$WOUT1" "a null field never renders as the word None"
assert_not_contains "bare            (could not be read" "$WOUT1" "declaring nothing is not the same as being unreadable"

_flow_test_begin "workflow.md: every workflow this plugin ships reads"
WW2=$(_sdu_workdir); mkdir -p "$WW2/repo"
WOUT2=$(cd "$WW2/repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$WF_BLOCK" 2>/dev/null)
assert_not_contains "could not be read" "$WOUT2" "no shipped workflow is misreported as unreadable"
SHIPPED=$(ls -1 "$PLUGIN_DIR"/workflows/*.workflow.yaml 2>/dev/null | grep -c . || true)
LISTED=$(printf '%s\n' "$WOUT2" | grep -cE '^  [a-z0-9-]+ ' || true)
assert_equal "$SHIPPED" "$LISTED" "every shipped workflow produces exactly one row"

_flow_test_begin "workflow.md: no shipped workflow means no row at all"
WW3=$(_sdu_workdir)
mkdir -p "$WW3/fakeplugin/bin" "$WW3/fakeplugin/workflows" "$WW3/repo"
printf '#!/bin/sh\nexit 0\n' > "$WW3/fakeplugin/bin/cascade-resolve.sh"
chmod +x "$WW3/fakeplugin/bin/cascade-resolve.sh"
WOUT3=$(cd "$WW3/repo" && CLAUDE_PLUGIN_ROOT="$WW3/fakeplugin" bash "$WF_BLOCK" 2>/dev/null)
# An unmatched glob leaves the loop variable as the literal pattern. Reported as
# unreadable it would be the same lie one level out.
assert_not_contains "could not be read" "$WOUT3" "an unmatched glob is not reported as an unreadable workflow"
assert_not_contains "*.workflow.yaml" "$WOUT3" "and the literal pattern never reaches the output"
