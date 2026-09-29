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
# python3 first cleans PYTHONPATH with the canonical sanitizer. It keeps an
# element only when it is absolute and resolves, with `cd -P`, to a directory
# outside the repository that is not the working directory or one of its
# ancestors; it keeps the resolved path, and unsets PYTHONPATH when none is
# left. An element that does not resolve to a directory is dropped rather than
# compared as written: a zip is not a directory, Python imports sitecustomize
# from one, and a zip inside the checkout named through a symlink or a `..`
# does not look like it is inside. The repository is the nearest directory at
# or above the working directory that has a .git entry (a worktree has a .git
# file), or the working directory when there is none; the nearest, because a
# home directory kept in git would otherwise make every element under home
# count as the repository. A PYTHONPATH element inside the checkout is common
# (a src/ layout set by direnv), and a pull request checked out there can
# plant a sitecustomize.py in it. When the working directory cannot be read,
# every element is dropped; zsh's `pwd -P` prints "." there and succeeds, so
# a working directory that is not an absolute path counts as unreadable.
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

# The scan is a function, not a $( ) around its heredoc: bash 3.2 reads the
# text of a $( ) as shell to find its closing parenthesis, heredoc body
# included, and an apostrophe in a docstring or a backquote in a string below
# does not parse there.
spg_scan() {
python3 - "$FLOW_DIR" <<'PY'
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
    '_flow_pp=""; _flow_rest="${PYTHONPATH-}:"; _flow_wd=$(pwd -P 2>/dev/null) || _flow_wd=""; case "$_flow_wd" in /*) ;; *) _flow_wd="" ;; esac; _flow_top=$_flow_wd; _flow_d=$_flow_wd',
    'while [ -n "$_flow_d" ]; do if [ -e "$_flow_d/.git" ]; then _flow_top=$_flow_d; break; fi; _flow_d=${_flow_d%/*}; done',
    'while [ -n "$_flow_rest" ]; do _flow_e=${_flow_rest%%:*}; _flow_rest=${_flow_rest#*:}; case "$_flow_e" in /*) ;; *) continue ;; esac; _flow_r=$(builtin cd -P -- "$_flow_e" >/dev/null 2>&1 && pwd -P) || continue; case "$_flow_r" in /*) ;; *) continue ;; esac; case "$_flow_wd/" in "${_flow_r%/}"/*) ;; *) case "$_flow_r/" in "$_flow_top"/*) ;; *) _flow_pp="${_flow_pp:+$_flow_pp:}$_flow_r" ;; esac ;; esac; done',
    'if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi',
]
OLD = re.compile(r"""not in \(\s*(""|'')\s*,\s*("\."|'\.')\s*\)""")
IMPORT = re.compile(r'^\s*(import|from)\s+([\w.]+)')
PY3 = re.compile(r"(^|[^\w/.-])python3(\s|$|\))")

