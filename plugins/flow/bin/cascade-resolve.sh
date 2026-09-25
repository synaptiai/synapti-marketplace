#!/usr/bin/env bash
# cascade-resolve.sh — read a flow plugin setting from the standard Claude Code
# settings cascade with per-source parse-error surfacing.
#
# Resolves a jq expression against four trusted sources, in precedence order
# (highest first — first non-empty value wins):
#
#   1. .claude/settings.flow.local.json — project-local; gitignored
#   2. .claude/settings.flow.json       — project-shared; committed
#   3. the user settings file — user-global: $FLOW_USER_SETTINGS when it is
#      set to an absolute path, otherwise $HOME/.claude/settings.flow.json
#   4. the plugin's own settings.json — plugin default. Taken from
#      $CLAUDE_PLUGIN_ROOT when set, otherwise from this script's own
#      directory: never from a path relative to the working directory, which
#      during a review belongs to the pull request under review.
#
# Usage:
#   cascade-resolve.sh [--default <fallback>] [--compact] [--allow-control-chars] <jq-expression>
#
# Flags:
#   --default <value>     value printed on stdout when no source has the key
#   --compact             use `jq -c` (preserves JSON quoting) instead of `jq -r`
#   --allow-control-chars print a value containing a control character instead of
#                         refusing it. See SECURITY below.
#   --no-repo-settings    ignore both settings files under the working directory,
#                         the project file and the local file: during a review
#                         either can come with the pull request (the local file
#                         is gitignored by convention, but a pull request can
#                         commit it, or a symlink to it). For a setting the
#                         change under review must not choose; a WARN names each
#                         file ignored that held a value. The user tier and the
#                         plugin default still apply, unless the file either one
#                         names resolves inside the repository (or is a symlink):
#                         then it is skipped with a WARN, and a script that is
#                         itself inside the repository refuses to answer.
#   --user-settings-path  print the user settings file this script would read
#                         (FLOW_USER_SETTINGS or $HOME/.claude/settings.flow.json,
#                         after the checks below), or nothing when there is none,
#                         and exit 0. Callers that read the user tier themselves
#                         use it, so one place decides which file that is.
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
#   Three review rounds found that class at a new call site each time. The first
#   fix guarded two sites by hand; the second added an opt-in flag, passed it at
#   seven, and claimed in this header that every consumer passed it — a claim
#   that was false when written, because commands/merge.md was still resolving
#   `.merge.strategy` without it, so a newline there forged the
#   `MERGE_SETTINGS_STATE=ok` line the merge gate reads. An opt-in guard is only
#   as good as the list of sites someone remembered, and that list was wrong
#   three times. So the refusal is the default and opting OUT is explicit.
#
#   Every expression any caller passes selects a single key. `.learning.sources`
#   resolves a JSON array and is read with --compact, whose `jq -c` output is one
#   line — but one line is not the same as safe: `jq -c` escapes C0 controls and
#   prints U+0085 and U+2028/U+2029 raw, so those are refused on this path too.
#   A caller that genuinely needs raw bytes has --allow-control-chars.

set -uo pipefail
# The plugin-tier directory is found with cd; an exported CDPATH makes cd print
# the match it found, and the captured path would be two lines.
unset CDPATH

