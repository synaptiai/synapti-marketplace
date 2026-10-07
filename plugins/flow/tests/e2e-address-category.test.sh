# shellcheck shell=bash
# End-to-end: the System One decision point address.category in /flow:address
# (issue #267). The probe in a `!` fence (S1_ADDRESS_MODES_BLOCK) says whether
# the site is active; the COMMENT_CATEGORY_BLOCK, run once per feedback item
# after the session has chosen a category, asks the shipped question through
# bin/flow-s1.sh and prints the category to use: the higher of the session's
# and the model's, in on mode, ranked P1 > P2 > P3 > Question.
#
# Each scenario runs the shipped blocks of commands/address.md in a scratch
# repository with its own HOME, under zsh and bash, against a stub System One
# server (tests/lib/s1_stub.py). The questions are the shipped
# system-one/questions.yaml. One artifact per scenario goes to
# $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   C1  the model's choice is taken whenever it differs, so a P1 is lowered
#       to P3 or to Question
#   C2  the rank is compared the wrong way round, so nothing is ever raised
#       or everything is lowered
#   C3  shadow mode, or a no-answer reason, prints a different category or a
#       raise line: stdout is read before the exit status is
#   C4  with the site off or no provider, the stub is reached or a record is
#       written
#   C5  a Resolved item is asked about and raised, undoing the still-applies
#       result
#   C6  the threshold is ignored: an answer below it is acted on
#   C7  the item text reaches a shell as code
#   C8  a repository's settings raise the user's mode (on over shadow, or
#       shadow over off), or choose the server
#   C9  a record cannot be matched to its item (no ref) or lacks the
#       session's category
#   C10 the item file, which holds reviewer text, is still there after the
#       block: on an answer, on no answer, or when the block is blocked
#   C11 the plugin loaded from inside the repository hides an install outside
#       it, so the site stays off although the user switched it on; or a
#       flow-s1-mode.sh committed in the repository is run by the probe
#   C12 ITEM_FILE names a file the session did not make (outside TMPDIR, a
#       symlink or a hard link, or a relative path), and the block sends it
#       to the provider or deletes it
#   C13 the client shortened the item to fit the provider's limit, and an
#       answer about part of the item raises it
#   C14 Phase 1 prints no integer id for a review, a finding row or a
#       conversation comment, so the session has no ITEM_ID the block
#       accepts, and the block is blocked and records nothing

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

ADDRESS_MD="commands/address.md"
CC_SHELLS=$(printf '%s\n' $E2E_FENCE_SHELLS | wc -l | tr -d ' ')

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _choice <choice> <P1> <P2> <P3> <Question> — a reply in TypeSafe's shape,
# with no confidence field, so the client computes (4m - 1) / 3 from the
# largest probability m.
_choice() {
  printf '{"body":{"model":"jev-1.13.0","answers":{"category":{"type":"choice","choice":"%s","probabilities":{"P1":%s,"P2":%s,"P3":%s,"Question":%s}}}}}' "$@"
}
# Confidence (4 * 0.97 - 1) / 3 = 0.96, over the provisional 0.8.
P1_SURE=$(_choice P1 0.97 0.01 0.01 0.01)
P2_SURE=$(_choice P2 0.01 0.97 0.01 0.01)
P3_SURE=$(_choice P3 0.01 0.01 0.97 0.01)
# Confidence (4 * 0.5 - 1) / 3 = 0.33, under 0.8.
P1_UNSURE=$(_choice P1 0.5 0.3 0.1 0.1)

_cc_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/cc
}

# _cc_user <mode> <stub> — user settings: provider custom at the stub, and the
# site in <mode> ("" leaves it out).
_cc_user() {
  if [ -n "$1" ]; then
    e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$2")" --arg m "$1" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"address.category":$m}}}')"
  else
    e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$2")" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  fi
}

