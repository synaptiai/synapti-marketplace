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
  [ -f "$HOOKS/tier-gate.sh" ] && \
    _feed "$HOOKS/tier-gate.sh" "$BENIGN" 0 "tier-gate allows a command that runs no tiered action"
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
    # tier-gate's journal breadcrumb goes through the same helper into the
    # same trail: with the plugin default (tiers.push journal) a push on the
    # issue-1 branch must add one breadcrumb to auto-log/issue-1.<YYYY-MM>.md.
    PUSH_PAYLOAD=$(jq -nc --arg cwd "$SMOKE_REPO" \
      '{session_id:"smoke", cwd:$cwd, tool_name:"Bash", tool_input:{command:"git push origin HEAD"}}')
    if [ -f "$HOOKS/tier-gate.sh" ]; then
      _feed "$HOOKS/tier-gate.sh" "$PUSH_PAYLOAD" 0 "tier-gate answers a push payload"
      if cat "$SMOKE_REPO/.decisions/auto-log/"issue-1.*.md 2>/dev/null | grep -q 'tiers.push (journal) "git push origin HEAD"'; then
        _ok "tier-gate wrote the push to the payload cwd's auto-log trail"
      else
        _bad "tier-gate wrote no breadcrumb to $SMOKE_REPO/.decisions/auto-log/"
        _out=$(printf '%s' "$PUSH_PAYLOAD" | bash "$HOOKS/tier-gate.sh" 2>&1 >/dev/null)
        printf 'DIAG: tier-gate stderr=%s\n' "$(printf '%s' "$_out" | tr '\n' '|' | cut -c1-400)"
      fi
    fi
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
      # Say WHY. A hook must never fail the tool call it follows, so it
      # swallows the helper's failure and this file can only report "nothing
      # was written" — the cause stayed invisible across four CI runs. Run the
      # helper directly, and the hook with its stderr kept, so the next
      # failure names itself instead of being inferred.
      _out=$(printf 'probe\n' | "$PLUGIN_ROOT/bin/journal-append.sh" \
        --file "$SMOKE_REPO/.decisions/probe.md" - 2>&1)
      _rc=$?
      printf 'DIAG: journal-append.sh exit=%s\nDIAG:   %s\n' \
        "$_rc" "$(printf '%s' "$_out" | tr '\n' '|' | cut -c1-400)"
      _out=$(printf '%s' "$EDIT_PAYLOAD" | bash "$HOOKS/log-file-changes.sh" 2>&1 >/dev/null)
      printf 'DIAG: hook stderr=%s\n' "$(printf '%s' "$_out" | tr '\n' '|' | cut -c1-400)"
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

# --- the SessionStart hook and the git and gh wrappers it puts on PATH -------
# The wrappers run on every git and gh call of a session, so one that does
# not start breaks git itself, not only the check.
if [ -f "$HOOKS/tier-session-start.sh" ] && command -v jq >/dev/null 2>&1; then
  SMOKE_STATE=$(mktemp -d "${TMPDIR:-/tmp}/flow-smoke-state.XXXXXX") || SMOKE_STATE=""
  SMOKE_ENV="${SMOKE_STATE:+$SMOKE_STATE/env.sh}"
  if [ -n "$SMOKE_ENV" ]; then
    printf '{"session_id":"smoke","hook_event_name":"SessionStart"}' \
      | CLAUDE_ENV_FILE="$SMOKE_ENV" FLOW_STATE_DIR="$SMOKE_STATE" bash "$HOOKS/tier-session-start.sh" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = 0 ] && grep -q 'hooks/shims' "$SMOKE_ENV"; then
      _ok "tier-session-start wrote the session's PATH line"
      _out=$(bash -c '. "$1"; command -v git; git --version' _ "$SMOKE_ENV" 2>&1)
      case "$_out" in
        *hooks/shims/git*"git version"*) _ok "git runs through flow's wrapper" ;;
        *) _bad "git through flow's wrapper: $(printf '%s' "$_out" | tr '\n' '|' | cut -c1-300)" ;;
      esac
    else
      _bad "tier-session-start — exit $rc, or no PATH line in CLAUDE_ENV_FILE"
    fi
    rm -r "$SMOKE_STATE"
  fi
fi
printf '\n'

