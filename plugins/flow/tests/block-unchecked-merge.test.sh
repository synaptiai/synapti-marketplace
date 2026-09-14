# Tests for hooks/scripts/block-unchecked-merge.sh (issue #170).
#
# Contract: a `gh pr merge` is refused while any check is unfinished or failing,
# and `--auto` is refused on a base branch that requires no status checks —
# because GitHub's auto-merge waits for REQUIRED checks, so where none are
# required it merges at once, which is the opposite of what --auto is reached
# for. A fully green pull request merges when the merge is written in the one
# shape the hook reads (#195); any other merge is refused with that shape.
#
# `gh` is stubbed so the scenarios are exact and offline: each case writes a
# small script named `gh` onto PATH that answers the three calls the hook makes
# (repo view, pr view --json, api). The rollup shapes are the ones GitHub
# actually returns, including a legacy StatusContext, which carries `state`
# rather than `status`/`conclusion` and was invisible to a check that counted
# only CheckRun entries.
#
# Prereq: jq. SKIPS gracefully otherwise.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"; _flow_assert_pass "SKIP: jq not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-unchecked-merge.sh"

# Every stub lives under one directory made here, at file scope. The stubs are
# built inside $(...), so a cleanup list appended to there never reached the
# EXIT trap and each run left its directories behind.
BUM_ROOT=$(mktemp -d -t flow-bum.XXXXXX 2>/dev/null)
if [ -z "$BUM_ROOT" ] || [ ! -d "$BUM_ROOT" ]; then
  _flow_test_begin "stub directory"; _flow_assert_fail "mktemp -d failed; no test below could run honestly"; return 0
fi
trap 'rm -rf "$BUM_ROOT" 2>/dev/null' EXIT

# _bum_stub <rollup-json> <protection-json> <rules-json>
# Builds a directory holding a `gh` stub and prints its path.
_bum_stub() {
  local rollup="$1" prot="$2" rules="$3" d
  d=$(mktemp -d "$BUM_ROOT/stub.XXXXXX" 2>/dev/null) || { printf ''; return 1; }
  printf '%s' "$rollup" > "$d/rollup.json"
  printf '%s' "$prot"   > "$d/prot.json"
  printf '%s' "$rules"  > "$d/rules.json"
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
case "$1 $2" in
  "repo view") echo "acme/widgets"; exit 0 ;;
  "pr view")   cat "$D/rollup.json"; exit 0 ;;
