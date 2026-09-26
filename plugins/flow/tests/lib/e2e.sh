# plugins/flow/tests/lib/e2e.sh — end-to-end harness for flow's command blocks
# and hooks. Sourced by the e2e-*.test.sh files after assert.sh.
#
# A scenario runs the real code the way Claude Code runs it: a `!` fence taken
# from the shipped command file and run with bash, or a hook script fed a hook
# payload, inside a scratch git repository with its own HOME. The only fakes
# are the programs at the edge: `gh` answers from fixture files, and `claude`
# must never be called.
#
# Every scenario writes one artifact file to $E2E_ARTIFACT_DIR (default: a
# scratch directory; CI sets FLOW_E2E_ARTIFACT_DIR and uploads it). The file
# holds the repository commit, the source file and sha256 of the code that ran,
# every input, the output, and each expectation with its result. Nothing in it
# depends on the clock, so two runs on the same commit produce the same file.
#
# E2E_PLUGIN_DIR points the harness at another copy of the plugin. It exists so
# a mutated copy can be run to check that a scenario fails for its own reason.

E2E_PLUGIN_DIR="${E2E_PLUGIN_DIR:-$REPO_ROOT/plugins/flow}"
E2E_REPO_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')

# One scratch root, created in the calling shell so the EXIT trap can remove
# it. Helpers called as $(...) run in a subshell and cannot add to a cleanup
# list, so everything goes under this root instead.
E2E_ROOT=$(mktemp -d -t flow-e2e.XXXXXX 2>/dev/null) || E2E_ROOT=""
if [ -z "$E2E_ROOT" ] || [ ! -d "$E2E_ROOT" ]; then
  _flow_assert_fail "mktemp -d failed; cannot create the e2e scratch root"
  return 0
fi
trap 'rm -rf "$E2E_ROOT" 2>/dev/null' EXIT
E2E_ARTIFACT_DIR="${FLOW_E2E_ARTIFACT_DIR:-$E2E_ROOT/artifacts}"
mkdir -p "$E2E_ARTIFACT_DIR"

_e2e_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# e2e_new <scenario-name> — a fresh scratch directory with a HOME, a stub bin
# and a gh fixture directory. Sets E2E_DIR, E2E_HOME, E2E_BIN, E2E_GH, and
# E2E_ARTIFACT (the scenario's artifact file, started here).
e2e_new() {
  E2E_NAME="$1"
  E2E_DIR="$E2E_ROOT/$1"
  E2E_HOME="$E2E_DIR/home"
  E2E_BIN="$E2E_DIR/bin"
  E2E_GH="$E2E_DIR/gh"
  mkdir -p "$E2E_HOME" "$E2E_BIN" "$E2E_GH"
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
  "repo view --json nameWithOwner") f=repo ;;
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
  # The goal judge must never run on the paths these scenarios take.
  cat > "$E2E_BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${E2E_DIR:?}/claude-calls.log"
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
  } > "$E2E_ARTIFACT"
}

# e2e_describe <text> — one line saying what the scenario sets up and why.
e2e_describe() { printf 'purpose: %s\n' "$1" >> "$E2E_ARTIFACT"; }

# e2e_repo <branch> — a git repository at $E2E_DIR/repo with one commit, on
# <branch>. The commit matters: on an unborn branch git reports no branch name,
# and branch-scoped goal lookup then takes a different path.
e2e_repo() {
  E2E_REPO="$E2E_DIR/repo"
  mkdir -p "$E2E_REPO"
  (
    cd "$E2E_REPO" || exit 1
    git init -q
    git config user.email e2e@example.invalid
    git config user.name e2e
    git config commit.gpgsign false
    printf 'e2e\n' > README.md
    git add README.md
    git commit -q -m init
    git checkout -q -b "$1"
  ) || _flow_assert_fail "could not create the scratch repository"
}

# e2e_gh_fixture <name> <json> — the answer gh gives for one call. Names:
# user, repo, prs, reviews-<pr>, comments-<pr>. e2e_gh_fail <name> makes that
# call exit 1 with an HTTP error, as real gh does.
e2e_gh_fixture() { printf '%s\n' "$2" > "$E2E_GH/$1.json"; }
e2e_gh_fail() { : > "$E2E_GH/$1.fail"; }

