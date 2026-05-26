# Tests for plugins/flow/bin/flow-migrate-settings.sh — settings schema upgrade.
#
# Migrates deprecated keys (currently flow.goals.requireGoalForStart ->
# flow.goals.goalCreation) in a committed settings file, atomically and
# idempotently, preserving all other keys.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-migrate-settings.sh"

MS_CLEANUP=()
_ms_cleanup() { local p; for p in "${MS_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _ms_cleanup EXIT

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

_ms_dir() {
  local d; d=$(mktemp -d -t flow-migrate.XXXXXX 2>/dev/null)
  [ -z "$d" ] && { echo "mktemp failed" >&2; exit 2; }
  MS_CLEANUP+=("$d"); mkdir -p "$d/.claude"; printf '%s' "$d"
}

_flow_test_begin "requireGoalForStart:true -> goalCreation:always (apply), other keys preserved"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"agentTeams":false,"flow":{"goals":{"requireGoalForStart":true},"runtime":{"enabled":true}}}' > "$F"
OUT=$(bash "$HELPER" --apply "$F" 2>&1); EXIT=$?
assert_equal "0" "$EXIT" "exit 0 on apply"
assert_contains "MIGRATE_APPLIED=1" "$OUT" "reports applied"
assert_equal "always" "$(jq -r '.flow.goals.goalCreation' "$F")" "goalCreation=always"
assert_equal "absent" "$(jq -r '.flow.goals.requireGoalForStart // "absent"' "$F")" "deprecated key removed"
assert_equal "false" "$(jq -r '.agentTeams' "$F")" "unrelated key agentTeams preserved"
assert_equal "true" "$(jq -r '.flow.runtime.enabled' "$F")" "unrelated key flow.runtime preserved"

_flow_test_begin "requireGoalForStart:false -> goalCreation:off"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"requireGoalForStart":false}}}' > "$F"
bash "$HELPER" --apply "$F" >/dev/null 2>&1
assert_equal "off" "$(jq -r '.flow.goals.goalCreation' "$F")" "false maps to off"

_flow_test_begin "non-boolean requireGoalForStart -> goalCreation:auto"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"requireGoalForStart":"yes"}}}' > "$F"
bash "$HELPER" --apply "$F" >/dev/null 2>&1
assert_equal "auto" "$(jq -r '.flow.goals.goalCreation' "$F")" "non-bool maps to auto"

_flow_test_begin "both keys present: goalCreation wins, deprecated key dropped"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"goalCreation":"auto","requireGoalForStart":true}}}' > "$F"
bash "$HELPER" --apply "$F" >/dev/null 2>&1
assert_equal "auto" "$(jq -r '.flow.goals.goalCreation' "$F")" "explicit goalCreation preserved (not overwritten to always)"
assert_equal "absent" "$(jq -r '.flow.goals.requireGoalForStart // "absent"' "$F")" "deprecated key dropped"

_flow_test_begin "no deprecated key: MIGRATE=none, file byte-unchanged"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"goalCreation":"auto"}},"agentTeams":true}' > "$F"
BEFORE=$(cat "$F")
OUT=$(bash "$HELPER" --apply "$F" 2>&1); EXIT=$?
assert_equal "0" "$EXIT" "exit 0"
assert_contains "MIGRATE=none" "$OUT" "reports nothing to migrate"
assert_equal "$BEFORE" "$(cat "$F")" "file unchanged when nothing to migrate"

_flow_test_begin "dry-run does NOT modify the file"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"requireGoalForStart":true}}}' > "$F"
BEFORE=$(cat "$F")
OUT=$(bash "$HELPER" "$F" 2>&1)
assert_contains "MIGRATE=requireGoalForStart->goalCreation" "$OUT" "dry-run reports the pending change"
assert_contains "dry-run" "$OUT" "dry-run mode noted"
assert_equal "$BEFORE" "$(cat "$F")" "dry-run left the file untouched"

_flow_test_begin "idempotent: a second --apply reports nothing to migrate"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"requireGoalForStart":true}}}' > "$F"
bash "$HELPER" --apply "$F" >/dev/null 2>&1
OUT=$(bash "$HELPER" --apply "$F" 2>&1)
assert_contains "MIGRATE=none" "$OUT" "second run is a no-op"

_flow_test_begin "malformed JSON -> exit 2, file untouched"
D=$(_ms_dir); F="$D/.claude/settings.flow.json"
printf '{ this is not json' > "$F"; BEFORE=$(cat "$F")
OUT=$(bash "$HELPER" --apply "$F" 2>&1); EXIT=$?
assert_equal "2" "$EXIT" "exit 2 on malformed JSON"
assert_contains "not valid JSON" "$OUT" "stderr names the parse failure"
assert_equal "$BEFORE" "$(cat "$F")" "malformed file left untouched"

_flow_test_begin "symlinked settings file -> exit 2 (refuse)"
D=$(_ms_dir); REAL="$D/real.json"; LINK="$D/.claude/settings.flow.json"
echo '{"flow":{"goals":{"requireGoalForStart":true}}}' > "$REAL"
rm -f "$LINK"; ln -s "$REAL" "$LINK"
OUT=$(bash "$HELPER" --apply "$LINK" 2>&1); EXIT=$?
assert_equal "2" "$EXIT" "exit 2 on symlinked settings"
assert_contains "symlink" "$OUT" "stderr names the symlink refusal"
assert_equal "true" "$(jq -r '.flow.goals.requireGoalForStart' "$REAL")" "symlink target untouched"

_flow_test_begin "missing file -> exit 2"
D=$(_ms_dir)
OUT=$(bash "$HELPER" --apply "$D/.claude/nope.json" 2>&1); EXIT=$?
assert_equal "2" "$EXIT" "exit 2 when file absent"
assert_contains "not found" "$OUT" "stderr names the missing file"
