# shellcheck shell=bash
# The factory engine's tier keys (bin/_flow_factory_tiers.py), run in
# isolation through fe_py: the strictest of four sources (design
# github_writes_and_tiers L48), the keys left on a job's path (design
# execution_model L46-L53, T:facts.tier_confirm_blocking), the write kind to
# key map behind blocking_write_confirm (rules.blocking_write.kinds), the base
# fetch, and intent_key_not_confirm. The rows that read these facts through
# `next` (40b, 41b, 41k, 40) are later files'.
#
# Ways it can be wrong, written down before the code:
#   TR1  (R26) the first source with a value wins, as in tier-gate's cascade,
#        so a local autonomous hides a base-ref confirm; or the order of the
#        three values is wrong (journal beats confirm, autonomous beats
#        journal)
#   TR2  (R27) the project file is read from the working tree or from the
#        checked-out job branch instead of origin/<base>, in either direction
#   TR3  a base ref that does not resolve, or a job with no base, reads as
#        "no project file" instead of confirm; a ref with no project file at
#        all reads as confirm instead of letting the other three decide
#   TR4  a source that cannot be read (bad JSON in the local file or at the
#        ref, a value that is none of the three names in the user file) is
#        skipped instead of counting as confirm
#   TR5  (R40) a value is kept from an earlier read, so a key changed between
#        two reads in one process is not seen
#   TR6  fetch_base leaves refs/remotes/origin/<base> where it was, reports
#        success when origin is gone, or passes a base that looks like an
#        option (or is not a branch name) to git
#   TR7  (R70) a write kind maps to the wrong key or to none (the in-progress
#        label missed, so row 11 with only issueUpdate at confirm does not
#        park); "PR create or edit" ignores whether the job has a PR; a kind
#        the map does not know resolves to no key instead of raising
#   TR8  the confirmed intent leaves out kinds although its item is not sent,
#        is missing, or belongs to another job; a label_add of another label
#        is taken as the in-progress label
#   TR9  the path keys are only the current stage's own (so a spec job with
#        push at confirm spends its spec and build budget before parking), the
#        order differs from the design's stage order, a parked job reads the
#        keys of waiting_operator instead of its resume_state, or an unknown
#        state answers [] silently
#   TR10 intent_key_not_confirm is true for a job with no pending intent, or
#        reads only one key of a two-key intent
#   TR11 a key no source sets reads as a value other than confirm; a
#        cascade-resolve.sh that prints its answer but exits non-zero is
#        believed, so the local and user files are read from what it printed
#   TR12 confirm_writes called without fdir covers nothing, so a confirmed
#        intent stops covering its kinds; a confirmed_intent that climbs out
#        of the outbox ('../x'), an item whose id is not its file's name, or
#        a job whose issue is not a whole number is taken as covering
#   TR14 the confirmed intent's status, kind or argv is read from the
#        editable item, so an item whose kind was edited, or a recorded item
#        whose status was edited to sent, covers kinds no write sent
#   TR13 a .claude at the base ref that is not a directory (a symbolic link to
#        one, or a file) is read as "no project file", since git lists no
#        .claude/settings.flow.json under it, so the project source drops out
#        instead of counting as confirm
#   TR14 a project file at the base ref named .Claude/settings.flow.json,
#        .claude/Settings.flow.json or .claude/ſettings.flow.json is read as
#        "no project file", since git matches names exactly, while a checkout
#        on a file system that ignores case finds it; or an unrelated name
#        that is not ASCII is refused along with them
#   TR15 the project file is read by walking the base ref's trees by name, so
#        what a checkout writes is missed: a top-level entry whose own name is
#        '.claude/settings.flow.json', the first of two '.claude' trees in one
#        tree (a checkout merges both), or a case variant in that first tree;
#        a tree git read-tree refuses ('..' or '.git' as a name) is read as no
#        project file; reading runs the main checkout's post-index-change
#        hook, or leaves its temporary index behind
#
# Every expected value is written out by hand from the design lines named in
# each scenario's description; none comes from the module.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# tr_commit <json> [<branch>] — commit <json> as .claude/settings.flow.json on
# the current branch (or on <branch>, made from main and left checked out
# only for the commit) of the scratch repository.
tr_commit() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    if [ -n "${2:-}" ]; then git checkout -q -B "$2" main || exit 1; fi
    mkdir -p .claude
    printf '%s\n' "$1" > .claude/settings.flow.json
    git add .claude/settings.flow.json && git commit -q -m "settings ${2:-main}" || exit 1
    if [ -n "${2:-}" ]; then git checkout -q main || exit 1; fi
  ) || _e2e_result fail "tr_commit committed the project file"
  printf 'committed .claude/settings.flow.json on %s: %s\n' "${2:-main}" "$1" | _e2e_art
}

# tr_file <path relative to the scratch repository or ~/> <text> — write a file.
tr_file() {
  local dst
  case "$1" in
    "~/"*) dst="$E2E_HOME/${1#"~/"}" ;;
    *) dst="$E2E_REPO/$1" ;;
  esac
  mkdir -p "$(dirname -- "$dst")"
  printf '%s\n' "$2" > "$dst"
  printf 'wrote %s: %s\n' "$1" "$2" | _e2e_art
}

# tr_start <name> <project json> — a scenario with the project file committed
# on main, then the probe record (which makes F and the local origin, with
# origin/main at that commit).
tr_start() {
  fe_new "$1"
  e2e_repo main
  [ -z "$2" ] || tr_commit "$2"
  fe_record
}

# The Python every scenario starts with: R the module, M the main checkout,
# BASE the base ref of a job whose base is main, and job(...) a job.
read -r -d '' TR_PRE <<'PY' || true
import sys
sys.dont_write_bytecode = True
import json, os
import _flow_factory_tiers as R
M = os.getcwd()
BASE = 'refs/remotes/origin/main'
def job(state='prepare', **kw):
    d = {'key': 'issue-7-j1', 'issue': 7, 'state': state, 'base': 'main', 'pr': None,
         'pending_intent': None, 'confirmed_intent': None, 'resume_state': None}
    d.update(kw)
    return d
def fixed(**values):
    return lambda key: values.get(key, 'journal')
PY

