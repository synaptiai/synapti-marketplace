# shellcheck shell=bash
# plugins/flow/tests/lib/factory-e2e.sh — helpers for the factory's end-to-end
# tests. Sourced after tests/lib/e2e.sh, by the e2e-factory-*.test.sh files
# that start processes; e2e.sh itself is not changed.
#
# Every helper that starts a process starts it the way e2e.sh's _e2e_exec runs
# a scenario's code: in the scenario's scratch repository, with the scratch
# HOME, the factory's gh and claude stand-ins first on PATH, and the person's
# settings variables unset. So no test can reach the real repository's
# .flow/factory, the person's settings, or the real gh and claude. A helper
# with no scratch repository (E2E_REPO empty or outside the scratch root)
# starts nothing and fails the scenario. The one exception is the read-only
# interpreter lookup behind fe_python, done once when this file is sourced.
#
# Every scenario starts with fe_new, never e2e_new: fe_new first kills what
# the previous scenario left running (every process a lease under the scratch
# root names, and every process a helper started in the background), each
# only when its start time is still the one recorded, so a pid the system has
# given to another process is left alone.
#
# The helpers are listed in plan 2.16 (phase 1a, #354); each has a comment
# below.

if ! declare -F e2e_new >/dev/null 2>&1; then
  printf '%s\n' "factory-e2e.sh: source tests/lib/e2e.sh first" >&2
  return 1 2>/dev/null; exit 1
fi

FE_FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/factory"
# Processes the helpers started in the background: one `<pid>\t<start>` line
# each. A file, because helpers called as $(...) run in a subshell.
FE_PROCS="$E2E_ROOT/fe-procs"
: > "$FE_PROCS"

# The worker variables must not reach anything a test starts, and GH_REPO
# would choose the sync's repository instead of flow-e2e/scratch.
unset FLOW_FACTORY_JOB FLOW_FACTORY_DIRECTIVE FLOW_FACTORY_IO FLOW_FACTORY_MAIN GH_REPO

# _fe_lstart <pid> — the pid's start time in the plan 2.4 form: `ps -o lstart=`
# under LC_ALL=C with outer white space removed and inner spaces kept. Empty
# when the pid is not running or not a number.
_fe_lstart() {
  local start
  case "${1:-}" in ''|*[!0-9]*) return 0 ;; esac
  start=$(LC_ALL=C /bin/ps -o lstart= -p "$1" 2>/dev/null) || start=""
  start="${start#"${start%%[![:space:]]*}"}"
  start="${start%"${start##*[![:space:]]}"}"
  printf '%s' "$start"
}

# _fe_has_repo — whether E2E_REPO is a scratch repository under the scratch
# root. Prints the reason on stderr when it is not.
_fe_has_repo() {
  case "${E2E_REPO:-}" in
    "$E2E_ROOT"/?*) return 0 ;;
  esac
  printf 'factory-e2e: no scratch repository (E2E_REPO=%s); call e2e_repo first, nothing was started\n' "${E2E_REPO:-}" >&2
  return 1
}

# _fe_need_repo — _fe_has_repo, failing the scenario when it is not.
_fe_need_repo() {
  _fe_has_repo && return 0
  E2E_KEEP=1
  _flow_assert_fail "${E2E_NAME:-?}: no scratch repository; call e2e_repo before a factory helper that starts a process"
  return 1
}

# _fe_scratch_env — the lines _e2e_exec runs before a scenario's code
# (e2e.sh:701-724), for helpers that start a process in the background or
# under a pty, which _e2e_exec cannot. Run it in a subshell, as
# `( _fe_scratch_env || exit 97; ... )`.
_fe_scratch_env() {
  _fe_has_repo || return 97
  _e2e_git_env
  cd "$E2E_REPO" || return 97
  unset CLAUDE_CONFIG_DIR FLOW_USER_SETTINGS FLOW_STATE_DIR CLAUDE_HOOK_GOAL_JUDGE_MODE
  unset HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
  unset TYPESAFE_API_KEY
  export CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" PATH="$E2E_BIN:$PATH"
  export E2E_GH E2E_DIR
}

# _fe_register <pid> — remember a background process for _fe_cleanup.
_fe_register() {
  printf '%s\t%s\n' "$1" "$(_fe_lstart "$1")" >> "$FE_PROCS"
}

# _fe_is_ours <pid or pgid> — whether it is this shell, an ancestor of this
# shell, or the process group of one of them: never to be killed.
_fe_is_ours() {
  local a=$$ g
  [ "$1" = "${BASHPID:-$$}" ] && return 0
  while [ -n "$a" ] && [ "$a" -gt 1 ]; do
    [ "$a" = "$1" ] && return 0
    g=$(/bin/ps -o pgid= -p "$a" 2>/dev/null | tr -d ' ')
    [ "$g" = "$1" ] && return 0
    a=$(/bin/ps -o ppid= -p "$a" 2>/dev/null | tr -d ' ')
  done
  return 1
}

