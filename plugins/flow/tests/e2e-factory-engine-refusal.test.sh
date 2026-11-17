# shellcheck shell=bash
# The worker refusal (plan 1a, T9): bin/_flow_factory_caller.py identifies a
# caller as a worker by the three worker variables of design person_channels
# L19 (FLOW_FACTORY_JOB, FLOW_FACTORY_DIRECTIVE, FLOW_FACTORY_IO) or by a live
# lease's launcher or claude process among its ancestors, and the early check
# in bin/_flow_factory.py refuses such a caller with exit 4 and
# PERSON_ONLY_REFUSED=<reason> before any other check, in every wrapped form.
#
# Ways it can be wrong, written down before the checks:
#   RF1  a wrapped form, or a person subcommand (or run, next, probe), gets
#        through from a worker (AC7); or the walk is never exercised because
#        only the variables are read (R2)
#   RF2  the check comes after argument parsing, the job lookup or the
#        table's occurs_in, so a worker sees exit 2, 3 or 5 (RM1, R1)
#   RF3  a worker whose cwd is outside any repository gets exit 5: the
#        repository lookup runs before the ancestry walk (A+5)
#   RF4  a width-limited ps, a ps found on PATH, or a plugin path or factory
#        directory holding a space loses the launcher (R28, R29, A+6)
#   RF5  the nearest marker wins, so a process below the real launcher that
#        imitates one chooses the factory directory (R30)
#   RF6  an ancestry that cannot be read passes (fails open), or a traceback
#        exits 1; or a subcommand that is never refused still runs ps
#   RF7  any live lease refuses everyone, also a process that is not below
#        its launcher (A+10)
#   RF8  the early check's import fails when the cwd is bin/ (the sys.path
#        guard drops it) or under -I, or under the macOS Python 3.9 (A+4, R5)
#   RF9  a construct newer than Python 3.9 slips into _flow_factory.py or
#        _flow_factory_caller.py (A+1)
#   RF10 a reused pid counts as a live launcher: the start time is not
#        compared (A+8)
#   RF11 launch or report from below claude is accepted (L66, B.7); or the
#        worker variables refuse them (they apply to person subcommands only)
#   RF12 the shell (flow-factory.sh ff_marker_dir) and the Python
#        (marker_factory_dir) marker rules disagree on the same command line
#   RF13 the P13 FLOW_FACTORY_LAUNCH_CONTEXT is read as a worker variable
#   RF14 lstart keeps the trailing padding macOS ps prints, or ancestry reads
#        the start time or the parent wrongly, or a pid ps prints nothing for
#        is read as the end of the walk instead of a failure
#   RF15 the session test misses CLAUDECODE or a `claude` ancestor, or takes
#        a name that only starts with claude
#   RF16 the early check runs after _flow_factory.py's own imports, so a
#        module found first on the caller's PYTHONPATH (argparse.py, in the
#        `python3 _flow_factory.py` form, which reads PYTHONPATH) runs before a
#        worker is refused; or the block is placed after an import that needs
#        Python 3.11, so the 3.9 form dies before refusing (RF8 (c))
#
# Each scenario checks two layers where it can: the shipped command through the
# wrapper (the early check in _flow_factory.py), and the module's own answer
# (`check`, `find_factory_dir`, ...) through the isolation driver, run in the
# same process tree. Process trees come from fe_fake_launcher: its "claude"
# child is the worker script, so what the script runs has both the launcher
# and the claude pid among its ancestors. A worker script waits until the
# lease names its launcher before it runs anything, and records that it did.
#
# FR_ONLY=<id> (RF1 ... RF16) runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

fr_run() { [ -z "${FR_ONLY:-}" ] || [ "$FR_ONLY" = "$1" ]; }

FR_ID=issue-7-j1-build-1
FR_DISABLED="FACTORY_REFUSED=disabled next: set flow.factory.enabled"
FR_ANCESTOR="PERSON_ONLY_REFUSED=lease_ancestor"
FR_ENV="PERSON_ONLY_REFUSED=worker_env"
# The design's wrapped forms (design e2e_tests L8; p0 WRAPPED_FORMS) and the
# nine person subcommands, each with arguments that would pass their parsers.
FR_FORMS="plain env bashc shc timeout nohup py var"
FR_PERSON='answer q --choice 1
approve-spec 7 --spec-hash ab
confirm i
feedback 7 x
rework 7 x
retry 7
reject 7
cancel 7
rebuild 7'
FR_TIMEOUT=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null \
  || printf '%s' "$REPO_ROOT/plugins/flow/tests/fixtures/factory/bin/timeout")
FR_IMPORT="import _flow_factory_caller as c"
# fr_mpy <statements> — fe_py with the module imported as c.
fr_mpy() { fe_py "$FR_IMPORT
$1"; }

# fr_form <form> <variant> <wrapper> <subcommand words...> — the shell command
# that runs the wrapper in that form. Variant i removes FLOW_FACTORY_JOB only
# in the env form; variant ii removes all four FLOW_FACTORY_* names.
fr_form() {
  local key="$1" var="$2" w="$3" inner args pyff
  shift 3
  args=$(printf ' %q' "$@")
  inner="$(printf '%q' "$w")$args"
  pyff="$(dirname -- "$w")/_flow_factory.py"
  case "$key" in
    plain) printf '%s' "$inner" ;;
    env)
      if [ "$var" = i ]; then printf 'env -u FLOW_FACTORY_JOB %s' "$inner"
      else printf 'env -u FLOW_FACTORY_JOB -u FLOW_FACTORY_DIRECTIVE -u FLOW_FACTORY_IO -u FLOW_FACTORY_MAIN %s' "$inner"; fi ;;
    bashc) printf 'bash -c %q' "$inner" ;;
    shc) printf 'sh -c %q' "$inner" ;;
    timeout) printf '%q 30 %s' "$FR_TIMEOUT" "$inner" ;;
    nohup) printf 'nohup %s' "$inner" ;;
    py) printf 'python3 %q%s' "$pyff" "$args" ;;
    var) printf 'FF=%q; "$FF"%s' "$w" "$args" ;;
  esac
}

