# shellcheck shell=bash disable=SC2034  # E2E_ACTIVE_PLUGIN is read by lib/e2e.sh
# End-to-end: the System One decision points guard.command-intent and
# guard.planted-instructions.
#
# guard.command-intent: a PreToolUse Bash hook (hooks/scripts/s1-command-intent.sh)
# asks whether a command could destroy data that is hard to recover, next to
# the pattern checks. Claude Code runs every matching PreToolUse hook in
# parallel, and deny > defer > ask > allow decides between them; exit 2 counts
# as deny (https://code.claude.com/docs/en/hooks, read 2026-10-12). So the
# hook can never let through what a pattern check refuses as long as it never
# prints allow, defer or deny, and in on mode it can at most ask.
#
# guard.planted-instructions: a PostToolUse Bash hook (hooks/scripts/s1-screen-text.sh)
# asks, after a gh command read issue or pull request text, whether that text
# holds instructions addressed to the agent, and in on mode adds a note that
# the output is data.
#
# Each scenario runs the shipped hooks in a scratch repository with its own
# HOME, against the shipped system-one/questions.yaml (so the shipped
# thresholds are what is tested) and a stub server (tests/lib/s1_stub.py) that
# logs every request. One artifact per scenario goes to
# $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   G1  the hook prints allow (or defer, or deny) on a harmless answer, or
#       exits 2, so the model changes what the pattern checks decided
#   G2  the cheap rule-out drops a command because its program is listed,
#       although an option or a redirection makes it write (find -delete,
#       sed -i, echo > file, git branch -D, gh api -X DELETE)
#   G3  the rule-out keeps commands it should drop: `2>&1` or `&>` read as a
#       second command, so nearly every command is sent
#   G4  ask or mark on a "harmless" or "plain" answer (p < 0.5), or on
#       confidence alone
#   G5  the value of an assignment (`TOKEN=x make`) is sent, or a command
#       the secrets check flags is sent at all
#   G6  current is read from the destructive check only, so a force push the
#       force-push check refuses is recorded as allowed
#   G7  shadow mode makes the command wait for the provider, or leaves the
#       state file behind
#   G8  a gh write (gh pr merge, gh api -X POST) or a read of something other
#       than issue or pull request text is screened, or a comment read is not
#   G9  a timeout, an HTTP error, a broken python3, a payload that is not
#       JSON, or a site that is off prints anything or sends anything
#   G10 the state's output is one string, or is not cut, so a long read is
#       sent whole
#   G11 hooks.json does not run the hooks on the events the design names, or
#       without a timeout, so a slow provider holds a Bash call for 600 s

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

INTENT="hooks/scripts/s1-command-intent.sh"
SCREEN="hooks/scripts/s1-screen-text.sh"
SITE_I="guard.command-intent"
SITE_T="guard.planted-instructions"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Replies in TypeSafe's noul shape for each site's one question.
_ri() { printf '{"model":"jev-1.13.0","answers":{"destructive":{"type":"noul","noul":%s}}}' "$1"; }
_rt() { printf '{"model":"jev-1.13.0","answers":{"planted":{"type":"noul","noul":%s}}}' "$1"; }

_g_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/g
  G_RECORDS="$E2E_HOME/.claude/flow-state/system-one.jsonl"
  G_TMP="$E2E_DIR/tmp"
  mkdir -p "$G_TMP"
}

# _g_settings <mode of command-intent> <mode of planted-instructions> [stub] [extra systemOne json]
_g_settings() {
  local url="" extra="${4:-}"
  [ -n "${3:-}" ] && url=$(e2e_stub_url "$3")
  [ -n "$extra" ] || extra='{}'
  e2e_user_settings "$(jq -nc --arg u "$url" --arg i "$1" --arg t "$2" --arg si "$SITE_I" --arg st "$SITE_T" --argjson x "$extra" \
    '{systemOne: ({provider: "custom", baseUrl: $u, uses: {($si): $i, ($st): $t}} + $x)}')"
}

