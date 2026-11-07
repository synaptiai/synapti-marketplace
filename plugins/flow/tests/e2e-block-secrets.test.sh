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
#   K11 an interpreter option that is not an inline script (-Wignore, -u), or
#      a word after the script file (`script.py -e prod`), is read as an
#      inline script, so a script's argument is refused; or an inline script
#      reached through a bundle (-pie, -ne), after -pi or after an option
#      value (-I lib) is missed, or one holding a literal secret is allowed
#   K12 a URL in a text command (echo into a README or an .env.example) is
#      refused, or one with a secret given to a sender, a setter or a git
#      URL subcommand (clone, remote add, fetch) is allowed
#   K13 gh api is judged on a field's value instead of its name, so a
#      comment body naming a token is refused, or a secrets endpoint field
#      (encrypted_value, token) is allowed; or aws, gcloud and az are
#      senders in their log searches, so a search for the pattern is
#      refused, or their secret-storing subcommands are allowed
#   K14 a global option before the subcommand (gh -R o/r, gh --repo o/r, npm
#      --location project) is read as the subcommand, so gh secret set, gh
#      api and npm config set are no longer judged as senders
#   K15 perl's or ruby's -i backup extension (-i.save, -pi.bak, -i.pre) is
#      read as option letters, so its `e` takes the next word as the inline
#      script and the real script after it is never checked
#   K16 the URL rule is kept to senders, setters and git's fetch and push
#      subcommands, so a URL with a password given to git ls-remote, git
#      config, pip, npm install or svn, or as a gh api field value, is
#      allowed; or it is applied to a text command (echo into a README or an
#      .env.example, git log --grep) or to a line of a heredoc body nothing
#      runs (cat <<EOF > notes.md), which only names the URL; or a body
#      piped into a shell is read as text
#   K17 aws, gcloud and az are senders only for their secret-storing
#      subcommands, so a literal password set as a function's or an app's
#      environment (lambda, run deploy, functions deploy, webapp appsettings)
#      is allowed; or they are senders in their log and monitoring searches,
#      where the value is a pattern; or npm set, npm's alias for config set,
#      is not a sender

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

# --- an interpreter's own inline-script options only (K11) -------------------
_case sec-python-wopt 'python3 -Wignore scripts/scan_logs.py "token=abcdefghij"' allowed "-Wignore is a warning filter, not an inline script (K11)"
_case sec-python-u 'python3 -u scripts/scan_logs.py --note "token=abcdefghij"' allowed "-u is not an inline script (K11)"
_case sec-python-after-file 'python3 scripts/scan_logs.py -e prod --pattern "token=abcdefghij"' allowed "a -e after the script file belongs to the script (K11)"
_case sec-python-c-argv 'python3 -c "import sys; print(sys.argv)" "token=abcdefghij"' allowed "a word after an inline script is the script's argument (K11)"
_case sec-python-environ "python3 -c \"import os; os.environ['API_TOKEN']='abcdefghijk'\"" refused "a literal token set in an inline python script (K11)"
_case sec-python-header-key "python3 -c \"h={'Authorization': 'Bearer abcdefghijklmnopqrstuvwxyz'}\"" refused "a literal auth header as a dict key in an inline python script (K11)"
_case sec-python-bundle "python3 -Bc \"x='password=abcdefghijk'\"" refused "an inline script after a bundle ending in c (K11)"
_case sec-node-e-body "node -e \"fetch(u,{body:'password=abcdefghijk'})\"" refused "a literal password in an inline node script (K11)"
_case sec-node-require-print "node -r dotenv/config --print \"process.env.X='token=abcdefghijk'\"" refused "an inline node script after -r and its module (K11)"
_case sec-perl-pi-e 'perl -pi -e "s/token=abcdefghij/token=REDACTED/" config.ini' refused "a literal token in a perl -pi -e redaction (K11)"
_case sec-perl-pie 'perl -pie "s/token=abcdefghij/token=REDACTED/" config.ini' refused "a literal token after the -pie bundle (K11)"
_case sec-perl-ne "perl -ne 'print if /password=abcdefghij/' app.log" refused "a literal password in a perl -ne script (K11)"
_case sec-perl-include 'perl -I lib -e "print q(token=abcdefghijk)"' refused "an inline perl script after -I and its directory (K11)"
_case sec-ruby-e "ruby -r json -e \"x='password=abcdefghijk'\"" refused "an inline ruby script after -r and its library (K11)"
_case sec-ruby-file 'ruby tools/check.rb -e "token=abcdefghij"' allowed "a -e after the ruby script file belongs to the script (K11)"
_case sec-sed-redact 'sed -i "s/token=abcdefghij/token=REDACTED/" config.ini' allowed "sed, the redaction the README suggests (K11)"

