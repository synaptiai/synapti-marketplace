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
#      posted with your GitHub token counts as yours; or it promises the
#      worker sandbox, names it by a planning phase instead of "a later
#      release", or drops that the sandbox would not cover other programs
#      running as you (the CHANGELOG likewise); or it says the hook's
#      factory rules turn on for a
#      variable they do not read, or that a job parks with a status line;
#      or it says no hold applies yet when the outbox hold on the
#      needs-human notice and label applies now; or the CHANGELOG leaves out
#      a setting the schema accepts, or what the intake judge runs when its
#      model is not set, or says the intake stage takes the budget and tools
#      keys the other stages take
#      (design github_writes_and_tiers L37 and L48, residual_risks L3;
#      plan B10 outline, plan 7.2 items 4 and 14; tier-gate's factory check)
#   D8 the Actions table of gate configuration leaves out a gh command, REST
#      endpoint or GraphQL mutation that design github_writes_and_tiers
#      L6-L17 or the Q9 forms (plan 7.2 item 12) put under issueUpdate, or
#      the safety reference's summary of those forms drops one
#   D9 a flow.factory.* row of gate configuration says a key is not read
#      yet, or that its use comes in a later change, when the factory's code
#      reads it; or says the engine does not add the in-progress label when
#      it does; or says the comment commands will use the trust test when
#      they use it now; or counts a quoted label name that is not a label
#      lookup as a read; or names a planning phase instead of "a later
#      release"; or a key the settings schema accepts has no row (one with
#      no default in settings.json among them), or a row leaves out a module
#      that reads its key; or the intake judge's model and timeout rows do not
#      say how the launcher reads them and passes them to flow-judge.sh
#   D10 under tiers.issueUpdate confirm, an untrusted edit (row 51b) or close
#      (row 53u) of an intake job posts the needs-human comment or label
#      anyway, or prints no PENDING_CONFIRM line for one of them, so the
#      safety reference's "One hold applies now" is untrue

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
# The opening says the parks take effect once next starts a judge or worker,
# but one hold applies now: rows 51b and 53u (an untrusted edit or close of
# the issue in intake, which plan 1.3 lists among the rows a shipped run can
# apply) post the needs-human notice and label, and with tiers.issueUpdate
# confirm the shipped flow-factory.sh next prints PENDING_CONFIRM for both
# and posts neither, which scenario D10 at the end of this file runs for
# both rows.
_td_fac_has "One hold applies now: when an untrusted edit or close of the issue moves a job to needs_human, the notice and the label \`next\` posts wait in the outbox while \`tiers.issueUpdate\` is \`confirm\`" "the opening says the outbox hold on the needs-human notice and label applies now"
# tier-gate turns its factory rules on for these four variables only
# (_tg_in_factory), not for any FLOW_FACTORY_* name.
_td_fac_lacks "when a \`FLOW_FACTORY_*\` variable is set" "no claim that any FLOW_FACTORY_* variable turns the rules on"
# Matched as one fragment: FLOW_FACTORY_JOB and FLOW_FACTORY_DIRECTIVE also
# appear in the worker bullet, so a check per name would pass without them here.
_td_fac_has "run only in a factory: when \`FLOW_FACTORY_JOB\`, \`FLOW_FACTORY_DIRECTIVE\`, \`FLOW_FACTORY_IO\` or \`FLOW_FACTORY_MAIN\` is set" "the sentence that turns the rules on names the four variables tier-gate reads"
# Residual risk (design residual_risks L2 and L3; plan 7.2 item 4): a comment
# posted with the person's token counts as the person's. The worker sandbox
# that would keep the token from a worker's shell commands holds only once
# probe P16 is go, which has not run, so the docs call it planned, in the
# reader's words ("a later release", as the base-fetch paragraph says), and
# say it would not cover other programs running as you (design
# worker_github_access L13).
_td_fac_has "posted with your GitHub token" "the engine cannot tell a comment posted with your token from yours"
_td_fac_has "\`gh auth token\`" "any process running as you can read the token"
_td_fac_has "A later release is planned to add a worker sandbox" "the worker sandbox is planned for a later release"
_td_fac_has "it would not cover other programs running as you" "the worker sandbox would not cover other programs running as you"
_td_fac_lacks "phase 1c" "no planning phase name for the worker sandbox"
_td_fac_lacks "comes with the factory's worker launch" "no promise of when the worker sandbox comes"
# The CHANGELOG's Unreleased section says the same, wrapped over several
# lines, so it is read as one line.
TD_UNREL=$(awk '/^## Unreleased/{on=1; next} on && /^## /{exit} on' "$TD_P/CHANGELOG.md" | tr '\n' ' ' | tr -s ' ')
_td_unrel_has() {   # <fixed text> <what>
  if printf '%s\n' "$TD_UNREL" | grep -qF -- "$1"; then _flow_assert_pass "$2"; else _flow_assert_fail "$2: '$1' not found in the CHANGELOG's Unreleased section"; fi
}
_td_unrel_has "a later release is planned to add a worker sandbox" "the CHANGELOG says the worker sandbox is planned for a later release"
_td_unrel_has "it would not cover other programs running as you" "the CHANGELOG says the worker sandbox would not cover other programs running as you"
# Every flow.factory setting the plugin's settings schema accepts, other than
# the worker block (listed there as a group), is named in the Unreleased
# settings entry, so a key this branch adds is not left out. The list comes
# from schema.json, not settings.json, because a key with no default (such
# as judges.intakeModel) is in the schema only. A leaf is a property with no
# properties of its own. Every key settings.json ships must be in that list,
# so reading the schema loses no key the old list had.
_td_schema_fkeys() {
  jq -r 'def leaves(p): to_entries[] | (p + [.key]) as $q | if (.value.properties | type) == "object" then (.value.properties | leaves($q)) else ($q | join(".")) end; .properties.flow.properties.factory.properties | leaves([])' "$TD_P/schema.json" 2>/dev/null
}
TD_SKEYS=$(_td_schema_fkeys)
if [ -n "$TD_SKEYS" ]; then _flow_assert_pass "schema.json has flow.factory keys"; else _flow_assert_fail "no flow.factory keys read from schema.json"; fi
for K in $(jq -r '.flow.factory | paths(type != "object") | select(map(type) | all(. == "string")) | join(".")' "$TD_P/settings.json" 2>/dev/null); do
  if printf '%s\n' "$TD_SKEYS" | grep -qxF -- "$K"; then :; else _flow_assert_fail "settings.json has flow.factory.$K, which the schema key list does not have"; fi
