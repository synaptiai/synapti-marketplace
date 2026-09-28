# shellcheck shell=bash
# plugins/flow/tests/lib/e2e.sh — end-to-end harness for flow's command blocks
# and hooks. Sourced by the e2e-*.test.sh files after assert.sh, as
#   source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0
# A test file that sources it must not set its own EXIT trap: the harness's
# trap is what removes the scratch root.
#
# A scenario runs the real code the way Claude Code runs it: a `!` fence taken
# from the shipped command file, with the invocation's arguments substituted
# into its text, or a hook script fed a hook payload. Claude Code runs fences
# with the user's shell, which on macOS is zsh, so a fence runs under zsh when
# zsh is installed and again under bash, and the two outputs must match. Each
# scenario runs inside a scratch git repository with its own HOME. The only
# fakes are the programs at the edge: `gh` answers from fixture files, and
# `claude` must never be called.
#
# Every scenario writes one artifact file. It holds the repository commit,
# whether the plugin tree had uncommitted changes, a sha256 over the plugin's
# code, the sha256 of the block that ran, every input, the output, and each
# expectation with its result. Nothing in it depends on the clock, so two runs
# on the same commit write the same file. Artifacts go to FLOW_E2E_ARTIFACT_DIR
# when it is set (CI sets it and uploads them). Otherwise they go to the scratch
# root, which is removed at exit unless an expectation failed; then it is kept
# and its path printed.
#
# E2E_PLUGIN_DIR points the harness at another copy of the plugin, so a mutated
# copy can be run to check that a scenario fails for its own reason.

E2E_PLUGIN_DIR="${E2E_PLUGIN_DIR:-$REPO_ROOT/plugins/flow}"
E2E_REPO_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')

_e2e_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
_e2e_sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

# One sha256 over every code file the plugin ships, so the artifact names the
# code that ran even when it differs from the commit.
_e2e_plugin_digest() {
  (
    cd "$1" 2>/dev/null || { printf 'unreadable'; exit 0; }
    find bin hooks commands skills agents system-one -type f ! -path '*/__pycache__/*' 2>/dev/null | LC_ALL=C sort |
      while IFS= read -r f; do printf '%s  %s\n' "$(_e2e_sha256 "$f")" "$f"; done |
      _e2e_sha256_stdin
  )
}

# One scratch root, created in the calling shell so the EXIT trap can remove
# it. Helpers called as $(...) run in a subshell and cannot add to a cleanup
# list, so everything goes under this root instead.
E2E_ROOT=$(mktemp -d -t flow-e2e.XXXXXX 2>/dev/null) || E2E_ROOT=""
if [ -z "$E2E_ROOT" ] || [ ! -d "$E2E_ROOT" ]; then
  _flow_assert_fail "mktemp -d failed; cannot create the e2e scratch root"
  return 1
fi
E2E_KEEP=0
# Stub servers started by e2e_stub_start, one pid per line. Every scenario's
# stubs are stopped when the next scenario starts and again at exit; each stub
# also exits by itself after its lifetime, in case neither runs.
_e2e_stop_stubs() {
  local pid
  [ -f "$E2E_ROOT/stub.pids" ] || return 0
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done < "$E2E_ROOT/stub.pids"
  : > "$E2E_ROOT/stub.pids"
}
_e2e_cleanup() {
  _e2e_stop_stubs
  if [ "$E2E_KEEP" = 1 ]; then
    printf 'e2e: an expectation failed; artifacts kept in %s\n' "$E2E_ARTIFACT_DIR" >&2
    [ -n "${FLOW_E2E_ARTIFACT_DIR:-}" ] && rm -rf "$E2E_ROOT" 2>/dev/null
  else
    rm -rf "$E2E_ROOT" 2>/dev/null
  fi
}
trap _e2e_cleanup EXIT
E2E_ARTIFACT_DIR="${FLOW_E2E_ARTIFACT_DIR:-$E2E_ROOT/artifacts}"
if ! mkdir -p "$E2E_ARTIFACT_DIR"; then
  _flow_assert_fail "cannot create the artifact directory $E2E_ARTIFACT_DIR"
  return 1
