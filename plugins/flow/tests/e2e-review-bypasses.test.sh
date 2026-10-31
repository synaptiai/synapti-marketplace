# shellcheck shell=bash
# End-to-end: every command that a review of the #316 branch reported as
# getting past a command hook, checked against flow as shipped now.
#
# The seven review rounds of the tier hook work (code and security reviewers,
# 2026-10-29 to 2026-10-30) reproduced 219 bypasses of tier-gate.sh,
# block-unchecked-merge.sh and block-destructive.sh. They are kept verbatim in
# fixtures/review-bypasses-316.tsv (round, hook, severity, command; a line
# break inside a command is written ⏎). Some need what the finding set up
# first; _rb_context below supplies it, from the finding's text.
#
#   block-destructive      the hook must refuse it (exit 2).
#   block-unchecked-merge  the hook must refuse it (exit 2): gh answers
#                          nothing here, so a merge it reads cannot show
#                          passing checks.
#   tier-gate              the hook must ask, or, when it does not, the
#                          command must be stopped when it runs: it is run
#                          for real, after the session's lines, against an
#                          ext:: remote and a fake gh, and flow's git or gh
#                          wrapper must refuse it, with no merge, release or
#                          tag on the remote.
#
# Ways it can be wrong, written down before the checks:
#   B1 a reported bypass is allowed again by the hook it got past, and for
#      a tier-gate row the wrapper does not stop it either
#   B2 the fixture is read wrongly (a tab or ⏎ inside a command), so the
#      hook is fed a different command from the one reported
#   B3 a line is skipped, so the count of commands checked is not the
#      count in the fixture
#   B4 a tier-gate row passes because, without its context, it did nothing:
#      the wrapper's refusal is required, not only the absence of an action

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "review bypasses: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

RB_FIXTURE="$REPO_ROOT/plugins/flow/tests/fixtures/review-bypasses-316.tsv"
RB_SID=sess-review-bypasses
ASK='"permissionDecision":"ask"'

_rb_hook() {
  case "$1" in
    tier-gate) printf 'hooks/scripts/tier-gate.sh' ;;
    block-unchecked-merge) printf 'hooks/scripts/block-unchecked-merge.sh' ;;
    block-destructive) printf 'hooks/scripts/block-destructive.sh' ;;
  esac
}

# _rb_context <hook> <command> — what the finding set up. Sets RB_PREFIX
# (text put before the command, for a hook that reads only the command),
# RB_ENV (variables the command runs with), and RB_REPO (a repository
# change: mirror-origin, mirror-mir, remote-tag-v5).
_rb_context() {
  RB_PREFIX=""; RB_ENV="CMD=gh pr merge 7"; RB_REPO=""
  case "$2" in
    'gh pr $A 7') RB_PREFIX='A=merge; ' ;;
    'eval X=$CMD')
      RB_ENV="CMD=x;gh pr merge 7"
      [ "$1" = block-unchecked-merge ] && RB_PREFIX="CMD='x;gh pr merge 1'; " ;;
    'git push --repo=mir') RB_REPO=mirror-mir ;;
    'git push 2>&1'|'git push >/dev/null'|'git push -q 2>&1 | tail -2') RB_REPO=mirror-origin ;;
    *'--force-with-lease=v5:<sha>'*) RB_REPO=remote-tag-v5 ;;
  esac
}

# _rb_run_hook <script> <command>
_rb_run_hook() {
  e2e_run_hook "$1" "$(jq -cn --arg c "$2" --arg cwd "$E2E_REPO" --arg s "$RB_SID" '{session_id:$s,cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
}