# _g_pre <command> [tool_use_id] — a PreToolUse Bash payload.
_g_pre() {
  jq -nc --arg cwd "$E2E_REPO" --arg cmd "$1" --arg id "${2:-toolu_01g}" '
    {session_id: "sess-g", cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash",
     tool_use_id: $id, tool_input: {command: $cmd}}'
}
# _g_post <command> <stdout> [event] [tool_use_id] — a PostToolUse Bash payload.
_g_post() {
  jq -nc --arg cwd "$E2E_REPO" --arg cmd "$1" --arg out "$2" --arg ev "${3:-PostToolUse}" --arg id "${4:-toolu_01t}" '
    {session_id: "sess-g", cwd: $cwd, hook_event_name: $ev, tool_name: "Bash", tool_use_id: $id,
     tool_input: {command: $cmd}}
    + (if $ev == "PostToolUseFailure" then {error: ("Exit code 1\n" + $out)}
       else {tool_response: {stdout: $out, stderr: "", interrupted: false, isImage: false, noOutputExpected: false}} end)'
}

_g_intent() { e2e_run_hook "TMPDIR=$G_TMP" "$INTENT" "$(_g_pre "$@")"; }
_g_screen() { e2e_run_hook "TMPDIR=$G_TMP" "$SCREEN" "$(_g_post "$@")"; }
_g_requests() { local _E2E_EXTRA_FRAMES=1; e2e_expect_equal "$2" "$(e2e_stub_requests "$1")" "requests received by stub $1"; }

# _g_sent <stub> <expected 0|1> <hook function> <args...> — run the hook once
# and check how many requests it added.
_g_sent() {
  local stub="$1" want="$2" before after; shift 2
  before=$(e2e_stub_requests "$stub")
  "$@"
  after=$(e2e_stub_requests "$stub")
  local _E2E_EXTRA_FRAMES=1
  e2e_expect_equal "$want" "$((after - before))" "requests sent for: $2"
}

# _g_wait_for <tenths> <command ...> — run the command every 0.1 s until it
# succeeds or <tenths> tries have been made.
_g_wait_for() {
  local n="$1" i=0; shift
  until "$@" || [ "$i" -ge "$n" ]; do sleep 0.1; i=$((i + 1)); done
}
_g_has_records() { [ -s "$G_RECORDS" ] && [ "$(wc -l < "$G_RECORDS")" -ge "$1" ]; }
_g_last_record() { tail -n 1 "$G_RECORDS" 2>/dev/null; }
_g_now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# Every decision a hook prints, checked in every scenario that runs one: never
# allow, defer or deny, and exit 0.
_g_no_decision() {
  local _E2E_EXTRA_FRAMES=1
  e2e_expect_equal "0" "$E2E_RC" "hook exit status"
  e2e_expect_equal "false" "$(printf '%s' "$E2E_OUT" | grep -qE '"(allow|defer|deny)"' && echo true || echo false)" "stdout names no allow, defer or deny"
}

# ------------------------------------------------------------- the sites

if _want g-shipped-off; then
  _flow_test_begin "g-shipped-off"
  _g_setup g-shipped-off "a provider is configured and no uses entry names the guard sites: both are off, so neither hook sends anything, and the plugin settings ship both off"
  e2e_stub_start a "{\"body\":$(_ri 0.99)}"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne: {provider: "custom", baseUrl: $u}}')"
  e2e_run_bin bin/flow-s1-mode.sh "$SITE_I"
  e2e_expect_equal "" "$E2E_OUT" "mode of $SITE_I"
  e2e_run_bin bin/flow-s1-mode.sh "$SITE_T"
  e2e_expect_equal "" "$E2E_OUT" "mode of $SITE_T"
  _g_intent "make deploy"
  e2e_expect_equal "" "$E2E_OUT" "intent hook stdout"
  _g_screen "gh issue view 5" "title: x"
  e2e_expect_equal "" "$E2E_OUT" "screen hook stdout"
  _g_requests a 0
  e2e_expect_equal "off off" "$(jq -r --arg a "$SITE_I" --arg b "$SITE_T" '"\(.systemOne.uses[$a]) \(.systemOne.uses[$b])"' "$E2E_ACTIVE_PLUGIN/settings.json")" "the plugin settings"
fi

