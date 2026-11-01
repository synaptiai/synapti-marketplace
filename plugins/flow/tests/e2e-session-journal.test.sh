# shellcheck shell=bash
# End-to-end: the session journal, the decision journal for work with no issue
# number (bin/journal-append.sh --session, bin/journal-record.sh --session).
#
# Each scenario runs the shipped helper in a scratch repository on a branch
# with no issue number, the way a goal with no linked issue and the tier hook
# call it. The file is named by the local calendar day, as the auto-log hooks
# name the session trail; a scenario that straddles midnight accepts either day.
#
# Ways it can be wrong, written down before the scenarios:
#   S1 --session writes somewhere other than <journal dir>/session-<day>.md,
#      or names the day another way than the auto-log hooks do (UTC, another
#      format), so log-commits.sh never finds the tracked session journal
#   S2 the session manifest is keyed issue (null, 0 or a crash) rather than
#      session: <day>
#   S3 a second record or a body append replaces the manifest or the body
#      instead of adding to it
#   S4 journal.dir is ignored for --session
#   S5 --session combined with --issue (or --file) is accepted, and one of
#      the two silently wins
#   S6 --issue stops writing issue-<N>.md
#
# The commands that read and write it. A session journal is one local
# calendar day of work with no issue number, not one branch's work, so a
# reader on such a branch loads today's file:
#   S7 /flow:pr and /flow:explain on a branch with no issue number report
#      STATE=empty while today's session journal holds entries
#   S8 they name the day differently from the writers, so the file the
#      helpers wrote is not the one they look for
#   S9 on an issue branch they read the session journal instead of, or as
#      well as, issue-<N>.md
#   S10 /flow:explain on such a branch leaves out today's auto-log trail
#      (auto-log/session-<day>.md), or lists another day's
#   S11 /flow:design and /flow:brainstorm on a branch with no issue number
#      write no decision section, or no manifest artifact, to the session
#      journal
#   S12 on an issue branch they write to the session journal

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "session journal: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _sj_file <dir under the repo> — the session journal the helper wrote there:
# today's, or yesterday's name when the run crossed midnight. Prints the path
# under the repository, or nothing.
_sj_file() {
  local d
  for d in "$SJ_DAY_AFTER" "$SJ_DAY_BEFORE"; do
    if [ -f "$E2E_REPO/$1/session-$d.md" ]; then printf '%s' "$1/session-$d.md"; return 0; fi
  done
  return 0
}

_sj_run_bin() {
  SJ_DAY_BEFORE=$(date +%Y-%m-%d)
  e2e_run_bin "$@"
  SJ_DAY_AFTER=$(date +%Y-%m-%d)
}

_sj_expect_session_file() {   # $1 = dir under the repo
  SJ_FILE=$(_sj_file "$1")
  if [ -n "$SJ_FILE" ]; then _E2E_EXTRA_FRAMES=1 _e2e_result pass "$1/session-<local day>.md was written"
  else _E2E_EXTRA_FRAMES=1 _e2e_result fail "$1/session-<local day>.md was written (found: $(ls "$E2E_REPO/$1" 2>/dev/null | tr '\n' ' '))"; fi
}

if _want sj-append; then
  _flow_test_begin "sj-append"
  e2e_new sj-append
  e2e_describe "journal-append.sh --session on a branch with no issue number writes the text to .decisions/session-<local day>.md and nothing else (S1)"
  e2e_repo feature/no-number
  _sj_run_bin bin/journal-append.sh --session --text "- tier journal line"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _sj_expect_session_file .decisions
  e2e_expect_file_has "$SJ_FILE" "- tier journal line"
  e2e_expect_equal "session-$SJ_DAY_AFTER.md" "$(cd "$E2E_REPO/.decisions" && ls *.md 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "the only journal file"
  e2e_expect_clean_edges
fi

