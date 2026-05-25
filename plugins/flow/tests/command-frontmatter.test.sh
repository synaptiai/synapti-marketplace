# Static lint over plugins/flow/commands/*.md.
#
# What this catches (regression-of-record from PR #103 / PR #104 review cycles):
#   - F3:  `!` block missing trailing `true` (start.md Phase 1 was the original miss)
#   - C4-*: `!` block silently exits non-zero from a trailing pipeline
#   - F2/F6: $ARGUMENTS interpolated into an `!` block without quoting/validation
#   - C1:  `allowed-tools` Bash() pattern that no body invocation actually matches
#   - Required Skills entry that doesn't resolve to a plugins/flow/skills/<name>/ dir
#   - destructive shell commands inside an `!` block (! blocks are read-only context)
#
# Approach: parse each command file once into an in-memory representation
# (frontmatter block + body + per-`!`-block bodies), then run each lint rule
# against that representation. The block extractor uses awk for portability
# (BSD/GNU awk both work).
#
# Trivial-pass guards: every lint that iterates over command files asserts a
# minimum scan count (FILE_COUNT_FLOOR). An empty COMMANDS_DIR — or a future
# refactor that silently moves command files elsewhere — would otherwise let
# a broken lint report PASS over zero work.

COMMANDS_DIR="$REPO_ROOT/plugins/flow/commands"
SKILLS_DIR="$REPO_ROOT/plugins/flow/skills"
# Floor matches the current count of command files (17 as of this writing).
# A drop below this is either a real deletion (update the floor in the same
# PR) or a path resolution bug (find and fix). Either way: fail loudly.
FILE_COUNT_FLOOR=15

# Strip bash-style quoted spans from a body of text. Used by the $ARGUMENTS
# lint to ignore safely-quoted occurrences. Removes "..." and '...' on a
# best-effort line-local basis — sed has no notion of bash escape semantics,
# so a `\"` inside a "..." span will close the span early. That's a
# conservative false-positive (flags too much), never a false-negative
# (misses unsafe forms), which is the right tradeoff for a lint.
_strip_quoted() {
  sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g"
}

# --- Test 1: every `!` block ends with `true`, and no triple-backtick fences
# appear inside an `!` block. The trailing-`true` check is the F3 regression
# guard; the no-nested-fence assertion guarantees the awk extractor's
# correctness (a `!` block containing a literal ``` line would silently
# close the block early, hiding everything after it).
_flow_test_begin "every ! block ends with explicit 'true' and contains no nested fences"
PASS=1
SCANNED=0
BLOCK_COUNT=0
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  SCANNED=$((SCANNED + 1))
  # awk extracts ! blocks; emits one block per "BLOCK_START" / "BLOCK_END"
  # delimited section. The block-index is appended so we can name failures.
  BLOCKS=$(awk '
    /^```!$/ { in_block=1; idx++; print "BLOCK_START " idx; next }
    /^```$/ && in_block { in_block=0; print "BLOCK_END " idx; next }
    in_block { print }
  ' "$FILE")
  [ -z "$BLOCKS" ] && continue

  # Walk the awk output: for each block, capture lines and check the last
  # non-blank line equals `true`. Also flag any line inside the block that
  # is itself a triple-backtick fence (a nested fence would have terminated
  # the awk extraction prematurely, but if the source markdown ever
  # introduces one, we want a clear failure).
  CURRENT_BLOCK=""
  CURRENT_IDX=""
  while IFS= read -r LINE; do
    case "$LINE" in
      "BLOCK_START "*)
        CURRENT_BLOCK=""
        CURRENT_IDX="${LINE#BLOCK_START }"
        BLOCK_COUNT=$((BLOCK_COUNT + 1))
        ;;
      "BLOCK_END "*)
        # Strip trailing blank lines; check last is `true`.
        LAST_NONBLANK=$(printf '%s' "$CURRENT_BLOCK" | awk 'NF { last=$0 } END { print last }')
        if [ "$LAST_NONBLANK" != "true" ]; then
          _flow_assert_fail "$CMD.md ! block #$CURRENT_IDX last line is '$LAST_NONBLANK', expected 'true'"
          PASS=0
        fi
        CURRENT_BLOCK=""
        ;;
      '```'*)
        # A bare ``` inside a captured block can only mean a nested fence
        # the awk pattern didn't recognize (the extractor swallowed it as
        # block content rather than a terminator — possible only via 4+
        # backticks or trailing whitespace on the closing fence). Flag.
        _flow_assert_fail "$CMD.md ! block #$CURRENT_IDX contains a nested fence: $LINE"
        PASS=0
        ;;
      *)
        if [ -z "$CURRENT_BLOCK" ]; then
          CURRENT_BLOCK="$LINE"
        else
          CURRENT_BLOCK=$(printf '%s\n%s' "$CURRENT_BLOCK" "$LINE")
        fi
        ;;
    esac
  done <<< "$BLOCKS"
