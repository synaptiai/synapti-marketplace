# shellcheck shell=bash
# The factory engine core (phase 1a, #354, task T5): subcommand dispatch in
# bin/_flow_factory.py, the job store and locks of bin/_flow_factory_jobs.py,
# the per-key settings read, the per-run charge, the per-run launch limit and
# the overshoot allowance; and the flow.factory keys in settings.json,
# schema.json and the Settings Reference.
#
# Every scenario runs _flow_factory.py in its direct form (fe_direct) or the
# job module through the isolation driver (fe_py), in the scratch repository
# with the scratch HOME. The wrapper's exec path is T4's.
#
# Ways it can be wrong, written down before the checks:
#   ST1  `next` acts while flow.factory.enabled is unset: it reaches its module
#        or writes under the factory directory
#   ST1b an enabled `next` never reaches its module, or reaches it without its
#        arguments; a person subcommand reaches cmd_person without its own name
#   ST1c a module that is not there yet makes main crash, or hides an import
#        error inside a module that is there
#   ST2  a refusal raised in a sibling module escapes main as a traceback,
#        because the script runs as __main__ and the sibling's
#        `from _flow_factory import Refused` loads a second copy
#   ST3  a lock waits for ever, a lock timeout names the wrong lock, or a job
#        lock is held when the global lock is taken
#   ST4  a write under the job lock deadlocks (plan R18), or job state is
#        written without the job lock held
#   ST5  a symlinked jobs directory is followed and written through
#   ST6  an invalid job.json is read as a job, or listed with a reason other
#        than invalid_json or the first schema error's path
#   ST7  a user settings file that sets one key hides every plugin default
#   ST8  a project settings file turns the factory on
#   ST9  the charge is the session total, or the first model's cost only, or
#        a resumed run without the since-last field is charged its total
#   ST10 a run with no result event is charged its limit only; the launch
#        limit is not capped at a third of the stage budget rounded down to
#        the cent, the overshoot allowance is fixed, or an amount is a float
#   ST11 a moved factory directory is not noticed, or the not_built
#        subcommands depend on it
#   ST12 the dearest turn counts a subagent turn, counts the last turn
#        instead of the largest, prices an unknown model, or gives None for a
#        stream with no turn at all (which must keep the $0.50 floor)
#   ST13 settings.json and schema.json disagree: a default the schema refuses,
#        a key the closed schema lets through (a maxTurns key, a sixth stage),
#        or a key the Settings Reference does not list

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# The lines every fe_py program here starts with.
ST_PRE='import os, sys, json, time
from decimal import Decimal
import _flow_factory_jobs as j
from _flow_factory import Refused
'

# st_listing <dir> <saved listing> — fe_py lists every entry under dir (path,
# kind, size, mtime in ns). The first call for a saved listing writes it there
# and prints the paths with their kind, or "absent"; a later call
# prints "unchanged" or each path whose line differs. Times stay out of the
# artifact, so two runs write the same file.
st_listing() {
  fe_py "import os, stat, sys
root, saved = '$1', '$2'
lines = []
if os.path.lexists(root):
    for top, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        for n in sorted(dirs + files):
            p = os.path.join(top, n); st = os.lstat(p)
            lines.append('%s %s %s %s' % (os.path.relpath(p, root), stat.S_IFMT(st.st_mode), st.st_size, st.st_mtime_ns))
if not os.path.exists(saved):
    open(saved, 'w').write('\\n'.join(lines))
    print('\\n'.join(' '.join(l.split(' ')[:2]) for l in lines) or 'absent')
else:
    before = open(saved).read().split('\\n') if os.path.getsize(saved) else []
    changed = sorted(set(before) ^ set(lines))
    print('unchanged' if not changed else 'changed: ' + ', '.join(sorted(set(l.split(' ')[0] for l in changed))))"
}

# st_next_module <body> — a plugin copy whose bin/_flow_factory_next.py is
# the given Python, for scenarios that need `next` to reach a known module.
st_next_module() { e2e_plugin_copy bin/_flow_factory_next.py "$1"; }

_flow_test_begin "factory engine: next refuses while flow.factory.enabled is unset and changes nothing (ST1, I5)"
fe_new st-disabled
# Source of the expected values: journal invariant I5; the line is plan 2.6; the person subcommands are plan 2.7 step 2.
e2e_describe "no flow.factory user setting; a record and a job exist; next prints the disabled line, exits 5, and F is the same before and after"
e2e_repo main
fe_record
fe_job 7 build
ST_F=$(fe_factory_dir)
st_listing "$ST_F" "$E2E_DIR/listing-F"
e2e_expect_line "jobs/issue-7/job.json 32768"
fe_direct next --executor headless
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=disabled next: set flow.factory.enabled" "$E2E_OUT" "the whole of stdout"
st_listing "$ST_F" "$E2E_DIR/listing-F"
e2e_expect_equal "unchanged" "$E2E_OUT" "F after next, against the listing before it"
# The eight acting person subcommands are gated too; status and rebuild are not.
for ST_SUB in answer approve-spec confirm feedback rework retry reject cancel; do
  fe_direct "$ST_SUB" 7
  e2e_expect_equal "5 FACTORY_REFUSED=disabled next: set flow.factory.enabled" "$E2E_RC $E2E_OUT" "$ST_SUB while disabled"
