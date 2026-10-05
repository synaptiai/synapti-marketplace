# shellcheck shell=bash
# End-to-end: the System One decision point review.dedup. At the synthesis step
# of /flow:review and /flow:pr, bin/flow-s1-dedup.sh asks, per candidate pair
# of consolidated findings, whether the two describe the same defect, and in on
# mode merges the pairs a confident answer says are one.
#
# Each scenario runs the shipped code in a scratch repository with its own
# HOME, against a stub System One server (tests/lib/s1_stub.py) that logs every
# request: the script itself, or the mode probe (S1_REVIEW_MODES_BLOCK) and
# REVIEW_DEDUP_BLOCK taken from commands/review.md and commands/pr.md. A block
# runs once under each shell in E2E_FENCE_SHELLS, so its stub request counts
# are per shell. Every scenario that expects findings to stay apart asserts the
# stub request count, so "stays apart" cannot pass because nothing was asked.
# One artifact per scenario goes to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   D1  every exit 3 is read as "possibly related", or none is: only the
#       stderr reason tells below-threshold from a timeout or an HTTP error
#   D2  shadow mode changes what the review shows: the client checks the
#       threshold before the mode, so a shadow answer below the threshold
#       exits 3 with below-threshold, and a script that follows the reason
#       alone marks the pair; or shadow applies merges
#   D3  only category=security is exempt, so a DEP- finding, a finding raised
#       by security-reviewer-skeptic, or a category from the grounding pass's
#       security list (or outside the non-security list) is merged
#   D4  the representative is the first finding in the input, so a P1 merged
#       into an earlier P3 is shown as P3, or a LOW finding is merged with a
#       counted one
#   D5  "same" pairs are joined greedily, so A~B and B~C make one finding of
#       three although A~C was answered "different"
#   D6  the code is read through the filesystem or with git textconv: a
#       ../ location or a committed symlink sends a file from outside the
#       repository to the provider, or a textconv driver runs
#   D7  finding text reaches a shell: $(...) runs, or a quote or a line
#       separator breaks the state
#   D8  with the site off, no provider, or the plugin only inside the
#       repository, a request is sent, a record is written, or the probe
#       prints a line
#   D9  a repository's settings raise the user's shadow to on
#   D10 a provider that is down holds the command for a timeout per pair, or
#       past the budget; a budget set above 90 s is used; a call that starts
#       just before the budget ends runs for the whole of a long timeoutMs
#   D11 two findings with the same reviewer list (in any order), or a
#       finding from a producer outside the finding schema, are asked about;
#       or two findings whose reviewer lists share a reviewer but differ are
#       not asked, or are asked and then never merged
#   D12 a malformed findings file is read as an empty or partial set and
#       merged from
#   D13 the ref does not name the pair, or a branch outside the ref grammar
#       makes the client refuse the call
#   D14 the stub's ordered replies are served out of order, so the chain
#       scenario tests nothing
#   D15 the code window counts a form feed as a line break, so the lines sent
#       are not the lines cited; a binary or non-UTF-8 file is sent as
#       replacement characters; a file of any size is read whole; or the file
#       is read again for every pair of it
#   D16 a category error-handler-inspector is told it may write (a sub-type
#       of error-handling) is treated as a security finding and never asked,
#       or a near miss of one (a plural, a bare "error") is accepted
#   D17 a category of the form error-handling/<sub-type> is treated as a
#       security finding; or the prefix match is loose, so a bare
#       missing-validation, a category starting with security
#       (security/correctness, security/dos), or error-handling/ with no
#       sub-type is accepted

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

DD_BIN="bin/flow-s1-dedup.sh"
DD_RECORDS=".claude/flow-state/system-one.jsonl"
# shellcheck disable=SC2086
DD_NSH=$(set -- $E2E_FENCE_SHELLS; printf '%s' "$#")

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _noul P — a stub config whose reply answers same_defect with probability P.
_noul() { printf '{"body":{"model":"jev-1.13.0","answers":{"same_defect":{"type":"noul","noul":%s}}}}' "$1"; }
# _reply P — one entry of a stub replies list.
_reply() { printf '{"status":200,"body":{"model":"jev-1.13.0","answers":{"same_defect":{"type":"noul","noul":%s}}}}' "$1"; }

# _dd_setup <scenario> <purpose> — scratch repository on a feature branch with
# app.py (200 numbered lines) committed, and a directory for the findings.
_dd_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo "${DD_BRANCH:-feature/issue-260-x}"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    i=1; while [ "$i" -le 200 ]; do printf 'value_%s = %s\n' "$i" "$i"; i=$((i + 1)); done > app.py
    git add app.py && git commit -q -m app
  ) || _flow_assert_fail "$1: could not commit app.py"
  DD_DIR="$E2E_DIR/dedup"
  DD_STUB=a
  mkdir -p "$DD_DIR"
  chmod 700 "$DD_DIR"
}

# _dd_settings <mode> [extra systemOne fields as JSON] — user settings naming
# the stub as a custom provider, with review.dedup in <mode>.
_dd_settings() {
  local extra="${2:-}"
  [ -n "$extra" ] || extra='{}'
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$DD_STUB")" --arg m "$1" --argjson x "$extra" \
    '{systemOne:({provider:"custom",baseUrl:$u,uses:{"review.dedup":$m}} + $x)}')"
}

# _f <id> <priority> <category> <location> <confidence> <reviewers,comma> [problem]
_f() {
  jq -nc --arg id "$1" --arg p "$2" --arg c "$3" --arg l "$4" --arg conf "$5" --arg r "$6" \
    --arg problem "${7:-problem of $1}" \
    '{id:$id,priority:$p,category:$c,location:$l,problem:$problem,suggested_fix:("fix for " + $id),
      confidence:$conf,disposition:"unchallenged",reviewers:($r | split(","))}'
}

# _dd_findings <finding json>... — the findings file, as the session writes it.
_dd_findings() {
  printf '%s\n' "$@" | jq -s . > "$DD_DIR/findings.json"
  printf 'findings: %s\n' "$(jq -c . "$DD_DIR/findings.json")" | _e2e_art
}

