# Tests that every inline-`!` block in every flow command parses on Windows
# under Git Bash (issue #130).
#
# Claude Code hands an inline `!` block to `bash -c` as one string. On Windows
# the executor mangles `#` comment handling, and an apostrophe that bash would
# have ignored inside a comment becomes a live quote character. A comment line
# carrying an ODD number of apostrophes therefore opens a quote that never
# closes, and the whole block dies with "unexpected EOF while looking for
# matching '" before any work starts. That is what made `/flow:review` abort on
# every run under Git Bash.
#
# The property is per comment line, not per block:
#
#   - An odd count on a comment line is the defect. The quote runs past the end
#     of the line and swallows whatever follows.
#   - An even count on a comment line is harmless. `grep -c '.'` inside a
#     comment opens and closes on that line, so only comment text is consumed.
#   - Apostrophes in CODE are none of this check's business. `echo "don't"` is
#     ordinary bash, and an earlier version of this test measured whole-block
#     quote parity instead, which flagged that as a defect and — because it read
#     only the span between two markers — missed three real defects in the same
#     file, in a block that runs earlier.
#
# Scope is every ```! fence in every plugins/flow/commands/*.md. Issue #130
# named one block in one file; the same defect was in sixteen blocks across nine
# files, which is why this scans rather than checking a known list.

CMD_DIR="$REPO_ROOT/plugins/flow/commands"

RGATE_CLEANUP=()
_rgate_cleanup() {
  local p
  for p in "${RGATE_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done
}
trap _rgate_cleanup EXIT

# _rgate_scan <file> — prints one "<line-number>:<text>" per offending comment
# line, and nothing when the file is clean. Also counts the blocks it looked at
# on stderr-free stdout via the BLOCKS= line, so a scan that reached nothing
# cannot read as a clean scan.
_rgate_scan() {
  awk '
    /^[[:space:]]*```!$/ { inblock = 1; blocks++; next }
    /^[[:space:]]*```$/  { inblock = 0; next }
    inblock && /^[[:space:]]*#/ {
      n = gsub(/'"'"'/, "&")
      if (n % 2 == 1) printf "%d:%s\n", FNR, $0
    }
    END { printf "BLOCKS=%d\n", blocks + 0 }
  ' "$1"
}

