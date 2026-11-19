# shellcheck shell=bash
# The flow factory's own rules for Bash commands (hooks/scripts/lib/tier-factory.sh,
# reached through hooks/scripts/tier-gate.sh) and the state guard for Write,
# Edit and NotebookEdit (hooks/scripts/factory-state-guard.sh). Every scenario
# runs the shipped hook with a PreToolUse payload, the way Claude Code runs it.
#
# Ways it can be wrong, written down before the code:
#   TF1  (R71, design github_writes_and_tiers L35) in a worker, the two allowed
#        forms are matched as a substring, so `context --mode; ... cancel 1`
#        passes; or the allowed forms themselves are denied
#   TF2  (R43, R44) in a worker, a wrapped form (env -u, bash -c, sh -c,
#        timeout, nohup, python3 .../_flow_factory.py, a variable naming the
#        script) of a person subcommand is not denied, or is asked about
#        instead of denied
#   TF3  (R42, R45, R60, R72) outside a worker, an always-ask subcommand in a
#        mode other than default, or with no mode, is allowed or asked about;
#        a wrapped form, an interpreter option's value or a later command of
#        a chain is not seen; a call that is not the whole command is asked
#        about
#   TF4  (R43, R85) a command that only mentions a subcommand (grep), or an
#        untiered subcommand (answer --choice, next, wait, question, status,
#        status --intent, probe), is asked about or denied
#   TF5  (R46, design L37) the confirm ask shows no literal, shows a literal
#        from a flow-factory.sh the command named, or asks when status
#        --intent fails; a hook that rewrote the command changes the literal
#   TF6  approve-spec asks without the hash, the head or the spec file line
#   TF7  (design L41) the always-ask list differs from the Person group that
#        flow-factory.sh usage prints, or answer is asked about without --text
#   TF8  (R61) without jq, a person subcommand passes outside a worker (also
#        with a quoted or escaped subcommand word); an untiered one in plain
#        words is refused
#   TF9  (R49, R80) the directory deny misses a session kind, takes the
#        directory from the cwd in a worker, matches another directory, or
#        compares spellings only (a .. path, a link, another case)
#   TF10 (R79) the comment-post deny is missing, or applies with the factory
#        disabled or in a repository with no factory
#   TF11 (design e2e_tests L118) lib/tier-factory.sh is sourced in a
#        repository with no factory directory and no FLOW_FACTORY_* variable
#   TF12 (R84, person_channels L48) the state guard resolves the factory
#        directory from the cwd in a worker, reads only file_path, misses a
#        relative or `..` path or another case of a name, misses a relative
#        path without jq, or denies a write outside the factory
#   TF13 (design e2e_tests L118) hooks.json has no PreToolUse entry for the
#        state guard whose matcher matches Write, Edit and NotebookEdit and not
#        Bash
#
# Every expected value is written out by hand from the plan or design line
# named in each scenario; none is taken from the code under test.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

TF_HOOK=hooks/scripts/tier-gate.sh
TF_GUARD=hooks/scripts/factory-state-guard.sh
tf_want() { [ -z "${TF_ONLY:-}" ] || [ "$TF_ONLY" = "$1" ]; }

# The person subcommands of design person_channels item 1 (the Person group),
# each with arguments as a person types them; answer with --text (design
# github_writes_and_tiers L37).
TF_SUBS="answer approve-spec confirm feedback rework retry reject cancel rebuild"
tf_args() {
  case "$1" in
    answer) printf '%s' 'answer NI-1 --text yes' ;;
    approve-spec) printf '%s' 'approve-spec 7 --spec-hash abc123' ;;
    confirm) printf '%s' 'confirm issue-7-j1-4-1' ;;
    feedback) printf '%s' 'feedback 7 --text more' ;;
    *) printf '%s 7' "$1" ;;
  esac
}
# The eight forms: the seven of design person_channels L23, and the
# variable-path form of R43 and R60. $1 = the form, $2 = subcommand and
# arguments, $3 = the plugin's bin folder.
TF_FORMS="plain env bash-c sh-c timeout nohup python variable"
tf_form() {
  case "$1" in
    plain) printf 'flow-factory.sh %s' "$2" ;;
    env) printf 'env -u FLOW_FACTORY_JOB flow-factory.sh %s' "$2" ;;
    bash-c) printf "bash -c 'flow-factory.sh %s'" "$2" ;;
    sh-c) printf "sh -c 'flow-factory.sh %s'" "$2" ;;
    timeout) printf 'timeout 5 flow-factory.sh %s' "$2" ;;
    nohup) printf 'nohup flow-factory.sh %s' "$2" ;;
    python) printf 'python3 %s/_flow_factory.py %s' "$3" "$2" ;;
    variable) printf 'FF=%s/flow-factory.sh; "$FF" %s' "$3" "$2" ;;
  esac
}