# _fe_kill_tree <pid> <recorded start> — kill the pid and every process below
# it, when the pid is running with that start time. Never pid 0 or 1, or
# anything _fe_is_ours names.
_fe_kill_tree() {
  local pid="$1" start="$2" list
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  [ "$pid" -gt 1 ] && [ -n "$start" ] || return 0
  [ "$(_fe_lstart "$pid")" = "$start" ] || return 0
  _fe_is_ours "$pid" && return 0
  list=$(/bin/ps -A -o pid=,ppid= 2>/dev/null | awk -v root="$pid" '
    { kids[$2] = kids[$2] " " $1 }
    END { out = root; queue = root
          while (queue != "") { n = split(queue, q, " "); queue = ""
            for (i = 1; i <= n; i++) { m = split(kids[q[i]], c, " ")
              for (j = 1; j <= m; j++) { out = out " " c[j]; queue = queue " " c[j] } } }
          print out }')
  # shellcheck disable=SC2086
  kill -KILL $list 2>/dev/null
  printf '%s\n' $list >> "$E2E_ROOT/fe-killed"
}

# _fe_kill_group <pgid> <recorded start of the group leader> — kill the group
# and the leader's tree, when the leader is running with that start time.
# Never anything _fe_is_ours names.
_fe_kill_group() {
  local pgid="$1" start="$2"
  case "$pgid" in ''|*[!0-9]*) return 0 ;; esac
  [ "$pgid" -gt 1 ] && [ -n "$start" ] || return 0
  [ "$(_fe_lstart "$pgid")" = "$start" ] || return 0
  _fe_is_ours "$pgid" && return 0
  _fe_kill_tree "$pgid" "$start"
  kill -KILL -- "-$pgid" 2>/dev/null
  printf '%s\n' "$pgid" >> "$E2E_ROOT/fe-killed"
}

# _fe_cleanup — kill every launcher and child group a lease file under the
# scratch root names, and every process a helper registered, each only when
# its start time is the one recorded (a lease that records none is left
# alone); then wait up to 5 s for them to be gone.
_fe_cleanup() {
  local f lpid lstart cpgid cstart pid start i alive
  [ -n "${E2E_ROOT:-}" ] && [ -d "$E2E_ROOT" ] || return 0
  : > "$E2E_ROOT/fe-killed"
  while IFS= read -r -d '' f; do
    # The four fields joined by the unit separator: a tab is white space to
    # read, which would merge an empty field into the next one.
    IFS=$'\037' read -r lpid lstart cpgid cstart < <(jq -r '[(.launcher_pid // "" | tostring), (.launcher_start // "" | tostring),
      (.child_pgid // "" | tostring), (.child_start // "" | tostring)] | join("\u001f")' "$f" 2>/dev/null) || continue
    _fe_kill_tree "$lpid" "$lstart"
    _fe_kill_group "$cpgid" "$cstart"
  done < <(find "$E2E_ROOT" -name '*.lease.json' -type f -print0 2>/dev/null)
  if [ -f "$FE_PROCS" ]; then
    while IFS='	' read -r pid start; do
      _fe_kill_tree "$pid" "$start"
    done < "$FE_PROCS"
    : > "$FE_PROCS"
  fi
  for i in $(seq 1 50); do
    alive=""
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      case "$(/bin/ps -o stat= -p "$pid" 2>/dev/null)" in ''|Z*) ;; *) alive=1 ;; esac
    done < "$E2E_ROOT/fe-killed"
    [ -z "$alive" ] && break
    sleep 0.1
  done
}
trap '_fe_cleanup; _e2e_cleanup' EXIT

# The interpreter the probe record names: the PYTHON= line of
# `flow-factory.sh probe --resolve-python`, resolved once per test file with
# the real HOME and PATH (the person's Python and its user site), from a
# scratch repository made with no git configuration of the person's.
_fe_resolve_python() {
  local d="$E2E_ROOT/fe-python-repo"
  mkdir -p "$d" "$E2E_ROOT/fe-python-home"
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    cd "$d" && HOME="$E2E_ROOT/fe-python-home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q .
  ) || return 1
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    cd "$d" && "$E2E_PLUGIN_DIR/bin/flow-factory.sh" probe --resolve-python 2>/dev/null
  ) | sed -n 's/^PYTHON=//p'
}
FE_PYTHON=$(_fe_resolve_python)
FE_REAL_HOME="$HOME"
FE_USER_SITE=""
if [ -n "$FE_PYTHON" ]; then
  FE_USER_SITE=$(cd / && "$FE_PYTHON" -I -c 'import site; print(site.getusersitepackages())' 2>/dev/null) || FE_USER_SITE=""
else
  _flow_assert_fail "factory-e2e.sh: flow-factory.sh probe --resolve-python found no Python 3.14 with PyYAML; the factory tests need one"
fi

# fe_python — print the interpreter the probe record names.
fe_python() {
  [ -n "$FE_PYTHON" ] || { printf '%s\n' "factory-e2e: no interpreter was resolved" >&2; return 1; }
  printf '%s\n' "$FE_PYTHON"
}

# fe_user_site [home] — link the real user site-packages into the scratch HOME
# (or the given home) at the same path relative to it, so the recorded
# interpreter finds jsonschema and PyYAML there. Nothing when the user site is
# missing or not under the real HOME.
fe_user_site() {
  local home="${1:-$E2E_HOME}" rel
  [ -n "$FE_USER_SITE" ] && [ -d "$FE_USER_SITE" ] || return 0
  rel="${FE_USER_SITE#"$FE_REAL_HOME"/}"
  [ "$rel" != "$FE_USER_SITE" ] || return 0
  mkdir -p "$home/$(dirname -- "$rel")"
  [ -e "$home/$rel" ] || [ -L "$home/$rel" ] || ln -s "$FE_USER_SITE" "$home/$rel"
}

# fe_new <name> — start a scenario: kill what the previous one left running,
# e2e_new, unset the worker variables, link the user site, and install the
# factory gh stub and the worker claude stand-in (no knobs) over e2e.sh's.
fe_new() {
  _fe_cleanup
  e2e_new "$1"
  unset FLOW_FACTORY_JOB FLOW_FACTORY_DIRECTIVE FLOW_FACTORY_IO FLOW_FACTORY_MAIN GH_REPO
  fe_user_site
  cp "$FE_FIXTURES/engine/gh" "$E2E_BIN/gh"
  mkdir -p "$E2E_BIN/fe-gh"
  cp "$FE_FIXTURES/worker/claude" "$E2E_BIN/claude"
  cp "$FE_FIXTURES/platform/claude_platform.py" "$E2E_BIN/claude_platform.py"
  chmod +x "$E2E_BIN/gh" "$E2E_BIN/claude"
}