ITEM='Calling close() twice frees the handle twice.'
CC_PATH=src/io.c
CC_LINE=42
CC_FINDING=""
# CC_ITEM_RAW, when set, is written to the item file as it is, in place of the
# JSON built from ITEM, CC_PATH, CC_LINE and CC_FINDING.
CC_ITEM_RAW=""
CC_ITEM_EMPTY=0
# _cc_item — write the item file the way the session does: a file from mktemp
# in the scenario's TMPDIR, holding the item as JSON. Sets CC_ITEM_FILE.
_cc_item() {
  mkdir -p "$E2E_DIR/tmp"
  CC_ITEM_FILE=$(TMPDIR="$E2E_DIR/tmp" mktemp "$E2E_DIR/tmp/tmp.XXXXXX")
  if [ "$CC_ITEM_EMPTY" = 1 ]; then : > "$CC_ITEM_FILE"
  elif [ -n "$CC_ITEM_RAW" ]; then printf '%s' "$CC_ITEM_RAW" > "$CC_ITEM_FILE"
  else jq -n --arg t "$ITEM" --arg p "$CC_PATH" --arg l "$CC_LINE" --arg f "$CC_FINDING" \
         '{text: $t, path: $p, line: $l, finding: $f}' > "$CC_ITEM_FILE"; fi
}
# _cc_block [NAME=value ...] — write the item file, run the block with
# ITEM_FILE naming it, and check the file is gone afterwards (C10). The block
# removes the file, so it runs under one shell at a time with the file written
# again before each; stdout is compared between the shells here, and E2E_OUT,
# E2E_ERR and E2E_RC are those of the first shell.
_cc_block() {
  local sh first="" first_out="" first_err="" first_rc="" all_shells="$E2E_FENCE_SHELLS"
  for sh in $all_shells; do
    _cc_item
    E2E_FENCE_SHELLS="$sh" e2e_run_block TMPDIR="$E2E_DIR/tmp" ITEM_FILE="$CC_ITEM_FILE" PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$@" "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
    if [ -e "$CC_ITEM_FILE" ]; then _e2e_result fail "the item file is removed under $sh"
    else _e2e_result pass "the item file is removed under $sh"; fi
    if [ -z "$first" ]; then
      first="$sh"; first_out="$E2E_OUT"; first_err="$E2E_ERR"; first_rc="$E2E_RC"
    elif [ "$E2E_OUT" = "$first_out" ]; then
      _e2e_result pass "stdout under $sh matches $first"
    else
      _e2e_result fail "stdout under $sh matches $first"
    fi
  done
  E2E_OUT="$first_out"; E2E_ERR="$first_err"; E2E_RC="$first_rc"
}
_cc_probe() { e2e_run_block "$ADDRESS_MD" S1_ADDRESS_MODES_BLOCK; }
_cc_requests() { e2e_expect_equal "$(( $2 * CC_SHELLS ))" "$(e2e_stub_requests "$1")" "requests stub $1 received ($2 per shell)"; }
_cc_records() { printf '%s' "$E2E_HOME/.claude/flow-state/system-one.jsonl"; }
_cc_first_record() { head -n 1 "$(_cc_records)" 2>/dev/null | jq -r "$1" 2>/dev/null; }

OFF_OUT=""
if _want cc-off-default; then
  _flow_test_begin "cc-off-default"
  _cc_setup cc-off-default "C4: a provider is set and the site is not named, so it is off: the session's category, nothing sent, nothing recorded"
  e2e_stub_start a "$P1_SURE"
  _cc_user "" a
  _cc_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "CATEGORY=P3" "$E2E_OUT" "stdout"
  OFF_OUT="$E2E_OUT"
  _cc_requests a 0
  e2e_expect_equal "no" "$([ -e "$(_cc_records)" ] && echo yes || echo no)" "a record exists"
  e2e_expect_clean_edges
fi
[ -n "$OFF_OUT" ] || OFF_OUT="CATEGORY=P3"

if _want cc-provider-none; then
  _flow_test_begin "cc-provider-none"
  _cc_setup cc-provider-none "C4: no user settings at all: the session's category, byte for byte as with the site off"
  e2e_stub_start a "$P1_SURE"
  _cc_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  _cc_requests a 0
  e2e_expect_clean_edges
fi

if _want cc-on-raises; then
  _flow_test_begin "cc-on-raises"
  _cc_setup cc-on-raises "C2, C9: on, session P3, the model says P1 at confidence 0.96: handled as P1, raised from P3, and the record holds both and the item reference"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  _cc_probe
  e2e_expect_equal "S1_CATEGORY=on" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "CATEGORY=P1
CATEGORY_RAISED_FROM=P3" "$E2E_OUT" "stdout"
  _cc_requests a 1
  e2e_expect_equal "on answered P3 P1 pr:7/inline:101 address.category category" \
    "$(_cc_first_record '"\(.mode) \(.result) \(.current) \(.answer.choice) \(.ref) \(.site) \(.question)"')" "record"
  e2e_expect_equal "$ITEM|src/io.c|42" "$(head -n 1 "$(e2e_stub_log a)" | jq -r '.body.state.comment | "\(.text)|\(.path)|\(.line)"')" "state sent"
  e2e_expect_clean_edges
