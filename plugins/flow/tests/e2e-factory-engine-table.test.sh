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
#   TB14 a 1b fact stays unbuilt, falls back to a guessed value without its
#        input, or a job-computed one ignores baseline_pending, the round
#        setting, the park reason or the pending foreign head (R91, R100)
#   TB15 a seam still supplies a 1b fact or confirm_keys (R12, R29)
#   TB16 blocking_write_confirm is taken from the seam or guessed instead of
#        asked of ctx.confirm_writes with the winner's writes
#   TB17 the push rows lose the pre-push order or the 1e texts are run
#   TB18 a 1b job handler ignores ctx.sync, acts in rebuild, or leaves a value
#        out of the transition line's fields (R94, R36)
#   TB19 a 1b text is left deferred or given the wrong handler
#   TB20 a handler that reads the issue sync sits in a pair that reads no
#        issue fact, so it could run in a pass with no sync (R88)

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
#   inputs(a, derived, setting, confirm, sync)
#                             a seam and a Context giving exactly the facts of a:
#                             unbuilt facts through the seam, built facts through
#                             ctx.built; a fact the pair reads that a lacks fails.
#                             The seam gives prepush_fails only (it refuses
#                             confirm_keys, plan B13 step 3); the confirm input
#                             is ctx.confirm_writes, returning the keys of
#                             confirm (default none) for any writes
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
def inputs(a, derived=None, setting=None, confirm=None, sync=None):
    unb = dict((f, v) for f, v in a.items() if T.PROVIDERS[f].kind == 'unbuilt')
    blt = dict((f, (lambda v=v: v)) for f, v in a.items() if T.PROVIDERS[f].kind == 'built')
    T.set_seam({'unbuilt': {'*': unb}, 'derived_inputs': derived or {'prepush_fails': False}})
    keys = list(confirm or [])
    return T.Context(built=blt, setting=setting or (lambda k, d: d), pass_id='p1',
                     now='2026-11-16T00:00:00Z', confirm_writes=lambda writes: list(keys), sync=sync)
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
e2e_describe "open_pr, stage_succeeded, whose only rows are 21f (precedence 44), 40 (45) and 21 (60, writes push and PR create or edit): both derived inputs true (the seam's prepush_fails and a confirm_writes returning the push and prCreate keys) gives 21f; only the confirm input gives 40; neither gives 21. The same on a table whose rows are in reverse file order"
read -r -d '' TB_CODE <<'PY' || true
print('reads=' + ','.join(sorted(T.facts_read(TAB, 'open_pr', 'stage_succeeded'))))
print('rows=' + ','.join('%s:%d' % (r['id'], r['precedence']) for r in TAB.rows_for('open_pr', 'stage_succeeded')))
def case(name, tab, keys, fails):
    T.set_seam({'default_unbuilt': False, 'derived_inputs': {'prepush_fails': fails}})
    ctx = T.Context(built={}, setting=lambda k, d: d, pass_id='p1', now='2026-11-16T00:00:00Z',
                    confirm_writes=lambda writes, keys=keys: list(keys))
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
    case(tag + ' both', tab, ['push', 'prCreate'], True)
    case(tag + ' confirm', tab, ['push', 'prCreate'], False)
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
T.set_seam({'default_unbuilt': False, 'derived_inputs': {'prepush_fails': True}})
ctx = T.Context(built={}, setting=lambda k, d: d, confirm_writes=lambda writes: ['push'])
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
# No text is left in phase 1b (plan B13 step 2).
e2e_expect_line "phases=1c,1d,1e,1f,1g,2"
e2e_expect_line "launching rows=66,66b,66bp,66i,66m,66p"
e2e_expect_line "teleport: FACTORY_REFUSED=table_unreadable"
e2e_expect_line "problem: row 21 effect not classified: teleport the job"

_flow_test_begin "factory table: outside the seam, a pair that reads an unbuilt fact is Blocked (TB8)"
fe_new tb8-fence
e2e_repo main
e2e_describe "build, launch_due with no seam: Blocked on the first unbuilt fact in sorted order of the facts the pair reads, computed here from the table and the 1a and 1b built lists, not from the evaluator"
read -r -d '' TB_CODE <<'PY' || true
BUILT_1A = {'probes_stale', 'group_gone', 'orphan_group_alive', 'attempts_exhausted', 'slot_free', 'slot_available',
            'tree_dirty', 'clone_config_changed', 'unvouched_session_action', 'build_started', 'blocked_before_spec',
            'reason_needs_info_exhausted', 'round_limit_reached', 'pr_exists', 'pr_merged_by_person',
            'pr_closed_by_person', 'foreign_head_change'}
# The 16 facts plan 5.3 "Fact inputs" moves from phase 1b's unbuilt list to built providers.
BUILT_1B = {'issue_changed', 'untrusted_edit', 'needs_info_answer', 'untrusted_needs_info_answer',
            'intake_rounds_exhausted', 'cancel_signal', 'untrusted_close', 'via_comment', 'retry_by_triage_only',
            'tier_confirm_blocking', 'park_tier_confirm', 'intent_effect_observed', 'intent_key_not_confirm',
            'pending_intent_stale', 'dependency_open', 'creation_allowed'}
BUILT_1A = BUILT_1A | BUILT_1B
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
e2e_describe "approve, stage_failed reads only built facts: with attempts exhausted row 43a wins with false and writes the undo of ready, so the confirm input decides: confirm_writes returning issueUpdate gives row 40x (T:40x, precedence 30), returning none gives 43a, and no confirm_writes is a caller defect (FactUnavailable); with attempts left row 39 (no writes) wins and confirm_writes is never asked. open_pr, stage_succeeded's winner pushes, so the pre-push input (1e) blocks it before any confirm input is asked. Under a seam that gives no derived input, the pre-push check passes and confirm_writes returns none, so row 21 wins; a seam that gives no value for an unbuilt fact the pair reads blocks it. creation_allowed is built: no callable is FactUnavailable, true gives row 1, false no move, with or without a seam, and a seam naming it is refused"
read -r -d '' TB_CODE <<'PY' || true
def attempt(label, fn):
    try:
        d = fn()
        print(label + ('NoMove' if type(d).__name__ == 'NoMove' else show(d)))
    except T.FactUnavailable:
        print(label + 'FactUnavailable')
