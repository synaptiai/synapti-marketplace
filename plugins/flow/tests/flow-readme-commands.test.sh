# Tests for plugins/flow/README.md command surface.
#
# Guards the count-drift fix dynamically: the README "COMMANDS (N)" header must
# equal the actual number of commands/*.md files, so the next added/removed
# command can't silently desync the docs again.

README="$REPO_ROOT/plugins/flow/README.md"
CMD_DIR="$REPO_ROOT/plugins/flow/commands"

_flow_test_begin "AC-7: README COMMANDS (N) matches the actual command-file count"
ACTUAL=$(ls -1 "$CMD_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
DOC_N=$(grep -oE 'COMMANDS \(([0-9]+)\)' "$README" | grep -oE '[0-9]+' | head -1)
assert_equal "$ACTUAL" "$DOC_N" "README COMMANDS ($DOC_N) equals $ACTUAL command files"

_flow_test_begin "AC-7: README leads with Work-first framing"
CONTENT=$(cat "$README")
assert_contains "you don't manage it by hand" "$CONTENT" "Work-first lead present"
assert_contains "### Work (intent) commands" "$CONTENT" "intent commands section heading"

_flow_test_begin "AC-7: runtime primitives demoted to Advanced / runtime internals"
assert_contains "### Advanced / runtime internals" "$CONTENT" "Advanced subsection present"
for c in goal workflow trigger run resume watch; do
  assert_contains "\`/flow:$c\`" "$CONTENT" "runtime command /flow:$c documented in Advanced"
done

_flow_test_begin "AC-7: /flow:goal create reframed as the --manual path"
assert_contains '`/flow:goal create` is the `--manual` path' "$CONTENT" "goal create reframed as manual-only"
