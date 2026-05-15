#!/usr/bin/env bash
# cascade-resolve.test.sh — unit tests for plugins/flow/bin/cascade-resolve.sh
#
# Focuses on the F1 tilde-expansion contract, HOME-unset warning, and cascade
# precedence. Pure jq operations — no gh stub needed.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$TESTS_DIR/../bin/cascade-resolve.sh"

_setup_cascade() {
  SCRATCH_HOME=$(mktemp -d -t flow-cascade-home.XXXXXX)
  SCRATCH_CWD=$(mktemp -d -t flow-cascade-cwd.XXXXXX)
  PLUGIN_DIR=$(mktemp -d -t flow-cascade-plugin.XXXXXX)
  export HOME="$SCRATCH_HOME"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  cd "$SCRATCH_CWD"
}

_teardown_cascade() {
  rm -rf "$SCRATCH_HOME" "$SCRATCH_CWD" "$PLUGIN_DIR" 2>/dev/null
  unset CLAUDE_PLUGIN_ROOT
}

# ─── Test 1: F1 — bare '~' expands to $HOME ─────────────────────────────────
_begin "F1: bare '~' value expands to \$HOME in raw mode"
_setup_cascade
mkdir -p .claude
echo '{"learning":{"proposalDir":"~"}}' > .claude/settings.flow.local.json
RESULT=$(bash "$HELPER" --default "/fallback" '.learning.proposalDir // empty')
assert_equal "$HOME" "$RESULT" "bare ~ must expand to \$HOME"
_teardown_cascade

# ─── Test 2: F1 — '~/path' expands to $HOME/path ────────────────────────────
_begin "F1: '~/path' expands to \$HOME/path in raw mode"
_setup_cascade
mkdir -p .claude
echo '{"learning":{"proposalDir":"~/.claude/flow-proposals"}}' > .claude/settings.flow.local.json
RESULT=$(bash "$HELPER" --default "/fallback" '.learning.proposalDir // empty')
assert_equal "$HOME/.claude/flow-proposals" "$RESULT" "~/foo must expand to \$HOME/foo"
_teardown_cascade

# ─── Test 3: F1 regression guard — non-tilde unchanged ──────────────────────
_begin "F1: non-tilde string passes through unchanged"
_setup_cascade
mkdir -p .claude
echo '{"journal":{"dir":"/var/log/flow"}}' > .claude/settings.flow.local.json
RESULT=$(bash "$HELPER" --default "/fallback" '.journal.dir // empty')
assert_equal "/var/log/flow" "$RESULT" "absolute path should not be touched"
_teardown_cascade

# ─── Test 4: F1 — middle-tilde NOT expanded (only leading) ──────────────────
_begin "F1: tilde in middle of string is NOT expanded (only leading ~ or ~/)"
_setup_cascade
mkdir -p .claude
echo '{"weird":"/foo/~/bar"}' > .claude/settings.flow.local.json
RESULT=$(bash "$HELPER" --default "/fallback" '.weird // empty')
assert_equal "/foo/~/bar" "$RESULT" "middle tilde must not expand"
_teardown_cascade

# ─── Test 5: F1 contract — compact mode does NOT expand tilde ───────────────
_begin "F1: --compact mode preserves '~' literally (no expansion)"
_setup_cascade
mkdir -p .claude
echo '{"learning":{"proposalDir":"~/.claude"}}' > .claude/settings.flow.local.json
RESULT=$(bash "$HELPER" --compact --default '"/fallback"' '.learning.proposalDir // empty')
# In --compact (jq -c), the result preserves JSON quoting: "~/.claude"
assert_equal '"~/.claude"' "$RESULT" "compact mode must NOT expand tilde"
_teardown_cascade

# ─── Test 6: HOME-unset warning ─────────────────────────────────────────────
_begin "C19: HOME unset → WARN to stderr in raw mode"
_setup_cascade
mkdir -p .claude
echo '{"dir":"/x"}' > .claude/settings.flow.local.json
# Unset HOME for this invocation only
WARNS=$(env -u HOME bash "$HELPER" --default "/fb" '.dir // empty' 2>&1 >/dev/null)
assert_contains "HOME env unset" "$WARNS" "HOME unset should emit WARN"
assert_contains "/nonexistent" "$WARNS" "WARN should mention /nonexistent fallback"
_teardown_cascade

