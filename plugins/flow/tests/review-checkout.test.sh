# Tests that /flow:review gets the pull request's tree without putting someone else's
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
  && ln -s /etc/hosts leak \
  && printf '*.txt filter=probe\n' > .gitattributes && printf 'hi\n' > note.txt && printf 'note.txt\n' > .ignore \
  && git add .claude leak .gitattributes note.txt .ignore && git -c user.name=t -c user.email=t@t commit -q -m pr \
  && git push -q ../remote.git HEAD:refs/pull/7/head ) >/dev/null 2>&1
RC_HEAD=$(git -C "$RC_TMP/seed" rev-parse HEAD)
RC_BASE=$(git -C "$RC_TMP/seed" rev-parse HEAD~1)
git clone -q -b main "$RC_TMP/remote.git" "$RC_TMP/session" >/dev/null 2>&1
# A filter driver configured on this machine, which the pull request's
# .gitattributes names; git-lfs is the real case (it contacts a host the pull
# request's .lfsconfig names). It runs at checkout unless the attributes are
# read from somewhere else.
git -C "$RC_TMP/session" config filter.probe.smudge "touch '$RC_TMP/filter-ran'; cat"

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
assert_equal "no" "$([ -e "$RC_TMP/filter-ran" ] && echo yes || echo no)" "the filter the pull request's .gitattributes names did not run"
assert_equal "hi" "$(cat "$RC_TREE/note.txt" 2>/dev/null)" "and the file it would have filtered is checked out as committed"
assert_contains "IGNORE_FILES_REMOVED=1" "$RC_OUT" "the ignore file it ships is counted"
assert_equal "no" "$([ -e "$RC_TREE/.ignore" ] && echo yes || echo no)" "and removed, so Grep and Glob skip nothing"
assert_contains "SYMLINKS_REMOVED=1" "$RC_OUT" "the symlink the pull request ships is counted"
assert_equal "no" "$([ -L "$RC_TREE/leak" ] || [ -e "$RC_TREE/leak" ] && echo yes || echo no)" \
  "and removed, so Read cannot follow it out of the tree"
assert_equal "120000" "$(git -C "$RC_TREE" ls-tree HEAD -- leak | cut -c1-6)" "while git still has it at the head"

_flow_test_begin "the filter fixture runs when attributes are applied, so the test above can fail"
git -C "$RC_TMP/session" -c core.hooksPath=/dev/null worktree add --quiet --detach "$RC_TMP/attr-control" "$RC_HEAD" >/dev/null 2>&1
assert_equal "yes" "$([ -e "$RC_TMP/filter-ran" ] && echo yes || echo no)" "a plain worktree add runs the filter"
git -C "$RC_TMP/session" worktree remove --force "$RC_TMP/attr-control"
rm -f "$RC_TMP/filter-ran"

_flow_test_begin "git before 2.40 cannot ignore the pull request's attributes, so the checkout refuses"
mkdir -p "$RC_TMP/oldgit"
printf '#!/usr/bin/env bash\n[ "$1" = version ] && { echo "git version 2.39.5"; exit 0; }\nexec "%s" "$@"\n' "$(command -v git)" > "$RC_TMP/oldgit/git"
chmod +x "$RC_TMP/oldgit/git"
RC_WT_BEFORE=$(git -C "$RC_TMP/session" worktree list | wc -l | tr -d ' ')
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/oldgit:$RC_TMP/bin:$PATH" STUB_AUTHOR=alice STUB_USER=bob STUB_HEAD="$RC_HEAD" PR_NUM=7 bash "$RC_TMP/checkout.sh" 2>"$RC_TMP/err"); RC_CODE=$?
assert_exit 1 "$RC_CODE" "the checkout refuses"
assert_contains "git 2.40 or later" "$(cat "$RC_TMP/err")" "and says which git it needs"
assert_equal "$RC_WT_BEFORE" "$(git -C "$RC_TMP/session" worktree list | wc -l | tr -d ' ')" "no worktree is added"

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
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT")
assert_not_contains "SYMLINKS_REMOVED" "$RC_OUT" "and the tree is left as shipped, for its own tests"
assert_equal "yes" "$([ -L "$RC_TREE/leak" ] && echo yes || echo no)" "its symlink included"
_rc_run cleanup "" "" ""; RC_TREE=""

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
# The critic has no Bash tool (Read, Grep, Glob, LSP), so its line says it reads only.
RC_RULE=$(awk '/^Agent\([^)]*\)( \[challenge mode\])?:$/ { getline nxt; if (nxt !~ /\{REVIEW_TREE\}/) next; n++; if (nxt !~ /REVIEW_RUN_PR_COMMANDS/ && nxt !~ /\), reading only: /) print NR } END { print "total " n }' "$REVIEW_MD")
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

