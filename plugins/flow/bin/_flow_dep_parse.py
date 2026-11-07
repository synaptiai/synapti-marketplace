"""Manifest and lockfile parsing for bin/flow-dep-diff.sh.

TOML formats — pyproject.toml, Cargo.toml, poetry.lock, Cargo.lock — are read
with a real TOML parser (`tomllib`, or `tomli` below 3.11). A hand-rolled line
scanner was tried first and cost three review cycles: each fix revealed the
next construct it did not know, and the last of those made a pyproject.toml
carrying an ordinary tri-quoted readme report an EMPTY dependency list while
the run still said ok.

Line-oriented formats — requirements.txt, go.mod, go.sum, Gemfile,
Gemfile.lock, yarn.lock, pnpm-lock.yaml — keep their own parsers, because
there the line IS the unit and the line number is a fact rather than a
reconstruction. TOML entries carry no line number at all: a parser returns
values, not the lines they came from, and the text search that tried to
recover them pointed at the wrong package for most entries in a lockfile.
`references/finding-schema.md` permits a file-level location, and a location
that is merely coarse is better than one that is confidently wrong.

Names and versions come from a manifest inside the change under review, so
they are author-controlled. `safe_scalar` and `safe_name` refuse anything that
could forge a field before it can reach the output.
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


import json
import os
import re
import shlex

# The record separator in the output. A value carrying one would split a line
# into two records, so it is refused rather than escaped: a dependency name is
# never legitimately a pipe.
_FORBIDDEN = re.compile(
    "["
    "\u0000-\u0008\u000a-\u001f"   # C0 controls except tab
    "\u007f-\u009f"                  # DEL and the C1 block
    "\u2028\u2029"                   # LINE and PARAGRAPH SEPARATOR
    "\u200b-\u200f\u202a-\u202e"    # zero-width and bidi overrides: a name
    "\u2066-\u2069\ufeff"           # carrying these can visually reorder the
                                      # record, or defeat the near-name check
                                      # while looking identical to a reader
    "|" '"'                           # the record separator, and the quote
                                      # `field()` wraps values in
    "]"
)


MAX_SCALAR = 200

# A name is emitted unquoted, so anything that could open a new field in the
# `KEY=value key=value` grammar is refused outright. No dependency name in any
# of the fourteen supported formats legitimately contains whitespace or `=`;
# a name that does is a forgery attempt or a parse gone wrong, and both are
# reasons to report the manifest unreadable rather than to print it.
#
# `@` is NOT refused: `@scope/name` is an ordinary npm package. It makes
# `name@version` ambiguous from the left, which is why a consumer splits it
# from the right, exactly as npm's own tooling does.
_FORBIDDEN_IN_NAME = re.compile(r"[\s=]")


def safe_name(value):
    """Return `value` if it is usable as an unquoted output field, else None."""
    value = safe_scalar(value)
    if value is None:
        return None
    if _FORBIDDEN_IN_NAME.search(value):
        return None
    return value


class ParseError(Exception):
    """A manifest could not be read. Carries the reason the output prints."""


class ParseResult(object):
    """What one manifest declares.

    deps: {name: (version_or_None, line_number)}
    hooks: [(name, line_number)] — packages the manifest itself says run an
           install script. Only a lockfile can answer this offline.
    """

    def __init__(self, deps=None, hooks=None, replaces=None):
        # {name: {version_or_None: line_or_None}}. A lockfile legitimately
        # holds several versions of one package — windows-sys and the pnpm
        # store do it routinely — and a plain name->version map reports only
        # whichever came last in the file, hiding the others entirely.
        self.deps = deps or {}
        self.hooks = hooks or []
        # [(module, target, version, line)] — a go.mod replace. Kept apart
        # from deps because the interesting fact is WHICH module stopped
        # coming from upstream, and a target reported as an added package
        # says nothing about that.
        self.replaces = replaces or []
        # Redirect candidates from a table named `sources`, kept aside until
        # the whole document is read so each can be checked against the
        # dependencies actually declared.
        self.pending_sources = []

    def add(self, name, version, line):
        self.deps.setdefault(name, {}).setdefault(version, line)

    def names(self):
        return set(self.deps)


def safe_scalar(value):
    """Return `value` collapsed to a printable single-line scalar, or None.

    None means the caller must refuse the value rather than print it. A
    truncated value is still a value the reader can act on; a value carrying a
    newline is a forged second record, so length is trimmed and control
    characters are refused.
    """
    if value is None:
        return None
    if not isinstance(value, str):
        value = str(value)
    value = value.strip()
    if not value:
        return None
    if _FORBIDDEN.search(value):
        return None
    if len(value) > MAX_SCALAR:
        value = value[:MAX_SCALAR - 1] + "…"
    return value


# ---------------------------------------------------------------------------
# TOML
#
# Parsed with a real TOML parser, not a hand-rolled scanner. Three review
# cycles were spent patching a line-oriented one, and each fix revealed the
# next construct it did not know: tri-quoted strings, backslash escapes,
# inline-table keys, multi-clause constraints. A parser has none of those gaps
# to find, and the last one was severe — a pyproject.toml carrying an ordinary
# tri-quoted readme made its whole dependency list invisible while the run
# still reported ok.
#
# The cost is line numbers: a TOML parser returns values, not the lines they
# came from. They are recovered by a separate best-effort text search, and
# when that fails the location is the file, which references/finding-schema.md
# permits. A wrong line is worse than no line; a wrong dependency list is
# worse than both.

try:
    import tomllib as _toml
except ImportError:  # pragma: no cover - Python < 3.11
    try:
        import tomli as _toml
    except ImportError:
        _toml = None


def _load_toml(text):
    if _toml is None:
        raise ParseError(
            "no TOML parser available (Python < 3.11 needs tomli; see "
            "plugins/flow/requirements.txt)"
        )
    try:
        return _toml.loads(text)
    except Exception as e:
        raise ParseError("not valid TOML (%s)" % type(e).__name__)


# A dependency name is never any of these; they are how a tool spells
# something other than a package inside a dependency table.
_NOT_A_PACKAGE = frozenset(("python", "include-group"))


def _constraint(raw):
    """Normalise a version constraint to one comparable, printable value.

    Whitespace is removed rather than preserved: `requests>=2.0` and
    `requests >= 2.0` are the same requirement, and treating them as different
    versions turns a formatter run into a dependency change. An exact pin
    keeps its bare version so the ordinary case still reads as a version;
    every other constraint keeps its operator, because `==2.31.0` becoming
    `>=2.31.0` is a real change and storing only the number hid it.
    """
    if raw is None:
        return None
    if not isinstance(raw, str):
        return None
    raw = re.sub(r"\s+", "", raw)
    if raw.startswith("=="):
        raw = raw[2:]
    return raw or None


# `name`, `name[extra]`, `name>=1.0,<2.0`, `name ; marker`
_PEP508 = re.compile(
    r'^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*([^;]*)'
)


# A direct reference's target is a URL: any scheme, recognised by its shape
# (RFC 3986: a letter, then letters, digits, +, . or -, then ://), not by a
# list. A fixed list read `pkg @ sftp://ex.com/p.whl` as the version
# "@sftp://ex.com/p.whl" of an ordinary package.
_DIRECT_REF_URL = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://")


def pep503(name):
    """A Python package name as PEP 503 normalises it: lowercase, and every run
    of -, _ and . one -. pip, uv and PyPI treat `my_pkg`, `My.Pkg` and
    `my-pkg` as one project, so wherever one Python name is matched against
    another it is matched in this form."""
    return re.sub(r"[-_.]+", "-", name.lower())


def _split_direct_reference(item):
    """Split `name @ url` into (name, url); otherwise (item, None).

    A direct reference is the standard PEP 621 and requirements.txt way to
    point a dependency somewhere other than the index — the Python equivalent
    of a go.mod replace. Dropping the url at the `@` reported an ordinary
    unpinned package from PyPI, with nothing to say the wheel comes from
    somewhere else.
    """
    left, sep, right = item.partition("@")
    if sep:
        right = right.strip()
        if _DIRECT_REF_URL.match(right):
            # An environment marker follows the URL after a `;`
            # (`pkg @ https://ex.com/a.whl ; python_version<"3.9"`); it says
            # when the requirement applies, and is not part of the target.
            return left.strip(), right.split(";", 1)[0].strip()
    return item, None


def _add_pep508(result, item, text):
    if not isinstance(item, str) or not item.strip():
        return
    item, url = _split_direct_reference(item)
    m = _PEP508.match(item)
    if not m:
        return
    name = m.group(1).lower()
    if name in _NOT_A_PACKAGE:
        return
    result.add(name, _constraint(m.group(2)), None)
    if url:
        result.replaces.append((name, url, None, None))


def _version_of(value):
    """A dependency's version, however the table spells it."""
    if isinstance(value, str):
        return _constraint(value)
    if isinstance(value, dict):
        v = value.get("version")
        return _constraint(v) if isinstance(v, str) else None
    if isinstance(value, list):
        # poetry multiple constraints: [{version = "<=1.9", ...}, ...]
        for entry in value:
            if isinstance(entry, dict) and isinstance(entry.get("version"), str):
                return _constraint(entry["version"])
    return None


