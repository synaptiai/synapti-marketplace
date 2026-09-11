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

## Contract

Iron law: do the thing. Applies whenever the thing is not done. Returns the
thing, done. Permitted skips: none.

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
assert_contains "would transform" "$OUT" "dry-run describes the next step"
assert_contains "the promoted skill is well-formed" "$OUT" "and it ran the real transform rather than only validating"
assert_contains "feature/learn-promote-$UNIQUE_NAME" "$OUT" "dry-run names the planned branch"

# --- Test 12: target SKILL.md already exists → exit 1 (refuse to overwrite)
# bin/promote-proposal.sh:161-169 refuses when the target SKILL.md exists.
# Pre-create the target inside REPO_ROOT/plugins/flow/skills/learned/<NAME>/
# and verify the refusal. Cleanup the target via CLEANUP_PATHS so the test
# is re-runnable.
_flow_test_begin "target SKILL.md exists → exit 1 (refuse to overwrite)"
DIR=$(_pp_mktemp_dir)
NAME_EXISTS="test-fake-target-exists-$(date +%s)-$$-$RANDOM"
PROP="$DIR/valid-exists.md"
_write_valid_proposal "$PROP" "$NAME_EXISTS"
# Pre-stage the target as if a prior promotion already landed.
TARGET_DIR="$REPO_ROOT/plugins/flow/skills/learned/$NAME_EXISTS"
mkdir -p "$TARGET_DIR"
echo "pre-existing skill content" > "$TARGET_DIR/SKILL.md"
PP_CLEANUP_PATHS+=("$TARGET_DIR")
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1 when target SKILL.md exists"
assert_contains "refusing to overwrite" "$ERR" "stderr names the refusal"
# Confirm the existing SKILL.md was not touched.
assert_equal "pre-existing skill content" "$(cat "$TARGET_DIR/SKILL.md")" "existing SKILL.md was not overwritten"

