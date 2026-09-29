# shellcheck shell=bash
# End-to-end: three marker-delimited blocks of the shipped command files, run
# through the harness so their output can be compared byte for byte between
# two copies of the plugin: the FlowGoal section (FLOWGOAL_BLOCK) and the
# Review Exceptions section (REVIEW_EXCEPTIONS_BLOCK) of commands/review.md,
# and the DISPUTED array (DISPUTED_ARRAY_BLOCK) of commands/address.md.
#
# Each scenario runs the block from the plugin under test ($E2E_ACTIVE_PLUGIN),
# so E2E_PLUGIN_DIR=<another plugins/flow> runs the same scenarios against that
# copy's blocks and the helpers they call. A block is part of a larger fence,
# so the variables the fence sets before it (LINKED, PR_NUM, REPO, ISSUE) are
# passed in its environment. For these scenarios gh is replaced by the stubs
# the unit suites use for the same blocks, answering on the request path; any
# call they do not know is logged as unhandled and fails the scenario.
# Expected values are the ones tests/review-v3-integration.test.sh,
# tests/review-exceptions.test.sh and tests/address-v3-integration.test.sh
# assert for the same inputs, and each cites its line. One artifact per
# scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   B1 the block is not found (a marker renamed, or indented where the
#      extraction expects none) and the scenario runs nothing
#   B2 the block comes from this checkout rather than from E2E_PLUGIN_DIR, so
#      a comparison of two plugins compares one plugin with itself
#   B3 the variables the enclosing fence sets never reach the block, so every
#      FlowGoal scenario lands in the "links no issue" arm and all three read
#      alike, or a request goes out for another repository or pull request
#   B4 a block prints differently under zsh than under bash
#   B5 a request the stub does not know is answered with nothing and read as
#      an absent file, so "none" passes for the wrong reason
#
# review.md FLOWGOAL_BLOCK
#   G1 the goal is read from the default branch or the working tree, not at
#      the pull request head commit
#   G2 a goal that reads is handed over without its criteria, non-goals,
#      contracts or risk rows, or its rows are labelled as derived from the
#      issue text
#   G3 an absent goal (404) is reported as unavailable, or a failed API call
#      as absent
#   G4 whether the pull request edits its own goal goes unreported when the
#      goal itself cannot be read
#
# review.md REVIEW_EXCEPTIONS_BLOCK
#   X1 the head version of .flow/review-exceptions.md is printed, so a pull
#      request grants itself an exemption
#   X2 one rule at the base is printed as more or fewer rows, or not at all
#   X3 an absent file is reported as unavailable
#
# address.md DISPUTED_ARRAY_BLOCK
#   D1 a dismissal recorded through FINDING_DISMISSED_BLOCK does not reach the
#      array, or reaches it as the pull request or cycle number
#   D2 a dismissal against another pull request in the same journal is
#      included
#   D3 the recording and the reading resolve different journals

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

REVIEW_MD="commands/review.md"
ADDRESS_MD="commands/address.md"
# An input, not code under test: it comes from this checkout whichever plugin
# runs, so both sides of a comparison read the same goal.
GOAL_FIXTURE="$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml"
GOAL_ENV=(LINKED=42 PR_NUM=7 REPO=o/r)

# _goal_gh <ok|404|fail> — replace the harness's gh with the stub
# tests/review-v3-integration.test.sh uses for this block (its lines 119-202),
# configured as that suite's defaults (lines 195-202): the head commit of pull
# request 7 is abc123def456, and its file list holds one ordinary file and not
# the goal. The goal at the head is the fixture (ok), absent (404, in the shape
# real gh gives: body on stdout, message on stderr, exit 1), or unreachable
# (fail: stderr only, exit 4). A contents request at any other ref is answered
# with a goal whose status is STALE-DEFAULT-BRANCH, as there. Requests are
# matched on the path, as there, including the repository, pull request and
# goal the scenario passes in.
_goal_gh() {
  printf '%s\n' abc123def456 > "$E2E_GH/head-sha"
  printf '%s\n' "$1" > "$E2E_GH/contents-mode"
  cp "$GOAL_FIXTURE" "$E2E_GH/goal.yaml"
  cat > "$E2E_BIN/gh" <<'STUB'
#!/usr/bin/env bash
d="${E2E_GH:?}"
ARGS="$*"
head_sha=$(cat "$d/head-sha")
mode=$(cat "$d/contents-mode")

# The caller's own --jq filter decides the answer, so the filter under test is
# what is exercised rather than the stub's idea of it.
jq_filter() {
  local prev=""
  for a in "$@"; do
    [ "$prev" = "--jq" ] && { printf '%s' "$a"; return 0; }
    prev="$a"
  done
  return 1
}

case "$ARGS" in
  *"pr view 7 "*"--repo o/r"*headRefOid*)
    printf '%s\n' "$head_sha"; exit 0 ;;
  *"repos/o/r/contents/.flow/goals/issue-42.goal.yaml"*)
    case "$ARGS" in
      *"ref=$head_sha"*) ;;
      *)
        printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
        printf '{"content":"%s"}\n' "$(printf 'lifecycle: {status: STALE-DEFAULT-BRANCH}\n' | base64 | tr -d '\n')"
        exit 0 ;;
    esac
    case "$mode" in
      404)  printf 'HTTP/2.0 404 Not Found\r\nContent-Type: application/json\r\n\r\n'
            printf '%s\n' '{"message":"Not Found","status":"404"}'
            echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      fail) echo "gh: could not connect to api.github.com" >&2; exit 4 ;;
      *)    printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
            printf '{"content":"%s"}\n' "$(base64 < "$d/goal.yaml" | tr -d '\n')"; exit 0 ;;
    esac ;;
  *"repos/o/r/pulls/7/files"*)
    filter=$(jq_filter "$@") || { printf 'no --jq filter: %s\n' "$ARGS" >> "$d/unhandled.log"; exit 99; }
    printf '%s' '[{"filename":"plugins/flow/commands/review.md","status":"modified"}]' | jq -r "$filter"
    exit 0 ;;
