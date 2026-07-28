#!/usr/bin/env bash
# dossier-policy.sh: staleness must actively trigger a scheduled sweep. Issue
# #135 AC #1 (a stale document with no other trigger gets a real re-verification
# pass on a scheduled cadence) and AC #3 (a single sweep never re-verifies an
# unbounded number of documents).
#
# dossier-policy.sh had zero behavioural test coverage before this file —
# bin-scripts.test.sh only checks it exists, is executable, and has a usage
# header. This fixture drives it through a real (if minimal) git repository,
# the same way the CI workflow and a local /dossier:refresh both do.

_dossier_test_begin "staleness-trigger"

POLICY="$(pwd)/plugins/dossier/bin/dossier-policy.sh"
PLUGIN_ROOT="$(pwd)/plugins/dossier"

if [ ! -x "$POLICY" ]; then
  _dossier_assert_fail "$POLICY missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

day_offset() { date -u -d "-$1 days" +%Y-%m-%d 2>/dev/null || date -u -v-"$1"d +%Y-%m-%d 2>/dev/null; }

# The sweep walk is restricted to the 23 canonical document paths (SEC-3) —
# fixtures must plant real canonical filenames, not made-up ones like
# "stale-1.md", or the sweep will silently never find them. Ten of the
# canonical paths live under 00-control/ and 02-architecture/, which is
# enough to cover this file's largest fixture (8 documents).
CANON_FIXTURE_DOCS='00-control/documentation-index.md
00-control/evidence-ledger.md
00-control/assumptions-questions-and-contradictions.md
00-control/claim-and-disclosure-register.md
00-control/terminology-and-ownership.md
02-architecture/system-architecture.md
02-architecture/components-and-codebase.md
02-architecture/data-and-ai.md
02-architecture/interfaces-and-integrations.md
02-architecture/infrastructure-and-deployment.md'

setup_fixture() {
  # $1 = number of stale documents to plant (each independently past 90 days),
  # drawn from CANON_FIXTURE_DOCS in order.
  local n="$1" fixture rel i=1
  fixture=$(_dossier_safe_mktemp_dir "policy-stale")
  mkdir -p "$fixture/docs/dossier/00-control" "$fixture/docs/dossier/02-architecture"
  printf '%s\n' "$CANON_FIXTURE_DOCS" | head -n "$n" | while IFS= read -r rel; do
    cat >"$fixture/docs/dossier/$rel" <<EOF
dossier-header: v1
last-verified: $(day_offset $((300 + i)))
---
Stale document.
EOF
    i=$((i + 1))
  done
  (
    cd "$fixture" || exit 1
    git init -q
    git config user.email test@example.com
    git config user.name "Test"
    git add -A
    git commit -q -m "watermark"
  ) >/dev/null 2>&1
  printf '%s' "$fixture"
}

run_policy() {
  # $1 = fixture dir, $2 = EVT, $3 = watermark sha, remaining = extra env assignments (KEY=VAL)
  local fixture="$1" evt="$2" watermark="$3"
  shift 3
  ( cd "$fixture" && env "$@" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" EVT="$evt" PR_LABELS="" PR_HEAD_REF="" PR_ACTOR="" PR_NUMBER="" \
      "$POLICY" --base "$watermark" 2>&1 )
}

get() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,""); print; exit}'; }

# --- One stale document, no other trigger, EVT=schedule ---------------------
F1=$(setup_fixture 1)
WM1=$(git -C "$F1" rev-parse HEAD)
( cd "$F1" && echo noise > random-file.txt && git add -A && git commit -q -m "irrelevant change" ) >/dev/null 2>&1

OUT_SCHEDULE=$(run_policy "$F1" schedule "$WM1")
assert_equal "true" "$(get "$OUT_SCHEDULE" should_run)" "AC1: a stale doc + no relevant-path diff + EVT=schedule forces should_run=true"
assert_equal "stale-sweep" "$(get "$OUT_SCHEDULE" reason)" "AC1: the reason is stale-sweep, not ok/forced"
assert_contains "00-control/documentation-index.md" "$(get "$OUT_SCHEDULE" stale_docs)" "AC1: the stale_docs output field names the actual stale document"

# --- The quiet-repo case: zero commits at all since the watermark (Rule 6) -
# Re-checkout the watermark itself so BASE_SHA == HEAD_SHA — the true
# quiet-week case change-triggers-and-blast-radius.md describes: "on a quiet
# repository the merge trigger never fires."
( cd "$F1" && git checkout -q "$WM1" ) >/dev/null 2>&1
OUT_R6=$(run_policy "$F1" schedule "$WM1")
assert_equal "true" "$(get "$OUT_R6" should_run)" "Rule 6 (up-to-date, zero commits since watermark) is also overridden by a stale document"
assert_equal "stale-sweep" "$(get "$OUT_R6" reason)" "Rule 6 override reports reason=stale-sweep"
( cd "$F1" && git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null || true ) >/dev/null 2>&1

