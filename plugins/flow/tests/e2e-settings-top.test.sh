# shellcheck shell=bash
# End-to-end: the command blocks that read the repository's settings files
# themselves, rather than through bin/cascade-resolve.sh, read them at the
# repository top, as the cascade does (#337).
#
# Four blocks read .claude/settings.flow.local.json and
# .claude/settings.flow.json directly: the marker trust list of the
# /flow:merge finding-ledger gate and of the /flow:status findings ledger
# (merge.markerTrust.allowedAssociations), the /flow:review agentTeams gate,
# and the trust list of the /flow:address review-cycle findings. Each
# scenario sets the value in the repository's settings at the top and runs
# the shipped block with the working directory in a subdirectory, as the
# Bash tool leaves it after a `cd`. The artifact for each scenario is written
# to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   T1 the /flow:merge gate, run in a subdirectory, does not read the top's
#      widened trust list, so a trusted CONTRIBUTOR's resolution marker is
#      called untrusted and the merge is blocked
#   T2 the /flow:status findings ledger, run in a subdirectory, does not count
#      the findings of a review whose author the top's settings trust
#   T3 the /flow:review agentTeams gate, run in a subdirectory, does not read
#      the top's agentTeams, so a team's setting is replaced by the plugin
#      default, and the source it names is not the top's file
#   T4 the /flow:address review-cycle findings, run in a subdirectory, do not
#      take a review from an author the top's settings trust, and report no
#      trusted marker
#   T5 the local file is not read at the top, or is read in place of the
#      project file when only the project file sets the value

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "settings at the top: jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

MERGE_MD="$E2E_PLUGIN_DIR/commands/merge.md"
STATUS_MD="$E2E_PLUGIN_DIR/commands/status.md"
SUB=packages/app
TRUST='{"merge":{"markerTrust":{"allowedAssociations":["OWNER","CONTRIBUTOR"]}}}'

# _write <path under the repository> <json>
_write() { mkdir -p "$E2E_REPO/${1%/*}"; printf '%s\n' "$2" > "$E2E_REPO/$1"; }

# _in <directory under the repository> <runner> [arguments] — run a harness
# runner with the working directory there, and name it in the artifact.
_in() {
  local dir="$1" top="$E2E_REPO"; shift
  printf 'working directory: %s\n' "$dir" | _e2e_art
  E2E_REPO="$top/$dir"
  "$@"
  E2E_REPO="$top"
}

_setup() {
  _flow_test_begin "$1"
  e2e_new "$2"; e2e_describe "$3"; e2e_repo feature/e2e
  mkdir -p "$E2E_REPO/$SUB"
  e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
}

_setup "/flow:merge ledger gate in a subdirectory reads the top's trust list (T1)" merge-trust-subdir \
  "the top's .claude/settings.flow.json trusts OWNER and CONTRIBUTOR; a CONTRIBUTOR resolves F1 and F2; the gate runs in $SUB"
_write .claude/settings.flow.json "$TRUST"
e2e_gh_fixture reviews-7 "$(jq -nc --arg b '<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F1|P1|logic|src/a.sh:3|open,F2|P2|style|src/b.sh:9|open] -->' '[{author_association:"OWNER",body:$b}]')"
e2e_gh_fixture comments-7 "$(jq -nc --arg b '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[F1,F2] ESCALATED:[] DISPUTED:[] -->' '[{author_association:"CONTRIBUTOR",body:$b}]')"
_in "$SUB" e2e_run_fence "$MERGE_MD" '### Finding-Ledger Gate' 7
e2e_expect_line "LEDGER_GATE_STATE=ok"
e2e_expect_no_out "none from trusted authors"
e2e_expect_clean_edges

_setup "/flow:status findings ledger in a subdirectory reads the top's trust list from the local file (T2, T5)" status-trust-subdir \
  "the top's .claude/settings.flow.local.json trusts OWNER and CONTRIBUTOR, its .claude/settings.flow.json trusts OWNER only; PR 7 (mine) has a CONTRIBUTOR review with a P1 finding; the ledger runs in $SUB"
_write .claude/settings.flow.local.json "$TRUST"
_write .claude/settings.flow.json '{"merge":{"markerTrust":{"allowedAssociations":["OWNER"]}}}'
e2e_gh_fixture user '{"login":"me"}'
e2e_gh_fixture prs '[{"number":7,"author":{"login":"me"},"assignees":[]}]'
e2e_gh_fixture reviews-7 "$(jq -nc --arg b '<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F1|P1|logic|a:1|open] -->' '[{author_association:"CONTRIBUTOR",body:$b}]')"
e2e_gh_fixture comments-7 '[]'
_in "$SUB" e2e_run_fence "$STATUS_MD" '### Findings Ledger'
e2e_expect_line "LEDGER_STATE=findings"
e2e_expect_line "TALLY_P1_in_fix_forward=1"
e2e_expect_clean_edges

_setup "/flow:review agentTeams gate in a subdirectory reads the top's setting and names its file (T3)" review-agentteams-subdir \
  "the top's .claude/settings.flow.json sets agentTeams false; the AGENTTEAMS_GATE block runs in $SUB"
_write .claude/settings.flow.json '{"agentTeams":false}'
_in "$SUB" e2e_run_block commands/review.md AGENTTEAMS_GATE
e2e_expect_line "Path A skipped: agentTeams=false (from $(cd "$E2E_REPO" && pwd -P)/.claude/settings.flow.json). Using Path B (single-session)."

_setup "/flow:address review-cycle findings in a subdirectory read the top's trust list (T4)" address-trust-subdir \
  "the top's .claude/settings.flow.json trusts OWNER and CONTRIBUTOR; the only review marker is a CONTRIBUTOR's; the block runs in $SUB"
_write .claude/settings.flow.json "$TRUST"
e2e_gh_fixture reviews-7 '[{"id":4123,"user":{"login":"rev"},"author_association":"CONTRIBUTOR","state":"COMMENTED","submitted_at":"2026-10-01T09:00:00Z","body":"<!-- FLOW_REVIEW_CYCLE:3 FINDINGS:[F7|P1|correctness|a.sh:1|open|HIGH|consensus] -->"}]'
_in "$SUB" e2e_run_block REPO=o/r PR_NUM=7 commands/address.md REVIEW_CYCLE_FINDINGS_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_out "FINDING=cycle=3 F7|"
e2e_expect_clean_edges
