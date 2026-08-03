#!/usr/bin/env bash
# dossier-policy.sh (issue #146): the EXISTING_PR lookup at line ~390 uses
# `gh pr list --head "$DOCS_BRANCH"`, which matches by branch name only,
# across every fork with an open PR against this repo — `gh` has no
# owner:branch syntax to scope `--head` to a specific fork. Left unfiltered,
# an external contributor could open a same-named decoy PR from a fork and
# have it silently returned instead of (or ahead of) the real docs-refresh
# PR, feeding straight into the publish job's write-token `gh pr edit` call.
#
# This is the pre-existing original that PR #145's SEC-1 fix (in the new
# dossier-rotation-check.sh) was copied from — that script already carries
# the isCrossRepository filter; this file regression-tests the same fix
# applied to the original call site.

_dossier_test_begin "policy-existing-pr"

POLICY="$(pwd)/plugins/dossier/bin/dossier-policy.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$POLICY" ]; then
  _dossier_assert_fail "$POLICY missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# Minimal fixture: a real git repo with one fresh (non-stale) canonical
# document, so the staleness sweep this script also runs has nothing to
# report and cannot interfere with the field this file actually asserts on
# (existing_pr) -- same fixture shape proven to work end-to-end for
# dossier-policy.sh in staleness-trigger.test.sh's own F3 case.
_dossier_require_mktemp_dir FIXTURE "policy-existing-pr"
mkdir -p "$FIXTURE/docs/dossier/02-architecture"
TODAY=$(date -u +%Y-%m-%d)
cat >"$FIXTURE/docs/dossier/02-architecture/system-architecture.md" <<EOF
dossier-header: v1
last-verified: $TODAY
---
Fresh document.
EOF
(
  cd "$FIXTURE" || exit 1
  git init -q
  git config user.email test@example.com
  git config user.name "Test"
  git add -A
  git commit -q -m "watermark"
) >/dev/null 2>&1
WM=$(git -C "$FIXTURE" rev-parse HEAD)
( cd "$FIXTURE" && echo noise > random-file.txt && git add -A && git commit -q -m "irrelevant change" ) >/dev/null 2>&1

get() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,""); print; exit}'; }

run_policy() {
  # $1 = PATH prefix (the fake-gh stub dir), rest is env passthrough.
  local stub_path="$1"
  shift
  ( cd "$FIXTURE" && env PATH="$stub_path:$PATH" "$@" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
      EVT=schedule PR_LABELS="" PR_HEAD_REF="" PR_ACTOR="" PR_NUMBER="" \
      "$POLICY" --base "$WM" 2>&1 )
}

# =============================================================================
# 1. A cross-repository decoy PR (same branch name, more recently opened, from
#    a fork) must never be preferred over the real same-repo PR. The stub
#    applies gh's real --jq filter via actual jq against a JSON array carrying
#    both PRs -- not a fixed echo -- so this exercises the exact jq expression
#    dossier-policy.sh sends, the same technique rotation-check.test.sh uses
#    in its own scenario 17 for the sibling script this fix was copied from.
# =============================================================================
_dossier_require_mktemp_dir STUB1 "policy-gh-stub-decoy"
STUB1_JSON='[{"number":99,"isCrossRepository":true},{"number":7,"isCrossRepository":false}]'
cat > "$STUB1/gh" <<STUBEOF
#!/usr/bin/env bash
FILTER=""
HAS_HEAD=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) FILTER="\$2"; shift 2 ;;
    --head) HAS_HEAD=1; shift 2 ;;
    *) shift ;;
  esac
done
# Distinguish the EXISTING_PR lookup (passes --head "\$DOCS_BRANCH") from the
# circuit-breaker count (passes --state all --label, no --head) by the flag
# actually used to select between the two call shapes -- not by which --json
# fields were requested, since the FIX under test is exactly a change to
# which fields the EXISTING_PR call requests (number -> number,isCrossRepository).
# A stub keyed on --json content would silently test the wrong thing against
# pre-fix code. isCrossRepository is always present in the served JSON
# regardless of what --json asked for, same as a real GitHub API response
# would carry -- only the caller's own --jq filter decides what it extracts.
if [ "\$HAS_HEAD" -eq 1 ]; then
  JSON='$STUB1_JSON'