T.set_seam(None)
for ex in (True, False):
    for name, cw in (('issueUpdate', lambda writes: ['issueUpdate']), ('none', lambda writes: []), ('absent', None)):
        ctx = T.Context(built={'attempts_exhausted': lambda ex=ex: ex, 'tree_dirty': lambda: False}, confirm_writes=cw)
        attempt('approve attempts_exhausted=%s confirm=%s: ' % (ex, name),
                lambda ctx=ctx: T.choose(TAB, job('approve'), 'stage_failed', ctx))
print('open_pr: ' + show(T.choose(TAB, job('open_pr'), 'stage_succeeded', T.Context(built={}))))
T.set_seam({'unbuilt': {}})
print('seam without derived inputs: ' + show(T.choose(TAB, job('open_pr'), 'stage_succeeded',
                                                      T.Context(built={}, confirm_writes=lambda writes: []))))
attempt('seam without derived inputs or confirm_writes: ',
        lambda: T.choose(TAB, job('open_pr'), 'stage_succeeded', T.Context(built={})))
print('seam without the fact: ' + show(T.choose(TAB, job('build'), 'launch_due', T.Context(built={}))))
for seam in (None, {'unbuilt': {}}):
    T.set_seam(seam)
    tag = 'no seam' if seam is None else 'seam'
    attempt('creation %s without callable: ' % tag, lambda: T.choose_creation(TAB, 'issue-7-j1', T.Context()))
    attempt('creation %s allowed: ' % tag,
            lambda: T.choose_creation(TAB, 'issue-7-j1', T.Context(built={'creation_allowed': lambda: True})))
    attempt('creation %s not allowed: ' % tag,
            lambda: T.choose_creation(TAB, 'issue-7-j1', T.Context(built={'creation_allowed': lambda: False})))
for bad in ({'unbuilt': {'issue-7-j1': {'creation_allowed': True}}},
            {'unbuilt': {'*': {'tree_dirty': False}}}, {'unbuilt': {'*': {BWC: False}}},
            {'unbuilt': {'*': {'no_such_fact': False}}}, {'built_inputs': {'tree_dirty': True}}):
    try:
        T.set_seam(bad)
        print('seam accepted: ' + json.dumps(bad))
    except T.SeamRefused as e:
        print(e.line)
PY
tb_py "$TB_CODE"
e2e_expect_line "approve attempts_exhausted=True confirm=issueUpdate: Winner row=40x to=waiting_operator stay=False"
e2e_expect_line "approve attempts_exhausted=True confirm=none: Winner row=43a to=needs_human stay=False"
e2e_expect_line "approve attempts_exhausted=True confirm=absent: FactUnavailable"
# Row 39 makes no write, so confirm_writes is never asked (plan 5.3 Context).
e2e_expect_line "approve attempts_exhausted=False confirm=issueUpdate: Winner row=39 to=None stay=True"
e2e_expect_line "approve attempts_exhausted=False confirm=none: Winner row=39 to=None stay=True"
e2e_expect_line "approve attempts_exhausted=False confirm=absent: Winner row=39 to=None stay=True"
e2e_expect_line "open_pr: Blocked fact=prepush_protected_failed phase=1e missing=False"
e2e_expect_line "seam without derived inputs: Winner row=21 to=gate stay=False"
e2e_expect_line "seam without derived inputs or confirm_writes: FactUnavailable"
e2e_expect_line "seam without the fact: Blocked fact=cost_cap_reached phase=1g missing=True"
for TB_S in "no seam" "seam"; do
  e2e_expect_line "creation $TB_S without callable: FactUnavailable"
  e2e_expect_line "creation $TB_S allowed: Winner row=1 to=queued stay=False"
  e2e_expect_line "creation $TB_S not allowed: NoMove"
done
e2e_expect_line "SEAM_REFUSED=creation_allowed provider=built"
e2e_expect_line "SEAM_REFUSED=tree_dirty provider=built"
e2e_expect_line "SEAM_REFUSED=blocking_write_confirm provider=derived"
e2e_expect_line "SEAM_REFUSED=no_such_fact provider=unknown_key"
e2e_expect_line "SEAM_REFUSED=tree_dirty provider=built"

_flow_test_begin "factory table: no winner and a tie are refused, and no_move_ok lets a job stay (TB9)"
fe_new tb9-no-winner
e2e_repo main
e2e_describe "a scratch table without row 21, every input false, for open_pr, stage_succeeded: no row wins; a scratch table with a copy of row 21 named 21z: rows 21 and 21z tie; build, github_change with every fact false: the no_move_ok entry lets the job stay"
read -r -d '' TB_CODE <<'PY' || true
T.set_seam({'default_unbuilt': False, 'derived_inputs': {'prepush_fails': False}})
ctx = T.Context(built={}, setting=lambda k, d: d, confirm_writes=lambda writes: [])
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

