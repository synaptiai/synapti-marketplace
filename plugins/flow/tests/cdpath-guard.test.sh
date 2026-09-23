# Every script that runs cd unsets CDPATH before its first cd.
#
# With CDPATH exported, `cd X` for a relative X looks for X under the CDPATH
# directories first and prints the directory it found. A captured
# `SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)` then holds two lines, or the
# path of a different directory, and the script reads its helpers and plugin
# defaults from there. cascade-resolve.test.sh and flow-eval-harness.test.sh
# show the effect on the two scripts that decide settings and build eval
# repositories; this suite holds the rest to the same line.

FLOW_DIR="$REPO_ROOT/plugins/flow"

# A real cd: `cd ` at command position, not in a comment and not inside a
# quoted word list (block-force-push.sh lists `cd` among safe command names).
_cd_lines() {
  awk '
    /^[[:space:]]*#/ { next }
    /" [^"]* cd / { next }
    /(^|[^a-zA-Z_#"])cd / { print NR }
  ' "$1"
}

_flow_test_begin "every bin/ and hooks/scripts/ script unsets CDPATH before its first cd"
CDG_CHECKED=0; CDG_BAD=""
for f in "$FLOW_DIR"/bin/*.sh "$FLOW_DIR"/hooks/scripts/*.sh; do
  first_cd=$(_cd_lines "$f" | head -1)
  [ -n "$first_cd" ] || continue
  CDG_CHECKED=$((CDG_CHECKED + 1))
  unset_at=$(grep -n '^unset CDPATH$' "$f" | head -1 | cut -d: -f1)
  if [ -z "$unset_at" ] || [ "$unset_at" -ge "$first_cd" ]; then
    CDG_BAD="$CDG_BAD ${f#"$FLOW_DIR"/}"
  fi
done
assert_match '^[1-9][0-9]+$' "$CDG_CHECKED" "the scan reached the scripts that run cd"
assert_equal "" "$CDG_BAD" "scripts whose first cd comes before any unset CDPATH"