# tf_payload <tool> <mode or -> <cwd> <tool_input json>
tf_payload() {
  if [ "$2" = - ]; then
    jq -cn --arg t "$1" --arg cwd "$3" --argjson i "$4" '{session_id:"s-1",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i}'
  else
    jq -cn --arg t "$1" --arg m "$2" --arg cwd "$3" --argjson i "$4" '{session_id:"s-1",cwd:$cwd,permission_mode:$m,hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i}'
  fi
}
# tf_run [NAME=value ...] <mode or -> <command> [cwd] — tier-gate on a Bash call.
tf_run() {
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in [A-Za-z_]*=*) envs+=("$1"); shift ;; *) break ;; esac
  done
  e2e_run_hook ${envs[@]+"${envs[@]}"} "$TF_HOOK" \
    "$(tf_payload Bash "$1" "${3:-$E2E_REPO}" "$(jq -cn --arg c "$2" '{command:$c}')")"
}
# tf_guard [NAME=value ...] <tool> <path key> <path> [cwd] — the state guard.
tf_guard() {
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in [A-Za-z_]*=*) envs+=("$1"); shift ;; *) break ;; esac
  done
  e2e_run_hook ${envs[@]+"${envs[@]}"} "$TF_GUARD" \
    "$(tf_payload "$1" default "${4:-$E2E_REPO}" "$(jq -cn --arg k "$2" --arg p "$3" '{($k):$p, content:"x", old_string:"a", new_string:"b", new_source:"c"}')")"
}
# tf_timed [NAME=value ...] <mode> <command> — tier-gate on a Bash call, timed
# inside the scenario's own process: the payload is read from a file and the
# hook's stdout goes to a file, so the harness, whose masking of a long text
# takes time of its own, is not timed. The artifact records the payload's
# size and sha256 instead of its text. TF_SECS is the hook's run time in
# whole seconds, E2E_OUT its stdout.
tf_timed() {
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in [A-Za-z_]*=*) envs+=("$1"); shift ;; *) break ;; esac
  done
  tf_payload Bash "$1" "$E2E_REPO" "$(jq -cn --arg c "$2" '{command:$c}')" > "$E2E_DIR/timed-payload.json"
  {
    printf 'code: %s\n' "$TF_HOOK"
    printf 'payload: %s bytes, sha256 %s\n' "$(wc -c < "$E2E_DIR/timed-payload.json" | tr -d ' ')" "$(_e2e_sha256 "$E2E_DIR/timed-payload.json")"
    [ "${#envs[@]}" -gt 0 ] && printf 'environment: %s\n' "${envs[*]}"
    printf 'stdout: the hook run time in seconds; the hook output is kept in a file\n'
  } | _e2e_art
  _e2e_exec env ${envs[@]+"${envs[@]}"} /bin/bash -c 'SECONDS=0; "$1" < "$2" > "$3"; rc=$?; printf "%s" "$SECONDS"; exit "$rc"' \
    tf-timed "$E2E_ACTIVE_PLUGIN/$TF_HOOK" "$E2E_DIR/timed-payload.json" "$E2E_DIR/timed-out"
  TF_SECS="$E2E_OUT"
  E2E_OUT=$(cat "$E2E_DIR/timed-out")
  printf -- '--- expectations\n' | _e2e_art
}
# The decision: deny, ask or allow from the JSON, none for no output, and
# unparsed for output that is not one decision object.
tf_decision() {
  [ -n "$E2E_OUT" ] || { printf none; return; }
  [ "$(printf '%s\n' "$E2E_OUT" | grep -c .)" = 1 ] || { printf unparsed; return; }
  printf '%s' "$E2E_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null || printf unparsed
}
tf_reason() { printf '%s' "$E2E_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }
# tf_expect <decision> <what> — the exit status is 0 and the decision is this.
tf_expect() {
  e2e_expect_equal "0 $1" "$E2E_RC $(tf_decision)" "$2"
}
# The deny text of design person_channels L31 for a command.
tf_terminal() { printf 'run it in a terminal outside Claude Code: %s' "$1"; }

# tf_factory <name> — a scenario with a scratch repository on main and its
# factory directory <main checkout>/.flow/factory (TF_F, as built and as the
# physical path TF_FP).
tf_factory() {
  fe_new "$1"
  e2e_repo main
  TF_F="$E2E_REPO/.flow/factory"
  mkdir -p "$TF_F/jobs/issue-5"
  TF_FP=$(cd "$TF_F" && pwd -P)
  TF_BIN="$E2E_ACTIVE_PLUGIN/bin"
}
# tf_other — a second scratch repository with no factory, at TF_OTHER.
tf_other() {
  TF_OTHER="$E2E_DIR/other"
  ( _e2e_git_env; cd "$E2E_DIR" && git init -q other ) \
    || _flow_assert_fail "$E2E_NAME: could not make the other repository"
}

read -r -d '' TF_PRE <<'PY' || true
import sys
sys.dont_write_bytecode = True
import hashlib, json, os
import _flow_factory_jobs as jobs
import _flow_factory_github as G
P = jobs.resolve()
REPO = 'flow-e2e/scratch'
def jd(n):
    return os.path.join(P.fdir, 'jobs', 'issue-%d' % n)
def comment(n, row, text):
    with jobs.job_lock(P, n):
        j = jobs.read_job(P, n)
        i = G.record_job_intent(P, j, row, 'comment', G.literal_comment(REPO, n), text, ['issueUpdate'], False, repo=REPO)
        jobs.write_job(P, j)
    return i
def body_of(n, i):
    with open(os.path.join(jd(n), 'outbox', i + '.body.md'), 'rb') as f:
        return f.read()
def want(argv, body):
    # plan 2.2: sha256 over the argv elements joined by NUL, a NUL, then the body bytes.
    return hashlib.sha256(b'\0'.join(a.encode('utf-8') for a in argv) + b'\0' + body).hexdigest()
PY

# ---------------------------------------------------------------- TF1 TF2
if tf_want TF1; then
_flow_test_begin "tier-factory: a worker may run exactly context --mode and await, and nothing else that names the factory (TF1, TF2, R43, R44, R71)"
tf_factory tf1-worker
# Source: design github_writes_and_tiers L35 and person_channels L21 (the two
# allowed forms; every other command naming flow-factory.sh or
# _flow_factory.py denied); plan 2.4 rule 1 ("exactly": an optional plain path,
# then the form, then the end of the text); R44 (a deny, not an ask).
e2e_describe "FLOW_FACTORY_JOB set: the two allowed forms with and without a path; the same forms with a chain, a substitution, a redirection or a line end after them; each person subcommand in each of the eight forms; then FLOW_FACTORY_DIRECTIVE alone"
for C in 'flow-factory.sh context --mode' "$TF_BIN/flow-factory.sh context --mode" \
         'flow-factory.sh await NI-1 --max-seconds 100' '  ./bin/flow-factory.sh await q-3  '; do
  tf_run FLOW_FACTORY_JOB=issue-7-j1 default "$C"
  tf_expect none "allowed in a worker: $C"
done
for C in 'flow-factory.sh context --mode; flow-factory.sh cancel 1' 'flow-factory.sh context --mode && true' \
         'flow-factory.sh context --mode $(flow-factory.sh cancel 1)' 'flow-factory.sh await NI-1 --max-seconds 100 > out.txt' \
         $'flow-factory.sh context --mode\nflow-factory.sh cancel 1' 'flow-factory.sh context --mode --json' \
         'flow-factory.sh await NI-1 --max-seconds 1e3' 'flow-factory.sh status' 'flow-factory.sh next' \
         'x$(y)/flow-factory.sh context --mode' "python3 $TF_BIN/_flow_factory.py context --mode"; do
  tf_run FLOW_FACTORY_JOB=issue-7-j1 default "$C"
  tf_expect deny "denied in a worker: $C"
done
for S in $TF_SUBS; do
  for FORM in $TF_FORMS; do
    C=$(tf_form "$FORM" "$(tf_args "$S")" "$TF_BIN")
    tf_run FLOW_FACTORY_JOB=issue-7-j1 default "$C"
    tf_expect deny "worker, $S, $FORM form"
  done
done
# Bash removes quotes and backslashes from the program word, and expands a
# pattern in it, before it runs: each of these runs the script (plan 2.4
# rule 1: every command naming either file but the two forms is denied).
for C in "\"$TF_BIN/flow-factory\".sh cancel 7" "flow-factory.s''h cancel 7" "$TF_BIN/flow-factor\\y.sh cancel 7" \
         "$TF_BIN/flow-fac*.sh cancel 7" "$TF_BIN/flow-factor?.sh cancel 7" "$TF_BIN/flow-fact{ory,}.sh cancel 7" \
         "python3 $TF_BIN/_flow_factory.p''y cancel 7" "python3 -m _flow_fact''ory cancel 7" \
         "\"$TF_BIN/flow-factory\".sh status" "$TF_BIN/flow-fac*.sh status" "$TF_BIN/flow-factor\\y.sh status"; do
  tf_run FLOW_FACTORY_JOB=issue-7-j1 default "$C"
  tf_expect deny "worker, a quoted, escaped or patterned script name: $C"
done
tf_run FLOW_FACTORY_JOB=issue-7-j1 default 'ls *.sh'
tf_expect none "worker, a pattern that is not the program"
tf_run FLOW_FACTORY_DIRECTIVE=issue-7-j1-intake-1 default 'flow-factory.sh cancel 7'
tf_expect deny "FLOW_FACTORY_DIRECTIVE alone makes a worker"
tf_run FLOW_FACTORY_DIRECTIVE=issue-7-j1-intake-1 default 'flow-factory.sh context --mode'
tf_expect none "FLOW_FACTORY_DIRECTIVE alone: context --mode allowed"
e2e_expect_clean_edges
fi

# ---------------------------------------------------------------- TF3 TF4
if tf_want TF3; then
_flow_test_begin "tier-factory: outside a worker, a person subcommand is denied in every mode but default, in every form and anywhere in a chain (TF3, TF4, R42, R43, R45, R60, R72, R85)"
tf_factory tf3-modes
# Source: design person_channels L29-L33 (default asks; any other mode, or no
# mode, denies with `run it in a terminal outside Claude Code: <command>`;
# answer without --text, next, wait, question, status and probe untiered);
# plan 2.4 rule 2 (program words after the wrapped forms; split at ;, &&, ||,
# | and line ends); R43 (a grep that only mentions a subcommand is no call).
e2e_describe "factory directory present, no FLOW_FACTORY_*: each person subcommand in each of the eight forms in auto mode; cancel in plan, acceptEdits, bypassPermissions and with no mode; chains; interpreter options that take a value, python3 -m _flow_factory and env --split-string; wrapper options the hook does not know exactly; a command given to flock -c, --command or script -c; in default mode a person call that is not the whole command (chain, cd, pushd, env -C, an assignment, a pipe, a substitution) and one that is; a grep naming a subcommand, also after wrapper options the hook knows; the untiered subcommands in default and auto mode; answer --choice --text"
for S in $TF_SUBS; do
  for FORM in $TF_FORMS; do
    C=$(tf_form "$FORM" "$(tf_args "$S")" "$TF_BIN")
    tf_run auto "$C"
    tf_expect deny "auto mode, $S, $FORM form"
  done
done
tf_run auto 'flow-factory.sh confirm issue-7-j1-4-1'
e2e_expect_equal "$(tf_terminal 'flow-factory.sh confirm issue-7-j1-4-1')" "$(tf_reason)" "the deny text (R42)"
for M in plan acceptEdits bypassPermissions dontAsk -; do
  tf_run "$M" 'flow-factory.sh cancel 7'
  tf_expect deny "mode $M (R45 for -)"
done
tf_run auto 'true && flow-factory.sh confirm x'
tf_expect deny "auto mode: the second command of a chain (R72)"
e2e_expect_equal "$(tf_terminal 'true && flow-factory.sh confirm x')" "$(tf_reason)" "the deny names the whole command"
for C in 'ls | flow-factory.sh reject 7' 'false || flow-factory.sh retry 7' $'echo hi\nflow-factory.sh rebuild 7' 'echo a; flow-factory.sh rework 7' \
         'echo $(flow-factory.sh cancel 7)' 'echo `flow-factory.sh cancel 7`' '(flow-factory.sh cancel 7)' '{ flow-factory.sh cancel 7; }' \
         'if true; then flow-factory.sh cancel 7; fi' "bash $TF_BIN/flow-factory.sh cancel 7" "PY=python3; \$PY $TF_BIN/_flow_factory.py cancel 7"; do
  tf_run auto "$C"
  tf_expect deny "auto mode, chain or nested: $C"
done
# Plan 2.4 rule 2 reads the wrapped forms by program words, so an interpreter
# option that takes the next word as its value (bash and sh -o, -O, +o,
# --rcfile, --init-file, also at the end of a bundle; python -W, -X, attached
# or not, --check-hash-based-pycs) is stepped over, and python -m runs the
# engine as a module.
for C in "bash -o pipefail $TF_BIN/flow-factory.sh cancel 7" "bash -O extglob $TF_BIN/flow-factory.sh cancel 7" \
         "bash --rcfile /dev/null $TF_BIN/flow-factory.sh cancel 7" "bash --init-file /dev/null $TF_BIN/flow-factory.sh cancel 7" \
         "sh -o errexit $TF_BIN/flow-factory.sh cancel 7" "bash -eo pipefail $TF_BIN/flow-factory.sh cancel 7" \
         "bash +o posix $TF_BIN/flow-factory.sh cancel 7" "bash -- $TF_BIN/flow-factory.sh cancel 7" \
         "python3 -W ignore $TF_BIN/_flow_factory.py cancel 7" "python3 -X dev $TF_BIN/_flow_factory.py cancel 7" \
         "python3 -Wignore -X dev -B $TF_BIN/_flow_factory.py cancel 7" "python3 -BW ignore $TF_BIN/_flow_factory.py cancel 7" \
         "python3 --check-hash-based-pycs never $TF_BIN/_flow_factory.py cancel 7" \
         "env PYTHONPATH=$TF_BIN python3 -m _flow_factory cancel 7" "python3 -m_flow_factory cancel 7" "python3 -Bm _flow_factory cancel 7" \
         "env --split-string='flow-factory.sh cancel 7'" "python3.12 $TF_BIN/_flow_factory.py cancel 7" \
         "bash /dev/fd/0 cancel 7 < $TF_BIN/flow-factory.sh" "timeout 5 python3.12 -m _flow_factory cancel 7"; do
  tf_run auto "$C"
  tf_expect deny "auto mode, an interpreter option with a value: $C"
done
# Each wrapper runs the program after its own options, their values and its
# own operands (timeout's duration, flock's file, chrt's priority, taskset's
# mask, script's file), so the script there is a call. An abbreviated long
# option (nice --adj, timeout --kill) leaves its number to be read as a
# value, never as the program.
for C in 'flock /tmp/l flow-factory.sh cancel 7' 'sudo -u x flow-factory.sh cancel 7' 'nice -n 5 flow-factory.sh cancel 7' \
         'nice --adjustment 5 flow-factory.sh cancel 7' 'script -q f flow-factory.sh cancel 7' 'watch -n 2 flow-factory.sh cancel 7' \
         'timeout -k 1 5 flow-factory.sh cancel 7' 'chrt -f 1 flow-factory.sh cancel 7' 'taskset -c 0 flow-factory.sh cancel 7' \
         'sudo timeout 5 flow-factory.sh cancel 7' 'sudo -s flow-factory.sh cancel 7' 'env -i A=1 flow-factory.sh cancel 7' \
         'stdbuf -oL flow-factory.sh cancel 7' 'ionice -c 3 flow-factory.sh cancel 7' 'caffeinate -i flow-factory.sh cancel 7' \
         'xargs -n 1 flow-factory.sh cancel' 'parallel flow-factory.sh cancel ::: 7' "env -S 'flow-factory.sh cancel 7'" \
         "env -S'flow-factory.sh cancel 7'" 'doas -u x flow-factory.sh cancel 7' 'command flow-factory.sh cancel 7' \
         'nice --adj 5 flow-factory.sh cancel 7' 'timeout --kill 1 5 flow-factory.sh cancel 7'; do
  tf_run auto "$C"
  tf_expect deny "auto mode, a wrapper's program: $C"
done
# A wrapper option the hook's grammar does not know exactly (an option it
# does not list, an abbreviated long option, a bare -) may take the next
# word as its value or not, so the program position after it cannot be
# read: the script word there still counts as the program, and the call is
# counted (finding 0 of the fourth B9 review; fails closed). Each of these
# runs the script with cancel 7 for GNU parallel, GNU env, doas, xargs,
# stdbuf and sudo.
for C in 'parallel --env FOO flow-factory.sh cancel ::: 7' 'parallel --workdir /tmp flow-factory.sh cancel ::: 7' \
         'parallel --tagstring x flow-factory.sh cancel ::: 7' 'parallel -J prof flow-factory.sh cancel ::: 7' \
         'parallel -C , flow-factory.sh cancel ::: 7' 'env -a foo flow-factory.sh cancel 7' 'env --argv0 foo flow-factory.sh cancel 7' \
         'doas -a x flow-factory.sh cancel 7' 'xargs --arg root flow-factory.sh cancel' 'stdbuf --out L flow-factory.sh cancel 7' \
         'sudo --us root flow-factory.sh cancel 7' 'env - flow-factory.sh cancel 7'; do
  tf_run auto "$C"
  tf_expect deny "auto mode, a wrapper option the grammar does not know: $C"
done
# Each guard of the reading has a call it alone finds (the fourth B9
# review, finding 2): python reading _flow_factory.py from its input
# through a pattern, exec's -a value, a long option's value in the next
# word, and a quoted spelling of the script in a command over 1 KB.
TF_LONGQ="echo $(printf 'a%.0s' $(seq 1 1500)); \"$TF_BIN/flow-factory\".sh cancel 7"
for C in "python3 - cancel 7 < $TF_BIN/_flow_fac*.py" 'exec -a foo flow-factory.sh cancel 7' \
         'sudo --user root flow-factory.sh cancel 7' "$TF_LONGQ"; do
  tf_run auto "$C"
  tf_expect deny "auto mode, a call one guard finds: ${C:0:80}"
done
# flock's -c and --command and script's -c hand their value to a shell, as
# env -S does: the value is read as a command of its own (the fourth B9
# review, finding 3), so a person call there is never the whole command.
# Both programs accept a long option by a prefix that is not ambiguous
# (--comm), and the lock file may be an expansion.
TF_NESTED=("flock /tmp/l -c 'flow-factory.sh cancel 7'" "flock -c 'flow-factory.sh cancel 7' /tmp/l" \
           "flock /tmp/l --command 'flow-factory.sh cancel 7'" "flock /tmp/l --command='flow-factory.sh cancel 7'" \
           "flock -xc 'flow-factory.sh cancel 7' /tmp/l" "flock /tmp/l -c'flow-factory.sh cancel 7'" \
           "script -c 'flow-factory.sh cancel 7' f" "script -qc 'flow-factory.sh cancel 7' f" \
           "sudo flock /tmp/l -c 'flow-factory.sh cancel 7'" "flock \"\$LOCK\" -c 'flow-factory.sh cancel 7'" \
           "flock /tmp/l.\$\$ -c 'flow-factory.sh cancel 7'" "flock /tmp/l --comm 'flow-factory.sh cancel 7'" \
           "flock /tmp/l --comm='flow-factory.sh cancel 7'" "script --c 'flow-factory.sh cancel 7' f")
for M in auto default; do
  for C in "${TF_NESTED[@]}"; do
    tf_run "$M" "$C"
    tf_expect deny "$M mode, a command given to flock or script: $C"
    e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
  done
done
# Bash removes quotes and backslashes from the program word and expands a
# pattern in it before it runs (finding 0 of the third B9 review). A quoted
# or escaped name reads as the script; a pattern that could match it cannot
# be read, so it is denied in default mode too.
TF_SPELLED=("\"$TF_BIN/flow-factory\".sh cancel 7" "flow-factory.s''h cancel 7" "$TF_BIN/flow-factor\\y.sh cancel 7" \
            "python3 $TF_BIN/_flow_factory.p''y cancel 7" "python3 -m _flow_fact''ory cancel 7" "$TF_BIN/FLOW-\"FACTORY\".sh cancel 7")
TF_PATTERNED=("$TF_BIN/flow-fac*.sh cancel 7" "$TF_BIN/flow-factor?.sh cancel 7" "$TF_BIN/flow-factor[y].sh cancel 7" \
              "$TF_BIN/flow-fact{ory,}.sh cancel 7" "python3 $TF_BIN/_flow_fac*.py cancel 7" "source $TF_BIN/flow-fac*.sh cancel 7" \
              "timeout 5 $TF_BIN/flow-fac*.sh cancel 7" "cat \"$TF_BIN/flow-factory\".sh | bash -s cancel 7" \
              "bash -s cancel 7 < $TF_BIN/flow-fac*.sh" "python3 -m _flow_fac* cancel 7" "$TF_BIN/flow-fac*.sh status")
for C in "${TF_SPELLED[@]}" "${TF_PATTERNED[@]}"; do
  tf_run auto "$C"
  tf_expect deny "auto mode, a quoted, escaped or patterned script name: $C"
done
for C in "${TF_SPELLED[@]}"; do
  tf_run default "$C"
  tf_expect ask "default mode, a quoted or escaped script name as the whole command: $C"
done
for C in "${TF_PATTERNED[@]}"; do
  tf_run default "$C"
  tf_expect deny "default mode, a patterned script name: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
# Any later word of a person call that bash expands cannot be shown as it
# will run, so it is denied in default mode too (design person_channels L30:
# the ask shows the spec hash).
for C in 'flow-factory.sh approve-spec 7 --spec-hash $H' 'flow-factory.sh cancel $N' 'flow-factory.sh cancel 7*' \
         'flow-factory.sh feedback 7 "$X"' 'flow-factory.sh rework 7 *' "flow-factory.sh cancel '\$N'"; do
  tf_run default "$C"
  tf_expect deny "default mode, a later word bash expands: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
tf_run FLOW_FACTORY_JOB=issue-7-j1 default "python3 -m _flow_factory cancel 7"
tf_expect deny "worker: the engine run as a module"
# Plan 2.4 rule 2 finds a call by program words wherever the shell runs one:
# eval runs its words as a command; source and `.` run the script word with
# the words after it; find -exec, -execdir, -ok and -okdir run the program
# after them (and `{}` is the file find found); a shell or python given its
# script on its input (-s, -, /dev/stdin, or no script word) runs whatever
# that input holds (for python, in a command naming _flow_factory.py);
# xargs adds words from its input; a -c word that is an expansion, or a
# program word that names the script and expands, may split into several
# words; a language's -c or -e script that names the engine is not shell
# this reading can follow. A subcommand word that
# bash expands ({a,b}, *, ?, [..]), and for answer any later word that bash
# expands, cannot be read. On a volume that ignores case, FLOW-FACTORY.SH
# runs the script. Each of these is denied in every mode but default, and in
# default mode too unless the call is the whole command (Inferred: what an
# ask would show must be what runs; decision of 2026-11-19).
TF_SHAPES=('eval flow-factory.sh cancel 7' 'builtin eval flow-factory.sh cancel 7' "eval 'flow-factory.sh cancel 7'" \
           'find . -maxdepth 0 -exec flow-factory.sh cancel 7 \;' 'find . -maxdepth 0 -execdir flow-factory.sh cancel 7 \;' \
           'find . -maxdepth 0 -ok flow-factory.sh cancel 7 \;' 'find . -maxdepth 0 -okdir flow-factory.sh cancel 7 \;' \
           'timeout 5 find . -maxdepth 0 -exec flow-factory.sh cancel 7 \;' "find $TF_BIN -name flow-factory.sh -exec {} cancel 7 \\;" \
           'flow-factory.sh {cancel,} 7' 'flow-factory.sh c[a]ncel 7' 'flow-factory.sh can*l 7' 'flow-factory.sh cance? 7' \
           'flow-factory.sh answer NI-1 --te{x,}t yes' 'flow-factory.sh answer NI-1 $OPT yes' \
           "bash -s cancel 7 < $TF_BIN/flow-factory.sh" "cat $TF_BIN/flow-factory.sh | bash -s cancel 7" \
           "bash /dev/stdin cancel 7 < $TF_BIN/flow-factory.sh" "bash - cancel 7 < $TF_BIN/flow-factory.sh" "sh < $TF_BIN/flow-factory.sh" \
           "cat $TF_BIN/_flow_factory.py | python3 - cancel 7" "python3 < $TF_BIN/_flow_factory.py" \
           'echo cancel 7 | xargs flow-factory.sh' 'xargs -I{} flow-factory.sh {} 7 < subs.txt' \
           'flow-factory.sh${IFS}cancel${IFS}7' "bash -c 'flow-factory.sh\${IFS}cancel\${IFS}7'" \
           "X='flow-factory.sh cancel 7'; bash -c \"\$X\"" 'eval eval eval eval eval flow-factory.sh cancel 7' \
           "source -- $TF_BIN/flow-factory.sh\$X cancel 7" \
           "python3 -c \"import subprocess; subprocess.run(['flow-factory.sh', 'cancel', '7'])\"" \
           "node -e \"require('child_process').execSync('flow-factory.sh cancel 7')\"" 'perl -le "system q{flow-factory.sh cancel 7}"' \
           "node -p \"require('child_process').execSync('flow-factory.sh cancel 7')\"")
# bash -c five levels deep: deeper than the hook reads, so it is unread.
TF_DEEP='flow-factory.sh cancel 7'
for TF_I in 1 2 3 4 5; do TF_DEEP="bash -c $(printf %q "$TF_DEEP")"; done
TF_SHAPES+=("$TF_DEEP")
for M in auto default; do
  for C in "${TF_SHAPES[@]}"; do
    tf_run "$M" "$C"
    tf_expect deny "$M mode, a call the shell runs another way: $C"
    e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
  done
done
for C in "source $TF_BIN/flow-factory.sh cancel 7" ". $TF_BIN/flow-factory.sh cancel 7" "builtin source $TF_BIN/flow-factory.sh cancel 7" \
         "bash -c \"bash -c 'flow-factory.sh cancel 7'\"" "$TF_BIN/FLOW-FACTORY.SH cancel 7" \
         "source -- $TF_BIN/flow-factory.sh cancel 7" "source -p $TF_BIN flow-factory.sh cancel 7" '$FF cancel 7 # flow-factory.sh'; do
  tf_run auto "$C"
  tf_expect deny "auto mode, a call the shell runs another way: $C"
done
# The same programs with an untiered subcommand or no call are not decided.
for M in auto default; do
  for C in 'eval flow-factory.sh status' "source $TF_BIN/flow-factory.sh status" 'find . -name flow-factory.sh' \
           'find . -name flow-factory.sh -exec ls -l {} \;' 'flow-factory.sh status --json | jq .' 'bash --version && flow-factory.sh status' \
           "bash $TF_BIN/flow-factory.sh status" 'flow-factory.sh question "q*" --prompt' \
           '[ -x bin/flow-factory.sh ] && flow-factory.sh status' 'if [[ -d .flow ]]; then flow-factory.sh status; fi' \
           'flow-factory.sh status | python3 -c "import json,sys; print(json.load(sys.stdin)[\"jobs\"][0])"' \
           'timeout 5 flow-factory.sh question q1 --prompt "[y/n] ok?"' 'flow-factory.sh status && $EDITOR notes.txt' \
           $'python3 - <<\'PY\'\nprint("see flow-factory.sh")\nPY' 'perl -p -e "s/a/b/" flow-factory.sh' \
           "cat $TF_BIN/flow-factory.sh | python3 -"; do
    tf_run "$M" "$C"
    tf_expect none "$M mode, no person call: $C"
  done
done
# Plan 2.4: what cannot be read is not asked about. A subcommand word that is
# a variable, and a command whose quote never closes, are denied in default
# mode too (Inferred: no ask can show what would run).
for C in 'flow-factory.sh $SUB 7' 'flow-factory.sh cancel 7 "oops'; do
  tf_run default "$C"
  tf_expect deny "default mode, unreadable: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
# A person subcommand is asked about only when it is the whole command,
# wrappers and bash -c aside: in a chain, after cd, pushd or env -C, with
# an assignment before it, or beside any other command, the ask could show
# one thing and the command do another (a confirm looked up in the payload's
# cwd, a merge's own ask not shown), so it is denied with the terminal text
# (decision of 2026-11-19 on the B9 review; it replaces R72's "default mode
# → ask").
for C in 'true && flow-factory.sh cancel 7' 'cd /tmp && flow-factory.sh confirm issue-7-j1-4-1' 'pushd /tmp; flow-factory.sh retry 7' \
         "env -C $E2E_DIR flow-factory.sh retry 7" 'env --chdir=/tmp flow-factory.sh retry 7' "env -iC $E2E_DIR flow-factory.sh retry 7" \
         'flow-factory.sh retry 7 && gh pr merge 5 --repo o/r --squash' "bash -c 'cd /tmp; flow-factory.sh retry 7'" \
         'flow-factory.sh retry 7 | tee out.txt' 'echo $(flow-factory.sh retry 7)' "FF=$TF_BIN/flow-factory.sh; \"\$FF\" retry 7" \
         'GIT_DIR=/tmp/x.git flow-factory.sh retry 7' 'env FLOW_FACTORY_MAIN=/tmp flow-factory.sh retry 7' 'cd /tmp && flow-factory.sh retry 7' \
         'sudo -D /tmp flow-factory.sh retry 7' 'bash -c "$X"; flow-factory.sh retry 7' "sh -c ''; flow-factory.sh retry 7" \
         'bash -c "$X" flow-factory.sh; flow-factory.sh retry 7' 'bash -c flow-factory.sh; flow-factory.sh retry 7' \
         "env -C /tmp bash -c 'flow-factory.sh retry 7'" "GIT_DIR=/tmp/x.git bash -c 'flow-factory.sh retry 7'" \
         'flow-factory.sh retry 7 $(' 'eval flow-factory.sh retry 7'; do
  tf_run default "$C"
  tf_expect deny "default mode, not the whole command: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
for C in 'flow-factory.sh retry 7' "bash $TF_BIN/flow-factory.sh retry 7" 'env -u FLOW_FACTORY_JOB flow-factory.sh retry 7' \
         'timeout 5 flow-factory.sh retry 7' 'nohup flow-factory.sh retry 7' "python3 $TF_BIN/_flow_factory.py retry 7" \
         "bash -c 'flow-factory.sh retry 7'" "sh -c 'flow-factory.sh retry 7'" 'flow-factory.sh retry 7 > out.txt' \
         "bash -o pipefail $TF_BIN/flow-factory.sh retry 7" "python3 -m _flow_factory retry 7" \
         "source $TF_BIN/flow-factory.sh retry 7" ". $TF_BIN/flow-factory.sh retry 7" "bash -c \"bash -c 'flow-factory.sh retry 7'\"" \
         "$TF_BIN/FLOW-FACTORY.SH retry 7"; do
  tf_run default "$C"
  tf_expect ask "default mode, the whole command: $C"
done
for M in default auto; do
  for C in 'grep -n "flow-factory.sh reject" docs/' 'flow-factory.sh answer NI-1 --choice 1' \
           'flow-factory.sh next --executor interactive' 'flow-factory.sh wait --max-seconds 5' \
           'flow-factory.sh question q1 --prompt' 'flow-factory.sh status' 'flow-factory.sh status --intent x' \
           'flow-factory.sh probe --environment' 'flow-factory.sh status --intent confirm' \
           'flow-factory.sh question q1 --prompt "cancel it"' 'echo "flow-factory.sh cancel 7" > notes.txt' \
           "find . -name '*.md' | xargs grep -l flow-factory.sh" 'git ls-files | xargs wc -l bin/flow-factory.sh' \
           'timeout 5 grep -rn --include=flow-factory.sh retry .' 'sudo rsync -a --exclude=_flow_factory.py a/ b/' \
           'timeout 5 grep flow-factory.sh cancel' 'nice grep flow-factory.sh cancel' 'sudo grep flow-factory.sh cancel' \
           'flock /tmp/l grep flow-factory.sh cancel' 'env grep flow-factory.sh cancel' 'xargs grep -l flow-factory.sh' \
           'nice -n 5 grep flow-factory.sh cancel' "ls $TF_BIN/flow-fac*.sh" 'ls *.sh' "grep -n 'flow-factory.s* cancel' docs/" \
           'nice --adjustment 5 grep flow-factory.sh cancel' 'exec -a foo grep flow-factory.sh cancel' \
           'sudo --user root grep flow-factory.sh cancel' 'sudo -E grep flow-factory.sh cancel' 'env -i grep flow-factory.sh cancel' \
           'find . -print0 | xargs -0 grep -l flow-factory.sh' 'nice -5 grep flow-factory.sh cancel' \
           'timeout -v 5 grep flow-factory.sh cancel' "flock /tmp/l -c 'flow-factory.sh status'" "script -q -c 'flow-factory.sh status' f" \
           "flock /tmp/l grep -c 'flow-factory.sh cancel' x" "script -q f grep -c 'flow-factory.sh cancel' x"; do
    tf_run "$M" "$C"
    tf_expect none "$M mode, untiered: $C"
  done
done
tf_run default 'flow-factory.sh answer NI-1 --choice 1 --text my reply'
tf_expect ask "default mode: answer --choice --text (R85)"
e2e_expect_out "my reply"
tf_run default 'flow-factory.sh answer NI-1 --text=my-reply'
tf_expect ask "default mode: answer --text=<t>"
tf_run auto 'flow-factory.sh answer NI-1 --choice 1 --text my reply'
tf_expect deny "auto mode: answer --choice --text (R85)"
e2e_expect_clean_edges
fi

# ---------------------------------------------------------------- TF5
if tf_want TF5; then
_flow_test_begin "tier-factory: the confirm ask shows the stored literal from the plugin's own status --intent, and a failed lookup denies (TF5, R46)"
fe_new tf5-confirm
# Source: design github_writes_and_tiers L37 (the literal and its sha256 from
# the read-only status --intent); plan 2.4 (run as tier-gate's own plugin's
# flow-factory.sh, never the path in the command; deny with the terminal text
# when the call fails); plan 2.3 status --intent (INTENT line, fences, exit
# 3 INTENT_UNKNOWN, INTENT_CHANGED); plan 2.2 hash rule, computed here;
# design e2e_tests L109 (unaffected by a command-rewriting hook).
e2e_describe "a probe record, job 7 in needs_info with a comment intent whose body mentions grep; confirm in default mode by the plain name, by another path holding a stand-in, after a hook rewrote grep to rtk grep; an unknown id, an id that is not an intent id, and the intent after its body file changed"
e2e_repo main
fe_record
fe_job 7 needs_info
fe_py "$TF_PRE
i = comment(7, '4', 'Please run grep on the log.')
it = json.load(open(os.path.join(jd(7), 'outbox', i + '.json')))
print(i, want(it['argv'], body_of(7, i)))"
read -r TF_ID TF_SHA <<<"$E2E_OUT"
e2e_expect_equal "0 issue-7-j1-4-1" "$E2E_RC $TF_ID" "the intent id (plan 2.2)"
TF_INTENT_LINE="INTENT id=$TF_ID job=issue-7-j1 key=issueUpdate sha256=$TF_SHA"
tf_run default "flow-factory.sh confirm $TF_ID"
tf_expect ask "default mode, confirm by name"
TF_R1=$(tf_reason)
case "$TF_R1" in *"$TF_INTENT_LINE"*) _e2e_result pass "the ask holds the INTENT line with the hand-computed sha256" ;; *) _e2e_result fail "the ask holds the INTENT line with the hand-computed sha256 (got: $TF_R1)" ;; esac
case "$TF_R1" in *"> gh"*"> api"*"> repos/flow-e2e/scratch/issues/7/comments"*) _e2e_result pass "the ask holds the literal, one argv element per line" ;; *) _e2e_result fail "the ask holds the literal, one argv element per line" ;; esac
case "$TF_R1" in *"> Please run grep on the log."*) _e2e_result pass "the ask holds the body" ;; *) _e2e_result fail "the ask holds the body" ;; esac
case "$TF_R1" in *"flow-factory.sh confirm $TF_ID"*) _e2e_result pass "the ask shows the whole command" ;; *) _e2e_result fail "the ask shows the whole command" ;; esac
# A stand-in at the path the command names prints another literal and leaves a mark.
mkdir -p "$E2E_DIR/fake"
printf '#!/bin/sh\n: > %q\necho "INTENT id=$3 job=forged key=none sha256=0"\n' "$E2E_DIR/fake/ran" > "$E2E_DIR/fake/flow-factory.sh"
chmod +x "$E2E_DIR/fake/flow-factory.sh"
tf_run default "$E2E_DIR/fake/flow-factory.sh confirm $TF_ID"
tf_expect ask "default mode, confirm by another path"
case "$(tf_reason)" in *"$TF_INTENT_LINE"*) _e2e_result pass "the literal comes from the plugin's own status --intent" ;; *) _e2e_result fail "the literal comes from the plugin's own status --intent" ;; esac
e2e_expect_no_out "forged"
e2e_expect_equal no "$([ -e "$E2E_DIR/fake/ran" ] && echo yes || echo no)" "the stand-in at the named path ran"
# A hook that rewrites grep to rtk grep before tier-gate sees the command.
cat > "$E2E_DIR/rewrite.sh" <<'SH'
#!/bin/sh
jq -c '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:{command:(.tool_input.command | gsub("(?<a>^|[ |;&])grep "; "\(.a)rtk grep "))}}}'
SH
# A confirm is asked about only as the whole command, so the stand-in hook is
# first shown to rewrite a command that holds grep, then run on the confirm
# itself; the ask's literal keeps the body's own grep (Inferred: design
# e2e_tests L109 with the whole-command rule of 2026-11-19).
TF_GREP=$(tf_payload Bash default "$E2E_REPO" "$(jq -cn '{command:"grep -v DEBUG log.txt"}')" | sh "$E2E_DIR/rewrite.sh" | jq -r .hookSpecificOutput.updatedInput.command)
e2e_expect_equal "rtk grep -v DEBUG log.txt" "$TF_GREP" "the stand-in hook's rewrite"
TF_NEW=$(tf_payload Bash default "$E2E_REPO" "$(jq -cn --arg c "flow-factory.sh confirm $TF_ID" '{command:$c}')" | sh "$E2E_DIR/rewrite.sh" | jq -r .hookSpecificOutput.updatedInput.command)
tf_run default "$TF_NEW"
tf_expect ask "default mode, the command the stand-in hook passed on"
case "$(tf_reason)" in *"$TF_INTENT_LINE"*"> Please run grep on the log."*) _e2e_result pass "the ask after the stand-in hook holds the same literal and body" ;; *) _e2e_result fail "the ask after the stand-in hook holds the same literal and body" ;; esac
e2e_expect_no_out "rtk grep"
tf_run default "flow-factory.sh confirm $TF_ID 2>&1 | rtk grep -v DEBUG"
tf_expect deny "default mode, a confirm piped into another command"
# The lookup runs in the payload's cwd, where this intent exists; after cd or
# env -C the engine would look elsewhere, so the call is denied with the
# terminal text, not asked about (decision of 2026-11-19 on the B9 review).
for C in "cd $E2E_DIR && flow-factory.sh confirm $TF_ID" "env -C $E2E_DIR flow-factory.sh confirm $TF_ID"; do
  tf_run default "$C"
  tf_expect deny "default mode, confirm after a change of directory: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
