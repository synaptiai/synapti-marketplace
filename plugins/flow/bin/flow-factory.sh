#!/usr/bin/env bash
# [flow] The factory's command-line entry point.
#
# Usage: flow-factory.sh <subcommand> [arguments]
#
# `context --mode` is answered here, in shell, before anything else: every
# flow command block may call it, so with no factory variable set it prints
# FACTORY_MODE=off and exits 0 without starting Python or reading the probe
# record. An ordinary flow run therefore works on a machine that has neither.
#
# `probe` runs bin/_flow_factory.py with a Python 3.14 or later that imports
# yaml, found by resolve_python below; it is the only subcommand that runs
# before a probe record exists, and the only one that runs a python3 found on
# PATH. `probe --resolve-python` is answered here: it prints how each
# candidate interpreter fared and which one is chosen.
#
# Every other subcommand runs the engine, bin/_flow_factory.py, with the
# interpreter the probe record <F>/probes.json names, as `<it> -E`, with
# PYTHONPATH removed (its value kept in FLOW_USER_PYTHONPATH). F, the
# factory directory, is found this way:
#   1. Walk the ancestors of this process with /bin/ps (by its full path, with
#      -ww so no width limit cuts a command line). An ancestor whose command
#      line is a launcher marker,
#        ... /bin/_flow_factory_launch.py --factory-dir <F> <directive-id>
#      names F when F holds a live lease of that ancestor: a lease file
#      <F>/jobs/*/directives/*.lease.json whose revoked_at is null and whose
#      launcher_pid and launcher_start are that ancestor's pid and start time.
#      The outermost such ancestor wins, so a process below the real launcher
#      cannot choose the record by imitating one.
#   2. Otherwise F is <main checkout>/<runtime dir>/factory for the working
#      directory's repository; the main checkout is the parent of the common
#      git directory, also from a linked worktree.
# No variable chooses F. So a worker run by a launcher finds the launcher's
# record from its own clone, or from outside any repository.
#
# First, a person-only subcommand (answer, approve-spec, confirm, feedback,
# rework, retry, reject, cancel, rebuild) or run, next or probe, from a worker,
# exits 4 with one line, before anything else is checked:
#   PERSON_ONLY_REFUSED=worker_env       (FLOW_FACTORY_JOB, _DIRECTIVE or _IO set)
#   PERSON_ONLY_REFUSED=lease_ancestor   (a launcher with a live lease is an
#                                         ancestor; probe leaves this to the engine)
#
# Before the exec the wrapper refuses, with exit 5 and one line:
#   FACTORY_REFUSED=jq_missing next: install jq
#   FACTORY_REFUSED=no_probe_record next: run the phase 0 probes
#   FACTORY_REFUSED=factory_path_changed recorded=<path> current=<F>
#     (no record at F, and <common git dir>/flow-factory-path names another
#     directory that holds one)
#   FACTORY_REFUSED=interpreter_missing recorded=<path or none> next: flow-factory.sh probe --environment
#     (the recorded interpreter is empty, starts with ~, is not absolute, is
#     not an executable file, is a #! script, has a shims component, or lies
#     inside the main checkout)
#
# With the recorded interpreter refused, two subcommands are answered here
# instead: `await` prints PARK and exits 0, and `report <directive-id>` appends
# one pending-report line to <F>/jobs/<job>/directives/<id>.pending-report.jsonl
# from the result JSON on stdin, naming its caller ($PPID and its start time),
# for the engine to check and apply once the interpreter is back. It refuses
# an id that is not a directive id (directive_id_invalid), a symlinked jobs,
# job or directives folder or pending-report file (pending_report_linked), and
# a directive with no directive file (directive_unknown).
#
# Exits:
#   0 — answered
#   2 — usage error; one stderr line, nothing on stdout
#   4 — refused for a worker; stdout holds one PERSON_ONLY_REFUSED=<reason> line
#   5 — refused; stdout holds one FACTORY_REFUSED=<reason> line
#   other — the engine's or `probe`'s own exit status (see bin/_flow_factory.py)

set -u
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

refuse() {
  printf 'FACTORY_REFUSED=%s\n' "$1"
  exit 5
}

# The worker check comes before every other refusal (the engine's
# _flow_factory_caller.check, which repeats it in full once Python starts):
# a person-only or engine-guarded subcommand from a worker exits 4 with
# PERSON_ONLY_REFUSED, not 5 for a missing record, jq or interpreter.
ff_guarded=""
case "${1:-}" in
  answer|approve-spec|confirm|feedback|rework|retry|reject|cancel|rebuild|run|next|probe) ff_guarded=1 ;;
