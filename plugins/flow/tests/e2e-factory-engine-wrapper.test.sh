# shellcheck shell=bash
# The factory wrapper, bin/flow-factory.sh: how it finds the probe record (the
# outermost live launcher above it, else the working directory's main
# checkout), how it vets the interpreter the record names, the refusal lines it
# prints, the `await` and `report` answers it gives in shell when that
# interpreter is gone, and its exec into the engine.
#
# Ways it can be wrong, written down before the checks:
#   WR1  `context --mode` starts Python or reads the record (AC1, I4)
#   WR2  a subcommand runs with no record, or refuses without the next: step
#   WR3  the recorded interpreter is missing and a subcommand runs anyway, or
#        `report` and `await` are refused instead of answered in shell
#   WR4  a #! script, a ~/ path, a shims path or an interpreter inside the main
#        checkout is exec'd
#   WR5  a PATH python3 runs on the exec path (the phase 0 PYTHONPATH
#        sanitizer ran one for every subcommand), or PYTHONPATH reaches the
#        processes the engine starts, whose own sanitizers then run one
#   WR6  the exec does not reach the engine
#   WR7  the shell `report` writes outside the job folder, or through a
#        symlinked pending-report file or directives folder
#   WR8  jq is missing and the wrapper crashes or runs on
#   WR16 a worker's person-only subcommand gets a shell refusal (exit 5) for a
#        missing record, jq or interpreter, not PERSON_ONLY_REFUSED (exit 4)
#   WR9  under a launcher, the record is found from the working directory, so a
#        worker in its clone or in /tmp gets no_probe_record or
#        not_in_repository (RM1 lookup half, R3, A+5)
#   WR10 FLOW_FACTORY_MAIN chooses the record, and so the interpreter (R4)
#   WR11 the nearest marker is taken, so a process below the real launcher that
#        imitates one chooses the record (R30)
#   WR12 a width-limited ps, or a ps found on PATH, loses the marker (R28, R29)
#   WR13 a plugin path or factory directory holding a space breaks the marker
#        parse (A+6)
#   WR14 a moved factory directory reads as "no record"
#   WR15 a marker ancestor counts although its lease is revoked, or names
#        another start time or pid (a pid the system gave to another process)
#
# WR9 and WR11-WR13 run `wait` under the launcher: the engine answers it with
# FACTORY_REFUSED=not_built before any other check (plan 2.7 step 1b), and only
# the engine prints that line once a record is found, so it shows the wrapper
# found the launcher's record and exec'd the engine. A worker script waits
# until the launcher's lease names its parent before it runs the wrapper, and
# records that it did, so a scenario cannot pass because a lease was not there
# yet.
#
# FW_ONLY=<id> (WR1 ... WR15) runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

fw_run() { [ -z "${FW_ONLY:-}" ] || [ "$FW_ONLY" = "$1" ]; }

FW_ID=issue-7-j1-build-1
FW_NO_RECORD="FACTORY_REFUSED=no_probe_record next: run the phase 0 probes"
FW_DISABLED="FACTORY_REFUSED=disabled next: set flow.factory.enabled"

# fw_fake_pythons — a folder holding python3, python3.14 and python stand-ins
# that each append their name, arguments and parent's command line to
# $E2E_DIR/python-ran. Prints the folder.
fw_fake_pythons() {
  local d="$E2E_DIR/fake-python" n
  mkdir -p "$d"
  for n in python3 python3.14 python; do
    printf '#!/bin/bash\nprintf "%%s %%s parent=%%s\\n" "$0" "$*" "$(/bin/ps -ww -o command= -p $PPID)" >> %q\nexit 0\n' \
      "$E2E_DIR/python-ran" > "$d/$n"
    chmod +x "$d/$n"
  done
  printf '%s' "$d"
}

# fw_expect_no_python — no python stand-in ran.
fw_expect_no_python() {
  if [ -e "$E2E_DIR/python-ran" ]; then
    e2e_expect_equal "absent" "present: $(tr '\n' ';' < "$E2E_DIR/python-ran")" "python-ran ${1:-}"
  else
    e2e_expect_equal "absent" "absent" "python-ran ${1:-}"
  fi
}

# fw_marker_script <path> <marker> — a #! script that touches the marker.
fw_marker_script() {
  mkdir -p "$(dirname -- "$1")"
  printf '#!/bin/bash\ntouch %q\nexit 0\n' "$2" > "$1"
  chmod +x "$1"
}