_flow_test_begin "factory table: the 1b facts are built, four computed from the job and twelve read from ctx.built (TB14, R91, R100)"
fe_new tb14-1b-providers
e2e_repo main
e2e_describe "the 16 facts of phase 1b's old unbuilt list have built providers (plan 5.3 Fact inputs). With no callable: issue_changed is false while baseline_pending is set or no baseline exists and true only when the digests differ (T:facts.issue_changed); intake_rounds_exhausted is intake_round >= flow.factory.intake.maxRounds, default 3 (T:facts.intake_rounds_exhausted, settings.json intake.maxRounds); park_tier_confirm is waiting_operator with reason tier_confirm (T:facts.park_tier_confirm); pending_intent_stale needs a pending push or comment intent and a pending foreign_head_change (T:facts.pending_intent_stale, T:fact_dependencies). The twelve others read ctx.built and raise FactUnavailable without a callable or for a value that is not a bool. Then R100's table half: intake, github_change with untrusted_edit true gives row 51b (T:51b), and without that callable FactUnavailable"
read -r -d '' TB_CODE <<'PY' || true
B1B = ('issue_changed', 'untrusted_edit', 'needs_info_answer', 'untrusted_needs_info_answer', 'intake_rounds_exhausted',
       'cancel_signal', 'untrusted_close', 'via_comment', 'retry_by_triage_only', 'tier_confirm_blocking',
       'park_tier_confirm', 'intent_effect_observed', 'intent_key_not_confirm', 'pending_intent_stale',
       'dependency_open', 'creation_allowed')
COMPUTED4 = ('issue_changed', 'intake_rounds_exhausted', 'park_tier_confirm', 'pending_intent_stale')
print('1b providers=' + ','.join(sorted(set('%s/%s' % (T.PROVIDERS[f].kind, T.PROVIDERS[f].phase) for f in B1B))))
print('1b unbuilt left=%d' % sum(1 for p in T.PROVIDERS.values() if p.kind == 'unbuilt' and p.phase == '1b'))
def val(fact, j, ctx=None):
    try:
        return str(T.PROVIDERS[fact].compute(ctx or T.Context(setting=lambda k, d: d), j))
    except T.FactUnavailable:
        return 'FactUnavailable'
A, B = 'a' * 64, 'b' * 64
for label, fields in (('pending, digests differ', {'baseline_pending': True, 'issue_digest': A, 'baseline_digest': B}),
                      ('no baseline', {'issue_digest': A}),
                      ('no baseline, pending false', {'issue_digest': A, 'baseline_pending': False, 'baseline_digest': None}),
                      ('not pending, digests differ', {'baseline_pending': False, 'issue_digest': A, 'baseline_digest': B}),
                      ('not pending, digests equal', {'baseline_pending': False, 'issue_digest': A, 'baseline_digest': A}),
                      ('no issue digest', {'baseline_pending': False, 'baseline_digest': B})):
    print('issue_changed %s: %s' % (label, val('issue_changed', job('needs_human', **fields))))
four = lambda k, d: 4 if k == 'flow.factory.intake.maxRounds' else d
for r, setting, tag in ((None, None, 'default'), (2, None, 'default'), (3, None, 'default'), (4, None, 'default'),
                        (3, four, 'maxRounds 4'), (4, four, 'maxRounds 4')):
    print('intake_rounds_exhausted round=%s %s: %s' % (r, tag, val('intake_rounds_exhausted', job('needs_info', intake_round=r),
                                                                   T.Context(setting=setting or (lambda k, d: d)))))
for bad in ('4', 0, True, None):
    setting = lambda k, d, bad=bad: bad if k == 'flow.factory.intake.maxRounds' else d
    print('intake_rounds_exhausted round=3 maxRounds %r: %s' % (bad, val('intake_rounds_exhausted', job('needs_info', intake_round=3),
                                                                        T.Context(setting=setting))))
for state, reason in (('waiting_operator', 'tier_confirm'), ('waiting_operator', None), ('needs_human', 'tier_confirm')):
    print('park_tier_confirm %s %s: %s' % (state, reason, val('park_tier_confirm', job(state, reason=reason))))
PI = lambda kind: {'id': 'issue-7-j1-40-3', 'kind': kind, 'key': ['issueUpdate']}
for label, fields in (('comment, foreign head pending', {'pending_intent': PI('comment'), 'pending_changes': ['foreign_head_change']}),
                      ('push, foreign head pending', {'pending_intent': PI('push'), 'pending_changes': ['foreign_head_change']}),
                      ('assign_label, foreign head pending', {'pending_intent': PI('assign_label'), 'pending_changes': ['foreign_head_change']}),
                      ('comment, no foreign head', {'pending_intent': PI('comment'), 'pending_changes': ['issue_changed']}),
                      ('no intent, foreign head pending', {'pending_intent': None, 'pending_changes': ['foreign_head_change']})):
    print('pending_intent_stale %s: %s' % (label, val('pending_intent_stale', job('waiting_operator', **fields))))
callable_read = [f for f in B1B if f not in COMPUTED4]
print('callable facts=%d' % len(callable_read))
res = {}
for f in callable_read:
    out = (val(f, job('intake')),
           val(f, job('intake'), T.Context(built={f: lambda: True})),
           val(f, job('intake'), T.Context(built={f: lambda: False})),
           val(f, job('intake'), T.Context(built={f: lambda: 'yes'})))
    res.setdefault(out, []).append(f)
for out, fs in sorted(res.items()):
    print('callable %s: %d' % ('/'.join(out), len(fs)))
reads = T.facts_read(TAB, 'intake', 'github_change')
built = dict((f, (lambda: False)) for f in reads if f not in COMPUTED4 and f not in ('build_started',))
built['untrusted_edit'] = lambda: True
T.set_seam(None)
ctx = T.Context(built=built, setting=lambda k, d: d, confirm_writes=lambda writes: [])
print('R100 untrusted_edit true: ' + show(T.choose(TAB, job('intake'), 'github_change', ctx)))
del built['untrusted_edit']
try:
    print('R100 no untrusted_edit callable: ' + show(T.choose(TAB, job('intake'), 'github_change',
                                                              T.Context(built=built, confirm_writes=lambda w: []))))
