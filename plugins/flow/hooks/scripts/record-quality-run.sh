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
#   exit_code       130 when the tool was interrupted (tool_response.interrupted
#                   or is_interrupt); else tool_response.exit_code when it is
#                   a number; on a PostToolUseFailure payload, the N of the
#                   leading "Exit code N" line of `error` / `tool_error`; on
#                   a PostToolUse payload whose tool_response is an object
#                   with none of backgroundTaskId, timedOutAfterMs or
#                   returnCodeInterpretation, 0 when the matched command is
#                   the whole command or follows only plain prefixes
#                   (_plain_run below), else null; else null. A 0 from
#                   tool_response.exit_code goes through the same check.
#                   Claude Code sends no exit code for a Bash call that
#                   succeeds (the result keys its 2.1.283 transcripts record
#                   are interrupted, isImage, noOutputExpected, stdout,
#                   stderr and the three above); a non-zero exit arrives as
#                   PostToolUseFailure, except one Claude Code reads as
#                   informational (grep's "No matches found"), which carries
#                   returnCodeInterpretation. A call moved to the background
#                   has not finished, so its exit code is unknown.
#   failed          true when the payload is a PostToolUseFailure (Claude Code
#                   fires that event, not PostToolUse, when the tool call
#                   fails — a failing test run may only ever reach this hook
#                   through it). A failed run never counts as passing.
#   masked          true when the command ends in `|| true`, `; true`, or
#                   `|| :` — exit 0 then says nothing, so it never passes
#                   (a 0 is recorded as null by the rule above).
#   worktree_digest sha256 of the working tree state right after the run
#                   (`flow-quality-ledger.sh digest --cwd <payload cwd>`
#                   with the journal dir, .flow/ and .screenshots/ excluded —
#                   the same ignore set the gate uses), null outside a git
#                   repo. The gate recomputes it at TaskCompleted time to see
#                   edits made outside Edit/Write.
#   tool_use_id     from the payload when present; the ledger helper skips a
#                   second append with the same id, so a tool call that
#                   fires both events is recorded once.
#   s1_state_sha256 only when the run was asked about at the System One site
#                   quality.tests-ran (shadow or on): the sha256 of the state
#                   sent, equal to the record's state_sha256.
#   output_check    only when that site, switched on, answered none_ran or
#                   all_skipped with enough confidence: {verdict, site,
#                   model, confidence}. The run then never counts as passing.
#                   Asked only after a PostToolUse built-in test run whose
#                   exit_code above is 0, unmasked and uninterrupted; see
#                   references/system-one.md.
#
# Non-quality commands exit 0 with no side effects. Missing jq, a payload
# without session_id, or an unreachable helper also exit 0 — this hook is
# bookkeeping, never a blocker.
#
# Payload (stdin JSON): session_id, cwd, hook_event_name, tool_name,
# tool_use_id, tool_input.command, and either
#   tool_response {stdout, stderr, interrupted, ...}          (PostToolUse) or
#   error <string>, is_interrupt <bool>                       (PostToolUseFailure)
# (per https://code.claude.com/docs/en/hooks, 2026-09-09).

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

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
# What the patterns below literally spell, and what the loop widens to CMD_END.
CMD_END_TOKEN='([[:space:]]|$)'

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
MATCH_RE=""
# The built-in pattern that matched, without the command-position prefix.
MATCH_PAT=""
for entry in "${BUILTIN_PATTERNS[@]}"; do
  pattern="${entry#*|}"
  # Widen the spelled command-end to CMD_END by suffix removal, not by
  # ${var//search/replacement}. CMD_END contains `&`, which bash 5.2's
  # patsub_replacement expands to the matched text; quoting the replacement to
  # prevent that is correct under bash 5.2 but leaves the quote characters in
  # the result under bash 3.2, which is what macOS ships as /bin/bash. That
  # produced `bats"([[:space:]]|[;&|)]|$)"` — a regex containing literal double
  # quotes, matching no command at all, so nothing was ever classified and no
  # ledger row was written. Suffix removal has no replacement side, so neither
  # shell can reinterpret it.
  if [ "${pattern%"$CMD_END_TOKEN"}" != "$pattern" ]; then
    pattern="${pattern%"$CMD_END_TOKEN"}$CMD_END"
  fi
  if grep -qE -- "${CMD_POS}${pattern}" <<<"$STRIPPED" 2>/dev/null; then
    KIND="${entry%%|*}"
    MATCH_RE="${CMD_POS}${pattern}"
    MATCH_PAT="$pattern"
    break
  fi
