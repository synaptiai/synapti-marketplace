# shellcheck shell=bash
# End-to-end: the GitHub rulesets step of /flow:setup (commands/setup.md,
# Phase 5). The two fences run as Claude Code runs them, in a scratch
# repository, with gh replaced by a fake that answers the calls the fences
# make and keeps what they post.
#
# Ways it can be wrong, written down before the scenarios:
#   R1 the state is misread: flow's rulesets are reported as missing (and
#      offered again), another ruleset is reported as flow's, or GitHub's
#      refusal (the free-plan 403) is reported as "none"
#   R2 a ruleset is created with the wrong target, branch pattern or rules:
#      the default branch is not limited to pull requests, force pushes or
#      deletion are not blocked, tags can still be moved or deleted
#   R3 the approval count is not the one chosen, or a value other than 0 or
#      1 creates anything
#   R4 a failure on GitHub is reported as created

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

SETUP="$E2E_PLUGIN_DIR/commands/setup.md"

# _sr_setup <name> <purpose> <rulesets answer: a JSON list, or http403, or fail>
# — a scratch repository and a fake gh. `gh repo view` answers acme/web;
# `gh api repos/acme/web/rulesets` answers $3; a POST saves its body as
# post-<n>.json and answers {} (or fails when $E2E_DIR/post.fail exists).
_sr_setup() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
  ( _e2e_git_env; cd "$E2E_REPO" && git remote add origin https://github.com/acme/web.git )
  printf '%s' "$3" > "$E2E_DIR/rulesets.answer"
  cat > "$E2E_BIN/gh" <<FAKE
#!/bin/sh
printf '%s\n' "\$*" >> "$E2E_DIR/gh-calls.log"
case "\$1 \$2" in
  "repo view") echo acme/web; exit 0 ;;
esac
if [ "\$1" = api ] && [ "\$2" = -X ] && [ "\$3" = POST ]; then
  [ -e "$E2E_DIR/post.fail" ] && { echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1; }
  n=\$(ls "$E2E_DIR" | grep -c '^post-')
  while [ \$# -gt 0 ]; do [ "\$1" = --input ] && cp "\$2" "$E2E_DIR/post-\$n.json"; shift; done
  echo '{}'; exit 0
fi
if [ "\$1" = api ] && case " \$* " in *" repos/acme/web/rulesets "*) true ;; *) false ;; esac; then
  a=\$(cat "$E2E_DIR/rulesets.answer")
  case "\$a" in
    http403) echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1 ;;
    fail) echo "gh: error connecting to api.github.com" >&2; exit 1 ;;
  esac
  printf '%s' "\$a" | jq -r '.[].name'; exit 0
fi
echo "unexpected gh call: \$*" >&2; exit 99
FAKE
  chmod +x "$E2E_BIN/gh"
}

for _sr in 'none|[]|RULESETS=none' 'flow|[{"name":"flow: tags"},{"name":"flow: default branch"}]|RULESETS=flow' 'other|[{"name":"main protection"}]|RULESETS=other' 'unavailable|http403|RULESETS=unavailable' 'unreadable|fail|RULESETS=unreadable'; do
  _sr_setup "setup-rulesets-read-${_sr%%|*}" "R1: GitHub answers the rulesets list with ${_sr#*|}" "$(printf '%s' "$_sr" | cut -d'|' -f2)"
  e2e_run_fence "$SETUP" "# SETUP_RULESETS_BEGIN"
  e2e_expect_line "${_sr##*|}"
  e2e_expect_line "REPO=acme/web"
done

for _sr_n in 0 1; do
  _sr_setup "setup-rulesets-create-$_sr_n" "R2, R3: create with APPROVALS=$_sr_n" "[]"
  e2e_run_fence REPO=acme/web APPROVALS=$_sr_n "$SETUP" "# SETUP_RULESETS_CREATE_BEGIN"
  e2e_expect_line "CREATED=flow: default branch"
  e2e_expect_line "CREATED=flow: tags"
  B="$E2E_DIR/post-0.json"; T="$E2E_DIR/post-1.json"
  e2e_expect_equal 'branch|active|~DEFAULT_BRANCH' "$(jq -r '[.target, .enforcement, .conditions.ref_name.include[0]] | join("|")' "$B" 2>/dev/null)" "the branch ruleset's target"
  e2e_expect_equal 'deletion non_fast_forward pull_request' "$(jq -r '[.rules[].type] | join(" ")' "$B" 2>/dev/null)" "the branch ruleset's rules"
  e2e_expect_equal "$_sr_n" "$(jq -r '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count' "$B" 2>/dev/null)" "the approvals required"
  e2e_expect_equal 'tag|active|~ALL' "$(jq -r '[.target, .enforcement, .conditions.ref_name.include[0]] | join("|")' "$T" 2>/dev/null)" "the tag ruleset's target"
  e2e_expect_equal 'deletion non_fast_forward update' "$(jq -r '[.rules[].type] | join(" ")' "$T" 2>/dev/null)" "the tag ruleset's rules"
done

_sr_setup setup-rulesets-create-bad-count "R3: APPROVALS=2 creates nothing" "[]"
e2e_run_fence REPO=acme/web APPROVALS=2 "$SETUP" "# SETUP_RULESETS_CREATE_BEGIN"
e2e_expect_out "FAILED=all"
e2e_expect_equal 0 "$(cat "$E2E_DIR/gh-calls.log" 2>/dev/null | grep -c POST)" "POST calls"

_sr_setup setup-rulesets-create-refused "R4: GitHub refuses the creation" "[]"
: > "$E2E_DIR/post.fail"
e2e_run_fence REPO=acme/web APPROVALS=0 "$SETUP" "# SETUP_RULESETS_CREATE_BEGIN"
e2e_expect_line "FAILED=flow: default branch: gh: Resource not accessible by integration (HTTP 403)"
e2e_expect_line "FAILED=flow: tags: gh: Resource not accessible by integration (HTTP 403)"
e2e_expect_no_out "CREATED="

_sr_setup setup-rulesets-read-noremote "R1: a repository with no git remote reports noremote and asks GitHub nothing" "[]"
( _e2e_git_env; cd "$E2E_REPO" && git remote remove origin )
e2e_run_fence "$SETUP" "# SETUP_RULESETS_BEGIN"
e2e_expect_line "RULESETS=noremote"
e2e_expect_equal 0 "$(cat "$E2E_DIR/gh-calls.log" 2>/dev/null | grep -c rulesets)" "rulesets calls"

_sr_setup setup-rulesets-read-half "R1: only one of flow's rulesets exists: other, not flow" '[{"name":"flow: tags"}]'
e2e_run_fence "$SETUP" "# SETUP_RULESETS_BEGIN"
e2e_expect_line "RULESETS=other"

_sr_setup setup-rulesets-review-fields "R3: with APPROVALS=1, a push after the approval dismisses it, and the approval must follow the last push" "[]"
e2e_run_fence REPO=acme/web APPROVALS=1 "$SETUP" "# SETUP_RULESETS_CREATE_BEGIN"
e2e_expect_equal "true true" "$(jq -r '.rules[] | select(.type == "pull_request") | .parameters | "\(.dismiss_stale_reviews_on_push) \(.require_last_push_approval)"' "$E2E_DIR/post-0.json" 2>/dev/null)" "dismiss stale reviews, require approval after the last push"
