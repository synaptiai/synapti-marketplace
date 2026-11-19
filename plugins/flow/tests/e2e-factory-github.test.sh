# shellcheck shell=bash
# The factory engine's GitHub writes (bin/_flow_factory_github.py) and its
# breadcrumb script (bin/flow-tier-crumb.sh), run in isolation through fe_py
# against the stateful gh stand-in (tests/fixtures/factory/engine/gh with a
# world file). The rows that make these writes through `next` are added by a
# later task (plan B14).
#
# Every write follows design stages L7-L11: look first, record, resolve the
# tier key, run. Ways it can be wrong, written down before the code:
#   GH1  (2.2) the intent id is not issue-N-j<seq>-<row>-<k>, the note word
#        is missing for a write no row makes, the body file does not start
#        with the engine marker naming that id, the item does not validate
#        against the outbox schema, or the intent_recorded line is missing or
#        carries another hash than sha256(argv joined by NUL, NUL, body)
#   GH2  (R25) k comes from write_seq alone, so after a rebuild that reset it
#        an earlier item's id is reused; or a body file in the outbox is
#        taken for an item when k is counted
#   GH3  (2.2 dedupe) a second intent answering the same comment, with the
#        same kind and row, is recorded again; or intents with no comment are
#        merged
#   GH4  (5.3) an outbox folder or events file that cannot be written is
#        reported as anything but outbox_unwritable, or leaves an item behind
#        that has no intent_recorded line
#   GH5  (R38) cleaning misses CRLF, a leading-space /flow-factory line, a
#        marker in the model text, an @mention (one after a full stop
#        included), or the 60,000 cap; or it puts backticks inside a code
#        span, which closes the span and leaves the mention live
#   GH6  (R75) a blocking write whose keys are all journal is never run, or
#        leaves one breadcrumb instead of one per key
#   GH7  a blocking write whose key is confirm is run, or becomes
#        pending_confirm (only notices do)
#   GH8  (Q12, B6 step 7) each tier value on one notice: autonomous leaves a
#        breadcrumb, journal leaves none, confirm posts; a pending_confirm
#        notice is not sent once the key changes, or is sent after the job
#        left its state
#   GH9  (5.2) a failed POST marks the item sent, or the retry posts twice
#   GH10 (R34, AC10) a write whose POST succeeded but whose process died
#        before the effect was recorded is posted again
#   GH11 (R35) the lookup reads only the first page of comments
#   GH12 (R10) a marker posted by another login, or by a deleted account,
#        counts as the engine's post; no engine login still runs writes
#   GH13 (R30, R31) the hash covers the argv only, is compared with the
#        item's own sha256 field, or an item with no intent_recorded line runs;
#        the hash is of the file body_file names while gh posts the file the
#        argv names, or of a body file that is a symbolic link
#   GH14 (R68, R74) the drain runs or looks up the pending intent; run_literal
#        runs an item that is not the pending intent, or runs without
#        looking first
#   GH15 run_literal does not run a pending intent whose effect is absent, or
#        leaves no breadcrumb for its journal keys
#   GH16 (R33) the literal runs through a shell, or gh is found on PATH
#        instead of the gh_real the caller passes; the write runs with the
#        session's FLOW_TIER_* variables, or with gh's prompts on
#   GH17 (R74, 2.2) pr_close records something for a job with no PR; on a
#        terminal job an item of another state is still sent; a closed PR is
#        closed again
#   GH18 (Q16) a confirmed notice waits for its confirm key, or runs without
#        the hash check
#   GH19 label_add and label_remove run when the label is already there (or
#        already gone)
#   GH20 lookup reports a failed read as "not found", which would make the
#        drain post twice
#   GH21 the P9 probe intent is not probe-p9-<n>, or is recorded outside the
#        probe folder
#   GH23 a file in the outbox whose id is not its name, or that is not an
#        item at all, is run or stops the drain
#   GH24 (3.2) the drain makes gh calls after the pass's time is spent, or
#        stops without a line that says so
#   GH25 the drain or run_literal decides from an item field (status, key,
#        blocking, row, ref, kind, state_at_write) that was edited after the
#        intent was recorded; a blocking item, or one with no intent_confirmed
#        line, runs as confirmed
#   GH26 lookup reports the effect of an item whose argv was edited
#   GH27 a process that dies between the record and the item leaves an item
#        with no record, which blocks the same write for ever
#   GH28 an item file or the outbox folder that is a symbolic link is run
#   GH29 a write found by the look-first step leaves a breadcrumb although
#        nothing ran
#   GH22 (design new_files L11) the breadcrumb goes to the trail of the
#        branch the main checkout has checked out instead of issue N's; a
#        repository with no journal folder gets one
#
# Every expected value is written out by hand from the plan or design line
# named in each scenario's description; none comes from the module.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# gw_start <name> <state> [python statements for fe_job] — a scenario with a
# scratch repository, the world (engine login flow-e2e-engine, repository
# flow-e2e/scratch, open issue 7), the probe record (which makes F) and job
# issue-7-j1 in <state>.
gw_start() {
  fe_new "$1"
  e2e_repo main
  fe_world_new flow-e2e-engine flow-e2e/scratch
  fe_record
  fe_world_issue 7 "Add a port setting" "The service needs a port setting."
  fe_job 7 "$2" "${3:-}"
}

# gw_journal — commit a .decisions/ folder in the scratch repository, so the
# breadcrumbs have a journal folder to go to (lib/tier-trail.sh writes only
# where one exists).
gw_journal() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    mkdir -p .decisions
    printf '# journal\n' > .decisions/README.md
    git add .decisions/README.md && git commit -q -m journal
  ) || _e2e_result fail "gw_journal committed .decisions/"
  printf 'committed .decisions/README.md\n' | _e2e_art
}

# gw_trail — print every breadcrumb line of issue 7's trail files.
gw_trail() { cat "$E2E_REPO"/.decisions/auto-log/issue-7.*.md 2>/dev/null | grep -c 'auto-log: '; }

# The Python every scenario starts with.
read -r -d '' GW_PRE <<'PY' || true
import sys
sys.dont_write_bytecode = True
import hashlib, json, os
import _flow_factory as ff
import _flow_factory_jobs as jobs
import _flow_factory_schema as schema
import _flow_factory_github as G
P = jobs.resolve()
REPO = 'flow-e2e/scratch'
SCHEMA = os.path.join(ff.PLUGIN_ROOT, 'schemas', 'v1', 'factory-outbox.schema.json')
JD = os.path.join(P.fdir, 'jobs', 'issue-7')
OUT = os.path.join(JD, 'outbox')
GH = ff.which_real('gh')
BIN = os.path.dirname(GH)
LOGIN = 'flow-e2e-engine'
LABEL = 'flow:in-progress'
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
def put(item):
    with open(os.path.join(OUT, item['id'] + '.json'), 'w', encoding='utf-8') as fh:
        json.dump(item, fh)
def check(i):
    it = items()[i]
    print('valid %s %s' % (i, schema.validate(it, SCHEMA)))
    return it
def events(t=None, path=None):
    out = []
    try:
        with open(path or os.path.join(JD, 'events.jsonl'), encoding='utf-8') as fh:
            for ln in fh:
                d = json.loads(ln)
                if t is None or d.get('type') == t:
                    out.append(d)
    except OSError:
        pass
    return out
def world():
    with open(os.environ['FE_WORLD'], encoding='utf-8') as fh:
        return json.load(fh)
def posts():
    return world()['posts']
def tiers(**values):
    return lambda key: values.get(key, 'journal')
def want(argv, body):
    # plan 2.2: sha256 over the argv elements joined by NUL, a NUL, then the body bytes.
    return hashlib.sha256(b'\0'.join(a.encode('utf-8') for a in argv) + b'\0' + body).hexdigest()
def body_of(it):
    with open(os.path.join(OUT, it['body_file']), 'rb') as fh:
        return fh.read()
def record(job, row, kind, argv, body, key, blocking, ref=None, state=None):
    with jobs.job_lock(P, 7):
        return G.record_job_intent(P, job, row, kind, argv, body, key, blocking, ref=ref, state=state)
def drain(job, t, login=LOGIN, gh=None):
    with jobs.job_lock(P, 7):
        lines = G.drain(P, job, gh or GH, t, login)
    for ln in lines:
        print('line ' + ln)
    print('lines %d' % len(lines))
    return lines
PY

