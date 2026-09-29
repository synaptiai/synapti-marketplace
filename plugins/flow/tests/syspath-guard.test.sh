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
#
# The guard runs inside Python, which is too late for one thing: at startup
# the interpreter imports sitecustomize, usercustomize and the encodings
# package from every PYTHONPATH element, and an empty element is the working
# directory. So every shell script, and every command fence, that runs
# python3 first cleans PYTHONPATH with the canonical sanitizer. It keeps only
# absolute elements that are outside the repository and are not the working
# directory or one of its ancestors, and unsets PYTHONPATH when none is left.
# The repository is the nearest directory at or above the working directory
# that has a .git entry (a worktree has a .git file), or the working directory
# when there is none; the nearest, because a home directory kept in git would
# otherwise make every element under home count as the repository. A
# PYTHONPATH element inside the checkout is common (a src/ layout set by
# direnv), and a pull request checked out there can plant a sitecustomize.py
# in it. When the working directory cannot be read, every element is dropped.
# The original is kept in FLOW_USER_PYTHONPATH for commands Flow runs on the
# user's behalf.
#
# The in-process guard is deliberately narrower: it drops only relative
# entries and the working directory. sys.path also holds site-packages, and a
# project's virtual environment often sits inside the repository (.venv/); a
# guard that dropped every entry under the repository would remove PyYAML for
# everyone whose python3 is that environment. Entries that came from
# PYTHONPATH never reach it inside the repository, because the sanitizer has
# already removed them.

FLOW_DIR="$REPO_ROOT/plugins/flow"

SPG_REPORT=$(python3 - "$FLOW_DIR" <<'PY'
import glob, os, re, sys
root = sys.argv[1]

# The canonical forms, verbatim. A partial copy (a sanitizer that keeps
# relative elements, a guard that sets _flow_cwd = None) is as unsafe as none.
GUARD = [
    "import os, sys",
    "try:",
    "    _flow_cwd = os.path.realpath(os.getcwd())",
    "except OSError:",
    "    _flow_cwd = None",
    "sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]",
]
ONE_LINER = ("import os, sys; _flow_cwd = os.path.realpath(os.getcwd()); "
             "sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]; ")
SANITIZER = [
    '[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"',
    '_flow_pp=""; _flow_rest="${PYTHONPATH-}:"; _flow_wd=$(pwd -P 2>/dev/null) || _flow_wd=""; _flow_top=$_flow_wd; _flow_d=$_flow_wd',
    'while [ -n "$_flow_d" ]; do if [ -e "$_flow_d/.git" ]; then _flow_top=$_flow_d; break; fi; _flow_d=${_flow_d%/*}; done',
    'while [ -n "$_flow_rest" ]; do _flow_e=${_flow_rest%%:*}; _flow_rest=${_flow_rest#*:}; case "$_flow_e" in /*) _flow_r=$(builtin cd -P -- "$_flow_e" >/dev/null 2>&1 && pwd -P) || _flow_r=$_flow_e; case "$_flow_wd/" in "${_flow_r%/}"/*) ;; *) case "$_flow_r/" in "$_flow_top"/*) ;; *) _flow_pp="${_flow_pp:+$_flow_pp:}$_flow_e" ;; esac ;; esac ;; esac; done',
    'if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi',
]
OLD = re.compile(r"""not in \(\s*(""|'')\s*,\s*("\."|'\.')\s*\)""")
IMPORT = re.compile(r'^\s*(import|from)\s+([\w.]+)')
PY3 = re.compile(r"(^|[^\w/.-])python3(\s|$|\))")

def at_command(line, pos):
    """True when a python3 at pos starts a command: the text before it on
    its line, after the last separator and any NAME=value assignments, is
    empty. A python3 inside a message or a quoted argument is prose."""
    before = line[:pos]
    if before.count('"') % 2 or before.count("'") % 2:
        return False  # inside a quoted string on this line
    head = re.split(r"&&|\|\||;|\||\$\(|\(|\b(?:if|then|elif|else|do|while|until|exec)\b|!", before)[-1]
    head = re.sub(r"^\s*(\w+=\S*\s+)*", "", head)
    return head.strip() == ""

def calls(line):
    """Each python3 call on the line: (position, flags after python3)."""
    for m in re.finditer(r"python3((?:\s+-[A-Za-z]+)*)", line):
        if (m.start() == 0 or not re.match(r"[\w/.-]", line[m.start() - 1])) and at_command(line, m.start()):
            yield m.start(), m.group(1)

def risky(line):
    m = IMPORT.match(line)
    if not m:
        return False
    if m.group(1) == "from":
        return True
    names = [n.split(" as ")[0].strip() for n in line.split("#")[0].strip()[len("import"):].split(",")]
    return any(n not in ("os", "sys") for n in names)

def has_seq(lines, seq):
    """seq appears as consecutive lines (after dedent) somewhere in lines."""
    flat = [l.strip() if l.strip() else l for l in lines]
    want = [x.strip() for x in seq]
    for i in range(len(flat) - len(want) + 1):
        if [x.strip() for x in lines[i:i + len(want)]] == want:
            return i
    return None

bad, units, shells = [], 0, 0

def check_block(where, lines):
    """A Python block: the full guard, before any import other than os/sys."""
    global units
    first = next((i for i, l in enumerate(lines) if risky(l)), None)
    if first is None:
        return
    units += 1
    at = has_seq(lines[:first], GUARD)
    if at is None:
        bad.append("%s: %r runs before the full guard" % (where(first), lines[first].strip()[:60]))

def check_one_liner(where, code):
    global units
    stmts = [x.strip() for x in re.split(r"[;\n]", code)]
    if not any(risky(x) for x in stmts):
        return
    units += 1
    if not code.startswith(ONE_LINER):
        bad.append("%s (python3 -c): does not start with the one-line guard" % where)

def heredocs(lines):
    i = 0
    while i < len(lines):
        m = None if lines[i].lstrip().startswith("#") else re.search(r"<<-?\s*['\"]?([A-Za-z_]\w*)['\"]?", lines[i])
        if m:
            tag, j = m.group(1), i + 1
            while j < len(lines) and lines[j].strip() != tag:
                j += 1
            body = lines[i + 1:j]
            if j < len(lines) and any(IMPORT.match(x) for x in body):
                yield i + 1, body
                i = j
        i += 1

def one_liners(text):
    for m in re.finditer(r"python3 -c (['\"])(.*?)\1", text, re.S):
        line_start = text.rfind("\n", 0, m.start()) + 1
        line = text[line_start:m.start()]
        if line.lstrip().startswith("#") or not at_command(line, len(line)):
            continue  # in a comment or inside an argument: prose, not a call
        yield text[:m.start()].count("\n") + 1, m.group(2)

def check_shell(rel, offset, lines):
    """Shell text: its heredocs, its one-liners, python3 -m, and the sanitizer
    before its first python3."""
    global shells
    for start, block in heredocs(lines):
        check_block(lambda i, s=start: "%s:%d" % (rel, offset + s + i + 1), block)
    text = "\n".join(lines)
    for n, code in one_liners(text):
        check_one_liner("%s:%d" % (rel, offset + n), code)
    first = None
    for n, l in enumerate(lines):
        if l.lstrip().startswith("#"):
            continue
        for pos, flags in calls(l):
            if "-I" in flags.split():
                continue  # isolated mode: no PYTHONPATH, no working directory
            if "-m" in l[pos:].split()[:4] and "-c" not in flags.split():
                bad.append("%s:%d: python3 -m puts the working directory on sys.path; use -I or a guarded -c" % (rel, offset + n + 1))
            if first is None:
                first = n
    if first is None:
        return
    shells += 1
    if has_seq(lines[:first], SANITIZER) is None:
        bad.append("%s:%d: python3 runs before the full PYTHONPATH sanitizer" % (rel, offset + first + 1))

def fences(lines):
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)```(!|bash)\s*$", lines[i])
        if m:
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*```\s*$", lines[j]):
                j += 1
            yield i + 1, lines[i + 1:j]
            i = j
        i += 1

