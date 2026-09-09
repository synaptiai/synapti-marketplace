# Tests for the rm rule in hooks/scripts/block-destructive.sh.
#
# Contract under test: an rm is blocked (exit 2) ONLY when BOTH a recursive
# flag (-r/-R/--recursive) AND a force flag (-f/-F/--force) are present, in any
# order or spelling, AND at least one target is not a SAFE_DIRS basename.
# `rm -f file`, `rm -r dir`, `rm -rf node_modules` pass. `rm` is matched only
# as a command word (never as a substring), and `git rm` is deliberately
# exempt because it is not filesystem-destructive.
#
# The hook reads {"tool_input":{"command":"..."}} on stdin and exits 0 (allow)
# or 2 (block). The rm rule does not consult git, so scenarios run from a
# plain scratch directory.
#
# Prereq: jq (the hook hard-requires it). SKIPS gracefully otherwise.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"; _flow_assert_pass "SKIP: jq not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-destructive.sh"

BDR_DIR=$(mktemp -d -t flow-bdr.XXXXXX)
_bdr_cleanup() { [ -n "${BDR_DIR:-}" ] && rm -rf "$BDR_DIR" 2>/dev/null; }
trap _bdr_cleanup EXIT

# Run the hook from inside $BDR_DIR with <command>; returns the hook's exit code.
_run_hook() {
  local cmd="$1" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  ( cd "$BDR_DIR" && printf '{"tool_input":{"command":%s}}' "$json" | bash "$HOOK" ) >/dev/null 2>&1
}

# Same, but prints the hook's stderr (for message assertions).
_run_hook_stderr() {
  local cmd="$1" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  ( cd "$BDR_DIR" && printf '{"tool_input":{"command":%s}}' "$json" | bash "$HOOK" ) 2>&1 >/dev/null
}

# --- a lone -f or -r is bounded and must pass (the false-block the audit found)
_flow_test_begin "rm without recursive+force is allowed"
_run_hook "rm a.txt";        assert_exit 0 "$?" "rm a.txt allowed"
_run_hook "rm -f a.txt";     assert_exit 0 "$?" "rm -f a.txt allowed (force alone)"
_run_hook "rm -r dir";       assert_exit 0 "$?" "rm -r dir allowed (recursive alone)"
_run_hook "rm -v a.txt";     assert_exit 0 "$?" "rm -v a.txt allowed"
_run_hook "rm -rv dir";      assert_exit 0 "$?" "rm -rv dir allowed (no force)"
_run_hook "rm --recursive dir"; assert_exit 0 "$?" "rm --recursive dir allowed (no force)"
_run_hook "rm --force a.txt";   assert_exit 0 "$?" "rm --force a.txt allowed (no recursive)"

# --- safe-dir allowance survives
_flow_test_begin "recursive+force on SAFE_DIRS targets is allowed"
_run_hook "rm -rf node_modules";        assert_exit 0 "$?" "rm -rf node_modules allowed"
_run_hook "rm -rf ./node_modules/";     assert_exit 0 "$?" "relative path with trailing slash allowed"
_run_hook "rm -rf node_modules dist";   assert_exit 0 "$?" "multiple safe targets allowed"
_run_hook "rm -rf -- node_modules";     assert_exit 0 "$?" "-- terminator before a safe target allowed"
_run_hook "rm -rf node_modules 2>/dev/null"; assert_exit 0 "$?" "attached redirection is not a target"
_run_hook "rm -rf node_modules > /dev/null"; assert_exit 0 "$?" "bare redirection operator's file is not a target"

