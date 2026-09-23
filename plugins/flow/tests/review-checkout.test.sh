# /flow:review gets the pull request's tree without putting someone else's
# pull request in the session's directory.
#
# Claude Code reads a .claude/settings.json that appears in the session's
# directory during the session, and its env block reaches every later command
# (checked with a live session). So a pull request checked out there could set
# PATH for the rest of the review. Someone else's pull request is fetched into a
# worktree under the temporary directory instead, checked against the head
# GitHub reports; your own is checked out as before, because self-review fixes
# forward onto its branch.

REVIEW_MD="$REPO_ROOT/plugins/flow/commands/review.md"

_rc_block() {
  awk -v b="# $1_BEGIN" -v e="# $1_END" '
    { t = $0; sub(/^[ \t]+/, "", t) }
    t == b { f = 1; next }
    t == e { f = 0 }
    f' "$REVIEW_MD"
}

RC_TMP=$(mktemp -d -t review-checkout.XXXXXX)
RC_TMP=$(cd "$RC_TMP" && pwd -P)
_rc_block REVIEW_CHECKOUT_BLOCK > "$RC_TMP/checkout.sh"
_rc_block REVIEW_TREE_CLEANUP_BLOCK > "$RC_TMP/cleanup.sh"

_flow_test_begin "the checkout and cleanup blocks extract"
assert_match '[^[:space:]]' "$(cat "$RC_TMP/checkout.sh")" "the checkout block"
assert_match '[^[:space:]]' "$(cat "$RC_TMP/cleanup.sh")" "the cleanup block"

# A remote with main and a pull request ref whose tree ships project settings.
( cd "$RC_TMP" && git init -q --bare remote.git && git init -q seed && cd seed \
  && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base \
  && git push -q ../remote.git HEAD:refs/heads/main \
  && mkdir -p .claude && printf '{"env":{"PATH":"/pr/bin"}}\n' > .claude/settings.json \
  && git add .claude && git -c user.name=t -c user.email=t@t commit -q -m pr \
  && git push -q ../remote.git HEAD:refs/pull/7/head ) >/dev/null 2>&1
RC_HEAD=$(git -C "$RC_TMP/seed" rev-parse HEAD)
RC_BASE=$(git -C "$RC_TMP/seed" rev-parse HEAD~1)
git clone -q -b main "$RC_TMP/remote.git" "$RC_TMP/session" >/dev/null 2>&1

mkdir -p "$RC_TMP/bin"
cat > "$RC_TMP/bin/gh" <<GHSTUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "repo view")
    case "\$*" in *url*) printf '%s\n' "$RC_TMP/remote.git" ;; *) printf '%s\n' "o/r" ;; esac; exit 0 ;;
  "api user") printf '%s\n' "\${STUB_USER:-}"; exit 0 ;;
  "pr view")
    case "\$*" in
      *headRefOid*) printf '%s\n' "\${STUB_HEAD:-}"; exit 0 ;;
      *author.name*) printf '%s\n' "Display Name"; exit 0 ;;
      *author*) printf '%s\n' "\${STUB_AUTHOR:-}"; exit 0 ;;
    esac; exit 1 ;;
  "pr checkout") printf 'checkout %s\n' "\$3" >> "$RC_TMP/gh.log"; exit 0 ;;
esac
exit 1
GHSTUB
chmod +x "$RC_TMP/bin/gh"
_rc_run() {
  # _rc_run <block> <author> <user> <head> -> stdout; RC_CODE, RC_ERR
  RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/bin:$PATH" STUB_AUTHOR="$2" STUB_USER="$3" STUB_HEAD="$4" \
           PR_NUM=7 REVIEW_TREE="${RC_TREE:-}" bash "$RC_TMP/$1.sh" 2>"$RC_TMP/err")
  RC_CODE=$?
  RC_ERR=$(cat "$RC_TMP/err")
}