# The lookup fails: deny with the terminal text (R46).
for C in 'flow-factory.sh confirm issue-7-j1-4-99' 'flow-factory.sh confirm ../../x' 'flow-factory.sh confirm' "flow-factory.sh confirm \$ID"; do
  tf_run default "$C"
  tf_expect deny "default mode, a lookup that cannot succeed: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
printf 'x' >> "$(fe_factory_dir)/jobs/issue-7/outbox/$TF_ID.body.md"
tf_run default "flow-factory.sh confirm $TF_ID"
tf_expect deny "default mode, the body file changed (INTENT_CHANGED)"
# A status --intent that exits 0 but whose first line is not the INTENT line
# of this id (another id, or no INTENT line) shows no literal of this intent,
# so the call is denied (plan 2.3: the first line is `INTENT id=<id> ...`).
# A copy of the plugin whose flow-factory.sh is a stand-in; last in this
# scenario, since the copy stays in use.
for TF_OUT in "INTENT id=issue-7-j1-4-2 job=issue-7-j1 key=issueUpdate sha256=0" "status: ok"; do
  e2e_plugin_copy bin/flow-factory.sh "#!/bin/sh
echo '$TF_OUT'"
  tf_run default "flow-factory.sh confirm $TF_ID"
  tf_expect deny "default mode, status --intent exits 0 with the first line: $TF_OUT"
  e2e_expect_equal "$(tf_terminal "flow-factory.sh confirm $TF_ID")" "$(tf_reason)" "the deny text when the first line is: $TF_OUT"