tr_py() { fe_py "$TR_PRE
$1"; }

_flow_test_begin "factory tiers: the strictest of four, not the first value (TR1, R26)"
tr_start tr1-strictest '{"tiers": {"issueAssign": "confirm", "push": "journal", "prCreate": "autonomous"}}'
tr_file .claude/settings.flow.local.json '{"tiers": {"issueAssign": "autonomous", "push": "autonomous", "prCreate": "autonomous", "issueUpdate": "autonomous"}}'
tr_file "~/.claude/settings.flow.json" '{"tiers": {"issueUpdate": "autonomous"}}'
e2e_describe "design github_writes_and_tiers L48: the base-ref project file sets issueAssign confirm, push journal and prCreate autonomous; the local file sets all four autonomous; the user file sets issueUpdate autonomous; the plugin default is journal for all four. Strictest: issueAssign confirm, push journal, prCreate journal (the plugin default beats autonomous), issueUpdate journal. tier-gate's first-value cascade gives autonomous for issueAssign. A prepare job's confirm path keys are [issueAssign]"
read -r -d '' TR_CODE <<'PY' || true
for k in ('issueAssign', 'push', 'prCreate', 'issueUpdate'):
    print('resolve %s %s' % (k, R.resolve(M, BASE, k)))
print('path %s' % R.confirm_path_keys(M, BASE, job('prepare')))
print('blocking %s' % R.tier_confirm_blocking(M, BASE, job('prepare')))
t = R.resolver(M, BASE)
print('problem %s' % t.base_problem)
PY
tr_py "$TR_CODE"
e2e_expect_line "resolve issueAssign confirm"
e2e_expect_line "resolve push journal"
e2e_expect_line "resolve prCreate journal"
e2e_expect_line "resolve issueUpdate journal"
e2e_expect_line "path ['issueAssign']"
e2e_expect_line "blocking True"
e2e_expect_line "problem None"
e2e_run_bin bin/cascade-resolve.sh .tiers.issueAssign
e2e_expect_line "autonomous"

_flow_test_begin "factory tiers: the project file comes from origin/<base>, never the working tree or a job branch (TR2, R27)"
tr_start tr2-source '{"tiers": {"issueAssign": "confirm", "issueUpdate": "journal"}}'
tr_commit '{"tiers": {"issueAssign": "autonomous", "issueUpdate": "confirm"}}' issue-7-branch
tr_commit '{"tiers": {"issueAssign": "autonomous", "issueUpdate": "confirm"}}' 
tr_file .claude/settings.flow.json '{"tiers": {"issueAssign": "autonomous", "issueUpdate": "confirm"}}'
e2e_describe "design github_writes_and_tiers L48 and worktrees_ports_bootstrap_auth L51: origin/main's project file has issueAssign confirm and issueUpdate journal; a job branch in the main checkout, a later commit on the local main (HEAD, not pushed) and the working-tree file all have issueAssign autonomous and issueUpdate confirm. The engine reads origin/main only: issueAssign confirm (not weakened), issueUpdate journal (not raised); the plugin default is journal"
read -r -d '' TR_CODE <<'PY' || true
for k in ('issueAssign', 'issueUpdate'):
    print('resolve %s %s' % (k, R.resolve(M, BASE, k)))
PY
tr_py "$TR_CODE"
e2e_expect_line "resolve issueAssign confirm"
e2e_expect_line "resolve issueUpdate journal"

_flow_test_begin "factory tiers: an unresolved ref or no base counts as confirm; a ref with no project file lets the other three decide (TR3)"
tr_start tr3-refs ''
tr_file "~/.claude/settings.flow.json" '{"tiers": {"push": "confirm"}}'
tr_file .claude/settings.flow.json '{"tiers": {"issueAssign": "confirm"}}'
e2e_describe "origin/main has no project file (the working tree has one with issueAssign confirm, which is not read); the user file sets push confirm; the plugin default is journal. At origin/main: issueAssign journal, push confirm, base_problem None. At refs/remotes/origin/nope (never fetched) and with no base ref (None): issueAssign confirm (the project source counts as confirm, plan B7 step 2), with base_problem naming the case. base_ref of a job: main gives refs/remotes/origin/main; a missing base, an empty one, one starting with '-', one holding '..' or ':', one ending in '.lock', one with a part ending in '.lock' (a.lock/b), one with a part starting with '.', one holding '//' and one of 201 characters give None (the module's branch-name rule); one of 200 characters gives its ref"
read -r -d '' TR_CODE <<'PY' || true
print('origin issueAssign %s push %s problem %s' % (R.resolve(M, BASE, 'issueAssign'), R.resolve(M, BASE, 'push'),
                                                   R.resolver(M, BASE).base_problem))
t = R.resolver(M, 'refs/remotes/origin/nope')
print('nope issueAssign %s problem %s' % (t('issueAssign'), t.base_problem))
t = R.resolver(M, None)
print('none issueAssign %s problem %s' % (t('issueAssign'), t.base_problem))
print('base_ref main %s' % R.base_ref(job()))
for tag, b in (('missing', None), ('empty', ''), ('dash', '-x'), ('dots', 'a..b'), ('colon', 'a:b'),
               ('lock', 'a.lock'), ('lock-part', 'a.lock/b'), ('dot-part', 'a/.b'), ('double-slash', 'a//b'), ('long', 'a' * 201)):
    print('base_ref %s %s' % (tag, R.base_ref(job(base=b))))
print('base_ref absent %s' % R.base_ref({'key': 'issue-7-j1'}))
print('base_ref 200 %s' % (R.base_ref(job(base='a' * 200)) == 'refs/remotes/origin/' + 'a' * 200))
PY
tr_py "$TR_CODE"
e2e_expect_line "origin issueAssign journal push confirm problem None"
e2e_expect_line "nope issueAssign confirm problem ref_unresolved refs/remotes/origin/nope"
e2e_expect_line "none issueAssign confirm problem no_base"
e2e_expect_line "base_ref main refs/remotes/origin/main"
for TR_N in missing empty dash dots colon lock lock-part dot-part double-slash long absent; do
  e2e_expect_line "base_ref $TR_N None"
done
e2e_expect_line "base_ref 200 True"

_flow_test_begin "factory tiers: a source that cannot be read counts as confirm (TR4)"
tr_start tr4-unreadable '{"tiers": {"push": "autonomous"}}'
e2e_describe "plan B7 step 2 (fail closed): each case changes one source and reads issueAssign, whose value is journal everywhere else. A local file that is not JSON gives confirm; a user file whose tiers.issueAssign is 'sometimes' gives confirm; a project file at origin/main that is not JSON gives confirm; a project file at origin/main that is a symbolic link (whose target text, {}, is JSON) gives confirm; a user file whose tiers is a list gives confirm; a user file whose tiers.issueAssign is a list gives confirm. Restored, each gives journal"
read -r -d '' TR_CODE <<'PY' || true
loc = os.path.join(M, '.claude', 'settings.flow.local.json')
usr = os.path.join(os.environ['HOME'], '.claude', 'settings.flow.json')
os.makedirs(os.path.dirname(usr), exist_ok=True)
print('clean %s' % R.resolve(M, BASE, 'issueAssign'))
open(loc, 'w').write('{not json')
print('local-bad %s' % R.resolve(M, BASE, 'issueAssign'))
os.remove(loc)
open(usr, 'w').write('{"tiers": {"issueAssign": "sometimes"}}')
print('user-value %s' % R.resolve(M, BASE, 'issueAssign'))
open(usr, 'w').write('{"tiers": ["confirm"]}')
print('user-shape %s' % R.resolve(M, BASE, 'issueAssign'))
open(usr, 'w').write('{"tiers": {"issueAssign": ["journal"]}}')
print('user-list-value %s' % R.resolve(M, BASE, 'issueAssign'))
os.remove(usr)
print('restored %s' % R.resolve(M, BASE, 'issueAssign'))
PY
tr_py "$TR_CODE"
e2e_expect_line "clean journal"
e2e_expect_line "local-bad confirm"
e2e_expect_line "user-value confirm"
e2e_expect_line "user-shape confirm"
e2e_expect_line "user-list-value confirm"
e2e_expect_line "restored journal"
tr_commit '{not json'
fe_origin_local
tr_py "print('ref-bad %s' % R.resolve(M, BASE, 'issueAssign'))"
e2e_expect_line "ref-bad confirm"
(
  _e2e_git_env
  cd "$E2E_REPO" && git rm -q .claude/settings.flow.json && mkdir -p .claude && ln -s '{}' .claude/settings.flow.json \
    && git add .claude/settings.flow.json && git commit -q -m 'settings as a link'
) || _e2e_result fail "committed .claude/settings.flow.json as a symbolic link to a file named {}"
printf 'committed .claude/settings.flow.json on main as a symbolic link whose target is {}\n' | _e2e_art
fe_origin_local
tr_py "print('ref-link %s' % R.resolve(M, BASE, 'issueAssign'))"
e2e_expect_line "ref-link confirm"

_flow_test_begin "factory tiers: nothing is kept between reads (TR5, R40)"
tr_start tr5-no-cache ''
e2e_describe "T:41b: a key changed between two reads in one process is seen by the second, through resolve and through a new resolver; tier_confirm_blocking of a prepare job turns false once the user file sets issueAssign back from confirm to journal"
read -r -d '' TR_CODE <<'PY' || true
usr = os.path.join(os.environ['HOME'], '.claude', 'settings.flow.json')
os.makedirs(os.path.dirname(usr), exist_ok=True)
open(usr, 'w').write('{"tiers": {"issueAssign": "confirm"}}')
print('first %s %s' % (R.resolve(M, BASE, 'issueAssign'), R.tier_confirm_blocking(M, BASE, job())))
open(usr, 'w').write('{"tiers": {"issueAssign": "journal"}}')
print('second %s %s' % (R.resolve(M, BASE, 'issueAssign'), R.tier_confirm_blocking(M, BASE, job())))
print('resolver %s' % R.resolver(M, BASE)('issueAssign'))
PY
tr_py "$TR_CODE"
e2e_expect_line "first confirm True"
e2e_expect_line "second journal False"
e2e_expect_line "resolver journal"

_flow_test_begin "factory tiers: fetch_base moves origin/<base>, fails without origin, and refuses a base that is not a branch name (TR6)"
tr_start tr6-fetch '{"tiers": {"issueAssign": "journal"}}'
(
  _e2e_git_env
  cd "$E2E_DIR" && git clone -q -b main origin.git other && cd other \
    && git -c user.name=o -c user.email=o@o.invalid -c commit.gpgsign=false commit -q --allow-empty -m moved \
    && git push -q origin HEAD:main && git rev-parse HEAD > "$E2E_DIR/moved-sha" \
    && cd "$E2E_REPO" && git config --unset-all remote.origin.fetch
) || _e2e_result fail "pushed a new commit to origin's main from a second clone, and removed the main checkout's fetch refspec"
e2e_describe "design worker_github_access L10: a second clone pushes a new commit to origin's main, and the main checkout has no remote.origin.fetch (so the fetch must name where origin's branch goes). Before fetch_base, refs/remotes/origin/main is the old commit; after it, (True, '') and the ref is the pushed commit. A base '-x' or 'a..b' gives False with no git run (origin/main unchanged). With origin/main set back one commit and its ref lock held by another process for 0.4 s, the fetch is tried again after one second and moves the ref; with the lock held throughout, (False, a reason naming the lock) after at least one second. With origin.git moved away: (False, <non-empty reason>)"
read -r -d '' TR_CODE <<'PY' || true
import subprocess
def ref():
    return subprocess.run(['git', 'rev-parse', BASE], capture_output=True, text=True).stdout.strip()
moved = open(os.path.join(os.environ['E2E_DIR'], 'moved-sha')).read().strip()
print('before moved=%s' % (ref() == moved))
ok, why = R.fetch_base(M, 'main')
print('fetch %s %r moved=%s' % (ok, why, ref() == moved))
for b in ('-x', 'a..b', ''):
    ok, why = R.fetch_base(M, b)
    print('refused %r %s %s' % (b, ok, why.split(' ')[0]))
import threading, time
lock = os.path.join(M, '.git', 'refs', 'remotes', 'origin', 'main.lock')
subprocess.run(['git', 'update-ref', BASE, BASE + '~1'], check=True)
open(lock, 'w').close()
threading.Timer(0.4, os.remove, [lock]).start()
ok, why = R.fetch_base(M, 'main')
print('lock-released %s %r moved=%s' % (ok, why, ref() == moved))
subprocess.run(['git', 'update-ref', BASE, BASE + '~1'], check=True)
open(lock, 'w').close()
t0 = time.time()
ok, why = R.fetch_base(M, 'main')
print('lock-held %s lock-named=%s retried=%s' % (ok, 'lock' in why, time.time() - t0 >= 1))
os.remove(lock)
os.rename(os.path.join(os.environ['E2E_DIR'], 'origin.git'), os.path.join(os.environ['E2E_DIR'], 'gone.git'))
ok, why = R.fetch_base(M, 'main')
print('gone %s reason=%s' % (ok, bool(why)))
PY
tr_py "$TR_CODE"
e2e_expect_line "before moved=False"
e2e_expect_line "fetch True '' moved=True"
e2e_expect_line "refused '-x' False base_invalid"
e2e_expect_line "refused 'a..b' False base_invalid"
e2e_expect_line "refused '' False base_invalid"
e2e_expect_line "lock-released True '' moved=True"
e2e_expect_line "lock-held False lock-named=True retried=True"
e2e_expect_line "gone False reason=True"

_flow_test_begin "factory tiers: every write kind maps to its key; PR create or edit follows the PR; an unknown kind raises (TR7, R70)"
tr_start tr7-kinds ''
e2e_describe "plan 5.3's write kind table (design github_writes_and_tiers L58-L64, stages L71), with a tiers callable that puts only one key at confirm: assignment → issueAssign; in-progress label, review marker, resolution marker, replies, ready mark, undo of ready → issueUpdate; push → push; PR create or edit → prCreate with no PR and issueUpdate with one. R70: row 11's writes from prepare with only issueUpdate at confirm give [issueUpdate]; with issueAssign and issueUpdate, [issueAssign, issueUpdate]; review's three writes with push and issueUpdate at confirm give [push, issueUpdate] (each key once, in order of first use). 'label' (not a kind of rules.blocking_write.kinds) raises ValueError"
read -r -d '' TR_CODE <<'PY' || true
want = {'assignment': 'issueAssign', 'in-progress label': 'issueUpdate', 'push': 'push',
        'review marker': 'issueUpdate', 'resolution marker': 'issueUpdate', 'replies': 'issueUpdate',
        'ready mark': 'issueUpdate', 'undo of ready': 'issueUpdate'}
for kind, key in want.items():
    hit = R.confirm_writes([kind], job(), fixed(**{key: 'confirm'}), None)
    miss = R.confirm_writes([kind], job(), lambda k: 'confirm' if k != key else 'journal', None)
    print('kind %s %s %s' % (kind, hit, miss))
for pr in (None, 5):
    print('pr %s %s' % (pr, R.confirm_writes(['PR create or edit'], job('open_pr', pr=pr),
                                               lambda k: 'confirm' if k in ('prCreate', 'issueUpdate') else 'journal', None)))
    print('pr-only-create %s %s' % (pr, R.confirm_writes(['PR create or edit'], job('open_pr', pr=pr),
                                                           fixed(prCreate='confirm'), None)))
print('r70 %s' % R.confirm_writes(['assignment', 'in-progress label'], job(), fixed(issueUpdate='confirm'), None))
print('row11 %s' % R.confirm_writes(['assignment', 'in-progress label'], job(),
                                    fixed(issueAssign='confirm', issueUpdate='confirm'), None))
print('none %s' % R.confirm_writes(['assignment', 'in-progress label'], job(), fixed(), None))
print('review %s' % R.confirm_writes(['push', 'review marker', 'resolution marker'], job('review'),
                                     fixed(push='confirm', issueUpdate='confirm'), None))
try:
    R.confirm_writes(['label'], job(), fixed(), None)
    print('unknown no-raise')
except ValueError as e:
    print('unknown raised')
print('kinds-match %s' % (sorted(R.WRITE_KINDS) == sorted(json.load(open(os.path.join(
    os.environ['CLAUDE_PLUGIN_ROOT'], 'references', 'factory-transitions.json')))['rules']['blocking_write']['kinds'])))
PY
tr_py "$TR_CODE"
e2e_expect_line "kind assignment ['issueAssign'] []"
for TR_N in "in-progress label" "review marker" "resolution marker" "replies" "ready mark" "undo of ready"; do
  e2e_expect_line "kind $TR_N ['issueUpdate'] []"
done
e2e_expect_line "kind push ['push'] []"
e2e_expect_line "pr None ['prCreate']"
e2e_expect_line "pr-only-create None ['prCreate']"
e2e_expect_line "pr 5 ['issueUpdate']"
e2e_expect_line "pr-only-create 5 []"
e2e_expect_line "r70 ['issueUpdate']"
e2e_expect_line "row11 ['issueAssign', 'issueUpdate']"
e2e_expect_line "none []"
e2e_expect_line "review ['push', 'issueUpdate']"
e2e_expect_line "unknown raised"
e2e_expect_line "kinds-match True"

_flow_test_begin "factory tiers: row 40b's and row 11's writes through the table; a sent confirmed intent covers its kinds, nothing else does (TR7, TR8)"
tr_start tr8-confirmed ''
e2e_describe "writes_for over the shipped table: row 40b from intake has no writes ([]), from approve the undo of ready ([issueUpdate] with issueUpdate at confirm). Row 11 from prepare with issueAssign and issueUpdate at confirm (plan 2.2, 'The confirmation of a released intent'): confirmed_intent naming a sent assign_label item gives []; a recorded one, a missing one, and a sent one whose job is another give [issueAssign, issueUpdate]; a sent label_add of flow:in-progress (the plugin's labels.inProgress) gives [issueAssign]; a sent label_add of flow:ready gives both. Sent means a write_recorded line names the item, and the item is the one its intent_recorded line records (plan 2.2 and 5.3, design person_channels L42; each item here is written with its intent_recorded line, the plan 2.2 hash computed with hashlib, and for a sent one its write_recorded line): a sent label_add of flow:in-progress whose kind was edited to assign_label, and a recorded assign_label item whose status was edited to sent with no write_recorded line, give both (TR14). Called with no fdir, the sent assign_label item in the main checkout's factory directory still gives [] (fdir defaults to it, as fetch_base's does). Each of these gives both keys, though a sent assign_label item for the job is there to be found if the guard were missing: confirmed_intent '../x' with such an item at jobs/issue-7/x.json; confirmed_intent issue-7-j1-11-6 whose file holds id issue-7-j1-11-1; and a job whose issue is the text '7'"
read -r -d '' TR_CODE <<'PY' || true
import _flow_factory_table as T
rows = {r['id']: r for r in json.load(open(os.path.join(os.environ['CLAUDE_PLUGIN_ROOT'], 'references',
                                                         'factory-transitions.json')))['rows']}
both = fixed(issueAssign='confirm', issueUpdate='confirm')
print('40b intake %s' % R.confirm_writes(T.writes_for(rows['40b'], 'intake'), job('intake'), both, None))
print('40b approve %s' % R.confirm_writes(T.writes_for(rows['40b'], 'approve'), job('approve'), both, None))
import _flow_factory as ff
F = os.path.join(M, ff.factory_rel(M))
out = os.path.join(F, 'jobs', 'issue-7', 'outbox')
os.makedirs(out, exist_ok=True)
import hashlib
EV = os.path.join(F, 'jobs', 'issue-7', 'events.jsonl')
ASSIGN = ['gh', 'issue', 'edit', '7', '--repo', 'flow-e2e/scratch', '--add-assignee', 'flow-e2e-engine',
          '--add-label', 'flow:in-progress']
def add(label):
    return ['gh', 'api', '--method', 'POST', 'repos/flow-e2e/scratch/issues/7/labels', '-f', 'labels[]=' + label]
def event(d):
    with open(EV, 'a') as fh:
        fh.write(json.dumps(d) + '\n')
def item(i, kind, status, job_key='issue-7-j1', argv=None, edit=None):
    # plan 2.2: sha256 over the argv elements joined by NUL, a NUL, then the
    # body bytes (none for a label or an assignment).
    argv = argv or ASSIGN
    sha = hashlib.sha256(b'\0'.join(a.encode('utf-8') for a in argv) + b'\0').hexdigest()
    d = {'id': i, 'job': job_key, 'row': '11', 'state_at_write': 'prepare', 'ref': None, 'kind': kind,
         'blocking': True, 'key': ['issueAssign', 'issueUpdate'], 'argv': argv,
         'body_file': None, 'sha256': sha, 'status': status, 'effect': None}
    rec = {'type': 'intent_recorded', 'time': '2026-11-16T00:00:00Z', 'sha256': sha}
    rec.update({f: d[f] for f in ('id', 'job', 'row', 'state_at_write', 'ref', 'kind', 'blocking', 'key')})
    event(rec)
    if status == 'sent':
        d['effect'] = {'label': 'flow:in-progress'}
        event({'type': 'write_recorded', 'job': job_key, 'time': '2026-11-16T00:00:00Z', 'id': i, 'effect': d['effect']})
    d.update(edit or {})
    json.dump(d, open(os.path.join(out, i + '.json'), 'w'))
item('issue-7-j1-11-1', 'assign_label', 'sent')
item('issue-7-j1-11-2', 'assign_label', 'recorded')
item('issue-7-j1-11-3', 'assign_label', 'sent', job_key='issue-7-j2')
item('issue-7-j1-11-4', 'label_add', 'sent', argv=add('flow:in-progress'))
item('issue-7-j1-11-5', 'label_add', 'sent', argv=add('flow:ready'))
item('issue-7-j1-11-7', 'label_add', 'sent', argv=add('flow:in-progress'), edit={'kind': 'assign_label'})
item('issue-7-j1-11-8', 'assign_label', 'recorded', edit={'status': 'sent'})
w11 = T.writes_for(rows['11'], 'prepare')
for tag, i in (('sent', 'issue-7-j1-11-1'), ('recorded', 'issue-7-j1-11-2'), ('missing', 'issue-7-j1-11-9'),
               ('other-job', 'issue-7-j1-11-3'), ('label-in-progress', 'issue-7-j1-11-4'),
               ('label-ready', 'issue-7-j1-11-5'), ('kind-edited', 'issue-7-j1-11-7'),
               ('status-edited', 'issue-7-j1-11-8'), ('null', None)):
    print('row11 %s %s' % (tag, R.confirm_writes(w11, job(confirmed_intent=i), both, F)))
# A sent assign_label item for this job, one directory up from the outbox:
# only the id's shape keeps '../x' from reaching it.
d = {'id': '../x', 'job': 'issue-7-j1', 'row': '11', 'state_at_write': 'prepare', 'ref': None, 'kind': 'assign_label',
     'blocking': True, 'key': ['issueAssign', 'issueUpdate'], 'argv': ['gh', 'issue', 'edit', '7'],
     'body_file': None, 'sha256': '0' * 64, 'status': 'sent', 'effect': None}
json.dump(d, open(os.path.join(F, 'jobs', 'issue-7', 'x.json'), 'w'))
print('row11 dotdot %s' % R.confirm_writes(w11, job(confirmed_intent='../x'), both, F))
# A sent assign_label item for this job whose id names another file.
json.dump(dict(d, id='issue-7-j1-11-1'), open(os.path.join(out, 'issue-7-j1-11-6.json'), 'w'))
print('row11 id-not-name %s' % R.confirm_writes(w11, job(confirmed_intent='issue-7-j1-11-6'), both, F))
print('row11 issue-text %s' % R.confirm_writes(w11, job(issue='7', confirmed_intent='issue-7-j1-11-1'), both, F))
print('row11 no-fdir %s' % R.confirm_writes(w11, job(confirmed_intent='issue-7-j1-11-1'), both))
PY
tr_py "$TR_CODE"
e2e_expect_line "40b intake []"
e2e_expect_line "40b approve ['issueUpdate']"
e2e_expect_line "row11 sent []"
for TR_N in recorded missing other-job label-ready kind-edited status-edited null dotdot id-not-name issue-text; do
  e2e_expect_line "row11 $TR_N ['issueAssign', 'issueUpdate']"
done
e2e_expect_line "row11 label-in-progress ['issueAssign']"
e2e_expect_line "row11 no-fdir []"

_flow_test_begin "factory tiers: the keys left on the path to ready, by stage, and a parked job's resume state (TR9)"
tr_start tr9-path ''
e2e_describe "design execution_model L46-L53 and T:facts.tier_confirm_blocking, read as every blocking write left on the path to ready (design github_writes_and_tiers L68: a job with push at confirm parks before spending spec and build budget). Stage order intake, prepare, spec, build, open_pr, gate, review, rework, sync, resolve, ready, approve; each stage's keys in the design's order, each key once at its first use: intake and prepare [issueAssign, issueUpdate, push, prCreate]; spec, build and open_pr [push, prCreate, issueUpdate]; gate, review, rework, sync and resolve [push, issueUpdate]; ready and approve [issueUpdate]. Plan B7 test plan: a prepare job with only issueUpdate at confirm gives [issueUpdate], with issueAssign and issueUpdate [issueAssign, issueUpdate], with none []; blocking true, true, false. A spec job with only push at confirm gives [push]. A waiting_operator job reads its resume_state's path (prepare: [issueAssign] with issueAssign at confirm; ready: [] with issueAssign at confirm). needs_human raises ValueError; a waiting_operator job with no resume_state, or one that has no path, reads every key any path has (fail closed, not an error, since rows 41b and 41p read the fact for every parked job): [issueAssign, issueUpdate, push, prCreate] filtered by confirm"
read -r -d '' TR_CODE <<'PY' || true
for s in ('intake', 'prepare', 'spec', 'build', 'open_pr', 'gate', 'review', 'rework', 'sync', 'resolve', 'ready', 'approve'):
    print('path %s %s' % (s, R.path_keys(s)))
for tag, t in (('upd', fixed(issueUpdate='confirm')), ('both', fixed(issueAssign='confirm', issueUpdate='confirm')),
               ('none', fixed())):
    print('prepare %s %s %s' % (tag, R.confirm_path_keys(M, BASE, job(), tiers=t),
                                R.tier_confirm_blocking(M, BASE, job(), tiers=t)))
print('spec push %s' % R.confirm_path_keys(M, BASE, job('spec'), tiers=fixed(push='confirm')))
assign = fixed(issueAssign='confirm')
print('parked prepare %s %s' % (R.confirm_path_keys(M, BASE, job('waiting_operator', resume_state='prepare'), tiers=assign),
                                R.tier_confirm_blocking(M, BASE, job('waiting_operator', resume_state='prepare'), tiers=assign)))
print('parked ready %s %s' % (R.confirm_path_keys(M, BASE, job('waiting_operator', resume_state='ready'), tiers=assign),
                              R.tier_confirm_blocking(M, BASE, job('waiting_operator', resume_state='ready'), tiers=assign)))
for tag, j in (('parked-no-resume', job('waiting_operator')), ('parked-merged', job('waiting_operator', resume_state='merged'))):
    print('%s %s' % (tag, R.confirm_path_keys(M, BASE, j, tiers=fixed(push='confirm', issueAssign='confirm'))))
for tag, j in (('needs_human', job('needs_human')),):
    try:
        R.confirm_path_keys(M, BASE, j, tiers=assign)
        print('unknown %s no-raise' % tag)
    except ValueError:
        print('unknown %s raised' % tag)
PY
tr_py "$TR_CODE"
e2e_expect_line "path intake ['issueAssign', 'issueUpdate', 'push', 'prCreate']"
e2e_expect_line "path prepare ['issueAssign', 'issueUpdate', 'push', 'prCreate']"
for TR_N in spec build open_pr; do
  e2e_expect_line "path $TR_N ['push', 'prCreate', 'issueUpdate']"
done
for TR_N in gate review rework sync resolve; do
  e2e_expect_line "path $TR_N ['push', 'issueUpdate']"
done
e2e_expect_line "path ready ['issueUpdate']"
e2e_expect_line "path approve ['issueUpdate']"
e2e_expect_line "prepare upd ['issueUpdate'] True"
e2e_expect_line "prepare both ['issueAssign', 'issueUpdate'] True"
e2e_expect_line "prepare none [] False"
e2e_expect_line "spec push ['push']"
e2e_expect_line "parked prepare ['issueAssign'] True"
e2e_expect_line "parked ready [] False"
e2e_expect_line "unknown needs_human raised"
e2e_expect_line "parked-no-resume ['issueAssign', 'push']"
e2e_expect_line "parked-merged ['issueAssign', 'push']"

_flow_test_begin "factory tiers: intent_key_not_confirm reads every key of the pending intent, and is false with none (TR10)"
tr_start tr10-intent ''
tr_file "~/.claude/settings.flow.json" '{"tiers": {"issueAssign": "confirm", "issueUpdate": "confirm", "push": "confirm", "prCreate": "confirm"}}'
e2e_describe "T:facts.intent_key_not_confirm and plan 3.1: with every key at confirm (user file), a job with pending_intent null gives False. Through a tiers callable: an intent keyed [issueAssign, issueUpdate] with both journal gives True; with only issueUpdate at confirm, False; an intent with an empty key list gives False (no key was checked)"
read -r -d '' TR_CODE <<'PY' || true
park = dict(state='waiting_operator', resume_state='prepare')
print('none %s' % R.intent_key_not_confirm(M, BASE, job(**park)))
pi = {'id': 'issue-7-j1-11-1', 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']}
print('real-confirm %s' % R.intent_key_not_confirm(M, BASE, job(pending_intent=pi, **park)))
print('journal %s' % R.intent_key_not_confirm(M, BASE, job(pending_intent=pi, **park), tiers=fixed()))
print('one-confirm %s' % R.intent_key_not_confirm(M, BASE, job(pending_intent=pi, **park), tiers=fixed(issueUpdate='confirm')))
print('empty %s' % R.intent_key_not_confirm(M, BASE, job(pending_intent=dict(pi, key=[]), **park), tiers=fixed()))
PY
tr_py "$TR_CODE"
e2e_expect_line "none False"
e2e_expect_line "real-confirm False"
e2e_expect_line "journal True"
e2e_expect_line "one-confirm False"
e2e_expect_line "empty False"

_flow_test_begin "factory tiers: issueUpdate's plugin default comes from the plugin's settings.json"
tr_start tr11-default ''
e2e_describe "design settings_keys L60 and plan 2.5: tiers.issueUpdate defaults to journal in the plugin's settings.json; with no other source, resolve gives journal; a user file setting it to autonomous still gives journal (the default is one of the four sources); confirm in the user file gives confirm"
read -r -d '' TR_CODE <<'PY' || true
usr = os.path.join(os.environ['HOME'], '.claude', 'settings.flow.json')
os.makedirs(os.path.dirname(usr), exist_ok=True)
print('default %s' % R.resolve(M, BASE, 'issueUpdate'))
open(usr, 'w').write('{"tiers": {"issueUpdate": "autonomous"}}')
print('user-autonomous %s' % R.resolve(M, BASE, 'issueUpdate'))
open(usr, 'w').write('{"tiers": {"issueUpdate": "confirm"}}')
print('user-confirm %s' % R.resolve(M, BASE, 'issueUpdate'))
print('plugin-file %s' % json.load(open(os.path.join(os.environ['CLAUDE_PLUGIN_ROOT'], 'settings.json')))['tiers']['issueUpdate'])
PY
tr_py "$TR_CODE"
e2e_expect_line "default journal"
e2e_expect_line "user-autonomous journal"
e2e_expect_line "user-confirm confirm"
e2e_expect_line "plugin-file journal"

_flow_test_begin "factory tiers: a key no source sets is confirm; a cascade-resolve.sh that exits 1 counts as confirm (TR11)"
tr_start tr11-unset ''
e2e_describe "plan B7 step 2 (fail closed): with no file setting anything, a key no source sets (noSuchKey, not in the plugin's settings.json either) resolves to confirm, with base_problem None and no problems, so the confirm comes from the empty case and not from a failed source. Then the plugin copy's cascade-resolve.sh prints the real script's answer for --repo-settings-paths and --user-settings-path and exits 1 (every other call runs the real script): issueAssign, journal everywhere else, gives confirm, with problems naming both calls as exited 1"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('unset %s %s %s' % (t('noSuchKey'), t.base_problem, t.problems))
print('assign %s' % t('issueAssign'))
PY
tr_py "$TR_CODE"
e2e_expect_line "unset confirm None []"
e2e_expect_line "assign journal"
e2e_plugin_copy bin/cascade-resolve.sh '#!/usr/bin/env bash
real="$(dirname "$0")/cascade-resolve-real.sh"
case "${1:-}" in
  --repo-settings-paths|--user-settings-path) "$real" "$@"; exit 1 ;;
esac
exec "$real" "$@"'
cp "$E2E_PLUGIN_DIR/bin/cascade-resolve.sh" "$E2E_ACTIVE_PLUGIN/bin/cascade-resolve-real.sh" \
  || _e2e_result fail "copied the real cascade-resolve.sh beside the stand-in"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('failing %s %s' % (t('issueAssign'), t.base_problem))
for p in t.problems:
    print('problem %s' % p)
PY
tr_py "$TR_CODE"
e2e_expect_line "failing confirm None"
e2e_expect_line "problem cascade-resolve.sh --repo-settings-paths: exited 1"
e2e_expect_line "problem cascade-resolve.sh --user-settings-path: exited 1"

_flow_test_begin "factory tiers: a .claude at the base ref that is not a directory counts as confirm (TR13)"
tr_start tr13-parent ''
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  if [ -e .claude ]; then mv .claude "$E2E_DIR/claude-before" || exit 1; fi
  mkdir real && printf '%s\n' '{"tiers": {"issueAssign": "confirm"}}' > real/settings.flow.json \
    && ln -s real .claude && git add .claude real/settings.flow.json \
    && git commit -q -m 'settings under a linked .claude'
) || _e2e_result fail "committed .claude as a symbolic link to real/, whose settings.flow.json sets issueAssign confirm"
printf 'committed .claude on main as a symbolic link to real/, with real/settings.flow.json setting issueAssign confirm\n' | _e2e_art
fe_origin_local
e2e_describe "plan B7 step 2 (fail closed): origin/main's .claude is a symbolic link (mode 120000) to a directory whose settings.flow.json sets issueAssign confirm, so git lists no .claude/settings.flow.json; every other source gives journal. Reading that as no project file gives journal; the engine instead refuses the source, so issueAssign is confirm and base_problem names .claude as not a directory. Then .claude committed as a regular file: confirm, with the same problem"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('link %s %s' % (t('issueAssign'), 'not a directory' in (t.base_problem or '')))
PY
tr_py "$TR_CODE"
e2e_expect_line "link confirm True"
(
  _e2e_git_env
  cd "$E2E_REPO" && git rm -q .claude && printf 'x\n' > .claude && git add .claude \
    && git commit -q -m '.claude as a file'
) || _e2e_result fail "committed .claude as a regular file"
printf 'committed .claude on main as a regular file\n' | _e2e_art
fe_origin_local
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('file %s %s' % (t('issueAssign'), 'not a directory' in (t.base_problem or '')))
PY
tr_py "$TR_CODE"
e2e_expect_line "file confirm True"