# fr_worker_script <file> <lease file> <body> — a worker script for
# fe_fake_launcher. It waits up to 10 s for the lease to name its parent (the
# launcher), records lease-live or lease-missing in $E2E_DIR/w/<name>.lease,
# then runs the body, and touches $E2E_DIR/w/<name>.done at its end. The body
# may call, each writing $E2E_DIR/w/<tag>.out, .err and .rc:
#   fr_sh <tag> <cwd> [NAME=value ...] -- <shell command>   (bash -c)
#   fr_w  <tag> <cwd> [NAME=value ...] -- <wrapper arguments>
#   fr_py <tag> <cwd> [NAME=value ...] -- <python statements>  (c is the module)
# each with every FLOW_FACTORY_* name removed and the settings added; and
#   fr_go <name>   wait up to 60 s for $E2E_DIR/w/go-<name>.
fr_worker_script() {
  local file="$1" lease="$2" body="$3"
  mkdir -p "$E2E_DIR/w"
  {
    printf 'W=%q\nR=%q\nLEASE=%q\nME=%q\nPY=%q\nBIN=%q\n' "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" "$E2E_DIR/w" \
      "$lease" "$(basename -- "$file")" "$(fe_python)" "$E2E_ACTIVE_PLUGIN/bin"
    cat <<'SH'
i=0
until [ "$(jq -r '.launcher_pid // empty' "$LEASE" 2>/dev/null)" = "$PPID" ]; do
  i=$((i + 1))
  [ "$i" -gt 100 ] && break
  sleep 0.1
done
if [ "$i" -gt 100 ]; then echo lease-missing > "$R/$ME.lease"; else echo lease-live > "$R/$ME.lease"; fi
fr_sh() {
  local tag="$1" cwd="$2" envs=()
  shift 2
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  ( cd "$cwd" || exit 96
    exec env -u FLOW_FACTORY_JOB -u FLOW_FACTORY_DIRECTIVE -u FLOW_FACTORY_IO -u FLOW_FACTORY_MAIN \
      ${envs[@]+"${envs[@]}"} bash -c "$1" ) < /dev/null > "$R/$tag.out" 2> "$R/$tag.err"
  echo "$?" > "$R/$tag.rc.t" && mv "$R/$tag.rc.t" "$R/$tag.rc"
}
fr_w() {
  local tag="$1" cwd="$2" envs=()
  shift 2
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  fr_sh "$tag" "$cwd" ${envs[@]+"${envs[@]}"} -- "$(printf '%q' "$W")$(printf ' %q' "$@")"
}
fr_py() {
  local tag="$1" cwd="$2" envs=() prog
  shift 2
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  prog="import sys; sys.path.insert(0, '$BIN')
import _flow_factory_caller as c
$1"
  fr_sh "$tag" "$cwd" ${envs[@]+"${envs[@]}"} -- "$(printf '%q -E -c %q' "$PY" "$prog")"
}
fr_go() {
  local n=0
  until [ -e "$R/go-$1" ]; do n=$((n + 1)); [ "$n" -gt 600 ] && return 1; sleep 0.1; done
}
SH
    printf '%s\n' "$body"
    printf 'touch "$R/$ME.done"\n'
  } > "$file"
}

# fr_result <tag> [seconds] — wait (default 60 s) for $E2E_DIR/w/<tag>.rc, set
# E2E_OUT, E2E_ERR and E2E_RC from it and write them to the artifact.
fr_result() {
  fe_wait_for "${2:-60}" "[ -f '$E2E_DIR/w/$1.rc' ]" || { E2E_OUT=""; E2E_ERR=""; E2E_RC=none; return 1; }
  E2E_RC=$(cat "$E2E_DIR/w/$1.rc")
  E2E_OUT=$(cat "$E2E_DIR/w/$1.out" 2>/dev/null)
  E2E_ERR=$(cat "$E2E_DIR/w/$1.err" 2>/dev/null)
  _fe_record_outcome "below the launcher ($1)"
}

# fr_expect_refused <reason> <what> — exit 4 and stdout exactly the line.
fr_expect_refused() {
  e2e_expect_equal 4 "$E2E_RC" "$2: exit status"
  e2e_expect_equal "PERSON_ONLY_REFUSED=$1" "$E2E_OUT" "$2: stdout"
}

# fr_expect_lease_live <script name> — the worker script saw its lease live.
fr_expect_lease_live() {
  e2e_expect_equal lease-live "$(cat "$E2E_DIR/w/$1.lease" 2>/dev/null)" "the lease $1 waited for"
}

# fr_clone — a clone of the scratch repository with no record, at
# $E2E_DIR/other. Prints its path.
fr_clone() {
  _fe_in_scratch git clone -q "$E2E_REPO" "$E2E_DIR/other" >/dev/null 2>&1 \
    || _e2e_result fail "cloned the scratch repository to $E2E_DIR/other"
  printf '%s' "$E2E_DIR/other"
}

