#!/usr/bin/env bash
# [flow] Check a FlowTrigger's recursion_policy against
# flow.triggers.allowTriggerCreationFromTriggeredRun.
#
# Usage:
#   flow-trigger-recursion-check.sh <trigger.yaml>
#
# Step 3 of skills/trigger-policy/SKILL.md. A trigger's recursion_policy has
# three flags, each false when unset:
#   triggered_runs_may_create_triggers  refused unless the setting
#                                       flow.triggers.allowTriggerCreationFromTriggeredRun
#                                       is true (shipped false)
#   triggered_runs_may_modify_triggers  always refused
#   triggered_runs_may_enable_triggers  always refused
# Any value other than false or unset counts as set. The setting is read from
# the whole settings cascade, so a team can turn it on for everyone in the
# repository's settings. That also means a repository can ship a trigger that
# lets its runs create triggers together with the setting that accepts it
# (the tier-3 check, by contrast, reads the user's settings only).
#
# Stdout: one RECURSION_VIOLATION=<flag> line per refused flag.
# Exits: 0 no violation; 2 violations; 1 when the check could not run: the
# trigger is a symbolic link, not a regular file, unreadable or not a YAML
# mapping, the setting cannot be read or is not true or false, or python3 or
# PyYAML is missing (one flow-trigger-recursion-check line on stderr says
# which).

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

# The setting is read with the cascade-resolve.sh beside this script, and the
# trigger with _flow_trigger_read.py beside it, found through any symbolic
# links to it.
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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || { printf 'flow-trigger-recursion-check: cannot find its own directory\n' >&2; exit 1; }

python3 - "${1-}" "$SELF_DIR/cascade-resolve.sh" "$SELF_DIR" <<'PYEOF'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import subprocess

def fail(msg):
    sys.stderr.write("flow-trigger-recursion-check: %s\n" % msg)
    sys.exit(1)

try:
    import yaml
except ImportError:
    fail("PyYAML is required (pip install pyyaml)")

# The reading is shared with the other trigger checks: bin/_flow_trigger_read.py.
sys.path.insert(0, sys.argv[3])
try:
    from _flow_trigger_read import ReadError, read_yaml_mapping
except ImportError:
    fail("cannot load _flow_trigger_read.py from %s" % sys.argv[3])

# The trigger comes with the repository, so it is never read through a
# symbolic link, and only a regular file holding a YAML mapping is judged.
try:
    doc = read_yaml_mapping(sys.argv[1])
except ReadError as e:
    fail({"link": "the trigger is a symbolic link; it is not read",
          "not-regular": "the trigger is not a regular file",
          "not-yaml": "the trigger is not valid YAML",
          "not-mapping": "the trigger is not a YAML mapping"}.get(e.kind, "cannot read the trigger: %s" % e.reason))
rp = doc.get("recursion_policy")
rp = rp if isinstance(rp, dict) else {}

# The cascade's own message, if any, goes straight to stderr.
r = subprocess.run([sys.argv[2], "--default", "false",
                    ".flow.triggers.allowTriggerCreationFromTriggeredRun"],
                   stdout=subprocess.PIPE)
if r.returncode != 0:
    fail("flow.triggers.allowTriggerCreationFromTriggeredRun could not be read (cascade-resolve.sh exited %d)" % r.returncode)
allow = r.stdout.decode("utf-8", "replace").strip()
if allow not in ("true", "false"):
    fail("flow.triggers.allowTriggerCreationFromTriggeredRun is %r, not true or false" % allow[:40])

violations = []
for flag in ("triggered_runs_may_create_triggers", "triggered_runs_may_modify_triggers",
             "triggered_runs_may_enable_triggers"):
    value = rp.get(flag)
    if value is None or value is False:
        continue
    if flag == "triggered_runs_may_create_triggers" and value is True and allow == "true":
        continue
    violations.append(flag)
for flag in violations:
    print("RECURSION_VIOLATION=%s" % flag)
sys.exit(2 if violations else 0)
PYEOF