# --- the URL rule, for commands that send or set only (K12) ------------------
_case sec-echo-env-example 'echo "DATABASE_URL=postgres://user:password@localhost:5432/app" >> .env.example' allowed "an example URL echoed into .env.example (K12)"
_case sec-echo-readme-url 'echo https://deploy:YOUR_TOKEN@github.com/org/repo.git >> README.md' allowed "a placeholder URL documented in a README (K12)"
_case sec-git-log-url 'git log --grep "https://deploy:abcdefghijk@x.example"' allowed "git log searching for a URL sends nothing (K12)"
_case sec-psql-url 'psql postgres://admin:abcdefghijk@db.example/app' refused "a password in the URL psql connects to (K12)"
_case sec-curl-url 'curl "https://x.example/api?access_token=abcdefghijk"' refused "a token in the query of a URL curl fetches (K12)"
_case sec-git-remote-add 'git remote add origin https://deploy:abcdefghijk@x.example/repo.git' refused "git remote add with a password in the URL (K12)"
_case sec-git-C-fetch 'git -C app fetch "https://x.example/repo.git?token=abcdefghijk"' refused "git fetch after -C with a token in the URL (K12)"
_case sec-export-url 'export DATABASE_URL=postgres://admin:abcdefghijk@db.example/app' refused "export of a URL with a password (K12)"
_case sec-assign-url 'DATABASE_URL=postgres://admin:abcdefghijk@db.example/app ./run.sh' refused "an assignment of a URL with a password in command position (K12)"

# --- gh api fields by name; aws, gcloud and az by subcommand (K13) -----------
_case sec-gh-api-body 'gh api repos/o/r/issues/5/comments -f body="rotated the token=abcdefghij"' allowed "a comment body that names a token (K13)"
_case sec-gh-api-encrypted 'gh api -X PUT repos/o/r/actions/secrets/X -f encrypted_value=abcdefghijklmnop -f key_id=0123456789012345' refused "gh api with a literal encrypted_value (K13)"
_case sec-gh-api-token-field 'gh api repos/o/r/hooks -f token=abcdefghijk' refused "gh api with a literal token field (K13)"
_case sec-gh-api-raw-field 'gh api repos/o/r/hooks --raw-field password=abcdefghijk' refused "gh api with a literal password --raw-field (K13)"
_case sec-gh-api-field-env 'gh api repos/o/r/hooks -f token="$HOOK_TOKEN"' allowed "gh api reading the field from the environment (K13)"
_case sec-aws-logs 'aws logs filter-log-events --log-group-name app --filter-pattern "token=abcdefghij"' allowed "aws searching logs for the pattern stores nothing (K13)"
_case sec-aws-secretsmanager 'aws --profile prod secretsmanager create-secret --name db --secret-string "password=abcdefghijk"' refused "aws secretsmanager create-secret with a literal password (K13)"
_case sec-aws-ssm-region 'aws --region eu-west-1 ssm put-parameter --name db --type SecureString --value "token=abcdefghijk"' refused "aws ssm put-parameter after a global option, with a literal token (K13)"
_case sec-gcloud-logging 'gcloud logging read "textPayload:token=abcdefghij"' allowed "gcloud reading logs for the pattern stores nothing (K13)"
_case sec-gcloud-secrets 'printf "token=abcdefghijk" | gcloud secrets versions add db --data-file=-' refused "text piped into gcloud secrets (K13)"
_case sec-az-keyvault 'az keyvault secret set --vault-name v --name db --value "password=abcdefghijk"' refused "az keyvault secret set with a literal password (K13)"
_case sec-az-monitor 'az monitor log-analytics query -w w --analytics-query "token=abcdefghij"' allowed "az querying logs for the pattern stores nothing (K13)"
_case sec-fly-secrets 'fly secrets set API_TOKEN=abcdefghijk' refused "fly secrets set stays a sender (K13)"

# --- global options before the subcommand (K14) ------------------------------
_case sec-gh-R-secret 'gh -R o/r secret set DEPLOY --body "token=abcdefghijklmnop"' refused "gh secret set after -R o/r (K14)"
_case sec-gh-repo-api 'gh --repo o/r api repos/o/r/actions/secrets -f token=abcdefghijk' refused "gh api after --repo o/r (K14)"
_case sec-npm-location 'npm --location project config set //r/:_authToken=abcdefghijk' refused "npm config set after --location project (K14)"
_case sec-gh-R-issue 'gh -R o/r issue create --title leak --body "the token=abcdefghij was committed"' allowed "gh issue create after -R o/r only files text (K14)"

# --- perl's and ruby's -i backup extension (K15) ----------------------------
_case sec-perl-pi-ext "perl -pi.save -e 's/password=abcdefghij/x/' f" refused "an inline perl script after -pi.save (K15)"
_case sec-perl-i-ext-pe "perl -i.save -pe 's/password=abcdefghij/x/' f" refused "an inline perl script in the -pe after -i.save (K15)"
_case sec-perl-i-pre "perl -i.pre -pe 's/password=abcdefghij/x/' f" refused "the e of -i.pre is the extension's, not -e (K15)"
_case sec-ruby-i-ext "ruby -i.save -pe 'sub(/password=abcdefghij/,\"x\")' f" refused "an inline ruby script in the -pe after -i.save (K15)"
_case sec-perl-i-ext-file 'perl -i.bak tools/redact.pl "token=abcdefghij" f' allowed "a word after the perl script file belongs to the script (K15)"

