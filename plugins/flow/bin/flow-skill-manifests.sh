#!/usr/bin/env bash
# [flow] Regenerate the tables in references/skill-manifests.md.
#
# Usage:
#   flow-skill-manifests.sh            print the regenerated file on stdout
#   flow-skill-manifests.sh --write    rewrite references/skill-manifests.md
#
# The file is its own template: everything outside the generated regions is
# kept as written. Each region sits between
#   <!-- BEGIN GENERATED: <name> (bin/flow-skill-manifests.sh) -->
#   <!-- END GENERATED: <name> -->
# and the three regions are:
#   commands  one row per commands/*.md: the skills its `## Required Skills`
#             bullets name, how many load whole (ambient) and how many load
#             only their Contract, and the words inlined, the sum of the
#             words= values bin/flow-load-skills.sh --list reports (wc -w)
#   skills    one row per skills/<name>/SKILL.md: loading mode, body words
#             (frontmatter stripped, split on whitespace by python, as
#             tests/flow-load-skills.test.sh counts them) and the description
#   budget    the largest command load and the sum across commands
#
# tests/flow-load-skills.test.sh fails when the committed file differs from
# this script's output.
#
# Exits: 0 with the file on stdout (or written); 1 when a region's markers are
# missing or repeated, a required skill does not load, or python3 or PyYAML is
# missing; 2 on usage error.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
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

WRITE=0
case "${1-}" in
  "") ;;
  --write) WRITE=1 ;;
  *) printf '%s\n' "usage: flow-skill-manifests.sh [--write]" >&2; exit 2 ;;
esac

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$PLUGIN_ROOT/references/skill-manifests.md"

OUT=$(python3 - "$PLUGIN_ROOT" "$FILE" <<'PYEOF'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import re, subprocess
try:
    import yaml
except ImportError:
    sys.exit("flow-skill-manifests: PyYAML is required")

root, path = sys.argv[1], sys.argv[2]
loader = os.path.join(root, "bin", "flow-load-skills.sh")

def fail(msg):
    sys.stderr.write("flow-skill-manifests: %s\n" % msg)
    sys.exit(1)

def split(text):
    """Frontmatter dict and body, as the loader and the size check split them."""
    lines = text.split("\n")
    if lines and lines[0] == "---":
        for i in range(1, len(lines)):
            if lines[i] == "---":
                return yaml.safe_load("\n".join(lines[1:i])) or {}, "\n".join(lines[i + 1:])
    return {}, text

def cell(s):
    return s.replace("|", "\\|").replace("\n", " ")

# --- commands
rows, totals = [], []
for f in sorted(os.listdir(os.path.join(root, "commands"))):
    if not f.endswith(".md"):
        continue
    text = open(os.path.join(root, "commands", f), encoding="utf-8").read()
    # The section runs to the next "## " heading or the end of the file; a
    # line that only starts with "#" (a comment in the inlining fence) does
    # not end it. A section must list a skill or say "_None".
    m = re.search(r"^## Required Skills\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    names = re.findall(r"^- `([a-z0-9-]+)`", m.group(1), re.M) if m else []
    if m and not names and not re.search(r"^_None", m.group(1), re.M):
        fail("commands/%s: the Required Skills section lists no skill and has no _None line" % f)
    amb = con = words = 0
    if names:
        # This plugin's skills, whatever CLAUDE_PLUGIN_ROOT names.
        env = dict(os.environ, FLOW_SKILLS_DIR=os.path.join(root, "skills"))
        res = subprocess.run(["bash", loader, "--list"] + names, capture_output=True, text=True, env=env)
        errors = re.findall(r"^SKILL_LOAD_ERROR=.*$", res.stdout, re.M)
        if res.returncode != 0 or errors:
            fail("commands/%s: %s" % (f, "; ".join(errors) or "the loader exited %d" % res.returncode))
        got = re.findall(r"^SKILL_LOADED=(\S+) mode=(\S+) words=(\d+)$", res.stdout, re.M)
        if [g[0] for g in got] != names:
            fail("commands/%s: the loader reported %s for %s" % (f, [g[0] for g in got], names))
        amb = sum(1 for g in got if g[1] == "ambient")
        con = sum(1 for g in got if g[1] == "contract")
        words = sum(int(g[2]) for g in got)
    cmd = "/flow:" + f[:-3]
    totals.append((words, cmd))
    rows.append("| `%s` | %s | %d | %d | %d |" % (cmd, ", ".join(names) or "(none)", amb, con, words))
if not rows:
    fail("no command files under %s/commands" % root)
commands = "\n".join(["| Command | Required skills | Ambient | Contracts | Words inlined |",
                      "|---------|-----------------|---------|-----------|---------------|"] + rows)

# --- skills
srows = []
sdir = os.path.join(root, "skills")
for name in sorted(os.listdir(sdir)):
    p = os.path.join(sdir, name, "SKILL.md")
    if not os.path.isfile(p):
        continue
    fm, body = split(open(p, encoding="utf-8").read())
    dispatched = fm.get("context") == "fork" or bool(str(fm.get("agent") or "").strip())
    mode = "dispatched" if dispatched else "ambient"
    if fm.get("disable-model-invocation") is True:
        mode += " · reference-only"
    desc = " ".join(str(fm.get("description") or "").split())
    if len(desc) > 105:
        desc = desc[:105].rstrip(" ,;:") + "..."
    srows.append("| %s | %s | %d | %s |" % (name, mode, len(body.split()), cell(desc)))
if not srows:
    fail("no skills under %s" % sdir)
skills = "\n".join(["| Skill | Loading | Body words | Purpose |",
                    "|-------|---------|------------|---------|"] + srows)

# --- budget
top = max(totals)
budget = ("The largest command load today is `%s` at %d words; the sum across all commands is %d."
          % (top[1], top[0], sum(w for w, _ in totals)))

text = open(path, encoding="utf-8").read()
for name, content in (("commands", commands), ("skills", skills), ("budget", budget)):
    begin = "<!-- BEGIN GENERATED: %s (bin/flow-skill-manifests.sh) -->\n" % name
    end = "<!-- END GENERATED: %s -->\n" % name
    if text.count(begin) != 1 or text.count(end) != 1 or text.index(begin) > text.index(end):
        fail("%s: the %s region must have one BEGIN marker followed by one END marker" % (path, name))
    s = text.index(begin) + len(begin)
    text = text[:s] + content + "\n" + text[text.index(end):]
sys.stdout.write(text)
PYEOF
) || exit 1

if [ "$WRITE" -eq 1 ]; then
  printf '%s\n' "$OUT" > "$FILE" || exit 1
else
  printf '%s\n' "$OUT"
fi