done
e2e_expect_clean_edges
fi

# ---------------------------------------------------------------- TF6 TF7
if tf_want TF6; then
_flow_test_begin "tier-factory: approve-spec and the other person subcommands ask in default mode, and the asked list equals usage's Person group (TF6, TF7)"
tf_factory tf6-person-list
# Source: design person_channels L30 (approve-spec shows the spec hash, the
# head and the spec file path); plan 2.4 (`spec file: none recorded` when
# job.json has none); design github_writes_and_tiers L41 (the always-ask list
# equals the Person group flow-factory.sh usage prints, answer only with
# --text).
e2e_describe "factory directory present: approve-spec with --spec-hash and --head; the Person line of the plugin's own flow-factory.sh usage; each subcommand of that line, and each of the other groups, in default mode"
tf_run default 'flow-factory.sh approve-spec 7 --spec-hash abc123 --head 0123abcd'
tf_expect ask "approve-spec in default mode"
e2e_expect_out "spec_hash: abc123"
e2e_expect_out "head: 0123abcd"
e2e_expect_out "spec file: none recorded"
tf_run default 'flow-factory.sh approve-spec 7 --spec-hash=abc456'
tf_expect ask "approve-spec with --spec-hash=<h>"
e2e_expect_out "spec_hash: abc456"
e2e_expect_out "head: none"
e2e_run_bin bin/flow-factory.sh usage
TF_PERSON=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^Person: //p')
TF_OTHERS=$(printf '%s\n' "$E2E_OUT" | grep -E '^(Engine|Worker): ' | sed 's/^[A-Za-z]*: //' | tr '\n' ' ')
e2e_expect_equal "$TF_SUBS" "$TF_PERSON" "the Person line of usage is the design's Person group"
for S in $TF_PERSON; do
  case "$S" in
    answer) tf_run default 'flow-factory.sh answer NI-1 --text yes'; tf_expect ask "Person word $S with --text"
            tf_run default 'flow-factory.sh answer NI-1'; tf_expect none "Person word $S without --text" ;;
    confirm) tf_run default 'flow-factory.sh confirm issue-7-j1-4-1'; tf_expect deny "Person word $S is tiered (no record, so the lookup fails)" ;;
    *) tf_run default "flow-factory.sh $S 7"; tf_expect ask "Person word $S" ;;
  esac