except T.FactUnavailable:
    print('R100 no untrusted_edit callable: FactUnavailable')
PY
tb_py "$TB_CODE"
e2e_expect_line "1b providers=built/1b"
e2e_expect_line "1b unbuilt left=0"
e2e_expect_line "issue_changed pending, digests differ: False"
e2e_expect_line "issue_changed no baseline: False"
e2e_expect_line "issue_changed no baseline, pending false: False"
e2e_expect_line "issue_changed not pending, digests differ: True"
e2e_expect_line "issue_changed not pending, digests equal: False"
e2e_expect_line "issue_changed no issue digest: False"
e2e_expect_line "intake_rounds_exhausted round=None default: False"
e2e_expect_line "intake_rounds_exhausted round=2 default: False"
e2e_expect_line "intake_rounds_exhausted round=3 default: True"
e2e_expect_line "intake_rounds_exhausted round=4 default: True"
e2e_expect_line "intake_rounds_exhausted round=3 maxRounds 4: False"
e2e_expect_line "intake_rounds_exhausted round=4 maxRounds 4: True"
# A setting that is not a whole number of at least 1 counts as the plugin
# default, 3 (settings.json flow.factory.intake.maxRounds; Inferred).
for TB_V in "'4'" 0 True None; do
  e2e_expect_line "intake_rounds_exhausted round=3 maxRounds $TB_V: True"
done
e2e_expect_line "park_tier_confirm waiting_operator tier_confirm: True"
e2e_expect_line "park_tier_confirm waiting_operator None: False"
e2e_expect_line "park_tier_confirm needs_human tier_confirm: False"
e2e_expect_line "pending_intent_stale comment, foreign head pending: True"
e2e_expect_line "pending_intent_stale push, foreign head pending: True"
e2e_expect_line "pending_intent_stale assign_label, foreign head pending: False"
e2e_expect_line "pending_intent_stale comment, no foreign head: False"
e2e_expect_line "pending_intent_stale no intent, foreign head pending: False"
e2e_expect_line "callable facts=12"
e2e_expect_line "callable FactUnavailable/True/False/FactUnavailable: 12"
e2e_expect_line "R100 untrusted_edit true: Winner row=51b to=needs_human stay=False"
e2e_expect_line "R100 no untrusted_edit callable: FactUnavailable"

_flow_test_begin "factory table: a seam naming a 1b fact or confirm_keys is refused (TB15, R12, R29)"
fe_new tb15-seam-refusals
e2e_repo main
e2e_describe "set_seam with each of the 16 facts that phase 1b builds in unbuilt raises SeamRefused provider=built (R12; plan 1.3); derived_inputs with confirm_keys, empty or not, raises SEAM_REFUSED=blocking_write_confirm provider=derived (R29; plan B13 step 3); prepush_fails alone is still accepted (1e)"
read -r -d '' TB_CODE <<'PY' || true
B1B = ('issue_changed', 'untrusted_edit', 'needs_info_answer', 'untrusted_needs_info_answer', 'intake_rounds_exhausted',
       'cancel_signal', 'untrusted_close', 'via_comment', 'retry_by_triage_only', 'tier_confirm_blocking',
       'park_tier_confirm', 'intent_effect_observed', 'intent_key_not_confirm', 'pending_intent_stale',
       'dependency_open', 'creation_allowed')
lines = set()
for f in B1B:
    try:
        T.set_seam({'unbuilt': {'*': {f: True}}})
        lines.add('accepted')
    except T.SeamRefused as e:
        lines.add(e.line.replace(f, '<fact>'))
print('1b facts: ' + ','.join(sorted(lines)))
try:
    T.set_seam({'unbuilt': {'*': {'untrusted_edit': True}}})
except T.SeamRefused as e:
    print(e.line)
for derived in ({'confirm_keys': []}, {'confirm_keys': ['push'], 'prepush_fails': True}, {'prepush_fails': True}):
    try:
        T.set_seam({'derived_inputs': derived})
        print('accepted ' + json.dumps(derived, sort_keys=True))
    except T.SeamRefused as e:
        print(json.dumps(derived, sort_keys=True) + ' ' + e.line)
PY
tb_py "$TB_CODE"
e2e_expect_line "1b facts: SEAM_REFUSED=<fact> provider=built"
e2e_expect_line "SEAM_REFUSED=untrusted_edit provider=built"
e2e_expect_line '{"confirm_keys": []} SEAM_REFUSED=blocking_write_confirm provider=derived'
e2e_expect_line '{"confirm_keys": ["push"], "prepush_fails": true} SEAM_REFUSED=blocking_write_confirm provider=derived'
e2e_expect_line 'accepted {"prepush_fails": true}'

_flow_test_begin "factory table: blocking_write_confirm comes from ctx.confirm_writes, with or without a seam (TB16, AC8)"
fe_new tb16-confirm-writes
e2e_repo main
e2e_describe "prepare, stage_succeeded: row 11 (writes assignment and in-progress label, T:11) asks confirm_writes with those writes; a callable returning issueAssign gives row 40 (T:40, guard blocking_write_confirm true), one returning none gives row 11, the same with no seam and under a seam with no derived inputs; a callable that is missing or returns something other than a list is a caller defect (FactUnavailable)"
read -r -d '' TB_CODE <<'PY' || true
for seam in (None, {'unbuilt': {}}):
    tag = 'no seam' if seam is None else 'seam'
    for name, ret in (('issueAssign', ['issueAssign']), ('none', []), ('string', 'issueAssign'), ('None', None),
                      ('absent', 'ABSENT')):
        T.set_seam(seam)
        asked = []
        def cw(writes, ret=ret):
            asked.append(list(writes))
            return ret
        ctx = T.Context(built={}, confirm_writes=None if ret == 'ABSENT' else cw)
        try:
            out = show(T.choose(TAB, job('prepare'), 'stage_succeeded', ctx))
        except T.FactUnavailable:
            out = 'FactUnavailable'
        print('%s %s: %s asked=%s' % (tag, name, out, json.dumps(asked)))
