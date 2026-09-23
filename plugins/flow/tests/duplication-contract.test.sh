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
        HOME|PATH|CLAUDE_PLUGIN_ROOT|CLAUDE_CONFIG_DIR|PWD|IFS) continue ;;
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
# The author-context resolver's second candidate is the working-directory
# relative `plugins/flow`, so after `gh pr checkout` the branch under review
# supplies the scripts that judge it - verified: such a branch's own
# flow-dep-diff.sh ran and printed a forged clean dependency verdict.
#
# This walk is written as the RULE, not as a list of files. Naming the files by
# hand is how the previous version passed while convention-checker.md and twelve
# command fences carried the old form: the walk could not fail for anything it
# had not been told about. The rule is the one
# references/plugin-root-resolution.md states - every resolver that runs after a
# `gh pr checkout`, and every resolver in an agent those commands dispatch, uses
# the post-checkout form.
DC_FR_DIR=$(mktemp -d -t flow-dup-fr.XXXXXX)
# Removed on exit: without this every run left an initialised git repository
# and three stub plugin trees behind, and 83 of them had accumulated.
trap 'rm -rf "$DC_FR_DIR"' EXIT
# The fence reports a physical path, and on macOS the temp root is reached
# through a symlink; comparing against the logical path would fail for a reason
# that has nothing to do with the fence.
DC_FR_DIR=$(cd "$DC_FR_DIR" && pwd -P)
DC_FR_BLOCKS="$DC_FR_DIR/blocks"
mkdir -p "$DC_FR_BLOCKS"

# The single source of both forms.
DC_FR_DOC="$REPO_ROOT/plugins/flow/references/plugin-root-resolution.md"

_flow_test_begin "plugin roots: both forms are defined in the reference doc"
DC_FR_SKIP=$(grep -m1 '^"\$(__t=' "$DC_FR_DOC")
DC_FR_AUTHOR=$(grep -m1 '^"\$(__fr=' "$DC_FR_DOC")
assert_not_contains "MISSING" "${DC_FR_SKIP:-MISSING}" "the post-checkout form is documented"
assert_not_contains "MISSING" "${DC_FR_AUTHOR:-MISSING}" "and so is the author-context form"

# Every site, found by the rule rather than by a list. A resolver may be written
# indented - commands/start.md already does - so neither the search nor the
# counting anchors at column 0.
# The script goes to a file first: bash 3.2 cannot parse a here-document
# inside $( ), and this suite runs on a bash 3.2 runner.
cat > "$DC_FR_DIR/rule.py" <<'FRPY'
import os, re, sys

root = os.environ["DC_ROOT"]
AUTHOR = "$(__fr="
SKIP = "$(__t="
CHECKOUT = "gh pr checkout"

# Which agents the two review commands dispatch: read it, do not assume it.
dispatched = set()
for name in ("review.md", "address.md"):
    src = open(os.path.join(root, "plugins/flow/commands", name), encoding="utf-8").read()
    # The closing paren is not always next: review.md writes
    # Agent(code-reviewer, model=$AGENT_TEAM_MODEL) in eight places, and an
    # agent dispatched only that way was classified as author context. No
    # classification changes in this tree today - the names the widening adds
    # are lens suffixes with no agent file behind them - so this is a guard
    # against the next agent that is dispatched only with arguments, not a fix
    # for a live exposure.
    dispatched |= set(re.findall(r"Agent\(([a-z0-9-]+)\s*[,)]", src))

problems = []
sites = 0

def scan(path, must_skip_from, checkout_bang=False):
    """must_skip_from: line number of an inline checkout, after which a resolver
    in an inline fence runs against the pull request's tree; 0 for a file that
    is post-checkout throughout (an agent the review commands dispatch); None
    when the file is author context. checkout_bang: the checkout itself is in a
    `!` fence, so `!` fences after it are post-checkout too."""
    global sites
    rel = os.path.relpath(path, root)
    fence = None
    gate = False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.startswith("```"):
            fence = None if fence else line.strip()
            continue
        # The review.groundingCritic lookup is the one named exception: in a
        # command that checks out a pull request it takes the post-checkout
        # form even in a ! fence, because the setting decides which of the pull
        # request's findings survive (references/plugin-root-resolution.md).
        if "# GROUNDING_CRITIC_BEGIN" in line:
            gate = True
        elif "# GROUNDING_CRITIC_END" in line:
            gate = False
        if AUTHOR not in line and SKIP not in line:
            continue
        sites += 1
        is_skip = SKIP in line
        if must_skip_from is None:
            post = False
        elif gate:
            post = True
        elif must_skip_from == 0:
            post = True
        elif fence == "```!":
            # Expanded before the command body, so an inline checkout has not
            # happened yet however far down the file this sits.
            post = checkout_bang and n > must_skip_from
        else:
            post = n > must_skip_from
        if post and not is_skip:
            problems.append("%s:%d runs against the pull request's tree but uses the author-context form" % (rel, n))
        elif not post and is_skip:
            problems.append("%s:%d runs in author context but uses the post-checkout form" % (rel, n))