else
  JSON='[]'
fi
if [ -n "\$FILTER" ]; then
  printf '%s' "\$JSON" | jq "\$FILTER"
else
  printf '%s' "\$JSON"
fi
STUBEOF
chmod +x "$STUB1/gh"

OUT1=$(run_policy "$STUB1")
RC1=$?
assert_equal "0" "$RC1" "cross-repository decoy PR present: dossier-policy.sh still exits 0"
assert_equal "7" "$(get "$OUT1" existing_pr)" "cross-repository decoy PR present: the real same-repo PR (#7) is selected, not the fork decoy (#99)"

# =============================================================================
# 2. No open PR at all (both same-repo and cross-repo): existing_pr is empty,
#    not a stale/wrong value from a prior lookup.
# =============================================================================
_dossier_require_mktemp_dir STUB2 "policy-gh-stub-none"
cat > "$STUB2/gh" <<'STUBEOF'
#!/usr/bin/env bash
FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$FILTER" ]; then
  printf '%s' '[]' | jq "$FILTER"
else
  printf '%s' '[]'
fi
STUBEOF
chmod +x "$STUB2/gh"

OUT2=$(run_policy "$STUB2")
RC2=$?
assert_equal "0" "$RC2" "no open PR at all: dossier-policy.sh still exits 0"
assert_equal "" "$(get "$OUT2" existing_pr)" "no open PR at all: existing_pr is empty, not a stale value"

# =============================================================================
# 3. Only a same-repo PR exists (the ordinary case, no fork involved): it is
#    still correctly selected -- the isCrossRepository filter must not
#    accidentally exclude legitimate same-repo PRs.
# =============================================================================
_dossier_require_mktemp_dir STUB3 "policy-gh-stub-samerepo"
STUB3_JSON='[{"number":42,"isCrossRepository":false}]'
cat > "$STUB3/gh" <<STUBEOF
#!/usr/bin/env bash
FILTER=""
HAS_HEAD=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) FILTER="\$2"; shift 2 ;;
    --head) HAS_HEAD=1; shift 2 ;;
    *) shift ;;
  esac
done
if [ "\$HAS_HEAD" -eq 1 ]; then
  JSON='$STUB3_JSON'
else
  JSON='[]'
fi
if [ -n "\$FILTER" ]; then
  printf '%s' "\$JSON" | jq "\$FILTER"
else
  printf '%s' "\$JSON"
fi
STUBEOF
chmod +x "$STUB3/gh"

OUT3=$(run_policy "$STUB3")
RC3=$?
assert_equal "0" "$RC3" "only a same-repo PR exists: dossier-policy.sh still exits 0"
assert_equal "42" "$(get "$OUT3" existing_pr)" "only a same-repo PR exists: it is correctly selected"
assert_equal "false" "$(get "$OUT3" existing_pr_lookup_failed)" "a genuinely successful lookup reports existing_pr_lookup_failed=false"

# =============================================================================
# 4. A gh pr list failure (auth/rate-limit/transient API error) must be
#    distinguishable from a genuine "no PR found" result. Left unguarded, this
#    is not merely a missed telemetry signal: the publish job's "Prepare the
#    documentation branch" step treats an empty existing_pr as license to
#    delete and recreate the documentation branch (git push origin --delete)
#    whenever the branch already exists with no foreign commits -- the exact
#    steady state whenever a real docs PR is open and gh only failed to
#    report it. existing_pr_lookup_failed is the signal that step uses to
#    refuse that path rather than silently guessing "no PR".
# =============================================================================
_dossier_require_mktemp_dir STUB4 "policy-gh-stub-failure"
cat > "$STUB4/gh" <<'STUBEOF'
#!/usr/bin/env bash
exit 1
STUBEOF
chmod +x "$STUB4/gh"

OUT4=$(run_policy "$STUB4")
RC4=$?
assert_equal "0" "$RC4" "gh pr list failure: dossier-policy.sh still exits 0 (advisory, does not hard-fail the policy job)"
assert_equal "" "$(get "$OUT4" existing_pr)" "gh pr list failure: existing_pr is empty (no data), not a guessed value"
assert_equal "true" "$(get "$OUT4" existing_pr_lookup_failed)" "gh pr list failure: existing_pr_lookup_failed distinguishes this from a genuine no-PR result"

