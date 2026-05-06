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

# === Security regressions (cycle 2) ===

# SEC-2: journal file as a symlink must be rejected with exit 2. After
# `gh pr checkout` of a hostile fork, an attacker-staged `issue-N.md`
# pointing at `~/.ssh/id_rsa` would otherwise be read into the new journal
# body and committed. Defense is `os.open(O_NOFOLLOW)` in the Python block.
SEC2_DIR=$(mktemp -d -t flow-sec2.XXXXXX)
mkdir -p "$SEC2_DIR/.decisions"
echo "sentinel-content-do-not-leak" > "$SEC2_DIR/secret.txt"
ln -sf "$SEC2_DIR/secret.txt" "$SEC2_DIR/.decisions/issue-777.md"
( cd "$SEC2_DIR" && "$HELPER" --issue 777 --type specification --metadata by=test 2>/dev/null )
assert "SEC-2: journal symlink rejected with exit 2" 2 $?
# Confirm the symlink target was NOT read into a new journal body.
SEC2_LEAK=$(grep -l "sentinel-content-do-not-leak" "$SEC2_DIR/.decisions/" 2>/dev/null | head -1)
assert "SEC-2: secret content NOT exfiltrated to journal" "" "$SEC2_LEAK"
rm -rf "$SEC2_DIR"

# F1 (TOCTOU upgrade): lockfile as a symlink must be rejected with exit 2.
# Defense moved from bash `[ -L ]` (TOCTOU window) to Python
# `os.open(O_NOFOLLOW | O_CREAT)` (atomic ELOOP).
F1_DIR=$(mktemp -d -t flow-f1.XXXXXX)
mkdir -p "$F1_DIR/.decisions"
ln -sf /etc/passwd "$F1_DIR/.decisions/issue-778.md.lock"
( cd "$F1_DIR" && "$HELPER" --issue 778 --type specification --metadata by=test 2>/dev/null )
assert "F1: lockfile symlink rejected atomically" 2 $?
rm -rf "$F1_DIR"

# SEC-8: metadata pair containing a literal newline must be rejected. A
# crafted value would otherwise emit a YAML block scalar that downstream
# readers would surprise on (or, with a `:` in the value, parse as
# multiple keys).
SEC8_DIR=$(mktemp -d -t flow-sec8.XXXXXX)
( cd "$SEC8_DIR" && "$HELPER" --issue 779 --type specification --metadata $'evil=line1\nline2' 2>/dev/null )
assert "SEC-8: metadata newline rejected with exit 1" 1 $?
rm -rf "$SEC8_DIR"

# SEC-1: PYTHONSAFEPATH must be exported, preventing CWD-shadow imports.
# Without this, an attacker-shipped `./yaml.py` at the repo root after
# `gh pr checkout` would be loaded by the inline `import yaml` (full RCE).
SEC1_DIR=$(mktemp -d -t flow-sec1.XXXXXX)
cat > "$SEC1_DIR/yaml.py" <<'PYEOF'
import sys
print("ATTACKER-YAML-LOADED", file=sys.stderr)
sys.exit(99)
PYEOF
( cd "$SEC1_DIR" && "$HELPER" --issue 780 --type specification --metadata by=test 2>"$SEC1_DIR/stderr.log" )
SEC1_RC=$?
# `grep -c` exits 1 when 0 matches found; capture stdout count without the
# error path so the assertion compares a single integer.
SEC1_LEAK=$(grep -c "ATTACKER-YAML-LOADED" "$SEC1_DIR/stderr.log" 2>/dev/null) || SEC1_LEAK=0
assert "SEC-1: attacker yaml.py NOT loaded via sys.path" 0 "$SEC1_LEAK"
assert "SEC-1: journal-record completed normally despite attacker yaml.py" 0 "$SEC1_RC"
rm -rf "$SEC1_DIR"

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && { echo "FAIL: no assertions ran — harness regression" >&2; exit 1; }
[ "$FAIL" -gt 0 ] && exit 1
exit 0
