"""Build the System One state for one test and one risk-map row.

The state asks about one test and one way the implementation could be wrong:

  {"spec": <the specification text>,
   "risk": {"area": <risk-map area>, "plausible_wrong_version": <its text>},
   "test": {"id": <test id>, "source": <the test and what it needs>}}

test.source is, from the test's own file: the module-level imports and
helpers the test refers to by name (and the helpers those refer to), then,
for a test in a class, the class line, its class attributes, setUp and
setUpClass, and the test function itself, each as written. It is capped at
12 KB: helpers are left out, largest first, until it fits, and the test
function is always kept whole. A name the test takes from a module in its
own directory (a helper file next to the tests) cannot be included; the
state is then marked helpers_missing in the metadata, which is never part of
the state.

The live decision point and the measurement in evals/s1-discrimination both
call this, so the measurement covers the state that would be sent.

Usage (through bin/flow-test-state.sh):
  flow-test-state.sh --test-file F (--test-id ID | --line N) --area A
                     --wrong-version W --spec-file S [--strip-comments]
                     [--rename-test NAME] [--meta FILE] [--out FILE]

  --test-id       module.Class.method, Class.method or method; matched on
                  its last one or two parts
  --line          the line of the test file inside the test function
  --strip-comments  remove every comment before taking the source
  --rename-test   rename the test function (and the last part of its id)
  --meta FILE     write {helpers_missing, helpers_dropped, bytes} to FILE
  --out FILE      write the state there instead of stdout

Exit 0 with the state on stdout, 2 on a usage error or a test that cannot be
found.
"""

# The guard below must stay verbatim (tests/syspath-guard.test.sh matches it)
# and must run before the other imports, so ruff's rules on one import per
# line and imports at the top do not apply to this file.
# ruff: noqa: E401, E402
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import ast
import io
import json
import tokenize

SOURCE_CAP = 12 * 1024
CLASS_SETUP = ("setUp", "setUpClass")


class StateError(Exception):
    pass


def strip_comments(text):
    """text without its comments. A line that held only a comment is
    removed; a comment after code is cut with the spaces before it. A # in a
    string is not a comment (tokenize tells them apart)."""
    cuts = {}
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.COMMENT:
                cuts[tok.start[0]] = tok.start[1]
    except (tokenize.TokenError, SyntaxError) as e:
        raise StateError("cannot read the test file: %s" % e)
    out = []
    for n, line in enumerate(text.splitlines(keepends=True), 1):
        if n not in cuts:
            out.append(line)
            continue
        kept = line[:cuts[n]].rstrip()
        if kept:
            out.append(kept + "\n")
    return "".join(out)


def _segment(lines, node):
    """The node's lines as written, with its decorators and the comment
    lines that follow its last statement inside its body."""
    first = min([node.lineno] + [d.lineno for d in getattr(node, "decorator_list", [])])
    last = node.end_lineno
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        while last < len(lines):
            nxt = lines[last]
            stripped = nxt.lstrip()
            indent = len(nxt) - len(stripped)
            if stripped.startswith("#") and indent > node.col_offset:
                last += 1
            else:
                break
    return "".join(lines[first - 1:last])


