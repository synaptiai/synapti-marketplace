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

# _add [extra args...] — a well-formed question for issue $Q_ISSUE (340).
Q_ISSUE=340
_add() {
  e2e_run_bin "$Q" add --situation "Two API versions fit" --tried "Read both changelogs" \
    --option "Target v2 (Recommended)" --option "Target v1" \
    --recommendation "v2 is the supported one" --blocking yes --risk "v1 is deprecated" \
    --command "/flow:start Phase 1" --issue "$Q_ISSUE" "$@"
}
_id() { printf '%s\n' "$E2E_OUT" | sed -n 's/^QUESTION_ID=//p'; }
_field() { python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1])).get(sys.argv[2]))' "$E2E_REPO/.flow/questions/$1.yaml" "$2"; }

# --- add, answer, withdraw, list, get (Q1-Q3, Q7) ----------------------------
_q_case q-roundtrip "a question is added, listed, answered with option 2, and no longer listed as open"
_add --pr 12 --run run-1
e2e_expect_equal 0 "$E2E_RC" "add exit status"
QID=$(_id)
e2e_expect_line "STATUS=open"
for f in situation tried recommendation blocking risk command issue pr run asked_at; do
  [ "$(_field "$QID" "$f")" != None ] && _e2e_result pass "the record has $f" || _e2e_result fail "the record has $f"
done
e2e_expect_equal "['Target v2 (Recommended)', 'Target v1']" "$(_field "$QID" options)" "the options, the recommended one first"
e2e_expect_equal "*" "$(cat "$E2E_REPO/.flow/questions/.gitignore" 2>/dev/null)" "the questions directory ignores itself"
e2e_run_bin "$Q" list
e2e_expect_line "$QID|open|yes|340|12|/flow:start Phase 1|Two API versions fit"
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
  --option "one (Recommended)" --option two --recommendation r --blocking soft --risk k --command "proc \$1" > "$E2E_DIR/out.\$1" 2>&1
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
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --recommendation r --blocking yes --command c
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "missing required field: risk"
e2e_expect_equal 0 "$(ls "$E2E_REPO/.flow/questions" 2>/dev/null | grep -c '\.yaml$')" "stored records"
e2e_expect_clean_edges

_q_case q-four-options "a question with four options is refused (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --option c --option d --recommendation r --blocking yes --risk k --command c
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "options: at most three (got 4)"
e2e_expect_equal 0 "$(ls "$E2E_REPO/.flow/questions" 2>/dev/null | grep -c '\.yaml$')" "stored records"
e2e_expect_clean_edges

_q_case q-one-option "a question with one option is refused (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a" --recommendation r --blocking yes --risk k --command c
e2e_expect_equal 1 "$E2E_RC" "add exit status"
e2e_expect_err "two or three are required"
e2e_expect_clean_edges

_q_case q-bad-blocking "a blocking level outside yes, soft and no is refused (Q5)"
e2e_run_bin "$Q" add --situation s --tried t --option "a (Recommended)" --option b --recommendation r --blocking "by Friday" --risk k --command c
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
e2e_expect_out "QUESTION=$OPEN_ID|open|yes|340"
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