done
for S in $TF_OTHERS question wait; do
  tf_run default "flow-factory.sh $S 7"
  tf_expect none "not a Person word: $S"
done
e2e_expect_clean_edges
fi

# ---------------------------------------------------------------- TF8
if tf_want TF8; then
_flow_test_begin "tier-factory: without jq a person subcommand is denied, and the untiered ones and the worker forms still run (TF8, R61)"
tf_factory tf8-nojq
# Source: R61 (no jq, factory directory present, no FLOW_FACTORY_*: confirm
# denied, status allowed); plan 2.4 "Without jq" (a person subcommand word,
# answer only with --text; in a worker, every text naming the files except
# the two worker forms); design person_channels L31 (no mode: deny).
e2e_describe "factory directory present, jq not on PATH: confirm, cancel through bash -c, answer --text and python3 _flow_factory.py reject outside a worker; the untiered subcommands in plain words; quoted, escaped and chained forms, a mention and an interpreter form; context --mode and cancel in a worker"
TF_NOJQ=$(e2e_path_without jq)
for C in 'flow-factory.sh confirm x' "bash -c 'flow-factory.sh cancel 7'" 'flow-factory.sh answer NI-1 --text yes' "python3 $TF_BIN/_flow_factory.py reject 7"; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect deny "no jq: $C"
done
for C in 'flow-factory.sh status' 'flow-factory.sh answer NI-1 --choice 1' 'flow-factory.sh next' \
         "$TF_BIN/flow-factory.sh status --intent x" 'flow-factory.sh wait --max-seconds 5' 'flow-factory.sh question q1 --prompt' \
         'flow-factory.sh probe --environment' '  flow-factory.sh next --executor interactive  '; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect none "no jq, untiered: $C"
