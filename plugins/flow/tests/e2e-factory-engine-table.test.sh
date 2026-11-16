# shellcheck shell=bash
# The factory's table evaluator (bin/_flow_factory_table.py): the fact and
# effect registries, choose, apply, check_move and the fence, run in
# isolation through fe_py. Every row driven through `next` is a later file's
# test; this one checks the evaluator against the shipped state table and
# against the docs checker, which an installed plugin does not have.
#
# Ways it can be wrong, written down before the checks:
#   TB1  it reads a table other than the plugin copy, or a missing or broken
#        table is not refused as table_unreadable
#   TB2  the derived facts are evaluated in the wrong order (the confirm park,
#        row 40, taken before the pre-push check, row 21f), or rows are chosen
#        by row id or by their place in the file instead of by precedence; so
#        a push the pre-push check refused is parked as a push intent
#   TB3  a list-valued record (row 20b from review) is copied whole, or its
#        first entry taken, instead of the target of the row that wins with
#        the record's fact false (rules.records_as_if)
#   TB4  `writes` is read as a list only, so a per-from-state map gives the
#        wrong writes or none
#   TB5  a pending change is dropped once any row applies, not only when a row
#        whose guard reads its fact as true applies
#   TB6  the slot is freed only by row effects, so a job entering ready or a
#        parked state keeps it; or it is freed on every move
#   TB7  an effect string no registry entry classifies passes, so a table edit
#        adds an effect nothing handles
#   TB8  an unbuilt fact is evaluated outside the seam, or a winner that makes
#        a blocking write is applied with its derived inputs guessed
#   TB9  no winner, or a tie, is not refused, or no_move_ok is ignored
#   TB10 a computed target (resume_state, blocked_stage) is used without
#        checking that a parking row can record it
#   TB11 a replayed move outside the table is accepted
#   TB12 an event outside its occurs_in list is evaluated
#   TB13 an effect that writes a job field the 1a facts or status read is
#        deferred instead of applied, or applied with the wrong value

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# The docs checker is the reference for the witnesses and the expected
# records. Importing it must not write bytecode into the repository, so the
# prelude turns bytecode off before the import (plan 2.16, Bytecode).
TB_DOCS="$REPO_ROOT/docs/flow-factory"

# The Python every scenario starts with: the evaluator, the shipped table
# through load_table, and helpers that take witnesses from the docs checker.
#   job(state, **fields)      a job dict in that state
#   checker(state)            the docs checker with only that state's pairs covered
#   witness(c, row, state, event)
#                             one fact assignment where that row is the single
#                             winner with both derived facts false
#   inputs(a, derived)        a seam and a Context giving exactly the facts of a:
#                             unbuilt facts through the seam, built facts through
#                             ctx.built; a fact the pair reads that a lacks fails
#   scratch_table(edit)       the shipped table edited by edit(data), written
#                             under the scenario folder, loaded with load_table
TB_PRE="import sys, os, json, copy
sys.dont_write_bytecode = True
DOCS = '$TB_DOCS'
"
read -r -d '' TB_PRE_BODY <<'PY' || true
import _flow_factory_table as T
from _flow_factory import Refused
TAB = T.load_table()
DATA = TAB.data
BWC, PPF = 'blocking_write_confirm', 'prepush_protected_failed'
def job(state, **kw):
    d = {'key': 'issue-7-j1', 'issue': 7, 'state': state, 'attempt': 0, 'holds_slot': False}
    d.update(kw)
    return d
def checker(state):
    sys.path.insert(0, DOCS)
    import check_transitions as ct
    sys.path.remove(DOCS)
    c = ct.Checker(copy.deepcopy(DATA))
    assert c.schema(), c.errors
    c.nonterm = [state]
    c.coverage()
    return c
def witness(c, row, state, event):
    rows, facts, deps = c.pair_info[(state, event)]
    for a in c.assignments_of(facts, deps):
        if a.get(BWC) or a.get(PPF):
            continue
        top = c.top_rows(rows, a)
        if len(top) == 1 and top[0]['id'] == row:
            return a
    raise SystemExit('no witness for row %s in %s' % (row, state))
def inputs(a, derived=None, setting=None):
    unb = dict((f, v) for f, v in a.items() if T.PROVIDERS[f].kind == 'unbuilt')
    blt = dict((f, (lambda v=v: v)) for f, v in a.items() if T.PROVIDERS[f].kind == 'built')
    T.set_seam({'unbuilt': {'*': unb},
                'derived_inputs': derived or {'confirm_keys': [], 'prepush_fails': False}})
    return T.Context(built=blt, setting=setting or (lambda k, d: d), pass_id='p1',
                     now='2026-11-16T00:00:00Z')