# fr_tree_sum <dir> — a checksum of every file under dir and its content,
# leaving out the lease files, whose heartbeat the launcher rewrites.
fr_tree_sum() {
  (cd "$1" && find . -type f ! -name '*.lease.json' ! -name '*.tmp-*' | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(_e2e_sha256 "$f")"; done) | cksum
}

# fr_rewrite_lease <lease> <jq filter> — apply the filter to the lease until it
# holds across two heartbeats: the launcher rewrites the file every second
# from what it read, so one write can be lost to a renewal in flight.
fr_rewrite_lease() {
  local lease="$1" filter="$2" i want
  for i in 1 2 3 4 5 6 7 8 9 10; do
    jq "$filter" "$lease" > "$lease.fr" && mv "$lease.fr" "$lease"
    want=$(jq -c "$filter | del(.heartbeat_at)" "$lease")
    sleep 2.2
    [ "$(jq -c 'del(.heartbeat_at)' "$lease")" = "$want" ] && return 0
  done
  _e2e_result fail "the lease edit '$filter' held across two heartbeats"
  return 1
}

if fr_run RF1; then
_flow_test_begin "factory refusal: every person subcommand in every wrapped form from a worker exits 4 (RF1)"
fe_new fr-forms
e2e_describe "9 person subcommands x 8 wrapped forms x 2 variants: (i) the worker variables set, no lease, cwd the main checkout with a record; (ii) every FLOW_FACTORY_* cleared, below a live fake launcher, cwd a clone with no record. Every run exits 4 with exactly PERSON_ONLY_REFUSED=worker_env (i) or lease_ancestor (ii). Also run, next and probe, and the module's own answer for every subcommand class."
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
FR_W="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
FR_OTHER=$(fr_clone)
FR_GUARDED="$FR_PERSON
next --executor headless
run --once
probe --verify-record $FR_F/probes.json"
# (ii) first: the forms file the worker script runs, one `tag<TAB>command`
# line each.
: > "$E2E_DIR/forms-ii"
while IFS= read -r FR_LINE; do
  read -r -a FR_WORDS <<<"$FR_LINE"
  for FR_FORM in $FR_FORMS; do
    printf '%s__%s\t%s\n' "${FR_WORDS[0]}" "$FR_FORM" "$(fr_form "$FR_FORM" ii "$FR_W" "${FR_WORDS[@]}")" >> "$E2E_DIR/forms-ii"
  done
done <<<"$FR_PERSON"
printf 'next__plain\t%s\nrun__plain\t%s\nprobe__plain\t%s\n' "$(fr_form plain ii "$FR_W" next --executor headless)" \
  "$(fr_form plain ii "$FR_W" run --once)" "$(fr_form plain ii "$FR_W" probe --verify-record "$FR_F/probes.json")" >> "$E2E_DIR/forms-ii"
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" "
while IFS=\$'\\t' read -r tag cmd; do fr_sh \"\$tag\" $(printf %q "$FR_OTHER") -- \"\$cmd\"; done < $(printf %q "$E2E_DIR/forms-ii")
fr_py module $(printf %q "$FR_OTHER") -- 'for s in c.PERSON + (\"run\", \"next\", \"probe\", \"launch\", \"report\", \"context\", \"status\", \"wait\", \"question\", \"runner\", \"await\"):
    print(s, c.check(s))'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
# (i) meanwhile, from the test shell: the variables set, no lease is an
# ancestor of these runs.
FR_LIST=""
while IFS= read -r FR_LINE; do
  read -r -a FR_WORDS <<<"$FR_LINE"
  for FR_FORM in $FR_FORMS; do
    _e2e_exec env FLOW_FACTORY_JOB=issue-7-j1 FLOW_FACTORY_DIRECTIVE="$FR_ID" FLOW_FACTORY_IO="$E2E_DIR/io" \
      bash -c "$(fr_form "$FR_FORM" i "$FR_W" "${FR_WORDS[@]}")"
    FR_LIST="$FR_LIST${FR_WORDS[0]} $FR_FORM i: exit $E2E_RC $E2E_OUT"$'\n'
    fr_expect_refused worker_env "${FR_WORDS[0]} $FR_FORM (i)"
  done
done <<<"$FR_PERSON"
for FR_LINE in "next --executor headless" "run --once" "probe --verify-record $FR_F/probes.json"; do
  read -r -a FR_WORDS <<<"$FR_LINE"
  _e2e_exec env FLOW_FACTORY_IO="$E2E_DIR/io" bash -c "$(fr_form plain i "$FR_W" "${FR_WORDS[@]}")"
  FR_LIST="$FR_LIST${FR_WORDS[0]} plain i: exit $E2E_RC $E2E_OUT"$'\n'
  fr_expect_refused worker_env "${FR_WORDS[0]} plain (i), FLOW_FACTORY_IO alone"
done
fe_wait_for 300 "[ -f '$E2E_DIR/w/worker.sh.done' ]"
fr_expect_lease_live worker.sh
while IFS=$'\t' read -r FR_TAG FR_CMD; do
  fr_result "$FR_TAG" 5
  FR_LIST="$FR_LIST${FR_TAG%%__*} ${FR_TAG##*__} ii: exit $E2E_RC $E2E_OUT"$'\n'
  fr_expect_refused lease_ancestor "${FR_TAG%%__*} ${FR_TAG##*__} (ii)"
done < "$E2E_DIR/forms-ii"
printf -- '--- every run\n%s' "$FR_LIST" | _e2e_art
# The module, from the same tree and from the test shell with the variables.
fr_result module 5
FR_WANT=""
for FR_S in answer approve-spec confirm feedback rework retry reject cancel rebuild run next probe launch report; do
  FR_WANT="$FR_WANT$FR_S lease_ancestor"$'\n'
done
for FR_S in context status wait question runner await; do FR_WANT="$FR_WANT$FR_S None"$'\n'; done
e2e_expect_equal "${FR_WANT%$'\n'}" "$E2E_OUT" "(module, ii) check() of every subcommand below the launcher"
fr_mpy "for v in c.WORKER_VARS:
    for s in c.PERSON + ('run', 'next', 'probe', 'launch', 'report', 'context', 'status', 'wait', 'await'):
        print(v, s, c.check(s, {v: 'x'}))
print('empty', c.check('cancel', {'FLOW_FACTORY_JOB': ''}))
print('main', c.check('cancel', {'FLOW_FACTORY_MAIN': 'x'}))"
FR_WANT=""
for FR_V in FLOW_FACTORY_JOB FLOW_FACTORY_DIRECTIVE FLOW_FACTORY_IO; do
  for FR_S in answer approve-spec confirm feedback rework retry reject cancel rebuild run next probe; do
    FR_WANT="$FR_WANT$FR_V $FR_S worker_env"$'\n'
  done
  for FR_S in launch report context status wait await; do FR_WANT="$FR_WANT$FR_V $FR_S None"$'\n'; done
done
FR_WANT="${FR_WANT}empty None"$'\n'"main None"
e2e_expect_equal 0 "$E2E_RC" "(module, i) exit status"
e2e_expect_equal "$FR_WANT" "$E2E_OUT" "(module, i) check() with each worker variable, an empty one, and FLOW_FACTORY_MAIN"
fi

if fr_run RF2; then
_flow_test_begin "factory refusal: the worker check comes before argument parsing and the job's state (RF2)"
fe_new fr-order
e2e_describe "below a live launcher, every FLOW_FACTORY_* cleared, cwd a clone: reject 7 --bogus extra, with job 7 in ready (where person_reject does not occur), exits 4 lease_ancestor, and nothing under the factory directory changes"
e2e_repo main
fe_record
fe_job 7 ready
FR_F=$(fe_factory_dir)
FR_OTHER=$(fr_clone)
FR_BEFORE=$(fr_tree_sum "$FR_F")
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" \
  "fr_w reject $(printf %q "$FR_OTHER") -- reject 7 --bogus extra"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fr_result reject
fr_expect_lease_live worker.sh
fr_expect_refused lease_ancestor "reject 7 --bogus extra"
fe_mask_text "$FR_BEFORE" '<checksum> <size>'
e2e_expect_equal "$FR_BEFORE" "$(fr_tree_sum "$FR_F")" "the checksum of the factory directory's files (leases left out)"
fi

if fr_run RF3; then
_flow_test_begin "factory refusal: a worker outside any repository exits 4, not 5 (RF3)"
fe_new fr-no-repo
e2e_describe "below a live launcher, every FLOW_FACTORY_* cleared, cwd /tmp: cancel 7 exits 4 lease_ancestor; the module's check gives lease_ancestor there too"
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" \
  "fr_w cancel /tmp -- cancel 7
fr_py module /tmp -- 'print(c.check(\"cancel\"))'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fr_result cancel
fr_expect_lease_live worker.sh
fr_expect_refused lease_ancestor "cancel 7 from /tmp"
fr_result module
e2e_expect_equal lease_ancestor "$E2E_OUT" "(module) check('cancel') from /tmp"
fi

if fr_run RF4; then
_flow_test_begin "factory refusal: a narrow terminal, a ps on PATH and spaces in paths do not lose the launcher (RF4)"
fe_new fr-ps-width
e2e_describe "a plugin copy at a path over 200 characters; below its launcher, from a clone, cancel 7 with (a) COLUMNS=20 and (b) a ps that prints nothing first on PATH: both exit 4 lease_ancestor, and so does the module's check"
e2e_repo main
FR_LONG="$E2E_DIR/$(printf 'p%.0s' $(seq 1 70))/$(printf 'q%.0s' $(seq 1 70))/$(printf 'r%.0s' $(seq 1 70))/plugin"
mkdir -p "$(dirname -- "$FR_LONG")"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$FR_LONG" || _e2e_result fail "copied the plugin to a long path"
E2E_ACTIVE_PLUGIN="$FR_LONG"
printf 'plugin for this scenario: a copy at a path of %s characters\n' "${#FR_LONG}" | _e2e_art
fe_record
FR_F=$(fe_factory_dir)
FR_OTHER=$(fr_clone)
mkdir -p "$E2E_DIR/fake-ps"
printf '#!/bin/bash\nexit 0\n' > "$E2E_DIR/fake-ps/ps"
chmod +x "$E2E_DIR/fake-ps/ps"
FR_PSPATH="PATH=$(printf %q "$E2E_DIR/fake-ps"):\"\$PATH\""
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" \
  "fr_w narrow $(printf %q "$FR_OTHER") COLUMNS=20 -- cancel 7
fr_w pathps $(printf %q "$FR_OTHER") $FR_PSPATH -- cancel 7
fr_py mnarrow $(printf %q "$FR_OTHER") COLUMNS=20 -- 'print(c.check(\"cancel\"))'
fr_py mpathps $(printf %q "$FR_OTHER") $FR_PSPATH -- 'print(c.check(\"cancel\"))'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fe_wait_for 60 "[ -f '$E2E_DIR/w/worker.sh.done' ]"
fr_expect_lease_live worker.sh
fr_result narrow
fr_expect_refused lease_ancestor "(a) COLUMNS=20"
fr_result pathps
fr_expect_refused lease_ancestor "(b) a ps on PATH that prints nothing"
fr_result mnarrow
e2e_expect_equal lease_ancestor "$E2E_OUT" "(module, a) check('cancel') with COLUMNS=20"
fr_result mpathps
e2e_expect_equal lease_ancestor "$E2E_OUT" "(module, b) check('cancel') with a ps on PATH"

fe_new fr-spaces
e2e_describe "(c) the plugin copy at '<dir>/plug in' and the main checkout at '<dir>/re po' (so the factory directory holds a space); below the launcher, from a clone, cancel 7 exits 4 lease_ancestor, and find_factory_dir names that directory"
FR_PLUG="$E2E_DIR/plug in"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$FR_PLUG" || _e2e_result fail "copied the plugin to a path with a space"
E2E_ACTIVE_PLUGIN="$FR_PLUG"
E2E_REPO="$E2E_DIR/re po"
mkdir -p "$E2E_REPO"
_fe_in_scratch sh -c 'git init -q && git config user.email e2e@example.invalid && git config user.name e2e \
  && git config commit.gpgsign false && printf "e2e\n" > README.md && git add README.md \
  && git commit -q -m init && git checkout -q -b main' || _e2e_result fail "made the scratch repository 're po'"
fe_record
FR_F=$(fe_factory_dir)
case "$FR_F" in *' '*) e2e_expect_equal ok ok "(c) the factory directory holds a space" ;;
  *) e2e_expect_equal "a path with a space" "$FR_F" "(c) the factory directory" ;; esac
