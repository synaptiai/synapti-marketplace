# Tests for plugins/flow/bin/flow-escalate.sh.
#
# Contract (from the helper's header):
#   - Six required fields: --situation, --tried, --options, --recommendation,
#     --time-sensitivity, --risk.
#   - Options are semicolon-separated, each `<n>: <text>`.
#   - Exit 0: prints formatted body to stdout.
#   - Exit 1: missing required field. Usage printed to stderr.
#   - Exit 2: invalid input (empty/malformed option, duplicate number).
#   - Output: markdown body with six bold-headed sections matching the canonical
#     shape in plugins/flow/references/escalation-format.md.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-escalate.sh"

# Six valid fields, used by happy-path assertions and as a baseline for the
# missing-field tests (drop one at a time).
ALL_ARGS=(
  --situation "Test situation"
  --tried "Tried thing A and B"
  --options "1: First option;2: Second option"
  --recommendation "Pick option 1"
  --time-sensitivity "blocking"
  --risk "Defer means service stays broken"
)

# --- Test 1: happy path — all six fields → exit 0, valid markdown body
_flow_test_begin "all six fields → exit 0, markdown body"
OUT=$("$HELPER" "${ALL_ARGS[@]}" 2>/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_contains "**Situation** — Test situation"           "$OUT" "Situation section present"
assert_contains "**What I tried** — Tried thing A and B"   "$OUT" "What I tried section present"
assert_contains "**Options**:"                             "$OUT" "Options heading present"
assert_contains "**Recommendation** — Pick option 1"       "$OUT" "Recommendation section present"
assert_contains "**Time sensitivity** — blocking"          "$OUT" "Time sensitivity section present"
assert_contains "**Risk** — Defer means service stays broken" "$OUT" "Risk section present"
# Options must be re-numbered as a Markdown numbered list.
assert_contains "1. First option"  "$OUT" "Option 1 rendered as numbered list"
assert_contains "2. Second option" "$OUT" "Option 2 rendered as numbered list"

# --- Test 2: missing each required field → exit 1
# Loop the six fields, drop each in turn, assert exit 1 + usage on stderr.
_flow_test_begin "missing required field → exit 1"
FIELDS=(--situation --tried --options --recommendation --time-sensitivity --risk)
for DROP in "${FIELDS[@]}"; do
  ARGS=()
  i=0
  while [ $i -lt "${#ALL_ARGS[@]}" ]; do
    if [ "${ALL_ARGS[$i]}" = "$DROP" ]; then
      i=$((i + 2))   # skip flag + value
      continue
    fi
    ARGS+=("${ALL_ARGS[$i]}" "${ALL_ARGS[$((i+1))]}")
    i=$((i + 2))
  done
  ERR=$("$HELPER" "${ARGS[@]}" 2>&1 >/dev/null)
  EXIT=$?
  assert_exit 1 "$EXIT" "exit 1 when $DROP missing"
  assert_contains "$DROP" "$ERR" "stderr names missing field $DROP"
done

# --- Test 3: malformed option (no `N:` prefix) → exit 2
_flow_test_begin "malformed option → exit 2"
ARGS=(
  --situation S --tried T
  --options "no-number-here"
  --recommendation R --time-sensitivity blocking --risk R
)
ERR=$("$HELPER" "${ARGS[@]}" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2 on malformed option"
assert_contains "malformed option" "$ERR" "stderr explains malformed option"

# --- Test 4: duplicate option number → exit 2
_flow_test_begin "duplicate option number → exit 2"
ARGS=(
  --situation S --tried T
  --options "1: First;1: Also first"
  --recommendation R --time-sensitivity blocking --risk R
)
ERR=$("$HELPER" "${ARGS[@]}" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2 on duplicate option number"
assert_contains "duplicate option number" "$ERR" "stderr explains duplicate"

# --- Test 5: empty options expansion → exit 2
_flow_test_begin "empty options → exit 2"
ARGS=(
  --situation S --tried T
  --options ";;"
  --recommendation R --time-sensitivity blocking --risk R
)
ERR=$("$HELPER" "${ARGS[@]}" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2 on zero-item options"
assert_contains "zero items" "$ERR" "stderr names the zero-item case"

# --- Test 6: unknown flag → exit 1
_flow_test_begin "unknown flag → exit 1"
ERR=$("$HELPER" --bogus value "${ALL_ARGS[@]}" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1 on unknown flag"
assert_contains "unknown argument" "$ERR" "stderr names the unknown flag"

# --- Test 7: -h flag → exit 0, usage on stderr
_flow_test_begin "-h prints usage and exits 0"
ERR=$("$HELPER" -h 2>&1 >/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_contains "All six fields are required" "$ERR" "usage text on stderr"
