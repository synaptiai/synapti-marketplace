# Tests for the Path A gate block in plugins/flow/commands/review.md (issue #130).
#
# Claude Code hands an inline `!` block to `bash -c` as one string. On Windows
# under Git Bash the executor mangles `#` comment handling, and an apostrophe
# that bash would have ignored inside a comment becomes a live quote character.
# With an odd number of single quotes in the block, one quote never closes and
# the whole block dies with "unexpected EOF while looking for matching '" before
# any review work starts.
#
# The property that keeps the block portable is therefore not "it parses" — it
# parses on Linux and macOS either way. It is:
#
#   1. no `#` comment line inside the block contains an apostrophe, and
#   2. the block's total single-quote count is even.
#
# Property 2 is the one that actually matters at run time; property 1 is what a
# future editor will break first, and it is the actionable message.

GATE_FILE="$REPO_ROOT/plugins/flow/commands/review.md"

_flow_test_begin "gate block is extractable by its markers"
if [ ! -f "$GATE_FILE" ]; then
  _flow_assert_fail "review.md not found at $GATE_FILE"
  return 0 2>/dev/null || true
fi

GATE_TMP=$(mktemp -t review-gate.XXXXXX)
awk '/# AGENTTEAMS_GATE_BEGIN/,/# AGENTTEAMS_GATE_END/' "$GATE_FILE" > "$GATE_TMP"
GATE_LINES=$(wc -l < "$GATE_TMP" | tr -d ' ')
if [ "${GATE_LINES:-0}" -gt 20 ]; then
  _flow_assert_pass "extracted $GATE_LINES lines between the gate markers"
else
  _flow_assert_fail "expected the gate block to be more than 20 lines, extracted $GATE_LINES"
fi

# --- Property 1: no apostrophe inside a comment line -------------------------
# Counted across the whole block rather than checked against the five lines that
# were wrong when this was reported. A fix that rewords exactly those five and
# leaves a sixth elsewhere would pass a five-line check and still ship an odd
# quote count.
_flow_test_begin "no # comment line inside the gate block contains an apostrophe"
COMMENT_APOSTROPHES=$(grep -cE "^[[:space:]]*#.*'" "$GATE_TMP" || true)
[ -z "$COMMENT_APOSTROPHES" ] && COMMENT_APOSTROPHES=0
if [ "$COMMENT_APOSTROPHES" -eq 0 ]; then
  _flow_assert_pass "0 comment lines carry an apostrophe"
else
  _flow_assert_fail "$COMMENT_APOSTROPHES comment line(s) carry an apostrophe; the inline-! executor on Windows treats them as live quotes:
$(grep -nE "^[[:space:]]*#.*'" "$GATE_TMP")"
fi

# --- Property 2: even total single-quote count -------------------------------
# The expected value is a parity, not a number: every quote in shell code pairs
# with another, so any odd total means one is unpaired. Source: the reproduction
# in issue #130, which measured 23 and named the five comment apostrophes that
# made it odd.
_flow_test_begin "gate block has an even number of single quotes"
QUOTE_COUNT=$(grep -o "'" "$GATE_TMP" | wc -l | tr -d ' ')
[ -z "$QUOTE_COUNT" ] && QUOTE_COUNT=0
if [ $((QUOTE_COUNT % 2)) -eq 0 ]; then
  _flow_assert_pass "single-quote count is $QUOTE_COUNT (even)"
else
  _flow_assert_fail "single-quote count is $QUOTE_COUNT (odd) — one quote is unpaired, so the block dies with 'unexpected EOF' wherever # comments are not honoured"
fi

# --- The block still parses --------------------------------------------------
_flow_test_begin "gate block passes bash -n"
if bash -n "$GATE_TMP" 2>/dev/null; then
  _flow_assert_pass "bash -n exits 0"
else
  _flow_assert_fail "bash -n rejected the extracted block: $(bash -n "$GATE_TMP" 2>&1 | head -3)"
fi

# --- Mutant that must fire ---------------------------------------------------
# A check that only ever confirms is not a check. Feed the two properties a
# block that reintroduces exactly the reported defect and require both to fail
# on it. Without this, a grep that silently matched nothing would report a clean
# block forever.
_flow_test_begin "both properties fail on a block with an apostrophe in a comment"
MUTANT=$(mktemp -t review-gate-mutant.XXXXXX)
cp "$GATE_TMP" "$MUTANT"
printf '%s\n' "# this comment reintroduces the defect: it is the user's pin" >> "$MUTANT"
M_COMMENTS=$(grep -cE "^[[:space:]]*#.*'" "$MUTANT" || true)
M_QUOTES=$(grep -o "'" "$MUTANT" | wc -l | tr -d ' ')
if [ "${M_COMMENTS:-0}" -gt 0 ] && [ $((M_QUOTES % 2)) -eq 1 ]; then
  _flow_assert_pass "mutant is caught by both properties (comments=$M_COMMENTS, quotes=$M_QUOTES)"
else
  _flow_assert_fail "mutant escaped: comments=$M_COMMENTS quotes=$M_QUOTES — the properties above cannot detect the defect they exist for"
fi

# --- Mutant that must NOT fire -----------------------------------------------
# The counterpart: an ordinary edit that adds a balanced quoted string in code
# must leave both properties satisfied, or the check would block routine work.
_flow_test_begin "properties stay satisfied when a balanced quoted string is added"
BENIGN=$(mktemp -t review-gate-benign.XXXXXX)
cp "$GATE_TMP" "$BENIGN"
printf '%s\n' "AGENT_TEAMS_NOTE=\$(printf '%s' ok)" >> "$BENIGN"
B_COMMENTS=$(grep -cE "^[[:space:]]*#.*'" "$BENIGN" || true)
B_QUOTES=$(grep -o "'" "$BENIGN" | wc -l | tr -d ' ')
if [ "${B_COMMENTS:-0}" -eq 0 ] && [ $((B_QUOTES % 2)) -eq 0 ]; then
  _flow_assert_pass "benign edit passes both properties (comments=$B_COMMENTS, quotes=$B_QUOTES)"
else
  _flow_assert_fail "benign edit was flagged: comments=$B_COMMENTS quotes=$B_QUOTES — the properties are too strict for ordinary edits"
fi

rm -f "$GATE_TMP" "$MUTANT" "$BENIGN"