FR_OTHER=$(fr_clone)
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" \
  "fr_w spaces $(printf %q "$FR_OTHER") -- cancel 7
fr_py module $(printf %q "$FR_OTHER") -- 'print(c.check(\"cancel\")); print(c.find_factory_dir())'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fr_result spaces
fr_expect_lease_live worker.sh
fr_expect_refused lease_ancestor "(c) spaces in the plugin and factory paths"
fr_result module
e2e_expect_equal "lease_ancestor
('$FR_F', 'launcher')" "$E2E_OUT" "(module, c) check('cancel') and find_factory_dir()"
fi

if fr_run RF5; then
_flow_test_begin "factory refusal: the outermost live launcher counts, not a nearer imitation (RF5)"
fe_new fr-outermost
e2e_describe "the launcher's worker starts a second launcher naming a planted factory directory (its own live lease, a record naming a marker script); the inner worker runs cancel 7 from a clone: exit 4 lease_ancestor, the planted script never runs, and find_factory_dir names the outer directory"
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
FR_OTHER=$(fr_clone)
FR_PF="$E2E_DIR/planted/F"
mkdir -p "$FR_PF" "$E2E_DIR/planted"
printf '#!/bin/bash\ntouch %q\nexit 0\n' "$E2E_DIR/planted-ran" > "$E2E_DIR/planted/py.sh"
chmod +x "$E2E_DIR/planted/py.sh"
jq -n --arg i "$E2E_DIR/planted/py.sh" '{interpreter: $i}' > "$FR_PF/probes.json"
fr_worker_script "$E2E_DIR/inner.sh" "$FR_PF/jobs/issue-7/directives/$FR_ID.lease.json" \
  "fr_w inner $(printf %q "$FR_OTHER") -- cancel 7
fr_py module $(printf %q "$FR_OTHER") -- 'print(c.check(\"cancel\")); print(c.find_factory_dir())'"
fr_worker_script "$E2E_DIR/outer.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" \
  "FE_WORKER_SCRIPT=$(printf %q "$E2E_DIR/inner.sh") $(printf %q "$(fe_python)") $(printf %q "$FE_FIXTURES/worker/fake_launcher.py") $(printf %q "$(cd "$E2E_ACTIVE_PLUGIN" && pwd -P)/bin/_flow_factory_launch.py") --factory-dir $(printf %q "$FR_PF") $FR_ID"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/outer.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fr_result inner
fr_expect_lease_live outer.sh
fr_expect_lease_live inner.sh
fr_expect_refused lease_ancestor "cancel 7 below two launchers"
if [ -e "$E2E_DIR/planted-ran" ]; then e2e_expect_equal absent present "the planted interpreter's marker"
else e2e_expect_equal absent absent "the planted interpreter's marker"; fi
fr_result module
e2e_expect_equal "lease_ancestor
('$FR_F', 'launcher')" "$E2E_OUT" "(module) check('cancel') and find_factory_dir() below two launchers"
fi