class Shell:
    """The python3 calls in a piece of shell text: each word python3 that is
    the name of a command, as (offset in the text, flags after it).

    Whether a word is a command name depends on the shell's structure, not on
    the characters in front of it on its line. `v="$(python3 -c ...)"` has an
    odd number of quotes before the call and `X="$(cmd)" python3` has `cmd)"`
    before it, and both are calls, while `echo "python3 is required"` and
    `command -v python3` are not. So this reads the whole text the way the
    shell does, as far as that question needs: quotes, backslash escapes and
    line continuations, comments, $( ) and backquotes (whose contents are
    commands in their own right), ${ } and $(( )), heredoc bodies (skipped,
    except for the $( ) and backquotes an unquoted one expands), NAME=value
    words in front of a command, redirections, the keywords after which a
    command starts, and case patterns (whose `)` closes nothing)."""

    KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "time", "exec", "command", "nohup"}
    ASSIGN = re.compile(r"[A-Za-z_]\w*(\[[^]]*\])?\+?=")
    FLAGS = re.compile(r"python3((?:(?:[ \t]|\\\n)+-[A-Za-z]+)*)")
    REDIRECTS = ("&>>", "&>", "<<<", "<<-", "<<", "<>", "<&", ">&", ">>", ">|", "<", ">")

    def __init__(self, text):
        self.t, self.n = text, len(text)
        self.pending = []  # (tag, expands) of heredocs whose body starts at the next newline
        self.found = []
        self.commands(0, None)
        self.found.sort()

    def commands(self, i, close):
        """A command list from i to the unquoted close (")" or "`"), or to the
        end of the text; returns the index just after close."""
        t, n = self.t, self.n
        cmd, cases = True, []  # cmd: the next word is a command name; cases: "subject", "pattern" or "body"
        while i < n:
            c, state = t[i], cases[-1] if cases else None
            if c == "\\" and t.startswith("\n", i + 1):
                i += 2  # a line continuation: the command goes on
            elif c in " \t":
                i += 1
            elif c == "\n":
                i, cmd = self.bodies(i + 1), True
            elif c == "#":
                while i < n and t[i] != "\n":
                    i += 1
            elif state == "pattern" and c in "(|":
                i += 1
            elif state == "pattern" and c == ")":
                cases[-1], cmd, i = "body", True, i + 1
            elif c == close:
                return i + 1
            elif c == ";":
                op = next(o for o in (";;&", ";;", ";&", ";") if t.startswith(o, i))
                if op != ";" and state == "body":
                    cases[-1] = "pattern"
                cmd, i = True, i + len(op)
            elif t.startswith(("&>", "<(", ">("), i) or c in "<>":
                if t.startswith(("<(", ">("), i):
                    i, cmd = self.commands(i + 2, ")"), False  # process substitution: an argument
                else:
                    i = self.redirection(i)  # leaves cmd as it was: `2>/dev/null python3` is a call
            elif c in "&|":
                cmd, i = True, i + (2 if t.startswith(("&&", "||", "|&"), i) else 1)
            elif c == "(":
                i, cmd = self.commands(i + 1, ")"), True  # a subshell, or the () of a function
            elif c == ")":
                cmd, i = True, i + 1
            else:
                end, word = self.word(i, close)
                if word.isdigit() and t[end:end + 1] in ("<", ">"):
                    i = end  # the file descriptor of a redirection
                    continue
                if state == "subject":
                    if word == "in":
                        cases[-1] = "pattern"
                elif state == "pattern":
                    if word == "esac":
                        cases.pop()
                        cmd = False
                elif cmd:
                    if word == "python3":
                        self.found.append((i, self.FLAGS.match(t, i).group(1)))
                        cmd = False
                    elif word == "case":
                        cases.append("subject")
                        cmd = False
                    elif word == "esac" and cases:
                        cases.pop()
                        cmd = False
                    else:
                        cmd = word in self.KEYWORDS or bool(self.ASSIGN.match(word))
                i = max(end, i + 1)
        return n

    def word(self, i, close):
        """The word at i, to the first unquoted blank or operator: (end, text)."""
        t, n, start = self.t, self.n, i
        while i < n:
            c = t[i]
            if c == "\\":
                i += 2
            elif c == "'":
                i = self.squote(i + 1)
            elif c == '"':
                i = self.dquote(i + 1)
            elif c == "`" and close == "`":
                break
            elif c in "$`":
                i = self.expansion(i, False)
            elif c in " \t\n;&|()<>":
                break
            else:
                i += 1
        return min(i, n), t[start:i]

    def expansion(self, i, quoted):
        """$(( )), $( ), ${ } or a backquote at i, else the one character."""
        t = self.t
        if t.startswith("$((", i):
            return self.arith(i + 3)
        if t.startswith("$(", i):
            return self.commands(i + 2, ")")
        if t.startswith("${", i):
            return self.brace(i + 2, quoted)
        if t[i] == "`":
            return self.commands(i + 1, "`")
        return i + 1

    def squote(self, i):
        j = self.t.find("'", i)
        return self.n if j < 0 else j + 1

    def dquote(self, i):
        """From inside a double-quoted string to just after its close."""
        t, n = self.t, self.n
        while i < n:
            c = t[i]
            if c == "\\":
                i += 2
            elif c == '"':
                return i + 1
            elif c in "$`":
                i = self.expansion(i, True)
            else:
                i += 1
        return n

    def brace(self, i, quoted):
        """From inside ${ to just after its }. Inside double quotes a single
        quote there is an ordinary character."""
        t, n = self.t, self.n
        while i < n:
            c = t[i]
            if c == "\\":
                i += 2
            elif c == "}":
                return i + 1
            elif c == '"':
                i = self.dquote(i + 1)
            elif c == "'" and not quoted:
                i = self.squote(i + 1)
            elif c in "$`":
                i = self.expansion(i, quoted)
            else:
                i += 1
        return n

    def arith(self, i):
        """From inside $(( to just after its )). Nothing in it is a command."""
        t, n, depth = self.t, self.n, 0
        while i < n:
            if t[i] == "(":
                depth += 1
            elif t[i] == ")":
                if depth == 0:
                    return i + (2 if t.startswith("))", i) else 1)
                depth -= 1
            i += 1
        return n

    def redirection(self, i):
        """A redirection operator at i and its target word. A heredoc's body
        is read at the next newline; it expands only when its tag is unquoted."""
        t = self.t
        op = next(o for o in self.REDIRECTS if t.startswith(o, i))
        i += len(op)
        while i < self.n and t[i] in " \t":
            i += 1
        end, word = self.word(i, None)
        if op in ("<<", "<<-"):
            self.pending.append((re.sub(r"[\"'\\]", "", word), not re.search(r"[\"'\\]", word)))
        return end

    def bodies(self, i):
        """Past the bodies of the heredocs opened on the line that ended just
        before i. The end line is matched once its blanks are removed, as the
        heredoc scan below matches it, since a fence body keeps its indent."""
        t, n = self.t, self.n
        pending, self.pending = self.pending, []
        for tag, expands in pending:
            while i < n:
                eol = t.find("\n", i)
                eol = n if eol < 0 else eol
                if t[i:eol].strip() == tag:
                    i = eol + 1
                    break
                j = i
                while expands and j < eol:
                    j = self.expansion(j, True) if t[j] in "$`" else j + (2 if t[j] == "\\" else 1)
                i = eol + 1
        return min(i, n)

