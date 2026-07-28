#!/usr/bin/env bash
# Mechanical prose-clarity lint, fixture-driven. The load-bearing case is the
# carve-out: a required epistemic-hedge marker must never be flagged, however
# long or hedge-like the sentence it opens, because that marker is the
# evidence ledger's own mechanism for honest uncertainty, not slop.

_dossier_test_begin "prose-lint"

LINT="$(pwd)/plugins/dossier/bin/dossier-prose-lint.sh"

W=$(mktemp -d 2>/dev/null) || W="/tmp/dossier-prose-lint.$$"

lint_json() { # <path>
  "$LINT" --file "$1" --json 2>/dev/null
}
count_of() { # <json> <field>
  printf '%s' "$1" | LC_ALL=C sed -n "s/.*\"$2\":\([0-9]*\).*/\1/p" | head -1
}

# --- clean prose passes -------------------------------------------------------
C="$W/clean.md"
cat > "$C" <<'EOF'
# Test

The cache compares the meaning of a new prompt with the prompts already stored. A short sentence carries one idea.

1. Restart the service.
2. Check the logs for errors.
EOF
"$LINT" --file "$C" >/dev/null 2>&1
assert_equal "0" "$?" "clean prose exits 0"

# --- one violation per hard category, isolated --------------------------------
MK="$W/marketing.md"
printf '# Test\n\nThis seamless platform helps you. This is fine.\n' > "$MK"
J=$(lint_json "$MK")
assert_equal "1" "$(count_of "$J" marketing_adjective)" "one marketing adjective is counted"

PH="$W/phrasal.md"
printf '# Test\n\nWe need to reach out to the team about this open item.\n' > "$PH"
J=$(lint_json "$PH")
assert_equal "1" "$(count_of "$J" phrasal_verb)" "one phrasal verb is counted"

LA="$W/latinate.md"
printf '# Test\n\nPlease utilize the correct format for all requests submitted here.\n' > "$LA"
J=$(lint_json "$LA")
assert_equal "1" "$(count_of "$J" latinate_word)" "one Latinate long-form word is counted"

FH="$W/filler.md"
printf '# Test\n\nIt is important to note that this requires review before merge happens today.\n' > "$FH"
J=$(lint_json "$FH")
assert_equal "1" "$(count_of "$J" filler_hedge)" "one filler/hedge phrase is counted"
assert_equal "0" "$(count_of "$J" long_sentence)" "the filler-hedge sentence is not also flagged long"

SC="$W/semicolon.md"
printf '# Test\n\nRestart the service; then check the logs.\n' > "$SC"
J=$(lint_json "$SC")
assert_equal "1" "$(count_of "$J" semicolon)" "one semicolon is counted"

LS="$W/long-sentence.md"
printf '# Test\n\nalpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu.\n' > "$LS"
J=$(lint_json "$LS")
assert_equal "1" "$(count_of "$J" long_sentence)" "a 26-word flavored-mode sentence exceeds the 25-word cap"

LP="$W/long-paragraph.md"
printf '# Test\n\nWord one here. Word two here. Word three here. Word four here. Word five here. Word six here. Word seven here.\n' > "$LP"
J=$(lint_json "$LP")
assert_equal "1" "$(count_of "$J" long_paragraph)" "a seven-sentence paragraph exceeds the six-sentence cap"

# --- the carve-out: THE load-bearing test -------------------------------------
# Every required hedge marker, each opening a long sentence that also contains
# hedge-shaped language. All of it must pass clean — a hedge marker is the
# ledger's mechanism for honest uncertainty, and flagging it as slop would
# break the plugin's own epistemic-honesty contract.
CO="$W/carveout.md"
cat > "$CO" <<'EOF'
# Test

This suggests the deployment process assumes forward-only migrations and does not support automated reversal in the event of a failure partway through a rollout.

The most likely reading is that the retry budget was sized for a single region and was never revisited after the service expanded to serve requests from three additional regions.

Inferred from the absence of a rollback step: the team assumed forward-only migrations across every environment this service has ever been deployed into since launch.

Inferred: the on-call rotation has not been updated since the reorganization, based on the owner names still listed in the outdated runbook.

Unknown: whether the retry budget accounts for downstream rate limits has not been established from the sources inspected so far during this engagement.

Recommendation: revisit the retry budget once the downstream service publishes its documented rate limits for partner integrations running at scale.
EOF
"$LINT" --file "$CO" >/dev/null 2>&1
assert_equal "0" "$?" "every required hedge marker passes clean despite long, hedge-shaped sentences"
J=$(lint_json "$CO")
assert_equal "0" "$(count_of "$J" filler_hedge)" "carve-out sentences never count as filler_hedge"
assert_equal "0" "$(count_of "$J" long_sentence)" "carve-out sentences are exempt from the length cap"

# --- em-dash is always advisory, never blocking -------------------------------
# This plugin's own reference documents use em-dashes constitutively; a linter
# that blocked on them would fail this plugin's own house style on day one.
ED="$W/emdash.md"
printf '# Test\n\nThe cache compares meaning, not exact text — a small change in wording no longer causes a miss.\n' > "$ED"
"$LINT" --file "$ED" >/dev/null 2>&1
assert_equal "0" "$?" "em-dash prose exits 0 — em-dash never blocks"
J=$(lint_json "$ED")
assert_equal "1" "$(count_of "$J" em_dash)" "em-dash is still counted, as advisory"