if fr_run RF6; then
_flow_test_begin "factory refusal: an ancestry that cannot be read is refused (RF6)"
fe_new fr-ps-unreadable
e2e_describe "a plugin copy whose _flow_factory_caller.py names /nonexistent/ps: cancel 7 from the test shell exits 4 ancestry_unreadable; the module's check refuses cancel, launch and next that way and answers context and status (which read no ancestry) with None"
e2e_repo main
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_DIR/plugin" || _e2e_result fail "copied the plugin"
E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
sed -i.bak 's|^PS = "/bin/ps"$|PS = "/nonexistent/ps"|' "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_caller.py"
rm -f "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_caller.py.bak"
e2e_expect_equal 1 "$(grep -c '^PS = "/nonexistent/ps"$' "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_caller.py")" "the copy names /nonexistent/ps"
printf 'plugin for this scenario: a copy with PS = "/nonexistent/ps" in bin/_flow_factory_caller.py\n' | _e2e_art
fe_record
e2e_run_bin bin/flow-factory.sh cancel 7 < /dev/null
fr_expect_refused ancestry_unreadable "cancel 7"
fr_mpy "for s in ('cancel', 'launch', 'next', 'context', 'status'):
    print(s, c.check(s))"
e2e_expect_equal 0 "$E2E_RC" "(module) exit status"
e2e_expect_equal "cancel ancestry_unreadable
launch ancestry_unreadable
next ancestry_unreadable
context None
status None" "$E2E_OUT" "(module) check() with an unreadable ancestry"
fr_mpy "try:
    c.ancestry()
    print('read')
except c.AncestryUnreadable:
    print('AncestryUnreadable')
c.early_exit(['cancel', '7'])
print('returned')"
e2e_expect_equal 4 "$E2E_RC" "(module) early_exit(['cancel', '7']): exit status"
e2e_expect_equal "AncestryUnreadable
PERSON_ONLY_REFUSED=ancestry_unreadable" "$E2E_OUT" "(module) ancestry() raises, then early_exit's stdout"
fi

if fr_run RF7; then
_flow_test_begin "factory refusal: a process that is not below a launcher is not refused while a lease is live (RF7)"
fe_new fr-non-descendant
e2e_describe "a fake launcher and its lease are live; the test shell, not its descendant, with no worker variable, runs next: the engine's disabled line, not PERSON_ONLY_REFUSED; the module's check gives None for next and cancel"
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" "fr_go end"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fe_wait_for 10 "[ -f '$E2E_DIR/w/worker.sh.lease' ]"
fr_expect_lease_live worker.sh
e2e_run_bin bin/flow-factory.sh next --executor headless < /dev/null
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_equal "$FR_DISABLED" "$E2E_OUT" "stdout"
fr_mpy "print(len(c.live_leases('$FR_F')))
print(c.check('next'))
print(c.check('cancel'))"
e2e_expect_equal "1
None
None" "$E2E_OUT" "(module) one live lease; check('next') and check('cancel') from the test shell"
touch "$E2E_DIR/w/go-end"
fi

if fr_run RF8; then
_flow_test_begin "factory refusal: the early check loads with cwd bin/, under -I, and under Python 3.9 (RF8)"
fe_new fr-import-path
e2e_describe "a plugin copy under the scenario folder: FLOW_FACTORY_JOB=x and cancel 7 through (a) cd bin && python3 _flow_factory.py, (b) python3 -I <plugin>/bin/_flow_factory.py, (c) /usr/bin/python3 when it is older than 3.11; each exits 4 worker_env. The module alone also loads and refuses under that Python."
e2e_repo main
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_DIR/plugin" || _e2e_result fail "copied the plugin"
E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
fe_record
_e2e_exec bash -c 'cd "$1/bin" && FLOW_FACTORY_JOB=x python3 _flow_factory.py cancel 7' _ "$E2E_ACTIVE_PLUGIN"
fr_expect_refused worker_env "(a) cd bin && python3 _flow_factory.py cancel 7"
_e2e_exec env FLOW_FACTORY_JOB=x python3 -I "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" cancel 7
fr_expect_refused worker_env "(b) python3 -I _flow_factory.py cancel 7"
FR_OLD=""
if [ -x /usr/bin/python3 ] && /usr/bin/python3 -I -c 'import sys; sys.exit(0 if sys.version_info < (3, 11) else 1)' 2>/dev/null; then
  FR_OLD=$(/usr/bin/python3 -I -c 'import platform; print(platform.python_version())')
fi
if [ -n "$FR_OLD" ]; then
  _e2e_exec env FLOW_FACTORY_JOB=x /usr/bin/python3 "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" cancel 7
  printf '(c) /usr/bin/python3 %s: exit %s %s\n' "$FR_OLD" "$E2E_RC" "$E2E_OUT" | _e2e_art
  fr_expect_refused worker_env "(c) /usr/bin/python3 $FR_OLD _flow_factory.py cancel 7"
  _e2e_exec bash -c 'cd "$1/bin" && FLOW_FACTORY_JOB=x /usr/bin/python3 -I -c "import sys; sys.path.append(\"$1/bin\"); import _flow_factory_caller as c; print(c.check(\"cancel\", {})); c.early_exit([\"cancel\", \"7\"]); print(\"returned\")"' _ "$E2E_ACTIVE_PLUGIN"
  e2e_expect_equal 4 "$E2E_RC" "(module, c) /usr/bin/python3 $FR_OLD early_exit: exit status"
  e2e_expect_equal "None
$FR_ENV" "$E2E_OUT" "(module, c) /usr/bin/python3 $FR_OLD: check('cancel', {}) walks and passes, then early_exit refuses"
else
  printf '(c) skipped: no python older than 3.11\n' | _e2e_art
fi
fi

if fr_run RF9; then
_flow_test_begin "factory refusal: _flow_factory.py and _flow_factory_caller.py hold nothing newer than Python 3.9 (RF9)"
fe_new fr-py39
e2e_describe "(a) ast.parse(feature_version=(3, 9)) and the f-string tokenize rule pass over both files; (b) a match statement, (c) an f-string reusing its quote, (d) except* appended to scratch copies each fail, (c) by the tokenize rule; (e) both compile under /usr/bin/python3 when it is older than 3.12"
e2e_repo main
cat > "$E2E_DIR/check39.py" <<'PY'
"""Whether each file loads under Python 3.9 (plan 2.17): ast.parse with
feature_version (3, 9), then a tokenize rule for what that parse accepts but
3.9 rejects: inside an f-string's replacement field, a string or f-string
holding the enclosing quote, a backslash, or a comment."""
import ast
import io
import sys
import tokenize