# --- every bin/ helper that hands python3 a path does its work ----------------
# Issue #246. Git Bash hands a script POSIX paths, and a native Windows python3
# reads /d/a/... as another place, so a helper whose module sits beside it
# imported nothing and did nothing, silently. Each helper is called once,
# against a scratch repository at an ordinary path, with the absolute paths it
# is usually given, and what it was asked to do is checked: a file written, an
# id printed, a record listed. lib/py-path.sh does the conversion.
_helper_dir() {
  local d="" _b _p
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      for _b in "${RUNNER_TEMP:-}" "${TEMP:-}" "${TMPDIR:-}" "${HOME:-}"; do
        [ -n "$_b" ] || continue
        _p=$(cygpath -u "$_b" 2>/dev/null) || continue
        [ -d "$_p" ] || continue
        d=$(mktemp -d "$_p/flow-helpers-smoke.XXXXXX" 2>/dev/null) || d=""
        [ -n "$d" ] && [ -d "$d" ] && break
        d=""
      done ;;
  esac
  [ -n "$d" ] || d=$(mktemp -d -t flow-helpers-smoke.XXXXXX 2>/dev/null)
  printf '%s' "$d"
}
# _helper <label> <check> -- <command...>: run the command in the scratch
# repository; pass when it exits 0 and the check (a shell test, run there)
# holds.
_helper() {
  local label="$1" check="$2" rc out
  shift 3
  out=$(cd "$HREPO" && "$@" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && (cd "$HREPO" && HOUT="$out" eval "$check"); then
    _ok "$label"
  else
    _bad "$label — exit $rc: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
  fi
}
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  HWORK=$(_helper_dir)
  if [ -n "$HWORK" ] && [ -d "$HWORK" ]; then
    HREPO="$HWORK/repo"
    mkdir -p "$HREPO" "$HWORK/state" "$HWORK/transcripts"
    (
      cd "$HREPO" || exit 1
      git init -q -b main >/dev/null 2>&1
      git config user.email smoke@example.invalid
      git config user.name smoke
      printf 'x\n' > README.md
      mkdir -p .decisions
      printf '# Journal\n' > .decisions/issue-42.md
      git add -A >/dev/null 2>&1
      git commit -qm init >/dev/null 2>&1
      git checkout -q -b feature/issue-42-search-fix >/dev/null 2>&1
    )
    export FLOW_STATE_DIR="$HWORK/state"
    RUN=2026-05-20T143000Z-issue-42
    mkdir -p "$HREPO/.flow/runs/$RUN"
    cp "$PLUGIN_ROOT/tests/fixtures/goal/valid.yaml" "$HWORK/goal.yaml"
    cp "$PLUGIN_ROOT/tests/fixtures/activity/valid.yaml" "$HWORK/activity.yaml"
    cp "$PLUGIN_ROOT/tests/fixtures/evidence/valid.yaml" "$HWORK/evidence.yaml"
    printf '%s\n' '{"verdict":"not_achieved","confidence":0.5,"delta":"unchanged","reason":"smoke","next_step_hint":"none","source":"command"}' > "$HWORK/verdict.json"
    B="$PLUGIN_ROOT/bin"
    _helper "flow-goal-record.sh creates a goal from an absolute path" '[ -f .flow/goals/issue-42.goal.yaml ]' -- \
      "$B/flow-goal-record.sh" --create --goal-file "$HWORK/goal.yaml"
    _helper "flow-active-goal.sh finds it" '[ "$HOUT" = issue-42 ]' -- \
      "$B/flow-active-goal.sh" --id --branch-strict
    _helper "flow-goal-trust.sh reads the per-user ledger" 'case "$HOUT" in *TRUSTED=yes*) true ;; *) false ;; esac' -- \
      "$B/flow-goal-trust.sh" check --goal-file .flow/goals/issue-42.goal.yaml
    _helper "flow-record-activity.sh writes an activity" 'ls .flow/runs/'"$RUN"'/activities/001-*.yaml >/dev/null 2>&1' -- \
      "$B/flow-record-activity.sh" --run-id "$RUN" --activity-file "$HWORK/activity.yaml"
    _helper "flow-record-evidence.sh writes an evidence sidecar" 'ls .flow/runs/'"$RUN"'/evidence/*.evidence.yaml >/dev/null 2>&1' -- \
      "$B/flow-record-evidence.sh" --run-id "$RUN" --evidence-file "$HWORK/evidence.yaml"
    _helper "flow-record-verdict.sh writes the last verdict" '[ -f .flow/runs/'"$RUN"'/last-verdict.json ]' -- \
      "$B/flow-record-verdict.sh" --run-id "$RUN" --verdict-file "$HWORK/verdict.json"
    _helper "journal-record.sh records an artifact" 'grep -q "type: smoke" .decisions/issue-42.md' -- \
      "$B/journal-record.sh" --issue 42 --type smoke --metadata note=windows
    _helper "flow-question.sh stores a question and leaves slash text alone" 'case "$(cd "$HREPO" && "$B/flow-question.sh" list)" in *"|/flow:start Phase 1|"*) true ;; *) false ;; esac' -- \
      "$B/flow-question.sh" add --situation s --tried t --option "a (Recommended)" --option b \
        --recommendation r --blocking soft --risk k --command "/flow:start Phase 1"
    printf '<!-- auto-log: smoke -->\n' >> "$HREPO/.decisions/issue-42.md"
    _helper "flow-strip-auto-log.sh reads a journal directory given absolutely" 'case "$HOUT" in *"STRIP_AUTO_LOG=1 files, 1 lines"*) true ;; *) false ;; esac' -- \
      "$B/flow-strip-auto-log.sh" "$HREPO/.decisions"
    _helper "flow-quality-ledger.sh appends and reads a session ledger" 'case "$("$B/flow-quality-ledger.sh" status --session smoke --cwd "$HREPO" 2>&1)" in *"LAST_PASSING_RUN=2026-05-20T14:00:00Z"*) true ;; *) false ;; esac' -- \
      "$B/flow-quality-ledger.sh" append --session smoke --json '{"at":"2026-05-20T14:00:00Z","type":"quality_run","command":"npm test","exit_code":0,"kind":"test"}'
    _helper "flow-mine-corrections.sh reads a transcript directory given absolutely" 'case "$HOUT" in *SESSION_COUNT=0*|*TRANSCRIPT_DIR_STATE=ok*) true ;; *) false ;; esac' -- \
      "$B/flow-mine-corrections.sh" --project-dir "$HREPO" --transcript-dir "$HWORK/transcripts" --format jsonl
    _helper "flow-eval-run.sh runs its Python helper (case check)" 'case "$HOUT" in *'"'"'"problems": []'"'"'*) true ;; *) false ;; esac' -- \
      "$B/flow-eval-run.sh" --check-cases
    unset FLOW_STATE_DIR
    rm -rf "$HWORK"
  else
    _bad "mktemp -d failed — could not build a scratch repo for the bin/ helpers"
  fi
fi
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
