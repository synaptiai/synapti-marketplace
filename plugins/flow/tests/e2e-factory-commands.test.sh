# shellcheck shell=bash
# The factory's /flow-factory comment commands (bin/_flow_factory_commands.py,
# plan 1b B5; design person_channels item 5, L54-L58 and L66; runner L14),
# run in isolation through fe_py. The issue is read by the issue module's
# read_issue and Permissions over the factory gh stand-in (engine/gh with a
# world file), so the commands are found in what the sync reads. The rows
# that apply the stored events through `next` are added by a later task
# (plan B14).
#
# Ways it can be wrong, written down before the code:
#   CM1  (R18, design stages L8) a command or a marker matched anywhere but
#        line 1; an engine notice with a command on line 2 raised; a person
#        command that quotes a marker on line 3 not raised
#   CM2  (R17, R58, L57) the "after the latest marker" floor read from
#        updated_at, or at or after rather than strictly after; a marker
#        posted by another login moving the floor; no floor before the job's
#        first marker, so a command left for an earlier job is raised; a
#        marker older than vouch_at used as the floor; a command whose time
#        cannot be read, or a job with no vouch_at, raising anything
#   CM3  (R19) spec raised as a person event or refused with a note
#   CM4  (R90, L54, L55) trust taken from the role alone, so a bot with write
#        raises a command; triage counted for anything but retry; a triage
#        retry not marked retry_by_triage_only; a listed bot not trusted
#   CM5  (R16, R78) the same comment raised in two passes; the pending-file
#        check missing, so a crash between the store and commands_seen gives
#        two events; commands_seen not kept, or kept in job.json only with no
#        events line for rebuild
#   CM6  (L15) a command whose event does not occur in the job's state raised,
#        or refused with no note; the note posted twice for one comment
#   CM7  (R57, runner L14, Q17) arguments parsed through a shell or changed;
#        a malformed command (missing text, short or upper-case hash, extra
#        words after a command that takes none, a word glued to the name)
#        raised instead of refused with a note; an NI answer outside
#        needs_info and needs_human, or naming a question the job never
#        asked, raised; an NI answer in needs_human refused, although the
#        terminal answer takes it there (rows 44v, 44u, 44w, 44x and 44q)
#   CM8  (L66) an untrusted command stored, noted, or listed with its text;
#        listed again on every later pass (plan B5 outline 5: one line); a
#        failed permission read marking the comment as seen, so the
#        person's command is lost for good; an author whose type is neither
#        User nor Bot (an Organization, a Mannequin) trusted by its role
#   CM9  (R56, L56) a queue-label removal by triage or a bot cancelling or
#        getting no note; a removal before vouch_at, of another label, or by
#        write access noted; the note posted twice
#   CM10 (5.3 pending event) a pending file that does not validate against
#        the pending_event schema, a comment channel stored without its
#        comment object or with another comment's id, or a comment object on
#        another channel
#   CM11 a note that echoes the comment's text (an @mention, a marker) into
#        the engine's own post
#
# Every expected value is written out by hand from the design line or risk
# row named in the scenario, never from the module's output.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# cm_start <name> <state> [python statements for fe_job] — a scratch
# repository, the world (engine login flow-e2e-engine with write, repository
# flow-e2e/scratch, open issue 7 labelled flow:factory by wrt at T1), the
# probe record (which makes F) and job issue-7-j1 in <state> with vouch_at T1
# unless the statements change it.
cm_start() {
  fe_new "$1"
  e2e_repo main
  fe_world_new flow-e2e-engine flow-e2e/scratch
  fe_world_perm flow-e2e-engine write
  fe_record
  fe_world_issue 7 "Add a port setting" "The service needs a port setting."
  fe_world_label 7 flow:factory wrt write 2026-11-18T10:00:00Z
  fe_job 7 "$2" "d['vouch_at'] = '2026-11-18T10:00:00Z'
${3:-}"
}

# cm_c <id> <author> <role> <time> <body> — a comment on issue 7.
cm_c() { fe_world_comment 7 "$@"; }

# The Python every scenario starts with (fe_py runs it with -E, bin/ first on
# sys.path, in the scratch environment):
#   gh(args)        Pass.gh's contract over the stand-in, through ff.run_cmd
#   SET, setting    the settings the scenario gives (else the default)
#   T0..T5          times an hour apart; T1 is the job's vouch_at
#   scan(job)       read issue 7 with read_issue and a new Permissions, then
#                   C.scan; prints one cmd line per command and a cmds list
#   store(job, c)   C.store under the job lock; prints each status line
#   pending()       the records in J/pending, oldest first
#   items()         the outbox items, by id
read -r -d '' CM_PRE <<'PY' || true
import sys
sys.dont_write_bytecode = True
import json, os
import _flow_factory as ff
import _flow_factory_jobs as jobs
import _flow_factory_schema as schema
import _flow_factory_issue as I
import _flow_factory_commands as C
P = jobs.resolve()
REPO = 'flow-e2e/scratch'
LOGIN = 'flow-e2e-engine'
GH = ff.which_real('gh')
JD = os.path.join(P.fdir, 'jobs', 'issue-7')
OUTBOX_SCHEMA = os.path.join(ff.PLUGIN_ROOT, 'schemas', 'v1', 'factory-outbox.schema.json')
def gh(args):
    rc, out, err = ff.run_cmd([GH] + list(args), os.getcwd(), dict(os.environ), timeout=30)
    if rc != 0:
        return False, None
    try:
        return True, json.loads(out)
    except ValueError:
        return False, None
SET = {}
def setting(key, default=None):
    return SET.get(key, default)
T0, T1, T2, T3, T4, T5 = ('2026-11-18T09:00:00Z', '2026-11-18T10:00:00Z', '2026-11-18T11:00:00Z',
                          '2026-11-18T12:00:00Z', '2026-11-18T13:00:00Z', '2026-11-18T14:00:00Z')
