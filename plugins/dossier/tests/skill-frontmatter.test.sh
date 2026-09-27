#!/usr/bin/env bash
# Skill contract: each skill's name matches its directory, it runs in a forked
# context, and its agent is one the harness provides.

# Refuse to run without the shared library: its fixture guard is what keeps
# this file's git commands inside its own fixtures (issue #252).
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: ${BASH_SOURCE[0]##*/} must be run through plugins/dossier/tests/run.sh, which loads the fixture guard" >&2; exit 2; }

_dossier_test_begin "skill-frontmatter"

SKILLS_DIR="plugins/dossier/skills"

for f in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  dir=$(basename "$(dirname "$f")")

  # name must match the directory — the loader resolves by directory, and a
  # mismatch produces a skill that cannot be invoked by its own name.
  name=$(awk -F': ' '/^name:/{print $2; exit}' "$f")
  assert_equal "$dir" "$name" "$dir: name matches directory"

  agent=$(awk -F': ' '/^agent:/{print $2; exit}' "$f")
  case "$agent" in
    general-purpose|Explore) _dossier_assert_pass "$dir: agent is $agent" ;;
    *) _dossier_assert_fail "$dir: agent '$agent' is not general-purpose or Explore" ;;
  esac

  assert_equal "fork" "$(awk -F': ' '/^context:/{print $2; exit}' "$f")" "$dir: context is fork"
done

_dossier_test_summary