FS = getattr(tokenize, "FSTRING_START", None)
FM = getattr(tokenize, "FSTRING_MIDDLE", None)
FE = getattr(tokenize, "FSTRING_END", None)


def quote(text):
    return text.lstrip("rRfFbBuUtT")


def check(path):
    src = open(path, encoding="utf-8").read()
    try:
        ast.parse(src, filename=path, feature_version=(3, 9))
    except SyntaxError as e:
        return "ast: line %s: %s" % (e.lineno, e.msg)
    if FS is None:
        return "ok"
    stack = []
    for tok in tokenize.generate_tokens(io.StringIO(src).readline):
        if tok.type == FS:
            if stack and stack[-1] in tok.string:
                return "tokenize: line %d: an f-string reuses its enclosing quote" % tok.start[0]
            stack.append(quote(tok.string))
            continue
        if tok.type == FE:
            stack.pop()
            continue
        if not stack or tok.type == FM:
            continue
        if tok.type == tokenize.STRING and stack[-1] in tok.string:
            return "tokenize: line %d: a string reuses its f-string's quote" % tok.start[0]
        if tok.type == tokenize.COMMENT:
            return "tokenize: line %d: a comment inside an f-string" % tok.start[0]
        if "\\" in tok.string:
            return "tokenize: line %d: a backslash inside an f-string" % tok.start[0]
    return "ok"


for p in sys.argv[1:]:
    print("%s: %s" % (p.rsplit("/", 1)[-1], check(p)))
PY
FR_BIN="$E2E_ACTIVE_PLUGIN/bin"
_fe_run_py -I "$E2E_DIR/check39.py" "$FR_BIN/_flow_factory.py" "$FR_BIN/_flow_factory_caller.py"
e2e_expect_equal 0 "$E2E_RC" "(a) exit status"
e2e_expect_equal "_flow_factory.py: ok
_flow_factory_caller.py: ok" "$E2E_OUT" "(a) both files"
mkdir -p "$E2E_DIR/m"
for FR_M in b c d; do
  cp "$FR_BIN/_flow_factory_caller.py" "$E2E_DIR/m/$FR_M.py"
  case "$FR_M" in
    b) printf '\nmatch x:\n    case 1:\n        pass\n' >> "$E2E_DIR/m/$FR_M.py" ;;
    c) printf '\nx = f"{"a"}"\n' >> "$E2E_DIR/m/$FR_M.py" ;;
    d) printf '\ntry:\n    pass\nexcept* E:\n    pass\n' >> "$E2E_DIR/m/$FR_M.py" ;;
  esac
done
_fe_run_py -I "$E2E_DIR/check39.py" "$E2E_DIR/m/b.py" "$E2E_DIR/m/c.py" "$E2E_DIR/m/d.py"
FR_B=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^b\.py: //p')
FR_C=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^c\.py: //p')
FR_D=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^d\.py: //p')
case "$FR_B" in ast:*) e2e_expect_equal ok ok "(b) match fails the ast check: $FR_B" ;; *) e2e_expect_equal "ast: ..." "$FR_B" "(b) match" ;; esac
case "$FR_C" in tokenize:*) e2e_expect_equal ok ok "(c) a reused quote fails the tokenize rule: $FR_C" ;; *) e2e_expect_equal "tokenize: ..." "$FR_C" "(c) f\"{\"a\"}\"" ;; esac
case "$FR_D" in ast:*) e2e_expect_equal ok ok "(d) except* fails the ast check: $FR_D" ;; *) e2e_expect_equal "ast: ..." "$FR_D" "(d) except*" ;; esac
if [ -x /usr/bin/python3 ] && /usr/bin/python3 -I -c 'import sys; sys.exit(0 if sys.version_info < (3, 12) else 1)' 2>/dev/null; then
  FR_OLD=$(/usr/bin/python3 -I -c 'import platform; print(platform.python_version())')
  _e2e_exec /usr/bin/python3 -I -c 'import sys
for p in sys.argv[1:]:
    compile(open(p, encoding="utf-8").read(), p, "exec")
    print(p.rsplit("/", 1)[-1], "compiles")' "$FR_BIN/_flow_factory.py" "$FR_BIN/_flow_factory_caller.py"
  e2e_expect_equal 0 "$E2E_RC" "(e) /usr/bin/python3 $FR_OLD compile: exit status"
  e2e_expect_equal "_flow_factory.py compiles
_flow_factory_caller.py compiles" "$E2E_OUT" "(e) /usr/bin/python3 $FR_OLD compile"
else
  printf '(e) skipped: no /usr/bin/python3 older than 3.12\n' | _e2e_art
fi
fi

if fr_run RF10; then
_flow_test_begin "factory refusal: a lease whose launcher start time no longer matches is not live (RF10)"
fe_new fr-pid-reuse
e2e_describe "below a fake launcher, cwd the main checkout (which has a record): next is refused with lease_ancestor while the lease names the launcher's true start; after the test rewrites launcher_start to 'Thu Jan  1 00:00:00 1970' (as if the pid were reused), next reaches the engine's disabled line; the module's check follows"
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
FR_LEASE="$FR_F/jobs/issue-7/directives/$FR_ID.lease.json"
fr_worker_script "$E2E_DIR/worker.sh" "$FR_LEASE" \
  "fr_w a $(printf %q "$E2E_REPO") -- next --executor headless
fr_py ma $(printf %q "$E2E_REPO") -- 'print(c.check(\"next\")); print(len(c.live_leases(\"$FR_F\")))'
touch \"\$R/ready-b\"
fr_go b
fr_w b $(printf %q "$E2E_REPO") -- next --executor headless
fr_py mb $(printf %q "$E2E_REPO") -- 'print(c.check(\"next\")); print(len(c.live_leases(\"$FR_F\")))'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fe_wait_for 60 "[ -f '$E2E_DIR/w/ready-b' ]"
fr_rewrite_lease "$FR_LEASE" '.launcher_start = "Thu Jan  1 00:00:00 1970"'
touch "$E2E_DIR/w/go-b"
fr_expect_lease_live worker.sh
fr_result a
fr_expect_refused lease_ancestor "next with the launcher's true start"
fr_result ma
e2e_expect_equal "lease_ancestor
1" "$E2E_OUT" "(module) check('next') and the live lease count with the true start"
fr_result b
e2e_expect_equal 5 "$E2E_RC" "next after the rewrite: exit status"
e2e_expect_equal "$FR_DISABLED" "$E2E_OUT" "next after the rewrite: stdout"
fr_result mb
e2e_expect_equal "None
0" "$E2E_OUT" "(module) check('next') and the live lease count after the rewrite"
fi

