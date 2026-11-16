# shellcheck shell=bash
# The factory's test entry point, tests/fixtures/factory/engine_under_test.py
# (E): it registers a seam of fixture inputs and runs the engine's own main
# with them. Nothing the plugin ships may reach it (plan 2.11, journal "Does
# not add": no path from flow-factory.sh to the test entry point or to a
# fixture fact provider).
#
# Ways it can be wrong, written down before the checks:
#   E1  something under bin/, hooks/ or commands/ names the entry point, a
#       fixture path or a fixture variable, or calls set_seam, so a real run
#       could reach the seam (R22, A+3); or the check that looks for this
#       passes on a tree that does name one
#   E2  a fixture names a built or derived fact, or a fact no provider has,
#       and silently overrides it (or is silently ignored) instead of being
#       refused before main runs
#   E3  an unknown top-level key is ignored; a fixture that is missing, not
#       JSON, not an object, or of the wrong shape, or a call with no
#       subcommand or no engine under --plugin, runs main anyway or exits
#       with a traceback
#   E4  E runs a copy of main, or the engine from some other plugin folder,
#       or loads _flow_factory twice (so main's `except Refused` misses a
#       sibling module's Refused), or registers the seam in a module the
#       engine does not read
#   E5  a pair that reads an unbuilt fact the fixture gives no value for is
#       Blocked silently, without the SEAM_MISSING line on stderr; or the
#       line is printed when the fixture does give a value
#   E6  the seam is visible to the engine run without E (the direct form)
#
# The real `next` pass (bin/_flow_factory_next.py) is T11's. Until it exists
# the scenarios that need `next` run a stand-in next module on a plugin copy,
# which calls the real choose() from the real dispatch; T11 and T13 drive the
# real `next` through E.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# se_grep <root> <plugin dir relative to root> — the E1 grep, run from root
# over the plugin's bin, hooks and commands, one line per match, sorted so
# the artifact does not depend on directory order. Prints nothing when
# nothing matches.
se_grep() {
  ( cd "$1" && grep -rnE 'engine_under_test|set_seam\(|tests/fixtures|FLOW_FACTORY_(FIXTURE|SEAM)' \
      "$2/bin" "$2/hooks" "$2/commands" | LC_ALL=C sort ) || true
}

# se_verdict <grep output> <plugin dir relative to root> — "ok" when the grep
# found exactly the one allowed line, the def set_seam( line of the table
# module; otherwise "fail <n> lines".
se_verdict() {
  local n=0
  [ -n "$1" ] && n=$(printf '%s\n' "$1" | wc -l | tr -d ' ')
  if [ "$n" = 1 ] && printf '%s\n' "$1" | grep -qE "^$2/bin/_flow_factory_table\.py:[0-9]+:def set_seam\("; then
    printf 'ok\n'
  else
    printf 'fail %s lines\n' "$n"
  fi
}

# se_control <tag> <file under the plugin> <line to append> — a copy of the
# plugin with one line appended to one file; prints the grep's verdict on it
# and writes the grep output to the artifact.
se_control() {
  local dst="$E2E_DIR/control-$1" out
  e2e_copy_plugin "$E2E_PLUGIN_DIR" "$dst" || { _flow_assert_fail "$E2E_NAME: cannot copy the plugin"; return 1; }
  printf '%s\n' "$3" >> "$dst/$2"
  out=$(se_grep "$E2E_DIR" "control-$1")
  printf -- '--- control %s: %s gets the line: %s\n%s\n' "$1" "$2" "$3" "$out" | _e2e_art
  SE_VERDICT=$(se_verdict "$out" "control-$1")
}

# se_fixture <name> <json> — a fixture file under the scenario folder; prints
# its path.
se_fixture() {
  printf '%s\n' "$2" > "$E2E_DIR/$1.json"
  printf 'fixture %s.json: %s\n' "$1" "$2" | _e2e_art
  printf '%s' "$E2E_DIR/$1.json"
}

