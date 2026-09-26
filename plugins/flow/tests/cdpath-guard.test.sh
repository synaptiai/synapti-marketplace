# Every script unsets CDPATH before it could run cd.
#
# With CDPATH exported, `cd X` for a relative X looks for X under the CDPATH
# directories first and prints the directory it found. A captured
# `SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)` then holds two lines, or the
# path of a different directory, and the script reads its helpers and plugin
# defaults from there. cascade-resolve.test.sh and flow-eval-harness.test.sh
# show the effect end to end on two scripts.
#
# The rule does not depend on finding which scripts run cd: every script under
# bin/ and hooks/scripts/, and both test runners, unsets CDPATH once, before
# any line that mentions cd. A detector for "runs cd" missed real commands
# after a quoted word; not needing one removes that question.

FLOW_DIR="$REPO_ROOT/plugins/flow"

# _cdg_check <file>: prints nothing when the file unsets CDPATH exactly once,
# before its first non-comment line containing `cd `; otherwise a reason.
_cdg_check() {
  local unsets first_unset first_cd
  unsets=$(grep -c '^unset CDPATH$' "$1")
  if [ "$unsets" != "1" ]; then printf '%s unsets CDPATH %s times\n' "$1" "$unsets"; return; fi
  first_unset=$(grep -n '^unset CDPATH$' "$1" | head -1 | cut -d: -f1)
  first_cd=$(awk '/^[[:space:]]*#/ { next } /(^|[^a-zA-Z_])cd / { print NR; exit }' "$1")
  if [ -n "$first_cd" ] && [ "$first_cd" -lt "$first_unset" ]; then
    printf '%s runs cd at line %s, before unset CDPATH at line %s\n' "$1" "$first_cd" "$first_unset"
  fi
}

_flow_test_begin "every script unsets CDPATH once, before any cd"
CDG_CHECKED=0; CDG_BAD=""
for f in "$FLOW_DIR"/bin/*.sh "$FLOW_DIR"/hooks/scripts/*.sh "$FLOW_DIR/tests/run.sh" "$REPO_ROOT/tests/run-all.sh"; do
  CDG_CHECKED=$((CDG_CHECKED + 1))
  CDG_BAD="$CDG_BAD$(_cdg_check "$f")"
done
assert_match '^[1-9][0-9]+$' "$CDG_CHECKED" "the scan reached the scripts"
assert_equal "" "$CDG_BAD" "scripts that break the rule"