_flow_test_begin "command files are present to scan"
CMD_FILES=$(find "$CMD_DIR" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
CMD_COUNT=$(printf '%s\n' "$CMD_FILES" | grep -c . || true)
[ -z "$CMD_COUNT" ] && CMD_COUNT=0
if [ "$CMD_COUNT" -ge 10 ]; then
  _flow_assert_pass "$CMD_COUNT command files found"
else
  _flow_assert_fail "only $CMD_COUNT command files found under $CMD_DIR — the scan below would be reporting on almost nothing"
fi

# --- The property, across every block -----------------------------------------
_flow_test_begin "no inline-! comment line carries an odd number of apostrophes"
OFFENDERS=""
TOTAL_BLOCKS=0
for f in $CMD_FILES; do
  OUT=$(_rgate_scan "$f")
  FILE_BLOCKS=$(printf '%s\n' "$OUT" | sed -n 's/^BLOCKS=//p')
  TOTAL_BLOCKS=$((TOTAL_BLOCKS + ${FILE_BLOCKS:-0}))
  HITS=$(printf '%s\n' "$OUT" | grep -v '^BLOCKS=' | grep . || true)
  if [ -n "$HITS" ]; then
    OFFENDERS="$OFFENDERS
${f#"$REPO_ROOT"/}:
$HITS"
  fi
done

if [ -z "$OFFENDERS" ]; then
  _flow_assert_pass "clean across $TOTAL_BLOCKS inline-! blocks in $CMD_COUNT files"
else
  _flow_assert_fail "comment lines with an unpaired apostrophe (each one kills its block on the Windows executor):$OFFENDERS"
fi

# A scan that found no blocks would report the same clean result as a scan that
# found many. Pin the floor: issue #130 counted the blocks in review.md alone,
# and the sweep that fixed it covered sixteen across nine files.
_flow_test_begin "the scan actually reached the blocks"
if [ "$TOTAL_BLOCKS" -ge 40 ]; then
  _flow_assert_pass "$TOTAL_BLOCKS inline-! blocks examined"
else
  _flow_assert_fail "only $TOTAL_BLOCKS inline-! blocks examined — the extraction no longer matches the fences, so the result above means nothing"
fi

# --- Every block still parses -------------------------------------------------
_flow_test_begin "every inline-! block passes bash -n"
PARSE_FAILS=""
BLOCK_TMP=$(mktemp -t review-gate-block.XXXXXX 2>/dev/null) || BLOCK_TMP=""
if [ -z "$BLOCK_TMP" ]; then
  _flow_assert_fail "mktemp failed; cannot extract a block to parse"
else
  RGATE_CLEANUP+=("$BLOCK_TMP")
  for f in $CMD_FILES; do
    IDX=0
    while :; do
      IDX=$((IDX + 1))
      awk -v want="$IDX" '
        /^[[:space:]]*```!$/ { n++; if (n == want) { inb = 1; next } }
        /^[[:space:]]*```$/  { if (inb) exit; next }
        inb { print }
      ' "$f" > "$BLOCK_TMP"
      [ -s "$BLOCK_TMP" ] || break
      if ! bash -n "$BLOCK_TMP" 2>/dev/null; then
        PARSE_FAILS="$PARSE_FAILS
${f#"$REPO_ROOT"/} block $IDX: $(bash -n "$BLOCK_TMP" 2>&1 | head -2)"
      fi
    done
  done
  if [ -z "$PARSE_FAILS" ]; then
    _flow_assert_pass "all blocks parse"
  else
    _flow_assert_fail "blocks that do not parse:$PARSE_FAILS"
  fi
fi

# --- Mutant that must fire ----------------------------------------------------
# A check that can only confirm is not a check. Feed the scanner a block that
# reintroduces the reported defect and require it to be found.
_flow_test_begin "the scan catches an apostrophe reintroduced in a comment"
MUTANT=$(mktemp -t review-gate-mutant.XXXXXX 2>/dev/null) || MUTANT=""
if [ -z "$MUTANT" ]; then
  _flow_assert_fail "mktemp failed; cannot build the mutant"
else
  RGATE_CLEANUP+=("$MUTANT")
  {
    printf '%s\n' '```!'
    printf '%s\n' "# this comment reintroduces the defect: it is the pin of the user"
    printf '%s\n' "# and this one is the real problem, because it's unpaired"
    printf '%s\n' 'echo ok'
    printf '%s\n' '```'
  } > "$MUTANT"
  M_HITS=$(_rgate_scan "$MUTANT" | grep -v '^BLOCKS=' | grep -c . || true)
  if [ "${M_HITS:-0}" -eq 1 ]; then
    _flow_assert_pass "the one unpaired comment line is found, and the paired one is not"
  else
    _flow_assert_fail "expected exactly 1 offending line in the mutant, found ${M_HITS:-0} — the scan cannot detect the defect it exists for"
  fi
fi

# --- Mutant that must NOT fire ------------------------------------------------
# The counterpart, and the case the earlier whole-block parity check got wrong:
# apostrophes in code, and balanced pairs inside a comment, are ordinary bash
# and must not be flagged.
_flow_test_begin "code apostrophes and balanced comment quotes are not flagged"
BENIGN=$(mktemp -t review-gate-benign.XXXXXX 2>/dev/null) || BENIGN=""
if [ -z "$BENIGN" ]; then
  _flow_assert_fail "mktemp failed; cannot build the benign case"
else
  RGATE_CLEANUP+=("$BENIGN")
  {
    printf '%s\n' '```!'
    printf '%s\n' "# a balanced pair inside a comment closes on this line: grep -c '.'"
    printf '%s\n' 'echo "do not worry"'
    printf '%s\n' "MSG=\$(printf '%s' ok)"
    printf '%s\n' 'echo "an apostrophe in code is fine: don'"'"'t"'
    printf '%s\n' '```'
  } > "$BENIGN"
  B_HITS=$(_rgate_scan "$BENIGN" | grep -v '^BLOCKS=' | grep -c . || true)
  if [ "${B_HITS:-0}" -eq 0 ]; then
    _flow_assert_pass "ordinary code and balanced comment quotes pass"
  else
    _flow_assert_fail "flagged $B_HITS ordinary line(s) — the check is too strict for everyday edits"
  fi
fi

# --- The block issue #130 named is still covered ------------------------------
_flow_test_begin "the Path A gate block is inside the scanned set"
if grep -q '# AGENTTEAMS_GATE_BEGIN' "$CMD_DIR/review.md"; then
  _flow_assert_pass "review.md still carries the gate the issue reported"
else
  _flow_assert_fail "the AGENTTEAMS_GATE markers are gone from review.md; confirm the gate moved rather than vanished"
fi