# =============================================================================
# 5. gh entirely unavailable on PATH carries the exact same downstream risk
#    as scenario 4 (existing_pr ends up empty either way) and must set the
#    same signal -- this is the pre-existing "gh CLI unavailable" branch,
#    not a new code path.
# =============================================================================
# gh and git/jq live in the same real directory on this machine (Homebrew),
# so a PATH restriction has to keep git/jq reachable by name (via symlinks
# into an otherwise-empty directory) while genuinely excluding gh, rather
# than just omitting one directory that happens to hold all three.
_dossier_require_mktemp_dir STUB5 "policy-no-gh"
ln -s "$(command -v git)" "$STUB5/git"
ln -s "$(command -v jq)" "$STUB5/jq"
OUT5=$(cd "$FIXTURE" && env PATH="$STUB5:/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    EVT=schedule PR_LABELS="" PR_HEAD_REF="" PR_ACTOR="" PR_NUMBER="" \
    "$POLICY" --base "$WM" 2>&1)
RC5=$?
assert_equal "0" "$RC5" "gh unavailable: dossier-policy.sh still exits 0"
assert_equal "" "$(get "$OUT5" existing_pr)" "gh unavailable: existing_pr is empty"
assert_equal "true" "$(get "$OUT5" existing_pr_lookup_failed)" "gh unavailable: existing_pr_lookup_failed is also true (same downstream risk as a failed lookup)"

# =============================================================================
# 6. The lookup must bound its own page size explicitly, matching this same
#    file's circuit-breaker call (--limit 100) a few lines below. Without an
#    explicit --limit, gh applies its own default cap of 30 items BEFORE the
#    isCrossRepository filter ever runs -- 30+ same-named fork PRs (cheap to
#    script) could paginate the real same-repo PR off the page entirely,
#    silently defeating both the isCrossRepository filter and the
#    existing_pr_lookup_failed guard (gh still exits 0; nothing "failed").
#    Asserted here by capturing the stub's own argv, not by trying to
#    simulate 30+ PRs.
# =============================================================================
_dossier_require_mktemp_dir STUB6 "policy-gh-stub-limit-capture"
STUB6_ARGS_LOG="$STUB6/args.log"
cat > "$STUB6/gh" <<STUBEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB6_ARGS_LOG"
FILTER=""
HAS_HEAD=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) FILTER="\$2"; shift 2 ;;
    --head) HAS_HEAD=1; shift 2 ;;
    *) shift ;;
  esac
done
JSON='[]'
if [ -n "\$FILTER" ]; then
  printf '%s' "\$JSON" | jq "\$FILTER"
else
  printf '%s' "\$JSON"
fi
STUBEOF
chmod +x "$STUB6/gh"

run_policy "$STUB6" >/dev/null 2>&1
ARGS_LINE=$(grep -- '--head' "$STUB6_ARGS_LOG" 2>/dev/null | head -1)
assert_contains "--limit" "$ARGS_LINE" "the EXISTING_PR lookup passes an explicit --limit, matching the circuit-breaker call's own precedent"

# =============================================================================
# 7. dossier.ci.rollingBranch resolving to an explicit empty override must
#    fall back to the documented default (docs/dossier), not leave DOCS_BRANCH
#    empty -- matching the identical guard already shipped in
#    dossier-rotation-check.sh. Without this, this script's own DOCS_BRANCH
#    could diverge from the sibling script's for the exact same config value.
# =============================================================================
_dossier_require_mktemp_dir FIXTURE7 "policy-empty-branch-override"
mkdir -p "$FIXTURE7/docs/dossier/02-architecture"
cat >"$FIXTURE7/docs/dossier/02-architecture/system-architecture.md" <<EOF
dossier-header: v1
last-verified: $TODAY
---
Fresh document.
EOF
mkdir -p "$FIXTURE7/.claude"
cat > "$FIXTURE7/.claude/settings.dossier.json" <<'EOF'
{"dossier":{"ci":{"rollingBranch":""}}}
EOF
(
  cd "$FIXTURE7" || exit 1
  git init -q
  git config user.email test@example.com
  git config user.name "Test"
  git add -A
  git commit -q -m "watermark"
) >/dev/null 2>&1
WM7=$(git -C "$FIXTURE7" rev-parse HEAD)
( cd "$FIXTURE7" && echo noise > random-file.txt && git add -A && git commit -q -m "irrelevant change" ) >/dev/null 2>&1