fi

if _want cc-on-never-lowers; then
  _flow_test_begin "cc-on-never-lowers"
  _cc_setup cc-on-never-lowers "C1: on, session P1, the model says P3 at confidence 0.96: stays P1, no raise line, and the answer is recorded"
  e2e_stub_start a "$P3_SURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=P1
  e2e_expect_equal "CATEGORY=P1" "$E2E_OUT" "stdout"
  _cc_requests a 1
  e2e_expect_equal "answered P3" "$(_cc_first_record '"\(.result) \(.answer.choice)"')" "record"
  e2e_expect_clean_edges
fi

if _want cc-on-question-raised; then
  _flow_test_begin "cc-on-question-raised"
  _cc_setup cc-on-question-raised "C2: on, session Question, the model says P2: Question ranks below P3, so the item becomes a fix"
  e2e_stub_start a "$P2_SURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=Question
  e2e_expect_equal "CATEGORY=P2
CATEGORY_RAISED_FROM=Question" "$E2E_OUT" "stdout"
  e2e_expect_clean_edges
fi

if _want cc-on-equal; then
  _flow_test_begin "cc-on-equal"
  _cc_setup cc-on-equal "on, the model agrees with the session (P2): no raise line"
  e2e_stub_start a "$P2_SURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=P2
  e2e_expect_equal "CATEGORY=P2" "$E2E_OUT" "stdout"
  e2e_expect_clean_edges
fi

if _want cc-on-below-threshold; then
  _flow_test_begin "cc-on-below-threshold"
  _cc_setup cc-on-below-threshold "C6: on, the model says P1 at confidence 0.33: the session's category, the reason on stderr, the answer recorded"
  e2e_stub_start a "$P1_UNSURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  e2e_expect_err "flow-s1: no answer: below-threshold"
  e2e_expect_equal "below-threshold P1" "$(_cc_first_record '"\(.result) \(.answer.choice)"')" "record"
  e2e_expect_clean_edges
fi

if _want cc-shadow; then
  _flow_test_begin "cc-shadow"
  _cc_setup cc-shadow "C3, C9: shadow with the model at P1 over a session P3: stdout byte for byte as off, the record holds both"
  e2e_stub_start a "$P1_SURE"
  _cc_user shadow a
  _cc_probe
  e2e_expect_equal "S1_CATEGORY=shadow" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  e2e_expect_err "flow-s1: no answer: shadow"
  _cc_requests a 1
  e2e_expect_equal "shadow answered P3 P1 pr:7/inline:101" "$(_cc_first_record '"\(.mode) \(.result) \(.current) \(.answer.choice) \(.ref)"')" "record"
  e2e_expect_clean_edges
fi

if _want cc-no-answer; then
  _flow_test_begin "cc-no-answer"
  _cc_setup cc-no-answer "C3: an HTTP 500, a reply slower than timeoutMs, and a choice outside the options each give stdout byte for byte as off, with the reason on stderr"
  e2e_stub_start a '{"status":500,"body":{"detail":"boom"}}'
  e2e_stub_start b "{\"delay_ms\":1500,${P1_SURE#\{}"
  e2e_stub_start c "$(_choice P0 0.97 0.01 0.01 0.01)"
  _cc_user on a
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout after http-500"
  e2e_expect_err "flow-s1: no answer: http-500"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:200,uses:{"address.category":"on"}}}')"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout after a timeout"
  e2e_expect_err "flow-s1: no answer: timeout"
  _cc_user on c
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout after a malformed reply"
  e2e_expect_err "flow-s1: no answer: malformed"
  _cc_requests c 1
  e2e_expect_clean_edges
fi

if _want cc-resolved-not-asked; then
  _flow_test_begin "cc-resolved-not-asked"
  _cc_setup cc-resolved-not-asked "C5: on, a Resolved item, the model would say P1: Resolved, and nothing is sent"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=Resolved
  e2e_expect_equal "CATEGORY=Resolved" "$E2E_OUT" "stdout"
  _cc_requests a 0
  e2e_expect_clean_edges
fi