done
TD_FKEYS=$(printf '%s\n' "$TD_SKEYS" | grep -v '^worker\.')
for K in $TD_FKEYS; do
  _td_unrel_has "\`$K\`" "the CHANGELOG names the setting flow.factory.$K"
done
# The intake judge's model has no default; the entry says what happens then
# (plan 2.5: the probe record's platform model; _flow_factory_launch.py
# refuses model_unknown when neither gives one).
_td_unrel_has "\`judges.intakeModel\` (the intake judge's model; when it is not set, the model the platform probe recorded" "the CHANGELOG says which model the intake judge runs when judges.intakeModel is not set"
# The worker's stages each take maxBudgetUsd, timeoutSeconds and
# allowedTools, except intake, whose judge runs with no tools and no budget
# key and so takes timeoutSeconds only (schema.json, worker.stages.intake).
# The entry says so, as the allowedTools row of gate configuration does.
TD_INTAKE_STAGE=$(jq -r '.properties.flow.properties.factory.properties.worker.properties.stages.properties.intake.properties | keys | join(",")' "$TD_P/schema.json" 2>/dev/null)
if [ "$TD_INTAKE_STAGE" = timeoutSeconds ]; then
  _td_unrel_has "each stage's \`maxBudgetUsd\`, \`timeoutSeconds\` and \`allowedTools\` (the intake stage has \`timeoutSeconds\` only, which the launcher passes to the intake judge)" "the CHANGELOG says the intake stage has timeoutSeconds only"
else
  _flow_assert_fail "schema.json's worker.stages.intake keys are '$TD_INTAKE_STAGE', not timeoutSeconds only; recheck the CHANGELOG's settings entry and this check"
fi
# The opening says the engine has no runner and no worker sandbox, and,
# separately, that it starts no judge or worker in this release; a relative
# clause between "a job engine" and "but no runner" reads as if the "but"
# belonged to it.
_td_unrel_has "it has a job engine but no runner and no worker sandbox, and in this release the engine starts no judge or worker." "the CHANGELOG's opening says what the factory lacks in one clause and what the engine does not start in another"
if printf '%s\n' "$TD_UNREL" | grep -qF -- "which in this release starts no judge or worker, but"; then
  _flow_assert_fail "the CHANGELOG's opening still puts the relative clause between 'a job engine' and 'but no runner'"
