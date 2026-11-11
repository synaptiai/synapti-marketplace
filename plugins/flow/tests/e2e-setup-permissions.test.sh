# shellcheck shell=bash
# End-to-end: the Claude Code ask rules step of /flow:setup
# (commands/setup.md, Phase 5). The fence runs as Claude Code runs it, in a
# scratch repository, and writes the rules into the settings file the person
# chose. With FLOW_E2E_LIVE=1 one more scenario runs the claude CLI against
# the written rules, with no flow hook loaded, to show that Claude Code itself
# stops the actions the rules name.
#
# Ways it can be wrong, written down before the scenarios:
#   P1 an existing settings file loses what it had: its other permission
#      lists, its other ask rules, or its other keys
#   P2 a second run changes the file (duplicate rules, reordering, a new
#      format), so setup is not safe to run again
#   P3 a file that is not a JSON object is overwritten, or a file reached
#      through a symlink is written through it
#   P4 the rules go to the wrong file: the other choice's file, or a file in
#      the subdirectory setup was started from instead of the repository top
#   P5 jq is missing and a partial or empty file is written anyway
#   P6 a rule is written in a syntax Claude Code does not match, so it never
#      asks (checked live: P6 is the scenario that needs the claude CLI)

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

SETUP="$E2E_PLUGIN_DIR/commands/setup.md"
SP_MARK="# SETUP_PERMISSIONS_BEGIN"
# The rules, in the order setup writes them (commands/setup.md).
SP_RULES='["Bash(gh pr merge *)","Bash(gh release create *)","Bash(gh release edit *)","Bash(gh release delete *)","Bash(gh release upload *)","Bash(gh release delete-asset *)","Bash(git push *--tags*)","Bash(git push *--follow-tags*)","Bash(git push *refs/tags/*)"]'

_sp_setup() {   # <name> <purpose>
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
}

# _sp_fence [NAME=value ...] — the fence under every shell of
# E2E_FENCE_SHELLS, each starting from the same .claude directory, since the
# fence writes it. Each shell must print the same stdout and leave the same
# files; the expectations then apply to the last run.
_sp_fence() {
  local shells="$E2E_FENCE_SHELLS" sh snap="$E2E_DIR/claude-before" out0="" sum0="" first="" sum
  rm -rf "$snap"
  [ -e "$E2E_REPO/.claude" ] && cp -RP "$E2E_REPO/.claude" "$snap"
  for sh in $shells; do
    rm -rf "$E2E_REPO/.claude"
    [ -e "$snap" ] && cp -RP "$snap" "$E2E_REPO/.claude"
    E2E_FENCE_SHELLS="$sh" e2e_run_fence "$@" "$SETUP" "$SP_MARK"
    sum=$(cd "$E2E_REPO" && find .claude -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort)
    if [ -z "$first" ]; then
      first=$sh; out0=$E2E_OUT; sum0=$sum
    else
      e2e_expect_equal "$out0" "$E2E_OUT" "stdout under $sh, against $first"
      e2e_expect_equal "$sum0" "$sum" "files under $sh, against $first"
    fi
  done
}

# _sp_has_rules <file> — every flow rule is in permissions.ask exactly once.
_sp_has_rules() {
  jq -e --argjson r "$SP_RULES" '.permissions.ask as $a | all($r[]; . as $x | ($a | map(select(. == $x)) | length) == 1)' "$1" >/dev/null 2>&1
}

_sp_setup sp-fresh "no settings file: the shared choice writes .claude/settings.json at the repository top with the nine ask rules and nothing else"
_sp_fence PERM_FILE=shared
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_out "PERMISSIONS=written"
e2e_expect_out "ADDED=9"
e2e_expect_equal yes "$(_sp_has_rules "$E2E_REPO/.claude/settings.json" && echo yes || echo no)" "each rule once in permissions.ask"
e2e_expect_equal '["permissions"]' "$(jq -c 'keys' "$E2E_REPO/.claude/settings.json" 2>/dev/null)" "top-level keys"
e2e_expect_equal '["ask"]' "$(jq -c '.permissions | keys' "$E2E_REPO/.claude/settings.json" 2>/dev/null)" "permission lists"
e2e_expect_equal no "$([ -e "$E2E_REPO/.claude/settings.local.json" ] && echo yes || echo no)" "settings.local.json exists"