fi

if [ "$E2E_PLUGIN_DIR" = "$REPO_ROOT/plugins/flow" ]; then
  E2E_PLUGIN_LABEL="plugins/flow in this repository"
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- plugins/flow 2>/dev/null)" ]; then
    E2E_PLUGIN_LABEL="$E2E_PLUGIN_LABEL, with uncommitted changes"
  fi
else
  E2E_PLUGIN_LABEL="a copy at $E2E_PLUGIN_DIR"
fi
E2E_PLUGIN_DIGEST=$(_e2e_plugin_digest "$E2E_PLUGIN_DIR")

# The shells a fence runs under: zsh first when installed, because that is the
# shell Claude Code uses on macOS, then bash.
E2E_FENCE_SHELLS="bash"
command -v zsh >/dev/null 2>&1 && E2E_FENCE_SHELLS="zsh bash"

# e2e_new <scenario-name> — a fresh scratch directory with a HOME, a stub bin
# and a gh fixture directory. Sets E2E_DIR, E2E_HOME, E2E_BIN, E2E_GH, and
# E2E_ARTIFACT (the scenario's artifact file, started here). Clears E2E_REPO,
# so a scenario that never calls e2e_repo cannot run in a previous one's.
e2e_new() {
  _e2e_stop_stubs
  E2E_NAME="$1"
  E2E_DIR="$E2E_ROOT/$1"
  E2E_HOME="$E2E_DIR/home"
  E2E_BIN="$E2E_DIR/bin"
  E2E_GH="$E2E_DIR/gh"
  E2E_REPO=""
  E2E_ACTIVE_PLUGIN="$E2E_PLUGIN_DIR"
  mkdir -p "$E2E_HOME" "$E2E_BIN" "$E2E_GH"
  : > "$E2E_DIR/masks"
  : > "$E2E_GH/unhandled.log"
  : > "$E2E_DIR/claude-calls.log"

  # gh answers the calls flow's commands make from files in $E2E_GH. Any other
  # call is logged and exits 99, and every scenario asserts that log is empty:
  # a stub that answered unknown calls with nothing would make every gate fail
  # closed, and "expected blocked" would pass for the wrong reason.
  cat > "$E2E_BIN/gh" <<'STUB'
#!/usr/bin/env bash
d="${E2E_GH:?}"
jqexpr=""; args=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) jqexpr="$2"; shift 2 ;;
    --paginate) shift ;;
    *) args="$args${args:+ }$1"; shift ;;
  esac
done
case "$args" in
  "api user") f=user ;;
  "auth status") f=auth ;;
  "issue view "*) n=${args#issue view }; f=issue-${n%% *} ;;
  "repo view --json "*) f=repo ;;
  "pr list --state open --limit 100 --json number,author,assignees") f=prs ;;
  "api repos/"*"/issues/"*"/comments") n=${args%/comments}; f=comments-${n##*/} ;;
  "api repos/"*"/pulls/"*"/reviews") n=${args%/reviews}; f=reviews-${n##*/} ;;
  *) printf 'unhandled: %s\n' "$args" >> "$d/unhandled.log"; exit 99 ;;
esac
# Real gh prints the error body on stdout and the message on stderr.
if [ -e "$d/$f.fail" ]; then echo '{"message":"Bad Gateway","status":"502"}'; echo "gh: HTTP 502: Bad Gateway" >&2; exit 1; fi
if [ ! -f "$d/$f.json" ]; then printf 'no fixture %s.json for: %s\n' "$f" "$args" >> "$d/unhandled.log"; exit 99; fi
if [ -n "$jqexpr" ]; then jq -r "$jqexpr" "$d/$f.json"; else cat "$d/$f.json"; fi
STUB
  # The goal judge: by default it must never run, and any call is logged and
  # fails. A scenario that needs a verdict writes it with e2e_judge_says, and
  # the calls are then logged to judge-calls.log instead.
  cat > "$E2E_BIN/claude" <<'STUB'