# --- mode resolution: strict inside steps, flavored in narrative --------------
# The same 21-word sentence: over the strict 20-word cap as a numbered step,
# under the flavored 25-word cap as a narrative paragraph.
TWENTYONE="Configure every single available environment variable setting across all deployment targets before the release process starts today for every listed target."

SM="$W/strict-mode.md"
printf '# Test\n\n1. %s\n' "$TWENTYONE" > "$SM"
J=$(lint_json "$SM")
assert_equal "1" "$(count_of "$J" long_sentence)" "a 21-word numbered-step sentence exceeds the strict 20-word cap"

FM="$W/flavored-mode.md"
printf '# Test\n\n%s\n' "$TWENTYONE" > "$FM"
J=$(lint_json "$FM")
assert_equal "0" "$(count_of "$J" long_sentence)" "the same 21-word sentence as narrative prose stays under the flavored 25-word cap"

# --- a file that cannot genuinely be scanned must never read as clean --------
# Reproduced during review: an unquoted file-list loop silently dropped any
# path with a space, and an unchecked awk exit status let binary content and
# an unclosed frontmatter fence render as "0 violations" — indistinguishable
# from a file that was actually scanned and found clean.
BIN="$W/binary.md"
printf '\xff\xfe\x00\x01This seamless robust platform utilizes cutting-edge technology.\n' > "$BIN"
"$LINT" --file "$BIN" >/dev/null 2>&1
assert_equal "1" "$?" "unscannable (binary) content exits 1, never a false clean pass"
J=$(lint_json "$BIN")
assert_equal "1" "$(count_of "$J" scan_errors)" "binary content is counted as a scan error, not silently zero"

UNCLOSED="$W/unclosed-header.md"
printf -- '---\nname: test\n\nThis seamless robust platform utilizes cutting-edge technology.\n' > "$UNCLOSED"
"$LINT" --file "$UNCLOSED" >/dev/null 2>&1
assert_equal "1" "$?" "an unclosed frontmatter fence exits 1, never a false clean pass"
J=$(lint_json "$UNCLOSED")
assert_equal "1" "$(count_of "$J" scan_errors)" "the unclosed fence is counted as a scan error"

SPACED_DIR="$W/spaced dir"
mkdir -p "$SPACED_DIR"
printf '# Test\n\nThis seamless platform helps you. This is fine.\n' > "$SPACED_DIR/doc.md"
J=$(lint_json "$SPACED_DIR/doc.md")
assert_equal "0" "$(count_of "$J" scan_errors)" "a path containing a space is not treated as a scan error"
assert_equal "1" "$(count_of "$J" marketing_adjective)" "a path containing a space is still linted, not silently skipped"

EMPTY_ROOT="$W/empty-root"
mkdir -p "$EMPTY_ROOT"
"$LINT" --output-root "$EMPTY_ROOT" >/dev/null 2>&1
assert_equal "1" "$?" "an output-root with zero .md files exits 1, not a false clean pass"
J=$("$LINT" --output-root "$EMPTY_ROOT" --json 2>/dev/null)
assert_equal "0" "$(count_of "$J" files_scanned)" "zero files were actually scanned"
assert_equal "1" "$(count_of "$J" scan_errors)" "zero files scanned is itself reported as a scan error"

# --- usage error ---------------------------------------------------------------
"$LINT" --nonexistent-flag >/dev/null 2>&1
assert_equal "2" "$?" "an unknown flag exits 2"

# --- --json emits valid JSON ----------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  if lint_json "$C" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    _dossier_assert_pass "--json emits valid JSON"
  else
    _dossier_assert_fail "--json output is not valid JSON"
  fi
fi

# --- word lists stay disjoint from disclosure-gating's prohibited vocabulary --
# disclosure-gating owns claim-scope words (a truth/legal-exposure concern);
# prose-clarity owns style words. tests/prose-lint.test.sh is the mechanical
# guard that keeps a maintainer from silently re-duplicating one list into the
# other.
LINT_LISTS=$(grep -E '^(MARKETING_RE|PHRASAL_RE|LATINATE_RE)=' "$LINT")
DISCLOSURE_TERMS="secure compliant encrypted anonymous private real-time unlimited always never guaranteed fully-automated zero-downtime bank-grade enterprise-ready military-grade"
OVERLAP=""
for term in $DISCLOSURE_TERMS; do
  needle=$(printf '%s' "$term" | tr '-' ' ')
  case "$LINT_LISTS" in
    *"$needle"*|*"$term"*) OVERLAP="$OVERLAP $term" ;;
  esac
done
if [ -z "$OVERLAP" ]; then
  _dossier_assert_pass "prose-clarity's word lists share no term with disclosure-gating's prohibited vocabulary"
else
  _dossier_assert_fail "prose-clarity's word lists overlap disclosure-gating's prohibited vocabulary:$OVERLAP"
fi

rm -rf "$W" 2>/dev/null

_dossier_test_summary
