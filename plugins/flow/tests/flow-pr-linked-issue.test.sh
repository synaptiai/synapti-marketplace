# Tests for plugins/flow/bin/flow-pr-linked-issue.sh.
#
# Contract (issue #212; .decisions/issue-212.md § Phase 4 self-review, round 3):
#   - The issue a pull request is linked to is one GitHub lists in the pull
#     request's closingIssuesReferences, in the same repository. Text in the
#     body is never parsed, so `hotfix #210`, a quoted `Closes #12` or an issue
#     mentioned before the closing keyword cannot pick the journal.
#   - When several issues in the repository are listed, the lowest number is
#     printed and a NOTE on stderr names them all, so every call site agrees.
#   - No listed issue prints nothing and exits 0; a gh failure exits 2 with
#     nothing on stdout, so a caller cannot mistake it for "no issue".
#
# Expected values come from the fixtures, which are `gh pr view --json
# closingIssuesReferences` output for PR #228 and PR #185 of this repository
# (captured 2026-09-16), read by hand; none is taken from the script's output.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-pr-linked-issue.sh"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/pr-linked-issue"

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed (the gh stub applies --jq with it)"
  return 0
fi

FPL_DIR=$(mktemp -d -t flow-pr-linked-issue.tests.XXXXXX 2>/dev/null)
if [ -z "$FPL_DIR" ] || [ ! -d "$FPL_DIR" ]; then
  _flow_test_begin "mktemp prerequisite"
  _flow_assert_fail "mktemp -d failed"
  return 0
fi
trap 'rm -rf "$FPL_DIR"' EXIT

# The stub applies --jq the way gh does, to the JSON in $STUB_JSON_FILE, and
# logs its arguments so the tests can see which repository was asked.
mkdir -p "$FPL_DIR/bin"
cat > "$FPL_DIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
[ "${STUB_FAIL:-0}" = 1 ] && { echo "HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "pr view") ;;
  *) exit 1 ;;
