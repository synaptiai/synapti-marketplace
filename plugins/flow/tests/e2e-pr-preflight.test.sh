# shellcheck shell=bash
# End-to-end: /flow:pr's Phase 1 pre-flight on the branch delta, and the
# record /flow:pr writes when the user overrides the FlowGoal gate (Phase 4
# step 7a, Option 2).
#
# Each scenario runs the shipped fence from commands/pr.md in a scratch
# repository, under zsh (when installed) and bash, with gh answering from
# fixtures. The repository's default branch is created as main, the name the
# gh fixture gives, so the count of commits ahead is read from a real ref.
#
# Ways it can be wrong, written down before the scenarios:
#
# Pre-flight (Phase 1, Branch Delta)
#   P1 a branch with zero commits ahead of the default branch reports
#      STATE=ok and goes on, so /flow:pr reviews and opens an empty PR
#   P2 a branch with commits ahead is blocked as well (the check is inverted,
#      or compares against the wrong ref)
#   P3 a count that could not be read (no local ref for the default branch)
#      is taken as zero and reported as "no commits ahead", stopping a branch
#      that may well have commits; it must be reported as unavailable
#   P4 an existing open PR for the branch blocks instead of being listed
#      for the "offer to update" step
#
# Goal-gate override record (Phase 4 step 7a)
#   G1 on a branch with no issue number nothing is recorded
#   G2 the record lacks escalation_field, the field the schema row for
#      escalation-resolved requires, or names a field outside the six
#   G3 on an issue branch the record goes to the session journal instead of
#      issue-<N>.md

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "pr pre-flight: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

# One record per shell the block runs under.
RUNS=$(set -- $E2E_FENCE_SHELLS; printf '%s' "$#")

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

PR_MD="$E2E_PLUGIN_DIR/commands/pr.md"
PR_PHASE1='### Branch Delta'
PR_OVERRIDE='PR_GOAL_OVERRIDE_BLOCK'

# _section <heading> — the lines of one ### section of the fence's output.
_section() {
  printf '%s\n' "$E2E_OUT" | awk -v h="### $1" '$0 == h { f = 1; next } /^### / { f = 0 } f'
}

# _pr_repo <branch> <commits on it> [default branch ref] — a scratch repository
# on <branch>, with main at the first commit (unless the third argument is
# "no-main") and the given number of commits on the branch after it. gh says
# the default branch is main and that the branch has no open PR.
_pr_repo() {
  local i
  e2e_repo "$1"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    [ "${3:-}" = no-main ] || git branch -f main HEAD
    i=0
    while [ "$i" -lt "$2" ]; do
      i=$((i + 1))
      printf '%s\n' "$i" > "work-$i.txt"
      git add "work-$i.txt"
      git commit -q -m "feat: work $i"
    done
  ) || _flow_assert_fail "$E2E_NAME: could not set up the scratch repository"
  e2e_gh_fixture repo '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}'
  e2e_gh_fixture "open-prs-$(printf '%s' "$1" | tr / _)" '[]'
  # The Review Exceptions section's ref lookup fails: that section reports
  # unavailable, which these scenarios do not look at.
  e2e_gh_fail commit-main
}

if _want pr-zero-ahead; then
  _flow_test_begin "pr-zero-ahead"
  e2e_new pr-zero-ahead
  e2e_describe "branch feature/tidy has no commits beyond main: the Branch Delta section blocks (P1)"
  _pr_repo feature/tidy 0
  e2e_run_fence "$PR_MD" "$PR_PHASE1"
  e2e_expect_equal "$(printf 'COMMITS_AHEAD=0\nSTATE=blocked\nERROR="No commits ahead of main: there is nothing to open a pull request for"')" \
    "$(_section 'Branch Delta' | grep -E '^(COMMITS_AHEAD|STATE|ERROR)=')" "the Branch Delta section"
  e2e_expect_clean_edges
fi

if _want pr-ahead; then
  _flow_test_begin "pr-ahead"
  e2e_new pr-ahead
  e2e_describe "branch feature/tidy has two commits beyond main: the Branch Delta section is not blocked (P2)"
  _pr_repo feature/tidy 2
  e2e_run_fence "$PR_MD" "$PR_PHASE1"
  e2e_expect_equal "COMMITS_AHEAD=2" "$(_section 'Branch Delta' | grep -E '^(COMMITS_AHEAD|STATE|ERROR)=')" "the Branch Delta section"
  e2e_expect_line "### Decision Journal"
  e2e_expect_clean_edges