if _want sj-record; then
  _flow_test_begin "sj-record"
  e2e_new sj-record
  e2e_describe "journal-record.sh --session creates a manifest keyed session: <day> with the artifact and no issue key (S1, S2)"
  e2e_repo feature/no-number
  _sj_run_bin bin/journal-record.sh --session --type goal-created --metadata goal_id=tidy-docs --metadata source=user
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _sj_expect_session_file .decisions
  MANIFEST=$(python3 - "$E2E_REPO/$SJ_FILE" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
m = yaml.safe_load(t.split("---\n")[1])
print("session=%s issue=%s types=%s goal=%s" % (m.get("session"), "issue" in m,
      ",".join(a["type"] for a in m["artifacts"]), m["artifacts"][0].get("goal_id")))
PY
)
  e2e_expect_equal "session=$SJ_DAY_AFTER issue=False types=goal-created goal=tidy-docs" "$MANIFEST" "the manifest"
  e2e_expect_clean_edges
fi

if _want sj-accumulate; then
  _flow_test_begin "sj-accumulate"
  e2e_new sj-accumulate
  e2e_describe "a second record and a body append on the same session journal add to it: two artifacts, the body line kept, the session key unchanged (S3)"
  e2e_repo feature/no-number
  _sj_run_bin bin/journal-record.sh --session --type goal-created --metadata goal_id=g1
  _sj_run_bin bin/journal-append.sh --session --text "- body entry"
  _sj_run_bin bin/journal-record.sh --session --type goal-evaluation --metadata goal_id=g1 --metadata result=achieved
  e2e_expect_equal 0 "$E2E_RC" "exit status of the last record"
  _sj_expect_session_file .decisions
  MANIFEST=$(python3 - "$E2E_REPO/$SJ_FILE" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
m = yaml.safe_load(t.split("---\n")[1])
print("session=%s types=%s" % (m.get("session"), ",".join(a["type"] for a in m["artifacts"])))
PY
)
  e2e_expect_equal "session=$SJ_DAY_AFTER types=goal-created,goal-evaluation" "$MANIFEST" "the manifest"
  e2e_expect_file_has "$SJ_FILE" "- body entry"
  e2e_expect_clean_edges
fi

if _want sj-journal-dir; then
  _flow_test_begin "sj-journal-dir"
  e2e_new sj-journal-dir
  e2e_describe "journal.dir set to notes in the repository settings: both helpers write notes/session-<day>.md, and no .decisions directory appears (S4)"
  e2e_repo feature/no-number
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"journal":{"dir":"notes"}}' > "$E2E_REPO/.claude/settings.flow.json"
  _sj_run_bin bin/journal-append.sh --session --text "- in notes"
  e2e_expect_equal 0 "$E2E_RC" "append exit status"
  _sj_run_bin bin/journal-record.sh --session --type goal-created --metadata goal_id=g2
  e2e_expect_equal 0 "$E2E_RC" "record exit status"
  _sj_expect_session_file notes
  e2e_expect_file_has "$SJ_FILE" "- in notes"
  e2e_expect_file_has "$SJ_FILE" "goal_id: g2"
  e2e_expect_equal "no" "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions exists"
  e2e_expect_clean_edges
fi

if _want sj-exclusive; then
  _flow_test_begin "sj-exclusive"
  e2e_new sj-exclusive
  e2e_describe "--session with --issue, or with --file, is refused with exit 1 and nothing is written (S5)"
  e2e_repo feature/issue-12-x
  _sj_run_bin bin/journal-record.sh --session --issue 12 --type goal-created
  e2e_expect_equal 1 "$E2E_RC" "record --session --issue exit status"
  e2e_expect_err "mutually exclusive"
  _sj_run_bin bin/journal-append.sh --session --issue 12 --text x
  e2e_expect_equal 1 "$E2E_RC" "append --session --issue exit status"
  e2e_expect_err "mutually exclusive"
  _sj_run_bin bin/journal-append.sh --session --file .decisions/other.md --text x
  e2e_expect_equal 1 "$E2E_RC" "append --session --file exit status"
  e2e_expect_err "mutually exclusive"
  e2e_expect_equal "no" "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions exists"
  e2e_expect_clean_edges
fi

