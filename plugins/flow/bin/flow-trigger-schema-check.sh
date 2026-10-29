#!/usr/bin/env bash
# [flow] Validate a FlowTrigger YAML against schemas/v1/trigger.schema.json.
#
# Usage:
#   flow-trigger-schema-check.sh <trigger.yaml>
#
# Step 1 of skills/trigger-policy/SKILL.md. The schema is read from the plugin
# this script ships in, so the check works in a project with no plugins/flow
# directory.
#
# Stdout: one SCHEMA_ERROR=<path>: <message> line per schema error.
# Exits: 0 valid; 2 schema errors; 1 when the trigger or the schema cannot be
# read, or python3, PyYAML or jsonschema is missing.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# PYTHONPATH and sys.path are cleaned first: the trigger comes with the
# repository, and so could a planted jsonschema.py or sitecustomize.py.
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

SCHEMA="$(cd "$(dirname "$0")/.." && pwd)/schemas/v1/trigger.schema.json"

python3 - "${1-}" "$SCHEMA" <<'PYEOF'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import json, yaml, jsonschema
with open(sys.argv[1], encoding="utf-8") as f:
    doc = yaml.safe_load(f)
with open(sys.argv[2], encoding="utf-8") as f:
    schema = json.load(f)
validator = jsonschema.validators.validator_for(schema)(schema)
errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.path))
for e in errors:
    print("SCHEMA_ERROR=%s: %s" % ("/".join(map(str, e.path)) or "(root)", e.message))
sys.exit(2 if errors else 0)
PYEOF
