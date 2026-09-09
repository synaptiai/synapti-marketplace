#!/usr/bin/env bash
# [flow] PostToolUse + PostToolUseFailure hook (matcher: Bash): record
# quality-command runs.
#
# Classifies tool_input.command as a quality run when it matches one of the
# built-in patterns below or any ERE from the cascade key
# `testing.qualityCommandPatterns` (array of strings; default []). A match
# appends a quality_run entry to the per-session ledger via
# bin/flow-quality-ledger.sh; the TaskCompleted gate
# (verify-task-completion.sh) later refuses to complete a task while files
# changed after the last PASSING quality_run.
#
# Classification rules (a "mention" is not a "run"):
#   - single- and double-quoted spans are stripped first, line by line, so
#     `git commit -m "chore: npm test config"` and `echo "pytest"` never match;
#   - a built-in pattern matches only at command position: start of a line
#     or right after `;`, `&&`, `||`, `|`, `(`, `$(`, `{`, with optional
#     whitespace and optional `VAR=value`, `env`, `time`, `nice [-n N]`,
#     `timeout N` prefixes. `echo cargo test`, `ls tests/run.sh`,
#     `cat tests/run.sh`, `grep pytest x` therefore do not match;
#     `cd x && pytest`, `FOO=1 pytest`, `bash tests/run.sh`,
#     `plugins/flow/tests/run.sh file` do;
#   - project patterns from testing.qualityCommandPatterns are applied as
#     written (against the quote-stripped command) — anchor them yourself.
#
# Recorded fields (see bin/flow-quality-ledger.sh for the entry shape):
#   exit_code       tool_response.exit_code; 130 when the tool was interrupted
#                   (tool_response.interrupted or is_interrupt); on a
#                   PostToolUseFailure payload, the N of the leading
#                   "Exit code N" line of `error` / `tool_error`, else null.
#   failed          true when the payload is a PostToolUseFailure (Claude Code
#                   fires that event, not PostToolUse, when the tool call
#                   fails — a failing test run may only ever reach this hook
#                   through it). A failed run never counts as passing.
#   masked          true when the command ends in `|| true`, `; true`, or
#                   `|| :` — exit 0 then says nothing, so it never passes.
#   worktree_digest sha256 of the working tree state right after the run
#                   (`flow-quality-ledger.sh digest --cwd <payload cwd>`
#                   with the journal dir, .flow/ and .screenshots/ excluded —
#                   the same ignore set the gate uses), null outside a git
#                   repo. The gate recomputes it at TaskCompleted time to see
#                   edits made outside Edit/Write.
#   tool_use_id     from the payload when present; the ledger helper skips a
#                   second append with the same id, so a tool call that
#                   fires both events is recorded once.
#
# Non-quality commands exit 0 with no side effects. Missing jq, a payload
# without session_id, or an unreachable helper also exit 0 — this hook is
# bookkeeping, never a blocker.
#
# Payload (stdin JSON): session_id, cwd, hook_event_name, tool_name,
# tool_use_id, tool_input.command, and either
#   tool_response {exit_code, stdout, stderr, interrupted}   (PostToolUse) or
#   error <string>, is_interrupt <bool>                       (PostToolUseFailure)
# (per https://code.claude.com/docs/en/hooks, 2026-09-09).

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

