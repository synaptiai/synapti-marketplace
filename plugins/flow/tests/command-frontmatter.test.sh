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

COMMANDS_DIR="$REPO_ROOT/plugins/flow/commands"
SKILLS_DIR="$REPO_ROOT/plugins/flow/skills"

# --- Test 1: every `!` block ends with `true`
# Extract each `!` block's body (everything between ```! and the next ```),
# strip trailing blanks, and assert the last meaningful line is exactly `true`.
_flow_test_begin "every ! block ends with explicit 'true'"
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  # awk extracts ! blocks; emits one block per "BLOCK_START" / "BLOCK_END"
  # delimited section. The block-index is appended so we can name failures.
  BLOCKS=$(awk '
    /^```!$/ { in_block=1; idx++; print "BLOCK_START " idx; next }
    /^```$/ && in_block { in_block=0; print "BLOCK_END " idx; next }
    in_block { print }
  ' "$FILE")
  [ -z "$BLOCKS" ] && continue

  # Walk the awk output: for each block, capture lines and check the last
  # non-blank line equals `true`.
  CURRENT_BLOCK=""
  CURRENT_IDX=""
  while IFS= read -r LINE; do
    case "$LINE" in
      "BLOCK_START "*)
        CURRENT_BLOCK=""
        CURRENT_IDX="${LINE#BLOCK_START }"
        ;;
      "BLOCK_END "*)
        # Strip trailing blank lines; check last is `true`.
        LAST_NONBLANK=$(printf '%s' "$CURRENT_BLOCK" | awk 'NF { last=$0 } END { print last }')
        if [ "$LAST_NONBLANK" != "true" ]; then
          _flow_assert_fail "$CMD.md ! block #$CURRENT_IDX last line is '$LAST_NONBLANK', expected 'true'"
        fi
        CURRENT_BLOCK=""
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
# Single PASS marker covers all 16 commands when no fail fired.
[ "$FLOW_TEST_FAIL" = "0" ] && _flow_assert_pass "all ! blocks across $(ls "$COMMANDS_DIR"/*.md | wc -l | tr -d ' ') commands end with 'true'"

# --- Test 2: no destructive commands inside ! blocks
# ! blocks are read-only context gatherers. Destructive verbs anywhere inside
# (even commented) are a code smell at minimum and a footgun if uncommented.
# We grep for verbs in word boundaries to avoid false positives in variable
# names or substrings.
_flow_test_begin "no destructive verbs inside ! blocks"
PASS=1
PROHIBITED='rm -rf|rm -f|rm[[:space:]]+-r|git[[:space:]]+push|git[[:space:]]+reset[[:space:]]+--hard|gh[[:space:]]+pr[[:space:]]+merge|gh[[:space:]]+pr[[:space:]]+close|gh[[:space:]]+release[[:space:]]+create|gh[[:space:]]+release[[:space:]]+delete|git[[:space:]]+tag[[:space:]]+-d|git[[:space:]]+branch[[:space:]]+-D'
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  # Extract block bodies (drop the BLOCK_START/END markers) and grep on them.
  awk '
    /^```!$/ { in_block=1; idx++; print "BLOCK_START " idx; next }
    /^```$/ && in_block { in_block=0; print "BLOCK_END " idx; next }
    in_block { print }
  ' "$FILE" | grep -nE "$PROHIBITED" > /tmp/flow_dest_match.$$ 2>/dev/null || true
  if [ -s /tmp/flow_dest_match.$$ ]; then
    HITS=$(cat /tmp/flow_dest_match.$$)
    _flow_assert_fail "$CMD.md contains destructive verb inside ! block: $HITS"
    PASS=0
  fi
  rm -f /tmp/flow_dest_match.$$
done
[ "$PASS" = "1" ] && _flow_assert_pass "no destructive verbs in any ! block"

