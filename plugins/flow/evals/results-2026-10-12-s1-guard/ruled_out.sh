#!/usr/bin/env bash
# Reads commands separated by NUL bytes on stdin and prints, for each, one
# line: 1 when the cheap check of the shipped hook library
# (hooks/scripts/lib/s1-guard.sh, _g_ruled_out) rules it out, 0 when it would
# be sent. Used by build_sets.py and summarize.py so the measurement applies
# the check the hook applies.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
LIB="${FLOW_GUARD_LIB:-$HERE/../../hooks/scripts/lib/s1-guard.sh}"
# shellcheck source=../../hooks/scripts/lib/s1-guard.sh
. "$LIB" || { printf 'ruled_out.sh: cannot load %s\n' "$LIB" >&2; exit 1; }
while IFS= read -r -d '' c; do
  # In a subshell, as the hook runs it: a parser that fails means sent.
  if ( _g_ruled_out "$c" ) 2>/dev/null; then echo 1; else echo 0; fi
done
