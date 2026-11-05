# shellcheck shell=bash
# End-to-end: what a review finding needs before it counts, and what each
# review cycle counts (issue #326). FINDING_ROUTE_BLOCK and FINDING_POST_BLOCK
# from commands/review.md run in a scratch repository, the way Claude Code
# runs them, with the one set of findings a review of a pull request raised:
#
#   P1A  P1  a trigger, HIGH
#   P2A  P2  a trigger, MEDIUM
#   P3A  P3  a trigger, MEDIUM
#   P2N  P2  no trigger, HIGH
#
# The same rows are routed as cycle 1, cycle 2 and cycle 3, one scenario and
# one artifact each, so the artifacts side by side show what a later cycle
# stops counting. The expected values come from the rule in the issue: a
# finding with no trigger is LOW whatever its confidence; from cycle 2 a P3,
# and from cycle 3 a P2, is listed and not counted; a P1 always counts.
#
# Ways it can be wrong, written down before the scenarios:
#   R1 the routing block does not pass the cycle, so every cycle routes as
#      cycle 1 and the rule never applies
#   R2 a finding with no trigger is counted at its priority, or on your own
#      pull request it is posted instead of sent back to step 5
#   R3 a P1 stops counting in a later cycle, or a P2 stops counting in cycle 2
#   R4 a finding set aside still reaches the marker the merge gate reads, or
#      the header the body must carry
#   R5 the posting block accepts a body that shows a finding set aside in the
#      shape of a counted one, which tells the author it still blocks
#   R6 the routing block runs with no cycle number at all
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

_rc_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-326-x
  printf '%s\n' \
    'P1A|P1|correctness|src/route.sh:12|HIGH|unchallenged|code-reviewer|an empty --input path → the router reads stdin and posts an empty marker' \
    'P2A|P2|error-handling|src/route.sh:40|MEDIUM|unchallenged|error-handler-inspector|gh is not authenticated → the step exits 0 and reports a clean review' \
    'P3A|P3|conventions|README.md:9|MEDIUM|unchallenged|convention-checker|a reader runs the documented --cycel flag → unknown argument' \
    'P2N|P2|error-handling|src/route.sh:51|HIGH|unchallenged|error-handler-inspector|' > "$E2E_DIR/rows"
}

# _rc_route <mode> [NAME=value ...] — FINDING_ROUTE_BLOCK with its placeholder
# replaced by the rows. The block prints the path mktemp chose, which differs
# on every run, so it runs once per shell and the outputs are compared without
# that line.
_rc_route() {
  local mode="$1" sh first="" first_out="" first_err="" first_rc=""; shift
  if ! (cd "$E2E_ACTIVE_PLUGIN" && flow_block commands/review.md FINDING_ROUTE_BLOCK) > "$E2E_DIR/route.raw"; then
    _flow_assert_fail "$E2E_NAME: FINDING_ROUTE_BLOCK not found"
    return 0
  fi
  printf 'rows: %s\n' "$(tr '\n' ';' < "$E2E_DIR/rows")" | _e2e_art
  for sh in $E2E_FENCE_SHELLS; do
    awk -v rows="$E2E_DIR/rows" '/^\{one row per consolidated finding/ { while ((getline l < rows) > 0) print l; next } { print }' \
      "$E2E_DIR/route.raw" > "$E2E_DIR/fence.sh.raw"
    E2E_FENCE_SHELLS="$sh" _e2e_run_code "commands/review.md (block FINDING_ROUTE_BLOCK)" "" REVIEW_MODE="$mode" PR_NUM=7 \
      FINDING_TOTAL="$(grep -c . "$E2E_DIR/rows")" "$@"
    if [ -z "$first" ]; then
      first="$sh"; first_out="$E2E_OUT"; first_err="$E2E_ERR"; first_rc="$E2E_RC"
    else
      e2e_expect_equal "$(grep -v '^FINDING_ROWS_FILE=' <<<"$first_out")" "$(grep -v '^FINDING_ROWS_FILE=' <<<"$E2E_OUT")" \
        "routing block stdout under $sh, without the rows file path, compared with $first"
    fi
  done
  E2E_OUT="$first_out"; E2E_ERR="$first_err"; E2E_RC="$first_rc"
}

