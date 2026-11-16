# shellcheck shell=bash
# The factory state table as the plugin ships it: the plugin copy, the table
# checker and its mutation test run on every interpreter the factory would
# use, and the CI path filters that make a change to the table reach this
# suite.
#
# The plugin reads the table from references/factory-transitions.json. The
# source of truth is docs/flow-factory/transitions.json, checked by
# docs/flow-factory/check_transitions.py; test_check_transitions.sh beside it
# breaks the table one rule at a time and expects that rule's message.
#
# Ways it can be wrong, written down before the checks:
#   X1 the plugin copy differs from the docs table
#   X2 the checker is never run on the plugin copy, or it passes the copy
#      without reporting the table the docs describe
#   X3 the mutation test runs under no interpreter and passes with nothing
#      checked
#   X4 the checker's --markdown, run on the plugin copy in place, writes
#      references/transitions.md into the plugin
#   X5 docs/flow-factory/transitions.md is not what the checker writes for the
#      table
#   X6 a change to the table, a schema, a setting or a template does not
#      trigger the flow suite in CI
#
# The interpreters are the one `bin/flow-factory.sh probe --resolve-python`
# chooses (its PYTHON= line, the interpreter a probe records), and every other
# python3.14 and python3 on PATH that runs Python 3.14 or later, each once by
# its real path. The checker refuses anything older than 3.14
# (check_transitions.py:84-85). With none found every scenario fails: a check
# that ran under no interpreter must not pass.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

TR_DOCS="$REPO_ROOT/docs/flow-factory"
TR_TABLE="$REPO_ROOT/plugins/flow/references/factory-transitions.json"
TR_REAL_HOME="$HOME"
# The Summary line check_transitions.py prints for the table (its main, at
# check_transitions.py:1452-1454), as plan.md "What this plan rests on"
# recorded it for transitions.json at 4738facc (2026-11-16).
TR_SUMMARY="Summary: 22 states (5 parked, 3 terminal), 23 events, 74 facts, 172 rows; 149 (state, event) pairs, 51112 fact assignments checked."

# _tr_scenario <name> <purpose> — a scenario with a scratch repository, so
# _e2e_exec runs the code below the scratch root.
_tr_scenario() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
}

# The interpreters, one real path per line.
_flow_test_begin "factory table: the interpreters the checks run under"
_tr_scenario tr-interpreters "the interpreter probe --resolve-python chooses, then every other python3.14 and python3 on PATH at 3.14 or later, by real path"
e2e_run_bin bin/flow-factory.sh probe --resolve-python
e2e_expect_equal "0" "$E2E_RC" "probe --resolve-python exit status"
TR_CHOSEN=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PYTHON=//p' | head -1)
TR_PYS=""
_tr_add_py() {
  local real
  real=$(cd "$E2E_DIR" && "$1" -I -c 'import os, sys
if sys.version_info >= (3, 14): print(os.path.realpath(sys.executable))' 2>/dev/null) || return 0
  [ -n "$real" ] || return 0
  case "$real" in *[[:space:]]*) _flow_assert_fail "interpreter path has a space, which PYTHONS cannot carry: $real"; return 0 ;; esac
  case "
$TR_PYS
" in *"
$real
"*) return 0 ;; esac
  TR_PYS="${TR_PYS:+$TR_PYS
}$real"
}
[ -n "$TR_CHOSEN" ] && _tr_add_py "$TR_CHOSEN"
TR_IFS="$IFS"; IFS=:
for _tr_d in $PATH; do
  IFS="$TR_IFS"
  for _tr_n in python3.14 python3; do
    [ -x "$_tr_d/$_tr_n" ] && [ ! -d "$_tr_d/$_tr_n" ] && _tr_add_py "$_tr_d/$_tr_n"
  done
  IFS=:
done
IFS="$TR_IFS"
TR_PYTHONS=$(printf '%s\n' "$TR_PYS" | tr '\n' ' ' | sed 's/ *$//')
TR_NPY=$(printf '%s\n' "$TR_PYS" | grep -c .)
printf 'chosen interpreter: %s\ninterpreters (PYTHONS): %s\n' "${TR_CHOSEN:-none}" "${TR_PYTHONS:-none}" | _e2e_art
if [ -n "$TR_CHOSEN" ] && [ "$TR_NPY" -ge 1 ]; then
  _e2e_result pass "an interpreter at Python 3.14 or later was found ($TR_NPY)"