# _dd_run [NAME=value ...] [extra arguments] — the script on the findings.
_dd_run() {
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in [A-Za-z_]*=*) envs+=("$1"); shift ;; *) break ;; esac
  done
  e2e_run_bin ${envs[@]+"${envs[@]}"} "$DD_BIN" --findings "$DD_DIR/findings.json" --out "$DD_DIR/dedup-out.json" \
    --tree "$E2E_REPO" --ref-prefix pr:7/review-cycle:2 "$@"
}

# _dd_block <command.md> [NAME=value ...] — REVIEW_DEDUP_BLOCK of that file.
_dd_block() {
  local md="$1"; shift
  e2e_run_block "$@" "commands/$md" REVIEW_DEDUP_BLOCK
}

# _dd_probe <command.md> — S1_REVIEW_MODES_BLOCK of that file.
_dd_probe() {
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/$1" S1_REVIEW_MODES_BLOCK_BEGIN
}

_requests() { e2e_expect_equal "$1" "$(e2e_stub_requests "$DD_STUB")" "requests received by stub $DD_STUB"; }
_out() { jq -c "$1" "$DD_DIR/dedup-out.json" 2>/dev/null; }
_unchanged() {
  e2e_expect_equal "$(jq -cS . "$DD_DIR/findings.json")" "$(jq -cS . "$DD_DIR/dedup-out.json" 2>/dev/null)" "the finding set written to DEDUP_OUT, compared with the input"
}
_no_marks() {
  e2e_expect_equal "0" "$(jq '[.[] | select(has("related") or has("also_reported_as") or has("locations"))] | length' "$DD_DIR/dedup-out.json" 2>/dev/null)" "findings carrying a related, also_reported_as or locations key"
}
# _no_line <prefix> — no stdout line starts with <prefix>.
_no_line() { e2e_expect_equal 0 "$(grep -c "^$1" <<<"$E2E_OUT")" "stdout lines starting $1"; }
_record() { jq -c "$1" "$E2E_HOME/$DD_RECORDS" 2>/dev/null; }
_logged_state() { sed -n "${1}p" "$(e2e_stub_log "$DD_STUB")" | jq -c ".body.state$2"; }
# _dd_stub <name> <config> — start a stub and make it the one the helpers use.
# A stub is started once per name in a scenario: a second start under the
# same name would read the first one's port.
_dd_stub() { DD_STUB="$1"; e2e_stub_start "$1" "$2"; }

# A same-file pair from two schema reviewers, the shape most scenarios use.
F1_A=$(_f F1 P1 correctness app.py:40 HIGH code-reviewer "the loop reads past the end of items")
ERR1_A=$(_f ERR-1 P2 error-handling app.py:47 HIGH error-handler-inspector "an IndexError escapes when items is short")

# ----------------------------------------------------------------- the stub

if _want stub-replies-order; then
  _flow_test_begin "stub-replies-order"
  _dd_setup stub-replies-order "the stub serves a replies list in request order and repeats the last entry, which the multi-pair scenarios rely on (D14)"
  e2e_stub_start a '{"replies":[{"status":500,"body":{"n":1}},{"status":200,"body":{"n":2}},{"status":202,"body":{"n":3}}]}'
  ORDER=$(python3 - "$(e2e_stub_url a)" <<'PY'
import sys, urllib.request, urllib.error
out = []
for _ in range(4):
    req = urllib.request.Request(sys.argv[1] + "/v1/systemone", data=b"{}", method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            out.append("%d:%s" % (r.status, r.read().decode()))
    except urllib.error.HTTPError as e:
        out.append("%d:%s" % (e.code, e.read().decode()))
print(" ".join(out))
PY
)
  e2e_expect_equal '500:{"n": 1} 200:{"n": 2} 202:{"n": 3} 202:{"n": 3}' "$ORDER" "statuses and bodies of four requests in order"
  _requests 4
fi

# ----------------------------------------------------------------- off and its look-alikes

if _want dedup-off; then
  _flow_test_begin "dedup-off"
  _dd_setup dedup-off "a provider is set but review.dedup is off: the probe prints nothing in either command, nothing is sent, no record is written; the block run anyway reports mode-off and leaves the findings as they were (D8)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings off
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_probe review.md
  e2e_expect_equal "" "$E2E_OUT" "review.md probe stdout"
  _dd_probe pr.md
  e2e_expect_equal "" "$E2E_OUT" "pr.md probe stdout"
  _dd_block review.md S1_DEDUP= DEDUP_DIR="$DD_DIR" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO"
  e2e_expect_line "DEDUP_STATE=skipped"
  e2e_expect_line "REASON=not-active"
  _dd_run
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "DEDUP_STATE=no-answer"
  e2e_expect_line "REASON=mode-off"
  e2e_expect_line "PAIRS_CANDIDATE=1"
  e2e_expect_line "PAIRS_ASKED=0"
  _unchanged
  _requests 0
  e2e_expect_equal "no" "$([ -e "$E2E_HOME/$DD_RECORDS" ] && echo yes || echo no)" "a records file exists"
  e2e_expect_clean_edges
fi

if _want dedup-provider-none; then
  _flow_test_begin "dedup-provider-none"
  _dd_setup dedup-provider-none "no provider, with the site set to on: the probe prints nothing and nothing is sent (D8)"
  e2e_stub_start a "$(_noul 0.99)"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"none",baseUrl:$u,uses:{"review.dedup":"on"}}}')"
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_probe review.md
  e2e_expect_equal "" "$E2E_OUT" "review.md probe stdout"
  _dd_probe pr.md
  e2e_expect_equal "" "$E2E_OUT" "pr.md probe stdout"
  _dd_run
  e2e_expect_line "DEDUP_STATE=no-answer"
  e2e_expect_line "REASON=provider-none"
  _unchanged
  _requests 0
fi

