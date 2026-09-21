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

import json
import os
import re

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


_DIRECT_REF_SCHEMES = ("http://", "https://", "file://", "git+", "ssh://", "hg+", "svn+", "bzr+")


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
        if right.lower().startswith(_DIRECT_REF_SCHEMES):
            return left.strip(), right
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
                # Either group -> [items] or name -> constraint.
                # Groups only when every value is a list OF STRINGS. A list
                # of tables is poetry's multiple-constraints form — a dev
                # group commonly uses it — and reading that as a group made
                # every dependency in the table vanish while the run still
                # reported ok.
                if value and all(
                        isinstance(v, list) and all(isinstance(x, str) for x in v)
                        for v in value.values()):
                    for group in value.values():
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
                    result.add(low_name, _version_of(spec),
                               None)
                    src = _source_of(spec)
                    if src:
                        result.replaces.append(
                            (low_name, src, None, None)
                        )
                continue

        if isinstance(value, dict):
            _harvest_dependencies(value, result, text, here)


def parse_toml_manifest(text):
    """pyproject.toml and Cargo.toml — every dependency table either declares."""
    data = _load_toml(text)
    r = ParseResult()
    _harvest_dependencies(data, r, text)
    for name, src in r.pending_sources:
        if name in r.deps:
            r.replaces.append((name, src, None, None))
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


def parse_requirements(text):
    r = ParseResult()
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("-"):
            continue
        # A VCS or URL requirement would otherwise match the name pattern as
        # the package "git" or "https". The real name lives in an optional
        # fragment, so this reports nothing rather than inventing one.
        if _URL_REQ.match(line):
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
                    _, _, rhs = spec.partition("@")
                    rhs = rhs.strip().strip('"')
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

_GEM_LINE = re.compile(r"^\s*gem\s+(.+)$")
_GEM_LITERAL = re.compile(r"^['\"]([^'\"]+)['\"]\s*(?:,\s*['\"]([^'\"]+)['\"])?")


def parse_gemfile(text):
    """A Gemfile is Ruby, not a data format.

    A `gem` line whose name is a literal is read. One whose name is a
    variable, a method call or an interpolation is NOT guessed at: the file is
    reported unreadable, because a dependency this cannot see is one a
    reviewer would be told does not exist.
    """
    r = ParseResult()
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip()
        m = _GEM_LINE.match(line)
        if not m:
            continue
        lm = _GEM_LITERAL.match(m.group(1).strip())
        if not lm:
            raise ParseError("gem name on line %d is not a string literal" % lineno)
        r.add(lm.group(1).lower(), lm.group(2), lineno)
    return r


# Exactly four spaces. Under `specs:` a resolved gem is indented four and its
# own requirements six; matching 4-6 reads `activesupport (= 7.0.0)` as a
# top-level gem.
_GEMFILE_LOCK_SPEC = re.compile(
    r"^ {4}(?! )([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\(([^)]*)\))?\s*$"
)


def parse_gemfile_lock(text):
    r = ParseResult()
    in_specs = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        if not raw[0].isspace():
            in_specs = False
            continue
        if raw.strip() == "specs:":
            in_specs = True
            continue
        if not in_specs:
            continue
        m = _GEMFILE_LOCK_SPEC.match(raw)
        if m:
            r.add(m.group(1).lower(), m.group(2), lineno)
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
