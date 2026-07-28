#!/usr/bin/env bash
# Issue #135 AC #2 — the stale-triggered verification-not-redraft path.
#
# The actual redraft-vs-verify decision happens inside an LLM agent dispatch
# (commands/refresh.md Phase 4), which this bash suite cannot execute. What
# IS mechanically testable, and is tested here:
#   1. dossier-evidence.sh --stale-docs correctly threads the list into
#      manifest.json's stale_docs field (the file Phase 2 actually reads).
#   2. commands/refresh.md's Phase 2/3/4 text carries the class:"stale"
#      branch, the never-redraft-without-drift rule, and the --stale-docs
#      wiring — structural assertions, the same technique
#      skill-frontmatter.test.sh and workflow-template.test.sh already use
#      for markdown command contracts.

_dossier_test_begin "refresh-staleness"

EVIDENCE_SCRIPT="$(pwd)/plugins/dossier/bin/dossier-evidence.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$EVIDENCE_SCRIPT" ]; then
  _dossier_assert_fail "$EVIDENCE_SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

# --- dossier-evidence.sh --stale-docs -> manifest.json stale_docs ----------
FIXTURE=$(_dossier_safe_mktemp_dir "refresh-staleness")
(
  cd "$FIXTURE" || exit 1
  git init -q
  git config user.email test@example.com
  git config user.name "Test"
  mkdir -p docs/dossier/00-control
  echo "seed" > seed.txt
  git add -A
  git commit -q -m "base"
  echo "change" > seed.txt
  git add -A
  git commit -q -m "head"
) >/dev/null 2>&1
BASE_SHA=$(git -C "$FIXTURE" log --format=%H | tail -1)
HEAD_SHA=$(git -C "$FIXTURE" rev-parse HEAD)

OUT_DIR="$FIXTURE/.dossier/evidence"
( cd "$FIXTURE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$EVIDENCE_SCRIPT" \
    --base "$BASE_SHA" --head "$HEAD_SHA" --out "$OUT_DIR" \
    --stale-docs "02-architecture/system-architecture.md,04-operating/onboarding-and-local-development.md" ) >/dev/null 2>&1

assert_file_exists "$OUT_DIR/manifest.json" "manifest.json was written"

STALE_DOCS_JSON=$(jq -c '.stale_docs' "$OUT_DIR/manifest.json" 2>/dev/null)
assert_equal '["02-architecture/system-architecture.md","04-operating/onboarding-and-local-development.md"]' "$STALE_DOCS_JSON" "manifest.json's stale_docs field carries both paths, in order"

UNTRUSTED_HAS_STALE=$(jq -r '.untrusted | any(. == "docs-state.json")' "$OUT_DIR/manifest.json" 2>/dev/null)
assert_equal "true" "$UNTRUSTED_HAS_STALE" "sanity: the untrusted array still lists docs-state.json (unaffected by this change)"
STALE_DOCS_IN_UNTRUSTED=$(jq -r '.untrusted | any(. == "stale_docs")' "$OUT_DIR/manifest.json" 2>/dev/null)
assert_equal "false" "$STALE_DOCS_IN_UNTRUSTED" "stale_docs is dossier-policy.sh's own computation, not repository content, so it is not marked untrusted"

# --- No --stale-docs flag: field defaults to an empty array ----------------
OUT_DIR2="$FIXTURE/.dossier/evidence2"
( cd "$FIXTURE" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$EVIDENCE_SCRIPT" \
    --base "$BASE_SHA" --head "$HEAD_SHA" --out "$OUT_DIR2" ) >/dev/null 2>&1
NO_STALE_JSON=$(jq -c '.stale_docs' "$OUT_DIR2/manifest.json" 2>/dev/null)
assert_equal '[]' "$NO_STALE_JSON" "without --stale-docs, manifest.json's stale_docs field is an empty array, not null or absent"

# --- commands/refresh.md: structural contract for the verification path ----
REFRESH_MD="plugins/dossier/commands/refresh.md"
if [ -f "$REFRESH_MD" ]; then
  BODY=$(cat "$REFRESH_MD")

  assert_contains "stale-docs" "$BODY" "Phase 2 passes --stale-docs to dossier-blast-radius.sh"
  assert_contains 'class: "stale"' "$BODY" "refresh.md documents the class:\"stale\" blast-radius value"
  assert_contains "do **not** dispatch the drafter" "$BODY" "Phase 4 explicitly says not to dispatch the drafter for stale-only documents"
  assert_contains "No drift" "$BODY" "Phase 4 documents the no-drift (advance last-verified only) branch"
  assert_contains "Drift found" "$BODY" "Phase 4 documents the drift-found (fall through to redraft) branch"
  assert_contains "dossier-evidence-collector" "$BODY" "Phase 3 still routes stale-only re-verification through the evidence-collector agent, never the drafter"
else
  _dossier_assert_fail "$REFRESH_MD missing"
fi

_dossier_test_summary
