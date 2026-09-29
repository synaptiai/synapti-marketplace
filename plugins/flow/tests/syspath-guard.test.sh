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
# python3 first cleans PYTHONPATH with the canonical sanitizer. When
# PYTHONPATH is set, an isolated python3 (-I: it reads neither PYTHONPATH nor
# the working directory, and adds no user site) computes the elements to keep:
# absolute paths that resolve to a directory, contain no colon or newline, and
# are neither inside the repository nor the working directory or one of its
# ancestors. Containment is decided by comparing directories' device and inode
# numbers along each path's chain of parents, never by comparing path text:
# a string comparison was defeated in turn by a zip named through a symlink,
# by a path spelled with two leading slashes (bash keeps them), by a resolved
# path containing a colon (Python splits it again), and would be by a case
# variant of the repository's path on a case-insensitive disk. The repository
# is the nearest directory at or above the working directory that has a .git
# entry (a worktree has a .git file), or the working directory when there is
# none; the nearest, because a home directory kept in git would otherwise make
# every element under home count as the repository. A PYTHONPATH element
# inside the checkout is common (a src/ layout set by direnv), and a pull
# request checked out there can plant a sitecustomize.py in it. When the
# working directory cannot be read, or python3 cannot run, every element is
# dropped. With PYTHONPATH unset, nothing runs. One known gap: a Linux bind
# mount of the repository has other device numbers, so an element reached
# through it is not recognised as inside.
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
    '_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c \'exec("import os, sys\\ndef ids(p):\\n    out = set()\\n    while True:\\n        try:\\n            st = os.stat(p)\\n        except OSError:\\n            return out\\n        out.add((st.st_dev, st.st_ino))\\n        q = os.path.dirname(p)\\n        if q == p:\\n            return out\\n        p = q\\ntry:\\n    cwd = os.getcwd()\\nexcept OSError:\\n    sys.exit(0)\\ntop = d = cwd\\nwhile True:\\n    if os.path.lexists(os.path.join(d, \\".git\\")):\\n        top = d\\n        break\\n    q = os.path.dirname(d)\\n    if q == d:\\n        break\\n    d = q\\nst = os.stat(top)\\ntop_id = (st.st_dev, st.st_ino)\\nup = ids(cwd)\\nkeep = []\\nfor e in os.environ.get(\\"PYTHONPATH\\", \\"\\").split(\\":\\"):\\n    if not e.startswith(\\"/\\"):\\n        continue\\n    r = os.path.realpath(e)\\n    if \\":\\" in r or chr(10) in r or not os.path.isdir(r):\\n        continue\\n    try:\\n        st = os.stat(r)\\n    except OSError:\\n        continue\\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\\n        continue\\n    keep.append(r)\\nsys.stdout.write(\\":\\".join(keep))")\' 2>/dev/null) || _flow_pp=""; fi',
    'if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi',
]
OLD = re.compile(r"""not in \(\s*(""|'')\s*,\s*("\."|'\.')\s*\)""")
IMPORT = re.compile(r'^\s*(import|from)\s+([\w.]+)')

class Wrap:
    """Where the reader is among the words after a wrapper's name (see
    Shell.WRAPPERS): the option whose value is the next word, the plain words
    still to come before the command, and whether a shell was given -c."""

    def __init__(self, name, words):
        self.name, self.value, self.words, self.c = name, None, words, False

