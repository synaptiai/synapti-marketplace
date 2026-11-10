# shellcheck shell=bash
# The documentation of the tier checks says what they catch, what they do not,
# and what stops a merge or release that reaches GitHub, and says nothing the
# hooks no longer do.
#
# Ways it can be wrong, written down before the checks:
#   D1 a doc still claims the hook asks about text it cannot read, or that a
#      script, an alias or eval cannot hide an action from the checks
#   D2 a doc lists ask rules that are not the ones setup writes (a rule added
#      to the script and not documented, or the reverse)
#   D3 the README's Safety Model or the safety reference omits one of the
#      checks: the hook, the wrappers, Claude Code's ask rules, rulesets
#   D4 nothing says that GitHub rulesets, not the local checks, are what stops
#      a merge or release that reaches GitHub

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null; } || {
  printf '%s\n' "run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

TD_P="$REPO_ROOT/plugins/flow"
TD_README="$TD_P/README.md"
TD_SAFETY="$TD_P/references/three-tier-safety.md"
TD_GATES="$TD_P/references/gate-configuration.md"
TD_SCRIPT="$TD_P/bin/flow-setup-permissions.sh"

_td_has() {   # <file> <fixed text> <what>
  if grep -qF -- "$2" "$1"; then _flow_assert_pass "$3"; else _flow_assert_fail "$3: '$2' not found in ${1#"$REPO_ROOT"/}"; fi
}
_td_lacks() {   # <file> <fixed text> <what>
  if grep -qF -- "$2" "$1"; then _flow_assert_fail "$3: '$2' is still in ${1#"$REPO_ROOT"/}"; else _flow_assert_pass "$3"; fi
}

_flow_test_begin "tier docs: no claim the checks no longer make (D1)"
for F in "$TD_README" "$TD_SAFETY" "$TD_GATES" "$TD_P/commands/setup.md"; do
  _td_lacks "$F" "cannot hide the action" "no claim that nothing can hide an action"
  _td_lacks "$F" "asks, since it may merge or release" "no ask for a GraphQL query the hook cannot read"
  _td_lacks "$F" "flow cannot read from the command text" "no ask for a program the hook cannot read"
  _td_lacks "$F" "under a command word that is a variable (\`\$GH pr merge 7\`), asks" "no ask under a variable command word"
  _td_lacks "$F" "BD_DATA_PROGRAMS" "no data-program list"
done

_flow_test_begin "tier docs: the ask rules documented are the ones setup writes (D2)"
TD_RULES=$(sed -n "s/^RULES='\(.*\)'\$/\1/p" "$TD_SCRIPT" | jq -r '.[]' 2>/dev/null)
TD_N=$(printf '%s\n' "$TD_RULES" | grep -c 'Bash(')
assert_equal "9" "$TD_N" "the setup script writes nine rules"
while IFS= read -r R; do
  [ -n "$R" ] || continue
  _td_has "$TD_SAFETY" "\`$R\`" "the safety reference lists $R"
done <<EOF
$TD_RULES
EOF
TD_DOC_N=$(grep -oE '`Bash\([^`]*\)`' "$TD_SAFETY" | sort -u | wc -l | tr -d ' ')
assert_equal "$TD_N" "$TD_DOC_N" "the safety reference lists no rule the script does not write"

_flow_test_begin "tier docs: each check is described, with what it does not cover (D3)"
_td_has "$TD_README" "**The \`tier-gate.sh\` hook**" "README describes the hook"
_td_has "$TD_README" "It does not ask about text it cannot read" "README says what the hook does not ask about"
_td_has "$TD_README" "**Flow's \`git\` and \`gh\` wrappers**" "README describes the wrappers"
_td_has "$TD_README" "**Claude Code's own ask rules**" "README describes the ask rules"
_td_has "$TD_README" "do not see a tag pushed by its name alone" "README says what the ask rules miss"
_td_has "$TD_README" "**GitHub rulesets**" "README describes the rulesets"
_td_has "$TD_SAFETY" "### Claude Code's ask rules" "the safety reference has the ask rules section"
_td_has "$TD_SAFETY" "The hook acts only on the gh and git commands it can read." "the safety reference says what the hook reads"
_td_has "$TD_SAFETY" "What none of these checks covers:" "the safety reference lists what no check covers"
_td_has "$TD_GATES" "text it cannot read" "gate configuration says what the hook does not ask about"

_flow_test_begin "tier docs: rulesets are what stops a merge or release on GitHub (D4)"
_td_has "$TD_README" "They are what stops a merge or release that reaches GitHub" "README"
_td_has "$TD_SAFETY" "are what stops a merge or release that reaches GitHub" "the safety reference"
