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
# before a probe record exists. `probe --resolve-python` is answered here: it
# prints how each candidate interpreter fared and which one is chosen.
#
# Every other subcommand needs a probe record, <runtime dir>/factory/probes.json
# in the main checkout. Until one exists the wrapper refuses with exit 5 and
# one line, FACTORY_REFUSED=no_probe_record. A subcommand that is not built
# yet is refused the same way with FACTORY_REFUSED=not_built.
#
# Exits:
#   0 — answered
#   5 — refused; stdout holds one FACTORY_REFUSED=<reason> line
#   other — `probe`'s own exit status (see bin/_flow_factory.py)

set -u
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

refuse() {
  printf 'FACTORY_REFUSED=%s\n' "$1"
  exit 5
}

if [ "${1:-}" = context ] && [ "${2:-}" = --mode ] && [ "$#" -eq 2 ] \
   && [ -z "${FLOW_FACTORY_JOB:-}" ] && [ -z "${FLOW_FACTORY_DIRECTIVE:-}" ]; then
  printf '%s\n' "FACTORY_MODE=off"
  exit 0
fi

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

HERE=$(cd "$(dirname -- "$0")" && pwd -P) || refuse plugin_unreadable

# The probe record lives in the main checkout, also when this runs from a
# linked worktree: the common git directory's parent is the main checkout.
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || refuse not_in_repository
main_top=$(dirname -- "$common")
runtime_dir=$(cd "$main_top" && "$HERE/flow-runtime-dir.sh" 2>/dev/null) || refuse runtime_dir_unreadable
record="$main_top/$runtime_dir/factory/probes.json"

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

if [ "${1:-}" = probe ] && [ "${2:-}" = --resolve-python ] && [ "$#" -eq 2 ]; then
  resolve_python explain || refuse_resolve $?
  exit 0
fi

if [ "${1:-}" = probe ]; then
  py=$(resolve_python) || refuse_resolve $?
  exec "$py" -E "$HERE/_flow_factory.py" "$@"
fi

[ -f "$record" ] || refuse no_probe_record
refuse not_built