_flow_test_begin "someone else's pull request is fetched into a worktree outside the session's directory"
rm -f "$RC_TMP/gh.log"
_rc_run checkout alice bob "$RC_HEAD"
assert_exit 0 "$RC_CODE" "the block succeeds ($RC_ERR)"
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT")
assert_match '^/' "$RC_TREE" "it prints an absolute REVIEW_TREE"
assert_equal "no" "$(case "$RC_TREE/" in ("$RC_TMP/session"/*) echo yes ;; (*) echo no ;; esac)" "outside the session's directory"
assert_equal "$RC_HEAD" "$(git -C "$RC_TREE" rev-parse HEAD 2>/dev/null)" "at the pull request's head"
assert_equal "$RC_BASE" "$(git -C "$RC_TMP/session" rev-parse HEAD)" "the session's own checkout is untouched"
assert_equal "no" "$([ -e "$RC_TMP/session/.claude/settings.json" ] && echo yes || echo no)" \
  "and the pull request's settings file is not in the session's directory"
assert_equal "no" "$([ -e "$RC_TMP/gh.log" ] && echo yes || echo no)" "gh pr checkout is not run"

_flow_test_begin "the cleanup step removes that worktree and nothing else"
_rc_run cleanup "" "" ""
assert_contains "REVIEW_TREE_CLEANUP=removed" "$RC_OUT" "it reports the removal ($RC_ERR)"
assert_equal "no" "$([ -e "$RC_TREE" ] && echo yes || echo no)" "the worktree is gone"
assert_equal "no" "$([ -e "${RC_TREE%/tree}" ] && echo yes || echo no)" "and so is the temporary directory that held it"
assert_equal "$RC_BASE" "$(git -C "$RC_TMP/session" rev-parse HEAD)" "the session's checkout is still there"
RC_TREE="$RC_TMP/session"
_rc_run cleanup "" "" ""
assert_contains "REVIEW_TREE_CLEANUP=none" "$RC_OUT" "the session's own checkout is never removed"
RC_TREE=""

_flow_test_begin "a fetched commit that is not the pull request's head is refused"
RC_WT_BEFORE=$(git -C "$RC_TMP/session" worktree list | wc -l | tr -d ' ')
_rc_run checkout alice bob "$RC_BASE"
assert_exit 1 "$RC_CODE" "the block refuses"
assert_contains "refusing to review a different commit" "$RC_ERR" "and says why"
assert_equal "$RC_WT_BEFORE" "$(git -C "$RC_TMP/session" worktree list | wc -l | tr -d ' ')" "no worktree is added"

_flow_test_begin "an author or user that cannot be read is refused, not taken as the same person"
_rc_run checkout "" "" "$RC_HEAD"
assert_exit 1 "$RC_CODE" "both empty"
assert_equal "no" "$([ -e "$RC_TMP/gh.log" ] && echo yes || echo no)" "and nothing is checked out"

_flow_test_begin "your own pull request is checked out in the session's directory"
_rc_run checkout alice alice "$RC_HEAD"
assert_exit 0 "$RC_CODE" "the block succeeds"
assert_equal "checkout 7" "$(cat "$RC_TMP/gh.log" 2>/dev/null)" "gh pr checkout is run for it"
assert_contains "REVIEW_TREE=$RC_TMP/session" "$RC_OUT" "and REVIEW_TREE is the session's own checkout"
assert_contains "REVIEW_RUN_PR_COMMANDS=yes" "$RC_OUT" "your own pull request's commands may run"

_flow_test_begin "the command names REVIEW_TREE for every reviewer and checks out nowhere else"
assert_contains 'Pass the `REVIEW_TREE` and' "$(cat "$REVIEW_MD")" "the dispatch rule is stated"
assert_equal "1" "$(grep -c 'gh pr checkout "\$PR_NUM"' "$REVIEW_MD")" "the only gh pr checkout is the one for your own pull request"