_sp_setup sp-merge "an existing .claude/settings.json with allow, deny, its own ask rules (one of them flow's) and another key: all of it is kept, the missing rules are added after the existing ones, and a second run leaves the file byte for byte as it was (P1, P2)"
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"model":"x","permissions":{"allow":["Bash(ls)"],"deny":["Read(.env)"],"ask":["Bash(rm *)","Bash(gh pr merge *)"]},"hooks":{}}' > "$E2E_REPO/.claude/settings.json"
_sp_fence PERM_FILE=shared
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_out "PERMISSIONS=written"
e2e_expect_out "ADDED=8"
F="$E2E_REPO/.claude/settings.json"
e2e_expect_equal '"x"' "$(jq -c '.model' "$F")" "model kept"
e2e_expect_equal '{}' "$(jq -c '.hooks' "$F")" "hooks kept"
e2e_expect_equal '["Bash(ls)"]' "$(jq -c '.permissions.allow' "$F")" "allow kept"
e2e_expect_equal '["Read(.env)"]' "$(jq -c '.permissions.deny' "$F")" "deny kept"
e2e_expect_equal '"Bash(rm *)"' "$(jq -c '.permissions.ask[0]' "$F")" "the existing ask rule stays first"
e2e_expect_equal 10 "$(jq '.permissions.ask | length' "$F")" "ask rules: the two there plus the eight missing"
e2e_expect_equal yes "$(_sp_has_rules "$F" && echo yes || echo no)" "each flow rule once"
cp "$F" "$E2E_DIR/first.json"
_sp_fence PERM_FILE=shared
e2e_expect_out "PERMISSIONS=unchanged"
e2e_expect_equal same "$(cmp -s "$F" "$E2E_DIR/first.json" && echo same || echo changed)" "the file after a second run"

_sp_setup sp-local "the personal choice writes .claude/settings.local.json and leaves .claude/settings.json as it was (P4)"
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"permissions":{"allow":["Bash(ls)"]}}' > "$E2E_REPO/.claude/settings.json"
cp "$E2E_REPO/.claude/settings.json" "$E2E_DIR/shared.json"
_sp_fence PERM_FILE=local
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_out "PERMISSIONS=written"
e2e_expect_equal yes "$(_sp_has_rules "$E2E_REPO/.claude/settings.local.json" && echo yes || echo no)" "each rule once in settings.local.json"
e2e_expect_equal same "$(cmp -s "$E2E_REPO/.claude/settings.json" "$E2E_DIR/shared.json" && echo same || echo changed)" "settings.json"

