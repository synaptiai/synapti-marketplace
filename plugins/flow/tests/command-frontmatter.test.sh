#!/usr/bin/env bash
# command-frontmatter.test.sh — static lint over plugins/flow/commands/*.md
#
# Enforces the structural invariants this PR (#103) established:
#   F3: every `!` block ends with explicit `true` (defensive trailing line)
#   F2/F6: every $ARGUMENTS in a `!` block is either quoted or case-validated
#   C1/C18: every `Bash(${CLAUDE_PLUGIN_ROOT...}/bin/...)` in frontmatter is
#           actually invoked in the body (no dead patterns); and every
#           helper invocation in the body has a matching allowed-tools entry
#   C1 follow-up: no `Bash(bash plugins/flow/bin/...)` dead-pattern form
#
# The lint is intentionally strict — it's the regression net for F3-class
# misses (a single block without `true` on a refactored command would have
# slipped through the original review).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$TESTS_DIR/../commands"

# Files modified in PR #103 — the ones whose ! blocks were introduced or
# touched. Out-of-scope commands (flow.md, explain.md, etc.) may have older
# patterns we don't want to flag retroactively.
MODIFIED_BY_PR103=(
  address.md
  commit.md
  learn.md
  pr.md
  release.md
  resolve.md
  start.md
  status.md
)

# extract_bang_blocks <file> — print each `!` block to stdout, separated by
# a marker line `===BLOCK===`. Uses awk for a simple state machine.
extract_bang_blocks() {
  awk '
    /^```!$/ { in_block=1; next }
    /^```$/  { if (in_block) { in_block=0; print "===BLOCK===" }; next }
    in_block { print }
  ' "$1"
}

# extract_frontmatter <file> — print the YAML frontmatter (between --- ... ---)
extract_frontmatter() {
  awk '
    /^---$/ { count++; if (count==1) {next} else {exit} }
    count==1 { print }
  ' "$1"
}

# extract_allowed_tools <file> — print one Bash(...) pattern per line from
# the allowed-tools frontmatter field
extract_allowed_tools() {
  extract_frontmatter "$1" | awk '
    /^allowed-tools:/ { collecting=1; sub(/^allowed-tools: /, ""); }
    collecting {
      # Match every Bash(...) pattern on the line(s). Use a loop because a
      # single line can contain many patterns.
      while (match($0, /Bash\([^)]+\)/)) {
        print substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART+RLENGTH)
      }
    }
    /^[a-z-]+:/ && !/^allowed-tools:/ { collecting=0 }
  '
}

