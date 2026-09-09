# Tests for plugins/flow/bin/flow-mine-corrections.sh (transcript correction
# miner), the `### Transcript Corrections` section of commands/learn.md, and
# the transcript signal in hooks/scripts/session-end-learn.sh.
#
# Fixtures (synthetic, invented content) live in tests/fixtures/transcripts/:
#   session-corrections.jsonl — 3 corrections + non-corrections (a tool_result
#                               user record, an isMeta record, a sidechain
#                               record, a task-notification origin, "thanks")
#   session-clean.jsonl       — a session with no corrections
#   session-malformed.jsonl   — a malformed line, then a repeated slash command

MINER="$REPO_ROOT/plugins/flow/bin/flow-mine-corrections.sh"
HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/session-end-learn.sh"
LEARN_CMD="$REPO_ROOT/plugins/flow/commands/learn.md"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/transcripts"
CORRECTIONS="$FIXTURES/session-corrections.jsonl"
CLEAN="$FIXTURES/session-clean.jsonl"

_flow_test_begin "prerequisites"
assert_file_exists "$MINER" "miner script exists"
assert_file_exists "$CORRECTIONS" "corrections fixture exists"
assert_file_exists "$CLEAN" "clean fixture exists"
assert_file_exists "$FIXTURES/session-malformed.jsonl" "malformed fixture exists"
if [ -x "$MINER" ]; then
  _flow_assert_pass "miner is executable"
else
  _flow_assert_fail "miner is not executable"
fi

# --- directory scan -----------------------------------------------------------
_flow_test_begin "dir scan — jsonl emits one record per candidate"
OUT=$("$MINER" --transcript-dir "$FIXTURES" --format jsonl 2>/dev/null)
RC=$?
assert_exit 0 "$RC" "exit 0"
assert_equal "4" "$(printf '%s\n' "$OUT" | grep -c '"session_id"')" "4 candidates across the fixture dir"
assert_contains '"line_no": 5' "$OUT" "first correction cites its transcript line"
assert_contains '"session_id": "fixture-session-c"' "$OUT" "repeated slash command from the malformed session is a candidate"
assert_contains '"text": "/flow:pr"' "$OUT" "slash-command text is the command name"
for KEY in session_id timestamp project text preceded_by transcript_path line_no; do
  assert_contains "\"$KEY\":" "$(printf '%s\n' "$OUT" | head -1)" "record has field $KEY"
done

_flow_test_begin "dir scan — markdown has counts + table header"
OUT=$("$MINER" --transcript-dir "$FIXTURES" --format markdown 2>/dev/null)
assert_contains "TRANSCRIPT_DIR_STATE=ok" "$OUT" "dir state ok"
assert_contains "CANDIDATE_COUNT=4" "$OUT" "candidate count"
assert_contains "SESSION_COUNT=3" "$OUT" "three transcripts scanned"
assert_contains "SESSIONS_WITH_CANDIDATES=2" "$OUT" "two sessions carry candidates"
assert_contains "| # | Session | Timestamp | Line | User said | Preceded by (assistant, truncated) |" "$OUT" "table header present"
assert_contains "session-corrections.jsonl:5 |" "$OUT" "rows cite transcript_path:line_no"

# --- exclusions ---------------------------------------------------------------
_flow_test_begin "file mode — excludes tool_result, isMeta, sidechain, task-notification, plain thanks"
OUT=$("$MINER" --file "$CORRECTIONS" --format jsonl 2>/dev/null)
assert_equal "3" "$(printf '%s\n' "$OUT" | grep -c '"session_id"')" "3 corrections in the corrections fixture"
assert_contains "That's not what I asked" "$OUT" "correction 1 kept"
assert_contains "it is empty" "$OUT" "correction 2 kept"
assert_contains "why didn't you run the tests" "$OUT" "correction 3 kept"
assert_not_contains "no output found" "$OUT" "tool_result block text excluded"
assert_not_contains "injected meta record" "$OUT" "isMeta record excluded"
assert_not_contains "sidechain record" "$OUT" "isSidechain record excluded"
assert_not_contains "background task finished" "$OUT" "non-human origin excluded"
assert_not_contains "thanks, looks good" "$OUT" "plain thanks excluded"
assert_not_contains "Please add a --json flag" "$OUT" "first turn (no assistant before it) excluded"

