# shellcheck shell=bash
# A trap for reads that wait on a FIFO, shared by the suites that set it.
#
# fifo_trap_site <dir> writes <dir>/sitecustomize.py. With <dir> first on
# PYTHONPATH, every python3 a command starts runs it at start-up:
#
#   - With SPY_HUNG_LOG set, a watchdog: after SPY_WATCHDOG seconds (8 unless
#     set) the process appends "a python3 waited <n> seconds at <file>:<line>"
#     to SPY_HUNG_LOG and exits 142. A blocking open is interrupted by the
#     alarm, and the handler runs before the call is retried, so the line
#     names where it waited. An empty log means no python3 waited.
#   - With SPY_FIFO_PATH set, every open of that path, by the builtin open()
#     or by os.open(), in any process, is counted in SPY_FIFO_LOG, one line
#     each, "<ordinal> <file>:<line>". Just before the SPY_FIFO_AT-th open
#     (none when 0 or unset), a regular file at the path is replaced by a FIFO
#     nothing writes to: the reader meets it after whatever check it made by
#     name.
#
# The sitecustomize then runs any sitecustomize it hides, so a python3 that
# had one still has it.

FIFO_TRAP_PY='
import builtins as _b18, os as _o18, signal as _s18, sys as _y18


def _hung18(signum, frame):
    # The frame that waited, not the wrapper around open() in this shim.
    while frame is not None and frame.f_code.co_filename == __file__:
        frame = frame.f_back
    try:
        with _b18_real_open(_o18.environ["SPY_HUNG_LOG"], "a") as _f18:
            _f18.write("a python3 waited %s seconds at %s:%d\n" % (
                _o18.environ.get("SPY_WATCHDOG", "8"),
                _o18.path.basename(frame.f_code.co_filename) if frame else "?",
                frame.f_lineno if frame else 0))
    finally:
        _o18._exit(142)


_b18_real_open = _b18.open
if _o18.environ.get("SPY_HUNG_LOG"):
    _s18.signal(_s18.SIGALRM, _hung18)
    _s18.alarm(int(_o18.environ.get("SPY_WATCHDOG", "8")))

def _where18(path):
    # The path with its directory resolved: a process whose working directory
    # is reached through a symlink (/var on macOS) names it by the real path.
    path = _o18.path.abspath(path)
    return _o18.path.join(_o18.path.realpath(_o18.path.dirname(path)), _o18.path.basename(path))


_p18 = _o18.environ.get("SPY_FIFO_PATH", "")
if _p18:
    _abs18 = _where18(_p18)
    _at18 = int(_o18.environ.get("SPY_FIFO_AT", "0") or "0")
    _real_os_open18 = _o18.open

    def _note18(path):
        try:
            if isinstance(path, int) or _where18(_o18.fsdecode(path)) != _abs18:
                return
        except (TypeError, ValueError):
            return
        _fr18 = _y18._getframe(2)
        with _b18_real_open(_o18.environ["SPY_FIFO_LOG"], "a+") as _f18:
            _f18.seek(0)
            _n18 = len(_f18.readlines()) + 1
            _f18.write("%d %s:%d\n" % (_n18, _o18.path.basename(_fr18.f_code.co_filename), _fr18.f_lineno))
        if _n18 == _at18 and _o18.path.isfile(_abs18) and not _o18.path.islink(_abs18):
            _o18.unlink(_abs18)
            _o18.mkfifo(_abs18)

    def _open18(file, *a, **k):
        _note18(file)
        return _b18_real_open(file, *a, **k)

    def _os_open18(path, *a, **k):
        _note18(path)
        return _real_os_open18(path, *a, **k)

    _b18.open = _open18
    _o18.open = _os_open18
'

fifo_trap_site() {
  mkdir -p "$1"
  {
    printf '%s\n' "$FIFO_TRAP_PY"
    cat <<'CHAIN'
import os as _os, sys as _sys
def _fifo_trap_chain():
    here = _os.path.dirname(_os.path.abspath(__file__))
    for d in _sys.path:
        p = _os.path.join(_os.path.abspath(d or "."), "sitecustomize.py")
        if _os.path.dirname(p) != here and _os.path.isfile(p):
            exec(compile(open(p).read(), p, "exec"), {"__name__": "sitecustomize", "__file__": p})
            return
_fifo_trap_chain()
CHAIN
  } > "$1/sitecustomize.py"
}