esac
if [ -n "$ff_guarded" ] && [ -n "${FLOW_FACTORY_JOB:-}${FLOW_FACTORY_DIRECTIVE:-}${FLOW_FACTORY_IO:-}" ]; then
  printf '%s\n' "PERSON_ONLY_REFUSED=worker_env"
  exit 4
fi

if [ "${1:-}" = context ] && [ "${2:-}" = --mode ] && [ "$#" -eq 2 ] \
   && [ -z "${FLOW_FACTORY_JOB:-}" ] && [ -z "${FLOW_FACTORY_DIRECTIVE:-}" ]; then
  printf '%s\n' "FACTORY_MODE=off"
  exit 0
fi

# Only `probe` starts a python3 found on PATH (resolve_python below), so only
# `probe` sanitizes PYTHONPATH first. Every other subcommand execs the recorded
# interpreter with -E, which reads no PYTHONPATH.
if [ "${1:-}" = probe ]; then
  # Keep the repository out of PYTHONPATH before python3 starts: the interpreter
  # imports sitecustomize from each element at startup. An isolated python3 (-I:
  # it reads neither PYTHONPATH nor the working directory) keeps only elements
  # that are directories outside the repository and not at or above the working
  # directory, comparing directories by identity, not by how the path is spelled;
  # tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
  # original for commands run for the user.
  [ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}" FLOW_USER_PYTHONPATH_SET="${PYTHONPATH+1}" FLOW_USER_PYTHONSAFEPATH="${PYTHONSAFEPATH-}" FLOW_USER_PYTHONSAFEPATH_SET="${PYTHONSAFEPATH+1}"
  _flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
  if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
  export PYTHONSAFEPATH=1
fi

HERE=$(cd "$(dirname -- "$0")" && pwd -P) || refuse plugin_unreadable

# ff_cwd_lookup — set main_top, common and F from the working directory's
# repository. The runtime directory helper gets no PYTHONPATH, so it starts no
# python3 to sanitize one.
ff_cwd_lookup() {
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || refuse not_in_repository
  main_top=$(dirname -- "$common")
  runtime_dir=$(cd "$main_top" && env -u PYTHONPATH "$HERE/flow-runtime-dir.sh" 2>/dev/null) || refuse runtime_dir_unreadable
  F="$main_top/$runtime_dir/factory"
}