if _want sj-issue-unchanged; then
  _flow_test_begin "sj-issue-unchanged"
  e2e_new sj-issue-unchanged
  e2e_describe "--issue still writes issue-<N>.md keyed issue: N, and no session journal (S6)"
  e2e_repo feature/issue-12-x
  _sj_run_bin bin/journal-record.sh --issue 12 --type goal-created --metadata goal_id=issue-12
  e2e_expect_equal 0 "$E2E_RC" "record exit status"
  _sj_run_bin bin/journal-append.sh --issue 12 --text "- issue entry"
  e2e_expect_equal 0 "$E2E_RC" "append exit status"
  e2e_expect_file_has .decisions/issue-12.md "issue: 12"
  e2e_expect_file_has .decisions/issue-12.md "- issue entry"
  e2e_expect_equal "" "$(_sj_file .decisions)" "a session journal"
  e2e_expect_clean_edges
fi

if _want sj-autolog-agrees; then
  _flow_test_begin "sj-autolog-agrees"
  e2e_new sj-autolog-agrees
  e2e_describe "after journal-record.sh --session, log-commits.sh on the same no-issue branch finds that tracked journal by its name and writes the commit to auto-log/session-<day>.md: the helpers and the hook name the day the same way (S1)"
  e2e_repo feature/no-number
  _sj_run_bin bin/journal-record.sh --session --type goal-created --metadata goal_id=g3
  e2e_expect_equal 0 "$E2E_RC" "record exit status"
  ( _e2e_git_env; cd "$E2E_REPO" && printf 'x\n' > x.txt && git add x.txt && git commit -q -m "feat: add x" ) \
    || _flow_assert_fail "sj-autolog-agrees: could not commit in the scratch repository"
  SJ_DAY_BEFORE=$(date +%Y-%m-%d)
  e2e_run_hook hooks/scripts/log-commits.sh "$(jq -cn --arg cwd "$E2E_REPO" '{cwd:$cwd,tool_input:{command:"git commit -m \"feat: add x\""}}')"
  SJ_DAY_AFTER=$(date +%Y-%m-%d)
  e2e_expect_equal 0 "$E2E_RC" "hook exit status"
  _sj_expect_session_file .decisions/auto-log
  e2e_expect_file_has "$SJ_FILE" 'commit "feat: add x"'
  e2e_expect_clean_edges
fi

# --- the commands that read and write the session journal --------------------

# _sj_cmd_repo <branch> — a scratch repository on <branch> with main at the
# first commit and one commit after it, gh answering for the repository, the
# branch's open PRs (none) and, failing, the review exceptions' ref lookup.
_sj_cmd_repo() {
  e2e_repo "$1"
  ( _e2e_git_env; cd "$E2E_REPO" && git branch -f main HEAD \
      && printf 'x\n' > x.txt && git add x.txt && git commit -q -m "feat: x" ) \
    || _flow_assert_fail "$E2E_NAME: could not set up the scratch repository"
  e2e_gh_fixture repo '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}'
  e2e_gh_fixture "open-prs-$(printf '%s' "$1" | tr / _)" '[]'
  e2e_gh_fail commit-main
}

# _sj_section <heading> — the lines of one ### section of the fence's output.
_sj_section() {
  printf '%s\n' "$E2E_OUT" | awk -v h="### $1" '$0 == h { f = 1; next } /^### / { f = 0 } f'
}

# _sj_manifest_types <file under the repo> — "<key>=<value> types=<the
# distinct artifact types, sorted>".
_sj_manifest_types() {
  python3 - "$E2E_REPO/$1" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
m = yaml.safe_load(t.split("---\n")[1])
key = "issue=%s" % m["issue"] if "issue" in m else "session=%s" % m.get("session")
print("%s types=%s" % (key, ",".join(sorted({a["type"] for a in m["artifacts"]}))))
PY
}

# _sj_day_of <session journal path> — the day in its name.
_sj_day_of() { local d="${1##*/session-}"; printf '%s' "${d%.md}"; }