if _want g-questions-valid; then
  _flow_test_begin "g-questions-valid"
  _g_setup g-questions-valid "the shipped questions file has one noul question per site, destructive and planted, and the client asks them"
  e2e_stub_start a "{\"body\":$(_ri 0.9)}"
  e2e_stub_start b "{\"body\":$(_rt 0.9)}"
  printf '{"command":"make deploy"}' > "$E2E_DIR/state.json"
  _g_settings on on a
  e2e_run_bin bin/flow-s1.sh ask --site "$SITE_I" --state-file "$E2E_DIR/state.json" --state-format json --current allow
  e2e_expect_equal "0" "$E2E_RC" "client exit for $SITE_I"
  e2e_expect_equal "noul" "$(jq -r '.body.questions.destructive.type' "$(e2e_stub_log a)")" "question destructive is a noul"
  _g_settings on on b
  e2e_run_bin bin/flow-s1.sh ask --site "$SITE_T" --state-file "$E2E_DIR/state.json" --state-format json --current unmarked
  e2e_expect_equal "0" "$E2E_RC" "client exit for $SITE_T"
  e2e_expect_equal "noul" "$(jq -r '.body.questions.planted.type' "$(e2e_stub_log b)")" "question planted is a noul"
fi

# ----------------------------------------------------- the cheap rule-out
# On mode with a stub that answers p=0.5 (confidence 0, below every
# threshold), so the hook waits for the client and prints nothing: the
# request count is final when the hook returns.

if _want g-ruleout-find; then
  _flow_test_begin "g-ruleout-find"
  _g_setup g-ruleout-find "find is read-only without -delete or -exec; with them it is sent (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 1 _g_intent "find . -name x -delete"
  _g_sent a 0 _g_intent "find . -name x"
  _g_sent a 1 _g_intent "find . -name '*.tmp' -exec rm {} +"
  _g_sent a 0 _g_intent "find . -type f | wc -l"
fi

if _want g-ruleout-redirect; then
  _flow_test_begin "g-ruleout-redirect"
  _g_setup g-ruleout-redirect "a redirection into a file is sent; into /dev/null it is not (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 1 _g_intent "echo hi > out.txt"
  _g_sent a 0 _g_intent "echo hi > /dev/null"
  _g_sent a 1 _g_intent "echo hi >> log.txt"
  _g_sent a 1 _g_intent "cat a.txt >out.txt"
  _g_sent a 0 _g_intent "cat a.txt </dev/null"
fi

if _want g-ruleout-fd; then
  _flow_test_begin "g-ruleout-fd"
  _g_setup g-ruleout-fd "a file-descriptor redirection is not a second command (G3); a file after it still is (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 0 _g_intent "ls 2>&1 | head"
  _g_sent a 0 _g_intent "echo hi > /dev/null 2>&1"
  _g_sent a 0 _g_intent "grep -rn foo . &>/dev/null"
  _g_sent a 1 _g_intent "ls 2>&1 > out.txt"
  _g_sent a 1 _g_intent "ls &> out.txt"
  _g_sent a 0 _g_intent "cd plugins && ls -la; echo done"
fi

if _want g-ruleout-sed; then
  _flow_test_begin "g-ruleout-sed"
  _g_setup g-ruleout-sed "sed is ruled out only as sed -n with N, N,M or N,\$ followed by p (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 0 _g_intent "sed -n 5p f.txt"
  _g_sent a 0 _g_intent "sed -n '1,80p' f.txt"
  _g_sent a 0 _g_intent "sed -n '10,\$p' f.txt"
  _g_sent a 1 _g_intent "sed -i s/a/b/ f.txt"
  _g_sent a 1 _g_intent "sed -n s/a/b/p f.txt"
  _g_sent a 1 _g_intent "sed -n '1w out.txt' f.txt"
fi

if _want g-ruleout-git; then
  _flow_test_begin "g-ruleout-git"
  _g_setup g-ruleout-git "git reads are ruled out, git writes are sent (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 0 _g_intent "git status"
  _g_sent a 0 _g_intent "git log --oneline | head -5"
  _g_sent a 0 _g_intent "git -C sub diff --stat"
  _g_sent a 0 _g_intent "git stash list"
  _g_sent a 0 _g_intent "git branch -a"
  _g_sent a 1 _g_intent "git branch -D x"
  _g_sent a 1 _g_intent "git branch newname"
  _g_sent a 1 _g_intent "git config user.name x"
  _g_sent a 0 _g_intent "git config --get user.name"
  _g_sent a 1 _g_intent "git stash drop"
  _g_sent a 1 _g_intent "git commit -m x"
fi