# fw_expect_absent <path> <what>
fw_expect_absent() {
  if [ -e "$1" ] || [ -L "$1" ]; then e2e_expect_equal absent present "$2"
  else e2e_expect_equal absent absent "$2"; fi
}

# fw_worker_script <file> <lease file> <body> — a worker script for
# fe_fake_launcher (or a launcher a worker starts). It waits up to 10 s for the
# lease to name its parent (the launcher), records lease-live or lease-missing
# in $E2E_DIR/w/<script name>.lease, then runs the body. The body may call
#   fw_w <tag> <cwd> [NAME=value ...] -- <wrapper arguments>
# which runs the active plugin's wrapper from <cwd> with every FLOW_FACTORY_*
# variable removed and the NAME=value settings added, writing
# $E2E_DIR/w/<tag>.out, .err and .rc.
fw_worker_script() {
  local file="$1" lease="$2" body="$3"
  mkdir -p "$E2E_DIR/w"
  {
    printf 'W=%q\nR=%q\nLEASE=%q\nME=%q\n' "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" "$E2E_DIR/w" "$lease" "$(basename -- "$file")"
    cat <<'SH'
i=0
until [ "$(jq -r '.launcher_pid // empty' "$LEASE" 2>/dev/null)" = "$PPID" ]; do
  i=$((i + 1))
  [ "$i" -gt 100 ] && break
  sleep 0.1
done
if [ "$i" -gt 100 ]; then echo lease-missing > "$R/$ME.lease"; else echo lease-live > "$R/$ME.lease"; fi
fw_w() {
  local tag="$1" cwd="$2" envs=()
  shift 2
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  ( cd "$cwd" || exit 96
    exec env -u FLOW_FACTORY_JOB -u FLOW_FACTORY_DIRECTIVE -u FLOW_FACTORY_IO -u FLOW_FACTORY_MAIN \
      ${envs[@]+"${envs[@]}"} "$W" "$@" ) < /dev/null > "$R/$tag.out" 2> "$R/$tag.err"
  echo "$?" > "$R/$tag.rc"
}
SH
    printf '%s\n' "$body"
  } > "$file"
}

# fw_worker_result <tag> — wait up to 60 s for $E2E_DIR/w/<tag>.rc, then set
# E2E_OUT, E2E_ERR and E2E_RC from it and write them to the artifact.
fw_worker_result() {
  fe_wait_for 60 "[ -f '$E2E_DIR/w/$1.rc' ]" || { E2E_OUT=""; E2E_ERR=""; E2E_RC=none; return 1; }
  E2E_RC=$(cat "$E2E_DIR/w/$1.rc")
  E2E_OUT=$(cat "$E2E_DIR/w/$1.out" 2>/dev/null)
  E2E_ERR=$(cat "$E2E_DIR/w/$1.err" 2>/dev/null)
  _fe_record_outcome "the wrapper below the launcher ($1)"
}

# fw_expect_lease_live <script name> — the worker script saw its lease live.
fw_expect_lease_live() {
  e2e_expect_equal lease-live "$(cat "$E2E_DIR/w/$1.lease" 2>/dev/null)" "the lease $1 waited for"
}

# fw_clone_no_record — a clone of the scratch repository with no record at
# $E2E_DIR/other. Prints its path.
fw_clone_no_record() {
  _fe_in_scratch git clone -q "$E2E_REPO" "$E2E_DIR/other" >/dev/null 2>&1 \
    || _e2e_result fail "cloned the scratch repository to $E2E_DIR/other"
  printf '%s' "$E2E_DIR/other"
}

# The subcommands WR2 and WR3 run, one per line.
FW_SUBS='next
status
wait --max-seconds 1
run --once
question q --prompt
runner start
runner print-launchd
runner print-cron
launch issue-7-j1-build-1
report issue-7-j1-build-1
await q --max-seconds 1
answer q --choice 1
approve-spec 7 --spec-hash ab
confirm i
feedback 7 x
rework 7 x
retry 7
reject 7
cancel 7
rebuild 7
context --mode'

# fw_each_sub <callback> — call the callback with each subcommand's words.
# `context --mode` is run with FLOW_FACTORY_JOB=x, so it is not the off path.
fw_each_sub() {
  local line words
  while IFS= read -r line; do
    read -r -a words <<<"$line"
    "$1" "${words[@]}"
  done <<<"$FW_SUBS"
}

