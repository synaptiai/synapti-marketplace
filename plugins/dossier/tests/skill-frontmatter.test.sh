#!/usr/bin/env bash
# Skill contract: frontmatter shape, description trigger phrases, body sections,
# and the size band. A skill whose description lacks its trigger phrases will
# not be invoked when it should be, which fails silently.

_dossier_test_begin "skill-frontmatter"

SKILLS_DIR="plugins/dossier/skills"
EXPECTED_COUNT=9

COUNT=$(find "$SKILLS_DIR" -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equal "$EXPECTED_COUNT" "$COUNT" "skill count"

for f in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  dir=$(basename "$(dirname "$f")")

  # name must match the directory — the loader resolves by directory, and a
  # mismatch produces a skill that cannot be invoked by its own name.
  name=$(awk -F': ' '/^name:/{print $2; exit}' "$f")
  assert_equal "$dir" "$name" "$dir: name matches directory"

  desc=$(awk -F'description: ' '/^description:/{print $2; exit}' "$f")
  case "$desc" in
    \"*\") _dossier_assert_pass "$dir: description is double-quoted" ;;
    *)     _dossier_assert_fail "$dir: description must be double-quoted" ;;
  esac

  # The two trigger phrases the house style depends on for invocation.
  assert_contains "Use when" "$desc" "$dir: description carries a 'Use when' trigger"
  assert_contains "MUST be consulted because" "$desc" "$dir: description justifies mandatory consultation"

  # At least three sentences: what it does, when to use it, why it is mandatory.
  sentences=$(printf '%s' "$desc" | tr '.' '\n' | grep -c '[A-Za-z]')
  if [ "$sentences" -ge 3 ]; then
    _dossier_assert_pass "$dir: description has $sentences sentences"
  else
    _dossier_assert_fail "$dir: description has $sentences sentences, expected at least 3"
  fi

  # allowed-tools is unquoted comma-separated, matching the house style.
  tools=$(awk -F': ' '/^allowed-tools:/{print $2; exit}' "$f")
  if [ -n "$tools" ]; then
    case "$tools" in
      \"*|\'*) _dossier_assert_fail "$dir: allowed-tools must be unquoted" ;;
      *)       _dossier_assert_pass "$dir: allowed-tools unquoted" ;;
    esac
  else
    _dossier_assert_fail "$dir: allowed-tools missing"
  fi

  agent=$(awk -F': ' '/^agent:/{print $2; exit}' "$f")
  case "$agent" in
    general-purpose|Explore) _dossier_assert_pass "$dir: agent is $agent" ;;
    *) _dossier_assert_fail "$dir: agent '$agent' is not general-purpose or Explore" ;;
  esac

  assert_equal "fork" "$(awk -F': ' '/^context:/{print $2; exit}' "$f")" "$dir: context is fork"

  # Required body sections.
  for section in "## Iron Law" "## Output Format" "## Rationalization Prevention" "## Integration"; do
    if grep -q "^$section" "$f"; then
      _dossier_assert_pass "$dir: has $section"
    else
      _dossier_assert_fail "$dir: missing $section"
    fi
  done

  # The Iron Law must be a bolded imperative, not a paragraph.
  iron=$(sed -n '/^## Iron Law/,/^## /p' "$f" | grep -c '^\*\*')
  if [ "$iron" -ge 1 ]; then
    _dossier_assert_pass "$dir: Iron Law is a bolded imperative"
  else
    _dossier_assert_fail "$dir: Iron Law must contain a bolded imperative statement"
  fi

  # Size band: below 58 lines a skill is a stub; above 170 it belongs in a
  # reference, and the drafting agents that load it pay for every line.
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -ge 58 ] && [ "$lines" -le 170 ]; then
    _dossier_assert_pass "$dir: $lines lines (within 58-170)"
  else
    _dossier_assert_fail "$dir: $lines lines is outside the 58-170 band"
  fi

  # No emoji — house style, and they render inconsistently in terminals.
  if LC_ALL=C grep -qP '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' "$f" 2>/dev/null; then
    _dossier_assert_fail "$dir: contains emoji"
  else
    _dossier_assert_pass "$dir: no emoji"
  fi

  # Per-file content bullets belong in references, not here. A skill naming a
  # specific canonical document's required content has absorbed a contract.
  if grep -qE '^\s*-\s+(conceptual and logical data model|hazard analysis|bill of materials)' "$f"; then
    _dossier_assert_fail "$dir: contains package-contract content that belongs in references/"
  else
    _dossier_assert_pass "$dir: no package-contract content inlined"
  fi
done

_dossier_test_summary
