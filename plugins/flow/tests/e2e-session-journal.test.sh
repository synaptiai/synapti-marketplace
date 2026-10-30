# shellcheck shell=bash
# End-to-end: the session journal, the decision journal for work with no issue
# number (bin/journal-append.sh --session, bin/journal-record.sh --session).
#
# Each scenario runs the shipped helper in a scratch repository on a branch
# with no issue number, the way a goal with no linked issue calls it. The
# file is named by the local calendar day, as the auto-log hooks name the
# session trail; a scenario that straddles midnight accepts either day.
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