if fw_run WR1; then
_flow_test_begin "factory wrapper: context --mode with no setting starts no Python and reads no record (WR1)"
fe_new fw-context-off
e2e_describe "a valid record, no flow.factory setting, no worker variable, and python3, python3.14 and python stand-ins first on PATH: context --mode prints exactly FACTORY_MODE=off and no stand-in runs"
e2e_repo main
fe_record
FW_FAKE=$(fw_fake_pythons)
e2e_run_bin PATH="$FW_FAKE:$E2E_BIN:$PATH" bin/flow-factory.sh context --mode < /dev/null
e2e_expect_equal 0 "$E2E_RC" "exit status"
assert_equal "FACTORY_MODE=off" "$E2E_OUT" "stdout is exactly FACTORY_MODE=off"
fw_expect_no_python
fi

if fw_run WR2; then
_flow_test_begin "factory wrapper: every subcommand with no record exits 5 naming the next step (WR2)"
fe_new fw-no-record
e2e_describe "no probe record: every subcommand but probe exits 5 with exactly the no_probe_record line and its next: step, and no python stand-in runs"
e2e_repo main
FW_FAKE=$(fw_fake_pythons)
fw_wr2() {
  if [ "$1" = context ]; then
    e2e_run_bin PATH="$FW_FAKE:$E2E_BIN:$PATH" FLOW_FACTORY_JOB=x bin/flow-factory.sh "$@" < /dev/null
  else
    e2e_run_bin PATH="$FW_FAKE:$E2E_BIN:$PATH" bin/flow-factory.sh "$@" < /dev/null
  fi
  e2e_expect_equal 5 "$E2E_RC" "exit status of $*"
  e2e_expect_equal "$FW_NO_RECORD" "$E2E_OUT" "stdout of $*"
}
fw_each_sub fw_wr2
# A worker's person-only (and engine-guarded) subcommand is refused with exit
# 4 before the shell's own refusals, as the engine refuses it first.
for FW_SUB in answer approve-spec confirm feedback rework retry reject cancel rebuild run next probe; do
  e2e_run_bin PATH="$FW_FAKE:$E2E_BIN:$PATH" FLOW_FACTORY_JOB=x bin/flow-factory.sh "$FW_SUB" < /dev/null
  e2e_expect_equal 4 "$E2E_RC" "exit status of $FW_SUB from a worker"
  e2e_expect_equal "PERSON_ONLY_REFUSED=worker_env" "$E2E_OUT" "stdout of $FW_SUB from a worker"
done
fw_expect_no_python
fi

if fw_run WR3; then
_flow_test_begin "factory wrapper: a missing interpreter refuses every subcommand but await and report, which are answered in shell (WR3)"
fe_new fw-interpreter-gone
e2e_describe "the record names a link that is then removed: every subcommand but await and report exits 5 with interpreter_missing and its next: step; await prints PARK; report appends one pending-report line from its caller"
e2e_repo main
fe_record_link
rm "$E2E_DIR/py/python3.14"
fe_directive "$FW_ID"
FW_F=$(fe_factory_dir)
FW_MISSING="FACTORY_REFUSED=interpreter_missing recorded=$E2E_DIR/py/python3.14 next: flow-factory.sh probe --environment"
fw_wr3() {
  case "$1" in report|await) return 0 ;; esac
  if [ "$1" = context ]; then
    e2e_run_bin FLOW_FACTORY_JOB=x bin/flow-factory.sh "$@" < /dev/null
  else
    e2e_run_bin bin/flow-factory.sh "$@" < /dev/null
  fi
  e2e_expect_equal 5 "$E2E_RC" "(a) exit status of $*"
  e2e_expect_equal "$FW_MISSING" "$E2E_OUT" "(a) stdout of $*"
}
fw_each_sub fw_wr3
e2e_run_bin bin/flow-factory.sh await q --max-seconds 1 < /dev/null
e2e_expect_equal 0 "$E2E_RC" "(b) exit status of await"
e2e_expect_equal PARK "$E2E_OUT" "(b) stdout of await"
printf '{"outcome":"completed","note":"from WR3"}\n' > "$E2E_DIR/r.json"
W="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
_e2e_exec bash -c 'echo $$ > "$E2E_DIR/caller.pid"; "$1" report issue-7-j1-build-1 < "$2"; rc=$?; echo "$rc" > "$E2E_DIR/report.rc"; :' _ "$W" "$E2E_DIR/r.json"
FW_PENDING="$FW_F/jobs/issue-7/directives/$FW_ID.pending-report.jsonl"
e2e_expect_equal 0 "$(cat "$E2E_DIR/report.rc" 2>/dev/null)" "(c) exit status of report"
e2e_expect_equal 1 "$(wc -l < "$FW_PENDING" 2>/dev/null | tr -d ' ')" "(c) lines in the pending-report file"
fe_mask_pid "$(cat "$E2E_DIR/caller.pid")" caller
e2e_expect_equal "$(cat "$E2E_DIR/caller.pid")" "$(jq -r .caller_pid "$FW_PENDING" 2>/dev/null)" "(c) caller_pid"
e2e_expect_equal "$(jq -c . "$E2E_DIR/r.json")" "$(jq -c .report "$FW_PENDING" 2>/dev/null)" "(c) report"
e2e_expect_equal "$FW_ID" "$(jq -r .directive "$FW_PENDING" 2>/dev/null)" "(c) directive"
FW_START=$(jq -r .caller_start "$FW_PENDING" 2>/dev/null)
case "$FW_START" in
  [A-Z][a-z][a-z]\ [A-Z][a-z][a-z]\ [\ 0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ [0-9][0-9][0-9][0-9])
    e2e_expect_equal ok ok "(c) caller_start is a trimmed lstart (24 characters)" ;;
  *) e2e_expect_equal "a trimmed lstart" "'$FW_START'" "(c) caller_start" ;;