done

_flow_test_begin "factory engine: an enabled next reaches its module with its arguments (ST1b)"
fe_new st-enabled
# Source of the expected values: plan 2.7 dispatch table (cmd_person takes the subcommand); amendments A.3 for status and rebuild.
e2e_describe "enabled in user settings; a plugin copy whose _flow_factory_next.py prints REACHED next; next prints it and exits 0. A copy whose person module prints its subcommand and arguments shows cmd_person gets both"
e2e_repo main
fe_enable
st_next_module 'def cmd_next(a):
    print("REACHED next")
    print("argv=" + " ".join(a))
    return 0'
fe_direct next --executor headless
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "REACHED next"
e2e_expect_line "argv=--executor headless"
e2e_plugin_copy bin/_flow_factory_person.py 'def cmd_person(sub, a):
    print("PERSON " + sub + " " + " ".join(a))
    return 0
def cmd_status(a):
    print("STATUS " + " ".join(a))
    return 0
def cmd_rebuild(a):
    print("REBUILD " + " ".join(a))
    return 0'
fe_direct approve-spec issue-7-j1
e2e_expect_equal "0 PERSON approve-spec issue-7-j1" "$E2E_RC $E2E_OUT" "approve-spec through cmd_person"
# status and rebuild are not gated (amendments A.3): they run with enabled unset.
fe_settings '{}'
fe_direct status --brief
e2e_expect_equal "0 STATUS --brief" "$E2E_RC $E2E_OUT" "status with enabled unset"
fe_direct rebuild 7
e2e_expect_equal "0 REBUILD 7" "$E2E_RC $E2E_OUT" "rebuild with enabled unset"

_flow_test_begin "factory engine: a module not there yet fails only its own subcommands, and an import error inside a module is not hidden (ST1c)"
fe_new st-missing-module
# Source of the expected values: plan 2.7 (a module not there yet fails only its own subcommands); the not_built line for it is this task's choice.
e2e_describe "a plugin copy without _flow_factory_launch.py: launch prints FACTORY_REFUSED=not_built and exits 5. A next module that imports a missing name ends in a traceback naming it, not in not_built"
e2e_repo main
fe_enable
st_next_module 'import _flow_factory_no_such_module
def cmd_next(a):
    return 0'
rm -f "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_launch.py"
fe_direct launch issue-7-j1-build-1
e2e_expect_equal "5 FACTORY_REFUSED=not_built" "$E2E_RC $E2E_OUT" "launch with no launch module"
fe_direct next --executor headless
e2e_expect_equal "1" "$E2E_RC" "exit status of next whose module fails to import"
e2e_expect_err "No module named '_flow_factory_no_such_module'"
e2e_expect_no_out "not_built"

_flow_test_begin "factory engine: a Refused raised in a sibling module is main's Refused (ST2)"
fe_new st-identity
# Source of the expected values: Python runs a script as __main__, so importing it by name loads a second module; plan 2.7 identity rule.
e2e_describe "a next module that raises Refused imported from _flow_factory: stdout is exactly FACTORY_REFUSED=identity_check, exit 5. Negative control: the same copy without the sys.modules line exits 1 with a traceback"
e2e_repo main
fe_enable
st_next_module 'from _flow_factory import Refused
def cmd_next(a):
    raise Refused("identity_check")'
fe_direct next --executor headless
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=identity_check" "$E2E_OUT" "the whole of stdout"
ST_ALIAS='sys.modules["_flow_factory"] = sys.modules["__main__"]'
grep -vF "$ST_ALIAS" "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" > "$E2E_DIR/ff-no-alias.py"
mv "$E2E_DIR/ff-no-alias.py" "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py"
e2e_expect_equal "0" "$(grep -cF "$ST_ALIAS" "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py")" "alias lines in the negative-control copy"
e2e_expect_equal "1" "$(grep -cF "$ST_ALIAS" "$E2E_PLUGIN_DIR/bin/_flow_factory.py")" "alias lines in the shipped file"
printf 'negative control: the copy'"'"'s _flow_factory.py without the line %s\n' "$ST_ALIAS" | _e2e_art
fe_direct next --executor headless
e2e_expect_equal "1" "$E2E_RC" "negative control exit status"
e2e_expect_err "Traceback"
e2e_expect_no_out "FACTORY_REFUSED=identity_check"