if _want g-ruleout-gh; then
  _flow_test_begin "g-ruleout-gh"
  _g_setup g-ruleout-gh "gh reads are ruled out, gh writes are sent (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 0 _g_intent "gh pr view 5"
  _g_sent a 0 _g_intent "gh api repos/o/r/pulls/5"
  _g_sent a 0 _g_intent "gh api --method GET repos/o/r/issues"
  _g_sent a 1 _g_intent "gh api -X DELETE repos/o/r/git/refs/heads/x"
  _g_sent a 1 _g_intent "gh api repos/o/r/issues -f title=x"
  _g_sent a 1 _g_intent "gh pr merge 5 --squash"
  _g_sent a 1 _g_intent "gh issue close 5"
fi

if _want g-ruleout-wrapper; then
  _flow_test_begin "g-ruleout-wrapper"
  _g_setup g-ruleout-wrapper "a wrapper or an interpreter runs something the list cannot see, so it is sent; a command substitution is checked as its own command (G2)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 1 _g_intent "sudo ls"
  _g_sent a 1 _g_intent "env ls"
  _g_sent a 1 _g_intent "bash -c ls"
  _g_sent a 1 _g_intent "ls | xargs cat"
  _g_sent a 1 _g_intent "echo \$(make clean)"
  _g_sent a 0 _g_intent "echo \$(git rev-parse HEAD)"
  _g_sent a 1 _g_intent "python3 script.py"
fi

if _want g-unsplittable-sent; then
  _flow_test_begin "g-unsplittable-sent"
  _g_setup g-unsplittable-sent "a command the parser cannot split, or with no words, is not ruled out; an empty command is not sent (G2, invalid input)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 1 _g_intent "ls \"unterminated"
  _g_sent a 0 _g_intent ""
fi

# --------------------------------------------------- secrets and the state

if _want g-mask; then
  _flow_test_begin "g-mask"
  _g_setup g-mask "the value of every NAME=value assignment is sent as ***, wherever it stands in the command (G5)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_sent a 1 _g_intent "TOKEN=abc123 make deploy"
  _g_sent a 1 _g_intent "cd x && API=zz9q make"
  _g_sent a 1 _g_intent "X=\"a b c\" make; Y='qq7w' make"
  e2e_expect_equal "false" "$(grep -qE 'abc123|zz9q|a b c|qq7w' "$(e2e_stub_log a)" && echo true || echo false)" "no assignment value reached the stub"
  e2e_expect_equal "TOKEN=*** make deploy" "$(jq -rs '.[0].body.state.command' "$(e2e_stub_log a)")" "the first command as sent"
  e2e_expect_equal "cd x && API=*** make" "$(jq -rs '.[1].body.state.command' "$(e2e_stub_log a)")" "the second command as sent"
  e2e_expect_equal "X=*** make; Y=*** make" "$(jq -rs '.[2].body.state.command' "$(e2e_stub_log a)")" "the third command as sent"
fi

if _want g-secrets-flagged; then
  _flow_test_begin "g-secrets-flagged"
  _g_setup g-secrets-flagged "a command the secrets check refuses is never sent, and the hook prints nothing (G5)"
  e2e_stub_start a "{\"body\":$(_ri 0.99)}"
  _g_settings on off a
  _g_sent a 0 _g_intent "TOKEN=abcdefghij1234 make deploy"
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  e2e_expect_equal "" "$E2E_ERR" "hook stderr"
  _g_no_decision
fi

if _want g-state-shape; then
  _flow_test_begin "g-state-shape"
  _g_setup g-state-shape "the state is the masked command, the working directory, the temporary directory and the repository root, and the record names the tool call"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_intent "make deploy" toolu_01state
  e2e_expect_equal "command,cwd,repository_root,temp_dir" "$(jq -r '.body.state | keys | join(",")' "$(e2e_stub_log a)")" "the state's fields"
  e2e_expect_equal "true" "$(jq -r --arg r "$E2E_REPO" --arg t "$G_TMP" '.body.state | (.cwd == $r) and ((.repository_root | ascii_downcase | endswith("/repo"))) and (.temp_dir | endswith("/tmp"))' "$(e2e_stub_log a)")" "cwd, repository root and temp dir"
  e2e_expect_equal "bash:toolu_01state" "$(jq -r '.ref' <<<"$(_g_last_record)")" "the record's ref"
  e2e_expect_equal "0" "$(find "$G_TMP" -type f | wc -l | tr -d ' ')" "state files left in TMPDIR"