_flow_test_begin "clean session yields zero candidates"
OUT=$("$MINER" --file "$CLEAN" --format markdown 2>/dev/null)
assert_contains "CANDIDATE_COUNT=0" "$OUT" "no candidates"
assert_contains "SESSION_COUNT=1" "$OUT" "one transcript scanned"
assert_not_contains "| # | Session" "$OUT" "no table when there is nothing to show"

_flow_test_begin "malformed line is skipped, later records still parsed"
OUT=$("$MINER" --file "$FIXTURES/session-malformed.jsonl" --format jsonl 2>/dev/null)
RC=$?
assert_exit 0 "$RC" "exit 0 despite the malformed line"
assert_equal "1" "$(printf '%s\n' "$OUT" | grep -c '"session_id"')" "one candidate (the repeated slash command)"
assert_not_contains "merging it myself" "$OUT" "non-reaction after the repeat is excluded"

# --- since / min-chars / preceded_by bound --------------------------------------
_flow_test_begin "--since filters by record timestamp"
OUT=$("$MINER" --file "$CORRECTIONS" --since 2026-08-10 --format jsonl 2>/dev/null)
assert_equal "2" "$(printf '%s\n' "$OUT" | grep -c '"session_id"')" "2 candidates at or after 2026-08-10"
assert_not_contains "2026-08-01T09:01:00" "$OUT" "August 1 record dropped"
OUT=$("$MINER" --file "$CORRECTIONS" --since 2026-09-01T11:00:00Z --format jsonl 2>/dev/null)
assert_equal "1" "$(printf '%s\n' "$OUT" | grep -c '"session_id"')" "full ISO --since keeps only the last correction"
"$MINER" --file "$CORRECTIONS" --since not-a-date >/dev/null 2>&1
assert_exit 1 "$?" "unparsable --since exits 1"

_flow_test_begin "--min-chars drops short candidates"
OUT=$("$MINER" --file "$CORRECTIONS" --min-chars 45 --format jsonl 2>/dev/null)
assert_equal "2" "$(printf '%s\n' "$OUT" | grep -c '"session_id"')" "the 41-char correction is dropped at --min-chars 45"