_SOURCE_KEYS = ("git", "url", "path")


def _source_of(value):
    """Where a dependency is fetched from, when it is not the index."""
    if isinstance(value, dict):
        for key in _SOURCE_KEYS:
            if isinstance(value.get(key), str):
                return value[key]
    return None


# Tables whose KEYS are group names, by specification rather than by guess.
# PEP 621 extras, PEP 735 groups and pdm's dev groups are defined this way; no
# inspection of their values can tell you more than the spec already does.
_GROUP_TABLES = frozenset((
    "dependency-groups",
    "tool.pdm.dev-dependencies",
))

# Tables whose KEYS are package names, by specification. poetry writes a
# version, an inline table, or an array of tables (multiple constraints) as
# the value, so its shape overlaps with a group table's and cannot separate
# the two.
_NAME_TABLE_PREFIXES = ("tool.poetry",)


def _table_kind(full_path, value):
    """Return 'groups' or 'names' for a dependency table.

    Shape is consulted only for a table no specification covers. Deciding by
    shape where the spec is explicit is what produced two defects in a row: a
    poetry group of multiple-constraints arrays read as groups and vanished,
    and then a PEP 735 group holding an include-group table read as names,
    inventing a package called after the group and losing its real contents.
    Each fix was a better guess; the guess itself was the defect.
    """
    if full_path in _GROUP_TABLES or full_path.endswith(".optional-dependencies"):
        return "groups"
    if full_path.startswith(_NAME_TABLE_PREFIXES):
        return "names"
    if value and all(
            isinstance(v, list) and all(isinstance(x, str) for x in v)
            for v in value.values()):
        return "groups"
    return "names"


def _harvest_dependencies(node, result, text, path=()):
    """Walk a parsed TOML document collecting every dependency table.

    Recognising tables by shape rather than by a list of known tool names is
    what makes an unknown tool readable. Three cycles were lost adding
    `tool.pdm`, then `tool.uv`, then `tool.rye`, then `tool.pixi` one at a
    time — each absence reported as `ok` with the packages missing, or as a
    blanket `unavailable`.
    """
    if not isinstance(node, dict):
        return
    for key, value in node.items():
        if not isinstance(key, str):
            continue
        low = key.lower()
        here = path + (low,)

        if low == "sources" and isinstance(value, dict):
            # tool.uv.sources and its kin redirect a package away from the
            # index. `sources` is a common word, though, so an entry only
            # counts when the project actually depends on that name — a source
            # override for something nothing depends on redirects nothing.
            # Resolved after the walk, when every dependency is known.
            for name, spec in value.items():
                src = _source_of(spec)
                if isinstance(name, str) and src:
                    result.pending_sources.append((name.lower(), src))
            continue

        # A build backend runs its own code at install time, so what it
        # requires is the highest-consequence dependency in the file. The key
        # is `requires`, so the *dependencies suffix never matched it.
        if low == "requires" and path[-1:] == ("build-system",) and isinstance(value, list):
            for item in value:
                _add_pep508(result, item, text)
            continue

        # Cargo redirects every crate in the tree away from the registry.
        # [patch.<registry>] and the deprecated [replace] are the Rust
        # equivalent of a go.mod replace, and were invisible.
        if not path and low in ("patch", "replace") and isinstance(value, dict):
            for outer_key, outer_val in value.items():
                pairs = (outer_val.items() if low == "patch" and isinstance(outer_val, dict)
                         else [(outer_key, outer_val)])
                for name, spec in pairs:
                    if not isinstance(name, str):
                        continue
                    src = _source_of(spec)
                    if src:
                        # [replace] keys carry a ":version" suffix.
                        result.replaces.append(
                            (name.split(":")[0].lower(), src, None, None))
            continue

        if low.endswith("dependencies") or low == "dependency-groups":
            if isinstance(value, list):
                for item in value:
                    _add_pep508(result, item, text)
                continue
            if isinstance(value, dict):
                if _table_kind(".".join(here), value) == "groups":
                    for group in value.values():
                        if isinstance(group, list):
                            # A group may hold tables as well as strings —
                            # PEP 735's {include-group = "..."} is one — and
                            # _add_pep508 ignores anything that is not a
                            # requirement string.
                            for item in group:
                                _add_pep508(result, item, text)
                    continue
                for name, spec in value.items():
                    if not isinstance(name, str):
                        continue
                    low_name = name.lower()
                    if low_name in _NOT_A_PACKAGE:
                        continue
                    if isinstance(spec, list) and all(
                            isinstance(x, str) for x in spec):
                        for item in spec:
                            _add_pep508(result, item, text)
                        continue
                    result.add(low_name, _version_of(spec), None)
                    src = _source_of(spec)
                    if src:
                        result.replaces.append((low_name, src, None, None))
                continue

        if isinstance(value, dict):
            _harvest_dependencies(value, result, text, here)


def parse_toml_manifest(text):
    """pyproject.toml and Cargo.toml — every dependency table either declares."""
    data = _load_toml(text)
    r = ParseResult()
    _harvest_dependencies(data, r, text)
    # Matched PEP 503 normalised: `[tool.uv.sources] my_pkg` redirects the
    # dependency declared as `my-pkg`, as uv itself reads it. Cargo treats -
    # and _ in a crate name the same way. The record names the dependency as
    # it is declared.
    declared = {pep503(n): n for n in r.deps}
    for name, src in r.pending_sources:
        if pep503(name) in declared:
            r.replaces.append((declared[pep503(name)], src, None, None))
    r.pending_sources = []
    return r


def parse_pyproject(text):
    return parse_toml_manifest(text)


def parse_cargo_toml(text):
    return parse_toml_manifest(text)


def parse_toml_lock(text):
    """poetry.lock and Cargo.lock: an array of [[package]] tables."""
    data = _load_toml(text)
    r = ParseResult()
    packages = data.get("package")
    if isinstance(packages, list):
        for entry in packages:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if not isinstance(name, str):
                continue
            version = entry.get("version")
            r.add(name.lower(),
                  _constraint(version) if isinstance(version, str) else None,
                  None)
    return r


# ---------------------------------------------------------------------------
# Python requirements files (not TOML)

