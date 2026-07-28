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
FLOWLESS_ROOT=$(_dossier_safe_mktemp_dir "flowless-plugins")
cp -R plugins/dossier "$FLOWLESS_ROOT/dossier"
if [ -d "$FLOWLESS_ROOT/flow" ]; then
  _dossier_assert_fail "fixture setup bug: flow plugin ended up in the flowless fixture"
else
  _dossier_assert_pass "fixture setup: the flow plugin does not exist under the flowless plugin root"
fi
PLUGIN_ROOT="$FLOWLESS_ROOT/dossier"

# A git repo to run the hook against — default branch checked out, HEAD has
# no second parent yet.
REPO=$(_dossier_safe_mktemp_dir "local-merge-repo")
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
  # $1 = bash command the (fake) Bash tool call carried, $2 = onLocalMerge mode,
  # $3 = optional DOSSIER_MERGE_FRESHNESS_SECONDS override (test-only escape
  # hatch — lets a test simulate "time has passed since the merge" without
  # actually sleeping out the hook's real 15s freshness window).
  #
  # Every path below is $REPO-absolute, never a bare relative ".claude" — a
  # `cd "$REPO"` that silently fails for any reason must not turn `rm -rf
  # .claude` into a deletion of the real caller's .claude/ directory. This is
  # the exact incident that happened during development (see
  # _dossier_safe_mktemp_dir's comment); this function closes the risk class
  # even though the mktemp-empty root cause is now fixed there too.
  local cmd="$1" mode="$2" freshness="${3:-}"
  ( mkdir -p "$REPO/.claude"
    jq -n --arg m "$mode" '{dossier:{local:{onLocalMerge:$m}}}' > "$REPO/.claude/settings.dossier.json"
    ( cd "$REPO" && printf '{"tool_input":{"command":"%s"}}' "$cmd" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_MERGE_FRESHNESS_SECONDS="$freshness" "$HOOK_ABS" 2>&1 )
    RC=$?
    rm -rf "$REPO/.claude"
    echo "RC=$RC" )
}

# --- git merge, command string only, no real merge behind it ---------------
# The hook must NOT fire on command-string match alone: it now requires HEAD
# to actually be a fresh merge commit. At this point in the fixture nothing
# has been merged at all (HEAD is still the lone seed commit) — this is the
# direct regression test for the bug where any merge-shaped command string
# fired regardless of whether a merge had actually happened.
OUT_NOOP_MERGE=$(run_hook "git merge feature-branch" "suggest")
assert_not_contains "dossier:refresh" "$OUT_NOOP_MERGE" "git merge command string alone, with no real merge commit on HEAD, does not trigger"
assert_contains "RC=0" "$OUT_NOOP_MERGE" "the hook exits 0 even when it declines to fire (advisory, never blocks)"

# --- A real merge, mode=suggest, flow plugin absent -------------------------
(
  cd "$REPO" || exit 1
  git checkout -q -b feature-branch main
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "feature work"
  git checkout -q main
  git merge -q --no-ff feature-branch -m "merge feature-branch"
) >/dev/null 2>&1

OUT=$(run_hook "git merge feature-branch" "suggest")
assert_contains "dossier:refresh" "$OUT" "a real git merge on the default branch, mode=suggest: mentions /dossier:refresh, with the flow plugin entirely absent"
assert_contains "RC=0" "$OUT" "the hook exits 0 (advisory, never blocks)"