fi

# ------------------------------------------------------------------ current

if _want g-current; then
  _flow_test_begin "g-current"
  _g_setup g-current "current is block when any pattern check refuses the command, the force-push check included, and allow otherwise (G6)"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  _g_intent "git push --force origin main"
  e2e_expect_equal "block" "$(jq -r '.current' <<<"$(_g_last_record)")" "current for a force push"
  _g_intent "rm -rf src"
  e2e_expect_equal "block" "$(jq -r '.current' <<<"$(_g_last_record)")" "current for rm -rf src"
  _g_intent "make deploy"
  e2e_expect_equal "allow" "$(jq -r '.current' <<<"$(_g_last_record)")" "current for make deploy"
fi

if _want g-current-unknown; then
  _flow_test_begin "g-current-unknown"
  _g_setup g-current-unknown "a pattern check that cannot run (here it exits 3) makes current unknown, and the command is still asked about"
  e2e_stub_start a "{\"body\":$(_ri 0.5)}"
  _g_settings on off a
  e2e_plugin_copy hooks/scripts/block-unchecked-merge.sh $'#!/bin/bash\nexit 3'
  _g_sent a 1 _g_intent "make deploy"
  e2e_expect_equal "unknown" "$(jq -r '.current' <<<"$(_g_last_record)")" "current"
fi

# -------------------------------------------------------------- on mode

if _want g-on-ask; then
  _flow_test_begin "g-on-ask"
  _g_setup g-on-ask "on, p=0.9 (confidence 0.8, at the shipped threshold) for a command the patterns allow: the hook asks, naming the site and p (G4)"
  e2e_stub_start a "{\"body\":$(_ri 0.9)}"
  _g_settings on off a
  _g_intent "make deploy"
  _g_no_decision
  e2e_expect_equal "PreToolUse ask" "$(jq -r '.hookSpecificOutput | "\(.hookEventName) \(.permissionDecision)"' <<<"$E2E_OUT" 2>/dev/null)" "the decision"
  e2e_expect_equal "true" "$(jq -r '.hookSpecificOutput.permissionDecisionReason | contains("guard.command-intent") and contains("0.9")' <<<"$E2E_OUT" 2>/dev/null)" "the reason names the site and p"
fi

if _want g-on-harmless; then
  _flow_test_begin "g-on-harmless"
  _g_setup g-on-harmless "on, p=0.1 (confidence 0.8, at the threshold, but harmless): nothing is printed (G4)"
  e2e_stub_start a "{\"body\":$(_ri 0.1)}"
  _g_settings on off a
  _g_intent "make deploy"
  _g_requests a 1
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  _g_no_decision
fi

if _want g-on-below-threshold; then
  _flow_test_begin "g-on-below-threshold"
  _g_setup g-on-below-threshold "on, p=0.6 (confidence 0.2, below the threshold): nothing is printed"
  e2e_stub_start a "{\"body\":$(_ri 0.6)}"
  _g_settings on off a
  _g_intent "make deploy"
  _g_requests a 1
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
fi

if _want g-precedence; then
  _flow_test_begin "g-precedence"
  _g_setup g-precedence "on, the model says harmless (p=0.02) about commands the pattern checks refuse: the pattern checks still exit 2, and the new hook prints nothing and exits 0, so the refusal stands (G1)"
  e2e_stub_start a "{\"body\":$(_ri 0.02)}"
  _g_settings on off a
  e2e_run_hook "$INTENT" "$(_g_pre "rm -rf src")"
  e2e_expect_equal "" "$E2E_OUT" "new hook stdout for rm -rf src"
  _g_no_decision
  e2e_run_hook hooks/scripts/block-destructive.sh "$(_g_pre "rm -rf src")"
  e2e_expect_equal "2" "$E2E_RC" "block-destructive.sh exit for rm -rf src"
  e2e_run_hook "$INTENT" "$(_g_pre "git push --force origin main")"
  e2e_expect_equal "" "$E2E_OUT" "new hook stdout for a force push"
  _g_no_decision
  e2e_run_hook hooks/scripts/block-force-push.sh "$(_g_pre "git push --force origin main")"
  e2e_expect_equal "2" "$E2E_RC" "block-force-push.sh exit for a force push"
fi

