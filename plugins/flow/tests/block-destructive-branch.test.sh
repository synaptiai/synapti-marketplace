# Tests for the merge-aware force-branch-delete rule in
# hooks/scripts/block-destructive.sh.
#
# Contract under test: a force branch-delete is allowed ONLY when every target
# branch is provably merged into the default branch — via ancestor check
# (regular/fast-forward merge) or synthetic-commit patch-equivalence (squash
# merge). Otherwise, and on any uncertainty, it is blocked (exit 2). All other
# destructive blocks are unchanged.
#
# The hook reads a JSON payload on stdin ({"tool_input":{"command":"..."}}) and
# exits 0 (allow) or 2 (block). It inspects the git repo in its CWD, so each
# scenario runs the hook from inside a purpose-built scratch repo.
#
# Prereq: jq (the hook hard-requires it) + git. SKIPS gracefully otherwise.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"; _flow_assert_pass "SKIP: jq not installed"; return 0
fi
if ! command -v git >/dev/null 2>&1; then
  _flow_test_begin "git prerequisite"; _flow_assert_pass "SKIP: git not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-destructive.sh"

BD_CLEANUP=()
_bd_cleanup() { local p; for p in "${BD_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _bd_cleanup EXIT

# Run the hook from inside <repo> with <command>; returns the hook's exit code.
_run_hook() {
  local repo="$1" cmd="$2" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  ( cd "$repo" && printf '{"tool_input":{"command":%s}}' "$json" | bash "$HOOK" ) >/dev/null 2>&1
}

# Fresh repo on `main` with one commit; prints its path.
_new_repo() {
  local d; d=$(mktemp -d -t flow-bd.XXXXXX); BD_CLEANUP+=("$d")
  ( cd "$d" \
    && git init -q -b main \
    && git config user.email t@t.test && git config user.name tester \
    && echo base > base.txt && git add base.txt && git commit -qm m0 ) >/dev/null 2>&1
  printf '%s' "$d"
}

# --- regular (no-ff) merge → branch tip is an ancestor of main → allow
_flow_test_begin "force-delete allowed for a normally-merged branch"
R=$(_new_repo)
( cd "$R" && git checkout -qb feat && echo x > f.txt && git add f.txt && git commit -qm c1 \
  && git checkout -q main && git merge -q --no-ff feat -m "merge feat" ) >/dev/null 2>&1
_run_hook "$R" "git branch -D feat"; assert_exit 0 "$?" "merged branch (--no-ff) → allowed"

# --- squash merge → branch NOT an ancestor, but combined diff is in main → allow
_flow_test_begin "force-delete allowed for a squash-merged branch"
R=$(_new_repo)
( cd "$R" && git checkout -qb feat && echo x > f.txt && git add f.txt && git commit -qm c1 \
  && echo y >> f.txt && git add f.txt && git commit -qm c2 \
  && git checkout -q main && git merge -q --squash feat && git commit -qm "squash feat" ) >/dev/null 2>&1
_run_hook "$R" "git branch -D feat"; assert_exit 0 "$?" "squash-merged branch → allowed (the core fix)"

# --- unmerged branch → block
_flow_test_begin "force-delete blocked for an unmerged branch"
R=$(_new_repo)
( cd "$R" && git checkout -qb feat && echo x > f.txt && git add f.txt && git commit -qm c1 \
  && git checkout -q main ) >/dev/null 2>&1
_run_hook "$R" "git branch -D feat"; assert_exit 2 "$?" "unmerged work → blocked"

# --- default branch is never force-deletable
_flow_test_begin "force-delete blocked for the default branch itself"
R=$(_new_repo)
_run_hook "$R" "git branch -D main"; assert_exit 2 "$?" "deleting main → blocked"

# --- multi-target: one merged, one unmerged → block (all must be merged)
_flow_test_begin "multi-branch force-delete blocked when any target is unmerged"
R=$(_new_repo)
( cd "$R" && git checkout -qb done && echo a > a.txt && git add a.txt && git commit -qm ca \
  && git checkout -q main && git merge -q --no-ff done -m "merge done" \
  && git checkout -qb wip && echo b > b.txt && git add b.txt && git commit -qm cb \
  && git checkout -q main ) >/dev/null 2>&1
_run_hook "$R" "git branch -D done wip"; assert_exit 2 "$?" "mixed merged/unmerged → blocked"

# --- multi-target: all merged → allow
_flow_test_begin "multi-branch force-delete allowed when all targets merged"
R=$(_new_repo)
( cd "$R" && git checkout -qb d1 && echo a > a.txt && git add a.txt && git commit -qm ca \
  && git checkout -q main && git merge -q --no-ff d1 -m "merge d1" \
  && git checkout -qb d2 && echo b > b.txt && git add b.txt && git commit -qm cb \
  && git checkout -q main && git merge -q --no-ff d2 -m "merge d2" ) >/dev/null 2>&1
_run_hook "$R" "git branch -D d1 d2"; assert_exit 0 "$?" "all merged → allowed"

# --- non-existent branch → fail-safe block (cannot verify)
_flow_test_begin "force-delete blocked for an unresolvable branch (fail-safe)"
R=$(_new_repo)
_run_hook "$R" "git branch -D ghost"; assert_exit 2 "$?" "nonexistent branch → blocked"

# --- not a git repo → cannot verify merge status → fail-safe block
_flow_test_begin "force-delete blocked outside a git repo (fail-safe)"
NR=$(mktemp -d -t flow-bd-nr.XXXXXX); BD_CLEANUP+=("$NR")
_run_hook "$NR" "git branch -D feat"; assert_exit 2 "$?" "no git repo → blocked"

# --- safe-delete (-d) is not our trigger and passes through
_flow_test_begin "safe-delete (-d) passes through untouched"
R=$(_new_repo)
( cd "$R" && git checkout -qb feat && git checkout -q main ) >/dev/null 2>&1
_run_hook "$R" "git branch -d feat"; assert_exit 0 "$?" "lowercase -d is allowed (git itself guards it)"

# --- other destructive blocks remain intact
_flow_test_begin "other destructive operations remain blocked"
R=$(_new_repo)
_run_hook "$R" "git reset --hard HEAD~1"; assert_exit 2 "$?" "git reset --hard still blocked"
_run_hook "$R" "git clean -fd"; assert_exit 2 "$?" "git clean -f still blocked"
_run_hook "$R" "rm -rf /some/important/path"; assert_exit 2 "$?" "rm -rf still blocked"
_run_hook "$R" "git restore ."; assert_exit 2 "$?" "git restore . still blocked"

# --- force-delete EQUIVALENT forms are also merge-aware (not bypassed)
_flow_test_begin "force-delete equivalents (--delete --force, -Df, -fD) are merge-aware"
R=$(_new_repo)
( cd "$R" && git checkout -qb gone && echo a > a.txt && git add a.txt && git commit -qm ca \
  && git checkout -q main && git merge -q --no-ff gone -m "merge gone" \
  && git checkout -qb live && echo b > b.txt && git add b.txt && git commit -qm cb \
  && git checkout -q main ) >/dev/null 2>&1
# merged target via each equivalent form → allowed
_run_hook "$R" "git branch --delete --force gone"; assert_exit 0 "$?" "--delete --force on merged → allowed"
_run_hook "$R" "git branch -Df gone"; assert_exit 0 "$?" "-Df on merged → allowed"
_run_hook "$R" "git branch -fD gone"; assert_exit 0 "$?" "-fD on merged → allowed"
# unmerged target via each equivalent form → blocked (the bypass is closed)
_run_hook "$R" "git branch --delete --force live"; assert_exit 2 "$?" "--delete --force on unmerged → blocked"
_run_hook "$R" "git branch -Df live"; assert_exit 2 "$?" "-Df on unmerged → blocked"
_run_hook "$R" "git branch -d --force live"; assert_exit 2 "$?" "-d --force on unmerged → blocked"

# --- merged into origin/<default> while local default is behind → allowed
_flow_test_begin "force-delete allowed when merged into origin/<default> (local behind)"
R=$(_new_repo)
( cd "$R" \
  && git checkout -qb feat && echo x > f.txt && git add f.txt && git commit -qm c1 \
  && git checkout -q main && git merge -q --squash feat && git commit -qm "squash feat" \
  && git update-ref refs/remotes/origin/main main \
  && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
  && git reset -q --hard HEAD~1 ) >/dev/null 2>&1   # local main now BEHIND origin/main
_run_hook "$R" "git branch -D feat"; assert_exit 0 "$?" "merged on origin/main but not local → allowed"

# --- compound command with a force-delete falls through to BLOCK
_flow_test_begin "force-delete chained into a compound command is blocked"
R=$(_new_repo)
( cd "$R" && git checkout -qb m1 && echo a > a.txt && git add a.txt && git commit -qm ca \
  && git checkout -q main && git merge -q --no-ff m1 -m "merge m1" ) >/dev/null 2>&1
# m1 is merged, but the chained tail must NOT be greenlit → block
_run_hook "$R" "git branch -D m1 && echo pwned"; assert_exit 2 "$?" "compound force-delete → blocked (no false allow)"

# --- ordinary commands pass
_flow_test_begin "non-destructive commands pass"
R=$(_new_repo)
_run_hook "$R" "git status"; assert_exit 0 "$?" "git status allowed"
_run_hook "$R" "rm -rf node_modules"; assert_exit 0 "$?" "rm -rf in safe dir allowed"
_run_hook "$R" "git branch -f other main"; assert_exit 0 "$?" "git branch -f (force-create/move, no delete) allowed"