else
  _flow_assert_pass "the CHANGELOG's opening has no relative clause before 'but no runner'"
fi
# next adds the needs-info or needs-human label when a job parks there and
# removes it when the job leaves (the labels.needsInfo and labels.needsHuman
# rows of gate configuration).
_td_unrel_has "adds the \`flow:needs-info\` or \`flow:needs-human\` label" "the CHANGELOG says next adds the park labels"
# next writes to GitHub in this release: a job that an untrusted edit or
# close sends to needs_human (rows 51b and 53u, which plan 1.3 lists among the
# rows a shipped run can apply) gets the needs-human notice and label. So the
# opening of the section does not say the factory makes no GitHub writes.
if printf '%s\n' "$TD_UNREL" | grep -qiF -- "no GitHub writes"; then
  _flow_assert_fail "the CHANGELOG still says the factory makes no GitHub writes, but next posts comments and labels"
else
  _flow_assert_pass "the CHANGELOG makes no claim that the factory makes no GitHub writes"
fi
if printf '%s\n' "$TD_UNREL" | grep -qF -- "keeps the token from workers comes later"; then
  _flow_assert_fail "the CHANGELOG still says the worker sandbox comes later, as a promise"
else
  _flow_assert_pass "the CHANGELOG makes no promise of the worker sandbox"
fi
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
# of plan 7.2 item 12, written as the row spells them. DELETE on
# `.../issues/{n}/labels/{name}` is GitHub's endpoint for removing one label
# (design L14's "DELETE issues/{n}/labels"), the form the engine's own label
# removal uses, and one tier-gate puts under issueUpdate.
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
DELETE on `.../issues/{n}/labels/{name}`
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

_flow_test_begin "tier docs: the safety reference's summary names the forms tiers.issueUpdate covers (D8)"
# Only the paragraph that lists them: `close`, `ready` and `gh label create`
# also appear elsewhere in the file, so a whole-file match would pass without
# them here. The forms are design github_writes_and_tiers L6-L17 and the Q9
# forms of plan 7.2 item 12, as the paragraph groups them.
TD_SUM=$(grep -F '`issueUpdate` covers writes' "$TD_SAFETY")
if [ -n "$TD_SUM" ]; then _flow_assert_pass "the safety reference has the issueUpdate summary"; else _flow_assert_fail "no paragraph with '\`issueUpdate\` covers writes' in the safety reference"; fi
while IFS= read -r T; do
  [ -n "$T" ] || continue
  if printf '%s\n' "$TD_SUM" | grep -qF -- "$T"; then _flow_assert_pass "the issueUpdate summary names $T"; else _flow_assert_fail "the issueUpdate summary does not name $T"; fi
done <<'EOS'
`gh issue comment`, `close` and `reopen`
`gh pr comment`, `review`, `ready` (and `--undo`) and `close`
`gh issue edit` and `gh pr edit` with a label, body, title or reviewer option
`gh label create`
the matching `gh api` calls
the matching GraphQL mutations
EOS

