# shellcheck shell=bash
# End-to-end: the System One decision point address.still_applies in
# /flow:address (issue #266). The probe in a `!` fence (S1_ADDRESS_MODES_BLOCK)
# says whether the site is active; the STILL_APPLIES_BLOCK, run once per inline
# review comment after the pull request is checked out, reads the comment,
# finds the code it refers to now, and asks the shipped question through
# bin/flow-s1.sh.
#
# Each scenario runs the shipped blocks of commands/address.md in a scratch
# repository with its own HOME, under zsh and bash, against a stub System One
# server (tests/lib/s1_stub.py) and a gh stub answering from fixtures. The
# questions are the shipped system-one/questions.yaml. One artifact per
# scenario goes to $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the
# named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   W1  the noul is read the wrong way round: p >= 0.5 taken as "addressed",
#       so every comment that still applies is skipped
#   W2  a repository's settings (the pull request head) raise the user's
#       mode: on where the user chose shadow, or shadow where the user left
#       the site off
#   W3  shadow mode prints an answer, or the record lacks the decision Flow
#       took (current), so the comparison cannot be made
#   W4  with the site off, no provider, or the plugin inside the repository
#       and no install outside it, the probe prints a line or the stub is
#       reached
#   W5  an outdated comment (line null) is checked against the wrong window,
#       such as the top of the file, or an anchor found nowhere is asked about
#   W6  the comment text reaches a shell or a jq program as code
#   W7  a path that is a symlink, or leaves the repository, sends a file from
#       outside the repository to the provider
#   W8  a no-answer reason (http error, timeout, malformed, below threshold)
#       prints an answer
#   W9  the gh stub has no route for the comment, every scenario reports
#       skipped, and "Explore runs" passes for the wrong reason. Rule: every
#       scenario asserts clean edges, and every answered scenario asserts one
#       request
#   W10 the state file kept for the comparison is not the state that was sent
#   W11 a value printed from a comment (CHECKED starts with the comment's
#       path) is run as shell when the reply that cites it is posted
#   W12 a comment whose line is not a line of the file now is checked anyway:
#       one on a removed line (side LEFT, a base-file line number), one on
#       the whole file (subject_type file), a reply in a thread, or a comment
#       of another pull request
#   W13 the code read is not the code at the commit CHECKED names: the file
#       has uncommitted changes, or is not in HEAD at all
#   W14 an outdated anchor that looks like a number matches a line that
#       equals it only as a number (`1` and `1.0`)
#   W15 the kept state is written into a directory or through a symlink that
#       stands where the state file or its directory should be
#   W16 a repository's settings supply the provider the user never set, and
#       the probe prints a mode
#   W17 reviewer text reaches a shell through a here-document whose fixed
#       delimiter the text can hold, or an addressed comment is dropped from
#       the reply, the Thread Status table or the summary with no check that
#       counts them
#   W18 the plugin loaded from inside the repository hides an install outside
#       it, so the site stays off although the user switched it on; or a
#       flow-s1-mode.sh committed in the repository is run by the probe
#   W19 a comment whose lines a fix replaced (outdated, its anchor nowhere in
#       the file now) is skipped, so a real fix is never recognised; or, asked
#       about, it is sent without its diff hunk, with a window that is not
#       around its original line, without telling the model the lines are
#       gone, or for a file that was deleted
#   W20 the reply block posts a file the session did not make, such as a
#       credentials file named by a misled call
#   W21 an answer about a state the client shortened (the cut can remove the
#       commented line) is acted on
#   W22 a comment's line is read in a commit other than the one GitHub counts
#       it in (the comment's commit_id), so the window is on other code
#   W23 Phase 1 lists only the first page of inline comments, so a comment
#       past the thirtieth is never checked or addressed
#   W24 a | or a backtick in the path breaks the code span that cites CHECKED
#       in the reply, or the row of the Thread Status table

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

ADDRESS_MD="commands/address.md"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Replies in TypeSafe's shape for the one question of the site.
_noul_reply() { printf '{"body":{"model":"jev-1.13.0","answers":{"concern_present":{"type":"noul","noul":%s}}}}' "$1"; }

# A 120-line source file. Line 60 holds the anchor of the outdated scenario.
_sa_source() {
  local i
  for i in $(seq 1 120); do
    if [ "$i" = 60 ]; then printf '    return compute_total(items)\n'
    else printf 'line %s\n' "$i"; fi
  done
}

# _sa_setup <scenario> <purpose> — scratch repository with src/app.py
# committed, the gh fixture for the repository, and comment 101 on line 20.
_sa_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/sa
  mkdir -p "$E2E_REPO/src"
  _sa_source > "$E2E_REPO/src/app.py"
  ( _e2e_git_env; cd "$E2E_REPO" && git add src/app.py && git commit -q -m "add app" ) \
    || _flow_assert_fail "$1: could not commit the fixture"
  e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
  _sa_comment '{"id":101,"path":"src/app.py","line":20,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n line 18\n line 19\n+line 20","body":"This loop does not handle an empty list.","user":{"login":"reviewer-x"}}'
}

# A comment on pull request 7 unless the fixture names another.
_sa_comment() {
  e2e_gh_fixture pull-comment-101 "$(printf '%s' "$1" | jq -c '.pull_request_url //= "https://api.github.com/repos/o/r/pulls/7"')"
}

# _sa_user <mode> [stub] — user settings: provider custom at the stub, and the
# site in <mode> ("" leaves it out).
_sa_user() {
  local url=""
  [ -n "${2:-}" ] && url=$(e2e_stub_url "$2")
  if [ -n "$1" ]; then
    e2e_user_settings "$(jq -nc --arg u "$url" --arg m "$1" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"address.still_applies":$m}}}')"
  else
    e2e_user_settings "$(jq -nc --arg u "$url" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  fi
}

_sa_probe() { e2e_run_block "$ADDRESS_MD" S1_ADDRESS_MODES_BLOCK; }
_sa_block() { e2e_run_block PR_NUM=7 COMMENT_ID=101 "$@" "$ADDRESS_MD" STILL_APPLIES_BLOCK; }

