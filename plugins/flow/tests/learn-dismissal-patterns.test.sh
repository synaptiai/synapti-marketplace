# Tests for /flow:learn dismissal patterns — issue #214.
#
# Contract under test:
#   - learn.md Phase 1 gathers `dropped-finding` and `finding-dismissed`
#     artifacts from every journal manifest and prints counts. Before this,
#     review.md wrote dropped-finding artifacts "so /flow:learn can detect
#     repeated drop reasons" and learn.md had no consumer for them at all.
#   - Phase 2 has a Dismissal patterns category naming both types.
#   - Phase 3 states the two-instances / two-PRs threshold.
#   - Phase 4 writes exception-type proposals whose body is one table row.
#   - Phase 5 shows the type.
#
# Prereq: python3 + PyYAML (manifest parsing). SKIPS gracefully if absent.

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
LEARN_MD="$PLUGIN_DIR/commands/learn.md"
LEARN=$(cat "$LEARN_MD")

LD_CLEANUP=()
_ld_cleanup() { local p; for p in "${LD_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _ld_cleanup EXIT

_ld_block() {
  awk '/# DISMISSAL_ARTIFACTS_BLOCK_BEGIN/{f=1;next} /# DISMISSAL_ARTIFACTS_BLOCK_END/{f=0} f' "$LEARN_MD"
}

# --- source presence ---------------------------------------------------------
_flow_test_begin "Phase 2 has a Dismissal patterns category"
assert_contains "Dismissal patterns" "$LEARN" "the category exists"
assert_contains "finding-dismissed" "$LEARN" "it reads the finding-dismissed artifact"
assert_contains "dropped-finding" "$LEARN" "and the dropped-finding artifact"

_flow_test_begin "Phase 3 states the dismissal threshold"
# Two instances across two pull requests: one team arguing one finding down once
# is not a rule, it is a conversation.
# Asserted as two phrases: the markdown wraps, and a single-line regex over a
# wrapped paragraph fails for a reason that has nothing to do with the contract.
assert_contains "two or more pull requests" "$LEARN" "the pull-request half of the threshold is stated"
assert_match 'two or more[[:space:]]*dismissals|two or more dismissals' "$LEARN" \
  "and the instance half"

_flow_test_begin "Phase 4 writes exception-type proposals"
assert_contains "exception" "$LEARN" "the exception proposal type is named"
assert_match 'type: exception|`exception`' "$LEARN" "and written as a type"
assert_contains "review-exceptions.md" "$LEARN" "the target file is named"

_flow_test_begin "Phase 5 shows the proposal type"
assert_match 'skill .*enforcement .*exception|skill \| enforcement \| exception' "$LEARN" \
  "the summary table vocabulary includes exception"

# --- functional: the gathering block counts both artifact types ---------------
_flow_test_begin "Phase 1 counts dismissal artifacts across journals"
D=$(mktemp -d -t flow-ld.XXXXXX); LD_CLEANUP+=("$D")
mkdir -p "$D/.decisions"
# Two journals, both artifact types, across three pull requests.
cat > "$D/.decisions/issue-1.md" <<'YAML'
---
issue: 1
artifacts:
- type: finding-dismissed
  captured_at: '2026-09-01T00:00:00Z'
  pr: 10
  cycle: 1
  finding_id: F1
  category: correctness
  location: a.sh:1
  by: address
  reason: contradicts-claude-md
  evidence: the rule about explicit loops
- type: dropped-finding
  captured_at: '2026-09-01T00:00:00Z'
  pr: 10
  cycle: 1
  finding_id: F2
  facet: code-reviewer
  reason: both variants disagreed
---
# one
YAML
cat > "$D/.decisions/issue-2.md" <<'YAML'
---
issue: 2
artifacts:
- type: finding-dismissed
  captured_at: '2026-09-02T00:00:00Z'
  pr: 11
  cycle: 2
  finding_id: F7
  category: correctness
  location: b.sh:9
  by: address
  reason: contradicts-claude-md
  evidence: the same rule again
- type: specification
  captured_at: '2026-09-02T00:00:00Z'
---
# two
YAML

_ld_block > "$D/block.sh"
if [ ! -s "$D/block.sh" ]; then
  _flow_assert_fail "DISMISSAL_ARTIFACTS_BLOCK extracted empty — the block does not exist yet"
else
  OUT=$(cd "$D" && JOURNAL_DIR=".decisions" bash block.sh 2>&1)
  assert_contains "DISMISSED_COUNT=2" "$OUT" "both finding-dismissed artifacts are counted"
  assert_contains "DROPPED_COUNT=1" "$OUT" "and the dropped-finding artifact separately"
  assert_contains "STATE=ok" "$OUT" "the section reports a state"
  # The rows carry what clustering needs: the reason and the pull request.
  assert_match 'DISMISSED=.*reason=contradicts-claude-md' "$OUT" "a row carries its reason"
  assert_match 'DISMISSED=.*pr=10' "$OUT" "and the pull request it came from"
  assert_match 'DISMISSED=.*pr=11' "$OUT" "including the second pull request"
  # A specification artifact in the same manifest is not a dismissal.
  assert_not_contains "type=specification" "$OUT" "unrelated artifacts are not counted"
fi

_flow_test_begin "no dismissal artifacts is empty, not a failure"
D2=$(mktemp -d -t flow-ld2.XXXXXX); LD_CLEANUP+=("$D2")
mkdir -p "$D2/.decisions"
printf -- '---\nissue: 3\nartifacts: []\n---\n# three\n' > "$D2/.decisions/issue-3.md"
_ld_block > "$D2/block.sh"
if [ -s "$D2/block.sh" ]; then
  OUT2=$(cd "$D2" && JOURNAL_DIR=".decisions" bash block.sh 2>&1)
  assert_contains "STATE=empty" "$OUT2" "a project with no dismissals reports empty"
  assert_contains "DISMISSED_COUNT=0" "$OUT2" "with a zero count"
fi

_flow_test_begin "a journal that cannot be read is named, not skipped"
# A manifest nobody could parse is not a project with no dismissals. Counting
# it as zero would hide exactly the evidence this category exists to find.
D3=$(mktemp -d -t flow-ld3.XXXXXX); LD_CLEANUP+=("$D3")
mkdir -p "$D3/.decisions"
printf -- '---\n{ this: is: not: valid: yaml }\n---\n# broken\n' > "$D3/.decisions/issue-4.md"
_ld_block > "$D3/block.sh"
if [ -s "$D3/block.sh" ]; then
  OUT3=$(cd "$D3" && JOURNAL_DIR=".decisions" bash block.sh 2>&1)
  assert_contains "JOURNAL_UNREADABLE=" "$OUT3" "the unreadable journal is named"
  assert_contains "issue-4.md" "$OUT3" "with its path"
  assert_not_contains "STATE=empty" "$OUT3" \
    "and the section does not claim the project has no dismissals"
fi