files = sorted(glob.glob(root + "/bin/*.sh") + glob.glob(root + "/bin/*.py") + glob.glob(root + "/bin/lib/*")
               + glob.glob(root + "/hooks/scripts/*.sh") + glob.glob(root + "/hooks/scripts/lib/*")
               + glob.glob(root + "/commands/*.md") + glob.glob(root + "/skills/*/*.md")
               + glob.glob(root + "/references/*.md") + glob.glob(root + "/agents/*.md"))
for f in files:
    if not os.path.isfile(f) or "__pycache__" in f:
        continue
    rel = os.path.relpath(f, root)
    lines = open(f, encoding="utf-8").read().splitlines()
    for n, l in enumerate(lines, 1):
        if OLD.search(l):
            bad.append("%s:%d: the old filter of \"\" and \".\" only" % (rel, n))
    if f.endswith(".py"):
        check_block(lambda i: "%s:%d" % (rel, i + 1), lines)
    elif f.endswith(".sh"):
        if "/lib/" in f:
            for start, block in heredocs(lines):
                check_block(lambda i, s=start: "%s:%d" % (rel, s + i + 1), block)
        else:
            check_shell(rel, 0, lines)
    else:
        # Markdown: only what runs, the bash and ! fences; the rest is prose,
        # including example commands that are the user's own.
        for start, body in fences(lines):
            check_shell(rel, start, body)
print("SHELLS=%d" % shells)
print("UNITS=%d" % units)
for b in bad:
    print("BAD=" + b)
PY
)

_flow_test_begin "every python unit runs the sys.path guard before its first import"
assert_match '^UNITS=[1-9][0-9]+$' "$(printf '%s\n' "$SPG_REPORT" | grep '^UNITS=')" "the scan reached the python units"
assert_match '^SHELLS=[1-9][0-9]+$' "$(printf '%s\n' "$SPG_REPORT" | grep '^SHELLS=')" "the scan reached the scripts and fences that run python3"
assert_equal "" "$(printf '%s\n' "$SPG_REPORT" | grep '^BAD=' | head -20)" "units that import before the guard, or keep the old filter"