def _names(node):
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def _find(tree, test_id, line):
    """(class node or None, function node)."""
    funcs = []
    for top in tree.body:
        if isinstance(top, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs.append((None, top))
        elif isinstance(top, ast.ClassDef):
            for item in top.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    funcs.append((top, item))
    if line is not None:
        hits = [(c, f) for c, f in funcs if f.lineno <= line <= f.end_lineno]
        if not hits:
            raise StateError("no test function contains line %d" % line)
        return hits[0]
    parts = test_id.split(".")
    method = parts[-1]
    owner = parts[-2] if len(parts) >= 2 else None
    hits = [(c, f) for c, f in funcs if f.name == method]
    if owner is not None:
        in_owner = [(c, f) for c, f in hits if c is not None and c.name == owner]
        if in_owner:
            hits = in_owner
        elif any(c is not None for c, _ in hits):
            # A class part that names no class here, while the method sits in
            # classes: a dotted module path with a top-level test function is
            # the only other reading.
            hits = [(c, f) for c, f in hits if c is None]
    if not hits:
        raise StateError("no test %s in the file" % test_id)
    if len(hits) > 1:
        raise StateError("test %s is ambiguous in the file (%d matches)" % (test_id, len(hits)))
    return hits[0]


def _local_module(test_dir, module, level):
    """True when a from-import names a module in the test's own directory."""
    if level:
        return True
    parts = (module or "").split(".")
    anc = test_dir
    for _ in range(4):
        cand = os.path.join(anc, *parts)
        for path in (cand + ".py", os.path.join(cand, "__init__.py")):
            if os.path.isfile(path):
                real = os.path.realpath(path)
                return os.path.dirname(real) == os.path.realpath(test_dir) or \
                    real.startswith(os.path.realpath(test_dir) + os.sep)
        parent = os.path.dirname(anc)
        if parent == anc:
            break
        anc = parent
    return False


def build_source(text, test_file, test_id=None, line=None, rename=None):
    """(test id as found, source, meta)."""
    tree = ast.parse(text, filename=test_file)
    lines = text.splitlines(keepends=True)
    cls, func = _find(tree, test_id or "", line)
    if test_id is None:
        test_id = "%s.%s" % (cls.name, func.name) if cls is not None else func.name

    # The class part: its line, attributes, setUp/setUpClass, the test.
    class_parts = []
    needed = _names(func)
    if cls is not None:
        # The class line's bases (unittest.TestCase) need their imports too.
        for base in cls.bases + [k.value for k in cls.keywords]:
            needed |= _names(base)
        header = lines[cls.lineno - 1]
        if not header.rstrip().endswith(":"):
            header = "".join(lines[cls.lineno - 1:cls.body[0].lineno - 1])
        for item in cls.body:
            if isinstance(item, (ast.Assign, ast.AnnAssign)):
                class_parts.append(_segment(lines, item))
                needed |= _names(item)
            elif isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and item.name in CLASS_SETUP:
                class_parts.append(_segment(lines, item))
                needed |= _names(item)
    func_text = _segment(lines, func)
    if rename:
        func_text = func_text.replace("def %s(" % func.name, "def %s(" % rename, 1)
        test_id = test_id.rsplit(".", 1)[0] + "." + rename if "." in test_id else rename

    # Module-level definitions and imports, and which of them the test needs,
    # following helpers into the helpers they use.
    defs, imports = {}, []
    for top in tree.body:
        if isinstance(top, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and top is not cls:
            defs.setdefault(top.name, top)
        elif isinstance(top, (ast.Assign, ast.AnnAssign)):
            targets = top.targets if isinstance(top, ast.Assign) else [top.target]
            for t in targets:
                for leaf in ast.walk(t):
                    if isinstance(leaf, ast.Name):
                        defs.setdefault(leaf.id, top)
        elif isinstance(top, (ast.Import, ast.ImportFrom)):
            imports.append(top)
    used_defs = []
    seen = set()
    todo = sorted(needed)
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        node = defs.get(name)
        if node is not None and node not in used_defs:
            used_defs.append(node)
            todo.extend(sorted(_names(node) - seen))
    helpers_missing = False
    used_imports = []
    test_dir = os.path.dirname(os.path.abspath(test_file))
    for imp in imports:
        bound = [(a.asname or a.name).split(".")[0] for a in imp.names]
        if not any(b in seen for b in bound) and not any(a.name == "*" for a in imp.names):
            continue
        used_imports.append(imp)
        if isinstance(imp, ast.ImportFrom) and _local_module(test_dir, imp.module, imp.level):
            helpers_missing = True

    def assemble(helpers):
        parts = [_segment(lines, i) for i in used_imports]
        head = "".join(parts)
        body = "\n\n".join(_segment(lines, h).rstrip("\n") + "\n" for h in sorted(helpers, key=lambda n: n.lineno))
        out = head + ("\n\n" if head and body else "") + body
        if cls is not None:
            block = header if header.endswith("\n") else header + "\n"
            for part in class_parts:
                block += part.rstrip("\n") + "\n"
            block += func_text.rstrip("\n") + "\n"
        else:
            block = func_text.rstrip("\n") + "\n"
        return out + ("\n\n" if out else "") + block

    helpers = list(used_defs)
    dropped = []
    source = assemble(helpers)
    while len(source.encode("utf-8")) > SOURCE_CAP and helpers:
        biggest = max(helpers, key=lambda n: len(_segment(lines, n)))
        helpers.remove(biggest)
        dropped.append(getattr(biggest, "name", "assignment@%d" % biggest.lineno))
        source = assemble(helpers)
    if len(source.encode("utf-8")) > SOURCE_CAP and class_parts:
        class_parts = []
        dropped.append("class setUp and attributes")
        source = assemble(helpers)
    meta = {"helpers_missing": helpers_missing or bool(dropped), "helpers_dropped": dropped,
            "bytes": len(source.encode("utf-8"))}
    return test_id, source, meta


def build_state(test_file, area, wrong_version, spec_text, test_id=None, line=None,
                strip=False, rename=None):
    """(state, meta) for one test and one risk row."""
    try:
        with open(test_file, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as e:
        raise StateError("cannot read %s: %s" % (test_file, e))
    try:
        if line is not None and strip:
            # Find the function by its original line, then strip.
            tree = ast.parse(text, filename=test_file)
            cls, func = _find(tree, "", line)
            test_id = "%s.%s" % (cls.name, func.name) if cls is not None else func.name
            line = None
        if strip:
            text = strip_comments(text)
        found_id, source, meta = build_source(text, test_file, test_id, line, rename)
    except SyntaxError as e:
        raise StateError("cannot parse %s: %s" % (test_file, e))
    state = {"spec": spec_text,
             "risk": {"area": area, "plausible_wrong_version": wrong_version},
             "test": {"id": found_id, "source": source}}
    meta["comments_stripped"] = bool(strip)
    return state, meta


def dump_state(state):
    """The bytes written for a state; their sha256 is what a record names."""
    return (json.dumps(state, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")


def main(argv):
    opts = {}
    flags = set()
    i = 0
    values = ("--test-file", "--test-id", "--line", "--area", "--wrong-version", "--spec-file",
              "--rename-test", "--meta", "--out")
    while i < len(argv):
        a = argv[i]
        if a in values:
            if i + 1 >= len(argv):
                sys.stderr.write("flow-test-state: %s needs a value\n" % a)
                return 2
            opts[a] = argv[i + 1]
            i += 2
        elif a == "--strip-comments":
            flags.add(a)
            i += 1
        else:
            sys.stderr.write("flow-test-state: unknown argument: %s\n" % a)
            return 2
    missing = [k for k in ("--test-file", "--area", "--wrong-version", "--spec-file") if k not in opts]
    if missing or ("--test-id" in opts) == ("--line" in opts):
        sys.stderr.write("flow-test-state: --test-file, one of --test-id or --line, --area, --wrong-version "
                         "and --spec-file are required\n")
        return 2
    line = None
    if "--line" in opts:
        if not opts["--line"].isdigit():
            sys.stderr.write("flow-test-state: --line must be a line number\n")
            return 2
        line = int(opts["--line"])
    try:
        with open(opts["--spec-file"], encoding="utf-8") as fh:
            spec = fh.read()
        state, meta = build_state(opts["--test-file"], opts["--area"], opts["--wrong-version"], spec,
                                  opts.get("--test-id"), line, "--strip-comments" in flags,
                                  opts.get("--rename-test"))
    except (OSError, UnicodeDecodeError) as e:
        sys.stderr.write("flow-test-state: cannot read the spec file: %s\n" % e)
        return 2
    except StateError as e:
        sys.stderr.write("flow-test-state: %s\n" % e)
        return 2
    data = dump_state(state)
    if "--out" in opts:
        with open(opts["--out"], "wb") as fh:
            fh.write(data)
    else:
        sys.stdout.buffer.write(data)
    if "--meta" in opts:
        with open(opts["--meta"], "w", encoding="utf-8") as fh:
            json.dump(meta, fh, sort_keys=True)
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
