"""Faults for the factory probe scenarios. At start Python runs the
usercustomize module it finds in the user site-packages folder (-E leaves
that on), so a scenario that puts this file in its scratch HOME's user
site-packages (_fp_inject) has it run in every Python started with that HOME.
Only the probe itself is changed, _flow_factory.py run without shim-log, and
only by the faults listed one per line in inject.txt beside this file:

  popen <word>        subprocess.Popen raises KeyboardInterrupt after it has
                      started a command with <word> among its arguments, as
                      an interrupt that lands before Popen returns does
  popen-error <word>  the same, with RuntimeError: an error, not a stop
  rename <from> <to>  os.rename and os.replace raise KeyboardInterrupt before
                      moving anything when the source path matches the
                      pattern <from> and the destination <to> (fnmatch, in
                      which * also matches /)
"""
import fnmatch
import os
import sys


def _faults():
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "inject.txt"), encoding="utf-8") as f:
            return [ln.split() for ln in f if ln.strip()]
    except OSError:
        return []


def _install(faults):
    words = {f[1] for f in faults if f[0] == "popen" and len(f) == 2}
    errors = {f[1] for f in faults if f[0] == "popen-error" and len(f) == 2}
    moves = [(f[1], f[2]) for f in faults if f[0] == "rename" and len(f) == 3]
    if words or errors:
        import subprocess
        start = subprocess.Popen.__init__

        def started_then_interrupted(self, args, *rest, **kwargs):
            start(self, args, *rest, **kwargs)
            given = [str(a) for a in (args if isinstance(args, (list, tuple)) else [args])]
            if any(a in words for a in given):
                raise KeyboardInterrupt
            if any(a in errors for a in given):
                raise RuntimeError("injected after the command started")

        subprocess.Popen.__init__ = started_then_interrupted
    if moves:
        def interrupt_move(event, args):
            if event != "os.rename":
                return
            src, dst = os.fsdecode(args[0]), os.fsdecode(args[1])
            if any(fnmatch.fnmatchcase(src, a) and fnmatch.fnmatchcase(dst, b) for a, b in moves):
                raise KeyboardInterrupt

        sys.addaudithook(interrupt_move)


if sys.argv and sys.argv[0].endswith("_flow_factory.py") and "shim-log" not in sys.argv:
    _install(_faults())