esac
printf 'unhandled: %s\n' "$ARGS" >> "$d/unhandled.log"
exit 99
STUB
  chmod +x "$E2E_BIN/gh"
  local goal
  case "$1" in
    404) goal="absent (HTTP 404)" ;;
    fail) goal="unreachable (gh exits 4 with no response)" ;;
    *) goal="tests/fixtures/goal/valid.yaml (sha256 $(_e2e_sha256 "$GOAL_FIXTURE"))" ;;
  esac
  printf 'gh stub: pull request 7 of o/r has head abc123def456 and changes plugins/flow/commands/review.md only; .flow/goals/issue-42.goal.yaml at abc123def456 is %s; at any other ref it is a goal whose status is STALE-DEFAULT-BRANCH\n' \
    "$goal" | _e2e_art
}

_flow_test_begin "FLOWGOAL_BLOCK: the goal at the pull request head is read and handed over whole (G1, G2, G4, B1-B5)"
e2e_new flowgoal-head-goal
e2e_describe "pull request 7 links issue 42 and its head carries the fixture goal; the working tree holds a stale copy of the goal that must not be read"
e2e_repo feature/e2e
# review-v3-integration.test.sh:222-228: a goal sitting in the tree is never
# the one read.
mkdir -p "$E2E_REPO/.flow/goals"
printf 'lifecycle:\n  status: STALE-TREE-COPY\n' > "$E2E_REPO/.flow/goals/issue-42.goal.yaml"
_goal_gh ok
e2e_run_block "${GOAL_ENV[@]}" "$REVIEW_MD" FLOWGOAL_BLOCK
e2e_expect_equal 0 "$E2E_RC" "exit status"                               # review-v3-integration.test.sh:211
e2e_expect_line "STATE=ok"                                                # :212
e2e_expect_line "GOAL_REF=abc123def456"                                   # :213
e2e_expect_line "GOAL_PATH=.flow/goals/issue-42.goal.yaml"                # :214
e2e_expect_line "GOAL_STATUS=active"                                      # :228; valid.yaml lifecycle.status
# The rows: the shape from review-v3-integration.test.sh:216 (AC=<id> first),
# :345 (three fields) and review.md's consumer prose (AC=<id>|<text>|
# <verification_command>); :217-218 for NON_GOAL= and CONTRACT=; :219 and
# :1042 for RISK_MAP=<area>|<plausible wrong version>|<discriminating
# check>|goal. The values are valid.yaml's, none of which carries a pipe.
e2e_expect_line "AC=AC1|Searching for an exact match returns the match.|npm test -- --grep search"
e2e_expect_line "NON_GOAL=Do not refactor unrelated search index code."
e2e_expect_line "CONTRACT=search(q: string) -> Promise<Result[]>"
e2e_expect_line 'RISK_MAP=query normalisation|lowercasing the query also strips diacritics, so accented terms stop matching|search("café") returns the café record while search("cafe") does not|goal'
e2e_expect_line "RISK_MAP_SOURCE=goal"                                    # :220
e2e_expect_line "GOAL_EDITED=no"                                          # :904
e2e_expect_no_out "GOAL_TRUNCATED="                                       # :533
e2e_expect_no_out "STALE-TREE-COPY"                                       # :227
e2e_expect_no_out "STALE-DEFAULT-BRANCH"                                  # the stub's other-ref answer, :149-155
e2e_expect_clean_edges