_flow_test_begin "no dispatch line runs the pull request's commands unless the flag is exactly yes"
# A rule that fires only on "no" runs everything when the value is missing,
# misspelt or left as the placeholder.
assert_equal "0" "$(grep -c 'REVIEW_RUN_PR_COMMANDS}: when it is no' "$REVIEW_MD")" "no line keys the rule on the value no"
RC_YES=$(awk '/^Agent\([^)]*\)( \[challenge mode\])?:$/ { getline nxt; if (nxt !~ /\{REVIEW_TREE\}/) next; if (nxt ~ /\), reading only: /) next; n++; if (nxt !~ /Unless REVIEW_RUN_PR_COMMANDS is exactly yes/ || nxt !~ /never `cd` into it/) print NR } END { print "total " n }' "$REVIEW_MD")
assert_match '^total [1-9][0-9]*$' "$(tail -1 <<<"$RC_YES")" "the scan reached the dispatch lines"
assert_equal "" "$(sed '$d' <<<"$RC_YES")" "dispatch lines that do not require exactly yes"
RC_HV=$(awk '/^Skill\(holdout-validation\):$/ { getline a; getline b; n++; if (b !~ /is exactly yes/ || b !~ /never `cd` into it/) print NR } END { print "total " n }' "$REVIEW_MD")
assert_match '^total [1-9]$' "$(tail -1 <<<"$RC_HV")" "the scan reached the holdout-validation calls"
assert_equal "" "$(sed '$d' <<<"$RC_HV")" "holdout-validation calls without the rule"
assert_contains 'Read the changed files of this pull request in `{REVIEW_TREE}` with `git -C` at its top, Read, Grep and Glob on full paths under it, no LSP, and run nothing from that tree.' \
  "$(cat "$REVIEW_MD")" "the Explore dispatch carries the tree and the rule"
for _RC_F in "$REVIEW_MD" "$REPO_ROOT/plugins/flow/commands/pr.md"; do
  assert_contains "Its prompt starts with that agent's dispatch sentence, copied verbatim" \
    "$(cat "$_RC_F")" "the re-pass carries the tree ($(basename "$_RC_F"))"
done
assert_contains "do not dispatch \`test-runner\`, \`test-runner-skeptic\` or \`test-runner-verifier\`" "$(cat "$REVIEW_MD")" \
  "the test reviewer is not dispatched for someone else's pull request"

_flow_test_begin "FLOW_REVIEW_RUN_PR_COMMANDS opts in only when it is 1"
for _RC_V in 0 true yes ""; do
  RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/bin:$PATH" STUB_AUTHOR=alice STUB_USER=bob STUB_HEAD="$RC_HEAD" \
           PR_NUM=7 FLOW_REVIEW_RUN_PR_COMMANDS="$_RC_V" bash "$RC_TMP/checkout.sh" 2>/dev/null)
  assert_contains "REVIEW_RUN_PR_COMMANDS=no" "$RC_OUT" "FLOW_REVIEW_RUN_PR_COMMANDS='$_RC_V' does not opt in"
  RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT"); _rc_run cleanup "" "" ""; RC_TREE=""
