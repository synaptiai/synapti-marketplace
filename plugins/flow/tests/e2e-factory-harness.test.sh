# shellcheck shell=bash
# The factory test helpers (tests/lib/factory-e2e.sh) and the stand-ins they
# install: the worker claude (fixtures/factory/worker/claude), the marker-shaped
# launcher (worker/fake_launcher.py), the terminal and detached spawner
# (worker/fe_spawn.py) and the factory gh stub (fixtures/factory/engine/gh).
#
# Ways it can be wrong, written down before the checks:
#   H1 fe_record writes a record the probe schema refuses, so every later
#      scenario starts from an invalid record
#   H2 the worker stand-in reads E2E_* variables, so it fails under an
#      environment built from nothing (plan R24); or its worker-result mode
#      prints a session id other than the one it was launched with
#   H3 fe_person_terminal still has a claude ancestor or CLAUDECODE, so the
#      terminal path is never exercised (plan R23)
#   H4 a leftover detached process survives the scenario (plan R25); or the
#      cleanup kills a pid whose start time is not the one the lease records
#      (the pid now belongs to another process)
#   H5 a mask leaves a pid or uuid in the artifact, so two runs differ
#   H6 fe_fake_launcher's process tree or lease does not have the shape the
#      refusal and lookup tests rely on, or its heartbeat rewrites fields a
#      test edited
#   H7 fe_detached keeps a terminal or an ancestor of the test, so a test of
#      the detached path depends on where the suite runs
#   H8 a helper runs its process in the worktree or with the person's HOME,
#      settings, gh or claude, so the engine resolves the real main checkout
#      and writes into its live .flow/factory; or a helper with no scratch
#      repository runs its command anyway
#   H9 the factory gh stub answers a call it has no fixture for, needs E2E_GH,
#      or loses the defaults the first `next` relies on
#   H10 fe_job or fe_directive seed a file the job or directive schema refuses,
#      or fe_job_clone leaves the clone off the job's branch
#   H11 fe_wait_for waits for ever, or past its limit, instead of failing the
#      scenario at its limit
#   H12 the stub with a world file (engine/gh_world.py) loses what it posts,
#      so a lookup after a post finds nothing; cuts a post's first line (the
#      engine marker); stores a post it answered with a failure; or keeps the
#      world it was given after a die_after_post kill instead of the write
#   H13 a list read gives one page only: no page parameter, no Link header,
#      or --paginate --slurp printing one flat list instead of the pages, so
#      an earlier post on page 2 is never found (plan R35)
#   H14 die_after_post kills the wrong process: the stub itself, so the
#      write's caller lives on, or the scenario's own shell
#   H15 the stub reports every actor as a User whatever actor_types says, so
#      a bot with no [bot] suffix looks like a person (plan R90); a list_fails
#      prefix misses `user`; a renamed event loses its from and to, or its
#      null actor; a permission entry answers a role the test did not set
#   H16 a factory scenario still has an https origin (a fetch would reach the
#      network), no origin/<base> or origin/HEAD ref, no gh-resolved naming
#      the repository, or a job.json with no base; or a second call of
#      fe_origin_local after a new commit leaves the old ref
#   H17 a world from one scenario answers the next one (fe_new keeps
#      FE_WORLD); or the stub with no world loses the defaults the engine's
#      new reads need (api user, api repos/O/R)
#   H18 _fe_scratch_env passes the test's own XDG_STATE_HOME on, so a probe
#      started through it makes folders outside the scratch HOME

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

FH_FILE="$REPO_ROOT/plugins/flow/tests/e2e-factory-harness.test.sh"
FH_SCHEMAS="$REPO_ROOT/plugins/flow/schemas/v1"

# fh_run <id> — whether this scenario runs. FE_HARNESS_ONLY=<id> runs only that
# one; H5 uses it to run H2 alone, twice.
fh_run() { [ -z "${FE_HARNESS_ONLY:-}" ] || [ "$FE_HARNESS_ONLY" = "$1" ]; }

# The real main checkout's factory folder: the parent of the common git
# directory, which for this worktree is the main checkout, not the worktree.
# Only its metadata is read (names, kinds, sizes, modification times); no file
# in it is opened and the folder is never created. The first listing is taken
# before factory-e2e.sh is sourced, because sourcing it runs the one helper
# step that uses the real HOME (the interpreter lookup).
FH_MAIN=$(dirname -- "$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)")
FH_REAL_FACTORY="$FH_MAIN/.flow/factory"
fh_listing() {
  python3 -I - "$FH_REAL_FACTORY" <<'PY'
import os, stat, sys
root = sys.argv[1]
if not os.path.lexists(root):
    print("absent")
    sys.exit(0)
def line(p):
    st = os.lstat(p)
    kind = "d" if stat.S_ISDIR(st.st_mode) else "l" if stat.S_ISLNK(st.st_mode) else "f"
    size = st.st_size if kind == "f" else ""
    print("%s\t%s\t%s\t%s" % (os.path.relpath(p, root), kind, size, st.st_mtime_ns))
line(root)
for top, dirs, files in os.walk(root, followlinks=False):
    dirs.sort()
    for n in sorted(dirs + files):
        line(os.path.join(top, n))
PY
}
# fh_changed <before> <after> — the paths whose line differs between two
# listings, space-separated; empty when they are equal.
fh_changed() {
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | sed -n 's/^[<>] //p' | cut -f1 | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//'
}
fh_run h8 && FH_FACTORY_BEFORE=$(fh_listing)

source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# fh_validate <schema file> <json file> [<$defs name>] — validate with
# jsonschema's Draft 2020-12 validator, run by the recorded interpreter under
# the scratch HOME (fe_py), whose user site holds jsonschema.
fh_validate() {
  fe_py "import json, jsonschema
schema = json.load(open('$1'))
target = schema if not '${3:-}' else dict(schema['\$defs']['${3:-}'], **{'\$defs': schema['\$defs']})
doc = json.load(open('$2'))
errs = sorted(jsonschema.Draft202012Validator(target).iter_errors(doc), key=str)
print('valid' if not errs else 'invalid: ' + '; '.join(e.message for e in errs[:5]))"
}

if fh_run h1; then
_flow_test_begin "factory helpers: fe_record writes a record the probe schema accepts (H1)"
fe_new fh-record
e2e_describe "fe_record writes F/probes.json naming the recorded interpreter, valid against the probe schema, and the factory path pointer"
e2e_repo main
fe_record
FH_F=$(fe_factory_dir)
e2e_expect_equal "$(cd "$E2E_REPO" && pwd -P)/.flow/factory" "$FH_F" "the factory directory"
fh_validate "$FH_SCHEMAS/factory-probes.schema.json" "$FH_F/probes.json"
e2e_expect_line "valid"
fe_py "import json
d = json.load(open('$FH_F/probes.json'))
print('interpreter=' + d['interpreter'])
print('platform=' + d['groups']['platform']['keyed_on']['claude_version'] + ' ' + d['groups']['platform']['keyed_on']['model'])
print('gh=' + d['groups']['environment']['keyed_on']['gh_version'])
print('p5=' + ','.join(sorted(set(p['result'] for p in d['probes']['P5']['parts'].values()))))
unstamped = [k for k, p in d['probes'].items() if p['result'] != 'not_run' and ('keyed_on' not in p or any('keyed_on' not in q for q in (p.get('parts') or {}).values()))]
print('unstamped=' + (','.join(unstamped) or 'none'))"
e2e_expect_line "interpreter=$(fe_python)"
e2e_expect_line "platform=2.1.325 (Claude Code) claude-opus-5-5"
e2e_expect_line "gh=gh version 2.101.0 (2026-09-15)"
e2e_expect_line "p5=go"
e2e_expect_line "unstamped=none"
e2e_expect_equal "$FH_F" "$(cat "$E2E_REPO/.git/flow-factory-path" 2>/dev/null)" "the pointer file's content"
e2e_expect_equal "$E2E_DIR/origin.git" "$(git -C "$E2E_REPO" config --local remote.origin.url)" "the scratch repository's origin (local, H16)"
# phase 0's own record check agrees.
e2e_run_bin bin/flow-factory.sh probe --verify-record "$FH_F/probes.json"
e2e_expect_line "PROBES_RECORD=ok"
fe_record_link
fe_py "import json; print(json.load(open('$FH_F/probes.json'))['interpreter'])"
e2e_expect_equal "$E2E_DIR/py/python3.14" "$E2E_OUT" "fe_record_link's recorded interpreter"
_e2e_exec "$E2E_DIR/py/python3.14" -I -c 'import os, sys; print(os.path.realpath(sys.executable))'
e2e_expect_equal "$(fe_python)" "$E2E_OUT" "the link resolves to fe_python"
fi