#!/usr/bin/env bash
if [ -f "${E2E_DIR:?}/judge-response.json" ]; then
  printf 'call\n' >> "$E2E_DIR/judge-calls.log"
  cat "$E2E_DIR/judge-response.json"
  exit 0
fi
printf '%s\n' "$*" >> "$E2E_DIR/claude-calls.log"
exit 99
STUB
  # The evaluator refuses to run without timeout(1); macOS has none by default.
  cat > "$E2E_BIN/timeout" <<'STUB'
#!/usr/bin/env bash
shift
exec "$@"
STUB
  chmod +x "$E2E_BIN/gh" "$E2E_BIN/claude" "$E2E_BIN/timeout"

  E2E_ARTIFACT="$E2E_ARTIFACT_DIR/$1.txt"
  {
    printf 'scenario: %s\n' "$1"
    printf 'repository commit: %s\n' "$E2E_REPO_SHA"
    printf 'plugin: %s\n' "$E2E_PLUGIN_LABEL"
    printf 'plugin code sha256: %s\n' "$E2E_PLUGIN_DIGEST"
  } > "$E2E_ARTIFACT"
}

# e2e_describe <text> — one line saying what the scenario sets up and why.
e2e_describe() { printf 'purpose: %s\n' "$1" | _e2e_art; }

# Git settings and variables from the caller must not reach a scratch
# repository: an inherited GIT_DIR would put its commit in the real one.
_e2e_git_env() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_ATTR_SOURCE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  export HOME="$E2E_HOME" GIT_CONFIG_NOSYSTEM=1
}

# e2e_repo <branch> — a git repository at $E2E_DIR/repo with one commit, on
# <branch>. The commit matters: on an unborn branch git reports no branch name,
# and branch-scoped goal lookup then takes a different path.
e2e_repo() {
  E2E_REPO="$E2E_DIR/repo"
  mkdir -p "$E2E_REPO"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git init -q
    git config user.email e2e@example.invalid
    git config user.name e2e
    git config commit.gpgsign false
    printf 'e2e\n' > README.md
    git add README.md
    git commit -q -m init
    git checkout -q -b "$1"
  ) || _flow_assert_fail "$E2E_NAME: could not create the scratch repository"
}

# e2e_plugin_copy <file under the plugin> <new content> — run this scenario
# against a copy of the plugin with one file replaced. For scenarios about a
# helper failing, which no input to the real helper produces.
e2e_plugin_copy() {
  E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
  cp -R "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" || { _flow_assert_fail "$E2E_NAME: cannot copy the plugin"; return 0; }
  printf '%s\n' "$2" > "$E2E_ACTIVE_PLUGIN/$1"
  chmod +x "$E2E_ACTIVE_PLUGIN/$1"
  printf 'plugin for this scenario: a copy with %s replaced by: %s\n' "$1" "$(printf '%s' "$2" | tr '\n' ' ')" | _e2e_art
}

# e2e_judge_says <json> — the reply the goal judge (claude --print) gives, in
# the CLI's --output-format json shape, for every call from here on.
e2e_judge_says() {
  printf '%s\n' "$1" > "$E2E_DIR/judge-response.json"
  printf 'judge replies: %s\n' "$1" | _e2e_art
}

# e2e_gh_fixture <name> <json> — the answer gh gives for one call. Names:
# user, auth, repo, prs, issue-<n>, reviews-<pr>, comments-<pr>. e2e_gh_fail <name> makes that
# call exit 1 with an HTTP error, as real gh does.
e2e_gh_fixture() { printf '%s\n' "$2" > "$E2E_GH/$1.json"; }
e2e_gh_fail() { : > "$E2E_GH/$1.fail"; }

