# shellcheck shell=bash
# The documentation of the tier checks says what they catch, what they do not,
# and what stops a merge or release that reaches GitHub, and makes no claim the
# hooks do not hold to. The ask rules it lists are compared with the rules the
# shipped setup fence installs in a scratch repository.
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
#   D5 a file of the plugin lists tiers.issueAssign and not tiers.issueUpdate
#      beside it (design github_writes_and_tiers L23-L30: the new key goes
#      every place issueAssign is listed, and this file asserts it)
#   D6 a command's tier table still says a pull request comment, review,
#      reply, body edit or re-requested review runs with no tier setting,
#      when tiers.issueUpdate covers it, or has no row for an issue edit the
#      command tells the agent to make (design github_writes_and_tiers L6-L17)
#   D7 the safety reference leaves out how the factory resolves a key (the
#      strictest of four sources) against the hook's cascade (the first
#      value), the fail-closed base fetch and its status lines, a person
#      subcommand that the hook asks about or denies, or that a comment
#      posted with your GitHub token counts as yours until the worker
#      sandbox arrives; or it says the hook's factory rules turn on for a
#      variable they do not read, or that a job parks with a status line
#      (design github_writes_and_tiers L37 and L48, residual_risks L3;
#      plan B10 outline, plan 7.2 items 4 and 14; tier-gate's factory check)
#   D8 the Actions table of gate configuration leaves out a gh command, REST
#      endpoint or GraphQL mutation that design github_writes_and_tiers
#      L6-L17 or the Q9 forms (plan 7.2 item 12) put under issueUpdate

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

# The plugin under test: the shipped one, or a copy E2E_PLUGIN_DIR names
# (a mutant made with e2e_copy_plugin).
TD_P="$E2E_PLUGIN_DIR"
TD_README="$TD_P/README.md"
TD_SAFETY="$TD_P/references/three-tier-safety.md"
TD_GATES="$TD_P/references/gate-configuration.md"

_td_has() {   # <file> <fixed text> <what>
  if grep -qF -- "$2" "$1"; then _flow_assert_pass "$3"; else _flow_assert_fail "$3: '$2' not found in ${1#"$REPO_ROOT"/}"; fi
}
_td_lacks() {   # <file> <fixed text> <what>
  if grep -qF -- "$2" "$1"; then _flow_assert_fail "$3: '$2' is still in ${1#"$REPO_ROOT"/}"; else _flow_assert_pass "$3"; fi
}

_flow_test_begin "tier docs: no claim that the hook asks about text it cannot read (D1)"
for F in "$TD_README" "$TD_SAFETY" "$TD_GATES" "$TD_P/commands/setup.md"; do
  _td_lacks "$F" "cannot hide the action" "no claim that nothing can hide an action"
  _td_lacks "$F" "asks, since it may merge or release" "no ask for a GraphQL query the hook cannot read"
  _td_lacks "$F" "flow cannot read from the command text" "no ask for a program the hook cannot read"
  _td_lacks "$F" "under a command word that is a variable (\`\$GH pr merge 7\`), asks" "no ask under a variable command word"
  _td_lacks "$F" "BD_DATA_PROGRAMS" "no data-program list"
done

_flow_test_begin "tier docs: the ask rules documented are the ones setup writes (D2)"
# The rules are the ones the shipped setup fence installs in a scratch
# repository, not the ones the script's source spells out. One shell is
# enough: the setup tests compare the fence's shells.
e2e_new td-setup-rules
e2e_describe "the shipped setup fence, run with the shared choice in a scratch repository, installs the rules the safety reference lists"
e2e_repo main
E2E_FENCE_SHELLS=bash e2e_run_fence PERM_FILE=shared "$E2E_ACTIVE_PLUGIN/commands/setup.md" "SETUP_PERMISSIONS_BEGIN"
e2e_expect_out "PERMISSIONS=written"
TD_RULES=$(jq -r '.permissions.ask[]' "$E2E_REPO/.claude/settings.json" 2>/dev/null)
TD_N=$(printf '%s\n' "$TD_RULES" | grep -c 'Bash(')
assert_equal "9" "$TD_N" "the setup script installs nine rules"
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
_td_has "$TD_SAFETY" "\`npx\`, \`bundle exec\`" "the safety reference names the launchers whose scripts are still read"

_flow_test_begin "tier docs: rulesets are what stops a merge or release on GitHub (D4)"
_td_has "$TD_README" "They are what stops a merge or release that reaches GitHub" "README"
_td_has "$TD_SAFETY" "are what stops a merge or release that reaches GitHub" "the safety reference"