done
# Trivial-pass guard: assert we actually scanned the expected number of
# files. An empty COMMANDS_DIR or a path-resolution bug would otherwise
# silently produce a green PASS over zero work (T1).
if [ "$SCANNED" -lt "$FILE_COUNT_FLOOR" ]; then
  _flow_assert_fail "scanned only $SCANNED command files (floor=$FILE_COUNT_FLOOR); COMMANDS_DIR=$COMMANDS_DIR"
  PASS=0
fi
[ "$PASS" = "1" ] && _flow_assert_pass "$BLOCK_COUNT ! blocks across $SCANNED commands end with 'true' (no nested fences)"

# --- Test 2: no destructive commands inside ! blocks
# ! blocks are read-only context gatherers. The lint flags destructive verbs
# as a structural reminder — a commented `# git push` is still flagged so the
# reader is forced to consciously remove it (or refactor it out of the !
# block) before merge. Word boundaries on the left side prevent false hits
# on substring matches like `magit push` or `/path/to/git push`.
_flow_test_begin "no destructive verbs inside ! blocks"
PASS=1
# Each alternative is left-anchored with `(^|[^[:alnum:]_/-])` so a verb only
# matches when it starts a token (the existing right side, e.g. `[[:space:]]+`,
# already enforces a right boundary).
LB='(^|[^[:alnum:]_/-])'
PROHIBITED="${LB}(rm[[:space:]]+-(rf|fr|f|r[a-z]*)|git[[:space:]]+push|git[[:space:]]+reset[[:space:]]+--hard|gh[[:space:]]+pr[[:space:]]+merge|gh[[:space:]]+pr[[:space:]]+close|gh[[:space:]]+release[[:space:]]+create|gh[[:space:]]+release[[:space:]]+delete|git[[:space:]]+tag[[:space:]]+-d|git[[:space:]]+branch[[:space:]]+-D|git[[:space:]]+stash[[:space:]]+drop|find[[:space:]]+[^|]*-delete|xargs[[:space:]]+rm)"
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  # Per-file scratch (replaces predictable /tmp/$$ from earlier revisions —
  # S1/SV1/CV2 — which was a TOCTOU/symlink-attack vector on shared hosts).
  MATCH_TMP=$(mktemp -t flow_dest_match.XXXXXX 2>/dev/null) || {
    _flow_assert_fail "mktemp failed for $CMD.md destructive-verb scratch"
    PASS=0; continue
  }
  # Extract block bodies, strip shell comments (a `# do not run gh pr merge`
  # in documentation prose is not a destructive command), and grep.
  awk '
    /^```!$/ { in_block=1; idx++; print "BLOCK_START " idx; next }
    /^```$/ && in_block { in_block=0; print "BLOCK_END " idx; next }
    in_block { print }
  ' "$FILE" | sed -E 's/[[:space:]]*#.*$//' | grep -nE "$PROHIBITED" > "$MATCH_TMP" 2>/dev/null || true
  if [ -s "$MATCH_TMP" ]; then
    HITS=$(cat "$MATCH_TMP")
    _flow_assert_fail "$CMD.md contains destructive verb inside ! block: $HITS"
    PASS=0
  fi
  rm -f "$MATCH_TMP"
done
[ "$PASS" = "1" ] && _flow_assert_pass "no destructive verbs in any ! block"