# _e2e_mask <text> — the text with every stub address replaced by the stub's
# name. A stub listens on a port the kernel picks, so an address written into
# an artifact would differ on every run.
_e2e_mask() {
  local text="$1" from to p_private="/private$E2E_ROOT" p_root="$E2E_ROOT"
  # The scratch root is named by a fixed token (reached as both /var/... and
  # /private/var/... on macOS); bash 3.2 needs the patterns in variables.
  text="${text//"$p_private"/<scratch>}"; text="${text//"$p_root"/<scratch>}"
  if [ -f "$E2E_DIR/masks" ]; then
    while IFS='	' read -r from to; do
      [ -n "$from" ] && text="${text//"$from"/$to}"
    done < "$E2E_DIR/masks"
  fi
  printf '%s' "$text"
}

# _e2e_art — append stdin to the scenario's artifact, masked, so nothing that
# changes between runs (a stub's port, the scratch root) reaches it. Every
# write to an artifact after its header goes through here.
_e2e_art() {
  local text
  # The x keeps trailing newlines, which $(...) would strip: an empty stdout
  # block is recorded as the blank line it is.
  text=$(cat; printf x)
  text=${text%x}
  text=$(_e2e_mask "$text"; printf x)
  printf '%s' "${text%x}" >> "$E2E_ARTIFACT"
}

# e2e_stub_start <name> <config json> — start a stub System One server
# (tests/lib/s1_stub.py; its header documents the config) for this scenario.
# Its address is e2e_stub_url <name>; e2e_stub_requests <name> counts the
# requests it received and e2e_stub_log <name> is the file that lists them.
e2e_stub_start() {
  local name="$1" dir="$E2E_DIR/stub-$1" i=0 port
  mkdir -p "$dir"
  printf '%s\n' "$2" > "$dir/config.json"
  : > "$dir/requests.jsonl"
  python3 "$REPO_ROOT/plugins/flow/tests/lib/s1_stub.py" --config "$dir/config.json" \
    --port-file "$dir/port" --log "$dir/requests.jsonl" --lifetime 60 >/dev/null 2>&1 &
  printf '%s\n' "$!" >> "$E2E_ROOT/stub.pids"
  while [ ! -s "$dir/port" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  if [ ! -s "$dir/port" ]; then
    _flow_assert_fail "$E2E_NAME: stub $name did not start"
    return 0
  fi
  port=$(cat "$dir/port")
  printf 'http://127.0.0.1:%s' "$port" > "$dir/url"
  printf '127.0.0.1:%s\t<stub %s>\n' "$port" "$name" >> "$E2E_DIR/masks"
  printf 'stub %s: %s\n' "$name" "$(_e2e_mask "$2")" | _e2e_art
}
e2e_stub_url() { cat "$E2E_DIR/stub-$1/url"; }
e2e_stub_log() { printf '%s' "$E2E_DIR/stub-$1/requests.jsonl"; }
e2e_stub_requests() { local n; n=$(wc -l < "$E2E_DIR/stub-$1/requests.jsonl"); printf '%s' "${n// /}"; }

# e2e_user_settings <json> — the user-level settings file
# ($HOME/.claude/settings.flow.json in the scenario's HOME).
e2e_user_settings() {
  mkdir -p "$E2E_HOME/.claude"
  printf '%s\n' "$1" > "$E2E_HOME/.claude/settings.flow.json"
  printf 'user settings: %s\n' "$(_e2e_mask "$1")" | _e2e_art
}

# e2e_run_bin [NAME=value ...] <script under the plugin> [arguments] — run a
# plugin script in the scratch repository, with the given environment
# variables set for it alone. Sets E2E_OUT, E2E_ERR, E2E_RC.
e2e_run_bin() {
  local envs=() script
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*) envs+=("$1"); shift ;;
      *) break ;;
    esac
  done
  script="$1"; shift
  {
    printf 'code: %s\n' "$script"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$script")"
    printf 'arguments: %s\n' "$*"
    [ "${#envs[@]}" -gt 0 ] && printf 'environment: %s\n' "${envs[*]}"
  } | _e2e_art
  _e2e_exec env ${envs[@]+"${envs[@]}"} "$E2E_ACTIVE_PLUGIN/$script" "$@"
  printf -- '--- expectations\n' | _e2e_art
}