# Which commands check out a pull request: read it, do not assume it. A command
# that gains a checkout later is covered without editing this list, which is
# what "written as the rule" has to mean for the command half too.
commands_dir = os.path.join(root, "plugins/flow/commands")
for name in sorted(os.listdir(commands_dir)):
    if not name.endswith(".md"):
        continue
    path = os.path.join(commands_dir, name)
    body = open(path, encoding="utf-8").read()
    if AUTHOR not in body and SKIP not in body:
        continue
    if not any(l.strip().startswith(CHECKOUT) for l in body.splitlines()):
        scan(path, None)       # no checkout: author context throughout
        continue
    # The checkout's own fence decides what "after" means. A `!` fence is
    # expanded before the command body runs, so an inline checkout leaves every
    # `!` fence in author context whatever its line number.
    fence = None
    checkout_inline = 0
    checkout_bang = False
    for i, l in enumerate(body.splitlines(), 1):
        if l.startswith("```"):
            fence = None if fence else l.strip()
            continue
        # The command itself, not a sentence about it: review.md mentions
        # `gh pr checkout` in prose and in comments, and counting those put the
        # checkout after every resolver in the file.
        if fence and l.strip().startswith(CHECKOUT):
            if fence == "```!":
                checkout_bang = True
            else:
                checkout_inline = max(checkout_inline, i)
    if not checkout_inline and not checkout_bang:
        problems.append("%s: `gh pr checkout` is outside any fence, so the rule cannot be applied" % name)
        continue
    scan(path, checkout_inline, checkout_bang)

agents_dir = os.path.join(root, "plugins/flow/agents")
for fn in sorted(os.listdir(agents_dir)):
    if not fn.endswith(".md"):
        continue
    path = os.path.join(agents_dir, fn)
    body = open(path, encoding="utf-8").read()
    if AUTHOR not in body and SKIP not in body:
        continue
    if fn[:-3] in dispatched:
        scan(path, 0)          # every resolver in it runs post-checkout
    else:
        scan(path, None)       # author context

# Counted a second time, by a different route, so a site that stops being
# reached by the walk shows up as a mismatch rather than as a smaller number
# still clearing a floor.
independent = 0
for d in ("plugins/flow/commands", "plugins/flow/agents"):
    full = os.path.join(root, d)
    for fn in sorted(os.listdir(full)):
        if fn.endswith(".md"):
            body = open(os.path.join(full, fn), encoding="utf-8").read()
            independent += body.count(AUTHOR) + body.count(SKIP)
print("DISPATCHED=%s" % ",".join(sorted(dispatched)))
print("SITES=%d" % sites)
print("INDEPENDENT=%d" % independent)
print("AGENTS_DISPATCHED=%d" % len(dispatched))
for p in problems:
    print("PROBLEM=%s" % p)
FRPY
DC_FR_REPORT=$(DC_ROOT="$REPO_ROOT" python3 "$DC_FR_DIR/rule.py")
DC_FR_SITES=$(printf '%s\n' "$DC_FR_REPORT" | sed -n 's/^SITES=//p')
DC_FR_INDEP=$(printf '%s\n' "$DC_FR_REPORT" | sed -n 's/^INDEPENDENT=//p')
DC_FR_DISPATCHED=$(printf '%s\n' "$DC_FR_REPORT" | sed -n 's/^DISPATCHED=//p')
DC_FR_PROBLEMS=$(printf '%s\n' "$DC_FR_REPORT" | grep -c '^PROBLEM=' || true)

# The dispatch parser decides whether an agent file is judged as post-checkout
# or as author context, so a dispatch it cannot see is an agent nothing checks.
# review.md writes most of its dispatches as Agent(name, model=$AGENT_TEAM_MODEL),
# and a regex requiring the closing paren next matched none of them.
_flow_test_begin "plugin roots: a dispatch written with arguments is still a dispatch"
assert_contains "code-reviewer-skeptic" "$DC_FR_DISPATCHED" \
  "a name that appears only as Agent(name, model=...) is in the dispatched set"