_rc_gh_stub() {
  cat > "$E2E_BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo o/r ;;
  "pr review") printf '%s\n' "$@" > "$E2E_DIR/gh-review.log" ;;
  *) printf 'unhandled: %s\n' "$*" >> "$E2E_GH/unhandled.log"; exit 99 ;;
esac
STUB
  chmod +x "$E2E_BIN/gh"
}

if _want cycle-1; then
  _flow_test_begin "cycle-1"
  _rc_setup cycle-1 "cycle 1 of someone else's pull request: P1A, P2A and P3A count; P2N names no trigger, so it is investigated and decides nothing (R1, R2)"
  _rc_route external CYCLE_NUMBER=1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "FINDINGS_HEADER=P1: 1, P2: 1, P3: 1 · Needs investigation: 1"
  e2e_expect_line "MARKER_ROWS=P1A|P1|correctness|src/route.sh:12|open|HIGH|unchallenged,P2A|P2|error-handling|src/route.sh:40|open|MEDIUM|unchallenged,P3A|P3|conventions|README.md:9|open|MEDIUM|unchallenged"
  e2e_expect_line "NEEDS_INVESTIGATION=P2N"
  e2e_expect_line "NO_TRIGGER=P2N"
  e2e_expect_line "NOT_COUNTED="
  e2e_expect_line "DECISION=REQUEST_CHANGES"
  e2e_expect_err "finding 'P2N' from error-handler-inspector names no trigger — routed LOW"
  e2e_expect_clean_edges
fi

if _want cycle-2; then
  _flow_test_begin "cycle-2"
  _rc_setup cycle-2 "cycle 2 of the same findings: P3A is listed and not counted, P1A and P2A still count (R1, R3, R4)"
  _rc_route external CYCLE_NUMBER=2
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "FINDINGS_HEADER=P1: 1, P2: 1, P3: 0 · Needs investigation: 1"
  e2e_expect_line "MARKER_ROWS=P1A|P1|correctness|src/route.sh:12|open|HIGH|unchallenged,P2A|P2|error-handling|src/route.sh:40|open|MEDIUM|unchallenged"
  e2e_expect_line "NOT_COUNTED=P3A"
  e2e_expect_line "NOT_COUNTED_PRIORITIES=P3A:P3"
  e2e_expect_line "NEEDS_INVESTIGATION=P2N"
  e2e_expect_line "DECISION=REQUEST_CHANGES"
  e2e_expect_line "ROUTED_TOTAL=2"
  e2e_expect_clean_edges
fi

if _want cycle-3; then
  _flow_test_begin "cycle-3"
  _rc_setup cycle-3 "cycle 3 of the same findings: only P1A counts; P2A, P2N and P3A are listed and not counted, and none is investigated (R1, R3, R4)"
  _rc_route external CYCLE_NUMBER=3
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "FINDINGS_HEADER=P1: 1, P2: 0, P3: 0 · Needs investigation: 0"
  e2e_expect_line "MARKER_ROWS=P1A|P1|correctness|src/route.sh:12|open|HIGH|unchallenged"
  e2e_expect_line "NOT_COUNTED=P2A,P3A,P2N"
  e2e_expect_line "NO_TRIGGER="
  e2e_expect_line "DECISION=REQUEST_CHANGES"
  e2e_expect_line "ROUTED_TOTAL=1"
  e2e_expect_clean_edges
fi