if fh_run h2; then
_flow_test_begin "factory helpers: the worker stand-in runs in an environment built from nothing (H2, R24)"
fe_new fh-worker-env
e2e_describe "fe_worker_says, then the stand-in claude run with env -i, HOME the scratch home and PATH the worker's shape: it answers, and records its argv, environment, pid and stdin beside itself"
e2e_repo main
fe_worker_says
FH_PYDIR=$(dirname -- "$(fe_python)")
_e2e_exec env -i HOME="$E2E_HOME" PATH="$FH_PYDIR:/usr/bin:/bin" bash -c 'printf x | "$1" -p --session-id 11111111-2222-4333-8444-555555555555 --output-format stream-json' _ "$E2E_BIN/claude"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out '"session_id": "11111111-2222-4333-8444-555555555555"'
for FH_F in claude-argv-1.txt claude-env-1.txt claude-pid-1 claude-stdin-1.txt; do
  if [ -f "$E2E_BIN/$FH_F" ]; then e2e_expect_equal yes yes "$FH_F exists"; else e2e_expect_equal yes no "$FH_F exists"; fi
done
e2e_expect_equal "x" "$(cat "$E2E_BIN/claude-stdin-1.txt" 2>/dev/null)" "the stdin the stand-in saw"
e2e_expect_equal "-p" "$(sed -n 1p "$E2E_BIN/claude-argv-1.txt" 2>/dev/null)" "the first recorded argument"
FH_E2E_NAMES=$(cut -d= -f1 "$E2E_BIN/claude-env-1.txt" 2>/dev/null | grep -c '^E2E_')
e2e_expect_equal "0" "$FH_E2E_NAMES" "E2E_ names in the recorded environment"
{
  printf 'recorded argv:\n'; cat "$E2E_BIN/claude-argv-1.txt"
  printf 'recorded environment names:\n'; cut -d= -f1 "$E2E_BIN/claude-env-1.txt" | LC_ALL=C sort
} 2>&1 | _e2e_art

_flow_test_begin "factory helpers: the worker-result knob prints the given result after an init event (H2)"
fe_new fh-worker-result
e2e_describe "with worker-result holding an is_error result, the stand-in prints an init event carrying --session-id, then that result, logs the launch, and exits 1"
e2e_repo main
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":true,"num_turns":1,"total_cost_usd":0,"api_error_status":429}'
_e2e_exec env -i HOME="$E2E_HOME" PATH="$FH_PYDIR:/usr/bin:/bin" bash -c 'printf go | "$1" -p --session-id 11111111-2222-4333-8444-555555555555' _ "$E2E_BIN/claude"
e2e_expect_equal "1" "$E2E_RC" "exit status"
e2e_expect_equal '{"type":"system","subtype":"init","session_id":"11111111-2222-4333-8444-555555555555"}' \
  "$(printf '%s\n' "$E2E_OUT" | sed -n 1p | jq -c '{type, subtype, session_id}')" "the first event"
e2e_expect_equal '429' "$(printf '%s\n' "$E2E_OUT" | sed -n 2p | jq -c '.api_error_status')" "the result event"
e2e_expect_equal "1" "$(wc -l < "$E2E_BIN/claude-launches.log" | tr -d ' ')" "launches logged"
e2e_expect_equal "go" "$(cat "$E2E_BIN/claude-stdin-1.txt" 2>/dev/null)" "the stdin the stand-in saw"

_flow_test_begin "factory helpers: with worker-sleep, the result comes first and no Python runs (H2, plan LA8(b))"
fe_new fh-worker-sleep
e2e_describe "worker-result and worker-sleep 3, with a python3 first on PATH that leaves a mark: one second in, both events are out, and no python3 ran"
e2e_repo main
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.1}' 'worker-sleep=3'
mkdir -p "$E2E_DIR/marked"
printf '#!/bin/sh\n: > "%s/python-ran"\nexit 1\n' "$E2E_DIR" > "$E2E_DIR/marked/python3"
chmod +x "$E2E_DIR/marked/python3"
_e2e_exec env -i HOME="$E2E_HOME" PATH="$E2E_DIR/marked:/usr/bin:/bin" bash -c \
  '"$1" -p --session-id 11111111-2222-4333-8444-555555555555 < /dev/null > "$2" & sleep 1; echo "lines at 1s=$(wc -l < "$2" | tr -d " ")"; wait $!; echo "rc=$?"' \
  _ "$E2E_BIN/claude" "$E2E_DIR/stream.out"
e2e_expect_line "lines at 1s=2"
e2e_expect_line "rc=0"
if [ -e "$E2E_DIR/python-ran" ]; then e2e_expect_equal "no python3" "python3 ran" "Python during worker-result"
else e2e_expect_equal "no python3" "no python3" "Python during worker-result"; fi
e2e_expect_equal '0.1' "$(sed -n 2p "$E2E_DIR/stream.out" | jq -c .total_cost_usd)" "the result event"
fi

if fh_run h3; then
_flow_test_begin "factory helpers: fe_person_terminal runs under a terminal with no claude ancestor and no CLAUDECODE (H3, R23)"
fe_new fh-terminal
e2e_describe "with CLAUDECODE=1 in the test shell, the command under fe_person_terminal gets a terminal, the typed job key, no CLAUDECODE, and no ancestor whose program is claude"
e2e_repo main
FH_SAVED_CC=${CLAUDECODE-__unset__}
export CLAUDECODE=1
# shellcheck disable=SC2016
FH_TERM_SCRIPT='printf "type the job key to confirm: "; read k; t=$(tty); echo "got=$k tty=${t%%[0-9]*} cc=${CLAUDECODE:-unset}"
p=$PPID
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
  l=$(LC_ALL=C /bin/ps -ww -o ppid=,command= -p "$p") || break
  set -- $l
  echo "anc exe=${2##*/}"
  p=$1
done
echo "anc end=$p"'
fe_person_terminal issue-7-j1 bash -c "$FH_TERM_SCRIPT"
e2e_expect_equal "0" "$E2E_RC" "exit status"
FH_GOT=$(printf '%s\n' "$E2E_OUT" | tr -d '\r' | sed -n 's/^.*got=/got=/p')
case "$FH_GOT" in
  "got=issue-7-j1 tty=/dev/"*" cc=unset") e2e_expect_equal ok ok "the got line ($FH_GOT)" ;;
  *) e2e_expect_equal "got=issue-7-j1 tty=/dev/... cc=unset" "$FH_GOT" "the got line" ;;