done
# Plan 2.4: the jq-free path fails closed. Without jq the text cannot be read
# as program words, so outside a worker every command naming either file is
# denied unless it is, as the whole command, an untiered subcommand with
# plain words (decision of 2026-11-19 on the B9 review): a quote, a
# backslash or a $ anywhere, a chain, or a mention also deny.
for C in "flow-factory.sh con''firm x" 'flow-factory.sh "con"firm x' 'flow-factory.sh con\firm x' \
         "flow-factory.sh \$'\\x63onfirm' x" "flow-factory.sh answer NI-1 --te''xt yes" 'flow-factory.sh answer NI-1 --tex yes' \
         'flow-factory.sh question q1 --prompt "cancel it"' 'flow-factory.sh status; flow-factory.sh cancel 7' \
         'flow-factory.sh status && true' 'grep -n "flow-factory.sh reject" docs/' 'flow-factory.sh status $X' \
         'flow-factory.sh status > out.txt' 'bash flow-factory.sh status' "python3 $TF_BIN/_flow_factory.py status" \
         "flow-factory.sh answer NI-1 --choice 1 {--text,yes}" 'flow-factory.sh answer NI-1 --choice 1 ?-text yes' \
         "\"$TF_BIN/flow-factory\".sh cancel 7" "flow-factory.s''h cancel 7" "$TF_BIN/flow-factor\\y.sh cancel 7" \
         "$TF_BIN/flow-fac*.sh cancel 7" "$TF_BIN/flow-factor?.sh cancel 7" "python3 $TF_BIN/_flow_factory.p''y cancel 7" \
         "python3 -m _flow_fact''ory cancel 7" "$TF_BIN/flow-fac*.sh status" "bash -s cancel 7 < $TF_BIN/flow-fac*.sh"; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect deny "no jq, not a plain untiered command: $C"
done
tf_run "PATH=$TF_NOJQ" default 'ls *.sh'
tf_expect none "no jq: a pattern that is not the program"
# The deny shows the command as written (plan 2.4: the terminal text names
# the command): the JSON escapes \" and \\ are read back, and the value is
# not cut at an escaped quote.
for C in 'flow-factory.sh question q1 --prompt "cancel it" --x' 'flow-factory.sh "cancel" 7' 'flow-factory.sh can\cel 7'; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect deny "no jq, the deny text: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "no jq: the deny shows the whole command: $C"
done
# The same over 1 KB, where the command is read back and the deny text
# escaped in one pass each (the fourth B9 review, findings 1 and 4): quotes,
# backslashes, a backslash before an n (JSON's \\n, never a line end), a
# tab, a carriage return and a line end come back as written, with jq and
# without it.
TF_PAD=$(printf 'b%.0s' $(seq 1 1100))
for C in "echo $TF_PAD; flow-factory.sh feedback 7 \"cancel \\\"it\\\"\"" "echo $TF_PAD; flow-factory.sh feedback 7 'a\\nb'" \
         "echo '$TF_PAD'"$'\t'"x\\\\y"$'\r'$'\n''flow-factory.sh can\cel 7'; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect deny "no jq, the deny text over 1 KB: ${C:0:40}"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "no jq: the deny shows the whole command over 1 KB: ${C:0:40}"
  tf_run auto "$C"
  tf_expect deny "jq, auto mode, the deny text over 1 KB: ${C:0:40}"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "jq: the deny shows the whole command over 1 KB: ${C:0:40}"
done
# A long command is decided in time: a 16 KB commit message in a heredoc
# that names bin/flow-factory.sh is denied without jq, the whole command
# shown, within 5 seconds (it took over 15 before the deny text was escaped
# in one pass).
TF_MSG=$(printf 'line of text abc %.0s\n' $(seq 1 900))
TF_HEREDOC="git commit -F - <<'EOF'
mention bin/flow-factory.sh
$TF_MSG
EOF"
tf_timed "PATH=$TF_NOJQ" default "$TF_HEREDOC"
tf_expect deny "no jq: a 16 KB heredoc naming bin/flow-factory.sh"
e2e_expect_equal "$(tf_terminal "$TF_HEREDOC")" "$(tf_reason)" "no jq: the deny shows the whole 16 KB command"
e2e_expect_equal yes "$([ "${TF_SECS:-99}" -lt 5 ] && echo yes || echo no)" "no jq: the 16 KB command decided within 5 seconds (${TF_SECS:-?} s)"
# A JSON escape the hook does not read back without jq (\u), or two command
# keys, leave the command unknown: the deny says so instead of showing JSON.
TF_UNREAD_TEXT='run it in a terminal outside Claude Code: the command, which this hook could not read without jq'
e2e_run_hook "PATH=$TF_NOJQ" "$TF_HOOK" "{\"session_id\":\"s-1\",\"cwd\":\"$E2E_REPO\",\"permission_mode\":\"default\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"flow-factory.sh can\\u0063el 7\"}}"
tf_expect deny "no jq: a \\u escape in the command"
e2e_expect_equal "$TF_UNREAD_TEXT" "$(tf_reason)" "no jq: the deny text for a \\u escape"
# A payload with two command keys: jq reads the last one, so the first one
# (here an untiered command) cannot be taken for the command.
e2e_run_hook "PATH=$TF_NOJQ" "$TF_HOOK" "{\"session_id\":\"s-1\",\"cwd\":\"$E2E_REPO\",\"permission_mode\":\"default\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"flow-factory.sh status\",\"command\":\"flow-factory.sh cancel 7\"}}"
tf_expect deny "no jq: a payload with two command keys"
e2e_expect_equal "$TF_UNREAD_TEXT" "$(tf_reason)" "no jq: the deny text for two command keys"
for C in "\"$TF_BIN/flow-factory\".sh status" "$TF_BIN/flow-fac*.sh status" "flow-factory.s''h context --mode"; do
  tf_run "PATH=$TF_NOJQ" FLOW_FACTORY_JOB=issue-7-j1 default "$C"
  tf_expect deny "no jq, worker: a quoted or patterned script name: $C"
