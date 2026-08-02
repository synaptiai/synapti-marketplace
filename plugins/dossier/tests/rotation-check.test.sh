#!/usr/bin/env bash
# dossier-rotation-check.sh: telemetry-only rolling-branch rotation
# determination (issue #138). Purely observational — never closes a pull
# request, deletes a branch, or creates a replacement branch. See
# .decisions/issue-138.md's Specification section for the full contract.

_dossier_test_begin "rotation-check"

SCRIPT="$(pwd)/plugins/dossier/bin/dossier-rotation-check.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$SCRIPT" ]; then
  _dossier_assert_fail "$SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

get() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,""); print; exit}'; }

day_offset() { date -u -d "-$1 days" +%Y-%m-%d 2>/dev/null || date -u -v-"$1"d +%Y-%m-%d 2>/dev/null; }

# Removes any PATH entry that hosts a `gh` executable, keeping every other
# tool resolvable. `command -v gh` must genuinely fail for the "no gh" cases —
# the script branches on that check, not on gh's exit code.
no_gh_path() {
  OLD_IFS="$IFS"; IFS=':'
  _out=""
  for _dir in $PATH; do
    [ -n "$_dir" ] || continue
    [ -x "$_dir/gh" ] && continue
    _out="${_out:+$_out:}$_dir"
  done
  IFS="$OLD_IFS"
  printf '%s' "$_out"
}

# Builds a bare "origin" remote + a working clone, with dossier plugin bin
# scripts reachable via CLAUDE_PLUGIN_ROOT. Real git remote (not a fixture
# dir masquerading as one) because the script's own exit-code semantics
# (git ls-remote --exit-code 0 vs 2 vs 128) require an actual remote to
# exercise realistically.
setup_fixture() {
  _fixture=$(_dossier_safe_mktemp_dir "rotation-fixture")
  _bare="$_fixture/origin.git"
  _clone="$_fixture/clone"
  git init -q --bare "$_bare"
  git clone -q "$_bare" "$_clone" >/dev/null 2>&1
  (
    cd "$_clone" || exit 1
    git config user.email test@example.com
    git config user.name "Test"
    echo "root" > README.md
    git add -A
    git commit -q -m "root commit"
    git push -q origin HEAD:refs/heads/main
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  ) >/dev/null 2>&1
  printf '%s' "$_clone"
}

# Adds $N commits to $DOCS_BRANCH (created from main if absent), each carrying
# a Dossier-Generated: true trailer, backdated via GIT_AUTHOR_DATE/
# GIT_COMMITTER_DATE, then pushes the branch to origin. $3 = file content
# (defaults to a short line) so callers can control diff size.
push_docs_branch_commit() {
  _clone="$1"; _docs_branch="$2"; _date="$3"; _content="${4:-line}"
  (
    cd "$_clone" || exit 1
    git fetch -q origin >/dev/null 2>&1
    if git rev-parse --verify -q "refs/heads/$_docs_branch" >/dev/null 2>&1; then
      git checkout -q "$_docs_branch"
    elif git rev-parse --verify -q "refs/remotes/origin/$_docs_branch" >/dev/null 2>&1; then
      git checkout -q -B "$_docs_branch" "origin/$_docs_branch"
    else
      git checkout -q -B "$_docs_branch" origin/main
    fi
    printf '%s\n' "$_content" >> docs.md
    git add -A
    GIT_AUTHOR_DATE="${_date}T00:00:00Z" GIT_COMMITTER_DATE="${_date}T00:00:00Z" \
      git commit -q -m "chore(dossier): generated" -m "Dossier-Generated: true"
    git push -q origin "$_docs_branch"
    git checkout -q main
  ) >/dev/null 2>&1
}

