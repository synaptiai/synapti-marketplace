# Tests for plugins/flow/bin/cascade-resolve.sh.
#
# Contract under test (from cascade-resolve.sh header):
#   - Resolves a jq expression against four settings sources in precedence
#     order: local > project > user > plugin.
#   - --default fallback when no source resolves a non-empty value.
#   - --compact preserves JSON quoting (uses jq -c instead of jq -r).
#   - Exit 2 on infrastructure errors (jq missing without --default, missing
#     expression, unknown flag).
#   - Per-source jq parse error → stderr WARN + skip + continue (not abort).
#
# Each test sets up an isolated CASCADE_DIR via mktemp, prepends it to the
# search by pointing CLAUDE_PLUGIN_ROOT and overriding HOME, then asserts on
# stdout/stderr/exit. Cleanup is via trap so a failed assertion doesn't
# leak temp dirs.

HELPER="$REPO_ROOT/plugins/flow/bin/cascade-resolve.sh"

# Single shared scratch root for all tests. Each test creates its own
# subdirectory inside it so isolation is per-test.
SCRATCH_ROOT=$(mktemp -d -t cascade-resolve.tests.XXXXXX)
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

_make_scratch() {
  local name="$1"
  local dir="$SCRATCH_ROOT/$name"
  mkdir -p "$dir/.claude" "$dir/plugins/flow"
  printf '%s\n' "$dir"
}

# --- Test 1: precedence — local beats project beats user beats plugin
_flow_test_begin "precedence: local > project > user > plugin"
DIR=$(_make_scratch precedence)
echo '{"journal": {"dir": "from-plugin"}}'  > "$DIR/plugins/flow/settings.json"
echo '{"journal": {"dir": "from-user"}}'    > "$DIR/user-settings.json"
echo '{"journal": {"dir": "from-project"}}' > "$DIR/.claude/settings.flow.json"
echo '{"journal": {"dir": "from-local"}}'   > "$DIR/.claude/settings.flow.local.json"
(
  cd "$DIR"
  HOME=. CLAUDE_PLUGIN_ROOT="plugins/flow" \
    "$HELPER" '.journal.dir // empty' 2>/dev/null
) > "$DIR/out.txt"
EXIT=$?
OUT=$(cat "$DIR/out.txt")
assert_equal "from-local" "$OUT" "local wins"
assert_exit 0 "$EXIT" "exit 0"