_flow_test_begin "tier docs: the factory settings rows match what the factory's code reads now (D9)"
# A row is checked against the engine's code, not a fixed list. A key other
# than a label is read where its full name is quoted. A label key is read
# only where _flow_factory_next.py looks its name up: a call
# label_name("<name>"), or a value of LABELLED_PARKS, which next passes to
# label_name. Any other quoted occurrence of the short name (the defaults
# table, a stage named "ready", an unrelated table) is not a read. A row
# whose key is read must name a module and must not say it is not read yet
# or that its use comes in a later change or phase.
TD_BIN="$TD_P/bin"
_td_gate_row() {   # <key>
  grep -F "| \`flow.factory.$1\` |" "$TD_GATES"
}
# The modules that read a key, one file name per line. Besides the quoted
# full name, a key is read through _flow_factory_next.py's num("<key>"),
# which prefixes flow.factory., and a stage key through an f-string such as
# "flow.factory.worker.stages.{stage}.timeoutSeconds" or the intake stage's
# own quoted name.
_td_key_files() {   # <key>
  case "$1" in
    labels.*)
      { grep -lF -- "label_name(\"${1#labels.}\")" "$TD_BIN/_flow_factory_next.py"
        if grep -E '^LABELLED_PARKS = \{' "$TD_BIN/_flow_factory_next.py" | grep -qF -- ": \"${1#labels.}\""; then
          printf '%s\n' "$TD_BIN/_flow_factory_next.py"
        fi
      } ;;
    'worker.stages.<stage>.'*)
      grep -lE -- "\"flow\.factory\.worker\.stages\.(\{[a-z_]+\}|[a-z_]+)\.${1##*.}\"" "$TD_BIN"/_flow_factory*.py ;;
    *) grep -lF -- "\"flow.factory.$1\"" "$TD_BIN"/_flow_factory*.py
       grep -lF -- ".num(\"$1\"" "$TD_BIN/_flow_factory_next.py" ;;
  esac 2>/dev/null | sed 's|.*/||' | sort -u
}
# Every leaf key of the schema's flow.factory block has a row, the worker
# stages folded into the rows' <stage> form, so a key with no default in
# settings.json is checked too (gate configuration: one row per setting).
TD_RKEYS=$(printf '%s\n' "$TD_SKEYS" | sed -E 's/^worker\.stages\.[^.]+\./worker.stages.<stage>./' | sort -u)
for K in $TD_RKEYS; do
  R=$(_td_gate_row "$K")
  if [ -z "$R" ]; then _flow_assert_fail "no row for flow.factory.$K in gate configuration"; continue; fi
  FILES=$(_td_key_files "$K")
  PAT=$(printf '%s\n' "$FILES" | tr '\n' ' ' | sed 's/ *$//')
  if [ -n "$FILES" ]; then
    case "$R" in
      *'not read yet'*|*'later change'*|*'later phase'*) _flow_assert_fail "the flow.factory.$K row says it is not used yet, but the code reads it ($PAT)" ;;
      *'`bin/_flow_factory'*) _flow_assert_pass "the flow.factory.$K row names the module that reads it" ;;
      *) _flow_assert_fail "the flow.factory.$K row names no module, but the code reads it ($PAT)" ;;
    esac
    for F in $FILES; do
      case "$R" in
        *"\`bin/$F\`"*) _flow_assert_pass "the flow.factory.$K row names bin/$F, which reads it" ;;
        *) _flow_assert_fail "the flow.factory.$K row does not name bin/$F, which reads it" ;;
      esac
    done
  else
    case "$R" in
      *'not read yet'*) _flow_assert_pass "the flow.factory.$K row says it is not read yet, and no code reads it" ;;
      *) _flow_assert_fail "the flow.factory.$K row does not say it is not read yet, and no code reads it" ;;
    esac
  fi
done
# A row whose key is not read yet says when it comes in the reader's words,
# "a later release", as the rest of the factory docs do, never by a planning
# phase.
TD_PHASE_ROWS=$(grep -F '| `flow.factory.' "$TD_GATES" | grep -iE 'later phase|phase 1[a-z]' | sed -n 's/^| `\([^`]*\)`.*/\1/p' | tr '\n' ' ')
assert_equal "" "$TD_PHASE_ROWS" "flow.factory rows that name a planning phase"
# The launcher reads the intake judge's two settings itself and passes them
# to flow-judge.sh as arguments (plan 2.5, B11 step 2): the model as
# --model, refusing model_unknown when neither the key nor the probe record
# gives one, and the intake timeout as --timeout-seconds, which
# flow-judge.sh does not cut to the 5-600 s of the goal and verdict judges.
TD_LAUNCH="$TD_BIN/_flow_factory_launch.py"
if grep -qF 'raise Refused(f"model_unknown directive={did} next: set flow.factory.judges.intakeModel' "$TD_LAUNCH" \
    && grep -qF '"--judge", "intake", "--model", directive["model"]' "$TD_LAUNCH"; then
  R=$(_td_gate_row judges.intakeModel)
  for T in '`--model`' 'the model the platform probe recorded' '`model_unknown`' 'user settings only'; do
    case "$R" in
      *"$T"*) _flow_assert_pass "the judges.intakeModel row says $T" ;;
      *) _flow_assert_fail "the judges.intakeModel row does not say $T" ;;
    esac
  done
else
  _flow_assert_fail "_flow_factory_launch.py no longer passes judges.intakeModel as --model or refuses model_unknown; recheck this row and this check"