# e2e_goal <id> <branch> <status> <must-pass command> [run_id] — write a FlowGoal
# into the scratch repo's .flow/goals, built from the schema-valid fixture.
e2e_goal() {
  mkdir -p "$E2E_REPO/.flow/goals"
  if ! python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" \
      "$E2E_REPO/.flow/goals/$1.goal.yaml" "$1" "$2" "$3" "$4" "${5:-}" <<'PY'
import sys, yaml
src, dst, gid, branch, status, cmd, run_id = sys.argv[1:8]
with open(src, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = gid
g["scope"]["branch"] = branch
if run_id:
    g["scope"]["run_id"] = run_id
g["lifecycle"]["status"] = status
ac = g["objective"]["acceptance_criteria"][0]
ac["verification_command"] = cmd
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  then
    _flow_assert_fail "$E2E_NAME: could not write goal $1"
  fi
  [ -f "$E2E_REPO/.flow/goals/$1.goal.yaml" ] || _flow_assert_fail "$E2E_NAME: goal $1 was not written"
}

# e2e_fence <command.md> <text on a line inside the fence> — print the `!` or
# bash fence of a command file that contains the text. The fence is found by a
# line inside it, not a line number, so the scenario follows the block if the
# file is edited around it.
e2e_fence() {
  awk -v m="$2" '
    /^```(!|bash)[[:space:]]*$/ { inb = 1; buf = ""; hit = 0; next }
    /^```/ && inb { inb = 0; if (hit) { printf "%s", buf; exit } next }
    inb { buf = buf $0 "\n"; if (index($0, m)) hit = 1 }' "$1"
}

# e2e_run_fence <command.md> <marker> [arguments] — run that fence in the
# scratch repo the way Claude Code does. The invocation's arguments are
# substituted into the text first, as Claude Code substitutes them: $ARGUMENTS
# is the whole argument string, and $ARGUMENTS[N] and $N are argument N
# (0-based), replaced only when that argument exists. So a fence that writes $1
# for a shell function's parameter receives the second argument instead. The
# block then runs under each shell in E2E_FENCE_SHELLS. Expectations apply to
# the first; every other shell must print the same stdout. Sets E2E_OUT,
# E2E_ERR, E2E_RC.
e2e_run_fence() {
  local md="$1" marker="$2" arg="${3:-}" src="$E2E_DIR/fence.sh" sh first="" first_out=""
  e2e_fence "$md" "$marker" > "$src.raw"
  if [ ! -s "$src.raw" ]; then
    _flow_assert_fail "$E2E_NAME: no fence in $(basename "$md") contains '$marker'"
    E2E_OUT=""; E2E_ERR=""; E2E_RC=127
    return 0
  fi
  if ! ARG="$arg" python3 -c '
import os, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
raw = os.environ["ARG"]
args = raw.split()
def nth(m):
    n = int(m.group(1))
    return args[n] if n < len(args) else m.group(0)
text = re.sub(r"\$ARGUMENTS\[(\d+)\]", nth, text)
text = text.replace("$ARGUMENTS", raw)
text = re.sub(r"\$(\d+)", nth, text)
sys.stdout.write(text)
' "$src.raw" > "$src"; then
    _flow_assert_fail "$E2E_NAME: argument substitution failed"
    E2E_OUT=""; E2E_ERR=""; E2E_RC=127
    return 0
  fi
  {
    printf 'code: %s (fence containing %s)\n' "${md#"$E2E_ACTIVE_PLUGIN"/}" "$marker"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$src.raw")"
    printf 'arguments: %s\n' "$arg"
  } | _e2e_art
  for sh in $E2E_FENCE_SHELLS; do
    printf '=== shell: %s\n' "$sh" | _e2e_art
    _e2e_exec "$sh" "$src"
    if [ -z "$first" ]; then
      first="$sh"; first_out="$E2E_OUT"; E2E_FIRST_ERR="$E2E_ERR"; E2E_FIRST_RC="$E2E_RC"
    elif [ "$E2E_OUT" = "$first_out" ]; then
      _e2e_result pass "stdout under $sh matches $first"
    else
      _e2e_result fail "stdout under $sh matches $first"
    fi
  done
  E2E_OUT="$first_out"; E2E_ERR="$E2E_FIRST_ERR"; E2E_RC="$E2E_FIRST_RC"
  printf -- '--- expectations (checked against %s)\n' "$first" | _e2e_art
}

# e2e_run_hook [NAME=value ...] <hook script under the plugin> <payload json> —
# feed a hook its payload on stdin, as the hook runner does, with the given
# environment variables set for it alone. Sets E2E_OUT, E2E_ERR, E2E_RC.
e2e_run_hook() {
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*) envs+=("$1"); shift ;;
      *) break ;;
    esac
  done
  local hook="$E2E_ACTIVE_PLUGIN/$1"
  {
    printf 'code: %s\n' "$1"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$hook")"
    printf 'payload: %s\n' "$2"
    [ "${#envs[@]}" -gt 0 ] && printf 'environment: %s\n' "${envs[*]}"
  } | _e2e_art
  printf '%s' "$2" > "$E2E_DIR/payload.json"
  _e2e_exec env ${envs[@]+"${envs[@]}"} "$hook" < "$E2E_DIR/payload.json"
  printf -- '--- expectations\n' | _e2e_art
}

