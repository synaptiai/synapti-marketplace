#!/usr/bin/env bash
# Reference integrity: every relative link resolves, every reference is reached
# by something, and the README's advertised surface matches what exists.
#
# A broken link in a plugin's own documentation is the same defect the package
# contract's G11 condition exists to catch in generated packages. Failing to
# hold ourselves to it would be the plainest possible form of not eating our
# own cooking.

_dossier_test_begin "references-integrity"

PLUGIN="plugins/dossier"
REFS="$PLUGIN/references"

# --- Every relative markdown link resolves -----------------------------------
BROKEN=0
CHECKED=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  dir=$(dirname "$f")
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    case "$target" in
      http*|mailto:*|'#'*) continue ;;
    esac
    t=${target%%#*}
    [ -z "$t" ] && continue
    CHECKED=$((CHECKED + 1))
    if [ ! -e "$dir/$t" ] && [ ! -e "$t" ]; then
      BROKEN=$((BROKEN + 1))
      _dossier_assert_fail "broken link in ${f#plugins/dossier/}: $target"
    fi
  done <<EOF
$(grep -oE '\]\([^)]+\)' "$f" 2>/dev/null | sed -e 's/^](//' -e 's/)$//')
EOF
done <<EOF
$(find "$PLUGIN" -name '*.md' -type f -not -path '*/templates/package/*' 2>/dev/null | sort)
EOF

if [ "$BROKEN" -eq 0 ]; then
  _dossier_assert_pass "all $CHECKED relative links resolve"
fi

# --- Every reference is cited by something -----------------------------------
# An orphan reference is either dead weight or a document somebody forgot to
# wire in; both are worth surfacing.
CONSUMERS=$(find "$PLUGIN/skills" "$PLUGIN/commands" "$PLUGIN/agents" "$PLUGIN/references" "$PLUGIN/bin" \
              -type f 2>/dev/null)
while IFS= read -r ref; do
  base=$(basename "$ref")
  hits=0
  while IFS= read -r c; do
    [ "$c" = "$ref" ] && continue
    grep -qF "$base" "$c" 2>/dev/null && { hits=1; break; }
  done <<EOF
$CONSUMERS
EOF
  if [ "$hits" -eq 1 ]; then
    _dossier_assert_pass "reference $base is cited"
  else
    _dossier_assert_fail "reference $base is orphaned — nothing cites it"
  fi
done <<EOF
$(find "$REFS" -name '*.md' -type f 2>/dev/null | sort)
EOF

# --- Every reference cited in a skill or command exists -----------------------
while IFS= read -r cited; do
  [ -z "$cited" ] && continue
  if [ -f "$REFS/$cited" ]; then
    _dossier_assert_pass "cited reference $cited exists"
  else
    _dossier_assert_fail "cited reference $cited does not exist"
  fi
done <<EOF
$(grep -rhoE 'references/[a-z0-9-]+\.md' "$PLUGIN/skills" "$PLUGIN/commands" "$PLUGIN/agents" 2>/dev/null \
   | sed 's|references/||' | sort -u)
EOF

# --- README surface matches reality ------------------------------------------
README="$PLUGIN/README.md"
assert_file_exists "$README" "README exists"

SKILL_COUNT=$(find "$PLUGIN/skills" -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')
CMD_COUNT=$(find "$PLUGIN/commands" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$PLUGIN/agents" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')

assert_contains "Skills ($SKILL_COUNT)" "$(cat "$README")" "README skill count matches the $SKILL_COUNT skills on disk"
assert_contains "Agents ($AGENT_COUNT)" "$(cat "$README")" "README agent count matches the $AGENT_COUNT agents on disk"

# Every command must appear in the README's command table — an undocumented
# command is one nobody finds.
for f in "$PLUGIN"/commands/*.md; do
  cmd=$(basename "$f" .md)
  assert_contains "/dossier:$cmd" "$(cat "$README")" "README documents /dossier:$cmd"
done

# Every skill must be named in the README.
for d in "$PLUGIN"/skills/*/; do
  s=$(basename "$d")
  assert_contains "$s" "$(cat "$README")" "README names skill $s"
done

# Every agent must be named in the README.
for f in "$PLUGIN"/agents/*.md; do
  a=$(basename "$f" .md)
  assert_contains "$a" "$(cat "$README")" "README names agent $a"
done

# --- The README states the limitations, not just the features ----------------
# These are the four things a user discovers painfully if we do not say them.
README_BODY=$(cat "$README")
assert_contains "plugin_marketplaces" "$README_BODY" "README states the no-ref limitation"
assert_contains "create and approve pull requests" "$README_BODY" "README states the Actions PR-permission gotcha"
assert_contains "spend cap" "$README_BODY" "README states the cost-cap limitation"
assert_contains "different model" "$README_BODY" "README states the model-independence limitation"

# --- No operational dependency on a sibling plugin ---------------------------
# The test harness and the cascade script were ported from flow, and several
# documents credit it. Prose attribution is fine and worth keeping. What is not
# fine is an executable path: it resolves on a dev machine with the whole
# marketplace checked out and fails on a real install, where only this plugin
# is present. So this checks shell lines, not comments or markdown.
STRAY=""
SELF="$PLUGIN/tests/references-integrity.test.sh"
while IFS= read -r f; do
  # This file necessarily contains the patterns it searches for.
  [ "$f" = "$SELF" ] && continue
  case "$f" in
    *.sh)
      # Non-comment lines only.
      if grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -q 'plugins/flow'; then
        STRAY="$STRAY $f"
      fi ;;
    *.json|*.yml|*.yaml)
      grep -q 'plugins/flow' "$f" 2>/dev/null && STRAY="$STRAY $f" ;;
    *.md)
      # Markdown: a relative link or an executable path in a fenced block is a
      # dependency; a sentence naming the file is a citation.
      if grep -qE '\]\(\.\./\.\./flow|source .*plugins/flow|exec .*plugins/flow|^\s*plugins/flow/bin' "$f" 2>/dev/null; then
        STRAY="$STRAY $f"
      fi ;;
  esac
done <<EOF
$(find "$PLUGIN" -type f \( -name '*.sh' -o -name '*.json' -o -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
EOF

if [ -z "$STRAY" ]; then
  _dossier_assert_pass "no operational dependency on a sibling plugin"
else
  _dossier_assert_fail "executable plugins/flow path in:$STRAY"
fi

_dossier_test_summary