_flow_test_begin "every dispatch template in the command names REVIEW_TREE"
# A rule stated once above the templates is only as good as the template the
# dispatch is built from: each Agent(...) prompt and each holdout-validation
# call carries the tree itself.
RC_AGENTS=$(awk '/^Agent\([^)]*\)( \[challenge mode\])?:$/ { getline nxt; n++; if (nxt !~ /\{REVIEW_TREE\}/) print NR": "$0 } END { print "total " n }' "$REVIEW_MD")
assert_match '^total [1-9][0-9]*$' "$(tail -1 <<<"$RC_AGENTS")" "the scan reached the Agent templates"
assert_equal "" "$(sed '$d' <<<"$RC_AGENTS")" "Agent templates whose prompt does not name the tree"
RC_SKILLS=$(awk '/^Skill\(holdout-validation\):$/ { getline a; getline b; n++; if (b !~ /\{REVIEW_TREE\}/) print NR } END { print "total " n }' "$REVIEW_MD")
assert_match '^total [1-9]$' "$(tail -1 <<<"$RC_SKILLS")" "the scan reached the holdout-validation calls"
assert_equal "" "$(sed '$d' <<<"$RC_SKILLS")" "holdout-validation calls that do not name the tree"

_flow_test_begin "someone else's pull request is fetched from the remote already configured for the repository"
# The user's own protocol and login: an ssh remote for o/r is used, and the
# https URL gh reports is not needed (here it points nowhere).
git -C "$RC_TMP/session" remote add upstream git@github.com:o/r.git
git -C "$RC_TMP/session" config url."$RC_TMP/remote.git".insteadOf git@github.com:o/r.git
RC_REAL_URL_STUB=$(cat "$RC_TMP/bin/gh")
printf '%s\n' "$RC_REAL_URL_STUB" | sed "s|$RC_TMP/remote.git|$RC_TMP/nowhere.git|" > "$RC_TMP/bin/gh"
RC_TREE=""
_rc_run checkout alice bob "$RC_HEAD"
assert_exit 0 "$RC_CODE" "the fetch succeeds through the configured remote ($RC_ERR)"
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT")
assert_equal "$RC_HEAD" "$(git -C "$RC_TREE" rev-parse HEAD 2>/dev/null)" "at the pull request's head"
_rc_run cleanup "" "" ""
RC_TREE=""

_flow_test_begin "someone else's pull request: its commands are not run unless the reviewer opted in"
git -C "$RC_TMP/session" worktree prune
cp "$RC_TMP/bin/gh" "$RC_TMP/gh.nowhere"
sed "s|$RC_TMP/nowhere.git|$RC_TMP/remote.git|" "$RC_TMP/gh.nowhere" > "$RC_TMP/bin/gh"
_rc_run checkout alice bob "$RC_HEAD"
assert_contains "REVIEW_RUN_PR_COMMANDS=no" "$RC_OUT" "by default they are not run ($RC_ERR)"
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT"); _rc_run cleanup "" "" ""; RC_TREE=""
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/bin:$PATH" STUB_AUTHOR=alice STUB_USER=bob STUB_HEAD="$RC_HEAD" \
         PR_NUM=7 FLOW_REVIEW_RUN_PR_COMMANDS=1 bash "$RC_TMP/checkout.sh" 2>/dev/null)
assert_contains "REVIEW_RUN_PR_COMMANDS=yes" "$RC_OUT" "with FLOW_REVIEW_RUN_PR_COMMANDS=1 they are"
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT"); _rc_run cleanup "" "" ""; RC_TREE=""

_flow_test_begin "the worktree is added with git hooks switched off"
# The reviewer's own post-checkout hook would run inside the pull request's
# tree, and a hook that installs or runs the project's scripts runs its code.
mkdir -p "$RC_TMP/session/.git/hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$RC_TMP" > "$RC_TMP/session/.git/hooks/post-checkout"
chmod +x "$RC_TMP/session/.git/hooks/post-checkout"
rm -f "$RC_TMP/hook-ran"
_rc_run checkout alice bob "$RC_HEAD"
assert_exit 0 "$RC_CODE" "the checkout succeeds ($RC_ERR)"
assert_equal "no" "$([ -e "$RC_TMP/hook-ran" ] && echo yes || echo no)" "and the post-checkout hook did not run"
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT")