_flow_test_begin "factory engine: a lock wait ends at its timeout and names the lock (ST3a, A+7)"
fe_new st-lock-timeout
# Source of the expected values: plan 2.1 (every wait has a timeout; the lock_timeout line names global or issue-N).
e2e_describe "a background process holds F/.lock and issue-7's job lock for 20 s; global_lock(timeout=2) and job_lock(7, timeout=2) in another process raise lock_timeout naming the lock after 2-4 s"
e2e_repo main
fe_bg holder fe_py "$ST_PRE
p = j.resolve()
with j.global_lock(p, 5):
    with j.job_lock(p, 7, 5):
        print('locked', flush=True)
        time.sleep(20)"
fe_wait_for 10 'grep -qx locked "$E2E_DIR/bg-holder.out"'
fe_py "$ST_PRE
p = j.resolve()
for name, take in (('global', lambda: j.global_lock(p, 2)), ('job', lambda: j.job_lock(p, 7, 2))):
    t = time.monotonic()
    try:
        with take():
            print(name + ' acquired')
    except Refused as r:
        e = time.monotonic() - t
        print(name + ' refused=' + str(r))
        print(name + ' elapsed_in_2_to_4=' + ('yes' if 2 <= e < 4 else 'no %.2f' % e))"
e2e_expect_line "global refused=lock_timeout lock=global"
e2e_expect_line "global elapsed_in_2_to_4=yes"
e2e_expect_line "job refused=lock_timeout lock=issue-7"
e2e_expect_line "job elapsed_in_2_to_4=yes"

_flow_test_begin "factory engine: the global lock is refused while a job lock is held (ST3b, journal invariant I1)"
fe_new st-lock-order
# Source of the expected values: journal invariant I1 (global lock before a job lock); plan T5 outline step 2.
e2e_describe "in one process, job_lock(7) then global_lock() raises lock_order; after the job lock is released, global_lock() is taken"
e2e_repo main
fe_py "$ST_PRE
p = j.resolve()
with j.job_lock(p, 7, 2):
    try:
        with j.global_lock(p, 2):
            print('global inside job: acquired')
    except Refused as r:
        print('global inside job: refused=' + str(r))
with j.global_lock(p, 2):
    with j.job_lock(p, 7, 2):
        print('global then job: acquired')
with j.global_lock(p, 2):
    print('global after: acquired')"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "global inside job: refused=lock_order"
e2e_expect_line "global then job: acquired"
e2e_expect_line "global after: acquired"

_flow_test_begin "factory engine: write_job, append_event and store_pending under the job lock do not deadlock (ST4, R18)"
fe_new st-no-deadlock
# Source of the expected values: _journal_atomic.append_jsonl locks events.jsonl.lock, not the job lock (plan R18); the lock_not_held refusals are this task's choice, from invariant I1.
e2e_describe "with a 10 s alarm set, under job_lock(7): write_job, append_event and store_pending each return; the three files exist. Outside the job lock, write_job and append_event are refused, and write_state outside the global lock"
e2e_repo main
fe_job 7 build
fe_py "$ST_PRE
import signal
signal.alarm(10)
p = j.resolve()
job = j.read_job(p, 7)
job['attempt'] = 1
job['cost']['dearest_turn_usd'] = Decimal('0.40')
with j.job_lock(p, 7, 5):
    j.write_job(p, job)
    j.append_event(p, 7, {'type': 'transition', 'job': 'issue-7-j1', 'pass': 'p1', 'event': 'stage_failed'})
    name = j.store_pending(p, 7, 'stage_failed', {}, 'terminal', {'pid': 1, 'start': 'Thu Jan  1 00:00:00 1970', 'ancestry': [1]},
                           {'unvouched_session_action': False})
signal.alarm(0)
J = os.path.join(p.fdir, 'jobs', 'issue-7')
print('job.json attempt=%s dearest=%s' % (json.load(open(J + '/job.json'))['attempt'], json.load(open(J + '/job.json'))['cost']['dearest_turn_usd']))
print('events=%d' % len(open(J + '/events.jsonl').read().splitlines()))
print('event time set=' + str('time' in json.loads(open(J + '/events.jsonl').readline())))
print('pending name ok=' + str(bool(__import__('re').match(r'^[0-9]{20}-stage_failed[.]json$', name))))
print('pending=' + ','.join(e for e, _ in [(n.split('-', 1)[1], r) for n, r in j.pending_events(p, 7)]))
for label, call in (('write_job', lambda: j.write_job(p, job)),
                    ('append_event', lambda: j.append_event(p, 7, {'type': 'x', 'job': 'issue-7-j1', 'pass': None})),
                    ('write_state', lambda: j.write_state(p, j.read_state(p)))):
    try:
        call(); print(label + ' unlocked: written')
    except Refused as r:
        print(label + ' unlocked: refused=' + str(r))