# The stand-in next module (on a plugin copy) for E4 to E6. It shows which
# seam the engine module sees, which _flow_factory file and entry script run,
# the real choose() for a queued job on sync_tick (it reads dependency_open,
# unbuilt, and slot_free, built), and the real choose_creation(); with
# argument `refuse` it raises _flow_factory.Refused, which only the one
# loaded copy of _flow_factory that main catches turns into exit 5.
SE_NEXT='import json, os, sys
import _flow_factory
import _flow_factory_table as T
def show(d):
    n = type(d).__name__
    if n == "Winner":
        return "Winner row=%s to=%s" % (d.row, d.to)
    if n == "Blocked":
        return "Blocked fact=%s phase=%s missing=%s" % (d.fact, d.phase, d.missing)
    if n == "NoMove":
        return "NoMove"
    return n + " " + str(getattr(d, "line", ""))
def cmd_next(a):
    if a[:1] == ["refuse"]:
        raise _flow_factory.Refused("from_next_module")
    print("seam=" + json.dumps(T.current_seam(), sort_keys=True))
    print("flow_factory=" + os.path.realpath(sys.modules["_flow_factory"].__file__))
    print("entry=" + os.path.basename(sys.modules["__main__"].__file__))
    t = T.load_table()
    job = {"key": "issue-7-j1", "issue": 7, "state": "queued", "attempt": 0, "holds_slot": False}
    print("decision=" + show(T.choose(t, job, "sync_tick", T.Context(built={"slot_free": lambda: True}))))
    print("creation=" + show(T.choose_creation(t, "issue-7-j1", T.Context())))
    return 0'

# se_next_copy — a plugin copy whose bin/_flow_factory_next.py is SE_NEXT,
# with the factory enabled, so `next` passes the gate and reaches it.
se_next_copy() {
  e2e_plugin_copy bin/_flow_factory_next.py "$SE_NEXT"
  fe_enable
  fe_record
}

_flow_test_begin "factory seam: nothing the plugin ships names the entry point, a fixture path or variable, or calls set_seam (E1, R22, A+3)"
fe_new se-reach
# Source of the expected value: journal "Does not add" (no path from flow-factory.sh to the entry point); plan 2.11 "Names that stay out of bin/".
e2e_describe "the grep over the shipped bin, hooks and commands finds only the def set_seam( line; each planted control (a fixture variable, a comment naming the entry point or a fixture path, a second set_seam call, the def renamed) makes the same check fail"
SE_OUT=$(se_grep "$REPO_ROOT" plugins/flow)
printf -- '--- grep over the shipped plugin\n%s\n' "$SE_OUT" | _e2e_art
e2e_expect_equal "ok" "$(se_verdict "$SE_OUT" plugins/flow)" "verdict on the shipped plugin"
e2e_expect_equal "1" "$(printf '%s\n' "$SE_OUT" | grep -c .)" "lines the shipped grep prints"
se_control env bin/_flow_factory_table.py '_x = os.environ.get("FLOW_FACTORY_SEAM")'
e2e_expect_equal "fail 2 lines" "$SE_VERDICT" "verdict with a FLOW_FACTORY_SEAM read in the table module"
se_control fixture-var bin/_flow_factory_jobs.py '_y = os.environ.get("FLOW_FACTORY_FIXTURES")'
e2e_expect_equal "fail 2 lines" "$SE_VERDICT" "verdict with a FLOW_FACTORY_FIXTURES read in the jobs module"
se_control comment-entry bin/_flow_factory_table.py '# see tests/fixtures/factory/engine_under_test.py'
e2e_expect_equal "fail 2 lines" "$SE_VERDICT" "verdict with a comment naming the entry point"
se_control comment-hook hooks/hooks.json '"tests/fixtures"'
e2e_expect_equal "fail 2 lines" "$SE_VERDICT" "verdict with a fixture path in hooks"
se_control command commands/status.md 'engine_under_test'
e2e_expect_equal "fail 2 lines" "$SE_VERDICT" "verdict with the entry point named in a command file"
se_control call bin/_flow_factory_jobs.py '_flow_factory_table.set_seam({})'
e2e_expect_equal "fail 2 lines" "$SE_VERDICT" "verdict with a set_seam call in another bin module"
SE_DST="$E2E_DIR/control-renamed"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$SE_DST" || _flow_assert_fail "$E2E_NAME: cannot copy the plugin"
sed 's/^def set_seam(/def register_seam(/' "$REPO_ROOT/plugins/flow/bin/_flow_factory_table.py" > "$SE_DST/bin/_flow_factory_table.py"
SE_OUT=$(se_grep "$E2E_DIR" control-renamed)
printf -- '--- control renamed: def set_seam( renamed\n%s\n' "$SE_OUT" | _e2e_art
e2e_expect_equal "fail 0 lines" "$(se_verdict "$SE_OUT" control-renamed)" "verdict with no def set_seam( line"