JSON_LINE=$(printf '%s\n' "$OUT" | grep '^{')
HOOK_EVENT=$(printf '%s' "$JSON_LINE" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
assert_equal "PostToolUse" "$HOOK_EVENT" "the hook emits well-formed JSON with hookEventName=PostToolUse"
CONTEXT_TEXT=$(printf '%s' "$JSON_LINE" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
assert_contains "/dossier:refresh" "$CONTEXT_TEXT" "additionalContext (the field Claude actually reads) names the refresh command"

# --- mode=off: no output at all, same real-merge state ----------------------
OUT_OFF=$(run_hook "git merge feature-branch" "off")
assert_equal "RC=0" "$(printf '%s' "$OUT_OFF" | tail -1)" "mode=off exits 0"
assert_not_contains "dossier:refresh" "$OUT_OFF" "mode=off produces no suggestion at all"

# --- gh pr merge: still command-string-driven, unaffected by the freshness
# check (a PostToolUse hook cannot verify a gh pr merge's success without a
# network round-trip; this is a documented, accepted false-positive class) --
OUT_GH=$(run_hook "gh pr merge 42 --squash" "suggest")
assert_contains "dossier:refresh" "$OUT_GH" "gh pr merge triggers the same suggestion"

# --- A non-merge command: no output, regardless of mode ---------------------
OUT_STATUS=$(run_hook "git status" "suggest")
assert_not_contains "dossier:refresh" "$OUT_STATUS" "a plain git status never triggers the hook"

OUT_LOG=$(run_hook "git log --oneline -- 'git merge in a comment'" "suggest")
assert_not_contains "dossier:refresh" "$OUT_LOG" "a command that merely mentions 'git merge' as an argument (not a command boundary) does not trigger"

# --- git merge --abort: HEAD never moves, so no output ----------------------
# A conflicting merge attempt that gets aborted must not read as "a merge
# landed" — nothing landed. HEAD's last real move stays the earlier
# feature-branch merge, which is no longer fresh enough to pass the
# freshness check even before the abort (a real regression test for this
# would need to freeze the clock; the abort itself proves the doesn't-move
# side of the fix independently: HEAD is provably unchanged by --abort).
(
  cd "$REPO" || exit 1
  git checkout -q -b conflict-branch main
  echo "conflict" > seed.txt
  git add -A
  git commit -q -m "conflicting change"
  git checkout -q main
  echo "other-conflict" > seed.txt
  git add -A
  git commit -q -m "other conflicting change"
) >/dev/null 2>&1
HEAD_BEFORE_ABORT=$(git -C "$REPO" rev-parse HEAD)
( cd "$REPO" && git merge -q conflict-branch >/dev/null 2>&1; git merge --abort >/dev/null 2>&1 )
HEAD_AFTER_ABORT=$(git -C "$REPO" rev-parse HEAD)
assert_equal "$HEAD_BEFORE_ABORT" "$HEAD_AFTER_ABORT" "sanity: git merge --abort leaves HEAD exactly where it was"
OUT_ABORT=$(run_hook "git merge conflict-branch" "suggest")
assert_not_contains "dossier:refresh" "$OUT_ABORT" "git merge --abort never triggers — HEAD was never a fresh merge commit"

# --- git pull: only counts when it actually produced a fresh merge commit --
# A fast-forward pull (HEAD has one parent) must NOT trigger — routine branch
# catch-up, not "new work landed via a merge".
OUT_PULL_FF=$(run_hook "git pull" "suggest")
assert_not_contains "dossier:refresh" "$OUT_PULL_FF" "git pull with no merge commit on HEAD (fast-forward case) does not trigger"

# A fresh real merge commit (HEAD has two parents, just landed) must trigger.
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
assert_contains "dossier:refresh" "$OUT_PULL_MERGE" "git pull that resulted in a fresh real merge commit (HEAD has two parents, just landed) triggers"

# --- Regression test for the actual bug: a SUBSEQUENT no-op pull must NOT
# re-fire off the same old merge commit still sitting at HEAD. This is the
# exact scenario that was broken before the freshness check: once any real
# merge has ever landed, HEAD stays a two-parent commit until the next
# ordinary commit, so a check that only asks "does HEAD have two parents"
# re-fires on every later pull forever, including a fully no-op one.
#
# A real no-op pull (nothing new to fetch) writes no new reflog entry, so
# HEAD's last-moved time never advances — this test cannot wait out the
# hook's real 15s freshness window without slowing the whole suite down for
# one assertion, so it uses the freshness override to deterministically
# simulate "the merge above is no longer fresh" instead. -1 guarantees
# elapsed-time (always >= 0) exceeds the window regardless of how fast this
# runs.
OUT_PULL_REFIRE=$(run_hook "git pull" "suggest" "-1")
assert_not_contains "dossier:refresh" "$OUT_PULL_REFIRE" "a subsequent git pull, with no new git activity since the last real merge, does not re-fire off the same stale merge commit"

_dossier_test_summary