esac
case "$(jq -r .at "$FW_PENDING" 2>/dev/null)" in
  20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z) e2e_expect_equal ok ok "(c) at is a UTC time" ;;
  *) e2e_expect_equal "a UTC time" "$(jq -r .at "$FW_PENDING" 2>/dev/null)" "(c) at" ;;
esac
fi

if fw_run WR4; then
_flow_test_begin "factory wrapper: an interpreter that fails vetting is refused, never exec'd (WR4)"
FW_N=0
for FW_KIND in hashbang tilde shims inrepo; do
  FW_N=$((FW_N + 1))
  fe_new "fw-vet-$FW_KIND"
  e2e_describe "the record's interpreter is a $FW_KIND path: next exits 5 with interpreter_missing naming it, and nothing runs it"
  e2e_repo main
  case "$FW_KIND" in
    hashbang) FW_INTERP="$E2E_DIR/hb/python3.14"; fw_marker_script "$FW_INTERP" "$E2E_DIR/interp-ran" ;;
    tilde) FW_INTERP="~/x/python3.14" ;;
    shims) FW_INTERP="$E2E_DIR/shims/python3.14"; mkdir -p "$E2E_DIR/shims"; cp "$(fe_python)" "$FW_INTERP" ;;
    inrepo) FW_INTERP="$E2E_REPO/py/python3.14"; mkdir -p "$E2E_REPO/py"; cp "$(fe_python)" "$FW_INTERP" ;;
  esac
  fe_record "d['interpreter'] = '$FW_INTERP'"
  e2e_run_bin bin/flow-factory.sh next --executor headless < /dev/null
  e2e_expect_equal 5 "$E2E_RC" "exit status"
  e2e_expect_equal "FACTORY_REFUSED=interpreter_missing recorded=$FW_INTERP next: flow-factory.sh probe --environment" "$E2E_OUT" "stdout"
  fw_expect_absent "$E2E_DIR/interp-ran" "the interpreter's marker"
done
fi

if fw_run WR5; then
_flow_test_begin "factory wrapper: no PATH python3 runs on the exec path, with PYTHONPATH set (WR5)"
fe_new fw-no-path-python
e2e_describe "a valid record, PYTHONPATH set to a folder, python stand-ins first on PATH: next reaches the engine's disabled line and no stand-in runs"
e2e_repo main
fe_record
mkdir -p "$E2E_DIR/pp"
FW_FAKE=$(fw_fake_pythons)
e2e_run_bin PATH="$FW_FAKE:$E2E_BIN:$PATH" PYTHONPATH="$E2E_DIR/pp" bin/flow-factory.sh next --executor headless < /dev/null
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "$FW_DISABLED" "$E2E_OUT" "stdout"
fw_expect_no_python "(marker) after next"
# status passes the gate, so the engine resolves the factory directory, which
# runs flow-runtime-dir.sh. Only the stand-ins' absence is checked: status's
# own output belongs to the engine.
e2e_run_bin PATH="$FW_FAKE:$E2E_BIN:$PATH" PYTHONPATH="$E2E_DIR/pp" bin/flow-factory.sh status < /dev/null
fw_expect_no_python "(marker) after status, through the engine's own helpers"
fi