_flow_test_begin "factory seam: a fixture naming a built, derived or unknown fact is refused before main runs (E2)"
fe_new se-provider
# Source of the expected values: plan 2.11 (tree_dirty is built in 1a; blocking_write_confirm is derived; built_inputs takes only group_gone and unvouched_session_action) and 2.6 (exit 2, SEAM_REFUSED=<fact> provider=<built|derived|unknown_key>).
e2e_describe "each fixture is run with the subcommand wait, whose not_built line only main prints; stdout is exactly the SEAM_REFUSED line and the exit status 2, so main never ran"
e2e_repo main
fe_e "$(se_fixture built '{"unbuilt":{"*":{"tree_dirty":false}}}')" wait
e2e_expect_equal "2 SEAM_REFUSED=tree_dirty provider=built" "$E2E_RC $E2E_OUT" "a built fact under unbuilt"
fe_e "$(se_fixture derived '{"unbuilt":{"issue-7-j1":{"blocking_write_confirm":true}}}')" wait
e2e_expect_equal "2 SEAM_REFUSED=blocking_write_confirm provider=derived" "$E2E_RC $E2E_OUT" "a derived fact under unbuilt"
fe_e "$(se_fixture unknown '{"unbuilt":{"*":{"no_such_fact":true}}}')" wait
e2e_expect_equal "2 SEAM_REFUSED=no_such_fact provider=unknown_key" "$E2E_RC $E2E_OUT" "an unknown fact under unbuilt"
fe_e "$(se_fixture built-input '{"built_inputs":{"tree_dirty":true}}')" wait
e2e_expect_equal "2 SEAM_REFUSED=tree_dirty provider=built" "$E2E_RC $E2E_OUT" "a built fact outside the two under built_inputs"
# Control: the two built inputs a seam may give are accepted, and main runs.
fe_e "$(se_fixture allowed '{"built_inputs":{"group_gone":true,"unvouched_session_action":false}}')" wait
e2e_expect_equal "5 FACTORY_REFUSED=not_built" "$E2E_RC $E2E_OUT" "group_gone and unvouched_session_action under built_inputs"