if _want dedup-plugin-in-repo; then
  _flow_test_begin "dedup-plugin-in-repo"
  _dd_setup dedup-plugin-in-repo "the only copy of flow is inside the repository: both lookups skip it, so the probe prints nothing, the block reports plugin-missing, and nothing is sent (D8)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  mkdir -p "$E2E_REPO/plugins"
  cp -R "$E2E_PLUGIN_DIR" "$E2E_REPO/plugins/flow"
  # The copy is the pull request's own: its mode helper says on and its
  # dedup script claims a merge, so a lookup that took it would show.
  printf '#!/bin/sh\necho on\n' > "$E2E_REPO/plugins/flow/bin/flow-s1-mode.sh"
  printf '#!/bin/sh\necho MERGED=F1+ERR-1\n' > "$E2E_REPO/plugins/flow/bin/flow-s1-dedup.sh"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugins/flow"
  printf 'plugin for this scenario: a copy inside the scratch repository at plugins/flow, whose bin/flow-s1-mode.sh prints on and whose bin/flow-s1-dedup.sh prints MERGED=F1+ERR-1\n' | _e2e_art
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_probe review.md
  e2e_expect_equal "" "$E2E_OUT" "review.md probe stdout"
  _dd_probe pr.md
  e2e_expect_equal "" "$E2E_OUT" "pr.md probe stdout"
  _dd_block review.md S1_DEDUP=on DEDUP_DIR="$DD_DIR" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO"
  e2e_expect_line "DEDUP_STATE=skipped"
  e2e_expect_line "REASON=plugin-missing"
  _dd_block pr.md S1_DEDUP=on DEDUP_DIR="$DD_DIR"
  e2e_expect_line "REASON=plugin-missing"
  _no_line MERGED=
  _requests 0
fi

if _want dedup-repo-cannot-raise; then
  _flow_test_begin "dedup-repo-cannot-raise"
  _dd_setup dedup-repo-cannot-raise "the user has review.dedup in shadow and the repository sets it on: the mode used is shadow, so a confident same changes nothing (D9)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings shadow
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"review.dedup":"on"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_probe review.md
  e2e_expect_equal "S1_DEDUP=shadow" "$E2E_OUT" "review.md probe stdout"
  _dd_run
  e2e_expect_line "MODE=shadow"
  _no_line MERGED=
  e2e_expect_line "FINDINGS_OUT=2"
  _unchanged
  _requests 1
  e2e_expect_equal '"shadow"' "$(_record .mode)" "the record's mode"
fi

# ----------------------------------------------------------------- on mode

if _want dedup-merge; then
  _flow_test_begin "dedup-merge"
  _dd_setup dedup-merge "two findings from two reviewers at app.py:40 and app.py:47 describe one defect and the provider says so with p=0.99: one finding remains, under the P1 id, with both locations and both reviewers; the state names neither reviewer nor priority"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_probe review.md
  e2e_expect_equal "S1_DEDUP=on" "$E2E_OUT" "review.md probe stdout"
  _dd_probe pr.md
  e2e_expect_equal "S1_DEDUP=on" "$E2E_OUT" "pr.md probe stdout"
  _dd_block review.md S1_DEDUP=on DEDUP_DIR="$DD_DIR" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "DEDUP_STATE=answered"
  e2e_expect_line "MODE=on"
  e2e_expect_line "FINDINGS_IN=2"
  e2e_expect_line "FINDINGS_OUT=1"
  e2e_expect_line "PAIRS_SAME=1"
  e2e_expect_line "MERGED=F1+ERR-1"
  e2e_expect_line "DEDUP_OUT=$DD_DIR/dedup-out.json"
  _requests "$DD_NSH"
  e2e_expect_equal '[{"id":"F1","priority":"P1","location":"app.py:40","locations":["app.py:40","app.py:47"],"reviewers":["code-reviewer","error-handler-inspector"]}]' \
    "$(_out '[.[] | {id, priority, location, locations, reviewers}]')" "the merged finding"
  e2e_expect_equal '[{"id":"ERR-1","reviewers":["error-handler-inspector"],"location":"app.py:47","priority":"P2","problem":"an IndexError escapes when items is short"}]' \
    "$(_out '.[0].also_reported_as')" "also_reported_as of F1"
  e2e_expect_equal '{"category":"correctness","location":"app.py:40","problem":"the loop reads past the end of items","suggested_fix":"fix for F1"}' "$(_logged_state 1 .a)" "finding a in the state sent"
  e2e_expect_equal '"an IndexError escapes when items is short"' "$(_logged_state 1 .b.problem)" "finding b's problem in the state sent"
  e2e_expect_equal "20 67" "$(_logged_state 1 '.code | "\(.start) \(.end)"' | tr -d '"')" "code window lines"
  e2e_expect_equal "true true" "$(_logged_state 1 '.code.text | (contains("value_40 = 40")|tostring) + " " + (contains("value_47 = 47")|tostring)' | tr -d '"')" "the window holds lines 40 and 47"
  e2e_expect_equal "\"$(git -C "$E2E_REPO" rev-parse HEAD)\"" "$(_logged_state 1 .code.head)" "the commit named in the state"
  e2e_expect_equal "false" "$(sed -n 1p "$(e2e_stub_log a)" | jq -c '.body.state | tostring | (contains("code-reviewer") or contains("error-handler-inspector") or contains("P1") or contains("HIGH"))')" "the state names a reviewer, a priority or a confidence"
  e2e_expect_equal '"pr:7/review-cycle:2/pair:F1+ERR-1"' "$(_record .ref | head -n 1)" "the record's ref"
  e2e_expect_equal '"separate"' "$(_record .current | head -n 1)" "the record's current decision"
fi

if _want dedup-distinct-same-hunk; then
  _flow_test_begin "dedup-distinct-same-hunk"
  _dd_setup dedup-distinct-same-hunk "two different defects at app.py:41 and app.py:43, and the provider says so with p=0.03: both stay, unmarked"
  e2e_stub_start a "$(_noul 0.03)"
  _dd_settings on
  _dd_findings "$(_f F1 P1 correctness app.py:41 HIGH code-reviewer "the total is never reset")" \
               "$(_f ERR-1 P2 error-handling app.py:43 HIGH error-handler-inspector "a failed write is ignored")"
  _dd_run
  e2e_expect_line "PAIRS_DIFFERENT=1"
  e2e_expect_line "FINDINGS_OUT=2"
  _no_line MERGED=
  _no_line RELATED=
  _unchanged
  _requests 1
fi