esac
e2e_expect_line "anc end=1"
FH_CLAUDE_ANC=$(printf '%s\n' "$E2E_OUT" | grep -c '^anc exe=claude$')
e2e_expect_equal "0" "$FH_CLAUDE_ANC" "ancestors whose program is claude"
# Control: the same script run directly, stdin not a terminal.
_e2e_exec bash -c "$FH_TERM_SCRIPT" </dev/null
FH_GOT=$(printf '%s\n' "$E2E_OUT" | tr -d '\r' | sed -n 's/^.*got=/got=/p')
e2e_expect_equal "got= tty=not a tty cc=1" "$FH_GOT" "the control's got line"
# The walk prints its lines in the form counted above (here a bash parent).
e2e_expect_line "anc exe=bash"
if [ "$FH_SAVED_CC" = __unset__ ]; then unset CLAUDECODE; else export CLAUDECODE="$FH_SAVED_CC"; fi
fi

if fh_run h4; then
# fh_sleeper — a sleep 300 in a new session, its stdout not this shell's, and
# a lease file under $E2E_DIR naming it as the child group with its start time.
fh_sleeper() {
  local pid
  pid=$("$(fe_python)" -I -c 'import subprocess; print(subprocess.Popen(["sleep", "300"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid)')
  jq -n --argjson p "$pid" --arg s "${1:-$(_fe_lstart "$pid")}" '{child_pgid: $p, child_start: $s}' > "$E2E_DIR/h4.lease.json"
  printf '%s' "$pid"
}
_flow_test_begin "factory helpers: a lease's child group does not outlive its scenario (H4, R25)"
fe_new fh-leftover-a
e2e_describe "start a detached sleep 300 named by a lease file; the next fe_new kills it"
FH_PID=$(fh_sleeper)
if kill -0 "$FH_PID" 2>/dev/null; then e2e_expect_equal alive alive "the sleep after it started"; else e2e_expect_equal alive gone "the sleep after it started"; fi
fe_new fh-leftover-b
e2e_describe "the sleep the previous scenario started is gone"
if kill -0 "$FH_PID" 2>/dev/null; then e2e_expect_equal gone alive "the previous scenario's sleep"; kill "$FH_PID" 2>/dev/null; else e2e_expect_equal gone gone "the previous scenario's sleep"; fi

_flow_test_begin "factory helpers: e2e_new alone leaves a lease's process alive (H4 control)"
fe_new fh-leftover-c
e2e_describe "control, part one: the same detached sleep and lease"
FH_PID=$(fh_sleeper)
e2e_new fh-leftover-d
e2e_describe "control, part two: started with e2e_new, the sleep is still alive; the scenario then kills it"
if kill -0 "$FH_PID" 2>/dev/null; then e2e_expect_equal alive alive "the sleep under e2e_new"; else e2e_expect_equal alive gone "the sleep under e2e_new"; fi
kill "$FH_PID" 2>/dev/null

_flow_test_begin "factory helpers: the cleanup leaves a process whose start time is not the lease's (H4, A+8)"
fe_new fh-leftover-e
e2e_describe "a lease names a live sleep's pid with another start time, as after pid reuse; the next fe_new leaves it alone"
FH_PID=$(fh_sleeper "Thu Jan  1 00:00:00 1970")
fe_new fh-leftover-f
e2e_describe "the sleep whose start time did not match is still alive; the scenario then kills it"
if kill -0 "$FH_PID" 2>/dev/null; then e2e_expect_equal alive alive "the mismatched sleep"; else e2e_expect_equal alive gone "the mismatched sleep"; fi
kill "$FH_PID" 2>/dev/null
fi

if fh_run h5; then
_flow_test_begin "factory helpers: two runs of the worker scenario write the same artifact (H5)"
fe_new fh-repeatable
e2e_describe "run this file twice with only H2 selected, each into its own artifact folder, and compare the folders"
FH_RUNS="$E2E_DIR/runs"
mkdir -p "$FH_RUNS/a" "$FH_RUNS/b"
for FH_R in a b; do
  FE_HARNESS_ONLY=h2 FLOW_E2E_ARTIFACT_DIR="$FH_RUNS/$FH_R" FLOW_TEST_JOBS=1 FLOW_TEST_TIMES="$FH_RUNS/times" \
    "$REPO_ROOT/plugins/flow/tests/run.sh" "$FH_FILE" > "$FH_RUNS/$FH_R.log" 2>&1
  e2e_expect_equal "0" "$?" "run $FH_R's exit status"
  e2e_expect_equal "TOTAL pass=$(sed -n 's/^TOTAL pass=\([0-9]*\) fail=0$/\1/p' "$FH_RUNS/$FH_R.log") fail=0" \
    "$(grep '^TOTAL ' "$FH_RUNS/$FH_R.log")" "run $FH_R's TOTAL line"
done
FH_COUNT=$(find "$FH_RUNS/a" -name 'fh-worker-*.txt' | wc -l | tr -d ' ')
e2e_expect_equal "3" "$FH_COUNT" "worker artifacts in run a"
if diff -r "$FH_RUNS/a" "$FH_RUNS/b" > "$FH_RUNS/diff" 2>&1; then
  printf 'diff: identical\n' | _e2e_art
  e2e_expect_equal identical identical "the two runs' artifacts"
else
  { printf 'diff:\n'; cat "$FH_RUNS/diff"; } | _e2e_art
  e2e_expect_equal identical different "the two runs' artifacts"
fi
fi

if fh_run h6; then
_flow_test_begin "factory helpers: fe_fake_launcher's process tree and lease (H6)"
fe_new fh-fake-launcher
e2e_describe "fe_fake_launcher with a worker script that sleeps 5: the printed pid is the lease's launcher, the claude child is its child, its command line is a marker, and the start times are in the trimmed form"
e2e_repo main
FH_F="$E2E_DIR/F"
printf 'sleep 5\n' > "$E2E_DIR/h6-worker.sh"
FH_PID=$(fe_fake_launcher "$FH_F" issue-7-j1-build-1 "$E2E_DIR/h6-worker.sh")
FH_LEASE="$FH_F/jobs/issue-7/directives/issue-7-j1-build-1.lease.json"
case "$FH_PID" in
  ''|*[!0-9]*) e2e_expect_equal "a pid" "'$FH_PID'" "what fe_fake_launcher printed" ;;
  # One token for both start times: the launcher and its child often start
  # in the same second, and then one mask would name both.
  *) fe_mask_pid "$FH_PID" launcher; fe_mask_text "$(_fe_lstart "$FH_PID")" "<lstart>"
     e2e_expect_equal ok ok "fe_fake_launcher printed a pid" ;;
esac
e2e_expect_equal "$FH_PID" "$(jq -r .launcher_pid "$FH_LEASE" 2>/dev/null)" "(a) the lease's launcher_pid"
FH_CHILD=$(jq -r .child_pid "$FH_LEASE" 2>/dev/null)
case "$FH_CHILD" in
  ''|*[!0-9]*) e2e_expect_equal "a pid" "'$FH_CHILD'" "the lease's child_pid" ;;
  *) fe_mask_pid "$FH_CHILD" claude; fe_mask_text "$(_fe_lstart "$FH_CHILD")" "<lstart>" ;;