# --- every recursive+force spelling blocks on an unsafe target
_flow_test_begin "recursive+force on an unsafe target is blocked in every spelling"
_run_hook "rm -rf dir";                    assert_exit 2 "$?" "rm -rf blocked"
_run_hook "rm -fr dir";                    assert_exit 2 "$?" "rm -fr blocked"
_run_hook "rm -Rf dir";                    assert_exit 2 "$?" "rm -Rf blocked"
_run_hook "rm -rF dir";                    assert_exit 2 "$?" "rm -rF blocked"
_run_hook "rm -r -f dir";                  assert_exit 2 "$?" "rm -r -f blocked"
_run_hook "rm -f -r dir";                  assert_exit 2 "$?" "rm -f -r blocked"
_run_hook "rm -rv -f dir";                 assert_exit 2 "$?" "rm -rv -f blocked"
_run_hook "rm --recursive --force dir";    assert_exit 2 "$?" "rm --recursive --force blocked"
_run_hook "rm --force --recursive dir";    assert_exit 2 "$?" "rm --force --recursive blocked"
_run_hook "rm -r --force dir";             assert_exit 2 "$?" "rm -r --force blocked"
_run_hook "rm --recursive -f dir";         assert_exit 2 "$?" "rm --recursive -f blocked"
_run_hook "rm dir -rf";                    assert_exit 2 "$?" "flags after the target still count (GNU permutation)"
_run_hook "rm --rec --forc dir";           assert_exit 2 "$?" "GNU long-option prefixes blocked"
_run_hook "rm -rf /some/important/path";   assert_exit 2 "$?" "absolute path blocked"
_run_hook "rm -rf node_modules src";       assert_exit 2 "$?" "mixed safe + unsafe targets blocked"
_run_hook "rm -rf -- -weird";              assert_exit 2 "$?" "unsafe target after -- blocked"
_run_hook 'rm -rf "$DIR"';                 assert_exit 2 "$?" "unresolved variable target blocked (fail-safe)"
_run_hook "rm -rf *";                      assert_exit 2 "$?" "glob target blocked (not expanded by the hook)"

# --- compound commands and wrappers
_flow_test_begin "rm is found in compound commands and behind wrappers"
_run_hook "cd /tmp && rm -rf x";           assert_exit 2 "$?" "after && blocked"
_run_hook "make clean; rm -rf out";        assert_exit 2 "$?" "after ; blocked"
_run_hook "true || rm -rf out";            assert_exit 2 "$?" "after || blocked"
_run_hook "ls | xargs rm -rf";             assert_exit 2 "$?" "xargs rm -rf with no visible target blocked (cannot verify)"
_run_hook "rm -rf";                        assert_exit 2 "$?" "bare rm -rf with no operand blocked (cannot verify; harmless to refuse)"
_run_hook "find . -name x | xargs rm -rf /y"; assert_exit 2 "$?" "xargs rm -rf with an unsafe target blocked"
_run_hook "sudo rm -rf /etc/x";            assert_exit 2 "$?" "sudo rm -rf blocked"
_run_hook "/bin/rm -rf /etc/x";            assert_exit 2 "$?" "absolute rm binary blocked"
_run_hook '\rm -rf /etc/x';                assert_exit 2 "$?" "alias-bypass \\rm blocked"
_run_hook '(rm -rf /etc/x)';               assert_exit 2 "$?" "subshell rm blocked"
_run_hook 'echo $(rm -rf /etc/x)';         assert_exit 2 "$?" "command-substitution rm blocked"
_run_hook "rm -f a.txt && rm -rf node_modules"; assert_exit 0 "$?" "two harmless rms in one command allowed"

# --- rm as a substring or as a git subcommand is not the filesystem rm
_flow_test_begin "rm is matched only as a command word; git rm is exempt"
_run_hook "git rm -r --cached dir";        assert_exit 0 "$?" "git rm -r --cached allowed"
_run_hook "git rm -rf dir";                assert_exit 0 "$?" "git rm -rf allowed (tracked files, recoverable)"
_run_hook "npm run rm-cache";              assert_exit 0 "$?" "rm-cache is not rm"
_run_hook "npm run rm-cache -- -rf x";     assert_exit 0 "$?" "rm-cache with -rf args is not rm"
_run_hook "perform -rf x";                 assert_exit 0 "$?" "perform is not rm"
_run_hook "git -C dir rm -rf x";           assert_exit 2 "$?" "only the immediate git rm form is exempt"
_run_hook "git rm -r --cached dir && rm -rf src"; assert_exit 2 "$?" "exempt git rm does not shield a later real rm"

# --- message wording
_flow_test_begin "block message names the rule and the remedy"
ERR=$(_run_hook_stderr "rm -rf /some/important/path")
assert_contains "BLOCKED: Destructive rm -rf" "$ERR" "message starts with the BLOCKED prefix"
assert_contains "run manually if intended" "$ERR" "message points at the manual remedy"

# --- neighbouring rules are untouched
_flow_test_begin "other destructive rules still fire"
_run_hook "git reset --hard HEAD~1";       assert_exit 2 "$?" "git reset --hard still blocked"
_run_hook "git clean -fd";                 assert_exit 2 "$?" "git clean -f still blocked"
_run_hook "git checkout -- .";             assert_exit 2 "$?" "git checkout -- . still blocked"
_run_hook "git status";                    assert_exit 0 "$?" "git status allowed"
