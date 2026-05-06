#!/usr/bin/env bash
# Simulate the full /flow lifecycle's calls to bin/journal-record.sh and assert
# the resulting manifest matches references/decision-journal-schema.md. This
# test is the contract the orchestrator wiring honors: every artifact type
# documented in the schema MUST be reachable via journal-record.sh with the
# documented --metadata fields, and the manifest assembled across multiple
# invocations MUST be diff-friendly + idempotent.
#
# Independent of the actual /flow:start, /flow:pr, /flow:merge calls — those
# invoke the same helper but through Claude Code's prompt layer. This test
# exercises the bash contract directly.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$REPO_ROOT/plugins/flow/bin/journal-record.sh"
SANDBOX=$(mktemp -d -t flow-journal-test.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

if [ ! -x "$HELPER" ]; then
  echo "FATAL: $HELPER not executable" >&2
  exit 2
fi

cd "$SANDBOX"
PASS=0
FAIL=0

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

ISSUE=99
JOURNAL=".decisions/issue-${ISSUE}.md"

# === Scenario: full /flow lifecycle for issue 99 ===
# Each invocation simulates a phase's natural emit point. Order matches the
# real lifecycle: start → review → pr → merge.

# /flow:start Phase 1 — specification-capture skill records the spec
"$HELPER" --issue "$ISSUE" --type specification \
  --metadata by=specification-capture \
  --metadata elements=non-goals,failure-modes,interface-contracts \
  >/dev/null 2>&1
assert "specification recorded (start Phase 1)" 0 $?

# /flow:start Phase 2 — Stranger Test gate result
"$HELPER" --issue "$ISSUE" --type stranger-test \
  --metadata result=PASS \
  --metadata task_count=5 \
  >/dev/null 2>&1
assert "stranger-test recorded (start Phase 2)" 0 $?

# /flow:review Phase 4 step 7 — first review cycle
"$HELPER" --issue "$ISSUE" --type review-cycle \
  --metadata cycle=1 \
  --metadata path=A \
  --metadata findings_count=3 \
  --metadata pr=98 \
  >/dev/null 2>&1
assert "review-cycle 1 recorded" 0 $?

# /flow:review Path A A.4 — a finding was dropped during consolidation
"$HELPER" --issue "$ISSUE" --type dropped-finding \
  --metadata cycle=1 \
  --metadata finding_id=F2 \
  --metadata facet=convention \
  --metadata reason=cosmetic-not-in-touched-files \
  --metadata pr=98 \
  >/dev/null 2>&1
assert "dropped-finding recorded" 0 $?

# /flow:review Path A A.5 — consolidation gap (fallback table fired)
"$HELPER" --issue "$ISSUE" --type consolidation-gap \
  --metadata cycle=1 \
  --metadata pr=98 \
  --metadata finding_id=F4 \
  --metadata reason=facet-disagreement \
  >/dev/null 2>&1
assert "consolidation-gap recorded" 0 $?

# /flow:start Phase 4 step 6 — verdict-judge result
"$HELPER" --issue "$ISSUE" --type verdict \
  --metadata result=PASS \
  --metadata pr=98 \
  >/dev/null 2>&1
assert "verdict recorded (start Phase 4)" 0 $?

# /flow:design Phase 4 — design-decision (only fires when /flow:design ran)
"$HELPER" --issue "$ISSUE" --type design-decision \
  --metadata decision=use-postgres-jsonb \
  --metadata category=architecture \
  >/dev/null 2>&1
assert "design-decision recorded (design)" 0 $?

# /flow:brainstorm Phase 4 — brainstorm-decision
"$HELPER" --issue "$ISSUE" --type brainstorm-decision \
  --metadata topic=cache-invalidation-strategy \
  --metadata chosen=time-based-ttl \
  --metadata options_considered=4 \
  >/dev/null 2>&1
assert "brainstorm-decision recorded (brainstorm)" 0 $?

# /flow:merge — escalation closed during merge gate
"$HELPER" --issue "$ISSUE" --type escalation-resolved \
  --metadata escalation_field=time-sensitivity \
  --metadata outcome=user-approved-defer \
  >/dev/null 2>&1
assert "escalation-resolved recorded (merge)" 0 $?

# === Manifest shape assertions ===
# After all 9 emits, the manifest MUST contain 9 artifacts in chronological
# order, with required per-type fields per the schema.

if [ ! -f "$JOURNAL" ]; then
  echo "FAIL: journal file not created at $JOURNAL"
  FAIL=$((FAIL + 1))
else
  # Count artifacts via Python YAML parse
  COUNT=$(python3 - "$JOURNAL" <<'PYTHON'
import sys, yaml
content = open(sys.argv[1]).read()
end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
print(len(fm.get("artifacts", [])))
PYTHON
)
  assert "manifest has 9 artifacts" 9 "$COUNT"

  # Verify top-level fields
  ISSUE_FIELD=$(python3 - "$JOURNAL" <<'PYTHON'
import sys, yaml
content = open(sys.argv[1]).read()
end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
print(fm.get("issue", "MISSING"))
PYTHON
)
  assert "manifest top-level issue=99" 99 "$ISSUE_FIELD"

  # Verify every artifact has captured_at (required by schema)
  CAPTURED_AT_COUNT=$(python3 - "$JOURNAL" <<'PYTHON'
import sys, yaml
content = open(sys.argv[1]).read()
end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
print(sum(1 for a in fm["artifacts"] if "captured_at" in a))
PYTHON
)
  assert "every artifact has captured_at" 9 "$CAPTURED_AT_COUNT"

  # Verify the artifact types appear in the order they were recorded
  TYPES=$(python3 - "$JOURNAL" <<'PYTHON'
import sys, yaml
content = open(sys.argv[1]).read()
end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
print(",".join(a["type"] for a in fm["artifacts"]))
PYTHON
)
  assert "artifact order preserved" \
    "specification,stranger-test,review-cycle,dropped-finding,consolidation-gap,verdict,design-decision,brainstorm-decision,escalation-resolved" \
    "$TYPES"

  # Verify per-type required fields present (spec says specification needs `by`
  # and `elements`; stranger-test needs `result` and `task_count`; etc.).
  REQUIRED_OK=$(python3 - "$JOURNAL" <<'PYTHON'
import sys, yaml
content = open(sys.argv[1]).read()
end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
required = {
    "specification":         {"by", "elements"},
    "stranger-test":         {"result", "task_count"},
    "review-cycle":          {"cycle", "path", "findings_count", "pr"},
    "dropped-finding":       {"cycle", "finding_id", "facet", "reason", "pr"},
    "consolidation-gap":     {"cycle", "pr", "finding_id", "reason"},
    "verdict":               {"result"},
    "design-decision":       {"decision", "category"},
    "brainstorm-decision":   {"topic", "chosen", "options_considered"},
    "escalation-resolved":   {"escalation_field", "outcome"},
}
gaps = []
for a in fm["artifacts"]:
    missing = required.get(a["type"], set()) - set(a.keys())
    if missing:
        gaps.append(f"{a['type']}: missing {sorted(missing)}")
print("OK" if not gaps else "; ".join(gaps))
PYTHON
)
  assert "every artifact has its required per-type fields" "OK" "$REQUIRED_OK"
fi

# === Idempotency check ===
# Re-recording the same artifact MUST append a new entry, not replace. Two
# review-cycle entries with cycle=1 and cycle=2 should both appear.
"$HELPER" --issue "$ISSUE" --type review-cycle \
  --metadata cycle=2 \
  --metadata path=B \
  --metadata findings_count=1 \
  --metadata pr=98 \
  >/dev/null 2>&1
assert "review-cycle 2 appended" 0 $?

CYCLE_COUNT=$(python3 - "$JOURNAL" <<'PYTHON'
import sys, yaml
content = open(sys.argv[1]).read()
end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
print(sum(1 for a in fm["artifacts"] if a["type"] == "review-cycle"))
PYTHON
)
assert "manifest has 2 review-cycle artifacts after second record" 2 "$CYCLE_COUNT"

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && { echo "FAIL: no assertions ran — harness regression" >&2; exit 1; }
[ "$FAIL" -gt 0 ] && exit 1
exit 0
