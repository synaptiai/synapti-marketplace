#!/usr/bin/env bash
# detect-local-merge.sh (issue #135 AC #4): a local merge to the default
# branch should be able to suggest/trigger a documentation refresh,
# regardless of which plugin or human ran it — and this must work with the
# flow plugin entirely absent from the environment.

_dossier_test_begin "local-merge-hook"

HOOK="plugins/dossier/hooks/scripts/detect-local-merge.sh"

if [ ! -x "$HOOK" ]; then
  _dossier_assert_fail "$HOOK missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# --- Fixture: an isolated copy of ONLY the dossier plugin, no flow present --
# This is the test that actually proves self-containment, not just asserts it
# in prose: PLUGIN_ROOT points at a directory tree where plugins/flow simply
# does not exist on disk, and the hook must still behave correctly.
FLOWLESS_ROOT=$(mktemp -d "$RUN_TMPDIR/flowless-plugins.XXXXXX")
cp -R plugins/dossier "$FLOWLESS_ROOT/dossier"
if [ -d "$FLOWLESS_ROOT/flow" ]; then
  _dossier_assert_fail "fixture setup bug: flow plugin ended up in the flowless fixture"
else
  _dossier_assert_pass "fixture setup: the flow plugin does not exist under the flowless plugin root"
fi
PLUGIN_ROOT="$FLOWLESS_ROOT/dossier"

# A git repo to run the hook against — default branch checked out, HEAD has
# no second parent yet.
REPO=$(mktemp -d "$RUN_TMPDIR/local-merge-repo.XXXXXX")
(
  cd "$REPO" || exit 1
  git init -q -b main
  git config user.email test@example.com
  git config user.name "Test"
  echo "seed" > seed.txt
  git add -A
  git commit -q -m "seed"
) >/dev/null 2>&1

HOOK_ABS="$(pwd)/$HOOK"
run_hook() {
  # $1 = bash command the (fake) Bash tool call carried, $2 = onLocalMerge mode
  local cmd="$1" mode="$2"
  ( cd "$REPO" && mkdir -p .claude && jq -n --arg m "$mode" '{dossier:{local:{onLocalMerge:$m}}}' > .claude/settings.dossier.json
    printf '{"tool_input":{"command":"%s"}}' "$cmd" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$HOOK_ABS" 2>&1
    RC=$?
    rm -rf .claude
    echo "RC=$RC" )
}

# --- git merge, mode=suggest, flow plugin absent ----------------------------
# The hook is command-string-driven for git-merge/gh-pr-merge (it trusts the
# PostToolUse payload's command text), so no real merge needs to have run —
# only gh pr merge and git pull cases below need real repository state.
OUT=$(run_hook "git merge feature-branch" "suggest")
assert_contains "dossier:refresh" "$OUT" "git merge on the default branch, mode=suggest: mentions /dossier:refresh, with the flow plugin entirely absent"
assert_contains "RC=0" "$OUT" "the hook exits 0 (advisory, never blocks)"

JSON_LINE=$(printf '%s\n' "$OUT" | grep '^{')
HOOK_EVENT=$(printf '%s' "$JSON_LINE" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
assert_equal "PostToolUse" "$HOOK_EVENT" "the hook emits well-formed JSON with hookEventName=PostToolUse"
CONTEXT_TEXT=$(printf '%s' "$JSON_LINE" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
assert_contains "/dossier:refresh" "$CONTEXT_TEXT" "additionalContext (the field Claude actually reads) names the refresh command"

# --- mode=off: no output at all ---------------------------------------------
OUT_OFF=$(run_hook "git merge feature-branch" "off")
assert_equal "RC=0" "$(printf '%s' "$OUT_OFF" | tail -1)" "mode=off exits 0"
assert_not_contains "dossier:refresh" "$OUT_OFF" "mode=off produces no suggestion at all"

# --- gh pr merge ------------------------------------------------------------
OUT_GH=$(run_hook "gh pr merge 42 --squash" "suggest")
assert_contains "dossier:refresh" "$OUT_GH" "gh pr merge triggers the same suggestion"

# --- A non-merge command: no output, regardless of mode ---------------------
OUT_STATUS=$(run_hook "git status" "suggest")
assert_not_contains "dossier:refresh" "$OUT_STATUS" "a plain git status never triggers the hook"

OUT_LOG=$(run_hook "git log --oneline -- 'git merge in a comment'" "suggest")
assert_not_contains "dossier:refresh" "$OUT_LOG" "a command that merely mentions 'git merge' as an argument (not a command boundary) does not trigger"

# --- git pull: only counts when it actually produced a merge commit --------
# A fast-forward pull (HEAD has one parent) must NOT trigger — routine branch
# catch-up, not "new work landed via a merge".
OUT_PULL_FF=$(run_hook "git pull" "suggest")
assert_not_contains "dossier:refresh" "$OUT_PULL_FF" "git pull with no merge commit on HEAD (fast-forward case) does not trigger"

# A real merge commit (HEAD has two parents) must trigger.
(
  cd "$REPO" || exit 1
  git checkout -q -b other-line main
  echo "other" > other.txt
  git add -A
  git commit -q -m "other line of work"
  git checkout -q main
  echo "main-side" > main-side.txt
  git add -A
  git commit -q -m "main-side work"
  git merge -q --no-ff other-line -m "merge other-line"
) >/dev/null 2>&1
OUT_PULL_MERGE=$(run_hook "git pull" "suggest")
assert_contains "dossier:refresh" "$OUT_PULL_MERGE" "git pull that resulted in a real merge commit (HEAD has two parents) triggers"

_dossier_test_summary