# A scratch repository with a tag v1, an ext:: remote origin (not a local
# path, as a GitHub remote is not), a fake gh, and the session's lines.
_rb_runtime_repo() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-317-bypasses
  mkdir -p "$E2E_REPO/.decisions" "$E2E_DIR/fakegh"
  (
    _e2e_git_env
    cd "$E2E_DIR" || exit 1
    git init -q --bare remote.git || exit 1
    cd "$E2E_REPO" || exit 1
    git config protocol.ext.allow always
    git remote add origin "ext::git %s $E2E_DIR/remote.git"
    git tag -a -m v1 v1
    case "$RB_REPO" in
      mirror-origin) git config remote.origin.mirror true ;;
      mirror-mir)
        git remote add mir "ext::git %s $E2E_DIR/remote.git"
        git config remote.mir.mirror true ;;
      remote-tag-v5)
        git tag -a -m v5 v5 && git push -q origin v5 2>/dev/null && git tag -d v5 >/dev/null ;;
    esac
  ) || _flow_assert_fail "$1: could not set up the repository"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh-calls.log"\necho FAKE-GH "$@"\n' "$E2E_DIR" > "$E2E_DIR/fakegh/gh"
  chmod +x "$E2E_DIR/fakegh/gh"
  : > "$E2E_DIR/gh-calls.log"
  e2e_run_hook CLAUDE_ENV_FILE="$E2E_DIR/env.sh" hooks/scripts/tier-session-start.sh \
    "$(jq -cn --arg s "$RB_SID" '{session_id:$s,hook_event_name:"SessionStart",source:"startup"}')"
}

_rb_remote_tags() { git --git-dir="$E2E_DIR/remote.git" for-each-ref --format='%(refname:short)' refs/tags 2>/dev/null | tr '\n' ' '; }

# --- the guards, and the tier hook's own reading ------------------------------

_flow_test_begin "review-bypasses"
e2e_new review-bypasses
e2e_describe "each command a #316 review round reported as getting past a hook, fed to that hook in a repository with a tag v1 and an origin remote"
e2e_repo feature/issue-317-bypasses
mkdir -p "$E2E_REPO/.decisions"
(
  _e2e_git_env
  cd "$E2E_DIR" || exit 1
  git init -q --bare origin.git || exit 1
  cd "$E2E_REPO" || exit 1
  git remote add origin "$E2E_DIR/origin.git"
  git tag -a -m v1 v1
  git push -q origin HEAD:refs/heads/main 2>/dev/null
  git fetch -q origin 2>/dev/null
) || _flow_assert_fail "review-bypasses: could not set up the repository"
RB_SHARED_DIR=$E2E_DIR
RB_SHARED_REPO=$E2E_REPO

RB_N=0
RB_LINES=$(grep -c '' "$RB_FIXTURE")
RB_RUNTIME=()
while IFS=$'\t' read -r RB_ROUND RB_HOOK RB_SEV RB_CMD; do
  RB_N=$((RB_N + 1))
  RB_SCRIPT=$(_rb_hook "$RB_HOOK")
  if [ -z "$RB_SCRIPT" ]; then
    _e2e_result fail "line $RB_N names a hook this file does not know: $RB_HOOK"
    continue
  fi
  _rb_context "$RB_HOOK" "$RB_CMD"
  # ⏎ stands for a line break inside the command.
  RB_TEXT=${RB_CMD//⏎/$'\n'}
  if [ "$RB_HOOK" = tier-gate ]; then
    # Read where the finding's repository change is, when it made one.
    if [ -z "$RB_REPO" ]; then
      _rb_run_hook "$RB_SCRIPT" "$RB_TEXT"
      case "$E2E_OUT" in
        *"$ASK"*) _e2e_result pass "round $RB_ROUND $RB_SEV, tier-gate asks: $RB_CMD"; continue ;;
      esac
    fi
    RB_RUNTIME+=("$RB_N"$'\t'"$RB_ROUND"$'\t'"$RB_SEV"$'\t'"$RB_CMD")
    continue
  fi
  _rb_run_hook "$RB_SCRIPT" "$RB_PREFIX$RB_TEXT"
  if [ "$E2E_RC" = 2 ]; then _e2e_result pass "round $RB_ROUND $RB_SEV, $RB_HOOK refuses: $RB_PREFIX$RB_CMD"
  else _e2e_result fail "round $RB_ROUND $RB_SEV, $RB_HOOK refuses (exit $E2E_RC): $RB_PREFIX$RB_CMD"; fi
done < "$RB_FIXTURE"
e2e_expect_equal "$RB_LINES" "$RB_N" "commands checked, against lines in the fixture (B3)"

# --- tier-gate rows the hook does not ask about: stopped when they run --------