esac
FILTER=""
while [ $# -gt 0 ]; do
  [ "$1" = "--jq" ] && FILTER="$2"
  shift
done
[ -n "${STUB_RAW+x}" ] && { printf '%s\n' "$STUB_RAW"; exit 0; }
[ -n "$FILTER" ] || { cat "$STUB_JSON_FILE"; exit 0; }
jq -r "$FILTER" "$STUB_JSON_FILE"
STUB
chmod +x "$FPL_DIR/bin/gh"

# _linked <json-file> <args...> — runs the helper; sets OUT, ERR, CODE, LOG.
_linked() {
  local json="$1"; shift
  : > "$FPL_DIR/gh.log"
  PATH="$FPL_DIR/bin:$PATH" STUB_LOG="$FPL_DIR/gh.log" STUB_JSON_FILE="$json" \
    "$HELPER" "$@" > "$FPL_DIR/out" 2> "$FPL_DIR/err"
  CODE=$?
  OUT=$(cat "$FPL_DIR/out")
  ERR=$(cat "$FPL_DIR/err")
  LOG=$(cat "$FPL_DIR/gh.log")
}

_json() {
  printf '%s' "$2" > "$FPL_DIR/$1.json"
  printf '%s' "$FPL_DIR/$1.json"
}

_ref() { # <owner> <name> <number>
  printf '{"number":%s,"repository":{"name":"%s","owner":{"login":"%s"}}}' "$3" "$2" "$1"
}

_flow_test_begin "real input: PR #228 closes #199"
_linked "$FIXTURES/pr-228.json" --pr 228 --repo synaptiai/synapti-marketplace
assert_exit 0 "$CODE" "exit 0"
assert_equal "199" "$OUT" "prints 199, the one issue the fixture lists"
assert_contains "--repo synaptiai/synapti-marketplace" "$LOG" "asks gh about the given repository"
assert_contains "closingIssuesReferences" "$LOG" "reads GitHub's closing references, not the body"
assert_not_contains "body" "$LOG" "never reads the body"

_flow_test_begin "real input: PR #185 closes three issues; the lowest is printed and all are named"
# The body of PR #185 lists them as #177, #130, #175; GitHub returns 130,175,177.
_linked "$FIXTURES/pr-185.json" --pr 185 --repo synaptiai/synapti-marketplace
assert_exit 0 "$CODE" "exit 0"
assert_equal "130" "$OUT" "prints 130"
assert_contains "130, 175, 177" "$ERR" "the NOTE names every closing issue"

_flow_test_begin "the lowest number wins whatever order GitHub returns"
J=$(_json unordered "{\"closingIssuesReferences\":[$(_ref o r 42),$(_ref o r 9),$(_ref o r 17)]}")
_linked "$J" --pr 7 --repo o/r
assert_equal "9" "$OUT" "9, not the first-listed 42"

_flow_test_begin "issues in another repository are not this repository's journal"
J=$(_json other "{\"closingIssuesReferences\":[$(_ref other r 3)]}")
_linked "$J" --pr 7 --repo o/r
assert_exit 0 "$CODE" "exit 0"
assert_equal "" "$OUT" "prints nothing"
J=$(_json mixed "{\"closingIssuesReferences\":[$(_ref other r 3),$(_ref o r 12)]}")
_linked "$J" --pr 7 --repo o/r
assert_equal "12" "$OUT" "the other repository's lower #3 is skipped"
J=$(_json prefix "{\"closingIssuesReferences\":[$(_ref o r-fork 3),$(_ref xo r 4),$(_ref o r 12)]}")
_linked "$J" --pr 7 --repo o/r
assert_equal "12" "$OUT" "o/r-fork and xo/r are not o/r"

_flow_test_begin "the repository comparison ignores letter case"
_linked "$FIXTURES/pr-228.json" --pr 228 --repo SynaptiAI/Synapti-Marketplace
assert_equal "199" "$OUT" "SynaptiAI/Synapti-Marketplace names the same repository"
J=$(_json cased "{\"closingIssuesReferences\":[$(_ref Octo-Org Repo 5)]}")
_linked "$J" --pr 7 --repo octo-org/repo
assert_equal "5" "$OUT" "GitHub's Octo-Org/Repo matches --repo octo-org/repo"

_flow_test_begin "no closing issue prints nothing and exits 0"
J=$(_json empty '{"closingIssuesReferences":[]}')
_linked "$J" --pr 7 --repo o/r
assert_exit 0 "$CODE" "exit 0"
assert_equal "" "$OUT" "prints nothing"
assert_equal "" "$ERR" "no NOTE"

_flow_test_begin "a gh failure is exit 2 with nothing on stdout"
: > "$FPL_DIR/gh.log"
PATH="$FPL_DIR/bin:$PATH" STUB_LOG="$FPL_DIR/gh.log" STUB_FAIL=1 STUB_JSON_FILE="$FIXTURES/pr-228.json" \
  "$HELPER" --pr 228 --repo synaptiai/synapti-marketplace > "$FPL_DIR/out" 2> "$FPL_DIR/err"
CODE=$?
assert_exit 2 "$CODE" "exit 2"
assert_equal "" "$(cat "$FPL_DIR/out")" "nothing on stdout"
assert_contains "228" "$(cat "$FPL_DIR/err")" "the error names the pull request"

_flow_test_begin "a result that is not a list of numbers is exit 2, never an issue number"
# The filter is the only thing shaping this value; a gh or jq change that makes
# it something else must not be recorded as an issue.
for RAW in '12,x' 'null' '{"number":12}' '12 13'; do
  : > "$FPL_DIR/gh.log"
  PATH="$FPL_DIR/bin:$PATH" STUB_LOG="$FPL_DIR/gh.log" STUB_RAW="$RAW" STUB_JSON_FILE="$FIXTURES/pr-228.json" \
    "$HELPER" --pr 7 --repo o/r > "$FPL_DIR/out" 2> "$FPL_DIR/err"
  CODE=$?
  assert_exit 2 "$CODE" "a result of '$RAW' is an infrastructure error"
  assert_equal "" "$(cat "$FPL_DIR/out")" "nothing on stdout for '$RAW'"
done

_flow_test_begin "a pull request with no closingIssuesReferences field fails closed"
for JSON in '{}' '{"closingIssuesReferences":null}'; do
  J=$(_json nofield "$JSON")
  _linked "$J" --pr 7 --repo o/r
  assert_exit 2 "$CODE" "$JSON is an infrastructure error, not 'no issue'"
  assert_equal "" "$OUT" "nothing on stdout for $JSON"
done

_flow_test_begin "input validation"
for BAD in '' 0 07 7a -1 '{N}'; do
  _linked "$FIXTURES/pr-228.json" --pr "$BAD" --repo o/r
  assert_exit 1 "$CODE" "--pr '$BAD' refused"
  assert_equal "" "$LOG" "gh not called for --pr '$BAD'"
done
for BAD in '' o 'o/r/x' 'o/r"' 'o /r' '/r' 'o/'; do
  _linked "$FIXTURES/pr-228.json" --pr 7 --repo "$BAD"
  assert_exit 1 "$CODE" "--repo '$BAD' refused"
  assert_equal "" "$LOG" "gh not called for --repo '$BAD'"
done
_linked "$FIXTURES/pr-228.json" --pr 7
assert_exit 1 "$CODE" "--repo is required"
_linked "$FIXTURES/pr-228.json" --repo o/r
assert_exit 1 "$CODE" "--pr is required"
_linked "$FIXTURES/pr-228.json" --pr 7 --repo o/r --bogus
assert_exit 1 "$CODE" "an unknown flag is refused"