# --- Test 13: target dir exists and is non-empty → exit 1 (refuse to clobber)
# bin/promote-proposal.sh:176-180 refuses when TARGET_DIR exists with any
# content other than the expected SKILL.md. This protects an in-progress
# hand-promotion (e.g., references/foo.md placed manually before SKILL.md)
# from being wiped on a python rewrite failure.
_flow_test_begin "target dir non-empty (no SKILL.md) → exit 1 (refuse to clobber)"
DIR=$(_pp_mktemp_dir)
NAME_DIRTY="test-fake-dirty-dir-$(date +%s)-$$-$RANDOM"
PROP="$DIR/valid-dirty.md"
_write_valid_proposal "$PROP" "$NAME_DIRTY"
TARGET_DIR="$REPO_ROOT/plugins/flow/skills/learned/$NAME_DIRTY"
mkdir -p "$TARGET_DIR/references"
echo "stray content" > "$TARGET_DIR/references/foo.md"
PP_CLEANUP_PATHS+=("$TARGET_DIR")
ERR=$("$HELPER" --proposal "$PROP" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1 when target dir is non-empty"
assert_contains "exists and is non-empty" "$ERR" "stderr names the clobber refusal"
# Confirm the stray content was not touched.
assert_equal "stray content" "$(cat "$TARGET_DIR/references/foo.md")" "stray content preserved"

# --- Tests 14-18: the proposal → skill transform
#
# The transform runs after the --dry-run exit, so every test above stops short
# of it and it shipped unexercised. Rather than re-implement it here (a copy
# would pass while the script was broken), extract the PYTHON heredoc from
# bin/promote-proposal.sh and run the shipped code against a temp file.
_flow_test_begin "the proposal → skill transform"
TRANSFORM_DIR=$(_pp_mktemp_dir)
TRANSFORM="$REPO_ROOT/plugins/flow/bin/lib/promote_transform.py"
if [ ! -f "$TRANSFORM" ]; then
  _flow_assert_fail "missing $TRANSFORM"
else
  _flow_assert_pass "the shipped transform is a file the tests can run directly"
fi

# Run the shipped transform. Sets TF_RC, TF_OUT, TF_BODY, TF_EVIDENCE as
# globals — a command substitution would discard the exit code the assertions
# need. PYTHONSAFEPATH matches what bin/promote-proposal.sh exports, so the
# tests do not give the code an environment production never gives it.
_pp_transform() {
  local src="$1"
  TF_TARGET="$TRANSFORM_DIR/target-$RANDOM.md"
  TF_EV="$TRANSFORM_DIR/evidence-$RANDOM.txt"
  TF_OUT=""; TF_RC=0; TF_BODY=""; TF_EVIDENCE=""
  # A silent cp failure leaves TF_BODY empty, and assert_not_contains passes on
  # an empty haystack — so every "... is removed" row would pass while the
  # transform was never run.
  if ! cp "$src" "$TF_TARGET"; then
    _flow_assert_fail "_pp_transform: cannot copy $src to $TF_TARGET"
    TF_RC=99
    return 1
  fi
  TF_OUT=$(PYTHONSAFEPATH=1 python3 "$TRANSFORM" "$TF_TARGET" "$TF_EV" 2>&1)
  TF_RC=$?
  TF_BODY=$(cat "$TF_TARGET")
  [ -f "$TF_EV" ] && TF_EVIDENCE=$(cat "$TF_EV")
  return 0
}

# Must-stay-silent: a well-formed proposal transforms cleanly.
_flow_test_begin "a well-formed proposal promotes to a skill"
GOOD="$TRANSFORM_DIR/good.md"
_write_valid_proposal "$GOOD" "test-fake-transform"
_pp_transform "$GOOD"
assert_exit 0 "$TF_RC" "exit 0"
assert_contains "status: promoted" "$TF_BODY" "status rewritten to promoted"
assert_contains "## Contract" "$TF_BODY" "the Contract survives"
assert_contains "## Knowledge" "$TF_BODY" "the Knowledge survives"
# Those two rows pass on an untransformed file, so they carry no power alone.
# This one cannot: the proposal has no `promoted:` key until the transform adds
# it, and the provenance keys are gone only after it runs.
assert_contains "promoted:" "$TF_BODY" "the transform actually ran on this file"
assert_not_contains "source-sessions" "$TF_BODY" "provenance frontmatter is removed too"
assert_contains "source-sessions" "$TF_EVIDENCE" "and lands in the removed-material block"
assert_not_contains "## Pattern Detected" "$TF_BODY" "Pattern Detected is removed"
assert_not_contains "## Promotion Checklist" "$TF_BODY" "Promotion Checklist is removed"
assert_not_contains "## Evidence" "$TF_BODY" "Evidence is removed"

# The evidence is moved, not destroyed — losing the audit trail would be a
# worse outcome than leaving it in the skill.
_flow_test_begin "removed sections are recorded, not discarded"
assert_contains "## Evidence" "$TF_EVIDENCE" "Evidence lands in the evidence file"
assert_contains "## Pattern Detected" "$TF_EVIDENCE" "Pattern Detected lands in the evidence file"
assert_contains "Cite one journal entry" "$TF_EVIDENCE" "with its content intact"

# Must-fire: a proposal whose Contract is not first.
_flow_test_begin "a proposal without a leading Contract is refused"
NOCONTRACT="$TRANSFORM_DIR/no-contract.md"
_write_valid_proposal "$NOCONTRACT" "test-fake-nocontract"
python3 - "$NOCONTRACT" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("## Contract", "## Preamble", 1))
PY
_pp_transform "$NOCONTRACT"
assert_exit 1 "$TF_RC" "exit 1"
assert_contains "expected 'Contract'" "$TF_OUT" "stderr names the missing Contract"

# Must-fire: an over-budget body. A promoted skill is loaded into context like
# any other, so an unbounded one costs every session that triggers it.
_flow_test_begin "an over-budget body is refused"
FAT="$TRANSFORM_DIR/fat.md"
_write_valid_proposal "$FAT" "test-fake-fat"
python3 - "$FAT" <<'PY'
import sys
p = sys.argv[1]
with open(p, "a") as f:
    f.write("\n## Knowledge\n\n" + ("filler " * 700) + "\n")
PY
_pp_transform "$FAT"
assert_exit 1 "$TF_RC" "exit 1"
assert_contains "max 600" "$TF_OUT" "stderr names the word budget"

