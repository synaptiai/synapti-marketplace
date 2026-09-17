#!/usr/bin/env bash
# cascade-resolve.sh — read a flow plugin setting from the standard Claude Code
# settings cascade with per-source parse-error surfacing.
#
# Resolves a jq expression against four trusted sources, in precedence order
# (highest first — first non-empty value wins):
#
#   1. .claude/settings.flow.local.json — project-local; gitignored
#   2. .claude/settings.flow.json       — project-shared; committed
#   3. $HOME/.claude/settings.flow.json — user-global
#   4. ${CLAUDE_PLUGIN_ROOT}/settings.json — plugin default
#
# Usage:
#   cascade-resolve.sh [--default <fallback>] [--compact] [--allow-control-chars] <jq-expression>
#
# Flags:
#   --default <value>     value printed on stdout when no source has the key
#   --compact             use `jq -c` (preserves JSON quoting) instead of `jq -r`
#   --allow-control-chars print a value containing a control character instead of
#                         refusing it. See SECURITY below.
#   --scalar              accepted and ignored: refusing such a value IS the
#                         default now, and this flag is kept so that a call site
#                         written against the revision that introduced it keeps
#                         behaving as it did.
#
# Output:
#   stdout: the resolved value (one line; the default if provided and no
#           source resolved; otherwise empty)
#   stderr: per-source `cascade-resolve: WARN: ...` for parse errors
#
# Exit:
#   0 — resolved a value (or returned the default; both are normal)
#   2 — infrastructure error (jq missing, no expression provided, a leftover
#       argument, or a refused value with no --default to fall back to)
#
# SECURITY — why refusing is the DEFAULT, and not a flag callers must remember:
#   .claude/settings.flow.json is a tracked file, so a fork pull request chooses
#   what is in it, and this helper prints a resolved string verbatim into output
#   an agent reads. A value containing a newline therefore closes the
#   `KEY=value` line the agent is reading and opens another one.
#
#   Three review rounds found that class at a new call site each time. Round 6
#   fixed it for `journal.dir` in commands/address.md and commands/learn.md;
#   round 7 added an opt-in flag and passed it at seven sites; round 8 found it
#   still live in commands/merge.md, where a newline in `.merge.strategy` forged
#   the `MERGE_SETTINGS_STATE=ok` line the merge gate reads, and in
#   `learning.transcriptDir`, which another process reprints. An opt-in guard is
#   only as good as the list of sites someone remembered, and that list was
#   wrong three times. So the refusal is the default and opting OUT is explicit.
#
#   Every expression any caller passes resolves a single scalar key — audited at
#   the revision that made this the default; `--compact` returns JSON, which is
#   one line by construction. A caller that genuinely needs raw bytes has
#   --allow-control-chars.

set -uo pipefail

MODE="-r"
DEFAULT_VALUE=""
DEFAULT_SET=0
ALLOW_CONTROL=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --default)
      [ $# -lt 2 ] && { echo "cascade-resolve: --default requires a value" >&2; exit 2; }
      DEFAULT_VALUE="$2"
      DEFAULT_SET=1
      shift 2
      ;;
    --compact)
      MODE="-c"
      shift
      ;;
    --scalar)
      # Now the default. Accepted so a call site written against the revision
      # that introduced it is not broken by its own defensiveness.
      shift
      ;;
    --allow-control-chars)
      ALLOW_CONTROL=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "cascade-resolve: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