esac
FH_PPID=$(/bin/ps -o ppid= -p "$FH_CHILD" 2>/dev/null | tr -d ' ')
e2e_expect_equal "$FH_PID" "$FH_PPID" "(b) the claude child's parent"
e2e_expect_equal "$FH_CHILD" "$(jq -r .child_pgid "$FH_LEASE" 2>/dev/null)" "the child's own group"
FH_CMD=$(/bin/ps -ww -o command= -p "$FH_PID" 2>/dev/null)
case "$FH_CMD" in
  *" --factory-dir $FH_F issue-7-j1-build-1") e2e_expect_equal ok ok "(c) the command line ends with --factory-dir <F> <id>" ;;
  *) e2e_expect_equal "... --factory-dir $FH_F issue-7-j1-build-1" "$FH_CMD" "(c) the command line's end" ;;
esac
case "$FH_CMD" in
  *"/bin/_flow_factory_launch.py --factory-dir "*) e2e_expect_equal ok ok "(c) the command line holds the marker" ;;
  *) e2e_expect_equal "*/bin/_flow_factory_launch.py --factory-dir *" "$FH_CMD" "(c) the marker" ;;
esac
FH_START=$(jq -r .launcher_start "$FH_LEASE" 2>/dev/null)
e2e_expect_equal "$(_fe_lstart "$FH_PID")" "$FH_START" "(d) launcher_start"
case "$FH_START" in
  ' '*|*' '|'') e2e_expect_equal "no outer space" "'$FH_START'" "(d) launcher_start's form" ;;
  *) e2e_expect_equal ok ok "(d) launcher_start has no leading or trailing space" ;;
esac
e2e_expect_equal "$(_fe_lstart "$FH_CHILD")" "$(jq -r .child_start "$FH_LEASE" 2>/dev/null)" "child_start"
if [ -f "$FH_SCHEMAS/factory-directive.schema.json" ]; then
  fh_validate "$FH_SCHEMAS/factory-directive.schema.json" "$FH_LEASE" lease
  e2e_expect_line "valid"
fi
# A renewal rewrites heartbeat_at alone.
FH_BEAT=$(jq -r .heartbeat_at "$FH_LEASE")
jq '.host = "edited-by-test"' "$FH_LEASE" > "$FH_LEASE.t" && mv "$FH_LEASE.t" "$FH_LEASE"
fe_wait_for 10 "[ \"\$(jq -r .heartbeat_at '$FH_LEASE' 2>/dev/null)\" != '$FH_BEAT' ] && [ -n \"\$(jq -r .heartbeat_at '$FH_LEASE' 2>/dev/null)\" ]"
e2e_expect_equal "edited-by-test" "$(jq -r .host "$FH_LEASE")" "a field the test edited, after a renewal"
fi

if fh_run h7; then
_flow_test_begin "factory helpers: fe_detached has no terminal and no ancestor of the test (H7)"
fe_new fh-detached
e2e_describe "with CLAUDECODE=1 in the test shell, the command under fe_detached has parent pid 1, no terminal and no CLAUDECODE"
e2e_repo main
FH_SAVED_CC=${CLAUDECODE-__unset__}
export CLAUDECODE=1
# shellcheck disable=SC2016
FH_DET_SCRIPT='[ "$PPID" = 1 ] && echo ppid=1 || echo ppid=not-1; tty; echo cc=${CLAUDECODE:-unset}
pp=$(/bin/ps -o ppid= -p $PPID | tr -d " "); [ "$pp" = 1 ] && echo pppid=1 || echo pppid=not-1'
fe_detached bash -c "$FH_DET_SCRIPT"
if [ "$(uname -s)" = Darwin ]; then
  e2e_expect_line "ppid=1"
else
  # Linux has no way to read a non-child's exit status, so the command's
  # parent is the spawner's waiter, itself a child of pid 1 and no ancestor
  # of the test.
  e2e_expect_line "pppid=1"
fi
e2e_expect_line "not a tty"
e2e_expect_line "cc=unset"
# Control: detach.py forks, calls setsid and waits, so its parent stays.
_e2e_exec "$(fe_python)" -I "$FE_FIXTURES/detach.py" bash -c "$FH_DET_SCRIPT"
e2e_expect_no_line "ppid=1"
e2e_expect_line "cc=1"
if [ "$FH_SAVED_CC" = __unset__ ]; then unset CLAUDECODE; else export CLAUDECODE="$FH_SAVED_CC"; fi
fi

if fh_run h8; then
_flow_test_begin "factory helpers: every process a helper starts runs in the scratch repository and home (H8)"
fe_new fh-scratch
e2e_describe "fe_py, _fe_run_py, fe_detached, fe_person_terminal and a fe_fake_launcher worker each report their working directory, HOME, gh and claude"
e2e_repo main
FH_REPO_REAL=$(cd "$E2E_REPO" && pwd -P)
# shellcheck disable=SC2016
FH_WHERE='pwd -P; printf "%s\n" "$HOME"; command -v gh; command -v claude'
fh_where_is_scratch() {   # <label> <four lines>
  local cwd home gh claude
  cwd=$(printf '%s\n' "$2" | sed -n 1p); home=$(printf '%s\n' "$2" | sed -n 2p)
  e2e_expect_equal "$FH_REPO_REAL" "$cwd" "$1: the working directory"
  e2e_expect_equal "$E2E_HOME" "$home" "$1: HOME"
  if [ "$#" -gt 2 ]; then
    gh=$(printf '%s\n' "$2" | sed -n 3p); claude=$(printf '%s\n' "$2" | sed -n 4p)
    e2e_expect_equal "$E2E_BIN/gh" "$gh" "$1: gh"
    e2e_expect_equal "$E2E_BIN/claude" "$claude" "$1: claude"
  fi
}
fe_py 'import os; print(os.getcwd()); print(os.environ["HOME"])'
fh_where_is_scratch "(a) fe_py" "$E2E_OUT"
printf 'import os\nprint(os.getcwd())\nprint(os.environ["HOME"])\n' > "$E2E_DIR/h8-where.py"
_fe_run_py "$E2E_DIR/h8-where.py"
fh_where_is_scratch "(b) _fe_run_py" "$E2E_OUT"
fe_detached bash -c "$FH_WHERE"
fh_where_is_scratch "(c) fe_detached" "$E2E_OUT" tools
fe_person_terminal x bash -c "$FH_WHERE"
fh_where_is_scratch "(c) fe_person_terminal" "$(printf '%s\n' "$E2E_OUT" | tr -d '\r')" tools
printf '%s\n' "{ $FH_WHERE; } > '$E2E_DIR/h8-launcher.out.t'; mv '$E2E_DIR/h8-launcher.out.t' '$E2E_DIR/h8-launcher.out'" > "$E2E_DIR/h8-worker.sh"
fe_fake_launcher "$E2E_DIR/F" issue-7-j1-build-1 "$E2E_DIR/h8-worker.sh" >/dev/null
fe_wait_for 10 "[ -f '$E2E_DIR/h8-launcher.out' ]"
fh_where_is_scratch "(c) fe_fake_launcher worker" "$(cat "$E2E_DIR/h8-launcher.out" 2>/dev/null)" tools
# Control: the same Python run from the test shell, with no helper, is in the
# worktree with the real HOME, so the checks above can fail.
FH_CONTROL=$(python3 -I -c 'import os; print(os.getcwd()); print(os.environ["HOME"])')
case "$(printf '%s\n' "$FH_CONTROL" | sed -n 1p)" in
  "$E2E_DIR"*) e2e_expect_equal "outside the scratch" "inside" "control: the working directory" ;;
  *) e2e_expect_equal "$(pwd -P)" "$(printf '%s\n' "$FH_CONTROL" | sed -n 1p)" "control: the working directory is the test shell's" ;;