with j.job_lock(p, 7, 5):
    j.drop_pending(p, 7, name)
print('pending after drop=%d' % len(j.pending_events(p, 7)))"
e2e_expect_equal "0" "$E2E_RC" "exit status (a deadlock is killed by SIGALRM and exits 142)"
e2e_expect_line "job.json attempt=1 dearest=0.4"
e2e_expect_line "events=1"
e2e_expect_line "event time set=True"
e2e_expect_line "pending name ok=True"
e2e_expect_line "pending=stage_failed.json"
e2e_expect_line "write_job unlocked: refused=lock_not_held lock=issue-7"
e2e_expect_line "append_event unlocked: refused=lock_not_held lock=issue-7"
e2e_expect_line "write_state unlocked: refused=lock_not_held lock=global"
e2e_expect_line "pending after drop=0"

_flow_test_begin "factory engine: a symlinked jobs directory is refused, not written through (ST5)"
fe_new st-symlink-jobs
# Source of the expected values: design e2e_tests L40; _repo_dir.ensure_repo_dir refuses a symlink below the repository top.
e2e_describe "F/jobs is a symlink to \$E2E_DIR/elsewhere; job_lock, write_job and jobs() are refused with factory_dir_refused, and elsewhere stays empty"
e2e_repo main
fe_job 7 build
ST_F=$(fe_factory_dir)
mkdir -p "$E2E_DIR/elsewhere"
mv "$ST_F/jobs" "$E2E_DIR/jobs-real"
ln -s "$E2E_DIR/elsewhere" "$ST_F/jobs"
fe_py "$ST_PRE
p = j.resolve()
job = json.load(open('$E2E_DIR/jobs-real/issue-7/job.json'))
try:
    with j.job_lock(p, 7, 2):
        j.write_job(p, job)
    print('write: written')
except Refused as r:
    print('write: refused=' + str(r).split(' ')[0])
try:
    print('jobs=%d' % len(j.jobs(p)))
except Refused as r:
    print('jobs: refused=' + str(r).split(' ')[0])"
e2e_expect_line "write: refused=factory_dir_refused"
e2e_expect_line "jobs: refused=factory_dir_refused"
e2e_expect_equal "" "$(ls -A "$E2E_DIR/elsewhere")" "the symlink target's contents"

_flow_test_begin "factory engine: an invalid job.json is listed as unreadable with its reason (ST6)"
fe_new st-unreadable
# Source of the expected values: design states_and_transitions L89; plan 2.14 Unreadable reasons (missing is this task's choice for a folder with an event log and no job.json).
e2e_describe "issue-7 job.json holds '{', issue-8 has state bogus, issue-9 is valid, issue-10 has an event log but no job.json, issue-11 is an empty folder: jobs() lists 7 invalid_json, 8 schema: state, 9 readable, 10 missing, and skips 11"
e2e_repo main
fe_job 7 build
fe_job 8 bogus
fe_job 9 build
ST_F=$(fe_factory_dir)
printf '{' > "$ST_F/jobs/issue-7/job.json"
mkdir -p "$ST_F/jobs/issue-10" "$ST_F/jobs/issue-11"
printf '%s\n' '{"type":"created","job":"issue-10-j1","time":"2026-11-16T00:00:00Z","pass":"p1"}' > "$ST_F/jobs/issue-10/events.jsonl"
fe_py "$ST_PRE
p = j.resolve()
for n, rec in j.jobs(p):
    if isinstance(rec, j.Unreadable):
        print('%d unreadable folder=%s reason=%s' % (n, rec.folder, rec.reason))
    else:
        print('%d job key=%s state=%s' % (n, rec['key'], rec['state']))
print('read_job 8: ' + type(j.read_job(p, 8)).__name__)
print('read_job 12: ' + repr(j.read_job(p, 12)))"
e2e_expect_line "7 unreadable folder=issue-7 reason=invalid_json"
e2e_expect_line "8 unreadable folder=issue-8 reason=schema: state"
e2e_expect_line "9 job key=issue-9-j1 state=build"
e2e_expect_line "10 unreadable folder=issue-10 reason=missing"
e2e_expect_no_out "11 "
e2e_expect_line "read_job 8: Unreadable"
e2e_expect_line "read_job 12: None"