PY
tb_py "$TB_CODE"
for TB_S in "no seam" "seam"; do
  e2e_expect_line "$TB_S issueAssign: Winner row=40 to=waiting_operator stay=False asked=[[\"assignment\", \"in-progress label\"]]"
  e2e_expect_line "$TB_S none: Winner row=11 to=spec stay=False asked=[[\"assignment\", \"in-progress label\"]]"
  e2e_expect_line "$TB_S string: FactUnavailable asked=[[\"assignment\", \"in-progress label\"]]"
  e2e_expect_line "$TB_S None: FactUnavailable asked=[[\"assignment\", \"in-progress label\"]]"
  e2e_expect_line "$TB_S absent: FactUnavailable asked=[]"
done

_flow_test_begin "factory table: the push rows keep the 1e push texts deferred and ask confirm_writes after the pre-push check (TB17)"
fe_new tb17-push-rows
e2e_repo main
e2e_describe "rows 21 (open_pr), 30 (rework) and 34 (resolve) on stage_succeeded under a seam that gives spec_change_needs_approval false and no prepush_fails, with confirm_writes returning none: each row wins, confirm_writes is asked with the row's writes (T:21, T:30, T:34), and apply lists push, the PR create or edit and the PR record in effects_deferred with phase 1e (plan B13 table, Q11); with no seam open_pr is Blocked on the pre-push input (1e) and confirm_writes is not asked"
read -r -d '' TB_CODE <<'PY' || true
TEXTS = ('push', 'create the draft PR (prCreate) or edit its body (issueUpdate)', 'record the PR number and head')
for row, state in (('21', 'open_pr'), ('30', 'rework'), ('34', 'resolve')):
    T.set_seam({'unbuilt': {'*': {'spec_change_needs_approval': False}}})
    asked = []
    ctx = T.Context(built={}, confirm_writes=lambda w: asked.append(list(w)) or [], now='2026-11-16T00:00:00Z')
    d = T.choose(TAB, job(state), 'stage_succeeded', ctx)
    new, line, run, deferred = T.apply(TAB, job(state), d, ctx)
    print('%s: %s asked=%s' % (row, show(d), json.dumps(asked)))
    print('%s deferred=%s' % (row, json.dumps([[x['effect'][:30], x['phase']] for x in line['effects_deferred'] if x['effect'] in TEXTS])))
T.set_seam(None)
asked = []
print('open_pr no seam: ' + show(T.choose(TAB, job('open_pr'), 'stage_succeeded',
                                          T.Context(built={}, confirm_writes=lambda w: asked.append(w) or []))) + ' asked=%d' % len(asked))
PY
tb_py "$TB_CODE"
e2e_expect_line '21: Winner row=21 to=gate stay=False asked=[["push", "PR create or edit"]]'
e2e_expect_line '21 deferred=[["push", "1e"], ["create the draft PR (prCreate)", "1e"], ["record the PR number and head", "1e"]]'
e2e_expect_line '30: Winner row=30 to=gate stay=False asked=[["push", "resolution marker", "replies"]]'
e2e_expect_line '30 deferred=[["push", "1e"]]'
e2e_expect_line '34: Winner row=34 to=gate stay=False asked=[["push"]]'
e2e_expect_line '34 deferred=[["push", "1e"]]'
e2e_expect_line "open_pr no seam: Blocked fact=prepush_protected_failed phase=1e missing=False asked=0"

_flow_test_begin "factory table: the 1b job handlers set their fields from ctx.sync and write them into the line's fields (TB18, R94, R36)"
fe_new tb18-job-handlers
e2e_repo main
e2e_describe "apply with a given ctx.sync: row 8r (re-vouch, T:8r) sets vouch_at to the decision's time and adds the sync's revouch replies to revouched_replies, and sets baseline_pending; row 40b records the sync's pending_keys (T:40b); row 51w drops the pending intent, held_result and pending_keys (T:51w); row 41b clears pending_keys and sets baseline_pending only when the target is intake (T:41b); row 50 drops the pending intent only from waiting_operator (T:50); row 66i clears baseline_pending and hands issue_md to the caller (T:66i). Each value is also in the transition line's fields (plan 2.2). With ctx.sync None (rebuild) each handler changes nothing, and a missing or malformed sync input is a caller defect"
read -r -d '' TB_CODE <<'PY' || true
NOW = '2026-11-16T00:00:00Z'
A, C = 'a' * 64, 'c' * 64
def go(row, state, event, fields, sync, confirm=None):
    a = witness(checker(state), row, state, event)
    ctx = inputs(a, sync=sync, confirm=confirm)
    j = job(state, **fields)
    d = T.choose(TAB, j, event, ctx)
    assert type(d).__name__ == 'Winner' and d.row == row, show(d)
    return j, T.apply(TAB, j, d, ctx)
def fld(line):
    return json.dumps(line['fields'], sort_keys=True)
def caught(fn):
    try:
        fn()
        return 'no error'
    except T.FactUnavailable:
        return 'FactUnavailable'
j8r = {'vouch_at': '2026-11-01T00:00:00Z', 'revouched_replies': {'99': C}, 'intake_round': 1}
j, (new, line, run, _) = go('8r', 'needs_info', 'person_retry', j8r, {'revouch': {101: A}})
print('8r: vouch_at=%s intake_round=%s baseline_pending=%s replies=%s' % (
    new['vouch_at'], new['intake_round'], new.get('baseline_pending'), json.dumps(new['revouched_replies'], sort_keys=True)))
