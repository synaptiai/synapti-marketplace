#!/usr/bin/env bash
# Proves the hooks this plugin ships actually run under the shell Windows users
# have, rather than asserting it in a policy document.
#
# The gap this closes: Claude Code silently skips a hook that fails to start.
# A Windows user installing a plugin whose hooks cannot run sees no journal
# entries, no destructive-command guard and no commit safety check — and no
# error either. The failure is indistinguishable from the hooks having nothing
# to say (issue #100).
#
# So this feeds each hook the payload the hook runner would feed it and checks
# the exit code. It runs on any platform; on the Windows runner it runs under
# Git Bash, which is the shell the policy in docs/windows-support.md commits to.
#
# Deliberately NOT a second copy of the hook test suites. Those live in
# plugins/flow/tests/*.test.sh and assert behaviour. This asserts that the
# scripts start, parse, find their dependencies and exit with a code the hook
# runner understands — the things that break when the platform changes.
#
# Usage: plugins/flow/tests/windows-hooks-smoke.sh
# Exit:  0 all hooks started and answered; 1 at least one did not.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
HOOKS="$PLUGIN_ROOT/hooks/scripts"
PASS=0
FAIL=0

_ok()   { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
_bad()  { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

printf 'shell: %s\n' "$(bash --version 2>/dev/null | head -1)"
printf 'uname: %s\n' "$(uname -s 2>/dev/null || echo unknown)"
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

# --- prerequisites the hooks hard-require -------------------------------------
# Named individually: "a hook exited 2" is not a useful report when the cause is
# that jq is not installed on the runner image.
for tool in jq git awk sed grep; do
  if command -v "$tool" >/dev/null 2>&1; then
    _ok "prerequisite present: $tool"
  else
    _bad "prerequisite MISSING: $tool — hooks that need it will refuse"
  fi
done
if command -v python3 >/dev/null 2>&1; then
  _ok "prerequisite present: python3"
  if python3 -c "import yaml" >/dev/null 2>&1; then
    _ok "prerequisite present: PyYAML"
  else
    _bad "PyYAML not importable — journal and run-state writes are skipped"
  fi
else
  _bad "prerequisite MISSING: python3"
fi
printf '\n'

# --- every shipped script parses under this shell -----------------------------
# A bash-ism that this shell rejects is the failure mode that produces silence:
# the script never starts, so it never reports anything.
for f in "$HOOKS"/*.sh "$HOOKS"/lib/*.sh "$PLUGIN_ROOT"/bin/*.sh; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>/dev/null; then
    _ok "parses: ${f#"$PLUGIN_ROOT"/}"
  else
    _bad "does NOT parse: ${f#"$PLUGIN_ROOT"/} — $(bash -n "$f" 2>&1 | head -1)"
  fi
done
printf '\n'

# --- the PreToolUse hooks answer a real payload -------------------------------
# Each is fed the JSON shape the hook runner sends and must exit 0 (allow) or 2
# (block). Any other code means it fell over.
_feed() {
  local script="$1" payload="$2" want="$3" label="$4"
  local rc
  printf '%s' "$payload" | bash "$script" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$want" ]; then
    _ok "$label (exit $rc)"
  else
    _bad "$label — exit $rc, expected $want"
  fi
}

if command -v jq >/dev/null 2>&1; then
  BENIGN=$(printf '%s' "git status --short" | jq -Rs . | sed 's/^/{"tool_input":{"command":/;s/$/}}/')
  DESTRUCTIVE=$(printf '%s' "rm -rf /some/important/path" | jq -Rs . | sed 's/^/{"tool_input":{"command":/;s/$/}}/')

  [ -f "$HOOKS/block-destructive.sh" ] && {
    _feed "$HOOKS/block-destructive.sh" "$BENIGN" 0 "block-destructive allows an ordinary command"
    _feed "$HOOKS/block-destructive.sh" "$DESTRUCTIVE" 2 "block-destructive refuses a recursive forced delete"
  }
  [ -f "$HOOKS/block-force-push.sh" ] && \
    _feed "$HOOKS/block-force-push.sh" "$BENIGN" 0 "block-force-push allows an ordinary command"
  [ -f "$HOOKS/block-secrets.sh" ] && \
    _feed "$HOOKS/block-secrets.sh" "$BENIGN" 0 "block-secrets allows an ordinary command"
  [ -f "$HOOKS/block-unchecked-merge.sh" ] && \
    _feed "$HOOKS/block-unchecked-merge.sh" "$BENIGN" 0 "block-unchecked-merge allows a command that is not a merge"
else
  _bad "jq missing — cannot build a hook payload to feed"
fi

# --- the Stop and SessionEnd hooks tolerate an empty session ------------------
# These run at moments the user is not watching, so falling over is invisible.
for h in flow-goal-stop.sh reply-style-check.sh session-end-state.sh session-end-learn.sh; do
  [ -f "$HOOKS/$h" ] || continue
  printf '{"session_id":"smoke","cwd":"%s"}' "$PLUGIN_ROOT" | bash "$HOOKS/$h" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "0" ] || [ "$rc" = "2" ]; then
    _ok "$h answers an empty session (exit $rc)"
  else
    _bad "$h — exit $rc on an empty session"
  fi
done
printf '\n'

# --- the settings resolver, which almost everything depends on ----------------
if [ -x "$PLUGIN_ROOT/bin/cascade-resolve.sh" ]; then
  OUT=$("$PLUGIN_ROOT/bin/cascade-resolve.sh" --default "fallback" '.nothing.here' 2>/dev/null)
  if [ "$OUT" = "fallback" ]; then
    _ok "cascade-resolve.sh returns its default"
  else
    _bad "cascade-resolve.sh returned '$OUT', expected 'fallback'"
  fi
fi

printf '\n============================================\n'
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
printf '============================================\n'
[ "$FAIL" -eq 0 ] || exit 1
exit 0
