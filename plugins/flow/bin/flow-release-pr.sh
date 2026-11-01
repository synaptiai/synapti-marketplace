#!/usr/bin/env bash
# [flow] Open the release branch for /flow:release's first run: create it
# from the commit checked out, bump the version files with
# flow-release-versions.sh, commit only the bumped files and the changelog
# file, and push the branch. Nothing is pushed to the default branch.
#
# It stops before creating anything when the release branch starts with + or
# -, already exists in this clone, the version script's plan fails or names
# no file to bump (its output is printed), or a version file it would bump
# has uncommitted changes of its own. When the bump, the commit or the push fails, it puts the repository back
# as it found it: the version files restored, the branch or commit it started
# on checked out again, the release branch deleted, and the changelog edit and
# anything staged before kept as they were. PR_CLEANUP says what it did or
# could not undo. With tiers.push set to confirm it stops after the commit
# (PR_STATE=committed) and names the push to run as its own command.
#
# The logic lives here rather than in the command file's fence because flow's
# own force-push guard refuses a command that holds both a push and a
# substitution, and its destructive-command guard refuses a branch deletion
# inside a compound command: as a fence, this block could never run.
#
# Input, from the environment (as /flow:release Phase 4 sets it):
#   RELEASE_BRANCH, DEFAULT_BRANCH, VERSION   required
#   PLUGIN, MARKET_VERSION                    a marketplace release (both empty otherwise)
#   TAG_PREFIX                                default v
#   CHANGELOG_FILE                            the changelog file edited (empty when none)
# Output: PR_STATE=blocked|committed|pushed, PR_TITLE, PR_ERROR, PR_CLEANUP,
# PR_WARN, PR_NEXT lines on stdout, and the version script's own lines.
# Exit 0 when the branch is committed or pushed, 1 when it stopped.
unset CDPATH
_self="$0"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$(dirname "$_self")/$_link" ;;
  esac
  _hops=$((_hops + 1))
done
_dir=$(cd "$(dirname "$_self")" && pwd -P) || { printf '%s\n' "PR_STATE=blocked" "PR_ERROR=\"cannot find the flow bin directory\""; exit 1; }
if [ -z "${RELEASE_BRANCH:-}" ] || [ -z "${DEFAULT_BRANCH:-}" ] || [ -z "${VERSION:-}" ]; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"set RELEASE_BRANCH, DEFAULT_BRANCH and VERSION from Phase 2\""
  exit 1
fi
# git push reads a first + as a forced push and a first - as an option, and
# git check-ref-format --branch accepts a name that starts with +.
case "$RELEASE_BRANCH" in
  [+-]*)
    printf '%s\n' "PR_STATE=blocked"
    printf '%s\n' "PR_ERROR=\"the release branch $RELEASE_BRANCH starts with + or -, which git push reads as a forced push or an option; change conventions.branchPatterns.release\""
    exit 1 ;;
esac
if [ -n "${PLUGIN:-}" ] && [ -n "${MARKET_VERSION:-}" ]; then
  PR_TITLE="chore(release): $PLUGIN $VERSION, marketplace $MARKET_VERSION"
elif [ -n "${PLUGIN:-}" ]; then
  PR_TITLE="chore(release): $PLUGIN $VERSION"
else
  PR_TITLE="chore(release): ${TAG_PREFIX:-v}$VERSION"
fi
VERSIONS="$_dir/flow-release-versions.sh"
if [ ! -x "$VERSIONS" ]; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"flow-release-versions.sh missing or non-executable at $VERSIONS\""
  exit 1
fi
if git rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"the local branch $RELEASE_BRANCH is left from an earlier run; push it and open its pull request (git push -u origin $RELEASE_BRANCH, then gh pr create --base $DEFAULT_BRANCH --head $RELEASE_BRANCH), or delete it (git branch -D $RELEASE_BRANCH), then run /flow:release again\""
  exit 1
fi
# The files the bump writes, from a plan with the same arguments. None may
# hold a change of its own: the bump commit would carry it, and a failure
# below restores these files from the last commit.
# A plan that fails, or names no file to bump, stops the run here: with no
# file named, none could be checked for changes of its own.
PLAN_RC=0
if [ -n "${PLUGIN:-}" ] && [ -n "${MARKET_VERSION:-}" ]; then
  PLAN_OUT=$("$VERSIONS" --plan --to "$VERSION" --plugin "$PLUGIN" --market-to "$MARKET_VERSION") || PLAN_RC=$?
