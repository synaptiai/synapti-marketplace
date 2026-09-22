# Tests for the duplication contract (issue #219): the plan-time reuse field,
# the four call sites, and the settings/schema/finding vocabulary.
#
# Contract (.decisions/issue-219.md § Interface contracts):
#   - The planner says what it searched before it plans a new helper, in one of
#     exactly two forms, and the Stranger Test fails a task that does not.
#   - Every review path and the task-time gate reach the scan, and the
#     code-reviewer states how many reuse candidates it examined.
#   - duplication.minTokens is a first-class setting, because the token floor is
#     half of a threshold whose other half is already documented.
#
# The schema assertions are behavioural: an instance is validated against
# schema.json with jsonschema, the way tests/flow-agentteam-model.test.sh
# asserts on settings rather than grepping for a type keyword. A grep for
# `"type": "integer"` would pass on a schema that never reaches the key.
#
# Expected values are quoted from the journal's Interface contracts section,
# never read back from the files under test.

PLANNER="$REPO_ROOT/plugins/flow/agents/implementation-planner.md"
REVIEWER="$REPO_ROOT/plugins/flow/agents/code-reviewer.md"
SCHEMA="$REPO_ROOT/plugins/flow/schema.json"
SETTINGS="$REPO_ROOT/plugins/flow/settings.json"
FINDING="$REPO_ROOT/plugins/flow/references/finding-schema.md"
CMD_DIR="$REPO_ROOT/plugins/flow/commands"

_flow_test_begin "files under test are present"
DC_EXAMINED=0
for F in "$PLANNER" "$REVIEWER" "$SCHEMA" "$SETTINGS" "$FINDING" \
         "$CMD_DIR/start.md" "$CMD_DIR/review.md" "$CMD_DIR/pr.md" "$CMD_DIR/address.md"; do
  if [ -s "$F" ]; then
    DC_EXAMINED=$((DC_EXAMINED + 1))
  else
    _flow_assert_fail "missing or empty: $F"
  fi
done
assert_equal "9" "$DC_EXAMINED" "all nine files read"

# --- AC1: the planner says what it searched -----------------------------------
DC_PLANNER=$(cat "$PLANNER")
_flow_test_begin "planner: the task template carries the reuse field"
assert_contains "Reuses:" "$DC_PLANNER" "the field is in the template"
assert_contains 'existing <file>:<symbol>' "$DC_PLANNER" "form one: name what to call"
assert_contains "candidates examined: N" "$DC_PLANNER" "form two: say what was searched and how much"

_flow_test_begin "planner: the field reaches the returned plan, not only the task body"
DC_TABLE=$(printf '%s\n' "$DC_PLANNER" | awk '/^### Tasks Created/{on=1} on&&/^\| /{print} on&&/^### Parallel/{exit}')
assert_contains "Reuses" "$DC_TABLE" "the Step 6 return table has a Reuses column"

# The Stranger Test mode must be IN the Stranger Test, not merely somewhere in a
# thousand-line command file. Extract the section and assert inside it.
DC_STRANGER=$(awk '/^\*\*Stranger Test check\*\*/{on=1} on{print} on&&/^If ANY task fails/{exit}' "$CMD_DIR/start.md")
_flow_test_begin "stranger test: the reuse failure mode is inside the gate"
assert_contains "Missing reuse check" "$DC_STRANGER" "the mode is listed in the Stranger Test"
DC_STRANGER_LINES=$(printf '%s\n' "$DC_STRANGER" | wc -l | tr -d ' ')
if [ "$DC_STRANGER_LINES" -gt 5 ] 2>/dev/null; then
  _flow_assert_pass "the extracted gate is $DC_STRANGER_LINES lines"
else
  _flow_assert_fail "the Stranger Test section extracted to $DC_STRANGER_LINES lines — the assertion above matched almost nothing"
fi

# --- AC4: the four call sites and the reviewer's two layers -------------------
DC_SITES=0
HELPER_NAME="flow-clone-scan.sh"
for F in start review pr address; do
  if grep -q "$HELPER_NAME" "$CMD_DIR/$F.md"; then
    DC_SITES=$((DC_SITES + 1))
  else
    _flow_assert_fail "commands/$F.md never names the scan"
  fi
