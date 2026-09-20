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

# --- the PostToolUse logging hooks answer a real payload ----------------------
# Parsing is not enough for these two. Issue #244 gave them real runtime logic —
# adopting the payload cwd, resolving the repository, physicalising the path,
# creating the trail directory and calling bin/journal-append.sh — and a failure
# in any of it is silent, because a hook that falls over just stops logging.
# They are fed a payload pointing at a scratch repository so the whole path runs.
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  SMOKE_REPO=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      # Git Bash's `mktemp -d -t` returns an MSYS-VIRTUAL /tmp path, whose
      # `cygpath -m` translation points at a real but different directory. The
      # fixture has to live somewhere that exists in both worlds so the helper's
      # path conversion lands on the file that was actually created. Every
      # expansion carries a default: this file runs under `set -u`, and a bare
      # "$TMPDIR" aborted the whole job before the loop body ran once.
      for _base in "${RUNNER_TEMP:-}" "${TEMP:-}" "${TMPDIR:-}" "${HOME:-}"; do
        [ -n "$_base" ] || continue
        _posix=$(cygpath -u "$_base" 2>/dev/null) || continue
        [ -d "$_posix" ] || continue
        SMOKE_REPO=$(mktemp -d "$_posix/flow-hooks-smoke.XXXXXX" 2>/dev/null) || SMOKE_REPO=""
        [ -n "$SMOKE_REPO" ] && [ -d "$SMOKE_REPO" ] && break
        SMOKE_REPO=""
      done
      ;;
  esac
  [ -n "$SMOKE_REPO" ] || SMOKE_REPO=$(mktemp -d -t flow-hooks-smoke.XXXXXX 2>/dev/null)
  if [ -n "$SMOKE_REPO" ] && [ -d "$SMOKE_REPO" ]; then
    (
      cd "$SMOKE_REPO" 2>/dev/null || exit 1
      git init -q -b main >/dev/null 2>&1
      git config user.email smoke@example.invalid
      git config user.name smoke
      mkdir -p .decisions
      printf '# Journal\n' > .decisions/issue-1.md
      git add -A >/dev/null 2>&1
      git commit -qm "init" >/dev/null 2>&1
      git checkout -q -b feature/issue-1-smoke >/dev/null 2>&1
      printf 'x\n' > f.txt
    ) >/dev/null 2>&1
    EDIT_PAYLOAD=$(jq -nc --arg cwd "$SMOKE_REPO" --arg f "$SMOKE_REPO/f.txt" \
      '{session_id:"smoke", cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$f}}')
    COMMIT_PAYLOAD=$(jq -nc --arg cwd "$SMOKE_REPO" \
      '{session_id:"smoke", cwd:$cwd, tool_name:"Bash", tool_input:{command:"git commit -m smoke"}}')
    [ -f "$HOOKS/log-file-changes.sh" ] && \
      _feed "$HOOKS/log-file-changes.sh" "$EDIT_PAYLOAD" 0 "log-file-changes answers an edit payload"
    [ -f "$HOOKS/log-commits.sh" ] && \
      _feed "$HOOKS/log-commits.sh" "$COMMIT_PAYLOAD" 0 "log-commits answers a commit payload"
    # The trail directory must exist and ignore itself. Both are written by the
    # shell, so they hold on every platform.
    if [ -s "$SMOKE_REPO/.decisions/auto-log/.gitignore" ]; then
      _ok "the trail directory ignores itself"
    else
      _bad "the trail directory did not drop its self-ignoring .gitignore"
    fi
    # The ENTRY is written by bin/journal-append.sh, which is python3 — a native
    # interpreter on Windows. The helper converts the path it hands the
    # interpreter (`py_path`), and this fixture lives at a directory that exists
    # in both worlds, so the write is now asserted on every platform rather than
    # skipped on one. A skip here is what let the write fail silently on Windows
    # while this file reported green.
    if ls "$SMOKE_REPO/.decisions/auto-log/"issue-1.*.md >/dev/null 2>&1; then
      _ok "the auto-log trail was created in the payload cwd's repo"
    else
      _bad "no auto-log trail written under $SMOKE_REPO/.decisions/auto-log/"
    fi
    command rm -rf -- "$SMOKE_REPO" 2>/dev/null
  else
    _bad "mktemp -d failed — could not build a scratch repo for the logging hooks"
  fi
fi
printf '\n'

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