# resolve_python [explain] — print the realpath of a Python 3.14 or later that
# imports yaml, or nothing. Each candidate runs from a fresh empty directory
# with the pyenv and Python path variables removed, so a .python-version or a
# module planted in the repository cannot choose the interpreter. The result
# must be a native executable (not a #! script such as a pyenv shim) outside
# the repository.
#
# With explain it tries every candidate and prints one tab-separated line for
# each, PYTHON_CANDIDATE <name> accepted|rejected <path on PATH> <realpath>
# <reason>, then PYTHON=<the first accepted>; `probe --resolve-python` prints
# that report, so the environment probe records the rules as they ran here.
resolve_python() {
  local explain="${1:-}" scratch cand path out ver exe ym shim reason maj min chosen=""
  # Exit 2, not 1: a temporary folder that cannot be made is not a missing
  # interpreter.
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/flow-factory-py.XXXXXX") || return 2
  for cand in python3.14 python3; do
    path=$(command -v "$cand" 2>/dev/null) || path=""
    if [ -z "$path" ]; then
      [ -n "$explain" ] && printf 'PYTHON_CANDIDATE\t%s\trejected\t-\t-\tnot on PATH\n' "$cand"
      continue
    fi
    shim=""
    case "$path" in */shims/*) shim="a shim in a shims directory" ;; esac
    if [ -z "$shim" ] && [ -f "$path" ] && [ "$(head -c 2 "$path" 2>/dev/null)" = '#!' ]; then
      shim="a shim (#! script)"
    fi
    out=$(cd "$scratch" && env -u PYENV_VERSION -u PYTHONPATH -u PYTHONHOME "$cand" -E -c \
      'import os, platform, sys; print(platform.python_version()); print(os.path.realpath(sys.executable)); import yaml; print("yaml")' 2>/dev/null)
    ver=$(printf '%s\n' "$out" | sed -n 1p)
    exe=$(printf '%s\n' "$out" | sed -n 2p)
    ym=$(printf '%s\n' "$out" | sed -n 3p)
    maj=${ver%%.*}; min=${ver#*.}; min=${min%%.*}
    reason=""
    case "$maj:$min" in
      :*|*:|*[!0-9:]*) reason="${shim:+$shim that }did not run" ;;
    esac
    if [ -z "$reason" ] && ! { [ "$maj" -gt 3 ] || { [ "$maj" -eq 3 ] && [ "$min" -ge 14 ]; }; }; then
      reason="${shim:+$shim that }runs Python $ver, older than 3.14"
    fi
    [ -z "$reason" ] && [ "$ym" != yaml ] && reason="${shim:+$shim that }runs Python $ver without PyYAML"
    if [ -z "$reason" ]; then
      case "$exe" in
        /*) ;;
        *) reason="its interpreter path is not absolute" ;;
      esac
    fi
    if [ -z "$reason" ]; then
      case "$exe" in
        */shims/*) reason="its interpreter is in a shims directory" ;;
        "$main_top"/*) reason="its interpreter is inside the repository" ;;
      esac
    fi
    [ -z "$reason" ] && [ ! -x "$exe" ] && reason="its interpreter is not executable"
    [ -z "$reason" ] && [ "$(head -c 2 "$exe" 2>/dev/null)" = '#!' ] && reason="its interpreter is a #! script, not a native executable"
    if [ -n "$reason" ]; then
      [ -n "$explain" ] && printf 'PYTHON_CANDIDATE\t%s\trejected\t%s\t%s\t%s\n' "$cand" "$path" "${exe:--}" "$reason"
      continue
    fi
    if [ -n "$explain" ]; then
      if [ -n "$chosen" ]; then
        reason="acceptable, after the one chosen"
      elif [ -n "$shim" ]; then
        reason="reached through $shim, run with no .python-version or PYENV_VERSION in effect"
      else
        reason="a native executable"
      fi
      printf 'PYTHON_CANDIDATE\t%s\taccepted\t%s\t%s\t%s\n' "$cand" "$path" "$exe" "$reason"
    fi
    [ -z "$chosen" ] && chosen="$exe"
    [ -z "$explain" ] && break
  done
  rmdir "$scratch" 2>/dev/null
  [ -n "$chosen" ] || return 1
  if [ -n "$explain" ]; then printf 'PYTHON=%s\n' "$chosen"; else printf '%s\n' "$chosen"; fi
  return 0
}

# refuse_resolve <status> — the refusal for a resolve_python that failed.
refuse_resolve() {
  [ "$1" = 2 ] && refuse "scratch_unwritable (mktemp -d in ${TMPDIR:-/tmp} failed)"
  refuse "python_missing (need Python 3.14 or later with PyYAML)"
}

if [ "${1:-}" = probe ]; then
  ff_cwd_lookup
  if [ "${2:-}" = --resolve-python ] && [ "$#" -eq 2 ]; then
    resolve_python explain || refuse_resolve $?
    exit 0
  fi
  py=$(resolve_python) || refuse_resolve $?
  exec "$py" -E "$HERE/_flow_factory.py" "$@"
fi

# ff_lstart <pid> — the pid's start time: `ps -o lstart=` under LC_ALL=C with
# outer white space removed and inner spaces kept (plan 2.4). Empty when the
# pid is not running.
ff_lstart() {
  local start
  case "${1:-}" in ''|*[!0-9]*) return 0 ;; esac
  start=$(LC_ALL=C /bin/ps -o lstart= -p "$1" 2>/dev/null) || start=""
  start="${start#"${start%%[![:space:]]*}"}"
  start="${start%"${start##*[![:space:]]}"}"
  printf '%s' "$start"
}

# ff_marker_dir <command line> — the factory directory a launcher marker
# names, or nothing. The rule is shared with bin/_flow_factory_caller.py
# (marker_factory_dir): the command line contains
# "/bin/_flow_factory_launch.py --factory-dir "; the text after its FIRST
# occurrence ends with " <directive-id>"; the directory is the text between,
# and is not empty. ps joins the arguments with single spaces and does not
# quote them, so the id at the end is what anchors a directory that holds
# spaces.
ff_marker_dir() {
  local cmd="$1" anchor="/bin/_flow_factory_launch.py --factory-dir " rest id suffix dir
  local re='^issue-[1-9][0-9]*-j[1-9][0-9]*-(intake|prepare|spec|build|open_pr|gate|review|rework|sync|resolve|approve|merging)-[1-9][0-9]*$'
  case "$cmd" in *"$anchor"*) ;; *) return 0 ;; esac
  rest="${cmd#*"$anchor"}"
  id="${rest##* }"
  [[ $id =~ $re ]] || return 0
  suffix=" $id"
  dir="${rest%"$suffix"}"
  [ "$dir" != "$rest" ] && [ -n "$dir" ] || return 0
  printf '%s\n' "$dir"
}

# ff_live_lease <F> <pid> <start> — whether F holds a lease that is not
# revoked and names that pid and start time as its launcher.
ff_live_lease() {
  local f
  for f in "$1"/jobs/*/directives/*.lease.json; do
    [ -f "$f" ] || continue
    jq -e --argjson p "$2" --arg s "$3" \
      '.revoked_at == null and .launcher_pid == $p and .launcher_start == $s' "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}

# ff_launcher_dir — the factory directory of the outermost ancestor that is a
# launcher with a live lease there, or nothing. Each ancestor is read with
# /bin/ps -ww -o ppid=,lstart=,command=: the ppid, then the start time (always
# 24 characters), then padding, then the command line. The walk stops at pid
# 1, at a pid ps prints nothing for, or when /bin/ps cannot run; the engine's
# own worker check fails closed on an ancestry it cannot read.
ff_launcher_dir() {
  local pid="$PPID" line ppid rest start cmd dir found="" n=0
  [ -x /bin/ps ] || return 0
  while [ "$n" -lt 4096 ]; do
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
    n=$((n + 1))
    line=$(LC_ALL=C /bin/ps -ww -o ppid=,lstart=,command= -p "$pid" 2>/dev/null) || break
    line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$line" ] || break
    ppid="${line%%[!0-9]*}"
    rest="${line#"$ppid"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    start="${rest:0:24}"
    start="${start%"${start##*[![:space:]]}"}"
    cmd="${rest:24}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    dir=$(ff_marker_dir "$cmd")
    if [ -n "$dir" ] && ff_live_lease "$dir" "$pid" "$start"; then found="$dir"; fi
    pid="$ppid"
  done
  printf '%s' "$found"
}

# ff_realpath <path> — the path with every symlink resolved and its directory
# in physical form; nothing and status 1 when it cannot be resolved.
ff_realpath() {
  local p="$1" t n=0 d
  while [ -L "$p" ]; do
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
    t=$(readlink -- "$p") || return 1
    case "$t" in /*) p="$t" ;; *) p="$(dirname -- "$p")/$t" ;; esac
  done
  d=$(cd "$(dirname -- "$p")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s' "$d" "$(basename -- "$p")"
}

# ff_vetted <path> — whether the recorded interpreter may be exec'd: an
# absolute path, not starting with ~, to an executable regular file that is
# not a #! script, with no shims component and not inside the main checkout,
# both as recorded and with its links resolved.
ff_vetted() {
  local p="$1" real at top
  [ -n "$p" ] || return 1
  case "$p" in "~"*|*$'\n'*) return 1 ;; /*) ;; *) return 1 ;; esac
  [ -f "$p" ] && [ -x "$p" ] || return 1
  [ "$(head -c 2 "$p" 2>/dev/null)" = '#!' ] && return 1
  real=$(ff_realpath "$p") || return 1
  at="$(cd "$(dirname -- "$p")" 2>/dev/null && pwd -P)/$(basename -- "$p")" || return 1
  case "/$p/:/$real/:/$at/" in */shims/*) return 1 ;; esac
  if [ -n "${main_top:-}" ]; then
    top=$(cd "$main_top" 2>/dev/null && pwd -P) || return 1
    case "$real" in "$top"/*) return 1 ;; esac
    case "$at" in "$top"/*) return 1 ;; esac
  fi
  return 0
}

# ff_report <id> — the shell `report`, for a launcher whose interpreter is
# gone: append one pending-report line built from the result JSON on stdin
# (at most 65536 bytes, one JSON object).
ff_report() {
  local id="${1:-}" re J D P body n report start now line
  re='^issue-[1-9][0-9]*-j[1-9][0-9]*-(intake|prepare|spec|build|open_pr|gate|review|rework|sync|resolve|approve|merging)-[1-9][0-9]*$'
  if [ "$#" -ne 1 ]; then
    printf '%s\n' "flow-factory.sh report: usage: flow-factory.sh report <directive-id> < <result json>" >&2
    exit 2
  fi
  [[ $id =~ $re ]] || refuse directive_id_invalid
  J="$F/jobs/${id%%-j*}"
  D="$J/directives"
  P="$D/$id.pending-report.jsonl"
  if [ -L "$F/jobs" ] || [ -L "$J" ] || [ -L "$D" ] || [ -L "$P" ] || { [ -e "$P" ] && [ ! -f "$P" ]; }; then
    refuse "pending_report_linked directive=$id"
  fi
  [ -f "$D/$id.json" ] && [ ! -L "$D/$id.json" ] || refuse "directive_unknown directive=$id"
  body=$(head -c 65537; printf x)
  body="${body%x}"
  n=$(printf '%s' "$body" | LC_ALL=C wc -c | tr -d ' ')
  if [ "$n" -gt 65536 ]; then
    printf '%s\n' "flow-factory.sh report: the result on stdin is over 65536 bytes" >&2
    exit 2
  fi
  if ! report=$(printf '%s' "$body" | jq -cse 'if length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' 2>/dev/null); then
    printf '%s\n' "flow-factory.sh report: stdin is not one JSON object" >&2
    exit 2
  fi
  start=$(ff_lstart "$PPID")
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  line=$(jq -nc --arg d "$id" --argjson p "$PPID" --arg s "$start" --arg at "$now" --argjson r "$report" \
    '{directive: $d, caller_pid: $p, caller_start: $s, at: $at, report: $r}') || exit 1
  if ! printf '%s\n' "$line" >> "$P"; then
    printf '%s\n' "flow-factory.sh report: cannot append to $P" >&2
    exit 1
  fi
  exit 0
}

# A worker under a launcher with a live lease: the same refusal, by ancestry
# (the variables were checked at the top).
main_top=""
common=""
F=$(ff_launcher_dir)
if [ -n "$ff_guarded" ] && [ -n "$F" ]; then
  printf '%s\n' "PERSON_ONLY_REFUSED=lease_ancestor"
  exit 4
fi
command -v jq >/dev/null 2>&1 || refuse "jq_missing next: install jq"
if [ -n "$F" ]; then
  # F lies inside the main checkout (ignored by its .gitignore), so git run
  # there names the main checkout whatever the working directory is.
  main_top=$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$F" rev-parse --show-toplevel 2>/dev/null) || main_top=""
  common=$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$F" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
else
  ff_cwd_lookup
fi
record="$F/probes.json"

if [ ! -f "$record" ]; then
  pointer="$common/flow-factory-path"
  if [ -n "$common" ] && [ -f "$pointer" ] && [ ! -L "$pointer" ]; then
    recorded=$(head -n 1 "$pointer" 2>/dev/null) || recorded=""
    if [ -n "$recorded" ] && [ -f "$recorded/probes.json" ] \
       && [ "$(cd "$recorded" 2>/dev/null && pwd -P)" != "$(cd "$F" 2>/dev/null && pwd -P)" ]; then
      refuse "factory_path_changed recorded=$recorded current=$F"
    fi
  fi
  refuse "no_probe_record next: run the phase 0 probes"
fi

interp=$(jq -r '.interpreter // empty | strings' "$record" 2>/dev/null) || interp=""
if ! ff_vetted "$interp"; then
  case "${1:-}" in
    await) printf '%s\n' PARK; exit 0 ;;
    report) shift; ff_report "$@" ;;
  esac
  shown=$(printf '%s' "${interp:-none}" | tr '\n\r' '??')
  refuse "interpreter_missing recorded=$shown next: flow-factory.sh probe --environment"
fi

# The engine runs with -E, which reads no PYTHONPATH, but the processes it
# starts would, and flow's helpers would each run a PATH python3 -I to clean
# it. So it is removed here, without running anything: the original is kept
# in FLOW_USER_PYTHONPATH for commands run for the user, as the sanitizer
# keeps it when it keeps no element.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}" FLOW_USER_PYTHONPATH_SET="${PYTHONPATH+1}" FLOW_USER_PYTHONSAFEPATH="${PYTHONSAFEPATH-}" FLOW_USER_PYTHONSAFEPATH_SET="${PYTHONSAFEPATH+1}"
unset PYTHONPATH
export PYTHONSAFEPATH=1
exec "$interp" -E "$HERE/_flow_factory.py" "$@"
