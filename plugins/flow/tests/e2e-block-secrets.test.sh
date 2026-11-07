# shellcheck shell=bash
# End-to-end: the secrets guard (hooks/scripts/block-secrets.sh) decides on how
# secret-shaped text is used, not on the fact that it appears (#241).
#
# Each scenario feeds the hook the PreToolUse payload Claude Code sends for a
# Bash call and reads its exit status (2 refuses). The artifact for each
# scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   K1 a command that only names a secret-shaped assignment in its text
#      (an issue about a leak, a README line, a grep, a commit message, an
#      echo) is refused
#   K2 export, a shell assignment, or a --password= option to a command being
#      run is allowed
#   K3 a literal token in a curl auth header is allowed, or curl reading the
#      token from the environment is refused
#   K4 a secret handed to a command that sends it (curl -d, docker -e) or to
#      a script run by a shell (bash -c "export ...") is allowed
#   K5 a payload with a backslash escape is rewritten before jq reads it
#      (echo), so the hook judges a different command
#   K6 when the command parser cannot be loaded, the hook allows instead of
#      falling back to the whole-line check

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

HOOK=hooks/scripts/block-secrets.sh
_payload() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

# _case <name> <command> <refused|allowed> <purpose>
_case() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$4"
  e2e_repo feature/issue-241-e2e
  e2e_run_hook "$HOOK" "$(_payload "$2")"
  case "$3" in
    refused) e2e_expect_equal 2 "$E2E_RC" "the hook's exit status (2 refuses)"; e2e_expect_err "BLOCKED" ;;
    allowed) e2e_expect_equal 0 "$E2E_RC" "the hook's exit status (0 allows)" ;;
  esac
  e2e_expect_clean_edges
}

# --- the five commands from #241 that only name the text (K1) ---------------
_case sec-issue 'gh issue create --title "leak" --body "the token=abcdefghij was committed"' allowed "filing an issue about a leaked token"
_case sec-readme 'printf "%s\n" "set it as password=CHANGEME" >> README.md' allowed "documenting the pattern in a README"
_case sec-echo 'echo "api_key=your-key-here-0000"' allowed "echoing an example"
_case sec-grep 'grep -rn "secret=abcdefgh" docs/' allowed "searching docs for the pattern"
_case sec-commit 'git commit -m "rotate password=abcdefghij in prod"' allowed "a commit message about a rotation"

# --- the three from #241 that place a secret inline (K2, K3) ----------------
_case sec-export 'export PASSWORD=abcdefghijklmnop' refused "export of a literal password"
_case sec-curl-header 'curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz" https://x.example' refused "a literal token in a curl auth header"
_case sec-mysql 'mysql -u root --password=abcdefghij' refused "a --password= option to a command being run"

# --- more of the same shapes ------------------------------------------------
_case sec-curl-env 'curl -H "Authorization: Bearer $TOKEN" https://x.example' allowed "curl reading the token from the environment (K3)"
_case sec-assign-prefix 'DB_PASSWORD=abcdefghij ./run.sh' refused "an assignment in front of a command (K2)"
_case sec-assign-alone 'cd app && API_TOKEN=abcdefghijk' refused "an assignment after a separator (K2)"
_case sec-env 'env GITHUB_TOKEN=abcdefghijk ./deploy.sh' refused "env setting a token for a command (K2)"
_case sec-curl-data 'curl -d "password=abcdefghijk" https://x.example' refused "a password sent as curl data (K4)"
_case sec-docker-env 'docker run -e DB_PASSWORD=abcdefghijk img' refused "a password passed into a container (K4)"
_case sec-bash-c 'bash -c "export API_KEY=abcdefghijk"' refused "an export inside a script run by bash -c (K4)"
_case sec-wget-header 'wget --header="X-API-Key: abcdefghijklmnopqrstuvwxyz" https://x.example' refused "a literal API key in a wget header (K3)"
_case sec-comment 'ls # PASSWORD=abcdefghijk' allowed "a comment that names the pattern"
_case sec-backslash 'printf "a\\nb" && echo "token=abcdefghij"' allowed "a payload with a backslash escape is judged as written (K5)"
_case sec-var 'export PASSWORD=$DB_PASSWORD' allowed "an export that reads the value from another variable"

# --- the parser cannot be loaded (K6) ---------------------------------------
_flow_test_begin "sec-no-parser"
e2e_new sec-no-parser
e2e_describe "lib/command-parse.sh is missing: the hook falls back to the whole-line check and refuses what it always refused"
e2e_repo feature/issue-241-e2e
E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
cp -R "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" && rm -f "$E2E_ACTIVE_PLUGIN/hooks/scripts/lib/command-parse.sh"
printf 'plugin for this scenario: a copy without hooks/scripts/lib/command-parse.sh\n' | _e2e_art
e2e_run_hook "$HOOK" "$(_payload 'echo "api_key=your-key-here-0000"')"
e2e_expect_equal 2 "$E2E_RC" "the hook's exit status (2 refuses)"
e2e_expect_clean_edges