elif [ -n "${PLUGIN:-}" ]; then
  PLAN_OUT=$("$VERSIONS" --plan --to "$VERSION" --plugin "$PLUGIN") || PLAN_RC=$?
else
  PLAN_OUT=$("$VERSIONS" --plan --to "$VERSION") || PLAN_RC=$?
fi
# The script names only paths without spaces or quotes, one per line.
VERSION_PATHS=$(printf '%s\n' "$PLAN_OUT" | sed -n 's/^VERSION_FILE=bump path=\([^ ]*\) .*/\1/p' | sort -u)
if [ "$PLAN_RC" -ne 0 ] || [ -z "$VERSION_PATHS" ]; then
  [ -n "$PLAN_OUT" ] && printf '%s\n' "$PLAN_OUT"
  printf '%s\n' "PR_STATE=blocked"
  if [ "$PLAN_RC" -ne 0 ]; then
    printf '%s\n' "PR_ERROR=\"the version files could not be planned: flow-release-versions.sh --plan exited $PLAN_RC; see its output above\""
  else
    printf '%s\n' "PR_ERROR=\"the version files could not be planned: flow-release-versions.sh --plan names no file to bump; see its output above\""
  fi
  exit 1
fi
DIRTY=""
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  [ -z "$(git status --porcelain -- "$_p")" ] || DIRTY="$DIRTY $_p"
done <<EOF
$VERSION_PATHS
EOF
if [ -n "$DIRTY" ]; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"these version files have uncommitted changes of their own:$DIRTY; commit or stash them, then run /flow:release again\""
  exit 1
fi
# What was checked out, to return to on a failure: a branch, or the commit
# of a detached HEAD.
START_BRANCH=$(git symbolic-ref -q --short HEAD)
START_COMMIT=$(git rev-parse HEAD)
if [ -n "$START_BRANCH" ]; then
  START_NAME="$START_BRANCH"
  START_SWITCH="git switch $START_BRANCH"
else
  START_NAME="the detached commit $START_COMMIT"
  START_SWITCH="git switch --detach $START_COMMIT"
fi
# The changelog's index entry before this block stages it: mode and blob,
# empty when git does not track the file. A failure puts it back, so a
# changelog the user had staged stays staged as they staged it.
CL_MODE=""
CL_BLOB=""
if [ -n "${CHANGELOG_FILE:-}" ]; then
  read -r CL_MODE CL_BLOB _cl_rest <<EOF
$(git ls-files -s -- "$CHANGELOG_FILE" | head -n 1)
EOF
fi
# _flow_undo: put the repository back as this block found it, and print
# PR_CLEANUP with what it did or could not do. The version files go back to
# the last commit (they were clean before the bump); the changelog edit and
# anything staged before this block stay as they were.
COMMITTED=0
_flow_undo() {
  _left=""
  if [ "$COMMITTED" = 1 ] && ! git reset -q --soft HEAD~1; then
    _left="$_left; the bump commit is still on $RELEASE_BRANCH"
  fi
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    git reset -q -- "$_p" >/dev/null 2>&1
    git checkout -q -- "$_p" || _left="$_left; $_p still holds the new version"
  done <<EOF
$VERSION_PATHS
EOF
  if [ -n "${CHANGELOG_FILE:-}" ]; then
    if [ -n "$CL_BLOB" ]; then
      git update-index --cacheinfo "$CL_MODE,$CL_BLOB,$CHANGELOG_FILE" \
        || _left="$_left; the staged $CHANGELOG_FILE is the release's version, not yours"
    else
      git reset -q -- "$CHANGELOG_FILE" >/dev/null 2>&1
    fi
  fi
  _back=0
  if [ -n "$START_BRANCH" ]; then
    git switch -q "$START_BRANCH" && _back=1
  else
    git switch -q --detach "$START_COMMIT" && _back=1
  fi
  if [ "$_back" = 1 ]; then
    git branch -q -D "$RELEASE_BRANCH" || _left="$_left; the local branch $RELEASE_BRANCH is still there (git branch -D $RELEASE_BRANCH)"
  else
    _left="$_left; still on $RELEASE_BRANCH ($START_SWITCH, then git branch -D $RELEASE_BRANCH)"
  fi
  if [ -z "$_left" ]; then
    printf '%s\n' "PR_CLEANUP=\"the version files are restored, $START_NAME is checked out and the local $RELEASE_BRANCH is deleted; the changelog edit and anything staged before are kept\""
  else
    printf '%s\n' "PR_CLEANUP=\"cleanup incomplete$_left\""
  fi
}
if ! git switch -q -c "$RELEASE_BRANCH"; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"cannot create the branch $RELEASE_BRANCH\""
  exit 1
