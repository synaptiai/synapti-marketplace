# shellcheck shell=bash
# End-to-end: the risk check of /flow:start Phase 1 (issue #327).
# RISK_CHECK_BLOCK from commands/start.md runs in a scratch repository, the
# way Claude Code runs it, on the files a change will modify, and says whether
# the change touches a risky area: a path matching the repository's declared
# design.riskAreas, or a fix hotspot, a file that at least
# design.hotspotFixCommits of the last 200 commits fixed. A risky change gets
# the design step before it is planned (references/design-step.md).
#
# The scratch repository's history, written below, is the source of every
# expected value: src/billing.sh has three fix commits (one a `fix(scope):`,
# one git's own `Revert "..."`, one written `Fix:`) and one `fixture:` commit,
# which is not a fix; src/ui.sh one feat; config/prod/app.yml none.
#
# Ways it can be wrong, written down before the scenarios:
#   K1 a file matching a declared risk area, or a hotspot, is reported normal
#   K2 a commit is counted as a fix by a substring (`fixture:`) or missed for
#      its letter case or git's Revert subject
#   K3 the threshold is off by one, or 0 does not turn the hotspot signal off
#   K4 a check that could not run (no files list, an empty one, not a git
#      repository) reports RISK=normal, which reads as "nothing risky"
#   K5 a risk-area pattern matches only one directory level, so a file deeper
#      below the declared directory is missed
#   K6 a setting of the wrong type stops the check instead of falling back
#
# One artifact per scenario goes to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _rk_setup <scenario> <purpose> — the scratch repository with the history
# described in the header.
_rk_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-327-x
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    mkdir -p src config/prod
    _c() { printf '%s\n' "$2" >> "$1"; git add "$1"; git commit -q -m "$3"; }
    _c src/billing.sh one 'feat(billing): charge the card'
    _c src/billing.sh two 'fix(billing): round half up, not down'
    _c src/ui.sh one 'feat(ui): show the total'
    _c src/billing.sh three 'Revert "feat(billing): retry a declined card"'
    _c src/billing.sh five 'fixture: add a sample cart'
    _c src/billing.sh four 'Fix: refund twice'
    _c config/prod/app.yml one 'chore: production settings'
  ) || _flow_assert_fail "$1: could not write the history"
  printf '%s\n' src/billing.sh ./src/ui.sh '' config/prod/app.yml > "$E2E_DIR/files"
  printf 'files list: %s\n' "$(tr '\n' ';' < "$E2E_DIR/files")" | _e2e_art
}

_rk_repo_settings() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
  printf 'repository settings: %s\n' "$1" | _e2e_art
}

_rk_run() { e2e_run_block "$@" commands/start.md RISK_CHECK_BLOCK; }

if _want risk-high; then
  _flow_test_begin "risk-high"
  _rk_setup risk-high "a declared risk area (config/*) and a fix hotspot (src/billing.sh, three fixes): RISK=high naming both files and why; the fixture: commit on src/billing.sh is not counted; src/ui.sh, with one feat, is not risky (K1, K2, K5)"
  _rk_repo_settings '{"design":{"riskAreas":["config/*"]}}'
  _rk_run RISK_FILES="$E2E_DIR/files"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "### Risk check"
  e2e_expect_line "STATE=ok"
  e2e_expect_line "RISK=high"
  e2e_expect_line "FILES_CHECKED=3"
  e2e_expect_line "HOTSPOT_WINDOW=8"
  e2e_expect_line "RISK_FILE=src/billing.sh|3 fix commits among the last 8 commits"
  e2e_expect_line "RISK_FILE=config/prod/app.yml|risk area config/*"
  e2e_expect_no_out "RISK_FILE=src/ui.sh"
  e2e_expect_clean_edges
fi

if _want risk-normal; then
  _flow_test_begin "risk-normal"
  _rk_setup risk-normal "no declared risk areas and the hotspot threshold at 4: no file is risky, RISK=normal and no RISK_FILE line (K1, K3)"
  _rk_repo_settings '{"design":{"hotspotFixCommits":4}}'
  _rk_run RISK_FILES="$E2E_DIR/files"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "RISK=normal"
  e2e_expect_no_out "RISK_FILE="
  e2e_expect_clean_edges
fi

if _want hotspot-off; then
  _flow_test_begin "hotspot-off"
  _rk_setup hotspot-off "design.hotspotFixCommits 0 turns the hotspot signal off: src/billing.sh is not risky and no history is read; the plugin default (3) makes it risky again (K3)"
  _rk_repo_settings '{"design":{"hotspotFixCommits":0}}'
  _rk_run RISK_FILES="$E2E_DIR/files"
  e2e_expect_line "RISK=normal"
  e2e_expect_line "HOTSPOT_WINDOW=0"
  rm -f "$E2E_REPO/.claude/settings.flow.json"
  _rk_run RISK_FILES="$E2E_DIR/files"
  e2e_expect_line "RISK=high"
  e2e_expect_line "RISK_FILE=src/billing.sh|3 fix commits among the last 8 commits"
  e2e_expect_clean_edges
fi

if _want not-run; then
  _flow_test_begin "not-run"
  _rk_setup not-run "a check that could not run says so and reports RISK=unknown, never normal: no RISK_FILES, an empty files list, and git finding no repository (K4)"
  _rk_run
  e2e_expect_equal 0 "$E2E_RC" "exit status with no RISK_FILES"
  e2e_expect_line "STATE=unavailable"
  e2e_expect_line "RISK=unknown"
  : > "$E2E_DIR/empty"
  _rk_run RISK_FILES="$E2E_DIR/empty"
  e2e_expect_line "STATE=unavailable"
  e2e_expect_line "RISK=unknown"
  e2e_expect_out "REASON=the files list is empty"
  # GIT_DIR naming no repository makes git find none, as in a plain directory.
  _rk_run RISK_FILES="$E2E_DIR/files" GIT_DIR="$E2E_DIR/no-such-repo"
  e2e_expect_line "RISK=unknown"
  e2e_expect_out "REASON=not inside a git work tree"
  e2e_expect_clean_edges
fi

if _want bad-settings; then
  _flow_test_begin "bad-settings"
  _rk_setup bad-settings "design.riskAreas that is not a list, and a hotspotFixCommits that is not a number: each is named in a WARN and its default used, and the check still runs (K6)"
  _rk_repo_settings '{"design":{"riskAreas":"config/*","hotspotFixCommits":"three"}}'
  _rk_run RISK_FILES="$E2E_DIR/files"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_err "WARN: design.riskAreas is not a list of strings"
  e2e_expect_err "WARN: design.hotspotFixCommits is not a whole number; 3 is used"
  e2e_expect_line "RISK=high"
  e2e_expect_line "RISK_FILE=src/billing.sh|3 fix commits among the last 8 commits"
  e2e_expect_no_out "RISK_FILE=config/prod/app.yml"
  e2e_expect_clean_edges
fi