done
_flow_test_begin "call sites: all four commands reach the scan"
assert_equal "4" "$DC_SITES" "four command files name the helper"

_flow_test_begin "task-time gate: the completion rule is stated in terms of what was found"
DC_START=$(cat "$CMD_DIR/start.md")
assert_contains "CLONE=added" "$DC_START" "the blocking condition is named"
assert_contains "never on the absence of a finder" "$DC_START" "and an absent scanner does not block"

DC_REVIEWER=$(cat "$REVIEWER")
_flow_test_begin "code-reviewer: both layers, and the count that makes silence legible"
assert_contains "candidates examined: N" "$DC_REVIEWER" "Layer B reports how many candidates it examined"
assert_contains "$HELPER_NAME" "$DC_REVIEWER" "Layer A runs the scan"
assert_contains "STATE=unavailable" "$DC_REVIEWER" "and distinguishes nobody-looked from found-nothing"

# A fence that cannot be extracted is prose: nothing tests it, and a name-grep
# does not pin that the script is actually called.
_flow_test_begin "code-reviewer: the scan sits in an extractable, parsable bash fence"
DC_FENCE=$(awk '/^```bash$/{on=1;buf="";next} on&&/^```$/{if (buf ~ /flow-clone-scan/) {printf "%s", buf; exit} on=0; next} on{buf=buf $0 "\n"}' "$REVIEWER")
if [ -n "$DC_FENCE" ]; then
  _flow_assert_pass "a bash fence containing the invocation was extracted"
  if printf '%s\n' "$DC_FENCE" | bash -n 2>/dev/null; then
    _flow_assert_pass "the extracted fence parses as bash"
  else
    _flow_assert_fail "the extracted fence does not parse as bash"
  fi
else
  _flow_assert_fail "no extractable bash fence in code-reviewer.md contains the invocation"
fi

_flow_test_begin "reviewer fences resolve every variable they read"
# Each bash fence is its own shell, so a variable set in an earlier fence is
# unset in this one. A command that reads one runs against an empty value: the
# clone scan against `origin/`, the secrets scan against `origin/`. Both fail
# and report nothing, which is indistinguishable from a clean result.
DC_FENCE_FILES="$REVIEWER $REPO_ROOT/plugins/flow/agents/security-reviewer.md"
DC_BAD=""
DC_FENCES_CHECKED=0
DC_VARS_SEEN=0
for DC_F in $DC_FENCE_FILES; do
  DC_N=$(awk '/^```bash$/{n++} END{print n+0}' "$DC_F")
  DC_I=1
  while [ "$DC_I" -le "$DC_N" ]; do
    DC_BODY=$(awk -v want="$DC_I" '/^```bash$/{n++; if(n==want){on=1; next}} on&&/^```$/{exit} on{print}' "$DC_F")
    DC_FENCES_CHECKED=$((DC_FENCES_CHECKED + 1))
    for DC_V in $(printf '%s\n' "$DC_BODY" | grep -oE '[$][{]?[A-Z_][A-Z0-9_]*' | tr -d '${' | sort -u); do
      DC_VARS_SEEN=$((DC_VARS_SEEN + 1))
      case "$DC_V" in
        HOME|PATH|CLAUDE_PLUGIN_ROOT|PWD|IFS) continue ;;
        *[!_]*) ;;
        *) continue ;;
      esac
      # Assigned covers more than `VAR=`: a read target and a for header bind
      # the name too, and flagging those would fire on correct fences.
      printf '%s\n' "$DC_BODY" | grep -qE "^[[:space:]]*(export[[:space:]]+)?$DC_V=|read([[:space:]]+-[A-Za-z]+)*[[:space:]]+$DC_V|for[[:space:]]+$DC_V[[:space:]]+in" \
        || DC_BAD="$DC_BAD $(basename "$DC_F"):fence$DC_I:$DC_V"
    done
    DC_I=$((DC_I + 1))
  done
