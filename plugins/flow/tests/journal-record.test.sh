# Tests for plugins/flow/bin/journal-record.sh.
#
# Contract (from the helper's header):
#   - Required args: --issue <N>, --type <artifact-type>.
#   - Optional: --metadata key=value (repeatable).
#   - Exit 0: artifact recorded.
#   - Exit 1: missing arg, invalid metadata, non-integer issue.
#   - Exit 2: infrastructure error (PyYAML missing, file unwritable, etc.).
#   - Writes YAML frontmatter at .decisions/issue-{N}.md (or settings-configured
#     directory) with atomic temp+rename, fcntl flock for concurrency, and
#     O_NOFOLLOW for symlink-attack rejection.
#   - Append-only: re-invocation appends to artifacts[]; never deduplicates.
#
# Prerequisites: python3 + PyYAML. Skipped (test PASS-with-skip-message) if
# either is missing — CI provides both, but a developer on a stripped system
# should see why the tests are no-ops rather than a cryptic exit.

HELPER="$REPO_ROOT/plugins/flow/bin/journal-record.sh"

# Reuse the cleanup pattern from cascade-resolve.test.sh: single trap, paths
# accumulate in an array, fail-fast mktemp.
JR_CLEANUP_PATHS=()
_jr_cleanup() {
  local p
  for p in "${JR_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _jr_cleanup EXIT

# See cascade-resolve.test.sh `_mktemp_or_die` for the kill-INT rationale —
# the caller invokes this via `DIR=$(_jr_mktemp_dir)` which puts us in a
# command-substitution subshell; a bare `exit 2` would only kill the subshell
# and let the test continue against an empty $DIR, writing the helper's
# output into REPO_ROOT instead of a scratch dir.
_jr_mktemp_dir() {
  local out
  out=$(mktemp -d -t journal-record.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "journal-record.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  JR_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Helper: run journal-record.sh inside a scratch dir with $CLAUDE_PLUGIN_ROOT
# set so the script's cascade-resolve.sh discovers `.decisions` as the journal
# dir (the default — no settings.json present means cascade-resolve falls back
# to the --default).
_run_journal() {
  local dir="$1"; shift
  (cd "$dir" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$@")
}

# Skip the whole suite gracefully if python3 + PyYAML are unavailable.
if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed (apt install python3-yaml / pip install pyyaml)"
  return 0
fi

# --- Test 1: missing --issue → exit 1
_flow_test_begin "missing --issue → exit 1"
DIR=$(_jr_mktemp_dir)
ERR=$(_run_journal "$DIR" --type review-cycle 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--issue is required" "$ERR" "stderr names the missing arg"

# --- Test 2: missing --type → exit 1
_flow_test_begin "missing --type → exit 1"
DIR=$(_jr_mktemp_dir)
ERR=$(_run_journal "$DIR" --issue 42 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--type is required" "$ERR" "stderr names the missing arg"

# --- Test 3: non-integer issue → exit 1
_flow_test_begin "non-integer --issue → exit 1"
DIR=$(_jr_mktemp_dir)
ERR=$(_run_journal "$DIR" --issue abc --type review-cycle 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "positive integer" "$ERR" "stderr explains integer requirement"

# --- Test 4: unknown argument → exit 1
_flow_test_begin "unknown argument → exit 1"
DIR=$(_jr_mktemp_dir)
ERR=$(_run_journal "$DIR" --bogus value --issue 42 --type t 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "unknown argument" "$ERR" "stderr names the unknown flag"

# --- Test 5: metadata with embedded newline → exit 1
_flow_test_begin "metadata with newline → exit 1"
DIR=$(_jr_mktemp_dir)
ERR=$(_run_journal "$DIR" --issue 42 --type review-cycle --metadata $'key=line1\nline2' 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "newline" "$ERR" "stderr names the safety reason"

# --- Test 6: happy path — creates a valid manifest with one artifact
_flow_test_begin "happy path: writes valid YAML manifest"
DIR=$(_jr_mktemp_dir)
ERR=$(_run_journal "$DIR" --issue 42 --type review-cycle \
  --metadata cycle=1 --metadata path=A --metadata findings_count=3 2>&1 >/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_file_exists "$DIR/.decisions/issue-42.md" "journal file created"
# Parse and inspect the YAML frontmatter — defense against silent malformed output.
# Use a heredoc (not `python3 -c '...'`) to avoid bash/python quoting collisions
# with f-string content.
PARSED=$(python3 - "$DIR/.decisions/issue-42.md" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    c = f.read()
assert c.startswith("---\n"), "no frontmatter"
end = c.find("\n---\n", 4)
fm = yaml.safe_load(c[4:end])
art = fm["artifacts"][0]
print("issue={} type={} cycle={} path={} findings_count={}".format(
    fm["issue"], art["type"], art["cycle"], art["path"], art["findings_count"]))
PYEOF
)
assert_equal "issue=42 type=review-cycle cycle=1 path=A findings_count=3" "$PARSED" "manifest fields parse correctly"

# --- Test 7: idempotent append — second invocation appends to artifacts[]
_flow_test_begin "append: second invocation adds a second artifact"
_run_journal "$DIR" --issue 42 --type stranger-test --metadata result=PASS --metadata task_count=5 >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "second invocation exits 0"
COUNT=$(python3 - "$DIR/.decisions/issue-42.md" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    c = f.read()
end = c.find("\n---\n", 4)
fm = yaml.safe_load(c[4:end])
print(len(fm["artifacts"]))
PYEOF
)
assert_equal "2" "$COUNT" "artifacts[] has 2 entries after append"

# --- Test 8: metadata type coercion (int, bool, comma-list, string)
_flow_test_begin "metadata coercion: int, bool, list, string"
DIR=$(_jr_mktemp_dir)
_run_journal "$DIR" --issue 7 --type test \
  --metadata count=42 \
  --metadata ready=true \
  --metadata items=a,b,c \
  --metadata note=hello >/dev/null 2>&1
TYPES=$(python3 - "$DIR/.decisions/issue-7.md" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    c = f.read()
end = c.find("\n---\n", 4)
art = yaml.safe_load(c[4:end])["artifacts"][0]
print("count={} ready={} items={}={} note={}".format(
    type(art["count"]).__name__,
    type(art["ready"]).__name__,
    type(art["items"]).__name__,
    art["items"],
    art["note"]))
PYEOF
)
assert_contains "count=int" "$TYPES" "numeric metadata coerced to int"
assert_contains "ready=bool" "$TYPES" "true/false coerced to bool"
assert_contains "items=list" "$TYPES" "comma-list coerced to list"
assert_contains "note=hello" "$TYPES" "plain string preserved"

# --- Test 9: symlink rejection — journal path is a pre-staged symlink
_flow_test_begin "symlink at journal path → exit 2 (O_NOFOLLOW)"
DIR=$(_jr_mktemp_dir)
mkdir -p "$DIR/.decisions"
TARGET_FILE="$DIR/elsewhere.md"
echo "untouched" > "$TARGET_FILE"
ln -s "$TARGET_FILE" "$DIR/.decisions/issue-99.md"
ERR=$(_run_journal "$DIR" --issue 99 --type test 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2 when journal is a symlink"
assert_contains "symlink" "$ERR" "stderr names the symlink refusal"
# Confirm the redirect target was NOT written to.
assert_equal "untouched" "$(cat "$TARGET_FILE")" "redirect target was not overwritten"
