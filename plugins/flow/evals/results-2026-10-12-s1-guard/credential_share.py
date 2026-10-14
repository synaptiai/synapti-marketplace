#!/usr/bin/env python3
"""Count, among the distinct real Bash commands in the transcripts that the
cheap check does not rule out (the ones guard.command-intent would send),
those the credential rule of the shipped hook library
(hooks/scripts/lib/s1-guard.sh, _g_skip_credential) keeps from being sent, and
write credentialskip.json ({commands, not_ruled_out, skipped, unreadable,
share, library_sha256}) into --out: share is skipped of not_ruled_out, and
unreadable counts the commands whose shell forms the masking does not read (a
command substitution, a heredoc, a line continuation, an open quote), which
the hook does not send either. It also writes
ruledout.json from the same read, so the two shares count the same commands.
The library is the one ruled_out.sh loads (FLOW_GUARD_LIB, else the shipped
one); it is hashed before and after the run, and nothing is written when it
changed.

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
import hashlib  # noqa: E402
import json  # noqa: E402
import subprocess  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_sets  # noqa: E402

# The verdict is read through _g_credential_verdict, not _g_skip_credential:
# that answers "skip" when the verdict cannot be made, the right default in the
# hook and a wrong count here. A command with no verdict prints E, and the
# script then refuses to write. So does a command the word scanner fails on
# other than by refusing it (exit 1): awk missing or failing.
SCRIPT = ('. "$0" || exit 9; command -v jq >/dev/null 2>&1 || exit 9; '
          'while IFS= read -r -d "" c; do '
          '_g_words "$c" >/dev/null 2>&1; w=$?; '
          'if [ "$w" = 1 ]; then echo U; continue; elif [ "$w" != 0 ]; then echo E; continue; fi; '
          'r=$(_g_credential_verdict "$c" 2>/dev/null) || r=E; '
          'case "$r" in true) echo 1 ;; false) echo 0 ;; *) echo E ;; esac; done')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts", action="append", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--home", default="")
    a = ap.parse_args()
    calls = build_sets.read_transcripts(a.transcripts)
    cmds = sorted({build_sets.normalise(c, a.home) for c in calls})
    cmds = [c for c in cmds if c.strip() and len(c) <= build_sets.MAX_LEN and "\0" not in c]
    lib = os.environ.get("FLOW_GUARD_LIB") or os.path.join(PLUGIN, "hooks", "scripts", "lib", "s1-guard.sh")
    digest = build_sets.library_sha256(lib)
    flags = build_sets.ruled_out(cmds)
    sent = [c for c, f in zip(cmds, flags) if not f]
    r = subprocess.run(["bash", "-c", SCRIPT, lib], input=b"".join(c.encode() + b"\0" for c in sent),
                       capture_output=True)
    out = r.stdout.decode().split()
    if r.returncode != 0 or len(out) != len(sent) or "E" in out:
        sys.stderr.write("credential_share.py: the library answered %d of %d commands (exit %d)\n"
                         % (sum(1 for o in out if o != "E"), len(sent), r.returncode))
        return 1
    n = sum(1 for o in out if o == "1")
    if build_sets.library_sha256(lib) != digest:
        sys.stderr.write("credential_share.py: the library changed during the run\n")
        return 1
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "ruledout.json"), "w", encoding="utf-8") as f:
        json.dump({"commands": len(cmds), "ruled_out": sum(flags),
                   "share": round(sum(flags) / len(cmds), 4) if cmds else None,
                   "library_sha256": digest}, f, sort_keys=True)
        f.write("\n")
    with open(os.path.join(a.out, "credentialskip.json"), "w", encoding="utf-8") as f:
        json.dump({"commands": len(cmds), "not_ruled_out": len(sent), "skipped": n,
                   "unreadable": sum(1 for o in out if o == "U"),
                   "share": round(n / len(sent), 4) if sent else None,
                   "library_sha256": digest}, f, sort_keys=True)
        f.write("\n")
    print("COMMANDS=%d NOT_RULED_OUT=%d SKIPPED=%d UNREADABLE=%d"
          % (len(cmds), len(sent), n, sum(1 for o in out if o == "U")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