if fr_run RF11; then
_flow_test_begin "factory refusal: launch and report from below claude are refused; the variables alone do not refuse them (RF11)"
fe_new fr-internal
e2e_describe "below a live launcher, every FLOW_FACTORY_* cleared, cwd a clone: launch and report of the directive exit 4 lease_ancestor; the module's check agrees, and gives None for launch and report with the variables set and no lease"
e2e_repo main
fe_record
fe_directive "$FR_ID"
FR_F=$(fe_factory_dir)
FR_OTHER=$(fr_clone)
fr_worker_script "$E2E_DIR/worker.sh" "$FR_F/jobs/issue-7/directives/$FR_ID.lease.json" \
  "fr_w launch $(printf %q "$FR_OTHER") -- launch $FR_ID
fr_w report $(printf %q "$FR_OTHER") -- report $FR_ID
fr_py module $(printf %q "$FR_OTHER") -- 'print(c.check(\"launch\")); print(c.check(\"report\"))'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fr_result report
fr_expect_lease_live worker.sh
fr_expect_refused lease_ancestor "report $FR_ID"
fr_result launch
fr_expect_refused lease_ancestor "launch $FR_ID"
fr_result module
e2e_expect_equal "lease_ancestor
lease_ancestor" "$E2E_OUT" "(module) check('launch') and check('report') below the launcher"
fr_mpy "e = {'FLOW_FACTORY_JOB': 'x', 'FLOW_FACTORY_DIRECTIVE': 'y', 'FLOW_FACTORY_IO': 'z'}
print(c.check('launch', e)); print(c.check('report', e))"
e2e_expect_equal "None
None" "$E2E_OUT" "(module) check('launch') and check('report') with the variables set, from the test shell"
fi

if fr_run RF12; then
_flow_test_begin "factory refusal: the shell and Python marker rules agree (RF12)"
fe_new fr-marker-rule
e2e_describe "13 command lines through flow-factory.sh's ff_marker_dir (extracted with sed) and _flow_factory_caller.marker_factory_dir: both print the value written by hand from plan 2.8's rule. Line 13 holds the whole anchor twice, so only it tells the first occurrence from the last (line 10 holds the anchor once)"
e2e_repo main
FR_M="/py -E /p/bin/_flow_factory_launch.py --factory-dir"
FR_STRINGS=(
  "$FR_M /f/F issue-7-j1-build-1"
  "/py -E /p q/bin/_flow_factory_launch.py --factory-dir /f/F issue-7-j1-build-1"
  "$FR_M /f g/F issue-7-j1-build-1"
  "$FR_M /f/F issue-7-j1-build-1 extra"
  "$FR_M /f/F issue-7-j1-open_pr-2"
  "$FR_M /f/F issue-7-j1-build-0"
  "$FR_M /f/F issue-07-j1-build-1"
  "/py -E /p/bin/_flow_factory_launch.py issue-7-j1-build-1"
  "/py /x/bin/other.py --factory-dir /f/F issue-7-j1-build-1"
  "$FR_M /f/a --factory-dir /f/F issue-7-j1-build-1"
  "$FR_M /f/F issue-7-j1-bogus-1"
  ""
  "$FR_M /f/a/bin/_flow_factory_launch.py --factory-dir /f/F issue-7-j1-build-1"
)
FR_WANT='[/f/F]
[/f/F]
[/f g/F]
[]
[/f/F]
[]
[]
[]
[]
[/f/a --factory-dir /f/F]
[]
[]
[/f/a/bin/_flow_factory_launch.py --factory-dir /f/F]'
printf '%s\0' "${FR_STRINGS[@]}" > "$E2E_DIR/strings"
FR_FN=$(sed -n '/^ff_marker_dir()/,/^}/p' "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh")
printf -- '--- ff_marker_dir as extracted\n%s\n' "$FR_FN" | _e2e_art
_e2e_exec bash -c "$FR_FN"'
while IFS= read -r -d "" s; do printf "[%s]\n" "$(ff_marker_dir "$s")"; done < "$1"' _ "$E2E_DIR/strings"
e2e_expect_equal 0 "$E2E_RC" "(shell) exit status"
e2e_expect_equal "$FR_WANT" "$E2E_OUT" "(shell) ff_marker_dir of the 13 lines"
fr_mpy "for s in open('$E2E_DIR/strings', encoding='utf-8').read().split(chr(0))[:-1]:
    d = c.marker_factory_dir(s)
    print('[%s]' % ('' if d is None else d))"
e2e_expect_equal 0 "$E2E_RC" "(python) exit status"
e2e_expect_equal "$FR_WANT" "$E2E_OUT" "(python) marker_factory_dir of the 13 lines"
fr_mpy "print(c.marker_factory_dir('$FR_M /f/F issue-7-j1-build-1' + chr(10)))"
e2e_expect_equal None "$E2E_OUT" "(python) a trailing newline after the id is not a marker, as in bash's =~"
fi

if fr_run RF13; then
_flow_test_begin "factory refusal: the P13 launch context variable is not a worker variable (RF13)"
fe_new fr-launch-context
e2e_describe "FLOW_FACTORY_LAUNCH_CONTEXT=cron flow-factory.sh probe --verify-record <record>: no PERSON_ONLY_REFUSED line and exit status not 4; the module's check of probe with that variable gives None"
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
e2e_run_bin FLOW_FACTORY_LAUNCH_CONTEXT=cron bin/flow-factory.sh probe --verify-record "$FR_F/probes.json" < /dev/null
e2e_expect_no_out "PERSON_ONLY_REFUSED"
if [ "$E2E_RC" = 4 ]; then e2e_expect_equal "not 4" 4 "exit status"; else e2e_expect_equal ok ok "exit status $E2E_RC is not 4"; fi
fr_mpy "print(c.check('probe', {'FLOW_FACTORY_LAUNCH_CONTEXT': 'cron'}))"
e2e_expect_equal None "$E2E_OUT" "(module) check('probe') with FLOW_FACTORY_LAUNCH_CONTEXT set"
fi

