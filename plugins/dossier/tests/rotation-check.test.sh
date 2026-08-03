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
future_offset() { date -u -d "+$1 days" +%Y-%m-%d 2>/dev/null || date -u -v+"$1"d +%Y-%m-%d 2>/dev/null; }

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

# =============================================================================
# 12. An explicitly-empty config override for the branch name or rotation
#     policy must never collide with the real "no-branch"/"disabled" signal.
#     DOSSIER_CI_ROLLING_BRANCH="" beats every cascade layer by design
#     (dossier-resolve-config.sh treats set-but-empty as deliberate, not
#     "fall through to default"), and an empty branch name reaches
#     `git ls-remote --exit-code --heads origin ""`, which returns exit code
#     2 -- the SAME code that means "branch genuinely doesn't exist". A real
#     docs/dossier branch exists in this fixture and would otherwise warrant
#     rotation (via size); an unguarded empty override must not silently
#     make it invisible. Regression test for a review finding (ERR-1).
# =============================================================================
F12=$(setup_fixture)
(
  cd "$F12" || exit 1
  git checkout -q -B docs/dossier origin/main
  i=1
  while [ "$i" -le 200 ]; do
    printf 'line %s\n' "$i" >> docs.md
    i=$((i + 1))
  done
  git add -A
  git config user.email test@example.com
  git config user.name "Test"
  GIT_AUTHOR_DATE="$(day_offset 1)T00:00:00Z" GIT_COMMITTER_DATE="$(day_offset 1)T00:00:00Z" \
    git commit -q -m "chore(dossier): generated" -m "Dossier-Generated: true"
  git push -q origin docs/dossier
  git checkout -q main
) >/dev/null 2>&1
NOGH_PATH12=$(no_gh_path)
OUT12=$(cd "$F12" && env PATH="$NOGH_PATH12" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH="" DOSSIER_CI_ROLLING_BRANCH_ROTATION=monthly DOSSIER_CI_THRESHOLDS_ROTATION_MAX_ACCUMULATED_LINES=100 "$SCRIPT" 2>&1)
RC12=$?
assert_equal "0" "$RC12" "empty DOSSIER_CI_ROLLING_BRANCH: exits 0"
assert_equal "docs/dossier" "$(get "$OUT12" docs_branch)" "empty DOSSIER_CI_ROLLING_BRANCH: falls back to the documented default, not an empty ref"
assert_equal "true" "$(get "$OUT12" would_rotate)" "empty DOSSIER_CI_ROLLING_BRANCH: still measures the real docs/dossier branch (200 lines > 100-line threshold), not a false no-branch result"

OUT12B=$(cd "$F12" && env PATH="$NOGH_PATH12" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH_ROTATION="" "$SCRIPT" 2>&1)
RC12B=$?
assert_equal "0" "$RC12B" "empty DOSSIER_CI_ROLLING_BRANCH_ROTATION: exits 0"
assert_equal "none" "$(get "$OUT12B" rotation_policy)" "empty DOSSIER_CI_ROLLING_BRANCH_ROTATION: falls back to the documented default (none)"
assert_equal "false" "$(get "$OUT12B" would_rotate)" "empty DOSSIER_CI_ROLLING_BRANCH_ROTATION: treated as disabled, not the unrecognized-policy branch"

# =============================================================================
# 13. A branch name containing a backtick or pipe must not break the job
#     summary's markdown table or inject a spoofed extra row. Regression
#     test for a review finding (SEC-1).
# =============================================================================
F13=$(setup_fixture)
WEIRD_BRANCH='docs/dossier`|evil'
SUMMARY13=$(_dossier_safe_mktemp_dir "rotation-summary13")/summary.md
OUT13=$(cd "$F13" && env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH="$WEIRD_BRANCH" "$SCRIPT" --summary "$SUMMARY13" 2>&1)
RC13=$?
assert_equal "0" "$RC13" "branch name with backtick/pipe: still exits 0"
assert_equal "$WEIRD_BRANCH" "$(get "$OUT13" docs_branch)" "branch name with backtick/pipe: raw key=value stdout is untouched by sanitize_md (sanitization is a display-boundary concern, not a working-value mutation)"
if [ -f "$SUMMARY13" ] && grep -qE '^\| Docs branch \| `docs/dossierevil` \|$' "$SUMMARY13" 2>/dev/null; then
  _dossier_assert_pass "branch name with backtick/pipe: summary table cell is sanitized, not broken"
