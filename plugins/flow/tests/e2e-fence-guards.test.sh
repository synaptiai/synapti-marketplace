# shellcheck shell=bash
# End-to-end: every ```bash fence a flow command ships passes flow's own
# PreToolUse Bash guards. The agent runs these fences through the Bash tool, so
# each one reaches block-force-push.sh, block-destructive.sh,
# block-unchecked-merge.sh and block-secrets.sh first. A fence a guard refuses
# never runs: the agent has to rewrite the command, and the step the command
# file describes does not happen as written.
#
# Each fence is fed to each guard as the PreToolUse payload the hook runner
# sends, in a scratch repository. A refusal (exit 2) fails the fence. The
# fences that hold an unfilled placeholder the agent replaces before running
# them (`<specific-files>`, `{PR_NUMBER}`) are listed, not run: the guard
# rightly refuses the placeholder text itself.
#
# Ways it can be wrong, written down before the scenarios:
#   F1 a fence a guard refuses ships, and nothing fails
#   F2 no fence is extracted (a changed fence marker, a wrong path), and an
#      empty loop passes
#   F3 the placeholder exemption grows to cover a fence that is not a
#      template, hiding its refusal
#   F4 a guard that did not run (missing, not executable, crashed with a status
#      other than 0 or 2) counts as a pass
#   F5 a fence is read from the wrong line range, so the text the guard sees is
#      not the text the agent runs

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

GUARDS="block-force-push block-destructive block-unchecked-merge block-secrets"

# The fences that are templates. Each entry is <command file>:<text inside the
# fence>; the expectation below pins that exactly these are skipped (F3).
TEMPLATE_FENCES="commit.md:git add <specific-files>
merge.md:gh pr merge {PR_NUMBER}
resolve.md:git checkout <headRefName>"

_payload() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

_is_template() {
  local md=$1 fence=$2 entry file text
  while IFS= read -r entry; do
    file=${entry%%:*}; text=${entry#*:}
    [ "$md" = "$file" ] || continue
    case "$fence" in *"$text"*) return 0 ;; esac
  done <<EOF
$TEMPLATE_FENCES
EOF
  return 1
}

_flow_test_begin "every bash fence in commands/*.md passes the PreToolUse Bash guards"
e2e_new fence-guards
e2e_describe "each \`\`\`bash fence of each command file, fed to each Bash guard as its payload; a refusal fails the fence (F1)"
e2e_repo feature/issue-1-fence-guards

FENCES=0
SKIPPED=""
mkdir -p "$E2E_DIR/fences"
for md_path in "$E2E_PLUGIN_DIR"/commands/*.md; do
  md=$(basename "$md_path")
  # Number the fences of this file and remember each one's first line, so a
  # failure names the line the reader can open (F5).
  awk -v out="$E2E_DIR/fences" -v md="$md" '
    /^[[:space:]]*```bash[[:space:]]*$/ && !inb { inb = 1; n++; f = sprintf("%s/%s.%03d", out, md, n); printf "%d\n", NR + 1 > (f ".line"); printf "" > f; next }
    /^[[:space:]]*```[[:space:]]*$/ && inb { inb = 0; close(f); next }
    inb { print > f }
  ' "$md_path"
done
for fence_file in "$E2E_DIR"/fences/*.md.[0-9][0-9][0-9]; do
  [ -f "$fence_file" ] || continue
  md=$(basename "$fence_file"); md=${md%.*}
  line=$(cat "$fence_file.line")
  text=$(cat "$fence_file")
  FENCES=$((FENCES + 1))
  if _is_template "$md" "$text"; then
    SKIPPED="$SKIPPED$md:$line
"
    continue
  fi
  for g in $GUARDS; do
    e2e_run_hook "hooks/scripts/$g.sh" "$(_payload "$text")"
    case "$E2E_RC" in
      0) ;;
      2) _e2e_result fail "$md:$line passes $g (refused: $(printf '%s' "$E2E_ERR" | head -n 1))" ;;
      *) _e2e_result fail "$md:$line passes $g (the guard exited $E2E_RC, so it did not decide; F4)" ;;
    esac
  done
done

# F2: the command files hold well over ninety bash fences; an empty or short
# loop is a broken extraction, not a clean result.
if [ "$FENCES" -ge 90 ]; then
  _e2e_result pass "at least 90 bash fences were checked ($FENCES)"
else
  _e2e_result fail "at least 90 bash fences were checked (got $FENCES)"
fi
# F3: exactly the three template fences were skipped.
e2e_expect_equal 3 "$(printf '%s' "$SKIPPED" | sed '/^$/d' | wc -l | tr -d ' ')" "the number of template fences skipped"