done
if [ "$DC_FENCES_CHECKED" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "$DC_FENCES_CHECKED fence(s) examined across both reviewer agents"
else
  _flow_assert_fail "no fences were extracted — the walk reached nothing and would pass on anything"
fi
# Fences examined is not variables examined: a walk whose variable match found
# nothing in every fence reports the same green fence count.
if [ "$DC_VARS_SEEN" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "$DC_VARS_SEEN variable reference(s) examined inside those fences"
else
  _flow_assert_fail "the walk found no variable references at all; the match reached nothing"
fi
assert_equal "" "$DC_BAD" "every variable a fence reads is assigned in the same fence"

# --- AC5: vocabulary and settings ---------------------------------------------
DC_FINDING=$(cat "$FINDING")
_flow_test_begin "finding schema: the category and the prefix"
assert_contains '| `duplication` |' "$DC_FINDING" "duplication is in the category vocabulary"
assert_contains '`DUP-`' "$DC_FINDING" "DUP- is in the prefix table"
assert_contains "The location is the **added** side" "$DC_FINDING" \
  "and the row says the location is the added side"

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import json, jsonschema" >/dev/null 2>&1; then
  _flow_test_begin "settings schema prerequisite"
  _flow_assert_pass "SKIP: python3 with jsonschema is not available"
else
  _dc_validate() {
    # $1 = instance JSON, $2 = schema path. Prints "valid" or "invalid".
    DC_INSTANCE="$1" DC_SCHEMA="$2" python3 -c '
import json, os, sys, jsonschema
schema = json.load(open(os.environ["DC_SCHEMA"]))
try:
    jsonschema.validate(json.loads(os.environ["DC_INSTANCE"]), schema)
    print("valid")
except jsonschema.ValidationError:
    print("invalid")
'
  }

  _flow_test_begin "settings schema: the token floor is typed, so a string is refused"
  assert_equal "invalid" "$(_dc_validate '{"duplication":{"minLines":"5"}}' "$SCHEMA")" \
    'minLines as the string "5" is rejected'
  assert_equal "valid" "$(_dc_validate '{"duplication":{"minLines":5}}' "$SCHEMA")" \
    "minLines as the integer 5 is accepted"
  assert_equal "invalid" "$(_dc_validate '{"duplication":{"minTokens":"20"}}' "$SCHEMA")" \
    'minTokens as the string "20" is rejected'

  # Input removal: with the duplication block gone from the schema, the string
  # must start passing. Without this the two assertions above would also hold
  # for a schema that never mentions the key, since additionalProperties is the
  # only thing that would have caught it.
  _flow_test_begin "settings schema: the assertions reach the duplication block"
  DC_STRIPPED=$(mktemp -t flow-dup-schema.XXXXXX)
  DC_SCHEMA_PATH="$SCHEMA" DC_OUT="$DC_STRIPPED" python3 -c '
import json, os
d = json.load(open(os.environ["DC_SCHEMA_PATH"]))
d["properties"].pop("duplication", None)
d["additionalProperties"] = True
json.dump(d, open(os.environ["DC_OUT"], "w"))
'
  assert_equal "valid" "$(_dc_validate '{"duplication":{"minLines":"5"}}' "$DC_STRIPPED")" \
    "the string passes once the duplication block is removed — the rejection came from it"
  rm -f "$DC_STRIPPED"

  _flow_test_begin "settings: the four defaults, and the artifact trees that must be exempt"
  DC_DEFAULTS=$(DC_SETTINGS="$SETTINGS" python3 -c '
import json, os
d = json.load(open(os.environ["DC_SETTINGS"])).get("duplication", {})
ex = d.get("excludePaths", [])
print("enabled=%s minLines=%s minTokens=%s n=%d decisions=%s flow=%s" % (
    d.get("enabled"), d.get("minLines"), d.get("minTokens"), len(ex),
    ".decisions/**" in ex, ".flow/**" in ex))
')
  assert_contains "enabled=True" "$DC_DEFAULTS" "enabled defaults to true"
  assert_contains "minLines=5" "$DC_DEFAULTS" "minLines defaults to 5"
  assert_contains "minTokens=20" "$DC_DEFAULTS" "minTokens defaults to 20 — below jscpd's own 50"
  assert_contains "decisions=True" "$DC_DEFAULTS" "the decision journal is exempt"
  assert_contains "flow=True" "$DC_DEFAULTS" "the runtime state tree is exempt"
fi

# --- the reviewer's plugin root comes from outside the repository under review ---
# The resolver's first candidate is the working-directory-relative
# `plugins/flow`, so a branch shipping that directory would supply the scripts
# that judge it - verified: such a branch's own flow-dep-diff.sh ran and printed
# a forged clean dependency verdict. Refusing outright was worse than it looked:
# flow's own repository is exactly such a checkout, so every self-review
# reported unavailable while an installed copy outside the tree went unused.
# The fence must SKIP the in-repository candidate and take the next one, and
# report unavailable only when every candidate is in-repository.
DC_FR_DIR=$(mktemp -d -t flow-dup-fr.XXXXXX)
# The fence reports a physical path, and on macOS the temp root is reached
# through a symlink; comparing against the logical path would fail for a reason
# that has nothing to do with the fence.
DC_FR_DIR=$(cd "$DC_FR_DIR" && pwd -P)
DC_FR_BLOCKS="$DC_FR_DIR/blocks"
mkdir -p "$DC_FR_BLOCKS"
DC_FR_FILES="$REPO_ROOT/plugins/flow/agents/code-reviewer.md $REPO_ROOT/plugins/flow/agents/security-reviewer.md"

# Counted twice, from two different anchors. A walk that trusts the number its
# own extractor reports cannot tell "this fence is sound" from "this fence left
# the walk": two mutants moved the count from 2 to 1 with every assertion still
# green, and one of them accepted the in-repository copy.
DC_FR_EXPECTED=0
for DC_FR_F in $DC_FR_FILES; do
  DC_FR_EXPECTED=$((DC_FR_EXPECTED + $(grep -c '^FLOW_ROOT=\$($' "$DC_FR_F")))
done
DC_FR_N=$(DC_FILES="$DC_FR_FILES" DC_OUT="$DC_FR_BLOCKS" python3 -c '
import os, re
n = 0
for path in os.environ["DC_FILES"].split():
    src = open(path, encoding="utf-8").read()
    for block in re.findall(r"^# FLOW_ROOT_BEGIN\n.*?^# FLOW_ROOT_END$", src, re.S | re.M):
        n += 1
        open(os.path.join(os.environ["DC_OUT"], "block%d.sh" % n), "w", encoding="utf-8").write(block + "\n")
print(n)
')

_flow_test_begin "reviewer agents: every plugin-root fence was extracted"
assert_equal "$DC_FR_EXPECTED" "${DC_FR_N:-0}" \
  "the walk examines every FLOW_ROOT assignment in both reviewer agents, counted independently"
if [ "${DC_FR_EXPECTED:-0}" -ge 3 ] 2>/dev/null; then
  _flow_assert_pass "$DC_FR_EXPECTED fence(s) found — a walk over zero would pass on anything"
else
  _flow_assert_fail "expected at least three plugin-root fences across the two reviewer agents, found $DC_FR_EXPECTED"
fi

# One resolver, three copies: a fix applied to two of them is the defect this
# whole cycle kept finding.
_flow_test_begin "reviewer agents: the three plugin-root fences are the same text"
DC_FR_UNIQUE=$(for f in "$DC_FR_BLOCKS"/block*.sh; do md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1; done | sort -u | wc -l | tr -d ' ')
assert_equal "1" "$DC_FR_UNIQUE" "every extracted fence is byte-identical to the others"

# A fake install outside the repository, and an in-repository copy that must
# lose to it. Both carry an executable cascade-resolve.sh, so the only thing
# separating them is where they sit.
DC_FR_HOME="$DC_FR_DIR/home"
mkdir -p "$DC_FR_HOME/.claude/plugins/cache/synapti-marketplace/flow/9.9.9/bin"
printf '#!/bin/sh\nexit 0\n' \
  > "$DC_FR_HOME/.claude/plugins/cache/synapti-marketplace/flow/9.9.9/bin/cascade-resolve.sh"
chmod +x "$DC_FR_HOME/.claude/plugins/cache/synapti-marketplace/flow/9.9.9/bin/cascade-resolve.sh"
DC_FR_CACHE="$DC_FR_HOME/.claude/plugins/cache/synapti-marketplace/flow/9.9.9"

# A third install, outside the repository and outside HOME, so a run that
# honours CLAUDE_PLUGIN_ROOT can be told apart from one that ignores it.
DC_FR_ELSEWHERE="$DC_FR_DIR/elsewhere/flow"
mkdir -p "$DC_FR_ELSEWHERE/bin"
printf '#!/bin/sh\nexit 0\n' > "$DC_FR_ELSEWHERE/bin/cascade-resolve.sh"
chmod +x "$DC_FR_ELSEWHERE/bin/cascade-resolve.sh"

DC_FR_REPO="$DC_FR_DIR/under-review"
mkdir -p "$DC_FR_REPO/plugins/flow/bin"
printf '#!/bin/sh\nexit 0\n' > "$DC_FR_REPO/plugins/flow/bin/cascade-resolve.sh"
chmod +x "$DC_FR_REPO/plugins/flow/bin/cascade-resolve.sh"
( cd "$DC_FR_REPO" && git init -q -b base . >/dev/null 2>&1 )

_dc_fence_root() {
  # _dc_fence_root <block> <env assignment...> — runs the fence in the
  # repository under review and echoes what it resolved, or its state line.
  local block="$1"; shift
  ( cd "$DC_FR_REPO" && env "$@" bash -c ". '$block'; printf 'FLOW_ROOT=%s\n' \"\$FLOW_ROOT\"" 2>&1 )
}

DC_FR_I=1
while [ "$DC_FR_I" -le "${DC_FR_N:-0}" ]; do
  DC_FR_B="$DC_FR_BLOCKS/block$DC_FR_I.sh"

  _flow_test_begin "plugin-root fence $DC_FR_I: an install outside the repository wins"
  DC_FR_OUT=$(_dc_fence_root "$DC_FR_B" -u CLAUDE_PLUGIN_ROOT "HOME=$DC_FR_HOME")
  assert_contains "FLOW_ROOT=$DC_FR_CACHE" "$DC_FR_OUT" \
    "the out-of-repository install is chosen over the in-repository copy"
  assert_not_contains "STATE=unavailable" "$DC_FR_OUT" \
    "and the in-repository candidate is skipped, not treated as the end of the search"

  # CLAUDE_PLUGIN_ROOT is a candidate like any other: honoured when it points
  # outside, skipped when it points inside. Neither half was exercised, so the
  # candidate could be deleted outright with every test still green.
  _flow_test_begin "plugin-root fence $DC_FR_I: CLAUDE_PLUGIN_ROOT is honoured when it points outside"
  DC_FR_OUT=$(_dc_fence_root "$DC_FR_B" "CLAUDE_PLUGIN_ROOT=$DC_FR_ELSEWHERE" "HOME=$DC_FR_HOME")
  assert_contains "FLOW_ROOT=$DC_FR_ELSEWHERE" "$DC_FR_OUT" \
    "the explicitly named root is preferred to the cache entry"

  _flow_test_begin "plugin-root fence $DC_FR_I: CLAUDE_PLUGIN_ROOT pointing inside is skipped"
  DC_FR_OUT=$(_dc_fence_root "$DC_FR_B" "CLAUDE_PLUGIN_ROOT=$DC_FR_REPO/plugins/flow" "HOME=$DC_FR_HOME")
  assert_contains "FLOW_ROOT=$DC_FR_CACHE" "$DC_FR_OUT" \
    "a root inside the repository under review loses to the cache entry"
  assert_not_contains "FLOW_ROOT=$DC_FR_REPO" "$DC_FR_OUT" \
    "the repository's own copy is never selected, however it was named"

  # Must-stay-silent's opposite: with nothing outside the repository there is
  # genuinely nothing safe to run, and that has to be said rather than fall
  # back to the branch's own copy.
  _flow_test_begin "plugin-root fence $DC_FR_I: no outside install is unavailable, not the branch's own"
  DC_FR_OUT=$(_dc_fence_root "$DC_FR_B" -u CLAUDE_PLUGIN_ROOT "HOME=$DC_FR_DIR/emptyhome")
  assert_contains "STATE=unavailable" "$DC_FR_OUT" "every candidate was in-repository, so nobody could look"
  # The fence ends there, so nothing downstream ever sees a root: no FLOW_ROOT
  # line is printed at all, and least of all the repository's own copy.
  assert_not_contains "FLOW_ROOT=" "$DC_FR_OUT" "no root is handed on"

  DC_FR_I=$((DC_FR_I + 1))
done