# tr_tree <json> <path>... — commit main with the project file removed and
# <json> written at each <path>, through git's index alone: on a file system
# that ignores case, git add can record a case-variant name under the name
# already tracked, so the paths are given to git exactly as written. The
# working tree is left as it was; the engine reads origin/main only. Every
# entry an earlier call made (.CLAUDE among them) leaves the index first.
tr_tree() {
  local json="$1"; shift
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    blob=$(printf '%s\n' "$json" | git hash-object -w --stdin) || exit 1
    git rm -q -r --cached --ignore-unmatch -- ':(icase).claude' café.txt || exit 1
    for p in "$@"; do git update-index --add --cacheinfo "100644,$blob,$p" || exit 1; done
    git commit -q -m "settings at $*" || exit 1
  ) || _e2e_result fail "tr_tree committed $*"
  printf 'committed main with %s at: %s\n' "$json" "$*" | _e2e_art
  fe_origin_local
}

_flow_test_begin "factory tiers: a project file named only by case or Unicode folding counts as confirm (TR14)"
tr_start tr14-case ''
e2e_describe "plan B7 step 2 (fail closed): a checkout on a file system that ignores case (macOS by default) finds .claude/settings.flow.json under .Claude/settings.flow.json, .claude/Settings.flow.json or .claude/ſettings.flow.json (the long s folds to s; probed on APFS 2026-11-19), but git lists those under their own names. Each holds issueAssign confirm; every other source gives journal. Reading the commit as having no project file gives journal; the engine refuses the source, so issueAssign is confirm and base_problem says the name matches only on a case-insensitive file system. The same holds when the exact file sits beside .CLAUDE/settings.flow.json. The exact file with issueAssign journal beside unrelated names that are not ASCII (café.txt at the top, .claude/naïve.json) reads journal with no problem"
for TR_P in .Claude/settings.flow.json .claude/Settings.flow.json .claude/ſettings.flow.json; do
  tr_tree '{"tiers": {"issueAssign": "confirm"}}' "$TR_P"
  TR_LS=$(cd "$E2E_REPO" && git ls-tree -r -z --name-only main | tr '\0' '\n')
  e2e_expect_equal "$TR_P" "$(printf '%s\n' "$TR_LS" | grep -Fx -- "$TR_P")" "main's entry under $TR_P"
  e2e_expect_equal "" "$(printf '%s\n' "$TR_LS" | grep -Fx -- .claude/settings.flow.json)" "main's entry under the exact name"
  read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('variant %s %s' % (t('issueAssign'), 'case-insensitive file system' in (t.base_problem or '')))