esac
case "$(printf '%s\n' "$FH_CONTROL" | sed -n 2p)" in
  "$E2E_DIR"*) e2e_expect_equal "outside the scratch" "inside" "control: HOME" ;;
  *) e2e_expect_equal ok ok "control: HOME is not under the scratch" ;;
esac

_flow_test_begin "factory helpers: with E2E_REPO empty or outside the scratch root, a helper starts nothing (H8)"
fe_new fh-no-repo
e2e_describe "with E2E_REPO empty, then naming this worktree, each process-starting helper refuses and runs nothing"
e2e_repo main
FH_SAVED_REPO=$E2E_REPO
for FH_BAD in "" "$REPO_ROOT"; do
  for FH_HELPER in fe_detached fe_person_terminal fe_fake_launcher fe_py; do
    rm -f "$E2E_DIR/h8-ran"
    case "$FH_HELPER" in
      fe_detached) FH_GOT=$(E2E_REPO=$FH_BAD; E2E_ARTIFACT="$E2E_DIR/expected-failures.txt"; fe_detached touch "$E2E_DIR/h8-ran" 2>&1) ;;
      fe_person_terminal) FH_GOT=$(E2E_REPO=$FH_BAD; E2E_ARTIFACT="$E2E_DIR/expected-failures.txt"; fe_person_terminal x touch "$E2E_DIR/h8-ran" 2>&1) ;;
      fe_fake_launcher)
        printf 'touch %s\n' "$E2E_DIR/h8-ran" > "$E2E_DIR/h8-bad.sh"
        FH_GOT=$(E2E_REPO=$FH_BAD; E2E_ARTIFACT="$E2E_DIR/expected-failures.txt"; fe_fake_launcher "$E2E_DIR/F2" issue-8-j1-build-1 "$E2E_DIR/h8-bad.sh" 2>&1) ;;
      fe_py) FH_GOT=$(E2E_REPO=$FH_BAD; E2E_ARTIFACT="$E2E_DIR/expected-failures.txt"; fe_py "open('$E2E_DIR/h8-ran', 'w')" 2>&1) ;;
    esac
    sleep 0.5
    if [ -e "$E2E_DIR/h8-ran" ]; then e2e_expect_equal "not run" "ran" "$FH_HELPER with E2E_REPO='$FH_BAD'"
    else e2e_expect_equal "not run" "not run" "$FH_HELPER with E2E_REPO='$FH_BAD'"; fi
    case "$FH_GOT" in
      *"no scratch repository; call e2e_repo"*|*"factory-e2e: no scratch repository (E2E_REPO="*)
        e2e_expect_equal refused refused "$FH_HELPER says why" ;;
      *) e2e_expect_equal refused "$FH_GOT" "$FH_HELPER says why" ;;
    esac
  done
done
E2E_REPO=$FH_SAVED_REPO
fi

if fh_run h9; then
_flow_test_begin "factory helpers: the factory gh stub answers from fixtures beside itself (H9, R24)"
fe_new fh-gh-stub
e2e_describe "the stub fe_new installs answers --version and the creation scan by default, a fixture, a failure and a hang, logs every call and pid, and exits 99 for any other call, also with an empty environment"
e2e_repo main
_e2e_exec env -i PATH=/usr/bin:/bin "$E2E_BIN/gh" --version
e2e_expect_equal "0" "$E2E_RC" "--version exit status, empty environment"
e2e_expect_line "gh version 2.101.0 (2026-09-15)"
_e2e_exec gh api --paginate --slurp 'repos/flow-e2e/scratch/issues?labels=flow:factory&state=open&per_page=100'
e2e_expect_equal "[]" "$E2E_OUT" "the creation scan's default"
fe_gh api_repos_flow-e2e_scratch_pulls_12 '{"number":12,"state":"open"}'
_e2e_exec gh api repos/flow-e2e/scratch/pulls/12
e2e_expect_equal '{"number":12,"state":"open"}' "$E2E_OUT" "a fixture's answer"
fe_gh --version 'gh version 2.200.0 (2026-11-01)'
_e2e_exec gh --version
e2e_expect_equal 'gh version 2.200.0 (2026-11-01)' "$E2E_OUT" "a --version fixture replaces the default"
fe_gh api_repos_flow-e2e_scratch_pulls_13 "fail 4 HTTP 502: Bad Gateway"
_e2e_exec gh api repos/flow-e2e/scratch/pulls/13
e2e_expect_equal "4" "$E2E_RC" "a fail fixture's exit status"
e2e_expect_err "HTTP 502: Bad Gateway"
fe_gh api_repos_flow-e2e_scratch_pulls_14 "hang 1"
FH_T0=$(date +%s)
_e2e_exec gh api repos/flow-e2e/scratch/pulls/14
FH_T1=$(date +%s)
if [ $((FH_T1 - FH_T0)) -ge 1 ]; then e2e_expect_equal waited waited "a hang fixture sleeps"; else e2e_expect_equal waited "returned at once" "a hang fixture sleeps"; fi
_e2e_exec gh pr list
e2e_expect_equal "99" "$E2E_RC" "an unhandled call's exit status"
e2e_expect_equal "pr list" "$(cat "$E2E_BIN/fe-gh-unhandled.log" 2>/dev/null)" "the unhandled log"
e2e_expect_equal "7" "$(wc -l < "$E2E_BIN/fe-gh-calls.log" | tr -d ' ')" "calls logged"
e2e_expect_equal "7" "$(wc -l < "$E2E_BIN/fe-gh-pids" | tr -d ' ')" "pids logged"
e2e_expect_equal "" "$(cat "$E2E_GH/unhandled.log")" "e2e.sh's own gh log (its stub was replaced)"
fi

if fh_run h10; then
_flow_test_begin "factory helpers: fe_job, fe_job_clone and fe_directive seed files the schemas accept (H10)"
fe_new fh-seeds
e2e_describe "fe_record, fe_enable, fe_job 7 build, fe_job_clone 7 and fe_directive issue-7-j1-build-1, then the job and directive validated against their schemas"
e2e_repo main
fe_record
fe_enable
e2e_expect_equal "true" "$(jq -c '.flow.factory.enabled' "$E2E_HOME/.claude/settings.flow.json")" "flow.factory.enabled in the scratch user settings"
fe_job 7 build
fe_job_clone 7
fe_directive issue-7-j1-build-1
FH_J="$(fe_factory_dir)/jobs/issue-7"
fh_validate "$FH_SCHEMAS/factory-job.schema.json" "$FH_J/job.json"
e2e_expect_line "valid"
fh_validate "$FH_SCHEMAS/factory-directive.schema.json" "$FH_J/directives/issue-7-j1-build-1.json"
e2e_expect_line "valid"
FH_WT=$(jq -r .worktree "$FH_J/job.json")
e2e_expect_equal "$(cd "$E2E_DIR" && pwd -P)/area/worktrees/issue-7" "$FH_WT" "job.worktree"
e2e_expect_equal "feature/issue-7-x-2" "$(git -C "$FH_WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" "the clone's branch"
fe_mask_text "$(git -C "$E2E_REPO" rev-parse HEAD)" "<scratch commit>"
e2e_expect_equal "$(git -C "$E2E_REPO" rev-parse HEAD)" "$(git -C "$FH_WT" rev-parse HEAD 2>/dev/null)" "the clone's commit"
if cmp -s "$FH_WT/.git/config" "$FH_J/clone-config/config"; then e2e_expect_equal same same "J/clone-config/config"; else e2e_expect_equal same different "J/clone-config/config"; fi
fe_job 7 build 'd["attempt"] = 2'
e2e_expect_equal "2" "$(jq .attempt "$FH_J/job.json")" "an edit passed to fe_job"
fe_art_state 7
fe_digest
fi