def scratch_table(edit, name='table.json'):
    d = copy.deepcopy(DATA)
    edit(d)
    p = os.path.join(os.environ['E2E_DIR'], name)
    with open(p, 'w') as f:
        json.dump(d, f)
    return T.load_table(p)
def show(d):
    n = type(d).__name__
    if n == 'Winner':
        return 'Winner row=%s to=%s stay=%s' % (d.row, d.to, d.stay)
    if n == 'Blocked':
        return 'Blocked fact=%s phase=%s missing=%s' % (d.fact, d.phase, d.missing)
    if n == 'Refusal':
        return d.line
    return '%s %s' % (n, getattr(d, 'entry', ''))
PY
TB_PRE="$TB_PRE$TB_PRE_BODY"

# tb_py <python> — run the prelude and then the scenario's Python.
tb_py() { fe_py "$TB_PRE
$1"; }

_flow_test_begin "factory table: load_table reads only the plugin's own copy and refuses a missing or broken one (TB1)"
fe_new tb1-plugin-copy
e2e_repo main
e2e_describe "a plugin copy whose references/factory-transitions.json is missing, then broken, then edited to drop row 21: the evaluator loaded from that copy refuses the first two and sees the edit, so it reads no other table"
E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" || _flow_assert_fail "tb1: cannot copy the plugin"
TB_TABLE="$E2E_ACTIVE_PLUGIN/references/factory-transitions.json"
read -r -d '' TB_LOAD <<'PY' || true
import sys; sys.dont_write_bytecode = True
import sys
import _flow_factory_table as T
from _flow_factory import Refused
print('table=' + T.TABLE_FILE)
try:
    t = T.load_table()
    print('rows=%d has_21=%s' % (len(t.rows), '21' in t.by_id))
except Refused as e:
    print('FACTORY_REFUSED=%s' % e)
PY
mv "$TB_TABLE" "$E2E_DIR/table.orig.json"
fe_py "$TB_LOAD"
e2e_expect_line "table=$E2E_ACTIVE_PLUGIN/references/factory-transitions.json"
e2e_expect_line "FACTORY_REFUSED=table_unreadable"
printf '{"rows": [' > "$TB_TABLE"
fe_py "$TB_LOAD"
e2e_expect_line "FACTORY_REFUSED=table_unreadable"
jq -c 'del(.rows[] | select(.id == "21"))' "$E2E_DIR/table.orig.json" > "$TB_TABLE"
fe_py "$TB_LOAD"
e2e_expect_line "rows=170 has_21=False"
E2E_ACTIVE_PLUGIN="$E2E_PLUGIN_DIR"
fe_py "$TB_LOAD"
e2e_expect_line "rows=171 has_21=True"

_flow_test_begin "factory table: with both derived inputs true, the pre-push check wins and no push intent is recorded (TB2, RM2)"
fe_new tb2-derived-order
e2e_repo main
e2e_describe "open_pr, stage_succeeded, whose only rows are 21f (precedence 44), 40 (45) and 21 (60, writes push and PR create or edit): both derived inputs true gives 21f; only the confirm input gives 40; neither gives 21. The same on a table whose rows are in reverse file order"
read -r -d '' TB_CODE <<'PY' || true
print('reads=' + ','.join(sorted(T.facts_read(TAB, 'open_pr', 'stage_succeeded'))))
print('rows=' + ','.join('%s:%d' % (r['id'], r['precedence']) for r in TAB.rows_for('open_pr', 'stage_succeeded')))
def case(name, tab, keys, fails):
    T.set_seam({'default_unbuilt': False, 'derived_inputs': {'confirm_keys': keys, 'prepush_fails': fails}})
    ctx = T.Context(built={}, setting=lambda k, d: d, pass_id='p1', now='2026-11-16T00:00:00Z')
    j = job('open_pr', holds_slot=True)
    d = T.choose(tab, j, 'stage_succeeded', ctx)
    print('%s: %s' % (name, show(d)))
    if type(d).__name__ != 'Winner':
        return
    new, line, run, deferred = T.apply(tab, j, d, ctx)
    mentions = sum('pending_intent' in x['effect'] for x in deferred) + sum('pending_intent' in e for h, e in run)
    print('%s: state=%s resume_state=%s blocked_stage=%s reason=%s pending_intent_mentions=%d' % (
        name, new['state'], new.get('resume_state'), new.get('blocked_stage'), new.get('reason'), mentions))
    print('%s: line row=%s to=%s stay=%s records=%s' % (name, line['row'], line['to'], line['stay'],
                                                     json.dumps(line['records'], sort_keys=True)))
for tab, tag in ((TAB, 'file'), (scratch_table(lambda d: d['rows'].reverse(), 'reversed.json'), 'reversed')):
    case(tag + ' both', tab, ['push', 'PR create or edit'], True)
    case(tag + ' confirm', tab, ['push', 'PR create or edit'], False)
    case(tag + ' none', tab, [], False)
PY
tb_py "$TB_CODE"
e2e_expect_line "reads="
e2e_expect_line "rows=21f:44,40:45,21:60"
for TB_T in file reversed; do
  e2e_expect_line "$TB_T both: Winner row=21f to=needs_human stay=False"
  e2e_expect_line "$TB_T both: state=needs_human resume_state=None blocked_stage=open_pr reason=protected pending_intent_mentions=0"
  e2e_expect_line "$TB_T both: line row=21f to=needs_human stay=False records={\"blocked_stage\": \"open_pr\"}"
  e2e_expect_line "$TB_T confirm: Winner row=40 to=waiting_operator stay=False"
  e2e_expect_line "$TB_T confirm: state=waiting_operator resume_state=open_pr blocked_stage=None reason=None pending_intent_mentions=1"
  e2e_expect_line "$TB_T none: Winner row=21 to=gate stay=False"
  e2e_expect_line "$TB_T none: state=gate resume_state=None blocked_stage=None reason=None pending_intent_mentions=0"
done

_flow_test_begin "factory table: the lowest precedence wins, whatever the row ids and file order (TB2, RM2)"
fe_new tb2-precedence
e2e_repo main
e2e_describe "the evaluator's row choice for open_pr, stage_succeeded with both derived facts set true at once: 21f (44) wins over 40 (45) on the shipped table, and 40 wins once 21f's precedence is 46 (conventions.precedence: the lowest number applies). A choice by row id or file order gives 21f both times; a choice by the highest number gives 40 both times. choose itself still gives 21f on the edited table, because it derives the pre-push fact before the confirm fact and row 40 then does not match"
read -r -d '' TB_CODE <<'PY' || true
both = {BWC: True, PPF: True}
def edit46(d):
    for r in d['rows']:
        if r['id'] == '21f':
            r['precedence'] = 46
t46 = scratch_table(edit46, 'p46.json')
print('shipped: ' + ','.join(r['id'] for r in T.winners(TAB, 'open_pr', 'stage_succeeded', both)))
print('21f at 46: ' + ','.join(r['id'] for r in T.winners(t46, 'open_pr', 'stage_succeeded', both)))
T.set_seam({'default_unbuilt': False, 'derived_inputs': {'confirm_keys': ['push'], 'prepush_fails': True}})
ctx = T.Context(built={}, setting=lambda k, d: d)
print('choose 21f at 46: ' + show(T.choose(t46, job('open_pr'), 'stage_succeeded', ctx)))
PY
tb_py "$TB_CODE"
e2e_expect_line "shipped: 21f"
e2e_expect_line "21f at 46: 40"
e2e_expect_line "choose 21f at 46: Winner row=21f to=needs_human stay=False"

_flow_test_begin "factory table: a list-valued record is the target of the row that wins with its fact false (TB3)"
fe_new tb3-records-as-if
e2e_repo main
e2e_describe "for every fact assignment the docs checker finds where row 20b (review, build, rework, resolve) or row 14 (spec) is the single winner, the evaluator picks the same row and records resume_state equal to the target of the checker's winner with the record's fact false"
read -r -d '' TB_CODE <<'PY' || true
for row, state, fact in (('20b', 'review', 'spec_change_needs_approval'), ('20b', 'build', 'spec_change_needs_approval'),
                         ('20b', 'rework', 'spec_change_needs_approval'), ('20b', 'resolve', 'spec_change_needs_approval'),
                         ('14', 'spec', 'spec_approval_required')):
    c = checker(state)
    rows, facts, deps = c.pair_info[(state, 'stage_succeeded')]
    n = same_row = same_record = 0
    values = set()
    for a in c.assignments_of(facts, deps):
        if a.get(BWC) or a.get(PPF):
            continue
        top = c.top_rows(rows, a)
        if len(top) != 1 or top[0]['id'] != row:
            continue
        a0 = dict(a); a0[fact] = False
        want = c.top_rows(rows, a0)[0]['to']
        n += 1
        ctx = inputs(a)
        d = T.choose(TAB, job(state), 'stage_succeeded', ctx)
        if type(d).__name__ == 'Winner' and d.row == row:
            same_row += 1
            new = T.apply(TAB, job(state), d, ctx)[0]
            if new.get('resume_state') == want:
                same_record += 1
            values.add(new.get('resume_state'))
    print('%s %s: witnesses>0=%s same_row=%s same_record=%s values=%s' % (
        row, state, n > 0, same_row == n, same_record == n, ','.join(sorted(map(str, values)))))
PY
tb_py "$TB_CODE"
e2e_expect_line "20b review: witnesses>0=True same_row=True same_record=True values=gate,rework,sync"
e2e_expect_line "20b build: witnesses>0=True same_row=True same_record=True values=open_pr"
e2e_expect_line "20b rework: witnesses>0=True same_row=True same_record=True values=gate"
e2e_expect_line "20b resolve: witnesses>0=True same_row=True same_record=True values=gate"
e2e_expect_line "14 spec: witnesses>0=True same_row=True same_record=True values=build"

_flow_test_begin "factory table: writes are read from a list or from a per-from-state map (TB4)"
fe_new tb4-writes
e2e_repo main
e2e_describe "row 43a's writes are {approve: [undo of ready]}; row 21's are a list; row 39 has none"
read -r -d '' TB_CODE <<'PY' || true
for rid, s in (('43a', 'approve'), ('43a', 'build'), ('21', 'open_pr'), ('39', 'build')):
    print('%s %s: %s' % (rid, s, json.dumps(T.writes_for(TAB.by_id[rid], s))))
PY
tb_py "$TB_CODE"
e2e_expect_line '43a approve: ["undo of ready"]'
e2e_expect_line '43a build: []'
e2e_expect_line '21 open_pr: ["push", "PR create or edit"]'
e2e_expect_line '39 build: []'

_flow_test_begin "factory table: a pending change stays until a row whose guard reads its fact as true applies (TB5)"
fe_new tb5-pending-changes
e2e_repo main
e2e_describe "intake, github_change: row 50 reads issue_changed true and not cancel_signal, so it clears issue_changed and keeps cancel_signal; row 53b reads cancel_signal true and clears it"
read -r -d '' TB_CODE <<'PY' || true
print('53b guard=' + json.dumps(TAB.by_id['53b']['guard'], sort_keys=True))
for row in ('50', '53b'):
    a = witness(checker('intake'), row, 'intake', 'github_change')
    ctx = inputs(a)
    j = job('intake', pending_changes=['issue_changed', 'cancel_signal'])
    d = T.choose(TAB, j, 'github_change', ctx)
    new = T.apply(TAB, j, d, ctx)[0]
    print('%s: winner=%s pending_changes=%s' % (row, d.row, ','.join(new['pending_changes'])))
PY
tb_py "$TB_CODE"
e2e_expect_line '53b guard={"cancel_signal": true}'
e2e_expect_line "50: winner=50 pending_changes=cancel_signal"
e2e_expect_line "53b: winner=53b pending_changes=issue_changed"

_flow_test_begin "factory table: the slot is freed on entry to ready, a parked state or a terminal state, and only then (TB6)"
fe_new tb6-slots
e2e_repo main
e2e_describe "a job holding a slot: row 31 (sync to ready on stage_succeeded), row 43a (build to needs_human) and row 53b (to cancelled) free it; row 21 (open_pr to gate) and stay row 39 keep it"
read -r -d '' TB_CODE <<'PY' || true
for row, state, event, extra in (('31', 'sync', 'stage_succeeded', {}), ('43a', 'build', 'stage_failed', {'attempt': 2}),
                                 ('53b', 'build', 'github_change', {}), ('21', 'open_pr', 'stage_succeeded', {}),
                                 ('39', 'build', 'stage_failed', {})):
    a = witness(checker(state), row, state, event)
    ctx = inputs(a)
    j = job(state, holds_slot=True, **extra)
    d = T.choose(TAB, j, event, ctx)
    new = T.apply(TAB, j, d, ctx)[0]
    print('%s: winner=%s state=%s holds_slot=%s' % (row, d.row, new['state'], new['holds_slot']))
PY
tb_py "$TB_CODE"
e2e_expect_line "31: winner=31 state=ready holds_slot=False"
e2e_expect_line "43a: winner=43a state=needs_human holds_slot=False"
e2e_expect_line "53b: winner=53b state=cancelled holds_slot=False"
e2e_expect_line "21: winner=21 state=gate holds_slot=True"
e2e_expect_line "39: winner=39 state=build holds_slot=True"

_flow_test_begin "factory table: every effect string of the table is classified, and an unknown one refuses the table (TB7)"
fe_new tb7-effects
e2e_repo main
e2e_describe "the effect registry against every effect string of every row and of creation row 1 (230, counted over the table), the launching rows T11 relies on, and a scratch table with one effect changed to 'teleport the job'"
read -r -d '' TB_CODE <<'PY' || true
strings = set()
for r in DATA['rows'] + DATA['creation']:
    strings.update(r['effects'])
print('effects classified: %d of %d' % (len(set(T.EFFECTS) & strings), len(strings)))
print('registry size=%d not in table=%d' % (len(T.EFFECTS), len(set(T.EFFECTS) - strings)))
kinds = sorted(set(v[0] for v in T.EFFECTS.values()))
print('kinds=' + ','.join(kinds))
print('phases=' + ','.join(sorted(set(v[1] for v in T.EFFECTS.values() if v[0] == 'deferred'))))
launching = sorted(r['id'] for r in DATA['rows'] if r['event'] == 'launch_due'
                   and any(T.EFFECTS[e] == ('handled', 'launch') for e in r['effects']))
print('launching rows=' + ','.join(launching))
def teleport(d):
    for r in d['rows']:
        if r['id'] == '21':
            r['effects'][0] = 'teleport the job'
try:
    scratch_table(teleport)
    print('teleport: loaded')
except Refused as e:
    print('teleport: FACTORY_REFUSED=%s' % e)
    for p in e.problems:
        print('problem: ' + p)
PY
tb_py "$TB_CODE"
e2e_expect_line "effects classified: 230 of 230"
e2e_expect_line "registry size=230 not in table=0"
e2e_expect_line "kinds=deferred,handled"
e2e_expect_line "phases=1b,1c,1d,1e,1f,1g,2"
e2e_expect_line "launching rows=66,66b,66bp,66i,66m,66p"
e2e_expect_line "teleport: FACTORY_REFUSED=table_unreadable"
e2e_expect_line "problem: row 21 effect not classified: teleport the job"

_flow_test_begin "factory table: outside the seam, a pair that reads an unbuilt fact is Blocked (TB8)"
fe_new tb8-fence
e2e_repo main
e2e_describe "build, launch_due with no seam: Blocked on the first unbuilt fact in sorted order of the facts the pair reads, computed here from the table and the 1a built list, not from the evaluator"
read -r -d '' TB_CODE <<'PY' || true
BUILT_1A = {'probes_stale', 'group_gone', 'orphan_group_alive', 'attempts_exhausted', 'slot_free', 'slot_available',
            'tree_dirty', 'clone_config_changed', 'unvouched_session_action', 'build_started', 'blocked_before_spec',
            'reason_needs_info_exhausted', 'round_limit_reached', 'pr_exists', 'pr_merged_by_person',
            'pr_closed_by_person', 'foreign_head_change'}
c = checker('build')
state, event = 'build', 'launch_due'
rows = [r for r in DATA['rows'] if state in r['from'] and r['event'] == event]
facts = set()
for r in rows:
    facts.update(r.get('guard', {}))
for nm in DATA['events'][event].get('no_move_ok', []):
    if state in nm['states']:
        facts.update(nm.get('when', {}))
if DATA['pass_first']['event'] == event:
    facts.update(DATA['pass_first']['when'])
facts = set(c.closure(facts, c.deps_for(state))) - {BWC, PPF}
print('facts_read agrees=%s' % (T.facts_read(TAB, state, event) == frozenset(facts)))
print('expected fact=' + sorted(f for f in facts if f not in BUILT_1A)[0])
print('built providers=%s' % (sorted(f for f, p in T.PROVIDERS.items() if p.kind == 'built') == sorted(BUILT_1A)))
print('derived providers=' + ','.join(sorted(f for f, p in T.PROVIDERS.items() if p.kind == 'derived')))
print('providers=%d table facts covered=%s' % (len(T.PROVIDERS), set(DATA['facts']) <= set(T.PROVIDERS)))
T.set_seam(None)
print('no seam: ' + show(T.choose(TAB, job(state), event, T.Context(built={}))))
PY
tb_py "$TB_CODE"
e2e_expect_line "facts_read agrees=True"
e2e_expect_line "expected fact=cost_cap_reached"
e2e_expect_line "built providers=True"
e2e_expect_line "derived providers=blocking_write_confirm,prepush_protected_failed"
e2e_expect_line "providers=75 table facts covered=True"
e2e_expect_line "no seam: Blocked fact=cost_cap_reached phase=1g missing=False"

_flow_test_begin "factory table: outside the seam, a winner that makes a blocking write is Blocked on its derived input (TB8)"
fe_new tb8-write-fence
e2e_repo main
e2e_describe "approve, stage_failed reads only built facts: with attempts exhausted row 43a wins with false and writes the undo of ready, so the confirm input (1b) blocks it; with attempts left row 39 (no writes) wins. open_pr, stage_succeeded's winner pushes, so the pre-push input (1e) blocks it. Under a seam that gives no derived input, the pre-push check passes and no key is at confirm (the shared ordinary seam gives none), so row 21 wins; a seam that gives no value for an unbuilt fact the pair reads blocks it"
read -r -d '' TB_CODE <<'PY' || true
T.set_seam(None)
for ex in (True, False):
    ctx = T.Context(built={'attempts_exhausted': lambda ex=ex: ex, 'tree_dirty': lambda: False})
    print('approve attempts_exhausted=%s: %s' % (ex, show(T.choose(TAB, job('approve'), 'stage_failed', ctx))))
print('open_pr: ' + show(T.choose(TAB, job('open_pr'), 'stage_succeeded', T.Context(built={}))))
T.set_seam({'unbuilt': {}})
print('seam without derived inputs: ' + show(T.choose(TAB, job('open_pr'), 'stage_succeeded', T.Context(built={}))))
print('seam without the fact: ' + show(T.choose(TAB, job('build'), 'launch_due', T.Context(built={}))))
T.set_seam(None)
print('creation without seam: ' + show(T.choose_creation(TAB, 'issue-7-j1', T.Context())))
T.set_seam({'unbuilt': {'issue-7-j1': {'creation_allowed': True}}})
print('creation allowed: ' + show(T.choose_creation(TAB, 'issue-7-j1', T.Context())))
print('creation for another job: ' + show(T.choose_creation(TAB, 'issue-8-j1', T.Context())))
for bad in ({'unbuilt': {'*': {'tree_dirty': False}}}, {'unbuilt': {'*': {BWC: False}}},
            {'unbuilt': {'*': {'no_such_fact': False}}}, {'built_inputs': {'tree_dirty': True}}):
    try:
        T.set_seam(bad)
        print('seam accepted: ' + json.dumps(bad))
    except T.SeamRefused as e:
        print(e.line)
PY
tb_py "$TB_CODE"
e2e_expect_line "approve attempts_exhausted=True: Blocked fact=blocking_write_confirm phase=1b missing=False"
e2e_expect_line "approve attempts_exhausted=False: Winner row=39 to=None stay=True"
e2e_expect_line "open_pr: Blocked fact=prepush_protected_failed phase=1e missing=False"
e2e_expect_line "seam without derived inputs: Winner row=21 to=gate stay=False"
e2e_expect_line "seam without the fact: Blocked fact=cost_cap_reached phase=1g missing=True"
e2e_expect_line "creation without seam: Blocked fact=creation_allowed phase=1b missing=False"
e2e_expect_line "creation allowed: Winner row=1 to=queued stay=False"
e2e_expect_line "creation for another job: Blocked fact=creation_allowed phase=1b missing=True"
e2e_expect_line "SEAM_REFUSED=tree_dirty provider=built"
e2e_expect_line "SEAM_REFUSED=blocking_write_confirm provider=derived"
e2e_expect_line "SEAM_REFUSED=no_such_fact provider=unknown_key"
e2e_expect_line "SEAM_REFUSED=tree_dirty provider=built"

_flow_test_begin "factory table: no winner and a tie are refused, and no_move_ok lets a job stay (TB9)"
fe_new tb9-no-winner
e2e_repo main
e2e_describe "a scratch table without row 21, every input false, for open_pr, stage_succeeded: no row wins; a scratch table with a copy of row 21 named 21z: rows 21 and 21z tie; build, github_change with every fact false: the no_move_ok entry lets the job stay"
read -r -d '' TB_CODE <<'PY' || true
T.set_seam({'default_unbuilt': False, 'derived_inputs': {'confirm_keys': [], 'prepush_fails': False}})
ctx = T.Context(built={}, setting=lambda k, d: d)
no21 = scratch_table(lambda d: d.update(rows=[r for r in d['rows'] if r['id'] != '21']), 'no21.json')
print('no row: ' + show(T.choose(no21, job('open_pr'), 'stage_succeeded', ctx)))
def tie(d):
    r = copy.deepcopy([x for x in d['rows'] if x['id'] == '21'][0])
    r['id'] = '21z'
    d['rows'].append(r)
print('tie: ' + show(T.choose(scratch_table(tie, 'tie.json'), job('open_pr'), 'stage_succeeded', ctx)))
reads = T.facts_read(TAB, 'build', 'github_change')
ctx = T.Context(built=dict((f, (lambda: False)) for f in reads if T.PROVIDERS[f].kind == 'built'))
d = T.choose(TAB, job('build'), 'github_change', ctx)
print('no move: %s states=%s' % (type(d).__name__, ','.join(d.entry['states'])))
PY
tb_py "$TB_CODE"
e2e_expect_line "no row: TRANSITION_REFUSED=open_pr->?: no row wins for event stage_succeeded"
e2e_expect_line "tie: TRANSITION_REFUSED=open_pr->?: rows 21,21z tie for event stage_succeeded"
e2e_expect_line "no move: NoMove states=intake,prepare,spec,build"

_flow_test_begin "factory table: a computed target that no parking row records is refused (TB10)"
fe_new tb10-computed-target
e2e_repo main
e2e_describe "waiting_operator, sync_tick, row 41b (resume from row 40b, which never records ready): resume_state ready is refused and build is taken; needs_human, person_answer, row 44 (resume_from every row entering needs_human): blocked_stage ready is refused and spec is taken"
read -r -d '' TB_CODE <<'PY' || true
for row, state, event, key, values in (('41b', 'waiting_operator', 'sync_tick', 'resume_state', ('ready', 'build')),
                                       ('44', 'needs_human', 'person_answer', 'blocked_stage', ('ready', 'spec'))):
    a = witness(checker(state), row, state, event)
    for v in values:
        ctx = inputs(a)
        j = job(state, reason='tier_confirm', **{key: v})
        d = T.choose(TAB, j, event, ctx)
        try:
            new = T.apply(TAB, j, d, ctx)[0]
            print('%s %s=%s: state=%s' % (d.row, key, v, new['state']))
        except T.TransitionRefused as e:
            print('%s %s=%s: %s' % (d.row, key, v, e.line))
PY
tb_py "$TB_CODE"
e2e_expect_line "41b resume_state=ready: TRANSITION_REFUSED=waiting_operator->ready: resume_state not recorded by a parking row"
e2e_expect_line "41b resume_state=build: state=build"
e2e_expect_line "44 blocked_stage=ready: TRANSITION_REFUSED=needs_human->ready: blocked_stage not recorded by a parking row"
e2e_expect_line "44 blocked_stage=spec: state=spec"

_flow_test_begin "factory table: a replayed move outside the table is refused (TB11)"
fe_new tb11-check-move
e2e_repo main
e2e_describe "check_move for queued to ready on sync_tick (no row), and three moves the table has: queued to intake (row 2), a stay in build on stage_failed (row 39), waiting_operator to build through a computed target (row 41b)"
read -r -d '' TB_CODE <<'PY' || true
for frm, to, ev in (('queued', 'ready', 'sync_tick'), ('queued', 'intake', 'sync_tick'), ('build', None, 'stage_failed'),
                    ('waiting_operator', 'build', 'sync_tick')):
    try:
        T.check_move(TAB, frm, to, ev)
        print('%s->%s %s: ok' % (frm, to, ev))
    except T.TransitionRefused as e:
        print(e.line)
PY
tb_py "$TB_CODE"
e2e_expect_line "TRANSITION_REFUSED=queued->ready: no row moves queued to ready"
e2e_expect_line "queued->intake sync_tick: ok"
e2e_expect_line "build->None stage_failed: ok"
e2e_expect_line "waiting_operator->build sync_tick: ok"

_flow_test_begin "factory table: an event outside its occurs_in list is refused before any fact is read (TB12)"
fe_new tb12-occurs-in
e2e_repo main
e2e_describe "person_reject occurs in needs_spec_approval, waiting_operator and needs_human: from ready it is refused with no fact read (ctx.built is empty and no seam is set); from needs_human it is evaluated and row 48 rejects the job"
read -r -d '' TB_CODE <<'PY' || true
T.set_seam(None)
print('ready: ' + show(T.choose(TAB, job('ready'), 'person_reject', T.Context(built={}))))
d = T.choose(TAB, job('needs_human'), 'person_reject', T.Context(built={'unvouched_session_action': lambda: False}))
print('needs_human: ' + show(d))
PY
tb_py "$TB_CODE"
e2e_expect_line "ready: EVENT_REFUSED=person_reject state=ready"
e2e_expect_line "needs_human: Winner row=48 to=rejected stay=False"

_flow_test_begin "factory table: the effects that write job fields the 1a facts and status read are applied (TB13)"
fe_new tb13-job-effects
e2e_repo main
e2e_describe "43a sets reason attempts_exhausted; 24 adds 1 to an absent round and resets attempt on leaving gate; 37 sets round_limit from round and maxRounds (default 3, then a setting of 4); 13 and 15 set build_started (15 only when resume_state is build); 39 and 39d count an attempt and record the relaunch kind; 66c sets paused_reason; each deferred effect is listed with its phase and leaves no field. attempt is kept on a park (43a leaves it at 2), a self-move (50) and a resume into the recorded stage (44), and reset on entering another stage (24, and 44c from a park in build to intake) or by a fresh-attempts effect (44r)"
read -r -d '' TB_CODE <<'PY' || true
def go(row, state, event, fields, setting=None):
    a = witness(checker(state), row, state, event)
    ctx = inputs(a, setting=setting)
    j = job(state, **fields)
    d = T.choose(TAB, j, event, ctx)
    assert d.row == row, show(d)
    return T.apply(TAB, j, d, ctx)
new, line, run, deferred = go('43a', 'build', 'stage_failed', {'attempt': 2})
print('43a: reason=%s blocked_stage=%s attempt=%s' % (new.get('reason'), new.get('blocked_stage'), new.get('attempt')))
new, line, run, deferred = go('24', 'gate', 'stage_succeeded', {'attempt': 1})
print('24: round=%s attempt=%s state=%s' % (new.get('round'), new.get('attempt'), new['state']))
new, line, run, deferred = go('37', 'ready', 'github_change', {'round': 2})
print('37 default: round_limit=%s' % new.get('round_limit'))
print('37 deferred=' + json.dumps(deferred))
print('37 run=' + ','.join(h for h, e in run))
new = go('37', 'ready', 'github_change', {'round': 2},
         setting=lambda k, d: 4 if k == 'flow.factory.maxRounds' else d)[0]
print('37 maxRounds 4: round_limit=%s' % new.get('round_limit'))
new, line, run, deferred = go('13', 'spec', 'stage_succeeded', {})
print('13: build_started=%s deferred=%s' % (new.get('build_started'), ','.join(x['phase'] for x in deferred)))
for rs in ('build', 'gate'):
    new = go('15', 'needs_spec_approval', 'person_approve_spec', {'resume_state': rs})[0]
    print('15 resume_state=%s: state=%s build_started=%s' % (rs, new['state'], new.get('build_started')))
for row, a0 in (('39', 0), ('39d', 1)):
    new, line, run, deferred = go(row, 'build', 'stage_failed', {'attempt': a0})
    print('%s: attempt=%s relaunch=%s to=%s stay=%s run=%s' % (row, new.get('attempt'), json.dumps(new.get('relaunch'), sort_keys=True),
          line['to'], line['stay'], ','.join(h for h, e in run)))
new, line, run, deferred = go('66c', 'build', 'launch_due', {})
print('66c: paused_reason=%s run=%s' % (new.get('paused_reason'), ','.join(h for h, e in run)))
new, line, run, deferred = go('50', 'intake', 'github_change', {'attempt': 1})
print('50: to=%s stay=%s attempt=%s' % (line['to'], line['stay'], new['attempt']))
for row, event in (('44', 'person_answer'), ('44r', 'person_retry'), ('44c', 'person_retry')):
    new = go(row, 'needs_human', event, {'attempt': 1, 'blocked_stage': 'build', 'reason': 'question'})[0]
    print('%s: state=%s attempt=%s' % (row, new['state'], new.get('attempt')))
PY
tb_py "$TB_CODE"
e2e_expect_line "43a: reason=attempts_exhausted blocked_stage=build attempt=2"
e2e_expect_line "24: round=1 attempt=0 state=rework"
e2e_expect_line "37 default: round_limit=5"
e2e_expect_line '37 deferred=[{"effect": "gh pr ready --undo and remove the flow:ready label", "phase": "1g"}, {"effect": "the review text goes into pr-feedback.md", "phase": "1g"}]'
e2e_expect_line "37 run=kill"
e2e_expect_line "37 maxRounds 4: round_limit=6"
e2e_expect_line "13: build_started=True deferred=1d"
e2e_expect_line "15 resume_state=build: state=build build_started=True"
e2e_expect_line "15 resume_state=gate: state=gate build_started=None"
e2e_expect_line '39: attempt=1 relaunch={"cause_row": "39", "mode": "resume"} to=None stay=True run='
e2e_expect_line '39d: attempt=2 relaunch={"cause_row": "39d", "mode": "fresh"} to=None stay=True run=snapshot,reset'
e2e_expect_line "66c: paused_reason=probes_stale run=no_launch,status_line"
e2e_expect_line "50: to=intake stay=False attempt=1"
e2e_expect_line "44: state=build attempt=1"
e2e_expect_line "44r: state=build attempt=0"
e2e_expect_line "44c: state=intake attempt=0"