fi

if _want pr-ahead-unreadable; then
  _flow_test_begin "pr-ahead-unreadable"
  e2e_new pr-ahead-unreadable
  e2e_describe "gh names main as the default branch, but the repository has no main ref: the count is unavailable, not zero (P3)"
  _pr_repo feature/tidy 1 no-main
  e2e_run_fence "$PR_MD" "$PR_PHASE1"
  e2e_expect_equal "$(printf 'STATE=unavailable\nERROR="Cannot count the commits ahead of main: git rev-list main..HEAD failed (is main fetched?)"')" \
    "$(_section 'Branch Delta' | grep -E '^(COMMITS_AHEAD|STATE|ERROR)=')" "the Branch Delta section"
  e2e_expect_clean_edges
fi

if _want pr-existing-pr; then
  _flow_test_begin "pr-existing-pr"
  e2e_new pr-existing-pr
  e2e_describe "branch feature/tidy has one commit beyond main and an open PR: the PR is listed and nothing blocks (P4)"
  _pr_repo feature/tidy 1
  e2e_gh_fixture open-prs-feature_tidy '[{"number":7,"url":"https://github.com/o/r/pull/7"}]'
  e2e_run_fence "$PR_MD" "$PR_PHASE1"
  e2e_expect_line "EXISTING_PR_COUNT=1"
  e2e_expect_line "EXISTING_PR=number=7 url=https://github.com/o/r/pull/7"
  e2e_expect_no_line "STATE=blocked"
  e2e_expect_clean_edges
fi

# _manifest_of <file under the repo> — the escalation-resolved artifacts in a
# journal's manifest: the manifest key, how many there are, and the distinct
# escalation_field, gate and outcome values among them. The block runs once
# under each shell in E2E_FENCE_SHELLS, so each run adds one.
_manifest_of() {
  python3 - "$E2E_REPO/$1" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
m = yaml.safe_load(t.split("---\n")[1])
key = "issue=%s" % m["issue"] if "issue" in m else "session=%s" % m.get("session")
arts = [a for a in m["artifacts"] if a["type"] == "escalation-resolved"]
vals = lambda k: ",".join(sorted({str(a.get(k)) for a in arts}))
print("%s count=%d field=%s gate=%s outcome=%s" % (key, len(arts),
      vals("escalation_field"), vals("gate"), vals("outcome")))
PY
}

if _want pr-override-session; then
  _flow_test_begin "pr-override-session"
  e2e_new pr-override-session
  e2e_describe "the goal-gate override on branch feature/tidy, which names no issue: recorded in today's session journal with escalation_field=blocking (G1, G2)"
  _pr_repo feature/tidy 1
  DAY_BEFORE=$(date +%Y-%m-%d)
  e2e_run_block commands/pr.md "$PR_OVERRIDE"
  DAY_AFTER=$(date +%Y-%m-%d)
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  SJ=""
  for d in "$DAY_AFTER" "$DAY_BEFORE"; do
    [ -f "$E2E_REPO/.decisions/session-$d.md" ] && { SJ=".decisions/session-$d.md"; break; }
  done
  e2e_expect_equal "yes" "$([ -n "$SJ" ] && echo yes || echo no)" "a session journal was written"
  [ -n "$SJ" ] && e2e_expect_equal "session=$(basename "$SJ" .md | sed 's/^session-//') count=$RUNS field=blocking gate=flowgoal-pr outcome=user-overrode: created PR with goal not yet achieved" \
    "$(_manifest_of "$SJ")" "the escalation-resolved artifact"
  e2e_expect_clean_edges
fi

if _want pr-override-issue; then
  _flow_test_begin "pr-override-issue"
  e2e_new pr-override-issue
  e2e_describe "the goal-gate override on branch feature/issue-42-tidy: recorded in issue-42.md with escalation_field=blocking, and no session journal (G2, G3)"
  _pr_repo feature/issue-42-tidy 1
  e2e_run_block commands/pr.md "$PR_OVERRIDE"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "issue=42 count=$RUNS field=blocking gate=flowgoal-pr outcome=user-overrode: created PR with goal not yet achieved" \
    "$(_manifest_of .decisions/issue-42.md)" "the escalation-resolved artifact"
  e2e_expect_equal "" "$(cd "$E2E_REPO/.decisions" && ls session-*.md 2>/dev/null)" "a session journal"
  e2e_expect_clean_edges
fi