done
tf_run "PATH=$TF_NOJQ" FLOW_FACTORY_JOB=issue-7-j1 default 'ls *.sh'
tf_expect none "no jq, worker: a pattern that is not the program"
tf_run "PATH=$TF_NOJQ" FLOW_FACTORY_JOB=issue-7-j1 default 'flow-factory.sh context --mode'
tf_expect none "no jq, worker: context --mode"
tf_run "PATH=$TF_NOJQ" FLOW_FACTORY_JOB=issue-7-j1 default 'flow-factory.sh status'
tf_expect deny "no jq, worker: status"
tf_run "PATH=$TF_NOJQ" FLOW_FACTORY_JOB=issue-7-j1 default 'flow-factory.sh context --mode; flow-factory.sh cancel 1'
tf_expect deny "no jq, worker: a chain after context --mode"
# Without jq flow.factory.enabled cannot be read (cascade-resolve.sh needs
# jq), so the comment-post deny counts the factory as enabled (Inferred).
tf_run "PATH=$TF_NOJQ" default 'gh issue comment 5 --body "/flow-factory cancel issue-5-j1"'
tf_expect deny "no jq: a comment post naming /flow-factory"
tf_run "PATH=$TF_NOJQ" default 'gh issue comment 5 --body "see /flow-factory docs" --dry-run && ls docs'
tf_expect deny "no jq: a post with /flow-factory anywhere in it"
tf_run "PATH=$TF_NOJQ" default 'ls /flow-factory-notes'
tf_expect none "no jq: /flow-factory text with no post"
e2e_expect_clean_edges
fi

# ---------------------------------------------------------------- TF9
if tf_want TF9; then
_flow_test_begin "tier-factory: a Bash command naming the absolute factory directory is denied in every session kind, and only that directory (TF9, R49, R80)"
tf_factory tf9-directory
tf_other
# Source: design github_writes_and_tiers L39 (Bash naming the resolved
# absolute factory directory denied; `ls src/outbox/` elsewhere is not); R80
# (an ordinary default-mode session, and a worker whose FLOW_FACTORY_MAIN
# names the checkout while its cwd is another repository); plan 2.4 (a deny
# wins over an ask).
e2e_describe "the factory repository: cat a job.json by the built and the physical path, by a .. path, through a link named factory and in another case; a sibling folder factory2; an ask and a deny in one command; a worker with FLOW_FACTORY_MAIN and its cwd in another repository; ls src/outbox/ in that other repository"
mkdir -p "$E2E_REPO/.flow/factory2"
tf_run default "cat $TF_F/jobs/issue-5/job.json"
tf_expect deny "ordinary session, the built path"
tf_run default "cat $TF_FP/jobs/issue-5/job.json"
tf_expect deny "ordinary session, the physical path"
tf_run default "ls '$TF_F'"
tf_expect deny "ordinary session, the folder itself in quotes"
tf_run default "ls $E2E_REPO/.flow/factory2/"
tf_expect none "a sibling folder whose name starts with factory"
# Bash removes quotes and backslashes before the program sees the path.
for C in "cat $E2E_REPO/.flow/fac''tory/jobs/issue-5/job.json" "cat $E2E_REPO/.flow/\"factory\"/jobs/issue-5/job.json" "cat $E2E_REPO/.flow/fact\\ory/x"; do
  tf_run default "$C"
  tf_expect deny "ordinary session, a quoted or escaped spelling of the folder: $C"
done
# The directory is compared by identity (device and inode), not spelling
# (decision of 2026-11-19 on the B9 review): a .. path, a link to it and, on
# a volume that ignores case, another case all reach it.
tf_run default "cat $E2E_REPO/src/../.flow/factory/jobs/issue-5/job.json"
tf_expect deny "ordinary session, a .. path"
# tier-gate.sh reaches these rules only for a command whose text has
# /factory in it, so the link is named factory as well.
mkdir -p "$E2E_DIR/links"
ln -s "$TF_F" "$E2E_DIR/links/factory"
tf_run default "cat $E2E_DIR/links/factory/jobs/issue-5/job.json"
tf_expect deny "ordinary session, a link to the folder"
tf_run default "cat --file=$E2E_DIR/links/factory/jobs/issue-5/job.json"
tf_expect deny "ordinary session, a link to the folder after ="
# A link to a folder inside the factory, then `..`: only the path as written
# reaches the factory (the text with `..` applied names the link's parent).
ln -s "$TF_F/jobs" "$E2E_DIR/links/jobs"
tf_run default "cat $E2E_DIR/links/jobs/../x/factory"
tf_expect deny "ordinary session, a link into the folder followed by .."
# tier-gate.sh reaches these rules for /factory in any case.
for TF_P in "$E2E_REPO/.FLOW/factory" "$E2E_REPO/.flow/Factory" "$E2E_REPO/.flow/FACTORY"; do
  if [ "$TF_P" -ef "$TF_F" ]; then
    tf_run default "cat $TF_P/jobs/issue-5/job.json"
    tf_expect deny "ordinary session, the folder in another case (this volume ignores case): $TF_P"
  else
    tf_run default "cat $TF_P/jobs/issue-5/job.json"
    tf_expect none "ordinary session, another folder in another case (this volume keeps case): $TF_P"
  fi
done
tf_run default "flow-factory.sh cancel 7; cat $TF_F/jobs/issue-5/job.json"
tf_expect deny "an ask and a deny in one command: the deny"
tf_run FLOW_FACTORY_JOB=issue-5-j1 "FLOW_FACTORY_MAIN=$E2E_REPO" default "cat $TF_F/jobs/issue-5/job.json" "$TF_OTHER"
tf_expect deny "worker in another repository, FLOW_FACTORY_MAIN names the checkout (R80)"
mkdir -p "$TF_OTHER/src/outbox"
tf_run default 'ls src/outbox/' "$TF_OTHER"
tf_expect none "ls src/outbox/ in a repository without a factory (R49)"
tf_run default "ls $TF_OTHER/.flow/factory/" "$TF_OTHER"
tf_expect none "a factory path in a repository without a factory"
e2e_expect_clean_edges
fi

# ---------------------------------------------------------------- TF10
if tf_want TF10; then
_flow_test_begin "tier-factory: a comment post naming /flow-factory is denied when the factory is enabled, and only then (TF10, R79)"
tf_factory tf10-comment-post
tf_other
# Source: design github_writes_and_tiers L40 (gh issue comment, gh pr comment
# and gh api to a comments or reviews endpoint naming /flow-factory, when
# flow.factory.enabled is true); R79 (not denied with it off, nor in a
# repository with no factory, where tier-gate decides them as issueUpdate).
e2e_describe "the three posts of R79 and a review post: with flow.factory.enabled true in the factory repository, with it false, and with it true in a repository with no factory; a post without /flow-factory with the factory enabled"
TF_POSTS=('gh issue comment 5 --body "/flow-factory cancel issue-5-j1"' 'gh pr comment 5 --body "/flow-factory reject issue-5-j1"' 'gh api repos/o/r/issues/5/comments -f body="/flow-factory retry issue-5-j1"' 'gh api --method POST repos/o/r/pulls/5/reviews -f body="/flow-factory retry issue-5-j1"')
for C in "${TF_POSTS[@]}"; do
  tf_run default "$C"
  case "$(tf_decision)" in deny) _e2e_result fail "factory disabled, not denied: $C" ;; *) _e2e_result pass "factory disabled, not denied: $C" ;; esac
done
fe_enable
for C in "${TF_POSTS[@]}"; do
  tf_run default "$C"
  tf_expect deny "factory enabled: $C"
done
tf_run FLOW_FACTORY_JOB=issue-5-j1 default "${TF_POSTS[0]}"
tf_expect deny "factory enabled, a worker"
tf_run default 'gh issue comment 5 --body "thanks"'
case "$(tf_decision)" in deny) _e2e_result fail "factory enabled, a post without /flow-factory is not denied" ;; *) _e2e_result pass "factory enabled, a post without /flow-factory is not denied" ;; esac
for C in "${TF_POSTS[@]}"; do
  tf_run default "$C" "$TF_OTHER"
  case "$(tf_decision)" in deny) _e2e_result fail "no factory, not denied: $C" ;; *) _e2e_result pass "no factory, not denied: $C" ;; esac
done
fi