_flow_test_begin "factory engine: a user file that sets one key keeps every other plugin default (ST7)"
fe_new st-settings-merge
# Source of the expected values: cascade-resolve.sh:6 (first non-empty value wins) and its header line 20 (plugin default layer); plan 2.13 defaults.
e2e_describe "user settings set flow.factory.concurrency 2 and worker.stages.build.maxBudgetUsd 30; one-argument setting() calls give 2, leaseSeconds 180 and build timeoutSeconds 3600 from the plugin's settings.json, and an unset key gives None"
e2e_repo main
fe_settings '{"flow":{"factory":{"concurrency":2,"worker":{"stages":{"build":{"maxBudgetUsd":30}}}}}}'
fe_py "$ST_PRE
for k in ('flow.factory.concurrency', 'flow.factory.leaseSeconds', 'flow.factory.worker.stages.build.maxBudgetUsd',
          'flow.factory.worker.stages.build.timeoutSeconds', 'flow.factory.worker.model', 'flow.factory.enabled'):
    print('%s=%r' % (k, j.setting(k)))"
e2e_expect_line "flow.factory.concurrency=2"
e2e_expect_line "flow.factory.leaseSeconds=180"
e2e_expect_line "flow.factory.worker.stages.build.maxBudgetUsd=30"
e2e_expect_line "flow.factory.worker.stages.build.timeoutSeconds=3600"
e2e_expect_line "flow.factory.worker.model=None"
e2e_expect_line "flow.factory.enabled=False"

_flow_test_begin "factory engine: a project settings file cannot turn the factory on (ST8)"
fe_new st-project-settings
# Source of the expected values: design settings_keys L2, L11 (view U: user settings and plugin defaults only).
e2e_describe "the repository's .claude/settings.flow.json sets flow.factory.enabled true and the user file does not: next still prints the disabled line"
e2e_repo main
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"factory":{"enabled":true}}}' > "$E2E_REPO/.claude/settings.flow.json"
st_next_module 'def cmd_next(a):
    print("REACHED next")
    return 0'
fe_direct next --executor headless
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=disabled next: set flow.factory.enabled" "$E2E_OUT" "the whole of stdout"

_flow_test_begin "factory engine: each run is charged its own cost (ST9, RM4, R10)"
fe_new st-charge
# Source of the expected values: journal RM4, hand computation 0.20 + 0.03 = 0.23 and 1.20 - 0.97 = 0.23; plan 2.14 bases; iv (a model without costUSD) and v (never below 0) are hand computations from 2.14.
e2e_describe "charge_run on a resumed result with since-last costs 0.20 + 0.03 and a session total of 1.20 (previous 0.97), the same without since-last, with since-last missing one model's cost, and a fresh result of 0.17"
e2e_repo main
fe_py "$ST_PRE
L, A = Decimal('1.00'), Decimal('0.50')
ev = {'type': 'result', 'total_cost_usd': 1.20,
      'model_usage_since_last_result': {'claude-opus-5-5': {'costUSD': 0.20}, 'claude-haiku-4-5': {'costUSD': 0.03}}}
cases = [('i', ev, 'resume', 0.97),
         ('ii', {'type': 'result', 'total_cost_usd': 1.20}, 'resume', 0.97),
         ('iii', {'type': 'result', 'total_cost_usd': 0.17}, 'fresh', None),
         ('iv', {'type': 'result', 'total_cost_usd': 1.20,
                 'model_usage_since_last_result': {'claude-opus-5-5': {'costUSD': 0.20}, 'claude-haiku-4-5': {}}}, 'resume', 0.97),
         ('v', {'type': 'result', 'total_cost_usd': 0.50}, 'resume', 0.97)]
for name, e, kind, prev in cases:
    c = j.charge_run(e, kind, prev, L, A)
    print('%s %s %s %s' % (name, c['charged_usd'], c['basis'], type(c['charged_usd']).__name__))
c = j.charge_run(ev, 'resume', 0.97, L, A)
print('i totals %s %s' % (c['total_cost_usd'], c['since_last_usd']))"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "i 0.23 since_last Decimal"
e2e_expect_line "ii 0.23 session_increase Decimal"
e2e_expect_line "iii 0.17 first_total Decimal"
e2e_expect_line "iv 0.23 session_increase Decimal"
e2e_expect_line "v 0 session_increase Decimal"
e2e_expect_line "i totals 1.2 0.23"