_dossier_require_mktemp_dir STUB7 "policy-gh-stub-empty-branch"
cat > "$STUB7/gh" <<'STUBEOF'
#!/usr/bin/env bash
FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$FILTER" ]; then
  printf '%s' '[]' | jq "$FILTER"
else
  printf '%s' '[]'
fi
STUBEOF
chmod +x "$STUB7/gh"

OUT7=$(cd "$FIXTURE7" && env PATH="$STUB7:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    EVT=schedule PR_LABELS="" PR_HEAD_REF="" PR_ACTOR="" PR_NUMBER="" \
    "$POLICY" --base "$WM7" 2>&1)
RC7=$?
assert_equal "0" "$RC7" "dossier.ci.rollingBranch=\"\": dossier-policy.sh still exits 0"
assert_equal "docs/dossier" "$(get "$OUT7" docs_branch)" "dossier.ci.rollingBranch=\"\": docs_branch falls back to the documented default, not empty"

# =============================================================================
# 8. A cross-repository decoy PR with NO legitimate same-repo PR open at all
#    (the "instead of" exploit shape, not "ahead of" -- scenario 1 above only
#    covers the latter) must resolve to a genuinely empty, successful lookup,
#    not the decoy's own number.
# =============================================================================
_dossier_require_mktemp_dir STUB8 "policy-gh-stub-decoy-only"
STUB8_JSON='[{"number":99,"isCrossRepository":true}]'
cat > "$STUB8/gh" <<STUBEOF
#!/usr/bin/env bash
FILTER=""
HAS_HEAD=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) FILTER="\$2"; shift 2 ;;
    --head) HAS_HEAD=1; shift 2 ;;
    *) shift ;;
  esac
done
if [ "\$HAS_HEAD" -eq 1 ]; then
  JSON='$STUB8_JSON'
else
  JSON='[]'
fi
if [ -n "\$FILTER" ]; then
  printf '%s' "\$JSON" | jq "\$FILTER"
else
  printf '%s' "\$JSON"
fi
STUBEOF
chmod +x "$STUB8/gh"

OUT8=$(run_policy "$STUB8")
RC8=$?
assert_equal "0" "$RC8" "cross-repo decoy with no real PR open: dossier-policy.sh still exits 0"
assert_equal "" "$(get "$OUT8" existing_pr)" "cross-repo decoy with no real PR open: existing_pr is empty, not the decoy's number"
assert_equal "false" "$(get "$OUT8" existing_pr_lookup_failed)" "cross-repo decoy with no real PR open: this is a successful lookup that correctly found nothing usable, not a failure"

# =============================================================================
# 9. The human-readable job-summary table must distinguish "lookup failed" from
#    "confirmed no PR" -- both leave existing_pr empty, but only the Notes
#    section (easy to miss) previously carried the distinction. An operator
#    skimming just the table must not read a failure as a confirmed fact.
# =============================================================================
_dossier_require_mktemp_dir STUB9 "policy-gh-stub-summary-failure"
cat > "$STUB9/gh" <<'STUBEOF'
#!/usr/bin/env bash
exit 1
STUBEOF
chmod +x "$STUB9/gh"
SUMMARY9="$STUB9/summary.md"
( cd "$FIXTURE" && env PATH="$STUB9:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    EVT=schedule PR_LABELS="" PR_HEAD_REF="" PR_ACTOR="" PR_NUMBER="" \
    "$POLICY" --base "$WM" --summary "$SUMMARY9" ) >/dev/null 2>&1
RC9=$?
assert_equal "0" "$RC9" "summary table test: dossier-policy.sh still exits 0"
SUMMARY9_BODY=$(cat "$SUMMARY9" 2>/dev/null)
assert_contains "unknown (lookup failed)" "$SUMMARY9_BODY" "the summary table's Existing docs PR row distinguishes a failed lookup from a confirmed no-PR result"
assert_not_contains "Existing docs PR | \`none\`" "$SUMMARY9_BODY" "the summary table never renders a failed lookup as the same 'none' value a confirmed no-PR result would show"

_dossier_test_summary