if _want dedup-security-never; then
  _flow_test_begin "dedup-security-never"
  _dd_setup dedup-security-never "a security finding beside a code finding is never asked about, whatever the provider would say: SEC- and DEP- ids, a finding raised by security-reviewer-skeptic with category correctness, each category of the grounding pass's security list (read from review.md), and csrf, a category outside the non-security list (D3)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  # The grounding pass's definition of a security finding, read from the
  # shipped text so the two cannot drift.
  SEC_CATS=$(grep -F 'A security finding is one raised by' "$E2E_PLUGIN_DIR/commands/review.md" | head -n 1 \
    | sed 's/.*whose category is \(.*\) — including.*/\1/' | grep -oE '`[a-z-]+`' | tr -d '`' | tr '\n' ' ')
  e2e_expect_equal "security dependency auth injection xss idor secrets " "$SEC_CATS" "security categories read from review.md"
  for spec in "SEC-1|security|security-reviewer" "DEP-1|dependency|security-reviewer" "S1|correctness|security-reviewer-skeptic" "C9|csrf|code-reviewer" $(for c in $SEC_CATS; do printf 'X-%s|%s|code-reviewer ' "$c" "$c"; done); do
    IFS='|' read -r sid scat srev <<<"$spec"
    _dd_findings "$(_f "$sid" P1 "$scat" app.py:42 HIGH "$srev")" "$ERR1_A"
    _dd_run
    e2e_expect_line "PAIRS_CANDIDATE=0"
    e2e_expect_line "DEDUP_STATE=skipped"
    _no_line MERGED=
    _unchanged
    # The same finding raised by code-reviewer (or, for the reviewer case,
    # by its security variant and code-reviewer), beside a partner whose
    # reviewer list shares code-reviewer but differs: a candidate by
    # reviewers, so only the security rule keeps it from being asked.
    case "$srev" in *security*) orev="$srev,code-reviewer" ;; *) orev=code-reviewer ;; esac
    _dd_findings "$(_f "$sid" P1 "$scat" app.py:42 HIGH "$orev")" "$(_f F5 P2 correctness app.py:47 HIGH code-reviewer,error-handler-inspector)"
    _dd_run
    e2e_expect_line "PAIRS_CANDIDATE=0"
    _no_line MERGED=
    _unchanged
  done
  _requests 0
fi

if _want dedup-below-threshold; then
  _flow_test_begin "dedup-below-threshold"
  _dd_setup dedup-below-threshold "on mode, the provider answers p=0.7 (confidence 0.4, below 0.8): the pair stays apart and both findings are marked possibly the same defect (D1)"
  e2e_stub_start a "$(_noul 0.7)"
  _dd_settings on
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_run
  e2e_expect_line "PAIRS_RELATED=1"
  e2e_expect_line "RELATED=F1+ERR-1"
  e2e_expect_line "FINDINGS_OUT=2"
  _no_line MERGED=
  e2e_expect_equal '[[{"id":"ERR-1","why":"unsure"}],[{"id":"F1","why":"unsure"}]]' "$(_out '[.[].related]')" "related marks"
  _requests 1
  e2e_expect_equal '"below-threshold"' "$(_record .result)" "the record's result"
fi

if _want dedup-no-answer; then
  _flow_test_begin "dedup-no-answer"
  _dd_setup dedup-no-answer "on mode, an HTTP 500, a reply slower than timeoutMs and a body that is not JSON: each keeps the pair apart with no mark and is counted by its reason (D1)"
  for spec in 'a|http-500|{"status":500,"body":{"detail":"boom"}}' 'b|timeout|{"delay_ms":1500,"body":{}}' 'c|malformed|{"body":"not json"}'; do
    IFS='|' read -r stub reason config <<<"$spec"
    _dd_stub "$stub" "$config"
    _dd_settings on '{"timeoutMs":300}'
    _dd_findings "$F1_A" "$ERR1_A"
    _dd_run
    e2e_expect_line "PAIRS_NO_ANSWER=1"
    e2e_expect_line "NO_ANSWER_$(printf '%s' "$reason" | tr 'a-z-' 'A-Z_')=1"
    _no_line RELATED=
    _no_marks
    _unchanged
    _requests 1
  done
fi

if _want dedup-provider-down; then
  _flow_test_begin "dedup-provider-down"
  _dd_setup dedup-provider-down "five candidate pairs and a provider that never answers within timeoutMs: two timeouts in a row stop the asking, and the other pairs are counted as not asked (D10)"
  e2e_stub_start a '{"delay_ms":1500,"body":{}}'
  _dd_settings on '{"timeoutMs":200}'
  _dd_findings "$F1_A" "$ERR1_A" "$(_f INT-1 P2 runtime app.py:44 HIGH integration-verifier)" "$(_f F2 P3 correctness app.py:50 HIGH code-reviewer)"
  _dd_run
  e2e_expect_line "PAIRS_CANDIDATE=5"
  e2e_expect_line "PAIRS_ASKED=2"
  e2e_expect_line "NO_ANSWER_TIMEOUT=2"
  e2e_expect_line "UNASKED=3"
  e2e_expect_line "STOPPED=provider-down"
  _requests 2
fi

if _want dedup-budget; then
  _flow_test_begin "dedup-budget"
  _dd_setup dedup-budget "FLOW_S1_DEDUP_BUDGET_S=1 with replies that take 600 ms: asking stops at the budget; a budget of 600 is reported as 90 (D10)"
  e2e_stub_start a '{"delay_ms":600,"body":{"model":"jev-1.13.0","answers":{"same_defect":{"type":"noul","noul":0.03}}}}'
  _dd_settings on '{"timeoutMs":1000}'
  _dd_findings "$F1_A" "$ERR1_A" "$(_f INT-1 P2 runtime app.py:44 HIGH integration-verifier)" "$(_f F2 P3 correctness app.py:50 HIGH code-reviewer)"
  _dd_run FLOW_S1_DEDUP_BUDGET_S=1
  e2e_expect_line "BUDGET_S=1"
  e2e_expect_line "STOPPED=budget"
  N=$(e2e_stub_requests a)
  e2e_expect_equal "yes" "$([ "$N" -ge 1 ] && [ "$N" -le 2 ] && echo yes || echo no)" "1 or 2 requests within a 1 s budget (got $N)"
  e2e_expect_line "UNASKED=$((5 - N))"
  _dd_stub b "$(_noul 0.03)"
  _dd_settings on
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_run FLOW_S1_DEDUP_BUDGET_S=600
  e2e_expect_line "BUDGET_S=90"
  _dd_run FLOW_S1_DEDUP_BUDGET_S=1.5
  e2e_expect_line "BUDGET_S=90"