if _want g-on-blocked-no-ask; then
  _flow_test_begin "g-on-blocked-no-ask"
  _g_setup g-on-blocked-no-ask "on, p=0.98 about a command a pattern check already refuses: no ask, the refusal decides"
  e2e_stub_start a "{\"body\":$(_ri 0.98)}"
  _g_settings on off a
  _g_intent "rm -rf src"
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  _g_no_decision
fi

if _want g-never-decides; then
  _flow_test_begin "g-never-decides"
  _g_setup g-never-decides "in off, shadow and on, for p 0.02, 0.5 and 0.98, on an allowed and a refused command: the intent hook exits 0 and never names allow, defer or deny (G1)"
  for p in 0.02 0.5 0.98; do
    e2e_stub_start "p${p//./}" "{\"body\":$(_ri "$p")}"
    for mode in off shadow on; do
      _g_settings "$mode" off "p${p//./}"
      for c in "make deploy" "rm -rf src"; do
        _g_intent "$c"
        _g_no_decision
      done
    done
  done
fi

# ------------------------------------------------------------- shadow mode

if _want g-shadow-detached; then
  _flow_test_begin "g-shadow-detached"
  _g_setup g-shadow-detached "shadow with a provider that takes 5 s: the hook returns at once with nothing printed, the record is written later, and no state file is left (G7)"
  e2e_stub_start a "{\"body\":$(_ri 0.9),\"delay_ms\":5000}"
  _g_settings shadow off a '{"timeoutMs":10000}'
  t0=$(_g_now_ms)
  _g_intent "make deploy" toolu_01shadow
  t1=$(_g_now_ms)
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  _g_no_decision
  e2e_expect_equal "true" "$([ $((t1 - t0)) -lt 3000 ] && echo true || echo false)" "the hook returned within 3 s (took $((t1 - t0)) ms)"
  _g_wait_for 200 _g_has_records 1
  e2e_expect_equal "shadow answered allow bash:toolu_01shadow" "$(jq -r '"\(.mode) \(.result) \(.current) \(.ref)"' <<<"$(_g_last_record)")" "the record"
  _g_wait_for 50 test "$(find "$G_TMP" -type f | wc -l | tr -d ' ')" = 0
  e2e_expect_equal "0" "$(find "$G_TMP" -type f | wc -l | tr -d ' ')" "state files left in TMPDIR"
fi

# --------------------------------------------------------- failure modes

if _want g-failures; then
  _flow_test_begin "g-failures"
  _g_setup g-failures "a timeout, an HTTP 500, a payload that is not JSON, one without a command, and a python3 that fails: exit 0, nothing printed (G9)"
  e2e_stub_start slow "{\"body\":$(_ri 0.99),\"delay_ms\":3000}"
  _g_settings on off slow '{"timeoutMs":500}'
  _g_intent "make deploy"
  e2e_expect_equal "" "$E2E_OUT" "stdout on a timeout"
  _g_no_decision
  e2e_stub_start err "{\"status\":500,\"body\":{\"detail\":\"x\"}}"
  _g_settings on off err
  _g_intent "make deploy"
  e2e_expect_equal "" "$E2E_OUT" "stdout on HTTP 500"
  _g_no_decision
  e2e_stub_start a "{\"body\":$(_ri 0.99)}"
  _g_settings on on a
  _g_sent a 0 e2e_run_hook "$INTENT" "not json"
  _g_no_decision
  _g_sent a 0 e2e_run_hook "$INTENT" '{"tool_name":"Bash","tool_input":{}}'
  _g_no_decision
  _g_sent a 0 e2e_run_hook "$SCREEN" "not json"
  _g_no_decision
  printf '#!/bin/sh\nexit 127\n' > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
  _g_sent a 0 _g_intent "make deploy"
  e2e_expect_equal "" "$E2E_OUT" "stdout with a broken python3"
  _g_no_decision
  _g_sent a 0 _g_screen "gh issue view 5" "title: x"
  e2e_expect_equal "" "$E2E_OUT" "screen stdout with a broken python3"
  rm -f "$E2E_BIN/python3"
fi