else
  _e2e_result fail "an interpreter at Python 3.14 or later was found (probe chose '${TR_CHOSEN:-none}')"
fi
e2e_expect_clean_edges

_flow_test_begin "factory table: the plugin copy is the docs table byte for byte (X1)"
_tr_scenario tr-copy-equal "cmp of plugins/flow/references/factory-transitions.json and docs/flow-factory/transitions.json"
_e2e_exec cmp "$TR_DOCS/transitions.json" "$TR_TABLE"
e2e_expect_equal "0" "$E2E_RC" "cmp exit status"
e2e_expect_clean_edges

_flow_test_begin "factory table: the checker passes the plugin copy under every interpreter (X2)"
_tr_scenario tr-checker-plugin-copy "check_transitions.py on a scratch copy of the plugin table, under each interpreter, prints PASS and the table's Summary line"
mkdir -p "$E2E_DIR/copy"
cp "$TR_TABLE" "$E2E_DIR/copy/factory-transitions.json" 2>/dev/null
if [ -z "$TR_PYS" ]; then _e2e_result fail "an interpreter to run the checker under"; fi
while IFS= read -r _tr_py; do
  [ -n "$_tr_py" ] || continue
  printf 'interpreter: %s\n' "$_tr_py" | _e2e_art
  _e2e_exec "$_tr_py" -I "$TR_DOCS/check_transitions.py" "$E2E_DIR/copy/factory-transitions.json"
  e2e_expect_equal "0" "$E2E_RC" "checker exit status under $_tr_py"
  e2e_expect_equal "PASS" "$(printf '%s\n' "$E2E_OUT" | tail -1)" "last line under $_tr_py"
  e2e_expect_line "$TR_SUMMARY"
done <<EOF
$TR_PYS
EOF
e2e_expect_clean_edges

# The negative control breaks one rule the checker owns: row 21f (the pre-push
# check's freeze, precedence 44) moved to 99, below the rows that push, so a
# push wins while the check has failed. The mutation and its message are
# test_check_transitions.sh's freeze_row_below_push_rows. A move to 46, past
# row 40 only, breaks no checker rule: the checker passes that table, so the
# order of rows 21f and 40 is left to the engine's own tests.
_flow_test_begin "factory table: the checker fails a copy with row 21f below the push rows (X2 negative control)"
_tr_scenario tr-checker-negative "row 21f's precedence 44 raised to 99: the checker must fail with a [push_check] line"
mkdir -p "$E2E_DIR/copy"
TR_PY1=$(printf '%s\n' "$TR_PYS" | head -1)
if [ -z "$TR_PY1" ]; then
  _e2e_result fail "an interpreter to run the checker under"
else
  _e2e_exec "$TR_PY1" -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
rows = [r for r in d["rows"] if r["id"] == "21f"]
assert len(rows) == 1 and rows[0]["precedence"] == 44, rows
rows[0]["precedence"] = 99
json.dump(d, open(sys.argv[2], "w"), indent=2)
print("row 21f precedence 44 -> 99")
' "$TR_TABLE" "$E2E_DIR/copy/factory-transitions.json"
  e2e_expect_equal "0" "$E2E_RC" "the mutant was written"
  _e2e_exec "$TR_PY1" -I "$TR_DOCS/check_transitions.py" "$E2E_DIR/copy/factory-transitions.json"
  e2e_expect_equal "1" "$E2E_RC" "checker exit status on the mutant"
  e2e_expect_no_line "PASS"
  e2e_expect_equal "FAIL: " "$(printf '%s\n' "$E2E_OUT" | tail -1 | cut -c1-6)" "start of the last line"
  if printf '%s\n' "$E2E_OUT" | grep -qE "^ERROR \\[push_check\\] \\((open_pr|review|rework|resolve|sync), stage_succeeded\\): row '[0-9a-z]+' pushes, but when prepush_protected_failed is true row '[0-9a-z]+' wins"; then
    _e2e_result pass "an ERROR [push_check] line names a push row winning over the failed check"
  else
    _e2e_result fail "an ERROR [push_check] line names a push row winning over the failed check"
  fi