_flow_test_begin "preceded_by never exceeds 300 chars and never carries a full long turn"
OUT=$("$MINER" --transcript-dir "$FIXTURES" --format jsonl 2>/dev/null)
MAXLEN=$(printf '%s\n' "$OUT" | PYTHONSAFEPATH=1 python3 -c '
import json, sys
print(max(len(json.loads(l)["preceded_by"]) for l in sys.stdin if l.strip()))
')
assert_equal "300" "$MAXLEN" "longest preceded_by is exactly the 300-char cap"
assert_not_contains "must never be emitted" "$OUT" "tail of the long assistant turn is not emitted"

# --- missing inputs -------------------------------------------------------------
_flow_test_begin "missing transcript dir -> CANDIDATE_COUNT=0, exit 0, stderr note"
ERR_TMP=$(mktemp -t flow_mine_err.XXXXXX)
OUT=$("$MINER" --transcript-dir "$REPO_ROOT/plugins/flow/tests/fixtures/no-such-transcripts" --format markdown 2>"$ERR_TMP")
RC=$?
assert_exit 0 "$RC" "exit 0"
assert_contains "CANDIDATE_COUNT=0" "$OUT" "zero candidates"
assert_contains "TRANSCRIPT_DIR_STATE=missing" "$OUT" "dir state missing"
assert_contains "transcript dir not found" "$(cat "$ERR_TMP")" "stderr note"
rm -f "$ERR_TMP"

_flow_test_begin "missing --file and symlinked --file -> zero candidates, exit 0"
OUT=$("$MINER" --file "$FIXTURES/does-not-exist.jsonl" --format markdown 2>/dev/null)
assert_exit 0 "$?" "missing file exits 0"
assert_contains "CANDIDATE_COUNT=0" "$OUT" "missing file reports zero"
LINK_DIR=$(mktemp -d -t flow_mine_link.XXXXXX)
ln -s "$CORRECTIONS" "$LINK_DIR/link.jsonl"
OUT=$("$MINER" --file "$LINK_DIR/link.jsonl" --format jsonl 2>/dev/null)
assert_exit 0 "$?" "symlink exits 0"
assert_equal "" "$OUT" "symlinked --file is not followed"
rm -rf "$LINK_DIR"

_flow_test_begin "argument validation"
"$MINER" --format bogus >/dev/null 2>&1
assert_exit 1 "$?" "bad --format exits 1"
"$MINER" --max-sessions two >/dev/null 2>&1
assert_exit 1 "$?" "non-numeric --max-sessions exits 1"
"$MINER" --no-such-flag >/dev/null 2>&1
assert_exit 1 "$?" "unknown flag exits 1"
assert_contains "Usage:" "$("$MINER" --help)" "--help prints usage"

# --- default dir resolution: <root>/<slug of project dir> -----------------------
_flow_test_begin "default transcript dir is CLAUDE_TRANSCRIPT_DIR/<slug>"
ROOT=$(mktemp -d -t flow_mine_root.XXXXXX)
PROJ=$(mktemp -d -t flow_mine_proj.XXXXXX)
SLUG=$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$ROOT/$SLUG"
cp "$CORRECTIONS" "$ROOT/$SLUG/aaaa-session.jsonl"
OUT=$(CLAUDE_TRANSCRIPT_DIR="$ROOT" "$MINER" --project-dir "$PROJ" --format markdown 2>/dev/null)
assert_contains "TRANSCRIPT_DIR=$ROOT/$SLUG" "$OUT" "slug dir resolved"
assert_contains "CANDIDATE_COUNT=3" "$OUT" "candidates found via the slug dir"
OUT=$(cd "$PROJ" && CLAUDE_TRANSCRIPT_DIR="$ROOT" "$MINER" --format markdown 2>/dev/null)
assert_contains "CANDIDATE_COUNT=3" "$OUT" "project dir defaults to \$PWD"

_flow_test_begin "--max-sessions keeps the newest N transcripts by mtime"
cp "$CLEAN" "$ROOT/$SLUG/bbbb-session.jsonl"
touch -t 202601010000 "$ROOT/$SLUG/aaaa-session.jsonl"   # corrections = oldest
OUT=$(CLAUDE_TRANSCRIPT_DIR="$ROOT" "$MINER" --project-dir "$PROJ" --max-sessions 1 --format markdown 2>/dev/null)
assert_contains "SESSION_COUNT=1" "$OUT" "one transcript scanned"
assert_contains "CANDIDATE_COUNT=0" "$OUT" "newest transcript (clean) chosen"
OUT=$(CLAUDE_TRANSCRIPT_DIR="$ROOT" "$MINER" --project-dir "$PROJ" --max-sessions 2 --format markdown 2>/dev/null)
assert_contains "CANDIDATE_COUNT=3" "$OUT" "both transcripts scanned at --max-sessions 2"
rm -rf "$ROOT" "$PROJ"

# --- learn.md `!` block: TRANSCRIPT_STATE ----------------------------------------
# Extract the Phase 1 ! block the same way flow-status-learn-v3.test.sh does
# and run it in a scratch project dir whose local settings set learning.sources.
LEARN_BLOCK=$(PYTHONSAFEPATH=1 python3 - "$LEARN_CMD" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
after = src.split("## Phase 1", 1)[1]
m = re.search(r"```!\n(.*?)\n```", after, re.S)
sys.stdout.write(m.group(1) if m else "")
PY
)
_run_learn_block() {  # $1 = project dir (cwd), $2 = HOME, $3 = transcript root
  (cd "$1" && HOME="$2" CLAUDE_TRANSCRIPT_DIR="$3" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash -c "$LEARN_BLOCK" 2>/dev/null)
}

_flow_test_begin "learn.md Phase 1 block — learning.sources [\"journal\"] -> TRANSCRIPT_STATE=disabled"
assert_contains "### Transcript Corrections" "$LEARN_BLOCK" "section heading present in the ! block"
assert_contains "learning.sources" "$LEARN_BLOCK" "reads learning.sources"
assert_contains "flow-mine-corrections.sh" "$LEARN_BLOCK" "invokes the miner"
assert_contains "--max-sessions 50" "$LEARN_BLOCK" "caps at 50 sessions"
PROJ=$(mktemp -d -t flow_learn_proj.XXXXXX)
FAKE_HOME=$(mktemp -d -t flow_learn_home.XXXXXX)
ROOT=$(mktemp -d -t flow_learn_root.XXXXXX)
mkdir -p "$PROJ/.claude"
printf '%s\n' '{"learning":{"sources":["journal"]}}' > "$PROJ/.claude/settings.flow.local.json"
OUT=$(_run_learn_block "$PROJ" "$FAKE_HOME" "$ROOT")
assert_contains "TRANSCRIPT_STATE=disabled" "$OUT" "disabled when transcripts not in sources"
assert_contains "CANDIDATE_COUNT=0" "$OUT" "count still emitted"
assert_contains 'TRANSCRIPT_SOURCES=["journal"]' "$OUT" "resolved sources echoed"

_flow_test_begin "learn.md Phase 1 block — default sources + slug dir -> TRANSCRIPT_STATE=ok with counts"
rm -f "$PROJ/.claude/settings.flow.local.json"
SLUG=$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$ROOT/$SLUG"
cp "$CORRECTIONS" "$ROOT/$SLUG/session.jsonl"
OUT=$(_run_learn_block "$PROJ" "$FAKE_HOME" "$ROOT")
assert_contains "TRANSCRIPT_STATE=ok" "$OUT" "ok when the slug dir exists"
assert_contains "CANDIDATE_COUNT=3" "$OUT" "candidates surfaced"
assert_contains "| # | Session |" "$OUT" "table injected into context"
assert_match '(^|\n)true$|.' "$LEARN_BLOCK" "block extracted"

_flow_test_begin "learn.md Phase 1 block — learning.transcriptDir overrides the slug dir"
printf '%s\n' "{\"learning\":{\"transcriptDir\":\"$FIXTURES\"}}" > "$PROJ/.claude/settings.flow.local.json"
OUT=$(_run_learn_block "$PROJ" "$FAKE_HOME" "$ROOT")
assert_contains "TRANSCRIPT_DIR=$FIXTURES" "$OUT" "explicit dir used"
assert_contains "CANDIDATE_COUNT=4" "$OUT" "fixture dir candidates"

_flow_test_begin "learn.md Phase 1 block — missing slug dir -> TRANSCRIPT_STATE=missing"
rm -f "$PROJ/.claude/settings.flow.local.json"
rm -rf "$ROOT/$SLUG"
OUT=$(_run_learn_block "$PROJ" "$FAKE_HOME" "$ROOT")
assert_contains "TRANSCRIPT_STATE=missing" "$OUT" "missing when no transcripts exist"
assert_contains "CANDIDATE_COUNT=0" "$OUT" "zero count"
rm -rf "$PROJ" "$FAKE_HOME" "$ROOT"

_flow_test_begin "learn.md documents transcript phases + tier row"
CONTENT=$(cat "$LEARN_CMD")
assert_contains "### Correction Patterns (transcript source)" "$CONTENT" "Phase 2 category present"
assert_contains "≥3 verified instances across ≥2" "$CONTENT" "threshold documented"
assert_contains "grep -ril" "$CONTENT" "cross-reference against skills"
assert_contains "rule exists in <skill>" "$CONTENT" "label vocabulary"
assert_contains '`enforcement`' "$CONTENT" "enforcement proposal type"
assert_contains "## Enforcement point" "$CONTENT" "template section referenced"
assert_contains "### Fatigue Circuit Breaker" "$CONTENT" "circuit breaker kept"
assert_contains "Read session transcripts under" "$CONTENT" "tier table row"
assert_contains "_None" "$CONTENT" "Required Skills _None_ marker kept"
assert_contains "## Enforcement point" "$(cat "$REPO_ROOT/plugins/flow/templates/skill-proposal.md")" "template has Enforcement point section"
assert_contains "### Transcript Citations" "$(cat "$REPO_ROOT/plugins/flow/templates/skill-proposal.md")" "template has transcript citations"

# --- SessionEnd hook: transcript signal -----------------------------------------
_run_hook() {  # $1 = cwd, $2 = HOME, $3 = stdin payload
  # Export inside the subshell: a `VAR=x cmd | hook` prefix would bind the
  # variables to the left-hand printf only, never to the hook.
  (cd "$1" && export HOME="$2" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" && printf '%s' "$3" | "$HOOK" 2>/dev/null)
}

_flow_test_begin "session-end-learn.sh — transcript with a correction sets the pending flag"
PROJ=$(mktemp -d -t flow_hook_proj.XXXXXX)
FAKE_HOME=$(mktemp -d -t flow_hook_home.XXXXXX)
_run_hook "$PROJ" "$FAKE_HOME" "{\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\",\"transcript_path\":\"$CORRECTIONS\",\"cwd\":\"$PROJ\"}"
assert_exit 0 "$?" "hook exits 0"
assert_file_exists "$FAKE_HOME/.claude/flow-learn-pending" "pending flag written"
assert_match '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$(cat "$FAKE_HOME/.claude/flow-learn-pending")" "flag holds today's date"

_flow_test_begin "session-end-learn.sh — clean transcript, no journal -> no flag"
rm -rf "$FAKE_HOME/.claude"
_run_hook "$PROJ" "$FAKE_HOME" "{\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\",\"transcript_path\":\"$CLEAN\",\"cwd\":\"$PROJ\"}"
assert_exit 0 "$?" "hook exits 0"
if [ -f "$FAKE_HOME/.claude/flow-learn-pending" ]; then
  _flow_assert_fail "flag written for a clean transcript"
else
  _flow_assert_pass "no flag for a clean transcript"
fi

_flow_test_begin "session-end-learn.sh — missing transcript_path falls back to slug dir, then to nothing"
rm -rf "$FAKE_HOME/.claude"
_run_hook "$PROJ" "$FAKE_HOME" "{\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\",\"transcript_path\":\"$PROJ/gone.jsonl\",\"cwd\":\"$PROJ\"}"
assert_exit 0 "$?" "hook exits 0 when the transcript is missing"
if [ -f "$FAKE_HOME/.claude/flow-learn-pending" ]; then
  _flow_assert_fail "flag written with no transcript at all"
else
  _flow_assert_pass "no flag when nothing can be scanned"
fi
SLUG=$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$FAKE_HOME/.claude/projects/$SLUG"
cp "$CORRECTIONS" "$FAKE_HOME/.claude/projects/$SLUG/session.jsonl"
_run_hook "$PROJ" "$FAKE_HOME" '{"hook_event_name":"SessionEnd","reason":"exit"}'
assert_file_exists "$FAKE_HOME/.claude/flow-learn-pending" "slug-dir fallback under \$HOME/.claude/projects sets the flag"

_flow_test_begin "session-end-learn.sh — learning.sources [\"journal\"] ignores transcripts"
rm -rf "$FAKE_HOME/.claude"
mkdir -p "$PROJ/.claude"
printf '%s\n' '{"learning":{"sources":["journal"]}}' > "$PROJ/.claude/settings.flow.local.json"
_run_hook "$PROJ" "$FAKE_HOME" "{\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\",\"transcript_path\":\"$CORRECTIONS\",\"cwd\":\"$PROJ\"}"
assert_exit 0 "$?" "hook exits 0"
if [ -f "$FAKE_HOME/.claude/flow-learn-pending" ]; then
  _flow_assert_fail "flag written although transcripts are disabled"
else
  _flow_assert_pass "no flag when transcripts are not a learning source"
fi

_flow_test_begin "session-end-learn.sh — journal activity still sets the flag on its own"
rm -f "$PROJ/.claude/settings.flow.local.json"
mkdir -p "$PROJ/.decisions"
printf '# decision\n' > "$PROJ/.decisions/issue-1.md"
_run_hook "$PROJ" "$FAKE_HOME" "{\"hook_event_name\":\"SessionEnd\",\"reason\":\"exit\",\"transcript_path\":\"$CLEAN\",\"cwd\":\"$PROJ\"}"
assert_file_exists "$FAKE_HOME/.claude/flow-learn-pending" "journal signal unchanged"
rm -rf "$PROJ" "$FAKE_HOME"