fi

if _want dedup-budget-stops-call; then
  _flow_test_begin "dedup-budget-stops-call"
  _dd_setup dedup-budget-stops-call "FLOW_S1_DEDUP_BUDGET_S=2, timeoutMs 30000 and a reply that takes 25 s: the call in flight is stopped 5 s after the budget, so the script ends well before the reply would come, and asking stops at the budget (D10)"
  e2e_stub_start a '{"delay_ms":25000,"body":{"model":"jev-1.13.0","answers":{"same_defect":{"type":"noul","noul":0.03}}}}'
  _dd_settings on '{"timeoutMs":30000}'
  _dd_findings "$F1_A" "$ERR1_A" "$(_f INT-1 P2 runtime app.py:44 HIGH integration-verifier)"
  DD_T0=$SECONDS
  _dd_run FLOW_S1_DEDUP_BUDGET_S=2
  DD_T=$((SECONDS - DD_T0))
  e2e_expect_equal "yes" "$([ "$DD_T" -lt 15 ] && echo yes || echo no)" "the script ended within 15 s (took $DD_T s)"
  e2e_expect_line "STOPPED=budget"
  e2e_expect_line "PAIRS_ASKED=1"
  e2e_expect_line "NO_ANSWER_TIMEOUT=1"
  e2e_expect_equal "1" "$(e2e_stub_requests a)" "requests received by stub a"
fi

# ----------------------------------------------------------------- shadow

if _want dedup-shadow; then
  _flow_test_begin "dedup-shadow"
  _dd_setup dedup-shadow "shadow mode with p=0.99 and with p=0.7: nothing merges and nothing is marked; each pair is recorded with mode shadow, current separate and the pair's ref, and the state sent is kept beside the run with the sha256 the record names (D2)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings shadow
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_probe review.md
  e2e_expect_equal "S1_DEDUP=shadow" "$E2E_OUT" "review.md probe stdout"
  _dd_block review.md S1_DEDUP=shadow DEDUP_DIR="$DD_DIR" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO" RUN_ID=r1
  e2e_expect_line "MODE=shadow"
  e2e_expect_line "NO_ANSWER_SHADOW=1"
  _no_line MERGED=
  e2e_expect_line "FINDINGS_OUT=2"
  _unchanged
  _requests "$DD_NSH"
  REC="$E2E_REPO/.flow/runs/r1/system-one.jsonl"
  e2e_expect_equal '{"mode":"shadow","current":"separate","ref":"pr:7/review-cycle:2/pair:F1+ERR-1","p":0.99}' \
    "$(head -n 1 "$REC" | jq -c '{mode, current, ref, p: .answer.p}')" "the record"
  KEPT="$E2E_REPO/.flow/runs/r1/system-one-state/dedup-F1+ERR-1.json"
  e2e_expect_equal "$(head -n 1 "$REC" | jq -r .state_sha256)" "$(_e2e_sha256 "$KEPT" 2>/dev/null)" "sha256 of the kept state"
  _dd_stub b "$(_noul 0.7)"
  _dd_settings shadow
  _dd_run --run-id r1
  e2e_expect_line "MODE=shadow"
  e2e_expect_line "NO_ANSWER_BELOW_THRESHOLD=1"
  _no_line RELATED=
  _no_marks
  _unchanged
  _requests 1
fi

# ----------------------------------------------------------------- who may be paired

if _want dedup-same-reviewer; then
  _flow_test_begin "dedup-same-reviewer"
  _dd_setup dedup-same-reviewer "two findings from one reviewer, and two findings whose reviewer lists hold the same two reviewers in a different order: nothing is asked (D11)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$(_f F1 P1 correctness app.py:40 HIGH code-reviewer)" "$(_f F2 P2 correctness app.py:42 HIGH code-reviewer)"
  _dd_run
  e2e_expect_line "DEDUP_STATE=skipped"
  e2e_expect_line "REASON=no-candidates"
  _unchanged
  _dd_findings "$(_f F1 P1 correctness app.py:40 HIGH code-reviewer,error-handler-inspector)" "$(_f F2 P2 correctness app.py:44 MEDIUM error-handler-inspector,code-reviewer)"
  _dd_run
  e2e_expect_line "PAIRS_CANDIDATE=0"
  e2e_expect_line "REASON=no-candidates"
  _unchanged
  _requests 0
fi

if _want dedup-overlapping-reviewers; then
  _flow_test_begin "dedup-overlapping-reviewers"
  _dd_setup dedup-overlapping-reviewers "two findings whose reviewer lists share code-reviewer but differ (synthesis lists every reviewer of a file:line merge), and an A.2 consensus finding beside a finding from one of its two variants: each pair is asked, and p=0.99 merges it, with the union of the reviewers (D11)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$(_f F1 P1 correctness app.py:40 HIGH code-reviewer,error-handler-inspector)" "$(_f F2 P2 correctness app.py:47 HIGH code-reviewer)"
  _dd_run
  e2e_expect_line "PAIRS_CANDIDATE=1"
  e2e_expect_line "PAIRS_SAME=1"
  e2e_expect_line "MERGED=F1+F2"
  e2e_expect_line "FINDINGS_OUT=1"
  e2e_expect_equal '[{"id":"F1","locations":["app.py:40","app.py:47"],"reviewers":["code-reviewer","error-handler-inspector"]}]' \
    "$(_out '[.[] | {id, locations, reviewers}]')" "the merged finding"
  _dd_findings "$(_f F1 P1 correctness app.py:40 HIGH code-reviewer-skeptic,code-reviewer-verifier)" "$(_f F7 P2 correctness app.py:44 MEDIUM code-reviewer-verifier)"
  _dd_run
  e2e_expect_line "PAIRS_CANDIDATE=1"
  e2e_expect_line "MERGED=F1+F7"
  e2e_expect_line "FINDINGS_OUT=1"
  _requests 2
fi