gw_py() { fe_py "$GW_PRE
$1"; }

_flow_test_begin "factory github: a comment intent's id, body file, item and record (GH1)"
gw_start gh1-record needs_info
e2e_describe "plan 2.2 and 5.3: the first intent of job issue-7-j1 by row 4 gets id issue-7-j1-4-1 and k 1 (write_seq absent, outbox empty); the body file starts with the engine marker <!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 --> (design stages L8, 5.3 Engine marker) as its only first line; the literal is gh api --method POST repos/O/R/issues/7/comments -F body=@<body file> (design stages L13); the item validates against factory-outbox.schema.json with job issue-7-j1, row 4, state_at_write the job's state needs_info, ref null, kind comment, blocking false, key [issueUpdate], status recorded, effect null; one intent_recorded line whose sha256 is the plan 2.2 hash over the argv and the body bytes, computed here with hashlib; nothing posted. A row 6 intent with state prepare gets k 2 and state_at_write prepare; a note intent gets issue-7-j1-note-3 with row null"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
print('id %s' % i)
it = check(i)
print('fields %s %s %s %s %s %s %s %s %s' % (it['job'], it['row'], it['state_at_write'], it['ref'], it['kind'],
      it['blocking'], it['key'], it['status'], it['effect']))
print('body_file %s' % it['body_file'])
body = body_of(it)
print('body %s' % body.decode('utf-8').split('\n'))
argv = it['argv']
print('argv %s' % argv[:5])
print('argv body %s' % (argv[5:] == ['-F', 'body=@' + os.path.join(OUT, it['body_file'])]))
rec = events('intent_recorded')
print('record %d %s %s %s %s' % (len(rec), rec[0]['id'] == i, rec[0]['row'], rec[0]['kind'], rec[0]['job']))
print('record hash %s' % (rec[0]['sha256'] == want(argv, body)))
print('item hash %s' % (it['sha256'] == want(argv, body)))
print('digest %s' % (G.intent_digest(argv, body) == want(argv, body)))
print('write_seq %s' % job.get('write_seq'))
i6 = record(job, '6', 'comment', G.literal_comment(REPO, 7), 'Accepted.', ['issueUpdate'], False, state='prepare')
it6 = check(i6)
print('row6 %s %s' % (i6, it6['state_at_write']))
iN = record(job, 'note', 'comment', G.literal_comment(REPO, 7), 'Not run.', ['issueUpdate'], False, ref=40)
itN = check(iN)
print('note %s %s %s %s' % (iN, itN['row'], itN['state_at_write'], itN['ref']))
print('posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "id issue-7-j1-4-1"
e2e_expect_line "valid issue-7-j1-4-1 []"
e2e_expect_line "fields issue-7-j1 4 needs_info None comment False ['issueUpdate'] recorded None"
e2e_expect_line "body_file issue-7-j1-4-1.body.md"
e2e_expect_line "body ['<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->', 'Please answer NI-1.']"
e2e_expect_line "argv ['gh', 'api', '--method', 'POST', 'repos/flow-e2e/scratch/issues/7/comments']"
e2e_expect_line "argv body True"
e2e_expect_line "record 1 True 4 comment issue-7-j1"
e2e_expect_line "record hash True"
e2e_expect_line "item hash True"
e2e_expect_line "digest True"
e2e_expect_line "write_seq 1"
e2e_expect_line "valid issue-7-j1-6-2 []"
e2e_expect_line "row6 issue-7-j1-6-2 prepare"
e2e_expect_line "valid issue-7-j1-note-3 []"
e2e_expect_line "note issue-7-j1-note-3 None needs_info 40"
e2e_expect_line "posts 0"

_flow_test_begin "factory github: k counts the outbox items as well as write_seq (GH2, R25)"
gw_start gh2-counter needs_info "d['write_seq'] = 0"
e2e_describe "plan 2.2: k = 1 + the larger of job.json write_seq and the largest k among the item ids in J/outbox. After a rebuild that reset write_seq to 0, with item issue-7-j1-4-3.json already in the outbox and a stray file issue-7-j1-4-9.body.md (a body file, not an item), the next id is issue-7-j1-4-4, and write_seq becomes 4. With write_seq 5 and items up to k 4, the next is issue-7-j1-4-6. Two needs-info notices of two rounds (no comment answered, ref null) get two ids"
read -r -d '' GW_CODE <<'PY' || true
job = J()
first = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Round 1.', ['issueUpdate'], False)
it = items()[first]
os.rename(os.path.join(OUT, first + '.json'), os.path.join(OUT, 'issue-7-j1-4-3.json'))
it['id'] = 'issue-7-j1-4-3'
put(it)
with open(os.path.join(OUT, 'issue-7-j1-4-9.body.md'), 'w') as fh:
    fh.write('x')
job['write_seq'] = 0
a = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Round 2.', ['issueUpdate'], False)
print('after reset %s write_seq %s' % (a, job['write_seq']))
job['write_seq'] = 5
b = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Round 3.', ['issueUpdate'], False)
print('after five %s' % b)
PY
gw_py "$GW_CODE"
e2e_expect_line "after reset issue-7-j1-4-4 write_seq 4"
e2e_expect_line "after five issue-7-j1-4-6"

_flow_test_begin "factory github: an intent answering a comment is recorded once (GH3)"
gw_start gh3-dedupe needs_info
e2e_describe "plan 2.2 'Dedupe before recording': a second intent with the same kind, row and non-null ref returns the first id and records nothing (one item, one intent_recorded line); the same row with another ref, and another row with the same ref, are new intents; two intents with ref null are two"
read -r -d '' GW_CODE <<'PY' || true
job = J()
a = record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Retry needed.', ['issueUpdate'], False, ref=31)
b = record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Retry needed again.', ['issueUpdate'], False, ref=31)
c = record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Other reply.', ['issueUpdate'], False, ref=32)
d = record(job, 'note', 'comment', G.literal_comment(REPO, 7), 'Note.', ['issueUpdate'], False, ref=31)
e = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'One.', ['issueUpdate'], False)
f = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Two.', ['issueUpdate'], False)
print('same %s %s' % (a, b))
print('others %s %s %s %s' % (c, d, e, f))
print('items %d records %d' % (len(items()), len(events('intent_recorded'))))
PY
gw_py "$GW_CODE"
e2e_expect_line "same issue-7-j1-8u-1 issue-7-j1-8u-1"
e2e_expect_line "others issue-7-j1-8u-2 issue-7-j1-note-3 issue-7-j1-4-4 issue-7-j1-4-5"
e2e_expect_line "items 5 records 5"

_flow_test_begin "factory github: an outbox or events file that cannot be written refuses with outbox_unwritable (GH4)"
gw_start gh4-unwritable needs_info
e2e_describe "plan 5.3: record_job_intent raises jobs.Refused('outbox_unwritable <path>: <reason>') on any failure to write the body file, the item or the record, and nothing else. A regular file where J/outbox should be; a directory where J/events.jsonl should be (the record is appended before the item is written, so the failed append leaves no item, and the body file written before it is removed); and a call without the job lock (append_event would refuse): each refuses with outbox_unwritable, and no item is left; the call without the lock refuses before it makes the outbox folder"
read -r -d '' GW_CODE <<'PY' || true
job = J()
def attempt(tag, locked=True):
    try:
        if locked:
            record(job, '4', 'comment', G.literal_comment(REPO, 7), 'x', ['issueUpdate'], False)
        else:
            G.record_job_intent(P, job, '4', 'comment', G.literal_comment(REPO, 7), 'x', ['issueUpdate'], False)
        print('%s recorded' % tag)
    except jobs.Refused as e:
        print('%s %s' % (tag, str(e).split(' ')[0]))
    print('%s items %d' % (tag, len(items()) if os.path.isdir(OUT) else 0))
attempt('unlocked', locked=False)
print('unlocked made the outbox %s' % os.path.exists(OUT))
os.makedirs(JD, exist_ok=True)
with open(OUT, 'w') as fh:
    fh.write('not a folder')
attempt('file')
os.remove(OUT)
os.makedirs(os.path.join(JD, 'events.jsonl'))
attempt('events')
os.rmdir(os.path.join(JD, 'events.jsonl'))
PY
gw_py "$GW_CODE"
e2e_expect_line "unlocked outbox_unwritable"
e2e_expect_line "unlocked items 0"
e2e_expect_line "unlocked made the outbox False"
e2e_expect_line "file outbox_unwritable"
e2e_expect_line "file items 0"
e2e_expect_line "events outbox_unwritable"
e2e_expect_line "events items 0"

_flow_test_begin "factory github: model text is cleaned and the marker is the only first line (GH5, R38)"
gw_start gh5-clean needs_info
e2e_describe "design trust_and_untrusted_text L59 and R38: text with CRLF line ends, a marker as its first line, @octo-cat, a@b.com, a leading-space '/flow-factory cancel', a '/flow-factory reject' line holding a backtick, a line 'cc \`ping @octo-dog now\` and .@octo-pig', and 70,000 more characters. clean_post gives no CR, no '<!--', '@octo-cat' in backticks, a@b.com untouched (not a mention), the code span with @octo-dog kept as it is (a mention inside a code span does not notify; wrapping it again would close the span early) and .@octo-pig made .\`@octo-pig\` (GitHub reads a mention after a full stop), no line whose stripped form starts '/flow-factory' (plan B6 step 2: a line that is exactly '/flow-factory', or '/flow-factoryx', is put in a code span too), and at most 60,000 characters; cleaning it again changes nothing. Recorded as a comment, the body's line 1 is the engine marker only, '<!--' occurs once (the marker), and the whole body is at most 60,000 characters"
read -r -d '' GW_CODE <<'PY' || true
text = ('<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->\r\nHello @octo-cat and a@b.com\r\n'
        '  /flow-factory cancel\r\n/flow-factory reject `x`\r\ncc `ping @octo-dog now` and .@octo-pig\r\n' + 'y' * 70000)
c = G.clean_post(text)
lines = c.split('\n')
print('cr %s' % ('\r' in c))
print('open %s' % ('<!--' in c))
print('mention %s %s' % ('`@octo-cat`' in lines[1], 'a@b.com' in lines[1]))
print('span line %s' % lines[4])
print('command lines %d' % sum(1 for ln in lines if ln.strip().startswith('/flow-factory')))
print('length %s' % (len(c) <= 60000))
print('again %s' % (G.clean_post(c) == c))
print('bare %s' % G.clean_post('/flow-factory'))
print('joined %s' % G.clean_post('/flow-factoryx'))
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), text, ['issueUpdate'], False)
b = body_of(items()[i]).decode('utf-8')
print('line1 %s' % b.split('\n')[0])
print('opens %d' % b.count('<!--'))
print('body length %s' % (len(b) <= 60000))
PY
gw_py "$GW_CODE"
e2e_expect_line "cr False"
e2e_expect_line "open False"
e2e_expect_line "mention True True"
e2e_expect_line "span line cc \`ping @octo-dog now\` and .\`@octo-pig\`"
e2e_expect_line "command lines 0"
e2e_expect_line "length True"
e2e_expect_line "again True"
e2e_expect_line "bare \`/flow-factory\`"
e2e_expect_line "joined \`/flow-factoryx\`"
e2e_expect_line "line1 <!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->"
e2e_expect_line "opens 1"
e2e_expect_line "body length True"