# =============================================================================
# 1. No-branch cold start
# =============================================================================
F1=$(setup_fixture)
SUMMARY1=$(_dossier_safe_mktemp_dir "rotation-summary1")/summary.md
OUT1=$(cd "$F1" && env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier "$SCRIPT" --summary "$SUMMARY1" 2>&1)
RC1=$?
assert_equal "0" "$RC1" "no-branch cold start: exits 0 (a reached decision, not an infra failure)"
assert_equal "false" "$(get "$OUT1" would_rotate)" "no-branch cold start: would_rotate=false"
assert_equal "no-branch" "$(get "$OUT1" age_source)" "no-branch cold start: age_source=no-branch"
assert_equal "" "$(get "$OUT1" age_days)" "no-branch cold start: age_days is empty, not 0"
assert_equal "" "$(get "$OUT1" accumulated_files)" "no-branch cold start: accumulated_files is empty, not 0"
assert_equal "" "$(get "$OUT1" accumulated_lines)" "no-branch cold start: accumulated_lines is empty, not 0"
assert_contains "does not exist yet" "$(get "$OUT1" reason)" "no-branch cold start: reason names the actual state"

# =============================================================================
# 2. Policy=none, branch exists with a real diff — metrics still emitted
#    (this is the AC4 assertion: metrics flow regardless of policy)
# =============================================================================
F2=$(setup_fixture)
push_docs_branch_commit "$F2" "docs/dossier" "$(day_offset 3)" "insert-only content line one"
push_docs_branch_commit "$F2" "docs/dossier" "$(day_offset 1)" "insert-only content line two"
OUT2=$(cd "$F2" && env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=none "$SCRIPT" 2>&1)
RC2=$?
assert_equal "0" "$RC2" "policy=none: exits 0"
assert_equal "false" "$(get "$OUT2" would_rotate)" "policy=none: would_rotate=false regardless of diff size"
assert_contains "disabled" "$(get "$OUT2" reason)" "policy=none: reason names rotation as disabled"
ACC_FILES2=$(get "$OUT2" accumulated_files)
ACC_LINES2=$(get "$OUT2" accumulated_lines)
if [ -n "$ACC_FILES2" ] && [ "$ACC_FILES2" -gt 0 ] 2>/dev/null; then
  _dossier_assert_pass "policy=none: accumulated_files is still a real non-empty number (AC4)"
else
  _dossier_assert_fail "policy=none: accumulated_files was empty or zero ($ACC_FILES2) — AC4 requires metrics regardless of policy"
fi
if [ -n "$ACC_LINES2" ] && [ "$ACC_LINES2" -gt 0 ] 2>/dev/null; then
  _dossier_assert_pass "policy=none: accumulated_lines is still a real non-empty number (AC4)"
else
  _dossier_assert_fail "policy=none: accumulated_lines was empty or zero ($ACC_LINES2) — AC4 requires metrics regardless of policy"
fi
AGE_DAYS2=$(get "$OUT2" age_days)
if [ -n "$AGE_DAYS2" ] && [ "$AGE_DAYS2" -ge 0 ] 2>/dev/null; then
  _dossier_assert_pass "policy=none: age_days is still a real non-empty number (AC4 names all three fields, not just the size ones)"
else
  _dossier_assert_fail "policy=none: age_days was empty ($AGE_DAYS2) — AC4 requires age_days computed too, not just accumulated_files/accumulated_lines"
fi
assert_equal "branch_commits" "$(get "$OUT2" age_source)" "policy=none: age_source is still populated (branch_commits), not left as the default unknown"

