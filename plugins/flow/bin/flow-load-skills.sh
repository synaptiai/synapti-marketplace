#!/usr/bin/env bash
# [flow] Inline a command's Required Skills into its rendered prompt.
#
# Why this exists: Claude Code commands cannot preload skills from frontmatter
# (only agents have `skills:`), so a command's "## Required Skills" list was a
# reading list the agent might or might not open mid-run. An audit of 43
# sessions found the skill carrying the most-broken rule loaded once in
# twenty-four chances. Commands now call this helper from a `!` block at the
# top of the file; Claude Code pre-executes the block and injects its stdout,
# so the rules are in context before the first phase runs.
#
# Two loading modes, decided from each skill's frontmatter:
#   ambient  — no `context: fork` and no `agent:` line. The whole body (after
#              the frontmatter) is inlined. These are stance skills that apply
#              throughout the command (e.g. llm-operator-principles).
#   contract — `context: fork` or `agent:` present. The skill is designed to
#              run as a subagent via Skill(<name>) at a specific phase, so only
#              its `## Contract` section (iron law, invoking phase, return
#              shape, permitted skips) is inlined. The full body loads when the
#              command dispatches it.
#
# Usage:
#   flow-load-skills.sh <skill-name> [<skill-name> ...]
#   flow-load-skills.sh --check <skill-name> [...]   # lint: exit 1 on any problem, no bodies
#   flow-load-skills.sh --list  <skill-name> [...]   # resolution lines only, no bodies
#
# Stdout follows references/command-output-format.md: a `### Loaded Skills`
# section with one SKILL_LOADED= record per skill, then one `#### Skill: ...`
# sub-heading per inlined body. Missing skills and dispatched skills without a
# `## Contract` section emit SKILL_LOAD_ERROR= lines; the helper still exits 0
# in normal mode (the `!` block must not fail), and the lint test in
# tests/flow-load-skills.test.sh catches the drift before it ships.
#
# Exits: 0 normally; --check exits 1 when any skill is missing or a dispatched
# skill lacks a `## Contract` section; 2 on usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}"
SKILLS_DIR="${FLOW_SKILLS_DIR:-${PLUGIN_ROOT}/skills}"

MODE_FLAG="load"
case "${1:-}" in
  --check) MODE_FLAG="check"; shift ;;
  --list)  MODE_FLAG="list";  shift ;;
  -h|--help)
    sed -n '2,32p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
esac

if [ $# -eq 0 ]; then
  echo "flow-load-skills.sh: at least one skill name is required" >&2
  exit 2
fi

# Body = everything after the closing frontmatter fence. A file without a
# frontmatter block is emitted whole.
_body() {
  awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } {print}' "$1"
}

# Frontmatter = lines between the first two `---` fences.
_frontmatter() {
  awk 'NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) exit; print }' "$1"
}

# Contract = from the `## Contract` heading up to (not including) the next H2.
_contract() {
  _body "$1" | awk '/^## Contract[[:space:]]*$/ {on=1; next} on && /^## / {exit} on {print}'
}

_words() { wc -w | tr -d ' '; }

RECORDS=""
BODIES=""
PROBLEMS=0

for NAME in "$@"; do
  case "$NAME" in
    ''|*/*|*..*)
      RECORDS="${RECORDS}SKILL_LOAD_ERROR=${NAME} reason=invalid-name"$'\n'
      PROBLEMS=$((PROBLEMS+1))
      continue
      ;;
  esac
  FILE="${SKILLS_DIR}/${NAME}/SKILL.md"
  if [ ! -f "$FILE" ]; then
    # A skill promoted by bin/promote-proposal.sh lives one level deeper, in
    # skills/learned/<name>/. The `*/*` guard above rejects the qualified form,
    # so without this fallback nothing this loader is asked for by plain name
    # can ever resolve to a learned skill. The name is already charset-checked
    # by that guard, so the path cannot escape SKILLS_DIR.
    if [ -f "${SKILLS_DIR}/learned/${NAME}/SKILL.md" ]; then
      FILE="${SKILLS_DIR}/learned/${NAME}/SKILL.md"
    else
      RECORDS="${RECORDS}SKILL_LOAD_ERROR=${NAME} reason=not-found"$'\n'
      PROBLEMS=$((PROBLEMS+1))
      continue
    fi
  fi
  FM=$(_frontmatter "$FILE")
  if printf '%s\n' "$FM" | grep -qE '^(context:[[:space:]]*fork|agent:[[:space:]]*[^[:space:]])'; then
    SKILL_MODE="contract"
  else
    SKILL_MODE="ambient"
  fi

  if [ "$SKILL_MODE" = "contract" ]; then
    TEXT=$(_contract "$FILE")
    if [ -z "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ]; then
      RECORDS="${RECORDS}SKILL_LOAD_ERROR=${NAME} reason=no-contract-section"$'\n'
      PROBLEMS=$((PROBLEMS+1))
      continue
    fi
    HEADER="#### Skill: ${NAME} (contract — the full skill runs when the command invokes Skill(${NAME}) at the phase named below)"
  else
    TEXT=$(_body "$FILE")
    HEADER="#### Skill: ${NAME} (ambient — applies throughout this command)"
  fi
  WORDS=$(printf '%s\n' "$TEXT" | _words)
  RECORDS="${RECORDS}SKILL_LOADED=${NAME} mode=${SKILL_MODE} words=${WORDS}"$'\n'
  BODIES="${BODIES}"$'\n'"${HEADER}"$'\n'"${TEXT}"$'\n'
done

case "$MODE_FLAG" in
  check)
    printf '%s' "$RECORDS"
    [ "$PROBLEMS" -eq 0 ] && exit 0
    exit 1
    ;;
  list)
    echo "### Loaded Skills"
    printf '%s' "$RECORDS"
    exit 0
    ;;
  load)
    echo "### Loaded Skills"
    printf '%s' "$RECORDS"
    printf '%s\n' "$BODIES"
    exit 0
    ;;
esac