if fw_run WR6; then
_flow_test_begin "factory wrapper: the exec reaches the engine (WR6)"
fe_new fw-exec
e2e_describe "a valid record and no flow.factory setting: next prints the disabled line, which only the engine prints"
e2e_repo main
fe_record
e2e_run_bin bin/flow-factory.sh next --executor headless < /dev/null
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "$FW_DISABLED" "$E2E_OUT" "stdout"
fi

if fw_run WR7; then
_flow_test_begin "factory wrapper: the shell report refuses a bad id and a symlinked pending-report file or folder (WR7)"
fe_new fw-report-refusals
e2e_describe "interpreter removed: report ../../x is refused as directive_id_invalid and writes nothing; a symlinked pending-report file, and a symlinked directives folder, are refused as pending_report_linked and nothing is written through them"
e2e_repo main
fe_record_link
rm "$E2E_DIR/py/python3.14"
FW_F=$(fe_factory_dir)
printf '{"outcome":"completed"}\n' > "$E2E_DIR/r.json"
# (i) the id
e2e_run_bin bin/flow-factory.sh status < /dev/null
FW_BEFORE=$(cd "$E2E_DIR" && find . ! -path ./out ! -path ./err | LC_ALL=C sort | cksum)
e2e_run_bin bin/flow-factory.sh report ../../x < "$E2E_DIR/r.json"
e2e_expect_equal 5 "$E2E_RC" "(i) exit status"
e2e_expect_equal "FACTORY_REFUSED=directive_id_invalid" "$E2E_OUT" "(i) stdout"
FW_AFTER=$(cd "$E2E_DIR" && find . ! -path ./out ! -path ./err | LC_ALL=C sort | cksum)
fe_mask_text "$FW_BEFORE" '<checksum> <size>'
e2e_expect_equal "$FW_BEFORE" "$FW_AFTER" "(i) the checksum of the list of files under the scenario folder"
# (ii) the pending-report file is a symlink
fe_directive "$FW_ID"
printf 'outside\n' > "$E2E_DIR/outside"
ln -s "$E2E_DIR/outside" "$FW_F/jobs/issue-7/directives/$FW_ID.pending-report.jsonl"
e2e_run_bin bin/flow-factory.sh report "$FW_ID" < "$E2E_DIR/r.json"
e2e_expect_equal 5 "$E2E_RC" "(ii) exit status"
e2e_expect_equal "FACTORY_REFUSED=pending_report_linked directive=$FW_ID" "$E2E_OUT" "(ii) stdout"
e2e_expect_equal outside "$(cat "$E2E_DIR/outside")" "(ii) the symlink's target"
# (iii) the directives folder is a symlink
rm "$FW_F/jobs/issue-7/directives/$FW_ID.pending-report.jsonl"
mv "$FW_F/jobs/issue-7/directives" "$E2E_DIR/real-directives"
ln -s "$E2E_DIR/real-directives" "$FW_F/jobs/issue-7/directives"
e2e_run_bin bin/flow-factory.sh report "$FW_ID" < "$E2E_DIR/r.json"
e2e_expect_equal 5 "$E2E_RC" "(iii) exit status"
e2e_expect_equal "FACTORY_REFUSED=pending_report_linked directive=$FW_ID" "$E2E_OUT" "(iii) stdout"
fw_expect_absent "$E2E_DIR/real-directives/$FW_ID.pending-report.jsonl" "(iii) a pending-report file in the linked folder"
fi

if fw_run WR8; then
_flow_test_begin "factory wrapper: jq missing is refused with its next: step (WR8)"
fe_new fw-no-jq
e2e_describe "a valid record and no jq on PATH: status exits 5 with jq_missing"
e2e_repo main
fe_record
FW_PATH=$(e2e_path_without jq)
e2e_run_bin PATH="$FW_PATH" bin/flow-factory.sh status < /dev/null
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=jq_missing next: install jq" "$E2E_OUT" "stdout"
fi

