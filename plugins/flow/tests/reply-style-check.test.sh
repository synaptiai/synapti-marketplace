# Tests for hooks/scripts/reply-style-check.sh (issue #172).
#
# Contract: a Stop hook reads the final assistant text — not tool calls, not
# their output — and warns on a short list of literal constructions. It never
# blocks, and it is off unless the project opts in.
#
# The design constraint worth holding onto is that a false positive here is
# worse than the prose it guards against: a warning on every reply teaches the
# reader to ignore warnings. So roughly half of these assertions are about what
# must NOT be flagged.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"; _flow_assert_pass "SKIP: jq not installed"; return 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"; _flow_assert_pass "SKIP: python3 not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/reply-style-check.sh"

RS_CLEANUP=()
_rs_cleanup() {
  local p
  for p in "${RS_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done
}
trap _rs_cleanup EXIT

RS_BASE=$(mktemp -d -t flow-replystyle.XXXXXX 2>/dev/null) || RS_BASE=""
if [ -z "$RS_BASE" ]; then
  _flow_test_begin "scratch dir"; _flow_assert_fail "mktemp failed"; return 0
fi
RS_CLEANUP+=("$RS_BASE")

# _rs_project <settings-json> -> prints a project dir with those flow settings
_rs_project() {
  local d
  d=$(mktemp -d -p "$RS_BASE" 2>/dev/null) || d=$(mktemp -d "$RS_BASE/p.XXXXXX")
  mkdir -p "$d/.claude"
  [ -n "$1" ] && printf '%s' "$1" > "$d/.claude/settings.flow.json"
  printf '%s' "$d"
}

# _rs_transcript <text> [more text...] -> prints a transcript path whose last
# assistant record carries the final argument.
_rs_transcript() {
  local f t
  f=$(mktemp "$RS_BASE/t.XXXXXX")
  for t in "$@"; do
    python3 -c '
import json,sys
print(json.dumps({"type":"assistant","message":{"role":"assistant",
      "content":[{"type":"text","text":sys.argv[1]}]}}))' "$t" >> "$f"
  done
  printf '%s' "$f"
}

# _rs_run <project> <transcript> -> sets RS_OUT (the hook stderr) and RS_RC.
# Not a command substitution: that runs in a subshell, so an exit code assigned
# inside it never reaches the caller — which is exactly how the first version of
# this helper aborted the file under `set -u`.
RS_OUT=""
RS_RC=0
_rs_run() {
  local errf="$RS_BASE/stderr.$$"
  ( cd "$1" && printf '{"transcript_path":"%s","session_id":"s1"}' "$2" \
    | bash "$HOOK" >/dev/null 2>"$errf" )
  RS_RC=$?
  RS_OUT=$(cat "$errf" 2>/dev/null)
  rm -f "$errf"
}

ON='{"replyStyle":{"enabled":true}}'

# --- off by default -----------------------------------------------------------
_flow_test_begin "the check is off unless the project opts in"
P=$(_rs_project "")
T=$(_rs_transcript "Fixed in #142. The key insight is that plugins/flow/x.sh was wrong.")
_rs_run "$P" "$T"; OUT="$RS_OUT"
assert_exit 0 "$RS_RC" "exits 0"
if [ -z "$OUT" ]; then
  _flow_assert_pass "no settings file, no output"
else
  _flow_assert_fail "the hook spoke without being asked to: $OUT"
fi

P=$(_rs_project '{"replyStyle":{"enabled":false}}')
_rs_run "$P" "$T"; OUT="$RS_OUT"
if [ -z "$OUT" ]; then
  _flow_assert_pass "enabled:false stays quiet"
else
  _flow_assert_fail "enabled:false still produced output: $OUT"
fi

# --- it never blocks ----------------------------------------------------------
# A Stop hook that exits non-zero or emits a block decision keeps the agent
# working. Neither is acceptable for a style warning.
_flow_test_begin "it warns and never blocks"
P=$(_rs_project "$ON")
T=$(_rs_transcript "Fixed in #142 and the key insight is plugins/flow/x.sh")
_rs_run "$P" "$T"; OUT="$RS_OUT"
assert_exit 0 "$RS_RC" "exit 0 even when it has something to say"
STDOUT=$( cd "$P" && printf '{"transcript_path":"%s","session_id":"s1"}' "$T" | bash "$HOOK" 2>/dev/null )
# Parsed, not grepped. The findings text contains the words "nothing was
# blocked", so a substring search for "block" fails on a correct hook.
DECISION=$(printf '%s' "$STDOUT" | jq -r '.decision // "none"' 2>/dev/null)
if [ "$DECISION" = "none" ]; then
  _flow_assert_pass "no decision field — it cannot override another Stop hook"