if _want dedup-error-subtypes; then
  _flow_test_begin "dedup-error-subtypes"
  _dd_setup dedup-error-subtypes "each sub-type error-handler-inspector is told it may write as its category (read from its agent definition) is asked about and merged at p=0.99; near misses of them (a plural, a bare error) are still treated as security and never asked (D16)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  # The sub-types are read from the shipped agent definition, so the list the
  # script accepts cannot drift from the one the agent is given.
  ERR_SUBTYPES=$(grep -oE 'sub-types \([^)]*\)' "$E2E_PLUGIN_DIR/agents/error-handler-inspector.md" | head -n 1 \
    | grep -oE '`[a-z-]+`' | tr -d '`' | tr '\n' ' ')
  e2e_expect_equal "unhandled-exception silent-failure swallowed-rescue missing-fallback " "$ERR_SUBTYPES" "sub-types read from the agent definition"
  for cat in $ERR_SUBTYPES; do
    _dd_findings "$F1_A" "$(_f ERR-1 P2 "$cat" app.py:47 HIGH error-handler-inspector)"
    _dd_run
    e2e_expect_line "PAIRS_CANDIDATE=1"
    e2e_expect_line "MERGED=F1+ERR-1"
  done
  for cat in silent-failures unhandled-exceptions error; do
    _dd_findings "$F1_A" "$(_f ERR-1 P2 "$cat" app.py:47 HIGH error-handler-inspector)"
    _dd_run
    e2e_expect_line "PAIRS_CANDIDATE=0"
    _no_line MERGED=
    _unchanged
  done
  # shellcheck disable=SC2086
  _requests "$(set -- $ERR_SUBTYPES; printf '%s' "$#")"
fi

if _want dedup-error-handling-forms; then
  _flow_test_begin "dedup-error-handling-forms"
  _dd_setup dedup-error-handling-forms "categories of the form error-handling/<sub-type> (error-handling/edge-case, error-handling/silent-failure, error-handling/missing-validation, in any case) are asked about and merged at p=0.99; a bare missing-validation, security/correctness, security/dos, error-handling/ with no sub-type and error-handling/a/b are still treated as security and never asked (D17)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  for cat in error-handling/edge-case error-handling/silent-failure error-handling/missing-validation Error-Handling/Edge-Case; do
    _dd_findings "$F1_A" "$(_f ERR-1 P2 "$cat" app.py:47 HIGH error-handler-inspector)"
    _dd_run
    e2e_expect_line "PAIRS_CANDIDATE=1"
    e2e_expect_line "MERGED=F1+ERR-1"
  done
  for cat in missing-validation security/correctness security/dos error-handling/ error-handling/a/b; do
    _dd_findings "$F1_A" "$(_f ERR-1 P2 "$cat" app.py:47 HIGH error-handler-inspector)"
    _dd_run
    e2e_expect_line "PAIRS_CANDIDATE=0"
    _no_line MERGED=
    _unchanged
  done
  _requests 4
fi

if _want dedup-non-schema-producer; then
  _flow_test_begin "dedup-non-schema-producer"
  _dd_setup dedup-non-schema-producer "a holdout-validation claim and a test-runner finding beside a code-reviewer finding in one file: nothing is asked (D11)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$(_f F1 P1 correctness app.py:40 HIGH code-reviewer)" \
               "$(_f H1 P2 claim-verification app.py:41 MEDIUM holdout-validation)" \
               "$(_f T1 P2 tests app.py:42 MEDIUM test-runner)"
  _dd_run
  e2e_expect_line "PAIRS_CANDIDATE=0"
  _unchanged
  _requests 0
fi

if _want dedup-mixed-routing; then
  _flow_test_begin "dedup-mixed-routing"
  _dd_setup dedup-mixed-routing "a LOW P1 and a HIGH P2 the provider calls one defect with p=0.99: asked, never merged, both marked probably the same defect (D4)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$(_f F1 P1 correctness app.py:40 LOW code-reviewer)" "$ERR1_A"
  _dd_run
  e2e_expect_line "PAIRS_SAME=1"
  e2e_expect_line "RELATED=F1+ERR-1"
  _no_line MERGED=
  e2e_expect_line "FINDINGS_OUT=2"
  e2e_expect_equal '[[{"id":"ERR-1","why":"mixed-confidence"}],[{"id":"F1","why":"mixed-confidence"}]]' "$(_out '[.[].related]')" "related marks"
  _requests 1
fi

if _want dedup-representative; then
  _flow_test_begin "dedup-representative"
  _dd_setup dedup-representative "the kept finding is the one with the highest priority, then the highest confidence, whatever the input order: a P3 before a P1 keeps the P1; a MEDIUM P2 before a HIGH P2 keeps the HIGH one (D4)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$(_f F1 P3 correctness app.py:40 HIGH code-reviewer)" "$(_f ERR-1 P1 error-handling app.py:47 HIGH error-handler-inspector)"
  _dd_run
  e2e_expect_line "MERGED=ERR-1+F1"
  e2e_expect_equal '[{"id":"ERR-1","priority":"P1","location":"app.py:47"}]' "$(_out '[.[] | {id, priority, location}]')" "the kept finding"
  _dd_findings "$(_f F1 P2 correctness app.py:40 MEDIUM code-reviewer)" "$(_f ERR-1 P2 error-handling app.py:47 HIGH error-handler-inspector)"
  _dd_run
  e2e_expect_line "MERGED=ERR-1+F1"
  e2e_expect_equal '[{"id":"ERR-1","confidence":"HIGH"}]' "$(_out '[.[] | {id, confidence}]')" "the kept finding"
  _requests 2
fi