if fr_run RF14; then
_flow_test_begin "factory refusal: lstart and ancestry read start times in the 2.4 form (RF14)"
fe_new fr-lstart
e2e_describe "lstart of a running pid equals the shell's trimmed form, has no outer white space and is 24 characters; lstart of a pid that has ended is None; ancestry from below a launcher holds the launcher and claude pids with the start times the lease records, each parent chained to the next; ancestry of a pid that has ended raises AncestryUnreadable"
e2e_repo main
fe_record
FR_F=$(fe_factory_dir)
sleep 60 & FR_SLEEP=$!
_fe_register "$FR_SLEEP"
FR_START=$(_fe_lstart "$FR_SLEEP")
sh -c 'exit 0' & FR_GONE=$!
wait "$FR_GONE"
fe_mask_pid "$FR_SLEEP" sleeper
fe_mask_pid "$FR_GONE" ended
fe_mask_found "$FR_START"
fr_mpy "s = c.lstart($FR_SLEEP)
print(repr(s)); print(len(s)); print(s == s.strip())
print(c.lstart($FR_GONE))
try:
    c.ancestry($FR_GONE)
    print('read')
except c.AncestryUnreadable:
    print('AncestryUnreadable')"
e2e_expect_equal "'$FR_START'
24
True
None
AncestryUnreadable" "$E2E_OUT" "lstart of a running and an ended pid; ancestry of an ended pid"
kill "$FR_SLEEP" 2>/dev/null; wait "$FR_SLEEP" 2>/dev/null
FR_LEASE="$FR_F/jobs/issue-7/directives/$FR_ID.lease.json"
fr_worker_script "$E2E_DIR/worker.sh" "$FR_LEASE" \
  "fr_py module /tmp -- 'import json, os
a = c.ancestry()
print(json.dumps([list(x) for x in a]))
print(a[0][0] == os.getpid())'"
FR_LPID=$(fe_fake_launcher "$FR_F" "$FR_ID" "$E2E_DIR/worker.sh")
[ -n "$FR_LPID" ] && fe_mask_pid "$FR_LPID" launcher
fr_result module
fr_expect_lease_live worker.sh
FR_A=$(printf '%s\n' "$E2E_OUT" | sed -n 1p)
fe_mask_pid "$(jq .child_pid "$FR_LEASE")" child
fe_mask_found "$(jq -r '.launcher_start, .child_start' "$FR_LEASE")"
e2e_expect_equal True "$(printf '%s\n' "$E2E_OUT" | sed -n 2p)" "the first entry is the process itself"
e2e_expect_equal "$(jq -c '[.launcher_pid, .launcher_start]' "$FR_LEASE")" \
  "$(jq -c --argjson p "$(jq .launcher_pid "$FR_LEASE")" '[.[] | select(.[0] == $p) | [.[0], .[2]]] | .[0]' <<<"$FR_A" 2>/dev/null)" \
  "the launcher's [pid, start] in the ancestry"
e2e_expect_equal "$(jq -c '[.child_pid, .child_start]' "$FR_LEASE")" \
  "$(jq -c --argjson p "$(jq .child_pid "$FR_LEASE")" '[.[] | select(.[0] == $p) | [.[0], .[2]]] | .[0]' <<<"$FR_A" 2>/dev/null)" \
  "the claude child's [pid, start] in the ancestry"
e2e_expect_equal true "$(jq 'length > 2 and ([range(0; length - 1) as $i | .[$i][1] == .[$i + 1][0]] | all)' <<<"$FR_A" 2>/dev/null)" \
  "each entry's parent is the next entry"
e2e_expect_equal true "$(jq --arg fl "$(cd "$E2E_ACTIVE_PLUGIN" && pwd -P)/bin/_flow_factory_launch.py --factory-dir $FR_F $FR_ID" \
  '[.[] | select(.[3] | endswith($fl))] | length == 1' <<<"$FR_A" 2>/dev/null)" "one entry's command is the launcher marker, read whole"
fi

if fr_run RF15; then
_flow_test_begin "factory refusal: the session test is CLAUDECODE or an ancestor named exactly claude (RF15)"
fe_new fr-session
e2e_describe "detached from the test (parent pid 1, CLAUDECODE removed): in_session() is False; with CLAUDECODE=1 it is True; below a program run as <dir>/claude it is True; below one run as <dir>/claude-x it is False"
e2e_repo main
mkdir -p "$E2E_DIR/s"
ln -s /bin/bash "$E2E_DIR/s/claude"
ln -s /bin/bash "$E2E_DIR/s/claude-x"
FR_PROG="import sys; sys.path.insert(0, '$E2E_ACTIVE_PLUGIN/bin')
$FR_IMPORT
print(c.in_session())"
fe_detached "$(fe_python)" -E -c "$FR_PROG"
e2e_expect_equal False "$E2E_OUT" "detached, no CLAUDECODE"
fe_detached env CLAUDECODE=1 "$(fe_python)" -E -c "$FR_PROG"
e2e_expect_equal True "$E2E_OUT" "detached, CLAUDECODE=1"
fe_detached "$E2E_DIR/s/claude" -c "$(printf '%q -E -c %q; :' "$(fe_python)" "$FR_PROG")"
e2e_expect_equal True "$E2E_OUT" "below <dir>/claude"
fe_detached "$E2E_DIR/s/claude-x" -c "$(printf '%q -E -c %q; :' "$(fe_python)" "$FR_PROG")"
e2e_expect_equal False "$E2E_OUT" "below <dir>/claude-x"
fi

if fr_run RF16; then
_flow_test_begin "factory refusal: the early check runs before _flow_factory.py imports argparse (RF16)"
fe_new fr-before-imports
e2e_describe "FLOW_FACTORY_JOB=x and PYTHONPATH naming a folder that holds an argparse.py which touches a marker: python3 <plugin>/bin/_flow_factory.py cancel 7 exits 4 worker_env and the planted argparse.py never runs; the same folder on PYTHONPATH with no worker variable shows the planted file is reachable (it runs)"
e2e_repo main
fe_record
mkdir -p "$E2E_DIR/planted-pp"
printf 'open(%s, "w").close()\n' "'$E2E_DIR/argparse-ran'" > "$E2E_DIR/planted-pp/argparse.py"
_e2e_exec env FLOW_FACTORY_JOB=x PYTHONPATH="$E2E_DIR/planted-pp" python3 "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" cancel 7
fr_expect_refused worker_env "cancel 7 with an argparse.py on PYTHONPATH"
if [ -e "$E2E_DIR/argparse-ran" ]; then e2e_expect_equal absent present "the planted argparse.py's marker, with the worker variable"
else e2e_expect_equal absent absent "the planted argparse.py's marker, with the worker variable"; fi
_e2e_exec env PYTHONPATH="$E2E_DIR/planted-pp" python3 "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" status
if [ -e "$E2E_DIR/argparse-ran" ]; then e2e_expect_equal present present "(control) the planted argparse.py's marker, with no worker variable"
else e2e_expect_equal present absent "(control) the planted argparse.py's marker, with no worker variable"; fi
fi