_sp_setup sp-subdir "setup started in a subdirectory writes the file at the repository top, not in the subdirectory (P4)"
mkdir -p "$E2E_REPO/src/deep"
# e2e_run_fence runs in the repository top, so the fence runs from the
# subdirectory here, as bash runs it.
e2e_fence "$SETUP" "$SP_MARK" > "$E2E_DIR/perm.sh"
OUT=$(cd "$E2E_REPO/src/deep" && _e2e_git_env && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" PERM_FILE=shared bash "$E2E_DIR/perm.sh" 2>&1)
printf 'from src/deep: %s\n' "$OUT" | _e2e_art
e2e_expect_equal yes "$(_sp_has_rules "$E2E_REPO/.claude/settings.json" && echo yes || echo no)" "rules at the repository top"
e2e_expect_equal no "$([ -e "$E2E_REPO/src/deep/.claude" ] && echo yes || echo no)" "a .claude directory in the subdirectory"

_sp_setup sp-not-json "a settings file that is not valid JSON, is JSON but not one object, or holds a permissions that is not an object or an ask that is not a list, is left byte for byte as it was and reported with the reason (P3)"
mkdir -p "$E2E_REPO/.claude"
for BODY in '{"permissions": {"ask": [' '["Bash(ls)"]' 'null' '{"a":1} {"b":2}' '{"permissions":"x"}' '{"permissions":{"ask":"Bash(x)"}}'; do
  printf '%s\n' "$BODY" > "$E2E_REPO/.claude/settings.json"
  cp "$E2E_REPO/.claude/settings.json" "$E2E_DIR/before.json"
  _sp_fence PERM_FILE=shared
  e2e_expect_equal 0 "$E2E_RC" "exit status for: $BODY"
  e2e_expect_out "PERMISSIONS=refused"
  e2e_expect_equal same "$(cmp -s "$E2E_REPO/.claude/settings.json" "$E2E_DIR/before.json" && echo same || echo changed)" "the file for: $BODY"
done

_sp_setup sp-mode "the file keeps its mode when rewritten (0644 stays 0644, not the 0600 of a temporary file), and a new file gets the mode the umask gives (P1)"
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"permissions":{}}' > "$E2E_REPO/.claude/settings.json"
chmod 644 "$E2E_REPO/.claude/settings.json"
_sp_fence PERM_FILE=shared
e2e_expect_out "PERMISSIONS=written"
e2e_expect_equal 644 "$(stat -c %a "$E2E_REPO/.claude/settings.json" 2>/dev/null || stat -f %Lp "$E2E_REPO/.claude/settings.json")" "mode of the rewritten file"
_sp_fence PERM_FILE=local
e2e_expect_equal "$(printf '%o' $(( 0666 & ~0$(umask) )))" "$(stat -c %a "$E2E_REPO/.claude/settings.local.json" 2>/dev/null || stat -f %Lp "$E2E_REPO/.claude/settings.local.json")" "mode of the new file"

_sp_setup sp-empty "an empty settings file, or one holding only blank lines, holds no settings: the nine rules are written to it, and a second run changes nothing"
mkdir -p "$E2E_REPO/.claude"
printf '\n  \n' > "$E2E_REPO/.claude/settings.local.json"
_sp_fence PERM_FILE=local
e2e_expect_out "PERMISSIONS=written"
e2e_expect_equal 9 "$(jq '.permissions.ask | length' "$E2E_REPO/.claude/settings.local.json")" "rules in the file"
_sp_fence PERM_FILE=local
e2e_expect_out "PERMISSIONS=unchanged"

_sp_setup sp-symlink "a settings file that is a symlink is not written through, and its target is left as it was (P3)"
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{}' > "$E2E_DIR/elsewhere.json"
ln -s "$E2E_DIR/elsewhere.json" "$E2E_REPO/.claude/settings.json"
_sp_fence PERM_FILE=shared
e2e_expect_out "PERMISSIONS=refused"
e2e_expect_equal '{}' "$(cat "$E2E_DIR/elsewhere.json")" "the symlink's target"

_sp_setup sp-no-jq "jq is missing: nothing is written and setup says the rules were not installed (P5)"
NOJQ=$(e2e_path_without jq)
_sp_fence "PATH=$NOJQ" PERM_FILE=shared
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_out "PERMISSIONS=skipped"
e2e_expect_out "jq"
e2e_expect_equal no "$([ -e "$E2E_REPO/.claude/settings.json" ] && echo yes || echo no)" "settings.json exists"

_sp_setup sp-bad-choice "a choice other than shared or local writes nothing"
_sp_fence PERM_FILE=everyone
e2e_expect_out "PERMISSIONS=refused"
e2e_expect_equal no "$([ -e "$E2E_REPO/.claude" ] && echo yes || echo no)" ".claude exists"