_flow_test_begin "factory seam: an unknown top-level key, and a malformed fixture, are refused with exit 2 (E3)"
fe_new se-keys
# Source of the expected values: plan 2.11 (the four input kinds plus default_unbuilt; any other key refused) and 2.6 (exit 2: one stderr line, nothing on stdout, for a usage error).
e2e_describe "an unknown key gives SEAM_REFUSED=<key> provider=unknown_key (the first in sorted order); a missing file, invalid JSON, a non-object and a wrongly shaped value each give exit 2, one stderr line and no stdout, and no traceback"
e2e_repo main
fe_e "$(se_fixture facts '{"facts":{}}')" wait
e2e_expect_equal "2 SEAM_REFUSED=facts provider=unknown_key" "$E2E_RC $E2E_OUT" "the key facts"
fe_e "$(se_fixture two '{"zeta":1,"unbuilt":{},"alpha":2}')" wait
e2e_expect_equal "2 SEAM_REFUSED=alpha provider=unknown_key" "$E2E_RC $E2E_OUT" "two unknown keys"
for SE_CASE in missing invalid-json array wrong-type; do
  case "$SE_CASE" in
    missing) SE_FILE="$E2E_DIR/no-such-fixture.json" ;;
    invalid-json) SE_FILE=$(se_fixture invalid-json '{"unbuilt":') ;;
    array) SE_FILE=$(se_fixture array '[]') ;;
    wrong-type) SE_FILE=$(se_fixture wrong-type '{"default_unbuilt":"yes"}') ;;
  esac
  fe_e "$SE_FILE" wait
  e2e_expect_equal "2|" "$E2E_RC|$E2E_OUT" "$SE_CASE: exit status and stdout"
  e2e_expect_equal "1" "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "$SE_CASE: stderr lines"
  e2e_expect_err "engine_under_test.py: "
  e2e_expect_err_lacks "Traceback"
done
# No subcommand, and a --plugin folder with no bin/_flow_factory.py.
fe_e "$E2E_DIR/two.json"
e2e_expect_equal "2|" "$E2E_RC|$E2E_OUT" "no subcommand: exit status and stdout"
e2e_expect_equal "engine_under_test.py: no subcommand" "$E2E_ERR" "no subcommand: the whole of stderr"
SE_PLUGIN="$E2E_ACTIVE_PLUGIN"
E2E_ACTIVE_PLUGIN="$E2E_DIR/no-plugin"
fe_e "$E2E_DIR/two.json" wait
E2E_ACTIVE_PLUGIN="$SE_PLUGIN"
e2e_expect_equal "2|" "$E2E_RC|$E2E_OUT" "no engine under --plugin: exit status and stdout"
e2e_expect_err "engine_under_test.py: no bin/_flow_factory.py under --plugin "

_flow_test_begin "factory seam: E runs the engine's own main from the --plugin folder, with one _flow_factory (E4)"
fe_new se-main
# Source of the expected values: plan 2.7 (wait prints FACTORY_REFUSED=not_built, exit 5; main turns Refused into FACTORY_REFUSED=<r>, exit 5; the module identity rule) and T3b step 1.
e2e_describe "an empty fixture with wait reaches main's not_built line; on a plugin copy whose next module raises _flow_factory.Refused, E prints FACTORY_REFUSED=from_next_module and exits 5 (a second copy of _flow_factory would escape main as a traceback); the next module sees the copy's _flow_factory and E as the entry script"
e2e_repo main
fe_e "$(se_fixture empty '{}')" wait
e2e_expect_equal "5 FACTORY_REFUSED=not_built" "$E2E_RC $E2E_OUT" "wait under an empty fixture"
se_next_copy
fe_e "$E2E_DIR/empty.json" next refuse
e2e_expect_equal "5 FACTORY_REFUSED=from_next_module" "$E2E_RC $E2E_OUT" "Refused raised in the next module"
e2e_expect_err_lacks "Traceback"
fe_e ordinary.json next --executor headless
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "flow_factory=$(cd "$E2E_ACTIVE_PLUGIN/bin" && pwd -P)/_flow_factory.py"
e2e_expect_line "entry=engine_under_test.py"