RB_SED_E=0
printf 'x\n' | sed 'e echo y' >/dev/null 2>&1 && RB_SED_E=1
for ((RB_I = 0; RB_I < ${#RB_RUNTIME[@]}; RB_I++)); do
  IFS=$'\t' read -r RB_N RB_ROUND RB_SEV RB_CMD <<EOF
${RB_RUNTIME[RB_I]}
EOF
  _flow_test_begin "review-bypass-runtime-$RB_N"
  _rb_context tier-gate "$RB_CMD"
  _rb_runtime_repo "review-bypass-runtime-$RB_N" "round $RB_ROUND $RB_SEV tier-gate bypass, run for real: $RB_CMD"
  RB_TEXT=${RB_CMD//⏎/$'\n'}
  case "$RB_TEXT" in
    *'<sha>'*)
      RB_SHA=$(git --git-dir="$E2E_DIR/remote.git" rev-parse v5 2>/dev/null)
      RB_TEXT=${RB_TEXT//<sha>/$RB_SHA} ;;
  esac
  RB_TAGS_BEFORE=$(_rb_remote_tags)
  _rb_run_hook hooks/scripts/tier-gate.sh "$RB_TEXT"
  case "$E2E_OUT" in
    *"$ASK"*)
      _e2e_result pass "round $RB_ROUND $RB_SEV, tier-gate asks, with the finding's setup: $RB_CMD"
      continue ;;
  esac
  case "$RB_TEXT" in
    *"sed 'e'"*)
      if [ "$RB_SED_E" = 0 ]; then
        _e2e_result pass "SKIP: this sed has no e command, so the row runs nothing here: $RB_CMD"
        continue
      fi ;;
  esac
  printf 'run with %s: %s\n' "$RB_ENV" "$RB_TEXT" | _e2e_art
  RB_SQ="'"; RB_ESC="'\"'\"'"
  _e2e_exec env "$RB_ENV" TR_ENV="$E2E_DIR/env.sh" TR_FAKE="$E2E_DIR/fakegh" \
    perl -e 'alarm shift; exec @ARGV' 60 bash -c "PATH=\"\$TR_FAKE:\$PATH\"; . \"\$TR_ENV\"; eval '${RB_TEXT//$RB_SQ/$RB_ESC}'"
  printf -- '--- expectations\n' | _e2e_art
  e2e_expect_err "needs your confirmation"
  if grep -qE '(^| )(merge|release)( |$)|graphql|/merge|/releases' "$E2E_DIR/gh-calls.log"; then
    _e2e_result fail "gh ran no merge or release: $(tr '\n' ';' < "$E2E_DIR/gh-calls.log")"
  else
    _e2e_result pass "gh ran no merge or release"
  fi
  e2e_expect_equal "$RB_TAGS_BEFORE" "$(_rb_remote_tags)" "the remote's tags"
done

# --- commands none of the hooks may stop or ask about ---------------------------
#   B5 an ordinary command (a pipe into grep or tee, `which bash`, a PR body
#      in a heredoc, `bash --version`, the false prompts round 7 reported)
#      is asked about by tier-gate or refused by a guard
# fixtures/review-false-prompts-316.tsv: the round that reported it (or
# "issue", for the commands issue #317 names), then the command.
RB_OK_FIXTURE="$REPO_ROOT/plugins/flow/tests/fixtures/review-false-prompts-316.tsv"
_flow_test_begin "review-no-prompts"
e2e_new review-no-prompts
e2e_describe "ordinary commands, and the false prompts the #316 reviews reported: no hook asks or refuses"
E2E_DIR=$RB_SHARED_DIR
E2E_REPO=$RB_SHARED_REPO
RB_N=0
while IFS=$'\t' read -r RB_ROUND RB_CMD; do
  RB_N=$((RB_N + 1))
  RB_TEXT=${RB_CMD//⏎/$'\n'}
  _rb_run_hook hooks/scripts/tier-gate.sh "$RB_TEXT"
  case "$E2E_OUT" in
    *"$ASK"*) _e2e_result fail "tier-gate does not ask ($RB_ROUND): $RB_CMD" ;;
    *) _e2e_result pass "tier-gate does not ask ($RB_ROUND): $RB_CMD" ;;
  esac
  for RB_GUARD in block-destructive block-unchecked-merge; do
    _rb_run_hook "$(_rb_hook "$RB_GUARD")" "$RB_TEXT"
    e2e_expect_equal 0 "$E2E_RC" "$RB_GUARD allows ($RB_ROUND): $RB_CMD"
  done
done < "$RB_OK_FIXTURE"
e2e_expect_equal "$(grep -c '' "$RB_OK_FIXTURE")" "$RB_N" "commands checked, against lines in the fixture"