if fw_run WR9; then
_flow_test_begin "factory wrapper: under a live launcher the record is the launcher's, not the working directory's (WR9)"
fe_new fw-launcher-lookup
e2e_describe "a fake launcher for the scratch main checkout's factory directory; its worker runs wait, with every FLOW_FACTORY_* removed, from (i) a clone with no record and (ii) /tmp: both reach the engine (not_built), not the shell's no_probe_record or not_in_repository"
e2e_repo main
fe_record
FW_F=$(fe_factory_dir)
FW_OTHER=$(fw_clone_no_record)
FW_LEASE="$FW_F/jobs/issue-7/directives/$FW_ID.lease.json"
fw_worker_script "$E2E_DIR/worker.sh" "$FW_LEASE" "fw_w clone $(printf %q "$FW_OTHER") -- wait --max-seconds 1
fw_w tmp /tmp -- wait --max-seconds 1"
FW_LPID=$(fe_fake_launcher "$FW_F" "$FW_ID" "$E2E_DIR/worker.sh")
[ -n "$FW_LPID" ] && fe_mask_pid "$FW_LPID" launcher
fe_wait_for 60 "[ -f '$E2E_DIR/w/tmp.rc' ]"
fw_expect_lease_live worker.sh
fw_worker_result clone
e2e_expect_equal 5 "$E2E_RC" "(i) exit status"
e2e_expect_equal "FACTORY_REFUSED=not_built" "$E2E_OUT" "(i) stdout, from a clone with no record"
fw_worker_result tmp
e2e_expect_equal 5 "$E2E_RC" "(ii) exit status"
e2e_expect_equal "FACTORY_REFUSED=not_built" "$E2E_OUT" "(ii) stdout, from /tmp"
fi

if fw_run WR10; then
_flow_test_begin "factory wrapper: FLOW_FACTORY_MAIN does not choose the record (WR10)"
fe_new fw-main-variable
e2e_describe "cwd the main checkout with a valid record; FLOW_FACTORY_MAIN names a folder whose record names a marker script: next reaches the engine's disabled line and the script never runs"
e2e_repo main
fe_record
mkdir -p "$E2E_DIR/planted/.flow/factory"
fw_marker_script "$E2E_DIR/planted/py.sh" "$E2E_DIR/planted-ran"
jq -n --arg i "$E2E_DIR/planted/py.sh" '{interpreter: $i}' > "$E2E_DIR/planted/.flow/factory/probes.json"
e2e_run_bin FLOW_FACTORY_MAIN="$E2E_DIR/planted" bin/flow-factory.sh next --executor headless < /dev/null
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "$FW_DISABLED" "$E2E_OUT" "stdout"
fw_expect_absent "$E2E_DIR/planted-ran" "the planted interpreter's marker"
fi

if fw_run WR11; then
_flow_test_begin "factory wrapper: the outermost live launcher chooses the record, not the nearest (WR11)"
fe_new fw-outermost
e2e_describe "the WR9 launcher's worker starts a second launcher naming a planted factory directory (its own live lease, a record naming a marker script); the inner worker runs wait from a clone with no record: the engine answers not_built and the planted script never runs"
e2e_repo main
fe_record
FW_F=$(fe_factory_dir)
FW_OTHER=$(fw_clone_no_record)
FW_PF="$E2E_DIR/planted/F"
mkdir -p "$FW_PF"
fw_marker_script "$E2E_DIR/planted/py.sh" "$E2E_DIR/planted-ran"
jq -n --arg i "$E2E_DIR/planted/py.sh" '{interpreter: $i}' > "$FW_PF/probes.json"
fw_worker_script "$E2E_DIR/inner.sh" "$FW_PF/jobs/issue-7/directives/$FW_ID.lease.json" \
  "fw_w inner $(printf %q "$FW_OTHER") -- wait --max-seconds 1"
fw_worker_script "$E2E_DIR/outer.sh" "$FW_F/jobs/issue-7/directives/$FW_ID.lease.json" \
  "FE_WORKER_SCRIPT=$(printf %q "$E2E_DIR/inner.sh") $(printf %q "$(fe_python)") $(printf %q "$FE_FIXTURES/worker/fake_launcher.py") $(printf %q "$(cd "$E2E_ACTIVE_PLUGIN" && pwd -P)/bin/_flow_factory_launch.py") --factory-dir $(printf %q "$FW_PF") $FW_ID"