_flow_test_begin "tier docs: every file that lists tiers.issueAssign lists tiers.issueUpdate (D5)"
# The scan leaves out tests/ and the recorded eval runs (evals/results-*):
# they are not documentation or settings, and e2e_copy_plugin leaves them
# out of a copy too.
TD_MISSING=""
TD_SEEN=0
while IFS= read -r F; do
  case "${F#"$TD_P"/}" in tests/*|evals/results-*) continue ;; esac
  TD_SEEN=$((TD_SEEN + 1))
  grep -q 'issueUpdate' "$F" || TD_MISSING="$TD_MISSING ${F#"$TD_P"/}"
done <<EOF
$(grep -rl 'issueAssign' "$TD_P" 2>/dev/null | LC_ALL=C sort)
EOF
if [ "$TD_SEEN" -gt 0 ]; then _flow_assert_pass "the scan found files naming issueAssign"; else _flow_assert_fail "the scan found no file naming issueAssign under $TD_P"; fi
assert_equal "" "$TD_MISSING" "files that name issueAssign but not issueUpdate"

_flow_test_begin "tier docs: the command tier tables put comments, reviews and pull request edits under tiers.issueUpdate (D6)"
for F in "$TD_P/commands/review.md" "$TD_P/commands/address.md"; do
  _td_lacks "$F" "no tier setting covers it" "no claim that no tier setting covers a comment or review"
  _td_lacks "$F" "no tier setting, no breadcrumb" "no claim that a reply, body edit or re-requested review has no tier setting"
  _td_has "$F" "Follows \`tiers.issueUpdate\`" "the tier table names tiers.issueUpdate"
done
# /flow:start tells the agent to update the issue with `gh issue edit` when it
# has no acceptance criteria; that edit sets a body, an issueUpdate write.
TD_START_ROW=$(grep -F '| `gh issue edit` ' "$TD_P/commands/start.md")
case "$TD_START_ROW" in
  *'tiers.issueUpdate'*) _flow_assert_pass "start.md's tier table has a row for its gh issue edit under tiers.issueUpdate" ;;
  *) _flow_assert_fail "start.md's tier table has no '| \`gh issue edit\` ' row naming tiers.issueUpdate" ;;
esac

_flow_test_begin "tier docs: the safety reference says how the factory applies the keys and what the hook does with its commands (D7)"
TD_FAC=$(awk '/^### The flow factory/{on=1; print; next} on && /^##/{exit} on' "$TD_SAFETY")
if [ -n "$TD_FAC" ]; then _flow_assert_pass "the safety reference has a section on the flow factory"; else _flow_assert_fail "no '### The flow factory' section in references/three-tier-safety.md"; fi
_td_fac_has() {   # <fixed text> <what>
  if printf '%s\n' "$TD_FAC" | grep -qF -- "$1"; then _flow_assert_pass "$2"; else _flow_assert_fail "$2: '$1' not found in the factory section"; fi
}
_td_fac_lacks() {   # <fixed text, any case> <what>
  if printf '%s\n' "$TD_FAC" | grep -qiF -- "$1"; then _flow_assert_fail "$2: '$1' is still in the factory section"; else _flow_assert_pass "$2"; fi
}
_td_fac_has "the strictest" "the engine takes the strictest value"
_td_fac_has "the first source that has a value" "the hook takes the first value"
_td_fac_has "BASE_FETCH_FAILED" "the fetch failure line"
_td_fac_has "BASE_REF_UNRESOLVED" "the unresolved base line"
_td_fac_has "credential helper" "the engine's git loads no credential helper"
_td_fac_has "A later release adds fetching from an origin that needs credentials." "a later release adds the authenticated fetch"
_td_fac_lacks "no workaround is documented" "no sentence about what the documentation leaves out"
# BASE_FETCH_FAILED is a line next prints; the park reason is tier_confirm,
# and the job parks before launch only when the session cannot confirm.
_td_fac_lacks "parks with \`BASE_FETCH_FAILED\`" "no park named after the fetch line"
_td_fac_has "tier_confirm" "the park before launch"
# tier-gate turns its factory rules on for these four variables only
# (_tg_in_factory), not for any FLOW_FACTORY_* name.
_td_fac_lacks "when a \`FLOW_FACTORY_*\` variable is set" "no claim that any FLOW_FACTORY_* variable turns the rules on"
# Matched as one fragment: FLOW_FACTORY_JOB and FLOW_FACTORY_DIRECTIVE also
# appear in the worker bullet, so a check per name would pass without them here.
_td_fac_has "run only in a factory: when \`FLOW_FACTORY_JOB\`, \`FLOW_FACTORY_DIRECTIVE\`, \`FLOW_FACTORY_IO\` or \`FLOW_FACTORY_MAIN\` is set" "the sentence that turns the rules on names the four variables tier-gate reads"
# Residual risk (design residual_risks L3; plan 7.2 item 4): a comment posted
# with the person's token counts as the person's, and the worker sandbox that
# keeps the token from workers comes in phase 1c.
_td_fac_has "posted with your GitHub token" "the engine cannot tell a comment posted with your token from yours"
_td_fac_has "\`gh auth token\`" "any process running as you can read the token"
_td_fac_has "worker sandbox" "the control that keeps the token from workers"
_td_fac_has "phase 1c" "when the worker sandbox arrives"
_td_has "$TD_SAFETY" "they are refused in \`claude -p\`" "what confirm does to flow's own comment and review posts in claude -p"
_td_fac_has "run it in a terminal outside Claude Code" "the deny text"
_td_fac_has "Without jq the hook cannot read the permission mode" "the jq-free deny"
_td_fac_has "the whole command" "a person call is asked about only as the whole command"
# The person subcommands are the Person group the shipped script prints
# (design github_writes_and_tiers L41).
TD_PERSON=$("$TD_P/bin/flow-factory.sh" usage 2>/dev/null | sed -n 's/^Person: //p')
if [ -n "$TD_PERSON" ]; then _flow_assert_pass "flow-factory.sh usage prints the Person group"; else _flow_assert_fail "flow-factory.sh usage printed no Person line"; fi
# Matched against the sentence that lists them only, up to its first full
# stop: `confirm` and `answer` also appear elsewhere in the section, as a tier
# value, as the subject of the next sentence and as an untiered form.
TD_LIST=$(printf '%s\n' "$TD_FAC" | sed -n 's/.*the person subcommands are \([^.]*\)\..*/\1/p')
if [ -n "$TD_LIST" ]; then _flow_assert_pass "the factory section has the sentence listing the person subcommands"; else _flow_assert_fail "no sentence with 'the person subcommands are' in the factory section"; fi
for W in $TD_PERSON; do
  if printf '%s\n' "$TD_LIST" | grep -qF -- "\`$W\`"; then _flow_assert_pass "the list names the person subcommand $W"; else _flow_assert_fail "the list of person subcommands does not name $W"; fi