fi
e2e_expect_clean_edges

_flow_test_begin "factory table: the mutation test passes under every interpreter (X3)"
_tr_scenario tr-mutation-test "test_check_transitions.sh with PYTHONS naming every interpreter: exit 0, '<N> passed, 0 failed' with N at least 1, and the original table passing once per interpreter"
mkdir -p "$E2E_DIR/tmp"
# The script names its mktemp folder in one message; that name is replaced by
# a fixed one so two runs write the same artifact. pipefail keeps the
# script's own exit status.
_e2e_exec env PYTHONS="$TR_PYTHONS" TMPDIR="$E2E_DIR/tmp" bash -c \
  'set -o pipefail; bash "$1" | sed -E "s#/check-transitions\.[A-Za-z0-9]+/#/check-transitions.XXXXXX/#g"' \
  _ "$TR_DOCS/test_check_transitions.sh"
e2e_expect_equal "0" "$E2E_RC" "mutation test exit status"
TR_LAST=$(printf '%s\n' "$E2E_OUT" | tail -1)
TR_N=$(printf '%s\n' "$TR_LAST" | sed -n 's/^\([0-9][0-9]*\) passed, 0 failed$/\1/p')
if [ -n "$TR_N" ] && [ "$TR_N" -ge 1 ]; then
  _e2e_result pass "last line is '<N> passed, 0 failed' with N >= 1 (N=$TR_N)"
else
  _e2e_result fail "last line is '<N> passed, 0 failed' with N >= 1 (got '$TR_LAST')"
fi
TR_ORIG=$(printf '%s\n' "$E2E_OUT" | grep -c '^ok   original table passes (')
e2e_expect_equal "$TR_NPY" "$TR_ORIG" "interpreters the original table passed under"
e2e_expect_no_out "skip interpreter"
e2e_expect_clean_edges

_flow_test_begin "factory table: --markdown on a scratch copy leaves the plugin unchanged (X4)"
_tr_scenario tr-markdown-not-in-plugin "git status of plugins/flow before and after --markdown on a scratch copy of the plugin table; no references/transitions.md (check_transitions.py:1455-1458 writes beside its input)"
mkdir -p "$E2E_DIR/copy"
cp "$TR_TABLE" "$E2E_DIR/copy/factory-transitions.json" 2>/dev/null
TR_BEFORE=$(git -C "$REPO_ROOT" status --porcelain -- plugins/flow 2>&1)
if [ -n "$TR_PY1" ]; then
  _e2e_exec "$TR_PY1" -I "$TR_DOCS/check_transitions.py" "$E2E_DIR/copy/factory-transitions.json" --markdown
  e2e_expect_equal "0" "$E2E_RC" "checker --markdown exit status"
else
  _e2e_result fail "an interpreter to run the checker under"
fi
TR_AFTER=$(git -C "$REPO_ROOT" status --porcelain -- plugins/flow 2>&1)
printf -- '--- git status --porcelain -- plugins/flow, before\n%s\n--- after\n%s\n' "$TR_BEFORE" "$TR_AFTER" | _e2e_art
e2e_expect_equal "$TR_BEFORE" "$TR_AFTER" "git status of plugins/flow after the run"
if [ -e "$REPO_ROOT/plugins/flow/references/transitions.md" ]; then TR_MD=present; else TR_MD=absent; fi
e2e_expect_equal "absent" "$TR_MD" "transitions.md"
if [ -f "$E2E_DIR/copy/transitions.md" ]; then TR_MD=present; else TR_MD=absent; fi
e2e_expect_equal "present" "$TR_MD" "the scratch copy's transitions.md"
e2e_expect_clean_edges