print('8r fields=' + fld(line))
print('8r input job unchanged=%s' % (j == job('needs_info', **j8r)))
j, (new, line, run, _) = go('8r', 'needs_info', 'person_retry', j8r, None)
print('8r no sync: vouch_at=%s replies=%s fields=%s' % (new['vouch_at'], json.dumps(new['revouched_replies']), fld(line)))
for label, sync in (('no revouch key', {}), ('bad id', {'revouch': {'abc': A}}), ('bad hash', {'revouch': {'101': 'xyz'}})):
    print('8r %s: %s' % (label, caught(lambda sync=sync: go('8r', 'needs_info', 'person_retry', j8r, sync))))
j, (new, line, run, _) = go('8r', 'needs_info', 'person_retry', j8r, {'revouch': {}})
a = witness(checker('needs_info'), '8r', 'needs_info', 'person_retry')
ctx = inputs(a, sync={'revouch': {}})
ctx.now = None
d = T.choose(TAB, job('needs_info', **j8r), 'person_retry', ctx)
new, line = T.apply(TAB, job('needs_info', **j8r), d, ctx)[:2]
print('8r now None: vouch_at equals line time=%s' % (new['vouch_at'] == line['time'] and new['vouch_at'] != j8r['vouch_at']))
j, (new, line, run, _) = go('40b', 'intake', 'launch_due', {}, {'pending_keys': ['issueAssign']})
print('40b: reason=%s pending_keys=%s fields=%s' % (new['reason'], json.dumps(new['pending_keys']), fld(line)))
for label, sync in (('None keys', {'pending_keys': None}), ('no key', {}), ('empty', {'pending_keys': []}),
                    ('unknown key', {'pending_keys': ['bogus']})):
    print('40b %s: %s' % (label, caught(lambda sync=sync: go('40b', 'intake', 'launch_due', {}, sync))))
held = {'event': 'stage_succeeded', 'args': {}, 'channel': 'launcher', 'caller': None, 'facts': {}}
pi = {'id': 'issue-7-j1-40-3', 'kind': 'assign_label', 'key': ['issueAssign', 'issueUpdate']}
j, (new, line, run, _) = go('51w', 'waiting_operator', 'github_change',
                            {'pending_intent': pi, 'held_result': held, 'pending_keys': ['issueAssign'],
                             'resume_state': 'prepare', 'build_started': True}, {})
print('51w: reason=%s pending_intent=%s held_result=%s pending_keys=%s fields=%s' % (
    new['reason'], new['pending_intent'], new['held_result'], new['pending_keys'], fld(line)))
for rs in ('intake', 'build'):
    j, (new, line, run, _) = go('41b', 'waiting_operator', 'sync_tick',
                                {'reason': 'tier_confirm', 'resume_state': rs, 'pending_keys': ['issueAssign']}, {})
    print('41b %s: state=%s pending_keys=%s baseline_pending=%s fields=%s' % (
        rs, new['state'], new['pending_keys'], new.get('baseline_pending'), fld(line)))
for state in ('intake', 'waiting_operator'):
    j, (new, line, run, _) = go('50', state, 'github_change', {'pending_intent': pi, 'resume_state': 'prepare'}, {})
    print('50 from %s: pending_intent=%s baseline_pending=%s fields=%s' % (
        state, 'kept' if new.get('pending_intent') == pi else new.get('pending_intent'), new.get('baseline_pending'), fld(line)))
j, (new, line, run, _) = go('66i', 'intake', 'launch_due', {'baseline_pending': True}, {})
print('66i: baseline_pending=%s run=%s fields=%s' % (new['baseline_pending'], ','.join(h for h, e in run), fld(line)))
class R(object):
    def __init__(self, row):
        self.row = row
names = ('intent_clear', 'baseline', 'revouch', 'pending_keys')
texts = [(e, c[1]) for e, c in T.EFFECTS.items() if c[0] == 'handled' and c[1] in names]
before = job('waiting_operator', reason='tier_confirm', resume_state='intake', pending_intent=pi, held_result=held,
             pending_keys=['issueAssign'], baseline_pending=False, vouch_at='2026-11-01T00:00:00Z',
             revouched_replies={'99': C})
same = 0
for e, name in texts:
    j = copy.deepcopy(before)
    T._run_job_handler(name, e, j, copy.deepcopy(before), R('41b'), T.Context(setting=lambda k, d: d))
    same += j == before