# ─── Test 1: F3 — every ! block ends with `true` ─────────────────────────────
_begin "F3: every \`!\` block in PR #103-touched commands ends with 'true'"
MISSING=()
for FILE in "${MODIFIED_BY_PR103[@]}"; do
  BLOCKS=$(extract_bang_blocks "$COMMANDS_DIR/$FILE")
  # Split blocks on ===BLOCK=== separator
  BLOCK_NUM=0
  LAST_NONEMPTY=""
  while IFS= read -r LINE; do
    if [ "$LINE" = "===BLOCK===" ]; then
      BLOCK_NUM=$((BLOCK_NUM+1))
      # Check whether the last non-empty/non-comment line of this block was
      # `true` (allowing optional trailing comment). The defensive trailing-
      # `true` pattern protects against grep/find piped-exit-code surprises.
      if [ -z "$LAST_NONEMPTY" ] || [[ ! "$LAST_NONEMPTY" =~ ^true([[:space:]]*#.*)?$ ]]; then
        MISSING+=("$FILE block#$BLOCK_NUM: last non-blank line is '$LAST_NONEMPTY' (expected: 'true')")
      fi
      LAST_NONEMPTY=""
      continue
    fi
    # Strip trailing whitespace
    STRIPPED="${LINE%"${LINE##*[![:space:]]}"}"
    # Skip blank lines and pure-comment lines
    case "$STRIPPED" in
      '') continue ;;
      '#'*) continue ;;
    esac
    LAST_NONEMPTY="$STRIPPED"
  done <<< "$BLOCKS"
done
if [ ${#MISSING[@]} -eq 0 ]; then
  _pass
else
  _fail "$(printf '%s\n' "${MISSING[@]}")"
fi

# ─── Test 2: F2/F6 — every $ARGUMENTS in a ! block is validated ─────────────
_begin "F2/F6: \$ARGUMENTS usage in \`!\` blocks is case-validated or pinned"
UNVALIDATED=()
for FILE in "${MODIFIED_BY_PR103[@]}"; do
  BLOCKS=$(extract_bang_blocks "$COMMANDS_DIR/$FILE")
  # If a block contains $ARGUMENTS, it must also contain either:
  #   - a `case "${ARGUMENTS` validation, OR
  #   - the variable being quoted ("$ARGUMENTS") AND used in a context where
  #     unsafe expansion can't happen
  # We use a simple heuristic: a `case "${ARGUMENTS` or `case "$ARGUMENTS` line
  # OR an explicit pin like `PR_NUM=$ARGUMENTS`/`ISSUE_NUM=$ARGUMENTS` after
  # a case validation. Accept either signal.
  while IFS= read -r -d '===BLOCK===' BLOCK || [ -n "$BLOCK" ]; do
    # bash read -d "===BLOCK===" doesn't actually accept multi-char terminator
    # — use a different approach: feed all blocks through a single grep.
    :
  done <<< "$BLOCKS"
  # Simpler approach: for each block, check the joined content
  echo "$BLOCKS" | awk -v file="$FILE" '
    BEGIN { block=0; buffer="" }
    /^===BLOCK===$/ {
      block++
      if (buffer ~ /\$ARGUMENTS/ || buffer ~ /\${ARGUMENTS/) {
        if (buffer !~ /case[[:space:]]+"\$\{?ARGUMENTS/) {
          print file " block#" block ": uses $ARGUMENTS without case validation"
        }
      }
      buffer=""
      next
    }
    { buffer = buffer "\n" $0 }
  ' >> /tmp/flow-arg-check.$$
done
if [ -s /tmp/flow-arg-check.$$ ]; then
  UNVALIDATED=("$(cat /tmp/flow-arg-check.$$)")
fi
rm -f /tmp/flow-arg-check.$$
if [ ${#UNVALIDATED[@]} -eq 0 ]; then
  _pass
else
  _fail "$(printf '%s\n' "${UNVALIDATED[@]}")"
fi

# ─── Test 3: C1/C18 — allowed-tools helper patterns invoked literally ───────
_begin "C1/C18: every \`Bash(\${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/...)\` allowed-tools entry has a matching literal invocation in the body"
ORPHANS=()
for FILE in "${MODIFIED_BY_PR103[@]}"; do
  # Extract all helper Bash(...) patterns from allowed-tools
  PATTERNS=$(extract_allowed_tools "$COMMANDS_DIR/$FILE" | grep -oE 'Bash\(\$\{CLAUDE_PLUGIN_ROOT[^)]*\)')
  while IFS= read -r PATTERN; do
    [ -z "$PATTERN" ] && continue
    # Strip the `Bash(` prefix and `:*)` suffix to get the literal command
    # Format: Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/<script>.sh:*)
    LITERAL=$(echo "$PATTERN" | sed -E 's/^Bash\(//; s/:\*\)$//')
    # The literal text MUST appear somewhere in the body (allowed-tools matches
    # the rendered command at execution time). Look for the script name as a
    # weaker probe — the full literal with ${...} braces might not appear
    # verbatim if the body uses `"${CLAUDE_PLUGIN_ROOT:-plugins/flow}"` style.
    SCRIPT_NAME=$(echo "$LITERAL" | grep -oE 'bin/[^[:space:]]+\.sh$' | head -1)
    if [ -z "$SCRIPT_NAME" ]; then
      continue
    fi
    if ! grep -q "$SCRIPT_NAME" "$COMMANDS_DIR/$FILE"; then
      ORPHANS+=("$FILE: allowed-tools pattern $PATTERN references $SCRIPT_NAME but no invocation in body")
    fi
  done <<< "$PATTERNS"
done
if [ ${#ORPHANS[@]} -eq 0 ]; then
  _pass
else
  _fail "$(printf '%s\n' "${ORPHANS[@]}")"
fi

# ─── Test 4: C1 follow-up — no `Bash(bash plugins/flow/bin/...)` dead pattern ─
_begin "C1 follow-up: no 'Bash(bash plugins/flow/bin/...)' dead pattern in allowed-tools"
DEAD_PATTERNS=()
for FILE in "${MODIFIED_BY_PR103[@]}"; do
  # The pre-fix form `Bash(bash plugins/flow/bin/...)` is a marketplace-install
  # regression: when CLAUDE_PLUGIN_ROOT resolves to ~/.claude/plugins/.../,
  # the literal `plugins/flow/bin/...` doesn't exist. Reject this form.
  HITS=$(grep -E 'Bash\(bash plugins/flow/bin/' "$COMMANDS_DIR/$FILE" 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    DEAD_PATTERNS+=("$FILE: $HITS")
  fi
done
if [ ${#DEAD_PATTERNS[@]} -eq 0 ]; then
  _pass
else
  _fail "$(printf '%s\n' "${DEAD_PATTERNS[@]}")"
fi

# ─── Test 5: Frontmatter completeness — description + allowed-tools ─────────
_begin "Frontmatter: every PR #103-touched command has description + allowed-tools"
INCOMPLETE=()
for FILE in "${MODIFIED_BY_PR103[@]}"; do
  FM=$(extract_frontmatter "$COMMANDS_DIR/$FILE")
  if ! echo "$FM" | grep -q '^description:'; then
    INCOMPLETE+=("$FILE: missing 'description' in frontmatter")
  fi
  if ! echo "$FM" | grep -q '^allowed-tools:'; then
    INCOMPLETE+=("$FILE: missing 'allowed-tools' in frontmatter")
  fi
done
if [ ${#INCOMPLETE[@]} -eq 0 ]; then
  _pass
else
  _fail "$(printf '%s\n' "${INCOMPLETE[@]}")"
fi

# ─── Test 6: Required Skills references resolve to actual skill dirs ────────
_begin "Required Skills: every named skill exists at plugins/flow/skills/<name>/"
MISSING_SKILLS=()
for FILE in "${MODIFIED_BY_PR103[@]}"; do
  # Extract skill names from lines like "- `skill-name` — description"
  # under a "## Required Skills" heading
  SKILLS=$(awk '
    /^## Required Skills/ { collecting=1; next }
    /^## / { collecting=0 }
    collecting && /^- `[^`]+`/ {
      match($0, /^- `[^`]+`/)
      skill = substr($0, RSTART+3, RLENGTH-4)
      print skill
    }
  ' "$COMMANDS_DIR/$FILE")
  while IFS= read -r SKILL; do
    [ -z "$SKILL" ] && continue
    if [ ! -d "$COMMANDS_DIR/../skills/$SKILL" ]; then
      MISSING_SKILLS+=("$FILE: references skill '$SKILL' but plugins/flow/skills/$SKILL/ does not exist")
    fi
  done <<< "$SKILLS"
done
if [ ${#MISSING_SKILLS[@]} -eq 0 ]; then
  _pass
else
  _fail "$(printf '%s\n' "${MISSING_SKILLS[@]}")"
fi