if _want cc-invalid-input; then
  _flow_test_begin "cc-invalid-input"
  _cc_setup cc-invalid-input "C10: a category outside the set, an empty item file, an item file that is not JSON or holds two JSON values, no item file, item text passed in the environment, an item kind or id that is not one, a line that is not a number, a finding id outside the ledger's shape, and a run id flow-s1.sh refuses: blocked, exit 1, nothing sent, never a guessed category, and the item file removed"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=P4
  e2e_expect_equal 1 "$E2E_RC" "exit status for P4"
  e2e_expect_line "STATE=blocked"
  e2e_expect_no_out "CATEGORY="
  CC_ITEM_EMPTY=1
  _cc_block SESSION_CATEGORY=P3
  CC_ITEM_EMPTY=0
  e2e_expect_equal 1 "$E2E_RC" "exit status for an empty item file"
  e2e_expect_line "STATE=blocked"
  CC_ITEM_RAW="$ITEM"
  _cc_block SESSION_CATEGORY=P3
  CC_ITEM_RAW=""
  e2e_expect_equal 1 "$E2E_RC" "exit status for an item file holding plain text"
  e2e_expect_line "STATE=blocked"
  # Two JSON values, the last a valid item: jq -e alone takes its exit status
  # from the last value, so the file would pass.
  CC_ITEM_RAW='"x" {"text":"a"}'
  _cc_block SESSION_CATEGORY=P3
  CC_ITEM_RAW=""
  e2e_expect_equal 1 "$E2E_RC" "exit status for an item file holding two JSON values"
  e2e_expect_line "STATE=blocked"
  e2e_expect_line "ERROR=ITEM_FILE must hold one JSON object with a non-empty text, and a path, a line of digits and a finding id when given"
  e2e_run_block SESSION_CATEGORY=P3 TMPDIR="$E2E_DIR/tmp" ITEM_FILE="$E2E_DIR/tmp/no-such-item" PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for no item file"
  e2e_expect_line "STATE=blocked"
  e2e_run_block SESSION_CATEGORY=P3 ITEM_TEXT=x PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for item text in the environment and no item file"
  e2e_expect_line "STATE=blocked"
  _cc_block SESSION_CATEGORY=P3 ITEM_KIND=
  e2e_expect_equal 1 "$E2E_RC" "exit status for a missing item kind"
  _cc_block SESSION_CATEGORY=P3 ITEM_KIND=thread
  e2e_expect_equal 1 "$E2E_RC" "exit status for an item kind outside the set"
  _cc_block SESSION_CATEGORY=P3 ITEM_ID=10x
  e2e_expect_equal 1 "$E2E_RC" "exit status for an item id that is not a number"
  _cc_block SESSION_CATEGORY=P3 PR_NUM=07
  e2e_expect_equal 1 "$E2E_RC" "exit status for a pull request number with a leading zero"
  CC_LINE=4x
  _cc_block SESSION_CATEGORY=P3
  CC_LINE=42
  e2e_expect_equal 1 "$E2E_RC" "exit status for a line that is not a number"
  CC_FINDING='F1;x'
  _cc_block SESSION_CATEGORY=P3 ITEM_KIND=review ITEM_ID=55
  CC_FINDING=""
  e2e_expect_equal 1 "$E2E_RC" "exit status for a finding id outside the ledger's shape"
  _cc_block SESSION_CATEGORY=P3 RUN_ID=../R1
  e2e_expect_equal 1 "$E2E_RC" "exit status for a run id with .."
  e2e_expect_line "STATE=blocked"
  e2e_expect_err "--run-id contains"
  _cc_requests a 0
  e2e_expect_clean_edges
fi