done

_flow_test_begin "tier docs: the Actions table lists the forms tiers.issueUpdate covers (D8)"
TD_ROW=$(grep -F '| `issueUpdate` |' "$TD_GATES")
if [ -n "$TD_ROW" ]; then _flow_assert_pass "gate configuration has an issueUpdate row"; else _flow_assert_fail "no issueUpdate row in the Actions table"; fi
# The expected list is design github_writes_and_tiers L6-L17 and the Q9 forms
# of plan 7.2 item 12, written as the row spells them.
while IFS= read -r T; do
  [ -n "$T" ] || continue
  if printf '%s\n' "$TD_ROW" | grep -qF -- "$T"; then _flow_assert_pass "the issueUpdate row names $T"; else _flow_assert_fail "the issueUpdate row does not name $T"; fi
done <<'EOF'
`gh issue comment`
`gh pr comment`
`gh pr review`
`gh issue edit` and `gh pr edit` with a label, body, title or reviewer option
`gh pr ready` (and `--undo`)
`gh pr close`
`gh label create`
`gh issue close`
`gh issue reopen`
POST to `.../issues/{n}/comments`
PATCH or DELETE on `.../issues/comments/{id}`
POST to `.../pulls/{n}/reviews`
`.../pulls/{n}/comments`
`.../pulls/{n}/comments/{id}/replies`
`.../pulls/{n}/requested_reviewers`
PATCH or DELETE on `.../pulls/comments/{id}`
POST, PUT or DELETE on `.../issues/{n}/labels`
PATCH on `.../pulls/{n}` with a state, body or title field
PATCH on `.../issues/{n}`
`addComment`
`updateIssueComment`
`addPullRequestReview`
`submitPullRequestReview`
`addPullRequestReviewComment`
`addPullRequestReviewThreadReply`
`addLabelsToLabelable`
`removeLabelsFromLabelable`
`markPullRequestReadyForReview`
`convertPullRequestToDraft`
`closePullRequest`
`updatePullRequest`
`requestReviews`
`updateIssue`
`closeIssue`
`reopenIssue`
EOF