def J():
    return jobs.read_job(P, 7)
def perms():
    return I.Permissions(gh, REPO, setting)
def show(cmds, only=None):
    cmds = [c for c in cmds if only is None or c['comment_id'] in only]
    for c in cmds:
        print('cmd %s %s raise=%s trusted=%s triage_only=%s event=%s args=%s note=%s' % (
            c['comment_id'], c['name'], c['raise'], c['trusted'], c['triage_only'], c['event'],
            json.dumps(c['args'], sort_keys=True), 'yes' if c['note'] else 'no'))
    print('cmds %s' % [c['comment_id'] for c in cmds])
def scan(job, p=None, only=None):
    p = p or perms()
    snap = I.read_issue(gh, REPO, 7, job, p)
    if snap is None:
        print('snapshot none')
        return []
    cmds = C.scan(snap, job, p, LOGIN)
    show(cmds, only)
    return cmds
def store(job, cmd):
    with jobs.job_lock(P, 7):
        lines = C.store(P, job, cmd, repo=REPO)
    for ln in lines:
        print('line ' + ln)
    return lines
def pending():
    return [rec for _name, rec in jobs.pending_events(P, 7)]
def items():
    out = {}
    d = os.path.join(JD, 'outbox')
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith('.json'):
                with open(os.path.join(d, f), encoding='utf-8') as fh:
                    out[f[:-5]] = json.load(fh)
    return out
def body(item):
    with open(os.path.join(JD, 'outbox', item['body_file']), encoding='utf-8') as fh:
        return fh.read()
def events(t):
    out = []
    try:
        with open(os.path.join(JD, 'events.jsonl'), encoding='utf-8') as fh:
            for ln in fh:
                d = json.loads(ln)
                if d.get('type') == t:
                    out.append(d)
    except OSError:
        pass
    return out
def state(job, s, **kw):
    d = dict(job, state=s)
    d.update(kw)
    return d
NI1 = {'asked_at': T1, 'questions': ['NI-1'], 'round': 1, 'earlier': []}
def world(edit):
    p = os.environ['FE_WORLD']
    with open(p, encoding='utf-8') as fh:
        w = json.load(fh)
    edit(w)
    with open(p, 'w', encoding='utf-8') as fh:
        json.dump(w, fh)
PY