_flow_test_begin "factory engine: the charge with no result, the per-run launch limit and the allowance (ST10, G3, A.7, A.10)"
fe_new st-limit
# Source of the expected values: plan T5 ST10 hand computations and the A.10 worked example; A.7 for the allowances; ii-float, usd_arg and the refusal line are hand computations from plan 2.14.
e2e_describe "charge_run with no result event; launch_limit on the plan's hand-computed inputs, the same with floats; turn_allowance at dearest turn 0 and 0.40; every amount a Decimal"
e2e_repo main
fe_py "$ST_PRE
D = Decimal
c = j.charge_run(None, 'fresh', None, D('1.00'), D('0.50'))
print('i %s %s %s %s' % (c['charged_usd'], c['basis'], c['total_cost_usd'], c['since_last_usd']))
cases = [('ii', '5.00', '4.40'), ('iii', '5.00', '4.60'), ('iv', '3.00', '0.00'), ('v', '3.00', '1.00'),
         ('vi', '3.00', '2.00'), ('vii', '1.50', '0.00'), ('viii', '2.00', '0.00'), ('ix', '3.00', '2.50')]
for name, b, s in cases:
    v = j.launch_limit(D(b), D(s), D('0.50'))
    print('%s %s %s' % (name, v, type(v).__name__))
v = j.launch_limit(5.0, 4.4, 0.5)
print('ii-float %s %s' % (v, type(v).__name__))
for d in (0, 0.40):
    v = j.turn_allowance({'cost': {'dearest_turn_usd': d}})
    print('x %s %s' % (v, type(v).__name__))
print('arg ' + j.usd_arg(D('0.50')) + ' ' + j.usd_arg(D('6.16')))
print(j.stage_budget_line('build', D('5.00'), D('4.60'), D('0.50')))"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "i 1.50 limit_plus_turn None None"
e2e_expect_line "ii 0.10 Decimal"
e2e_expect_line "iii None NoneType"
e2e_expect_line "iv 0.50 Decimal"
e2e_expect_line "v 0.50 Decimal"
e2e_expect_line "vi 0.50 Decimal"
e2e_expect_line "vii None NoneType"
e2e_expect_line "viii 0.16 Decimal"
e2e_expect_line "ix None NoneType"
e2e_expect_line "ii-float 0.10 Decimal"
e2e_expect_line "x 0.50 Decimal"
e2e_expect_line "x 0.80 Decimal"
e2e_expect_line "arg 0.5 6.16"
e2e_expect_line "FACTORY_REFUSED=stage_budget_exhausted stage=build remaining=0.40 needed=0.50"

_flow_test_begin "factory engine: a moved factory directory is refused before the module runs (ST11, B.3)"
fe_new st-path-changed
# Source of the expected values: amendment B.3; plan 2.7 order (step 1b, then the gate, then the path check).
e2e_describe "enabled; next's module prints REACHED next. The pointer names /elsewhere/factory: next prints factory_path_changed, exit 5, and F is not created. With no pointer, and with fe_record's pointer, next is reached. wait prints not_built with the wrong pointer; the disabled line comes before the path check"
e2e_repo main
fe_enable
st_next_module 'def cmd_next(a):
    print("REACHED next")
    return 0'
ST_F=$(fe_factory_dir)
printf '%s\n' /elsewhere/factory > "$E2E_REPO/.git/flow-factory-path"
fe_direct next --executor headless
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_equal "FACTORY_REFUSED=factory_path_changed recorded=/elsewhere/factory current=$ST_F" "$E2E_OUT" "the whole of stdout"
if [ -e "$ST_F" ]; then e2e_expect_equal "absent" "present" "F after the refusal"; else e2e_expect_equal "absent" "absent" "F after the refusal"; fi
fe_direct wait
e2e_expect_equal "5 FACTORY_REFUSED=not_built" "$E2E_RC $E2E_OUT" "wait with the wrong pointer"
for ST_SUB in run question runner await; do
  fe_direct "$ST_SUB"
  e2e_expect_equal "5 FACTORY_REFUSED=not_built" "$E2E_RC $E2E_OUT" "$ST_SUB with the wrong pointer"
done
fe_settings '{}'
fe_direct next --executor headless
e2e_expect_equal "5 FACTORY_REFUSED=disabled next: set flow.factory.enabled" "$E2E_RC $E2E_OUT" "disabled before the path check"
fe_enable
rm -f "$E2E_REPO/.git/flow-factory-path"
fe_direct next --executor headless
e2e_expect_equal "0 REACHED next" "$E2E_RC $E2E_OUT" "next with no pointer"
fe_record
fe_direct next --executor headless
e2e_expect_equal "0 REACHED next" "$E2E_RC $E2E_OUT" "next with fe_record's pointer"

_flow_test_begin "factory engine: the dearest turn of a run's stream (ST12, A.7)"
fe_new st-dearest-turn
e2e_describe "streams priced by hand from MODEL_PRICES (claude-opus-5-5: input 4, output 20, cache read 0.20 dollars per million): the dearest main-thread turn, 0 for a stream with no turn, None for an unpriced model or a turn without usage"
e2e_repo main
fe_py "$ST_PRE
d = os.environ['E2E_DIR']
def stream(name, events):
    path = os.path.join(d, name)
    with open(path, 'w') as f:
        for e in events:
            f.write(json.dumps(e) + '\n')
    return path