if _want cc-item-file-outside-tmp; then
  _flow_test_begin "cc-item-file-outside-tmp"
  _cc_setup cc-item-file-outside-tmp "C12: ITEM_FILE names a file the session did not make with mktemp: one outside TMPDIR, a symlink or a hard link in TMPDIR to a file outside it, and a relative path that names a file in TMPDIR: blocked, exit 1, nothing sent, and the file and the symlink's target left as they were"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  mkdir -p "$E2E_DIR/tmp" "$E2E_DIR/secret"
  jq -n '{text: "private key"}' > "$E2E_DIR/secret/key.json"
  CC_SECRET_SUM=$(_e2e_sha256 "$E2E_DIR/secret/key.json")
  e2e_run_block SESSION_CATEGORY=P3 TMPDIR="$E2E_DIR/tmp" ITEM_FILE="$E2E_DIR/secret/key.json" PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for a file outside TMPDIR"
  e2e_expect_line "STATE=blocked"
  ln -s "$E2E_DIR/secret/key.json" "$E2E_DIR/tmp/tmp.link"
  e2e_run_block SESSION_CATEGORY=P3 TMPDIR="$E2E_DIR/tmp" ITEM_FILE="$E2E_DIR/tmp/tmp.link" PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for a symlink in TMPDIR"
  e2e_expect_line "STATE=blocked"
  e2e_expect_equal "yes" "$([ -L "$E2E_DIR/tmp/tmp.link" ] && echo yes || echo no)" "the symlink is still there"
  # A hard link in TMPDIR to the file outside it: a regular file, not a
  # symlink, in TMPDIR, so only the one-link rule refuses it.
  ln "$E2E_DIR/secret/key.json" "$E2E_DIR/tmp/tmp.hard"
  e2e_run_block SESSION_CATEGORY=P3 TMPDIR="$E2E_DIR/tmp" ITEM_FILE="$E2E_DIR/tmp/tmp.hard" PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for a hard link in TMPDIR"
  e2e_expect_line "STATE=blocked"
  e2e_expect_line "ERROR=ITEM_FILE must be a file made by mktemp directly in \$TMPDIR; it was not read"
  e2e_expect_equal "yes" "$([ -f "$E2E_DIR/tmp/tmp.hard" ] && echo yes || echo no)" "the hard link is still there"
  # A relative path that names a file in TMPDIR from the repository, where
  # the block runs: only the rule that the path is absolute refuses it.
  jq -n '{text: "relative"}' > "$E2E_DIR/tmp/tmp.rel"
  if [ "$E2E_DIR/repo/../tmp/tmp.rel" -ef "$E2E_DIR/tmp/tmp.rel" ] && [ "$E2E_REPO" = "$E2E_DIR/repo" ]; then
    _e2e_result pass "../tmp/tmp.rel from the repository names the file in TMPDIR"
  else
    _e2e_result fail "../tmp/tmp.rel from the repository names the file in TMPDIR"
  fi
  e2e_run_block SESSION_CATEGORY=P3 TMPDIR="$E2E_DIR/tmp" ITEM_FILE="../tmp/tmp.rel" PR_NUM=7 ITEM_KIND=inline ITEM_ID=101 "$ADDRESS_MD" COMMENT_CATEGORY_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "exit status for a relative path"
  e2e_expect_line "STATE=blocked"
  e2e_expect_line "ERROR=ITEM_FILE must be a file made by mktemp directly in \$TMPDIR; it was not read"
  e2e_expect_equal "yes" "$([ -f "$E2E_DIR/tmp/tmp.rel" ] && echo yes || echo no)" "the file named by the relative path is still there"
  e2e_expect_equal "$CC_SECRET_SUM" "$(_e2e_sha256 "$E2E_DIR/secret/key.json" 2>/dev/null)" "the file outside TMPDIR is unchanged"
  _cc_requests a 0
  e2e_expect_clean_edges
fi

if _want cc-repo-cannot-choose; then
  _flow_test_begin "cc-repo-cannot-choose"
  _cc_setup cc-repo-cannot-choose "C8: the user chose shadow; the repository sets the site on and its own baseUrl: the user's server gets the request, the repository's none, the mode stays shadow and nothing is raised"
  e2e_stub_start a "$P1_SURE"
  e2e_stub_start b "$P1_SURE"
  _cc_user shadow a
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"address.category":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _cc_probe
  e2e_expect_equal "S1_CATEGORY=shadow" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  _cc_requests a 1
  _cc_requests b 0
  e2e_expect_equal "shadow" "$(_cc_first_record '.mode')" "record mode"
  e2e_expect_clean_edges
fi

if _want cc-repo-cannot-switch-on; then
  _flow_test_begin "cc-repo-cannot-switch-on"
  _cc_setup cc-repo-cannot-switch-on "C8: the user has a provider and leaves the site unset, and the repository sets it on: the probe prints nothing, the session's category is printed, nothing is sent or recorded"
  e2e_stub_start a "$P1_SURE"
  _cc_user "" a
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"address.category":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _cc_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  _cc_requests a 0
  e2e_expect_equal "no" "$([ -e "$(_cc_records)" ] && echo yes || echo no)" "a record exists"
  e2e_expect_clean_edges
fi

