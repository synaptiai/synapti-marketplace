#!/usr/bin/env bash
# Command contract: frontmatter, required sections, and — most importantly —
# that every Skill() and Agent() invocation in a body resolves to something on
# disk and is declared in Required Skills. A dangling reference fails at
# runtime, in front of the user, halfway through a phase.

_dossier_test_begin "command-frontmatter"

CMD_DIR="plugins/dossier/commands"
SKILLS_DIR="plugins/dossier/skills"
AGENTS_DIR="plugins/dossier/agents"
EXPECTED_COUNT=9

COUNT=$(find "$CMD_DIR" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equal "$EXPECTED_COUNT" "$COUNT" "command count"

for f in "$CMD_DIR"/*.md; do
  [ -f "$f" ] || continue
  cmd=$(basename "$f" .md)

  # Commands take their name from the filename; a `name:` key is a sign the
  # file was written against the skill contract by mistake.
  if awk '/^---$/{c++} c==1 && /^name:/{found=1} END{exit !found}' "$f"; then
    _dossier_assert_fail "$cmd: has a name: key (the filename is the command name)"
  else
    _dossier_assert_pass "$cmd: no name: key"
  fi

  for field in description allowed-tools; do
    if grep -qE "^$field:" "$f"; then
      _dossier_assert_pass "$cmd: has $field"
    else
      _dossier_assert_fail "$cmd: missing $field"
    fi
  done

  for section in "## Required Skills" "## Tier Classification"; do
    if grep -q "^$section" "$f"; then
      _dossier_assert_pass "$cmd: has $section"
    else
      _dossier_assert_fail "$cmd: missing $section"
    fi
  done

  # Tier Classification belongs at the bottom, after the phases.
  tier_line=$(grep -n '^## Tier Classification' "$f" | cut -d: -f1)
  total=$(wc -l < "$f" | tr -d ' ')
  if [ -n "$tier_line" ] && [ "$tier_line" -gt 20 ]; then
    _dossier_assert_pass "$cmd: Tier Classification at line $tier_line of $total"
  else
    _dossier_assert_fail "$cmd: Tier Classification too early (line ${tier_line:-none})"
  fi

  # Every Skill(X) must be declared AND exist.
  req_block=$(sed -n '/## Required Skills/,/^## /p' "$f")
  for s in $(grep -oE 'Skill\([a-z-]+\)' "$f" | sed -E 's/Skill\((.*)\)/\1/' | sort -u); do
    if [ -f "$SKILLS_DIR/$s/SKILL.md" ]; then
      _dossier_assert_pass "$cmd: Skill($s) exists"
    else
      _dossier_assert_fail "$cmd: Skill($s) does not resolve to $SKILLS_DIR/$s/SKILL.md"
    fi
    case "$req_block" in
      *"\`$s\`"*) _dossier_assert_pass "$cmd: Skill($s) declared in Required Skills" ;;
      *)          _dossier_assert_fail "$cmd: Skill($s) invoked but not declared in Required Skills" ;;
    esac
  done

  # Every skill declared in Required Skills must exist too — a stale entry is
  # as misleading as a missing one.
  for s in $(printf '%s' "$req_block" | sed -nE 's/^- `([a-z-]+)`.*/\1/p'); do
    if [ -f "$SKILLS_DIR/$s/SKILL.md" ]; then
      _dossier_assert_pass "$cmd: declared skill $s exists"
    else
      _dossier_assert_fail "$cmd: Required Skills lists $s which does not exist"
    fi
  done

  # Every Agent(X) must exist.
  for a in $(grep -oE 'Agent\(dossier-[a-z-]+\)' "$f" | sed -E 's/Agent\((.*)\)/\1/' | sort -u); do
    if [ -f "$AGENTS_DIR/$a.md" ]; then
      _dossier_assert_pass "$cmd: Agent($a) exists"
    else
      _dossier_assert_fail "$cmd: Agent($a) does not resolve"
    fi
  done

  # `!` bash blocks are read-only pre-execution context. They must end with a
  # literal `true` so a non-zero exit from the last command does not abort the
  # block, and they must not contain destructive shell.
  awk '
    /^```!$/ { inblock=1; last=""; next }
    inblock && /^```$/ {
      inblock=0
      if (last != "true") { print "BADEND" }
      next
    }
    inblock && NF { last=$0 }
  ' "$f" > /tmp/dossier-cmd-check.$$ 2>/dev/null
  if grep -q BADEND /tmp/dossier-cmd-check.$$ 2>/dev/null; then
    _dossier_assert_fail "$cmd: a \`!\` block does not end with a literal 'true'"
  else
    _dossier_assert_pass "$cmd: all \`!\` blocks end with 'true'"
  fi
  rm -f /tmp/dossier-cmd-check.$$ 2>/dev/null

  # Bare $ARGUMENTS must be copied into a shell var before parameter expansion:
  # `${ARGUMENTS%% *}` is not substituted by the harness and silently yields "".
  if grep -qE '\$\{ARGUMENTS[%#:]' "$f"; then
    _dossier_assert_fail "$cmd: uses \${ARGUMENTS...} parameter expansion — assign to a var first"
  else
    _dossier_assert_pass "$cmd: no direct \${ARGUMENTS} expansion"
  fi

  # Read-only context blocks must not mutate the repository.
  if awk '/^```!$/{i=1;next} /^```$/{i=0} i' "$f" | grep -qE '(^|[;&|[:space:]])(rm|git (commit|push|checkout|reset|merge)|gh (pr|issue|release) (create|merge|edit))\b'; then
    _dossier_assert_fail "$cmd: destructive command inside a read-only \`!\` block"
  else
    _dossier_assert_pass "$cmd: \`!\` blocks are read-only"
  fi
done

# The nine commands the README and CHANGELOG advertise.
for expected in init baseline refresh audit reconcile gate claim status setup; do
  assert_file_exists "$CMD_DIR/$expected.md" "command $expected exists"
done

_dossier_test_summary