if fh_run h11; then
_flow_test_begin "factory helpers: fe_wait_for fails at its limit instead of hanging (H11)"
fe_new fh-wait-for
e2e_describe "fe_wait_for 2 false returns 1 after about two seconds and reports a failure; fe_wait_for 5 true returns 0 at once"
FH_T0=$(date +%s)
FH_GOT=$(E2E_ARTIFACT="$E2E_DIR/expected-failures.txt"; fe_wait_for 2 false; printf 'rc=%s\n' "$?")
FH_T1=$(date +%s)
e2e_expect_equal "rc=1" "$(printf '%s\n' "$FH_GOT" | grep '^rc=')" "fe_wait_for 2 false's status"
case "$FH_GOT" in
  *"FAIL "*"within 2 s: false"*) e2e_expect_equal reported reported "the failure it reports" ;;
  *) e2e_expect_equal reported "$FH_GOT" "the failure it reports" ;;
esac
FH_DT=$((FH_T1 - FH_T0))
if [ "$FH_DT" -ge 1 ] && [ "$FH_DT" -le 4 ]; then e2e_expect_equal "1-4 s" "1-4 s" "time fe_wait_for 2 took ($FH_DT s)"
else e2e_expect_equal "1-4 s" "$FH_DT s" "time fe_wait_for 2 took"; fi
FH_T0=$(date +%s)
fe_wait_for 5 true
e2e_expect_equal "0" "$?" "fe_wait_for 5 true's status"
FH_T1=$(date +%s)
if [ $((FH_T1 - FH_T0)) -le 1 ]; then e2e_expect_equal "at once" "at once" "fe_wait_for 5 true"
else e2e_expect_equal "at once" "$((FH_T1 - FH_T0)) s" "fe_wait_for 5 true"; fi
fi

# fh_q <jq filter> — the filter over the last command's stdout, compact.
fh_q() { printf '%s' "$E2E_OUT" | jq -c "$1" 2>&1; }
# fh_w <jq filter> — the filter over the scenario's world file, compact.
fh_w() { jq -c "$1" "$FE_WORLD" 2>&1; }
FH_R=repos/flow-e2e/scratch

if fh_run h12; then
_flow_test_begin "factory helpers: the world stub lists back what it was sent, first line intact (H12)"
fe_new fh-world-post
e2e_describe "fe_world_new and an issue; a comment posted with -F body=@file whose first line is an engine marker; the comment list then holds it under the engine login, and fe_world_posts shows the write"
e2e_repo main
fe_world_new flow-e2e-engine flow-e2e/scratch
fe_world_issue 7 "Add a port setting" "The server needs a port."
e2e_expect_equal "$E2E_DIR/world.json" "${FE_WORLD:-}" "FE_WORLD after fe_world_new"
e2e_expect_equal "flow-e2e/scratch" "$(git -C "$E2E_REPO" config remote.origin.gh-resolved)" "gh-resolved after fe_world_new"
printf '%s\n%s\n' '<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->' 'Which port?' > "$E2E_DIR/body.md"
_e2e_exec gh api --method POST "$FH_R/issues/7/comments" -F "body=@$E2E_DIR/body.md"
e2e_expect_equal "0" "$E2E_RC" "the POST's exit status ($E2E_ERR)"
FH_ID=$(fh_q .id)
_e2e_exec gh api "$FH_R/issues/7/comments?per_page=100"
e2e_expect_equal "0" "$E2E_RC" "the list's exit status ($E2E_ERR)"
e2e_expect_equal "1 $FH_ID flow-e2e-engine User" "$(fh_q '"\(length) \(.[0].id) \(.[0].user.login) \(.[0].user.type)"' | tr -d '"')" "the comment listed back"
e2e_expect_equal "$(cat "$E2E_DIR/body.md")" "$(printf '%s' "$E2E_OUT" | jq -r '.[0].body')" "the listed body, first line intact"
FH_POSTS=$(fe_world_posts)
e2e_expect_equal "1" "$(printf '%s\n' "$FH_POSTS" | grep -c .)" "posts lines"
e2e_expect_equal "\"POST $FH_R/issues/7/comments @$E2E_DIR/body.md\"" "$(printf '%s' "$FH_POSTS" | jq -c '"\(.method) \(.path) \(.fields.body)"')" "the post's method, path and field"
e2e_expect_equal "$(cat "$E2E_DIR/body.md")" "$(printf '%s' "$FH_POSTS" | jq -r .body)" "the post's body"

_flow_test_begin "factory helpers: a list read is paged, and --paginate --slurp gives every page (H13, R35)"
e2e_describe "150 comments 1001-1150 on issue 8: page 2 of 100 holds 1101-1150, page 1 under --include has a Link header naming page 2 as next, and --paginate --slurp prints two pages holding all 150 in id order"
fe_world_issue 8 "Many comments" "Body"
FH_I=1001
while [ "$FH_I" -le 1150 ]; do
  fe_world_comment 8 "$FH_I" alice write 2026-11-16T01:00:00Z "comment $FH_I"
  FH_I=$((FH_I + 1))
done
_e2e_exec gh api "$FH_R/issues/8/comments?per_page=100&page=2"
e2e_expect_equal "50 1101 1150" "$(fh_q '"\(length) \(.[0].id) \(.[-1].id)"' | tr -d '"')" "page 2"
_e2e_exec gh api --include "$FH_R/issues/8/comments?per_page=100"
e2e_expect_out "rel=\"next\""
e2e_expect_out "page=2>; rel=\"next\""
_e2e_exec gh api --paginate --slurp "$FH_R/issues/8/comments?per_page=100"
e2e_expect_equal "0" "$E2E_RC" "the --paginate --slurp exit status ($E2E_ERR)"
e2e_expect_equal "[100,50]" "$(fh_q '[.[] | length]')" "the pages"
e2e_expect_equal "true" "$(fh_q '[.[][] | .id] == [range(1001; 1151)]')" "every comment, in id order"

_flow_test_begin "factory helpers: post_fails stores nothing (H12)"
e2e_describe "with post_fails, a POST exits non-zero and leaves the comments and posts as they were"
fe_world_knob post_fails true
FH_BEFORE=$(fh_w '[(.comments["7"] | length), (.posts | length)]')
e2e_expect_equal "[1,1]" "$FH_BEFORE" "comments and posts before (the one comment posted above)"
_e2e_exec gh api --method POST "$FH_R/issues/7/comments" -f body=lost
e2e_expect_equal "1" "$E2E_RC" "the POST's exit status"
e2e_expect_err "HTTP 502"
e2e_expect_equal "$FH_BEFORE" "$(fh_w '[(.comments["7"] | length), (.posts | length)]')" "comments and posts"
fe_world_knob post_fails false

_flow_test_begin "factory helpers: die_after_post stores the write, then kills the stub's parent (H12, H14)"
e2e_describe "with die_after_post, gh run under a disposable bash parent that echoes after it: the comment is stored, the parent ends by SIGKILL so it never echoes, and this shell goes on"
fe_world_knob die_after_post true
_e2e_exec bash -c '"$0" api --method POST repos/flow-e2e/scratch/issues/7/comments -f body=last-words; echo survived' "$E2E_BIN/gh"
e2e_expect_equal "137" "$E2E_RC" "the disposable parent's exit status"
e2e_expect_no_out "survived"
e2e_expect_equal '"last-words"' "$(fh_w '.comments["7"][-1].body')" "the comment stored before the kill"
e2e_expect_equal '"last-words"' "$(fh_w '.posts[-1].body')" "the post recorded before the kill"
e2e_expect_equal "the scenario shell" "the scenario shell" "this shell is still running"
fi