if _want cc-repo-shadow-cannot-start; then
  _flow_test_begin "cc-repo-shadow-cannot-start"
  _cc_setup cc-repo-shadow-cannot-start "C8: the repository sets the site to shadow, which would send the item to the user's provider: with the site unset or off for the user the probe prints nothing, the session's category is printed, nothing is sent or recorded; and a repository's off lowers the user's on"
  e2e_stub_start a "$P1_SURE"
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"address.category":"shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _cc_user "" a
  _cc_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, site unset for the user"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout with the site unset, against the off scenario"
  _cc_user off a
  _cc_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, site off for the user"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout with the site off, against the off scenario"
  printf '%s\n' '{"systemOne":{"uses":{"address.category":"off"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _cc_user on a
  _cc_probe
  e2e_expect_equal "" "$E2E_OUT" "probe stdout, user on and repository off"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout with the user on and the repository off, against the off scenario"
  _cc_requests a 0
  e2e_expect_equal "no" "$([ -e "$(_cc_records)" ] && echo yes || echo no)" "a record exists"
  e2e_expect_clean_edges
fi

if _want cc-inside-repo-installed-outside; then
  _flow_test_begin "cc-inside-repo-installed-outside"
  _cc_setup cc-inside-repo-installed-outside "C11: the plugin is loaded from a copy inside the repository and flow is also installed outside it: the probe and the block skip the copy inside and use the install outside, so the site the user switched on prints its mode and the item is raised from P3 to P1"
  mkdir -p "$E2E_HOME/.claude/plugins/cache/synapti-marketplace/flow"
  cp -R "$E2E_PLUGIN_DIR" "$E2E_HOME/.claude/plugins/cache/synapti-marketplace/flow/$(jq -r .version "$E2E_PLUGIN_DIR/.claude-plugin/plugin.json")"
  cp -R "$E2E_ACTIVE_PLUGIN" "$E2E_REPO/plugin-copy"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugin-copy"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  _cc_probe
  e2e_expect_equal "S1_CATEGORY=on" "$E2E_OUT" "probe stdout"
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "CATEGORY=P1
CATEGORY_RAISED_FROM=P3" "$E2E_OUT" "stdout"
  _cc_requests a 1
  e2e_expect_equal "on answered pr:7/inline:101" "$(_cc_first_record '"\(.mode) \(.result) \(.ref)"')" "record in the user's state"
  e2e_expect_equal "" "$(find "$E2E_REPO" -name system-one.jsonl 2>/dev/null)" "records inside the repository"
  e2e_expect_clean_edges
fi