# --- Test 3: $ARGUMENTS inside ! blocks is quoted or extracted via case
# Acceptable forms inside an ! block:
#   - "$ARGUMENTS"           (double-quoted scalar)
#   - "${ARGUMENTS%% *}"     (first-token extraction; the case-validated form)
#   - assigned to a var then used: ARG1="${ARGUMENTS%% *}"; then "$ARG1"
# Unacceptable: bare $ARGUMENTS (word-split + glob risk).
_flow_test_begin "\$ARGUMENTS in ! blocks is quoted or extracted"
PASS=1
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  BODY=$(awk '
    /^```!$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0; next }
    in_block { print }
  ' "$FILE")
  [ -z "$BODY" ] && continue
  # Look for any $ARGUMENTS occurrence that is NOT preceded by a quote-or-brace.
  # Simplest robust check: bare \$ARGUMENTS appearing anywhere flags as fail.
  # The accepted forms always have `{` or `"` immediately before ARGUMENTS:
  #   "${ARGUMENTS...    "$ARGUMENTS"    ${ARGUMENTS  (inside other quoting)
  # Bare $ARGUMENTS (no `{` immediately after `$`, no `"` before `$`) is the
  # vulnerable form.
  BAD=$(printf '%s\n' "$BODY" | grep -nE '(^|[^"\$])\$ARGUMENTS([^a-zA-Z_]|$)' || true)
  if [ -n "$BAD" ]; then
    _flow_assert_fail "$CMD.md has bare \$ARGUMENTS in ! block: $BAD"
    PASS=0
  fi
done
[ "$PASS" = "1" ] && _flow_assert_pass "all \$ARGUMENTS uses in ! blocks are quoted/extracted"

# --- Test 4: Required Skills entries resolve to plugins/flow/skills/<name>/
# Each command's "## Required Skills" section lists `- skill-name` bullets;
# every name must correspond to an existing skills/ directory.
_flow_test_begin "Required Skills entries resolve to skills/ directories"
PASS=1
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
  while IFS= read -r SKILL; do
    [ -z "$SKILL" ] && continue
    # Permit two forms: `skills/<skill>/` or `skills/<skill>/SKILL.md`.
    if [ ! -d "$SKILLS_DIR/$SKILL" ] && [ ! -f "$SKILLS_DIR/$SKILL/SKILL.md" ]; then
      _flow_assert_fail "$CMD.md Required Skills references '$SKILL' but $SKILLS_DIR/$SKILL/ does not exist"
      PASS=0
    fi
  done <<< "$SKILLS"
done
[ "$PASS" = "1" ] && _flow_assert_pass "all Required Skills references resolve"

# --- Test 5: allowed-tools Bash(...) patterns have at least one matching body invocation
# Frontmatter pattern: `Bash(<command-prefix>:*)`. For the literal-prefix form
# we extract the prefix and assert the body contains it somewhere. Glob forms
# (Bash(*) or Bash(:*)) are skipped — they match everything by definition.
_flow_test_begin "allowed-tools Bash() prefixes have at least one body invocation"
PASS=1
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  # Frontmatter is the first --- ... --- block.
  FRONT=$(awk '
    BEGIN { state=0 }
    /^---$/ { state++; if (state==1) next; if (state==2) exit }
    state==1 { print }
  ' "$FILE")
  # Body is everything after the closing --- of frontmatter.
  BODY=$(awk '
    BEGIN { state=0 }
    /^---$/ { state++; next }
    state>=2 { print }
  ' "$FILE")
  # Extract Bash(...) entries from allowed-tools. Multi-line allowed-tools
  # (YAML list form) flatten to one line per entry.
  PATTERNS=$(printf '%s\n' "$FRONT" | grep -oE 'Bash\([^)]+\)' | sed -E 's/^Bash\((.*)\)$/\1/')
  [ -z "$PATTERNS" ] && continue
  while IFS= read -r PATTERN; do
    [ -z "$PATTERN" ] && continue
    # Strip trailing `:*` if present — Claude Code's wildcard for "any args".
    PREFIX="${PATTERN%:\*}"
    # Skip pure-wildcard patterns.
    case "$PREFIX" in
      ""|"*") continue ;;
    esac
    # Expand ${CLAUDE_PLUGIN_ROOT:-plugins/flow} so the body grep can match
    # the actual literal path in helper invocations.
    EXPANDED=$(printf '%s' "$PREFIX" | sed 's|\${CLAUDE_PLUGIN_ROOT:-plugins/flow}|plugins/flow|g')
    # Strip a leading `bash ` so a `Bash(bash plugins/flow/bin/foo.sh)` pattern
    # matches a `plugins/flow/bin/foo.sh` body invocation that doesn't repeat
    # the explicit interpreter.
    CHECK="${EXPANDED#bash }"
    if ! printf '%s' "$BODY" | grep -qF "$CHECK"; then
      _flow_assert_fail "$CMD.md allowed-tools 'Bash($PATTERN)' has no matching body invocation (looked for '$CHECK')"
      PASS=0
    fi
  done <<< "$PATTERNS"
done
[ "$PASS" = "1" ] && _flow_assert_pass "all literal Bash() prefixes resolve to body invocations"