done

_flow_test_begin "the fallback fetch uses gh's own login and drops any other"
# Reached only with no configured remote for the repository. A wrapper logs
# git's arguments, since the local remote here needs no login at all.
git -C "$RC_TMP/session" remote remove upstream 2>/dev/null
git -C "$RC_TMP/session" remote set-url origin "$RC_TMP/elsewhere.git"
RC_REAL_GIT=$(command -v git)
mkdir -p "$RC_TMP/gitlog-bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/git.log"\nexec "%s" "$@"\n' "$RC_TMP" "$RC_REAL_GIT" > "$RC_TMP/gitlog-bin/git"
chmod +x "$RC_TMP/gitlog-bin/git"
rm -f "$RC_TMP/git.log"
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/gitlog-bin:$RC_TMP/bin:$PATH" STUB_AUTHOR=alice STUB_USER=bob STUB_HEAD="$RC_HEAD" \
         PR_NUM=7 bash "$RC_TMP/checkout.sh" 2>/dev/null)
assert_contains "-c credential.helper= -c credential.helper=!gh auth git-credential fetch" "$(cat "$RC_TMP/git.log" 2>/dev/null)" \
  "the fetch resets the credential helpers, then uses gh's"
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT"); _rc_run cleanup "" "" ""; RC_TREE=""

_flow_test_begin "a removed worktree is reported as removed even when its directory is not empty"
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/bin:$PATH" STUB_AUTHOR=alice STUB_USER=bob STUB_HEAD="$RC_HEAD" PR_NUM=7 bash "$RC_TMP/checkout.sh" 2>/dev/null)
RC_TREE=$(sed -n 's/^REVIEW_TREE=//p' <<<"$RC_OUT")
printf 'x\n' > "${RC_TREE%/tree}/beside-the-tree"
_rc_run cleanup "" "" ""
assert_contains "REVIEW_TREE_CLEANUP=removed" "$RC_OUT" "the worktree is reported removed ($RC_ERR)"
assert_equal "no" "$([ -e "$RC_TREE" ] && echo yes || echo no)" "and it is gone"
assert_contains "is not empty and was left" "$RC_ERR" "and the directory left behind is named"
RC_TREE=""

_flow_test_begin "cleanup never removes a session that is itself a linked worktree"
# git refuses to remove a main worktree whatever the spelling, so a session
# made by git clone cannot catch this; a linked one can. Each spelling names
# the session's own directory; the uncommitted file must survive every one.
git -C "$RC_TMP/session" worktree add --quiet -b linked-session "$RC_TMP/linked" 2>/dev/null
ln -s "$RC_TMP/linked" "$RC_TMP/linked-link"
printf 'keep\n' > "$RC_TMP/linked/uncommitted.txt"
for _RC_SPELL in "$RC_TMP/linked/" "$RC_TMP/linked-link" "." "$RC_TMP/linked/../linked"; do
  RC_OUT=$(cd "$RC_TMP/linked" && REVIEW_TREE="$_RC_SPELL" bash "$RC_TMP/cleanup.sh" 2>"$RC_TMP/err")
  assert_contains "REVIEW_TREE_CLEANUP=none" "$RC_OUT" "'$_RC_SPELL' is the session's own checkout ($(cat "$RC_TMP/err"))"
  assert_equal "keep" "$(cat "$RC_TMP/linked/uncommitted.txt" 2>/dev/null)" "and its uncommitted file survives '$_RC_SPELL'"
done

