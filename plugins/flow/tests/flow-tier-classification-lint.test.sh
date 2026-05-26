# Tests for the Tier Classification convention.
#
# Every commands/*.md MUST include a `## Tier Classification` section so
# users can see at a glance what actions the command takes and at which
# safety tier. This lint runs in CI to prevent regression — an audit
# found v3 commands missing the section.

_flow_test_begin "every commands/*.md has '## Tier Classification'"

CMD_DIR="$REPO_ROOT/plugins/flow/commands"
MISSING=$(grep -L "^## Tier Classification" "$CMD_DIR"/*.md 2>/dev/null | sed "s|$CMD_DIR/||g" | sort | tr '\n' ',' | sed 's/,$//')

if [ -z "$MISSING" ]; then
  _flow_assert_pass "all commands/*.md include the section header"
else
  _flow_assert_fail "missing in: $MISSING"
fi

_flow_test_begin "Tier Classification section appears after the command body"
# Section should not be at the top of the file (i.e., line number > 20).
# Use grep -n to get the line number rather than grep -c (which under
# pipefail concatenates with `|| echo 0` and produces non-numeric junk).

OFFENDERS=""
for f in "$CMD_DIR"/*.md; do
  LINE=$(grep -n "^## Tier Classification" "$f" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$LINE" ] && [ "$LINE" -le 20 ]; then
    OFFENDERS="${OFFENDERS}$(basename "$f"),"
  fi
done
OFFENDERS="${OFFENDERS%,}"

if [ -z "$OFFENDERS" ]; then
  _flow_assert_pass "Tier Classification appears late in each file (line > 20)"
else
  _flow_assert_fail "Tier Classification appears too early in: $OFFENDERS"
fi