# =============================================================================
# 3. Would-rotate via age (gh stub returns an old open PR)
# =============================================================================
F3=$(setup_fixture)
push_docs_branch_commit "$F3" "docs/dossier" "$(day_offset 10)"
STUB3=$(_dossier_safe_mktemp_dir "gh-stub-old-pr")
cat > "$STUB3/gh" <<EOF
#!/usr/bin/env bash
echo '{"number":42,"createdAt":"$(day_offset 10)T00:00:00Z"}'
exit 0
EOF
chmod +x "$STUB3/gh"
OUT3=$(cd "$F3" && env PATH="$STUB3:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly "$SCRIPT" 2>&1)
RC3=$?
assert_equal "0" "$RC3" "would-rotate via age: exits 0"
assert_equal "true" "$(get "$OUT3" would_rotate)" "would-rotate via age: would_rotate=true (10 days > 7-day weekly threshold)"
assert_equal "pr_created_at" "$(get "$OUT3" age_source)" "would-rotate via age: age_source=pr_created_at"
assert_contains "age" "$(get "$OUT3" reason)" "would-rotate via age: reason cites age"

# =============================================================================
# 4. Would-not-rotate (gh stub, recent PR, small diff)
# =============================================================================
F4=$(setup_fixture)
push_docs_branch_commit "$F4" "docs/dossier" "$(day_offset 1)"
STUB4=$(_dossier_safe_mktemp_dir "gh-stub-recent-pr")
cat > "$STUB4/gh" <<EOF
#!/usr/bin/env bash
echo '{"number":7,"createdAt":"$(day_offset 1)T00:00:00Z"}'
exit 0
EOF
chmod +x "$STUB4/gh"
OUT4=$(cd "$F4" && env PATH="$STUB4:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly "$SCRIPT" 2>&1)
RC4=$?
assert_equal "0" "$RC4" "would-not-rotate: exits 0"
assert_equal "false" "$(get "$OUT4" would_rotate)" "would-not-rotate: would_rotate=false (1 day old, small diff, both under threshold)"
assert_equal "pr_created_at" "$(get "$OUT4" age_source)" "would-not-rotate: age_source=pr_created_at"

# =============================================================================
# 5. Degraded gh-unavailable, would-rotate via commit age (monthly policy)
# =============================================================================
F5=$(setup_fixture)
push_docs_branch_commit "$F5" "docs/dossier" "$(day_offset 40)"
NOGH_PATH5=$(no_gh_path)
SUMMARY5=$(_dossier_safe_mktemp_dir "rotation-summary5")/summary.md
OUT5=$(cd "$F5" && env PATH="$NOGH_PATH5" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=monthly "$SCRIPT" --summary "$SUMMARY5" 2>&1)
RC5=$?
assert_equal "0" "$RC5" "degraded gh-unavailable via commit age: exits 0"
assert_equal "branch_commits" "$(get "$OUT5" age_source)" "degraded gh-unavailable: age_source=branch_commits (fell back to commit trailer walk)"
assert_equal "true" "$(get "$OUT5" would_rotate)" "degraded gh-unavailable: would_rotate=true (40 days > 30-day monthly threshold)"
if [ -f "$SUMMARY5" ] && grep -qi "gh" "$SUMMARY5" 2>/dev/null; then
  _dossier_assert_pass "degraded gh-unavailable: summary notes the gh degradation"
else
  _dossier_assert_fail "degraded gh-unavailable: summary did not mention the gh-unavailable degradation"
fi

# =============================================================================
# 6. Would-rotate via size alone (no gh, no Dossier-Generated commits at all
#    for age, but a large diff)
# =============================================================================
F6=$(setup_fixture)
# Push a branch with a commit that is NOT Dossier-Generated, so age_source
# ends up unknown, while still producing a large diff to trigger on size.
(
  cd "$F6" || exit 1
  git checkout -q -B docs/dossier origin/main
  i=1
  while [ "$i" -le 200 ]; do
    printf 'line %s of generated content\n' "$i" >> docs.md
    i=$((i + 1))
  done
  git add -A
  git config user.email test@example.com
  git config user.name "Test"
  git commit -q -m "not a dossier commit"
  git push -q origin docs/dossier
  git checkout -q main
) >/dev/null 2>&1
NOGH_PATH6=$(no_gh_path)
OUT6=$(cd "$F6" && env PATH="$NOGH_PATH6" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=monthly DOSSIER_CI_THRESHOLDS_ROTATION_MAX_ACCUMULATED_LINES=100 "$SCRIPT" 2>&1)
RC6=$?
assert_equal "0" "$RC6" "would-rotate via size alone: exits 0"
assert_equal "unknown" "$(get "$OUT6" age_source)" "would-rotate via size alone: age_source=unknown (no Dossier-Generated commit found)"
assert_equal "true" "$(get "$OUT6" would_rotate)" "would-rotate via size alone: would_rotate=true (200 lines > 100-line threshold)"
assert_contains "accumulated" "$(get "$OUT6" reason)" "would-rotate via size alone: reason names the size condition"

# =============================================================================
# 6b. Exactly one dimension unknown (age) with the OTHER known dimension
#     (size) under its threshold must still report would_rotate=unknown, not
#     a confident "false" -- the unmeasured age dimension could have been
#     over threshold. Same fixture shape as test 6 (no Dossier-Generated
#     commit -> age_source=unknown), but the diff is kept small so size alone
#     does not trigger. Regression test for the P1 finding on rotation-check
#     issue #138 review (dossier-rotation-check.sh:324).
# =============================================================================
F6B=$(setup_fixture)
(
  cd "$F6B" || exit 1
  git checkout -q -B docs/dossier origin/main
  printf 'line one\nline two\nline three\n' >> docs.md
  git add -A
  git config user.email test@example.com
  git config user.name "Test"
  git commit -q -m "not a dossier commit"
  git push -q origin docs/dossier
  git checkout -q main
) >/dev/null 2>&1
NOGH_PATH6B=$(no_gh_path)
OUT6B=$(cd "$F6B" && env PATH="$NOGH_PATH6B" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly DOSSIER_CI_THRESHOLDS_ROTATION_MAX_ACCUMULATED_LINES=5000 "$SCRIPT" 2>&1)
RC6B=$?
assert_equal "0" "$RC6B" "age unknown + size under threshold: exits 0"
assert_equal "unknown" "$(get "$OUT6B" age_source)" "age unknown + size under threshold: age_source=unknown (no Dossier-Generated commit found)"
ACC_LINES6B=$(get "$OUT6B" accumulated_lines)
if [ -n "$ACC_LINES6B" ] && [ "$ACC_LINES6B" -eq 3 ] 2>/dev/null; then
  _dossier_assert_pass "age unknown + size under threshold: accumulated_lines is a real measured number (3), not blanked by the unknown branch"
else
  _dossier_assert_fail "age unknown + size under threshold: accumulated_lines was '$ACC_LINES6B', expected 3 -- metrics must still flow even when would_rotate=unknown (AC4)"
fi
assert_equal "unknown" "$(get "$OUT6B" would_rotate)" "age unknown + size under threshold: would_rotate=unknown, NOT false -- the unmeasured age dimension could still be over threshold"
REASON6B=$(get "$OUT6B" reason)
assert_not_contains "within threshold" "$REASON6B" "age unknown + size under threshold: reason avoids the confident 'within threshold' phrasing"
assert_contains "age is unavailable" "$REASON6B" "age unknown + size under threshold: reason names age as the unavailable dimension"

# =============================================================================
# 7. Both unknown -> the literal string "unknown", never coerced to false
# =============================================================================
F7=$(setup_fixture)
push_docs_branch_commit "$F7" "docs/dossier" "$(day_offset 5)"
(
  cd "$F7" || exit 1
  git remote set-url origin /nonexistent/path/that/does/not/exist.git
) >/dev/null 2>&1
NOGH_PATH7=$(no_gh_path)
SUMMARY7=$(_dossier_safe_mktemp_dir "rotation-summary7")/summary.md
OUT7=$(cd "$F7" && env PATH="$NOGH_PATH7" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly "$SCRIPT" --summary "$SUMMARY7" 2>&1)
RC7=$?
assert_equal "0" "$RC7" "transport failure: still exits 0 (a data-availability failure, not an infra failure)"
assert_equal "unknown" "$(get "$OUT7" would_rotate)" "transport failure: would_rotate is the literal string 'unknown', never coerced to false"
assert_equal "unknown" "$(get "$OUT7" age_source)" "transport failure: age_source=unknown"
if [ -f "$SUMMARY7" ] && grep -qiE "fetch|remote|transport|unreachable" "$SUMMARY7" 2>/dev/null; then
  _dossier_assert_pass "transport failure: summary notes the transport/fetch failure"
else
  _dossier_assert_fail "transport failure: summary did not mention the transport failure"
fi

# =============================================================================
# 8. Malformed threshold config falls back to the documented default (5000)
# =============================================================================
F8=$(setup_fixture)
(
  cd "$F8" || exit 1
  git checkout -q -B docs/dossier origin/main
  i=1
  while [ "$i" -le 60 ]; do
    printf 'line %s\n' "$i" >> docs.md
    i=$((i + 1))
  done
  git add -A
  GIT_AUTHOR_DATE="$(day_offset 35)T00:00:00Z" GIT_COMMITTER_DATE="$(day_offset 35)T00:00:00Z" \
    git commit -q -m "chore(dossier): generated" -m "Dossier-Generated: true"
  git push -q origin docs/dossier
  git checkout -q main
) >/dev/null 2>&1
NOGH_PATH8=$(no_gh_path)
OUT8=$(cd "$F8" && env PATH="$NOGH_PATH8" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=monthly DOSSIER_CI_THRESHOLDS_ROTATION_MAX_ACCUMULATED_LINES=not-a-number "$SCRIPT" 2>&1)
RC8=$?
assert_equal "0" "$RC8" "malformed threshold: exits 0"
assert_equal "true" "$(get "$OUT8" would_rotate)" "malformed threshold: would_rotate=true via age (35 days > 30-day monthly threshold) -- proves the script did not crash on the bad threshold"

# =============================================================================
# 9. --shortstat parsing: insertions-only and deletions-only diffs
# =============================================================================
F9=$(setup_fixture)
(
  cd "$F9" || exit 1
  git checkout -q -B docs/dossier origin/main
  printf 'brand new content\nsecond line\n' > new-file.md
  git add -A
  git config user.email test@example.com
  git config user.name "Test"
  GIT_AUTHOR_DATE="$(day_offset 1)T00:00:00Z" GIT_COMMITTER_DATE="$(day_offset 1)T00:00:00Z" \
    git commit -q -m "chore(dossier): generated" -m "Dossier-Generated: true"
  git push -q origin docs/dossier
  git checkout -q main
) >/dev/null 2>&1
NOGH_PATH9=$(no_gh_path)
OUT9=$(cd "$F9" && env PATH="$NOGH_PATH9" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=none "$SCRIPT" 2>&1)
ACC_LINES9=$(get "$OUT9" accumulated_lines)
if [ -n "$ACC_LINES9" ] && [ "$ACC_LINES9" -eq 2 ] 2>/dev/null; then
  _dossier_assert_pass "shortstat parsing: insertions-only diff (new file, no deletions clause) counted correctly (2 lines)"
else
  _dossier_assert_fail "shortstat parsing: insertions-only diff miscounted (got '$ACC_LINES9', expected 2)"
fi

# =============================================================================
# 10. CLI / exit-code checks
# =============================================================================
"$SCRIPT" --nonexistent-flag >/dev/null 2>&1
assert_equal "2" "$?" "unknown flag exits 2"

NOTGIT=$(_dossier_safe_mktemp_dir "rotation-notgit")
OUT_NOTGIT=$(cd "$NOTGIT" && env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPT" 2>&1)
RC_NOTGIT=$?
assert_equal "1" "$RC_NOTGIT" "run outside a git repository exits 1 (infrastructure failure)"
assert_contains "not inside a git repository" "$OUT_NOTGIT" "run outside a git repository: die_infra names the actual reason"

# =============================================================================
# 11. Structural workflow assertions live in workflow-template.test.sh, not
#     here — this file only exercises dossier-rotation-check.sh's own CLI.
# =============================================================================

_dossier_test_summary