FW_LPID=$(fe_fake_launcher "$FW_F" "$FW_ID" "$E2E_DIR/outer.sh")
[ -n "$FW_LPID" ] && fe_mask_pid "$FW_LPID" launcher
fw_worker_result inner
fw_expect_lease_live outer.sh
fw_expect_lease_live inner.sh
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=not_built" "$E2E_OUT" "stdout"
fw_expect_absent "$E2E_DIR/planted-ran" "the planted interpreter's marker"
fi

if fw_run WR12; then
_flow_test_begin "factory wrapper: a narrow terminal and a ps on PATH do not lose the marker (WR12)"
fe_new fw-ps-width
e2e_describe "a plugin copy at a path over 200 characters; under its launcher the worker runs wait from a clone with no record, (a) with COLUMNS=20 and (b) with a ps that prints nothing first on PATH: both reach the engine"
e2e_repo main
FW_LONG="$E2E_DIR/$(printf 'p%.0s' $(seq 1 70))/$(printf 'q%.0s' $(seq 1 70))/$(printf 'r%.0s' $(seq 1 70))/plugin"
mkdir -p "$(dirname -- "$FW_LONG")"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$FW_LONG" || _e2e_result fail "copied the plugin to a long path"
E2E_ACTIVE_PLUGIN="$FW_LONG"
printf 'plugin for this scenario: a copy at a path of %s characters\n' "${#FW_LONG}" | _e2e_art
fe_record
FW_F=$(fe_factory_dir)
FW_OTHER=$(fw_clone_no_record)
mkdir -p "$E2E_DIR/fake-ps"
printf '#!/bin/bash\nexit 0\n' > "$E2E_DIR/fake-ps/ps"
chmod +x "$E2E_DIR/fake-ps/ps"
fw_worker_script "$E2E_DIR/worker.sh" "$FW_F/jobs/issue-7/directives/$FW_ID.lease.json" \
  "fw_w narrow $(printf %q "$FW_OTHER") COLUMNS=20 -- wait --max-seconds 1
fw_w pathps $(printf %q "$FW_OTHER") PATH=$(printf %q "$E2E_DIR/fake-ps"):\"\$PATH\" -- wait --max-seconds 1"
FW_LPID=$(fe_fake_launcher "$FW_F" "$FW_ID" "$E2E_DIR/worker.sh")
[ -n "$FW_LPID" ] && fe_mask_pid "$FW_LPID" launcher
fe_wait_for 60 "[ -f '$E2E_DIR/w/pathps.rc' ]"
fw_expect_lease_live worker.sh
fw_worker_result narrow
e2e_expect_equal 5 "$E2E_RC" "(a) exit status"
e2e_expect_equal "FACTORY_REFUSED=not_built" "$E2E_OUT" "(a) stdout with COLUMNS=20"
fw_worker_result pathps
e2e_expect_equal 5 "$E2E_RC" "(b) exit status"
e2e_expect_equal "FACTORY_REFUSED=not_built" "$E2E_OUT" "(b) stdout with a ps on PATH that prints nothing"
fi

if fw_run WR13; then
_flow_test_begin "factory wrapper: a plugin path and factory directory holding spaces still parse (WR13)"
fe_new fw-spaces
e2e_describe "the plugin copy at '<dir>/plug in' and the main checkout at '<dir>/re po' (so the factory directory holds a space); under the launcher the worker runs wait from a clone with no record and reaches the engine"
FW_PLUG="$E2E_DIR/plug in"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$FW_PLUG" || _e2e_result fail "copied the plugin to a path with a space"
E2E_ACTIVE_PLUGIN="$FW_PLUG"
E2E_REPO="$E2E_DIR/re po"
mkdir -p "$E2E_REPO"
_fe_in_scratch sh -c 'git init -q && git config user.email e2e@example.invalid && git config user.name e2e \
  && git config commit.gpgsign false && printf "e2e\n" > README.md && git add README.md \
  && git commit -q -m init && git checkout -q -b main' || _e2e_result fail "made the scratch repository 're po'"
fe_record
FW_F=$(fe_factory_dir)
case "$FW_F" in *' '*) e2e_expect_equal ok ok "the factory directory holds a space" ;;
  *) e2e_expect_equal "a path with a space" "$FW_F" "the factory directory" ;; esac
