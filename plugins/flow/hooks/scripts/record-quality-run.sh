#!/usr/bin/env bash
# [flow] PostToolUse hook (matcher: Bash): record quality-command runs.
#
# Classifies tool_input.command as a quality run when it matches one of the
# built-in patterns below or any ERE from the cascade key
# `testing.qualityCommandPatterns` (array of strings; default []). A match
# appends a quality_run entry to the per-session ledger via
# bin/flow-quality-ledger.sh; the TaskCompleted gate
# (verify-task-completion.sh) later refuses to complete a task while files
# changed after the last quality_run with exit_code 0.
#
# exit_code comes from tool_response.exit_code (null when absent). An
# interrupted command (tool_response.interrupted == true) is recorded as 130
# so a test run the user cancelled never counts as passing.
#
# Non-quality commands exit 0 with no side effects. Missing jq, a payload
# without session_id, or an unreachable helper also exit 0 — this hook is
# bookkeeping, never a blocker.
#
# Payload (stdin JSON): session_id, cwd, tool_name, tool_input.command,
# tool_response {exit_code, stdout, stderr, interrupted}.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"
LEDGER_HELPER="${PLUGIN_ROOT}/bin/flow-quality-ledger.sh"
CASCADE="${PLUGIN_ROOT}/bin/cascade-resolve.sh"
[ -x "$LEDGER_HELPER" ] || exit 0

# Built-in patterns, `kind|ERE`. Each ERE is anchored at a command boundary
# (start of string, `;`, `&`, `|`, or whitespace) so `cargo test` does not
# also read as `go test` and a quoted mention inside `echo "npm test"` does
# not count. First match wins; order groups by tool so the kind is the
# sub-command's kind.
BUILTIN_PATTERNS=(
  'test|(^|[;&|[:space:]])(npm|pnpm|yarn|bun)[[:space:]]+(test|run[[:space:]]+(test|tests))([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+(lint|check)([[:space:]]|$)'
  'typecheck|(^|[;&|[:space:]])(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+(typecheck|type-check)([[:space:]]|$)'
  'build|(^|[;&|[:space:]])(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+build([[:space:]]|$)'
  'test|(^|[;&|[:space:]])(npx[[:space:]]+)?(vitest|jest|mocha|ava|tap)([[:space:]]|$)'
  'test|(^|[;&|[:space:]])(pytest|python3?[[:space:]]+-m[[:space:]]+pytest)([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])(ruff|flake8|black[[:space:]]+--check)([[:space:]]|$)'
  'typecheck|(^|[;&|[:space:]])(mypy|pyright)([[:space:]]|$)'
  'typecheck|(^|[;&|[:space:]])(npx[[:space:]]+)?tsc([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])(npx[[:space:]]+)?(eslint|prettier[[:space:]]+--check|biome)([[:space:]]|$)'
  'test|(^|[;&|[:space:]])cargo[[:space:]]+test([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])cargo[[:space:]]+clippy([[:space:]]|$)'
  'typecheck|(^|[;&|[:space:]])cargo[[:space:]]+check([[:space:]]|$)'
  'build|(^|[;&|[:space:]])cargo[[:space:]]+build([[:space:]]|$)'
  'test|(^|[;&|[:space:]])go[[:space:]]+test([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])go[[:space:]]+vet([[:space:]]|$)'
  'build|(^|[;&|[:space:]])go[[:space:]]+build([[:space:]]|$)'
  'test|(^|[;&|[:space:]])(rspec|bundle[[:space:]]+exec[[:space:]]+rspec)([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])(rubocop|bundle[[:space:]]+exec[[:space:]]+rubocop)([[:space:]]|$)'
  'test|(^|[;&|[:space:]])make[[:space:]]+test([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])make[[:space:]]+(lint|check)([[:space:]]|$)'
  'typecheck|(^|[;&|[:space:]])make[[:space:]]+typecheck([[:space:]]|$)'
  'build|(^|[;&|[:space:]])make[[:space:]]+build([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])shellcheck([[:space:]]|$)'
  'test|(^|[;&|[:space:]])bats([[:space:]]|$)'
  'test|tests?/run\.sh([[:space:]]|$)'
  'test|(^|[;&|[:space:]])(\./)?(scripts/)?test\.sh([[:space:]]|$)'
  'lint|(^|[;&|[:space:]])(\./)?(scripts/)?lint\.sh([[:space:]]|$)'
  'project|(^|[;&|[:space:]])(\./)?(scripts/)?(verify|check)\.sh([[:space:]]|$)'
)

KIND=""
for entry in "${BUILTIN_PATTERNS[@]}"; do
  pattern="${entry#*|}"
  if grep -qE -- "$pattern" <<<"$COMMAND" 2>/dev/null; then
    KIND="${entry%%|*}"
    break
  fi
done

# Project-defined patterns (settings cascade). Each is an ERE string; an
# invalid regex simply fails to match (grep exits 2) and is skipped.
if [ -z "$KIND" ] && [ -x "$CASCADE" ]; then
  USER_PATTERNS=$("$CASCADE" --compact --default '[]' '.testing.qualityCommandPatterns // empty' 2>/dev/null)
  [ -z "$USER_PATTERNS" ] && USER_PATTERNS='[]'
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if grep -qE -- "$pattern" <<<"$COMMAND" 2>/dev/null; then
      KIND="project"
      break
    fi
  done < <(printf '%s' "$USER_PATTERNS" | jq -r 'if type == "array" then .[] | select(type == "string") else empty end' 2>/dev/null)
fi

[ -z "$KIND" ] && exit 0

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENTRY=$(printf '%s' "$INPUT" | jq -c --arg at "$NOW" --arg kind "$KIND" '
  {
    at: $at,
    type: "quality_run",
    command: ((.tool_input.command // "") | .[0:200]),
    exit_code: (
      if (.tool_response.interrupted == true) then 130
      elif ((.tool_response.exit_code | type) == "number") then (.tool_response.exit_code | floor)
      else null
      end
    ),
    kind: $kind
  }' 2>/dev/null)
[ -z "$ENTRY" ] && exit 0

"$LEDGER_HELPER" append --session "$SESSION_ID" --json "$ENTRY" >/dev/null 2>&1 || true
exit 0
