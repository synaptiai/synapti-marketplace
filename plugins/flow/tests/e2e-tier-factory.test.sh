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
#        a wrapped form or a later command of a chain is not seen
#   TF4  (R43, R85) a command that only mentions a subcommand (grep), or an
#        untiered subcommand (answer --choice, next, wait, question, status,
#        status --intent, probe), is asked about or denied
#   TF5  (R46, design L37) the confirm ask shows no literal, shows a literal
#        from a flow-factory.sh the command named, or asks when status
#        --intent fails; a hook that rewrote the command changes the literal
#   TF6  approve-spec asks without the hash, the head or the spec file line
#   TF7  (design L41) the always-ask list differs from the Person group that
#        flow-factory.sh usage prints, or answer is asked about without --text
#   TF8  (R61) without jq, a person subcommand passes outside a worker; an
#        untiered one is refused
#   TF9  (R49, R80) the directory deny misses a session kind, takes the
#        directory from the cwd in a worker, or matches another directory
#   TF10 (R79) the comment-post deny is missing, or applies with the factory
#        disabled or in a repository with no factory
#   TF11 (design e2e_tests L118) lib/tier-factory.sh is sourced in a
#        repository with no factory directory and no FLOW_FACTORY_* variable
#   TF12 (R84, person_channels L48) the state guard resolves the factory
#        directory from the cwd in a worker, reads only file_path, misses a
#        relative or `..` path, or denies a write outside the factory
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
e2e_describe "factory directory present, no FLOW_FACTORY_*: each person subcommand in each of the eight forms in auto mode; cancel in plan, acceptEdits, bypassPermissions and with no mode; chains; a grep naming a subcommand; the untiered subcommands in default and auto mode; answer --choice --text"
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
# Plan 2.4: what cannot be read is not asked about. A subcommand word that is
# a variable, and a command whose quote never closes, are denied in default
# mode too (Inferred: no ask can show what would run).
for C in 'flow-factory.sh $SUB 7' 'flow-factory.sh cancel 7 "oops'; do
  tf_run default "$C"
  tf_expect deny "default mode, unreadable: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
tf_run default 'true && flow-factory.sh cancel 7'
tf_expect ask "default mode: the second command of a chain (R72)"
for M in default auto; do
  for C in 'grep -n "flow-factory.sh reject" docs/' 'flow-factory.sh answer NI-1 --choice 1' \
           'flow-factory.sh next --executor interactive' 'flow-factory.sh wait --max-seconds 5' \
           'flow-factory.sh question q1 --prompt' 'flow-factory.sh status' 'flow-factory.sh status --intent x' \
           'flow-factory.sh probe --environment' 'flow-factory.sh status --intent confirm' \
           'flow-factory.sh question q1 --prompt "cancel it"' 'echo "flow-factory.sh cancel 7" > notes.txt'; do
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
TF_ORIG="flow-factory.sh confirm $TF_ID 2>&1 | grep -v DEBUG"
TF_NEW=$(tf_payload Bash default "$E2E_REPO" "$(jq -cn --arg c "$TF_ORIG" '{command:$c}')" | sh "$E2E_DIR/rewrite.sh" | jq -r .hookSpecificOutput.updatedInput.command)
e2e_expect_equal "flow-factory.sh confirm $TF_ID 2>&1 | rtk grep -v DEBUG" "$TF_NEW" "the stand-in hook's rewrite"
tf_run default "$TF_NEW"
tf_expect ask "default mode, the rewritten command"
case "$(tf_reason)" in *"$TF_INTENT_LINE"*"> Please run grep on the log."*) _e2e_result pass "the rewritten command's ask holds the same literal and body" ;; *) _e2e_result fail "the rewritten command's ask holds the same literal and body" ;; esac
# The lookup fails: deny with the terminal text (R46).
for C in 'flow-factory.sh confirm issue-7-j1-4-99' 'flow-factory.sh confirm ../../x' 'flow-factory.sh confirm' "flow-factory.sh confirm \$ID"; do
  tf_run default "$C"
  tf_expect deny "default mode, a lookup that cannot succeed: $C"
  e2e_expect_equal "$(tf_terminal "$C")" "$(tf_reason)" "the deny text for: $C"
done
printf 'x' >> "$(fe_factory_dir)/jobs/issue-7/outbox/$TF_ID.body.md"
tf_run default "flow-factory.sh confirm $TF_ID"
tf_expect deny "default mode, the body file changed (INTENT_CHANGED)"
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
e2e_describe "factory directory present, jq not on PATH: confirm, cancel through bash -c, answer --text, answer --choice and status outside a worker; context --mode and cancel in a worker"
TF_NOJQ=$(e2e_path_without jq)
for C in 'flow-factory.sh confirm x' "bash -c 'flow-factory.sh cancel 7'" 'flow-factory.sh answer NI-1 --text yes' "python3 $TF_BIN/_flow_factory.py reject 7"; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect deny "no jq: $C"
done
for C in 'flow-factory.sh status' 'flow-factory.sh answer NI-1 --choice 1' 'flow-factory.sh next'; do
  tf_run "PATH=$TF_NOJQ" default "$C"
  tf_expect none "no jq, untiered: $C"
done
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
e2e_describe "the factory repository: cat a job.json by the built and the physical path; a sibling folder factory2; an ask and a deny in one command; a worker with FLOW_FACTORY_MAIN and its cwd in another repository; ls src/outbox/ in that other repository"
mkdir -p "$E2E_REPO/.flow/factory2"
tf_run default "cat $TF_F/jobs/issue-5/job.json"
tf_expect deny "ordinary session, the built path"
tf_run default "cat $TF_FP/jobs/issue-5/job.json"
tf_expect deny "ordinary session, the physical path"
tf_run default "ls '$TF_F'"
tf_expect deny "ordinary session, the folder itself in quotes"
tf_run default "ls $E2E_REPO/.flow/factory2/"
tf_expect none "a sibling folder whose name starts with factory"
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
e2e_describe "the factory repository: each tool under the factory by an absolute, a physical, a relative and a .. path, and outside it; a linked worktree; a repository with no factory; FLOW_FACTORY_MAIN naming no folder; a worker in another repository with FLOW_FACTORY_MAIN"
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