if _want sj-pr-reads; then
  _flow_test_begin "sj-pr-reads"
  e2e_new sj-pr-reads
  e2e_describe "/flow:pr Phase 1 on feature/no-number, after journal-append.sh --session wrote today's session journal: the Decision Journal section names that file and carries its text (S7, S8)"
  _sj_cmd_repo feature/no-number
  _sj_run_bin bin/journal-append.sh --session --text "- chose the flat layout"
  SJ_BEFORE_READ=$SJ_DAY_BEFORE
  e2e_run_fence "$E2E_PLUGIN_DIR/commands/pr.md" '### Decision Journal'
  SJ_DAY_AFTER=$(date +%Y-%m-%d); SJ_DAY_BEFORE=$SJ_BEFORE_READ
  _sj_expect_session_file .decisions
  e2e_expect_equal "yes" "$(_sj_section 'Decision Journal' | grep -qxF "JOURNAL_FILE=$SJ_FILE" && echo yes || echo no)" "the Decision Journal section names $SJ_FILE"
  e2e_expect_equal "yes" "$(_sj_section 'Decision Journal' | grep -qxF -- '- chose the flat layout' && echo yes || echo no)" "the Decision Journal section carries the entry"
  e2e_expect_clean_edges
fi

if _want sj-pr-issue-branch; then
  _flow_test_begin "sj-pr-issue-branch"
  e2e_new sj-pr-issue-branch
  e2e_describe "/flow:pr Phase 1 on feature/issue-42-x with issue-42.md and a session journal: only issue-42.md is read (S9)"
  _sj_cmd_repo feature/issue-42-x
  e2e_gh_fixture issue-42 '{"title":"X","body":"x","labels":[]}'
  _sj_run_bin bin/journal-append.sh --session --text "- session entry"
  _sj_run_bin bin/journal-append.sh --issue 42 --text "- issue entry"
  e2e_run_fence "$E2E_PLUGIN_DIR/commands/pr.md" '### Decision Journal'
  e2e_expect_equal "yes" "$(_sj_section 'Decision Journal' | grep -qxF 'JOURNAL_FILE=.decisions/issue-42.md' && echo yes || echo no)" "the Decision Journal section names issue-42.md"
  e2e_expect_equal "no" "$(_sj_section 'Decision Journal' | grep -qF 'session entry' && echo yes || echo no)" "the Decision Journal section carries the session entry"
  e2e_expect_clean_edges
fi

if _want sj-explain-reads; then
  _flow_test_begin "sj-explain-reads"
  e2e_new sj-explain-reads
  e2e_describe "/flow:explain on feature/no-number with today's session journal and today's session auto-log trail, and a trail from another day: both of today's are loaded, the other day's is not (S7, S8, S10)"
  _sj_cmd_repo feature/no-number
  _sj_run_bin bin/journal-append.sh --session --text "- chose the flat layout"
  SJ_BEFORE_READ=$SJ_DAY_BEFORE
  mkdir -p "$E2E_REPO/.decisions/auto-log"
  printf '%s\n' '<!-- auto-log: today commit "feat: x" -->' > "$E2E_REPO/.decisions/auto-log/session-$SJ_DAY_AFTER.md"
  printf '%s\n' 'another day' > "$E2E_REPO/.decisions/auto-log/session-2001-01-01.md"
  e2e_run_fence "$E2E_PLUGIN_DIR/commands/explain.md" '### Decision Journal'
  SJ_DAY_AFTER=$(date +%Y-%m-%d); SJ_DAY_BEFORE=$SJ_BEFORE_READ
  _sj_expect_session_file .decisions
  e2e_expect_line "JOURNAL_FILE=$SJ_FILE"
  e2e_expect_line "- chose the flat layout"
  e2e_expect_line '<!-- auto-log: today commit "feat: x" -->'
  e2e_expect_line "AUTOLOG_FILES=1"
  e2e_expect_no_out "another day"
  e2e_expect_clean_edges
fi

if _want sj-explain-issue-branch; then
  _flow_test_begin "sj-explain-issue-branch"
  e2e_new sj-explain-issue-branch
  e2e_describe "/flow:explain on feature/issue-42-x with issue-42.md and a session journal: only issue-42.md is read (S9)"
  _sj_cmd_repo feature/issue-42-x
  e2e_gh_fixture issue-42 '{"title":"X","body":"x"}'
  _sj_run_bin bin/journal-append.sh --session --text "- session entry"
  _sj_run_bin bin/journal-append.sh --issue 42 --text "- issue entry"
  e2e_run_fence "$E2E_PLUGIN_DIR/commands/explain.md" '### Decision Journal'
  e2e_expect_line "JOURNAL_FILE=.decisions/issue-42.md"
  e2e_expect_line "- issue entry"
  e2e_expect_no_out "session entry"
  e2e_expect_clean_edges