else
  _flow_assert_fail "the hook emitted decision=$DECISION"
fi

# stderr goes to the debug log and is shown to nobody, so a warning delivered
# only that way is a warning nobody receives. The finding has to be on stdout as
# systemMessage.
_flow_test_begin "the finding is delivered where a Stop hook can be heard"
SYSMSG=$(printf '%s' "$STDOUT" | jq -r '.systemMessage // empty' 2>/dev/null)
if [ -n "$SYSMSG" ]; then
  _flow_assert_pass "systemMessage carries the finding"
else
  _flow_assert_fail "nothing on stdout: stderr alone reaches no one. stdout was: $STDOUT"
fi
assert_contains "reply-style check" "$SYSMSG" "and it is the finding text"
assert_contains "warning only" "$OUT" "and the message says so"

# --- what it catches ----------------------------------------------------------
_flow_test_begin "an issue reference is flagged"
P=$(_rs_project "$ON")
_rs_run "$P" "$(_rs_transcript "This was fixed in #142 last week.")"; OUT="$RS_OUT"
assert_contains "issue-references" "$OUT" "the construction is named"
assert_contains "#142" "$OUT" "and the text that matched is quoted"

_flow_test_begin "the not-X-but-Y contrast is flagged"
_rs_run "$P" "$(_rs_transcript "The change is not a rewrite but a precision fix.")"; OUT="$RS_OUT"
assert_contains "not-x-but-y" "$OUT" "flagged"

_flow_test_begin "staged emphasis is flagged wherever it sits in a sentence"
_rs_run "$P" "$(_rs_transcript "The key insight is that it never ran.")"; OUT="$RS_OUT"
assert_contains "staged-emphasis" "$OUT" "sentence-initial, capitalised"
_rs_run "$P" "$(_rs_transcript "Here the real reason is the ordering.")"; OUT="$RS_OUT"
assert_contains "staged-emphasis" "$OUT" "mid-sentence, lowercase"
# "problem" and "issue" are not in the noun list, because "the real problem is
# solved" is a statement of fact and no pattern tells it from the tic.
_rs_run "$P" "$(_rs_transcript "The real problem is the ordering.")"; OUT="$RS_OUT"
if printf '%s' "$OUT" | grep -q 'staged-emphasis'; then
  _flow_assert_fail "flagged a noun deliberately left out of the list"
else
  _flow_assert_pass "the ambiguous nouns are left alone, by design"
fi

_flow_test_begin "coined compounds and surface-as-a-noun are flagged"
_rs_run "$P" "$(_rs_transcript "It is a load-bearing constraint.")"; OUT="$RS_OUT"
assert_contains "gated-compounds" "$OUT" "load-bearing"
_rs_run "$P" "$(_rs_transcript "That widens the review surface considerably.")"; OUT="$RS_OUT"
assert_contains "surface-as-noun" "$OUT" "surface as a noun"

_flow_test_begin "a bare repository path is flagged"
_rs_run "$P" "$(_rs_transcript "The bug lived in plugins/flow/hooks/scripts/thing.sh for months.")"; OUT="$RS_OUT"
assert_contains "repo-paths" "$OUT" "flagged"

# --- what it must NOT catch ---------------------------------------------------
# The issue is explicit: a reply naming a path the user is being asked to open
# is not flagged. Half the value of this check is that it stays quiet.
_flow_test_begin "a path the reader is asked to open is not flagged"
_rs_run "$P" "$(_rs_transcript "Open plugins/flow/README.md to see the new requirements.")"; OUT="$RS_OUT"
if printf '%s' "$OUT" | grep -q 'repo-paths'; then
  _flow_assert_fail "flagged a path the reader was told to open: $OUT"
else
  _flow_assert_pass "an instruction to open a file is left alone"
fi
_rs_run "$P" "$(_rs_transcript "Run tests/run-all.sh and see what it says.")"; OUT="$RS_OUT"
if printf '%s' "$OUT" | grep -q 'repo-paths'; then
  _flow_assert_fail "flagged a path the reader was told to run: $OUT"
