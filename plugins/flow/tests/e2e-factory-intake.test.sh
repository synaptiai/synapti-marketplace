# shellcheck shell=bash
# The factory's intake judge (plan 1b, B11): the intake module
# (bin/_flow_factory_intake.py) run through fe_py, bin/flow-judge.sh's intake
# kind run under e2e_new, and `flow-factory.sh launch` of a hand-written
# intake judge directive, with the worker claude stand-in answering as the
# judge (fe_judge_says, fe_judge_raw). The scenarios that need rows to apply
# through `next` (round exhaustion, three malformed results then row 43a,
# the rounds half of R25) are added by a later task (plan B14).
#
# Ways it can be wrong, written down before the code:
#   IN1  (R20, 5.3 "Judge reply") a reply that is not one JSON object, has
#        is_error true, has no structured_output or one that is not an
#        object, fails the judge schema (a decision outside the enum, a key
#        too many), or is an ACCEPT with no proposed_criteria or a NEEDS_INFO
#        with no questions, still maps to a judge_* event
#   IN2  (5.3) the judge's stdin is not issue.md, the fact sheet fence and
#        json.dumps(sheet, sort_keys=True), byte for byte; the fact sheet
#        lacks a key or reads open questions from somewhere else
#   IN3  (R11, 2.2) two question ids repeat; the counter starts at 0; an
#        unreadable counter is taken as empty (which repeats ids) instead of
#        failing
#   IN4  (T:4, 2.2, 5.3) the needs-info effect does not give each question a
#        new NI id and a question file, keeps no earlier round, records no
#        notice or two, records it under another row or state, leaves the
#        notice without the question ids or the reply instructions, or lets
#        judge text post a live @mention, a comment opener or a command line
#   IN5  an effect runs without the job lock, or burns question ids before
#        it finds the lock missing; an unreadable counter leaves a question
#        file or a notice behind
#   IN6  (T:6, design stages L44) intake_inputs is read from the live issue
#        rather than the comments intake read, or counts a fence line quoted
#        inside a comment; the accept notice is recorded under the
#        intake state, so it would be dropped when the job moves on
#   IN7  (T:5, T:8u, 2.2 dedupe) the reject notice is not recorded for the
#        terminal state; a second re-vouch notice for the same reply is
#        recorded again
#   IN8  (T:8a) an answer is not appended in order, or an answer to another
#        job's question is recorded
#   IN9  the needs-human and tier-confirm notices do not carry the row that
#        made them, the state they belong to, or the keys and how to change
#        them; an unknown key is accepted; a notice template that is missing,
#        unreadable or not UTF-8 escapes as a bare OSError or decode error
#        rather than the Refused the command module raises
#        (template_unreadable), which the rows' callers catch, or an effect
#        burns question ids, writes a question file or intake.json, or
#        changes the job before it finds the template unreadable
#   IN10 (trust_and_untrusted_text L30) the needs-info template does not ask
#        for replies that start with the question id, or does not explain
#        /flow-factory spec
#   IN11 (trust_and_untrusted_text L59) a backtick in judge text is left
#        live, so it can pair with the engine's backticks around a mention
#        and leave the mention outside any code span; or the templates' own
#        backticks, or an engine reason's, are escaped
#   FJ1  (2.5, R22, R101) flow-judge.sh --judge intake runs without --model or
#        --timeout-seconds, or with a timeout that is not a positive whole
#        number; goal or verdict accepts the intake-only arguments
#   FJ2  (2.5, design trust_and_untrusted_text L36) the intake judge reads its
#        model or timeout from the settings cascade, cuts the timeout to
#        5-600 s, drops the no-tool flag or the intake schema, or does not use
#        agents/factory-intake.md
#   LI1  (R93, R22, AC2) an intake judge directive (session_id null) is
#        refused; the judge's model is the project file's instead of
#        judges.intakeModel from the user file, else the probe record's; the
#        judge's stdin is not intake_stdin; the result file's judge differs
#        from the reply's structured_output, or the result does not validate
#   LI2  (R23) the judge's cost is not charged, is read from another field,
#        or is not charged for a malformed reply
#   LI3  (AC4) a malformed reply gives a judge_* event or writes a judge key
#   LI4  (R101) the judge gets the goal timeout or the 5-600 s clamp, the
#        person's HOME, a PATH without the stand-ins, a FLOW_FACTORY_*
#        variable, or a CLAUDE_HOOK_GOAL_JUDGE_MODE from the launcher's own
#        environment (which makes flow-judge.sh refuse); a timeout with no
#        reply is anything but stage_failed
#   LI5  (R24) a worker launched after a judge gets CLAUDE_HOOK_GOAL_JUDGE_MODE
#   LI6  an intake judge launches with no in-copies/issue.md
#   LI7  a valid reply padded past JUDGE_REPLY_LIMIT (4 MiB) is applied as a
#        judge_* result instead of a stage_failed one with no judge key
#   LI9  the launcher reads the whole judge reply rather than at most
#        JUDGE_REPLY_LIMIT + 1 bytes of it, so a reply of any size is held
#        in memory (the outcome is the same either way, so LI7 cannot see
#        it; LI9 makes the reply a named pipe and counts what was read)
#   LI8  a hung flow-judge.sh that its own timeout(1) does not end runs on
#        past the launcher's limit (the intake timeout plus the margin), or
#        ends with an outcome other than timeout, a judge key, or a process
#        left running
#
# Every expected value is written out by hand from the plan or design line
# named in each scenario's description; none comes from the module.
#
# IN_ONLY=<id> runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

in_run() { [ -z "${IN_ONLY:-}" ] || [ "$IN_ONLY" = "$1" ]; }

IN_ID=issue-7-j1-intake-1

# The judge replies the scenarios use (plan 5.3 "Intake judge output schema").
IN_ACCEPT='{"decision":"ACCEPT","risk":"low","surfaces":["settings"],"scope":"Add a port setting","proposed_criteria":["The service reads PORT"],"questions":[],"reason":"The issue names one observable change."}'
IN_NEEDS='{"decision":"NEEDS_INFO","risk":"medium","surfaces":["settings"],"scope":"unclear","proposed_criteria":[],"questions":["Which port should it use?"],"reason":"No port is named."}'
IN_REJECT='{"decision":"REJECT","risk":"high","surfaces":[],"scope":"none","proposed_criteria":[],"questions":[],"reason":"Out of scope for this repository."}'

# The Python every module scenario starts with.
read -r -d '' IN_PRE <<'PY' || true
import sys
sys.dont_write_bytecode = True
import json, os
import _flow_factory as ff
import _flow_factory_jobs as jobs
import _flow_factory_schema as schema
import _flow_factory_intake as I
P = jobs.resolve()
REPO = 'flow-e2e/scratch'
JD = os.path.join(P.fdir, 'jobs', 'issue-7')
OUT = os.path.join(JD, 'outbox')
OUTBOX_SCHEMA = os.path.join(ff.PLUGIN_ROOT, 'schemas', 'v1', 'factory-outbox.schema.json')
def J():
    return jobs.read_job(P, 7)
def save(job):
    with jobs.job_lock(P, 7):
        jobs.write_job(P, job)
def items():
    if not os.path.isdir(OUT):
        return {}
    out = {}
    for f in sorted(os.listdir(OUT)):
        if f.endswith('.json'):
            with open(os.path.join(OUT, f), encoding='utf-8') as fh:
                out[f[:-5]] = json.load(fh)
    return out
def body(i):
    with open(os.path.join(OUT, i + '.body.md'), encoding='utf-8') as fh:
        return fh.read()
def show(i):
    it = items()[i]
    print('item %s row=%s state=%s kind=%s key=%s blocking=%s ref=%s valid=%s' % (
        i, it['row'], it['state_at_write'], it['kind'], ','.join(it['key']), it['blocking'], it['ref'],
        schema.validate(it, OUTBOX_SCHEMA) == []))
    return it
def records():
    out = []
    try:
        with open(os.path.join(JD, 'events.jsonl'), encoding='utf-8') as fh:
            for ln in fh:
                d = json.loads(ln)
                if d.get('type') == 'intent_recorded':
                    out.append(d['id'])
    except OSError:
        pass
    return out
PY