MODE="-r"
DEFAULT_VALUE=""
DEFAULT_SET=0
ALLOW_CONTROL=0
NO_REPO_SETTINGS=0
USER_PATH_ONLY=0

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
    --no-repo-settings)
      NO_REPO_SETTINGS=1
      shift
      ;;
    --user-settings-path)
      USER_PATH_ONLY=1
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
[ "$USER_PATH_ONLY" -eq 1 ] && EXPR="${EXPR:-.}"
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
# FLOW_USER_SETTINGS names a different user settings file. The review-precision
# eval uses it to give each session its own settings, because changing HOME
# logs the session out. It comes from the environment the reviewer started,
# not from the working tree. A relative value is refused: it would resolve
# inside the working directory, which --no-repo-settings exists to keep out.
# A value that names no regular file is refused too: taking it would replace
# the user tier with nothing, silently.
if [ -n "${FLOW_USER_SETTINGS:-}" ]; then
  case "$FLOW_USER_SETTINGS" in
    /*)
      if [ -f "$FLOW_USER_SETTINGS" ]; then
        USER_SETTINGS="$FLOW_USER_SETTINGS"
      else
        printf '%s\n' "cascade-resolve: WARN: FLOW_USER_SETTINGS='$FLOW_USER_SETTINGS' is not a file; ignoring it and reading $USER_SETTINGS" >&2
      fi ;;
    *) printf '%s\n' "cascade-resolve: WARN: FLOW_USER_SETTINGS='$FLOW_USER_SETTINGS' is not an absolute path; ignoring it and reading $USER_SETTINGS" >&2 ;;
  esac
fi
# The plugin tier is THIS script's own settings.json, found as a sibling of
# the directory it lives in - never a path relative to the working directory.
# A relative fallback meant that during a review, where the working directory
# is the checked-out pull request, a branch shipping plugins/flow/settings.json
# supplied the plugin-tier defaults governing its own review: verified, a
# planted file made the convention checker report forged commit types and
# turned the FlowRun off. bin/flow-clone-scan.sh already defended against this
# by pinning CLAUDE_PLUGIN_ROOT at its call site; deriving it here covers every
# caller instead of every call site, including the ones not yet written.
#
# CLAUDE_PLUGIN_ROOT still wins when set, because a real command context sets
# it to the plugin that is actually loaded.
_cr_self="$0"
_cr_hops=0
while [ -L "$_cr_self" ] && [ "$_cr_hops" -lt 40 ]; do
  _cr_link=$(readlink "$_cr_self") || break
  case "$_cr_link" in
    /*) _cr_self="$_cr_link" ;;
    *)  _cr_self="$(dirname "$_cr_self")/$_cr_link" ;;
  esac
  _cr_hops=$((_cr_hops + 1))
done
_cr_dir="$(cd "$(dirname "$_cr_self")" 2>/dev/null && pwd -P)"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_SETTINGS="$CLAUDE_PLUGIN_ROOT/settings.json"
elif [ -n "$_cr_dir" ]; then
  PLUGIN_SETTINGS="$_cr_dir/../settings.json"
else
  PLUGIN_SETTINGS=""
fi

# --no-repo-settings reads nothing that lives inside the repository under
# review, whichever tier names it: a user settings file, CLAUDE_PLUGIN_ROOT or
# this script itself can all point into the checked-out pull request. Each
# source is judged by the directory it is actually in: a symlink is followed to
# its target, and the target's directory is inside the repository when it, or
# one of its parents, is the same directory as the repository's top (`-ef`,
# which compares the directories themselves, so letter case, symlinks and mount
# spellings do not matter). The top is git's toplevel; when git cannot say, the
# nearest parent holding .git, else the working directory. A source that cannot
# be resolved is refused too, so a failure never widens what is read.
if [ "$NO_REPO_SETTINGS" -eq 1 ]; then
  _cr_top=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$_cr_top" ]; then
    _cr_top=$(pwd -P)
    _cr_up=$_cr_top
    while [ -n "$_cr_up" ] && [ "$_cr_up" != / ]; do
      if [ -e "$_cr_up/.git" ]; then _cr_top=$_cr_up; break; fi
      _cr_up=$(dirname "$_cr_up")
    done
  fi
  _cr_top=$(cd "$_cr_top" 2>/dev/null && pwd -P)
  # Only an absolute top can be judged against; anything else (a working
  # directory that was removed prints nothing, and cd "" then stays put and
  # prints a relative answer) counts as unresolved, which refuses.
  case "$_cr_top" in /*) ;; *) _cr_top="" ;; esac
  # _cr_where <file>: 0 inside the repository, 1 outside, 2 cannot be resolved
  # (a broken or looping link, a directory that cannot be entered, no top).
  _cr_where() {
    local f="$1" hops=0 l d
    while [ -L "$f" ] && [ "$hops" -lt 40 ]; do
      l=$(readlink "$f") || return 2
      case "$l" in
        /*) f="$l" ;;
        *)  f="$(dirname "$f")/$l" ;;
      esac
      hops=$((hops + 1))
    done
    [ -L "$f" ] && return 2
    d=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || return 2
    [ -n "$d" ] && [ -n "$_cr_top" ] || return 2
    while :; do
      [ "$d" -ef "$_cr_top" ] && return 0
      [ "$d" = / ] && return 1
      d=$(dirname "$d")
    done
  }
  if [ -n "$_cr_dir" ]; then
    _cr_where "$_cr_dir/cascade-resolve.sh"; _cr_rc=$?
    if [ "$_cr_rc" -ne 1 ]; then
      echo "cascade-resolve: ERROR: this script is inside the repository under review, or its location cannot be resolved ($_cr_dir); refusing to answer with --no-repo-settings" >&2
      exit 2
    fi
  fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -n "$PLUGIN_SETTINGS" ]; then
    _cr_where "$PLUGIN_SETTINGS"; _cr_rc=$?
    if [ "$_cr_rc" -eq 0 ]; then
      echo "cascade-resolve: WARN: CLAUDE_PLUGIN_ROOT ($CLAUDE_PLUGIN_ROOT) is inside the repository under review; reading this script's own plugin default instead" >&2
      PLUGIN_SETTINGS="$_cr_dir/../settings.json"
    elif [ "$_cr_rc" -eq 2 ]; then
      echo "cascade-resolve: WARN: CLAUDE_PLUGIN_ROOT ($CLAUDE_PLUGIN_ROOT) cannot be resolved; reading this script's own plugin default instead" >&2
      PLUGIN_SETTINGS="$_cr_dir/../settings.json"
    fi
  fi
  if [ -f "$USER_SETTINGS" ]; then
    _cr_where "$USER_SETTINGS"; _cr_rc=$?
    if [ "$_cr_rc" -eq 0 ]; then
      echo "cascade-resolve: WARN: ignoring the user settings file $USER_SETTINGS: it is inside the repository under review" >&2
      USER_SETTINGS=""
    elif [ "$_cr_rc" -eq 2 ]; then
      echo "cascade-resolve: WARN: ignoring the user settings file $USER_SETTINGS: its location cannot be resolved" >&2
      USER_SETTINGS=""
    fi
  fi
fi

if [ "$USER_PATH_ONLY" -eq 1 ]; then
  if [ -n "$USER_SETTINGS" ] && [ -f "$USER_SETTINGS" ]; then printf '%s\n' "$USER_SETTINGS"; fi
  exit 0
fi

for SETTINGS in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -n "$SETTINGS" ] && [ -f "$SETTINGS" ] || continue

  # --no-repo-settings: neither file under the working directory is read.
  # Deciding which of them the reviewer wrote (git tracking, symlinks, case)
  # was a check over a path the kernel resolves differently, and each version
  # of it had a way around; not reading them leaves nothing to get around. Say
  # so only when the file actually held a value for this expression, so the
  # warning is about a setting that was ignored, not about a file that exists.
  if [ "$NO_REPO_SETTINGS" -eq 1 ]; then
    if [ "$SETTINGS" = "$PROJECT_SETTINGS" ] || [ "$SETTINGS" = "$LOCAL_SETTINGS" ]; then
      _cr_ignored=$(jq $MODE "$EXPR" "$SETTINGS" 2>/dev/null)
      if [ -n "$_cr_ignored" ] && [ "$_cr_ignored" != "null" ]; then
        echo "cascade-resolve: WARN: ignoring $SETTINGS for $EXPR: the repository supplies that file, and this setting is read from the reviewer's own settings only" >&2
      fi
      continue
    fi
  fi

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
      # bin/flow-finding-route.sh pins LC_ALL for its bracket ranges. Pinning it
      # NARROWS the class: in a UTF-8 locale [[:cntrl:]] also covers the C1 range
      # U+0080-U+009F, and a C1 character injected into an agent's output is an
      # ANSI escape introducer (U+009B is CSI) as well as, for U+0085 NEL, a line
      # break Python's str.splitlines() takes. So the C1 range is matched
      # explicitly as its two-byte UTF-8 form, and the two Unicode separators
      # that lie outside it (U+2028, U+2029) are matched the same way.
      #
      # The byte-class arms are what make this deterministic: the pattern means
      # the same thing under every locale a caller might have.
      _REFUSED=0
      if ( LC_ALL=C
           case "$RESULT" in
             *[[:cntrl:]]*) exit 0 ;;
           esac
           # C1 control characters, U+0080-U+009F, as two-byte UTF-8. One arm
           # covers NEL (U+0085) as well as the escape introducers.
           case "$RESULT" in
             *$'\302'[$'\200'-$'\237']*) exit 0 ;;
           esac
           # U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR, outside C1.
           case "$RESULT" in
             *$'\342\200\250'*|*$'\342\200\251'*) exit 0 ;;
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