# Must-fire: an over-long Contract. The Contract is what a dispatched skill
# shows before its body loads, so a bloated one defeats the point.
_flow_test_begin "an over-long Contract is refused"
LONGC="$TRANSFORM_DIR/long-contract.md"
_write_valid_proposal "$LONGC" "test-fake-longcontract"
python3 - "$LONGC" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("Permitted skips: none.", "Permitted skips: none. " + ("word " * 150), 1))
PY
_pp_transform "$LONGC"
assert_exit 1 "$TF_RC" "exit 1"
assert_contains "max 120" "$TF_OUT" "stderr names the Contract budget"


# --- Test 19: a `## ` line inside a fenced block is not a section boundary
#
# The regression this guards: the transform split on the fenced heading, moved
# the rest of ## Knowledge (including the closing fence) into the evidence file,
# and wrote a skill ending mid-fence — exit 0, "promoted" on stdout. The shape
# checks all still passed, because the word count went DOWN and the first H2 was
# still Contract. Only an assertion about content fidelity catches it.
_flow_test_begin "a fenced heading does not split the section"
FENCED="$TRANSFORM_DIR/fenced.md"
_write_valid_proposal "$FENCED" "test-fake-fenced"
python3 - "$FENCED" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("""## Knowledge

Do the thing.""", """## Knowledge

Proposals often quote the section layout:

```markdown
## Evidence

- not a real citation
```

KEEP-THIS-SENTENCE after the fence.""", 1)
open(p, "w").write(s)
PY
_pp_transform "$FENCED"
assert_exit 0 "$TF_RC" "exit 0"
assert_contains "KEEP-THIS-SENTENCE" "$TF_BODY" "prose after the fenced heading stays in the skill"
assert_not_contains "KEEP-THIS-SENTENCE" "$TF_EVIDENCE" "and is not relocated into the commit message"
assert_contains "not a real citation" "$TF_BODY" "the fenced example survives intact"
_flow_test_begin "the promoted body has no unterminated fence"
FENCE_COUNT=$(printf '%s\n' "$TF_BODY" | grep -c '^```' || true)
if [ $((FENCE_COUNT % 2)) -eq 0 ]; then
  _flow_assert_pass "$FENCE_COUNT fence markers — balanced"
else
  _flow_assert_fail "$FENCE_COUNT fence markers — the body ends inside a code fence"
fi