fi
if grep -qF '"flow.factory.worker.stages.intake.timeoutSeconds"' "$TD_LAUNCH" && grep -qF '"--timeout-seconds", str(timeout)' "$TD_LAUNCH"; then
  R=$(_td_gate_row 'worker.stages.<stage>.timeoutSeconds')
  T="For intake, \`bin/_flow_factory_launch.py\` reads the key itself and passes it to \`flow-judge.sh --judge intake\` as \`--timeout-seconds\`, without the 5-600 s limit of the goal and verdict judges"
  case "$R" in
    *"$T"*) _flow_assert_pass "the timeoutSeconds row says the launcher reads the intake timeout and passes it as --timeout-seconds" ;;
    *) _flow_assert_fail "the timeoutSeconds row does not say: $T" ;;
  esac
else
  _flow_assert_fail "_flow_factory_launch.py no longer reads the intake timeout or passes --timeout-seconds; recheck this row and this check"
fi
# The engine adds the in-progress label with its assignment (the assign_label
# write of rows 11 and 40, design stages: prepare's "assignment and label
# written").
R=$(_td_gate_row labels.inProgress)
if grep -qF 'literal_assign_label(self.repo(), self.n, self.login(), label_name("inProgress"))' "$TD_BIN/_flow_factory_next.py"; then
  case "$R" in
    *'does not add the label'*) _flow_assert_fail "the labels.inProgress row says the engine does not add the label, but next adds it with the assignment" ;;
    *) _flow_assert_pass "the labels.inProgress row makes no claim that the engine does not add the label" ;;
  esac
else
  _flow_assert_fail "next no longer adds labels.inProgress with the assignment; recheck this row and this check"
fi
# The comment commands test their author with Permissions.trusted.
for K in trustedPermission trustedBots; do
  R=$(_td_gate_row "$K")
  if grep -qF 'perms.trusted(' "$TD_BIN/_flow_factory_commands.py"; then
    case "$R" in
      *'will use'*) _flow_assert_fail "the flow.factory.$K row says the comment commands will use the trust test, but they use it now" ;;
      *'`bin/_flow_factory_commands.py`'*) _flow_assert_pass "the flow.factory.$K row names the comment commands' module" ;;
      *) _flow_assert_fail "the flow.factory.$K row does not name bin/_flow_factory_commands.py, which uses the trust test" ;;
    esac
  else
    _flow_assert_fail "_flow_factory_commands.py no longer calls perms.trusted; recheck this row and this check"
  fi
done

# ---------------------------------------------------------------- D10
# The hold the safety reference says applies now, run through the shipped
# flow-factory.sh next (no seam) with the gh stand-in. factory-e2e.sh is
# sourced here, after every docs check, because it replaces the EXIT trap
# with one that also stops the factory's processes.
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  _flow_assert_fail "cannot load tests/lib/factory-e2e.sh"
  return 1 2>/dev/null; exit 1
}
# _td_hold_run <scenario> <edit|close> <issueUpdate value or default> — job 7
# in intake, vouched at 00:00, a sync on every pass; at 01:00 an outsider with
# read access edits the body (row 51b) or ci[bot], a bot not in trustedBots,
# closes the issue (row 53u); then one pass of the shipped wrapper's next.
_td_hold_run() {
  local tiers='{}'
  [ "$3" = default ] || tiers="{\"issueUpdate\": \"$3\"}"
  fe_new "$1"
  e2e_repo main
  fe_record
  e2e_user_settings "{\"flow\": {\"factory\": {\"enabled\": true, \"syncIntervalSeconds\": 0}}, \"tiers\": $tiers}"
  fe_world_new flow-e2e-engine flow-e2e/scratch
  fe_gh --version 'gh version 2.101.0 (2026-09-15)'
  fe_world_issue 7 "Add a port setting" "The service needs a port setting."
  fe_job 7 intake "d['vouch_at'] = '2026-11-16T00:00:00Z'"
  TD_J="$(fe_factory_dir)/jobs/issue-7"
  if [ "$2" = edit ]; then
    fe_world_perm outsider read
    fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
  else
    fe_world_close 7 'ci[bot]' write 2026-11-16T01:00:00Z
  fi
  e2e_run_bin bin/flow-factory.sh next --executor headless
}
# _td_status_count <extended regex> — how many of next's status lines match.
_td_status_count() {
  printf '%s\n' "$E2E_OUT" | jq -Rr 'fromjson? | .status? // empty' | grep -cE -- "$1"
}
# _td_comment_posts — how many comments the stand-in received for issue 7.
_td_comment_posts() {
  fe_world_posts | jq -r 'select(.method == "POST" and (.path | endswith("/issues/7/comments"))) | .path' | grep -c .
}