# _sa_requests <stub> <per run> — every block runs once under each shell in
# E2E_FENCE_SHELLS, so a stub asked once per run is asked once per shell.
_sa_requests() { e2e_expect_equal "$(( $2 * SA_SHELLS ))" "$(e2e_stub_requests "$1")" "requests stub $1 received ($2 per shell)"; }
SA_SHELLS=$(printf '%s\n' $E2E_FENCE_SHELLS | wc -l | tr -d ' ')
_sa_head() { ( _e2e_git_env; cd "$E2E_REPO" && git rev-parse --short=12 HEAD ); }
_sa_records() { printf '%s' "$E2E_HOME/.claude/flow-state/system-one.jsonl"; }
_sa_no_records() {
  if [ -e "$(_sa_records)" ] || [ -n "$(find "$E2E_REPO" -name system-one.jsonl 2>/dev/null)" ]; then
    _e2e_result fail "no system-one.jsonl was written"
  else
    _e2e_result pass "no system-one.jsonl was written"
  fi
}
# The request body the stub logged, as one JSON value.
_sa_sent() { head -n 1 "$(e2e_stub_log "$1")" | jq -c '.body'; }

if _want sa-off; then
  _flow_test_begin "sa-off"
  _sa_setup sa-off "W4, W10: a provider is set but the site is off: the probe prints nothing, and the block, run anyway with a run directory present, sends nothing, records nothing and keeps no state"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user off a
  mkdir -p "$E2E_REPO/.flow/runs/R1"
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _sa_block RUN_ID=R1
  e2e_expect_line "COMMENT_ID=101"
  e2e_expect_line "STILL_APPLIES_STATE=no-answer"
  e2e_expect_line "REASON=mode-off"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 0
  _sa_no_records
  e2e_expect_equal "" "$(find "$E2E_REPO/.flow" -name system-one-state 2>/dev/null)" "state directory beside the run, when nothing was sent"
  e2e_expect_clean_edges
fi

if _want sa-default-off; then
  _flow_test_begin "sa-default-off"
  _sa_setup sa-default-off "W4: a provider is set and the site is not named: the shipped default is off, so the probe prints nothing"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user "" a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _sa_block
  e2e_expect_line "REASON=mode-off"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-provider-none; then
  _flow_test_begin "sa-provider-none"
  _sa_setup sa-provider-none "W4: provider none with the site on and a stub address present: nothing is sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"none",baseUrl:$u,uses:{"address.still_applies":"on"}}}')"
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _sa_block
  e2e_expect_line "REASON=provider-none"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-inside-repo; then
  _flow_test_begin "sa-inside-repo"
  _sa_setup sa-inside-repo "W4: the plugin sits inside the repository, as it does in synapti-marketplace, and no install outside the repository exists: the probe prints nothing, and the block, which never uses a copy inside the repository, finds no plugin and sends nothing"
  cp -R "$E2E_ACTIVE_PLUGIN" "$E2E_REPO/plugin-copy"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugin-copy"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=plugin-missing"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-inside-repo-installed-outside; then
  _flow_test_begin "sa-inside-repo-installed-outside"
  _sa_setup sa-inside-repo-installed-outside "W18: the plugin is loaded from a copy inside the repository and flow is also installed outside it: the probe and the block skip the copy inside and use the install outside, so the site the user switched on prints its mode and the comment is asked about once per shell"
  mkdir -p "$E2E_HOME/.claude/plugins/cache/synapti-marketplace/flow"
  cp -R "$E2E_PLUGIN_DIR" "$E2E_HOME/.claude/plugins/cache/synapti-marketplace/flow/$(jq -r .version "$E2E_PLUGIN_DIR/.claude-plugin/plugin.json")"
  cp -R "$E2E_ACTIVE_PLUGIN" "$E2E_REPO/plugin-copy"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugin-copy"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_probe
  e2e_expect_equal "S1_STILL_APPLIES=on" "$E2E_OUT" "probe stdout"
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "STILL_APPLIES=addressed"
  _sa_requests a 1
  e2e_expect_equal "on answered pr:7/inline:101" \
    "$(head -n 1 "$(_sa_records)" | jq -r '"\(.mode) \(.result) \(.ref)"' 2>/dev/null)" "record in the user's state"
  e2e_expect_equal "" "$(find "$E2E_REPO" -name system-one.jsonl 2>/dev/null)" "records inside the repository"
  e2e_expect_clean_edges
fi