if _want cc-repo-helper-not-run; then
  _flow_test_begin "cc-repo-helper-not-run"
  _cc_setup cc-repo-helper-not-run "C11: the repository commits its own plugins/flow/bin/flow-s1-mode.sh, which prints on, and nothing is installed: with no plugin root set, the probe never runs that script and prints nothing, and the block keeps the session's category"
  mkdir -p "$E2E_REPO/plugins/flow/bin"
  printf '#!/bin/sh\n: > "%s"\necho on\n' "$E2E_DIR/repo-helper-ran" > "$E2E_REPO/plugins/flow/bin/flow-s1-mode.sh"
  printf '#!/bin/sh\n: > "%s"\n' "$E2E_DIR/repo-helper-ran" > "$E2E_REPO/plugins/flow/bin/cascade-resolve.sh"
  printf '#!/bin/sh\n: > "%s"\n' "$E2E_DIR/repo-helper-ran" > "$E2E_REPO/plugins/flow/bin/flow-s1.sh"
  chmod +x "$E2E_REPO"/plugins/flow/bin/*.sh
  ( _e2e_git_env; cd "$E2E_REPO" && git add plugins && git commit -q -m "add a plugin copy" ) \
    || _flow_assert_fail "cc-repo-helper-not-run: could not commit the fixture"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  e2e_run_block CLAUDE_PLUGIN_ROOT= "$ADDRESS_MD" S1_ADDRESS_MODES_BLOCK
  e2e_expect_equal "" "$E2E_OUT" "probe stdout"
  e2e_expect_equal "no" "$([ -e "$E2E_DIR/repo-helper-ran" ] && echo yes || echo no)" "a script inside the repository ran, after the probe"
  _cc_block SESSION_CATEGORY=P3 CLAUDE_PLUGIN_ROOT=
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  e2e_expect_equal "no" "$([ -e "$E2E_DIR/repo-helper-ran" ] && echo yes || echo no)" "a script inside the repository ran, after the block"
  _cc_requests a 0
  e2e_expect_equal "no" "$([ -e "$(_cc_records)" ] && echo yes || echo no)" "a record exists"
  e2e_expect_clean_edges
fi

if _want cc-text-is-data; then
  _flow_test_begin "cc-text-is-data"
  _cc_setup cc-text-is-data "C7: item text holding \$(touch pwned), backticks, both quotes, a newline and a final newline, and a path holding \$(touch PWNED) and a single quote, are data: no file is created and the stub receives text and path verbatim"
  e2e_stub_start a "$P1_SURE"
  _cc_user on a
  ITEM=$(printf 'Run $(touch pwned) and `touch pwned2`; say "hi" it'"'"'s\nnext line\nx')
  ITEM="${ITEM%x}"
  CC_PATH='src/$(touch PWNED)'"'"'q.py'
  _cc_block SESSION_CATEGORY=P2
  e2e_expect_line "CATEGORY=P1"
  e2e_expect_equal "true" "$(head -n 1 "$(e2e_stub_log a)" | jq -r --arg t "$ITEM" '.body.state.comment.text == $t')" "text received verbatim, the final newline kept"
  e2e_expect_equal "true" "$(head -n 1 "$(e2e_stub_log a)" | jq -r --arg p "$CC_PATH" '.body.state.comment.path == $p')" "path received verbatim"
  e2e_expect_equal "42" "$(head -n 1 "$(e2e_stub_log a)" | jq -r '.body.state.comment.line')" "line received"
  if [ -n "$(find "$E2E_DIR" "$E2E_REPO" -name 'pwned*' -o -name 'PWNED*' 2>/dev/null)" ]; then _e2e_result fail "no pwned file was created"
  else _e2e_result pass "no pwned file was created"; fi
  ITEM='Calling close() twice frees the handle twice.'
  CC_PATH=src/io.c
  e2e_expect_clean_edges
fi

if _want cc-review-finding-ref; then
  _flow_test_begin "cc-review-finding-ref"
  _cc_setup cc-review-finding-ref "C9, C14: the ids come from the Phase 1 output, as the session takes them: the REST id on the REVIEW= row, the review= on the FINDING= row and the id on the CONVERSATION_COMMENT= row each reach the category block, and the record's ref is built from them (with the finding id read from the item file for a finding row)"
  e2e_stub_start a "$P3_SURE"
  _cc_user shadow a
  e2e_gh_fixture reviews-7 '[{"id":4123,"user":{"login":"rev"},"author_association":"OWNER","state":"COMMENTED","submitted_at":"2026-10-01T09:00:00Z","body":"Findings\n\n<!-- FLOW_REVIEW_CYCLE:2 FINDINGS:[SEC-2|P1|security|src/io.c:42|open|HIGH|consensus] -->"}]'
  e2e_gh_fixture comments-7 '[{"id":9876,"user":{"login":"rev"},"created_at":"2026-10-01T10:00:00Z","body":"Why is close() called twice here?"}]'
  e2e_run_block REPO=o/r PR_NUM=7 "$ADDRESS_MD" REVIEW_SUMMARIES_BLOCK
  CC_REVIEW_ID=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^REVIEW=id=\([^ ]*\) .*/\1/p')
  e2e_expect_equal 4123 "$CC_REVIEW_ID" "the review's REST id, from its REVIEW= row"
  e2e_run_block REPO=o/r PR_NUM=7 "$ADDRESS_MD" REVIEW_CYCLE_FINDINGS_BLOCK
  e2e_expect_line "STATE=ok"
  CC_FINDING_REVIEW_ID=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^FINDING=cycle=2 SEC-2|.* review=\([^ ]*\)$/\1/p')
  e2e_expect_equal 4123 "$CC_FINDING_REVIEW_ID" "the id of the review that supplied the finding, from its FINDING= row"
  e2e_run_block REPO=o/r PR_NUM=7 "$ADDRESS_MD" CONVERSATION_COMMENTS_BLOCK
  CC_COMMENT_ID=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^CONVERSATION_COMMENT=id=\([^ ]*\) .*/\1/p')
  e2e_expect_equal 9876 "$CC_COMMENT_ID" "the comment's id, from its CONVERSATION_COMMENT= row"
  CC_FINDING=SEC-2
  _cc_block SESSION_CATEGORY=P3 ITEM_KIND=review ITEM_ID="$CC_FINDING_REVIEW_ID"
  CC_FINDING=""
  e2e_expect_equal "CATEGORY=P3" "$E2E_OUT" "stdout for the finding row"
  e2e_expect_equal "pr:7/review:4123/SEC-2" "$(_cc_first_record '.ref')" "record ref for a finding row"
  _cc_block SESSION_CATEGORY=P3 ITEM_KIND=review ITEM_ID="$CC_REVIEW_ID"
  e2e_expect_equal "pr:7/review:4123" "$(tail -n 1 "$(_cc_records)" | jq -r '.ref')" "record ref for a review summary"
  _cc_block SESSION_CATEGORY=P3 ITEM_KIND=comment ITEM_ID="$CC_COMMENT_ID"
  e2e_expect_equal "pr:7/comment:9876" "$(tail -n 1 "$(_cc_records)" | jq -r '.ref')" "record ref for a conversation comment"
  e2e_expect_clean_edges