else
  _flow_assert_pass "an instruction to run a script is left alone"
fi

_flow_test_begin "code is not prose"
FENCED=$(printf 'Try this:\n\n```\ngit show #142 plugins/flow/x.sh\n```\n\nThat is all.')
_rs_run "$P" "$(_rs_transcript "$FENCED")"; OUT="$RS_OUT"
if [ -z "$OUT" ]; then
  _flow_assert_pass "a fenced code block is not scanned"
else
  _flow_assert_fail "scanned inside a code fence: $OUT"
fi
_rs_run "$P" "$(_rs_transcript 'The file `plugins/flow/x.sh` is the one.')"; OUT="$RS_OUT"
if printf '%s' "$OUT" | grep -q 'repo-paths'; then
  _flow_assert_fail "scanned inside inline code: $OUT"
else
  _flow_assert_pass "inline code is not scanned"
fi

_flow_test_begin "ordinary prose produces nothing"
_rs_run "$P" "$(_rs_transcript "Both suites pass. The hook now refuses a merge while a check is still running, and says which check it is waiting for.")"; OUT="$RS_OUT"
if [ -z "$OUT" ]; then
  _flow_assert_pass "a clean reply is silent"
else
  _flow_assert_fail "a clean reply produced warnings: $OUT"
fi

_flow_test_begin "a hash that is not an issue number is not flagged"
_rs_run "$P" "$(_rs_transcript "The colour is ##ff0000 and the anchor is page#42x.")"; OUT="$RS_OUT"
if printf '%s' "$OUT" | grep -q 'issue-references'; then
  _flow_assert_fail "flagged a hash that is not an issue reference: $OUT"
else
  _flow_assert_pass "left alone"
fi

# --- it reads the right thing -------------------------------------------------
_flow_test_begin "only the LAST assistant message is read"
T=$(_rs_transcript "An earlier turn mentioning #999 and plugins/flow/old.sh." "A clean final reply with nothing to flag.")
_rs_run "$P" "$T"; OUT="$RS_OUT"
if [ -z "$OUT" ]; then
  _flow_assert_pass "an earlier turn is not re-flagged"
else
  _flow_assert_fail "flagged an earlier turn: $OUT"
fi

_flow_test_begin "tool calls and their output are not the reply"
TOOLT=$(mktemp "$RS_BASE/tool.XXXXXX")
python3 - "$TOOLT" <<'PY'
import json,sys
p=sys.argv[1]
with open(p,"w") as f:
    f.write(json.dumps({"type":"assistant","message":{"role":"assistant","content":[
        {"type":"text","text":"Here is what I found."},
        {"type":"tool_use","id":"t1","name":"Bash","input":{"command":"grep -n '#142' plugins/flow/x.sh"}}]}})+"\n")
    f.write(json.dumps({"type":"user","message":{"role":"user","content":[
        {"type":"tool_result","tool_use_id":"t1","content":"plugins/flow/x.sh:12: #142"}]}})+"\n")
PY
_rs_run "$P" "$TOOLT"; OUT="$RS_OUT"
if [ -z "$OUT" ]; then
  _flow_assert_pass "the tool call and its result are not scanned"
else
  _flow_assert_fail "scanned a tool call or its output: $OUT"
fi

# --- configuration ------------------------------------------------------------
_flow_test_begin "the construction list is selectable"
P2=$(_rs_project '{"replyStyle":{"enabled":true,"constructions":["issue-references"]}}')
T2=$(_rs_transcript "Fixed in #142. The change is not a rewrite but a fix.")
_rs_run "$P2" "$T2"; OUT="$RS_OUT"
assert_contains "issue-references" "$OUT" "the selected construction still fires"
if printf '%s' "$OUT" | grep -q 'not-x-but-y'; then
  _flow_assert_fail "an unselected construction fired: $OUT"
else
  _flow_assert_pass "unselected constructions stay quiet"
fi

_flow_test_begin "a project can add its own pattern"
P3=$(_rs_project '{"replyStyle":{"enabled":true,"constructions":[],"extraPatterns":[{"name":"house-tic","pattern":"\\bsynergy\\b","advice":"we do not say this."}]}}')
_rs_run "$P3" "$(_rs_transcript "This creates real synergy across the team.")"; OUT="$RS_OUT"
assert_contains "house-tic" "$OUT" "the project pattern fires"
assert_contains "we do not say this" "$OUT" "and carries its own advice"
_rs_run "$P3" "$(_rs_transcript "Fixed in #142.")"; OUT="$RS_OUT"
if printf '%s' "$OUT" | grep -q 'issue-references'; then
  _flow_assert_fail "an empty constructions list still ran the built-ins: $OUT"