# Remove local; project wins.
rm "$DIR/.claude/settings.flow.local.json"
OUT=$(cd "$DIR" && HOME=. CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-project" "$OUT" "project wins after local removed"

# Remove project; user wins. HOME points to the test dir; user settings live
# at $HOME/.claude/settings.flow.json.
rm "$DIR/.claude/settings.flow.json"
mkdir -p "$DIR/home/.claude"
echo '{"journal": {"dir": "from-user"}}' > "$DIR/home/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-user" "$OUT" "user wins after project removed"

# Remove user; plugin wins.
rm "$DIR/home/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-plugin" "$OUT" "plugin wins after user removed"

# --- Test 2: --default fallback when nothing resolves
_flow_test_begin "default fallback when no source has key"
DIR=$(_make_scratch default)
echo '{"unrelated": true}' > "$DIR/plugins/flow/settings.json"
OUT=$(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
EXIT=$?
assert_equal ".decisions" "$OUT" "default emitted"
assert_exit 0 "$EXIT" "default exits 0"

# --- Test 3: no default + no resolution → empty stdout + exit 0
_flow_test_begin "no default, no resolution → empty stdout exit 0"
DIR=$(_make_scratch nodefault)
echo '{}' > "$DIR/plugins/flow/settings.json"
OUT=$(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' 2>/dev/null)
EXIT=$?
assert_equal "" "$OUT" "empty stdout"
assert_exit 0 "$EXIT" "exit 0"

# --- Test 4: --compact preserves JSON quoting
_flow_test_begin "--compact preserves JSON quoting"
DIR=$(_make_scratch compact)
echo '{"k": "v"}' > "$DIR/plugins/flow/settings.json"
RAW=$(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" '.k' 2>/dev/null)
CMP=$(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --compact '.k' 2>/dev/null)
# jq -r drops the surrounding double-quotes; jq -c preserves them.
assert_equal "v" "$RAW" "raw mode strips quotes"
assert_equal '"v"' "$CMP" "compact mode preserves quotes"

# --- Test 5: missing expression → exit 2
_flow_test_begin "missing expression → exit 2"
OUT=$(cd "$SCRATCH_ROOT" && HOME="$SCRATCH_ROOT" "$HELPER" 2>&1)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "missing <jq-expression>" "$OUT" "stderr names the problem"

# --- Test 6: unknown flag → exit 2
_flow_test_begin "unknown flag → exit 2"
OUT=$(cd "$SCRATCH_ROOT" && HOME="$SCRATCH_ROOT" "$HELPER" --bogus '.x' 2>&1)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "unknown flag" "$OUT" "stderr names the unknown flag"

# --- Test 7: per-source parse error → stderr WARN + skip + continue
# Project has a syntax-broken JSON; plugin has the correct value. Helper
# should WARN about the project, skip it, and resolve from plugin.
_flow_test_begin "parse error per-source → WARN + skip + continue"
DIR=$(_make_scratch parse_err)
echo '{not valid json' > "$DIR/.claude/settings.flow.json"
echo '{"journal": {"dir": "from-plugin"}}' > "$DIR/plugins/flow/settings.json"
STDOUT_TMP=$(mktemp -t cascade.so.XXXXXX)
STDERR_TMP=$(mktemp -t cascade.se.XXXXXX)
(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' >"$STDOUT_TMP" 2>"$STDERR_TMP")
EXIT=$?
OUT=$(cat "$STDOUT_TMP"); ERR=$(cat "$STDERR_TMP")
rm -f "$STDOUT_TMP" "$STDERR_TMP"
assert_equal "from-plugin" "$OUT" "fell through to plugin"
assert_exit 0 "$EXIT" "exit 0 despite bad JSON"
assert_contains "WARN: failed to parse" "$ERR" "stderr WARN was emitted"
assert_contains "settings.flow.json" "$ERR" "WARN names the failing source"

# --- Test 8: --default emits even when jq is missing (graceful degrade)
# We need a PATH that finds /bin/bash and the POSIX utils the helper uses
# (mktemp, tr, cut, rm) but NOT jq. macOS Sequoia ships jq in /usr/bin and
# Homebrew puts it in /opt/homebrew/bin or /usr/local/bin, so neither /bin
# nor /usr/bin is safe to pass through. Build a shadow PATH with symlinks
# to every needed tool except jq — portable across macOS and CI runners.
SHADOW=$(mktemp -d -t cascade.shadow.XXXXXX)
for tool in bash mktemp tr cut rm sh env cat; do
  T=$(command -v "$tool" 2>/dev/null) || continue
  ln -s "$T" "$SHADOW/$tool"
done
NO_JQ_PATH="$SHADOW"
trap 'rm -rf "$SCRATCH_ROOT" "$SHADOW"' EXIT

_flow_test_begin "jq missing + --default → emit default, exit 0"
DIR=$(_make_scratch nojq)
echo '{"k": "v"}' > "$DIR/plugins/flow/settings.json"
STDOUT_TMP=$(mktemp -t cascade.nojq.so.XXXXXX)
STDERR_TMP=$(mktemp -t cascade.nojq.se.XXXXXX)
(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" PATH="$NO_JQ_PATH" \
  /bin/bash "$HELPER" --default "fallback" '.k' \
  >"$STDOUT_TMP" 2>"$STDERR_TMP")
EXIT=$?
OUT=$(cat "$STDOUT_TMP"); ERR=$(cat "$STDERR_TMP")
rm -f "$STDOUT_TMP" "$STDERR_TMP"
assert_equal "fallback" "$OUT" "default emitted on stdout"
assert_exit 0 "$EXIT" "exit 0 with --default"
assert_contains "jq not installed" "$ERR" "stderr WARN about missing jq"

# --- Test 9: jq missing + no --default → exit 2
_flow_test_begin "jq missing + no default → exit 2"
DIR=$(_make_scratch nojq2)
echo '{"k": "v"}' > "$DIR/plugins/flow/settings.json"
STDERR_TMP=$(mktemp -t cascade.nojq2.se.XXXXXX)
(cd "$DIR" && HOME="$DIR" CLAUDE_PLUGIN_ROOT="plugins/flow" PATH="$NO_JQ_PATH" \
  /bin/bash "$HELPER" '.k' 2>"$STDERR_TMP")
EXIT=$?
ERR=$(cat "$STDERR_TMP")
rm -f "$STDERR_TMP"
assert_exit 2 "$EXIT" "exit 2 without --default"
assert_contains "jq not installed" "$ERR" "stderr WARN about missing jq"
