# Every Python entry point in the plugin keeps the working directory off
# sys.path before it imports anything.
#
# Flow's scripts and hooks run with the repository as their working directory,
# and during a review that repository is the pull request. A yaml.py, json.py
# or glob.py planted there runs in place of the real module whenever the
# working directory is on sys.path when the import happens. It gets there two
# ways: as "" or "." for `python3 -c` and `python3 -` when PYTHONSAFEPATH is
# not honored (Python before 3.11; macOS /usr/bin/python3 is 3.9), and as an
# absolute path, on every version, when PYTHONPATH has an empty element
# (`export PYTHONPATH="$PYTHONPATH:/x"` with PYTHONPATH unset). A filter of
# "" and "." misses the second, and a filter placed after an import misses
# both, which is how the Stop hook was.
#
# The rule does not depend on judging which modules are safe to import early:
# before any import other than `os` and `sys` (both loaded by the interpreter
# before any user code runs), each unit runs the canonical guard, which drops
# every relative entry and every entry that resolves to the working directory.
# A unit is a .py file, a Python heredoc in a shell script or command fence,
# or a `python3 -c` string.

FLOW_DIR="$REPO_ROOT/plugins/flow"

SPG_REPORT=$(python3 - "$FLOW_DIR" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
GUARD = "sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]"
OLD = re.compile(r'not in \(\s*""\s*,\s*"\."\s*\)')
IMPORT = re.compile(r'^\s*(import|from)\s+([\w.]+)')

def risky(line):
    m = IMPORT.match(line)
    if not m:
        return False
    if m.group(1) == "from":
        return True
    names = [n.split(" as ")[0].strip() for n in line.split("#")[0].strip()[len("import"):].split(",")]
    return any(n not in ("os", "sys") for n in names)

def check_lines(where, lines, bad):
    seen_guard = False
    for i, l in enumerate(lines):
        if GUARD in l:
            seen_guard = True
        if risky(l):
            if not seen_guard:
                bad.append("%s: %r runs before the guard" % (where(i), l.strip()[:60]))
            return 1
    return 0

def heredocs(lines):
    i = 0
    while i < len(lines):
        m = None if lines[i].lstrip().startswith("#") else re.search(r"<<-?\s*['\"]?([A-Za-z_]\w*)['\"]?", lines[i])
        if m:
            tag, j = m.group(1), i + 1
            while j < len(lines) and lines[j].strip() != tag:
                j += 1
            body = lines[i + 1:j]
            # A heredoc is Python when its body imports something; a
            # heredoc that never closes is not a heredoc (it is prose).
            if j < len(lines) and any(IMPORT.match(x) for x in body):
                yield i + 1, body
                i = j
        i += 1

def one_liners(text):
    for m in re.finditer(r"python3 -c (['\"])(.*?)\1", text, re.S):
        line_start = text.rfind("\n", 0, m.start()) + 1
        if text[line_start:m.start()].lstrip().startswith("#"):
            continue  # quoted in a comment: prose, not a call
        yield text[:m.start()].count("\n") + 1, m.group(2)

bad, units = [], 0
files = sorted(glob.glob(root + "/bin/*.sh") + glob.glob(root + "/bin/*.py") + glob.glob(root + "/bin/lib/*")
               + glob.glob(root + "/hooks/scripts/*.sh") + glob.glob(root + "/hooks/scripts/lib/*")
               + glob.glob(root + "/commands/*.md"))
for f in files:
    if not os.path.isfile(f) or "__pycache__" in f:
        continue
    rel = os.path.relpath(f, root)
    text = open(f, encoding="utf-8").read()
    lines = text.splitlines()
    for n, l in enumerate(lines, 1):
        if OLD.search(l):
            bad.append("%s:%d: the old filter of \"\" and \".\" only" % (rel, n))
    if f.endswith(".py"):
        units += check_lines(lambda i: "%s:%d" % (rel, i + 1), lines, bad)
        continue
    for start, block in heredocs(lines):
        units += check_lines(lambda i, s=start: "%s:%d" % (rel, s + i + 1), block, bad)
    for n, code in one_liners(text):
        stmts = [s.strip() for s in re.split(r"[;\n]", code)]
        units += check_lines(lambda i, n=n: "%s:%d (python3 -c)" % (rel, n), stmts, bad)
print("UNITS=%d" % units)
for b in bad:
    print("BAD=" + b)
PY
)

_flow_test_begin "every python unit runs the sys.path guard before its first import"
assert_match '^UNITS=[1-9][0-9]+$' "$(printf '%s\n' "$SPG_REPORT" | grep '^UNITS=')" "the scan reached the python units"
assert_equal "" "$(printf '%s\n' "$SPG_REPORT" | grep '^BAD=' | head -20)" "units that import before the guard, or keep the old filter"