assert_contains "code-reviewer," "$DC_FR_DISPATCHED," "and the bare form is still read"

_flow_test_begin "plugin roots: the walk reached every site, not merely enough of them"
# A floor is not a reach check: with "at least 15" against 92 sites, seventy-odd
# could be deleted and every assertion here would still pass.
assert_equal "$DC_FR_INDEP" "${DC_FR_SITES:-0}" \
  "every resolver in commands/ and agents/ was classified, counted independently"
if [ "${DC_FR_SITES:-0}" -ge 15 ] 2>/dev/null; then
  _flow_assert_pass "$DC_FR_SITES resolver site(s) examined — a walk over zero would pass on anything"
else
  _flow_assert_fail "only ${DC_FR_SITES:-0} resolver site(s) reached"
fi

_flow_test_begin "plugin roots: every post-checkout site uses the post-checkout form"
if [ "$DC_FR_PROBLEMS" = "0" ]; then
  _flow_assert_pass "no site carries the wrong form for where it runs"
else
  _flow_assert_fail "$(printf '%s\n' "$DC_FR_REPORT" | sed -n 's/^PROBLEM=/  /p')"
fi

# The three agent fences that turn an empty result into a STATE line.
DC_FR_N=$(DC_ROOT="$REPO_ROOT" DC_OUT="$DC_FR_BLOCKS" python3 -c '
import os, re
n = 0
d = os.path.join(os.environ["DC_ROOT"], "plugins/flow/agents")
for fn in sorted(os.listdir(d)):
    if not fn.endswith(".md"):
        continue
    src = open(os.path.join(d, fn), encoding="utf-8").read()
    for block in re.findall(r"^[ \t]*# FLOW_ROOT_BEGIN\n.*?^[ \t]*# FLOW_ROOT_END$", src, re.S | re.M):
        n += 1
        open(os.path.join(os.environ["DC_OUT"], "block%d.sh" % n), "w", encoding="utf-8").write(block + "\n")
print(n)
')
DC_FR_EXPECTED=$(grep -rc '# FLOW_ROOT_BEGIN' "$REPO_ROOT"/plugins/flow/agents/*.md | sed 's/.*://' | awk '{t+=$1} END{print t+0}')

_flow_test_begin "plugin roots: every STATE-emitting fence was extracted"
assert_equal "$DC_FR_EXPECTED" "${DC_FR_N:-0}" \
  "the extractor finds every sentinel, counted independently"
if [ "${DC_FR_EXPECTED:-0}" -ge 3 ] 2>/dev/null; then
  _flow_assert_pass "$DC_FR_EXPECTED fence(s) found — a walk over zero would pass on anything"
else
  _flow_assert_fail "expected at least three STATE-emitting fences, found $DC_FR_EXPECTED"
fi

_flow_test_begin "plugin roots: the STATE-emitting fences are one text"
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
mkdir -p "$DC_FR_DIR/notarepo"

_dc_fence_root() {
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

  # Outside a git repository nothing is in-repository, so nothing may be
  # skipped. `cd ""` returns 0 on bash 3.2 and leaves the working directory
  # alone, which turned "not a repository" into "everything under here is one"
  # and refused an install sitting above the working directory.
  _flow_test_begin "plugin-root fence $DC_FR_I: outside a repository nothing is skipped"
  # The working directory must be an ANCESTOR of the install for this to
  # discriminate: from a sibling directory the faulty form finds it anyway.
  # $DC_FR_DIR contains home/ and is not a git repository.
  DC_FR_OUT=$( cd "$DC_FR_DIR" && env -u CLAUDE_PLUGIN_ROOT HOME="$DC_FR_HOME" \
    bash -c ". '$DC_FR_B'; printf 'FLOW_ROOT=%s\n' \"\$FLOW_ROOT\"" 2>&1 )
  assert_contains "FLOW_ROOT=$DC_FR_CACHE" "$DC_FR_OUT" "the install is found, not refused"
  assert_not_contains "STATE=unavailable" "$DC_FR_OUT" "and no state line is emitted"

  _flow_test_begin "plugin-root fence $DC_FR_I: no outside install is unavailable, not the branch's own"
  DC_FR_OUT=$(_dc_fence_root "$DC_FR_B" -u CLAUDE_PLUGIN_ROOT "HOME=$DC_FR_DIR/emptyhome")
  assert_contains "STATE=unavailable" "$DC_FR_OUT" "every candidate was in-repository, so nobody could look"
  assert_not_contains "FLOW_ROOT=" "$DC_FR_OUT" "no root is handed on"

  DC_FR_I=$((DC_FR_I + 1))
done