_flow_test_begin "the cleanup step removes a worktree the reviewers left files in"
printf 'x\n' > "$RC_TREE/left-by-a-test.txt"
_rc_run cleanup "" "" ""
assert_contains "REVIEW_TREE_CLEANUP=removed" "$RC_OUT" "it is removed ($RC_ERR)"
assert_equal "no" "$([ -e "$RC_TREE" ] && echo yes || echo no)" "and is gone"
RC_TREE=""
_rc_run cleanup "" "" ""
assert_contains "REVIEW_TREE_CLEANUP=unset" "$RC_OUT" "an unset REVIEW_TREE is reported as unset, not as nothing to do"
assert_contains "REVIEW_TREE is not set" "$RC_ERR" "with a warning"

_flow_test_begin "every dispatch line carries the rule on running the pull request's commands"
RC_RULE=$(awk '/^Agent\([^)]*\)( \[challenge mode\])?:$/ { getline nxt; if (nxt !~ /\{REVIEW_TREE\}/) next; n++; if (nxt !~ /REVIEW_RUN_PR_COMMANDS/) print NR } END { print "total " n }' "$REVIEW_MD")
assert_match '^total [1-9][0-9]*$' "$(tail -1 <<<"$RC_RULE")" "the scan reached the dispatch lines"
assert_equal "" "$(sed '$d' <<<"$RC_RULE")" "dispatch lines without the rule"

_flow_test_begin "only the same login is your own pull request"
# A near-match must take the worktree path, not the in-session checkout.
rm -f "$RC_TMP/gh.log"
for _RC_PAIR in alice-bot:alice alice:alice-bot Alice:alice; do
  _rc_run checkout "${_RC_PAIR%%:*}" "${_RC_PAIR#*:}" "$RC_HEAD"
  assert_contains "REVIEW_RUN_PR_COMMANDS=no" "$RC_OUT" "${_RC_PAIR%%:*} vs ${_RC_PAIR#*:}: someone else's pull request"
  RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT"); _rc_run cleanup "" "" ""; RC_TREE=""
done
assert_equal "no" "$([ -e "$RC_TMP/gh.log" ] && echo yes || echo no)" "and none of them was checked out in the session"

_flow_test_begin "the address trust list asks cascade-resolve which file the user tier is"
ADDR_MD="$REPO_ROOT/plugins/flow/commands/address.md"
assert_match 'cascade-resolve.sh" --user-settings-path' "$(cat "$ADDR_MD")" "it asks"
assert_contains 'for SETTINGS_PATH in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$USER_SETTINGS"; do' "$(cat "$ADDR_MD")" \
  "and reads that file"

_flow_test_begin "the reviewer agents' own git commands read the tree they are pointed at"
# A command that reads the working directory reviews the session's own branch
# in an external review: an empty diff, and a review that looks clean.
RC_AGENT_BAD=""
for _RC_AG in code-reviewer security-reviewer error-handler-inspector convention-checker; do
  RC_AGENT_BAD="$RC_AGENT_BAD$(grep -nE '(^|[^-])git (diff|log)[^|]*\.\.' "$REPO_ROOT/plugins/flow/agents/$_RC_AG.md" \
    | grep -v 'REVIEW_TREE' | grep -v '^[0-9]*:#' | sed "s|^|$_RC_AG.md:|")"
done
assert_equal "" "$RC_AGENT_BAD" "agent git diff/log commands that do not name REVIEW_TREE"

_flow_test_begin "the test-runner agent itself carries the rule on someone else's pull request"
# The dispatch line is one line; the agent's own steps discover and run
# commands, so the rule and the tree are in the agent's instructions as well.
TR_MD="$REPO_ROOT/plugins/flow/agents/test-runner.md"
assert_contains "When \`REVIEW_RUN_PR_COMMANDS=no\`" "$(cat "$TR_MD")" "the agent names the rule"
assert_contains "run none of them (skip" "$(cat "$TR_MD")" "and skips running"
assert_equal "3" "$(grep -c '^cd "\${REVIEW_TREE:-.}" || exit 1$' "$TR_MD")" "every command fence starts in the tree"
rm -rf "$RC_TMP"
