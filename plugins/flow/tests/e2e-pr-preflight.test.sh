# shellcheck shell=bash
# End-to-end: /flow:pr's Phase 1 pre-flight on the branch delta.
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

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

PR_MD="$E2E_PLUGIN_DIR/commands/pr.md"
PR_PHASE1='### Branch Delta'

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
