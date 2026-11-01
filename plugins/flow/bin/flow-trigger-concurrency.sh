#!/usr/bin/env bash
# [flow] The concurrency check /flow:run trigger <id> and /flow:trigger run <id>
# make before they dispatch the trigger's target.
#
# Usage:
#   flow-trigger-concurrency.sh <trigger-id>
#
# Run from the repository root. Reads .flow/triggers/<id>.trigger.yaml for its
# concurrency.policy (when the trigger sets none, the setting
# flow.triggers.defaultConcurrency, read with cascade-resolve.sh, applies),
# and every .flow/runs/<run>/run.yaml for runs this
# trigger started: a run whose metadata.trigger is <id> and whose
# state.status is active is in flight. A run that records no trigger, or
# another trigger, is never this trigger's, whatever its workflow.
#
# Stdout:
#   CONCURRENCY_POLICY=<skip_if_running|queue|cancel_previous>
#   POLICY_SOURCE=trigger     the trigger sets concurrency.policy
#   POLICY_SOURCE=setting     it does not; flow.triggers.defaultConcurrency
#                             (shipped as skip_if_running) applies
#   IN_FLIGHT=<run id>        one line per run in flight, oldest id first
#
# Never read (each is skipped, with one line on stderr): a symbolic link at
# .flow, .flow/runs, a run directory or a run.yaml (it can point outside the
# checkout), and a run.yaml that is not a YAML mapping.
#
# Exits: 0 the check ran; 1 the id is not a trigger id, the trigger is
# missing, a symbolic link, not a regular file or not a YAML mapping, the
# policy (the trigger's or the setting's) is not one of the three, the setting
# cannot be read, or python3 or PyYAML is missing (one flow-trigger-concurrency
# line on stderr says which).

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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || { printf 'flow-trigger-concurrency: cannot find its own directory\n' >&2; exit 1; }

python3 - "${1-}" "$SELF_DIR/cascade-resolve.sh" <<'PYEOF'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import errno, re, stat, subprocess

def fail(msg):
    sys.stderr.write("flow-trigger-concurrency: %s\n" % msg)
    sys.exit(1)

def warn(msg):
    sys.stderr.write("flow-trigger-concurrency: %s\n" % msg)

try:
    import yaml
except ImportError:
    fail("PyYAML is required (pip install pyyaml)")

POLICIES = ("skip_if_running", "queue", "cancel_previous")
tid = sys.argv[1]
# The trigger schema's id pattern: no '/', no '..', so the name stays inside
# .flow/triggers.
if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", tid):
    fail("%r is not a trigger id (lower-case letters, digits and '-')" % tid[:80])

def read_regular(path):
    # O_NOFOLLOW refuses a link at the open itself; O_NONBLOCK opens a FIFO in
    # the file's place at once, and fstat refuses it.
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    if not nofollow and os.path.islink(path):
        raise OSError(errno.ELOOP, "symbolic link")
    fd = os.open(path, os.O_RDONLY | nofollow | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_BINARY", 0))
    with os.fdopen(fd, "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise OSError(errno.EINVAL, "not a regular file")
        return f.read().decode("utf-8")

def is_link(path):
    try:
        return stat.S_ISLNK(os.lstat(path).st_mode)
    except OSError:
        return False

tpath = os.path.join(".flow", "triggers", tid + ".trigger.yaml")
for d in (".flow", os.path.join(".flow", "triggers")):
    if is_link(d):
        fail("%s is a symbolic link; the trigger is not read" % d)
try:
    trigger = yaml.safe_load(read_regular(tpath))
except OSError as e:
    if e.errno == errno.ENOENT:
        fail("no trigger %s (looked for %s)" % (tid, tpath))
    if e.errno == errno.ELOOP:
        fail("%s is a symbolic link; it is not read" % tpath)
    fail("cannot read %s: %s" % (tpath, e.strerror))
except (yaml.YAMLError, UnicodeDecodeError):
    fail("%s is not valid YAML" % tpath)
if not isinstance(trigger, dict):
    fail("%s is not a YAML mapping" % tpath)

conc = trigger.get("concurrency")
policy = conc.get("policy") if isinstance(conc, dict) else None
if policy is None:
    # The cascade's own message, if any, goes straight to stderr.
    r = subprocess.run([sys.argv[2], "--default", "skip_if_running", ".flow.triggers.defaultConcurrency"],
                       stdout=subprocess.PIPE)
    if r.returncode != 0:
        fail("flow.triggers.defaultConcurrency could not be read (cascade-resolve.sh exited %d)" % r.returncode)
    policy, source = r.stdout.decode("utf-8", "replace").strip(), "setting"
    if policy not in POLICIES:
        fail("flow.triggers.defaultConcurrency is %r, not one of %s" % (policy[:40], ", ".join(POLICIES)))
else:
    source = "trigger"
if policy not in POLICIES:
    fail("concurrency.policy %r in %s is not one of %s" % (str(policy)[:40], tpath, ", ".join(POLICIES)))

in_flight = []
runs = os.path.join(".flow", "runs")
if is_link(".flow") or is_link(runs):
    warn("%s is a symbolic link; no run under it is read" % (".flow" if is_link(".flow") else runs))
elif os.path.isdir(runs):
    for name in sorted(os.listdir(runs)):
        rdir = os.path.join(runs, name)
        ryaml = os.path.join(rdir, "run.yaml")
        if is_link(rdir):
            warn("%s is a symbolic link; it is not read" % rdir)
            continue
        if not os.path.isdir(rdir):
            continue
        try:
            run = yaml.safe_load(read_regular(ryaml))
        except OSError as e:
            if e.errno == errno.ENOENT:
                continue
            if e.errno == errno.ELOOP:
                warn("%s is a symbolic link; it is not read" % ryaml)
            else:
                warn("cannot read %s: %s; skipped" % (ryaml, e.strerror))
            continue
        except (yaml.YAMLError, UnicodeDecodeError):
            warn("%s is not valid YAML; skipped" % ryaml)
            continue
        if not isinstance(run, dict):
            warn("%s is not a YAML mapping; skipped" % ryaml)
            continue
        meta = run.get("metadata") if isinstance(run.get("metadata"), dict) else {}
        state = run.get("state") if isinstance(run.get("state"), dict) else {}
        if meta.get("trigger") == tid and state.get("status") == "active":
            in_flight.append(name)

print("CONCURRENCY_POLICY=%s" % policy)
print("POLICY_SOURCE=%s" % source)
for name in in_flight:
    print("IN_FLIGHT=%s" % name)
PYEOF