init = {'type': 'system', 'subtype': 'init', 'model': 'claude-opus-5-5', 'session_id': 's'}
def turn(mid, usage, parent=None):
    m = {'id': mid, 'content': [{'type': 'text', 'text': 'x'}]}
    if usage is not None:
        m['usage'] = usage
    return {'type': 'assistant', 'parent_tool_use_id': parent, 'message': m}
result = {'type': 'result', 'total_cost_usd': 2.1}
big = turn('m2', {'input_tokens': 2000, 'output_tokens': 1000, 'cache_read_input_tokens': 10000})
cases = {
  'a': [init, big, big, turn('sub', {'input_tokens': 0, 'output_tokens': 100000}, parent='toolu_1'),
        turn('m1', {'input_tokens': 1000, 'output_tokens': 500}), result],
  'b': [init, result],
  'c': [dict(init, model='claude-unpriced-9'), turn('m1', {'input_tokens': 1000, 'output_tokens': 500}), result],
  'd': [init, turn('m1', None), result],
}
for k in sorted(cases):
    v = j.dearest_turn(stream(k + '.jsonl', cases[k]))
    print('%s %s %s' % (k, 'None' if v is None else v.normalize(), type(v).__name__))"
e2e_expect_equal "0" "$E2E_RC" "exit status"
# a: m2 = (2000*4 + 1000*20 + 10000*0.20) / 1e6 = 0.03; m1 = (1000*4 + 500*20) / 1e6 = 0.014.
# Wrong versions: the subagent turn 2.00, the last turn 0.014, the sum 0.044.
e2e_expect_line "a 0.03 Decimal"
e2e_expect_line "b 0 Decimal"
e2e_expect_line "c None NoneType"
e2e_expect_line "d None NoneType"

_flow_test_begin "factory engine: settings.json, schema.json and the Settings Reference agree on flow.factory (ST13)"
fe_new st-settings-schema
# Source of the expected values: plan 2.13 table (defaults, ranges, the six stages, no maxTurns per amendments A.6); p0 WORKER_TOOLS for allowedTools.
e2e_describe "the plugin's settings.json validates against schema.json with jsonschema; its flow.factory defaults are plan 2.13's; schema.json refuses a maxTurns key, a seventh stage, concurrency 5 and a bad extraEnv name; every flow.factory leaf key is a row of the Settings Reference"
e2e_repo main
fe_py "import json, copy, jsonschema
P = '$E2E_PLUGIN_DIR'
schema = json.load(open(P + '/schema.json'))
settings = json.load(open(P + '/settings.json'))
V = jsonschema.Draft7Validator(schema)
def check(label, doc):
    errs = list(V.iter_errors(doc))
    print('%s %s' % (label, 'valid' if not errs else 'invalid'))
check('shipped', settings)
for label, edit in (('maxTurns', lambda f: f['worker']['stages']['build'].update(maxTurns=5)),
                    ('stage intake', lambda f: f['worker']['stages'].update(intake={'maxBudgetUsd': 1})),
                    ('concurrency 5', lambda f: f.update(concurrency=5)),
                    ('extraEnv bad', lambda f: f['worker'].update(extraEnv=['bad-name'])),
                    ('unknown key', lambda f: f.update(maxStageAttempts=2)),
                    ('model set', lambda f: f['worker'].update(model='claude-opus-5-5'))):
    d = copy.deepcopy(settings); edit(d['flow']['factory']); check(label, d)
f = settings['flow']['factory']
print('defaults', f['enabled'], f['label'], f['concurrency'], f['maxOpenJobs'], f['leaseSeconds'], f['heartbeatSeconds'],
      f['nextBudgetSeconds'], f['syncIntervalSeconds'], f['maxRounds'], f['worker']['extraEnv'], 'model' in f['worker'], 'mcpConfig' in f['worker'])
for s in ('spec', 'build', 'open_pr', 'review', 'rework', 'resolve'):
    st = f['worker']['stages'][s]
    print('stage', s, st['maxBudgetUsd'], st['timeoutSeconds'], ','.join(st['allowedTools']), sorted(st))
def leaves(prefix, node):
    if isinstance(node, dict) and node:
        for k in node:
            yield from leaves(prefix + '.' + k, node[k])
    else:
        yield prefix
ref = open(P + '/references/gate-configuration.md').read()
missing = [k for k in leaves('flow.factory', f) if '\`' + k + '\`' not in ref and not k.startswith('flow.factory.worker.stages.')]
for k in ('flow.factory.worker.model', 'flow.factory.worker.mcpConfig', 'flow.factory.worker.stages.<stage>.maxBudgetUsd',
          'flow.factory.worker.stages.<stage>.timeoutSeconds', 'flow.factory.worker.stages.<stage>.allowedTools'):
    if '\`' + k + '\`' not in ref:
        missing.append(k)