# Best-effort, line-local quote stripping (same approach as _strip_quoted in
# tests/command-frontmatter.test.sh). A quote that spans lines is left as-is.
STRIPPED=$(printf '%s\n' "$COMMAND" | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g")

# Command position: start of line, or right after `;` `&` `|` `(` `{` (which
# covers `&&`, `||`, `$(`), then optional whitespace and optional
# assignment / env / time / nice / timeout prefixes.
CMD_POS='(^|[;&|({])[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|time|nice([[:space:]]+-n[[:space:]]+-?[0-9]+)?|timeout[[:space:]]+[0-9]+[smhd]?)[[:space:]]+)*'

# Command end: whitespace, an operator (`;` `&` `|` `)`), or end of line, so
# `pytest; true` and `(npm test)` still match while `pytest-watch` and
# `cargo tests-helper` do not. Patterns below spell it as ([[:space:]]|$) and
# the loop widens that to CMD_END.
CMD_END='([[:space:]]|[;&|)]|$)'

# Built-in patterns, `kind|ERE`. Every ERE is prefixed with CMD_POS at match
# time. First match wins; order groups by tool so the kind is the
# sub-command's kind. Script runners accept an optional `bash `/`sh `
# interpreter and any directory prefix (`./`, `scripts/`, `plugins/flow/`).
BUILTIN_PATTERNS=(
  'test|(npm|pnpm|yarn|bun)[[:space:]]+(test|run[[:space:]]+(test|tests))([[:space:]]|$)'
  'lint|(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+(lint|check)([[:space:]]|$)'
  'typecheck|(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+(typecheck|type-check)([[:space:]]|$)'
  'build|(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+build([[:space:]]|$)'
  'test|(npx[[:space:]]+)?(vitest|jest|mocha|ava|tap)([[:space:]]|$)'
  'test|(pytest|python3?[[:space:]]+-m[[:space:]]+(pytest|unittest|doctest))([[:space:]]|$)'
  'lint|(ruff|flake8|black[[:space:]]+--check)([[:space:]]|$)'
  'typecheck|(mypy|pyright)([[:space:]]|$)'
  'typecheck|(npx[[:space:]]+)?tsc([[:space:]]|$)'
  'lint|(npx[[:space:]]+)?(eslint|prettier[[:space:]]+--check|biome)([[:space:]]|$)'
  'test|cargo[[:space:]]+test([[:space:]]|$)'
  'lint|cargo[[:space:]]+clippy([[:space:]]|$)'
  'typecheck|cargo[[:space:]]+check([[:space:]]|$)'
  'build|cargo[[:space:]]+build([[:space:]]|$)'
  'test|go[[:space:]]+test([[:space:]]|$)'
  'lint|go[[:space:]]+vet([[:space:]]|$)'
  'build|go[[:space:]]+build([[:space:]]|$)'
  'test|(rspec|bundle[[:space:]]+exec[[:space:]]+rspec)([[:space:]]|$)'
  'lint|(rubocop|bundle[[:space:]]+exec[[:space:]]+rubocop)([[:space:]]|$)'
  'test|make[[:space:]]+test([[:space:]]|$)'
  'lint|make[[:space:]]+(lint|check)([[:space:]]|$)'
  'typecheck|make[[:space:]]+typecheck([[:space:]]|$)'
  'build|make[[:space:]]+build([[:space:]]|$)'
  'lint|shellcheck([[:space:]]|$)'
  'test|bats([[:space:]]|$)'
  'test|((bash|sh)[[:space:]]+)?([^[:space:]]*/)?tests?/run\.sh([[:space:]]|$)'
  'test|((bash|sh)[[:space:]]+)?([^[:space:]]*/)?test\.sh([[:space:]]|$)'
  'lint|((bash|sh)[[:space:]]+)?([^[:space:]]*/)?lint\.sh([[:space:]]|$)'
  'project|((bash|sh)[[:space:]]+)?([^[:space:]]*/)?(verify|check)\.sh([[:space:]]|$)'
)

KIND=""
for entry in "${BUILTIN_PATTERNS[@]}"; do
  pattern="${entry#*|}"
  pattern="${pattern//'([[:space:]]|$)'/"$CMD_END"}"   # quoted: keeps & literal under bash 5.2 patsub_replacement
  if grep -qE -- "${CMD_POS}${pattern}" <<<"$STRIPPED" 2>/dev/null; then
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
    if grep -qE -- "$pattern" <<<"$STRIPPED" 2>/dev/null; then
      KIND="project"
      break
    fi
  done < <(printf '%s' "$USER_PATTERNS" | jq -r 'if type == "array" then .[] | select(type == "string") else empty end' 2>/dev/null)
fi

[ -z "$KIND" ] && exit 0

# Exit-code masking: the last non-empty line ends in `|| true`, `; true`, or
# `|| :` (an optional trailing `;` tolerated).
MASKED=false
LAST_LINE=$(printf '%s\n' "$COMMAND" | sed -e 's/[[:space:]]*$//' | grep -v '^$' | tail -n 1)
if grep -qE -- '(\|\|[[:space:]]*(true|:)|;[[:space:]]*true)[[:space:]]*;?$' <<<"$LAST_LINE" 2>/dev/null; then
  MASKED=true
fi

# Failure payload: PostToolUseFailure names itself in hook_event_name and
# carries `error` (documented) — `tool_error` is read too in case the field
# is renamed — instead of tool_response.
FAILED=$(printf '%s' "$INPUT" | jq -r '
  if .hook_event_name == "PostToolUseFailure" then "true"
  elif ((.tool_response | type) != "object") and (((.error | type) == "string") or ((.tool_error | type) == "string")) then "true"
  else "false" end' 2>/dev/null)
[ "$FAILED" = "true" ] || FAILED=false

# Worktree digest with the gate's ignore set (verify-task-completion.sh
# resolves the same three prefixes against the payload cwd).
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
JOURNAL_DIR=".decisions"
if [ -x "$CASCADE" ]; then
  JOURNAL_DIR=$("$CASCADE" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
  [ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
fi
_abs() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "${CWD%/}/$1" ;;
  esac
}
DIGEST=$("$LEDGER_HELPER" digest --cwd "$CWD" \
  --ignore-prefix "$(_abs "$JOURNAL_DIR")" \
  --ignore-prefix "$(_abs ".flow")" \
  --ignore-prefix "$(_abs ".screenshots")" 2>/dev/null) || DIGEST=""

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENTRY=$(printf '%s' "$INPUT" | jq -c --arg at "$NOW" --arg kind "$KIND" \
  --argjson masked "$MASKED" --argjson failed "$FAILED" --arg digest "$DIGEST" '
  def error_exit:
    ((.error // .tool_error // "") | if type == "string" then . else "" end)
    | (capture("^Exit code (?<n>[0-9]+)") | .n | tonumber)? // null;
  {
    at: $at,
    type: "quality_run",
    command: ((.tool_input.command // "") | .[0:200]),
    exit_code: (
      if (.tool_response.interrupted == true) or (.is_interrupt == true) then 130
      elif ((.tool_response.exit_code | type) == "number") then (.tool_response.exit_code | floor)
      elif $failed then error_exit
      else null
      end
    ),
    kind: $kind,
    masked: $masked,
    failed: $failed,
    worktree_digest: (if $digest == "" then null else $digest end)
  }
  + (if (.tool_use_id | type) == "string" and .tool_use_id != "" then {tool_use_id: .tool_use_id} else {} end)
  ' 2>/dev/null)
[ -z "$ENTRY" ] && exit 0

"$LEDGER_HELPER" append --session "$SESSION_ID" --json "$ENTRY" >/dev/null 2>&1 || true
exit 0