if fh_run h15; then
_flow_test_begin "factory helpers: actor types, list_fails and the renamed event (H15)"
fe_new fh-world-actors
e2e_describe "deploy-app set to Bot: its comment and label event say Bot, alice's comment says User; list_fails [user] makes gh api user fail; a rename by outsider and one with no actor"
e2e_repo main
fe_world_new flow-e2e-engine flow-e2e/scratch
fe_world_issue 7 "Old title" "Body"
fe_world_actor_type deploy-app Bot
fe_world_comment 7 11 deploy-app write 2026-11-16T01:00:00Z "from the app"
fe_world_comment 7 12 alice write 2026-11-16T01:01:00Z "from a person"
fe_world_label 7 flow:factory deploy-app write 2026-11-16T01:02:00Z
_e2e_exec gh api "$FH_R/issues/7/comments"
e2e_expect_equal '["deploy-app Bot","alice User"]' "$(fh_q '[.[] | "\(.user.login) \(.user.type)"]')" "the comment authors"
_e2e_exec gh api "$FH_R/issues/7/events"
e2e_expect_equal '["labeled flow:factory deploy-app Bot"]' "$(fh_q '[.[] | "\(.event) \(.label.name) \(.actor.login) \(.actor.type)"]')" "the label event"
_e2e_exec gh api "$FH_R/issues?labels=flow:factory&state=open&per_page=100"
e2e_expect_equal '[7]' "$(fh_q '[.[].number]')" "the labelled open issues"
_e2e_exec gh api "$FH_R/collaborators/deploy-app/permission"
e2e_expect_equal '"write write"' "$(fh_q '"\(.role_name) \(.permission)"')" "the actor's permission from fe_world_label"
_e2e_exec gh api user
e2e_expect_equal '"flow-e2e-engine User"' "$(fh_q '"\(.login) \(.type)"')" "gh api user"
fe_world_knob list_fails '["user"]'
_e2e_exec gh api user
e2e_expect_equal "1" "$E2E_RC" "gh api user under list_fails [user]"
fe_world_knob list_fails '[]'
fe_world_rename 7 outsider read 2026-11-17T01:00:00Z "New title"
_e2e_exec gh api "$FH_R/issues/7"
e2e_expect_equal '"New title"' "$(fh_q .title)" "the title after fe_world_rename"
_e2e_exec gh api "$FH_R/issues/7/events"
e2e_expect_equal '[{"from":"Old title","to":"New title","actor":"outsider"}]' "$(fh_q '[.[] | select(.event == "renamed") | {from: .rename.from, to: .rename.to, actor: .actor.login}]')" "the renamed event"
_e2e_exec gh api "$FH_R/collaborators/outsider/permission"
e2e_expect_equal '"read"' "$(fh_q .role_name)" "the renamer's role"
fe_world_rename 7 - read 2026-11-17T02:00:00Z "Third title"
_e2e_exec gh api "$FH_R/issues/7/events"
e2e_expect_equal '[{"from":"New title","to":"Third title","actor":null}]' "$(fh_q '[.[] | select(.event == "renamed")][1:] | map({from: .rename.from, to: .rename.to, actor: .actor})')" "a rename with no actor"

_flow_test_begin "factory helpers: permissions, edits, labels, assignees, issue edit, pulls and closing through the world stub (H12, H15)"
e2e_describe "each read and write form B4 and B6 use, against values this scenario set"
fe_world_perm triager triage
fe_world_perm ghost status:404
fe_world_knob permission_fails '["flaky"]'
fe_world_perm flaky write
_e2e_exec gh api "$FH_R/collaborators/triager/permission"
e2e_expect_equal '"triage read"' "$(fh_q '"\(.role_name) \(.permission)"')" "triage: role_name triage, legacy permission read"
_e2e_exec gh api "$FH_R/collaborators/ghost/permission"
e2e_expect_equal "1" "$E2E_RC" "a status:404 entry"
e2e_expect_err "HTTP 404"
_e2e_exec gh api "$FH_R/collaborators/flaky/permission"
e2e_expect_err "HTTP 502"
_e2e_exec gh api "$FH_R/collaborators/nobody/permission"
e2e_expect_equal "1" "$E2E_RC" "a login with no entry"
fe_world_edit issue:7 outsider 2026-11-17T03:00:00Z
fe_world_edit issue:7 alice 2026-11-17T04:00:00Z
fe_world_edit comment:12 - 2026-11-17T05:00:00Z
_e2e_exec gh api graphql -f 'query=query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){lastEditedAt}}}' -f owner=flow-e2e -f name=scratch -F number=7
e2e_expect_equal "0" "$E2E_RC" "the graphql read ($E2E_ERR)"
e2e_expect_equal '{"last":"2026-11-17T04:00:00Z","editor":"alice","edits":["alice","outsider"]}' "$(fh_q '.data.repository.issue | {last: .lastEditedAt, editor: .editor.login, edits: [.userContentEdits.nodes[].editor.login]}')" "the issue body's edits, newest first"
e2e_expect_equal '[{"id":11,"editor":null},{"id":12,"editor":null,"at":"2026-11-17T05:00:00Z"}]' "$(fh_q '[.data.repository.issue.comments.nodes[] | {id: .databaseId, editor: .editor} + (if .lastEditedAt then {at: .lastEditedAt} else {} end)]')" "the comments' edits, a null editor kept"
_e2e_exec gh api --method POST "$FH_R/issues/7/labels" -f 'labels[]=flow:in-progress'
e2e_expect_equal '["flow:factory","flow:in-progress"]' "$(fh_w '.issues["7"].labels')" "after the label POST"
_e2e_exec gh api --method DELETE "$FH_R/issues/7/labels/flow%3Ain-progress"
e2e_expect_equal '["flow:factory"]' "$(fh_w '.issues["7"].labels')" "after the label DELETE"
_e2e_exec gh api --method POST "$FH_R/issues/7/assignees" -f 'assignees[]=alice'
e2e_expect_equal '["alice"]' "$(fh_w '.issues["7"].assignees')" "after the assignees POST"
_e2e_exec gh issue edit 7 --repo flow-e2e/scratch --add-assignee flow-e2e-engine --add-label flow:in-progress
e2e_expect_equal "0" "$E2E_RC" "gh issue edit ($E2E_ERR)"
e2e_expect_equal '{"a":["alice","flow-e2e-engine"],"l":["flow:factory","flow:in-progress"]}' "$(fh_w '.issues["7"] | {a: .assignees, l: .labels}')" "after gh issue edit"
_e2e_exec gh api --method PATCH "$FH_R/issues/comments/12" -f body=edited
e2e_expect_equal '"edited"' "$(fh_w '.comments["7"][] | select(.id == 12) | .body')" "after the comment PATCH"
fe_world_pull 31 feature/issue-7-x-2 alice write "Closes #7"
_e2e_exec gh api "$FH_R/pulls?state=open"
e2e_expect_equal '[{"n":31,"ref":"feature/issue-7-x-2","body":"Closes #7","by":"alice","head":"flow-e2e/scratch"}]' "$(fh_q '[.[] | {n: .number, ref: .head.ref, body, by: .user.login, head: .head.repo.full_name}]')" "the open pulls"
_e2e_exec gh api --method PATCH "$FH_R/pulls/31" -f state=closed
_e2e_exec gh api "$FH_R/pulls?state=open"
e2e_expect_equal '[]' "$(fh_q '.')" "no open pull after the PATCH"
e2e_expect_equal '["POST","DELETE","POST","issue edit","PATCH","PATCH"]' "$(fh_w '[.posts[].method]')" "every write in posts, in order"
fe_world_close 7 alice write 2026-11-17T06:00:00Z not_planned
_e2e_exec gh api "$FH_R/issues/7"
e2e_expect_equal '"closed not_planned alice"' "$(fh_q '"\(.state) \(.state_reason) \(.closed_by.login)"')" "the issue after fe_world_close"
_e2e_exec gh api "$FH_R/issues?labels=flow:factory&state=open&per_page=100"
e2e_expect_equal '[]' "$(fh_q '.')" "a closed issue is not listed as open"
_e2e_exec gh api "repos/someone/else/issues/7"
e2e_expect_equal "1" "$E2E_RC" "a repository the world does not name"
_e2e_exec gh pr list
e2e_expect_equal "99" "$E2E_RC" "an unhandled call under a world"
fi