if _want g-provider-none; then
  _flow_test_begin "g-provider-none"
  _g_setup g-provider-none "no provider, with both sites on in the user settings: nothing is sent and nothing printed"
  e2e_stub_start a "{\"body\":$(_ri 0.99)}"
  e2e_user_settings "$(jq -nc --arg si "$SITE_I" --arg st "$SITE_T" '{systemOne: {provider: "none", uses: {($si): "on", ($st): "on"}}}')"
  _g_intent "make deploy"
  e2e_expect_equal "" "$E2E_OUT" "intent stdout"
  _g_screen "gh issue view 5" "title: x"
  e2e_expect_equal "" "$E2E_OUT" "screen stdout"
  _g_requests a 0
fi

if _want g-repo-cannot-raise; then
  _flow_test_begin "g-repo-cannot-raise"
  _g_setup g-repo-cannot-raise "the user has both sites off and the repository's settings switch them on: nothing is sent"
  e2e_stub_start a "{\"body\":$(_ri 0.99)}"
  _g_settings off off a
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg si "$SITE_I" --arg st "$SITE_T" '{systemOne: {uses: {($si): "on", ($st): "on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _g_intent "make deploy"
  _g_screen "gh issue view 5" "title: x"
  _g_requests a 0
  e2e_expect_equal "" "$E2E_OUT" "stdout"
fi

# ------------------------------------------------- planted-instructions

if _want g-gh-read-detect; then
  _flow_test_begin "g-gh-read-detect"
  _g_setup g-gh-read-detect "only gh reads of issue or pull request text are screened; writes and other reads are not (G8)"
  e2e_stub_start a "{\"body\":$(_rt 0.5)}"
  _g_settings off on a
  _g_sent a 1 _g_screen "gh api repos/o/r/issues/5/comments" '[{"body":"x"}]'
  _g_sent a 1 _g_screen "gh api /repos/o/r/pulls/5/reviews --paginate" '[{"body":"x"}]'
  _g_sent a 1 _g_screen "gh issue view 5" "title: x"
  _g_sent a 1 _g_screen "gh pr view 5 --comments" "title: x"
  _g_sent a 1 _g_screen "gh api --method GET repos/o/r/issues" '[{"body":"x"}]'
  _g_sent a 1 _g_screen "cd sub && gh issue view 5 --json body --jq .body" "x"
  _g_sent a 0 _g_screen "gh pr merge 5 --squash" "merged"
  _g_sent a 0 _g_screen "gh api -X POST repos/o/r/issues/5/comments -f body=x" '{"id":1}'
  _g_sent a 0 _g_screen "gh api repos/o/r/contents/README.md" '{"content":"x"}'
  _g_sent a 0 _g_screen "gh issue list" "5 open x"
  _g_sent a 0 _g_screen "git log -1" "commit abc"
fi

if _want g-screen-direction; then
  _flow_test_begin "g-screen-direction"
  _g_setup g-screen-direction "on: p=0.9 adds a note that the output is data; p=0.1, with the same confidence, adds nothing (G4)"
  e2e_stub_start hi "{\"body\":$(_rt 0.9)}"
  _g_settings off on hi
  _g_screen "gh issue view 5" "title: x"
  _g_no_decision
  e2e_expect_equal "PostToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$E2E_OUT" 2>/dev/null)" "the event named"
  e2e_expect_equal "true" "$(jq -r '.hookSpecificOutput.additionalContext | contains("guard.planted-instructions") and contains("data")' <<<"$E2E_OUT" 2>/dev/null)" "the note names the site and says the output is data"
  e2e_expect_equal "false" "$(printf '%s' "$E2E_OUT" | grep -qE '"(decision|permissionDecision|continue)"' && echo true || echo false)" "the note decides nothing"
  e2e_stub_start lo "{\"body\":$(_rt 0.1)}"
  _g_settings off on lo
  _g_screen "gh issue view 5" "title: x"
  _g_requests lo 1
  e2e_expect_equal "" "$E2E_OUT" "stdout on p=0.1"
fi

if _want g-screen-mask; then
  _flow_test_begin "g-screen-mask"
  _g_setup g-screen-mask "the gh command is sent with assignment values masked (G5)"
  e2e_stub_start a "{\"body\":$(_rt 0.5)}"
  _g_settings off on a
  _g_screen "GH_TOKEN=abc123 gh issue view 5" "title: x"
  _g_requests a 1
  e2e_expect_equal "GH_TOKEN=*** gh issue view 5" "$(jq -r '.body.state.command' "$(e2e_stub_log a)")" "the command as sent"
  e2e_expect_equal "false" "$(grep -q abc123 "$(e2e_stub_log a)" && echo true || echo false)" "the value did not reach the stub"