# --- P6, live: Claude Code itself asks, with no flow hook loaded ---------------
# Run only with FLOW_E2E_LIVE=1: it starts the claude CLI, which needs an
# account and costs a few cents. Bash is allowed on the command line
# (--allowedTools: a project's own allow list is ignored in a workspace that
# was never trusted), so only an ask rule can stop a command, and `claude -p`
# turns an ask into a refusal that it lists in permission_denials. A stub gh
# logs every call it gets; a stub git logs `git push` and hands every other
# call (Claude Code's own) to git. The controls (gh pr view, a branch push)
# must reach the stubs, or the run shows nothing about the rules.
_flow_test_begin "sp-live-claude-asks"
if [ "${FLOW_E2E_LIVE:-0}" != 1 ]; then
  _flow_assert_pass "SKIP: set FLOW_E2E_LIVE=1 to run the claude CLI against the rules"
elif ! command -v claude >/dev/null 2>&1; then
  _flow_assert_fail "FLOW_E2E_LIVE=1 but the claude CLI is not on PATH"
else
  e2e_new sp-live-claude-asks
  e2e_describe "the rules setup writes, read by Claude Code with no flow hook loaded (project and local settings only): cd sub && gh pr merge 7, echo \"\$(gh release create v1)\" and git push origin --tags are refused by Claude Code's permission check and never reach a stub gh or git, while the controls gh pr view 7 and git push origin main do (P6)"
  e2e_repo main
  mkdir -p "$E2E_REPO/sub" "$E2E_DIR/stub"
  _sp_fence PERM_FILE=shared
  SP_GIT=$(command -v git)
  printf '#!/bin/sh\nprintf "gh %%s\\n" "$*" >> "%s/calls.log"\necho "STUB gh $*"\n' "$E2E_DIR" > "$E2E_DIR/stub/gh"
  printf '#!/bin/sh\nif [ "$1" = push ]; then printf "git %%s\\n" "$*" >> "%s/calls.log"; echo "STUB git $*"; exit 0; fi\nexec "%s" "$@"\n' "$E2E_DIR" "$SP_GIT" > "$E2E_DIR/stub/git"
  chmod +x "$E2E_DIR/stub/gh" "$E2E_DIR/stub/git"
  : > "$E2E_DIR/calls.log"
  : > "$E2E_DIR/denied.txt"
  for C in 'gh pr view 7' 'git push origin main' 'cd sub && gh pr merge 7' 'gh pr merge' 'echo "$(gh release create v1)"' 'gh release edit v1 --draft=false' 'git push origin --tags'; do
    (cd "$E2E_REPO" && PATH="$E2E_DIR/stub:$PATH" perl -e 'alarm shift; exec @ARGV' 180 claude -p --setting-sources project,local \
      --allowedTools Bash --model haiku --output-format json \
      "Use the Bash tool exactly once to run this exact command, character for character, and nothing else: $C" \
      > "$E2E_DIR/claude.json" 2>"$E2E_DIR/claude.err")
    printf -- '--- %s\n%s\n%s\n' "$C" "$(jq -c '{result, permission_denials}' "$E2E_DIR/claude.json" 2>/dev/null)" "$(cat "$E2E_DIR/claude.err")" | _e2e_art
    jq -r '.permission_denials[]?.tool_input.command // empty' "$E2E_DIR/claude.json" 2>/dev/null >> "$E2E_DIR/denied.txt"
  done
  printf -- '--- calls\n%s\n--- denied\n%s\n' "$(cat "$E2E_DIR/calls.log")" "$(cat "$E2E_DIR/denied.txt")" | _e2e_art
  e2e_expect_equal 1 "$(grep -c '^gh pr view 7' "$E2E_DIR/calls.log")" "the control gh pr view 7 reached the stub gh"
  e2e_expect_equal 1 "$(grep -c '^git push origin main' "$E2E_DIR/calls.log")" "the control git push origin main reached the stub git"
  e2e_expect_equal 0 "$(grep -c 'merge\|release\|--tags' "$E2E_DIR/calls.log")" "calls that merge, release or push tags"
  for C in 'cd sub && gh pr merge 7' 'gh pr merge' 'echo "$(gh release create v1)"' 'gh release edit v1 --draft=false' 'git push origin --tags'; do
    e2e_expect_equal yes "$(grep -qxF -- "$C" "$E2E_DIR/denied.txt" && echo yes || echo no)" "Claude Code's permission check refused: $C"
  done
fi
