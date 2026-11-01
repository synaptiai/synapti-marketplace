#!/usr/bin/env bash
# [flow] Check that a FlowTrigger forbids merge and release, unless
# flow.triggers.allowAutonomousMerge is true.
#
# Usage:
#   flow-trigger-tier3-check.sh <trigger.yaml>
#
# Step 2 of skills/trigger-policy/SKILL.md. A trigger's policy.forbidden_actions
# must list both merge and release. When flow.triggers.allowAutonomousMerge
# is true, a trigger may leave either out, so the command a trigger runs may
# include /flow:merge or /flow:release; those still ask before they merge or
# release, and flow's tier hook asks again, because tiers.merge and
# tiers.release never go below confirm. The setting is read from the user's
# settings and the plugin default only (cascade-resolve.sh --no-repo-settings):
# a repository's own settings cannot relax this check.
#
# Stdout: one TIER3_VIOLATION=<action> line for each of merge and release the
# trigger does not forbid.
# Exits: 0 no violation; 2 violations; 1 when the check could not run: the
# trigger is a symbolic link, not a regular file, unreadable or not a YAML
# mapping, the setting cannot be read or is not true or false, or python3 or
# PyYAML is missing (one flow-trigger-tier3-check line on stderr says which).

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# PYTHONPATH and sys.path are cleaned first: the trigger comes with the
# repository, and so could a planted yaml.py or sitecustomize.py.
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi

# The setting is read with the cascade-resolve.sh beside this script, found
# through any symbolic links to it.
_self="$0"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$(dirname "$_self")/$_link" ;;
  esac
  _hops=$((_hops + 1))
done
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || { printf 'flow-trigger-tier3-check: cannot find its own directory\n' >&2; exit 1; }

python3 - "${1-}" "$SELF_DIR/cascade-resolve.sh" <<'PYEOF'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import errno, stat, subprocess

def fail(msg):
    sys.stderr.write("flow-trigger-tier3-check: %s\n" % msg)
    sys.exit(1)

try:
    import yaml
except ImportError:
    fail("PyYAML is required (pip install pyyaml)")

# The trigger comes with the repository, so it is never read through a
# symbolic link: O_NOFOLLOW refuses a link at the open itself, O_NONBLOCK opens
# a FIFO in its place at once, and fstat refuses anything but a regular file.
path = sys.argv[1]
nofollow = getattr(os, "O_NOFOLLOW", 0)
if not nofollow and os.path.islink(path):
    fail("the trigger is a symbolic link; it is not read")
try:
    fd = os.open(path, os.O_RDONLY | nofollow | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_BINARY", 0))
except OSError as e:
    if e.errno == errno.ELOOP:
        fail("the trigger is a symbolic link; it is not read")
    fail("cannot read the trigger: %s" % e.strerror)
with os.fdopen(fd, "rb") as f:
    if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
        fail("the trigger is not a regular file")
    raw = f.read()
try:
    doc = yaml.safe_load(raw.decode("utf-8"))
except (yaml.YAMLError, UnicodeDecodeError):
    fail("the trigger is not valid YAML")
if not isinstance(doc, dict):
    fail("the trigger is not a YAML mapping")
policy = doc.get("policy")
policy = policy if isinstance(policy, dict) else {}
forbidden = policy.get("forbidden_actions")
forbidden = forbidden if isinstance(forbidden, list) else []

r = subprocess.run([sys.argv[2], "--no-repo-settings", "--default", "false", ".flow.triggers.allowAutonomousMerge"],
                   stdout=subprocess.PIPE)
if r.returncode != 0:
    fail("flow.triggers.allowAutonomousMerge could not be read (cascade-resolve.sh exited %d)" % r.returncode)
allow = r.stdout.decode("utf-8", "replace").strip()
if allow not in ("true", "false"):
    fail("flow.triggers.allowAutonomousMerge is %r, not true or false" % allow[:40])

violations = []
if allow != "true":
    for action in ("merge", "release"):
        if action not in forbidden:
            violations.append(action)
for action in violations:
    print("TIER3_VIOLATION=%s" % action)
sys.exit(2 if violations else 0)
PYEOF