if _want dedup-chain; then
  _flow_test_begin "dedup-chain"
  _dd_setup dedup-chain "three findings from three reviewers; pairs are asked nearest first (ERR-1~INT-1, F1~ERR-1, F1~INT-1) and answered 0.99, 0.99, 0.02: one group of two, the third apart. With F1 and the third from one reviewer, that pair is never asked (D5)"
  e2e_stub_start a "{\"replies\":[$(_reply 0.99),$(_reply 0.99),$(_reply 0.02)]}"
  _dd_settings on
  _dd_findings "$(_f F1 P2 correctness app.py:10 HIGH code-reviewer)" "$(_f ERR-1 P2 error-handling app.py:12 HIGH error-handler-inspector)" "$(_f INT-1 P2 runtime app.py:13 HIGH integration-verifier)"
  _dd_run
  e2e_expect_line "PAIRS_ASKED=3"
  e2e_expect_line "MERGED=ERR-1+INT-1"
  e2e_expect_equal "1" "$(grep -c '^MERGED=' <<<"$E2E_OUT")" "MERGED lines"
  e2e_expect_line "FINDINGS_OUT=2"
  e2e_expect_equal '"pr:7/review-cycle:2/pair:ERR-1+INT-1","pr:7/review-cycle:2/pair:F1+ERR-1","pr:7/review-cycle:2/pair:F1+INT-1"' \
    "$(_record .ref | paste -sd, -)" "pairs in the order asked"
  _dd_stub b "{\"replies\":[$(_reply 0.99),$(_reply 0.99)]}"
  _dd_settings on
  : > "$E2E_HOME/$DD_RECORDS"
  _dd_findings "$(_f F1 P2 correctness app.py:10 HIGH code-reviewer)" "$(_f ERR-1 P2 error-handling app.py:12 HIGH error-handler-inspector)" "$(_f F2 P2 correctness app.py:13 HIGH code-reviewer)"
  _dd_run
  e2e_expect_line "PAIRS_ASKED=2"
  e2e_expect_equal "1" "$(grep -c '^MERGED=' <<<"$E2E_OUT")" "MERGED lines"
  e2e_expect_line "FINDINGS_OUT=2"
fi

# ----------------------------------------------------------------- hostile input

if _want dedup-hostile-location; then
  _flow_test_begin "dedup-hostile-location"
  _dd_setup dedup-hostile-location "a ../ location and a committed symlink to a file outside the repository, and a textconv driver the repository's attributes name: the outside file never reaches the provider, the symlink is sent as its target text, and the driver never runs (D6)"
  e2e_stub_start a "$(_noul 0.03)"
  _dd_settings on
  printf 'OUTSIDE-SECRET-1\n' > "$E2E_DIR/outside.txt"
  printf '#!/bin/sh\ntouch "%s/textconv-ran"\ncat "$1"\n' "$E2E_DIR" > "$E2E_DIR/conv.sh"; chmod +x "$E2E_DIR/conv.sh"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    ln -s ../outside.txt link.py
    printf 'app.py diff=evil\n' > .gitattributes
    git config diff.evil.textconv "$E2E_DIR/conv.sh"
    git add link.py .gitattributes && git commit -q -m link
  ) || _flow_assert_fail "dedup-hostile-location: setup"
  _dd_findings "$(_f F1 P2 correctness ../outside.txt:1 HIGH code-reviewer)" "$(_f ERR-1 P2 error-handling ../outside.txt:1 HIGH error-handler-inspector)" \
               "$(_f F2 P2 correctness link.py:1 HIGH code-reviewer)" "$(_f ERR-2 P2 error-handling link.py:1 HIGH error-handler-inspector)" \
               "$(_f F3 P2 correctness app.py:5 HIGH code-reviewer)" "$(_f ERR-3 P2 error-handling app.py:6 HIGH error-handler-inspector)"
  _dd_run
  _requests 3
  e2e_expect_equal "0" "$(grep -c 'OUTSIDE-SECRET' "$(e2e_stub_log a)")" "requests carrying the outside file"
  e2e_expect_equal '""' "$(jq -c 'select(.body.state.file == "../outside.txt") | .body.state.code.text' "$(e2e_stub_log a)")" "code text sent for the ../ location"
  e2e_expect_equal '"../outside.txt"' "$(jq -c 'select(.body.state.file == "link.py") | .body.state.code.text' "$(e2e_stub_log a)")" "code text sent for the symlink"
  e2e_expect_equal "true" "$(jq -c 'select(.body.state.file == "app.py") | .body.state.code.text | contains("value_5 = 5")' "$(e2e_stub_log a)")" "the app.py window is the committed text"
  e2e_expect_equal "no" "$([ -e "$E2E_DIR/textconv-ran" ] && echo yes || echo no)" "the textconv driver ran"
fi

if _want dedup-code-window; then
  _flow_test_begin "dedup-code-window"
  _dd_setup dedup-code-window "a form feed inside a line does not shift the line numbers; a window holding a NUL byte or a byte that is not UTF-8 is sent empty, as is a file over 8 MB; three pairs in one file read it once (D15)"
  e2e_stub_start a "$(_noul 0.03)"
  _dd_settings on
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    i=1; while [ "$i" -le 80 ]; do
      if [ "$i" = 5 ]; then printf 'value_5 = 5\f# page\n'; else printf 'value_%s = %s\n' "$i" "$i"; fi
      i=$((i + 1))
    done > ff.py
    printf 'line 1\nline 2\nnul\000here\nline 4\n' > nul.py
    printf 'line 1\nline 2\nlatin \351\nline 4\n' > latin.py
    { printf 'big_1 = 1\nbig_2 = 2\n'; head -c 8400000 /dev/zero | tr '\0' 'x'; printf '\n'; } > big.py
    git add ff.py nul.py latin.py big.py && git commit -q -m windows
  ) || _flow_assert_fail "dedup-code-window: setup"
  _dd_findings "$(_f F1 P2 correctness ff.py:40 HIGH code-reviewer)" "$(_f ERR-1 P2 error-handling ff.py:41 HIGH error-handler-inspector)" \
               "$(_f INT-1 P2 correctness ff.py:42 HIGH integration-verifier)" \
               "$(_f F2 P2 correctness nul.py:2 HIGH code-reviewer)" "$(_f ERR-2 P2 error-handling nul.py:4 HIGH error-handler-inspector)" \
               "$(_f F3 P2 correctness latin.py:2 HIGH code-reviewer)" "$(_f ERR-3 P2 error-handling latin.py:4 HIGH error-handler-inspector)" \
               "$(_f F4 P2 correctness big.py:1 HIGH code-reviewer)" "$(_f ERR-4 P2 error-handling big.py:2 HIGH error-handler-inspector)"
  _dd_run GIT_TRACE="$E2E_DIR/git-trace"
  _requests 6
  _code() { jq -c --arg f "$1" "select(.body.state.file == \$f) | .body.state.code$2" "$(e2e_stub_log a)" | head -n 1; }
  # The first ff.py pair asked is ERR-1+INT-1 (lines 41 and 42): its window
  # is lines 21 to 62.
  e2e_expect_equal '21' "$(_code ff.py .start)" "the first line of the ff.py window"
  e2e_expect_equal '"value_21 = 21"' "$(_code ff.py '.text | split("\n")[0]')" "the text of the first line of the ff.py window"
  e2e_expect_equal '"value_62 = 62"' "$(_code ff.py '.text | split("\n")[-1]')" "the text of the last line of the ff.py window"
  e2e_expect_equal '""' "$(_code nul.py .text)" "code text sent for a window holding a NUL byte"
  e2e_expect_equal '""' "$(_code latin.py .text)" "code text sent for a window that is not UTF-8"
  e2e_expect_equal '""' "$(_code big.py .text)" "code text sent for a file over 8 MB"
  e2e_expect_equal "1 0" "$(grep -c 'cat-file.*blob.*HEAD:ff\.py' "$E2E_DIR/git-trace") $(grep -c 'cat-file.*blob.*HEAD:big\.py' "$E2E_DIR/git-trace")" "reads of the ff.py and big.py blobs"
  rm -f "$E2E_REPO/big.py"