print('rebuild-shaped calls: %d texts, %d unchanged' % (len(texts), same))
PY
tb_py "$TB_CODE"
e2e_expect_line "8r: vouch_at=2026-11-16T00:00:00Z intake_round=2 baseline_pending=True replies={\"101\": \"$(printf 'a%.0s' {1..64})\", \"99\": \"$(printf 'c%.0s' {1..64})\"}"
e2e_expect_line "8r fields={\"baseline_pending\": true, \"revouched_replies\": {\"101\": \"$(printf 'a%.0s' {1..64})\", \"99\": \"$(printf 'c%.0s' {1..64})\"}, \"vouch_at\": \"2026-11-16T00:00:00Z\"}"
e2e_expect_line "8r input job unchanged=True"
e2e_expect_line "8r no sync: vouch_at=2026-11-01T00:00:00Z replies={\"99\": \"$(printf 'c%.0s' {1..64})\"} fields={}"
e2e_expect_line "8r no revouch key: FactUnavailable"
e2e_expect_line "8r bad id: FactUnavailable"
e2e_expect_line "8r bad hash: FactUnavailable"
e2e_expect_line "8r now None: vouch_at equals line time=True"
e2e_expect_line '40b: reason=tier_confirm pending_keys=["issueAssign"] fields={"pending_keys": ["issueAssign"]}'
e2e_expect_line "40b None keys: FactUnavailable"
e2e_expect_line "40b no key: FactUnavailable"
e2e_expect_line "40b empty: FactUnavailable"
e2e_expect_line "40b unknown key: FactUnavailable"
e2e_expect_line '51w: reason=issue_changed pending_intent=None held_result=None pending_keys=None fields={"held_result": null, "pending_intent": null, "pending_keys": null}'
e2e_expect_line '41b intake: state=intake pending_keys=None baseline_pending=True fields={"baseline_pending": true, "held_result": null, "pending_intent": null, "pending_keys": null}'
e2e_expect_line '41b build: state=build pending_keys=None baseline_pending=None fields={"held_result": null, "pending_intent": null, "pending_keys": null}'
e2e_expect_line '50 from intake: pending_intent=kept baseline_pending=True fields={"baseline_pending": true}'
e2e_expect_line '50 from waiting_operator: pending_intent=None baseline_pending=True fields={"baseline_pending": true, "held_result": null, "pending_intent": null, "pending_keys": null}'
e2e_expect_line '66i: baseline_pending=False run=issue_md,issue_md,launch fields={"baseline_pending": false}'
e2e_expect_line "rebuild-shaped calls: 11 texts, 11 unchanged"

_flow_test_begin "factory table: every text of phase 1b is disposed of as plan B13's table says (TB19)"
fe_new tb19-effect-disposition
e2e_repo main
e2e_describe "the 41 texts of the old ('deferred', '1b') group: 38 handled by the named handler and 3 moved to phase 1e (plan B13 table, Q11); the four job handlers are in JOB_HANDLERS and the nine caller handlers in CALLER_HANDLERS; no ('deferred', '1b') group is left in the module source (a grep, no jq)"
read -r -d '' TB_CODE <<'PY' || true
WANT = {
    'pr_close': ['close a factory PR through the outbox', 'close any PR through the outbox'],
    'intent_clear': ['drop the pending intent', 'from waiting_operator: drop the pending intent and clear pending_keys',
                     'drop the pending intent: it was written for the head before the push', 'clear pending_keys'],
    'baseline': ['set baseline_pending', 'when the target is intake: set baseline_pending', 'clear baseline_pending'],
    'answer': ['record the answer comment ids in events.jsonl; they are already in the spec-input set',
               "record the answer in the job's answers file, which is in the spec-input set", 'record the answer'],
    'notice': ['post a notice that a trusted /flow-factory retry is needed before the reply counts', 'post the intake notice',
               'post the reject notice', 'post the needs-info notice with the factory marker and question ids NI-<k>'],
    'revouch': ['re-vouch: untrusted needs-info answers now count', 're-vouch', 're-vouch: vouch_at = now'],
    'refuse_note': ['refuse: a retry from triage access only re-vouches a needs-info reply from someone without write access, and none waits; this park needs a needs-info answer or a retry from write access or higher',
                    'refuse: a retry from triage access only re-vouches text from someone without write access; this park needs a retry from write access or higher',
                    'refuse: a tier_confirm park has no intent; change the key or start an interactive executor that can confirm',
                    'refuse to resume: the issue is closed; reopen it and retry, or cancel',
                    'refuse: the issue is closed; reopen it and retry, or cancel',
                    'refuse: the untrusted edit needs a trusted retry first', 'refuse: the issue change needs a retry first'],
    'pending_keys': ['record pending_keys'],
    'issue_md': ['write in/issue.md from the spec-input set',
                 'set baseline_digest = issue_digest (the only place baseline_digest is written)'],
    'intake_record': ['record intake_inputs (its only writer), risk, surfaces and scope'],
    'noop': ["the notice says that a reply counts when it names a question id, and that '/flow-factory spec' adds spec input"],
    'hold_intent': ['record pending_intent and the held stage result'],
    'write': ['assignment and label written', 'run exactly the stored literal with the real binary', 'record the effect',
              'record the observed effect', 'the engine runs the write'],
    'replay': ['replay the held stage result or event'],
}
MOVED = ['push', 'create the draft PR (prCreate) or edit its body (issueUpdate)', 'record the PR number and head']
n = sum(len(v) for v in WANT.values())
ok = sum(T.EFFECTS.get(t) == ('handled', h) for h, ts in WANT.items() for t in ts)
print('handled as planned: %d of %d' % (ok, n))
print('moved to 1e: %d of %d' % (sum(T.EFFECTS.get(t) == ('deferred', '1e') for t in MOVED), len(MOVED)))
print('job handlers: %s' % all(h in T.JOB_HANDLERS for h in ('intent_clear', 'baseline', 'revouch', 'pending_keys')))
print('caller handlers: %s' % all(h in T.CALLER_HANDLERS for h in ('pr_close', 'answer', 'notice', 'refuse_note', 'issue_md',
                                                                    'intake_record', 'hold_intent', 'write', 'replay')))
print('deferred 1b texts=%d' % sum(1 for v in T.EFFECTS.values() if v == ('deferred', '1b')))
PY
tb_py "$TB_CODE"
e2e_expect_line "handled as planned: 38 of 38"
e2e_expect_line "moved to 1e: 3 of 3"
e2e_expect_line "job handlers: True"
e2e_expect_line "caller handlers: True"
e2e_expect_line "deferred 1b texts=0"
TB_SRC="$E2E_PLUGIN_DIR/bin/_flow_factory_table.py"
e2e_expect_equal "0" "$(grep -c "('deferred', '1b')" "$TB_SRC")" "no ('deferred', '1b') group left in the module source"

