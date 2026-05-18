# Tests for plugins/flow/bin/promote-proposal.sh.
#
# Contract (from the helper's header):
#   Usage: promote-proposal.sh --proposal <path> [--dry-run]
#
#   Exit 0: validation passed (or dry-run completed).
#   Exit 1: validation failed (missing fields, bad status, invalid name, etc.).
#   Exit 2: infrastructure error (file not found, not in git repo, etc.).
#
# Tests focus on the validation path (using --dry-run to short-circuit before
# the git/gh mutating steps). The gh-invoking branches are intentionally NOT
# exercised — testing them properly requires a mock-gh stub plus a throwaway
# branch, which is heavier than smoke-test scope.
#
# Prerequisites: python3 + PyYAML + git. Skipped gracefully if absent.

HELPER="$REPO_ROOT/plugins/flow/bin/promote-proposal.sh"

PP_CLEANUP_PATHS=()
_pp_cleanup() {
  local p
  for p in "${PP_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _pp_cleanup EXIT

# See cascade-resolve.test.sh `_mktemp_or_die` for the kill-INT rationale —
# bare `exit 2` would only kill the command-substitution subshell, leaving
# the test running against an empty DIR.
_pp_mktemp_dir() {
  local out
  out=$(mktemp -d -t promote-proposal.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "promote-proposal.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  PP_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Build a valid proposal file with the given name. Caller can override fields
# by passing --status / --name etc. — we keep it minimal.
_write_valid_proposal() {
  local path="$1" name="${2:-test-fake-proposal}" status="${3:-proposal}"
  cat > "$path" <<PROPOSAL
---
name: "$name"
description: "[flow-learned] Test proposal — never promoted in practice."
source-sessions:
  - "2026-05-18 test session"
evidence-count: 1
status: $status
proposed: "2026-05-18"
---

# Test fake proposal

## Pattern Detected

Something keeps happening.

## Knowledge

Do the thing.

## Evidence

Cite one journal entry.

## Verification

Check the thing.

## Promotion Checklist

- [ ] Reviewed
PROPOSAL
}

# Skip if python3 / PyYAML / git unavailable.
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
if ! command -v git >/dev/null 2>&1; then
  _flow_test_begin "git prerequisite"
  _flow_assert_pass "SKIP: git not installed"
  return 0
fi

# --- Test 1: missing --proposal → exit 1
_flow_test_begin "missing --proposal → exit 1"
ERR=$("$HELPER" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--proposal is required" "$ERR" "stderr names the missing arg"

# --- Test 2: proposal file not found → exit 2
_flow_test_begin "proposal file not found → exit 2"
ERR=$("$HELPER" --proposal /nonexistent/path.md 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "not found" "$ERR" "stderr names the missing file"

# --- Test 3: unknown argument → exit 1
_flow_test_begin "unknown argument → exit 1"
ERR=$("$HELPER" --bogus value 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "unknown argument" "$ERR" "stderr names the unknown flag"

# --- Test 4: missing YAML frontmatter → exit 1
_flow_test_begin "no frontmatter → exit 1"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/no-frontmatter.md"
printf 'Just a body, no frontmatter.\n' > "$PROP"
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "missing YAML frontmatter" "$ERR" "stderr names the missing frontmatter"

# --- Test 5: malformed YAML → exit 1
_flow_test_begin "malformed YAML frontmatter → exit 1"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/bad-yaml.md"
cat > "$PROP" <<'BAD'
---
this is: [unclosed
---

body
BAD
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "malformed YAML frontmatter" "$ERR" "stderr names YAML parse failure"

# --- Test 6: missing required field → exit 1
_flow_test_begin "missing required frontmatter field → exit 1"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/missing-field.md"
cat > "$PROP" <<'INCOMPLETE'
---
name: test-fake
description: "[flow-learned] x"
status: proposal
---

# fake

## Pattern Detected
## Knowledge
## Evidence
## Verification
## Promotion Checklist
INCOMPLETE
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "missing required frontmatter fields" "$ERR" "stderr names the missing fields"

# --- Test 7: status != "proposal" → exit 1
_flow_test_begin "status != 'proposal' → exit 1"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/wrong-status.md"
_write_valid_proposal "$PROP" "test-fake-proposal" "promoted"
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "status must be 'proposal'" "$ERR" "stderr names the wrong-status reason"

# --- Test 8: invalid kebab-case name → exit 1
_flow_test_begin "invalid kebab-case name → exit 1"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/bad-name.md"
_write_valid_proposal "$PROP" "BadCamelCase"
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "kebab-case" "$ERR" "stderr names the kebab-case requirement"

# --- Test 9: missing required body section → exit 1
_flow_test_begin "missing required body section → exit 1"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/missing-section.md"
cat > "$PROP" <<'INCOMPLETE'
---
name: test-fake-proposal
description: "[flow-learned] x"
source-sessions:
  - "2026-05-18"
evidence-count: 1
status: proposal
proposed: "2026-05-18"
---

# Body

## Pattern Detected

x
INCOMPLETE
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "missing required body sections" "$ERR" "stderr names the missing sections"

# --- Test 10: plain-ASCII path passes the newline-rejection safety check
# The helper's newline/CR rejection branch (bin/promote-proposal.sh:58-63)
# guards against programmatically-built $PROPOSAL paths containing embedded
# newlines (POSIX permits `\n` in filenames; bash CAN pass them via array
# expansion). Directly testing the rejection branch via a shell-arg-passed
# newline-bearing path is awkward because the bash command line accepts the
# newline, then the script's `[ ! -f "$PROPOSAL" ]` check at line 52 fires
# FIRST when the test fixture creates a file with a `\n` in its name (the
# subsequent open hits the kernel's path-resolution which usually rejects).
#
# DELIBERATE GAP: the rejection branch is not directly exercised here. This
# test instead verifies the inverse — that a plain-ASCII path does NOT
# false-positive — which is the regression direction most likely to matter
# (a future tightening of the guard breaking innocent paths). A direct
# rejection-branch test would need the helper to expose the guard as a
# function, sourceable from a unit test; that refactor is out of scope.
_flow_test_begin "plain-ASCII path does not trigger newline-rejection guard"
DIR=$(_pp_mktemp_dir)
PROP="$DIR/plain.md"
_write_valid_proposal "$PROP"
OUT=$("$HELPER" --proposal "$PROP" --dry-run 2>&1)
EXIT=$?
# Either DRY-RUN passes (exit 0) or it hits target-already-exists (exit 1).
# We only care that the safety check did NOT trigger.
assert_not_contains "newline/carriage-return" "$OUT" "no spurious newline rejection for plain path"

# --- Test 11: --dry-run with a valid proposal → exit 0 (when the learned/
# target does not already exist) OR exit 1 (target exists). Either way, we
# expect a deterministic outcome, NOT exit 2 (infrastructure error). Use a
# random name to avoid target-already-exists collisions with real skills.
_flow_test_begin "--dry-run valid proposal → no infrastructure error"
DIR=$(_pp_mktemp_dir)
UNIQUE_NAME="test-fake-$(date +%s)-$$"
PROP="$DIR/valid.md"
_write_valid_proposal "$PROP" "$UNIQUE_NAME"
OUT=$("$HELPER" --proposal "$PROP" --dry-run 2>&1)
EXIT=$?
# Exit must be 0 — random name guarantees the target dir does not exist.
assert_exit 0 "$EXIT" "exit 0 for dry-run with valid never-before-seen name"
assert_contains "DRY-RUN: validation passed for '$UNIQUE_NAME'" "$OUT" "dry-run prints the validated name"
assert_contains "would copy" "$OUT" "dry-run describes the next step"
assert_contains "feature/learn-promote-$UNIQUE_NAME" "$OUT" "dry-run names the planned branch"