fi

if _want dedup-hostile-text; then
  _flow_test_begin "dedup-hostile-text"
  _dd_setup dedup-hostile-text "a problem holding \$(touch pwned), a double quote, a newline and U+2028: no command runs, the text reaches the provider byte for byte, and both shells print the same (D7)"
  e2e_stub_start a "$(_noul 0.03)"
  _dd_settings on
  HOSTILE=$'a $(touch pwned) "quoted"\nsecond line\xe2\x80\xa8after LS `touch pwned2`'
  _dd_findings "$(_f F1 P2 correctness app.py:40 HIGH code-reviewer "$HOSTILE")" "$ERR1_A"
  _dd_block review.md S1_DEDUP=on DEDUP_DIR="$DD_DIR" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO"
  e2e_expect_line "PAIRS_DIFFERENT=1"
  e2e_expect_equal "no no" "$([ -e "$E2E_REPO/pwned" ] && echo yes || echo no) $([ -e "$E2E_REPO/pwned2" ] && echo yes || echo no)" "files the text names"
  e2e_expect_equal "$(jq -c --arg h "$HOSTILE" -n '$h')" "$(_logged_state 1 .a.problem)" "the problem as sent"
  _requests "$DD_NSH"
fi

if _want dedup-malformed-input; then
  _flow_test_begin "dedup-malformed-input"
  _dd_setup dedup-malformed-input "a findings file that is not JSON, one with a duplicate id, one without a reviewers list, one that is not a list: exit 2 with STATE=blocked and nothing asked (D12)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  printf 'not json' > "$DD_DIR/findings.json"
  _dd_run
  e2e_expect_equal 2 "$E2E_RC" "exit status for text that is not JSON"
  e2e_expect_line "STATE=blocked"
  _dd_findings "$F1_A" "$F1_A"
  _dd_run
  e2e_expect_equal 2 "$E2E_RC" "exit status for a duplicate id"
  e2e_expect_out "ERROR=id F1 appears twice"
  _dd_findings "$(jq -c 'del(.reviewers)' <<<"$F1_A")" "$ERR1_A"
  _dd_run
  e2e_expect_equal 2 "$E2E_RC" "exit status without reviewers"
  e2e_expect_out "ERROR=F1 has no reviewers list"
  printf '{"id":"F1"}' > "$DD_DIR/findings.json"
  _dd_run
  e2e_expect_equal 2 "$E2E_RC" "exit status for an object"
  e2e_expect_line "STATE=blocked"
  # The block refuses what it would build the ref or find the files from.
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_block review.md S1_DEDUP=on DEDUP_DIR="$DD_DIR" PR_NUM=07 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO"
  e2e_expect_equal "2 STATE=blocked ERROR=PR_NUM must be a positive integer" "$E2E_RC $(tr '\n' ' ' <<<"$E2E_OUT" | sed 's/ $//')" "exit status and stdout for PR_NUM 07"
  _dd_block review.md S1_DEDUP=on DEDUP_DIR="$DD_DIR" PR_NUM=7 CYCLE_NUMBER=x REVIEW_TREE="$E2E_REPO"
  e2e_expect_equal "2" "$E2E_RC" "exit status for CYCLE_NUMBER x"
  _dd_block review.md S1_DEDUP=on DEDUP_DIR="$E2E_DIR/missing" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO"
  e2e_expect_out "ERROR=DEDUP_DIR must be the directory from mktemp -d that holds findings.json"
  _requests 0
fi

# ----------------------------------------------------------------- /flow:pr

if _want dedup-pr-ref; then
  _flow_test_begin "dedup-pr-ref"
  _dd_setup dedup-pr-ref "/flow:pr names each record after the branch and its head commit; a branch with a character outside the ref grammar gives the head commit alone (D13)"
  e2e_stub_start a "$(_noul 0.99)"
  _dd_settings on
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_block pr.md S1_DEDUP=on DEDUP_DIR="$DD_DIR"
  e2e_expect_line "MERGED=F1+ERR-1"
  HEAD12=$(git -C "$E2E_REPO" rev-parse HEAD | cut -c1-12)
  e2e_expect_equal "\"branch:feature/issue-260-x@$HEAD12/pair:F1+ERR-1\"" "$(_record .ref | head -n 1)" "the record's ref"
  (_e2e_git_env; cd "$E2E_REPO" && git checkout -q -b 'feature/a,b') || _flow_assert_fail "dedup-pr-ref: branch"
  : > "$E2E_HOME/$DD_RECORDS"
  _dd_findings "$F1_A" "$ERR1_A"
  _dd_block pr.md S1_DEDUP=on DEDUP_DIR="$DD_DIR"
  e2e_expect_line "MERGED=F1+ERR-1"
  e2e_expect_equal "\"head:$HEAD12/pair:F1+ERR-1\"" "$(_record .ref | head -n 1)" "the record's ref on a branch outside the grammar"
  _requests "$((2 * DD_NSH))"
fi