# --- Test 3: $ARGUMENTS inside ! blocks is quoted
# Acceptable forms inside an ! block:
#   - "$ARGUMENTS"           (double-quoted scalar)
#   - "${ARGUMENTS}"         (double-quoted, braces, no operator)
#   - copied to a local then expanded: _RAW="$ARGUMENTS"; ARG1="${_RAW%% *}"
# Unacceptable here: any unquoted form including bare $ARGUMENTS or ${ARGUMENTS}.
# The previous "char-before" regex over-accepted ${ARGUMENTS} because `$` was
# in the negative class to permit `${...}` braces — but unquoted braces are
# still word-split-vulnerable. Fix: strip all quoted spans first, then flag
# any remaining $ARGUMENTS form.
#
# NOTE: this test only guards QUOTING (word-split safety). It does NOT catch
# bash parameter-expansion applied to $ARGUMENTS (e.g. "${ARGUMENTS%% *}"),
# which is quoted-and-safe but still BROKEN because Claude Code never
# substitutes it (see Test 6).
_flow_test_begin "\$ARGUMENTS in ! blocks is inside double quotes"
PASS=1
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  BODY=$(awk '
    /^```!$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0; next }
    in_block { print }
  ' "$FILE")
  [ -z "$BODY" ] && continue
  # Strip "..." and '...' spans line-locally. What remains is everything
  # NOT inside quotes (plus comments — those aren't shell-execution-relevant
  # but if a comment contains a `$ARGUMENTS` it's just confusing, not a
  # security issue, so we strip them too).
  STRIPPED=$(printf '%s\n' "$BODY" | sed -E 's/[[:space:]]*#.*$//' | _strip_quoted)
  # After stripping, ANY occurrence of $ARGUMENTS or ${ARGUMENTS is unsafe.
  BAD=$(printf '%s\n' "$STRIPPED" | grep -nE '\$\{?ARGUMENTS' || true)
  if [ -n "$BAD" ]; then
    _flow_assert_fail "$CMD.md has unquoted \$ARGUMENTS reference in ! block: $BAD"
    PASS=0
  fi
done
[ "$PASS" = "1" ] && _flow_assert_pass "all \$ARGUMENTS references in ! blocks are double-quoted"

# --- Test 4: Required Skills entries resolve to plugins/flow/skills/<name>/
# Each command's "## Required Skills" section lists `- skill-name` bullets;
# every name must correspond to an existing skills/ directory.
_flow_test_begin "Required Skills entries resolve to skills/ directories"
PASS=1
SKILLS_SCANNED=0
RESOLVED_COUNT=0
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  # Extract the Required Skills section: from "## Required Skills" up to the
  # next "##" heading. Then grab the leading-token of each "- name" or
  # "- `name`" bullet line.
  SKILLS=$(awk '
    /^## Required Skills/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section && /^- / { print }
  ' "$FILE" | sed -E 's/^- *`?([a-zA-Z0-9_-]+)`?.*/\1/' | grep -v '^_' | grep -v '^$')
  [ -z "$SKILLS" ] && continue
  SKILLS_SCANNED=$((SKILLS_SCANNED + 1))
  while IFS= read -r SKILL; do
    [ -z "$SKILL" ] && continue
    RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
    # Permit two forms: `skills/<skill>/` or `skills/<skill>/SKILL.md`.
    if [ ! -d "$SKILLS_DIR/$SKILL" ] && [ ! -f "$SKILLS_DIR/$SKILL/SKILL.md" ]; then
      _flow_assert_fail "$CMD.md Required Skills references '$SKILL' but $SKILLS_DIR/$SKILL/ does not exist"
      PASS=0
    fi
  done <<< "$SKILLS"
done
# Sanity floor — every flow command has a Required Skills section.
if [ "$SKILLS_SCANNED" -lt 5 ]; then
  _flow_assert_fail "only $SKILLS_SCANNED commands had a Required Skills section (expected most of them)"
  PASS=0
fi
[ "$PASS" = "1" ] && _flow_assert_pass "$RESOLVED_COUNT Required Skills references across $SKILLS_SCANNED commands resolve"

# --- Test 5: allowed-tools Bash(...) prefix-validation logic works
# Currently NO flow command file uses prefix-restricted `Bash(prefix:*)`
# patterns — they all declare full `Bash` access. The previous form of this
# test iterated over zero patterns and trivially passed (F6/TV6). Instead,
# exercise the logic against synthetic fixtures: one frontmatter where the
# prefix has a matching body invocation (must PASS), one where it doesn't
# (must FAIL the inner check).
#
# When real `Bash(prefix:*)` patterns are introduced into the plugin, the
# real-files sweep below is appended; for now the fixture is the test of record.
_flow_test_begin "allowed-tools Bash() prefix check (synthetic fixture)"
PASS=1

_check_pattern_in_body() {
  local front="$1" body="$2"
  local pattern prefix check
  printf '%s\n' "$front" | grep -oE 'Bash\([^)]+\)' | sed -E 's/^Bash\((.*)\)$/\1/' | while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    prefix="${pattern%:\*}"
    case "$prefix" in ""|"*") continue ;; esac
    check="${prefix#bash }"
    # `--` protects against a leading-dash check string (SV2: grep -qF
    # would otherwise misinterpret a `-foo` pattern as a flag).
    if printf '%s' "$body" | grep -qF -- "$check"; then
      printf 'MATCH=%s\n' "$pattern"
    else
      printf 'MISS=%s|%s\n' "$pattern" "$check"
    fi
  done
}

# Fixture A: pattern HAS matching invocation → expected MATCH.
RESULT=$(_check_pattern_in_body \
  'allowed-tools: Bash(plugins/flow/bin/cascade-resolve.sh:*)' \
  '... and then we run plugins/flow/bin/cascade-resolve.sh --default ... here')
assert_contains "MATCH=plugins/flow/bin/cascade-resolve.sh:*" "$RESULT" "fixture A: real prefix matches body"

# Fixture B: pattern has NO matching invocation → expected MISS.
RESULT=$(_check_pattern_in_body \
  'allowed-tools: Bash(plugins/flow/bin/no-such-helper.sh:*)' \
  '... body talks about something else entirely ...')
assert_contains "MISS=plugins/flow/bin/no-such-helper.sh:*" "$RESULT" "fixture B: orphan prefix is flagged"

# Fixture C: ${CLAUDE_PLUGIN_ROOT:-plugins/flow} expansion in pattern.
RESULT=$(_check_pattern_in_body \
  'allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/foo.sh:*)' \
  '... invokes plugins/flow/bin/foo.sh ...')
# Note: the synthetic helper doesn't expand the literal — that's the real
# linter's job. So this fixture is a MISS-by-literal, MATCH-by-expansion.
# Verify the helper at least produces an output line.
assert_match '^(MATCH|MISS)=' "$RESULT" "fixture C: helper emits a result line"

# Real-files sweep — currently a no-op (no commands declare Bash(prefix:*)),
# but the loop is structured so it activates the moment one is introduced.
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  FRONT=$(awk 'BEGIN{s=0} /^---$/{s++; if(s==1)next; if(s==2)exit} s==1{print}' "$FILE")
  BODY=$(awk 'BEGIN{s=0} /^---$/{s++; next} s>=2{print}' "$FILE")
  PATTERNS=$(printf '%s\n' "$FRONT" | grep -oE 'Bash\([^)]+\)' | sed -E 's/^Bash\((.*)\)$/\1/')
  [ -z "$PATTERNS" ] && continue
  while IFS= read -r PATTERN; do
    [ -z "$PATTERN" ] && continue
    PREFIX="${PATTERN%:\*}"
    case "$PREFIX" in ""|"*") continue ;; esac
    EXPANDED=$(printf '%s' "$PREFIX" | sed 's|\${CLAUDE_PLUGIN_ROOT:-plugins/flow}|plugins/flow|g')
    CHECK="${EXPANDED#bash }"
    if ! printf '%s' "$BODY" | grep -qF -- "$CHECK"; then
      _flow_assert_fail "$CMD.md allowed-tools 'Bash($PATTERN)' has no matching body invocation (looked for '$CHECK')"
      PASS=0
    fi
  done <<< "$PATTERNS"
done
[ "$PASS" = "1" ] && _flow_assert_pass "allowed-tools Bash() prefix linter handles synthetic fixtures correctly"

# --- Test 6: no bash parameter-expansion applied directly to $ARGUMENTS.
# Claude Code's slash-command preprocessor textually substitutes
# bare $ARGUMENTS and ${ARGUMENTS} (no operator), but NOT parameter-expansion
# forms like ${ARGUMENTS%% *}, ${ARGUMENTS#foo}, ${ARGUMENTS:0:3}. The bash
# interpreter then sees an undefined ARGUMENTS var and the expansion yields
# the empty string — every downstream guard silently degrades to its no-arg
# path even when the user passed an argument.
#
# The correct pattern copies the substituted bare form into a line-local var
# first, then applies parameter-expansion to THAT var:
#   _RAW="$ARGUMENTS"        # Claude Code substitutes bare $ARGUMENTS
#   ARG1="${_RAW%% *}"       # bash now operates on a real env var
#
# This check scans RAW block bodies (NOT quote-stripped): "${ARGUMENTS%% *}"
# is quoted-and-safe per Test 3 but still broken, so quoting is irrelevant.
# The operator class [%#/:^,@+-] covers every bash parameter-expansion
# operator that can follow the variable name (%/%% suffix, #/## prefix,
# / substitution, : substring/default, ^/, case, @ operator, +/- default).
#
# Scope covers `!`, `bash`, and `sh` executable fences — not just `!` blocks.
# Claude Code's $ARGUMENTS substitution is a template-wide preprocessing pass,
# so a `${ARGUMENTS:-}` in a ```bash block fed to the Bash tool is just as
# broken as one in a ```! block (a ```bash fence was the second affected site). Only
# `!` and `bash` fences exist today; `sh` is included so a future ```sh fence
# is covered the moment it lands rather than slipping through.
#
# Comment-strip subtlety: the strip must remove a TRAILING shell comment (so a
# doc comment like `# the ${ARGUMENTS:-} form is broken` is not flagged) WITHOUT
# eating the `#`/`##` prefix-removal operators inside `${ARGUMENTS#foo}`. A
# naive `s/[[:space:]]*#.*$//` truncates at the operator `#` (zero-space match)
# and silently loses those two operators. Anchoring the strip to a word
# boundary — `#` at line-start or preceded by whitespace — keeps real comments
# stripped while preserving operator `#`, which is never space-preceded.
_strip_arg_comment() { sed -E 's/(^|[[:space:]])#.*$/\1/'; }
_flow_test_begin "no bash parameter-expansion on \$ARGUMENTS in executable blocks"
PASS=1
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  BODY=$(awk '
    /^```(!|bash|sh)$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0; next }
    in_block { print }
  ' "$FILE")
  [ -z "$BODY" ] && continue
  BAD=$(printf '%s\n' "$BODY" | _strip_arg_comment \
        | grep -nE '\$\{ARGUMENTS[%#/:^,@+-]' || true)
  if [ -n "$BAD" ]; then
    _flow_assert_fail "$CMD.md applies bash parameter-expansion to \$ARGUMENTS in an executable block (Claude Code won't substitute it; copy to a local var first): $BAD"
    PASS=0
  fi
done
[ "$PASS" = "1" ] && _flow_assert_pass "no executable block applies bash parameter-expansion directly to \$ARGUMENTS"

# Self-guard for Test 6: the strip+grep pipeline
# is the line of defense, so prove it actually catches every operator it claims
# — including the `#`/`##` prefix forms that a naive comment-strip would lose —
# and that it does NOT false-positive on a trailing doc comment that merely
# *mentions* a broken form.
_flow_test_begin "Test 6 strip+grep catches all \$ARGUMENTS operators, ignores doc mentions"
PASS=1
for FORM in '${ARGUMENTS#foo}' '${ARGUMENTS##*/}' '${ARGUMENTS%% *}' '${ARGUMENTS:-}' \
            '${ARGUMENTS/a/b}' '${ARGUMENTS^^}' '${ARGUMENTS,,}' '${ARGUMENTS:0:3}' '${ARGUMENTS@Q}'; do
  HIT=$(printf 'X="%s"\n' "$FORM" | _strip_arg_comment | grep -nE '\$\{ARGUMENTS[%#/:^,@+-]' || true)
  if [ -z "$HIT" ]; then
    _flow_assert_fail "Test 6 pipeline failed to flag broken form: $FORM"
    PASS=0
  fi
done
# Bare forms Claude Code DOES substitute must NOT be flagged.
for OK in '$ARGUMENTS' '${ARGUMENTS}' '"$ARGUMENTS"'; do
  HIT=$(printf 'X="%s"\n' "$OK" | _strip_arg_comment | grep -nE '\$\{ARGUMENTS[%#/:^,@+-]' || true)
  if [ -n "$HIT" ]; then
    _flow_assert_fail "Test 6 pipeline false-positived on a CC-substituted bare form: $OK"
    PASS=0
  fi
done
# Trailing doc comment mentioning a broken form must be stripped, not flagged.
FP=$(printf '%s\n' 'RUN_ID="$ARGUMENTS"  # the ${ARGUMENTS:-} form is NOT substituted' \
     | _strip_arg_comment | grep -nE '\$\{ARGUMENTS[%#/:^,@+-]' || true)
if [ -n "$FP" ]; then
  _flow_assert_fail "Test 6 pipeline false-positived on a doc-comment mention: $FP"
  PASS=0
fi
[ "$PASS" = "1" ] && _flow_assert_pass "Test 6 strip+grep covers all operators with no false positives"