_flow_test_begin "cleanup removes only a detached tree inside a tmp.* directory"
mkdir -p "$RC_TMP/notmp"
git -C "$RC_TMP/session" worktree add --quiet --detach "$RC_TMP/notmp/tree" 2>/dev/null
RC_OUT=$(cd "$RC_TMP/linked" && REVIEW_TREE="$RC_TMP/notmp/tree" bash "$RC_TMP/cleanup.sh" 2>"$RC_TMP/err")
assert_contains "REVIEW_TREE_CLEANUP=refused" "$RC_OUT" "a detached tree not inside a tmp.* directory is refused"
assert_equal "yes" "$([ -d "$RC_TMP/notmp/tree" ] && echo yes || echo no)" "and is left in place"
RC_OUT=$(cd "$RC_TMP/linked" && REVIEW_TREE="$RC_TMP/tmp.gone/tree" bash "$RC_TMP/cleanup.sh" 2>"$RC_TMP/err")
assert_contains "REVIEW_TREE_CLEANUP=failed" "$RC_OUT" "a tree that cannot be removed says so on the state line"
git -C "$RC_TMP/session" worktree add --quiet --detach "$RC_TMP/other-tree" 2>/dev/null
RC_OUT=$(cd "$RC_TMP/linked" && REVIEW_TREE="$RC_TMP/other-tree" bash "$RC_TMP/cleanup.sh" 2>"$RC_TMP/err")
assert_contains "REVIEW_TREE_CLEANUP=refused" "$RC_OUT" "a worktree not named tmp.*/tree is refused"
assert_equal "yes" "$([ -d "$RC_TMP/other-tree" ] && echo yes || echo no)" "and is left in place"
mkdir -p "$RC_TMP/tmp.branch"
git -C "$RC_TMP/session" worktree add --quiet -b on-a-branch "$RC_TMP/tmp.branch/tree" 2>/dev/null
RC_OUT=$(cd "$RC_TMP/linked" && REVIEW_TREE="$RC_TMP/tmp.branch/tree" bash "$RC_TMP/cleanup.sh" 2>"$RC_TMP/err")
assert_contains "REVIEW_TREE_CLEANUP=refused" "$RC_OUT" "a tmp.*/tree on a branch is refused: the checkout step adds a detached one"
assert_equal "yes" "$([ -d "$RC_TMP/tmp.branch/tree" ] && echo yes || echo no)" "and is left in place"
mkdir -p "$RC_TMP/tmp.detached"
git -C "$RC_TMP/session" worktree add --quiet --detach "$RC_TMP/tmp.detached/tree" 2>/dev/null
RC_OUT=$(cd / && REVIEW_TREE="$RC_TMP/tmp.detached/tree" bash "$RC_TMP/cleanup.sh" 2>"$RC_TMP/err")
assert_contains "REVIEW_TREE_CLEANUP=refused" "$RC_OUT" "outside any checkout nothing can be compared, so nothing is removed"
assert_equal "yes" "$([ -d "$RC_TMP/tmp.detached/tree" ] && echo yes || echo no)" "and the tree is left in place"

# Agent fences: extract the bash fence holding a marker line.
_rc_fence() {
  # _rc_fence <file> <fixed text on a line of the fence>
  awk -v m="$2" '
    /^ *```bash/ { inb = 1; buf = ""; hit = 0; next }
    /^ *```/ && inb { inb = 0; if (hit) { printf "%s", buf; exit } next }
    inb { t = $0; sub(/^   /, "", t); buf = buf t "\n"; if (index($0, m)) hit = 1 }' "$1"
}
RC_GUARD='if [ -n "${REVIEW_TREE:-}${REVIEW_RUN_PR_COMMANDS:-}" ] && [ "${REVIEW_RUN_PR_COMMANDS:-}" != yes ]; then'

