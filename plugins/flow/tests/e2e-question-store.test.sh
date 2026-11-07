# shellcheck shell=bash
# End-to-end: escalation questions are stored with their status, not kept only
# in the live tool call (#340).
#
# Each scenario runs bin/flow-question.sh, or the shipped block of
# commands/status.md or commands/resume.md that reads the store, in a scratch
# repository. The artifact for each scenario is written to
# $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   Q1 add stores nothing, or a record without one of the six fields, the
#      options, the blocking level, the issue, the command or the time
#   Q2 answer accepts a choice that is not one of the options, or answers a
#      question that is already answered or withdrawn
#   Q3 withdraw leaves the question open, or list shows it as open
#   Q4 two adds at once share an id, so one question overwrites the other
#   Q5 a malformed question (a field missing, more than three options, one
#      option, a blocking level outside yes/soft/no) is stored
#   Q6 the store is written through a symlinked questions directory
#   Q7 the questions are committed (no .gitignore in the directory)
#   Q8 --journal writes no escalation-asked or escalation-resolved artifact
#   Q9 /flow:status does not list open questions, or lists answered ones
#   Q10 /flow:resume does not show the open question of the run it resumes,
#      or shows another run's
#   Q11 a question added from a subdirectory (packages/app) is stored under
#      packages/app/.flow, so list, /flow:status and /flow:resume at the
#      repository top do not see it
#   Q12 add stores no class, or stores a question with none or with one
#      outside decision, permission and default, so nobody can tell later
#      how it may be asked
#   Q13 /flow:resume asks a stored question with another class than the one
#      it was stored with: a default question asked as a decision gets past
#      the autonomous policy, a permission asked as a decision is labeled
#      wrong, and a record with no class is lifted past the policy
#   Q14 answer or withdraw in a repository where no question was ever stored
#      exits 2 (a broken store) instead of 3 (no such question), so a caller
#      cannot tell a mistyped id from a broken store

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "question store: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

Q=bin/flow-question.sh

_q_case() { _flow_test_begin "$1"; e2e_new "$1"; e2e_describe "$2"; e2e_repo feature/issue-340-e2e; }

# _add [extra args...] — a well-formed question for issue $Q_ISSUE (340), of
# class $Q_CLASS (decision).
Q_ISSUE=340
Q_CLASS=decision
_add() {
  e2e_run_bin "$Q" add --situation "Two API versions fit" --tried "Read both changelogs" \
    --option "Target v2 (Recommended)" --option "Target v1" \
    --recommendation "v2 is the supported one" --blocking yes --risk "v1 is deprecated" \
    --command "/flow:start Phase 1" --class "$Q_CLASS" --issue "$Q_ISSUE" "$@"
}
_id() { printf '%s\n' "$E2E_OUT" | sed -n 's/^QUESTION_ID=//p'; }
_field() { python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1])).get(sys.argv[2]))' "$E2E_REPO/.flow/questions/$1.yaml" "$2"; }

# --- add, answer, withdraw, list, get (Q1-Q3, Q7) ----------------------------
_q_case q-roundtrip "a question is added, listed, answered with option 2, and no longer listed as open"
_add --pr 12 --run run-1
e2e_expect_equal 0 "$E2E_RC" "add exit status"
QID=$(_id)
e2e_expect_line "STATUS=open"
for f in situation tried recommendation blocking risk command class issue pr run asked_at; do
  [ "$(_field "$QID" "$f")" != None ] && _e2e_result pass "the record has $f" || _e2e_result fail "the record has $f"
done
e2e_expect_equal "['Target v2 (Recommended)', 'Target v1']" "$(_field "$QID" options)" "the options, the recommended one first"
e2e_expect_equal "*" "$(cat "$E2E_REPO/.flow/questions/.gitignore" 2>/dev/null)" "the questions directory ignores itself"
e2e_run_bin "$Q" list
e2e_expect_line "$QID|open|decision|yes|340|12|/flow:start Phase 1|Two API versions fit"
e2e_run_bin "$Q" answer "$QID" --choice 2
e2e_expect_equal 0 "$E2E_RC" "answer exit status"
e2e_expect_line "ANSWER=Target v1"
e2e_expect_equal answered "$(_field "$QID" status)" "the record's status"
e2e_run_bin "$Q" list
e2e_expect_no_out "$QID"
e2e_run_bin "$Q" list --status answered
e2e_expect_out "$QID|answered"
e2e_run_bin "$Q" get "$QID" --prompt
e2e_expect_out "**Situation** — Two API versions fit"
e2e_expect_out "1. Target v2 (Recommended)"
e2e_expect_clean_edges