# --- the URL rule for every command but a text command (K16) ----------------
_case sec-git-log-userinfo 'git log --grep "https://u:abcdefghijk@x"' allowed "git log searching for a URL with a password sends nothing (K16)"
_case sec-git-ls-remote 'git ls-remote https://deploy:abcdefghijk@x.example/repo.git' refused "git ls-remote with a password in the URL (K16)"
_case sec-git-config-url 'git config remote.origin.url https://deploy:abcdefghijk@x.example/r.git' refused "git config storing a URL with a password (K16)"
_case sec-pip-index 'pip install --index-url https://user:abcdefghijk@pypi.example/simple pkg' refused "pip with a password in its index URL (K16)"
_case sec-pip-git 'pip install git+https://deploy:abcdefghijk@github.com/o/r.git' refused "pip installing from a git URL with a password (K16)"
_case sec-npm-install-url 'npm install https://deploy:abcdefghijk@x.example/pkg.tgz' refused "npm install from a URL with a password (K16)"
_case sec-svn-checkout 'svn checkout https://deploy:abcdefghijk@svn.example/r' refused "svn checkout with a password in the URL (K16)"
_case sec-gh-api-url-query 'gh api repos/o/r/hooks -f config[url]="https://hook.example/in?token=abcdefghijk"' refused "a gh api field value that is a URL with a token in its query (K16)"
_case sec-gh-api-url-userinfo 'gh api repos/o/r/hooks -f config[url]=https://u:abcdefghijk@hook.example/in' refused "a gh api field value that is a URL with a password (K16)"
_case sec-cat-url 'cat docs/setup.md | grep "https://deploy:abcdefghijk@x.example"' allowed "cat and grep only read and search for a URL (K16)"
_case sec-gh-issue-url 'gh issue comment 5 --body "it was cloned from https://deploy:abcdefghijk@x.example"' allowed "gh issue comment only files text naming a URL (K16)"
_case sec-sudo-git-log 'sudo git log --grep "https://u:abcdefghijk@x"' allowed "git log through sudo only searches (K16)"
_case sec-heredoc-notes "cat <<'EOF' > notes.md
cloned from https://deploy:abcdefghijk@x.example
EOF" allowed "a heredoc body cat writes to a file is text, not a command (K16)"
_case sec-heredoc-commit "git commit -F - <<'EOF'
fix: rotate the deploy URL https://deploy:abcdefghijk@x.example
EOF" allowed "a commit message read from a heredoc is text (K16)"
_case sec-heredoc-bash "cat <<'EOF' | bash
pip install https://deploy:abcdefghijk@x.example/pkg.tgz
EOF" refused "a heredoc body piped into bash is run, so its pip install is judged (K16)"

# --- aws, gcloud and az send, but for their log searches (K17) --------------
_case sec-aws-lambda-env 'aws lambda update-function-configuration --environment "Variables={DB_PASSWORD=abcdefghijk}"' refused "a literal password set as a lambda's environment (K17)"
_case sec-gcloud-run-env 'gcloud run deploy api --set-env-vars DB_PASSWORD=abcdefghijk' refused "a literal password set as a Cloud Run service's environment (K17)"
_case sec-gcloud-functions-env 'gcloud functions deploy f --set-env-vars API_TOKEN=abcdefghijk' refused "a literal token set as a function's environment (K17)"
_case sec-az-appsettings 'az webapp config appsettings set --settings DB_PASSWORD=abcdefghijk' refused "a literal password set as a web app's settings (K17)"
_case sec-aws-region-logs 'aws --region eu-west-1 logs filter-log-events --log-group-name app --filter-pattern "token=abcdefghij"' allowed "aws searching logs after --region and its value (K17)"
_case sec-aws-cloudwatch 'aws cloudwatch get-metric-data --cli-input-json "token=abcdefghij"' allowed "aws cloudwatch is a monitoring search (K17)"
_case sec-gcloud-project-logging 'gcloud --project p logging read "textPayload:token=abcdefghij"' allowed "gcloud reading logs after --project and its value (K17)"
_case sec-az-monitor-q "az monitor log-analytics query -q \"x | where m has 'token=abcdefghij'\"" allowed "az querying logs with -q for the pattern (K17)"
_case sec-npm-set 'npm set //registry.example/:_authToken=abcdefghijk' refused "npm set, the alias of npm config set (K17)"
_case sec-npm-location-set 'npm --location project set //r/:_authToken=abcdefghijk' refused "npm set after --location project (K17)"