def calls(text):
    """Each python3 call in the shell text: (offset, flags after python3)."""
    return Shell(text).found

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

def one_liners(text, at):
    """Each `python3 -c '...'` whose python3 is a call (its offset is in at):
    (line number, code). One in a comment or inside an argument is prose."""
    for m in re.finditer(r"python3 -c (['\"])(.*?)\1", text, re.S):
        if m.start() in at:
            yield text[:m.start()].count("\n") + 1, m.group(2)

# Units that carry the sanitizer, units that run python3 without -I (so need
# it), and units whose python3 calls include one with -I.
carry, need, isolated = set(), set(), set()
# A unit that carries any line of the sanitizer has it because it runs
# python3. One that carries it with no python3 call the lint recognizes is a
# call form the scan misses (as `X="$(cmd)" python3` in flow-dep-diff.sh
# was), so the two sets must be equal, except for a unit named here with the
# reason it keeps a sanitizer it does not need. Any line counts, not only the
# full sequence, so a partial copy in such a unit shows up as well.
SANITIZED_WITHOUT_NEED = {
    "hooks/scripts/reply-style-check.sh":
        "its one python3 call runs with -I, which ignores PYTHONPATH; it kept the sanitizer when that call took -I",
}
SANITIZER_LINES = {x.strip() for x in SANITIZER if x.strip()}

def check_shell(rel, offset, lines, unit):
    """Shell text: its heredocs, its one-liners, python3 -m, and the sanitizer
    before its first python3."""
    global shells
    for start, block in heredocs(lines):
        check_block(lambda i, s=start: "%s:%d" % (rel, offset + s + i + 1), block)
    text = "\n".join(lines)
    found = calls(text)
    for n, code in one_liners(text, {pos for pos, _ in found}):
        check_one_liner("%s:%d" % (rel, offset + n), code)
    if any(l.strip() in SANITIZER_LINES for l in lines):
        carry.add(unit)
    first = None
    for pos, flags in found:
        n = text.count("\n", 0, pos)
        if "-I" in flags.split():
            isolated.add(unit)
            continue  # isolated mode: no PYTHONPATH, no working directory
        if "-m" in text[pos:].split("\n", 1)[0].split()[:4] and "-c" not in flags.split():
            bad.append("%s:%d: python3 -m puts the working directory on sys.path; use -I or a guarded -c" % (rel, offset + n + 1))
        if first is None:
            first = n
    if first is None:
        return
    need.add(unit)
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
            check_shell(rel, 0, lines, rel)
    else:
        # Markdown: only what runs, the bash and ! fences; the rest is prose,
        # including example commands that are the user's own.
        for start, body in fences(lines):
            check_shell(rel, start, body, "%s:%d (fence)" % (rel, start))