PY
  tr_py "$TR_CODE"
  e2e_expect_line "variant confirm True"
done
tr_tree '{"tiers": {"issueAssign": "confirm"}}' .claude/settings.flow.json .CLAUDE/settings.flow.json
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('both %s %s' % (t('issueAssign'), 'case-insensitive file system' in (t.base_problem or '')))
PY
tr_py "$TR_CODE"
e2e_expect_line "both confirm True"
tr_tree '{"tiers": {"issueAssign": "journal"}}' .claude/settings.flow.json café.txt .claude/naïve.json
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('unrelated %s %s' % (t('issueAssign'), t.base_problem))
PY
tr_py "$TR_CODE"
e2e_expect_line "unrelated journal None"

# tr_rawtree (<mode> <name> <id>)... — write a tree object with exactly these
# entries, in this order, through hash-object --literally (which takes names
# git fsck warns about or refuses), and print its id.
tr_rawtree() {
  (
    cd "$E2E_REPO" || exit 1
    while [ $# -ge 3 ]; do
      printf '%s %s\0' "$1" "$2"
      printf "$(printf '%s' "$3" | sed 's/../\\x&/g')"
      shift 3
    done | git hash-object -w -t tree --literally --stdin
  )
}
# tr_blob <value> — a project file blob setting issueAssign to <value>.
tr_blob() { printf '{"tiers": {"issueAssign": "%s"}}\n' "$1" | (cd "$E2E_REPO" && git hash-object -w --stdin); }
# tr_rawcommit <tree> <what> — make main a commit of <tree>, then origin/main.
tr_rawcommit() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    c=$(git -c commit.gpgsign=false commit-tree -p main -m raw "$1") || exit 1
    git update-ref refs/heads/main "$c"
  ) || _e2e_result fail "committed main as $2"
  printf 'committed main as %s\n' "$2" | _e2e_art
  fe_origin_local
}

