# [flow] Shared `<base>..<head>` argument handling for the bin/ helpers.
#
# shellcheck shell=bash
#
# Sourced, never executed. Two helpers need the same two things — split a
# positional range, and refuse a reference shape that would change what a git
# command means — and two copies of a security check drift. The clone scan
# flagged the second copy the day it was written, which is the argument for
# this file existing.
#
# Callers set PROG and read FLOW_RANGE_BASE / FLOW_RANGE_HEAD.

# flow_range_positional <argv-entry> <current-base> <current-head>
#   0 — parsed; FLOW_RANGE_BASE and FLOW_RANGE_HEAD are set
#   1 — the range was already given through flags, so this would be a second,
#       silently-winning specification of the same thing
#   2 — the entry is not a range
flow_range_positional() {
  if [ -n "${2:-}" ] || [ -n "${3:-}" ]; then
    return 1
  fi
  case "$1" in
    *..*)
      # shellcheck disable=SC2034  # both are read by the sourcing helper
      FLOW_RANGE_BASE="${1%%..*}"
      # shellcheck disable=SC2034  # both are read by the sourcing helper
      FLOW_RANGE_HEAD="${1##*..}"
      return 0
      ;;
  esac
  return 2
}

# flow_range_validate <ref>...
#   0 — every reference is safe to hand to git as an argv entry
#   1 — one is not; the caller reports which and exits
#
# References reach git as argv entries, never a shell string, so a reference
# cannot run a command. What this refuses is the shapes git itself reads as
# options or as pathspec separators, which would change what the command means.
flow_range_validate() {
  for _flow_ref in "$@"; do
    case "$_flow_ref" in
      -*|*' '*|'') return 1 ;;
    esac
  done
  return 0
}

# flow_range_parse_args <argv>...
#   The whole shared command line: `--base <ref>`, `--head <ref>`,
#   `<base>..<head>`, and `--help`. Anything else is left for the caller in
#   FLOW_RANGE_REST, in order, so a helper with its own options parses only
#   those and the two helpers do not each carry a copy of this loop.
#
#   Sets FLOW_RANGE_BASE, FLOW_RANGE_HEAD and FLOW_RANGE_REST. Requires the
#   caller to define PROG and usage(); exits 1 on a malformed range, and 0 via
#   the caller's usage() on --help.
#
#   A caller whose own options take values sets FLOW_RANGE_VALUE_OPTS to the
#   space-separated list of them. Their values are then passed through
#   untouched, which matters because a value like `../foo/**` contains `..` and
#   would otherwise be read as a range.
#
#   Both refs must be present and safe before the caller proceeds; that is the
#   caller's check, because only it knows what to print when they are not.
flow_range_parse_args() {
  FLOW_RANGE_BASE=""
  FLOW_RANGE_HEAD=""
  FLOW_RANGE_REST=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --base)
        [ $# -ge 2 ] || { usage; exit 1; }
        FLOW_RANGE_BASE="$2"; shift 2 ;;
      --head)
        [ $# -ge 2 ] || { usage; exit 1; }
        FLOW_RANGE_HEAD="$2"; shift 2 ;;
      --help|-h)
        usage; exit 0 ;;
      *..*)
        # A second way of saying the same thing has no silent winner.
        [ -z "$FLOW_RANGE_BASE" ] && [ -z "$FLOW_RANGE_HEAD" ] || { usage; exit 1; }
        FLOW_RANGE_BASE="${1%%..*}"
        FLOW_RANGE_HEAD="${1##*..}"
        shift ;;
      *)
        # An option of the caller's. If it takes a value, its value is passed
        # through WITHOUT being looked at: a value like `../foo/**` contains
        # `..` and would otherwise be taken for a range.
        _flow_takes_value=0
        for _flow_vo in ${FLOW_RANGE_VALUE_OPTS:-}; do
          if [ "$1" = "$_flow_vo" ]; then
            _flow_takes_value=1
            break
          fi
        done
        if [ "$_flow_takes_value" = 1 ] && [ $# -ge 2 ]; then
          FLOW_RANGE_REST[${#FLOW_RANGE_REST[@]}]="$1"
          FLOW_RANGE_REST[${#FLOW_RANGE_REST[@]}]="$2"
          shift 2
          continue
        fi
        FLOW_RANGE_REST[${#FLOW_RANGE_REST[@]}]="$1"
        shift ;;
    esac
  done
  return 0
}