# The call scan on the forms it must find and the prose it must not: each
# snippet with the line numbers of its python3 calls.
for snippet, want in [
    ('v="$(python3 -c "print(1)")"', [1]),
    ('X="$(pwd)" python3 -c "print(1)"', [1]),
    ('X=${x// /_} python3 y', [1]),
    ('v=`python3 x`', [1]),
    ('A=1 \\\n  B="$(f "$x")" python3 - <<\'E\'\npython3 x\nE\npython3 y', [2, 5]),
    ('if [ "$(python3 x)" = y ]; then :; fi', [1]),
    ('if ! python3 -c "import yaml"; then exit 1; fi', [1]),
    ('exec python3 x', [1]),
    ('2>/dev/null python3 x', [1]),
    ('f() { python3 x; }', [1]),
    ('case "$e" in /*) python3 x ;; *) python3 y ;; esac', [1, 1]),
    ('v=$(case "$e" in a) python3 x ;; esac)', [1]),
    ('cat <<EOF\n$(python3 x)\nEOF', [2]),
    ('command -v python3 >/dev/null', []),
    ('echo "python3 is required"', []),
    ("echo 'run: python3 -m x'", []),
    ('die "the $(basename "$0") python3 call"', []),
    ('# python3 x', []),
    ('x=1 # it is; python3 x', []),
    ("# it's\npython3 x", [2]),
    ('case "$x" in python3) : ;; esac', []),
    ("cat <<'EOF'\npython3 x\nEOF", []),
    ('cat <<EOF\npython3 x\nEOF', []),
]:
    got = [snippet.count("\n", 0, pos) + 1 for pos, _ in calls(snippet)]
    if got != want:
        print("SCAN=python3 calls on lines %s of %r, not %s" % (got, snippet, want))
for u in sorted(carry - need - set(SANITIZED_WITHOUT_NEED)):
    print("MISMATCH=%s: carries the PYTHONPATH sanitizer, but the scan finds no python3 call there that needs it" % u)
for u in sorted(need - carry):
    print("MISMATCH=%s: runs python3 and carries no line of the PYTHONPATH sanitizer" % u)
for u, why in sorted(SANITIZED_WITHOUT_NEED.items()):
    if u not in carry or u in need or u not in isolated:
        print("MISMATCH=%s: listed as keeping a sanitizer it does not need (%s), which is no longer so" % (u, why))
print("SHELLS=%d" % shells)
print("UNITS=%d" % units)
for b in bad:
    print("BAD=" + b)
PY
}
SPG_REPORT=$(spg_scan)

_flow_test_begin "every python unit runs the sys.path guard before its first import"
assert_match '^UNITS=[1-9][0-9]+$' "$(printf '%s\n' "$SPG_REPORT" | grep '^UNITS=')" "the scan reached the python units"
assert_match '^SHELLS=[1-9][0-9]+$' "$(printf '%s\n' "$SPG_REPORT" | grep '^SHELLS=')" "the scan reached the scripts and fences that run python3"
assert_equal "" "$(printf '%s\n' "$SPG_REPORT" | grep '^BAD=' | head -20)" "units that import before the guard, or keep the old filter"

_flow_test_begin "the call scan finds python3 where it is a command, and not in prose"
assert_equal "" "$(printf '%s\n' "$SPG_REPORT" | grep '^SCAN=' | head -20)" "snippets the call scan reads wrongly"

_flow_test_begin "the units that carry the PYTHONPATH sanitizer are the units that run python3"
assert_equal "" "$(printf '%s\n' "$SPG_REPORT" | grep '^MISMATCH=' | head -20)" "units where carrying the sanitizer and needing it disagree"
