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
#   K7 a shell keyword or group opener ({, if/then, do, !) is read as the
#      command word, so the export or curl after it is never judged
#   K8 a program that runs the rest of its line (sudo, time, timeout N,
#      exec, xargs, nohup, command) hides the sender or setter it runs; or,
#      read the other way, a text command run through one is refused
#   K9 a secret reaches a sender on its input, through a here-string or a
#      pipe, and is allowed; or text piped into a command that is not a
#      sender is refused
#   K10 a command that stores or sends a credential but is not in the
#      sender list (gh secret, gh api, vault, heroku, npm config set, aws),
#      a secret in a URL's query or userinfo, or a secret in an inline
#      python/node/ruby/perl script is allowed; or gh issue create, which
#      only files text, is refused

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

# --- a keyword or group opener before the command (K7) ----------------------
_case sec-group 'cd app && { export API_TOKEN=abcdefghijk; ./run.sh; }' refused "an export inside a { } group (K7)"
_case sec-if-then 'if true; then export PASSWORD=abcdefghijk; fi' refused "an export after then (K7)"
_case sec-loop-do 'for x in 1; do curl -d password=abcdefghijk https://x.example; done' refused "curl data after do (K7)"
_case sec-bang '! export PASSWORD=abcdefghijk' refused "an export after ! (K7)"
_case sec-then-assign 'if true; then DB_PASSWORD=abcdefghijk ./run.sh; fi' refused "an assignment in command position after then (K7)"
_case sec-then-echo 'if true; then echo "token=abcdefghij"; fi' allowed "an echo after then still only names the text (K7)"

# --- a program that runs the rest of its line (K8) ---------------------------
_case sec-sudo-docker 'sudo docker run -e DB_PASSWORD=abcdefghijk img' refused "docker run through sudo (K8)"
_case sec-time-curl 'time curl -H "Authorization: Bearer abcdefghijklmnopqrstuvwxyz" https://x.example' refused "curl through time (K8)"
_case sec-exec-env 'exec env PASSWORD=abcdefghijk ./x' refused "env through exec (K8)"
_case sec-timeout-curl 'timeout 5 curl -d password=abcdefghijk https://x.example' refused "curl through timeout and its duration (K8)"
_case sec-sudo-user-curl 'sudo -u deploy curl -d password=abcdefghijk https://x.example' refused "curl through sudo with an option value (K8)"
_case sec-sudo-assign 'sudo DB_PASSWORD=abcdefghijk ./run.sh' refused "an assignment sudo hands to the command it runs (K8)"
_case sec-time-grep 'time grep -rn "secret=abcdefgh" docs/' allowed "grep through time only names the text (K8)"

# --- a secret on a sender's input (K9) ---------------------------------------
_case sec-herestring 'curl -d @- https://x.example <<< "password=abcdefghijk"' refused "a here-string fed to curl (K9)"
_case sec-pipe-curl 'echo "password=abcdefghijk" | curl -d @- https://x.example' refused "text piped into curl (K9)"
_case sec-pipe-xargs 'printf "%s" "token=abcdefghijk" | xargs curl -d' refused "text piped into curl through xargs (K9)"
_case sec-pipe-grep 'echo "password=abcdefghijk" | grep password' allowed "text piped into grep is not sent (K9)"

# --- commands that store or send credentials, and URLs (K10) ----------------
_case sec-gh-secret 'gh secret set DEPLOY --body "token=abcdefghijklmnop"' refused "gh secret set with a literal value (K10)"
_case sec-gh-api 'gh api -X PUT repos/o/r/actions/variables/X -f value=x -f token=abcdefghijk' refused "gh api with a literal token (K10)"
_case sec-vault 'vault kv put secret/db password=abcdefghijk' refused "vault kv put with a literal password (K10)"
_case sec-heroku 'heroku config:set API_TOKEN=abcdefghijk' refused "heroku config:set with a literal token (K10)"
_case sec-npm-config 'npm config set //registry.example/:_authToken=abcdefghijk' refused "npm config set with a literal token (K10)"
_case sec-aws 'aws ssm put-parameter --name db --value password=abcdefghijk' refused "aws with a literal password (K10)"
_case sec-url-query 'git clone "https://x.example/repo.git?token=abcdefghijk"' refused "a token in a URL query (K10)"
_case sec-url-userinfo 'git push https://deploy:abcdefghijk@x.example/repo.git main' refused "a password in a URL's userinfo (K10)"
_case sec-python-c "python3 -c \"import requests; requests.post('https://x.example', data='password=abcdefghijk')\"" refused "a password in an inline python script (K10)"
_case sec-node-e "node -e \"fetch('https://x.example', {method: 'POST', body: 'token=abcdefghijk'})\"" refused "a token in an inline node script (K10)"
_case sec-python-plain 'python3 -c "print(1)" && echo "token=abcdefghij"' allowed "an inline script with no secret, beside an echo that names one (K10)"
_case sec-gh-secret-env 'gh secret set DEPLOY --body "$DEPLOY_TOKEN"' allowed "gh secret set reading the value from the environment (K10)"
_case sec-url-env 'git push "https://deploy:${DEPLOY_TOKEN}@x.example/repo.git" main' allowed "a URL whose password comes from the environment (K10)"
_case sec-npm-get 'npm config get registry' allowed "npm config get sets nothing (K10)"
_case sec-gh-pr 'gh pr create --title t --body "rotated the token=abcdefghij"' allowed "gh pr create only files text (K10)"