else
  _dossier_assert_fail "branch name with backtick/pipe: summary table cell was not sanitized as expected"
fi
TABLE_ROW_COUNT13=$(grep -c '^| ' "$SUMMARY13" 2>/dev/null || echo 0)
assert_equal "9" "$TABLE_ROW_COUNT13" "branch name with backtick/pipe: exactly the 9 real table rows (header + 8 fields), no injected extra row"

# =============================================================================
# 14. `gh pr list` failing (auth/rate-limit) must be distinguished from "no
#     PR found" and must not abort the run — regression test for a review
#     finding (ERR-3): previously claimed fixed but never covered by a test.
# =============================================================================
F14=$(setup_fixture)
push_docs_branch_commit "$F14" "docs/dossier" "$(day_offset 10)"
STUB14=$(_dossier_safe_mktemp_dir "gh-stub-list-fails")
cat > "$STUB14/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$STUB14/gh"
SUMMARY14=$(_dossier_safe_mktemp_dir "rotation-summary14")/summary.md
OUT14=$(cd "$F14" && env PATH="$STUB14:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly "$SCRIPT" --summary "$SUMMARY14" 2>&1)
RC14=$?
assert_equal "0" "$RC14" "gh pr list failure: still exits 0 (falls back to the commit-based age walk, not an infra failure)"
assert_equal "branch_commits" "$(get "$OUT14" age_source)" "gh pr list failure: age_source falls back to branch_commits, not silently treated as no-PR"
assert_equal "true" "$(get "$OUT14" would_rotate)" "gh pr list failure: the fallback age (10 days) still correctly triggers rotation under the weekly threshold"
if [ -f "$SUMMARY14" ] && grep -q "gh pr list failed" "$SUMMARY14" 2>/dev/null; then
  _dossier_assert_pass "gh pr list failure: the summary distinguishes a lookup failure from a genuine no-PR-found result"
else
  _dossier_assert_fail "gh pr list failure: no note recorded distinguishing lookup failure from no-PR-found"
fi

# =============================================================================
# 15. rotationMaxAccumulatedLines=0 must not make the size signal trigger
#     unconditionally (0 <= any non-negative line count is always true) --
#     regression test for a review finding (F1/CONV1), reproduced live.
# =============================================================================
F15=$(setup_fixture)
push_docs_branch_commit "$F15" "docs/dossier" "$(day_offset 1)"
NOGH_PATH15=$(no_gh_path)
OUT15=$(cd "$F15" && env PATH="$NOGH_PATH15" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly DOSSIER_CI_THRESHOLDS_ROTATION_MAX_ACCUMULATED_LINES=0 "$SCRIPT" 2>&1)
RC15=$?
assert_equal "0" "$RC15" "zero size threshold: exits 0"
assert_equal "false" "$(get "$OUT15" would_rotate)" "zero size threshold: falls back to the documented default (5000) instead of triggering on every non-empty diff"

# =============================================================================
# 16. A future-dated PR createdAt (clock skew) must not surface a negative
#     age_days alongside a reason claiming age is unavailable -- regression
#     test for a review finding (AgeDaysNegative/ERR-3/ERR-4).
# =============================================================================
F16=$(setup_fixture)
push_docs_branch_commit "$F16" "docs/dossier" "$(day_offset 1)"
STUB16=$(_dossier_safe_mktemp_dir "gh-stub-future-pr")
cat > "$STUB16/gh" <<EOF
#!/usr/bin/env bash
echo '{"number":99,"createdAt":"$(future_offset 3)T00:00:00Z"}'
exit 0
EOF
chmod +x "$STUB16/gh"
OUT16=$(cd "$F16" && env PATH="$STUB16:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly "$SCRIPT" 2>&1)
RC16=$?
assert_equal "0" "$RC16" "future-dated PR createdAt (clock skew): still exits 0"
assert_equal "" "$(get "$OUT16" age_days)" "future-dated PR createdAt: age_days is blanked, not a negative number, once age is known-unreliable"
assert_equal "unknown" "$(get "$OUT16" would_rotate)" "future-dated PR createdAt: would_rotate=unknown, not a false coerced from a negative age"
assert_contains "unavailable" "$(get "$OUT16" reason)" "future-dated PR createdAt: reason states age is unavailable, consistent with the blanked age_days"

# =============================================================================
# 17. `gh pr list --head` matches by branch name only, across every fork with
#     an open PR against this repo. A cross-repository decoy PR (same branch
#     name, recent, opened from a fork) must never be preferred over the real
#     same-repo PR -- regression test for a review finding (SEC-1), reproduced
#     via a stub that actually applies gh's --jq filter (real `gh` behavior),
#     not just a fixed echo like the other gh stubs in this file.
# =============================================================================
F17=$(setup_fixture)
push_docs_branch_commit "$F17" "docs/dossier" "$(day_offset 10)"
STUB17=$(_dossier_safe_mktemp_dir "gh-stub-cross-repo")
STUB17_JSON="[{\"number\":13,\"createdAt\":\"$(day_offset 1)T00:00:00Z\",\"isCrossRepository\":true},{\"number\":7,\"createdAt\":\"$(day_offset 10)T00:00:00Z\",\"isCrossRepository\":false}]"
cat > "$STUB17/gh" <<STUBEOF
#!/usr/bin/env bash
FILTER=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) FILTER="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
JSON='$STUB17_JSON'
if [ -n "\$FILTER" ]; then
  printf '%s' "\$JSON" | jq "\$FILTER"
else
  printf '%s' "\$JSON"
fi
STUBEOF
chmod +x "$STUB17/gh"
OUT17=$(cd "$F17" && env PATH="$STUB17:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION=weekly "$SCRIPT" 2>&1)
RC17=$?
assert_equal "0" "$RC17" "cross-repository decoy PR: exits 0"
assert_equal "true" "$(get "$OUT17" would_rotate)" "cross-repository decoy PR: the real same-repo PR (10 days old) drives the age determination, not the more-recent fork decoy that would mask rotation"
assert_equal "pr_created_at" "$(get "$OUT17" age_source)" "cross-repository decoy PR: age_source is still pr_created_at (the real PR was found, not silently skipped)"

# =============================================================================
# 18. A genuine config-resolver infrastructure failure (not an empty/default
#     value) must be reported as a hard failure, never silently treated as a
#     deliberate empty override -- regression test for a review finding
#     (ERR1/skeptic), reproduced live on this session's machine via a stub
#     `mktemp` that fails only for cascade-resolve.sh's own error-capture
#     temp file (its real Ubuntu-runner trigger, an unwritable $TMPDIR, is
#     silently tolerated by BSD/macOS mktemp, so it can't be reproduced
#     directly on a macOS dev machine -- this reproduces the same downstream
#     failure, $CASCADE exiting 2, by the most portable available means).
# =============================================================================
F18=$(setup_fixture)
REAL_MKTEMP=$(command -v mktemp)
STUB18=$(_dossier_safe_mktemp_dir "mktemp-stub-cascade-fail")
cat > "$STUB18/mktemp" <<STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    *cascade-resolve.err*) echo "mktemp: stub failure (simulated infra failure)" >&2; exit 1 ;;
  esac
done
exec "$REAL_MKTEMP" "\$@"
STUBEOF
chmod +x "$STUB18/mktemp"
OUT18=$(cd "$F18" && env PATH="$STUB18:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier "$SCRIPT" 2>&1)
RC18=$?
assert_equal "1" "$RC18" "config resolver infra failure: exits 1 (a hard infrastructure failure), not 0 (a reached decision)"
assert_contains "could not resolve" "$OUT18" "config resolver infra failure: die_infra names the actual cause, not a generic empty-override note"
assert_not_contains "would_rotate=false" "$OUT18" "config resolver infra failure: never emits a confident would_rotate result"

# =============================================================================
# 19. An unrecognized rotation policy value must (a) be treated as disabled,
#     with its own distinct reason (not silently merged into "none"), and
#     (b) have any markdown-active syntax in the value neutralized in the
#     job summary's Notes section -- regression test for two review findings
#     (UnrecognizedPolicyUntested: the fallback arm had no test at all;
#     SEC-1/verifier: note() didn't neutralize markdown link/bold/heading
#     syntax the way table cells already do).
# =============================================================================
F19=$(setup_fixture)
push_docs_branch_commit "$F19" "docs/dossier" "$(day_offset 1)"
NOGH_PATH19=$(no_gh_path)
SUMMARY19=$(_dossier_safe_mktemp_dir "rotation-summary19")/summary.md
WEIRD_POLICY='biweekly [click here](https://evil.example)'
OUT19=$(cd "$F19" && env PATH="$NOGH_PATH19" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH=docs/dossier DOSSIER_CI_ROLLING_BRANCH_ROTATION="$WEIRD_POLICY" "$SCRIPT" --summary "$SUMMARY19" 2>&1)
RC19=$?
assert_equal "0" "$RC19" "unrecognized rotation policy: exits 0"
assert_equal "false" "$(get "$OUT19" would_rotate)" "unrecognized rotation policy: treated as disabled"
assert_contains "not recognised" "$(get "$OUT19" reason)" "unrecognized rotation policy: reason names it as unrecognized, distinct from the 'none' (deliberately disabled) case"
# Scoped to the Notes section specifically -- the table's "Rotation policy"
# row ALREADY wraps its value in backticks regardless of this fix (that's a
# separate, pre-existing safe path), so a file-wide grep would pass even
# without the fix by matching the table row instead of the actually
# vulnerable bullet line.
NOTES_SECTION19=$(awk '/^Notes:$/{found=1; next} found' "$SUMMARY19" 2>/dev/null)
if printf '%s\n' "$NOTES_SECTION19" | grep -qE '^- `.*\[click here\]\(https://evil\.example\).*`$'; then
  _dossier_assert_pass "unrecognized rotation policy: the Notes bullet is backtick-wrapped, neutralizing the embedded link syntax"
else
  _dossier_assert_fail "unrecognized rotation policy: the Notes bullet is not backtick-wrapped as expected"
fi
if printf '%s\n' "$NOTES_SECTION19" | grep -qF '](https://evil.example)' && ! printf '%s\n' "$NOTES_SECTION19" | grep -qE '^- `.*\[click here\]\(https://evil\.example\).*`$'; then
  _dossier_assert_fail "unrecognized rotation policy: the Notes section renders a live markdown link instead of an inert code span"
else
  _dossier_assert_pass "unrecognized rotation policy: the Notes section does not render a live markdown link"
fi

# =============================================================================
# 20. The --github-output flag's newline-injection defense (emit()'s
#     control-character stripping, which is the only thing preventing a
#     crafted config value from forging additional key=value pairs for a
#     later CI step to read) had no test at all -- regression test for a
#     review finding (TEST2, raised independently by both review lenses).
# =============================================================================
F20=$(setup_fixture)
NOGH_PATH20=$(no_gh_path)
GHOUT20=$(_dossier_safe_mktemp_dir "rotation-ghout20")/github_output
: > "$GHOUT20"
INJECT_BRANCH='docs/dossier
fake_output=INJECTED
real='
OUT20=$(cd "$F20" && env PATH="$NOGH_PATH20" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" DOSSIER_CI_ROLLING_BRANCH="$INJECT_BRANCH" "$SCRIPT" --github-output "$GHOUT20" 2>&1)
RC20=$?
assert_equal "0" "$RC20" "github-output newline injection attempt: still exits 0"
assert_equal "docs/dossierfake_output=INJECTEDreal=" "$(get "$OUT20" docs_branch)" "github-output newline injection attempt: stdout's own docs_branch field is collapsed the same way as the --github-output file"
GHOUT_LINES20=$(wc -l < "$GHOUT20" | tr -d ' ')
assert_equal "8" "$GHOUT_LINES20" "github-output newline injection attempt: exactly the 8 real fields written, no forged extra key=value pairs"
if grep -q '^fake_output=INJECTED$' "$GHOUT20" 2>/dev/null; then
  _dossier_assert_fail "github-output newline injection attempt: a forged fake_output key was written to \$GITHUB_OUTPUT"
else
  _dossier_assert_pass "github-output newline injection attempt: no forged key was written to \$GITHUB_OUTPUT"
fi
assert_contains "docs_branch=docs/dossierfake_output=INJECTEDreal=" "$(cat "$GHOUT20")" "github-output newline injection attempt: the embedded newlines collapse onto the single docs_branch line rather than forging new lines"

_dossier_test_summary