in_py() { fe_py "$IN_PRE
$1"; }

# in_module <name> <state> [fe_job statements] — a module scenario: scratch
# repository, probe record (which makes F) and job issue-7-j1 in <state>.
in_module() {
  fe_new "$1"
  e2e_repo main
  fe_record
  fe_job 7 "$2" "${3:-}"
}

# ---------------------------------------------------------------- IN1
if in_run IN1; then
in_module in1-map-result intake
e2e_describe "plan 5.3 'Judge reply' and R20: map_result gives a judge_* event and judge = .structured_output only when stdout is one JSON object whose is_error is not true and whose structured_output is an object that passes the intake schema, with proposed_criteria non-empty for ACCEPT and questions non-empty for NEEDS_INFO; every other stdout gives stage_failed and no judge"
in_py "
A = $IN_ACCEPT
N = $IN_NEEDS
R = $IN_REJECT
def env(so, **extra):
    d = {'type': 'result', 'subtype': 'success', 'is_error': False, 'total_cost_usd': 0.01}
    if so is not None:
        d['structured_output'] = so
    d.update(extra)
    return json.dumps(d).encode()
no_crit = dict(A, proposed_criteria=[])
no_q = dict(N, questions=[])
maybe = dict(A, decision='MAYBE')
extra = dict(A, mood='good')
no_reason = {k: v for k, v in A.items() if k != 'reason'}
no_err = json.dumps({'type': 'result', 'structured_output': A}).encode()
cases = [
    ('accept', env(A)), ('needs', env(N)), ('reject', env(R)),
    ('accept-newline', env(A) + b'\n'), ('no-is-error-key', no_err),
    ('not-json', b'this is not json'), ('empty', b''), ('is-error', env(A, is_error=True)),
    ('no-structured', env(None)), ('structured-text', env('ACCEPT')), ('structured-list', env([A])),
    ('maybe', env(maybe)), ('accept-no-criteria', env(no_crit)), ('needs-no-questions', env(no_q)),
    ('extra-key', env(extra)), ('missing-reason', env(no_reason)), ('two-values', env(A) + b'\n' + env(A)),
    ('envelope-list', json.dumps([json.loads(env(A))]).encode()), ('bad-utf8', b'\xff\xfe'),
]
for label, out in cases:
    event, judge = I.map_result(out)
    same = 'none' if judge is None else ('equal' if judge in (A, N, R) else 'other')
    print('%s %s %s' % (label, event, same))
"
for IN_L in "accept judge_accept equal" "needs judge_needs_info equal" "reject judge_reject equal" \
    "accept-newline judge_accept equal" "no-is-error-key judge_accept equal" \
    "not-json stage_failed none" "empty stage_failed none" "is-error stage_failed none" \
    "no-structured stage_failed none" "structured-text stage_failed none" "structured-list stage_failed none" \
    "maybe stage_failed none" "accept-no-criteria stage_failed none" "needs-no-questions stage_failed none" \
    "extra-key stage_failed none" "missing-reason stage_failed none" "two-values stage_failed none" \
    "envelope-list stage_failed none" "bad-utf8 stage_failed none"; do
  e2e_expect_line "$IN_L"
done
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN2
if in_run IN2; then
in_module in2-stdin intake "d['intake_round'] = 1; d['vouch_at'] = '2026-11-16T00:00:00Z'; d['labels_set'] = ['flow:needs-info']; d['needs_info'] = {'asked_at': '2026-11-16T01:00:00Z', 'questions': ['NI-4', 'NI-5'], 'round': 2, 'earlier': [{'asked_at': '2026-11-15T00:00:00Z', 'questions': ['NI-1'], 'round': 1}]}"
e2e_describe "plan 5.3 Intake module: fact_sheet(job) is {job, issue, intake_round, open_questions, labels, vouch_at}, open_questions being the current round's questions; intake_stdin is issue.md's bytes, then a newline and <<<ENGINE_FACT_SHEET>>>, a newline, json.dumps(sheet, sort_keys=True), a newline, <<<END_ENGINE_FACT_SHEET>>> and a newline. A job with no needs_info and no intake_round gives no open questions and round 0"
in_py "
sheet = I.fact_sheet(J())
want = {'job': 'issue-7-j1', 'issue': 7, 'intake_round': 1, 'open_questions': ['NI-4', 'NI-5'],
        'labels': ['flow:needs-info'], 'vouch_at': '2026-11-16T00:00:00Z'}
print('sheet equal %s' % (sheet == want))
md = '<<<UNTRUSTED_ISSUE_TITLE>>>\n> Add a port é\n<<<END_UNTRUSTED_ISSUE_TITLE>>>\n'
got = I.intake_stdin(md, want)
expected = (md.encode('utf-8') + b'\n<<<ENGINE_FACT_SHEET>>>\n'
            + b'{\"intake_round\": 1, \"issue\": 7, \"job\": \"issue-7-j1\", \"labels\": [\"flow:needs-info\"], '
            + b'\"open_questions\": [\"NI-4\", \"NI-5\"], \"vouch_at\": \"2026-11-16T00:00:00Z\"}'
            + b'\n<<<END_ENGINE_FACT_SHEET>>>\n')
print('stdin bytes %s' % (isinstance(got, bytes)))
print('stdin equal %s' % (got == expected))
bare = dict(J())
for k in ('needs_info', 'intake_round', 'labels_set'):
    bare.pop(k, None)
print('bare %s' % json.dumps(I.fact_sheet(bare), sort_keys=True))
"
e2e_expect_line "sheet equal True"
e2e_expect_line "stdin bytes True"
e2e_expect_line "stdin equal True"
e2e_expect_line 'bare {"intake_round": 0, "issue": 7, "job": "issue-7-j1", "labels": [], "open_questions": [], "vouch_at": "2026-11-16T00:00:00Z"}'
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN3
if in_run IN3; then
in_module in3-question-ids intake
e2e_describe "plan 2.2 'Question ids' and R11: F/questions.json {next} is the factory-wide counter; with no file the first id is NI-1 and the next NI-2, and the file then holds next 3; a counter of 41 gives NI-41; a file that is not JSON, or whose next is not a whole number of at least 1, refuses (questions_unreadable) and is left as it was"
in_py "
Q = os.path.join(P.fdir, 'questions.json')
print('ids %s %s' % (I.next_question_id(P), I.next_question_id(P)))
print('file %s' % json.load(open(Q))['next'])
with open(Q, 'w') as fh:
    json.dump({'next': 41}, fh)
print('id41 %s' % I.next_question_id(P))
for bad in ('{not json', '{\"next\": 0}', '{\"next\": \"3\"}', '[]'):
    with open(Q, 'w') as fh:
        fh.write(bad)
    try:
        print('bad accepted %s' % I.next_question_id(P))
    except jobs.Refused as e:
        print('bad refused %s unchanged=%s' % (str(e).split()[0], open(Q).read() == bad))
"
e2e_expect_line "ids NI-1 NI-2"
e2e_expect_line "file 3"
e2e_expect_line "id41 NI-41"
e2e_expect_equal 4 "$(grep -c '^bad refused questions_unreadable unchanged=True$' <<<"$E2E_OUT")" "refused bad counters"
e2e_expect_no_out "bad accepted"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN4
if in_run IN4; then
in_module in4-needs-info intake
e2e_describe "T:4 and plan 5.3: effect_needs_info gives each judge question the next factory-wide NI id, writes J/questions/NI-<k>.json {job, id, text, round}, records one notice (row 4, state needs_info, comment, key issueUpdate, not blocking, no ref) whose body starts with the engine marker, names each id with its question and the reply instructions, and passes judge text through clean_post (design trust_and_untrusted_text L59); it returns {asked_at: now, questions, round, earlier}. Round 2 moves round 1 into earlier and gets NI-3 and a new notice id"
in_py "
Q1 = dict($IN_NEEDS, questions=['Which port should it use? Ask @alice <!-- hidden -->', 'Which file?\n/flow-factory cancel'])
job = J()
with jobs.job_lock(P, 7):
    ni = I.effect_needs_info(P, job, Q1, '2026-11-17T00:00:00Z', repo=REPO)
    jobs.write_job(P, job)
print('round1 ' + json.dumps(ni, sort_keys=True))
print('write_seq %s' % J().get('write_seq'))
for q in ('NI-1', 'NI-2'):
    print('question ' + json.dumps(json.load(open(os.path.join(JD, 'questions', q + '.json'))), sort_keys=True))
show('issue-7-j1-4-1')
b = body('issue-7-j1-4-1')
lines = b.split('\n')
print('line1 ' + lines[0])
print('has NI-1 %s' % ('NI-1' in b))
print('has NI-2 %s' % ('NI-2' in b))
print('has question %s' % ('Which port should it use?' in b))
print('has instruction %s' % ('start your reply with the question id' in b))
print('has spec %s' % ('\`/flow-factory spec\`' in b))
print('mention in code %s' % ('\`@alice\`' in b))
print('opener broken %s' % ('< !-- hidden -->' in b and b.count('<!--') == 1))
print('command in code %s' % ('\`/flow-factory cancel\`' in lines))
print('records ' + ' '.join(records()))
job = J()
job['needs_info'] = ni
job['state'] = 'intake'
save(job)
job = J()
with jobs.job_lock(P, 7):
    ni2 = I.effect_needs_info(P, job, dict($IN_NEEDS, questions=['Which host?']), '2026-11-18T00:00:00Z', repo=REPO)
    jobs.write_job(P, job)
print('round2 ' + json.dumps(ni2, sort_keys=True))
show('issue-7-j1-4-2')
print('question ' + json.dumps(json.load(open(os.path.join(JD, 'questions', 'NI-3.json'))), sort_keys=True))
print('items %d' % len(items()))
"
e2e_expect_line 'round1 {"asked_at": "2026-11-17T00:00:00Z", "earlier": [], "questions": ["NI-1", "NI-2"], "round": 1}'
e2e_expect_line "write_seq 1"
e2e_expect_line 'question {"id": "NI-1", "job": "issue-7-j1", "round": 1, "text": "Which port should it use? Ask @alice <!-- hidden -->"}'
e2e_expect_line 'question {"id": "NI-2", "job": "issue-7-j1", "round": 1, "text": "Which file?\n/flow-factory cancel"}'
e2e_expect_line "item issue-7-j1-4-1 row=4 state=needs_info kind=comment key=issueUpdate blocking=False ref=None valid=True"
e2e_expect_line "line1 <!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->"
for IN_L in "has NI-1 True" "has NI-2 True" "has question True" "has instruction True" "has spec True" \
    "mention in code True" "opener broken True" "command in code True"; do
  e2e_expect_line "$IN_L"
done
e2e_expect_line "records issue-7-j1-4-1"
e2e_expect_line 'round2 {"asked_at": "2026-11-18T00:00:00Z", "earlier": [{"asked_at": "2026-11-17T00:00:00Z", "questions": ["NI-1", "NI-2"], "round": 1}], "questions": ["NI-3"], "round": 2}'
e2e_expect_line "item issue-7-j1-4-2 row=4 state=needs_info kind=comment key=issueUpdate blocking=False ref=None valid=True"
e2e_expect_line 'question {"id": "NI-3", "job": "issue-7-j1", "round": 2, "text": "Which host?"}'
e2e_expect_line "items 2"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN5
if in_run IN5; then
in_module in5-lock-and-counter intake
e2e_describe "plan 2.2 'Question ids' (a leaf lock taken only under a job lock) and the B11 test plan ('the question counter file unreadable → the effect fails'): effect_needs_info without the job lock refuses lock_not_held before it takes an id (the counter is still absent); with the lock and a counter that is not JSON it refuses questions_unreadable and leaves no question file, no outbox item and no intent_recorded line"
in_py "
Q = os.path.join(P.fdir, 'questions.json')
try:
    I.effect_needs_info(P, J(), $IN_NEEDS, '2026-11-17T00:00:00Z', repo=REPO)
    print('no lock accepted')
except jobs.Refused as e:
    print('no lock refused %s' % str(e).split()[0])
print('counter after %s' % os.path.lexists(Q))
with open(Q, 'w') as fh:
    fh.write('{oops')
try:
    with jobs.job_lock(P, 7):
        I.effect_needs_info(P, J(), $IN_NEEDS, '2026-11-17T00:00:00Z', repo=REPO)
    print('bad counter accepted')
except jobs.Refused as e:
    print('bad counter refused %s' % str(e).split()[0])
print('question files %d' % len(os.listdir(os.path.join(JD, 'questions'))) if os.path.isdir(os.path.join(JD, 'questions')) else 'question files 0')
print('items %d records %d' % (len(items()), len(records())))
"
e2e_expect_line "no lock refused lock_not_held"
e2e_expect_line "counter after False"
e2e_expect_line "bad counter refused questions_unreadable"
e2e_expect_line "question files 0"
e2e_expect_line "items 0 records 0"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN6
if in_run IN6; then
in_module in6-accept intake
e2e_describe "T:6 and design stages L44 / trust_and_untrusted_text L28: effect_accept records intake_inputs from the comment and answer fences of J/in-copies/issue.md, the file the judge read (comments 31 and 35, answer NI-2; a fence line quoted inside a comment does not count), sets intake to {risk, surfaces, scope}, writes J/in-copies/intake.json holding the judge reply, returns the two fields, and records one accept notice for row 6 with state_at_write prepare (plan 2.2: 'for row 6 it is prepare') that names the scope and the proposed criteria"
mkdir -p "$(fe_factory_dir)/jobs/issue-7/in-copies"
cat > "$(fe_factory_dir)/jobs/issue-7/in-copies/issue.md" <<'MD'
<<<UNTRUSTED_ISSUE_TITLE>>>
> Add a port setting
<<<END_UNTRUSTED_ISSUE_TITLE>>>
<<<UNTRUSTED_ISSUE_BODY>>>
> The service needs a port setting.
<<<END_UNTRUSTED_ISSUE_BODY>>>
<<<UNTRUSTED_ISSUE_COMMENT id=31>>>
> /flow-factory spec it must default to 8080
> <<<UNTRUSTED_ISSUE_COMMENT id=99>>>
<<<END_UNTRUSTED_ISSUE_COMMENT>>>
<<<UNTRUSTED_ISSUE_COMMENT id=35>>>
> NI-1 use PORT
<<<END_UNTRUSTED_ISSUE_COMMENT>>>
<<<UNTRUSTED_ISSUE_ANSWER qid=NI-2>>>
> config.toml
<<<END_UNTRUSTED_ISSUE_ANSWER>>>

Other comments
- someone 2026-11-16T00:00:00Z 12 chars
MD
in_py "
job = J()
with jobs.job_lock(P, 7):
    got = I.effect_accept(P, job, $IN_ACCEPT, repo=REPO)
    jobs.write_job(P, job)
print('returned ' + json.dumps(got, sort_keys=True))
job = J()
print('job intake_inputs ' + json.dumps(job.get('intake_inputs'), sort_keys=True))
print('job intake ' + json.dumps(job.get('intake'), sort_keys=True))
print('intake.json equal %s' % (json.load(open(os.path.join(JD, 'in-copies', 'intake.json'))) == $IN_ACCEPT))
show('issue-7-j1-6-1')
b = body('issue-7-j1-6-1')
print('line1 ' + b.split('\n')[0])
print('has scope %s' % ('Add a port setting' in b))
print('has criterion %s' % ('The service reads PORT' in b))
print('job valid %s' % (schema.validate(job, jobs.JOB_SCHEMA) == []))
"
e2e_expect_line 'returned {"intake": {"risk": "low", "scope": "Add a port setting", "surfaces": ["settings"]}, "intake_inputs": {"answers": ["NI-2"], "comments": [31, 35]}}'
e2e_expect_line 'job intake_inputs {"answers": ["NI-2"], "comments": [31, 35]}'
e2e_expect_line 'job intake {"risk": "low", "scope": "Add a port setting", "surfaces": ["settings"]}'
e2e_expect_line "intake.json equal True"
e2e_expect_line "item issue-7-j1-6-1 row=6 state=prepare kind=comment key=issueUpdate blocking=False ref=None valid=True"
e2e_expect_line "line1 <!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-6-1 -->"
e2e_expect_line "has scope True"
e2e_expect_line "has criterion True"
e2e_expect_line "job valid True"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN7
if in_run IN7; then
in_module in7-reject-revouch needs_info
e2e_describe "T:5: effect_reject records one notice for row 5 with state_at_write rejected, naming the judge's reason. T:8u and plan 2.2 dedupe ('keyed by reply id'): effect_revouch_notice records one notice for row 8u with ref = the reply id and the job's own state (8u is a stay row); a second call for reply 31 returns the same id and records nothing; reply 32 gets the next id; the body says a /flow-factory retry is needed"
in_py "
job = J()
with jobs.job_lock(P, 7):
    r = I.effect_reject(P, job, $IN_REJECT, repo=REPO)
    a = I.effect_revouch_notice(P, job, 31, repo=REPO)
    b = I.effect_revouch_notice(P, job, 31, repo=REPO)
    c = I.effect_revouch_notice(P, job, 32, repo=REPO)
    jobs.write_job(P, job)
print('ids %s %s %s %s' % (r, a, b, c))
show('issue-7-j1-5-1')
print('reason %s' % ('Out of scope for this repository.' in body('issue-7-j1-5-1')))
show('issue-7-j1-8u-2')
show('issue-7-j1-8u-3')
print('retry %s' % ('/flow-factory retry' in body('issue-7-j1-8u-2')))
print('items %d records %d' % (len(items()), len(records())))
"
e2e_expect_line "ids issue-7-j1-5-1 issue-7-j1-8u-2 issue-7-j1-8u-2 issue-7-j1-8u-3"
e2e_expect_line "item issue-7-j1-5-1 row=5 state=rejected kind=comment key=issueUpdate blocking=False ref=None valid=True"
e2e_expect_line "reason True"
e2e_expect_line "item issue-7-j1-8u-2 row=8u state=needs_info kind=comment key=issueUpdate blocking=False ref=31 valid=True"
e2e_expect_line "item issue-7-j1-8u-3 row=8u state=needs_info kind=comment key=issueUpdate blocking=False ref=32 valid=True"
e2e_expect_line "retry True"
e2e_expect_line "items 3 records 3"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN8
if in_run IN8; then
in_module in8-answers needs_info
e2e_describe "T:8a and plan 2.2 (J/answers.json is [{qid, text, at}], in the spec-input set): effect_answer appends each answer in order; an answer to a question that is not this job's (no J/questions/NI-9.json naming issue-7-j1) is refused with ValueError and appends nothing; without the job lock it refuses lock_not_held"
mkdir -p "$(fe_factory_dir)/jobs/issue-7/questions"
printf '%s\n' '{"job": "issue-7-j1", "id": "NI-1", "text": "Which port?", "round": 1}' > "$(fe_factory_dir)/jobs/issue-7/questions/NI-1.json"
printf '%s\n' '{"job": "issue-7-j1", "id": "NI-2", "text": "Which file?", "round": 1}' > "$(fe_factory_dir)/jobs/issue-7/questions/NI-2.json"
printf '%s\n' '{"job": "issue-8-j1", "id": "NI-9", "text": "Other job", "round": 1}' > "$(fe_factory_dir)/jobs/issue-7/questions/NI-9.json"
in_py "
job = J()
with jobs.job_lock(P, 7):
    I.effect_answer(P, job, 'NI-2', 'config.toml')
    I.effect_answer(P, job, 'NI-1', 'Port 8080')
    for q in ('NI-9', 'NI-4', 'XX-1'):
        try:
            I.effect_answer(P, job, q, 'nope')
            print('accepted %s' % q)
        except ValueError:
            print('refused %s' % q)
try:
    I.effect_answer(P, job, 'NI-1', 'no lock')
    print('no lock accepted')
except jobs.Refused as e:
    print('no lock refused %s' % str(e).split()[0])
got = json.load(open(os.path.join(JD, 'answers.json')))
print('answers ' + json.dumps([[a['qid'], a['text']] for a in got]))
print('at set %s' % all(isinstance(jobs.epoch(a.get('at')), float) for a in got))
"
e2e_expect_line 'answers [["NI-2", "config.toml"], ["NI-1", "Port 8080"]]'
e2e_expect_line "at set True"
e2e_expect_line "refused NI-9"
e2e_expect_line "refused NI-4"
e2e_expect_line "refused XX-1"
e2e_expect_line "no lock refused lock_not_held"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN9
if in_run IN9; then
in_module in9-parked-notices needs_human "d['reason'] = 'attempts_exhausted'"
e2e_describe "plan B14 step 8 ('each recorded with the row that made the entry'): effect_needs_human records a notice for the given row with state_at_write needs_human that names the reason; effect_tier_confirm records one for the given row with state_at_write waiting_operator that names each key as tiers.<key> and how to change it (design new_files L16: tier-confirm names the keys); an unknown key is refused with ValueError"
in_py "
job = J()
with jobs.job_lock(P, 7):
    h = I.effect_needs_human(P, job, repo=REPO, row='43a')
    t = I.effect_tier_confirm(P, job, ['issueAssign', 'push'], repo=REPO, row='40b')
    try:
        I.effect_tier_confirm(P, job, ['merge2'], repo=REPO, row='40b')
        print('unknown key accepted')
    except ValueError:
        print('unknown key refused')
    jobs.write_job(P, job)
print('ids %s %s' % (h, t))
show('issue-7-j1-43a-1')
show('issue-7-j1-40b-2')
print('reason %s' % ('attempts_exhausted' in body('issue-7-j1-43a-1')))
b = body('issue-7-j1-40b-2')
print('keys %s %s' % ('tiers.issueAssign' in b, 'tiers.push' in b))
print('how %s' % ('journal' in b and 'autonomous' in b))
print('items %d' % len(items()))
"
e2e_expect_line "ids issue-7-j1-43a-1 issue-7-j1-40b-2"
e2e_expect_line "item issue-7-j1-43a-1 row=43a state=needs_human kind=comment key=issueUpdate blocking=False ref=None valid=True"
e2e_expect_line "item issue-7-j1-40b-2 row=40b state=waiting_operator kind=comment key=issueUpdate blocking=False ref=None valid=True"
e2e_expect_line "reason True"
e2e_expect_line "keys True True"
e2e_expect_line "how True"
e2e_expect_line "unknown key refused"
e2e_expect_line "items 2"
e2e_expect_equal 0 "$E2E_RC" "exit status"

in_module in9-template-unreadable intake
e2e_describe "review finding on _template: a notice template that cannot be read is refused as the command module's _render refuses it, Refused('template_unreadable <path>: ...'), so the rows' callers, which catch Refused as EFFECT_FAILED, report it instead of crashing; on a plugin copy intake-accept, revouch-needed, needs-human and tier-confirm are removed, intake-needs-info has mode 000 and intake-reject is not UTF-8. Each of the six effects is refused with template_unreadable naming its template, and none leaves anything behind: no outbox item, no question id taken (no F/questions.json), no question file, no J/in-copies/intake.json, and the job unchanged (plan 2.2: an effect checks before it changes anything; Inferred for the template)"
e2e_plugin_copy templates/factory/intake-reject.comment.md "$(printf 'bad \377\376 bytes')"
IN_TD="$E2E_ACTIVE_PLUGIN/templates/factory"
rm -f "$IN_TD/intake-accept.comment.md" "$IN_TD/revouch-needed.comment.md" "$IN_TD/needs-human.comment.md" "$IN_TD/tier-confirm.comment.md"
chmod 000 "$IN_TD/intake-needs-info.comment.md"
mkdir -p "$(fe_factory_dir)/jobs/issue-7/in-copies"
printf '%s\n' '<<<UNTRUSTED_ISSUE_TITLE>>>' '> Add a port setting' '<<<END_UNTRUSTED_ISSUE_TITLE>>>' > "$(fe_factory_dir)/jobs/issue-7/in-copies/issue.md"
in_py "
A = $IN_ACCEPT
N = $IN_NEEDS
R = $IN_REJECT
job = J()
before = json.dumps(job, sort_keys=True)
def attempt(name, template, f):
    try:
        f()
        print('%s not refused' % name)
    except jobs.Refused as e:
        print('%s refused %s %s' % (name, str(e).split()[0], (template + '.comment.md') in str(e)))
    except Exception as e:
        print('%s raised %s' % (name, type(e).__name__))
with jobs.job_lock(P, 7):
    attempt('accept', 'intake-accept', lambda: I.effect_accept(P, job, A, repo=REPO))
    attempt('needs_info', 'intake-needs-info', lambda: I.effect_needs_info(P, job, N, '2026-11-17T00:00:00Z', repo=REPO))
    attempt('reject', 'intake-reject', lambda: I.effect_reject(P, job, R, repo=REPO))
    attempt('revouch', 'revouch-needed', lambda: I.effect_revouch_notice(P, job, 31, repo=REPO))
    attempt('needs_human', 'needs-human', lambda: I.effect_needs_human(P, job, repo=REPO, row='43a'))
    attempt('tier_confirm', 'tier-confirm', lambda: I.effect_tier_confirm(P, job, ['push'], repo=REPO, row='40b'))
print('items %d' % len(items()))
print('counter %s' % os.path.exists(os.path.join(P.fdir, 'questions.json')))
print('question files %s' % os.path.exists(os.path.join(JD, 'questions')))
print('intake.json %s' % os.path.exists(os.path.join(JD, 'in-copies', 'intake.json')))
print('job unchanged %s' % (json.dumps(job, sort_keys=True) == before))
"
chmod 600 "$IN_TD/intake-needs-info.comment.md"
for IN_E in "accept refused template_unreadable True" "needs_info refused template_unreadable True" \
    "reject refused template_unreadable True" "revouch refused template_unreadable True" \
    "needs_human refused template_unreadable True" "tier_confirm refused template_unreadable True"; do
  e2e_expect_line "$IN_E"
done
e2e_expect_line "items 0"
e2e_expect_line "counter False"
e2e_expect_line "question files False"
e2e_expect_line "intake.json False"
e2e_expect_line "job unchanged True"
e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

# ---------------------------------------------------------------- IN10
if in_run IN10; then
fe_new in10-templates
e2e_repo main
e2e_describe "design trust_and_untrusted_text L30 and T:4's second effect: the needs-info template asks for replies that start with the question id and explains /flow-factory spec; every template B11 owns exists (plan 2.1)"
for IN_T in intake-accept intake-needs-info intake-reject needs-human tier-confirm revouch-needed; do
  e2e_expect_equal yes "$([ -s "$E2E_PLUGIN_DIR/templates/factory/$IN_T.comment.md" ] && echo yes || echo no)" "template $IN_T.comment.md"
done
IN_TPL=$(cat "$E2E_PLUGIN_DIR/templates/factory/intake-needs-info.comment.md" 2>/dev/null)
e2e_expect_equal yes "$(grep -qF 'start your reply with the question id' <<<"$IN_TPL" && echo yes || echo no)" "needs-info template asks for the question id first"
e2e_expect_equal yes "$(grep -qF '/flow-factory spec' <<<"$IN_TPL" && echo yes || echo no)" "needs-info template explains /flow-factory spec"
fi

# ---------------------------------------------------------------- IN11
if in_run IN11; then
in_module in11-model-backticks intake
e2e_describe "design trust_and_untrusted_text L59 (@mentions are put in backticks) and the user's choice of 2026-11-23 (PR review round 3): every backtick in judge text is escaped before it goes into a notice, so the only backticks GitHub can pair are the templates' and the engine's own. A backtick gets a backslash unless an odd run of backslashes already escapes it. Expected strings are traced by hand: 'see \\\`\`@octocat and @hubot' (the review's input) becomes 'see \\\`\\\`' with both mentions in two-backtick fences, a space after the escaped backtick, because the needs-info template's own one-backtick spans take length 1; in a reject reason, a code span becomes 'see \\\`code\\\`' with the mention in a two-backtick fence, a three-backtick fence and a backtick after an escaped backslash are escaped; the templates' own spans such as \`NI-1: ...\` and \`/flow-factory spec\` are unchanged, and an engine reason in the needs-human notice keeps its code span, because only judge values are escaped"
in_py "
Q = dict($IN_NEEDS, questions=['see \\\\\`\`@octocat and @hubot'])
job = J()
with jobs.job_lock(P, 7):
    I.effect_needs_info(P, job, Q, '2026-11-17T00:00:00Z', repo=REPO)
    jobs.write_job(P, job)
b = body('issue-7-j1-4-1')
print('needs question %s' % ('- NI-1: see \\\\\`\\\\\` \`\`@octocat\`\` and \`\`@hubot\`\`' in b.split('\n')))
print('needs template %s' % ('for example \`NI-1: ...\`' in b and '\`/flow-factory spec\`' in b))
R = dict($IN_REJECT, reason='see \`code\` and @x\n\`\`\`js fence\na \\\\\\\\\` b')
job = J()
with jobs.job_lock(P, 7):
    I.effect_reject(P, job, R, repo=REPO)
    jobs.write_job(P, job)
lines = body('issue-7-j1-5-2').split('\n')
print('reject scope %s' % ('Reason: see \\\\\`code\\\\\` and \`\`@x\`\`' in lines))
print('reject fence %s' % ('\\\\\`\\\\\`\\\\\`js fence' in lines))
print('reject backslash %s' % ('a \\\\\\\\\\\\\` b' in lines))
for ln in lines:
    print('reject line %r' % ln)
job = J()
job['reason'] = 'the \`x\` step failed'
with jobs.job_lock(P, 7):
    iid = I.effect_needs_human(P, job, repo=REPO, row='51b')
print('engine reason %s' % ('Reason: the \`x\` step failed' in body(iid).split('\n')))
"
e2e_expect_line "needs question True"
e2e_expect_line "needs template True"
e2e_expect_line "reject scope True"
e2e_expect_line "reject fence True"
e2e_expect_line "reject backslash True"
e2e_expect_line "engine reason True"
fi

# ---------------------------------------------------------------- FJ1, FJ2
# fj_start <name> — e2e_new with a claude stub that logs its arguments one per
# line to claude-argv.txt and answers with the e2e_judge_says reply, and a
# timeout stub that logs its first argument to timeout-args.log.
fj_start() {
  fe_new "$1"
  e2e_repo main
  cat > "$E2E_BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${E2E_DIR:?}/claude-argv.txt"
env > "$E2E_DIR/claude-env.txt"
pwd > "$E2E_DIR/claude-cwd.txt"
cat > "$E2E_DIR/claude-stdin.txt"
cat "$E2E_DIR/judge-response.json"
STUB
  cat > "$E2E_BIN/timeout" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${E2E_DIR:?}/timeout-args.log"
shift
exec "$@"
STUB
  chmod +x "$E2E_BIN/claude" "$E2E_BIN/timeout"
}
fj_judge() { _e2e_exec bash -c 'printf "%s" "the prompt" | "$@"' _ "$E2E_ACTIVE_PLUGIN/bin/flow-judge.sh" "$@"; }
fj_arg_after() { awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$E2E_DIR/claude-argv.txt" 2>/dev/null; }

if in_run FJ1; then
fj_start fj1-usage
e2e_describe "plan 2.5: for --judge intake the model comes from --model only and the timeout from --timeout-seconds only; a missing --model, an empty one, a missing --timeout-seconds, or one that is not a whole number of at least 1 exits 2 and starts no judge; goal and verdict refuse the two arguments (exit 2)"
for IN_ARGS in "--judge intake --timeout-seconds 60" "--judge intake --model claude-sonnet-4-6" \
    "--judge intake --model claude-sonnet-4-6 --timeout-seconds 0" "--judge intake --model claude-sonnet-4-6 --timeout-seconds -5" \
    "--judge intake --model claude-sonnet-4-6 --timeout-seconds abc" "--judge intake --model claude-sonnet-4-6 --timeout-seconds 1.5" \
    "--judge goal --model haiku" "--judge verdict --timeout-seconds 60"; do
  # shellcheck disable=SC2086
  fj_judge $IN_ARGS
  e2e_expect_equal 2 "$E2E_RC" "exit status of flow-judge.sh $IN_ARGS"
done
fj_judge --judge intake --model "" --timeout-seconds 60
e2e_expect_equal 2 "$E2E_RC" "exit status with an empty --model"
e2e_expect_equal no "$([ -f "$E2E_DIR/claude-argv.txt" ] && echo yes || echo no)" "a judge started"
fi

if in_run FJ2; then
fj_start fj2-intake-run
e2e_describe "plan 2.5 and design trust_and_untrusted_text L36: flow-judge.sh --judge intake --model claude-sonnet-4-6 --timeout-seconds 1800, with flow.goals.judge.model opus and timeoutSeconds 7 in the user file and verdict.model haiku in the project file, runs claude with --model claude-sonnet-4-6 (a full id), timeout(1) with 1800 (no 5-600 clamp), --disallowedTools '*', --json-schema of the intake output (decision ACCEPT, NEEDS_INFO, REJECT; the seven required keys), the body of agents/factory-intake.md as the system prompt, the prompt on stdin, in \$HOME/.claude/flow-goal-judge, and prints the CLI reply unchanged"
e2e_user_settings '{"flow":{"goals":{"judge":{"model":"opus","timeoutSeconds":7}}}}'
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"verdict":{"model":"haiku","timeoutSeconds":9}}' > "$E2E_REPO/.claude/settings.flow.json"
IN_REPLY='{"type":"result","is_error":false,"structured_output":'"$IN_ACCEPT"',"total_cost_usd":0.02}'
e2e_judge_says "$IN_REPLY"
fj_judge --judge intake --model claude-sonnet-4-6 --timeout-seconds 1800
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "$IN_REPLY" "$E2E_OUT" "stdout"
e2e_expect_equal claude-sonnet-4-6 "$(fj_arg_after --model)" "--model"
e2e_expect_equal 1800 "$(cat "$E2E_DIR/timeout-args.log" 2>/dev/null)" "timeout(1) argument"
e2e_expect_equal '*' "$(fj_arg_after --disallowedTools)" "--disallowedTools"
e2e_expect_equal json "$(fj_arg_after --output-format)" "--output-format"
e2e_expect_equal yes "$(grep -qxF -- --print "$E2E_DIR/claude-argv.txt" && echo yes || echo no)" "--print"
IN_SCHEMA=$(fj_arg_after --json-schema)
e2e_expect_equal '["ACCEPT","NEEDS_INFO","REJECT"]' "$(jq -c '.properties.decision.enum' <<<"$IN_SCHEMA" 2>/dev/null)" "schema decision enum"
e2e_expect_equal '["decision","proposed_criteria","questions","reason","risk","scope","surfaces"]' "$(jq -c '.required | sort' <<<"$IN_SCHEMA" 2>/dev/null)" "schema required keys"
IN_FIRST_BODY=$(awk 'NR == 1 && /^---/ { fm = 1; next } fm && /^---/ { fm = 0; next } fm { next } NF { print; exit }' "$E2E_PLUGIN_DIR/agents/factory-intake.md" 2>/dev/null)
e2e_expect_equal yes "$([ -n "$IN_FIRST_BODY" ] && grep -qxF -- "$IN_FIRST_BODY" "$E2E_DIR/claude-argv.txt" && echo yes || echo no)" "the system prompt holds the agent file's first body line"
e2e_expect_err_lacks "using the built-in judge prompt"
e2e_expect_equal "the prompt" "$(cat "$E2E_DIR/claude-stdin.txt")" "stdin"
e2e_expect_equal "$(cd "$E2E_HOME/.claude/flow-goal-judge" 2>/dev/null && pwd -P)" "$(cd "$(cat "$E2E_DIR/claude-cwd.txt")" && pwd -P)" "working directory"
fi

# ---------------------------------------------------------------- launcher
# li_seed — main checkout, probe record through fe_record_link (plan R101),
# factory enabled, job issue-7-j1 in intake with no clone or io folder (an
# intake job has none yet), its current directive IN_ID: an intake judge
# directive as 1a's create_directive writes one (session_id, prompt_template,
# timeout_seconds and allowed_tools null), and J/in-copies/issue.md. The
# timeout stand-in logs its first argument and, while timeout-124 exists
# beside it, exits 124 with no output; while timeout-hang exists it writes
# its pid to timeout-hang-pid and becomes `sleep 120`, ignoring its
# argument: a flow-judge.sh that hangs.
li_seed() {
  e2e_repo main
  fe_record_link "${IN_RECORD_EDITS:-}"
  fe_enable
  fe_job 7 intake "d['directive'] = '$IN_ID'; d['worktree'] = None; d['io_dir'] = None; d['vouch_at'] = '2026-11-16T00:00:00Z'
${1:-}"
  li_directive "$IN_ID"
  LI_F=$(fe_factory_dir)
  LI_J="$LI_F/jobs/issue-7"
  mkdir -p "$LI_J/in-copies"
  printf '%s\n' '<<<UNTRUSTED_ISSUE_TITLE>>>' '> Add a port setting' '<<<END_UNTRUSTED_ISSUE_TITLE>>>' \
    '<<<UNTRUSTED_ISSUE_BODY>>>' '> The service needs a port setting.' '<<<END_UNTRUSTED_ISSUE_BODY>>>' > "$LI_J/in-copies/issue.md"
  cat > "$E2E_BIN/timeout" <<'STUB'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
printf '%s\n' "$1" >> "$here/timeout-args.log"
[ -f "$here/timeout-124" ] && exit 124
if [ -f "$here/timeout-hang" ]; then
  printf '%s\n' "$$" > "$here/timeout-hang-pid"
  exec sleep 120
fi
shift
exec "$@"
STUB
  chmod +x "$E2E_BIN/timeout"
}
li_directive() {
  fe_directive "$1" "d['kind'] = 'judge'; d['session_id'] = None; d['prompt_template'] = None; d['timeout_seconds'] = None; d['allowed_tools'] = None"
}
# li_next <id> — another intake judge directive, made the job's current one.
li_next() {
  li_directive "$1"
  jq --arg d "$1" '.directive = $d' "$LI_J/job.json" > "$LI_J/job.json.t" && mv "$LI_J/job.json.t" "$LI_J/job.json"
}
li_launch() { e2e_run_bin "$@" bin/flow-factory.sh launch "${LI_LAUNCH_ID:-$IN_ID}"; }
li_wait() {
  local id="${1:-$IN_ID}" lp
  fe_wait_for 60 "[ -f '$LI_J/results/$id.json' ]" || return 1
  lp=$(jq -r '.launcher_pid // empty' "$LI_J/directives/$id.lease.json" 2>/dev/null)
  [ -n "$lp" ] && fe_wait_for 10 "! kill -0 $lp 2>/dev/null"
  fe_art_state 7
}
li_jq() { jq -r "$2" "$1" 2>/dev/null; }
li_arg_after() { awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }' "$E2E_BIN/claude-argv-$1.txt" 2>/dev/null; }
li_env_has() { grep -q "^$2=" "$E2E_BIN/claude-env-$1.txt" 2>/dev/null && echo yes || echo no; }
li_env_value() { sed -n "s/^$2=//p" "$E2E_BIN/claude-env-$1.txt" 2>/dev/null | head -n 1; }
li_launches() { if [ -f "$E2E_BIN/claude-launches.log" ]; then wc -l < "$E2E_BIN/claude-launches.log" | tr -d ' '; else echo 0; fi; }
li_pending() { cat "$LI_J"/pending/*.json 2>/dev/null | jq -r -s 'map(.event) | join(",")'; }
li_result_valid() {
  fe_py "import json, _flow_factory_jobs as jobs, _flow_factory_schema as schema
print(schema.validate(json.load(open('$LI_J/results/$1.json')), jobs.DIRECTIVE_SCHEMA, 'result'))"
  printf '%s' "$E2E_OUT"
}

if in_run LI1; then
fe_new li1-launch-accept
e2e_describe "R93's launcher half, R22, AC2: launch of an intake judge directive with session_id null prints LAUNCHED (not kind_not_built or directive_unknown); the stand-in sees --model equal to the probe record's platform model M (judges.intakeModel unset in the user file and haiku in the project file, which the judge ignores: plan 2.5 reads it user-only; worker.model cannot differ from the record's model here, since the launch gate then reports the platform stale), --disallowedTools then '*', --json-schema of the intake output; its stdin equals issue.md + the fact sheet fence of plan 5.3 built by hand; after the run the result has outcome completed, event null, judge equal to the fe_judge_says object, and validates against \$defs.result; one pending judge_accept; the lease kind is judge; the job is charged 0.01 under intake with basis first_total and no session"
IN_RECORD_EDITS="d['groups']['platform']['keyed_on']['model'] = 'claude-model-m-1'"
li_seed
IN_RECORD_EDITS=""
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"factory":{"judges":{"intakeModel":"haiku"}}}}' > "$E2E_REPO/.claude/settings.flow.json"
fe_judge_says "$IN_ACCEPT"
li_launch
e2e_expect_line "LAUNCHED directive=$IN_ID"
e2e_expect_equal 0 "$E2E_RC" "launch exit status"
li_wait
e2e_expect_equal 1 "$(li_launches)" "claude launches"
e2e_expect_equal claude-model-m-1 "$(li_arg_after 1 --model)" "--model"
e2e_expect_equal '*' "$(li_arg_after 1 --disallowedTools)" "--disallowedTools"
e2e_expect_equal '["ACCEPT","NEEDS_INFO","REJECT"]' "$(li_arg_after 1 --json-schema | jq -c '.properties.decision.enum' 2>/dev/null)" "--json-schema decision enum"
printf '%s' '{"intake_round": 0, "issue": 7, "job": "issue-7-j1", "labels": [], "open_questions": [], "vouch_at": "2026-11-16T00:00:00Z"}' > "$E2E_DIR/sheet.json"
{ cat "$LI_J/in-copies/issue.md"; printf '\n<<<ENGINE_FACT_SHEET>>>\n'; cat "$E2E_DIR/sheet.json"; printf '\n<<<END_ENGINE_FACT_SHEET>>>\n'; } > "$E2E_DIR/want-stdin"
e2e_expect_equal yes "$(cmp -s "$E2E_DIR/want-stdin" "$E2E_BIN/claude-stdin-1.txt" && echo yes || echo no)" "judge stdin is intake_stdin(issue.md, fact sheet)"
IN_R="$LI_J/results/$IN_ID.json"
e2e_expect_equal completed "$(li_jq "$IN_R" .outcome)" "outcome"
e2e_expect_equal null "$(li_jq "$IN_R" .event)" "result event"
e2e_expect_equal "$(jq -cS . <<<"$IN_ACCEPT")" "$(jq -cS .judge "$IN_R")" "result judge"
e2e_expect_equal "[]" "$(li_result_valid "$IN_ID")" "result validates"
e2e_expect_equal judge_accept "$(li_pending)" "pending events"
e2e_expect_equal judge "$(li_jq "$LI_J/directives/$IN_ID.lease.json" .kind)" "lease kind"
e2e_expect_equal claude-model-m-1 "$(li_jq "$LI_J/directives/$IN_ID.json" .model)" "directive model"
e2e_expect_equal 1 "$(jq -r '.cost.usd_total * 100 | round' "$LI_J/job.json")" "job cost in cents"
e2e_expect_equal 1 "$(jq -r '.cost.stage_usd.intake * 100 | round' "$LI_J/job.json")" "intake cost in cents"
e2e_expect_equal "first_total null" "$(jq -r '.cost.runs[0] | "\(.basis) \(.session_id)"' "$LI_J/job.json")" "charged run"
e2e_expect_equal "{}" "$(jq -c '.sessions' "$LI_J/job.json")" "job sessions"
e2e_expect_equal 0 "$(grep -c 'kind_not_built\|directive_unknown' "$LI_J/events.jsonl")" "refusal events"
fi

if in_run LI2; then
fe_new li2-model-and-cost
e2e_describe "R22 and R23: with flow.factory.judges.intakeModel claude-sonnet-4-6 in the user file, the judge gets --model claude-sonnet-4-6; a reply written with fe_judge_says --cost 0.12 charges the job 0.12; a malformed reply (an envelope with total_cost_usd 0.05 and no structured_output) gives a stage_failed result with outcome error, no judge key, that validates, and charges 0.05 more"
li_seed
e2e_user_settings '{"flow":{"factory":{"enabled":true,"judges":{"intakeModel":"claude-sonnet-4-6"}}}}'
fe_judge_says --cost 0.12 "$IN_NEEDS"
li_launch
li_wait
e2e_expect_equal claude-sonnet-4-6 "$(li_arg_after 1 --model)" "--model"
e2e_expect_equal 12 "$(jq -r '.cost.usd_total * 100 | round' "$LI_J/job.json")" "job cost in cents after the first reply"
e2e_expect_equal judge_needs_info "$(li_pending)" "pending events after the first reply"
li_next issue-7-j1-intake-2
fe_judge_raw "$(head -n 1 "$E2E_BIN/judge-result")" '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.05}'
LI_LAUNCH_ID=issue-7-j1-intake-2 li_launch
li_wait issue-7-j1-intake-2
IN_R="$LI_J/results/issue-7-j1-intake-2.json"
e2e_expect_equal "error stage_failed false" "$(jq -r '"\(.outcome) \(.event) \(has("judge"))"' "$IN_R")" "malformed result"
e2e_expect_equal "[]" "$(li_result_valid issue-7-j1-intake-2)" "malformed result validates"
e2e_expect_equal 17 "$(jq -r '.cost.usd_total * 100 | round' "$LI_J/job.json")" "job cost in cents after the malformed reply"
e2e_expect_equal 2 "$(li_launches)" "claude launches"
fi

if in_run LI3; then
fe_new li3-malformed
e2e_describe "AC4's malformed forms (plan 5.3 'Judge reply', R20), one launch each: not JSON, is_error true, no structured_output, a structured_output that is not an object, decision MAYBE, ACCEPT with no criteria, NEEDS_INFO with no questions; each result is outcome error, event stage_failed, with no judge key, and each pending event is stage_failed"
li_seed
IN_ENV='{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"structured_output":'
fe_judge_raw 'this is not json' \
  '{"type":"result","is_error":true,"total_cost_usd":0.01,"structured_output":'"$IN_ACCEPT"'}' \
  '{"type":"result","is_error":false,"total_cost_usd":0.01}' \
  "$IN_ENV\"ACCEPT\"}" \
  "$IN_ENV$(jq -c '.decision = "MAYBE"' <<<"$IN_ACCEPT")}" \
  "$IN_ENV$(jq -c '.proposed_criteria = []' <<<"$IN_ACCEPT")}" \
  "$IN_ENV$(jq -c '.questions = []' <<<"$IN_NEEDS")}"
for IN_K in 1 2 3 4 5 6 7; do
  IN_D="issue-7-j1-intake-$IN_K"
  [ "$IN_K" = 1 ] || li_next "$IN_D"
  LI_LAUNCH_ID="$IN_D" li_launch
  e2e_expect_line "LAUNCHED directive=$IN_D"
  li_wait "$IN_D"
  e2e_expect_equal "error stage_failed false" "$(jq -r '"\(.outcome) \(.event) \(has("judge"))"' "$LI_J/results/$IN_D.json")" "result of malformed reply $IN_K"
done
e2e_expect_equal 7 "$(li_launches)" "claude launches"
e2e_expect_equal "stage_failed,stage_failed,stage_failed,stage_failed,stage_failed,stage_failed,stage_failed" "$(li_pending)" "pending events"
fi

if in_run LI4; then
fe_new li4-timeout-env
e2e_describe "R101: with no timeout key in the user file the timeout stand-in gets 1800 (settings.json's flow.factory.worker.stages.intake.timeoutSeconds); with 900 in the user file it gets 900. The judge runs although the launcher's own environment has CLAUDE_HOOK_GOAL_JUDGE_MODE=true (flow-judge.sh refuses inside a judge), with HOME the scratch HOME, no FLOW_FACTORY_JOB or FLOW_FACTORY_IO, the probe record's interpreter folder first on PATH, the judge folder under the scratch HOME. A timeout stand-in that exits 124 with no output gives a stage_failed result with no judge"
li_seed
fe_judge_says "$IN_ACCEPT" "$IN_ACCEPT" "$IN_ACCEPT"
li_launch CLAUDE_HOOK_GOAL_JUDGE_MODE=true FLOW_FACTORY_JOB=issue-1-j1
e2e_expect_line "LAUNCHED directive=$IN_ID"
li_wait
e2e_expect_equal 1800 "$(sed -n 1p "$E2E_BIN/timeout-args.log" 2>/dev/null)" "timeout argument with no key"
e2e_expect_equal 1 "$(li_launches)" "claude launches"
e2e_expect_equal "$E2E_HOME" "$(li_env_value 1 HOME)" "judge HOME"
e2e_expect_equal no "$(li_env_has 1 FLOW_FACTORY_JOB)" "judge has FLOW_FACTORY_JOB"
e2e_expect_equal no "$(li_env_has 1 FLOW_FACTORY_IO)" "judge has FLOW_FACTORY_IO"
e2e_expect_equal "$E2E_DIR/py" "$(li_env_value 1 PATH | cut -d: -f1)" "first PATH folder"
e2e_expect_equal yes "$([ -d "$E2E_HOME/.claude/flow-goal-judge" ] && echo yes || echo no)" "judge folder under the scratch HOME"
e2e_expect_equal judge_accept "$(li_pending)" "pending events"
li_next issue-7-j1-intake-2
e2e_user_settings '{"flow":{"factory":{"enabled":true,"worker":{"stages":{"intake":{"timeoutSeconds":900}}}}}}'
LI_LAUNCH_ID=issue-7-j1-intake-2 li_launch
li_wait issue-7-j1-intake-2
e2e_expect_equal 900 "$(sed -n 2p "$E2E_BIN/timeout-args.log" 2>/dev/null)" "timeout argument with 900 in the user file"
li_next issue-7-j1-intake-3
: > "$E2E_BIN/timeout-124"
LI_LAUNCH_ID=issue-7-j1-intake-3 li_launch
li_wait issue-7-j1-intake-3
e2e_expect_equal 2 "$(li_launches)" "claude launches after the 124 run"
e2e_expect_equal "error stage_failed false" "$(jq -r '"\(.outcome) \(.event) \(has("judge"))"' "$LI_J/results/issue-7-j1-intake-3.json")" "result of the timed-out judge"
fi

if in_run LI5; then
fe_new li5-worker-after-judge
e2e_describe "R24 (design execution_model L112): a worker launched after an intake judge of the same job has no CLAUDE_HOOK_GOAL_JUDGE_MODE, while the judge's own claude had it set to true by flow-judge.sh"
e2e_repo main
fe_record_link
fe_enable
fe_job 7 build "d['directive'] = '$IN_ID'"
fe_job_clone 7
li_directive "$IN_ID"
LI_F=$(fe_factory_dir)
LI_J="$LI_F/jobs/issue-7"
mkdir -p "$LI_J/in-copies"
printf '%s\n' '<<<UNTRUSTED_ISSUE_TITLE>>>' '> x' '<<<END_UNTRUSTED_ISSUE_TITLE>>>' > "$LI_J/in-copies/issue.md"
e2e_plugin_copy templates/factory/build.prompt.md 'RUN: true'
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.05}'
fe_judge_says "$IN_ACCEPT"
li_launch
li_wait
fe_directive issue-7-j1-build-1
jq '.directive = "issue-7-j1-build-1"' "$LI_J/job.json" > "$LI_J/job.json.t" && mv "$LI_J/job.json.t" "$LI_J/job.json"
LI_LAUNCH_ID=issue-7-j1-build-1 li_launch
e2e_expect_line "LAUNCHED directive=issue-7-j1-build-1"
li_wait issue-7-j1-build-1
e2e_expect_equal true "$(li_env_value 1 CLAUDE_HOOK_GOAL_JUDGE_MODE)" "the judge's CLAUDE_HOOK_GOAL_JUDGE_MODE"
e2e_expect_equal no "$(li_env_has 2 CLAUDE_HOOK_GOAL_JUDGE_MODE)" "the worker has CLAUDE_HOOK_GOAL_JUDGE_MODE"
e2e_expect_equal stream-json "$(li_arg_after 2 --output-format)" "the second launch is the worker"
fi

if in_run LI6; then
fe_new li6-no-issue-md
e2e_describe "T:66i writes in/issue.md before the launch (design stages L39): an intake judge directive whose job has no J/in-copies/issue.md is refused with issue_md_missing (exit 5), a launch_not_started event names it, the directive is not claimed, and no judge starts"
li_seed
rm -f "$LI_J/in-copies/issue.md"
fe_judge_says "$IN_ACCEPT"
li_launch
e2e_expect_line "FACTORY_REFUSED=issue_md_missing directive=$IN_ID"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal null "$(li_jq "$LI_J/directives/$IN_ID.json" .started_at)" "started_at"
e2e_expect_equal 1 "$(jq -c 'select(.type == "launch_not_started" and .reason == "issue_md_missing")' "$LI_J/events.jsonl" | wc -l | tr -d ' ')" "launch_not_started events"
e2e_expect_equal 0 "$(li_launches)" "claude launches"
fi

if in_run LI7; then
fe_new li7-reply-over-cap
e2e_describe "a reply over 4 MiB is malformed (decision journal, launcher: 'A reply over 4 MiB is malformed and its cost is not charged') and plan 5.3 'Judge reply' maps any stdout that is not a usable reply to stage_failed: a reply that is a valid ACCEPT envelope padded with 4194400 spaces inside the object (so jq still reads it as an ACCEPT) gives outcome error, event stage_failed, no judge key, a result that validates, and one pending stage_failed"
li_seed
{ printf '%s' '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,'
  head -c 4194400 /dev/zero | tr '\0' ' '
  printf '"structured_output":%s}\n' "$IN_ACCEPT"; } > "$E2E_BIN/judge-result"
printf 'judge reply (written by hand): an ACCEPT envelope with 4194400 spaces after "total_cost_usd":0.01,\n' | _e2e_art
li_launch
e2e_expect_line "LAUNCHED directive=$IN_ID"
# li_wait without its state dump: fe_art_state would pass the 4 MiB reply
# file through the artifact's masking, which takes minutes on one line.
fe_wait_for 60 "[ -f '$LI_J/results/$IN_ID.json' ]"
IN_LP=$(jq -r '.launcher_pid // empty' "$LI_J/directives/$IN_ID.lease.json" 2>/dev/null)
[ -n "$IN_LP" ] && fe_wait_for 10 "! kill -0 $IN_LP 2>/dev/null"
IN_RP="$LI_J/results/$IN_ID.reply.json"
IN_RP_SIZE=$(wc -c < "$IN_RP" 2>/dev/null | tr -d ' ')
e2e_expect_equal yes "$([ "${IN_RP_SIZE:-0}" -gt 4194304 ] && echo yes || echo no)" "the kept reply is over 4 MiB"
e2e_expect_equal ACCEPT "$(jq -r .structured_output.decision "$IN_RP" 2>/dev/null)" "the kept reply is a valid ACCEPT envelope"
printf 'replaced after the two checks above so the state dump stays small: a %s-byte reply\n' "${IN_RP_SIZE:-0}" > "$IN_RP"
fe_art_state 7
IN_R="$LI_J/results/$IN_ID.json"
e2e_expect_equal "error stage_failed false" "$(jq -r '"\(.outcome) \(.event) \(has("judge"))"' "$IN_R" 2>/dev/null)" "result of the oversized reply"
e2e_expect_equal "[]" "$(li_result_valid "$IN_ID")" "result validates"
e2e_expect_equal stage_failed "$(li_pending)" "pending events"
e2e_expect_equal 1 "$(li_launches)" "claude launches"
fi

if in_run LI8; then
fe_new li8-hung-judge
e2e_describe "plan B11 step 2 and the table row 'flow-judge.sh hangs past the launcher's limit (the intake timeout plus 60 s)': with timeoutSeconds 1 in the user file and a plugin copy whose JUDGE_MARGIN_SECONDS is 1 (so the limit is 2 s rather than 61 s), a flow-judge.sh whose timeout(1) ignores its argument and hangs is stopped by the launcher at 2 s: SIGTERM to the group, the hung process gone, outcome timeout (finish_judge: 'timeout when the launcher's own limit fired'), event stage_failed, no judge key, a result that validates, one pending stage_failed, and no claude launch"
li_seed
E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" || _flow_assert_fail "$E2E_NAME: cannot copy the plugin"
sed 's/^JUDGE_MARGIN_SECONDS = 60$/JUDGE_MARGIN_SECONDS = 1/' "$E2E_PLUGIN_DIR/bin/_flow_factory_launch.py" > "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_launch.py"
printf 'plugin for this scenario: a copy with JUDGE_MARGIN_SECONDS = 60 changed to 1 in bin/_flow_factory_launch.py\n' | _e2e_art
e2e_expect_equal 1 "$(grep -c '^JUDGE_MARGIN_SECONDS = 1$' "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_launch.py")" "the copy's margin is 1"
e2e_user_settings '{"flow":{"factory":{"enabled":true,"worker":{"stages":{"intake":{"timeoutSeconds":1}}}}}}'
fe_judge_says "$IN_ACCEPT"
: > "$E2E_BIN/timeout-hang"
li_launch
e2e_expect_line "LAUNCHED directive=$IN_ID"
li_wait
IN_HANG=$(cat "$E2E_BIN/timeout-hang-pid" 2>/dev/null)
e2e_expect_equal yes "$([ -n "$IN_HANG" ] && echo yes || echo no)" "the hung timeout(1) started"
e2e_expect_equal gone "$( [ -n "$IN_HANG" ] && kill -0 "$IN_HANG" 2>/dev/null && echo running || echo gone)" "the hung process after the run"
e2e_expect_equal 1 "$(sed -n 1p "$E2E_BIN/timeout-args.log" 2>/dev/null)" "timeout argument"
e2e_expect_equal 1 "$(grep -c 'stage timeout after 2 s' "$LI_J/results/$IN_ID.launcher.log" 2>/dev/null)" "launcher log: its own limit of 2 s fired"
IN_R="$LI_J/results/$IN_ID.json"
e2e_expect_equal "timeout stage_failed false" "$(jq -r '"\(.outcome) \(.event) \(has("judge"))"' "$IN_R" 2>/dev/null)" "result of the hung judge"
e2e_expect_equal "[]" "$(li_result_valid "$IN_ID")" "result validates"
e2e_expect_equal stage_failed "$(li_pending)" "pending events"
e2e_expect_equal 0 "$(li_launches)" "claude launches"
# Leave nothing running when an expectation above failed.
if [ -n "$IN_HANG" ]; then kill "$IN_HANG" 2>/dev/null || true; fi
rm -f "$E2E_BIN/timeout-hang"
fi

if in_run LI9; then
fe_new li9-reply-read-capped
e2e_describe "the launcher reads at most JUDGE_REPLY_LIMIT + 1 (4194305) bytes of a judge reply (decision journal, launcher: 'A reply over 4 MiB is malformed ... because the reply is not read'): the judge's timeout(1) stand-in replaces the reply file with a named pipe and leaves a writer behind in a session of its own, which offers 16 MiB (16777216 bytes) once the launcher opens the pipe; the launcher closes the pipe after its capped read, so the writer's next write fails with a broken pipe after at least 4128769 and at most 5242881 counted bytes (bounds from the cap of 4194305 bytes, not design values: the bytes of the one 64 KiB write the broken pipe cut short are not counted, so the floor is the cap less 64 KiB, and the ceiling is the cap plus 1 MiB of room for the pipe's own buffer, 64 KiB on macOS and Linux by default), never all 16 MiB; the result is still outcome error, event stage_failed, no judge key"
li_seed
IN_FIFO="$LI_J/results/$IN_ID.reply.json"
printf '%s\n' "$IN_FIFO" > "$E2E_BIN/li9-fifo-path"
cat > "$E2E_BIN/li9-fifo-writer.py" <<'PY'
import errno, os, signal, sys, time
path, here = sys.argv[1], sys.argv[2]
def note(name, text):
    t = os.path.join(here, name + '.t')
    with open(t, 'w') as f:
        f.write(text)
    os.replace(t, os.path.join(here, name))
os.unlink(path)
os.mkfifo(path, 0o600)
# Leave the judge's process group, so the launcher sees the judge end.
if os.fork():
    os._exit(0)
os.setsid()
if os.fork():
    os._exit(0)
null = os.open(os.devnull, os.O_RDWR)
for fd in (0, 1, 2):
    os.dup2(null, fd)
signal.alarm(90)
note('li9-writer-pid', str(os.getpid()))
end = time.monotonic() + 60
while True:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
        break
    except OSError as e:
        if e.errno != errno.ENXIO or time.monotonic() > end:
            note('li9-writer.txt', 'no reader')
            sys.exit(1)
        time.sleep(0.05)
os.set_blocking(fd, True)
chunk = b' ' * 65536
total = 16 * 1024 * 1024
n = 0
try:
    while n < total:
        n += os.write(fd, chunk[:total - n])
    os.close(fd)
    note('li9-writer.txt', 'EOF %d' % n)
except BrokenPipeError:
    note('li9-writer.txt', 'EPIPE %d' % n)
PY
cat > "$E2E_BIN/timeout" <<'STUB'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
printf '%s\n' "$1" >> "$here/timeout-args.log"
exec "$(cat "$here/fe-gh-python")" -I "$here/li9-fifo-writer.py" "$(cat "$here/li9-fifo-path")" "$here"
STUB
chmod +x "$E2E_BIN/timeout"
printf 'judge stand-in: timeout(1) replaced by li9-fifo-writer.py, which makes the reply file a named pipe and offers 16777216 spaces through it\n' | _e2e_art
li_launch
e2e_expect_line "LAUNCHED directive=$IN_ID"
fe_wait_for 60 "[ -f '$E2E_BIN/li9-writer.txt' ]"
li_wait
IN_W=$(cat "$E2E_BIN/li9-writer.txt" 2>/dev/null)
printf 'writer: %s\n' "$IN_W" | _e2e_art
IN_WN=${IN_W#* }
case "$IN_WN" in ''|*[!0-9]*) IN_WN=0 ;; esac
e2e_expect_equal EPIPE "${IN_W%% *}" "how the writer ended (EOF means the launcher read all 16 MiB)"
e2e_expect_equal yes "$([ "$IN_WN" -ge 4128769 ] && [ "$IN_WN" -le 5242881 ] && echo yes || echo no)" "bytes the writer counted ($IN_WN) lie in 4128769..5242881"
IN_R="$LI_J/results/$IN_ID.json"
e2e_expect_equal "error stage_failed false" "$(jq -r '"\(.outcome) \(.event) \(has("judge"))"' "$IN_R" 2>/dev/null)" "result of the oversized reply"
e2e_expect_equal stage_failed "$(li_pending)" "pending events"
# Leave nothing running when an expectation above failed: the writer, and a
# launcher still waiting to open the pipe.
IN_WP=$(cat "$E2E_BIN/li9-writer-pid" 2>/dev/null)
if [ -n "$IN_WP" ]; then kill "$IN_WP" 2>/dev/null || true; fi
IN_LP=$(jq -r '.launcher_pid // empty' "$LI_J/directives/$IN_ID.lease.json" 2>/dev/null)
if [ -n "$IN_LP" ]; then kill "$IN_LP" 2>/dev/null || true; fi
rm -f "$IN_FIFO"
fi