else
  _flow_assert_pass "constructions:[] means only the project patterns apply"
fi

_flow_test_begin "a malformed project pattern does not take the hook down"
P4=$(_rs_project '{"replyStyle":{"enabled":true,"extraPatterns":[{"name":"broken","pattern":"([unclosed"}]}}')
_rs_run "$P4" "$(_rs_transcript "Fixed in #142.")"; OUT="$RS_OUT"
assert_exit 0 "$RS_RC" "still exits 0"
assert_contains "issue-references" "$OUT" "and the built-ins still run"

# --- degradation ---------------------------------------------------------------
_flow_test_begin "a missing or unreadable transcript is not an error"
P5=$(_rs_project "$ON")
OUT=$( cd "$P5" && printf '{"transcript_path":"%s/nope.jsonl","session_id":"s1"}' "$RS_BASE" | bash "$HOOK" 2>&1 )
assert_exit 0 "$?" "a missing transcript exits 0"
OUT=$( cd "$P5" && printf '{"session_id":"s1"}' | bash "$HOOK" 2>&1 )
assert_exit 0 "$?" "no transcript_path at all exits 0"
if [ -z "$OUT" ]; then
  _flow_assert_pass "and says nothing"
else
  _flow_assert_fail "produced output with no transcript: $OUT"
fi

_flow_test_begin "a symlinked transcript path is not followed"
REAL=$(_rs_transcript "Fixed in #142.")
LINK="$RS_BASE/link.jsonl"
ln -sf "$REAL" "$LINK"
_rs_run "$P5" "$LINK"; OUT="$RS_OUT"
assert_exit 0 "$RS_RC" "exits 0"
if [ -z "$OUT" ]; then
  _flow_assert_pass "a symlink is declined rather than read"
else
  _flow_assert_fail "followed a symlink: $OUT"
fi