# ─── Test 7: HOME='' → /nonexistent expansion sentinel ──────────────────────
_begin "C19: empty HOME → '~/' expands to /nonexistent/ in raw mode"
_setup_cascade
mkdir -p .claude
echo '{"dir":"~/foo"}' > .claude/settings.flow.local.json
RESULT=$(env -u HOME bash "$HELPER" --default "/fb" '.dir // empty' 2>/dev/null)
assert_equal "/nonexistent/foo" "$RESULT" "empty HOME with ~/ should produce /nonexistent/ sentinel"
_teardown_cascade

# ─── Test 8: --default value tilde-expanded ─────────────────────────────────
_begin "F1: --default value is tilde-expanded when no source resolves"
_setup_cascade
# No settings files at all — default kicks in
RESULT=$(bash "$HELPER" --default "~/.flow-defaults" '.nonexistent // empty')
assert_equal "$HOME/.flow-defaults" "$RESULT" "--default value should be tilde-expanded"
_teardown_cascade

# ─── Test 9: cascade precedence — local > project ───────────────────────────
_begin "Cascade: local (.claude/settings.flow.local.json) wins over project (.claude/settings.flow.json)"
_setup_cascade
mkdir -p .claude
echo '{"k":"from-project"}' > .claude/settings.flow.json
echo '{"k":"from-local"}' > .claude/settings.flow.local.json
RESULT=$(bash "$HELPER" --default "fb" '.k // empty')
assert_equal "from-local" "$RESULT" "local should beat project in cascade"
_teardown_cascade

# ─── Test 10: cascade precedence — project > user ───────────────────────────
_begin "Cascade: project wins over user when local absent"
_setup_cascade
mkdir -p .claude "$HOME/.claude"
echo '{"k":"from-project"}' > .claude/settings.flow.json
echo '{"k":"from-user"}' > "$HOME/.claude/settings.flow.json"
RESULT=$(bash "$HELPER" --default "fb" '.k // empty')
assert_equal "from-project" "$RESULT" "project should beat user when local absent"
_teardown_cascade

# ─── Test 11: cascade precedence — plugin fallback ──────────────────────────
_begin "Cascade: plugin settings.json used when local/project/user all absent"
_setup_cascade
echo '{"k":"from-plugin"}' > "$CLAUDE_PLUGIN_ROOT/settings.json"
RESULT=$(bash "$HELPER" --default "fb" '.k // empty')
assert_equal "from-plugin" "$RESULT" "plugin tier used when higher tiers absent"
_teardown_cascade

# ─── Test 12: malformed JSON in one source → WARN, fall through ─────────────
_begin "Malformed JSON in local → WARN, fall through to next source"
_setup_cascade
mkdir -p .claude
echo '{not valid json' > .claude/settings.flow.local.json
echo '{"k":"from-project"}' > .claude/settings.flow.json
RESULT=$(bash "$HELPER" --default "fb" '.k // empty' 2>/dev/null)
WARNS=$(bash "$HELPER" --default "fb" '.k // empty' 2>&1 >/dev/null)
assert_equal "from-project" "$RESULT" "malformed local should fall through to project"
assert_contains "failed to parse" "$WARNS" "WARN should describe the parse failure"
_teardown_cascade

# ─── Test 13: missing expression → exit 2 ───────────────────────────────────
_begin "Missing <jq-expression> → exit 2 with usage message"
_setup_cascade
EXIT_CODE=0
ERROR=$(bash "$HELPER" 2>&1) || EXIT_CODE=$?
assert_exit 2 "$EXIT_CODE" "missing expression must exit 2"
assert_contains "missing <jq-expression>" "$ERROR" "should print usage hint"
_teardown_cascade

# ─── Test 14: unknown flag → exit 2 ─────────────────────────────────────────
_begin "Unknown flag → exit 2"
_setup_cascade
EXIT_CODE=0
ERROR=$(bash "$HELPER" --frobnicate '.k' 2>&1) || EXIT_CODE=$?
assert_exit 2 "$EXIT_CODE" "unknown flag must exit 2"
assert_contains "unknown flag" "$ERROR" "should describe the unknown flag"
_teardown_cascade