_flow_test_begin "factory tiers: the project file is the one a checkout of the base ref writes (TR15)"
tr_start tr15-index ''
e2e_describe "plan B7 step 2 (fail closed): the project file at the base ref is the one a checkout writes; probed with git 2.55.0 on 2026-11-19, git read-tree and a real checkout give the same file for each tree below. Every source but the project file gives journal. (1) origin/main's top tree holds one entry named '.claude/settings.flow.json' (a slash in the name) setting issueAssign confirm: a checkout writes it as the project file, so issueAssign is confirm with no problem; a walk of the trees by name finds no .claude and gives journal. (2) Two '.claude' trees, the first holding settings.flow.json (confirm), the second only other.json: a checkout merges them, so confirm with no problem; reading only the last gives journal. (3) The same with Settings.flow.json in the first: confirm, refused as a case variant. (4) A tree holding '..' or '.git': read-tree refuses it, so the source is refused (confirm) and base_problem names read-tree. (5) .claude/settings.flow.json a directory: refused as not a regular file, so confirm. (6) .Claude a symbolic link to a directory whose settings.flow.json sets confirm: a checkout on a file system that ignores case finds the file through it, so confirm, refused as a case variant. (7) Two '.claude' trees, the second holding settings.flow.json (journal): journal with no problem; the main checkout's index is unchanged, its post-index-change hook does not run, and no temporary file is left in the temporary directory"
tr_rawcommit "$(tr_rawtree 100644 .claude/settings.flow.json "$(tr_blob confirm)")" "a top tree with one entry named .claude/settings.flow.json (confirm)"
e2e_expect_equal ".claude/settings.flow.json" "$(cd "$E2E_REPO" && git ls-tree --name-only refs/remotes/origin/main)" "origin/main's top tree"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('slash %s %s' % (t('issueAssign'), t.base_problem))
PY
tr_py "$TR_CODE"
e2e_expect_line "slash confirm None"
# git ls-files lists only the paths under its working directory; the file is
# read the same with main given as a subdirectory of the checkout.
mkdir -p "$E2E_REPO/sub"
read -r -d '' TR_CODE <<'PY' || true
print('sub %s' % (R._project_at(os.path.join(M, 'sub'), BASE, R._fdir(M, None)),))
PY
tr_py "$TR_CODE"
e2e_expect_line "sub ({'issueAssign': 'confirm'}, None)"
TR_T1=$(tr_rawtree 100644 settings.flow.json "$(tr_blob confirm)")
TR_T2=$(tr_rawtree 100644 other.json "$(tr_blob autonomous)")
tr_rawcommit "$(tr_rawtree 40000 .claude "$TR_T1" 40000 .claude "$TR_T2")" "a top tree with two .claude trees, the first holding settings.flow.json (confirm)"
e2e_expect_equal "2" "$(cd "$E2E_REPO" && git ls-tree refs/remotes/origin/main | grep -c '	\.claude$')" "origin/main's .claude entries"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('dup %s %s' % (t('issueAssign'), t.base_problem))
PY
tr_py "$TR_CODE"
e2e_expect_line "dup confirm None"
TR_T1=$(tr_rawtree 100644 Settings.flow.json "$(tr_blob confirm)")
tr_rawcommit "$(tr_rawtree 40000 .claude "$TR_T1" 40000 .claude "$TR_T2")" "a top tree with two .claude trees, the first holding Settings.flow.json (confirm)"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('dupcase %s %s' % (t('issueAssign'), 'case-insensitive file system' in (t.base_problem or '')))
PY
tr_py "$TR_CODE"
e2e_expect_line "dupcase confirm True"
for TR_N in .. .git; do
  tr_rawcommit "$(tr_rawtree 100644 "$TR_N" "$(tr_blob autonomous)")" "a top tree holding $TR_N"
  e2e_expect_equal "$TR_N" "$(cd "$E2E_REPO" && git ls-tree --name-only refs/remotes/origin/main)" "origin/main's top tree"
  read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('refused %s %s' % (t('issueAssign'), 'read-tree' in (t.base_problem or '')))