fi

if _want cc-on-adjacent-ranks; then
  _flow_test_begin "cc-on-adjacent-ranks"
  _cc_setup cc-on-adjacent-ranks "C1, C2: on, each pair of adjacent ranks: session P2 with the model at P1 is raised to P1; session P1 with the model at P2 stays P1; session Question with the model at P3 is raised to P3; session Question with the model at Question is not raised"
  e2e_stub_start a "$P1_SURE"
  e2e_stub_start b "$P2_SURE"
  e2e_stub_start c "$P3_SURE"
  _cc_user on a
  _cc_block SESSION_CATEGORY=P2
  e2e_expect_equal "CATEGORY=P1
CATEGORY_RAISED_FROM=P2" "$E2E_OUT" "stdout, session P2 and model P1"
  _cc_user on b
  _cc_block SESSION_CATEGORY=P1
  e2e_expect_equal "CATEGORY=P1" "$E2E_OUT" "stdout, session P1 and model P2"
  _cc_user on c
  _cc_block SESSION_CATEGORY=Question
  e2e_expect_equal "CATEGORY=P3
CATEGORY_RAISED_FROM=Question" "$E2E_OUT" "stdout, session Question and model P3"
  e2e_stub_start d "$(_choice Question 0.01 0.01 0.01 0.97)"
  _cc_user on d
  _cc_block SESSION_CATEGORY=Question
  e2e_expect_equal "CATEGORY=Question" "$E2E_OUT" "stdout, session Question and model Question"
  _cc_requests a 1
  _cc_requests b 1
  _cc_requests c 1
  _cc_requests d 1
  e2e_expect_clean_edges
fi

if _want cc-no-answer-with-stdout; then
  _flow_test_begin "cc-no-answer-with-stdout"
  _cc_setup cc-no-answer-with-stdout "C3: a client that prints a confident P1 answer on stdout and exits 3: the exit status decides, so the session's category is printed and nothing is raised"
  e2e_plugin_copy bin/flow-s1.sh '#!/usr/bin/env bash
printf "%s\n" "{\"site\":\"address.category\",\"provider\":\"custom\",\"model\":\"jev-1.13.0\",\"truncated\":false,\"answers\":{\"category\":{\"choice\":\"P1\",\"confidence\":0.96}}}"
printf "%s\n" "flow-s1: no answer: shadow" >&2
exit 3'
  _cc_block SESSION_CATEGORY=P3
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_clean_edges
fi

if _want cc-truncated; then
  _flow_test_begin "cc-truncated"
  _cc_setup cc-truncated "C13: on, the item is longer than the user's stateTokenCap, so the client shortens it, and the model says P1 confidently: the answer is not about the whole item, so the session's category is printed with a warning"
  e2e_stub_start a "$P1_SURE"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:40,uses:{"address.category":"on"}}}')"
  ITEM=$(printf 'word %.0s' $(seq 1 200))
  _cc_block SESSION_CATEGORY=P3
  ITEM='Calling close() twice frees the handle twice.'
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "stdout, against the off scenario"
  e2e_expect_err "shortened to fit"
  _cc_requests a 1
  e2e_expect_equal "true" "$(head -n 1 "$(e2e_stub_log a)" | jq -r '(.body.state.comment.text | length) < 1000')" "the state sent was shortened"
  e2e_expect_clean_edges
fi

if _want cc-run-id-records; then
  _flow_test_begin "cc-run-id-records"
  _cc_setup cc-run-id-records "C9: with the run directory present the record goes beside the run; the per-user file gets nothing"
  e2e_stub_start a "$P1_SURE"
  _cc_user shadow a
  mkdir -p "$E2E_REPO/.flow/runs/R1"
  _cc_block SESSION_CATEGORY=P3 RUN_ID=R1
  e2e_expect_equal "shadow P3" "$(head -n 1 "$E2E_REPO/.flow/runs/R1/system-one.jsonl" 2>/dev/null | jq -r '"\(.mode) \(.current)"')" "record beside the run"
  e2e_expect_equal "no" "$([ -e "$(_cc_records)" ] && echo yes || echo no)" "a per-user record exists"
  e2e_expect_clean_edges
fi