if _want sa-repo-helper-not-run; then
  _flow_test_begin "sa-repo-helper-not-run"
  _sa_setup sa-repo-helper-not-run "W18: the repository commits its own plugins/flow/bin/flow-s1-mode.sh, which prints on, and nothing is installed: with no plugin root set, the probe never runs that script and prints nothing, and the block finds no plugin"
  mkdir -p "$E2E_REPO/plugins/flow/bin"
  printf '#!/bin/sh\n: > "%s"\necho on\n' "$E2E_DIR/repo-helper-ran" > "$E2E_REPO/plugins/flow/bin/flow-s1-mode.sh"
  printf '#!/bin/sh\n: > "%s"\n' "$E2E_DIR/repo-helper-ran" > "$E2E_REPO/plugins/flow/bin/cascade-resolve.sh"
  printf '#!/bin/sh\n: > "%s"\n' "$E2E_DIR/repo-helper-ran" > "$E2E_REPO/plugins/flow/bin/flow-s1.sh"
  chmod +x "$E2E_REPO"/plugins/flow/bin/*.sh
  ( _e2e_git_env; cd "$E2E_REPO" && git add plugins && git commit -q -m "add a plugin copy" ) \
    || _flow_assert_fail "sa-repo-helper-not-run: could not commit the fixture"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  e2e_run_block CLAUDE_PLUGIN_ROOT= "$ADDRESS_MD" S1_ADDRESS_MODES_BLOCK
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  e2e_expect_equal "no" "$([ -e "$E2E_DIR/repo-helper-ran" ] && echo yes || echo no)" "a script inside the repository ran, after the probe"
  _sa_block CLAUDE_PLUGIN_ROOT=
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=plugin-missing"
  e2e_expect_equal "no" "$([ -e "$E2E_DIR/repo-helper-ran" ] && echo yes || echo no)" "a script inside the repository ran, after the block"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-on-addressed; then
  _flow_test_begin "sa-on-addressed"
  _sa_setup sa-on-addressed "W1: on, and the model says the concern is not present (p 0.03, confidence 0.94 against the provisional 0.9): addressed, with the place and commit checked"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_probe
  e2e_expect_equal "S1_STILL_APPLIES=on" "$E2E_OUT" "probe stdout"
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "STILL_APPLIES=addressed"
  e2e_expect_line "P=0.03"
  e2e_expect_line "CONFIDENCE=0.94"
  e2e_expect_line "MODEL=jev-1.13.0"
  # Line 20 of 120, at most 40 lines either side: lines 1 to 60.
  e2e_expect_line "CHECKED=src/app.py:1-60@$(_sa_head)"
  # shellcheck disable=SC2016
  e2e_expect_line "CHECKED_SPAN=\`src/app.py:1-60@$(_sa_head)\`"
  # shellcheck disable=SC2016
  e2e_expect_line "CHECKED_CELL=\`src/app.py:1-60@$(_sa_head)\`"
  e2e_expect_no_out "TRUNCATED"
  _sa_requests a 1
  e2e_expect_equal "This loop does not handle an empty list." "$(_sa_sent a | jq -r '.state.comment.body')" "comment body sent"
  e2e_expect_equal "1 60 true true" "$(_sa_sent a | jq -r '.state.code_now | "\(.start) \(.end) \(.text | startswith("line 1\nline 2\n")) \(.original_lines_present)"')" "code window sent, the commented line present"
  e2e_expect_equal "false" "$(_sa_sent a | jq -r '.state | tostring | contains("reviewer-x")')" "the reviewer is not sent"
  e2e_expect_equal "on answered address.still_applies concern_present pr:7/inline:101" \
    "$(head -n 1 "$(_sa_records)" | jq -r '"\(.mode) \(.result) \(.site) \(.question) \(.ref)"' 2>/dev/null)" "record"
  e2e_expect_clean_edges
fi

if _want sa-on-applies; then
  _flow_test_begin "sa-on-applies"
  _sa_setup sa-on-applies "W1: on, and the model says the concern is still present (p 0.97): applies"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "STILL_APPLIES=applies"
  e2e_expect_no_line "STILL_APPLIES=addressed"
  _sa_requests a 1
  e2e_expect_clean_edges
fi

if _want sa-on-below-threshold; then
  _flow_test_begin "sa-on-below-threshold"
  _sa_setup sa-on-below-threshold "W8: p 0.6 is confidence 0.2, below the threshold: no answer, and the record keeps the answer"
  e2e_stub_start a "$(_noul_reply 0.6)"
  _sa_user on a
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=no-answer"
  e2e_expect_line "REASON=below-threshold"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 1
  e2e_expect_equal "below-threshold 0.6" "$(head -n 1 "$(_sa_records)" | jq -r '"\(.result) \(.answer.p)"' 2>/dev/null)" "record"
  e2e_expect_clean_edges
fi

if _want sa-no-answer; then
  _flow_test_begin "sa-no-answer"
  _sa_setup sa-no-answer "W8: an HTTP 500, a reply slower than timeoutMs and a malformed reply each give no answer with their reason, and never an answer"
  e2e_stub_start a '{"status":500,"body":{"detail":"boom"}}'
  e2e_stub_start b "{\"delay_ms\":1500,$(_noul_reply 0.03 | sed 's/^{//')"
  e2e_stub_start c '{"body":{"model":"jev-1.13.0","answers":{"concern_present":{"type":"noul","noul":"low"}}}}'
  _sa_user on a
  _sa_block
  e2e_expect_line "REASON=http-500"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 1
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:200,uses:{"address.still_applies":"on"}}}')"
  _sa_block
  e2e_expect_line "REASON=timeout"
  e2e_expect_no_out "STILL_APPLIES="
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url c)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"address.still_applies":"on"}}}')"
  _sa_block
  e2e_expect_line "REASON=malformed"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests c 1
  e2e_expect_clean_edges
fi

if _want sa-shadow; then
  _flow_test_begin "sa-shadow"
  _sa_setup sa-shadow "W3, W10: shadow with Explore's verdict as CURRENT: no answer is printed, the record holds both, and the state file kept beside it is the one that was sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user shadow a
  mkdir -p "$E2E_REPO/.flow/runs/R1"
  _sa_probe
  e2e_expect_equal "S1_STILL_APPLIES=shadow" "$E2E_OUT" "probe stdout"
  _sa_block RUN_ID=R1 CURRENT=applies
  e2e_expect_line "STILL_APPLIES_STATE=no-answer"
  e2e_expect_line "REASON=shadow"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 1
  REC="$E2E_REPO/.flow/runs/R1/system-one.jsonl"
  # Two shells ran the block, so two records; the first is checked.
  e2e_expect_equal "shadow applies 0.03 answered" "$(head -n 1 "$REC" | jq -r '"\(.mode) \(.current) \(.answer.p) \(.result)"' 2>/dev/null)" "record"
  SAVED="$E2E_REPO/.flow/runs/R1/system-one-state/101.json"
  if [ -f "$SAVED" ]; then
    e2e_expect_equal "$(tail -n 1 "$REC" | jq -r '.state_sha256')" "$(_e2e_sha256 "$SAVED")" "sha256 of the saved state file"
    e2e_expect_equal "$(tail -n 1 "$(e2e_stub_log a)" | jq -cS '.body.state')" "$(jq -cS '.' "$SAVED")" "saved state equals the state sent"
  else
    _e2e_result fail "the state file is saved under the run"
  fi
  e2e_expect_clean_edges
fi

if _want sa-current-invalid; then
  _flow_test_begin "sa-current-invalid"
  _sa_setup sa-current-invalid "CURRENT outside applies and addressed is a usage error: exit 2, nothing sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user shadow a
  _sa_block CURRENT=maybe
  e2e_expect_equal 2 "$E2E_RC" "exit status"
  e2e_expect_line "STATE=blocked"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-repo-cannot-raise; then
  _flow_test_begin "sa-repo-cannot-raise"
  _sa_setup sa-repo-cannot-raise "W2: the user chose shadow and the checked-out pull request sets the site on: the probe says shadow, nothing is acted on, and the record says shadow"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user shadow a
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"address.still_applies":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _sa_probe
  e2e_expect_equal "S1_STILL_APPLIES=shadow" "$E2E_OUT" "probe stdout"
  _sa_block CURRENT=applies
  e2e_expect_no_out "STILL_APPLIES=addressed"
  e2e_expect_line "REASON=shadow"
  _sa_requests a 1
  e2e_expect_equal "shadow" "$(head -n 1 "$(_sa_records)" | jq -r '.mode' 2>/dev/null)" "record mode"
  e2e_expect_clean_edges
fi

if _want sa-repo-cannot-switch-on; then
  _flow_test_begin "sa-repo-cannot-switch-on"
  _sa_setup sa-repo-cannot-switch-on "W2: the user has a provider and leaves the site unset, then sets it off, and the checked-out pull request sets the site on: the probe prints nothing and the block sends nothing"
  e2e_stub_start a "$(_noul_reply 0.03)"
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"address.still_applies":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _sa_user "" a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, site unset for the user"
  _sa_block
  e2e_expect_line "REASON=mode-off"
  _sa_user off a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, site off for the user"
  _sa_block
  e2e_expect_line "REASON=mode-off"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-repo-shadow-cannot-start; then
  _flow_test_begin "sa-repo-shadow-cannot-start"
  _sa_setup sa-repo-shadow-cannot-start "W2: the checked-out pull request sets the site to shadow, which would send the state of the comment to the user's provider: with the site unset or off for the user the probe prints nothing and the block sends nothing; and a repository's off lowers the user's on"
  e2e_stub_start a "$(_noul_reply 0.03)"
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"address.still_applies":"shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _sa_user "" a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, site unset for the user"
  _sa_block CURRENT=applies
  e2e_expect_line "REASON=mode-off"
  _sa_user off a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, site off for the user"
  _sa_block CURRENT=applies
  e2e_expect_line "REASON=mode-off"
  printf '%s\n' '{"systemOne":{"uses":{"address.still_applies":"off"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _sa_user on a
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, user on and repository off"
  _sa_block
  e2e_expect_line "REASON=mode-off"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-not-a-line-now; then
  _flow_test_begin "sa-not-a-line-now"
  _sa_setup sa-not-a-line-now "W12: a comment on a removed line (side LEFT, line 100 of the base file), a comment on the whole file, a reply in a thread, and a comment of pull request 8: each skipped with its reason, nothing sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/app.py","side":"LEFT","line":100,"original_line":100,"diff_hunk":"@@ -98,3 +130,0 @@\n-old 98\n-old 99\n-old 100","body":"removed check"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=removed-line"
  _sa_comment '{"id":101,"path":"src/app.py","subject_type":"file","line":null,"original_line":null,"diff_hunk":"@@ -1,2 +1,2 @@\n line 1\n+line 2","body":"whole file"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=file-comment"
  # shellcheck disable=SC2016
  _sa_comment '{"id":101,"in_reply_to_id":100,"path":"src/app.py","line":20,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"Addressed in `abc`."}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=reply"
  _sa_comment '{"id":101,"pull_request_url":"https://api.github.com/repos/o/r/pulls/8","path":"src/app.py","line":20,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"x"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=comment-not-found"
  # A right-side comment and an outdated line comment still reach the model.
  _sa_comment '{"id":101,"side":"RIGHT","subject_type":"line","path":"src/app.py","line":20,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"x"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  _sa_requests a 1
  e2e_expect_clean_edges
fi

if _want sa-path-injection; then
  _flow_test_begin "sa-path-injection"
  _sa_setup sa-path-injection "W11: a committed file named src/\$(touch pwned).py: CHECKED prints the path as it is, and the reply citing it, written to a file and posted by the reply block, reaches gh byte for byte with no file created"
  # shellcheck disable=SC2016
  INJ='src/$(touch pwned).py'
  _sa_source > "$E2E_REPO/$INJ"
  ( _e2e_git_env; cd "$E2E_REPO" && git add -A && git commit -q -m "add injected name" ) \
    || _flow_assert_fail "sa-path-injection: could not commit the fixture"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment "$(jq -nc --arg p "$INJ" '{id:101,path:$p,line:20,original_line:20,diff_hunk:"@@ -18,3 +18,3 @@\n+line 20",body:"x"}')"
  _sa_block
  e2e_expect_line "STILL_APPLIES=addressed"
  e2e_expect_line "CHECKED=$INJ:1-60@$(_sa_head)"
  CHECKED=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^CHECKED=//p' | head -n 1)
  mkdir -p "$E2E_DIR/tmp"
  REPLY_FILE=$(mktemp "$E2E_DIR/tmp/tmp.XXXXXX")
  # shellcheck disable=SC2016
  printf 'Already addressed: checked against `%s` (System One, confidence 0.94). No change made for it in this cycle.\n' "$CHECKED" > "$REPLY_FILE"
  e2e_gh_fixture reply-101 '{"id":202}'
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID=101 REPLY_FILE="$REPLY_FILE" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "reply exit status"
  e2e_expect_line "REPLY_EXIT=0"
  e2e_expect_equal "$(for _ in $(seq 1 "$SA_SHELLS"); do cat "$REPLY_FILE"; done)" "$(cat "$E2E_GH/reply-101.posted" 2>/dev/null)" "reply text gh received, once per shell"
  if [ -n "$(find "$E2E_DIR" -name 'pwned' 2>/dev/null)" ]; then _e2e_result fail "no pwned file was created"
  else _e2e_result pass "no pwned file was created"; fi
  e2e_expect_equal "0" "$(grep -c 'body="' "$E2E_PLUGIN_DIR/$ADDRESS_MD")" "lines of commands/address.md that put a body in a double-quoted string"
  e2e_expect_clean_edges
fi

if _want sa-checked-markdown; then
  _flow_test_begin "sa-checked-markdown"
  _sa_setup sa-checked-markdown "W24: a committed file whose name holds a | and a backtick: CHECKED_SPAN is a code span whose fence is longer than the backtick, and CHECKED_CELL also writes the | as \\|, so the reply's code span and the Thread Status row keep their shape"
  # shellcheck disable=SC2016
  ODD='src/a|b`c.py'
  _sa_source > "$E2E_REPO/$ODD"
  ( _e2e_git_env; cd "$E2E_REPO" && git add -A && git commit -q -m "add odd name" ) \
    || _flow_assert_fail "sa-checked-markdown: could not commit the fixture"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment "$(jq -nc --arg p "$ODD" '{id:101,path:$p,line:20,original_line:20,diff_hunk:"@@ -18,3 +18,3 @@\n+line 20",body:"x"}')"
  _sa_block
  e2e_expect_line "STILL_APPLIES=addressed"
  e2e_expect_line "CHECKED=$ODD:1-60@$(_sa_head)"
  # shellcheck disable=SC2016
  e2e_expect_line "CHECKED_SPAN=\`\` src/a|b\`c.py:1-60@$(_sa_head) \`\`"
  # shellcheck disable=SC2016
  e2e_expect_line "CHECKED_CELL=\`\` src/a\\|b\`c.py:1-60@$(_sa_head) \`\`"
  e2e_expect_clean_edges
fi

if _want sa-reply-refused; then
  _flow_test_begin "sa-reply-refused"
  _sa_setup sa-reply-refused "W20: the reply block refuses a missing or empty reply file, a COMMENT_ID that is not a number, and a file the session did not make with mktemp (outside TMPDIR, a symlink in TMPDIR, a relative path), and posts nothing"
  e2e_gh_fixture reply-101 '{"id":202}'
  mkdir -p "$E2E_DIR/tmp" "$E2E_DIR/secret"
  : > "$E2E_DIR/tmp/tmp.empty"
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID=101 REPLY_FILE="$E2E_DIR/tmp/tmp.none" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status, missing file"
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID=101 REPLY_FILE="$E2E_DIR/tmp/tmp.empty" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status, empty file"
  printf 'x\n' > "$E2E_DIR/tmp/tmp.reply"
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID='101;x' REPLY_FILE="$E2E_DIR/tmp/tmp.reply" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status, COMMENT_ID not a number"
  printf 'aws_secret_access_key = x\n' > "$E2E_DIR/secret/credentials"
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID=101 REPLY_FILE="$E2E_DIR/secret/credentials" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status, a file outside TMPDIR"
  e2e_expect_err "it was not posted"
  ln -s "$E2E_DIR/secret/credentials" "$E2E_DIR/tmp/tmp.link"
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID=101 REPLY_FILE="$E2E_DIR/tmp/tmp.link" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status, a symlink in TMPDIR"
  e2e_run_block TMPDIR="$E2E_DIR/tmp" PR_NUM=7 COMMENT_ID=101 REPLY_FILE="secret/credentials" "$ADDRESS_MD" INLINE_REPLY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status, a relative path"
  e2e_expect_equal "no" "$([ -e "$E2E_GH/reply-101.posted" ] && echo yes || echo no)" "a reply was posted"
  e2e_expect_clean_edges
fi

if _want sa-outdated-located; then
  _flow_test_begin "sa-outdated-located"
  _sa_setup sa-outdated-located "W5: an outdated comment (line null) whose anchor, the last line of its diff hunk that is not removed, now sits at line 60, fifty lines lower: the window is around line 60"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/app.py","line":null,"original_line":10,"diff_hunk":"@@ -8,3 +8,3 @@\n line 8\n line 9\n+    return compute_total(items)\n-    return total","body":"compute_total ignores discounts."}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "CHECKED=src/app.py:20-100@$(_sa_head)"
  _sa_requests a 1
  e2e_expect_equal "20 100 true true true" "$(_sa_sent a | jq -r '.state | "\(.code_now.start) \(.code_now.end) \(.code_now.text | contains("    return compute_total(items)\n")) \(.comment.outdated) \(.code_now.original_lines_present)"')" "window around the anchor, the lines present"
  e2e_expect_clean_edges
fi

if _want sa-outdated-not-found; then
  _flow_test_begin "sa-outdated-not-found"
  _sa_setup sa-outdated-not-found "W5: an outdated comment whose anchor is nowhere in the file now and which has no original line: there is no place to look, so it is skipped and nothing is sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/app.py","line":null,"original_line":null,"diff_hunk":"@@ -8,2 +8,2 @@\n line 8\n+    return gone()","body":"x"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=location-not-found"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-outdated-lines-replaced; then
  _flow_test_begin "sa-outdated-lines-replaced"
  _sa_setup sa-outdated-lines-replaced "W19: a comment whose lines a later commit replaced (GitHub marks it outdated, line null, and its anchor is nowhere in the file now) is asked about anyway: the state holds its diff hunk byte for byte, the code now around its original line (10, so lines 1 to 50), and original_lines_present false; on, p 0.03, it is already addressed. An original line past the end of the file now (200 of 120) is clamped to the last line: lines 80 to 120"
  # The history a fix leaves: line 10 held the commented code, a later commit
  # replaced it with what the fixture holds now.
  sed 's/^line 10$/    total = sum(items)/' "$E2E_REPO/src/app.py" > "$E2E_DIR/old.py" && cp "$E2E_DIR/old.py" "$E2E_REPO/src/app.py"
  ( _e2e_git_env; cd "$E2E_REPO" && git commit -q -am "the commented code" ) \
    || _flow_assert_fail "sa-outdated-lines-replaced: could not commit the old code"
  _sa_source > "$E2E_REPO/src/app.py"
  ( _e2e_git_env; cd "$E2E_REPO" && git commit -q -am "fix: replace the commented line" ) \
    || _flow_assert_fail "sa-outdated-lines-replaced: could not commit the fix"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  HUNK=$(printf '@@ -8,3 +8,3 @@\n line 8\n line 9\n+    total = sum(items)')
  _sa_comment "$(jq -nc --arg h "$HUNK" '{id:101,path:"src/app.py",line:null,original_line:10,diff_hunk:$h,body:"sum() ignores discounts."}')"
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "STILL_APPLIES=addressed"
  e2e_expect_line "CHECKED=src/app.py:1-50@$(_sa_head)"
  _sa_requests a 1
  e2e_expect_equal "true" "$(_sa_sent a | jq -r --arg h "$HUNK" '.state.comment.diff_hunk == $h')" "diff hunk sent byte for byte"
  e2e_expect_equal "1 50 false true true null 10" "$(_sa_sent a | jq -r '.state | "\(.code_now.start) \(.code_now.end) \(.code_now.original_lines_present) \(.comment.outdated) \(.code_now.text | startswith("line 1\n") and endswith("line 50\n")) \(.comment.line) \(.comment.original_line)"')" "state: window around the original line, the lines marked gone"
  e2e_expect_equal "on answered pr:7/inline:101" \
    "$(head -n 1 "$(_sa_records)" | jq -r '"\(.mode) \(.result) \(.ref)"' 2>/dev/null)" "record"
  _sa_comment "$(jq -nc --arg h "$HUNK" '{id:101,path:"src/app.py",line:null,original_line:200,diff_hunk:$h,body:"x"}')"
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "CHECKED=src/app.py:80-120@$(_sa_head)"
  _sa_requests a 2
  e2e_expect_equal "80 120 false" "$(tail -n 1 "$(e2e_stub_log a)" | jq -r '.body.state.code_now | "\(.start) \(.end) \(.original_lines_present)"')" "state: original line past the end, clamped"
  e2e_expect_clean_edges
fi

if _want sa-outdated-file-deleted; then
  _flow_test_begin "sa-outdated-file-deleted"
  _sa_setup sa-outdated-file-deleted "W19: an outdated comment on a file a later commit deleted: the code-now fallback does not apply, it is skipped as file-missing, nothing is sent and it is never reported as addressed"
  _sa_source > "$E2E_REPO/src/old.py"
  ( _e2e_git_env; cd "$E2E_REPO" && git add src/old.py && git commit -q -m "add old" && git rm -q src/old.py && git commit -q -m "delete old" ) \
    || _flow_assert_fail "sa-outdated-file-deleted: could not commit the fixture"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/old.py","line":null,"original_line":10,"diff_hunk":"@@ -8,3 +8,3 @@\n line 8\n line 9\n+    total = sum(items)","body":"x"}'
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=file-missing"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-outdated-hunk-injection; then
  _flow_test_begin "sa-outdated-hunk-injection"
  _sa_setup sa-outdated-hunk-injection "W6, W19: an outdated comment whose diff hunk, sent because its anchor is gone, holds \$(touch pwned), backticks, quotes, lines equal to here-document delimiters, a newline and U+2028: it is data, no file is created and the stub receives it byte for byte"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  # shellcheck disable=SC2016
  HUNK=$(printf '@@ -8,4 +8,4 @@\n EOF\n DISPUTED_PY\n-  x = "$(touch pwned)"\n+  y = `touch pwned2`; echo '"'"'it'"'"'s\xe2\x80\xa8done $(touch pwned3)')
  _sa_comment "$(jq -nc --arg h "$HUNK" '{id:101,path:"src/app.py",line:null,original_line:30,diff_hunk:$h,body:"x"}')"
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "STILL_APPLIES=applies"
  e2e_expect_line "CHECKED=src/app.py:1-70@$(_sa_head)"
  _sa_requests a 1
  e2e_expect_equal "true false" "$(_sa_sent a | jq -r --arg h "$HUNK" '.state | "\(.comment.diff_hunk == $h) \(.code_now.original_lines_present)"')" "diff hunk received byte for byte; lines marked gone"
  if [ -n "$(find "$E2E_DIR" -name 'pwned*' 2>/dev/null)" ]; then _e2e_result fail "no pwned file was created"
  else _e2e_result pass "no pwned file was created"; fi
  e2e_expect_clean_edges
fi

if _want sa-outdated-ambiguous; then
  _flow_test_begin "sa-outdated-ambiguous"
  _sa_setup sa-outdated-ambiguous "W5: an outdated comment whose anchor appears twice in the file now: skipped, nothing sent"
  printf 'line 61\n' >> "$E2E_REPO/src/app.py"
  ( _e2e_git_env; cd "$E2E_REPO" && git commit -q -am "repeat a line" ) \
    || _flow_assert_fail "sa-outdated-ambiguous: could not commit the fixture"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/app.py","line":null,"original_line":10,"diff_hunk":"@@ -60,2 +60,2 @@\n line 59\n line 61","body":"x"}'
  _sa_block
  e2e_expect_line "REASON=location-not-found"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-file-missing; then
  _flow_test_begin "sa-file-missing"
  _sa_setup sa-file-missing "a comment on a file deleted since: skipped, nothing sent, never reported as addressed"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/gone.py","line":3,"original_line":3,"diff_hunk":"@@ -1,3 +1,3 @@\n+x","body":"x"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=file-missing"
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-path-escapes; then
  _flow_test_begin "sa-path-escapes"
  _sa_setup sa-path-escapes "W7: a path that is a symlink to a file outside the repository, a path through a symlinked directory, and a path with .. : each skipped, nothing sent"
  printf 'SECRET outside the repository\n' > "$E2E_DIR/outside.txt"
  ln -s "$E2E_DIR/outside.txt" "$E2E_REPO/src/link.py"
  ln -s "$E2E_DIR" "$E2E_REPO/linkdir"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/link.py","line":1,"original_line":1,"diff_hunk":"@@ -1 +1 @@\n+x","body":"x"}'
  _sa_block
  e2e_expect_line "REASON=file-missing"
  _sa_comment '{"id":101,"path":"linkdir/outside.txt","line":1,"original_line":1,"diff_hunk":"@@ -1 +1 @@\n+x","body":"x"}'
  _sa_block
  e2e_expect_line "REASON=file-missing"
  _sa_comment '{"id":101,"path":"src/../../outside.txt","line":1,"original_line":1,"diff_hunk":"@@ -1 +1 @@\n+x","body":"x"}'
  _sa_block
  e2e_expect_line "REASON=file-missing"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-comment-injection; then
  _flow_test_begin "sa-comment-injection"
  _sa_setup sa-comment-injection "W6: a comment body holding \$(touch pwned), a double quote, a single quote, a newline and U+2028 is data: no file is created and the stub receives it byte for byte"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  BODY=$(printf 'Run $(touch pwned) and `touch pwned2`; say "hi" it'"'"'s\nnext\xe2\x80\xa8line')
  _sa_comment "$(jq -nc --arg b "$BODY" '{id:101,path:"src/app.py",line:20,original_line:20,diff_hunk:"@@ -1 +1 @@\n+line 20",body:$b}')"
  _sa_block
  e2e_expect_line "STILL_APPLIES=applies"
  _sa_requests a 1
  e2e_expect_equal "true" "$(jq -r --arg b "$BODY" '.body.state.comment.body == $b' "$(e2e_stub_log a)" | head -n 1)" "body received byte for byte"
  if [ -n "$(find "$E2E_DIR" -name 'pwned*' 2>/dev/null)" ]; then _e2e_result fail "no pwned file was created"
  else _e2e_result pass "no pwned file was created"; fi
  e2e_expect_clean_edges
fi

if _want sa-comment-not-found; then
  _flow_test_begin "sa-comment-not-found"
  _sa_setup sa-comment-not-found "gh answers with a comment whose id is not the one asked for, and then with none at all (HTTP 502): skipped, exit 0, nothing sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_comment '{"id":999,"path":"src/app.py","line":20,"original_line":20,"diff_hunk":"@@ -1 +1 @@\n+x","body":"x"}'
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "REASON=comment-not-found"
  e2e_gh_not_found pull-comment-101
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=comment-not-found"
  rm -f "$E2E_GH/pull-comment-101.404"
  e2e_gh_fail pull-comment-101
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=gh-unavailable"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-no-run-id; then
  _flow_test_begin "sa-no-run-id"
  _sa_setup sa-no-run-id "no RUN_ID: the record goes to the per-user state directory and the temporary state file is removed"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  mkdir -p "$E2E_DIR/tmp"
  _sa_block TMPDIR="$E2E_DIR/tmp"
  e2e_expect_line "STILL_APPLIES=applies"
  e2e_expect_equal "answered" "$(head -n 1 "$(_sa_records)" | jq -r '.result' 2>/dev/null)" "record in the per-user state directory"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "temporary directory after the run"
  e2e_expect_equal "" "$(find "$E2E_REPO" -name system-one-state 2>/dev/null)" "state directory in the repository"
  e2e_expect_clean_edges
fi

if _want sa-run-id-invalid; then
  _flow_test_begin "sa-run-id-invalid"
  _sa_setup sa-run-id-invalid "a RUN_ID with .. or a slash, and a PR_NUM with a leading zero, are usage errors: exit 2, nothing sent"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  _sa_block RUN_ID=../x
  e2e_expect_equal 2 "$E2E_RC" "exit status"
  e2e_expect_line "STATE=blocked"
  e2e_run_block PR_NUM=07 COMMENT_ID=101 "$ADDRESS_MD" STILL_APPLIES_BLOCK
  e2e_expect_equal 2 "$E2E_RC" "exit status"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-truncated; then
  _flow_test_begin "sa-truncated"
  _sa_setup sa-truncated "W21: on, the state is larger than the user's stateTokenCap, so the client shortens it, and the model says the concern is gone (p 0.03): the answer may be about a state without the commented line, so no answer (REASON=truncated) and Explore runs"
  e2e_stub_start a "$(_noul_reply 0.03)"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:200,uses:{"address.still_applies":"on"}}}')"
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=no-answer"
  e2e_expect_line "REASON=truncated"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 1
  e2e_expect_equal "true" "$(_sa_sent a | jq -r '(.state.code_now.text | length) < 400')" "the state sent was shortened"
  e2e_expect_clean_edges
fi

if _want sa-head-mismatch; then
  _flow_test_begin "sa-head-mismatch"
  _sa_setup sa-head-mismatch "W22: a comment GitHub still places (line 20) whose commit_id is not the commit checked out: its line may count lines of other code, so it is skipped (head-mismatch) and nothing is sent; with commit_id equal to HEAD it is asked about"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/app.py","line":20,"original_line":20,"commit_id":"0123456789abcdef0123456789abcdef01234567","diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"x"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=head-mismatch"
  _sa_requests a 0
  SA_FULL_HEAD=$( _e2e_git_env; cd "$E2E_REPO" && git rev-parse HEAD )
  _sa_comment "$(jq -nc --arg c "$SA_FULL_HEAD" '{id:101,path:"src/app.py",line:20,original_line:20,commit_id:$c,diff_hunk:"@@ -18,3 +18,3 @@\n+line 20",body:"x"}')"
  _sa_block
  e2e_expect_line "STILL_APPLIES=applies"
  _sa_requests a 1
  e2e_expect_clean_edges
fi

if _want sa-line-written-as-float; then
  _flow_test_begin "sa-line-written-as-float"
  _sa_setup sa-line-written-as-float "a comment whose line is the JSON number 20.0: it is line 20, located the same way as 20, not skipped"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  e2e_gh_fixture pull-comment-101 '{"id":101,"path":"src/app.py","line":20.0,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"x","pull_request_url":"https://api.github.com/repos/o/r/pulls/7"}'
  e2e_expect_equal '"line":20.0' "$(grep -o '"line":20.0' "$E2E_GH/pull-comment-101.json")" "the fixture keeps 20.0"
  _sa_block
  e2e_expect_line "STILL_APPLIES=applies"
  e2e_expect_line "CHECKED=src/app.py:1-60@$(_sa_head)"
  _sa_requests a 1
  e2e_expect_clean_edges
fi

if _want sa-state-script-failures; then
  _flow_test_begin "sa-state-script-failures"
  _sa_setup sa-state-script-failures "the state script fails in ways that are not a reason: TMPDIR names a regular file, so it has no temporary file (tmp-failed, run directly); and a state script that exits 2 with no output is reported as state-error, not as location-not-found"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  printf '%s' '{"id":101,"path":"src/app.py","line":20,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"x"}' > "$E2E_DIR/comment.json"
  : > "$E2E_DIR/tmp-file"
  e2e_run_bin TMPDIR="$E2E_DIR/tmp-file" bin/flow-comment-state.sh --comment "$E2E_DIR/comment.json" --out "$E2E_DIR/state.json"
  e2e_expect_equal 1 "$E2E_RC" "exit status, run directly"
  e2e_expect_line "REASON=tmp-failed"
  e2e_plugin_copy bin/flow-comment-state.sh '#!/bin/sh
exit 2'
  _sa_block
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=state-error"
  _sa_requests a 0
  e2e_expect_clean_edges
fi

if _want sa-phase1-all-pages; then
  _flow_test_begin "sa-phase1-all-pages"
  _sa_setup sa-phase1-all-pages "W23: a pull request with 31 inline comments, 30 on the first page of the list endpoint and 1 on the second: Phase 1 lists all 31, so the comment on the second page reaches the still-applies check and the address loop"
  SA_PAGE1=$(jq -nc '[range(101; 131) | {id: ., user: {login: "r"}, path: "src/app.py", line: 20, body: "x"}]')
  SA_PAGE2=$(jq -nc '[{id: 131, user: {login: "r"}, path: "src/other.py", line: 5, body: "late"}]')
  e2e_gh_pages pull-comments-7 "$SA_PAGE1" "$SA_PAGE2"
  e2e_run_block REPO=o/r PR_NUM=7 "$ADDRESS_MD" INLINE_COMMENTS_BLOCK
  e2e_expect_line "INLINE_COUNT=31"
  e2e_expect_line "INLINE_COMMENT=id=131 author=@r path=src/other.py line=5 length=4"
  e2e_expect_equal 31 "$(printf '%s\n' "$E2E_OUT" | grep -c '^INLINE_COMMENT=')" "INLINE_COMMENT rows"
  e2e_expect_clean_edges
fi

if _want sa-uncommitted; then
  _flow_test_begin "sa-uncommitted"
  _sa_setup sa-uncommitted "W13: a comment on a file with an edit that is not committed, and one on a file that is not in HEAD, are skipped and nothing is sent; once the edit is committed the comment is asked about"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user on a
  printf 'line 121\n' >> "$E2E_REPO/src/app.py"
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=skipped"
  e2e_expect_line "REASON=uncommitted"
  e2e_expect_no_out "STILL_APPLIES="
  _sa_source > "$E2E_REPO/src/new.py"
  _sa_comment '{"id":101,"path":"src/new.py","line":20,"original_line":20,"diff_hunk":"@@ -18,3 +18,3 @@\n+line 20","body":"x"}'
  _sa_block
  e2e_expect_line "REASON=uncommitted"
  _sa_requests a 0
  _sa_no_records
  ( _e2e_git_env; cd "$E2E_REPO" && git add -A && git commit -q -m "commit the edits" ) \
    || _flow_assert_fail "sa-uncommitted: could not commit the edits"
  _sa_block
  e2e_expect_line "STILL_APPLIES=addressed"
  e2e_expect_line "CHECKED=src/new.py:1-60@$(_sa_head)"
  _sa_requests a 1
  e2e_expect_clean_edges
fi

if _want sa-outdated-numeric; then
  _flow_test_begin "sa-outdated-numeric"
  _sa_setup sa-outdated-numeric "W14: an outdated comment whose anchor is 1, in a file holding the lines 1.0 and 1: the anchor is found once, at the line 1, not twice"
  printf 'x = (\n1.0\n,\n1\n)\n' > "$E2E_REPO/src/num.py"
  ( _e2e_git_env; cd "$E2E_REPO" && git add src/num.py && git commit -q -m "add num" ) \
    || _flow_assert_fail "sa-outdated-numeric: could not commit the fixture"
  e2e_stub_start a "$(_noul_reply 0.97)"
  _sa_user on a
  _sa_comment '{"id":101,"path":"src/num.py","line":null,"original_line":2,"diff_hunk":"@@ -1,2 +1,2 @@\n x = (\n+1","body":"x"}'
  _sa_block
  e2e_expect_line "STILL_APPLIES_STATE=answered"
  e2e_expect_line "CHECKED=src/num.py:1-5@$(_sa_head)"
  _sa_requests a 1
  e2e_expect_clean_edges
fi

if _want sa-state-target; then
  _flow_test_begin "sa-state-target"
  _sa_setup sa-state-target "W15: shadow with a run directory where the state file name is already a directory, then where system-one-state is a symlink to a directory outside the repository: a warning, and nothing is written into either"
  e2e_stub_start a "$(_noul_reply 0.03)"
  _sa_user shadow a
  mkdir -p "$E2E_REPO/.flow/runs/R1/system-one-state/101.json"
  _sa_block RUN_ID=R1 CURRENT=applies
  e2e_expect_line "REASON=shadow"
  e2e_expect_err "could not be saved beside the run"
  e2e_expect_equal "" "$(find "$E2E_REPO/.flow/runs/R1/system-one-state" -type f 2>/dev/null)" "files under system-one-state, when the state file name is a directory"
  mkdir -p "$E2E_DIR/outside-state" "$E2E_REPO/.flow/runs/R2"
  ln -s "$E2E_DIR/outside-state" "$E2E_REPO/.flow/runs/R2/system-one-state"
  _sa_block RUN_ID=R2 CURRENT=applies
  e2e_expect_line "REASON=shadow"
  e2e_expect_err "could not be saved beside the run"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/outside-state")" "files in the directory the symlink points to"
  _sa_requests a 2
  e2e_expect_clean_edges
fi

if _want sa-repo-provider-only; then
  _flow_test_begin "sa-repo-provider-only"
  _sa_setup sa-repo-provider-only "W16: the user sets no provider, and the checked-out pull request sets a provider, its address and both sites to shadow: the probe prints nothing and the block sends nothing"
  e2e_stub_start a "$(_noul_reply 0.03)"
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"address.still_applies":"shadow","address.category":"shadow"}}}' \
    > "$E2E_REPO/.claude/settings.flow.json"
  _sa_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _sa_block CURRENT=applies
  e2e_expect_no_out "STILL_APPLIES="
  _sa_requests a 0
  _sa_no_records
  e2e_expect_clean_edges
fi

if _want sa-text-not-in-shell; then
  _flow_test_begin "sa-text-not-in-shell"
  _sa_setup sa-text-not-in-shell "W17: commands/address.md has no here-document but the fixed Python script, writes reviewer text with the Write tool, and counts the comments found addressed against the replies, the Thread Status rows and the summary before posting"
  MD="$E2E_PLUGIN_DIR/$ADDRESS_MD"
  e2e_expect_equal "" "$(grep -n "<<'" "$MD" | grep -v "<<'DISPUTED_PY'$")" "here-documents other than the fixed Python script"
  e2e_expect_equal "" "$(grep -nE '(^|[^<])<<-?[A-Za-z_"]' "$MD")" "unquoted or double-quoted here-documents"
  # shellcheck disable=SC2016
  e2e_expect_equal 1 "$(grep -c '^   \*\*Already-addressed count\*\* — when the System One block in Phase 1 printed `S1_STILL_APPLIES=on`, count the comments whose still-applies block printed `STILL_APPLIES=addressed`\. That number must equal each of:.*A mismatch is a P1 holdout finding: do not post' "$MD")" "the holdout step counts the comments found addressed"
  e2e_expect_clean_edges
fi