esac
if [ "$1" = "api" ]; then
  case "$2" in
    *protection/required_status_checks)
      [ -s "$D/prot.json" ] && cat "$D/prot.json" && exit 0
      echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
    *rules/branches/*)
      [ -s "$D/rules.json" ] && cat "$D/rules.json" && exit 0
      echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  esac
fi
exit 1
STUB
  chmod +x "$d/gh"
  printf '%s' "$d"
}

_bum_run() {
  local stub="$1" cmd="$2" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  printf '{"tool_input":{"command":%s}}' "$json" \
    | PATH="$stub:$PATH" bash "$HOOK" >/dev/null 2>&1
}

_bum_stderr() {
  local stub="$1" cmd="$2" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  printf '{"tool_input":{"command":%s}}' "$json" \
    | PATH="$stub:$PATH" bash "$HOOK" 2>&1 >/dev/null
}

GREEN='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]}'
QUEUED='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"CheckRun","name":"build","status":"QUEUED","conclusion":null}]}'
RUNNING='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"e2e","status":"IN_PROGRESS","conclusion":null}]}'
FAILING='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]}'
LEGACY_PENDING='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"StatusContext","context":"ci/jenkins","state":"PENDING"}]}'
NO_CHECKS='{"number":7,"baseRefName":"main","statusCheckRollup":[]}'
PROT='{"contexts":["test"]}'
RULES='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]'

# --- the case that prompted the issue -----------------------------------------
_flow_test_begin "a merge is refused while a check is queued"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "queued check blocks the merge"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --repo acme/widgets --squash")
assert_contains "build" "$ERR" "the message names the unfinished check"
assert_contains "queued" "$ERR" "and says what state it is in"

_flow_test_begin "a merge is refused while a check is running"
S=$(_bum_stub "$RUNNING" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "in-progress check blocks the merge"

_flow_test_begin "a merge is refused when a check failed"
S=$(_bum_stub "$FAILING" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "failing check blocks the merge"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --repo acme/widgets --squash")
assert_contains "did not pass" "$ERR" "the message says the check did not pass"

# A legacy StatusContext carries `state`, not `status`/`conclusion`. A rollup
# reader that selects only CheckRun sees an empty list here and calls it green.
_flow_test_begin "a pending legacy status is not invisible"
S=$(_bum_stub "$LEGACY_PENDING" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "pending StatusContext blocks the merge"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --repo acme/widgets --squash")
assert_contains "ci/jenkins" "$ERR" "the message names it"

# --- green passes, by any route -----------------------------------------------
_flow_test_begin "a fully green pull request merges"
S=$(_bum_stub "$GREEN" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash --delete-branch"
assert_exit 0 "$?" "green merge allowed"
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --merge"
assert_exit 0 "$?" "strategy does not matter"

# --- --auto, with and without required checks ---------------------------------
_flow_test_begin "--auto is refused where nothing is required"
S=$(_bum_stub "$GREEN" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --auto --squash"
assert_exit 2 "$?" "--auto blocked when the base requires no checks"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --repo acme/widgets --auto --squash")
assert_contains "requires no status checks" "$ERR" "the message says that is why"
assert_contains "merges immediately" "$ERR" "and what --auto would actually do"

_flow_test_begin "--auto is allowed where branch protection requires checks"
S=$(_bum_stub "$GREEN" "$PROT" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --auto --squash"
assert_exit 0 "$?" "--auto allowed with required checks from branch protection"

# Branch protection is not the only way to require a check. Asking only the
# protection endpoint reports "none required" on a repository that requires
# plenty through a ruleset.
_flow_test_begin "--auto is allowed where a ruleset requires checks"
S=$(_bum_stub "$GREEN" "" "$RULES")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --auto --squash"
assert_exit 0 "$?" "--auto allowed with required checks from a ruleset"

_flow_test_begin "a pull request with no checks at all is not called green"
S=$(_bum_stub "$NO_CHECKS" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash"
assert_exit 0 "$?" "no checks is not a failure — nothing is pending"
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --auto --squash"
assert_exit 2 "$?" "but --auto still has nothing to wait for"

# --- the hook reads commands, not text ----------------------------------------
_flow_test_begin "text that names a merge but runs none is allowed"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" 'echo "gh pr merge 7 --auto"'
assert_exit 0 "$?" "quoting the command is not running it"
_bum_run "$S" "# gh pr merge 7"
assert_exit 0 "$?" "a comment naming it is not running it"
_bum_run "$S" "npm run merge-check"
assert_exit 0 "$?" "a script whose name contains merge is not gh pr merge"
_bum_run "$S" "git merge --no-ff feature/x"
assert_exit 0 "$?" "git merge is a different command and not this gate"
_bum_run "$S" "gh pr view 7"
assert_exit 0 "$?" "another gh subcommand is untouched"

_flow_test_begin "a merge inside a compound command is still examined"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "git fetch && gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "after && the merge is still found"
_bum_run "$S" "/usr/bin/gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "an absolute gh path is still gh"

# --- it refuses rather than guessing ------------------------------------------
_flow_test_begin "a gate that cannot see refuses"
S=$(_bum_stub "" "" "")
_bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash"
assert_exit 2 "$?" "an unreadable rollup blocks rather than allowing"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --repo acme/widgets --squash")
assert_contains "cannot see must not open" "$ERR" "and says why"

# --- a value it cannot read is named, not blamed on the checks (#195) ---------
# The hook reads text. `"$REPO"` reached the probe as the literal `$REPO`, the
# lookup failed, and the refusal said the checks could not be read — which sent
# the reader to CI. The stub marks any gh call (`called`) and the checks lookup
# itself (`probed`). A refusal for a value that was never expanded must make no
# call at all; a merge that is allowed must have looked its checks up.
_bum_probe_stub() {
  local d
  d=$(_bum_stub "$GREEN" "$PROT" "") || return 1
  [ -n "$d" ] && [ -f "$d/gh" ] || return 1
  { printf '#!/usr/bin/env bash\ntouch "$(dirname "$0")/called"\n[ "$1 $2" = "pr view" ] && touch "$(dirname "$0")/probed"\n'; tail -n +2 "$d/gh"; } > "$d/gh.new" \
    && mv "$d/gh.new" "$d/gh" && chmod +x "$d/gh" || return 1
  printf '%s' "$d"
}

_flow_test_begin "a merge naming a value this hook cannot read is refused by name"
for CASE in \
  'pull request|$PR_NUM|gh pr merge "$PR_NUM" --squash' \
  'repository|$REPO|gh pr merge 7 --repo "$REPO" --squash' \
  'pull request|$PR_NUM|gh pr merge "$PR_NUM" --repo "$REPO" --squash --delete-branch' \
  'repository|${REPO}|gh pr merge 7 -R ${REPO}' \
  'repository|$REPO|gh pr merge 7 --repo=$REPO' \
  'repository|$REPO|gh pr merge 7 -R"$REPO"' \
  'repository|$(...)|gh pr merge 7 --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"' \
  'repository|acme/$(...)|gh pr merge 7 --repo acme/$(printf w)' \
  'pull request|$(...)|gh pr merge `cat pr.txt` --repo acme/widgets' \
  'pull request|7 $EXTRA|gh pr merge 7 $EXTRA --repo acme/widgets' \
  'pull request|7 $(...)|gh pr merge 7 $(echo --repo other/x)' \
  'repository|acme/$R|gh --repo "acme/$R" pr merge 7' \
  'gh command|$GH|GH=gh; $GH pr merge 7 --repo acme/widgets'; do
  WHAT="${CASE%%|*}"; REST="${CASE#*|}"; SHOWN="${REST%%|*}"; CMD="${REST#*|}"
  if ! S=$(_bum_probe_stub); then
    _flow_assert_fail "could not build the gh stub for: $CMD"; continue
  fi
  ERR=$(_bum_stderr "$S" "$CMD"); RC=$?
  if [ "$RC" -ne 2 ]; then
    _flow_assert_fail "exit $RC, expected 2, for: $CMD"
  elif [[ "$ERR" != *"the $WHAT is given as \"$SHOWN\""* ]]; then
    _flow_assert_fail "refusal does not name the $WHAT \"$SHOWN\" for: $CMD — got: $ERR"
  elif [[ "$ERR" == *"could not be read"* ]]; then
    _flow_assert_fail "refusal still blames the checks for: $CMD"
  elif [ -e "$S/called" ]; then
    _flow_assert_fail "gh was called for a value that was never expanded: $CMD"
  else
    _flow_assert_pass "refused by name without calling gh: $CMD"
  fi
done

_flow_test_begin "an unfilled placeholder is named as one"
S=$(_bum_probe_stub) || S=""
if [ -z "$S" ]; then
  _flow_assert_fail "could not build the gh stub"
else
  ERR=$(_bum_stderr "$S" "gh pr merge {PR_NUMBER} --repo {OWNER/NAME} --squash"); RC=$?
  assert_exit 2 "$RC" "a merge still carrying {PR_NUMBER} is refused"
  assert_contains "a placeholder that was not filled in" "$ERR" "and the refusal says so"
  if [ -e "$S/called" ]; then
    _flow_assert_fail "gh was called for an unfilled placeholder"
  else
    _flow_assert_pass "without calling gh"
  fi
fi

_flow_test_begin "the refused value is shown safely"
if ! S=$(_bum_probe_stub); then
  _flow_assert_fail "could not build the gh stub"
else
  LONG="\$$(printf 'x%.0s' $(seq 1 5000))"
  ERR=$(_bum_stderr "$S" "gh pr merge $LONG --repo acme/widgets")
  if [ "${#ERR}" -lt 1000 ]; then
    _flow_assert_pass "a 5000-character value is cut short (${#ERR} bytes of stderr)"
  else
    _flow_assert_fail "a 5000-character value produced ${#ERR} bytes of stderr"
  fi
  assert_contains "Write it literally" "$ERR" "and the instruction after it survives"
  # No `;` in the escape sequence: it would split the command, and the case would
  # pass without the refusal ever running.
  ERR=$(_bum_stderr "$S" "$(printf 'gh pr merge a\033[31mb\007$X --repo acme/widgets')")
  case "$ERR" in
    *"is given as"*) ;;
    *) _flow_assert_fail "the control-character case was not refused by name: $ERR" ;;
  esac
  case "$ERR" in
    *$'\033'*|*$'\007'*) _flow_assert_fail "control characters from the command reached stderr" ;;
    *"is given as"*) _flow_assert_pass "control characters are replaced" ;;
  esac
fi

_flow_test_begin "literal values are unaffected by the variable rule"
if ! S=$(_bum_probe_stub); then
  _flow_assert_fail "could not build the gh stub"
else
  _bum_run "$S" "gh pr merge 7 --repo acme/widgets --squash --delete-branch"
  assert_exit 0 "$?" "a literal number and repository on a green PR merge"
  if [ -e "$S/probed" ]; then
    _flow_assert_pass "and its checks were looked up"
  else
    _flow_assert_fail "a literal merge was allowed without looking up its checks"
  fi
fi
if ! S=$(_bum_probe_stub); then
  _flow_assert_fail "could not build the gh stub"
else
  _bum_run "$S" 'gh pr merge 7 --repo acme/widgets --squash --body "saves $5 a month"'
  assert_exit 0 "$?" "a \$ in the merge body is not the selector or the repository"
  if [ -e "$S/probed" ]; then
    _flow_assert_pass "and its checks were looked up"
  else
    _flow_assert_fail "the body case was allowed without looking up its checks"
  fi
fi

# The merge step /flow:merge documents is what a model runs. If it goes back to
# variables, every merge through the command is refused again.
_flow_test_begin "the merge step in /flow:merge passes this hook"
MERGE_MD="$REPO_ROOT/plugins/flow/commands/merge.md"
DOC_LINES=$(awk '/^## Phase 3/ { p = 1 } /^## Phase 4/ { p = 0 } p && /^gh pr merge / { print }' "$MERGE_MD")
if [ -z "$DOC_LINES" ]; then
  _flow_assert_fail "no gh pr merge line found in merge.md Phase 3"
else
  while IFS= read -r DOC_LINE; do
    case "$DOC_LINE" in
      *'$'*) _flow_assert_fail "the documented merge line uses a shell expansion: $DOC_LINE"; continue ;;
      *--repo*) _flow_assert_pass "documented merge line is literal and keeps --repo" ;;
      *) _flow_assert_fail "the documented merge line lost its --repo pin: $DOC_LINE"; continue ;;
    esac
    # Filled in both ways the instructions allow: with the branch deleted, and
    # with the placeholder removed when the setting is false.
    for DELETE in "--delete-branch" ""; do
      FILLED="${DOC_LINE//\{PR_NUMBER\}/7}"
      FILLED="${FILLED//\{OWNER\/NAME\}/acme/widgets}"
      FILLED="${FILLED//\{STRATEGY\}/squash}"
      FILLED="${FILLED//\{DELETE_BRANCH\}/$DELETE}"
      case "$FILLED" in
        *'{'*|*'}'*) _flow_assert_fail "a placeholder this test does not know is left in: $FILLED" ;;
        *)
          S=$(_bum_stub "$GREEN" "" "")
          _bum_run "$S" "$FILLED"
          assert_exit 0 "$?" "the documented merge, filled in as: $FILLED" ;;
      esac
    done
  done <<DOC_EOF
$DOC_LINES
DOC_EOF
fi

# --- one shape: anything else that is a merge is refused with the shape --------
# A merge is checked only as `gh pr merge <number> --repo owner/name
# --squash|--merge|--rebase ...`. Every case below is a merge gh would run, and
# each once reached GitHub checked against a pull request other than the one
# merged, or not checked at all. The stub is green, so only a refusal passes.
_flow_test_begin "a merge in any other shape is refused, and the refusal gives the shape"
for CASE in \
  'names no --repo|gh pr merge 7 --squash' \
  'names no pull request number|gh pr merge --repo acme/widgets --squash' \
  'not a number|gh pr merge some-branch --repo acme/widgets --squash' \
  'not a number|gh pr merge https://github.com/acme/widgets/pull/7 --repo acme/widgets --squash' \
  'exactly one of --squash|gh pr merge 7 --repo acme/widgets' \
  'exactly one of --squash|gh pr merge 7 --repo acme/widgets --squash --rebase' \
  'more than once|gh pr merge 7 --repo acme/widgets --repo other/repo --squash' \
  'not one of the options|gh pr merge 7 -R other/repo --squash' \
  'not one of the options|gh pr merge 7 -Rother/repo --squash' \
  'not one of the options|gh pr merge 7 --repo acme/widgets -ds' \
  'not one of the options|gh pr merge 7 --repo acme/widgets --squash -dR other/repo' \
  'not owner/name|gh pr merge 7 --repo widgets --squash' \
  'not owner/name|gh pr merge 7 --repo github.example.com/acme/widgets --squash' \
  'comes before gh|GH_REPO=other/repo gh pr merge 7 --repo acme/widgets --squash' \
  'comes before gh|env GH_HOST=ghe.example.com gh pr merge 7 --repo acme/widgets --squash' \
  'comes before gh|sudo gh pr merge 7 --repo acme/widgets --squash' \
  'comes before gh|timeout 60 env GH_REPO=other/repo gh pr merge 7 --repo acme/widgets --squash' \
  'comes before gh|echo 7 | xargs gh pr merge --repo acme/widgets --squash' \
  'is not pr merge followed by one|gh pr merge 7 8 --repo acme/widgets --squash'; do
  WANT="${CASE%%|*}"; CMD="${CASE#*|}"
  if ! S=$(_bum_probe_stub); then
    _flow_assert_fail "could not build the gh stub for: $CMD"; continue
  fi
  ERR=$(_bum_stderr "$S" "$CMD"); RC=$?
  if [ "$RC" -ne 2 ]; then
    _flow_assert_fail "exit $RC, expected 2, for: $CMD"
  elif [[ "$ERR" != *"$WANT"* ]]; then
    _flow_assert_fail "refusal does not say \"$WANT\" for: $CMD — got: $ERR"
  elif [[ "$ERR" != *"gh pr merge <number> --repo owner/name"* ]]; then
    _flow_assert_fail "refusal does not give the shape for: $CMD"
  elif [ -e "$S/probed" ]; then
    _flow_assert_fail "the checks were looked up for a merge refused on its shape: $CMD"
  else
    _flow_assert_pass "refused on its shape: $CMD"
  fi
done

# The shape is strict about form, not about ordinary ways of running it.
_flow_test_begin "the shape still reads ordinary merges"
for CMD in \
  'gh pr merge 7 --repo acme/widgets --squash --delete-branch' \
  'gh --repo acme/widgets pr merge 7 --rebase' \
  'gh pr merge 7 --repo=acme/widgets --merge --admin' \
  'cd /tmp/elsewhere && gh pr merge 7 --repo acme/widgets --squash' \
  'gh pr merge 7 --repo acme/widgets --squash > "$TMPDIR/merge.log" 2>&1' \
  'gh pr merge 7 --repo acme/widgets --squash --subject "Merge: widgets" --body "fixes #3"' \
  'bash -c "gh pr merge 7 --repo acme/widgets --squash"'; do
  if ! S=$(_bum_probe_stub); then
    _flow_assert_fail "could not build the gh stub for: $CMD"; continue
  fi
  ERR=$(_bum_stderr "$S" "$CMD"); RC=$?
  if [ "$RC" -ne 0 ]; then
    _flow_assert_fail "exit $RC, expected 0, for: $CMD — got: $ERR"
  elif [ ! -e "$S/probed" ]; then
    _flow_assert_fail "allowed without looking up its checks: $CMD"
  else
    _flow_assert_pass "read and checked: $CMD"
  fi
done

# A newline inside a quoted body, or a backslash continuing a line, is one
# command to the shell. Reading either as two commands lost the merge.
_flow_test_begin "a merge written across lines is still found"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "$(printf 'gh pr merge 7 --repo acme/widgets --squash --body "Summary\n\nDetails"')"
assert_exit 2 "$?" "a multi-line --body does not hide a queued merge"
_bum_run "$S" "$(printf 'gh pr comment 7 --body "Ready.\nCloses #12" && gh pr merge 7 --repo acme/widgets --squash')"
assert_exit 2 "$?" "a # inside a multi-line string is not a comment that cuts the merge off"
_bum_run "$S" "$(printf 'gh pr \\\nmerge 7 --repo acme/widgets --squash')"
assert_exit 2 "$?" "a backslash continuation between pr and merge does not hide it"
_bum_run "$S" "$(printf 'gh pr merge 7 \\\n  --repo acme/widgets \\\n  --squash')"
assert_exit 2 "$?" "a merge continued over three lines is read as one"
S=$(_bum_stub "$GREEN" "" "")
_bum_run "$S" "$(printf 'gh pr merge 7 \\\n  --repo acme/widgets \\\n  --squash')"
assert_exit 0 "$?" "and the same merge on a green PR is allowed, so it was read whole"
_bum_run "$S" "$(printf 'echo done \\\\\ngh pr view 7')"
assert_exit 0 "$?" "an escaped backslash at a line end does not continue the line"

_flow_test_begin "quote-split spellings of merge are still read"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" 'gh pr me""rge 7 --repo acme/widgets --squash'
assert_exit 2 "$?" "me\"\"rge is merge"

# --- gh api and gh alias: refused, not parsed ----------------------------------
_flow_test_begin "gh api on a merge is refused outright"
for CMD in \
  'gh api -X PUT repos/acme/widgets/pulls/7/merge' \
  'gh api -X=PUT repos/acme/widgets/pulls/7/merge' \
  'gh api --method PUT https://api.github.com/repos/acme/widgets/pulls/7/merge' \
  'gh api -X PUT repos/{owner}/{repo}/pulls/7/merge' \
  'gh api /graphql -f query="mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }"' \
  'gh api graphql -f query="mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"x\"}) { clientMutationId } }"' \
  'gh api graphql -f query="mutation { enqueuePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }"' \
  'gh api graphql -f query="mutation { mergeBranch(input: {repositoryId: \"x\", base: \"main\", head: \"feature\"}) { clientMutationId } }"' \
  'gh api graphql -F query=@merge.graphql' \
  'gh api graphql --input q.json' \
  'echo merge next && gh api -X PUT "$EP"' \
  'gh api -X POST repos/acme/widgets/merges -f base=main -f head=feature' \
  'EP=repos/acme/widgets/pulls/7/merge; gh api -X PUT "$EP"' \
  "gh alias set m 'pr merge'"; do
  if ! S=$(_bum_probe_stub); then
    _flow_assert_fail "could not build the gh stub for: $CMD"; continue
  fi
  ERR=$(_bum_stderr "$S" "$CMD"); RC=$?
  if [ "$RC" -ne 2 ]; then
    _flow_assert_fail "exit $RC, expected 2, for: $CMD"
  elif [ -e "$S/called" ]; then
    _flow_assert_fail "gh was called for a refused api call: $CMD"
  else
    _flow_assert_pass "refused: $CMD"
  fi
done
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" 'gh api repos/acme/widgets/pulls/7 --jq .mergeable_state'
assert_exit 0 "$?" "an api read whose only merge is a field name is untouched"
_bum_run "$S" 'gh api repos/acme/widgets/pulls/7 --jq .state'
assert_exit 0 "$?" "an api call with no merge in it is untouched"
_bum_run "$S" 'gh api graphql -f query="{ viewer { login } }"'
assert_exit 0 "$?" "an inline GraphQL query with no merge in it is untouched"
_bum_run "$S" 'gh api graphql -f query="query(\$o:String!){ repository(owner:\$o,name:\"widgets\"){ pullRequest(number:7){ mergeable } } }" -F o=acme'
assert_exit 0 "$?" "a GraphQL query with variables is a query, not an unreadable merge"
_bum_run "$S" 'gh api "repos/$REPO/pulls/$PR" --jq .mergeable'
assert_exit 0 "$?" "an endpoint with variables in its path is not a merge endpoint"
_bum_run "$S" 'gh api "repos/$REPO/issues/$PR_NUM/comments" && git log --merges -1'
assert_exit 0 "$?" "a merge elsewhere in the command does not make an api read with variables a merge"
_bum_run "$S" "gh api graphql -f query='query(\$owner:String!,\$name:String!,\$pr:Int!){repository(owner:\$owner,name:\$name){pullRequest(number:\$pr){autoMergeRequest{enabledAt mergeMethod}}}}' -f owner=acme -f name=widgets -F pr=7"
assert_exit 0 "$?" "reading a pull request's autoMergeRequest is a query, not the auto-merge mutation"
_bum_run "$S" "gh api graphql -f query='{ repository(owner:\"acme\", name:\"widgets\") { autoMergeAllowed mergeCommitAllowed squashMergeAllowed } }'"
assert_exit 0 "$?" "reading a repository's merge settings is a query"
_bum_run "$S" "gh api graphql -f query='{ repository(owner:\"acme\", name:\"widgets\") { pullRequest(number: 7) { viewerCanEnableAutoMerge } } }'"
assert_exit 0 "$?" "reading viewerCanEnableAutoMerge is a query"

# --- lines, comments and heredocs, read the way the shell reads them ----------
# Each of these once lost a merge, or refused text that only mentions one.
_flow_test_begin "a comment ending in a backslash does not swallow the next line"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "$(printf '# clean up first \\\ngh pr merge 7 --repo acme/widgets --squash')"
assert_exit 2 "$?" "a merge after a comment ending in a backslash is still checked"
_bum_run "$S" "$(printf 'ls # list \\\ngh pr merge 7 --repo acme/widgets --squash')"
assert_exit 2 "$?" "and after a trailing comment ending in a backslash"

_flow_test_begin "an apostrophe in a heredoc body does not hide what follows"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "$(printf "git commit -F - <<EOF\nDon't ship yet\nEOF\ngit commit --amend -m 'Refs #12' && gh pr merge 7 --repo acme/widgets --squash")"
assert_exit 2 "$?" "a quoted # after a kept heredoc with an apostrophe does not cut the merge off"
S=$(_bum_stub "$GREEN" "" "")
_bum_run "$S" "$(printf "cat > notes.md <<'X'\nit's done\nX\ngh pr merge 3 --repo acme/widgets --squash\ngh pr merge 7 --repo acme/widgets --squash --body \"Summary")"
assert_exit 2 "$?" "a merge in a command whose quotes do not balance is refused, even beside one in the shape"
# Two bodies with one apostrophe each, or a body and a comment with one, pair up
# and balance, so the text looks balanced with the merge between hidden.
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "$(printf "git commit -F - <<'EOF'\nfix: don't drop the cache\nEOF\ngh pr merge 9 --repo acme/widgets --squash\ngit commit -F - <<'EOF'\ndocs: it's documented now\nEOF")"
assert_exit 2 "$?" "a merge between two commit bodies with an apostrophe each is checked"
_bum_run "$S" "$(printf "git commit -F - <<'EOF'\r\nfix: don't drop the cache\r\nEOF\r\ngh pr merge 9 --repo acme/widgets --squash\r\ngit commit -F - <<'EOF'\r\ndocs: it's documented now\r\nEOF\r\n")"
assert_exit 2 "$?" "and with CRLF line endings"
_bum_run "$S" "$(printf "cat > notes.md <<'EOF'\nDon't merge before CI.\nEOF\ngh pr merge 9 --repo acme/widgets --squash   # we're green")"
assert_exit 2 "$?" "a merge after a body with an apostrophe, carrying a comment with one, is checked"
_bum_run "$S" "$(printf "cat <<EOF | tee x.md\nWe're shipping\nEOF\ngh pr merge 9 --repo acme/widgets --squash\necho 'merged' # that's it")"
assert_exit 2 "$?" "a merge after a piped body with an apostrophe is checked"

_flow_test_begin "a dollar-quoted string ends where the shell ends it"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "echo \$'it\\'s' && gh pr merge 9 --repo acme/widgets --squash && echo \$'don\\'t'"
assert_exit 2 "$?" "a merge between two dollar-quoted strings with escaped quotes is checked"
_bum_run "$S" "echo \$'All checks green'; gh pr merge 9 --repo acme/widgets --squash"
assert_exit 2 "$?" "a merge after a dollar-quoted string containing A is checked"
_bum_run "$S" "git commit -m \$'Add merge gate\\n\\nRefs #195' && gh pr merge 9 --repo acme/widgets --squash"
assert_exit 2 "$?" "a merge after a dollar-quoted commit message with a # is checked"
_bum_run "$S" "echo \\\$'x\\' ; gh pr merge 9 --repo acme/widgets --squash"
assert_exit 2 "$?" "an escaped dollar before a quote does not open a dollar-quoted string"

_flow_test_begin "-h as the value of an option is not a request for help"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "gh pr merge 9 --repo acme/widgets --squash --subject -h"
assert_exit 2 "$?" "--subject -h merges, so it is checked"

_flow_test_begin "text that mentions a merge on a middle line is text"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "$(printf 'git commit -m "fix(flow): the gate\n\nThe hook now reads gh pr merge 9 --squash.\nCloses #195"')"
assert_exit 0 "$?" "a multi-line commit message naming a merge is not a merge"
_bum_run "$S" "$(printf 'gh pr create --title t --body "## Summary\n- gate reads gh pr merge 9"')"
assert_exit 0 "$?" "a multi-line PR body naming a merge is not a merge"
_bum_run "$S" 'gh pr merge --help'
assert_exit 0 "$?" "asking gh how to merge merges nothing"

# The preflight blocks of /flow:merge run the gh calls a model also runs. None of
# them is a merge, so none may be refused.
_flow_test_begin "the preflight blocks of /flow:merge pass this hook"
S=$(_bum_stub "$QUEUED" "" "")
BLOCKS_DIR="$BUM_ROOT/merge-md-blocks"
mkdir -p "$BLOCKS_DIR"
awk -v dir="$BLOCKS_DIR" '
  /^```!$/ { inb = 1; nb++; f = sprintf("%s/block-%02d.sh", dir, nb); next }
  inb && /^```$/ { inb = 0; close(f); next }
  inb { print > f }
' "$REPO_ROOT/plugins/flow/commands/merge.md"
NBLOCKS=$(ls "$BLOCKS_DIR" | wc -l | tr -d ' ')
if [ "$NBLOCKS" -lt 3 ]; then
  _flow_assert_fail "found only $NBLOCKS preflight blocks in merge.md"
else
  for B in "$BLOCKS_DIR"/block-*.sh; do
    ERR=$(_bum_stderr "$S" "$(cat "$B")"); RC=$?
    if [ "$RC" -eq 0 ]; then
      _flow_assert_pass "$(basename "$B") passes"
    else
      _flow_assert_fail "$(basename "$B") of merge.md is refused (exit $RC): $ERR"
    fi
  done
fi

# --- the parser must actually load ---------------------------------------------
_flow_test_begin "a parser that did not load refuses"
BROKEN="$BUM_ROOT/broken"
mkdir -p "$BROKEN/lib"
cp "$HOOK" "$BROKEN/block-unchecked-merge.sh"
printf '# truncated\n' > "$BROKEN/lib/command-parse.sh"
S=$(_bum_stub "$GREEN" "" "")
JSON=$(printf '%s' "gh pr merge 7 --repo acme/widgets --squash" | jq -Rs .)
ERR=$(printf '{"tool_input":{"command":%s}}' "$JSON" | PATH="$S:$PATH" bash "$BROKEN/block-unchecked-merge.sh" 2>&1 >/dev/null); RC=$?
assert_exit 2 "$RC" "a library that defines nothing blocks rather than allows"
assert_contains "did not load" "$ERR" "and says so"

# --- a long command costs linear time ------------------------------------------
_flow_test_begin "a merge after thousands of words is checked in reasonable time"
S=$(_bum_stub "$QUEUED" "" "")
FILES=$(seq 1 20000 | sed 's/^/f/' | tr '\n' ' ')
START=$(date +%s)
_bum_run "$S" "git add $FILES && gh pr merge 7 --repo acme/widgets --squash"
RC=$?
ELAPSED=$(( $(date +%s) - START ))
assert_exit 2 "$RC" "the merge at the end is found"
if [ "$ELAPSED" -le 20 ]; then
  _flow_assert_pass "20000 words took ${ELAPSED}s"
else
  _flow_assert_fail "20000 words took ${ELAPSED}s; the hook's own timeout would let the merge through"
fi

# Every Bash call passes through this hook, so a long PR body or comment that
# never merges anything must not wait on it. A bash pattern substitution over
# such a body once took 49s for 9KB under a UTF-8 locale.
_flow_test_begin "a long PR comment with no merge in it passes quickly"
S=$(_bum_stub "$QUEUED" "" "")
PARA="Reviewed the gate — it’s “fine”; don't worry, it's ok. The checks pass and this body is long."
BODY=""
for _ in $(seq 1 100); do BODY="$BODY$PARA"$'\n'; done
START=$(date +%s)
LC_ALL=en_US.UTF-8 _bum_run "$S" "gh pr comment 7 --repo acme/widgets --body \"\$(cat <<'EOF'
$BODY
EOF
)\""
RC=$?
ELAPSED=$(( $(date +%s) - START ))
assert_exit 0 "$RC" "the comment is allowed"
if [ "$ELAPSED" -le 3 ]; then
  _flow_assert_pass "a ${#BODY}-character comment took ${ELAPSED}s"
else
  _flow_assert_fail "a ${#BODY}-character comment took ${ELAPSED}s; every ordinary gh call would stall on this hook"
fi

# --- registered where it will actually run ------------------------------------
_flow_test_begin "the hook is registered on PreToolUse for Bash"
HOOKS_JSON="$REPO_ROOT/plugins/flow/hooks/hooks.json"
if command -v python3 >/dev/null 2>&1; then
  REGISTERED=$(python3 -c "
import json,sys
d=json.load(open('$HOOKS_JSON'))
pre=d.get('hooks',{}).get('PreToolUse',[])
print(sum(1 for m in pre if m.get('matcher')=='Bash'
          for h in m.get('hooks',[]) if 'block-unchecked-merge.sh' in h.get('command','')))
" 2>/dev/null)
  if [ "${REGISTERED:-0}" = "1" ]; then
    _flow_assert_pass "hooks.json runs it on PreToolUse/Bash"
  else
    _flow_assert_fail "block-unchecked-merge.sh is not registered in hooks.json — it would never run"
  fi
else
  if grep -q 'block-unchecked-merge.sh' "$HOOKS_JSON"; then
    _flow_assert_pass "hooks.json names it (python3 unavailable for a structural check)"
  else
    _flow_assert_fail "block-unchecked-merge.sh is not named in hooks.json"
  fi
fi

_flow_test_begin "the hook is executable"
if [ -x "$HOOK" ]; then
  _flow_assert_pass "mode allows execution"
else
  _flow_assert_fail "$HOOK is not executable, so the hook runner cannot start it"
fi

# --- the bypass matrix --------------------------------------------------------
# Twenty-seven commands that two reviewers constructed against an earlier
# version of this hook, each of which let a merge through. They live in a
# python fixture rather than here because each needs a gh stub that answers
# differently per selector and LOGS ITS ARGV — the discriminating input this
# file could not see, because the stub above matches on "$1 $2" and ignores
# everything after it. That is why a green run of this file was not evidence.
_flow_test_begin "every known bypass is closed"
MATRIX="$REPO_ROOT/plugins/flow/tests/fixtures/merge-bypass-matrix.py"
if ! command -v python3 >/dev/null 2>&1; then
  _flow_assert_pass "SKIP: python3 unavailable"
elif [ ! -f "$MATRIX" ]; then
  _flow_assert_fail "the bypass matrix is missing at $MATRIX"
else
  MOUT=$(python3 "$MATRIX" "$HOOK" 2>&1); MRC=$?
  MCOUNT=$(printf '%s' "$MOUT" | sed -n 's/^\([0-9]*\) bypass cases.*/\1/p')
  if [ "$MRC" -eq 0 ] && [ "${MCOUNT:-0}" -ge 25 ]; then
    _flow_assert_pass "$MCOUNT bypass cases, all correct"
  else
    _flow_assert_fail "bypass matrix failed (exit $MRC, ${MCOUNT:-0} cases):
$(printf '%s' "$MOUT" | grep -E '^  BAD|wrong$' | head -12)"
  fi
fi