_flow_test_begin "factory seam: the fixture's values reach the real choose() through the real dispatch, and only under E (E4, E6)"
fe_new se-choose
# Source of the expected values: the shipped seam/ordinary.json for the seam line; the docs checker (check_transitions.Checker.top_rows over dependency_open false, slot_free true, both derived facts false) for the row; plan 2.11 (outside a seam a pair reading an unbuilt fact is Blocked; creation row 1 is fenced through creation_allowed, phase 1b; under default_unbuilt false creation_allowed is false).
e2e_describe "with ordinary.json the stand-in next module sees exactly that seam, and choose for a queued job on sync_tick returns the row the docs checker picks; the direct form, without E, sees no seam and is Blocked on dependency_open"
e2e_repo main
fe_py "import sys, json, copy
sys.dont_write_bytecode = True
sys.path.insert(0, '$REPO_ROOT/docs/flow-factory')
import check_transitions as ct
data = json.load(open('$E2E_PLUGIN_DIR/references/factory-transitions.json'))
c = ct.Checker(copy.deepcopy(data))
assert c.schema(), c.errors
c.nonterm = ['queued']
c.coverage()
rows, facts, deps = c.pair_info[('queued', 'sync_tick')]
a = dict((f, False) for f in facts)
a['slot_free'] = True
top = c.top_rows(rows, a)
assert len(top) == 1, top
print('Winner row=%s to=%s' % (top[0]['id'], top[0].get('to')))
print('seam=' + json.dumps(json.load(open('$FE_FIXTURES/seam/ordinary.json')), sort_keys=True))"
e2e_expect_equal "0" "$E2E_RC" "the checker's computation"
SE_WANT_ROW=$(printf '%s\n' "$E2E_OUT" | sed -n 1p)
SE_WANT_SEAM=$(printf '%s\n' "$E2E_OUT" | sed -n 2p)
e2e_expect_equal "1" "$(printf '%s\n' "$SE_WANT_ROW" | grep -c '^Winner row=')" "the checker gives one winner"
se_next_copy
fe_e ordinary.json next --executor headless
e2e_expect_equal "0" "$E2E_RC" "exit status under E"
e2e_expect_line "$SE_WANT_SEAM"
e2e_expect_line "decision=$SE_WANT_ROW"
e2e_expect_line "creation=NoMove"
e2e_expect_err_lacks "SEAM_MISSING"
fe_direct next --executor headless
e2e_expect_equal "0" "$E2E_RC" "exit status of the direct form"
e2e_expect_line "seam=null"
e2e_expect_line "entry=_flow_factory.py"
e2e_expect_line "decision=Blocked fact=dependency_open phase=1b missing=False"
e2e_expect_line "creation=Blocked fact=creation_allowed phase=1b missing=False"
e2e_expect_err_lacks "SEAM_MISSING"

_flow_test_begin "factory seam: an unbuilt fact the fixture gives no value for prints SEAM_MISSING to stderr (E5)"
fe_new se-missing
# Source of the expected values: plan 2.11 seam item 1 (without default_unbuilt an unnamed unbuilt fact the pair reads makes the pair Blocked under E too, and E writes SEAM_MISSING=<fact> state=<s> event=<e> to stderr); creation row 1's event is issue_labelled and it has no from state (transitions.json creation).
e2e_describe "an empty fixture: choose for queued on sync_tick is Blocked with missing true and stderr has the SEAM_MISSING line for dependency_open; choose_creation gives the line for creation_allowed with state=none; a fixture naming dependency_open for this job only gives no SEAM_MISSING line for that pair"
e2e_repo main
se_next_copy
fe_e "$(se_fixture empty '{}')" next --executor headless
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "seam={}"
e2e_expect_line "decision=Blocked fact=dependency_open phase=1b missing=True"
e2e_expect_line "creation=Blocked fact=creation_allowed phase=1b missing=True"
e2e_expect_equal "SEAM_MISSING=dependency_open state=queued event=sync_tick
SEAM_MISSING=creation_allowed state=none event=issue_labelled" "$E2E_ERR" "the whole of stderr"
fe_e "$(se_fixture job-only '{"unbuilt":{"issue-7-j1":{"dependency_open":false},"issue-8-j1":{"creation_allowed":true}}}')" next --executor headless
e2e_expect_equal "0" "$E2E_RC" "exit status with a per-job fixture"
e2e_expect_no_line "decision=Blocked fact=dependency_open phase=1b missing=True"
e2e_expect_line "creation=Blocked fact=creation_allowed phase=1b missing=True"
e2e_expect_equal "SEAM_MISSING=creation_allowed state=none event=issue_labelled" "$E2E_ERR" "stderr with dependency_open given for issue-7-j1 only"
