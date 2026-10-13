#!/usr/bin/env python3
"""Count the distinct real Bash commands in the transcripts that the
credential rule of the shipped hook library (hooks/scripts/lib/s1-guard.sh,
_g_skip_credential) keeps from being sent, and write credentialskip.json
({commands, skipped, share}) into --out.

The commands are read and normalised as build_sets.py reads them for
ruledout.json: deduplicated, at most build_sets.MAX_LEN characters, the home
path replaced.

Usage: credential_share.py --transcripts <dir> [--transcripts <dir> ...]
                           --out <dir> [--home <path>]
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import argparse  # noqa: E402
import json  # noqa: E402
import subprocess  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_sets  # noqa: E402

SCRIPT = ('. "$0" || exit 9; while IFS= read -r -d "" c; do '
          'if _g_skip_credential "$c"; then echo 1; else echo 0; fi; done')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts", action="append", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--home", default="")
    a = ap.parse_args()
    calls = build_sets.read_transcripts(a.transcripts)
    cmds = sorted({build_sets.normalise(c, a.home) for c in calls})
    cmds = [c for c in cmds if c.strip() and len(c) <= build_sets.MAX_LEN and "\0" not in c]
    lib = os.path.join(PLUGIN, "hooks", "scripts", "lib", "s1-guard.sh")
    r = subprocess.run(["bash", "-c", SCRIPT, lib], input=b"".join(c.encode() + b"\0" for c in cmds),
                       capture_output=True)
    out = r.stdout.decode().split()
    if r.returncode != 0 or len(out) != len(cmds):
        sys.stderr.write("credential_share.py: the library answered %d of %d commands (exit %d)\n"
                         % (len(out), len(cmds), r.returncode))
        return 1
    n = sum(1 for o in out if o == "1")
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "credentialskip.json"), "w", encoding="utf-8") as f:
        json.dump({"commands": len(cmds), "skipped": n, "share": round(n / len(cmds), 4) if cmds else None},
                  f, sort_keys=True)
        f.write("\n")
    print("COMMANDS=%d SKIPPED=%d" % (len(cmds), n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