_flow_test_begin "factory table: docs/flow-factory/transitions.md is the checker's --markdown output (X5)"
_tr_scenario tr-markdown-current "--markdown on a scratch copy of the docs table named transitions.json; the file it writes equals docs/flow-factory/transitions.md"
mkdir -p "$E2E_DIR/md"
cp "$TR_DOCS/transitions.json" "$E2E_DIR/md/transitions.json"
while IFS= read -r _tr_py; do
  [ -n "$_tr_py" ] || continue
  rm -f "$E2E_DIR/md/transitions.md"
  _e2e_exec "$_tr_py" -I "$TR_DOCS/check_transitions.py" "$E2E_DIR/md/transitions.json" --markdown
  e2e_expect_equal "0" "$E2E_RC" "checker --markdown exit status under $_tr_py"
  _e2e_exec cmp "$TR_DOCS/transitions.md" "$E2E_DIR/md/transitions.md"
  e2e_expect_equal "0" "$E2E_RC" "cmp of transitions.md under $_tr_py"
done <<EOF
$TR_PYS
EOF
[ -n "$TR_PYS" ] || _e2e_result fail "an interpreter to run the checker under"
e2e_expect_clean_edges

_flow_test_begin "factory table: a change to the table, a schema, a setting or a template triggers the flow suite (X6)"
_tr_scenario tr-ci-paths "each path below matches a pull_request and a push path filter of flow-tests.yml, under GitHub's glob rules; and flow-workflow-check.py accepts the workflow"
cat > "$E2E_DIR/paths.py" <<'PY'
import re, sys
import yaml

wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get("on", wf.get(True))
samples = sys.argv[2:]

def regex(pattern):
    # GitHub's filter patterns: * is any run of characters but /, ** any run
    # of characters. A pattern using another special character is not read
    # here, so it is reported rather than guessed at.
    if re.search(r"[?\[\]!+]", pattern):
        raise SystemExit("unsupported pattern: %s" % pattern)
    out = ""
    for part in re.split(r"(\*\*|\*)", pattern):
        out += {"**": ".*", "*": "[^/]*"}.get(part, re.escape(part))
    return re.compile(out + r"\Z")

bad = 0
for trigger in ("pull_request", "push"):
    patterns = on[trigger]["paths"]
    for path in samples:
        hit = [p for p in patterns if regex(p).match(path)]
        if hit:
            print("MATCH %s %s %s" % (trigger, path, hit[0]))
        else:
            print("NOMATCH %s %s" % (trigger, path))
            bad += 1
sys.exit(1 if bad else 0)
PY
# One path per area the factory adds or reads (plan T1 step 2): the docs
# table, the plugin table, a schema, the two settings files and a template.
TR_SAMPLES="docs/flow-factory/transitions.json plugins/flow/references/factory-transitions.json plugins/flow/schemas/v1/factory-job.schema.json plugins/flow/settings.json plugins/flow/schema.json plugins/flow/templates/factory/resume.prompt.md"
if [ -n "$TR_CHOSEN" ]; then
  # shellcheck disable=SC2086
  _e2e_exec env HOME="$TR_REAL_HOME" "$TR_CHOSEN" -E "$E2E_DIR/paths.py" "$REPO_ROOT/.github/workflows/flow-tests.yml" $TR_SAMPLES
  e2e_expect_equal "0" "$E2E_RC" "path match exit status"
  for _tr_t in pull_request push; do
    for _tr_s in $TR_SAMPLES; do
      if printf '%s\n' "$E2E_OUT" | grep -q "^MATCH $_tr_t $_tr_s "; then
        _e2e_result pass "$_tr_t paths match $_tr_s"
      else
        _e2e_result fail "$_tr_t paths match $_tr_s"
      fi
    done
  done
  _e2e_exec env HOME="$TR_REAL_HOME" "$TR_CHOSEN" -E "$REPO_ROOT/plugins/flow/tests/lib/flow-workflow-check.py" "$REPO_ROOT/.github/workflows/flow-tests.yml"
  if printf '%s\n' "$E2E_OUT" | grep -q '^OK '; then
    _e2e_result pass "flow-workflow-check.py accepts the workflow"
  else
    _e2e_result fail "flow-workflow-check.py accepts the workflow"
  fi
else
  _e2e_result fail "an interpreter to read the workflow with"
fi
e2e_expect_clean_edges