fi

# _sj_decision <command.md> <decision fence marker> <manifest block> [NAME=value ...]
# — run a command's Phase 4 decision section fence, then its manifest block
# with the given settings, in the current scratch repository.
_sj_decision() {
  local md="$1" fence="$2" block="$3"
  shift 3
  e2e_run_fence "$E2E_PLUGIN_DIR/commands/$md" "$fence"
  e2e_expect_equal 0 "$E2E_RC" "$md decision section exit status"
  e2e_run_block "$@" "commands/$md" "$block"
  e2e_expect_equal 0 "$E2E_RC" "$md manifest block exit status"
}

if _want sj-design-writes; then
  _flow_test_begin "sj-design-writes"
  e2e_new sj-design-writes
  e2e_describe "/flow:design Phase 4 on feature/no-number: the Design Decision section and a design-decision artifact go to today's session journal (S11)"
  _sj_cmd_repo feature/no-number
  SJ_DAY_BEFORE=$(date +%Y-%m-%d)
  _sj_decision design.md '## Design Decision: {title}' DESIGN_MANIFEST_BLOCK DECISION_TITLE=flat-layout
  SJ_DAY_AFTER=$(date +%Y-%m-%d)
  _sj_expect_session_file .decisions
  e2e_expect_file_has "$SJ_FILE" "## Design Decision: {title}"
  e2e_expect_file_has "$SJ_FILE" "decision: flat-layout"
  e2e_expect_equal "session=$(_sj_day_of "$SJ_FILE") types=design-decision" "$(_sj_manifest_types "$SJ_FILE")" "the manifest"
  e2e_expect_clean_edges
fi

if _want sj-brainstorm-writes; then
  _flow_test_begin "sj-brainstorm-writes"
  e2e_new sj-brainstorm-writes
  e2e_describe "/flow:brainstorm Phase 4 on feature/no-number: the Brainstorm Decision section and a brainstorm-decision artifact go to today's session journal (S11)"
  _sj_cmd_repo feature/no-number
  SJ_DAY_BEFORE=$(date +%Y-%m-%d)
  _sj_decision brainstorm.md '## Brainstorm Decision: {topic}' BRAINSTORM_MANIFEST_BLOCK TOPIC=layout CHOSEN_APPROACH=flat N_OPTIONS=3
  SJ_DAY_AFTER=$(date +%Y-%m-%d)
  _sj_expect_session_file .decisions
  e2e_expect_file_has "$SJ_FILE" "## Brainstorm Decision: {topic}"
  e2e_expect_file_has "$SJ_FILE" "chosen: flat"
  e2e_expect_equal "session=$(_sj_day_of "$SJ_FILE") types=brainstorm-decision" "$(_sj_manifest_types "$SJ_FILE")" "the manifest"
  e2e_expect_clean_edges
fi

if _want sj-decisions-issue-branch; then
  _flow_test_begin "sj-decisions-issue-branch"
  e2e_new sj-decisions-issue-branch
  e2e_describe "/flow:design and /flow:brainstorm Phase 4 on feature/issue-42-x: both write issue-42.md, and no session journal (S12)"
  _sj_cmd_repo feature/issue-42-x
  SJ_DAY_BEFORE=$(date +%Y-%m-%d)
  _sj_decision design.md '## Design Decision: {title}' DESIGN_MANIFEST_BLOCK DECISION_TITLE=flat-layout
  _sj_decision brainstorm.md '## Brainstorm Decision: {topic}' BRAINSTORM_MANIFEST_BLOCK TOPIC=layout CHOSEN_APPROACH=flat N_OPTIONS=3
  SJ_DAY_AFTER=$(date +%Y-%m-%d)
  e2e_expect_file_has .decisions/issue-42.md "## Design Decision: {title}"
  e2e_expect_file_has .decisions/issue-42.md "## Brainstorm Decision: {topic}"
  e2e_expect_equal "issue=42 types=brainstorm-decision,design-decision" "$(_sj_manifest_types .decisions/issue-42.md)" "the manifest"
  e2e_expect_equal "" "$(_sj_file .decisions)" "a session journal"
  e2e_expect_clean_edges
fi