fi
if [ -n "${PLUGIN:-}" ] && [ -n "${MARKET_VERSION:-}" ]; then
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION" --plugin "$PLUGIN" --market-to "$MARKET_VERSION"); BUMP_RC=$?
elif [ -n "${PLUGIN:-}" ]; then
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION" --plugin "$PLUGIN"); BUMP_RC=$?
else
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION"); BUMP_RC=$?
fi
printf '%s\n' "$BUMP_OUT"
if [ "$BUMP_RC" -ne 0 ] || ! printf '%s\n' "$BUMP_OUT" | grep -qx 'VERSIONS_STATE=written'; then
  # The script writes every file or none, and names any it could not put
  # back on a WRITTEN_PATH line; the undo restores them all either way.
  _flow_undo
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"the version files were not bumped; see VERSIONS_STATE\""
  exit 1
fi
COMMIT_FILES=$(printf '%s\n' "$BUMP_OUT" | sed -n 's/^VERSION_FILE=bump path=\([^ ]*\) .*/\1/p' | sort -u)
if [ -n "${CHANGELOG_FILE:-}" ]; then
  # Compared with the last commit, not the index: a changelog edit the user
  # already staged is a change too.
  if git diff --quiet HEAD -- "$CHANGELOG_FILE" 2>/dev/null && ! git ls-files --others --exclude-standard -- "$CHANGELOG_FILE" | grep -q .; then
    printf '%s\n' "PR_WARN=\"$CHANGELOG_FILE has no change; the release pull request carries no changelog entry\""
  else
    COMMIT_FILES=$(printf '%s\n%s\n' "$COMMIT_FILES" "$CHANGELOG_FILE")
  fi
fi
# git add first: git commit's paths match only files git already knows, so a
# changelog file written for the first time would fail the commit. Paths
# given to git commit commit those files alone, whatever else is staged.
set --
ADD_OK=1
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  git add -- "$_p" || ADD_OK=0
  set -- "$@" "$_p"
done <<EOF
$COMMIT_FILES
EOF
if [ "$ADD_OK" = 1 ] && git commit -q -m "$PR_TITLE" -- "$@"; then
  COMMITTED=1
else
  _flow_undo
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"git add or git commit failed on $RELEASE_BRANCH, so nothing was committed; see the git output above\""
  exit 1
fi
# tiers.push confirm: the push has to be its own command, so the tier hook
# can ask before it runs. flow's git wrapper refuses a confirm push the hook
# did not ask about, so pushing from here would only fail.
PUSH_TIER=$("$_dir/cascade-resolve.sh" --default journal '.tiers.push' 2>/dev/null) || PUSH_TIER=journal
if [ "$PUSH_TIER" = confirm ]; then
  printf '%s\n' "PR_STATE=committed"
  printf '%s\n' "PR_TITLE=\"$PR_TITLE\""
  printf '%s\n' "PR_NEXT=\"tiers.push is confirm: push the branch as its own command, git push -u origin $RELEASE_BRANCH, then open the pull request\""
  exit 0
fi
# A full refspec: the branch name is never read as anything but a branch.
if ! git push -q -u origin "refs/heads/$RELEASE_BRANCH:refs/heads/$RELEASE_BRANCH"; then
  _flow_undo
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"git push of $RELEASE_BRANCH failed, so the bump commit was undone; check that origin is reachable, then run /flow:release again\""
  exit 1
fi
printf '%s\n' "PR_STATE=pushed"
printf '%s\n' "PR_TITLE=\"$PR_TITLE\""
