#!/usr/bin/env bash
# Test shim for `claude --print`. Used by flow-goal-evaluator.test.sh to
# stub the judge subprocess without hitting the real Claude API.
#
# Usage (test harness):
#   export FLOW_TEST_CLAUDE_RESPONSE=/path/to/fixture.json
#   export PATH="${tmpdir}/mock-bin:$PATH"      # mock-bin/claude → this script
#   ./flow-goal-evaluator.sh < event.json
#
# Contract:
#   - Accepts ALL flags so it survives hook arg drift; records two of them
#     only when FLOW_TEST_CLAUDE_ARGS_DIR is set (see below).
#   - Reads stdin to /dev/null so the producer's `<` redirect doesn't SIGPIPE.
#   - Emits the fixture file's contents on stdout, byte-for-byte.
#   - Exits 0 if fixture is readable; 1 if env var unset or fixture unreadable.
#
# Why a separate file (not inline in the test): symlinking/copying this as
# `claude` in a per-test mock-bin keeps PATH manipulation simple and lets
# multiple tests reuse the same shim with different fixtures via env var.

set -u

if [ -z "${FLOW_TEST_CLAUDE_RESPONSE:-}" ]; then
  echo "mock-claude: FLOW_TEST_CLAUDE_RESPONSE unset" >&2
  exit 1
fi
# `-f` (regular file) is stricter than `-r` (readable) — `-r` is true for
# directories too, which would later make `cat <dir>` emit "Is a directory"
# stderr and confuse test diagnostics.
if [ ! -f "$FLOW_TEST_CLAUDE_RESPONSE" ]; then
  echo "mock-claude: fixture is not a regular file: $FLOW_TEST_CLAUDE_RESPONSE" >&2
  exit 1
fi
if [ ! -r "$FLOW_TEST_CLAUDE_RESPONSE" ]; then
  echo "mock-claude: fixture unreadable: $FLOW_TEST_CLAUDE_RESPONSE" >&2
  exit 1
fi

# With FLOW_TEST_CLAUDE_ARGS_DIR set, the shim keeps what it was given, one
# file each, byte for byte: the value after each of --system-prompt, --model,
# --disallowedTools, --output-format and --json-schema in
# system-prompt.txt, model.txt, disallowed-tools.txt, output-format.txt and
# json-schema.txt (absent when the flag was not passed); every argument
# starting with -- in flags.txt, one per line; stdin (the prompt) in
# stdin.txt; and in env.txt the lines judge_mode=<CLAUDE_HOOK_GOAL_JUDGE_MODE>
# and pwd=<physical working directory>. A value can span lines, so each goes
# to its own file rather than one flattened line. Without it, every flag is
# ignored as before.
#
# FLOW_TEST_CLAUDE_SLEEP=<seconds> waits that long before replying, for a
# caller's time limit to cut it off.
if [ -n "${FLOW_TEST_CLAUDE_ARGS_DIR:-}" ]; then
  d="$FLOW_TEST_CLAUDE_ARGS_DIR"
  : > "$d/flags.txt"
  while [ $# -gt 0 ]; do
    case "$1" in --*) printf '%s\n' "$1" >> "$d/flags.txt" ;; esac
    case "$1" in
      --system-prompt|--model|--disallowedTools|--output-format|--json-schema)
        if [ $# -lt 2 ]; then shift; continue; fi
        case "$1" in
          --system-prompt) f=system-prompt ;;
          --model) f=model ;;
          --disallowedTools) f=disallowed-tools ;;
          --output-format) f=output-format ;;
          --json-schema) f=json-schema ;;
        esac
        printf '%s' "$2" > "$d/$f.txt"
        shift 2 ;;
      *) shift ;;
    esac
  done
  printf 'judge_mode=%s\npwd=%s\n' "${CLAUDE_HOOK_GOAL_JUDGE_MODE:-}" "$(pwd -P)" > "$d/env.txt"
  cat > "$d/stdin.txt" 2>/dev/null || true
else
  # Tolerate a closed FD 0 — `cat > /dev/null <&-` errors with "Bad file
  # descriptor". `|| true` keeps the shim exit 0 so the hook sees clean stdout.
  cat > /dev/null 2>/dev/null || true
fi
[ -n "${FLOW_TEST_CLAUDE_SLEEP:-}" ] && sleep "$FLOW_TEST_CLAUDE_SLEEP"
cat "$FLOW_TEST_CLAUDE_RESPONSE"
# Optionally exit with a non-zero code (real `claude --print` can return
# a partial-JSON stdout with a non-zero exit on network/model errors).
# Used by tests that exercise the hook's "non-empty RESP regardless of
# exit code" contract.
if [ -n "${FLOW_TEST_CLAUDE_EXIT:-}" ]; then
  exit "$FLOW_TEST_CLAUDE_EXIT"
fi