FW_OTHER=$(fw_clone_no_record)
fw_worker_script "$E2E_DIR/worker.sh" "$FW_F/jobs/issue-7/directives/$FW_ID.lease.json" \
  "fw_w spaces $(printf %q "$FW_OTHER") -- wait --max-seconds 1"
FW_LPID=$(fe_fake_launcher "$FW_F" "$FW_ID" "$E2E_DIR/worker.sh")
[ -n "$FW_LPID" ] && fe_mask_pid "$FW_LPID" launcher
fw_worker_result spaces
fw_expect_lease_live worker.sh
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=not_built" "$E2E_OUT" "stdout"
fi

if fw_run WR14; then
_flow_test_begin "factory wrapper: a moved factory directory is reported as moved, not as no record (WR14)"
fe_new fw-moved
e2e_describe "no record at F, and the pointer in the common git directory names another folder holding probes.json: exit 5 with factory_path_changed naming both"
e2e_repo main
fe_record
FW_F=$(fe_factory_dir)
mkdir -p "$E2E_DIR/old/F"
mv "$FW_F/probes.json" "$E2E_DIR/old/F/probes.json"
FW_COMMON=$(_fe_in_scratch git rev-parse --path-format=absolute --git-common-dir)
printf '%s\n' "$E2E_DIR/old/F" > "$FW_COMMON/flow-factory-path"
e2e_run_bin bin/flow-factory.sh status < /dev/null
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=factory_path_changed recorded=$E2E_DIR/old/F current=$FW_F" "$E2E_OUT" "stdout"
fi

if fw_run WR15; then
_flow_test_begin "factory wrapper: a marker ancestor counts only with a live lease naming its pid and start time (WR15)"
# The marker ancestor is a bash whose arguments end in a marker; it writes its
# own lease (so no launcher has to be waited for) and runs wait from the main
# checkout, which has a valid record. The planted F's record names a marker
# script, so taking the planted F gives interpreter_missing naming it, and
# taking the main checkout's record reaches the engine (not_built).
FW_SCRIPT='s=$(LC_ALL=C /bin/ps -o lstart= -p $$); s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
pid=$$; rev=null
case "$FW_MODE" in
  badstart) s="Thu Jan  1 00:00:00 1970" ;;
  badpid) pid=1 ;;
  revoked) rev="\"2026-11-16T00:00:00Z\"" ;;
esac
mkdir -p "$FW_LD"
jq -n --argjson p "$pid" --arg s "$s" --argjson r "$rev" "{directive: \"issue-7-j1-build-1\", kind: \"worker\", host: \"h\",
  launcher_pid: \$p, launcher_start: \$s, started_at: \"2026-11-16T00:00:00Z\", heartbeat_at: \"2026-11-16T00:00:00Z\",
  child_pid: null, child_pgid: null, child_start: null, revoked_at: \$r}" > "$FW_LD/issue-7-j1-build-1.lease.json"
"$FW_W" wait --max-seconds 1
echo "rc=$?"
:'
for FW_MODE in live revoked badstart badpid; do
  fe_new "fw-lease-$FW_MODE"
  e2e_describe "a marker ancestor naming a planted F whose lease is $FW_MODE; wait from the main checkout"
  e2e_repo main
  fe_record
  FW_PF="$E2E_DIR/planted/F"
  mkdir -p "$FW_PF"
  fw_marker_script "$E2E_DIR/planted/py.sh" "$E2E_DIR/planted-ran"
  jq -n --arg i "$E2E_DIR/planted/py.sh" '{interpreter: $i}' > "$FW_PF/probes.json"
  _e2e_exec env FW_MODE="$FW_MODE" FW_LD="$FW_PF/jobs/issue-7/directives" FW_W="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" \
    bash -c "$FW_SCRIPT" _ /x/bin/_flow_factory_launch.py --factory-dir "$FW_PF" "$FW_ID"
  if [ "$FW_MODE" = live ]; then
    e2e_expect_line "FACTORY_REFUSED=interpreter_missing recorded=$E2E_DIR/planted/py.sh next: flow-factory.sh probe --environment"
  else
    e2e_expect_line "FACTORY_REFUSED=not_built"
  fi
  e2e_expect_line "rc=5"
  fw_expect_absent "$E2E_DIR/planted-ran" "the planted interpreter's marker"
done
fi
