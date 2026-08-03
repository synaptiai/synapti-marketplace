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

_dossier_test_summary