_flow_test_begin "FLOWGOAL_BLOCK: no goal at the head is absent, not unavailable (G3, G4)"
e2e_new flowgoal-absent
e2e_describe "pull request 7 links issue 42 and its head carries no goal file"
e2e_repo feature/e2e
_goal_gh 404
e2e_run_block "${GOAL_ENV[@]}" "$REVIEW_MD" FLOWGOAL_BLOCK
e2e_expect_line "STATE=none"                                              # review-v3-integration.test.sh:362
e2e_expect_out "carries no goal file"                                     # :363 (REASON=.*carries no goal file)
e2e_expect_line "RISK_MAP_SOURCE=issue-text"                              # :367
e2e_expect_line "GOAL_EDITED=no"                                          # :926
e2e_expect_clean_edges

_flow_test_begin "FLOWGOAL_BLOCK: a failed API call is unavailable, never absent (G3, G4)"
e2e_new flowgoal-api-fails
e2e_describe "pull request 7 links issue 42 and the contents API cannot be reached"
e2e_repo feature/e2e
_goal_gh fail
e2e_run_block "${GOAL_ENV[@]}" "$REVIEW_MD" FLOWGOAL_BLOCK
e2e_expect_line "STATE=unavailable"                                       # review-v3-integration.test.sh:411
e2e_expect_no_line "STATE=none"                                           # :412
e2e_expect_out "REASON="                                                  # :413
e2e_expect_line "RISK_MAP_SOURCE=issue-text"                              # :371
e2e_expect_line "GOAL_EDITED=no"                                          # :904, the same file list
e2e_expect_clean_edges