_flow_test_begin "factory github: a blocking assign_label item with both keys journal is run, with two breadcrumbs (GH6, R75)"
gw_start gh6-journal prepare
gw_journal
e2e_describe "plan 2.2 'Who runs an item' and 'Prepare's writes are one intent': row 11's literal gh issue edit 7 --repo O/R --add-assignee flow-e2e-engine --add-label flow:in-progress, kind assign_label, key [issueAssign, issueUpdate], blocking, no park. With both keys journal the drain runs it: one 'issue edit' in the stub's posts, the world issue then has the assignee and the label, the item is sent with effect {label} (the outbox schema's effect holds one key), one write_recorded line, and one breadcrumb per journal key, two in issue 7's trail (5.3 breadcrumb rule). A second drain does nothing"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '11', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True, state='spec')
drain(job, tiers(issueAssign='journal', issueUpdate='journal'))
it = check(i)
print('item %s %s %s' % (it['status'], it['effect'], it['body_file']))
w = world()
print('issue %s %s' % (w['issues']['7']['assignees'], w['issues']['7']['labels']))
print('posts %s' % [p['method'] for p in posts()])
wr = events('write_recorded')
print('write_recorded %d %s %s' % (len(wr), wr[0]['id'] == i, wr[0]['effect']))
drain(job, tiers(issueAssign='journal', issueUpdate='journal'))
print('posts after %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-11-1 kind=assign_label"
e2e_expect_line "valid issue-7-j1-11-1 []"
e2e_expect_line "item sent {'label': 'flow:in-progress'} None"
e2e_expect_line "issue ['flow-e2e-engine'] ['flow:in-progress']"
e2e_expect_line "posts ['issue edit']"
e2e_expect_line "write_recorded 1 True {'label': 'flow:in-progress'}"
e2e_expect_line "lines 0"
e2e_expect_line "posts after 1"
e2e_expect_equal "2" "$(gw_trail)" "breadcrumbs in issue 7's trail"
e2e_expect_equal "1 1" "$(grep -c 'tiers.issueAssign (journal, factory engine)' "$E2E_REPO"/.decisions/auto-log/issue-7.*.md) $(grep -c 'tiers.issueUpdate (journal, factory engine)' "$E2E_REPO"/.decisions/auto-log/issue-7.*.md)" "one breadcrumb for issueAssign and one for issueUpdate"

_flow_test_begin "factory github: a blocking item whose key is confirm stays recorded (GH7)"
gw_start gh7-confirm prepare
gw_journal
e2e_describe "design stages L15-L17 and plan 2.2: a blocking write whose key is confirm is not run by the drain and does not become pending_confirm (that is for notices); row 40 parks the job instead. With issueAssign confirm: no line, item recorded, nothing posted, no breadcrumb"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '11', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True, state='spec')
drain(job, tiers(issueAssign='confirm', issueUpdate='journal'))
print('item %s' % items()[i]['status'])
print('posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "lines 0"
e2e_expect_line "item recorded"
e2e_expect_line "posts 0"
e2e_expect_equal "0" "$(gw_trail)" "breadcrumbs in issue 7's trail"

_flow_test_begin "factory github: one notice under each tier value, and a pending_confirm notice later sent or dropped (GH8)"
gw_start gh8-values needs_info
gw_journal
e2e_describe "design stages L10-L17, Q12 and plan B6 step 7: a notice under issueUpdate autonomous is posted with no breadcrumb; under journal it is posted with one breadcrumb; under confirm it becomes pending_confirm with the line PENDING_CONFIRM job=issue-7-j1 intent=<id> kind=comment (plan 2.3) and nothing is posted; a later drain still under confirm changes nothing; once the key is journal it is posted (a third post, a second breadcrumb). A pending_confirm notice whose job has left its state_at_write (needs_info, now spec) is dropped and never posted"
read -r -d '' GW_CODE <<'PY' || true
job = J()
a = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'A.', ['issueUpdate'], False)
drain(job, tiers(issueUpdate='autonomous'))
print('a %s posts %d' % (items()[a]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment"
e2e_expect_line "a sent posts 1"
e2e_expect_equal "0" "$(gw_trail)" "breadcrumbs after the autonomous notice"
read -r -d '' GW_CODE <<'PY' || true
job = J()
b = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'B.', ['issueUpdate'], False)
drain(job, tiers(issueUpdate='journal'))
print('b %s posts %d' % (items()[b]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "b sent posts 2"
e2e_expect_equal "1" "$(gw_trail)" "breadcrumbs after the journal notice"
read -r -d '' GW_CODE <<'PY' || true
job = J()
c = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'C.', ['issueUpdate'], False)
drain(job, tiers(issueUpdate='confirm'))
it = check(c)
print('c %s posts %d' % (it['status'], len(posts())))
drain(job, tiers(issueUpdate='confirm'))
print('c again %s' % items()[c]['status'])
drain(job, tiers(issueUpdate='journal'))
print('c later %s posts %d' % (items()[c]['status'], len(posts())))
d = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'D.', ['issueUpdate'], False)
drain(job, tiers(issueUpdate='confirm'))
job['state'] = 'spec'
drain(job, tiers(issueUpdate='journal'))
check(d)
print('d %s posts %d' % (items()[d]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line PENDING_CONFIRM job=issue-7-j1 intent=issue-7-j1-4-3 kind=comment"
e2e_expect_line "valid issue-7-j1-4-3 []"
e2e_expect_line "c pending_confirm posts 2"
e2e_expect_line "c again pending_confirm"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-3 kind=comment"
e2e_expect_line "c later sent posts 3"
e2e_expect_line "line WRITE_DROPPED job=issue-7-j1 intent=issue-7-j1-4-4 state_at_write=needs_info state=spec"
e2e_expect_line "valid issue-7-j1-4-4 []"
e2e_expect_line "d dropped posts 3"
e2e_expect_equal "2" "$(gw_trail)" "breadcrumbs after the confirm notice was sent under journal"

_flow_test_begin "factory github: a failed POST stays recorded and the retry posts once (GH9)"
gw_start gh9-retry needs_info
e2e_describe "plan 5.2 'POST fails': with the stub's post_fails knob the drain prints WRITE_FAILED job=issue-7-j1 intent=issue-7-j1-4-1 <reason>, the item stays recorded and nothing is stored; with the knob off the next drain looks first, finds nothing and posts once; a third drain posts nothing (two drains in one round, one post: R25)"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
drain(job, tiers())
print('item %s posts %d' % (items()[i]['status'], len(posts())))
PY
fe_world_knob post_fails true
gw_py "$GW_CODE"
e2e_expect_out "line WRITE_FAILED job=issue-7-j1 intent=issue-7-j1-4-1 "
e2e_expect_line "item recorded posts 0"
fe_world_knob post_fails false
read -r -d '' GW_CODE <<'PY' || true
job = J()
drain(job, tiers())
drain(job, tiers())
print('item %s posts %d' % (items()['issue-7-j1-4-1']['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment"
e2e_expect_line "item sent posts 1"

_flow_test_begin "factory github: a post whose process died before recording it is found, not posted again (GH10, R34, AC10)"
gw_start gh10-die needs_info
e2e_describe "AC10 and R34: the stub's die_after_post knob stores the comment and kills the drain's process before it records the effect; the item is still recorded and the stub holds one post. With the knob off the next drain finds the engine's marker by intent id (comment 1, the world's first id) and prints WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-4-1 found=1 (plan 2.3); still one post; the item is sent with effect {comment_id: 1}"
read -r -d '' GW_CODE <<'PY' || true
job = J()
record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
PY
gw_py "$GW_CODE"
fe_world_knob die_after_post true
read -r -d '' GW_CODE <<'PY' || true
drain(J(), tiers())
print('survived')
PY
gw_py "$GW_CODE"
e2e_expect_no_line "survived"
fe_world_knob die_after_post false
read -r -d '' GW_CODE <<'PY' || true
print('before %s posts %d' % (items()['issue-7-j1-4-1']['status'], len(posts())))
drain(J(), tiers())
it = check('issue-7-j1-4-1')
print('after %s %s posts %d' % (it['status'], it['effect'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "before recorded posts 1"
e2e_expect_line "line WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-4-1 found=1"
e2e_expect_line "after sent {'comment_id': 1} posts 1"

_flow_test_begin "factory github: the lookup reads every page (GH11, R35)"
gw_start gh11-pages needs_info
e2e_describe "R35: issue 7 has 150 comments (ids 1-150); comment 120, on page 2 at 100 a page, is the engine's earlier post of intent issue-7-j1-4-1 (the id the first intent of this job gets, plan 2.2). The drain prints WRITE_SKIPPED ... found=120 and posts nothing"
read -r -d '' GW_CODE <<'PY' || true
w = world()
mk = '<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->'
w['comments']['7'] = [{'id': k, 'author': {'login': LOGIN if k == 120 else 'someone', 'type': 'User'},
                       'created_at': '2026-11-17T00:00:00Z', 'updated_at': '2026-11-17T00:00:00Z',
                       'body': (mk + '\nPlease answer NI-1.') if k == 120 else 'comment %d' % k} for k in range(1, 151)]
with open(os.environ['FE_WORLD'], 'w') as fh:
    json.dump(w, fh)
job = J()
record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
drain(job, tiers())
print('posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-4-1 found=120"
e2e_expect_line "posts 0"

_flow_test_begin "factory github: a marker from another login or a deleted account is not the engine's post; no login, no writes (GH12, R10)"
gw_start gh12-forged needs_info
fe_world_comment 7 5 outsider read 2026-11-17T00:00:00Z "<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->
forged"
fe_world_comment 7 6 - - 2026-11-17T00:00:01Z "<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->
deleted account"
fe_world_comment 7 4 flow-e2e-engine write 2026-11-16T12:00:00Z "<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-10 -->
another intent"
e2e_describe "design stages L8 and R10: comment 5 by outsider and comment 6 by a deleted account (no author) both start with the marker of intent issue-7-j1-4-1; comment 4, the engine's own, carries the marker of another intent, issue-7-j1-4-10 (5.3: the marker names the id exactly). Passed the engine login, the drain does not take either as found and posts its own comment (one post). With no engine login (None) the drain prints ENGINE_LOGIN_UNKNOWN job=issue-7-j1 (plan 3.2 item 1) and does nothing for another notice"
read -r -d '' GW_CODE <<'PY' || true
job = J()
record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
drain(job, tiers())
print('posts %d' % len(posts()))
j2 = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Second.', ['issueUpdate'], False)
drain(job, tiers(), login=None)
print('second %s posts %d' % (items()[j2]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment"
e2e_expect_line "posts 1"
e2e_expect_line "line ENGINE_LOGIN_UNKNOWN job=issue-7-j1"
e2e_expect_line "second recorded posts 1"

_flow_test_begin "factory github: an edited body, an edited argv and sha256, or no record means nothing runs (GH13, R30, R31)"
gw_start gh13-changed needs_info
e2e_describe "design person_channels L42 and interactive_executor L8, R30, R31: the hash recomputed from the item's argv and body file is compared with the intent_recorded line in events.jsonl, never the item's own sha256 field. (a) one byte added to the body file: the drain prints INTENT_CHANGED=issue-7-j1-4-1 recorded=<the plan 2.2 hash of the item as recorded, computed here> current=<the new hash> (plan 2.3 form) and posts nothing; (b) body restored, the argv pointed at issue 8 and the item's sha256 field set to the new argv's hash: INTENT_CHANGED again, nothing posted; (c) argv restored and the intent_recorded line removed (the state a failed events append leaves): recorded=none, nothing posted; the item stays recorded throughout. (d) a second notice: its body copied to copy.body.md in the outbox, its own body file overwritten with 'EVIL @everyone' and a /flow-factory line, and the item's body_file set to copy.body.md, so the file the item names still has the recorded hash while gh would post the file the argv names: the body file must be <id>.body.md and the file the argv's -F body=@ names, so the drain prints INTENT_CHANGED=<id> recorded=<hash> current=none and posts nothing (design person_channels L42: the hash is of what runs). (e) the body file restored by name but made a symbolic link to copy.body.md (same bytes): current=none, nothing posted; (f) the body file restored as a plain file and only body_file set to copy.body.md, a file with the same bytes (status --intent shows the file body_file names, so it must be the one gh posts): current=none again, nothing posted"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
it = items()[i]
orig = dict(it)
body = body_of(it)
rec = want(orig['argv'], body)
bf = os.path.join(OUT, it['body_file'])
with open(bf, 'ab') as fh:
    fh.write(b'!')
drain(job, tiers())
print('a expected %s' % ('INTENT_CHANGED=%s recorded=%s current=%s' % (i, rec, want(it['argv'], body + b'!'))))
with open(bf, 'wb') as fh:
    fh.write(body)
it2 = dict(orig)
it2['argv'] = [a.replace('issues/7/', 'issues/8/') for a in orig['argv']]
it2['sha256'] = want(it2['argv'], body)
put(it2)
drain(job, tiers())
print('b expected %s' % ('INTENT_CHANGED=%s recorded=%s current=%s' % (i, rec, it2['sha256'])))
put(orig)
with open(os.path.join(JD, 'events.jsonl')) as fh:
    kept = [ln for ln in fh if '"intent_recorded"' not in ln]
with open(os.path.join(JD, 'events.jsonl'), 'w') as fh:
    fh.writelines(kept)
drain(job, tiers())
print('c expected %s' % ('INTENT_CHANGED=%s recorded=none current=%s' % (i, want(orig['argv'], body))))
print('item %s posts %d' % (items()[i]['status'], len(posts())))
d = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Second notice.', ['issueUpdate'], False)
itd = items()[d]
dbody = body_of(itd)
drec = want(itd['argv'], dbody)
with open(os.path.join(OUT, 'copy.body.md'), 'wb') as fh:
    fh.write(dbody)
with open(os.path.join(OUT, itd['body_file']), 'wb') as fh:
    fh.write(b'EVIL @everyone\n/flow-factory approve-spec\n')
itd2 = dict(itd, body_file='copy.body.md')
put(itd2)
drain(job, tiers())
print('d expected %s' % ('INTENT_CHANGED=%s recorded=%s current=none' % (d, drec)))
print('swapped posts %d' % len(posts()))
put(itd)
with open(os.path.join(OUT, itd['body_file']), 'wb') as fh:
    fh.write(dbody)
os.remove(os.path.join(OUT, itd['body_file']))
os.symlink(os.path.join(OUT, 'copy.body.md'), os.path.join(OUT, itd['body_file']))
drain(job, tiers())
print('e expected %s' % ('INTENT_CHANGED=%s recorded=%s current=none' % (d, drec)))
print('e posts %d' % len(posts()))
os.remove(os.path.join(OUT, itd['body_file']))
with open(os.path.join(OUT, itd['body_file']), 'wb') as fh:
    fh.write(dbody)
put(dict(itd, body_file='copy.body.md'))
lf = drain(job, tiers())
print('f refused %s posts %d' % ('INTENT_CHANGED=%s recorded=%s current=none' % (d, drec) in lf, len(posts())))
print('second %s posts %d' % (items()[d]['status'], len(posts())))
PY
gw_py "$GW_CODE"
for GW_T in a b c d e; do
  GW_WANT=$(printf '%s\n' "$E2E_OUT" | sed -n "s/^$GW_T expected //p")
  e2e_expect_line "line $GW_WANT"
done
e2e_expect_line "item recorded posts 0"
e2e_expect_line "swapped posts 0"
e2e_expect_line "e posts 0"
e2e_expect_line "f refused True posts 0"
e2e_expect_line "second recorded posts 0"

_flow_test_begin "factory github: the pending intent is left to rows 41, 41e and 41k; run_literal checks the id and looks first (GH14, R68, R74)"
gw_start gh14-pending waiting_operator "d['resume_state'] = 'prepare'; d['reason'] = 'tier_confirm'; d['pending_intent'] = {'id': 'issue-7-j1-40-1', 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']}"
e2e_describe "plan 2.2 'Who runs an item' and R74 (module half): job parked by row 40 with pending intent P = issue-7-j1-40-1 (assign_label, recorded) and a notice N = issue-7-j1-40-2; the world issue already has the engine as assignee and the in-progress label. With both keys journal the drain posts N only and does not look up or run P (P stays recorded). R68: run_literal(N) raises IntentNotPending with the line INTENT_NOT_PENDING=issue-7-j1-40-2 pending=issue-7-j1-40-1 (plan 2.3). run_literal(P) looks first, finds both on the issue, records WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-40-1 found=flow:in-progress, posts nothing, and P is sent with effect {label}"
read -r -d '' GW_CODE <<'PY' || true
w = world()
w['issues']['7']['assignees'] = [LOGIN]
w['issues']['7']['labels'] = [LABEL]
with open(os.environ['FE_WORLD'], 'w') as fh:
    json.dump(w, fh)
job = J()
p = record(job, '40', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True)
n = record(job, '40', 'comment', G.literal_comment(REPO, 7), 'Waiting for a confirm.', ['issueUpdate'], False)
open(os.path.join(BIN, 'fe-gh-calls.log'), 'w').close()
drain(job, tiers(issueAssign='journal', issueUpdate='journal'))
print('p %s posts %s' % (items()[p]['status'], [x['method'] for x in posts()]))
with open(os.path.join(BIN, 'fe-gh-calls.log')) as fh:
    print('issue reads %d' % sum(1 for ln in fh if ln.startswith('api repos/flow-e2e/scratch/issues/7 ')
                                 or ln.strip() == 'api repos/flow-e2e/scratch/issues/7'))
try:
    with jobs.job_lock(P, 7):
        G.run_literal(P, job, n, GH, LOGIN)
    print('n ran')
except G.IntentNotPending as e:
    print('n refused %s' % e.line)
lines = []
with jobs.job_lock(P, 7):
    eff = G.run_literal(P, job, p, GH, LOGIN, lines=lines)
print('p effect %s lines %s' % (eff, lines))
it = check(p)
print('p %s %s posts %d' % (it['status'], it['effect'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-40-2 kind=comment"
e2e_expect_line "p recorded posts ['POST']"
e2e_expect_line "issue reads 0"
e2e_expect_line "n refused INTENT_NOT_PENDING=issue-7-j1-40-2 pending=issue-7-j1-40-1"
e2e_expect_line "p effect {'label': 'flow:in-progress'} lines ['WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-40-1 found=flow:in-progress']"
e2e_expect_line "valid issue-7-j1-40-1 []"
e2e_expect_line "p sent {'label': 'flow:in-progress'} posts 1"

_flow_test_begin "factory github: run_literal runs a pending intent whose effect is absent, refusing a changed one (GH15)"
gw_start gh15-runliteral waiting_operator "d['resume_state'] = 'prepare'; d['reason'] = 'tier_confirm'; d['pending_intent'] = {'id': 'issue-7-j1-40-1', 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']}"
gw_journal
e2e_describe "plan B6 step 4: with the body of nothing changed but the argv edited (issue 8), run_literal raises IntentChanged whose line is INTENT_CHANGED=issue-7-j1-40-1 recorded=<hash> current=<hash>; restored, with the issue holding the label but not the engine as assignee (plan B6 step 5: the effect is found only when both are there) it runs the literal once (one 'issue edit' post), P is sent with effect {label}, the world issue has both, one write_recorded line, and with a tiers callable resolving both keys to journal one breadcrumb per key"
read -r -d '' GW_CODE <<'PY' || true
job = J()
p = record(job, '40', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True)
it = items()[p]
orig = dict(it)
it['argv'] = [a.replace('7', '8') if a == '7' else a for a in it['argv']]
put(it)
try:
    with jobs.job_lock(P, 7):
        G.run_literal(P, job, p, GH, LOGIN)
    print('ran')
except G.IntentChanged as e:
    print('refused %s' % e.line.split(' ')[0])
put(orig)
w = world()
w['issues']['7']['labels'] = [LABEL]
with open(os.environ['FE_WORLD'], 'w') as fh:
    json.dump(w, fh)
with jobs.job_lock(P, 7):
    eff = G.run_literal(P, job, p, GH, LOGIN, tiers=tiers(issueAssign='journal', issueUpdate='journal'))
it = check(p)
w = world()
print('ran %s %s %s' % (eff, it['status'], [x['method'] for x in posts()]))
print('issue %s %s' % (w['issues']['7']['assignees'], w['issues']['7']['labels']))
print('write_recorded %d' % len(events('write_recorded')))
PY
gw_py "$GW_CODE"
e2e_expect_line "refused INTENT_CHANGED=issue-7-j1-40-1"
e2e_expect_line "valid issue-7-j1-40-1 []"
e2e_expect_line "ran {'label': 'flow:in-progress'} sent ['issue edit']"
e2e_expect_line "issue ['flow-e2e-engine'] ['flow:in-progress']"
e2e_expect_line "write_recorded 1"
e2e_expect_equal "2" "$(gw_trail)" "breadcrumbs in issue 7's trail"

_flow_test_begin "factory github: the literal runs without a shell, through the gh the caller found (GH16, R33)"
gw_start gh16-noshell needs_info
mkdir -p "$E2E_DIR/decoy/bin" "$E2E_DIR/decoy/scripts/lib" "$E2E_DIR/plain"
printf '#!/bin/sh\ntouch "%s/decoy-ran"\n' "$E2E_DIR" > "$E2E_DIR/decoy/bin/gh"
printf '#!/bin/sh\ntouch "%s/plain-ran"\n' "$E2E_DIR" > "$E2E_DIR/plain/gh"
: > "$E2E_DIR/decoy/scripts/lib/tier-runtime.sh"
mkdir -p "$E2E_DIR/envgh"
printf '#!/bin/sh\nenv > "%s/gh-env.txt"\nexec "%s/gh" "$@"\n' "$E2E_DIR" "$E2E_BIN" > "$E2E_DIR/envgh/gh"
chmod +x "$E2E_DIR/decoy/bin/gh" "$E2E_DIR/plain/gh" "$E2E_DIR/envgh/gh"
e2e_describe "R33: a body holding \$(touch pwned) and a backticked \`touch pwned2\` is posted verbatim and no file is made; a directory holding a gh that writes decoy-ran, with ../scripts/lib/tier-runtime.sh beside it, first on PATH: which_real('gh') skips it and gives the stub (plan B6 step 4, _flow_factory.py which_real). Then a plain directory whose gh writes plain-ran is put first on PATH: the drain, passed the stub as gh_real, runs the stub, so plain-ran is never made (the item's argv[0] 'gh' is never looked up on PATH). A label_add of the label 'x\$(touch pwned);y' (shell text in the argv itself) adds exactly that label and makes no file. Run through a gh_real that saves its environment and then runs the stub, with FLOW_TIER_CALL and FLOW_TIER_DIR set and GH_PROMPT_DISABLED unset in the caller: the write sees no FLOW_TIER_ variable and GH_PROMPT_DISABLED=1 (plan B6 step 4)"
read -r -d '' GW_CODE <<PY || true
os.environ['PATH'] = '$E2E_DIR/decoy/bin' + os.pathsep + os.environ['PATH']
real = ff.which_real('gh')
print('which_real stub %s' % (real == os.path.join(BIN, 'gh')))
os.environ['PATH'] = '$E2E_DIR/plain' + os.pathsep + os.environ['PATH']
job = J()
text = 'Run \$(touch pwned) and \`touch pwned2\` now.'
record(job, '4', 'comment', G.literal_comment(REPO, 7), text, ['issueUpdate'], False)
drain(job, tiers(), gh=real)
print('verbatim %s' % (text in posts()[0]['body']))
label = 'x\$(touch pwned);y'
record(job, '4', 'label_add', G.literal_label_add(REPO, 7, label), None, ['issueUpdate'], False)
os.environ['FLOW_TIER_CALL'] = 'call-record'
os.environ['FLOW_TIER_DIR'] = '/nowhere'
os.environ.pop('GH_PROMPT_DISABLED', None)
drain(job, tiers(), gh='$E2E_DIR/envgh/gh')
print('label verbatim %s' % (world()['issues']['7']['labels'] == [label]))
with open('$E2E_DIR/gh-env.txt') as fh:
    env = fh.read().splitlines()
print('env tier %s prompt %s' % ([e for e in env if e.startswith('FLOW_TIER_')], 'GH_PROMPT_DISABLED=1' in env))
PY
gw_py "$GW_CODE"
e2e_expect_line "which_real stub True"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment"
e2e_expect_line "verbatim True"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-2 kind=label_add"
e2e_expect_line "label verbatim True"
e2e_expect_line "env tier [] prompt True"
e2e_expect_equal "none" "$(ls "$E2E_DIR"/decoy-ran "$E2E_DIR"/plain-ran "$E2E_REPO"/pwned "$E2E_REPO"/pwned2 "$E2E_DIR"/pwned 2>/dev/null || echo none)" "files the decoys or the body made"

_flow_test_begin "factory github: pr_close needs a PR; a terminal job runs only its own state's items (GH17, R74)"
gw_start gh17-prclose cancelled "d['pr'] = 12"
fe_world_pull 12 feature/issue-7-x-2 flow-e2e-engine write "Closes #7"
e2e_describe "plan B6 step 5 and 2.2 (terminal jobs): a cancelled job with PR 12 has a row-11 item recorded for state spec (its POST failed earlier) and row 53's pr_close (gh api --method PATCH repos/O/R/pulls/12 -f state=closed) for state cancelled. The drain drops the spec item (WRITE_DROPPED ... state_at_write=spec state=cancelled) and posts the PATCH once; the PR is closed and the item sent with effect {pr: 12}. A job with no PR records nothing for pr_close (None, no new item). A pr_close whose PR is already closed is found: WRITE_SKIPPED ... found=12, no post"
read -r -d '' GW_CODE <<'PY' || true
job = J()
old = record(job, '11', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
             ['issueAssign', 'issueUpdate'], True, state='spec')
c = record(job, '53', 'pr_close', G.literal_pr_close(REPO, 12), None, ['issueUpdate'], False)
drain(job, tiers())
check(old)
it = check(c)
print('old %s close %s %s' % (items()[old]['status'], it['status'], it['effect']))
print('posts %s %s' % ([(x['method'], x['path']) for x in posts()], world()['pulls'][0]['state']))
nopr = dict(job, pr=None)
print('no pr %s items %d' % (record(nopr, '53', 'pr_close', G.literal_pr_close(REPO, 12), None, ['issueUpdate'], False),
                             len(items())))
again = record(job, '53', 'pr_close', G.literal_pr_close(REPO, 12), None, ['issueUpdate'], False)
drain(job, tiers())
print('again %s posts %d' % (items()[again]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_DROPPED job=issue-7-j1 intent=issue-7-j1-11-1 state_at_write=spec state=cancelled"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-53-2 kind=pr_close"
e2e_expect_line "valid issue-7-j1-11-1 []"
e2e_expect_line "valid issue-7-j1-53-2 []"
e2e_expect_line "old dropped close sent {'pr': 12}"
e2e_expect_line "posts [('PATCH', 'repos/flow-e2e/scratch/pulls/12')] closed"
e2e_expect_line "no pr None items 2"
e2e_expect_line "line WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-53-3 found=12"
e2e_expect_line "again sent posts 1"

_flow_test_begin "factory github: a confirmed notice is sent under a confirm key, after the hash check (GH18, Q16)"
gw_start gh18-confirmed needs_info
e2e_describe "Q16 and plan B6 step 3: a notice a person confirmed at a terminal (status confirmed, and the intent_confirmed events line {type, job, time, id} of plan 5.3 that the terminal confirm writes) is run by the drain although issueUpdate is still confirm. With the status set to confirmed by hand and no intent_confirmed line it is refused with INTENT_CHANGED=<id> recorded=<hash> current=<hash> field=status (Inferred form: plan 2.3's line plus the field that differs from the record) and nothing is posted; with its body edited first it is refused with INTENT_CHANGED and nothing is posted, and once restored it is posted once and is sent"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
it = items()[i]
it['status'] = 'confirmed'
put(it)
rec = want(it['argv'], body_of(it))
drain(job, tiers(issueUpdate='confirm'))
print('no line expected INTENT_CHANGED=%s recorded=%s current=%s field=status' % (i, rec, rec))
print('no line %s posts %d' % (items()[i]['status'], len(posts())))
with jobs.job_lock(P, 7):
    jobs.append_event(P, 7, {'type': 'intent_confirmed', 'job': 'issue-7-j1', 'id': i})
bf = os.path.join(OUT, it['body_file'])
body = body_of(it)
with open(bf, 'ab') as fh:
    fh.write(b'!')
drain(job, tiers(issueUpdate='confirm'))
print('edited %s posts %d' % (items()[i]['status'], len(posts())))
with open(bf, 'wb') as fh:
    fh.write(body)
drain(job, tiers(issueUpdate='confirm'))
print('restored %s posts %d' % (items()[i]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line $(printf '%s\n' "$E2E_OUT" | sed -n 's/^no line expected //p')"
e2e_expect_line "no line confirmed posts 0"
e2e_expect_out "line INTENT_CHANGED=issue-7-j1-4-1 recorded="
e2e_expect_line "edited confirmed posts 0"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment"
e2e_expect_line "restored sent posts 1"

_flow_test_begin "factory github: label_add and label_remove run, and are found when already done (GH19)"
gw_start gh19-labels needs_info
e2e_describe "plan B6 step 5: label_add of flow:needs-info (POST repos/O/R/issues/7/labels -f labels[]=flow:needs-info) adds it, effect {label}; label_remove (DELETE repos/O/R/issues/7/labels/flow%3Aneeds-info) removes it; a second label_remove finds it already gone (WRITE_SKIPPED found=flow:needs-info) and a label_add of a label already there is found the same way; three posts in all"
read -r -d '' GW_CODE <<'PY' || true
job = J()
a = record(job, '4', 'label_add', G.literal_label_add(REPO, 7, 'flow:needs-info'), None, ['issueUpdate'], False)
drain(job, tiers())
print('after add %s %s' % (world()['issues']['7']['labels'], check(a)['effect']))
r = record(job, '8', 'label_remove', G.literal_label_remove(REPO, 7, 'flow:needs-info'), None, ['issueUpdate'], False)
drain(job, tiers())
print('after remove %s %s' % (world()['issues']['7']['labels'], check(r)['effect']))
r2 = record(job, '8', 'label_remove', G.literal_label_remove(REPO, 7, 'flow:needs-info'), None, ['issueUpdate'], False)
drain(job, tiers())
w = world()
w['issues']['7']['labels'] = ['flow:x']
with open(os.environ['FE_WORLD'], 'w') as fh:
    json.dump(w, fh)
a2 = record(job, '4', 'label_add', G.literal_label_add(REPO, 7, 'flow:x'), None, ['issueUpdate'], False)
drain(job, tiers())
print('posts %s' % [(x['method'], x['path']) for x in posts()])
PY
gw_py "$GW_CODE"
e2e_expect_line "after add ['flow:needs-info'] {'label': 'flow:needs-info'}"
e2e_expect_line "after remove [] {'label': 'flow:needs-info'}"
e2e_expect_line "line WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-8-3 found=flow:needs-info"
e2e_expect_line "line WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-4-4 found=flow:x"
e2e_expect_line "posts [('POST', 'repos/flow-e2e/scratch/issues/7/labels'), ('DELETE', 'repos/flow-e2e/scratch/issues/7/labels/flow%3Aneeds-info')]"

_flow_test_begin "factory github: lookup tells found, absent and a failed read apart (GH20)"
gw_start gh20-lookup needs_info
e2e_describe "plan 3.1 (intent_effect_observed) and 5.2: lookup returns None when the effect is absent, the effect when present ({comment_id: 9} for the engine's marker comment 9), and raises ReadFailed when the list read fails (the stub's list_fails on the comments path) or the engine login is None; a drain over the failed read posts nothing and leaves the item recorded"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
print('absent %s' % G.lookup(GH, job, i, LOGIN))
PY
gw_py "$GW_CODE"
e2e_expect_line "absent None"
fe_world_comment 7 9 flow-e2e-engine write 2026-11-17T00:00:00Z "<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->
Please answer NI-1."
read -r -d '' GW_CODE <<'PY' || true
job = J()
print('found %s' % G.lookup(GH, job, 'issue-7-j1-4-1', LOGIN))
try:
    G.lookup(GH, job, 'issue-7-j1-4-1', None)
    print('no login answered')
except G.ReadFailed:
    print('no login ReadFailed')
PY
gw_py "$GW_CODE"
e2e_expect_line "found {'comment_id': 9}"
e2e_expect_line "no login ReadFailed"
fe_world_knob list_fails '["repos/flow-e2e/scratch/issues/7/comments"]'
read -r -d '' GW_CODE <<'PY' || true
job = J()
try:
    G.lookup(GH, job, 'issue-7-j1-4-1', LOGIN)
    print('failed read answered')
except G.ReadFailed:
    print('failed read ReadFailed')
drain(job, tiers())
print('item %s posts %d' % (items()['issue-7-j1-4-1']['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "failed read ReadFailed"
e2e_expect_out "line WRITE_FAILED job=issue-7-j1 intent=issue-7-j1-4-1 "
e2e_expect_line "item recorded posts 0"

_flow_test_begin "factory github: the P9 probe intent (GH21)"
gw_start gh21-probe needs_info
e2e_describe "plan 2.2 and 5.3: record_probe_intent(<P9-3 folder>, 3, argv, body) returns probe-p9-3; the item in <folder>/outbox validates with job, row and state_at_write null, kind comment, key [issueUpdate], blocking false; the body's first line is the probe marker <!-- FLOW_FACTORY job=issue-0-j1 event=probe-p9-3 --> (_flow_factory.py PROBE_JOB_MARKER); one intent_recorded line in <folder>/events.jsonl with the plan 2.2 hash. A regular file where <folder>/outbox should be refuses with outbox_unwritable"
read -r -d '' GW_CODE <<PY || true
folder = '$E2E_DIR/probe/P9-3'
os.makedirs(folder)
i = G.record_probe_intent(folder, 3, G.literal_comment(REPO, 7), 'Probe text.')
with open(os.path.join(folder, 'outbox', i + '.json')) as fh:
    it = json.load(fh)
print('id %s valid %s' % (i, schema.validate(it, SCHEMA)))
print('fields %s %s %s %s %s %s %s' % (it['job'], it['row'], it['state_at_write'], it['kind'], it['key'], it['blocking'], it['status']))
with open(os.path.join(folder, 'outbox', it['body_file']), 'rb') as fh:
    body = fh.read()
print('line1 %s' % body.decode().split('\n')[0])
rec = events('intent_recorded', os.path.join(folder, 'events.jsonl'))
print('record %d %s %s' % (len(rec), rec[0]['id'], rec[0]['sha256'] == want(it['argv'], body)))
bad = '$E2E_DIR/probe/P9-4'
os.makedirs(bad)
open(os.path.join(bad, 'outbox'), 'w').close()
try:
    G.record_probe_intent(bad, 4, G.literal_comment(REPO, 7), 'x')
    print('bad recorded')
except jobs.Refused as e:
    print('bad %s' % str(e).split(' ')[0])
PY
gw_py "$GW_CODE"
e2e_expect_line "id probe-p9-3 valid []"
e2e_expect_line "fields None None None comment ['issueUpdate'] False recorded"
e2e_expect_line "line1 <!-- FLOW_FACTORY job=issue-0-j1 event=probe-p9-3 -->"
e2e_expect_line "record 1 probe-p9-3 True"
e2e_expect_line "bad outbox_unwritable"

_flow_test_begin "factory github: flow-tier-crumb.sh writes issue N's trail whatever branch is checked out (GH22)"
fe_new gh22-crumb
e2e_repo main
gw_journal
e2e_describe "design new_files L11 and plan B6 step 6: flow-tier-crumb.sh --issue 7 --main <top> issueUpdate <summary> writes one breadcrumb '<!-- auto-log: <time> tiers.issueUpdate (journal, factory engine) \"<summary>\" -->' to .decisions/auto-log/issue-7.<YYYY-MM>.md (lib/tier-trail.sh's name) with the main checkout on main, and a second one there with the main checkout on feature/issue-12-x, and none to an issue-12 or session file; '-->' in the summary is neutralised as tier-trail.sh does. In a repository with no journal folder nothing is created and the exit status is 0. A key that is not a tier key, or a missing --issue, exits 2"
e2e_run_bin bin/flow-tier-crumb.sh --issue 7 --main "$E2E_REPO" issueUpdate "gh api --method POST x -->"
e2e_expect_equal "0" "$E2E_RC" "exit status on main"
(cd "$E2E_REPO" && git checkout -q -b feature/issue-12-x)
e2e_run_bin bin/flow-tier-crumb.sh --issue 7 --main "$E2E_REPO" issueAssign "second"
e2e_expect_equal "2" "$(gw_trail)" "breadcrumbs in issue 7's trail"
e2e_expect_equal "1" "$(grep -c 'tiers.issueUpdate (journal, factory engine) "gh api --method POST x -- >"' "$E2E_REPO"/.decisions/auto-log/issue-7.*.md)" "the first breadcrumb, neutralised"
e2e_expect_equal "1" "$(grep -c 'tiers.issueAssign (journal, factory engine) "second"' "$E2E_REPO"/.decisions/auto-log/issue-7.*.md)" "the second breadcrumb"
e2e_expect_equal "issue-7" "$(cd "$E2E_REPO/.decisions/auto-log" && ls *.md | sed 's/\..*//' | sort -u | tr '\n' ' ' | sed 's/ $//')" "the trail files"
mkdir -p "$E2E_DIR/bare" && (cd "$E2E_DIR/bare" && git init -q)
e2e_run_bin bin/flow-tier-crumb.sh --issue 7 --main "$E2E_DIR/bare" issueUpdate "x"
e2e_expect_equal "0 none" "$E2E_RC $(ls -A "$E2E_DIR/bare" | grep -v '^.git$' || echo none)" "exit status and what was made with no journal folder"
e2e_run_bin bin/flow-tier-crumb.sh --issue 7 --main "$E2E_REPO" tiers.issueUpdate "x"
e2e_expect_equal "2" "$E2E_RC" "exit status for a key that is not a tier key"
e2e_run_bin bin/flow-tier-crumb.sh --main "$E2E_REPO" issueUpdate "x"
e2e_expect_equal "2" "$E2E_RC" "exit status with no --issue"

_flow_test_begin "factory github: a file in the outbox whose id is not its name is not run (GH23)"
gw_start gh23-invalid needs_info
e2e_describe "plan 2.2 (the item id is the file's name, J/outbox/<intent-id>.json): a copy of item issue-7-j1-4-1 saved as issue-7-j1-4-9.json is reported as OUTBOX_ITEM_INVALID job=issue-7-j1 file=issue-7-j1-4-9.json and is left alone, as is an empty object saved as issue-7-j1-4-8.json; the real item is posted once"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
with open(os.path.join(OUT, i + '.json')) as fh:
    copy = fh.read()
with open(os.path.join(OUT, 'issue-7-j1-4-9.json'), 'w') as fh:
    fh.write(copy)
with open(os.path.join(OUT, 'issue-7-j1-4-8.json'), 'w') as fh:
    fh.write('{}')
drain(job, tiers())
print('copy %s posts %d' % (items()['issue-7-j1-4-9']['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment"
e2e_expect_line "line OUTBOX_ITEM_INVALID job=issue-7-j1 file=issue-7-j1-4-9.json"
e2e_expect_line "line OUTBOX_ITEM_INVALID job=issue-7-j1 file=issue-7-j1-4-8.json"
e2e_expect_line "lines 3"
e2e_expect_line "copy recorded posts 1"

_flow_test_begin "factory github: the drain stops when the pass has no time left (GH24)"
gw_start gh24-enough needs_info
e2e_describe "plan 3.2: the drain checks enough() before each gh call, and when it says no it stops and prints WRITE_DEFERRED job=issue-7-j1 intent=<the item it stopped at> reason=budget (Inferred line, so the pass can tell the drain stopped early). With enough answering no, the drain makes no gh call and prints that line, the item stays recorded and nothing is posted. With enough answering yes for the look-first read and no before the run, the drain makes the one read, prints the same line and posts nothing. With enough answering yes it posts once"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
open(os.path.join(BIN, 'fe-gh-calls.log'), 'w').close()
with jobs.job_lock(P, 7):
    print('no time %s' % G.drain(P, job, GH, tiers(), LOGIN, enough=lambda: False))
with open(os.path.join(BIN, 'fe-gh-calls.log')) as fh:
    print('gh calls %d' % len(fh.read().splitlines()))
print('item %s posts %d' % (items()[i]['status'], len(posts())))
answers = iter([True, False])
open(os.path.join(BIN, 'fe-gh-calls.log'), 'w').close()
with jobs.job_lock(P, 7):
    print('read only %s' % G.drain(P, job, GH, tiers(), LOGIN, enough=lambda: next(answers)))
with open(os.path.join(BIN, 'fe-gh-calls.log')) as fh:
    print('read only gh calls %d' % len(fh.read().splitlines()))
print('read only item %s posts %d' % (items()[i]['status'], len(posts())))
with jobs.job_lock(P, 7):
    print('time %s' % G.drain(P, job, GH, tiers(), LOGIN, enough=lambda: True))
print('item %s posts %d' % (items()[i]['status'], len(posts())))
PY
gw_py "$GW_CODE"
e2e_expect_line "no time ['WRITE_DEFERRED job=issue-7-j1 intent=issue-7-j1-4-1 reason=budget']"
e2e_expect_line "gh calls 0"
e2e_expect_line "item recorded posts 0"
e2e_expect_line "read only ['WRITE_DEFERRED job=issue-7-j1 intent=issue-7-j1-4-1 reason=budget']"
e2e_expect_line "read only gh calls 1"
e2e_expect_line "read only item recorded posts 0"
e2e_expect_line "time ['WRITE_SENT job=issue-7-j1 intent=issue-7-j1-4-1 kind=comment']"
e2e_expect_line "item sent posts 1"

_flow_test_begin "factory github: an edit to the item's recorded fields or status means nothing runs (GH25)"
gw_start gh25-fields prepare
e2e_describe "plan 2.2 and design person_channels L42: the intent_recorded line also holds the item's job, row, state_at_write, ref, kind, blocking and key (Inferred extension of the 2.2 line), and the drain, run_literal and lookup compare them with the item before they act on any of them, the drain's drop rule included. A blocking row-11 assign_label item (state_at_write spec, keys issueAssign and issueUpdate) with issueAssign confirm stays recorded (GH7). Each edit alone, then restored: status set to confirmed (a blocking item is never confirmed in the outbox, Q16 covers notices only, and there is no intent_confirmed line), key cut to [issueUpdate], blocking set to false, row set to 12, ref set to 5, kind set to label_add: each drain prints INTENT_CHANGED=<id> recorded=<hash> current=<hash> field=<that field> and posts nothing. With an intent_confirmed line for the blocking item, status confirmed is still refused (field=status). A row-6 notice under issueUpdate confirm becomes pending_confirm; its state_at_write edited to spec (another state than the job's prepare) gives field=state_at_write and the notice stays pending_confirm, not dropped by the edited value. On a cancelled job, with all keys journal, state_at_write edited to cancelled (so the item would pass as a write of the ending row): field=state_at_write, nothing posted. The same item as the job's pending intent, key edited: run_literal raises IntentChanged with field=key, and lookup raises ReadFailed whose text starts intent_changed"
read -r -d '' GW_CODE <<'PY' || true
job = J()
i = record(job, '11', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True, state='spec')
orig = items()[i]
rec = want(orig['argv'], b'')
for field, value in (('status', 'confirmed'), ('key', ['issueUpdate']), ('blocking', False), ('row', '12'),
                     ('ref', 5), ('kind', 'label_add')):
    put(dict(orig, **{field: value}))
    drain(job, tiers(issueAssign='confirm', issueUpdate='journal'))
    print('%s expected INTENT_CHANGED=%s recorded=%s current=%s field=%s' % (field, i, rec, rec, field))
    put(orig)
print('after edits %s posts %d' % (items()[i]['status'], len(posts())))
with jobs.job_lock(P, 7):
    jobs.append_event(P, 7, {'type': 'intent_confirmed', 'job': 'issue-7-j1', 'id': i})
put(dict(orig, status='confirmed'))
drain(job, tiers(issueAssign='confirm', issueUpdate='journal'))
print('lined expected INTENT_CHANGED=%s recorded=%s current=%s field=status' % (i, rec, rec))
print('lined posts %d' % len(posts()))
put(orig)
nt = record(job, '6', 'comment', G.literal_comment(REPO, 7), 'Accepted.', ['issueUpdate'], False, state='prepare')
drain(job, tiers(issueUpdate='confirm'))
pend = items()[nt]
nrec = want(pend['argv'], body_of(pend))
put(dict(pend, state_at_write='spec'))
drain(job, tiers(issueUpdate='confirm'))
print('notice expected INTENT_CHANGED=%s recorded=%s current=%s field=state_at_write' % (nt, nrec, nrec))
print('notice %s' % items()[nt]['status'])
put(dict(orig, state_at_write='cancelled'))
drain(dict(job, state='cancelled'), tiers())
print('state_at_write expected INTENT_CHANGED=%s recorded=%s current=%s field=state_at_write' % (i, rec, rec))
print('cancelled posts %d' % len(posts()))
put(dict(orig, key=['issueUpdate']))
parked = dict(job, state='waiting_operator', pending_intent={'id': i, 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']})
try:
    with jobs.job_lock(P, 7):
        G.run_literal(P, parked, i, GH, LOGIN)
    print('run_literal ran')
except G.IntentChanged as e:
    print('run_literal %s' % e.line)
try:
    print('lookup answered %s' % G.lookup(GH, parked, i, LOGIN))
except G.ReadFailed as e:
    print('lookup ReadFailed %s' % str(e).split(' ')[0])
print('end posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
for GW_T in status key blocking row ref kind lined notice state_at_write; do
  GW_WANT=$(printf '%s\n' "$E2E_OUT" | sed -n "s/^$GW_T expected //p")
  e2e_expect_line "line $GW_WANT"
done
e2e_expect_line "after edits recorded posts 0"
e2e_expect_line "notice pending_confirm"
e2e_expect_line "lined posts 0"
e2e_expect_line "cancelled posts 0"
e2e_expect_line "run_literal $(printf '%s\n' "$E2E_OUT" | sed -n 's/^key expected //p')"
e2e_expect_line "lookup ReadFailed intent_changed"
e2e_expect_line "end posts 0"

_flow_test_begin "factory github: lookup refuses an intent whose argv was edited (GH26)"
gw_start gh26-lookup waiting_operator "d['resume_state'] = 'prepare'; d['reason'] = 'tier_confirm'; d['pending_intent'] = {'id': 'issue-7-j1-40-1', 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']}"
fe_world_issue 8 "Another issue" "Not this job's issue."
e2e_describe "plan 3.1 (intent_effect_observed) and design person_channels L42: the pending assign_label intent issue-7-j1-40-1 is for issue 7, and issue 8 has the engine as assignee and the in-progress label. With the argv edited to name issue 8, lookup raises ReadFailed whose text starts intent_changed (so row 41e's fact fails rather than reads true from another issue); restored, it returns None, since issue 7 has neither"
read -r -d '' GW_CODE <<'PY' || true
w = world()
w['issues']['8']['assignees'] = [LOGIN]
w['issues']['8']['labels'] = [LABEL]
with open(os.environ['FE_WORLD'], 'w') as fh:
    json.dump(w, fh)
job = J()
p = record(job, '40', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True)
orig = items()[p]
put(dict(orig, argv=G.literal_assign_label(REPO, 8, LOGIN, LABEL)))
try:
    print('edited answered %s' % G.lookup(GH, job, p, LOGIN))
except G.ReadFailed as e:
    print('edited ReadFailed %s' % str(e).split(' ')[0])
put(orig)
print('restored %s' % G.lookup(GH, job, p, LOGIN))
PY
gw_py "$GW_CODE"
e2e_expect_line "edited ReadFailed intent_changed"
e2e_expect_line "restored None"

_flow_test_begin "factory github: a process that dies between the record and the item leaves nothing that blocks the write (GH27)"
gw_start gh27-die needs_info
e2e_describe "plan 2.2 ('Dedupe before recording') and 5.2: the intent_recorded line is appended before the item file is written, so a process that dies between the two leaves a record with no item, never an item with no record. (1) The process dies inside the events append of an answer to comment 31: no item is left, and the next record_job_intent of the same kind, row and ref records it (one item, issue-7-j1-8u-1) and the drain posts it (WRITE_SENT, one post), with no INTENT_CHANGED line. (2) The process dies while writing the item of an answer to comment 32, after its record: no item; the next record_job_intent with another text gets the same id issue-7-j1-8u-2 (k counts items and write_seq, plan 2.2), its newer record is the one compared (the last intent_recorded line for an id), and the drain posts the new text once"
read -r -d '' GW_CODE <<'PY' || true
job = J()
jobs.append_event = lambda *a, **k: os._exit(9)
record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Retry needed.', ['issueUpdate'], False, ref=31)
print('survived')
PY
gw_py "$GW_CODE"
e2e_expect_no_line "survived"
read -r -d '' GW_CODE <<'PY' || true
print('left items %d records %d' % (len(items()), len(events('intent_recorded'))))
job = J()
i = record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Retry needed.', ['issueUpdate'], False, ref=31)
print('id %s' % i)
drain(job, tiers())
print('posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "left items 0 records 0"
e2e_expect_line "id issue-7-j1-8u-1"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-8u-1 kind=comment"
e2e_expect_line "lines 1"
e2e_expect_line "posts 1"
read -r -d '' GW_CODE <<'PY' || true
job = J()
real_write = G._atomic_write
def dying(path, *a, **k):
    if path.endswith('.json'):
        os._exit(9)
    return real_write(path, *a, **k)
G._atomic_write = dying
record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Other reply.', ['issueUpdate'], False, ref=32)
print('survived')
PY
gw_py "$GW_CODE"
e2e_expect_no_line "survived"
read -r -d '' GW_CODE <<'PY' || true
print('left items %d records %d' % (len(items()), len(events('intent_recorded'))))
job = J()
i = record(job, '8u', 'comment', G.literal_comment(REPO, 7), 'Other reply, again.', ['issueUpdate'], False, ref=32)
print('id %s' % i)
drain(job, tiers())
print('posts %d last %s' % (len(posts()), 'Other reply, again.' in posts()[-1]['body']))
PY
gw_py "$GW_CODE"
e2e_expect_line "id issue-7-j1-8u-2"
e2e_expect_line "line WRITE_SENT job=issue-7-j1 intent=issue-7-j1-8u-2 kind=comment"
e2e_expect_line "lines 1"
e2e_expect_line "posts 2 last True"

_flow_test_begin "factory github: an item file or an outbox folder that is a symbolic link is not run (GH28)"
gw_start gh28-links needs_info
e2e_describe "plan 2.2 (the item is J/outbox/<id>.json) and the factory's no-symlink rule for its own files: (1) the item issue-7-j1-4-1.json moved out of the outbox and replaced by a symbolic link to it (same content): the drain prints OUTBOX_ITEM_INVALID job=issue-7-j1 file=issue-7-j1-4-1.json and posts nothing; (2) the whole J/outbox folder moved to J/outbox-real and J/outbox made a symbolic link to it: the drain reads nothing (no line) and posts nothing"
read -r -d '' GW_CODE <<PY || true
job = J()
i = record(job, '4', 'comment', G.literal_comment(REPO, 7), 'Please answer NI-1.', ['issueUpdate'], False)
os.makedirs('$E2E_DIR/elsewhere')
os.rename(os.path.join(OUT, i + '.json'), '$E2E_DIR/elsewhere/' + i + '.json')
os.symlink('$E2E_DIR/elsewhere/' + i + '.json', os.path.join(OUT, i + '.json'))
drain(job, tiers())
print('item link posts %d' % len(posts()))
os.remove(os.path.join(OUT, i + '.json'))
os.rename('$E2E_DIR/elsewhere/' + i + '.json', os.path.join(OUT, i + '.json'))
os.rename(OUT, os.path.join(JD, 'outbox-real'))
os.symlink(os.path.join(JD, 'outbox-real'), OUT)
drain(job, tiers())
print('folder link posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "line OUTBOX_ITEM_INVALID job=issue-7-j1 file=issue-7-j1-4-1.json"
e2e_expect_line "item link posts 0"
e2e_expect_line "lines 0"
e2e_expect_line "folder link posts 0"

_flow_test_begin "factory github: a write found by the look-first step leaves no breadcrumb (GH29)"
gw_start gh29-found waiting_operator "d['resume_state'] = 'prepare'; d['reason'] = 'tier_confirm'; d['pending_intent'] = {'id': 'issue-7-j1-40-1', 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']}"
gw_journal
fe_world_comment 7 9 flow-e2e-engine write 2026-11-17T00:00:00Z "<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-40-2 -->
Waiting for a confirm."
e2e_describe "design github_writes_and_tiers L50 ('journal: run, plus one breadcrumb') and stages L11: the breadcrumb goes with running the literal, so a write the look-first step finds is recorded with no run and no breadcrumb. With every key journal and a journal folder: the pending assign_label intent issue-7-j1-40-1, whose assignee and label are already on issue 7, run through run_literal with a tiers callable, is WRITE_SKIPPED found=flow:in-progress; the notice issue-7-j1-40-2, whose marker comment 9 the engine already posted, is WRITE_SKIPPED found=9 by the drain; nothing is posted and issue 7's trail has no breadcrumb"
read -r -d '' GW_CODE <<'PY' || true
w = world()
w['issues']['7']['assignees'] = [LOGIN]
w['issues']['7']['labels'] = [LABEL]
with open(os.environ['FE_WORLD'], 'w') as fh:
    json.dump(w, fh)
job = J()
p = record(job, '40', 'assign_label', G.literal_assign_label(REPO, 7, LOGIN, LABEL), None,
           ['issueAssign', 'issueUpdate'], True)
n = record(job, '40', 'comment', G.literal_comment(REPO, 7), 'Waiting for a confirm.', ['issueUpdate'], False)
lines = []
with jobs.job_lock(P, 7):
    G.run_literal(P, job, p, GH, LOGIN, tiers=tiers(), lines=lines)
print('run_literal %s' % lines)
drain(job, tiers())
print('posts %d' % len(posts()))
PY
gw_py "$GW_CODE"
e2e_expect_line "run_literal ['WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-40-1 found=flow:in-progress']"
e2e_expect_line "line WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-40-2 found=9"
e2e_expect_line "posts 0"
e2e_expect_equal "0" "$(gw_trail)" "breadcrumbs in issue 7's trail"