done
# Only a built-in test command is ever asked about (System One block below):
# a repository's own patterns must not widen what is sent to the provider.
BUILTIN_KIND="$KIND"

# Project-defined patterns (settings cascade). Each is an ERE string; an
# invalid regex simply fails to match (grep exits 2) and is skipped.
if [ -z "$KIND" ] && [ -x "$CASCADE" ]; then
  USER_PATTERNS=$("$CASCADE" --compact --default '[]' '.testing.qualityCommandPatterns // empty' 2>/dev/null)
  [ -z "$USER_PATTERNS" ] && USER_PATTERNS='[]'
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if grep -qE -- "$pattern" <<<"$STRIPPED" 2>/dev/null; then
      KIND="project"
      MATCH_RE="$pattern"
      break
    fi
  done < <(printf '%s' "$USER_PATTERNS" | jq -r 'if type == "array" then .[] | select(type == "string") else empty end' 2>/dev/null)
fi

[ -z "$KIND" ] && exit 0

# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi

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

# The run's exit code, used by the System One pre-filter and the ledger entry
# (see "Recorded fields" above). "null" when unknown.
EXIT_CODE=$(printf '%s' "$INPUT" | jq -c --argjson failed "$FAILED" '
  def error_exit:
    ((.error // .tool_error // "") | if type == "string" then . else "" end)
    | (capture("^Exit code (?<n>[0-9]+)") | .n | tonumber)? // null;
  if ((.tool_response | type) == "object" and .tool_response.interrupted == true) or (.is_interrupt == true) then 130
  elif ((.tool_response.exit_code? | type) == "number") then (.tool_response.exit_code | floor)
  elif $failed then error_exit
  elif .hook_event_name == "PostToolUse" and (.tool_response | type) == "object"
       and (.tool_response | has("backgroundTaskId") or has("timedOutAfterMs") or has("returnCodeInterpretation") | not)
  then 0
  else null
  end' 2>/dev/null) || EXIT_CODE=null
[[ "$EXIT_CODE" =~ ^-?[0-9]+$ ]] || EXIT_CODE=null

# A Bash call reports one status for the whole command, so a succeeded call
# says the test command exited 0 only when nothing else in the command could
# have produced that status. _plain_run succeeds when the test command is the
# whole command, or follows only these prefixes:
#   - `cd <dir> &&` and assignments such as `FOO=1`, on the same line, with
#     no quote, backslash or brace in the directory or the value;
#   - one leading line holding only `set` with the flags e, u, x, v (after
#     `-` or `+`) and `-o`/`+o` with pipefail, errexit, nounset or xtrace
#     (`set -e`, `set -euo pipefail`). Any other option, such as `set -n`,
#     can stop the test command from running.
# A built-in pattern must match at the start of what follows the prefixes; a
# pattern from testing.qualityCommandPatterns must match a non-empty text
# there too.
# Anything else fails, and the exit code is then recorded as null: a pipe,
# `;`, `&&` or `||` after the test command, a background `&`, a subshell,
# group or substitution, a heredoc or here-string anywhere, a command over
# more than one line, and prefixes such as `env`, `time` or `timeout`.
# Redirections (`2>&1`, `> file`, `&> file`) are allowed. The command is read
# as written, quotes included, so a `|` or `;` inside a quoted argument also
# fails; that costs a plain re-run, never a false pass. Each check is one
# pattern match over the text, not a walk over its characters.
_plain_run() {
  local cmd="$COMMAND" line first body set_re pre_re
  case "$cmd" in *'<<'*) return 1 ;; esac
  # Suffix and prefix removal with a pattern that does not match at once
  # tries every position, which takes seconds on a 50 KB command under bash
  # 3.2 in a UTF-8 locale; `%?`, `read` and substrings do not.
  while case "$cmd" in *$'\n') true ;; *) false ;; esac; do cmd="${cmd%?}"; done
  line="$cmd"
  case "$cmd" in
    *$'\n'*)
      IFS= read -r first <<<"$cmd"
      line="${cmd:$((${#first} + 1))}"
      case "$line" in *$'\n'*) return 1 ;; esac
      set_re='^[[:space:]]*set([[:space:]]+([-+][euxv]*o[[:space:]]+(pipefail|errexit|nounset|xtrace)|[-+][euxv]+))+[[:space:]]*$'
      [[ "$first" =~ $set_re ]] || return 1
      ;;
  esac
  # A quote, backslash or brace can hide a space inside the directory or the
  # value, and the rest of the line would then not be the command that runs.
  pre_re="^[[:space:]]*(cd[[:space:]]+[^[:space:];&|()<>\`'\"\\{}]+[[:space:]]*&&[[:space:]]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|()<>\`'\"\\{}]*[[:space:]]+)*"
  [[ "$line" =~ $pre_re ]] || return 1
  body="${line:${#BASH_REMATCH[0]}}"
  if [ -n "$MATCH_PAT" ]; then
    local start_re="^($MATCH_PAT)"
    [[ "$body" =~ $start_re ]] || return 1
  else
    # A repository pattern, used as written: its leftmost match must be
    # non-empty and be the text the body starts with.
    case "$body" in '!'*) return 1 ;; esac
    [[ "$body" =~ $MATCH_RE ]] || return 1
    local m="${BASH_REMATCH[0]}"
    [ -n "$m" ] && [ "${body:0:${#m}}" = "$m" ] || return 1
  fi
  # Remove redirections, then refuse any operator that is left.
  body=$(printf '%s' "$body" | LC_ALL=C sed -E -e 's/[0-9]*[<>]&[0-9]*-?//g' -e 's/&>>?//g' 2>/dev/null) || return 1
  case "$body" in *['|;&()`']*) return 1 ;; esac
  return 0
}
if [ "$EXIT_CODE" = 0 ] && ! _plain_run; then
  EXIT_CODE=null