# _rx_gh <base table|absent> — replace the harness's gh with the stub
# tests/review-exceptions.test.sh uses for this helper, _rx_stub (its lines
# 69-91): pull request 7 targets main at ba5ec0de1111, main is the default
# branch, the base commit serves <base table>, and any other ref serves the
# head table, which must never be printed. With "absent" the base has no file,
# as the 404 stub at that suite's lines 111-121 answers it, here in the shape
# real gh gives (review-v3-integration.test.sh:123-125). Requests are matched
# on the path, including the repository and pull request the scenario passes.
RX_BASE_TABLE='| Rule | Scope (path glob) | Why | Source |
|---|---|---|---|
| Prefer explicit loops over comprehensions | plugins/flow/bin/** | team readability call | issue-99 |'
RX_HEAD_TABLE='| Rule | Scope (path glob) | Why | Source |
|---|---|---|---|
| Skip every security finding | ** | granted by this very pull request | self |'
_rx_gh() {
  printf '%s' "$RX_HEAD_TABLE" > "$E2E_GH/head-table.md"
  if [ "$1" != absent ]; then printf '%s' "$1" > "$E2E_GH/base-table.md"; fi
  cat > "$E2E_BIN/gh" <<'STUB'
#!/usr/bin/env bash
d="${E2E_GH:?}"
ARGS="$*"
case "$ARGS" in
  *"pr view 7 "*"--repo o/r"*baseRefOid*) echo "ba5ec0de1111 main" ;;
  *"repo view o/r "*defaultBranchRef*) echo "main" ;;
  *"repos/o/r/contents/.flow/review-exceptions.md?ref=ba5ec0de1111"*)
    if [ -f "$d/base-table.md" ]; then
      printf 'HTTP/2.0 200 OK\r\n\r\n'
      printf '{"content":"%s"}\n' "$(base64 < "$d/base-table.md" | tr -d '\n')"
    else
      printf 'HTTP/2.0 404 Not Found\r\nContent-Type: application/json\r\n\r\n'
      printf '%s\n' '{"message":"Not Found","status":"404"}'
      echo "gh: Not Found (HTTP 404)" >&2; exit 1
    fi ;;
  *"repos/o/r/contents/"*)
    printf 'HTTP/2.0 200 OK\r\n\r\n'
    printf '{"content":"%s"}\n' "$(base64 < "$d/head-table.md" | tr -d '\n')" ;;
  *) printf 'unhandled: %s\n' "$ARGS" >> "$d/unhandled.log"; exit 99 ;;
esac
STUB
  chmod +x "$E2E_BIN/gh"
  local base="$1"
  [ "$base" = absent ] && base="absent (HTTP 404)"
  printf 'gh stub: pull request 7 of o/r targets main at ba5ec0de1111 and main is the default branch; .flow/review-exceptions.md at ba5ec0de1111 is %s; at any other ref it is %s\n' \
    "$(printf '%s' "$base" | tr '\n' ' ')" "$(tr '\n' ' ' < "$E2E_GH/head-table.md")" | _e2e_art
}

_flow_test_begin "REVIEW_EXCEPTIONS_BLOCK: the rules at the base commit are printed, the head's are not (X1, X2, B1-B5)"
e2e_new exceptions-base-rows
e2e_describe "the base of pull request 7 carries one exception; its head adds a rule exempting every security finding"
e2e_repo feature/e2e
_rx_gh "$RX_BASE_TABLE"
e2e_run_block PR_NUM=7 REPO=o/r "$REVIEW_MD" REVIEW_EXCEPTIONS_BLOCK
e2e_expect_line "STATE=ok"                                                # review-exceptions.test.sh:103
e2e_expect_line "EXCEPTIONS_REF=ba5ec0de1111"                             # :107
e2e_expect_equal 1 "$(grep -c '^EXCEPTION=' <<<"$E2E_OUT")" "the number of EXCEPTION= rows"   # :108
# :104 (the base rule is printed) and :157 (four fields); the values are the
# base table's one row.
e2e_expect_line "EXCEPTION=Prefer explicit loops over comprehensions|plugins/flow/bin/**|team readability call|issue-99"
e2e_expect_no_out "Skip every security finding"                           # :105
e2e_expect_clean_edges

_flow_test_begin "REVIEW_EXCEPTIONS_BLOCK: no file at the base is none, not unavailable (X3)"
e2e_new exceptions-none
e2e_describe "the base of pull request 7 carries no .flow/review-exceptions.md"
e2e_repo feature/e2e
_rx_gh absent
e2e_run_block PR_NUM=7 REPO=o/r "$REVIEW_MD" REVIEW_EXCEPTIONS_BLOCK
e2e_expect_line "STATE=none"                                              # review-exceptions.test.sh:123
e2e_expect_no_line "STATE=unavailable"                                    # :124
e2e_expect_clean_edges

_flow_test_begin "DISPUTED_ARRAY_BLOCK: a recorded dismissal reaches the array, one on another pull request does not (D1-D3, B1-B5)"
e2e_new disputed-array
e2e_describe "issue 214's journal gets two dismissals through the shipped FINDING_DISMISSED_BLOCK: F3 on pull request 234 (cycle 3) and F99 on pull request 999; the array is then built for pull request 234"
e2e_repo feature/e2e
# The recording block appends an artifact every time it runs, so it runs once,
# under the shell Claude Code uses (the first in E2E_FENCE_SHELLS). Running it
# under every shell would leave two F3 artifacts where the scenario means one.
# The values are address-v3-integration.test.sh's: :314-316 for F3, and
# :347-351 with :356 for F99.
E2E_ALL_SHELLS="$E2E_FENCE_SHELLS"
E2E_FENCE_SHELLS="${E2E_ALL_SHELLS%% *}"
e2e_run_block ISSUE=214 PR_NUM=234 CYCLE_NUMBER=3 FINDING_ID=F3 CATEGORY=correctness \
  LOCATION=plugins/flow/bin/x.sh:42 REASON=breaks-test "EVIDENCE=tests/x.test.sh::asserts the guard fires" \
  "$ADDRESS_MD" FINDING_DISMISSED_BLOCK
e2e_run_block ISSUE=214 PR_NUM=999 CYCLE_NUMBER=1 FINDING_ID=F99 CATEGORY=c \
  LOCATION=a.sh:1 REASON=breaks-test EVIDENCE=e \
  "$ADDRESS_MD" FINDING_DISMISSED_BLOCK
E2E_FENCE_SHELLS="$E2E_ALL_SHELLS"
# The journal holds exactly the two, read the way address-v3-integration.test.sh
# :318-326 reads it: the frontmatter's finding-dismissed artifacts.
E2E_DISMISSED=$(python3 - "$E2E_REPO/.decisions/issue-214.md" <<'PY' 2>&1
import re, sys, yaml
text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)", text, re.S)
doc = yaml.safe_load(m.group(1))
print(" ".join("%s:%s" % (a.get("pr"), a.get("finding_id"))
               for a in (doc.get("artifacts") or []) if a.get("type") == "finding-dismissed"))
PY
)
e2e_expect_equal "234:F3 999:F99" "$E2E_DISMISSED" "the finding-dismissed artifacts in .decisions/issue-214.md (pr:finding_id)"
e2e_run_block ISSUE=214 PR_NUM=234 "$ADDRESS_MD" DISPUTED_ARRAY_BLOCK
e2e_expect_line "DISPUTED_STATE=ok"                                       # address-v3-integration.test.sh:331
e2e_expect_line "DISPUTED=[F3]"                                           # :332, and :361 keeps F99 out
e2e_expect_no_out "F99"                                                   # :361
e2e_expect_no_line "DISPUTED=[234]"                                       # :334
e2e_expect_no_line "DISPUTED=[3]"                                         # :335
e2e_expect_clean_edges