cm_py() { fe_py "$CM_PRE
$1"; }

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: trusted commands become pending person events with their comment (CM3, CM4, CM5, CM10)"
cm_start cm-raise needs_info "d['needs_info'] = {'asked_at': '2026-11-18T10:00:00Z', 'questions': ['NI-1'], 'round': 1, 'earlier': []}"
fe_world_perm tri triage
cm_c 11 wrt write 2026-11-18T11:00:00Z '/flow-factory answer NI-1 use port 8080'
cm_c 12 wrt write 2026-11-18T11:05:00Z '/flow-factory retry'
cm_c 13 tri triage 2026-11-18T11:10:00Z '/flow-factory retry'
cm_c 14 wrt write 2026-11-18T11:15:00Z '/flow-factory cancel'
cm_c 15 wrt write 2026-11-18T11:20:00Z '/flow-factory spec also log the port'
cm_c 16 wrt write 2026-11-18T11:25:00Z 'thanks, NI-1 is clear'
cm_c 17 wrt write 2026-11-18T11:30:00Z '/flow-factory foo NI-1 x'
e2e_describe "a needs_info job (vouch_at T1, round 1 asks NI-1). Expected: design person_channels L54 (write or higher counts; retry also from triage, marked retry_by_triage_only, L55), Q17 (/flow-factory answer NI-<k> <text> gives a person_answer with qid and text, plan 5.3 Context args {qid, text}), R19 (spec raises nothing: it is spec input), plan 3.1 (an unknown /flow-factory word raises nothing and posts nothing), T:events (person_answer, person_retry and person_cancel occur in needs_info). Stored: one pending file per command, channel comment:<id>, facts unvouched_session_action false, via_comment true and retry_by_triage_only (plan 2.2 Pending person event), a comment object {id, author, permission, created_at} with the author's role_name, each valid against the pending_event shape of factory-directive.schema.json; commands_seen [11, 12, 13, 14] in job.json and in one commands_seen events line carrying the whole list (plan 2.2, LOGGED_LISTS); no outbox item"
read -r -d '' CM_CODE <<'PY' || true
job = J()
cmds = scan(job)
for c in cmds:
    store(job, c)
recs = pending()
for r in recs:
    print('pending %s %s %s facts=%s comment=%s valid=%s' % (
        r['event'], r['channel'], json.dumps(r['args'], sort_keys=True), json.dumps(r['facts'], sort_keys=True),
        json.dumps(r['comment'], sort_keys=True),
        schema.validate(r, jobs.DIRECTIVE_SCHEMA, 'pending_event')))
print('pending count %d' % len(recs))
print('seen %s' % J().get('commands_seen'))
print('seen lines %s' % [e['commands_seen'] for e in events('commands_seen')])
print('outbox %d' % len(items()))
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line 'cmd 11 answer raise=True trusted=True triage_only=False event=person_answer args={"qid": "NI-1", "text": "use port 8080"} note=no'
e2e_expect_line 'cmd 12 retry raise=True trusted=True triage_only=False event=person_retry args={} note=no'
e2e_expect_line 'cmd 13 retry raise=True trusted=True triage_only=True event=person_retry args={} note=no'
e2e_expect_line 'cmd 14 cancel raise=True trusted=True triage_only=False event=person_cancel args={} note=no'
e2e_expect_line "cmds [11, 12, 13, 14]"
e2e_expect_line 'pending person_answer comment:11 {"qid": "NI-1", "text": "use port 8080"} facts={"retry_by_triage_only": false, "unvouched_session_action": false, "via_comment": true} comment={"author": "wrt", "created_at": "2026-11-18T11:00:00Z", "id": 11, "permission": "write"} valid=[]'
e2e_expect_line 'pending person_retry comment:12 {} facts={"retry_by_triage_only": false, "unvouched_session_action": false, "via_comment": true} comment={"author": "wrt", "created_at": "2026-11-18T11:05:00Z", "id": 12, "permission": "write"} valid=[]'
e2e_expect_line 'pending person_retry comment:13 {} facts={"retry_by_triage_only": true, "unvouched_session_action": false, "via_comment": true} comment={"author": "tri", "created_at": "2026-11-18T11:10:00Z", "id": 13, "permission": "triage"} valid=[]'
e2e_expect_line 'pending person_cancel comment:14 {} facts={"retry_by_triage_only": false, "unvouched_session_action": false, "via_comment": true} comment={"author": "wrt", "created_at": "2026-11-18T11:15:00Z", "id": 14, "permission": "write"} valid=[]'
e2e_expect_line "pending count 4"
e2e_expect_line "seen [11, 12, 13, 14]"
e2e_expect_line "seen lines [[11], [11, 12], [11, 12, 13], [11, 12, 13, 14]]"
e2e_expect_line "outbox 0"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: only line 1 counts, after the latest engine marker and after vouch_at (CM1, CM2)"
cm_start cm-floor needs_human
fe_world_perm rdr read
# 30: a command for an earlier job, before this job's vouch_at T1 (R58).
cm_c 30 wrt write 2026-11-18T09:30:00Z '/flow-factory cancel'
# 31: the engine's marker at T2, with a command on its line 2 (R18).
cm_c 31 flow-e2e-engine write 2026-11-18T11:00:00Z '<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->
/flow-factory reject'
# 32: created between vouch_at and the marker, edited after it (R17).
cm_c 32 wrt write 2026-11-18T10:30:00Z '/flow-factory reject'
_fe_world "comment 32 edited at T4" '.comments["7"] |= map(if .id == 32 then .updated_at = "2026-11-18T13:00:00Z" else . end)'
# 33: a marker line posted by another login at T3; it must not move the floor.
cm_c 33 rdr read 2026-11-18T12:00:00Z '<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-9 -->'
# 34: after the engine marker, before the forged one.
cm_c 34 wrt write 2026-11-18T11:30:00Z '/flow-factory reject'
# 35: a person command quoting a marker on line 3 (R18).
cm_c 35 wrt write 2026-11-18T13:00:00Z '/flow-factory retry
I read this notice:
<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->'
# 36: the engine's own login without a marker: the person signed in as it.
cm_c 36 flow-e2e-engine write 2026-11-18T13:30:00Z '/flow-factory cancel'
# 37: at exactly the marker's time.
cm_c 37 wrt write 2026-11-18T11:00:00Z '/flow-factory cancel'
# 38: a command on line 2 only.
cm_c 38 wrt write 2026-11-18T13:40:00Z 'Please stop this.
/flow-factory cancel'
e2e_describe "a needs_human job, vouch_at T1. Expected: design person_channels L57 (posted after the factory's latest marker: created_at, strictly after), plan 5.3 Engine marker (the floor moves only for a marker from the engine login, R10), R17 (32 was created before the marker; its edit after it does not count), R18 (31's command is on line 2 of an engine notice; 35 quotes a marker on line 3 and is a command; 38's command is on line 2), R58 (30 is before vouch_at), and a person signed in as the engine login (person_channels L59-L60) still commands (36). Raised: 34, 35, 36. With vouch_at T3, later than the marker, the floor is vouch_at and 34 is no longer raised (plan B5 outline 3, Inferred: the floor is the later of the two). With vouch_at null, or a comment time that cannot be read, nothing is raised (fail closed); so is an engine marker whose time cannot be read, since the floor is then unknown"
read -r -d '' CM_CODE <<'PY' || true
job = J()
scan(job)
print('-- vouch T3')
scan(state(job, 'needs_human', vouch_at=T3))
print('-- vouch null')
scan(state(job, 'needs_human', vouch_at=None))
print('-- bad time')
snap = I.read_issue(gh, REPO, 7, job, perms())
for c in snap['comments']:
    if c['id'] == 36:
        c['created_at'] = 'not a time'
show(C.scan(snap, job, perms(), LOGIN))
print('-- engine marker with an unreadable time')
snap = I.read_issue(gh, REPO, 7, job, perms())
for c in snap['comments']:
    if c['id'] == 31:
        c['created_at'] = 'not a time'
print('bad-marker %s' % [c['comment_id'] for c in C.scan(snap, job, perms(), LOGIN)])
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "bad-marker []"
e2e_expect_line "cmds [34, 35, 36]"
e2e_expect_line 'cmd 34 reject raise=True trusted=True triage_only=False event=person_reject args={} note=no'
e2e_expect_line 'cmd 35 retry raise=True trusted=True triage_only=False event=person_retry args={} note=no'
e2e_expect_line 'cmd 36 cancel raise=True trusted=True triage_only=False event=person_cancel args={} note=no'
e2e_expect_line "cmds [35, 36]"
e2e_expect_line "cmds []"
e2e_expect_line "cmds [34, 35]"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: untrusted and bot commands raise nothing and are listed by author, time and length only (CM4, CM8)"
cm_start cm-trust queued "d['needs_info'] = {'asked_at': '2026-11-18T10:00:00Z', 'questions': ['NI-1'], 'round': 1, 'earlier': []}"
fe_world_perm 'botri[bot]' triage
fe_world_actor_type deploy-app Bot
fe_world_actor_type orgacct Organization
cm_c 41 rdr read 2026-11-18T11:00:00Z '/flow-factory cancel'
cm_c 42 'ci[bot]' write 2026-11-18T11:01:00Z '/flow-factory cancel'
cm_c 43 deploy-app write 2026-11-18T11:02:00Z '/flow-factory cancel'
cm_c 44 'botri[bot]' triage 2026-11-18T11:03:00Z '/flow-factory retry'
cm_c 45 tri triage 2026-11-18T11:04:00Z '/flow-factory cancel'
cm_c 46 rdr read 2026-11-18T11:05:00Z '/flow-factory answer NI-1 use port 8080'
cm_c 47 err status:500 2026-11-18T11:06:00Z '/flow-factory cancel'
cm_c 48 orgacct write 2026-11-18T11:07:00Z '/flow-factory cancel'
e2e_describe "design person_channels L54 and R90: a [bot] login or a Bot type is untrusted whatever its role unless trustedBots lists it (ci[bot] write, deploy-app of type Bot with write, botri[bot] triage on retry); triage counts for retry only (45); read access (41, 46) and a failed permission read (47) are untrusted; an author of type Organization with write (48) is untrusted (plan AC2: an unknown account fails closed; L54 trusts a person's role, and names Bot as the other type). L66: an untrusted command is ignored and listed by author, date and length only: one UNTRUSTED_COMMAND job=<key> comment=<id> author=<login> at=<t> length=<n> line (plan 2.3), length the body's characters, no pending file and no outbox item (the read-only answer gets no row 8u notice, plan 3.1). Each comment is scanned and stored in two passes here, and plan B5 outline 5 asks for one line per comment, so each id is listed once, recorded by one untrusted_command events line per comment. Inferred: an untrusted command is not added to commands_seen, because L54 judges trust by the permission read of each sync (cached for one sync, a failed read untrusted), so a permission read that failed once does not lose a later trusted reading of it: with err's read answering write in a later sync, 47 is stored. With trustedBots [deploy-app] its cancel is stored (R90: for a listed bot the role decides)"
read -r -d '' CM_CODE <<'PY' || true
job = J()
cmds = scan(job)
cmds += scan(state(job, 'needs_info'))
for c in cmds:
    store(job, c)
print('pending %d outbox %d seen %s lines %d' % (len(pending()), len(items()), J().get('commands_seen'),
                                                len(events('commands_seen'))))
print('recorded %s' % sorted(e['comment'] for e in events('untrusted_command')))
SET['flow.factory.trustedBots'] = ['deploy-app']
job = J()
for c in scan(job):
    if c['comment_id'] == 43:
        store(job, c)
print('listed %s' % [(r['event'], r['channel']) for r in pending()])
print('-- a later sync reads err as write')
world(lambda w: w['permissions'].update(err={'role_name': 'write', 'permission': 'write'}))
job = J()
for c in scan(job, only=(47,)):
    store(job, c)
print('later %s seen %s' % ([(r['event'], r['channel']) for r in pending()], J().get('commands_seen')))
print('-- a later job on the same issue')
c41 = [c for c in cmds if c['comment_id'] == 41][0]
store(dict(J(), key='issue-7-j2'), c41)
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line 'cmd 41 cancel raise=False trusted=False triage_only=False event=person_cancel args={} note=no'
e2e_expect_line 'cmd 42 cancel raise=False trusted=False triage_only=False event=person_cancel args={} note=no'
e2e_expect_line 'cmd 43 cancel raise=False trusted=False triage_only=False event=person_cancel args={} note=no'
e2e_expect_line 'cmd 45 cancel raise=False trusted=False triage_only=False event=person_cancel args={} note=no'
e2e_expect_line 'cmd 47 cancel raise=False trusted=False triage_only=False event=person_cancel args={} note=no'
e2e_expect_line 'cmd 44 retry raise=False trusted=False triage_only=False event=person_retry args={} note=no'
e2e_expect_line 'cmd 46 answer raise=False trusted=False triage_only=False event=person_answer args={} note=no'
e2e_expect_line "line UNTRUSTED_COMMAND job=issue-7-j1 comment=41 author=rdr at=2026-11-18T11:00:00Z length=20"
e2e_expect_line "line UNTRUSTED_COMMAND job=issue-7-j1 comment=42 author=ci[bot] at=2026-11-18T11:01:00Z length=20"
e2e_expect_line "line UNTRUSTED_COMMAND job=issue-7-j1 comment=46 author=rdr at=2026-11-18T11:05:00Z length=39"
e2e_expect_line "line UNTRUSTED_COMMAND job=issue-7-j1 comment=47 author=err at=2026-11-18T11:06:00Z length=20"
e2e_expect_line 'cmd 48 cancel raise=False trusted=False triage_only=False event=person_cancel args={} note=no'
e2e_expect_line "line UNTRUSTED_COMMAND job=issue-7-j1 comment=48 author=orgacct at=2026-11-18T11:07:00Z length=20"
# A later job on the same issue keeps its events in the same folder; the
# listing is per job and comment, so its own first store lists 41 once.
e2e_expect_line "line UNTRUSTED_COMMAND job=issue-7-j2 comment=41 author=rdr at=2026-11-18T11:00:00Z length=20"
# One line per comment although every comment was stored in two passes.
for CM_ID in 41 42 43 44 45 46 47 48; do
  e2e_expect_equal "1" "$(grep -c "^line UNTRUSTED_COMMAND job=issue-7-j1 comment=$CM_ID " <<<"$E2E_OUT")" \
    "UNTRUSTED_COMMAND lines for comment $CM_ID"
done
e2e_expect_line "pending 0 outbox 0 seen None lines 0"
e2e_expect_line "recorded [41, 42, 43, 44, 45, 46, 47, 48]"
e2e_expect_line "listed [('person_cancel', 'comment:43')]"
e2e_expect_line "later [('person_cancel', 'comment:43'), ('person_cancel', 'comment:47')] seen [43, 47]"
# The answer's text is listed nowhere (L66: author, date and length only).
e2e_expect_no_out "use port"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: a comment is raised once, and a crash between the store and commands_seen gives one event (CM5, R16, R78)"
cm_start cm-once queued
cm_c 51 wrt write 2026-11-18T11:00:00Z '/flow-factory cancel'
e2e_describe "person_channels L78 (one action per comment) and plan B5 outline 4: store stores nothing when J/pending already holds a file whose channel is comment:<id>, then adds the id to commands_seen. Pass 1 stores one person_cancel. Pass 2 finds 51 in commands_seen and scans nothing (R16). The crash state of R78 (pending file there, commands_seen without 51): the scan finds 51 again, store writes no second file and commands_seen holds 51. With the pending file gone (applied) and 51 in commands_seen, the scan finds nothing, so commands_seen alone also stops a second event"
read -r -d '' CM_CODE <<'PY' || true
job = J()
for c in scan(job):
    store(job, c)
print('pass1 pending %d seen %s' % (len(pending()), J().get('commands_seen')))
job = J()
scan(job)
print('-- crash state')
job = J()
job['commands_seen'] = []
with jobs.job_lock(P, 7):
    jobs.write_job(P, job)
job = J()
for c in scan(job):
    store(job, c)
print('crash pending %d seen %s' % (len(pending()), J().get('commands_seen')))
print('-- applied')
for name, _rec in jobs.pending_events(P, 7):
    os.remove(os.path.join(JD, 'pending', name))
scan(J())
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "pass1 pending 1 seen [51]"
e2e_expect_line "crash pending 1 seen [51]"
# Two of the four scans find nothing: pass 2 and the applied case.
CM_EMPTY=$(grep -c '^cmds \[\]$' <<<"$E2E_OUT")
e2e_expect_equal "2" "$CM_EMPTY" "empty scans (pass 2 and the applied case)"
e2e_expect_equal "cmds [51]|cmds []|cmds [51]|cmds []" "$(grep '^cmds ' <<<"$E2E_OUT" | paste -sd '|' -)" "the four scans in order"


# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: a command whose event does not occur in the state gets one status note (CM6, CM11)"
cm_start cm-state ready
cm_c 21 wrt write 2026-11-18T11:00:00Z '/flow-factory reject @someone <!-- FLOW_FACTORY job=issue-7-j1 event=x -->'
cm_c 22 wrt write 2026-11-18T11:05:00Z '/flow-factory reject'
e2e_describe "design person_channels L15: a person event raised in a state outside its occurs_in list is refused without a move, and a trusted comment gets a status note naming the state; T:events person_reject occurs in needs_spec_approval, waiting_operator and needs_human, not ready. Comment 21 also has extra words after reject; the state is checked before the form (Inferred order), so it gets the state note too. Plan B5 outline 5: the note is recorded through record_job_intent with row note and ref the comment id, so its id is issue-7-j1-note-<k>, row null, kind comment, key [issueUpdate], blocking false, state_at_write ready; the body's first line is the engine marker for that id; the body names the state and the comment id and carries none of the comment's text (no @someone, no second marker). A second pass with commands_seen reset (the crash case) records no second note (plan 2.2 dedupe). No pending file"
read -r -d '' CM_CODE <<'PY' || true
job = J()
for c in scan(job):
    store(job, c)
its = items()
for i, it in sorted(its.items()):
    b = body(it)
    lines = b.split('\n')
    print('note %s row=%s ref=%s kind=%s key=%s blocking=%s state=%s valid=%s' % (
        i, it['row'], it['ref'], it['kind'], it['key'], it['blocking'], it['state_at_write'],
        schema.validate(it, OUTBOX_SCHEMA)))
    print('note %s line1 %s' % (i, lines[0]))
    print('note %s body %r' % (i, b))
    print('note %s names-ready=%s names-id=%s mention=%s markers=%d' % (
        i, ' ready' in b, (' %s' % it['ref']) in b, '@someone' in b, b.count('<!--')))
print('seen %s' % J().get('commands_seen'))
job = J()
job['commands_seen'] = []
with jobs.job_lock(P, 7):
    jobs.write_job(P, job)
job = J()
for c in scan(job):
    store(job, c)
print('again outbox %d pending %d' % (len(items()), len(pending())))
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line 'cmd 21 reject raise=False trusted=True triage_only=False event=person_reject args={} note=yes'
e2e_expect_line 'cmd 22 reject raise=False trusted=True triage_only=False event=person_reject args={} note=yes'
e2e_expect_line "note issue-7-j1-note-1 row=None ref=21 kind=comment key=['issueUpdate'] blocking=False state=ready valid=[]"
e2e_expect_line "note issue-7-j1-note-1 line1 <!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-note-1 -->"
e2e_expect_line "note issue-7-j1-note-1 names-ready=True names-id=True mention=False markers=1"
e2e_expect_line "note issue-7-j1-note-2 row=None ref=22 kind=comment key=['issueUpdate'] blocking=False state=ready valid=[]"
e2e_expect_line "note issue-7-j1-note-2 names-ready=True names-id=True mention=False markers=1"
e2e_expect_line "seen [21, 22]"
e2e_expect_line "again outbox 2 pending 0"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: arguments are parsed without a shell and malformed commands get a note (CM7)"
cm_start cm-args needs_info "d['needs_info'] = {'asked_at': '2026-11-18T09:00:00Z', 'questions': ['NI-2'], 'round': 2, 'earlier': [{'asked_at': '2026-11-18T08:00:00Z', 'questions': ['NI-1'], 'round': 1}]}"
cm_c 61 wrt write 2026-11-18T11:00:00Z '/flow-factory approve-spec 0123456789ab'
cm_c 62 wrt write 2026-11-18T11:01:00Z '/flow-factory approve-spec 0123456789abcdef fedcba9876543210'
cm_c 63 wrt write 2026-11-18T11:02:00Z '/flow-factory approve-spec 0123abc'
cm_c 64 wrt write 2026-11-18T11:03:00Z '/flow-factory approve-spec 0123456789AB'
cm_c 65 wrt write 2026-11-18T11:04:00Z '/flow-factory answer SPEC-1 2 tighten the scope'
cm_c 66 wrt write 2026-11-18T11:05:00Z '/flow-factory answer SPEC-1 0'
cm_c 67 wrt write 2026-11-18T11:06:00Z '/flow-factory reject'
cm_c 68 wrt write 2026-11-18T11:07:00Z '/flow-factory reject now please'
cm_c 69 wrt write 2026-11-18T11:08:00Z '/flow-factory cancel-now'
cm_c 70 wrt write 2026-11-18T11:09:00Z '/flow-factory rework $(touch pwned) `id`'
cm_c 71 wrt write 2026-11-18T11:10:00Z '/flow-factory rework'
cm_c 72 wrt write 2026-11-18T11:11:00Z "$(printf '/flow-factory rework  keep\tthe  spacing  ')"
cm_c 73 wrt write 2026-11-18T11:12:00Z '/flow-factory answer NI-1 use port 8080'
cm_c 74 wrt write 2026-11-18T11:13:00Z '/flow-factory answer NI-2'
cm_c 75 wrt write 2026-11-18T11:14:00Z '/flow-factory answer NI-9 something'
cm_c 76 wrt write 2026-11-18T11:15:00Z "$(printf '/flow-factory cancel\r\nsecond line')"
cm_c 77 wrt write 2026-11-18T11:16:00Z '/flow-factory answer NI-2 a; rm -rf ~'
cm_c 78 wrt write 2026-11-18T11:17:00Z '/flow-factory rework-later fix it'
e2e_describe "design runner L14 and person_channels L58 give the forms: approve-spec <spec-hash> [<head>], each at least 12 hex digits (lower case, as the terminal's --spec-hash, person module HEX); answer <qid> <n> [<text>], n a whole number of 1 or more; rework <text>; reject, cancel and retry with nothing after them (Inferred: extra words get a note rather than a guess). Q17: answer NI-<k> <text>, the text the rest of line 1 after the id, not empty; an NI answer applies in needs_info (rows 8a and 9a) and in needs_human (rows 44v, 44u, 44w, 44x and 44q of transitions.json take person_answer there, the one source of states and events; plan 2.3 says needs_info only, and the terminal answer already takes needs_human, so both channels give one result), and (Inferred) only for a question of this job, any round (NI-1 of round 1 counts, NI-9 does not, in either state); design person_channels L11: a SPEC-<k> answer is the needs_spec_approval form, so (Inferred) it applies there only. R57: the text is stored as written, apart from the blanks at its two ends, and no shell runs (no file pwned). A CRLF line 1 is read without its CR (plan 5.3 command_of). A word glued to the name (cancel-now, rework-later) is a form note, not text. Each state is one where the event occurs (T:events): needs_spec_approval for approve-spec, answer SPEC-1 and reject; ready for rework; needs_info for the NI answers and cancel"
read -r -d '' CM_CODE <<'PY' || true
job = J()
print('-- needs_spec_approval')
scan(state(job, 'needs_spec_approval'), only=(61, 62, 63, 64, 65, 66, 67, 68))
print('-- ready')
scan(state(job, 'ready'), only=(70, 71, 72, 78))
print('-- needs_info')
scan(job, only=(69, 73, 74, 75, 76, 77))
print('-- the NI answer in ready, needs_spec_approval and needs_human, the SPEC answer in needs_info')
for s, cid in (('ready', 73), ('needs_spec_approval', 73), ('needs_info', 65), ('needs_human', 73),
               ('needs_human', 75)):
    for c in C.scan(I.read_issue(gh, REPO, 7, job, perms()), state(job, s), perms(), LOGIN):
        if c['comment_id'] == cid:
            print('wrong-state %s %s note=%s raise=%s' % (s, cid, 'yes' if c['note'] else 'no', c['raise']))
print('pwned %s' % os.path.exists('pwned'))
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line 'cmd 61 approve-spec raise=True trusted=True triage_only=False event=person_approve_spec args={"spec_hash": "0123456789ab"} note=no'
e2e_expect_line 'cmd 62 approve-spec raise=True trusted=True triage_only=False event=person_approve_spec args={"head": "fedcba9876543210", "spec_hash": "0123456789abcdef"} note=no'
e2e_expect_line 'cmd 63 approve-spec raise=False trusted=True triage_only=False event=person_approve_spec args={} note=yes'
e2e_expect_line 'cmd 64 approve-spec raise=False trusted=True triage_only=False event=person_approve_spec args={} note=yes'
e2e_expect_line 'cmd 65 answer raise=True trusted=True triage_only=False event=person_answer args={"choice": 2, "qid": "SPEC-1", "text": "tighten the scope"} note=no'
e2e_expect_line 'cmd 66 answer raise=False trusted=True triage_only=False event=person_answer args={} note=yes'
e2e_expect_line 'cmd 67 reject raise=True trusted=True triage_only=False event=person_reject args={} note=no'
e2e_expect_line 'cmd 68 reject raise=False trusted=True triage_only=False event=person_reject args={} note=yes'
e2e_expect_line 'cmd 70 rework raise=True trusted=True triage_only=False event=person_rework args={"text": "$(touch pwned) `id`"} note=no'
e2e_expect_line 'cmd 71 rework raise=False trusted=True triage_only=False event=person_rework args={} note=yes'
e2e_expect_line 'cmd 72 rework raise=True trusted=True triage_only=False event=person_rework args={"text": "keep\tthe  spacing"} note=no'
e2e_expect_line 'cmd 78 rework raise=False trusted=True triage_only=False event=person_rework args={} note=yes'
e2e_expect_line 'cmd 69 cancel raise=False trusted=True triage_only=False event=person_cancel args={} note=yes'
e2e_expect_line 'cmd 73 answer raise=True trusted=True triage_only=False event=person_answer args={"qid": "NI-1", "text": "use port 8080"} note=no'
e2e_expect_line 'cmd 74 answer raise=False trusted=True triage_only=False event=person_answer args={} note=yes'
e2e_expect_line 'cmd 75 answer raise=False trusted=True triage_only=False event=person_answer args={} note=yes'
e2e_expect_line 'cmd 76 cancel raise=True trusted=True triage_only=False event=person_cancel args={} note=no'
e2e_expect_line 'cmd 77 answer raise=True trusted=True triage_only=False event=person_answer args={"qid": "NI-2", "text": "a; rm -rf ~"} note=no'
e2e_expect_line "wrong-state ready 73 note=yes raise=False"
e2e_expect_line "wrong-state needs_spec_approval 73 note=yes raise=False"
e2e_expect_line "wrong-state needs_info 65 note=yes raise=False"
e2e_expect_line "wrong-state needs_human 73 note=no raise=True"
e2e_expect_line "wrong-state needs_human 75 note=yes raise=False"
e2e_expect_line "pwned False"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: a queue-label removal by triage or a bot gets one status note and cancels nothing (CM9, R56)"
cm_start cm-label intake
fe_world_perm tri triage
fe_world_label 7 flow:factory tri triage 2026-11-18T09:30:00Z unlabeled
fe_world_label 7 flow:factory wrt write 2026-11-18T10:30:00Z unlabeled
fe_world_label 7 flow:factory wrt write 2026-11-18T10:45:00Z
fe_world_label 7 flow:factory tri triage 2026-11-18T11:00:00Z unlabeled
fe_world_label 7 flow:factory wrt write 2026-11-18T11:30:00Z
fe_world_label 7 flow:other tri triage 2026-11-18T11:40:00Z unlabeled
fe_world_label 7 flow:factory 'ci[bot]' write 2026-11-18T12:00:00Z unlabeled
e2e_describe "design person_channels L56 and R56: removing the queue label cancels only when the actor has write access or higher; a removal by a triage user or a bot posts a status note and the job keeps running. Removals before vouch_at T1 (tri's at 09:30), of another label (tri's flow:other) and by write access (wrt's at 10:30) are not noted (Inferred: the note is for the removal L56 names, after the vouch). B4's cancel_signal stays false (the latest removal is the bot's). Each note is recorded through record_job_intent with row note and ref the removal's event id (Inferred carrier: ref holds a GitHub id the note answers), state_at_write intake, and names the label and the actor; recording the same removals again in a later pass adds no item (plan 2.2 dedupe)"
read -r -d '' CM_CODE <<'PY' || true
job = J()
p = perms()
snap = I.read_issue(gh, REPO, 7, job, p)
print('cancel_signal %s' % I.facts(snap, job, setting)['cancel_signal'])
notes = C.label_notes(snap, job, 'flow:factory')
ev = {e['id']: e for e in snap['events']}
print('notes %s' % [(ev[x['event_id']]['actor'], ev[x['event_id']]['created_at']) for x in notes])
for _ in range(2):
    job = J()
    for x in notes:
        with jobs.job_lock(P, 7):
            C.store_label_note(P, job, x, repo=REPO)
for i, it in sorted(items().items()):
    b = body(it)
    print('item %s ref-is-event=%s state=%s valid=%s label=%s actor=%s' % (
        i, it['ref'] in ev, it['state_at_write'], schema.validate(it, OUTBOX_SCHEMA), '`flow:factory`' in b,
        ev.get(it['ref'], {}).get('actor', '?') in b))
    print('body %s %r' % (i, b))
print('items %d write_seq %s' % (len(items()), J().get('write_seq')))
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "cancel_signal False"
e2e_expect_line "notes [('tri', '2026-11-18T11:00:00Z'), ('ci[bot]', '2026-11-18T12:00:00Z')]"
e2e_expect_line "item issue-7-j1-note-1 ref-is-event=True state=intake valid=[] label=True actor=True"
e2e_expect_line "item issue-7-j1-note-2 ref-is-event=True state=intake valid=[] label=True actor=True"
e2e_expect_line "items 2 write_seq 2"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: store_pending keeps the comment object to the comment channel (CM10)"
cm_start cm-pending queued
e2e_describe "plan 2.2 Pending person event and the wave 1 journal (Schemas: 'a comment object on every comment-channel event' is the writer's rule): store_pending with channel comment:12 and no comment object, or a comment object whose id is 13, is refused as pending_invalid and writes nothing; a comment object on the terminal channel is refused; a terminal event with no comment keyword is stored as before (the existing callers); comment:12 with its object is stored and valid"
read -r -d '' CM_CODE <<'PY' || true
caller = {'pid': os.getpid(), 'start': '', 'ancestry': [os.getpid()]}
facts = {'unvouched_session_action': False}
obj = {'id': 12, 'author': 'wrt', 'permission': 'write', 'created_at': T2}
cases = (('no object', 'comment:12', None), ('other id', 'comment:12', dict(obj, id=13)),
         ('terminal with object', 'terminal', obj),
         ('terminal', 'terminal', None), ('comment', 'comment:12', obj))
for what, channel, comment in cases:
    kw = {} if comment is None else {'comment': comment}
    try:
        jobs.store_pending(P, 7, 'person_cancel', {}, channel, caller, facts, **kw)
        print('%s stored' % what)
    except jobs.Refused as e:
        print('%s refused %s' % (what, str(e).split(' ')[0]))
for r in pending():
    print('kept %s %s valid=%s' % (r['channel'], r.get('comment', {}).get('id'),
                                   schema.validate(r, jobs.DIRECTIVE_SCHEMA, 'pending_event')))
try:
    C.scan({'comments': []}, J(), perms(), None)
    print('no login scanned')
except ValueError:
    print('no login refused')
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "no object refused pending_invalid"
e2e_expect_line "other id refused pending_invalid"
e2e_expect_line "terminal with object refused pending_invalid"
e2e_expect_line "terminal stored"
e2e_expect_line "comment stored"
e2e_expect_line "kept terminal None valid=[]"
e2e_expect_line "kept comment:12 12 valid=[]"
e2e_expect_line "no login refused"

# ---------------------------------------------------------------------------
_flow_test_begin "factory commands: form notes are stored, store skips a seen comment, and an unreadable pending file stops the store (CM5, CM6, CM7)"
cm_start cm-store needs_info "d['needs_info'] = {'asked_at': '2026-11-18T09:00:00Z', 'questions': ['NI-1'], 'round': 1, 'earlier': []}"
cm_c 81 wrt write 2026-11-18T11:00:00Z '/flow-factory answer NI-1'
cm_c 82 wrt write 2026-11-18T11:01:00Z '/flow-factory answer NI-7 use port 8080'
cm_c 83 wrt write 2026-11-18T11:02:00Z '/flow-factory answer build-q1 2 use the default'
cm_c 84 wrt write 2026-11-18T11:03:00Z '/flow-factory approve-spec 0123abc'
cm_c 85 wrt write 2026-11-18T11:04:00Z '/flow-factory cancel'
e2e_describe "plan B5 test plan: '/flow-factory answer NI-1' with no text gets a status note (Q17: the text must not be empty), and so does an answer naming a question the job never asked (NI-7, Inferred) and an answer to a worker question (build-q1) in needs_info (Inferred: a needs-info answer names an NI id, plan 2.3); each note is an outbox item with ref the comment id, and its body names the reason without the comment's text. In needs_spec_approval, approve-spec with a 7-digit hash gets a form note (design person_channels L58: at least 12 hex digits). store called again for a comment already in commands_seen adds no events line and no item (person_channels L78). A file in J/pending that cannot be read may be the same comment's event, so store refuses (pending_unreadable), stores nothing and leaves the comment unseen, for the next pass to try again (Inferred)"
read -r -d '' CM_CODE <<'PY' || true
job = J()
cmds = {c['comment_id']: c for c in scan(job, only=(81, 82, 83))}
for cid in (81, 82, 83):
    store(job, cmds[cid])
lines = len(events('commands_seen'))
store(J(), cmds[81])
print('again lines %d -> %d items %d' % (lines, len(events('commands_seen')), len(items())))
job = J()
job['state'] = 'needs_spec_approval'
with jobs.job_lock(P, 7):
    jobs.write_job(P, job)
job = J()
for c in scan(job, only=(84,)):
    if c['comment_id'] == 84:
        store(job, c)
for i, it in sorted(items().items()):
    b = body(it)
    print('item %s ref=%s state=%s text-copied=%s' % (i, it['ref'], it['state_at_write'],
                                                     'use port' in b or 'use the default' in b or '0123abc' in b))
    print('body %s %r' % (it['ref'], b.split('\n', 1)[1]))
job = J()
job['state'] = 'needs_info'
with jobs.job_lock(P, 7):
    jobs.write_job(P, job)
os.makedirs(os.path.join(JD, 'pending'), exist_ok=True)
with open(os.path.join(JD, 'pending', '00000000000000000001-person_cancel.json'), 'w') as fh:
    fh.write('{')
job = J()
c85 = [c for c in scan(job, only=(85,)) if c['comment_id'] == 85][0]
try:
    store(job, c85)
    print('unreadable stored')
except jobs.Refused as e:
    print('unreadable refused %s' % str(e).split(' ')[0])
print('after pending %d seen %s' % (len(os.listdir(os.path.join(JD, 'pending'))), J().get('commands_seen')))
PY
cm_py "$CM_CODE"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line 'cmd 81 answer raise=False trusted=True triage_only=False event=person_answer args={} note=yes'
e2e_expect_line 'cmd 82 answer raise=False trusted=True triage_only=False event=person_answer args={} note=yes'
e2e_expect_line 'cmd 83 answer raise=False trusted=True triage_only=False event=person_answer args={} note=yes'
e2e_expect_line 'cmd 84 approve-spec raise=False trusted=True triage_only=False event=person_approve_spec args={} note=yes'
e2e_expect_line "again lines 3 -> 3 items 3"
e2e_expect_line "item issue-7-j1-note-1 ref=81 state=needs_info text-copied=False"
e2e_expect_line "item issue-7-j1-note-2 ref=82 state=needs_info text-copied=False"
e2e_expect_line "item issue-7-j1-note-3 ref=83 state=needs_info text-copied=False"
e2e_expect_line "item issue-7-j1-note-4 ref=84 state=needs_spec_approval text-copied=False"
e2e_expect_out "Job issue-7-j1 has no question NI-7."
e2e_expect_out "Job issue-7-j1 is in state needs_info, where this command does not apply."
e2e_expect_line 'cmd 85 cancel raise=True trusted=True triage_only=False event=person_cancel args={} note=no'
e2e_expect_line "unreadable refused pending_unreadable"
e2e_expect_line "after pending 1 seen [81, 82, 83, 84]"