fi

# Worktree digest with the gate's ignore set (verify-task-completion.sh
# resolves the same three prefixes against the payload cwd).
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
# The journal directory as every journal writer resolves it.
JOURNAL_DIR=".decisions"
if [ -x "${CASCADE%/cascade-resolve.sh}/journal-dir.sh" ]; then
  JOURNAL_DIR=$("${CASCADE%/cascade-resolve.sh}/journal-dir.sh" 2>/dev/null)
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

# System One, site quality.tests-ran (references/system-one.md). Asked only
# after a passing built-in test run, and only when the site is shadow or on.
# Every other call starts no process for it. The answer can only take a pass
# away, never give one.
EXTRA='{}'
# _s1_ref_ok <ref>: the shape flow-s1.sh accepts for --ref, in the C locale so
# the ranges are ASCII only. In [[ =~ ]], ^ and $ match only at the ends of the
# string, so a ref holding a newline does not match.
_s1_ref_ok() {
  local LC_ALL=C
  [ "${#1}" -le 200 ] && [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$ ]]
}
_s1_quality_check() {
  local event mode ref tid state out rc sha check
  [ "$BUILTIN_KIND" = test ] && [ "$MASKED" = false ] && [ "$FAILED" = false ] && [ "$EXIT_CODE" = 0 ] || return 0
  event=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null) || return 0
  [ "$event" = PostToolUse ] || return 0
  # The mode as the client resolves it (bin/flow-s1-mode.sh: a repository can
  # only lower the user's mode, and no provider means off). Reading it here
  # keeps python3 from starting, and the record from carrying a state digest,
  # when nothing would be asked.
  [ -x "${PLUGIN_ROOT}/bin/flow-s1-mode.sh" ] || return 0
  mode=$("${PLUGIN_ROOT}/bin/flow-s1-mode.sh" quality.tests-ran 2>/dev/null) || mode=""
  case "$mode" in shadow|on) ;; *) return 0 ;; esac
  # The record names the tool call it judged. The client refuses a ref of
  # another shape (and then writes no record), so one is never passed.
  tid=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // empty | strings' 2>/dev/null) || tid=""
  ref="quality-run:unknown"
  if _s1_ref_ok "quality-run:$tid" && [ -n "$tid" ]; then
    ref="quality-run:$tid"
  elif _s1_ref_ok "quality-run:session:$SESSION_ID"; then
    ref="quality-run:session:$SESSION_ID"
  fi
  # The output goes as lists of lines: the client shortens a long state by
  # cutting each string from its end, which keeps every line, the runner's
  # summary at the end among them.
  state=$(mktemp "${TMPDIR:-/tmp}/flow-s1-quality.XXXXXX" 2>/dev/null) || return 0
  [ -n "$state" ] && [ -f "$state" ] || return 0
  # The file holds the test output: remove it if the hook is stopped while it
  # waits for the answer. Bash runs the handler once the client has exited.
  S1_STATE_FILE="$state"
  trap 'rm -f "$S1_STATE_FILE"' EXIT
  trap 'rm -f "$S1_STATE_FILE"; exit 0' INT TERM HUP
  if ! printf '%s' "$INPUT" | jq -c --argjson ec "$EXIT_CODE" '
      def lines: (if type == "string" then . else "" end)
        | (if endswith("\n") then .[:-1] else . end)
        | if . == "" then [] else split("\n") end
        | map(.[0:400]);
      {command: ((.tool_input.command // "") | .[0:2000]),
       exit_code: $ec,
       output_head: (.tool_response.stdout | lines | .[0:40]),
       output_tail: (.tool_response.stdout | lines | .[-200:]),
       stderr_tail: (.tool_response.stderr | lines | .[-40:])}' > "$state" 2>/dev/null; then
    rm -f "$state"
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha=$(sha256sum "$state" 2>/dev/null | cut -d' ' -f1) || sha=""
  else
    sha=$(shasum -a 256 "$state" 2>/dev/null | cut -d' ' -f1) || sha=""
  fi
  if ! LC_ALL=C grep -qE '^[0-9a-f]{64}$' <<<"$sha" 2>/dev/null; then
    rm -f "$state"
    return 0
  fi
  out=$("${PLUGIN_ROOT}/bin/flow-s1.sh" ask --site quality.tests-ran --state-file "$state" \
    --state-format json --current pass --ref "$ref" 2>/dev/null)
  rc=$?
  rm -f "$state"
  trap - EXIT INT TERM HUP
  EXTRA=$(jq -nc --arg sha "$sha" '{s1_state_sha256: $sha}' 2>/dev/null) || EXTRA='{}'
  [ -n "$EXTRA" ] || EXTRA='{}'
  # Exit 0 comes only in on mode, with every answer confident enough.
  [ "$rc" -eq 0 ] && [ "$mode" = on ] || return 0
  check=$(printf '%s' "$out" | jq -ce '
    (.answers.outcome.choice) as $c
    | select($c == "none_ran" or $c == "all_skipped")
    | {verdict: $c, site: "quality.tests-ran", model: .model, confidence: .answers.outcome.confidence}' 2>/dev/null) || return 0
  [ -n "$check" ] || return 0
  out=$(jq -nc --arg sha "$sha" --argjson c "$check" '{s1_state_sha256: $sha, output_check: $c}' 2>/dev/null) || return 0
  [ -n "$out" ] && EXTRA="$out"
  return 0
}
_s1_quality_check

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENTRY=$(printf '%s' "$INPUT" | jq -c --arg at "$NOW" --arg kind "$KIND" \
  --argjson masked "$MASKED" --argjson failed "$FAILED" --argjson ec "$EXIT_CODE" \
  --arg digest "$DIGEST" --argjson extra "$EXTRA" '
  {
    at: $at,
    type: "quality_run",
    command: ((.tool_input.command // "") | .[0:200]),
    exit_code: $ec,
    kind: $kind,
    masked: $masked,
    failed: $failed,
    worktree_digest: (if $digest == "" then null else $digest end)
  }
  + (if (.tool_use_id | type) == "string" and .tool_use_id != "" then {tool_use_id: .tool_use_id} else {} end)
  + $extra
  ' 2>/dev/null)
[ -z "$ENTRY" ] && exit 0

"$LEDGER_HELPER" append --session "$SESSION_ID" --json "$ENTRY" >/dev/null 2>&1 || true
exit 0