# e2e_goal <id> <branch> <status> <must-pass command> [run_id] — write a FlowGoal
# into the scratch repo's .flow/goals, built from the schema-valid fixture.
e2e_goal() {
  mkdir -p "$E2E_REPO/.flow/goals"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" \
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

# e2e_run_fence <command.md> <marker> [argument] — run that fence in the
# scratch repo the way Claude Code does: `$ARGUMENTS` replaced by the argument
# text, then the block run by bash. Sets E2E_OUT, E2E_ERR, E2E_RC.
e2e_run_fence() {
  local md="$1" marker="$2" arg="${3:-}" src="$E2E_DIR/fence.sh"
  e2e_fence "$md" "$marker" > "$src.raw"
  if [ ! -s "$src.raw" ]; then
    _flow_assert_fail "$E2E_NAME: no fence in $(basename "$md") contains '$marker'"
    E2E_OUT=""; E2E_ERR=""; E2E_RC=127
    return 0
  fi
  ARG="$arg" python3 -c '
import os, sys
sys.stdout.write(open(sys.argv[1], encoding="utf-8").read().replace("$ARGUMENTS", os.environ["ARG"]))
' "$src.raw" > "$src"
  {
    printf 'code: %s (fence containing %s)\n' "${md#"$E2E_PLUGIN_DIR"/}" "$marker"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$src.raw")"
    printf 'argument: %s\n' "$arg"
  } >> "$E2E_ARTIFACT"
  _e2e_exec bash "$src"
}

# e2e_run_hook <hook script> <payload json> — feed a hook its payload on stdin,
# as the hook runner does. Sets E2E_OUT, E2E_ERR, E2E_RC.
e2e_run_hook() {
  {
    printf 'code: %s\n' "${1#"$E2E_PLUGIN_DIR"/}"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$1")"
    printf 'payload: %s\n' "$2"
  } >> "$E2E_ARTIFACT"
  printf '%s' "$2" > "$E2E_DIR/payload.json"
  _e2e_exec "$1" < "$E2E_DIR/payload.json"
}

_e2e_exec() {
  (
    cd "$E2E_REPO" || exit 1
    unset CLAUDE_CONFIG_DIR FLOW_USER_SETTINGS FLOW_STATE_DIR CLAUDE_HOOK_GOAL_JUDGE_MODE
    export HOME="$E2E_HOME" CLAUDE_PLUGIN_ROOT="$E2E_PLUGIN_DIR" PATH="$E2E_BIN:$PATH"
    export E2E_GH E2E_DIR
    "$@"
  ) > "$E2E_DIR/out" 2> "$E2E_DIR/err"
  E2E_RC=$?
  E2E_OUT=$(cat "$E2E_DIR/out")
  E2E_ERR=$(cat "$E2E_DIR/err")
  # The artifact names the scratch root by a fixed token so two runs of the
  # same commit write the same file. On macOS the root is reached as both
  # /var/... and /private/var/....
  local art_out="${E2E_OUT//"/private$E2E_ROOT"/<scratch>}" art_err="${E2E_ERR//"/private$E2E_ROOT"/<scratch>}"
  art_out="${art_out//"$E2E_ROOT"/<scratch>}"; art_err="${art_err//"$E2E_ROOT"/<scratch>}"
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
        printf 'goal %s: branch=%s status=%s\n' "$(basename "$f")" \
          "$(awk '/^  branch:/{print $2; exit}' "$f")" "$(awk '/^  status:/{print $2; exit}' "$f")"
      done
    fi
    for f in "$E2E_REPO"/.claude/settings.flow.json; do
      [ -e "$f" ] && printf 'settings: %s\n' "$(tr '\n' ' ' < "$f")"
    done
    printf -- '--- exit status: %s\n' "$E2E_RC"
    printf -- '--- stdout\n%s\n' "$art_out"
    printf -- '--- stderr\n%s\n' "$art_err"
    printf -- '--- expectations\n'
  } >> "$E2E_ARTIFACT"
}

_e2e_result() {
  if [ "$1" = pass ]; then
    printf 'PASS %s\n' "$2" >> "$E2E_ARTIFACT"; _flow_assert_pass "$E2E_NAME: $2"
  else
    printf 'FAIL %s\n' "$2" >> "$E2E_ARTIFACT"; _flow_assert_fail "$E2E_NAME: $2"
  fi
}

# e2e_expect_line <line> — stdout has this exact line.
e2e_expect_line() {
  if printf '%s\n' "$E2E_OUT" | grep -qxF -- "$1"; then _e2e_result pass "stdout has line: $1"
  else _e2e_result fail "stdout has line: $1"; fi
}

# e2e_expect_no_line <line> — stdout does not have this exact line.
e2e_expect_no_line() {
  if printf '%s\n' "$E2E_OUT" | grep -qxF -- "$1"; then _e2e_result fail "stdout lacks line: $1"
  else _e2e_result pass "stdout lacks line: $1"; fi
}

# e2e_expect_out <text> / e2e_expect_err <text> — stdout / stderr contains text.
e2e_expect_out() {
  case "$E2E_OUT" in *"$1"*) _e2e_result pass "stdout contains: $1" ;; *) _e2e_result fail "stdout contains: $1" ;; esac
}
e2e_expect_err() {
  case "$E2E_ERR" in *"$1"*) _e2e_result pass "stderr contains: $1" ;; *) _e2e_result fail "stderr contains: $1" ;; esac
}

# e2e_expect_file_has <path under repo> <text> — a file the code wrote.
e2e_expect_file_has() {
  if [ -f "$E2E_REPO/$1" ] && grep -qF -- "$2" "$E2E_REPO/$1"; then _e2e_result pass "$1 contains: $2"
  else _e2e_result fail "$1 contains: $2"; fi
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