_flow_test_begin "no agent changes into the tree without the guard first"
# The guard is the one line that lets a fence run anything in the tree, and it
# runs only when the flag is exactly yes (or there is no review tree at all).
RC_UNGUARDED=""
for _RC_AG in "$REPO_ROOT"/plugins/flow/agents/*.md; do
  RC_UNGUARDED="$RC_UNGUARDED$(awk -v g="$RC_GUARD" -v f="$(basename "$_RC_AG")" '
    /^ *```bash/ { inb = 1; guarded = 0; next }
    /^ *```/ { inb = 0; next }
    inb && index($0, g) { guarded = 1 }
    inb && /cd "\$\{REVIEW_TREE/ && !guarded { print f ":" NR }' "$_RC_AG")"
done
assert_equal "" "$RC_UNGUARDED" "cd into REVIEW_TREE with no guard before it in the fence"
RC_PY=$(grep -n 'python3 -c' "$REPO_ROOT"/plugins/flow/agents/*.md)
assert_equal "" "$RC_PY" "every python3 -c in an agent runs isolated (-I), so a module in the tree is not imported"
assert_contains '--tree "${REVIEW_TREE:-.}"' "$(cat "$REPO_ROOT/plugins/flow/agents/security-reviewer.md")" \
  "the dependency diff is pointed at the tree by argument"
assert_equal "0" "$(grep -c 'grep -rn' "$REPO_ROOT/plugins/flow/agents/error-handler-inspector.md")" "no error-handling scan greps the working directory"
assert_equal "4" "$(grep -cF 'git -C "${REVIEW_TREE:-.}" grep -n' "$REPO_ROOT/plugins/flow/agents/error-handler-inspector.md")" \
  "every error-handling scan is a git grep of the tree it is given"
RC_DIFFS=$(grep -hF 'git -C "${REVIEW_TREE:-.}" diff' "$REPO_ROOT"/plugins/flow/agents/*.md | grep -v -- '--name-only' | grep -v -- '--text --no-ext-diff --no-textconv')
assert_equal "" "$RC_DIFFS" "every content diff of the tree ignores its .gitattributes"
for _RC_AG in code-reviewer error-handler-inspector finding-critic; do
  assert_contains "rooted at this session's checkout" "$(cat "$REPO_ROOT/plugins/flow/agents/$_RC_AG.md")" "$_RC_AG does not trust LSP on another tree"
done
assert_contains "callers examined: N (git grep)" "$(cat "$REPO_ROOT/plugins/flow/agents/code-reviewer.md")" "and the code reviewer counts callers with git grep there"
# Counting to a fixed number cannot see a prompt that never had them: every
# line that hands an agent the tree carries both, except the critic's, which
# has no Bash tool.
RC_NOPRE=$(grep -n '{REVIEW_TREE}' "$REVIEW_MD" | grep -v '), reading only: ' \
  | grep -v 'GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=explicit GIT_ATTR_SOURCE="$(git hash-object -t tree /dev/null)"' | cut -c1-80)
assert_equal "" "$RC_NOPRE" "prompts that name the tree without the git settings"
assert_match '^2[1-9]$' "$(grep -c 'GIT_ATTR_SOURCE="$(git hash-object -t tree /dev/null)"' "$REVIEW_MD")" \
  "the scan reached the 17 dispatches, the Explore prompt and the three holdout calls"
assert_contains "### Checks not run" "$(cat "$REPO_ROOT/plugins/flow/templates/review-comment.md")" \
  "the external review template has the section the posting step requires"
assert_contains 'git -C "${REVIEW_TREE:-.}" cat-file -e "origin/$DEFAULT_BRANCH:$CLAUDE_MD"' \
  "$(cat "$REPO_ROOT/plugins/flow/agents/convention-checker.md")" "the convention checker reads the base branch's CLAUDE.md"

_rc_mkpr() {
  # A pull request tree whose files would run code if anything loaded them.
  rm -rf "$RC_TMP/prtree"; mkdir -p "$RC_TMP/prtree" "$RC_TMP/stub"; rm -f "$RC_TMP/ran"
  printf 'open("%s/ran", "a").write("json.py\\n")\n' "$RC_TMP" > "$RC_TMP/prtree/json.py"
  printf '{"scripts":{"test":"x"}}\n' > "$RC_TMP/prtree/package.json"
  printf 'GEM\n' > "$RC_TMP/prtree/Gemfile.lock"
  for _t in npm bundle pip-audit; do
    printf '#!/bin/sh\necho %s >> "%s/ran"\n' "$_t" "$RC_TMP" > "$RC_TMP/stub/$_t"; chmod +x "$RC_TMP/stub/$_t"
  done
}

_flow_test_begin "license lookups that read the tree are not run on someone else's pull request"
assert_contains 'report those licenses as
   `not run: someone else'"'"'s pull request`' "$(cat "$REPO_ROOT/plugins/flow/agents/security-reviewer.md")" "the security reviewer says so"
assert_contains 'Your user settings file (`{user-settings-path}`' "$(cat "$REPO_ROOT/plugins/flow/commands/setup.md")" \
  "setup names the user settings file it read, not always the default path"

_flow_test_begin "run.sh clears the review variables before any suite reads them"
assert_equal "" "${REVIEW_TREE:-}${REVIEW_RUN_PR_COMMANDS:-}" "neither is set inside a test"

_flow_test_begin "the guard holds when a call drops REVIEW_TREE but keeps the flag"
_rc_fence "$REPO_ROOT/plugins/flow/agents/security-reviewer.md" "bundle audit check" > "$RC_TMP/advisory.sh"
_rc_mkpr
RC_OUT=$(cd "$RC_TMP/prtree" && env -u REVIEW_TREE PATH="$RC_TMP/stub:$PATH" REVIEW_RUN_PR_COMMANDS=no bash "$RC_TMP/advisory.sh" 2>&1)
assert_contains "ADVISORY=not run" "$RC_OUT" "the audits say they did not run"
assert_equal "" "$(cat "$RC_TMP/ran" 2>/dev/null)" "and none of them ran"

_flow_test_begin "the advisory audits do not run in someone else's pull request's tree"
_rc_fence "$REPO_ROOT/plugins/flow/agents/security-reviewer.md" "bundle audit check" > "$RC_TMP/advisory.sh"
assert_contains "$RC_GUARD" "$(cat "$RC_TMP/advisory.sh")" "the advisory fence extracts with its guard"
_rc_mkpr
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/stub:$PATH" REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=no bash "$RC_TMP/advisory.sh" 2>&1)
assert_contains "ADVISORY=not run: someone else's pull request" "$RC_OUT" "it says the audits did not run"
assert_equal "" "$(cat "$RC_TMP/ran" 2>/dev/null)" "and none of them ran"
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/stub:$PATH" REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS='{REVIEW_RUN_PR_COMMANDS}' bash "$RC_TMP/advisory.sh" 2>&1)
assert_equal "" "$(cat "$RC_TMP/ran" 2>/dev/null)" "an unfilled placeholder runs nothing either"
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/stub:$PATH" REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=yes bash "$RC_TMP/advisory.sh" 2>&1)
assert_contains "bundle" "$(cat "$RC_TMP/ran" 2>/dev/null)" "with yes they run, in the tree"
assert_contains "ADVISORY=unavailable: npm audit returned no report" "$RC_OUT" "an audit that returned nothing says so, not an empty table"
printf '#!/bin/sh\necho bundle >> "%s/ran"\nexit 7\n' "$RC_TMP" > "$RC_TMP/stub/bundle"
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/stub:$PATH" REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=yes bash "$RC_TMP/advisory.sh" 2>&1)
assert_contains "ADVISORY=unavailable: bundle audit check exited 7" "$RC_OUT" "an audit that failed says so"
printf '#!/bin/sh\necho "bundle $*" >> "%s/ran"\n' "$RC_TMP" > "$RC_TMP/stub/bundle"
printf '#!/bin/sh\necho "pip-audit $*" >> "%s/ran"\n' "$RC_TMP" > "$RC_TMP/stub/pip-audit"
chmod +x "$RC_TMP/stub/bundle" "$RC_TMP/stub/pip-audit"
printf 'flask==2.0.0\n' > "$RC_TMP/prtree/requirements.txt"
for _RC_SH in bash zsh; do
  command -v "$_RC_SH" >/dev/null 2>&1 || continue
  rm -f "$RC_TMP/ran"
  RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/stub:$PATH" REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=yes "$_RC_SH" "$RC_TMP/advisory.sh" 2>&1)
  assert_contains "bundle audit check" "$(cat "$RC_TMP/ran" 2>/dev/null)" "$_RC_SH runs bundle with its arguments ($RC_OUT)"
  assert_contains "pip-audit -r requirements.txt" "$(cat "$RC_TMP/ran" 2>/dev/null)" "$_RC_SH audits the project's requirements, not this machine's Python"
done

_flow_test_begin "the test reviewer's fences run nothing in someone else's pull request's tree"
_rc_fence "$REPO_ROOT/plugins/flow/agents/test-runner.md" '[ -f "tsconfig.json" ]' > "$RC_TMP/tr1.sh"
assert_contains "$RC_GUARD" "$(cat "$RC_TMP/tr1.sh")" "Step 1 extracts with its guard"
_rc_mkpr
RC_OUT=$(cd "$RC_TMP/session" && REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=no bash "$RC_TMP/tr1.sh" 2>&1)
assert_contains "not run: someone else's pull request" "$RC_OUT" "it reports not run"
assert_not_contains "node" "$RC_OUT" "and detects nothing"
RC_OUT=$(cd "$RC_TMP/session" && REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=yes bash "$RC_TMP/tr1.sh" 2>&1)
assert_contains "test: x" "$RC_OUT" "with yes it reads the scripts"
assert_equal "" "$(cat "$RC_TMP/ran" 2>/dev/null)" "and the tree's json.py is still not imported"

_flow_test_begin "the test reviewer's lint and test step runs nothing in someone else's pull request's tree"
_rc_fence "$REPO_ROOT/plugins/flow/agents/test-runner.md" 'bash -c "$TEST_CMD" 2>&1' > "$RC_TMP/tr4.sh"
assert_contains "$RC_GUARD" "$(cat "$RC_TMP/tr4.sh")" "Step 4 extracts with its guard"
rm -f "$RC_TMP/lint-ran"
RC_OUT=$(cd "$RC_TMP/session" && REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=no LINT_CMD="touch $RC_TMP/lint-ran" TEST_CMD=true TYPECHECK_CMD=true bash "$RC_TMP/tr4.sh" 2>&1)
assert_equal "no" "$([ -e "$RC_TMP/lint-ran" ] && echo yes || echo no)" "the lint command did not run"
RC_OUT=$(cd "$RC_TMP/session" && REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=yes LINT_CMD="touch $RC_TMP/lint-ran" TEST_CMD=true TYPECHECK_CMD=true bash "$RC_TMP/tr4.sh" 2>&1)
assert_equal "yes" "$([ -e "$RC_TMP/lint-ran" ] && echo yes || echo no)" "with yes it does"
if command -v zsh >/dev/null 2>&1; then
  rm -f "$RC_TMP/lint-ran"
  RC_OUT=$(cd "$RC_TMP/session" && REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=yes LINT_CMD="touch $RC_TMP/lint-ran" TEST_CMD=true TYPECHECK_CMD=true zsh "$RC_TMP/tr4.sh" 2>&1)
  assert_equal "yes" "$([ -e "$RC_TMP/lint-ran" ] && echo yes || echo no)" "a command with an argument runs under zsh too ($RC_OUT)"
fi
_rc_fence "$REPO_ROOT/plugins/flow/agents/test-runner.md" 'CLAUDE_MD=".claude/CLAUDE.md"' > "$RC_TMP/tr2.sh"
printf 'npm test\n' > "$RC_TMP/prtree/CLAUDE.md"
RC_OUT=$(cd "$RC_TMP/session" && REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=no bash "$RC_TMP/tr2.sh" 2>&1)
assert_not_contains "npm test" "$RC_OUT" "Step 2 does not read the tree's CLAUDE.md either"

_flow_test_begin "the convention checker reads the base branch's CLAUDE.md, and says when there is none"
_rc_fence "$REPO_ROOT/plugins/flow/agents/convention-checker.md" 'CONVENTIONS_FROM=""' > "$RC_TMP/conv.sh"
mkdir -p "$RC_TMP/nogh"; printf '#!/bin/sh\nexit 1\n' > "$RC_TMP/nogh/gh"; chmod +x "$RC_TMP/nogh/gh"
( cd "$RC_TMP" && git init -q -b main conv && cd conv \
  && printf 'Commit: base-rule\n' > CLAUDE.md && git add CLAUDE.md \
  && git -c user.name=t -c user.email=t@t commit -q -m base && git update-ref refs/remotes/origin/main HEAD \
  && printf 'Commit: pr-rule\n' > CLAUDE.md && git -c user.name=t -c user.email=t@t commit -q -am pr ) >/dev/null 2>&1
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/nogh:$PATH" REVIEW_TREE="$RC_TMP/conv" bash "$RC_TMP/conv.sh" 2>&1)
assert_contains "base-rule" "$RC_OUT" "the base branch's rule is read"
assert_not_contains "pr-rule" "$RC_OUT" "not the one the pull request wrote"
assert_contains "CONVENTIONS=origin/main:CLAUDE.md" "$RC_OUT" "and it says which file"
( cd "$RC_TMP" && git init -q -b main conv2 && cd conv2 \
  && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base && git update-ref refs/remotes/origin/main HEAD \
  && printf 'Commit: pr-rule\n' > CLAUDE.md && git add CLAUDE.md && git -c user.name=t -c user.email=t@t commit -q -m pr ) >/dev/null 2>&1
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/nogh:$PATH" REVIEW_TREE="$RC_TMP/conv2" bash "$RC_TMP/conv.sh" 2>&1)
assert_contains "CONVENTIONS=unavailable" "$RC_OUT" "a base with no CLAUDE.md is reported, not read as clean"
assert_not_contains "pr-rule" "$RC_OUT" "and the pull request's own file is not used instead"

_flow_test_begin "the convention checker lists the pull request's commits against origin, and says when it cannot"
_rc_fence "$REPO_ROOT/plugins/flow/agents/convention-checker.md" 'COMMITS=unavailable' > "$RC_TMP/commits.sh"
# conv's local main is its head, one commit past origin/main: comparing with the
# local branch would list nothing and pass every commit check unread.
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/nogh:$PATH" REVIEW_TREE="$RC_TMP/conv" bash "$RC_TMP/commits.sh" 2>&1)
assert_match '^[0-9a-f]{40} pr$' "$RC_OUT" "the pull request's commit is listed"
( cd "$RC_TMP" && git init -q -b main conv3 && git -C conv3 -c user.name=t -c user.email=t@t commit -q --allow-empty -m only ) >/dev/null 2>&1
RC_OUT=$(cd "$RC_TMP/session" && PATH="$RC_TMP/nogh:$PATH" REVIEW_TREE="$RC_TMP/conv3" bash "$RC_TMP/commits.sh" 2>&1)
assert_contains "COMMITS=unavailable" "$RC_OUT" "with no origin/main it says the commits could not be listed"

_flow_test_begin "the duplication scan does not run in someone else's pull request's tree"
_rc_fence "$REPO_ROOT/plugins/flow/agents/code-reviewer.md" 'flow-clone-scan.sh" --base' > "$RC_TMP/clone.sh"
assert_contains "$RC_GUARD" "$(cat "$RC_TMP/clone.sh")" "the clone scan fence extracts with its guard"
RC_OUT=$(cd "$RC_TMP/session" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" DEFAULT_BRANCH=main REVIEW_TREE="$RC_TMP/prtree" REVIEW_RUN_PR_COMMANDS=no bash "$RC_TMP/clone.sh" 2>&1)
assert_contains "REASON=not run: someone else's pull request" "$RC_OUT" "it says the scan did not run"
rm -rf "$RC_TMP"