_e2e_exec() {
  # A scenario runs only in its own scratch repository. An empty E2E_REPO would
  # leave the code running in the directory run.sh changed into: this checkout.
  case "$E2E_REPO" in
    "$E2E_ROOT"/*) ;;
    *)
      _flow_assert_fail "$E2E_NAME: no scratch repository; call e2e_repo before running code"
      E2E_OUT=""; E2E_ERR=""; E2E_RC=127
      return 0 ;;
  esac
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    unset CLAUDE_CONFIG_DIR FLOW_USER_SETTINGS FLOW_STATE_DIR CLAUDE_HOOK_GOAL_JUDGE_MODE
    # A proxy on the machine running the tests would receive the requests
    # meant for the stub servers.
    unset HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
    export CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" PATH="$E2E_BIN:$PATH"
    export E2E_GH E2E_DIR
    "$@"
  ) > "$E2E_DIR/out" 2> "$E2E_DIR/err"
  E2E_RC=$?
  E2E_OUT=$(cat "$E2E_DIR/out")
  E2E_ERR=$(cat "$E2E_DIR/err")
  # The artifact names the scratch root by a fixed token so two runs of the
  # same commit write the same file. On macOS the root is reached as both
  # /var/... and /private/var/.... The pattern is held in a variable first:
  # bash 3.2 does not match a quoted pattern built inline.
  local p_private="/private$E2E_ROOT" p_root="$E2E_ROOT"
  local art_out="${E2E_OUT//"$p_private"/<scratch>}" art_err="${E2E_ERR//"$p_private"/<scratch>}"
  art_out="${art_out//"$p_root"/<scratch>}"; art_err="${art_err//"$p_root"/<scratch>}"
  art_out=$(_e2e_mask "$art_out"); art_err=$(_e2e_mask "$art_err")
  {
    printf -- '--- inputs\n'
    local f
    for f in "$E2E_GH"/*.json "$E2E_GH"/*.fail; do
      [ -e "$f" ] || continue
      printf 'gh %s: %s\n' "$(basename "$f")" "$(tr '\n' ' ' < "$f")"
    done
    if [ -d "$E2E_REPO/.flow/goals" ]; then
      for f in "$E2E_REPO"/.flow/goals/*.goal.yaml; do
        [ -e "$f" ] || continue
        printf 'goal %s: branch=%s status=%s turns_evaluated=%s\n' "$(basename "$f")" \
          "$(awk '/^  branch:/{print $2; exit}' "$f")" "$(awk '/^  status:/{print $2; exit}' "$f")" \
          "$(awk '/^  turns_evaluated:/{print $2; exit}' "$f")"
      done
    fi
    f="$E2E_REPO/.claude/settings.flow.json"
    if [ -e "$f" ]; then printf 'settings: %s\n' "$(_e2e_mask "$(tr '\n' ' ' < "$f")")"; fi
    printf -- '--- exit status: %s\n' "$E2E_RC"
    printf -- '--- stdout\n%s\n' "$art_out"
    printf -- '--- stderr\n%s\n' "$art_err"
  } | _e2e_art
}

# Reports against the scenario line that made the expectation: the caller of
# the e2e_expect_* helper, two frames up.
_e2e_result() {
  local where="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
  if [ "$1" = pass ]; then
    printf 'PASS %s\n' "$2" | _e2e_art; _flow_assert_pass "$E2E_NAME: $2"
  else
    E2E_KEEP=1
    printf 'FAIL %s\n' "$2" | _e2e_art; _flow_assert_fail "$E2E_NAME: $2 (at $where; artifact $E2E_ARTIFACT)"
  fi
}

# e2e_expect_line <line> — stdout has this exact line.
e2e_expect_line() {
  if grep -qxF -- "$1" <<<"$E2E_OUT"; then _e2e_result pass "stdout has line: $1"
  else _e2e_result fail "stdout has line: $1"; fi
}

# e2e_expect_no_line <line> — stdout does not have this exact line.
e2e_expect_no_line() {
  if grep -qxF -- "$1" <<<"$E2E_OUT"; then _e2e_result fail "stdout lacks line: $1"
  else _e2e_result pass "stdout lacks line: $1"; fi
}

# e2e_expect_out <text> / e2e_expect_err <text> — stdout / stderr contains text.
e2e_expect_out() {
  case "$E2E_OUT" in *"$1"*) _e2e_result pass "stdout contains: $1" ;; *) _e2e_result fail "stdout contains: $1" ;; esac
}
e2e_expect_err() {
  case "$E2E_ERR" in *"$1"*) _e2e_result pass "stderr contains: $1" ;; *) _e2e_result fail "stderr contains: $1" ;; esac
}
e2e_expect_no_out() {
  case "$E2E_OUT" in *"$1"*) _e2e_result fail "stdout lacks: $1" ;; *) _e2e_result pass "stdout lacks: $1" ;; esac
}

# e2e_expect_file_has <path under repo> <text> — a file the code wrote.
e2e_expect_file_has() {
  if [ -f "$E2E_REPO/$1" ] && grep -qF -- "$2" "$E2E_REPO/$1"; then _e2e_result pass "$1 contains: $2"
  else _e2e_result fail "$1 contains: $2"; fi
}
e2e_expect_file_lacks() {
  if [ -f "$E2E_REPO/$1" ] && grep -qF -- "$2" "$E2E_REPO/$1"; then _e2e_result fail "$1 lacks: $2"
  else _e2e_result pass "$1 lacks: $2"; fi
}

# e2e_expect_equal <expected> <actual> <what> — a value the scenario computed.
e2e_expect_equal() {
  if [ "$1" = "$2" ]; then _e2e_result pass "$3 is '$1'"
  else _e2e_result fail "$3 is '$1' (got '$2')"; fi
}

# e2e_expect_clean_edges — no gh call went unanswered and claude never ran.
e2e_expect_clean_edges() {
  if [ -s "$E2E_GH/unhandled.log" ]; then
    _e2e_result fail "every gh call had a fixture ($(tr '\n' ';' < "$E2E_GH/unhandled.log"))"
  else
    _e2e_result pass "every gh call had a fixture"
  fi
  if [ -s "$E2E_DIR/claude-calls.log" ]; then _e2e_result fail "the claude CLI was not called"
  else _e2e_result pass "the claude CLI was not called"; fi
}