# --- registered where it will run ----------------------------------------------
_flow_test_begin "the hook is registered on Stop and is executable"
HOOKS_JSON="$REPO_ROOT/plugins/flow/hooks/hooks.json"
REG=$(python3 -c "
import json
d=json.load(open('$HOOKS_JSON'))
print(sum(1 for m in d.get('hooks',{}).get('Stop',[])
          for h in m.get('hooks',[]) if 'reply-style-check.sh' in h.get('command','')))
" 2>/dev/null)
if [ "${REG:-0}" = "1" ]; then
  _flow_assert_pass "hooks.json runs it on Stop"
else
  _flow_assert_fail "reply-style-check.sh is not registered on Stop — it would never run"
fi
if [ -x "$HOOK" ]; then
  _flow_assert_pass "executable"
else
  _flow_assert_fail "not executable, so the hook runner cannot start it"
fi

# --- ordinary prose that must stay silent --------------------------------------
# Each of these was flagged by an earlier version of a pattern. They are the
# reason the patterns are narrow: a check that fires on sentences like these
# teaches the reader to ignore it, which is worse than the prose it guards
# against. Table-driven so adding a case is one line.
_flow_test_begin "ordinary technical sentences are not flagged"
PQUIET=$(_rs_project "$ON")
FP_CASES=(
  "It is not clear, but we can check the logs."
  "The result was not cached, but the second call still returned quickly."
  "Failure was not silent, but logged to stderr."
  "The key file is missing from the archive."
  "The real problem is solved now."
  "The central column is empty."
  "The attack surface is small."
  "The API surface changed in v2."
  "Widths are set on the drawing surface."
  "The wall is load-bearing."
  "The endpoint is rate-gated by the proxy."
  "The feature is flag-gated for now."
  "Docs live at https://example.com/guide/setup.md for the moment."
  "Install @scope/pkg.js from the registry."
  "The theme color is #123456 in the palette."
  "Priority #1 in the queue."
  # "Room #205" is not in this list. A hash followed by digits cannot be told
  # from an issue number without knowing what the sentence is about, and the
  # cost of missing a real issue reference is higher than the cost of one odd
  # flag on a sentence about rooms. Stated rather than quietly dropped.
  "We pinned it at 1.2.3 after the regression."
)
FP_FLAGGED=""
for CASE in "${FP_CASES[@]}"; do
  _rs_run "$PQUIET" "$(_rs_transcript "$CASE")"
  if [ -n "$RS_OUT" ]; then
    FP_FLAGGED="$FP_FLAGGED
  \"$CASE\"
$(printf '%s' "$RS_OUT" | grep -E 'line [0-9]+:' | head -2)"
  fi
done
if [ -z "$FP_FLAGGED" ]; then
  _flow_assert_pass "${#FP_CASES[@]} ordinary sentences, none flagged"
else
  _flow_assert_fail "ordinary prose was flagged:$FP_FLAGGED"
fi

_flow_test_begin "an unterminated code fence is still code"
UNTERM=$(printf 'Here is the change:\n\n```python\nx = open("plugins/flow/x.sh")\nthe key insight is wrong here')
_rs_run "$PQUIET" "$(_rs_transcript "$UNTERM")"
if [ -z "$RS_OUT" ]; then
  _flow_assert_pass "a reply ending mid-fence is not scanned as prose"
else
  _flow_assert_fail "scanned inside an unterminated fence: $RS_OUT"
fi

_flow_test_begin "line numbers survive a code block"
NUMBERED=$(printf 'First line.\n\n```\na\nb\nc\n```\n\nFixed in #142.')
_rs_run "$PQUIET" "$(_rs_transcript "$NUMBERED")"
if printf '%s' "$RS_OUT" | grep -q 'line 9:'; then
  _flow_assert_pass "the reported line number points at the real line"
else
  _flow_assert_fail "expected the match on line 9; got: $(printf '%s' "$RS_OUT" | grep -E 'line [0-9]+:' | head -1)"
fi

_flow_test_begin "a pathological project pattern cannot hang the stop"
PSLOW=$(_rs_project '{"replyStyle":{"enabled":true,"constructions":[],"extraPatterns":[{"name":"redos","pattern":"(x+x+)+y"}]}}')
LONG=$(awk 'BEGIN { s=""; while (length(s) < 200) s = s "x"; print s "z" }')
RS_START=$(date +%s)
_rs_run "$PSLOW" "$(_rs_transcript "$LONG")"
RS_ELAPSED=$(( $(date +%s) - RS_START ))
assert_exit 0 "$RS_RC" "still exits 0"
if [ "$RS_ELAPSED" -le 20 ]; then
  _flow_assert_pass "returned in ${RS_ELAPSED}s — the watchdog bounds it"
else
  _flow_assert_fail "took ${RS_ELAPSED}s; a project regex can hang every stop"
fi

_flow_test_begin "a non-list constructions value narrows to nothing, never to everything"
PBAD=$(_rs_project '{"replyStyle":{"enabled":true,"constructions":"issue-references"}}')
_rs_run "$PBAD" "$(_rs_transcript "Fixed in #142 and the review surface grew.")"
assert_exit 0 "$RS_RC" "exits 0"
if printf '%s' "$RS_OUT" | grep -q 'line [0-9]*: '; then
  _flow_assert_fail "a malformed config enabled the checks instead of skipping them: $RS_OUT"
else
  _flow_assert_pass "a malformed config skips rather than falling open"
fi

_flow_test_begin "an unknown construction name is reported, not silently ignored"
PUNK=$(_rs_project '{"replyStyle":{"enabled":true,"constructions":["issue-refs"]}}')
_rs_run "$PUNK" "$(_rs_transcript "Fixed in #142.")"
assert_contains "names nothing known" "$RS_OUT" "the typo is named"

_flow_test_begin "a subagent reply is not the reply the user sees"
SIDE=$(mktemp "$RS_BASE/side.XXXXXX")
python3 - "$SIDE" <<'PY'
import json,sys
with open(sys.argv[1],"w") as f:
    f.write(json.dumps({"type":"assistant","isSidechain":True,"message":{"role":"assistant",
        "content":[{"type":"text","text":"Subagent says fixed in #142 in plugins/flow/x.sh"}]}})+"\n")
    f.write(json.dumps({"type":"assistant","message":{"role":"assistant",
        "content":[{"type":"text","text":"A clean final reply."}]}})+"\n")
PY
_rs_run "$PQUIET" "$SIDE"
if [ -z "$RS_OUT" ]; then
  _flow_assert_pass "a sidechain record is skipped"
else
  _flow_assert_fail "scanned a subagent reply: $RS_OUT"
fi