_flow_test_begin "factory table: every handler that reads the issue sync sits in a pair that reads an issue fact (TB20, R88)"
fe_new tb20-sync-handlers
e2e_repo main
e2e_describe "for every row with a revouch effect, row 8u's notice and row 8's answer (plan 3.1 Handlers that read the sync), each from-state's (state, event) pair reads at least one of the six issue facts of plan 3.1, so such a handler runs only in a pass whose sync completed for the job"
read -r -d '' TB_CODE <<'PY' || true
ISSUE = {'untrusted_edit', 'needs_info_answer', 'untrusted_needs_info_answer', 'cancel_signal', 'untrusted_close',
         'dependency_open'}
rows = []
for r in DATA['rows']:
    hs = set(T.EFFECTS[e][1] for e in r['effects'] if T.EFFECTS[e][0] == 'handled')
    if 'revouch' in hs or (r['id'] == '8u' and 'notice' in hs) or (r['id'] == '8' and 'answer' in hs):
        rows.append(r)
print('rows=' + ','.join(sorted(r['id'] for r in rows)))
bad = ['%s/%s' % (r['id'], s) for r in rows for s in r['from'] if not (T.facts_read(TAB, s, r['event']) & ISSUE)]
print('pairs without an issue fact=' + (','.join(bad) or 'none'))
PY
tb_py "$TB_CODE"
e2e_expect_line "rows=44c,44d,44r,47,8,8r,8u,9r"
e2e_expect_line "pairs without an issue fact=none"

_flow_test_begin "factory table: next's JobPass.ctx gives every 1b fact an input in every decision (TB14, R100, R103)"
fe_new tb21-jobpass-ctx
e2e_repo main
fe_record
fe_enable
fe_world_new flow-e2e-engine flow-e2e/scratch
fe_world_knob list_fails '["user"]'
e2e_describe "R100's next half and R103's table half: a JobPass of a job parked by row 40b (waiting_operator, reason tier_confirm, resume_state intake, no pending_intent), in a pass with no issue-sync entry for the job and gh api user failing. Each of the six issue facts raises next's FactFailed (plan 3.1, a pass with no sync entry); via_comment and retry_by_triage_only are false with no pending record (plan 2.2); tier_confirm_blocking is a bool; intent_effect_observed and intent_key_not_confirm are false with no login read and no lookup (plan 3.1, T:fact_dependencies); the four table-computed facts give a bool with no callable (plan 5.3); confirm_writes is a callable and ctx.sync a dict (plan 5.3 Context); no fact raises FactUnavailable"
read -r -d '' TB_CODE <<'PY' || true
import time
import _flow_factory_next as N
import _flow_factory_jobs as jobs
p = N.Pass(jobs.resolve(), 'headless', time.time())
p.pass_id, p.holds, p.open_jobs = 'p1', 0, 0
j = job('waiting_operator', reason='tier_confirm', resume_state='intake', pending_intent=None, base='main',
        vouch_at='2026-11-16T00:00:00Z')
jp = N.JobPass(p, 7, j)
ctx = jp.ctx('engine', None)
moved = [f for f, pr in sorted(T.PROVIDERS.items()) if pr.phase == '1b' and pr.kind == 'built']
print('moved=%d' % len(moved))
for f in moved:
    if f == T.CREATION_FACT:
        continue
    try:
        v = T.PROVIDERS[f].compute(ctx, j)
        print('%s=%s' % (f, type(v).__name__ if f == 'tier_confirm_blocking' else v))
    except N.FactFailed:
        print('%s=FactFailed' % f)
    except T.FactUnavailable as e:
        print('%s=FactUnavailable %s' % (f, e))
print('confirm_writes callable=%s' % callable(ctx.confirm_writes))
print('sync=%s' % type(ctx.sync).__name__)
import shutil
calls = os.path.join(os.path.dirname(shutil.which('gh')), 'fe-gh-calls.log')
print('api user calls=%d' % sum(1 for x in (open(calls).read().splitlines() if os.path.exists(calls) else [])
                                if x == 'api user'))
PY
tb_py "$TB_CODE"
e2e_expect_line "moved=16"
for TB_F in cancel_signal dependency_open needs_info_answer untrusted_close untrusted_edit untrusted_needs_info_answer; do
  e2e_expect_line "$TB_F=FactFailed"
done
e2e_expect_line "via_comment=False"
e2e_expect_line "retry_by_triage_only=False"
e2e_expect_line "tier_confirm_blocking=bool"
e2e_expect_line "intent_effect_observed=False"
e2e_expect_line "intent_key_not_confirm=False"
e2e_expect_line "issue_changed=False"
e2e_expect_line "intake_rounds_exhausted=False"
e2e_expect_line "park_tier_confirm=True"
e2e_expect_line "pending_intent_stale=False"
e2e_expect_line "confirm_writes callable=True"
e2e_expect_line "sync=dict"
e2e_expect_line "api user calls=0"
e2e_expect_no_out "FactUnavailable"
e2e_expect_err_lacks "Traceback"

_flow_test_begin "factory table: a seam body for the intake judge is refused; the approve judge's body stays (TB15, R93)"
fe_new tb22-judge-body
e2e_repo main
e2e_describe "plan B14 step 11: set_seam refuses bodies[\"judge:intake\"] with SEAM_REFUSED=bodies:judge:intake provider=built, because 1b launches the intake judge for real; a judge:approve body (phase 2) is still accepted"
read -r -d '' TB_CODE <<'PY' || true
for bodies in ({'judge:intake': 'judge_accept'}, {'judge:approve': 'judge_approve'}):
    try:
        T.set_seam({'bodies': bodies})
        print('accepted ' + ','.join(bodies))
    except T.SeamRefused as e:
        print(e.line)
PY
tb_py "$TB_CODE"
e2e_expect_line "SEAM_REFUSED=bodies:judge:intake provider=built"
e2e_expect_line "accepted judge:approve"