# --- Test 20: the validator and the transform agree on what a section is
_flow_test_begin "a near-miss section name is refused, not silently shipped"
NEARMISS="$TRANSFORM_DIR/near-miss.md"
_write_valid_proposal "$NEARMISS" "test-fake-nearmiss"
python3 - "$NEARMISS" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("## Evidence", "## Evidence (journal citations)", 1))
PY
ERR=$("$HELPER" --proposal "$NEARMISS" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "missing required body sections" "$ERR" "the substring lookalike no longer satisfies the validator"

_flow_test_begin "an H3 does not satisfy a required H2"
H3="$TRANSFORM_DIR/h3.md"
_write_valid_proposal "$H3" "test-fake-h3"
python3 - "$H3" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("## Verification", "### Verification", 1))
PY
ERR=$("$HELPER" --proposal "$H3" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "Verification" "$ERR" "the H3 is named as missing"

_flow_test_begin "a proposal ending inside a fence is refused"
UNTERM="$TRANSFORM_DIR/unterminated.md"
_write_valid_proposal "$UNTERM" "test-fake-unterm"
printf '\n```\nopen forever\n' >> "$UNTERM"
ERR=$("$HELPER" --proposal "$UNTERM" --dry-run 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "unterminated code fence" "$ERR" "stderr names the open fence"

# --- Test 21: the budget is measured on the promoted body, not the proposal
#
# A mutant that counted words BEFORE stripping the proposal-only sections
# survived the whole suite, because the fixture's removed sections are only a
# few words each. A real proposal carries paragraphs of Pattern Detected and
# Evidence, so a pre-strip gate would refuse a skill that is well under budget.
# This fixture makes the two measurements differ by more than the budget.
_flow_test_begin "the word budget is measured after the reviewer sections come out"
FAT_EVIDENCE="$TRANSFORM_DIR/fat-evidence.md"
_write_valid_proposal "$FAT_EVIDENCE" "test-fake-fatevidence"
python3 - "$FAT_EVIDENCE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# 700 words of Evidence: pre-strip the body is far over 600, post-strip it is
# the fixture's own ~30. Only a post-strip measurement accepts this.
s = s.replace("Cite one journal entry.", "journal " * 700, 1)
open(p, "w").write(s)
PY
_pp_transform "$FAT_EVIDENCE"
assert_exit 0 "$TF_RC" "accepted: the promoted body is small even though the proposal is not"
assert_not_contains "journal journal" "$TF_BODY" "the bulk is not in the skill"
assert_contains "journal journal" "$TF_EVIDENCE" "it is in the removed material"

# --- Test 22: the budget boundary
#
# Both comparisons could be flipped from `>` to `>=` and every test still
# passed — no fixture sat on the boundary. These two do.
_flow_test_begin "exactly at the budget passes, one word over fails"
BOUNDARY="$TRANSFORM_DIR/boundary.md"
python3 - "$BOUNDARY" "$REPO_ROOT/plugins/flow/bin/lib" <<'PY'
import sys

HEAD = """---
name: "test-fake-boundary"
description: "[flow-learned] boundary fixture"
source-sessions:
  - "2026-05-18 test session"
evidence-count: 1
status: proposal
proposed: "2026-05-18"
---

# Boundary

## Contract

"""
TAIL = """

## Pattern Detected

p

## Evidence

e

## Verification

v

## Promotion Checklist

- [ ] Reviewed
"""


def build(body_words):
    # Headings and the fixed words below count toward the body budget, so the
    # filler is solved for rather than guessed: build, measure, adjust.
    filler = "word " * body_words
    return HEAD + "contract words here.\n\n## Knowledge\n\n" + filler + TAIL


def body_of(text):
    end = text.find("\n---\n", 4)
    return text[end + 5:]


# Remove the sections the transform removes, then count, so the target is the
# promoted body's length rather than the proposal's.
DROP = ("Pattern Detected", "Evidence", "Promotion Checklist")
sys.path.insert(0, sys.argv[2])
import proposal_sections as ps


def promoted_words(text):
    pre, secs = ps.split(body_of(text))
    kept = [x for x in secs if x.title not in DROP]
    return len(ps.render(pre, kept).split())


n = 500
for _ in range(4000):
    w = promoted_words(build(n))
    if w == 600:
        break
    n += 600 - w
else:
    print("could not land on 600", file=sys.stderr)
    sys.exit(2)

open(sys.argv[1], "w").write(build(n))
open(sys.argv[1] + ".over", "w").write(build(n + 1))
PY
if [ ! -s "$BOUNDARY" ] || [ ! -s "$BOUNDARY.over" ]; then
  _flow_assert_fail "the boundary fixture was not built — nothing below tests the boundary"
fi
_pp_transform "$BOUNDARY"
assert_exit 0 "$TF_RC" "a body of exactly 600 words is accepted"
assert_contains "600 body words" "$TF_OUT" "and it really is 600"
_pp_transform "$BOUNDARY.over"
assert_exit 1 "$TF_RC" "601 words is refused"
assert_contains "601 words (max 600)" "$TF_OUT" "and the message names the boundary"

# --- Test 23: the Contract budget boundary
#
# Flipping `>` to `>=` on the Contract comparison survived every test: no
# fixture had a Contract of exactly 120 words. These two do.
_flow_test_begin "a Contract of exactly 120 words passes, 121 fails"
CBOUND="$TRANSFORM_DIR/contract-boundary.md"
python3 - "$CBOUND" <<'PY'
import sys

TEMPLATE = """---
name: "test-fake-cboundary"
description: "[flow-learned] contract boundary fixture"
source-sessions:
  - "2026-05-18 test session"
evidence-count: 1
status: proposal
proposed: "2026-05-18"
---

# Contract boundary

## Contract

{contract}

## Knowledge

k

## Pattern Detected

p

## Evidence

e

## Verification

v

## Promotion Checklist

- [ ] Reviewed
"""

# The Contract section's word count is the words between its heading and the
# next H2, which is exactly the filler plus nothing else.
at = TEMPLATE.format(contract="word " * 120)
over = TEMPLATE.format(contract="word " * 121)
open(sys.argv[1], "w").write(at)
open(sys.argv[1] + ".over", "w").write(over)
PY
_pp_transform "$CBOUND"
assert_exit 0 "$TF_RC" "a Contract of exactly 120 words is accepted"
_pp_transform "$CBOUND.over"
assert_exit 1 "$TF_RC" "121 words is refused"
assert_contains "121 words (max 120)" "$TF_OUT" "and the message names the boundary"