class Shell:
    """The python3 calls in a piece of shell text: each command name whose
    last path component is python3, as (offset of that python3 in the text,
    flags after the name). python3.11 and the like count too: a versioned
    name is the same interpreter, which reads PYTHONPATH and puts the working
    directory on sys.path the same way. python and python2 do not: the rule is
    about python3, and those names need not be Python 3.

    Whether a word is a command name depends on the shell's structure, not on
    the characters in front of it on its line. `v="$(python3 -c ...)"` has an
    odd number of quotes before the call and `X="$(cmd)" python3` has `cmd)"`
    before it, and both are calls, while `echo "python3 is required"` and
    `command -v python3` are not. So this reads the whole text the way the
    shell does, as far as that question needs: quotes, backslash escapes and
    line continuations, comments, $( ) and backquotes (whose contents are
    commands in their own right), ${ }, $(( )) and (( )) (arithmetic, where
    only a $( ) or backquotes hold commands), heredoc bodies (skipped, except
    for the $( ) and backquotes an unquoted one expands), NAME=value words in
    front of a command, redirections, the keywords after which a command
    starts, function definitions, case patterns (whose `)` closes nothing),
    the commands that run the command named after their own options (env,
    timeout, xargs and the others in WRAPPERS, and a variable followed by a
    number, as `"$TIMEOUT_BIN" 30 cmd`), and the string that sh -c and
    env -S run as a command line."""

    KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{"}
    ASSIGN = re.compile(r"[A-Za-z_]\w*(\[[^]]*\])?\+?=")
    PYTHON = re.compile(r"python3(\.\d+)?")
    NUMBER = re.compile(r"\d+(\.\d+)?[smhd]?")
    FLAGS = re.compile(r"(?:(?:[ \t]|\\\n)+-[A-Za-z]+)*")
    REDIRECTS = ("&>>", "&>", "<<<", "<<-", "<<", "<>", "<&", ">&", ">>", ">|", "<", ">")
    # Commands that run the command named after their own options: for each,
    # its options whose value is the next word (short letters, long names),
    # and how many plain words come before the command (timeout's duration).
    # NAME=value words before it (env, sudo) are read as they are in front of
    # any command. command -v and -V only look a name up; a shell runs the
    # command in its -c string, and env in -S's.
    SHELL_OPTS = ("oO", ("--rcfile", "--init-file"), 0)
    TIMEOUT_OPTS = ("sk", ("--signal", "--kill-after"), 1)
    WRAPPERS = {
        "env": ("uCPSa", ("--unset", "--chdir", "--split-string", "--argv0"), 0),
        "sudo": ("ugCDprtTUR", ("--user", "--group", "--close-from", "--chdir", "--prompt", "--role",
                                "--type", "--command-timeout", "--other-user", "--chroot", "--host"), 0),
        "timeout": TIMEOUT_OPTS,
        "gtimeout": TIMEOUT_OPTS,
        "nice": ("n", ("--adjustment",), 0),
        "xargs": ("IaEdLnPs", ("--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-chars",
                               "--process-slot-var"), 0),
        "exec": ("a", (), 0),
        "command": ("", (), 0),
        "time": ("fo", ("--format", "--output"), 0),
        "nohup": ("", (), 0),
        "sh": SHELL_OPTS, "bash": SHELL_OPTS, "zsh": SHELL_OPTS, "dash": SHELL_OPTS, "ksh": SHELL_OPTS,
    }
    SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}

    def __init__(self, text):
        self.t, self.n = text, len(text)
        self.pending = []  # (tag, expands) of heredocs whose body starts at the next newline
        self.found = []
        self.commands(0, None)
        # A call in a $( ) inside a double-quoted -c string, or inside a ((
        # that turned out to be two subshells, is found by both readings.
        first = {}
        for pos, flags in self.found:
            first.setdefault(pos, flags)
        self.found = sorted(first.items())

    def commands(self, i, close):
        """A command list from i to the unquoted close (")" or "`"), or to the
        end of the text; returns the index just after close."""
        t, n = self.t, self.n
        # cmd: True when the next word is a command name, False when it is an
        # argument, else what the words before it make it (see name()).
        # cases: "subject", "pattern" or "body".
        cmd, cases = True, []
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
                end = self.dparen(i) if t.startswith("((", i) and (cmd is True or cmd == "for") else None
                if end is not None:
                    i, cmd = end, False  # (( )), not a heredoc in `(( x << 2 ))`
                else:
                    i, cmd = self.commands(i + 1, ")"), True  # a subshell, or the () of a function
            elif c == ")":
                cmd, i = True, i + 1
            else:
                end, word, spans = self.word(i, close)
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
                elif cmd is True and word == "case":
                    cases.append("subject")
                    cmd = False
                elif cmd is True and word == "esac" and cases:
                    cases.pop()
                    cmd = False
                elif cmd:
                    cmd = self.name(i, end, word, spans, cmd)
                i = max(end, i + 1)
        return n

    def name(self, i, end, word, spans, cmd):
        """The word from i to end, read where cmd says it stands: True for a
        command name, "function" for the name a function keyword defines,
        "for" for a for loop's variable, "$" for the word after a variable
        used as a command, or a Wrap. Returns what the next word is."""
        v, at = self.value(i, end, spans)
        if cmd is True:
            if word in self.KEYWORDS or self.ASSIGN.match(word):
                return True  # before the name: py=/usr/bin/python3 is not a call
            base = v.rsplit("/", 1)[-1]
            if self.PYTHON.fullmatch(base):
                self.found.append((at[len(v) - len(base)], self.FLAGS.match(self.t, end).group(0)))
                return False
            if word in ("function", "for"):
                return word
            if base in self.WRAPPERS:
                return Wrap(base, self.WRAPPERS[base][2])
            return "$" if v.startswith("$") else False
        if cmd == "function":
            return True  # a { or () follows the name
        if cmd == "for":
            return False
        if cmd == "$":
            return bool(self.NUMBER.fullmatch(v))  # "$TIMEOUT_BIN" 30 python3
        w = cmd
        shorts, longs, _ = self.WRAPPERS[w.name]
        if w.value:
            opt, w.value = w.value, None
            if opt in ("S", "--split-string"):
                self.script(v, at)
                return False
            return w
        if v == "-" and w.name == "env":
            return w  # env's - is its -i
        if len(v) > 1 and (v[0] == "-" or v[0] == "+" and w.name in self.SHELLS):
            if v.startswith("--"):
                if v.startswith("--split-string=") and w.name == "env":
                    k = len("--split-string=")
                    self.script(v[k:], at[k:])
                    return False
                if v in longs:
                    w.value = v  # its value is the next word; --name=value carries its own
                return w
            for k, ch in enumerate(v[1:], 1):
                if w.name == "command" and ch in "vV":
                    return False  # command -v python3 looks python3 up
                if w.name in self.SHELLS and ch == "c" and v[0] == "-":
                    w.c = True
                if ch in shorts:
                    if k == len(v) - 1:
                        w.value = ch  # its value is the next word
                    elif ch == "S" and w.name == "env":
                        self.script(v[k + 1:], at[k + 1:])
                        return False
                    break  # the rest of the word is its value
            return w
        if w.words:
            w.words -= 1
            return w
        if w.name in self.SHELLS:
            if w.c:
                self.script(v, at)  # sh -c 'python3 x'
            return False  # without -c, a script file
        return self.name(i, end, word, spans, True)

    def script(self, text, at):
        """A command line held in a word (sh -c, env -S): its calls, at the
        offsets in this text that their characters came from."""
        for pos, flags in Shell(text).found:
            self.found.append((at[pos], flags))

    def word(self, i, close):
        """The word at i, to the first unquoted blank or operator: (end, text,
        spans), spans being the (start, end) of each quoted part of it."""
        t, n, start, spans = self.t, self.n, i, []
        while i < n:
            c = t[i]
            if c == "\\":
                i += 2
            elif c == "'":
                spans.append((i, self.squote(i + 1)))
                i = spans[-1][1]
            elif c == '"':
                spans.append((i, self.dquote(i + 1)))
                i = spans[-1][1]
            elif c == "`" and close == "`":
                break
            elif c in "$`":
                i = self.expansion(i, False)
            elif c in " \t\n;&|()<>":
                break
            else:
                i += 1
        return min(i, n), t[start:i], spans

    def value(self, i, end, spans):
        """The word from i to end with its quoting removed, and for each of
        its characters the offset in the text it came from. Built from the
        quoted parts word() found, since reading them again would queue a
        heredoc in them twice."""
        t, out, at, k, spans = self.t, [], [], i, dict(spans)
        while k < end:
            if k in spans:
                q, stop = t[k], spans[k]
                last = stop - 1 if stop - 1 > k and t[stop - 1] == q else stop
                j = k + 1
                while j < last:
                    if q == '"' and t[j] == "\\" and j + 1 < last and t[j + 1] in '$`"\\\n':
                        j += 1
                        if t[j] == "\n":
                            j += 1
                            continue
                    out.append(t[j])
                    at.append(j)
                    j += 1
                k = stop
            elif t[k] == "\\":
                if k + 1 < end and t[k + 1] != "\n":
                    out.append(t[k + 1])
                    at.append(k + 1)
                k += 2
            elif t[k] == "$" and k + 1 in spans and t[k + 1] == "'":
                k += 1  # $'...': its contents, escapes left as written
            else:
                out.append(t[k])
                at.append(k)
                k += 1
        return "".join(out), at

    def expansion(self, i, quoted):
        """$(( )), $( ), ${ } or a backquote at i, else the one character."""
        t = self.t
        if t.startswith("$((", i):
            end = self.dparen(i + 1)
            if end is not None:
                return end
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

    def dparen(self, i):
        """The (( at i read as arithmetic: the index just after its )), or
        None when what it opens does not close with )), which bash then reads
        as a ( inside a ( instead."""
        end, whole = self.arith(i + 2)
        return end if whole else None

    def arith(self, i):
        """From inside (( to just after the ) that closes it, and whether that
        was )). Only a $( ) or backquotes in it hold commands; a << in it is a
        shift, not a heredoc."""
        t, n, depth = self.t, self.n, 0
        while i < n:
            c = t[i]
            if c in "$`":
                i = self.expansion(i, False)
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    return (i + 2, True) if t.startswith("))", i) else (i + 1, False)
                depth -= 1
            i += 1
        return n, False

    def redirection(self, i):
        """A redirection operator at i and its target word. A heredoc's body
        is read at the next newline; it expands only when its tag is unquoted."""
        t = self.t
        op = next(o for o in self.REDIRECTS if t.startswith(o, i))
        i += len(op)
        while i < self.n and t[i] in " \t":
            i += 1
        end, word, _ = self.word(i, None)
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
    for m in re.finditer(r"python3(?:\.\d+)? -c (['\"])(.*?)\1", text, re.S):
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
# snippet with the line numbers of its python3 calls. Each call's offset must
# also be where its python3 starts, as the one-liner and -m checks read the
# text from there.
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
    # A command that runs the command after its own options, the name by its
    # last path component, a function keyword, arithmetic, and the string that
    # sh -c or env -S runs; each next to prose of the same shape.
    ('env python3 x', [1]),
    ('env -i -u PYTHONPATH PATH=/usr/bin python3 x', [1]),
    ('env -S \'python3 -I x\'', [1]),
    ("env -S'python3 -I' x", [1]),
    ("env --split-string='python3 x'", [1]),
    ('env - PATH=/bin python3 x', [1]),
    ('/usr/bin/env python3 x', [1]),
    ('env | grep python3', []),
    ('timeout 5 python3 x', [1]),
    ('timeout -k 2 --signal TERM 5 python3 x', [1]),
    ('gtimeout 5 python3 x', [1]),
    ('"$TIMEOUT_BIN" 30 python3 x', [1]),
    ('timeout 5 grep python3 f', []),
    ('xargs python3 x', [1]),
    ('xargs -0 -I {} python3 {}', [1]),
    ('xargs grep python3', []),
    ('nice -n 5 python3 x', [1]),
    ('sudo -u root -E python3 x', [1]),
    ('sudo env X=1 timeout 5 nice python3 x', [1]),
    ('exec -a name python3 x', [1]),
    ('nohup python3 x &', [1]),
    ('command python3 x', [1]),
    ('command -p python3 x', [1]),
    ('command -V python3', []),
    ('time -p python3 x', [1]),
    ('time -p grep python3 f', []),
    ('/usr/bin/python3 x', [1]),
    ('"/usr/bin/python3" -I x', [1]),
    ('python3.11 x', [1]),
    ('/opt/python3/bin/tool x', []),
    ('py=/usr/bin/python3\n"$py" x', []),
    ('python3-config --prefix', []),
    ('function f { python3 x; }', [1]),
    ('function f() {\n  python3 x\n}', [2]),
    ('x=$(( $(python3 a) + 1 ))', [1]),
    ('x=$(( python3 + 1 ))', []),
    ('(( x << 2 ))\npython3 y', [2]),
    ('for (( i = 0; i << 1; i++ ))\ndo\n  python3 x\ndone', [3]),
    ('((python3 x) )', [1]),
    ('v=$((python3 x) )', [1]),
    ("sh -c 'python3 x'", [1]),
    ('bash -ec "python3 x"', [1]),
    ("zsh -o pipefail -c 'cd /tmp\npython3 x'", [2]),
    ('bash -c "v=\\"$(python3 x)\\""', [1]),
    ("bash -c $'python3 x'", [1]),
    ("bash +o posix -c 'python3 x'", [1]),
    ('bash -c "echo \\"step 1; python3 runs next\\""', []),
    ("sh -c 'echo python3'", []),
    ('sh setup.sh python3', []),
    ('echo "run python3 later"', []),
    ('# python3 in a comment', []),
]:
    found = calls(snippet)
    got = [snippet.count("\n", 0, pos) + 1 for pos, _ in found]
    if got != want:
        print("SCAN=python3 calls on lines %s of %r, not %s" % (got, snippet, want))
    for pos, _ in found:
        if not snippet.startswith("python3", pos):
            print("SCAN=a call in %r at offset %d, where %r starts" % (snippet, pos, snippet[pos:pos + 12]))
# The one-liner check reads the code of a -c call in each of these forms.
for snippet in ("python3.11 -c 'import yaml'", "/usr/bin/python3 -c 'import yaml'",
                "timeout 5 python3 -c 'import yaml'", "sh -c \"python3 -c 'import yaml'\""):
    if [code for _, code in one_liners(snippet, {pos for pos, _ in calls(snippet)})] != ["import yaml"]:
        print("SCAN=the one-liner check does not read the code of %r" % snippet)
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