_flow_test_begin "tier docs: an untrusted edit or close under tiers.issueUpdate confirm holds the needs-human notice and label in the outbox, through the shipped next (D10)"
# Source: three-tier-safety.md, the factory section's opening ("One hold
# applies now"); T:51b (intake, github_change, untrusted_edit -> needs_human,
# reason untrusted_edit); T:53u (untrusted_close -> needs_human, reason
# issue_closed_untrusted); plan B14 step 8 (on entry to needs_human a
# needs-human comment and a label_add of labels.needsHuman, both notices
# under issueUpdate, drained in the same pass); plan B6 step 7 and 2.3 (a
# notice whose key is confirm becomes pending_confirm and next prints
# PENDING_CONFIRM job=<key> intent=<id> kind=<kind>); design
# github_writes_and_tiers (confirm holds the write). The control under the
# plugin default (journal) shows that the user key, not a failed base fetch,
# made the hold.
for TD_CASE in edit:51b:untrusted_edit close:53u:issue_closed_untrusted; do
  TD_KIND=${TD_CASE%%:*}; TD_REST=${TD_CASE#*:}; TD_ROW=${TD_REST%%:*}; TD_WHY=${TD_REST#*:}
  _td_hold_run "td-hold-$TD_KIND-confirm" "$TD_KIND" confirm
  e2e_describe "job 7 in intake; tiers.issueUpdate confirm in the user settings; an untrusted $TD_KIND of issue 7 at 01:00; one pass of the shipped flow-factory.sh next"
  e2e_expect_equal 0 "$E2E_RC" "$TD_KIND under confirm: exit status ($E2E_ERR)"
  e2e_expect_equal "$TD_ROW needs_human $TD_WHY" "$(jq -r 'select(.type == "transition") | .row' "$TD_J/events.jsonl" 2>/dev/null | tr '\n' ' ')$(jq -r '"\(.state) \(.reason)"' "$TD_J/job.json" 2>/dev/null)" "$TD_KIND under confirm: row, state and reason"
  e2e_expect_equal 0 "$(_td_status_count '^BASE_(FETCH_FAILED|REF_UNRESOLVED) ')" "$TD_KIND under confirm: the base fetch succeeded"
  e2e_expect_equal 1 "$(_td_status_count '^PENDING_CONFIRM job=issue-7-j1 intent=[^ ]+ kind=comment$')" "$TD_KIND under confirm: one PENDING_CONFIRM line for the needs-human comment"
  e2e_expect_equal 1 "$(_td_status_count '^PENDING_CONFIRM job=issue-7-j1 intent=[^ ]+ kind=label_add$')" "$TD_KIND under confirm: one PENDING_CONFIRM line for the needs-human label"
  e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "$TD_KIND under confirm: nothing posted"
  e2e_expect_equal '[]' "$(jq -c '.issues["7"].labels' "$FE_WORLD")" "$TD_KIND under confirm: no label on the issue"
  e2e_expect_err_lacks "Traceback"

  _td_hold_run "td-hold-$TD_KIND-default" "$TD_KIND" default
  e2e_describe "control: the same world under the plugin default for tiers.issueUpdate (journal)"
  e2e_expect_equal 0 "$E2E_RC" "$TD_KIND under the default: exit status ($E2E_ERR)"
  e2e_expect_equal "$TD_ROW needs_human" "$(jq -r 'select(.type == "transition") | .row' "$TD_J/events.jsonl" 2>/dev/null | tr '\n' ' ')$(jq -r .state "$TD_J/job.json" 2>/dev/null)" "$TD_KIND under the default: row and state"
  e2e_expect_equal 0 "$(_td_status_count '^PENDING_CONFIRM ')" "$TD_KIND under the default: no PENDING_CONFIRM line"
  e2e_expect_equal 1 "$(_td_comment_posts)" "$TD_KIND under the default: one needs-human comment posted"
  e2e_expect_equal '["flow:needs-human"]' "$(jq -c '.issues["7"].labels' "$FE_WORLD")" "$TD_KIND under the default: the needs-human label on the issue"
done