# ---------------------------------------------------------------- TF11
if tf_want TF11; then
_flow_test_begin "tier-factory: not sourced in a repository with no factory directory and no FLOW_FACTORY_* (TF11)"
fe_new tf11-not-sourced
e2e_repo main
# Source: design e2e_tests L118 and github_writes_and_tiers L34.
e2e_describe "no factory directory, no FLOW_FACTORY_*: cancel in auto mode with xtrace on"
tf_run SHELLOPTS=xtrace auto 'flow-factory.sh cancel 7'
tf_expect none "decision"
e2e_expect_err_lacks "lib/tier-factory.sh"
# Plan 2.4: the rules read program words; a parser that does not load leaves
# them unable to tell a call from a mention, so the command is denied.
mkdir -p "$E2E_REPO/.flow/factory"
e2e_plugin_copy hooks/scripts/lib/command-parse.sh 'return 1'
tf_run default 'flow-factory.sh status'
tf_expect deny "factory directory, the parser fails to load"
e2e_expect_out "command-parse.sh"
fi

# ---------------------------------------------------------------- TF12
if tf_want TF12; then
_flow_test_begin "factory-state-guard: Write, Edit and NotebookEdit under the factory directory are denied, from FLOW_FACTORY_MAIN in a worker; every other write is allowed (TF12, R84)"
tf_factory tf12-state-guard
tf_other
# Source: design person_channels L48 (deny under <main checkout>/<runtime
# dir>/factory; exit at once when FLOW_FACTORY_MAIN is unset and the cwd's
# repository has no factory directory; FLOW_FACTORY_MAIN in a worker; allow
# when the directory cannot be resolved); R84; design e2e_tests L110.
e2e_describe "the factory repository: each tool under the factory by an absolute, a physical, a relative and a .. path, and outside it; without jq by an absolute and a relative path; by another case of a folder on the path; a linked worktree; a repository with no factory; FLOW_FACTORY_MAIN naming no folder; a worker in another repository with FLOW_FACTORY_MAIN"
for T in Write:file_path Edit:file_path NotebookEdit:notebook_path; do
  tf_guard "${T%%:*}" "${T#*:}" "$TF_F/jobs/issue-5/job.json"
  tf_expect deny "${T%%:*} under the factory, absolute"
done
tf_guard Write file_path "$TF_FP/jobs/issue-5/new.json"
tf_expect deny "Write under the factory, physical path"
tf_guard Write file_path ".flow/factory/jobs/issue-5/job.json"
tf_expect deny "Write under the factory, relative to the cwd"
tf_guard Write file_path "$E2E_REPO/src/../.flow/factory/x.json"
tf_expect deny "Write under the factory through .."
tf_guard Write file_path "$TF_F"
tf_expect deny "Write to the factory folder itself"
tf_guard Write file_path "$E2E_REPO/.flow/factory2/x.json"
tf_expect none "Write to a sibling folder factory2"
tf_guard Write file_path "$E2E_REPO/src/a.txt"
tf_expect none "Write outside the factory"
mkdir -p "$E2E_REPO/src"
printf '{}\n' > "$TF_F/jobs/issue-5/job.json"
ln -s "$TF_F/jobs/issue-5/job.json" "$E2E_REPO/src/link.json"
tf_guard Write file_path "$E2E_REPO/src/link.json"
tf_expect deny "Write to a link outside that points into the factory"
TF_NOJQ=$(e2e_path_without jq)
tf_guard "PATH=$TF_NOJQ" Write file_path "$TF_F/jobs/issue-5/job.json"
tf_expect deny "no jq: a payload naming the factory directory"
tf_guard "PATH=$TF_NOJQ" Write file_path "$E2E_REPO/src/b.txt"
tf_expect none "no jq: a write outside the factory"
# Without jq the payload text is also matched for the factory directory
# relative to the repository top (decision of 2026-11-19 on the B9 review).
for P in .flow/factory/jobs/issue-5/job.json .flow/factory ../repo/.flow/factory/x.json \
         ./.flow//factory/x.json .flow/./factory/x.json .flow/.//./factory/x.json .FLOW/factory/x.json .flow/Factory \
         "$E2E_REPO//.flow/factory/x.json" "$E2E_REPO/.flow/./FACTORY/x.json"; do
  tf_guard "PATH=$TF_NOJQ" Write file_path "$P"
  tf_expect deny "no jq: a path naming the factory: $P"
done
# A JSON escape of / (a payload jq would read as .flow/factory/x.json).
e2e_run_hook "PATH=$TF_NOJQ" "$TF_GUARD" "{\"cwd\":\"$E2E_REPO\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\".flow\\/factory\\/x.json\",\"content\":\"x\"}}"
tf_expect deny "no jq: a path naming the factory with \\/ escapes"
for P in .flow/factory2/x.json src/factory/x.json .flow//factory2/x.json "$E2E_REPO/.flow/factory2/x.json" "$E2E_REPO/.flow/factory.bak/x.json"; do
  tf_guard "PATH=$TF_NOJQ" Write file_path "$P"
  tf_expect none "no jq: a path naming another folder: $P"
done
# A runtime directory that is a link to a folder whose name has capitals:
# without jq the factory's physical path is matched in any case, as the
# payload text is.
mkdir -p "$E2E_DIR/Real/FlowData/factory/jobs"
( _e2e_git_env; cd "$E2E_DIR" && git init -q linkrepo ) || _flow_assert_fail "$E2E_NAME: could not make the linked repository"
ln -s "$E2E_DIR/Real/FlowData" "$E2E_DIR/linkrepo/.flow"
TF_LP=$(cd "$E2E_DIR/Real/FlowData/factory" && pwd -P)
for P in "$E2E_DIR/Real/FlowData/factory/jobs/x" "$TF_LP/jobs/x"; do
  tf_guard "PATH=$TF_NOJQ" "FLOW_FACTORY_MAIN=$E2E_DIR/linkrepo" Write file_path "$P"
  tf_expect deny "no jq, a linked runtime directory: the factory's physical path: $P"
done
# The directory is compared by identity (decision of 2026-11-19): on a
# volume that ignores case, another case of a folder on the path is the
# factory itself.
for P in "$E2E_REPO/.FLOW/factory/x.json" "$E2E_REPO/.flow/Factory/x.json" "$E2E_REPO/.flow/FACTORY"; do
  tf_guard Write file_path "$P"
  if [ "$E2E_REPO/.FLOW" -ef "$E2E_REPO/.flow" ]; then
    tf_expect deny "Write by another case of the path (this volume ignores case): $P"
  else
    tf_expect none "Write by another case of the path (this volume keeps case): $P"
  fi
done
( _e2e_git_env; cd "$E2E_REPO" && git worktree add -q -b wt "$E2E_DIR/linked" ) || _flow_assert_fail "$E2E_NAME: no worktree"
tf_guard Edit file_path "$TF_F/jobs/issue-5/job.json" "$E2E_DIR/linked"
tf_expect deny "Edit from a linked worktree of the factory repository"
tf_guard Write file_path "$TF_OTHER/.flow/factory/x.json" "$TF_OTHER"
tf_expect none "a repository with no factory directory"
tf_guard "FLOW_FACTORY_MAIN=$E2E_DIR/no-such" FLOW_FACTORY_JOB=issue-5-j1 Write file_path "$TF_F/x.json" "$TF_OTHER"
tf_expect none "FLOW_FACTORY_MAIN naming no folder: cannot resolve, allowed"
for T in Write:file_path Edit:file_path NotebookEdit:notebook_path; do
  tf_guard "FLOW_FACTORY_MAIN=$E2E_REPO" FLOW_FACTORY_JOB=issue-5-j1 "${T%%:*}" "${T#*:}" "$TF_F/jobs/issue-5/job.json" "$TF_OTHER"
  tf_expect deny "worker in another repository, ${T%%:*} under the factory (R84)"
done
tf_guard "FLOW_FACTORY_MAIN=$E2E_REPO" FLOW_FACTORY_JOB=issue-5-j1 Write file_path "$TF_OTHER/src/a.txt" "$TF_OTHER"
tf_expect none "worker in another repository, a write outside the factory (R84)"
fi

# ---------------------------------------------------------------- TF13
if tf_want TF13; then
_flow_test_begin "hooks.json registers factory-state-guard.sh on PreToolUse for Write, Edit and NotebookEdit only (TF13)"
fe_new tf13-registered
e2e_repo main
# Source: design e2e_tests L118; plan B9 test plan (one PreToolUse entry whose
# matcher, anchored at both ends, matches Write, Edit and NotebookEdit and not
# Bash).
e2e_describe "hooks.json of the plugin under test, read with jq"
TF_HJ="$E2E_ACTIVE_PLUGIN/hooks/hooks.json"
e2e_expect_equal 1 "$(jq '[.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("/factory-state-guard\\.sh$")))] | length' "$TF_HJ")" "PreToolUse entries running the state guard"
e2e_expect_equal 1 "$(jq '[.hooks[][] | select(any(.hooks[]; .command | test("factory-state-guard")))] | length' "$TF_HJ")" "entries running the state guard under any event"
TF_M=$(jq -r '.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("/factory-state-guard\\.sh$"))) | .matcher' "$TF_HJ")
for T in Write Edit NotebookEdit Bash; do
  e2e_expect_equal "$( [ "$T" = Bash ] && echo false || echo true)" "$(jq -nr --arg m "$TF_M" --arg t "$T" '$t | test("^(" + $m + ")$")')" "the matcher matches $T"
done
e2e_expect_equal yes "$([ -x "$E2E_ACTIVE_PLUGIN/$TF_GUARD" ] && echo yes || echo no)" "the state guard is executable"
fi