print('reference missing: ' + (','.join(missing) or 'none'))"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "shipped valid"
e2e_expect_line "maxTurns invalid"
e2e_expect_line "stage intake invalid"
e2e_expect_line "concurrency 5 invalid"
e2e_expect_line "extraEnv bad invalid"
e2e_expect_line "unknown key invalid"
e2e_expect_line "model set valid"
e2e_expect_line "defaults False flow:factory 1 5 180 60 60 60 3 [] False False"
ST_TOOLS="Bash,Read,Write,Edit,Glob,Grep,Agent,Task,Skill,TaskCreate,TaskUpdate,TaskList,TaskGet"
ST_KEYS="['allowedTools', 'maxBudgetUsd', 'timeoutSeconds']"
e2e_expect_line "stage spec 5 1800 $ST_TOOLS $ST_KEYS"
e2e_expect_line "stage build 20 3600 $ST_TOOLS $ST_KEYS"
e2e_expect_line "stage open_pr 5 1800 $ST_TOOLS $ST_KEYS"
e2e_expect_line "stage review 10 1800 $ST_TOOLS $ST_KEYS"
e2e_expect_line "stage rework 10 1800 $ST_TOOLS $ST_KEYS"
e2e_expect_line "stage resolve 5 1800 $ST_TOOLS $ST_KEYS"
e2e_expect_line "reference missing: none"

_flow_test_begin "factory engine: the store's other guards and a factory folder not made yet (ST14)"
fe_new st-store-edges
e2e_describe "with no F: jobs, read_state and pending_events answer empty and create nothing; write_state under the global lock reads back; a second hold of one job lock, an invalid job, a corrupt state.json, a symlinked job.json, an invalid pending file and an empty pointer are each refused or listed with their reason"
e2e_repo main
fe_py "$ST_PRE
p = j.resolve(create=False)
print('jobs=%r state pass_seq=%s pending=%r' % (j.jobs(p), j.read_state(p)['pass_seq'], j.pending_events(p, 7)))
print('F exists=' + str(os.path.exists(p.fdir)))
p = j.resolve()
with j.global_lock(p, 2):
    s = j.read_state(p); s['pass_seq'] = 3; j.write_state(p, s)
print('state pass_seq after write=%s' % j.read_state(p)['pass_seq'])
with j.job_lock(p, 7, 2):
    try:
        with j.job_lock(p, 7, 2):
            print('second hold: acquired')
    except Refused as r:
        print('second hold: refused=' + str(r))
    try:
        j.write_job(p, {'issue': 7, 'state': 'bogus'})
    except Refused as r:
        print('invalid job: refused=' + str(r).split(':')[0])
open(os.path.join(p.fdir, 'state.json'), 'w').write('{')
try:
    j.read_state(p)
except Refused as r:
    print('corrupt state: refused=' + str(r))
J = os.path.join(p.fdir, 'jobs', 'issue-7')
os.symlink(os.path.join(os.environ['E2E_DIR'], 'elsewhere.json'), os.path.join(J, 'job.json'))
print('symlinked job.json: ' + repr(j.read_job(p, 7)))
os.makedirs(os.path.join(J, 'pending'))
open(os.path.join(J, 'pending', '00000000000000000001-cancel.json'), 'w').write('{')
open(os.path.join(J, 'pending', 'notes.txt'), 'w').write('x')
print('pending: ' + repr(j.pending_events(p, 7)))
common = os.path.join(p.main, '.git')
open(os.path.join(common, 'flow-factory-path'), 'w').write('')
print(j.factory_path_check(p).replace(p.fdir, '<F>'))"
e2e_expect_equal "0" "$E2E_RC" "exit status"
# Sources: plan 2.14 (the store's API) and 2.1 (layout); the reasons and refusal
# names below are this task's own choices, reported with the task.
e2e_expect_line "jobs=[] state pass_seq=0 pending=[]"
e2e_expect_line "F exists=False"
e2e_expect_line "state pass_seq after write=3"
e2e_expect_line "second hold: refused=lock_reentered lock=issue-7"
e2e_expect_line "invalid job: refused=job_invalid apiVersion"
e2e_expect_line "corrupt state: refused=state_unreadable"
e2e_expect_line "symlinked job.json: Unreadable(folder='issue-7', reason='unreadable')"
e2e_expect_line "pending: [('00000000000000000001-cancel.json', Unreadable(folder='00000000000000000001-cancel.json', reason='invalid_json'))]"
e2e_expect_line "FACTORY_REFUSED=factory_path_changed recorded=unreadable current=<F>"