_REQ_LINE = re.compile(
    r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*([^;#]*)"
)
_URL_REQ = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*(\+[A-Za-z][A-Za-z0-9+.-]*)?://")
# pip's own comment rule: a `#` at the start of a line or after whitespace.
# A `#` inside a token is part of it: `git+https://h/x.git#egg=x` names its
# package in that fragment.
_REQ_COMMENT = re.compile(r"(?:^|\s)#.*$")
# pip's comment line: `#` first on the line after any whitespace. It ends a
# backslash continuation instead of being joined to it.
_REQ_COMMENT_LINE = re.compile(r"^\s*#")
# `-e <target>`, `-e<target>`, `--editable <target>`, `--editable=<target>`.
_REQ_EDITABLE = re.compile(r"^(?:-e|--editable(?=[\s=]))\s*=?\s*(\S+)")
# A requirement given as a local path rather than a name: it starts with `.`,
# `/` or `~`, carries a path separator, or is an archive file.
_REQ_PATH = re.compile(
    r"^(?:[.~/\\]|[^\s;]*[/\\]"
    r"|[^\s;]*\.(?:whl|zip|tar|tgz|tar\.gz|tar\.bz2|tar\.xz)(?:\s|$))"
)
# The project itself (`.`, `./`, `.[dev]`), what `pip install -e .` installs:
# the code under review, not a package fetched from somewhere else.
_REQ_PROJECT_ITSELF = re.compile(r"^\.[/\\]?(?:\[[^\]]*\])?$")
_REQ_EGG = re.compile(r"[#&]egg=([^&]*)")
_REQ_NAME = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$")


def _requirement_target_name(target, lineno):
    """The package a URL or path requirement installs, read from what the
    line itself says: an `#egg=name` fragment, or a wheel file name
    (`name-1.0-py3-none-any.whl`). A target naming neither is NOT guessed
    at: the file is unreadable, because the package it installs is one a
    reviewer would otherwise be told is not there."""
    egg = _REQ_EGG.search(target)
    if egg:
        name = re.sub(r"\[[^\]]*\]$", "", egg.group(1))
        if _REQ_NAME.match(name):
            return name.lower()
        raise ParseError(
            "the egg fragment of the requirement on line %d is not a package name" % lineno)
    base = re.split(r"[/\\]", re.split(r"[?#]", target, 1)[0].rstrip("/\\"))[-1]
    # {name}-{version}(-{build})?-{python}-{abi}-{platform}.whl
    parts = base[:-4].split("-") if base.lower().endswith(".whl") else []
    if len(parts) in (5, 6) and _REQ_NAME.match(parts[0]):
        return parts[0].lower()
    raise ParseError(
        "the requirement on line %d is a URL or path that names no package "
        "(no egg fragment and no wheel file name)" % lineno)


def _req_continued(lines, index):
    """The line at `index` joined with the lines its trailing backslashes
    continue onto, as pip joins them before it strips comments or splits
    an option line: each backslash-ended line loses its backslashes and runs
    straight into the next, a comment line ends the run, and so does the
    end of the file. Returns the joined line and the index of the line
    after it."""
    parts = []
    while index < len(lines):
        raw = lines[index]
        index += 1
        if not raw.endswith("\\") or _REQ_COMMENT_LINE.match(raw):
            parts.append(" " + raw if _REQ_COMMENT_LINE.match(raw) else raw)
            break
        parts.append(raw.strip("\\"))
    return "".join(parts), index


def _editable_target(line, lineno):
    """The target of an `-e`/`--editable` line, read as pip reads an option
    line: split with shell quoting, so `-e ".[dev]"` is `.[dev]`. None when
    the line names no target. An unclosed quote makes the file unreadable:
    the target cannot be told."""
    try:
        words = shlex.split(line)
    except ValueError:
        raise ParseError("the option on line %d has an unclosed quote" % lineno)
    if not words:
        return None
    first = words[0]
    if first in ("-e", "--editable"):
        return words[1] if len(words) > 1 else None
    for prefix in ("--editable=", "-e"):
        if first.startswith(prefix):
            return first[len(prefix):].lstrip("=") or (words[1] if len(words) > 1 else None)
    return None


def parse_requirements(text):
    """requirements*.txt, line by line.

    A requirement is a name (`flask==2.0`), a direct reference
    (`name @ url`), a URL (`git+https://h/x.git#egg=x`, `https://h/x.whl`),
    a local path (`../x`, `./dist/x.whl`) or an editable install
    (`-e ../x`, `-e git+https://...#egg=x`). Each of the last three installs
    a package from somewhere other than the index, so it is a redirect as
    well as a dependency, named by its `#egg=` fragment or its wheel file
    name; one that names neither makes the file unreadable. An editable
    line is split with shell quoting, as pip splits it (`-e ".[dev]"`),
    once the lines its trailing backslashes continue onto are joined to it,
    as pip joins them; one with an unclosed quote makes the file
    unreadable. The project
    itself (`.`, `-e .`, `-e .[dev]`) is the code under review and is not
    read. No other option line (`-r`, `-c`, `--index-url`,
    `--extra-index-url`, `--find-links`, ...) is read."""
    r = ParseResult()
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        lineno = index + 1
        raw = lines[index]
        index += 1
        line = _REQ_COMMENT.sub("", raw).strip()
        if not line:
            continue
        target = None
        if line.startswith("-"):
            if not _REQ_EDITABLE.match(line):
                continue
            if raw.endswith("\\"):
                raw, index = _req_continued(lines, index - 1)
                line = _REQ_COMMENT.sub("", raw).strip()
            target = _editable_target(line, lineno)
            if target is None:
                continue
        elif _URL_REQ.match(line) or _REQ_PATH.match(line):
            target = line.split()[0]
        if target is not None:
            if _REQ_PROJECT_ITSELF.match(target):
                continue
            name = _requirement_target_name(target, lineno)
            r.add(name, None, lineno)
            r.replaces.append((name, target, None, lineno))
            continue
        # A direct reference here is the same redirect as in pyproject.toml;
        # the two Python formats must not disagree about what it means.
        line, url = _split_direct_reference(line)
        m = _REQ_LINE.match(line)
        if not m:
            continue
        name = m.group(1).lower()
        if name in _NOT_A_PACKAGE:
            continue
        r.add(name, _constraint(m.group(2)), lineno)
        if url:
            r.replaces.append((name, url, None, lineno))
    return r


# ---------------------------------------------------------------------------
# Go

_GO_REQUIRE = re.compile(
    r"^\s*(?:require\s+)?([a-zA-Z0-9][^\s]*\.[^\s]*/?[^\s]*)\s+(v[^\s/]+)"
)
_GO_REPLACE = re.compile(
    r"^\s*(?:replace\s+)?([^\s]+)(?:\s+v[^\s]+)?\s*=>\s*([^\s]+)(?:\s+(v[^\s]+))?\s*$"
)


def parse_go_mod(text):
    """require and replace.

    `replace` is read because it is the one go.mod directive that changes
    which code is actually fetched: a module redirected to a fork is a
    dependency change however the require block reads.
    """
    r = ParseResult()
    block = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("//", 1)[0].rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        bm = re.match(r"^(require|replace|exclude)\s*\($", stripped)
        if bm:
            block = bm.group(1)
            continue
        if block and stripped == ")":
            block = None
            continue
        kind = block
        if kind is None:
            for word in ("require", "replace", "exclude"):
                if stripped.startswith(word + " "):
                    kind = word
                    break
        if kind == "exclude" or kind is None:
            continue
        if kind == "replace":
            m = _GO_REPLACE.match(line)
            if m:
                r.replaces.append((m.group(1), m.group(2), m.group(3), lineno))
            continue
        m = _GO_REQUIRE.match(line)
        if m:
            r.add(m.group(1), m.group(2), lineno)
    return r


def parse_go_sum(text):
    r = ParseResult()
    for lineno, raw in enumerate(text.splitlines(), 1):
        parts = raw.split()
        if len(parts) < 3:
            continue
        name, version = parts[0], parts[1]
        version = version.replace("/go.mod", "")
        if not version.startswith("v"):
            continue
        r.add(name, version, lineno)
    return r


# ---------------------------------------------------------------------------
# npm

_NPM_DEP_SECTIONS = (
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
)
_NPM_ALIAS = re.compile(r"^npm:(.+)@([^@]+)$")
# A package.json spec that npm fetches from somewhere other than the
# registry, as npm-package-arg reads it: a URL (git+https://, git+ssh://,
# git://, https://...tgz), a hosted-git shorthand (github:, gitlab:,
# bitbucket:, gist:), a local path with file: or link:, or without one (one
# starting with `.`, `~/`, `/` or `\`, or a drive letter: `../x`, `~/x`,
# `/abs`, `C:/x`), an scp-style git spec (`git@host:path`), any other spec
# holding a slash (the GitHub shorthand `user/repo[#ref]`, a path `a/b/c`),
# and a tarball file name (`x.tgz`, in any case, as npm-package-arg matches
# it: `x.TGZ`, `x.Tar.Gz`). A semver range (`~1.2.3`, `^2.0.0`) or a
# dist-tag (`latest`) is none of these, and an `npm:` alias is read apart.
_NPM_REDIRECT = re.compile(
    r"^(?!npm:)(?:[A-Za-z][A-Za-z0-9+.-]*://|(?:github|gitlab|bitbucket|gist|file|link):"
    r"|[.]|~/|[/\\]|[A-Za-z]:|[^@\s/:]+@[^:\s/]+:|.*[/\\]|.*(?i:\.(?:tgz|tar\.gz|tar))$)"
)


def _line_of_key(text, key):
    """Line number of the first `"key":` occurrence, or None.

    The value is parsed from JSON and the line found separately: a JSON parser
    has no line numbers, and inventing one from the parse order points at a
    different row whenever key order and file order disagree. None is a real
    answer — a minified manifest has no line to cite, and finding-schema.md
    allows a file-level location.
    """
    needle = '"%s"' % key
    for lineno, raw in enumerate(text.splitlines(), 1):
        stripped = raw.lstrip()
        if stripped.startswith(needle) and stripped[len(needle):].lstrip().startswith(":"):
            return lineno
    return None


def parse_package_json(text):
    try:
        data = json.loads(text)
    except ValueError as e:
        raise ParseError("not valid JSON (%s)" % type(e).__name__)
    if not isinstance(data, dict):
        raise ParseError("top level is not a JSON object")
    r = ParseResult()
    for section in _NPM_DEP_SECTIONS:
        block = data.get(section)
        if not isinstance(block, dict):
            continue
        for name, version in block.items():
            if not isinstance(name, str):
                continue
            line = _line_of_key(text, name)
            v = version if isinstance(version, str) else None
            r.add(name, v, line)
            # `"react": "npm:evil-react@1.0.0"` installs evil-react. Compared
            # only under the key, the near-name check runs against a name the
            # project already trusts and the package that actually installs is
            # never compared with anything.
            if v:
                am = _NPM_ALIAS.match(v)
                if am:
                    r.add(am.group(1), am.group(2), line)
                elif _NPM_REDIRECT.match(v.strip()):
                    r.replaces.append((name, v.strip(), None, line))
    return r


def parse_package_lock(text):
    try:
        data = json.loads(text)
    except ValueError as e:
        raise ParseError("not valid JSON (%s)" % type(e).__name__)
    if not isinstance(data, dict):
        raise ParseError("top level is not a JSON object")
    r = ParseResult()
    packages = data.get("packages")
    if isinstance(packages, dict):
        for path, entry in packages.items():
            if not isinstance(entry, dict) or not path:
                continue
            marker = "node_modules/"
            idx = path.rfind(marker)
            if idx == -1:
                continue
            name = path[idx + len(marker):]
            if not name:
                continue
            version = entry.get("version")
            line = _line_of_key(text, path) or _line_of_key(text, name)
            r.add(name, version if isinstance(version, str) else None, line)
            if entry.get("hasInstallScript") is True:
                r.hooks.append((name, line))
    legacy = data.get("dependencies")
    if isinstance(legacy, dict) and not r.deps:
        for name, entry in legacy.items():
            if not isinstance(name, str):
                continue
            version = entry.get("version") if isinstance(entry, dict) else None
            r.add(name, version if isinstance(version, str) else None,
                  _line_of_key(text, name))
    return r


_YARN_HEADER = re.compile(r'^"?([^",\s][^",]*?)@[^",]*"?[,:]')
_YARN_VERSION = re.compile(r'^\s+version\s+"?([^"\s]+)"?')


def parse_yarn_lock(text):
    """yarn v1 classic. A berry (v2+) lock is YAML and is not this format."""
    if "__metadata:" in text:
        raise ParseError("yarn berry lockfile — not the v1 format this reads")
    r = ParseResult()
    pending = []
    pending_line = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        if raw.startswith("#") or not raw.strip():
            continue
        if not raw[0].isspace():
            pending = []
            pending_line = lineno
            for spec in raw.rstrip(":").split(","):
                spec = spec.strip()
                m = _YARN_HEADER.match(spec + ":")
                if m:
                    alias = None
                    # Take the remainder after the name the header regex
                    # already extracted. Splitting on the first `@` instead
                    # splits a scoped key on its own scope marker, so
                    # `@scope/react@npm:evil-scoped@1.0.0` never looked like
                    # an alias at all and the package that installs went
                    # unnamed — while the unscoped form worked, which is how
                    # the fixture missed it.
                    _name = m.group(1)
                    _idx = spec.find(_name)
                    rhs = spec[_idx + len(_name) + 1:] if _idx != -1 else ""
                    rhs = rhs.strip().strip('"').rstrip(":")
                    if rhs.startswith("npm:"):
                        am = _NPM_ALIAS.match(rhs)
                        if am:
                            alias = am.group(1)
                    pending.append((m.group(1), alias))
            continue
        m = _YARN_VERSION.match(raw)
        if m and pending:
            for name, alias in pending:
                r.add(name, m.group(1), pending_line)
                # `react@npm:evil-react@^1.0.0` installs evil-react. Reported
                # only under the key, the near-name check runs against a name
                # the project already trusts. package.json already defends
                # this; yarn was the one parser that did not.
                if alias:
                    r.add(alias, m.group(1), pending_line)
            pending = []
    return r


_PNPM_ENTRY = re.compile(r"^\s{2,}(/?[^:\s][^:]*?):\s*$")


def _pnpm_strip_peers(key):
    """Remove a peer-dependency suffix from a pnpm store key.

    v5 writes `/react-dom/16.14.0_react@16.14.0`, v6+ writes
    `react-dom@18.2.0(react@18.2.0)`. Left on, the suffix becomes part of the
    name and the version, so the entry names a package that does not exist and
    the one that does is never reported.
    """
    cut = key.find("(")
    if cut != -1:
        key = key[:cut]
    idx = key.find("_", 1)
    while idx != -1:
        if "@" in key[idx + 1:]:
            return key[:idx]
        idx = key.find("_", idx + 1)
    return key


def parse_pnpm_lock(text):
    r = ParseResult()
    in_packages = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw[0].isspace():
            in_packages = raw.startswith("packages:") or raw.startswith("snapshots:")
            continue
        if not in_packages:
            continue
        m = _PNPM_ENTRY.match(raw)
        if not m:
            continue
        key = _pnpm_strip_peers(m.group(1).strip().strip("'\""))
        name = version = None
        if key.startswith("/"):
            body = key[1:]
            if "@" in body[1:]:
                h, _, t = body.rpartition("@")
                if h and "/" not in t:
                    name, version = h, t
            if name is None:
                h, _, t = body.rpartition("/")
                if h:
                    name, version = h, t
        elif "@" in key[1:]:
            h, _, t = key.rpartition("@")
            if h and "/" not in t:
                name, version = h, t
        if name:
            r.add(name, version, lineno)
    return r


# ---------------------------------------------------------------------------
# Ruby

# `gem` as a method call: `gem "x"`, `gem("x")`. Not `gemspec` or `gem_group`.
_GEM_START = re.compile(r"^\s*gem(?![A-Za-z0-9_?!])\s*(\(?)(.*)$")
_GEM_LITERAL = re.compile(r"^(['\"])([^'\"]+)\1")
# The options that fetch a gem from somewhere other than its registry, with
# the key written as a label (`git: "url"`, `"git": "url"`), a symbol
# (`:git => "url"`) or a string (`"git" => "url"`): Bundler reads them all
# alike. A `git_source(:name)` line adds `name` to them. `gist` is one of
# Bundler's built-in git sources, beside `github`, `gitlab` and `bitbucket`.
_GEM_SOURCE_KEYS = ("git", "github", "gitlab", "bitbucket", "gist", "path")
_GEM_ARG_LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):(?!:)")
_GEM_ARG_SYMBOL_KEY = re.compile(r"^:([A-Za-z_][A-Za-z0-9_]*)\s*=>")
_GEM_ARG_STRING_KEY = re.compile(r"^\s*(?:=>|:(?!:))")
# `git_source(:mine) { |repo| ... }` declares the gem option `mine:`.
_GIT_SOURCE = re.compile(r"^\s*git_source(?![A-Za-z0-9_?!])")
_GIT_SOURCE_NAME = re.compile(
    r"^\s*git_source\s*\(?\s*(?::([A-Za-z_][A-Za-z0-9_]*)|(['\"])([A-Za-z_][A-Za-z0-9_]*)\2)"
)
# A statement that starts a block whose gems all come from one place:
# `git "url" do`, `path "dir" do`, `github "user/repo" do`, also written
# `git("url") { ... }`, and with its options over several lines. Not
# `git_source`, a label (`git:`), a method call on a variable named `path`
# (`path.each`) or an assignment to one (`path = ...`).
_GEM_BLOCK_START = re.compile(
    r"^\s*(git|github|gitlab|bitbucket|gist|path)(?![A-Za-z0-9_?!:])(?!\s*(?:\.|::|=))"
)
_DO = re.compile(r"\bdo\s*(\|[^|]*\|)?\s*$")
# A `{` that ends a line and opens a block (`path("x") {`, `{ |g|`): one
# after a comma, a bracket, `=`, `=>`, a label, `|` or `&` opens a hash.
_BRACE_OPEN = re.compile(r"(\S)\s*(\{)\s*(?:\|[^|]*\|)?\s*$")
_END = re.compile(r"^\s*end\b")
# A line that opens a keyword block closed by `end`: the keyword starts the
# statement (`if ENV["X"]`) or is the value of an assignment
# (`pin = if ENV["X"]`, `x ||= begin`). A modifier (`gem "x" if c`) follows an
# expression instead and opens nothing. A label (`if:`) is not the keyword.
_KEYWORD_OPEN = re.compile(
    r"(?:^\s*|(?<![=!<>])=(?![=~>])\s*)"
    r"(if|unless|case|while|until|for|begin|def|class|module)(?![A-Za-z0-9_?!:])"
)
# A keyword block that also closes on its line (`def x; end`,
# `if c then y end`), and an endless method (`def x = 1`, `def x(a) = a`),
# which takes no end. Its `=` follows the parameter list or a space after the
# name: `def mode=(v)` and `def []=(k, v)` are setters, which take an end.
_ENDS_ON_LINE = re.compile(r"(?:^|[\s;])end\s*$")
_ENDLESS_DEF = re.compile(r"^\s*def\s+[^\s(;]+(?:\s*\([^)]*\)|\s)\s*=(?![=~>])")
# A gem call without parentheses carries on to the next line when its line
# ends where Ruby cannot end a statement: after a comma, a backslash, a hash
# rocket, a label with no value yet, `||`/`&&`, or an open bracket.
_GEM_CONTINUES = re.compile(r"(?:,|\\|=>|[A-Za-z0-9_]:|\|\||&&|[(\[{])\s*$")
_RUBY_STRING = re.compile(r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`")
# A line a continued gem call cannot run into: a statement of its own.
_GEMFILE_STATEMENT = re.compile(
    r"^\s*(?:gem|gemspec|git|github|gitlab|bitbucket|gist|path|group|platforms?"
    r"|source|ruby|git_source|install_if|eval_gemfile|end|else|elsif|when"
    r"|if|unless|case|while|until|for|begin|def|class|module)(?![A-Za-z0-9_?!:])"
)
# What a backslash may continue a statement into: a modifier that ends it
# (`gem "x" \` then `if c`), and, for a statement other than a gem call, a
# keyword that is the value it assigns (`pin = \` then `if c`).
_MODIFIER = re.compile(r"^\s*(?:if|unless|while|until|rescue)(?![A-Za-z0-9_?!:])")
_KEYWORD_VALUE = re.compile(
    r"^\s*(?:if|unless|case|while|until|for|begin|def|class|module)(?![A-Za-z0-9_?!:])"
)
# A block comment: from a line starting `=begin` to one starting `=end`.
_DOC_BEGIN = re.compile(r"^=begin(?:\s|$)")
_DOC_END = re.compile(r"^=end(?:\s|$)")


# A `gem` call anywhere in a line's code: not `gemspec`, `gem_group`,
# `Gem::Version`, `.gem` or `:gem`. Read on the line with its strings blanked.
_GEM_CALL_ANYWHERE = re.compile(r"(?<![A-Za-z0-9_.:@$])gem(?=[ \t(])")
_RUBY_STRING = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`')


def _ruby_code(raw):
    """A Gemfile line without its comment, as this parser reads it. A `#`
    inside a quoted string or a backtick command (a URL fragment, a `#{...}`
    interpolation) is not a comment, so the rest of the line is kept."""
    stack = []  # open quotes, and `{` for the code of an interpolation
    i = 0
    while i < len(raw):
        c = raw[i]
        top = stack[-1] if stack else None
        if top in ('"', "'", "`"):
            if c == "\\":
                i += 2
                continue
            if c == top:
                stack.pop()
            elif top != "'" and raw.startswith("#{", i):
                stack.append("{")
                i += 2
                continue
        elif c == "#" and not stack:
            return raw[:i].rstrip()
        elif c in "\"'`":
            stack.append(c)
        elif top == "{" and c in "{}":
            if c == "{":
                stack.append(c)
            else:
                stack.pop()
        i += 1
    return raw.rstrip()


# What starts an interpolation in a double-quoted string: `#{expr}`,
# `#@ivar`, `#@@cvar` and `#$gvar`. Read wider than Ruby's own rule (`#@`
# and `#$` count whatever follows them, and an escaped `\#{` counts too), so
# a value this cannot be sure of is refused rather than printed as a target
# it may not be.
_INTERPOLATION = re.compile(r"#[{@$]")


def _literal(quote, value):
    """A quoted value as written, or None when it interpolates: a
    double-quoted value holding `#{...}`, `#@ivar`, `#@@cvar` or `#$gvar`,
    whose text is then decided when the Gemfile runs, not by what it says.
    A single-quoted value is not interpolated, so it is always as written."""
    if value is None or (quote != "'" and _INTERPOLATION.search(value)):
        return None
    return value


def _ruby_lines(text):
    """The Gemfile's lines, with each line of a `=begin` ... `=end` block
    comment blank, so it is read as the comment it is."""
    lines = text.splitlines()
    begun = None
    for index, raw in enumerate(lines):
        if begun is not None:
            if _DOC_END.match(raw):
                begun = None
            lines[index] = ""
        elif _DOC_BEGIN.match(raw):
            begun = index + 1
            lines[index] = ""
    if begun is not None:
        raise ParseError("the =begin on line %d has no =end" % begun)
    return lines


def _statement(lines, index, line, lineno, kind=None):
    """The statement that starts with `line` (line `lineno`), read with the
    lines that continue it, and the index of the line after it. `kind` is
    "gem call" for a gem call without parentheses, "<keyword> block" for a
    statement starting with a git/github/path block keyword, and None for any
    other. A statement continues past a trailing backslash; a gem call or a
    block keyword's call also past a trailing comma, hash rocket, label,
    `||`/`&&` or open bracket, and over blank lines, until the block
    keyword's line ends by opening its block (`do`, `{`). A continuation
    line that is a statement of its own makes the file unreadable, except a
    modifier (`if`, `unless`, ...) right after a backslash, which ends the
    statement it follows, and, for any other statement, a keyword that is
    the value it assigns."""
    joined = kind is not None
    what = kind or "statement"
    while True:
        backslash = line.endswith("\\")
        head = line[:-1].rstrip() if backslash else line
        continues = joined and _gem_call_continues(line) and not (
            kind != "gem call" and _block_opener(line))
        if not backslash and not continues:
            return line, index
        start = index
        if joined:
            while index < len(lines) and not _ruby_code(lines[index]).strip():
                index += 1
        if index >= len(lines):
            if joined:
                raise ParseError("the %s on line %d continues past the end of the file" % (what, lineno))
            return head, index
        nxt = _ruby_code(lines[index])
        if _GEMFILE_STATEMENT.match(nxt):
            modifier = backslash and index == start and _MODIFIER.match(nxt) and not _gem_call_continues(head)
            value = backslash and not joined and _KEYWORD_VALUE.match(nxt)
            if not (modifier or value):
                raise ParseError("the %s on line %d continues into line %d, which is not part of it" % (what, lineno, index + 1))
        line = ("%s %s" % (head, nxt.strip())).rstrip()
        index += 1


def _gem_call_continues(line):
    if _GEM_CONTINUES.search(line):
        return True
    bare = _RUBY_STRING.sub('""', line)
    return sum(bare.count(c) for c in "([{") > sum(bare.count(c) for c in ")]}")


def _keyword_block_opens(line):
    """Whether `line` opens a keyword block that a later `end` closes."""
    if not _KEYWORD_OPEN.search(line):
        return False
    return not (_ENDS_ON_LINE.search(line) or _ENDLESS_DEF.match(line))


def _gem_source(kind, value):
    """The target a gem source option names: the URL or path as written, with
    the hosted-git shorthands kept recognisable (`github:user/repo`)."""
    return value if kind in ("git", "path") else "%s:%s" % (kind, value)


def _blank_strings(code):
    """`code` with the text inside each quoted string or backtick command
    replaced by spaces, so brackets, commas and `;` in it are not read as
    code. Every character keeps its position."""
    return _RUBY_STRING.sub(
        lambda m: m.group(0)[0] + " " * (len(m.group(0)) - 2) + m.group(0)[-1], code)


def _top_level_semicolon(code):
    """The position of the first `;` outside brackets and strings, or None."""
    depth = 0
    for i, c in enumerate(_blank_strings(code)):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ";" and depth == 0:
            return i
    return None


def _string_at(text):
    """(quote, value) of the quoted string `text` starts with, or None. A
    backtick command is not a string literal."""
    sm = _RUBY_STRING.match(text)
    if not sm or sm.group(0)[0] == "`":
        return None
    return sm.group(0)[0], sm.group(0)[1:-1], text[sm.end():]


def _gem_args(code, lineno, what="the gem call"):
    """The arguments of a gem call (or a block keyword's call, named by
    `what`) after its first, split at the commas
    outside brackets and strings: [("version", quote, value)] for a string,
    [("option", key, quote, value)] for an option (quote and value None when
    the value is not a string). An argument this cannot read as either (a
    variable, a method call, a hash literal, a `*`/`**` splat: any of them
    can carry a `git:` option) makes the file unreadable."""
    blank = _blank_strings(code)
    spans, depth, start = [], 0, 0
    for i, c in enumerate(blank):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            spans.append((start, i))
            start = i + 1
    spans.append((start, len(blank)))
    out = []
    for a, b in spans[1:]:
        arg = code[a:b].strip()
        if not arg:
            continue
        lm = _GEM_ARG_LABEL.match(arg) or _GEM_ARG_SYMBOL_KEY.match(arg)
        key, rest = (lm.group(1), arg[lm.end():]) if lm else (None, None)
        if key is None:
            st = _string_at(arg)
            if st is None:
                if arg.startswith("*"):
                    raise ParseError("%s on line %d passes arguments through a splat" % (what, lineno))
                raise ParseError("%s on line %d passes an argument that is not a string literal or an option" % (what, lineno))
            km = _GEM_ARG_STRING_KEY.match(st[2])
            if not km:
                out.append(("version", st[0], st[1]))
                continue
            key, rest = st[1], st[2][km.end():]
        val = _string_at(rest.strip())
        out.append(("option", key) + ((val[0], val[1]) if val else (None, None)))
    return out


def _block_opener(line):
    """("do" or "{", position) when `line` ends by opening a block, else
    None. Read with its strings blanked, so a `do` or `{` inside one is not
    an opener. A `{` after a comma, a bracket, `=`, `=>`, a label, `|` or `&`
    opens a hash, not a block."""
    blank = _blank_strings(line)
    m = _DO.search(blank)
    if m:
        return "do", m.start()
    m = _BRACE_OPEN.search(blank)
    if m and m.group(1) not in ",([{=>:|&":
        return "{", m.start(2)
    return None


def _block_source(keyword, line, start, lineno):
    """(target, ref) of the git/github/path block that `line` opens, its
    opener (`do` or `{`) at `start`. The target is the first argument, a
    string literal and nothing more (`git "u" + x do` is not one); the ref
    is a literal `ref:`, `tag:` or `branch:` option, written as an argument
    or in a hash literal that is the one argument after the target
    (`git "u", { branch: "x" } do`), or None."""
    what = "the %s block" % keyword
    args = line[_GEM_BLOCK_START.match(line).end():start].strip()
    if args.startswith("("):
        if not args.endswith(")"):
            raise ParseError("%s on line %d does not name a string literal" % (what, lineno))
        args = args[1:-1].strip()
    st = _string_at(args)
    if (st is None or _literal(st[0], st[1]) is None
            or (st[2].strip() and not st[2].lstrip().startswith(","))):
        raise ParseError("%s on line %d does not name a string literal" % (what, lineno))
    # Bundler's block methods take their options as a hash
    # (`git(uri, options = {})`), so `git "u", { branch: "x" } do` passes
    # them as a hash literal: when that is the one argument after the
    # target, its entries are read as the options.
    rest = st[2].strip()[1:].strip()
    if rest.startswith("{"):
        depth = 0
        for i, c in enumerate(_blank_strings(rest)):
            depth += (c == "{") - (c == "}")
            if depth == 0:
                if not rest[i + 1:].strip():
                    args = '"", ' + rest[1:i]
                break
    ref = None
    for arg in _gem_args(args, lineno, what):
        if arg[0] == "option" and arg[1] in ("ref", "tag", "branch"):
            ref = _literal(arg[2], arg[3]) or ref
    return st[1], ref


# What a block frame's closer is called in a message, by what opened it.
_CLOSER = {"do": "end", "{": "}"}


def _close_block(blocks, closer, lineno):
    """Pop the innermost block, which `closer` (`end` or `}`) on line
    `lineno` closes. One that closes nothing, or a block the other closer
    belongs to (`end` for a `{`, `}` for a `do`), makes the file
    unreadable: Ruby would not read it as this parser would."""
    if not blocks:
        raise ParseError("the %s on line %d closes no block this can see" % (closer, lineno))
    opener, _source, opened = blocks[-1]
    if _CLOSER.get(opener, "end") != closer:
        raise ParseError("the %s on line %d closes the %s on line %d" % (closer, lineno, opener, opened))
    blocks.pop()


def _brace_frame(blocks):
    """The innermost `{` frame open, or None. Braces are counted only while
    there is one: a `}` can close only a `{`, so where no `{` frame is open
    a brace changes nothing this tracks, and a lone `{` or `}` in a regex
    or a character literal (`x = /\\{/`, `?}`) around a `do` block is not
    read as one."""
    return next((b for b in reversed(blocks) if b[0] == "{"), None)


# What may hold a `{` or `}` that is not a brace, or start a literal whose
# text runs on over later lines: a regex or a division (`/`), a %-literal or
# a modulo (`%`), a heredoc or an append (`<<`), a character literal or a
# ternary (a `?` that does not end a method name such as `key?`), and a
# quote left open. Read on the code with its closed strings removed.
_BRACE_UNSURE = re.compile(r"[/%]|<<|(?<![A-Za-z0-9_])\?|[\"'`]")


def _brace_unsure(code):
    """Whether this parser cannot be sure which `{` and `}` in `code` are
    braces: it holds one of _BRACE_UNSURE's forms, or a double-quoted
    string or backtick command that interpolates (`"#{"}"}"`), whose inner
    quotes the string pattern does not pair. Ruby is not lexed here, so
    every such line is unsure, whether or not a brace is in it."""
    for m in _RUBY_STRING.finditer(code):
        if m.group(0)[0] != "'" and "#{" in m.group(0):
            return True
    return bool(_BRACE_UNSURE.search(_RUBY_STRING.sub("", code)))


def _close_and_open_braces(blocks, code, lineno):
    """Close a block for each `}` in `code` that no earlier `{` on the line
    opened, then open one for each `{` left open: a multi-line hash literal
    or a brace block (`.each { |g|`), whose `}` must not close a git block
    around it. Nothing is counted while no `{` frame is open."""
    if _brace_frame(blocks) is None:
        return
    opened = 0
    for c in _blank_strings(code):
        if c == "{":
            opened += 1
        elif c == "}":
            if opened:
                opened -= 1
            else:
                _close_block(blocks, "}", lineno)
    for _ in range(opened):
        blocks.append(("{", None, lineno))


def parse_gemfile(text):
    """A Gemfile is Ruby, not a data format.

    A `gem` call that starts its statement and whose name is a literal is
    read, written `gem "x"` or `gem("x")`, with its arguments: string
    versions, and options keyed by a label (`git:`, `"git":`), a symbol
    (`:git =>`) or a string (`"git" =>`). A `gem` line this cannot read (the
    name a variable, a method call or an interpolation; a gem call that does
    not start its statement; a second statement after a `;`; another gem
    call inside its arguments; an argument that is neither a string nor an
    option, such as a variable, a hash literal or a `*`/`**` splat, any of
    which can carry a source option; a `gem(` call that does not close on
    its line; a call without parentheses, or a git/github/path block's
    opening call, whose continuation runs past the end of the file or into
    another statement; a source option or block target whose value is not
    a literal; a `git_source` whose name is not a literal; an `end` that
    closes no block this has seen, or closes a `{` block; inside a `{`
    block, a `}` that closes no block this has seen or closes a `do` block,
    or a line holding a regex, a %-literal, a character literal, a heredoc,
    an interpolation or an unclosed string, any of which can hide a brace
    this would miscount, as can a git/path `{` block's opening call) is
    NOT guessed at: the file is
    reported unreadable, because a dependency this cannot see is one a
    reviewer would be told does not exist. A call without parentheses
    whose line ends with a comma, a backslash or an open bracket is read
    together with the lines that continue it, so options written one per
    line are read like options written on one. Any statement continued with
    a backslash onto a modifier (`if`, `unless`, ...) ends there, so the
    modifier opens no block. A `#` starts a comment only outside a string or
    a backtick command, a double-quoted value that interpolates (`"#{x}"`,
    `"#@ivar"`, `"#@@cvar"`, `"#$gvar"`) is not a literal while a
    single-quoted one, which Ruby does not interpolate, is, and the
    lines of a `=begin` ... `=end` block comment are not read (a `=begin`
    with no `=end` makes the file unreadable).

    A gem fetched from somewhere other than its registry, by a `git:`,
    `github:`, `gitlab:`, `bitbucket:`, `gist:` or `path:` option, an
    option a `git_source(:name)` line declared earlier, or inside a
    `git`/`github`/`path` block (`... do` ... `end` or `(...) {` ... `}`,
    its opening call continued over lines like a gem call's, its options
    arguments or one hash literal), is also a
    redirect: the same record a go.mod replace makes, so a gem built from a
    fork does not read as an unpinned gem from rubygems.org. The redirect's
    version is the git ref, tag or branch (the gem's, else its block's) and
    None for a path, never the version constraint: a version bump is a
    changed dependency, not a new place to fetch it from. Every other block
    a later `end` closes (`group ... do`, and `if`, `unless`, `case`,
    `while`, `until`, `for`, `begin`, `def`, `class` and `module` other than
    their modifier and one-line forms, and other than an endless
    `def x = expr`; a setter or operator `def mode=(v)` takes an end), and
    every `{` a later line's `}` closes (a hash literal, an `.each { |g|`
    block) inside a `{` block, is tracked too, so its closer does not close
    the git block around it. Braces are counted only inside a `{` block,
    since only there can a `}` close anything tracked: around `do` blocks
    alone a lone `{` or `}` in a regex or a character literal is not read
    as one.
    """
    r = ParseResult()
    blocks = []
    source_keys = set(_GEM_SOURCE_KEYS)
    lines = _ruby_lines(text)
    index = 0
    while index < len(lines):
        lineno = index + 1
        line = _ruby_code(lines[index])
        index += 1
        if not line.strip():
            continue
        m = _GEM_START.match(line)
        bk = None if m else _GEM_BLOCK_START.match(line)
        kind = "gem call" if m and not m.group(1) else ("%s block" % bk.group(1) if bk else None)
        line, index = _statement(lines, index, line, lineno, kind)
        # Inside a `{` block, a `}` closes it, so a `}` or `{` this cannot
        # be sure is a brace (one in a regex, a %-literal, a character
        # literal, a heredoc's body or an interpolation) could end the block
        # early and drop the redirect of every gem after it. The file is
        # unreadable instead.
        frame = _brace_frame(blocks)
        if frame is not None and _brace_unsure(line):
            raise ParseError(
                "line %d, inside the { block on line %d, holds a regex, "
                "%%-literal, character literal, heredoc, interpolation or "
                "unclosed string, whose braces this cannot count" % (lineno, frame[2]))
        opener = _block_opener(line) if bk else None
        if opener and opener[0] == "{" and frame is None and _brace_unsure(line[:opener[1]]):
            raise ParseError(
                "the %s { block on line %d holds a regex, %%-literal, "
                "character literal, heredoc, interpolation or unclosed "
                "string in its opening call, whose braces this cannot "
                "count" % (bk.group(1), lineno))
        if opener:
            keyword = bk.group(1)
            target, ref = _block_source(keyword, line, opener[1], lineno)
            blocks.append((opener[0], (_gem_source(keyword, target), ref, keyword), lineno))
            continue
        m = _GEM_START.match(line)
        if m:
            # One statement per gem line: a second one after a `;` (another
            # gem call, say) is not read, so the file is unreadable rather
            # than missing it. A `;` inside brackets or a string is not one.
            semi = _top_level_semicolon(line)
            if semi is not None:
                if line[semi + 1:].strip():
                    raise ParseError("the gem call on line %d is followed by another statement after a ;" % lineno)
                line = line[:semi].rstrip()
                m = _GEM_START.match(line)
            args = m.group(2).strip()
            if m.group(1):
                if not args.endswith(")"):
                    raise ParseError("the gem call on line %d does not close on its line" % lineno)
                args = args[:-1].strip()
            lm = _GEM_LITERAL.match(args)
            if not lm or _literal(lm.group(1), lm.group(2)) is None:
                raise ParseError("gem name on line %d is not a string literal" % lineno)
            name = lm.group(2).lower()
            if _GEM_CALL_ANYWHERE.search(_blank_strings(args[lm.end():])):
                raise ParseError("the gem call on line %d holds another gem call" % lineno)
            version, source, ref, source_key = None, None, None, None
            for arg in _gem_args(args, lineno):
                if arg[0] == "version":
                    if version is None:
                        version = _literal(arg[1], arg[2]) or None
                    continue
                key, value = arg[1], _literal(arg[2], arg[3])
                if key in source_keys:
                    if value is None:
                        raise ParseError("the %s: of gem %s on line %d is not a string literal" % (key, name, lineno))
                    source, source_key = _gem_source(key, value), key
                elif key in ("ref", "tag", "branch") and value is not None:
                    ref = value
            r.add(name, version, lineno)
            if source is None:
                frame = next((b[1] for b in reversed(blocks) if b[1]), None)
                if frame is not None:
                    source, block_ref, source_key = frame
                    ref = ref or block_ref
            # The redirect is the place a gem is fetched from: a path, or a
            # git source at its ref. The version constraint is not part of
            # it, so a version bump there is DEP_CHANGED, not a new
            # redirect, as in Gemfile.lock.
            if source is not None:
                r.replaces.append((name, source, None if source_key == "path" else ref, lineno))
            if _DO.search(line):
                blocks.append(("do", None, lineno))
            continue
        # `git_source(:mine) { |repo| ... }` makes `mine:` a gem source
        # option like `github:`.
        if _GIT_SOURCE.match(line):
            gm = _GIT_SOURCE_NAME.match(line)
            if not gm:
                raise ParseError("the git_source on line %d does not name a literal symbol or string" % lineno)
            source_keys.add(gm.group(1) or gm.group(3))
        # A gem call that does not start its statement (`%w(a b).each { |g|
        # gem g }`, `group :test do gem "x" end`) is one this reads nothing
        # from: the Gemfile is unreadable rather than missing a dependency.
        if _GEM_CALL_ANYWHERE.search(_RUBY_STRING.sub('""', line)):
            raise ParseError("the gem call on line %d is not at the start of its statement" % lineno)
        em = _END.match(line)
        if em:
            _close_block(blocks, "end", lineno)
            _close_and_open_braces(blocks, line[em.end():], lineno)
            continue
        _close_and_open_braces(blocks, line, lineno)
        km = _KEYWORD_OPEN.search(line)
        if _keyword_block_opens(line) or _DO.search(line):
            # One frame even for `while c do`: its do is part of the loop.
            blocks.append((km.group(1) if km and _keyword_block_opens(line) else "do", None, lineno))
    return r


# Exactly four spaces. Under `specs:` a resolved gem is indented four and its
# own requirements six; matching 4-6 reads `activesupport (= 7.0.0)` as a
# top-level gem.
_GEMFILE_LOCK_SPEC = re.compile(
    r"^ {4}(?! )([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\(([^)]*)\))?\s*$"
)
_GEMFILE_LOCK_FIELD = re.compile(r"^ {2}(remote|revision|ref|tag|branch):\s*(.*?)\s*$")


def parse_gemfile_lock(text):
    """Gemfile.lock's specs. A gem resolved in a GIT or PATH section comes
    from that section's remote, not from the registry: each is also a
    redirect. A GIT gem is redirected to the remote at its revision. A PATH
    gem is redirected to the path with no version, since a path names no
    revision and a version bump there is not a new place to fetch from. The
    PATH section whose remote is the project root (`.` or `./`, what a
    Gemfile `gemspec` line resolves to) is the project's own gem, not a
    redirect."""
    r = ParseResult()
    in_specs = False
    section = None
    fields = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        if not raw[0].isspace():
            in_specs = False
            section = raw.strip()
            fields = {}
            continue
        fm = _GEMFILE_LOCK_FIELD.match(raw)
        if fm and not in_specs:
            fields[fm.group(1)] = fm.group(2)
            continue
        if raw.strip() == "specs:":
            in_specs = True
            continue
        if not in_specs:
            continue
        m = _GEMFILE_LOCK_SPEC.match(raw)
        if m:
            name = m.group(1).lower()
            r.add(name, m.group(2), lineno)
            if section in ("GIT", "PATH"):
                remote = fields.get("remote")
                if not remote:
                    raise ParseError("the %s section above line %d names no remote" % (section, lineno))
                if section == "PATH":
                    if remote not in (".", "./"):
                        r.replaces.append((name, remote, None, lineno))
                    continue
                ref = fields.get("revision") or fields.get("ref") or fields.get("tag") or fields.get("branch")
                r.replaces.append((name, remote, ref or m.group(2), lineno))
    return r


# ---------------------------------------------------------------------------
# Dispatch

_EXACT = {
    "package.json": ("npm", parse_package_json),
    "package-lock.json": ("npm", parse_package_lock),
    "yarn.lock": ("npm", parse_yarn_lock),
    "pnpm-lock.yaml": ("npm", parse_pnpm_lock),
    "pyproject.toml": ("python", parse_pyproject),
    "poetry.lock": ("python", parse_toml_lock),
    "go.mod": ("go", parse_go_mod),
    "go.sum": ("go", parse_go_sum),
    "Cargo.toml": ("rust", parse_cargo_toml),
    "Cargo.lock": ("rust", parse_toml_lock),
    "Gemfile": ("ruby", parse_gemfile),
    "Gemfile.lock": ("ruby", parse_gemfile_lock),
}

_REQUIREMENTS = re.compile(r"^requirements[A-Za-z0-9._-]*\.txt$")


def classify(path):
    """Return (ecosystem, parser) for a repo-relative path, or None.

    Matching is on the basename, so a manifest in a subdirectory counts. A
    path this does not know returns None and is not examined — different from
    a manifest it knows and cannot read.
    """
    base = os.path.basename(path)
    if base in _EXACT:
        return _EXACT[base]
    if _REQUIREMENTS.match(base):
        return ("python", parse_requirements)
    return None


def edit_distance(a, b, cap=2):
    """Levenshtein distance, saturating at cap + 1.

    Only "is this within the cap" is ever asked, so the exact value beyond it
    is not computed, and a length pre-check avoids walking a matrix that
    cannot come back under the cap.
    """
    if a == b:
        return 0
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1,
                               previous[j - 1] + (ca != cb)))
        if min(current) > cap:
            return cap + 1
        previous = current
    return previous[-1] if previous[-1] <= cap else cap + 1