EXPR="${1:-}"
[ -z "$EXPR" ] && {
  echo "cascade-resolve: missing <jq-expression>. Usage: $0 [--default <v>] [--compact] <jq-expression>" >&2
  exit 2
}
# Flags after the expression were silently ignored — the parse loop breaks at the
# first non-flag — so `cascade-resolve '.journal.dir' --scalar` resolved without
# the guard and reported nothing. A caller cannot be told about it by behaviour,
# so it is refused.
if [ $# -gt 1 ]; then
  echo "cascade-resolve: unexpected argument after the expression: $2 (flags must precede it)" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "cascade-resolve: WARN: jq not installed; cannot resolve cascade" >&2
  if [ $DEFAULT_SET -eq 1 ]; then
    printf '%s\n' "$DEFAULT_VALUE"
    exit 0
  fi
  exit 2
fi

LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"

for SETTINGS in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS" ] || continue

  # Capture stdout and stderr separately. `2>&1` would mix jq's parse-error
  # text with the resolved value when jq emits warnings on stderr while
  # exiting 0 (older jq versions can do this).
  STDERR_TMP=$(mktemp -t cascade-resolve.err.XXXXXX 2>/dev/null) || STDERR_TMP="/tmp/cascade-resolve.err.$$"
  RESULT=$(jq $MODE "$EXPR" "$SETTINGS" 2>"$STDERR_TMP")
  EXIT=$?

  if [ $EXIT -ne 0 ]; then
    ERR=$(tr '\n' ' ' <"$STDERR_TMP" 2>/dev/null | cut -c1-200)
    rm -f "$STDERR_TMP" 2>/dev/null
    echo "cascade-resolve: WARN: failed to parse $SETTINGS (jq exit=$EXIT, error: $ERR); skipping this source" >&2
    continue
  fi
  rm -f "$STDERR_TMP" 2>/dev/null

  # Treat jq's "null" output as not-found. Boolean callers MUST use a BARE
  # expression (`.flow.workflows.enabled`): jq then prints "false" verbatim
  # and an explicit project-level false wins over a lower-precedence true.
  # Both `// empty` and `// null` treat false as falsy and swallow it, so a
  # project's `enabled: false` would fall through to the plugin default.
  # `// empty` remains fine for string/number keys (tests/flow-cycle14-
  # behavioral.test.sh pins both behaviours).
  if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
    if [ "$ALLOW_CONTROL" -eq 0 ]; then
      # A control character here is either corruption or an injection. It is
      # never part of a path, a name, or a flag, so refusing costs nothing a
      # caller would miss, and refusing silently would be the failure this
      # whole plugin is written to avoid: report it, then fall back.
      #
      # LC_ALL=C so [[:cntrl:]] is the C locale's byte class (0x00-0x1F, 0x7F)
      # rather than whatever the caller's locale makes of it — the same reason
      # bin/flow-finding-route.sh pins LC_ALL for its bracket ranges. That class
      # cannot express the Unicode separators, so the three that a consumer may
      # treat as a line break are matched as their UTF-8 byte sequences: U+0085
      # NEL, U+2028 LINE SEPARATOR, U+2029 PARAGRAPH SEPARATOR. Python's
      # str.splitlines() — which bin/_journal_manifest.py uses — splits on all
      # three, so a value carrying one is a forgery there even though a shell
      # echo would print it as one line.
      _REFUSED=0
      if ( LC_ALL=C
           case "$RESULT" in
             *[[:cntrl:]]*) exit 0 ;;
           esac
           case "$RESULT" in
             *$'\302\205'*|*$'\342\200\250'*|*$'\342\200\251'*) exit 0 ;;
           esac
           exit 1 ); then _REFUSED=1; fi
      if [ "$_REFUSED" -eq 1 ]; then
        echo "cascade-resolve: WARN: the value resolved for $EXPR from $SETTINGS contains a control character or a Unicode line separator (a newline forges a second KEY=value line for whoever reads this); refusing it" >&2
        if [ $DEFAULT_SET -eq 1 ]; then
          printf '%s\n' "$DEFAULT_VALUE"
          exit 0
        fi
        exit 2
      fi
    fi
    printf '%s\n' "$RESULT"
    exit 0
  fi
done

# No source resolved a non-empty value
if [ $DEFAULT_SET -eq 1 ]; then
  printf '%s\n' "$DEFAULT_VALUE"
fi
exit 0