_q_case q-answer-refused "a choice that is not an option is refused and the question stays open; an answered question cannot be answered again (Q2)"
_add
QID=$(_id)
e2e_run_bin "$Q" answer "$QID" --choice 3
e2e_expect_equal 1 "$E2E_RC" "answer with option 3 of 2"
e2e_expect_err "is not one of the question's options"
e2e_expect_equal open "$(_field "$QID" status)" "the record's status"
e2e_run_bin "$Q" answer "$QID" --choice "Target v2 (Recommended)"
e2e_expect_equal 0 "$E2E_RC" "answer with the option's text"
e2e_run_bin "$Q" answer "$QID" --choice 1
e2e_expect_equal 4 "$E2E_RC" "answering an answered question"
e2e_run_bin "$Q" withdraw "$QID" --reason "late"
e2e_expect_equal 4 "$E2E_RC" "withdrawing an answered question"
e2e_expect_clean_edges

_q_case q-withdraw "a withdrawn question is not open (Q3)"
_add
QID=$(_id)
e2e_run_bin "$Q" withdraw "$QID" --reason "asked again in another form"
e2e_expect_equal 0 "$E2E_RC" "withdraw exit status"
e2e_expect_equal withdrawn "$(_field "$QID" status)" "the record's status"
e2e_run_bin "$Q" list
e2e_expect_no_out "$QID"
e2e_run_bin "$Q" list --status withdrawn
e2e_expect_out "$QID|withdrawn"
e2e_expect_clean_edges

# --- two adds at once (Q4) ---------------------------------------------------
_q_case q-concurrent "two processes add a question at the same moment, both trying the same id first: both are stored, under different ids"
mkdir -p "$E2E_DIR/sync"
HINT=q-20260101T000000Z-aaaaaa
cat > "$E2E_DIR/add.sh" <<SH
#!/usr/bin/env bash
cd "$E2E_REPO" || exit 1
# Wait for the other process, then add at once.
: > "$E2E_DIR/sync/ready.\$1"
while [ ! -e "$E2E_DIR/sync/ready.a" ] || [ ! -e "$E2E_DIR/sync/ready.b" ]; do :; done
FLOW_QUESTION_ID_HINT=$HINT "$E2E_ACTIVE_PLUGIN/$Q" add --situation "from \$1" --tried t \
  --option "one (Recommended)" --option two --recommendation r --blocking soft --risk k --command "proc \$1" --class default > "$E2E_DIR/out.\$1" 2>&1
SH
chmod +x "$E2E_DIR/add.sh"
( _e2e_git_env; "$E2E_DIR/add.sh" a & "$E2E_DIR/add.sh" b & wait )
printf 'two processes ran add with FLOW_QUESTION_ID_HINT=%s\n' "$HINT" | _e2e_art
e2e_run_bin "$Q" list
e2e_expect_equal 2 "$(printf '%s\n' "$E2E_OUT" | grep -c '|open|')" "open questions listed"
e2e_expect_equal 2 "$(printf '%s\n' "$E2E_OUT" | cut -d'|' -f1 | sort -u | grep -c .)" "distinct ids"
e2e_expect_out "|proc a|from a"
e2e_expect_out "|proc b|from b"
e2e_expect_clean_edges

# --- malformed questions are refused (Q5) ------------------------------------
_q_case q-missing-field "a question without its risk is refused with the field named, and nothing is stored (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --recommendation r --blocking yes --command c --class decision
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "missing required field: risk"
e2e_expect_equal 0 "$(ls "$E2E_REPO/.flow/questions" 2>/dev/null | grep -c '\.yaml$')" "stored records"
e2e_expect_clean_edges

_q_case q-four-options "a question with four options is refused (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --option c --option d --recommendation r --blocking yes --risk k --command c --class decision
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "options: at most three (got 4)"
e2e_expect_equal 0 "$(ls "$E2E_REPO/.flow/questions" 2>/dev/null | grep -c '\.yaml$')" "stored records"
e2e_expect_clean_edges

_q_case q-one-option "a question with one option is refused (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a" --recommendation r --blocking yes --risk k --command c --class decision
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "two or three are required"
e2e_expect_clean_edges

_q_case q-bad-blocking "a blocking level outside yes, soft and no is refused (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --recommendation r --blocking "by Friday" --risk k --command c --class decision
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "blocking must be yes, soft or no"
e2e_expect_clean_edges

# --- no write through a symlink (Q6) -----------------------------------------
_q_case q-symlink "the questions directory is a symlink to a directory outside the repository: nothing is written there (Q6)"
mkdir -p "$E2E_REPO/.flow" "$E2E_DIR/outside"
ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow/questions"
_add
e2e_expect_equal 2 "$E2E_RC" "add exit status"
e2e_expect_err "symlink"
e2e_expect_equal 0 "$(ls -A "$E2E_DIR/outside" | grep -c .)" "files written outside"
e2e_expect_clean_edges