# --- Same fixture, EVT=pull_request: staleness must NOT override -----------
OUT_PR=$(run_policy "$F1" pull_request "$WM1")
assert_equal "false" "$(get "$OUT_PR" should_run)" "staleness never overrides on a non-schedule event"
assert_equal "no-relevant-paths" "$(get "$OUT_PR" reason)" "a non-schedule event keeps the original no-relevant-paths reason"

# --- Many stale documents: the sweep is bounded, not unbounded (AC3) -------
F2=$(setup_fixture 8)
WM2=$(git -C "$F2" rev-parse HEAD)
( cd "$F2" && echo noise > random-file.txt && git add -A && git commit -q -m "irrelevant change" ) >/dev/null 2>&1

OUT_CAPPED=$(run_policy "$F2" schedule "$WM2" DOSSIER_REFRESH_MAX_STALE_DOCS_PER_SWEEP=3)
assert_equal "true" "$(get "$OUT_CAPPED" should_run)" "AC3: 8 stale docs still trigger a sweep"
STALE_DOCS_FIELD=$(get "$OUT_CAPPED" stale_docs)
STALE_DOCS_COUNT=$(printf '%s' "$STALE_DOCS_FIELD" | tr ',' '\n' | grep -c .)
assert_equal "3" "$STALE_DOCS_COUNT" "AC3: the stale_docs list is capped at maxStaleDocsPerSweep (3), not all 8"

# --- No stale documents at all: schedule sweep behaves exactly as before ---
F3=$(_dossier_safe_mktemp_dir "policy-fresh")
mkdir -p "$F3/docs/dossier/00-control" "$F3/docs/dossier/02-architecture"
cat >"$F3/docs/dossier/02-architecture/system-architecture.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 5)
---
Fresh document.
EOF
( cd "$F3" && git init -q && git config user.email test@example.com && git config user.name "Test" && git add -A && git commit -q -m "watermark" ) >/dev/null 2>&1
WM3=$(git -C "$F3" rev-parse HEAD)
( cd "$F3" && echo noise > random-file.txt && git add -A && git commit -q -m "irrelevant change" ) >/dev/null 2>&1

OUT_NOSTALE=$(run_policy "$F3" schedule "$WM3")
assert_equal "false" "$(get "$OUT_NOSTALE" should_run)" "no stale documents: the schedule sweep still declines to run, unchanged from before this feature"
assert_equal "no-relevant-paths" "$(get "$OUT_NOSTALE" reason)" "no stale documents: reason is still no-relevant-paths, not stale-sweep"

# --- ERR-3: an infrastructure failure in dossier-staleness-check.sh must not
# be silently treated as "zero stale documents" ------------------------------
# A real sibling-script copy (dossier-policy.sh needs dossier-resolve-config.sh
# alongside it) with only dossier-staleness-check.sh swapped for a script that
# always fails — entirely inside an isolated fixture, the real repo scripts
# are never touched.
ERR3_ROOT=$(_dossier_safe_mktemp_dir "policy-staleness-failure")
mkdir -p "$ERR3_ROOT/bin"
cp "$(pwd)/plugins/dossier/bin/"*.sh "$ERR3_ROOT/bin/"
cat >"$ERR3_ROOT/bin/dossier-staleness-check.sh" <<'FAKE'
#!/usr/bin/env bash
echo "dossier-staleness-check: simulated infrastructure failure" >&2
exit 2
FAKE
chmod +x "$ERR3_ROOT/bin"/*.sh

F4=$(setup_fixture 1)
WM4=$(git -C "$F4" rev-parse HEAD)
( cd "$F4" && echo noise > random-file.txt && git add -A && git commit -q -m "irrelevant change" ) >/dev/null 2>&1

ERR3_SUMMARY="$ERR3_ROOT/summary.md"
OUT_ERR3=$( cd "$F4" && env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" EVT="schedule" PR_LABELS="" PR_HEAD_REF="" PR_ACTOR="" PR_NUMBER="" \
    "$ERR3_ROOT/bin/dossier-policy.sh" --base "$WM4" --summary "$ERR3_SUMMARY" 2>&1 )
assert_not_contains "reason=stale-sweep" "$OUT_ERR3" "ERR-3: a staleness-check infrastructure failure never masquerades as reason=stale-sweep"
ERR3_SUMMARY_BODY=$(cat "$ERR3_SUMMARY" 2>/dev/null)
assert_contains "dossier-staleness-check.sh failed" "$ERR3_SUMMARY_BODY" "ERR-3: the failure is noted in the run summary, not silently swallowed"
assert_contains "simulated infrastructure failure" "$ERR3_SUMMARY_BODY" "ERR-3: the note carries the underlying script's stderr, not just a generic message"

_dossier_test_summary
