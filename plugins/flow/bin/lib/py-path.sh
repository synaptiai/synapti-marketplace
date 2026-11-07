# shellcheck shell=bash
# bin/lib/py-path.sh — hand python3 paths it can open, on every platform (#246).
#
# Git Bash, MSYS2 and Cygwin give a script POSIX paths (/d/a/proj/...). The
# python3 there is usually a native Windows build, which reads /d/a/proj as a
# different place, so `sys.path.insert(0, argv[1])` imports nothing and a
# helper whose module sits beside it fails before doing any work; a hook
# swallows that, and the helper looks like it had nothing to do. `cygpath -m`
# renders a path in the one form bash, git and a native Python all resolve
# (D:/a/proj/...).
#
# Sourced by every bin/ helper and hook that runs python3 with a path, so the
# conversion is made once, here, at the boundary between the shell and the
# interpreter:
#
#   py_path <path>   the path as python3 on this platform reads it (unchanged
#                    off Windows, or when cygpath is missing)
#
# Under Git Bash, MSYS2 or Cygwin, sourcing also defines a `python3` shell
# function in front of the real one. It converts, in the arguments it is
# given, each absolute path that exists or whose parent directory exists (a
# file about to be written), and the module-directory variables FLOW_PY_BIN,
# FLOW_DEP_BIN and FLOW_BIN_LIB, then runs the real python3 with the same
# standard input. Text that only starts with a slash (`/flow:pr step 7a`) is
# left as it is: its parent is the root, which is not taken as evidence of a
# path. Off those platforms nothing is defined but py_path, and every helper
# runs exactly as before.
#
# FLOW_PY_PATH_PLATFORM overrides `uname -s` for the platform test (a test
# runs the Windows branch on another system with a stub cygpath).

_flow_py_platform() {
  printf '%s' "${FLOW_PY_PATH_PLATFORM:-$(uname -s 2>/dev/null)}"
}

py_path() {
  case "$(_flow_py_platform)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
      else
        printf '%s' "$1"
      fi ;;
    *) printf '%s' "$1" ;;
  esac
}

case "$(_flow_py_platform)" in
  MINGW*|MSYS*|CYGWIN*)
    # Only in front of a python3 that exists: `command -v python3` is how the
    # helpers decide python3 is missing, and a function would always answer.
    if command -v python3 >/dev/null 2>&1 && ! declare -F python3 >/dev/null 2>&1; then
      python3() {
        (
          _fpp_out=()
          for _fpp_a in "$@"; do
            case "$_fpp_a" in
              /*)
                _fpp_d=$(dirname -- "$_fpp_a" 2>/dev/null) || _fpp_d=/
                if [ -e "$_fpp_a" ] || { [ "$_fpp_d" != / ] && [ -d "$_fpp_d" ]; }; then
                  _fpp_a=$(py_path "$_fpp_a")
                fi ;;
            esac
            _fpp_out+=("$_fpp_a")
          done
          for _fpp_v in FLOW_PY_BIN FLOW_DEP_BIN FLOW_BIN_LIB; do
            eval "_fpp_val=\${$_fpp_v:-}"
            case "$_fpp_val" in
              /*) export "$_fpp_v=$(py_path "$_fpp_val")" ;;
            esac
          done
          exec python3 ${_fpp_out[@]+"${_fpp_out[@]}"}
        )
      }
    fi ;;
esac