# --- the journal (Q8) --------------------------------------------------------
_q_case q-journal "--journal records escalation-asked on add and escalation-resolved on answer, with the question id (Q8)"
_add --journal
QID=$(_id)
e2e_expect_line "JOURNAL=recorded"
e2e_expect_file_has .decisions/issue-340.md "type: escalation-asked"
e2e_expect_file_has .decisions/issue-340.md "question_id: $QID"
e2e_run_bin "$Q" answer "$QID" --choice 1 --by recommendation --journal
e2e_expect_line "JOURNAL=recorded"
e2e_expect_file_has .decisions/issue-340.md "type: escalation-resolved"
e2e_expect_file_has .decisions/issue-340.md "outcome: Target v2 (Recommended)"
e2e_expect_equal recommendation "$(_field "$QID" answered_by)" "answered_by"
e2e_expect_clean_edges

# --- /flow:status and /flow:resume (Q9, Q10) ----------------------------------
_q_case q-status "/flow:status lists the open question and not the answered one (Q9)"
_add --run run-a
OPEN_ID=$(_id)
_add --run run-b
DONE_ID=$(_id)
e2e_run_bin "$Q" answer "$DONE_ID" --choice 1
e2e_run_block commands/status.md OPEN_QUESTIONS_BLOCK
e2e_expect_line "STATE=open"
e2e_expect_line "COUNT=1"
e2e_expect_out "QUESTION=$OPEN_ID|open|decision|yes|340"
e2e_expect_no_out "$DONE_ID"
e2e_expect_clean_edges

_q_case q-status-none "/flow:status with no questions says none (Q9)"
e2e_run_block commands/status.md OPEN_QUESTIONS_BLOCK
e2e_expect_line "STATE=none"
e2e_expect_clean_edges

_q_case q-resume "/flow:resume shows the open question of its run, and not another run's (Q10)"
Q_ISSUE=341 _add --run 2026-11-07T00-00-00Z-a
MINE=$(_id)
Q_ISSUE=342 _add --run 2026-11-07T00-00-00Z-b
OTHER=$(_id)
e2e_run_block RUN_ID=2026-11-07T00-00-00Z-a GOAL_ID= commands/resume.md RESUME_QUESTIONS_BLOCK
e2e_expect_line "STATE=open"
e2e_expect_out "QUESTION=$MINE"
e2e_expect_no_out "$OTHER"
e2e_expect_clean_edges

_q_case q-resume-goal-issue "/flow:resume also shows an open question of its goal's issue that names no run (Q10)"
Q_ISSUE=343 _add
BYISSUE=$(_id)
e2e_run_block RUN_ID=2026-11-07T00-00-00Z-c GOAL_ID=issue-343 commands/resume.md RESUME_QUESTIONS_BLOCK
e2e_expect_line "STATE=open"
e2e_expect_out "QUESTION=$BYISSUE"
e2e_expect_clean_edges

# --- a subdirectory (Q11) -----------------------------------------------------
# _in_app <script under the plugin> [arguments] — run it in packages/app.
_in_app() {
  mkdir -p "$E2E_REPO/packages/app"
  printf 'code: %s (run in packages/app)\narguments: %s\n' "$1" "${*:2}" | _e2e_art
  _e2e_exec sh -c 'cd packages/app && s=$1 && shift && exec "$CLAUDE_PLUGIN_ROOT/$s" "$@"' sh "$@"
  printf -- '--- expectations\n' | _e2e_art
}
_q_case q-subdir "a question added in packages/app is stored at the repository top, listed there, and answered from packages/app (Q11)"
_in_app "$Q" add --situation "Two API versions fit" --tried "Read both changelogs" \
  --option "Target v2 (Recommended)" --option "Target v1" \
  --recommendation "v2 is the supported one" --blocking yes --risk "v1 is deprecated" \
  --command "/flow:start Phase 1" --class decision --issue 344
e2e_expect_equal 0 "$E2E_RC" "add exit status in packages/app"
QID=$(_id)
e2e_expect_equal yes "$([ -f "$E2E_REPO/.flow/questions/$QID.yaml" ] && echo yes || echo no)" "the record at the top"
e2e_expect_equal no "$([ -e "$E2E_REPO/packages/app/.flow" ] && echo yes || echo no)" "a .flow in packages/app"
e2e_run_bin "$Q" list
e2e_expect_line "$QID|open|decision|yes|344|-|/flow:start Phase 1|Two API versions fit"
e2e_run_block commands/status.md OPEN_QUESTIONS_BLOCK
e2e_expect_out "QUESTION=$QID|open|decision|yes|344"
_in_app "$Q" answer "$QID" --choice 1
e2e_expect_equal 0 "$E2E_RC" "answer exit status in packages/app"
e2e_expect_equal answered "$(_field "$QID" status)" "the record's status at the top"
e2e_expect_clean_edges