if fh_run h16; then
_flow_test_begin "factory helpers: every factory scenario has a local origin, origin/HEAD and a base (H16)"
fe_new fh-origin-local
e2e_describe "fe_record gives the scratch repository a local bare origin with origin/main and origin/HEAD, gh-resolved flow-e2e/scratch; fe_job writes base main; a second fe_origin_local after a new commit moves origin/main"
e2e_repo main
fe_record
e2e_expect_equal "$E2E_DIR/origin.git" "$(git -C "$E2E_REPO" remote get-url origin)" "origin, a local path"
e2e_expect_equal "true" "$(git --git-dir="$E2E_DIR/origin.git" rev-parse --is-bare-repository 2>&1)" "origin is a bare repository"
e2e_expect_equal "$(git -C "$E2E_REPO" rev-parse HEAD)" "$(git -C "$E2E_REPO" rev-parse refs/remotes/origin/main 2>&1)" "origin/main"
e2e_expect_equal "refs/remotes/origin/main" "$(git -C "$E2E_REPO" symbolic-ref refs/remotes/origin/HEAD 2>&1)" "origin/HEAD"
e2e_expect_equal "flow-e2e/scratch" "$(git -C "$E2E_REPO" config remote.origin.gh-resolved)" "gh-resolved"
_e2e_exec git fetch -q origin main
e2e_expect_equal "0" "$E2E_RC" "a fetch from the local origin ($E2E_ERR)"
e2e_expect_equal "0" "$(grep -c 'https://' "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh")" "lines of factory-e2e.sh naming an https address"
fe_job 7 queued
e2e_expect_equal '"main"' "$(jq -c .base "$(fe_factory_dir)/jobs/issue-7/job.json")" "job.json base"
printf 'more\n' > "$E2E_REPO/more.txt"
_fe_in_scratch git add more.txt
_fe_in_scratch git commit -q -m more
fe_origin_local
e2e_expect_equal "$(git -C "$E2E_REPO" rev-parse HEAD)" "$(git -C "$E2E_REPO" rev-parse refs/remotes/origin/main 2>&1)" "origin/main after a second fe_origin_local"
fe_record_link
e2e_expect_equal "$E2E_DIR/origin.git" "$(git -C "$E2E_REPO" remote get-url origin)" "origin after fe_record_link"
_fe_in_scratch git remote set-url origin "$E2E_DIR/missing.git"
fe_record
e2e_expect_equal "$E2E_DIR/missing.git" "$(git -C "$E2E_REPO" remote get-url origin)" "an origin the scenario set is kept by fe_record"
fe_origin_local
fe_world_new flow-e2e-engine acme/widgets
e2e_expect_equal "acme/widgets" "$(git -C "$E2E_REPO" config remote.origin.gh-resolved)" "gh-resolved after fe_world_new"
fe_origin_local
e2e_expect_equal "acme/widgets" "$(git -C "$E2E_REPO" config remote.origin.gh-resolved)" "gh-resolved after fe_origin_local under a world"
fi

if fh_run h17; then
_flow_test_begin "factory helpers: fe_new drops the last world, and the stub with no world answers the new reads (H17)"
fe_new fh-world-gone
e2e_describe "a world in one scenario; fe_new; then FE_WORLD is unset and the stub answers api user and api repos/O/R from its defaults"
e2e_repo main
fe_world_new someone-else flow-e2e/scratch
fe_new fh-world-gone-next
e2e_repo main
e2e_expect_equal "" "${FE_WORLD:-}" "FE_WORLD after fe_new"
_e2e_exec gh api user
e2e_expect_equal '"flow-e2e-engine User"' "$(fh_q '"\(.login) \(.type)"')" "gh api user with no world"
_e2e_exec gh api repos/flow-e2e/scratch
e2e_expect_equal '"flow-e2e/scratch main"' "$(fh_q '"\(.full_name) \(.default_branch)"')" "gh api repos/O/R with no world"
fi

if fh_run h18; then
_flow_test_begin "factory helpers: _fe_scratch_env drops the test's XDG_STATE_HOME (H18)"
fe_new fh-xdg-state
e2e_describe "XDG_STATE_HOME exported in the test's shell; probe_area run through a helper that uses _fe_scratch_env makes its folder under the scratch HOME's .local/state"
e2e_repo main
FH_XDG_KEEP=${XDG_STATE_HOME-__unset__}
export XDG_STATE_HOME="$E2E_DIR/outer-state"
FH_AREA=$(_fe_in_scratch "$(fe_python)" -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import _flow_factory as ff; print(ff.probe_area("P9"))' "$E2E_ACTIVE_PLUGIN/bin")
if [ "$FH_XDG_KEEP" = __unset__ ]; then unset XDG_STATE_HOME; else export XDG_STATE_HOME="$FH_XDG_KEEP"; fi
e2e_expect_equal "$(cd "$E2E_HOME" && pwd -P)/.local/state/flow-factory/probe/P9-1" "$FH_AREA" "the probe folder"
e2e_expect_equal "absent" "$([ -e "$E2E_DIR/outer-state" ] && echo present || echo absent)" "the exported state folder"
fi

if fh_run h8; then
_flow_test_begin "factory helpers: the real main checkout's factory folder did not change during this file (H8)"
fe_new fh-real-factory-unchanged
e2e_describe "the listing (names, kinds, sizes, modification times; no file opened) of the main checkout's .flow/factory, taken before the first scenario and now, is the same; a folder that did not exist still does not"
# The comparison names each changed path: checked on two made-up listings, one
# path's time changed and one path added.
e2e_expect_equal "jobs/a.json new.json" "$(fh_changed "$(printf '.\td\t\t1\njobs/a.json\tf\t3\t5')" \
  "$(printf '.\td\t\t1\njobs/a.json\tf\t3\t6\nnew.json\tf\t1\t7')")" "the paths a changed listing names"
FH_FACTORY_AFTER=$(fh_listing)
FH_CHANGED=$(fh_changed "$FH_FACTORY_BEFORE" "$FH_FACTORY_AFTER")
if [ -z "$FH_CHANGED" ] && [ -n "$FH_FACTORY_AFTER" ]; then
  e2e_expect_equal unchanged unchanged "the main checkout's factory folder ($(printf '%s\n' "$FH_FACTORY_AFTER" | sed -n 1p | cut -f1))"
else
  e2e_expect_equal unchanged "changed: ${FH_CHANGED:-no listing}" "the main checkout's factory folder $FH_REAL_FACTORY (another session, such as a probe, may also write there)"
fi
fi