if _want own-pr-no-trigger; then
  _flow_test_begin "own-pr-no-trigger"
  _rc_setup own-pr-no-trigger "your own pull request, cycle 1: P2N names no trigger, so routing stops and sends the review back to step 5 naming it, and nothing can be posted (R2)"
  _rc_route self CYCLE_NUMBER=1
  e2e_expect_equal 1 "$E2E_RC" "exit status"
  e2e_expect_line "NO_TRIGGER=P2N"
  e2e_expect_line "UNRESOLVED_LOW=P2N"
  e2e_expect_no_out "MARKER_ROWS="
  e2e_expect_err "return to step 5 for: P2N (named no trigger: P2N)"
  e2e_expect_clean_edges
fi

if _want no-cycle; then
  _flow_test_begin "no-cycle"
  _rc_setup no-cycle "the routing block with no cycle number, and with cycle 0: it refuses rather than routing every cycle as the first (R6)"
  _rc_route external
  e2e_expect_equal 1 "$E2E_RC" "exit status with no cycle"
  e2e_expect_err "CYCLE_NUMBER must be a positive integer"
  e2e_expect_no_out "DECISION="
  _rc_route external CYCLE_NUMBER=0
  e2e_expect_equal 1 "$E2E_RC" "exit status with cycle 0"
  e2e_expect_clean_edges
fi

if _want post-not-counted; then
  _flow_test_begin "post-not-counted"
  _rc_setup post-not-counted "posting cycle 3: a body that lists the set-aside findings as plain bullets posts as request-changes with only P1A in the marker; a body that shows P2A in a counted finding's shape is refused and nothing is posted (R4, R5)"
  _rc_gh_stub
  cat > "$E2E_DIR/body.md" <<'BODY'
## Review: PR #7

### Findings: P1: 1, P2: 0, P3: 0 · Needs investigation: 0

### Checks not run
Tests, advisory audit, duplication scan: not run: someone else's pull request

#### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
| **P1A · correctness · `src/route.sh:12`**<br>An empty --input path reads stdin.<br>Trigger: an empty --input path → the router reads stdin and posts an empty marker _(HIGH · unchallenged)_ | Refuse an empty path. |

#### Not counted in this cycle
- P2A (P2, error-handling, `src/route.sh:40`) — an unauthenticated gh reads as a clean review
- P3A (P3, conventions, `README.md:9`) — the README spells the flag --cycel
- P2N (P2, error-handling, `src/route.sh:51`) — names no trigger
BODY
  e2e_run_block REVIEW_MODE=external PR_NUM=7 CYCLE_NUMBER=3 FINDING_ROWS_FILE="$E2E_DIR/rows" FINDING_TOTAL=4 \
    BODY_FILE="$E2E_DIR/body.md" REVIEW_RUN_PR_COMMANDS=no commands/review.md FINDING_POST_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "POSTED_AS=--request-changes POST_EXIT=0"
  e2e_expect_line "COUNT_TOTAL=1"
  e2e_expect_equal "--request-changes" "$(grep -x -- '--comment\|--approve\|--request-changes' "$E2E_DIR/gh-review.log")" "the event gh received"
  rm -f "$E2E_DIR/gh-review.log"
  sed 's/^- P2A (P2, error-handling, `src\/route.sh:40`)/- **P2A · error-handling · `src\/route.sh:40`**/' "$E2E_DIR/body.md" > "$E2E_DIR/body-bold.md"
  e2e_run_block REVIEW_MODE=external PR_NUM=7 CYCLE_NUMBER=3 FINDING_ROWS_FILE="$E2E_DIR/rows" FINDING_TOTAL=4 \
    BODY_FILE="$E2E_DIR/body-bold.md" REVIEW_RUN_PR_COMMANDS=no commands/review.md FINDING_POST_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for a set-aside finding in the counted shape"
  e2e_expect_err "P2A is not counted in cycle 3 but the body renders it as a finding"
  e2e_expect_equal "no" "$([ -e "$E2E_DIR/gh-review.log" ] && echo yes || echo no)" "gh pr review was called"
  e2e_expect_clean_edges
fi