# --- the class a question is stored with (Q12) --------------------------------
_q_case q-class-missing "a question without its class is refused with the field named, and nothing is stored (Q12)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --recommendation r --blocking yes --risk k --command c
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "missing required field: class (--class)"
e2e_expect_equal 0 "$(ls "$E2E_REPO/.flow/questions" 2>/dev/null | grep -c '\.yaml$')" "stored records"
e2e_expect_clean_edges

_q_case q-class-unknown "a class outside decision, permission and default is refused (Q12)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --recommendation r --blocking yes --risk k --command c --class urgent
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "class must be decision, permission or default"
e2e_expect_equal 0 "$(ls "$E2E_REPO/.flow/questions" 2>/dev/null | grep -c '\.yaml$')" "stored records"
e2e_expect_clean_edges

_q_case q-class-journal "the class is stored and written to the escalation-asked artifact (Q12)"
Q_CLASS=permission _add --journal
QID=$(_id)
e2e_expect_equal permission "$(_field "$QID" class)" "the record's class"
e2e_expect_file_has .decisions/issue-340.md "class: permission"
e2e_expect_clean_edges

# --- /flow:resume asks with the stored class (Q13) ----------------------------
# _resume_classes <true|unset> — four open questions of one run: a decision, a
# permission, a default, and a record whose class was removed; then the resume
# block, with autonomous set in the repository's settings unless "unset".
_resume_classes() {
  if [ "$1" != unset ]; then
    mkdir -p "$E2E_REPO/.claude"
    printf '{"autonomous":%s}\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
  fi
  Q_CLASS=decision _add --run 2026-11-07T00-00-00Z-r; C_DEC=$(_id)
  Q_CLASS=permission _add --run 2026-11-07T00-00-00Z-r; C_PERM=$(_id)
  Q_CLASS=default _add --run 2026-11-07T00-00-00Z-r; C_DEF=$(_id)
  Q_CLASS=decision _add --run 2026-11-07T00-00-00Z-r; C_NONE=$(_id)
  python3 -c 'import sys, yaml
p = sys.argv[1]
r = yaml.safe_load(open(p))
r.pop("class", None)
open(p, "w").write(yaml.safe_dump(r, sort_keys=False))' "$E2E_REPO/.flow/questions/$C_NONE.yaml"
  printf 'four questions of run 2026-11-07T00-00-00Z-r: %s decision, %s permission, %s default, %s with its class removed; autonomous: %s\n' \
    "$C_DEC" "$C_PERM" "$C_DEF" "$C_NONE" "$1" | _e2e_art
  e2e_run_block RUN_ID=2026-11-07T00-00-00Z-r GOAL_ID= commands/resume.md RESUME_QUESTIONS_BLOCK
}

_q_case q-resume-class-autonomous "/flow:resume under autonomous: true asks a decision as flow:decision and a permission as flow:permission, takes the recommendation of a default, and leaves a record with no class open (Q13)"
_resume_classes true
e2e_expect_line "STATE=open"
e2e_expect_line "ASK=$C_DEC|flow:decision"
e2e_expect_line "ASK=$C_PERM|flow:permission"
e2e_expect_line "ASK=$C_DEF|take-recommendation"
e2e_expect_line "ASK=$C_NONE|leave-open"
e2e_expect_clean_edges

_q_case q-resume-class-attended "/flow:resume while attended asks a default, and a record with no class, with no class; decisions and permissions keep theirs (Q13)"
_resume_classes unset
e2e_expect_line "ASK=$C_DEC|flow:decision"
e2e_expect_line "ASK=$C_PERM|flow:permission"
e2e_expect_line "ASK=$C_DEF|ask"
e2e_expect_line "ASK=$C_NONE|ask"
e2e_expect_clean_edges

# --- answer and withdraw on an empty store (Q14) ------------------------------
_q_case q-empty-store "answer and withdraw where no question was ever stored exit 3 (no such question) and create nothing; a malformed id is still refused input (Q14)"
e2e_run_bin "$Q" answer q-20261107T000000Z-abcdef --choice 1
e2e_expect_equal 3 "$E2E_RC" "answer exit status"
e2e_expect_err "no question q-20261107T000000Z-abcdef"
e2e_run_bin "$Q" withdraw q-20261107T000000Z-abcdef --reason "no longer relevant"
e2e_expect_equal 3 "$E2E_RC" "withdraw exit status"
e2e_expect_err "no question q-20261107T000000Z-abcdef"
e2e_expect_equal no "$([ -e "$E2E_REPO/.flow/questions" ] && echo yes || echo no)" "a questions directory created"
e2e_run_bin "$Q" answer not-an-id --choice 1
e2e_expect_equal 1 "$E2E_RC" "answer exit status for a malformed id"
e2e_expect_clean_edges