fi

if _want g-screen-skip; then
  _flow_test_begin "g-screen-skip"
  _g_setup g-screen-skip "no output, a failed call, or the intent site's event: nothing is sent"
  e2e_stub_start a "{\"body\":$(_rt 0.99)}"
  _g_settings off on a
  _g_sent a 0 _g_screen "gh issue view 5" ""
  _g_sent a 0 _g_screen "gh issue view 5" "title: x" PostToolUseFailure
  _g_sent a 0 e2e_run_hook "$SCREEN" "$(_g_pre "gh issue view 5")"
fi

if _want g-screen-state-shape; then
  _flow_test_begin "g-screen-state-shape"
  _g_setup g-screen-state-shape "the output is sent as a list of lines, each cut to 1000 characters, at most 600 lines (G10)"
  e2e_stub_start a "{\"body\":$(_rt 0.5)}"
  _g_settings off on a
  out=$(python3 -c 'import sys; L = ["line %d" % i for i in range(700)]; L[2] = "x" * 1500; sys.stdout.write("\n".join(L) + "\n")')
  _g_screen "gh issue view 5 --comments" "$out" PostToolUse toolu_01read
  e2e_expect_equal "array 600 1000 line 0 line 599" "$(jq -r '.body.state.output | "\(type) \(length) \(.[2] | length) \(.[0]) \(.[-1])"' "$(e2e_stub_log a)")" "the output as sent"
  e2e_expect_equal "gh-read:toolu_01read unmarked" "$(jq -r '"\(.ref) \(.current)"' <<<"$(_g_last_record)")" "the record's ref and current"
fi

if _want g-screen-shadow-detached; then
  _flow_test_begin "g-screen-shadow-detached"
  _g_setup g-screen-shadow-detached "shadow with a provider that takes 5 s: the screen hook returns at once, the record is written later, no state file is left (G7)"
  e2e_stub_start a "{\"body\":$(_rt 0.9),\"delay_ms\":5000}"
  _g_settings off shadow a '{"timeoutMs":10000}'
  t0=$(_g_now_ms)
  _g_screen "gh issue view 5" "title: x"
  t1=$(_g_now_ms)
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  _g_no_decision
  e2e_expect_equal "true" "$([ $((t1 - t0)) -lt 3000 ] && echo true || echo false)" "the hook returned within 3 s (took $((t1 - t0)) ms)"
  _g_wait_for 200 _g_has_records 1
  e2e_expect_equal "shadow answered unmarked" "$(jq -r '"\(.mode) \(.result) \(.current)"' <<<"$(_g_last_record)")" "the record"
  _g_wait_for 50 test "$(find "$G_TMP" -type f | wc -l | tr -d ' ')" = 0
  e2e_expect_equal "0" "$(find "$G_TMP" -type f | wc -l | tr -d ' ')" "state files left in TMPDIR"
fi

# ------------------------------------------------------------- hooks.json

if _want g-hooks-json; then
  _flow_test_begin "g-hooks-json"
  _g_setup g-hooks-json "hooks.json runs the intent hook on PreToolUse Bash and the screen hook on PostToolUse Bash, each with a 35 s timeout (G11)"
  e2e_expect_equal "35" "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | endswith("/s1-command-intent.sh")) | .timeout] | join(",")' "$E2E_ACTIVE_PLUGIN/hooks/hooks.json")" "the intent hook entry"
  e2e_expect_equal "35" "$(jq -r '[.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | endswith("/s1-screen-text.sh")) | .timeout] | join(",")' "$E2E_ACTIVE_PLUGIN/hooks/hooks.json")" "the screen hook entry"
  e2e_expect_equal "" "$(jq -r '[.hooks.PostToolUseFailure[]?.hooks[]? | select(.command | endswith("/s1-screen-text.sh"))] | length | select(. > 0)' "$E2E_ACTIVE_PLUGIN/hooks/hooks.json")" "no PostToolUseFailure entry for the screen hook"
  for h in "$INTENT" "$SCREEN"; do
    e2e_expect_equal "true" "$([ -x "$E2E_ACTIVE_PLUGIN/$h" ] && echo true || echo false)" "$h is executable"
  done
fi