# fe_wait_for <seconds> <shell test> — poll every 0.1 s until the test
# succeeds; at the limit fail the scenario and return 1.
fe_wait_for() {
  local limit="$1" end
  shift
  # Bounded by the clock, not a count of polls: each poll's own time counts.
  # SECONDS is whole seconds, so the wait ends within one second after the
  # limit, never before it.
  end=$((SECONDS + limit))
  while [ "$SECONDS" -le "$end" ]; do
    eval "$*" && return 0
    sleep 0.1
  done
  _e2e_result fail "within ${limit} s: $*"
  return 1
}

# fe_mask_pid <pid> <name>, fe_mask_text <text> <token> — write them into the
# artifact as fixed tokens from here on.
fe_mask_pid() { printf '%s\t<pid %s>\n' "$1" "$2" >> "$E2E_DIR/masks"; }
fe_mask_text() { printf '%s\t%s\n' "$1" "$2" >> "$E2E_DIR/masks"; }

# The values a test or a fixture writes as they are (a time, a ps start time,
# a uuid, the pid of a pid or pgid key), found once per test file in the
# tests and in docs/flow-factory. fe_unvary keeps these and masks the rest.
FE_CONSTANTS="$E2E_ROOT/fe-constants"
{
  grep -rhoE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z|(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 0-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    "$REPO_ROOT/plugins/flow/tests" "$REPO_ROOT/docs/flow-factory" 2>/dev/null
  grep -rhoE "[\"'](launcher_pid|child_pid|child_pgid|caller_pid|pid|pgid)[\"'] ?[:=] ?[0-9]+|[\"']ancestry[\"'] ?[:=] ?\[[0-9, ]*\]" \
    "$REPO_ROOT/plugins/flow/tests" 2>/dev/null | grep -oE '[0-9]+' | sed 's/^/pid /'
  printf 'pid 1\n'
} | LC_ALL=C sort -u > "$FE_CONSTANTS"

# fe_unvary — stdin to stdout with every value that changes from run to run
# written as a fixed token, for text a factory helper or test writes to the
# artifact (fe_art). Each unless FE_CONSTANTS holds it: a UTC time as <time>;
# a ps start time (any weekday, month, and a day padded with a space) as
# <lstart>; a uuid as <uuid>, except the fixed 00000000-0000-... session ids
# fe_directive makes. The time-ordered number that starts a pending change's
# file name as <seq>. Then the scenario's masks (fe_mask_pid, fe_mask_text),
# so a named pid keeps its name; they come after the times, so a pid's digits
# cannot be found inside one. Last, again unless FE_CONSTANTS holds it, the
# value of a pid, pgid, launcher_pid, child_pid, child_pgid or caller_pid key
# (in JSON, or in the Python a test edits a job with),
# each pid of an ancestry list, the pid and parent pid that start an
# ancestry entry ([pid, ppid, "<start>", ...]), and the group a launcher log
# line names, as <pid>.
fe_unvary() {
  FE_MASKS="${E2E_DIR:-}/masks" FE_CONSTANTS="$FE_CONSTANTS" perl -0777 -e '
    my %c;
    if (open(my $fh, "<", $ENV{FE_CONSTANTS})) { $c{$_} = 1 for split /\n/, scalar <$fh> }
    my $t = <STDIN>; $t = "" unless defined $t;
    my $pid = sub { $c{"pid $_[0]"} ? $_[0] : "<pid>" };
    $t =~ s/(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z)/$c{$1} ? $1 : "<time>"/ge;
    $t =~ s/((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ \d]\d \d\d:\d\d:\d\d \d{4})/$c{$1} ? $1 : "<lstart>"/ge;
    $t =~ s/\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b/my $u = $1; ($c{$u} || $u =~ m{^00000000-0000-}) ? $u : "<uuid>"/ge;
    $t =~ s/\b\d{19,20}(-[a-z_]+\.json)/<seq>$1/g;
    if (open(my $mh, "<", $ENV{FE_MASKS})) {
      for my $ln (split /\n/, scalar <$mh>) {
        my ($from, $to) = split /\t/, $ln, 2;
        $t =~ s/\Q$from\E/$to/g if defined $from && length $from && defined $to;
      }
    }
    $t =~ s/((["\x27])(?:launcher_pid|child_pid|child_pgid|caller_pid|pid|pgid)\2:\s*)(\d+)/$1 . $pid->($3)/ge;
    $t =~ s/(\bgroup )(\d+)/$1 . $pid->($2)/ge;
    $t =~ s/("ancestry":\s*\[)([^\]]*)(\])/my ($a, $l, $b) = ($1, $2, $3); $l =~ s{(\d+)}{$pid->($1)}ge; $a . $l . $b/ge;
    my $pn = sub { my $v = $_[0]; $v =~ m{^\d+$} ? $pid->($v) : $v };
    $t =~ s/\[(\d+|<pid [^>]*>), (\d+|<pid [^>]*>), (?="(?:<lstart>|[A-Z][a-z]{2} [A-Z][a-z]{2} ))/"[" . $pn->($1) . ", " . $pn->($2) . ", "/ge;
    print $t;'
}

# fe_art — fe_unvary, then append to the scenario's artifact (_e2e_art).
fe_art() { fe_unvary | _e2e_art; }

# fe_mask_found <text> — register a mask (fe_mask_text) for each value in the
# text that fe_unvary would write as a token: a time, a ps start time, a uuid.
# For a value that reaches the artifact through e2e.sh, an expectation's
# value or a command's output, which fe_art never sees. A pid alone cannot be
# told from another number; fe_mask_pid names those.
fe_mask_found() {
  local v tok
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    case "$v" in *T*Z) tok='<time>' ;; *-*-*-*-*) tok='<uuid>' ;; *) tok='<lstart>' ;; esac
    fe_mask_text "$v" "$tok"
  done < <(printf '%s' "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z|(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 0-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    | LC_ALL=C sort -u | grep -vxF -f "$FE_CONSTANTS" | grep -v '^00000000-0000-')
}

# fe_mask_back <text> <token> — fe_mask_text, and the same replacement in what
# the artifact already holds: for a value first seen in a command's output,
# which e2e.sh has written to the artifact before the test can read it.
fe_mask_back() {
  [ -n "$1" ] || return 0
  fe_mask_text "$1" "$2"
  FE_FROM="$1" FE_TO="$2" perl -0777 -pi -e 's/\Q$ENV{FE_FROM}\E/$ENV{FE_TO}/g' "$E2E_ARTIFACT"
}

# fe_mask_output <extended regex> <token> — fe_mask_back for each distinct
# match of the regex in the last command's stdout and stderr (E2E_OUT,
# E2E_ERR): a name the command made up, such as a mktemp folder.
fe_mask_output() {
  local m
  while IFS= read -r m; do
    fe_mask_back "$m" "$2"
  done < <(printf '%s\n%s\n' "${E2E_OUT:-}" "${E2E_ERR:-}" | grep -oE "$1" | LC_ALL=C sort -u)
}

# fe_mask_random <path> — register masks for the random part of a mktemp
# name (what follows its last .), as written, in lower case and in upper
# case, as XXXXXX: a test that writes the path in another case or with each
# / as - keeps the random part, which no mask of the whole path matches.
fe_mask_random() {
  local r="${1##*.}"
  [ -n "$r" ] && [ "$r" != "$1" ] || return 0
  fe_mask_text "$r" XXXXXX
  fe_mask_text "$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')" XXXXXX
  fe_mask_text "$(printf '%s' "$r" | tr '[:lower:]' '[:upper:]')" XXXXXX
}

# _fe_in_scratch <command...> — run a command in the scratch environment in
# the foreground, its output as the command's own. For the helpers' own
# git and Python steps.
_fe_in_scratch() {
  _fe_need_repo || return 97
  ( _fe_scratch_env || exit 97; "$@" )
}

# fe_factory_dir — print F, the scratch main checkout's factory directory:
# <parent of the common git directory>/<runtime dir>/factory.
fe_factory_dir() {
  local common rt
  _fe_need_repo || return 97
  common=$(_fe_in_scratch git rev-parse --path-format=absolute --git-common-dir) || return 1
  rt=$(_fe_in_scratch "$E2E_ACTIVE_PLUGIN/bin/flow-runtime-dir.sh" 2>/dev/null) || rt=.flow
  printf '%s/%s/factory\n' "$(dirname -- "$common")" "${rt:-.flow}"
}

# fe_record [python statements] — write a valid F/probes.json naming
# fe_python, and the pointer <common git dir>/flow-factory-path holding F.
# Every probe group, entry and part is stamped with claude 2.1.325 (Claude
# Code), model claude-opus-5-5 (platform and interactive groups), the gh
# stub's version, the real git's version and fe_python's realpath and
# version; every result is go except P8, which never ran. The probes and
# their parts are those of docs/flow-factory/probes.json. The statements edit
# the dict d before it is written. Also gives the scratch repository an
# origin of https://github.com/flow-e2e/scratch.git when it has none.
fe_record() { _fe_record "$(fe_python)" "${1:-}"; }

# fe_record_link [python statements] — fe_record, but the record names
# $E2E_DIR/py/python3.14, a link to fe_python, so a scenario can remove it.
fe_record_link() {
  mkdir -p "$E2E_DIR/py"
  ln -sfn "$(fe_python)" "$E2E_DIR/py/python3.14"
  _fe_record "$E2E_DIR/py/python3.14" "${1:-}"
}

_fe_record() {
  local named="$1" edits="$2" fdir gitv common
  _fe_need_repo || return 97
  fdir=$(fe_factory_dir) || return 1
  mkdir -p "$fdir"
  [ -f "$fdir/.gitignore" ] || printf '*\n' > "$fdir/.gitignore"
  gitv=$(_fe_in_scratch git --version | sed -n 1p)
  _fe_in_scratch git remote get-url origin >/dev/null 2>&1 \
    || _fe_in_scratch git remote add origin https://github.com/flow-e2e/scratch.git
  common=$(_fe_in_scratch git rev-parse --path-format=absolute --git-common-dir) || return 1
  printf '%s\n' "$fdir" > "$common/flow-factory-path"
  if ! _fe_in_scratch "$(fe_python)" -I - "$REPO_ROOT/docs/flow-factory/probes.json" "$fdir/probes.json" \
      "$named" "$gitv" "$edits" <<'PY'
import json, os, platform, sys
base, dst, named, gitv, edits = sys.argv[1:6]
real = os.path.realpath(sys.executable)
common = {"claude_version": "2.1.325 (Claude Code)", "gh_version": "gh version 2.101.0 (2026-09-15)",
          "git_version": gitv, "interpreter": real, "interpreter_version": platform.python_version()}
keyed = {g: dict(common) for g in ("platform", "interactive", "environment", "github_write")}
for g in ("platform", "interactive"):
    keyed[g]["model"] = "claude-opus-5-5"
at = "2026-11-16T00:00:00Z"
with open(base, encoding="utf-8") as f:
    src = json.load(f)
d = {"apiVersion": "flow.synapti.ai/v1", "kind": "FlowFactoryProbes", "interpreter": named,
     "groups": {g: {"keyed_on": dict(k), "ran_at": at} for g, k in keyed.items()},
     "probes": {}, "spend": {"cap_usd": 25, "spent_usd": 0}}
for pid, p in sorted(src["probes"].items()):
    if p.get("result") == "not_run" and not p.get("parts"):
        d["probes"][pid] = {k: p[k] for k in ("group", "result", "reason", "stand_in", "evidence", "cost_usd",
                                               "github_writes", "fallback") if k in p}
        continue
    entry = {"group": p["group"], "result": "go", "reason": "fe_record fixture", "stand_in": False,
             "evidence": "evidence/%s" % pid, "cost_usd": 0, "github_writes": [],
             "keyed_on": dict(keyed[p["group"]]), "ran_at": at}
    if p.get("parts"):
        entry["parts"] = {n: {"result": "go", "reason": "fe_record fixture", "keyed_on": dict(keyed[p["group"]]),
                              "ran_at": at} for n in p["parts"]}
    d["probes"][pid] = entry
exec(edits)
with open(dst + ".t", "w", encoding="utf-8") as f:
    json.dump(d, f, indent=1)
    f.write("\n")
os.replace(dst + ".t", dst)
PY
  then
    _e2e_result fail "fe_record wrote $fdir/probes.json"
    return 1
  fi
  printf 'probe record: fe_record naming %s%s\n' "$named" "${edits:+, edited by: $edits}" | _e2e_art
}

# fe_settings <json> — the scratch user settings (e2e_user_settings).
fe_settings() { e2e_user_settings "$1"; }

# fe_enable — set flow.factory.enabled true in the scratch user settings,
# keeping what is there.
fe_enable() {
  local f="$E2E_HOME/.claude/settings.flow.json" cur='{}'
  [ -f "$f" ] && cur=$(cat "$f")
  e2e_user_settings "$(printf '%s' "$cur" | jq -c '.flow.factory.enabled = true')"
}

# fe_job <n> <state> [python statements] — write J/job.json, valid per plan
# 2.3: key issue-<n>-j1, branch feature/issue-<n>-x-2, goal_id issue-<n>-f2,
# worktree $E2E_DIR/area/worktrees/issue-<n> and io_dir
# $E2E_DIR/area/jobs/issue-<n>/io (with in/ and out/), as physical paths. The
# statements edit the dict d before it is written.
fe_job() {
  local n="$1" state="$2" edits="${3:-}" fdir area
  _fe_need_repo || return 97
  fdir=$(fe_factory_dir) || return 1
  area="$(cd "$E2E_DIR" && pwd -P)/area"
  mkdir -p "$fdir/jobs/issue-$n" "$area/jobs/issue-$n/io/in" "$area/jobs/issue-$n/io/out" "$area/worktrees"
  if ! _fe_in_scratch "$(fe_python)" -I - "$fdir/jobs/issue-$n/job.json" "$n" "$state" "$area" "$edits" <<'PY'
import json, os, sys
dst, n, state, area, edits = sys.argv[1:6]
n = int(n)
at = "2026-11-16T00:00:00Z"
d = {"apiVersion": "flow.synapti.ai/v1", "kind": "FlowFactoryJob", "key": "issue-%d-j1" % n, "issue": n,
     "state": state, "attempt": 0, "stage_launches": {}, "sessions": {}, "holds_slot": False, "directive": None,
     "cost": {"usd_total": 0, "runs": [], "stage_usd": {}, "dearest_turn_usd": 0},
     "created_at": at, "updated_at": at, "vouch_at": None,
     "branch": "feature/issue-%d-x-2" % n, "goal_id": "issue-%d-f2" % n,
     "worktree": os.path.join(area, "worktrees", "issue-%d" % n),
     "io_dir": os.path.join(area, "jobs", "issue-%d" % n, "io")}
exec(edits)
with open(dst + ".t", "w", encoding="utf-8") as f:
    json.dump(d, f, indent=1)
    f.write("\n")
os.replace(dst + ".t", dst)
PY
  then
    _e2e_result fail "fe_job wrote job issue-$n"
    return 1
  fi
  printf 'job: fe_job %s %s%s\n' "$n" "$state" "${edits:+, edited by: $edits}" | fe_art
}

# fe_job_clone <n> — clone $E2E_REPO into job.json's worktree with
# `git clone --no-hardlinks`, on job.json's branch, then copy the clone's
# .git/config (and config.worktree when present) to J/clone-config/.
fe_job_clone() {
  local n="$1" j wt branch
  _fe_need_repo || return 97
  j="$(fe_factory_dir)/jobs/issue-$n"
  wt=$(jq -r '.worktree // empty' "$j/job.json" 2>/dev/null)
  branch=$(jq -r '.branch // empty' "$j/job.json" 2>/dev/null)
  case "$wt" in "$E2E_ROOT"/*|"$E2E_ROOT_REAL"/*) ;; *)
    _e2e_result fail "fe_job_clone: job issue-$n has a worktree under the scratch root (got '$wt')"; return 1 ;;
  esac
  if ! _fe_in_scratch sh -c '
      git clone -q --no-hardlinks "$1" "$2" && cd "$2" \
      && git config user.email e2e@example.invalid && git config user.name e2e && git config commit.gpgsign false \
      && { [ -z "$3" ] || git checkout -q -B "$3"; }' _ "$E2E_REPO" "$wt" "$branch"; then
    _e2e_result fail "fe_job_clone cloned the scratch repository into $wt"
    return 1
  fi
  mkdir -p "$j/clone-config"
  cp "$wt/.git/config" "$j/clone-config/config"
  [ -f "$wt/.git/config.worktree" ] && cp "$wt/.git/config.worktree" "$j/clone-config/config.worktree"
  printf 'job clone: issue-%s on %s\n' "$n" "${branch:-the default branch}" | _e2e_art
}

# fe_directive <id> [python statements] — write J/directives/<id>.json, valid
# per plan 2.4: a fresh worker directive of the id's stage, cause row "first",
# made in pass p1, with a fixed session id; the statements edit the dict d.
fe_directive() {
  local id="$1" edits="${2:-}" fdir
  _fe_need_repo || return 97
  fdir=$(fe_factory_dir) || return 1
  mkdir -p "$fdir/jobs/${id%%-j*}/directives"
  if ! _fe_in_scratch "$(fe_python)" -I - "$fdir/jobs/${id%%-j*}/directives/$id.json" "$id" "$edits" <<'PY'
import json, os, re, sys
dst, did, edits = sys.argv[1:4]
m = re.match(r"^(issue-([1-9][0-9]*)-j[1-9][0-9]*)-([a-z_]+)-([1-9][0-9]*)$", did)
if not m:
    sys.exit("fe_directive: not a directive id: " + did)
key, issue, stage = m.group(1), int(m.group(2)), m.group(3)
tools = "Bash,Read,Write,Edit,Glob,Grep,Agent,Task,Skill,TaskCreate,TaskUpdate,TaskList,TaskGet".split(",")
d = {"id": did, "job": key, "issue": issue, "kind": "worker", "stage": stage, "start_mode": "fresh",
     "cause_row": "first", "created_in_pass": "p1", "created_at": "2026-11-16T00:00:00Z",
     "session_id": "00000000-0000-4000-8000-%012d" % issue,
     "prompt_template": "templates/factory/%s.prompt.md" % stage, "model": None,
     "timeout_seconds": 3600 if stage == "build" else 1800, "allowed_tools": tools,
     "max_budget_usd": None, "snapshot_ref": None, "started_at": None, "not_started_reason": None}
exec(edits)
with open(dst + ".t", "w", encoding="utf-8") as f:
    json.dump(d, f, indent=1)
    f.write("\n")
os.replace(dst + ".t", dst)
PY
  then
    _e2e_result fail "fe_directive wrote $id"
    return 1
  fi
  printf 'directive: fe_directive %s%s\n' "$id" "${edits:+, edited by: $edits}" | _e2e_art
}

# fe_worker_says [--hooks] [<knob> | <knob>=<content>]... — install the worker
# claude stand-in (worker/claude and claude_platform.py) into $E2E_BIN with
# these knob files beside it: a bare name is an empty file, name=content a
# file holding the content and a newline. The knobs are claude_platform.py's
# (its docstring) plus the stand-in's own: worker-result, worker-sleep and
# claude-version. Without --hooks it also writes claude-hooks-only holding
# __fe_no_hook__, which no hook command contains, so the plugin's hooks never
# run inside the stand-in.
fe_worker_says() {
  local hooks="" k
  cp "$FE_FIXTURES/worker/claude" "$E2E_BIN/claude"
  cp "$FE_FIXTURES/platform/claude_platform.py" "$E2E_BIN/claude_platform.py"
  chmod +x "$E2E_BIN/claude"
  for k in "$@"; do
    case "$k" in
      --hooks) hooks=1 ;;
      */*|'') _e2e_result fail "fe_worker_says: a knob name without a /: '$k'"; return 1 ;;
      *=*) printf '%s\n' "${k#*=}" > "$E2E_BIN/${k%%=*}" ;;
      *) : > "$E2E_BIN/$k" ;;
    esac
  done
  if [ -n "$hooks" ]; then rm -f "$E2E_BIN/claude-hooks-only"
  else printf '%s\n' "__fe_no_hook__" > "$E2E_BIN/claude-hooks-only"; fi
  printf 'worker stand-in: %s\n' "${*:-no knobs}" | _e2e_art
}

# fe_gh <key> <json | "hang <s>" | "fail <rc> <stderr>"> — the factory gh
# stub's answer for one call (engine/gh describes the key).
fe_gh() {
  mkdir -p "$E2E_BIN/fe-gh"
  printf '%s\n' "$2" > "$E2E_BIN/fe-gh/$1.json"
  printf 'gh stub: %s -> %s\n' "$1" "$2" | _e2e_art
}

# _fe_py_cmd <helper> <arguments...> — set FE_CMD to the command fe_py, fe_e
# or fe_direct runs.
_fe_py_cmd() {
  local helper="$1" fixture
  shift
  case "$helper" in
    fe_py)
      FE_CMD=("$(fe_python)" -E -c "import sys; sys.path.insert(0, '$E2E_ACTIVE_PLUGIN/bin')
$1") ;;
    fe_e)
      fixture="$1"; shift
      case "$fixture" in */*) ;; *) fixture="$FE_FIXTURES/seam/$fixture" ;; esac
      FE_CMD=("$(fe_python)" -E "$FE_FIXTURES/engine_under_test.py" --plugin "$E2E_ACTIVE_PLUGIN" --fixtures "$fixture" "$@") ;;
    fe_direct)
      FE_CMD=("$(fe_python)" -E "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" "$@") ;;
    *) return 1 ;;
  esac
}

# _fe_run_py <python arguments...> — run "$(fe_python)" -E <arguments> through
# _e2e_exec (the scratch repository and environment), recording the code, its
# arguments and the outcome in the artifact. Sets E2E_OUT, E2E_ERR, E2E_RC.
_fe_run_py() {
  local a code="" shown=""
  _fe_has_repo || { _e2e_exec true; return 0; }
  for a in "$@"; do
    case "$a" in
      *.py) [ -z "$code" ] && [ -f "$a" ] && code="$a" ;;
    esac
  done
  {
    if [ -n "$code" ]; then
      printf 'code: %s\n' "${code#"$E2E_ACTIVE_PLUGIN"/}"
      printf 'code sha256: %s\n' "$(_e2e_sha256 "$code")"
    fi
    for a in "$@"; do shown="$shown${shown:+ }$(printf '%s' "$a" | tr '\n' ';')"; done
    printf 'python -E arguments: %s\n' "$shown"
  } | fe_art
  _e2e_exec "$(fe_python)" -E "$@"
  printf -- '--- expectations\n' | _e2e_art
}

# fe_py <statements> — the isolation driver: the recorded interpreter with
# -E -c, bin/ first on sys.path, in the scratch environment.
fe_py() { _fe_py_cmd fe_py "$1" && _fe_run_py "${FE_CMD[@]:2}"; }

# fe_e <fixture> <subcommand...> — the test entry point E with a seam fixture
# (a path, or a name under fixtures/factory/seam/).
fe_e() { _fe_py_cmd fe_e "$@" && _fe_run_py "${FE_CMD[@]:2}"; }

# fe_direct <subcommand...> — bin/_flow_factory.py run directly.
fe_direct() { _fe_py_cmd fe_direct "$@" && _fe_run_py "${FE_CMD[@]:2}"; }

# fe_bg <tag> <fe_py|fe_e|fe_direct> <arguments...> — that call in the
# background, in the same scratch environment, its output in
# $E2E_DIR/bg-<tag>.out and .err and its exit status in .rc when it ends.
# fe_bg_wait <tag> <seconds> waits for the .rc and records the outcome.
fe_bg() {
  local tag="$1" helper="$2" d="$E2E_DIR"
  shift 2
  _fe_need_repo || return 97
  _fe_py_cmd "$helper" "$@" || { _e2e_result fail "fe_bg: $helper is fe_py, fe_e or fe_direct"; return 1; }
  rm -f "$d/bg-$tag.out" "$d/bg-$tag.err" "$d/bg-$tag.rc"
  printf 'background %s: %s %s\n' "$tag" "$helper" "$(printf '%s ' "$@" | tr '\n' ';')" | fe_art
  (
    ( _fe_scratch_env || exit 97; exec "${FE_CMD[@]}" ) < /dev/null > "$d/bg-$tag.out" 2> "$d/bg-$tag.err"
    printf '%s\n' "$?" > "$d/bg-$tag.rc.t" && mv "$d/bg-$tag.rc.t" "$d/bg-$tag.rc"
  ) &
  _fe_register "$!"
}
fe_bg_wait() {
  fe_wait_for "$2" "[ -f '$E2E_DIR/bg-$1.rc' ]" || return 1
  {
    printf -- '--- background %s: exit status %s\n' "$1" "$(cat "$E2E_DIR/bg-$1.rc")"
    printf -- '--- stdout\n%s\n--- stderr\n%s\n' "$(cat "$E2E_DIR/bg-$1.out")" "$(cat "$E2E_DIR/bg-$1.err")"
  } | fe_art
}

# _fe_next <prefix> — the next free n for $E2E_DIR/<prefix>-<n>, reserved.
_fe_next() {
  local n=1
  while ! mkdir "$E2E_DIR/.$1-$n" 2>/dev/null; do n=$((n + 1)); done
  printf '%s' "$n"
}

# _fe_record_outcome <what> — write E2E_RC, E2E_OUT and E2E_ERR to the artifact.
_fe_record_outcome() {
  {
    printf 'ran: %s\n' "$1"
    printf -- '--- exit status: %s\n--- stdout\n%s\n--- stderr\n%s\n--- expectations\n' "$E2E_RC" "$E2E_OUT" "$E2E_ERR"
  } | fe_art
}

# fe_detached <command...> — run the command with no controlling terminal and
# no ancestor of the test (double fork with setsid; its parent is pid 1 on
# macOS), with CLAUDECODE unset, in the scratch environment. Waits up to 60 s
# for it. Its stdout, stderr and exit status are in $E2E_DIR/detached-<n>/
# and in E2E_OUT, E2E_ERR and E2E_RC.
fe_detached() {
  local n d
  _fe_need_repo || return 97
  n=$(_fe_next detached); d="$E2E_DIR/detached-$n"
  mkdir -p "$d"
  ( _fe_scratch_env || exit 97
    exec "$(fe_python)" -I "$FE_FIXTURES/worker/fe_spawn.py" detached "$d" 60 "$FE_PROCS" -- "$@" ) < /dev/null > "$d/spawn.log" 2>&1
  E2E_RC=$(cat "$d/rc" 2>/dev/null || printf 'none')
  E2E_OUT=$(cat "$d/out" 2>/dev/null)
  E2E_ERR=$(cat "$d/err" 2>/dev/null)
  _fe_record_outcome "fe_detached $*"
}

# fe_person_terminal [--delay <s>] <word> <command...> — run the command
# under a pty, double-forked with setsid, with CLAUDECODE unset and no claude
# ancestor, in the scratch environment. When its output shows a prompt (a line
# starting `type ` and ending in `:` or `: `) it waits --delay seconds (default
# 0) and types <word> and a newline. Its output goes to
# $E2E_DIR/terminal-<n>.out as it arrives and its exit status to
# terminal-<n>.rc; both end up in E2E_OUT (carriage returns removed) and
# E2E_RC. Gives up after 60 s.
fe_person_terminal() {
  local delay=0 word n out rc
  if [ "${1:-}" = --delay ]; then delay="$2"; shift 2; fi
  word="$1"; shift
  _fe_need_repo || return 97
  n=$(_fe_next terminal); out="$E2E_DIR/terminal-$n.out"; rc="$E2E_DIR/terminal-$n.rc"
  : > "$out"
  ( _fe_scratch_env || exit 97
    exec "$(fe_python)" -I "$FE_FIXTURES/worker/fe_spawn.py" terminal "$out" "$rc" "$word" "$delay" 60 "$FE_PROCS" -- "$@"
  ) < /dev/null > "$E2E_DIR/terminal-$n.log" 2>&1
  E2E_RC=$(cat "$rc" 2>/dev/null || printf 'none')
  E2E_OUT=$(tr -d '\r' < "$out")
  E2E_ERR=""
  _fe_record_outcome "fe_person_terminal (typing '$word') $*"
}

# fe_fake_launcher <F> <directive-id> <worker script> — start
# worker/fake_launcher.py in the background in the scratch environment, with
# a launcher marker as its command line:
#   <fe_python> <fixtures>/worker/fake_launcher.py <plugin>/bin/_flow_factory_launch.py --factory-dir <F> <id>
# It runs the script as its "claude" child and writes the lease. Prints the
# launcher's pid once the lease names it (10 s at most).
fe_fake_launcher() {
  local fdir="$1" id="$2" script="$3" plugin pid lease n i
  _fe_has_repo || { E2E_KEEP=1; _flow_assert_fail "${E2E_NAME:-?}: fe_fake_launcher: no scratch repository"; return 97; }
  plugin=$(cd "$E2E_ACTIVE_PLUGIN" && pwd -P)
  lease="$fdir/jobs/${id%%-j*}/directives/$id.lease.json"
  n=$(_fe_next fake-launcher)
  ( _fe_scratch_env || exit 97
    FE_WORKER_SCRIPT="$script" exec "$(fe_python)" "$FE_FIXTURES/worker/fake_launcher.py" \
      "$plugin/bin/_flow_factory_launch.py" --factory-dir "$fdir" "$id"
  ) < /dev/null > "$E2E_DIR/fake-launcher-$n.log" 2>&1 &
  pid=$!
  _fe_register "$pid"
  for i in $(seq 1 100); do
    [ "$(jq -r '.launcher_pid // empty' "$lease" 2>/dev/null)" = "$pid" ] && { printf '%s\n' "$pid"; return 0; }
    sleep 0.1
  done
  printf 'factory-e2e: fe_fake_launcher: no lease naming launcher %s at %s within 10 s\n' "$pid" "$lease" >&2
  return 1
}

# fe_art_state <n> — write job issue-<n>'s state to the artifact: job.json,
# events.jsonl (each line's time as <time>), pending/, directives/, results/,
# the gh stub's call log, and the stand-in's argv files; of each env file all
# the names, and the values only of FLOW_FACTORY_*, CLAUDE_PLUGIN_ROOT,
# FLOW_STATE_DIR, GH_REPO, GH_PROMPT_DISABLED and PATH's first entry.
fe_art_state() {
  local j f
  j="$(fe_factory_dir)/jobs/issue-$1"
  {
    printf -- '--- state of job issue-%s\n' "$1"
    for f in "$j/job.json" "$j"/pending/* "$j"/directives/* "$j"/results/*; do
      [ -f "$f" ] || continue
      printf '%s:\n%s\n' "${f#"$j"/}" "$(cat "$f")"
    done
    if [ -f "$j/events.jsonl" ]; then
      printf 'events.jsonl:\n'
      jq -c 'if type == "object" and has("time") then .time = "<time>" else . end' "$j/events.jsonl" 2>/dev/null
    fi
    [ -f "$E2E_BIN/fe-gh-calls.log" ] && printf 'gh calls:\n%s\n' "$(cat "$E2E_BIN/fe-gh-calls.log")"
    for f in "$E2E_BIN"/claude-argv-*.txt; do
      [ -f "$f" ] && printf '%s:\n%s\n' "${f##*/}" "$(cat "$f")"
    done
    for f in "$E2E_BIN"/claude-env-*.txt; do
      [ -f "$f" ] || continue
      printf '%s:\n' "${f##*/}"
      LC_ALL=C sort "$f" | awk -F= '
        /^(FLOW_FACTORY_[A-Z_]*|CLAUDE_PLUGIN_ROOT|FLOW_STATE_DIR|GH_REPO|GH_PROMPT_DISABLED)=/ { print; next }
        /^PATH=/ { v = substr($0, 6); sub(/:.*/, "", v); print "PATH=" v ":..."; next }
        /^[A-Za-z_][A-Za-z0-9_]*=/ { print $1 }'
    done
  } | fe_art
}

# fe_digest — the sha256 of the factory files e2e.sh's plugin digest leaves
# out: references/factory-transitions.json, schemas/v1/factory-*.schema.json
# and templates/factory/*.
fe_digest() {
  local f p="$E2E_ACTIVE_PLUGIN"
  {
    for f in "$p/references/factory-transitions.json" "$p"/schemas/v1/factory-*.schema.json "$p"/templates/factory/*; do
      [ -f "$f" ] && printf 'sha256 %s: %s\n' "${f#"$p"/}" "$(_e2e_sha256 "$f")"
    done
  } | _e2e_art
}