PY
  tr_py "$TR_CODE"
  e2e_expect_line "refused confirm True"
done
tr_rawcommit "$(tr_rawtree 40000 .claude "$(tr_rawtree 40000 settings.flow.json "$(tr_rawtree 100644 x "$(tr_blob journal)")")")" "a top tree whose .claude/settings.flow.json is a directory"
e2e_expect_equal "040000 tree" "$(cd "$E2E_REPO" && git ls-tree refs/remotes/origin/main -- .claude/settings.flow.json | cut -c1-11)" "origin/main's .claude/settings.flow.json"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('dir %s %s' % (t('issueAssign'), 'not a regular file' in (t.base_problem or '')))
PY
tr_py "$TR_CODE"
e2e_expect_line "dir confirm True"
tr_rawcommit "$(tr_rawtree 120000 .Claude "$(cd "$E2E_REPO" && printf 'real' | git hash-object -w --stdin)" 40000 real "$(tr_rawtree 100644 settings.flow.json "$(tr_blob confirm)")")" "a top tree with .Claude a symbolic link to real/, whose settings.flow.json sets confirm"
e2e_expect_equal "120000" "$(cd "$E2E_REPO" && git ls-tree refs/remotes/origin/main -- .Claude | cut -c1-6)" "origin/main's .Claude mode"
read -r -d '' TR_CODE <<'PY' || true
t = R.resolver(M, BASE)
print('caselink %s %s' % (t('issueAssign'), 'case-insensitive file system' in (t.base_problem or '')))
PY
tr_py "$TR_CODE"
e2e_expect_line "caselink confirm True"
tr_rawcommit "$(tr_rawtree 40000 .claude "$TR_T2" 40000 .claude "$(tr_rawtree 100644 settings.flow.json "$(tr_blob journal)")")" "a top tree with two .claude trees, the second holding settings.flow.json (journal)"
mkdir -p "$E2E_DIR/tiers-tmp"
cp "$E2E_REPO/.git/index" "$E2E_DIR/index-before"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$E2E_DIR" > "$E2E_REPO/.git/hooks/post-index-change"
chmod +x "$E2E_REPO/.git/hooks/post-index-change"
read -r -d '' TR_CODE <<PY || true
import tempfile
tempfile.tempdir = '$E2E_DIR/tiers-tmp'
t = R.resolver(M, BASE)
print('read %s %s %s' % (t('issueAssign'), t.base_problem, os.listdir(tempfile.tempdir)))
PY
tr_py "$TR_CODE"
e2e_expect_line "read journal None []"
e2e_expect_equal "no" "$([ -e "$E2E_DIR/hook-ran" ] && echo yes || echo no)" "whether the post-index-change hook ran"
e2e_expect_equal "same" "$(cmp -s "$E2E_DIR/index-before" "$E2E_REPO/.git/index" && echo same || echo changed)" "the main checkout's index"
