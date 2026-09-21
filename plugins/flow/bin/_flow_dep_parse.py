"""Manifest and lockfile parsing for bin/flow-dep-diff.sh.

Every parser here is line-oriented and offline. Two constraints force that
shape, and neither is negotiable:

  - The output contract is `manifest=<path>:<line>`, and a JSON, YAML or TOML
    parser returns values without the line they came from. Parsing for values
    and then hunting for the line is how a location drifts one row off the
    thing it names.
  - Avoiding tomllib also removes a Python floor. The plugin pins no Python
    version, and `tomllib` is 3.11+.

Every parser returns a ParseResult. A parser that cannot read its input says
so — it never returns an empty dependency list, because "this file declares
nothing" and "I could not read this file" are different answers and the whole
point of this helper is that the caller can tell them apart.

Names and versions come from a manifest inside the pull request under review,
so they are author-controlled. `safe_scalar` refuses anything carrying a
control character or a newline before it can reach the output, where it would
otherwise forge extra records.
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
# Python

_REQ_LINE = re.compile(
    r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*"
    r"(?:(==|>=|<=|~=|!=|>|<)\s*([^;#\s]+))?"
)

_URL_REQ = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*(\+[A-Za-z][A-Za-z0-9+.-]*)?://")


def parse_requirements(text):
    r = ParseResult()
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        # -r / -e / --flag lines point elsewhere; they declare no version here.
        if line.startswith("-"):
            continue
        # A VCS or URL requirement (`git+https://...#egg=foo`, a bare wheel
        # URL) would otherwise match the name pattern as the package `git` or
        # `https`. The real name lives in an optional fragment, so this
        # reports nothing rather than inventing one.
        if _URL_REQ.match(line):
            continue
        m = _REQ_LINE.match(line)
        if not m:
            continue
        r.add(m.group(1).lower(),
              _normalise_constraint((m.group(2) or '') + (m.group(3) or '')),
              lineno)
    return r


def _strip_toml_comment(line):
    """Remove a `#` comment, ignoring one inside a string literal."""
    out = []
    quote = None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out)


def _bracket_delta(line):
    """Net `[`/`{` nesting change, counting only outside string literals.

    Counting inside strings is what made a PEP 508 extras marker close an
    array: `"requests[security]>=2.31.0"` carries a `]` that belongs to the
    dependency's own text, not to the array holding it.
    """
    depth = 0
    quote = None
    for ch in line:
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
    return depth


def _toml_statements(text):
    """Yield (lineno, statement) with multi-line values joined into one.

    A value may legally span lines — a Cargo `features = [` list, a poetry
    multiple-constraints array — and reading those lines individually makes
    each continuation look like a malformed key. Treating that as unreadable
    turned valid, common manifests into a blocking `unavailable` on every
    pull request.
    """
    buf = []
    start = None
    depth = 0
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = _strip_toml_comment(raw)
        if not line.strip() and depth <= 0:
            continue
        if start is None:
            start = lineno
        buf.append(line)
        depth += _bracket_delta(line)
        if depth <= 0:
            yield start, "\n".join(buf)
            buf = []
            start = None
            depth = 0
    if buf:
        yield start, "\n".join(buf)


# Both quote styles. A single-quoted TOML item is as ordinary as a
# double-quoted one, and scanning only for `"` dropped it silently.
_TOML_ITEM = re.compile(r'"([^"]*)"|\'([^\']*)\'')


def _toml_items(payload):
    for m in _TOML_ITEM.finditer(payload):
        yield m.group(1) if m.group(1) is not None else m.group(2)


_TOML_SECTION = re.compile(r"^\s*\[+([^\]]+)\]+\s*$")
# DOTALL: a statement handed here may span lines — the scanner joins a
# multi-line value into one — and without it the value simply does not match,
# which the caller then reads as a malformed key.
_TOML_KEY = re.compile(
    r'^\s*((?:"[^"]+"|\'[^\']+\'|[A-Za-z0-9][A-Za-z0-9._-]*))\s*=\s*(.+?)\s*$',
    re.DOTALL,
)
_TOML_STR = re.compile(r'^"([^"]*)"$|^\'([^\']*)\'$')
_INLINE_VERSION = re.compile(r'version\s*=\s*"([^"]*)"')
# The comparison operator is part of the constraint, not decoration: storing
# only the number makes `requests==2.31.0` and `requests>=2.31.0` identical,
# so loosening a pin — a standard supply-chain move — produces no change.
_PEP508 = re.compile(
    r'^\s*"?([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*'
    r'((?:[=<>!~]=?\s*[^",;\]]+)?)'
)

# Keys that appear INSIDE a dependency sub-table and are attributes of the
# dependency, not dependency names themselves.
_DEP_ATTRS = frozenset((
    "version", "features", "path", "git", "branch", "tag", "rev", "optional",
    "default-features", "default_features", "workspace", "package", "registry",
    "extras", "python", "markers", "source", "url", "subdirectory", "allow-prereleases",
))


def _toml_scalar(raw):
    m = _TOML_STR.match(raw)
    if m:
        return m.group(1) if m.group(1) is not None else m.group(2)
    m = _INLINE_VERSION.search(raw)
    if m:
        return m.group(1)
    return None


def _unquote_key(key):
    m = _TOML_STR.match(key)
    if m:
        return m.group(1) if m.group(1) is not None else m.group(2)
    return key


def _dep_subtable_name(section):
    """If `section` is a dependency SUB-table, return the package it names.

    `[dependencies.serde]`, `[tool.poetry.dependencies.requests]` and
    `[target.'cfg(unix)'.dependencies.nix]` each declare one package in a table
    of their own. Read as an ordinary section, their `version = "..."` and
    `features = [...]` keys look like two packages called version and features,
    and the package itself is never reported at all.
    """
    parts = section.split(".")
    for i in range(len(parts) - 1, 0, -1):
        if parts[i - 1].endswith("dependencies"):
            name = ".".join(parts[i:])
            return _unquote_key(name) if name else None
    return None


def _is_dep_section(section):
    last = section.split(".")[-1]
    return last.endswith("dependencies")


# Sections whose KEYS are group names and whose VALUES are arrays of PEP 508
# strings. All of these are ways a Python project declares dependencies; a
# typosquat added to any of them is a dependency this must report.
_GROUPED_PEP508_SECTIONS = (
    "project.optional-dependencies",   # PEP 621 extras
    "dependency-groups",               # PEP 735
    "tool.pdm.dev-dependencies",
)
# Sections with NAMED array keys rather than arbitrary group names.
_NAMED_PEP508_KEYS = {
    "project": ("dependencies",),
    "tool.uv": ("dev-dependencies", "constraint-dependencies",
                "override-dependencies"),
}
_HATCH_KEYS = ("dependencies", "extra-dependencies")


def _add_pep508_items(result, payload, lineno):
    found = False
    for item in _toml_items(payload):
        if not item or item.startswith("include-group"):
            continue
        m = _PEP508.match(item)
        if m:
            result.add(m.group(1).lower(), _normalise_constraint(m.group(2)), lineno)
            found = True
    return found


def _normalise_constraint(raw):
    """Keep the comparison operator, except on an exact pin.

    `requests==2.31.0` becoming `requests>=2.31.0` is a real dependency change
    — loosening a pin is a standard supply-chain move — and storing only the
    number made the two identical, so no DEP_CHANGED was emitted. An exact pin
    keeps its bare version so the ordinary case still reads as a version.
    """
    if raw is None:
        return None
    raw = raw.strip()
    if raw.startswith("=="):
        return raw[2:].strip() or None
    return raw or None


def parse_pyproject(text):
    """Every way a pyproject.toml declares a dependency.

    PEP 621 `[project] dependencies` and its extras (both the section form and
    the inline-table form), PEP 735 `[dependency-groups]`, poetry, pdm, uv and
    hatch. A section this recognises as a dependency section but cannot read
    raises, rather than being skipped: skipping it reports the manifest as
    read with a package missing from it, which is the one outcome this helper
    exists to prevent.
    """
    r = ParseResult()
    section = None
    for lineno, stmt in _toml_statements(text):
        m = _TOML_SECTION.match(stmt.strip()) if "\n" not in stmt else None
        if m:
            section = m.group(1).strip()
            sub = _dep_subtable_name(section)
            if sub:
                r.add(sub.lower(), None, lineno)
            continue
        if section is None:
            continue

        sub = _dep_subtable_name(section)
        if sub:
            km = _TOML_KEY.match(stmt)
            if km and _unquote_key(km.group(1)).lower() == "version":
                name = sub.lower()
                r.deps.get(name, {}).pop(None, None)
                r.add(name, _toml_scalar(km.group(2)), lineno)
            continue

        km = _TOML_KEY.match(stmt)

        if section in _GROUPED_PEP508_SECTIONS:
            if km:
                _add_pep508_items(r, km.group(2), lineno)
            continue

        if section.startswith("tool.hatch.envs.") or section == "tool.hatch.envs":
            if km and _unquote_key(km.group(1)).lower() in _HATCH_KEYS:
                _add_pep508_items(r, km.group(2), lineno)
            continue

        named = _NAMED_PEP508_KEYS.get(section)
        if named:
            if km:
                key = _unquote_key(km.group(1)).lower()
                if key in named:
                    _add_pep508_items(r, km.group(2), lineno)
                elif key == "optional-dependencies":
                    # The inline-table form: optional-dependencies = {dev = [...]}
                    _add_pep508_items(r, km.group(2), lineno)
            continue

        if _is_dep_section(section) and section.startswith("tool.poetry"):
            if not km:
                raise ParseError(
                    "unreadable statement at line %d in [%s]" % (lineno, section)
                )
            key = _unquote_key(km.group(1)).lower()
            if key == "python":
                continue
            value = km.group(2)
            if value.lstrip().startswith("["):
                # Multiple constraints: foo = [{version = "<=1.9", ...}, ...].
                versions = re.findall(r'version\s*=\s*"([^"]*)"', value)
                if versions:
                    for v in versions:
                        r.add(key, v, lineno)
                else:
                    r.add(key, None, lineno)
                continue
            r.add(key, _toml_scalar(value), lineno)
            continue

        if _is_dep_section(section):
            # Recognised as a dependency section but not one of the shapes
            # above. Reporting the manifest read would hide whatever it holds.
            raise ParseError(
                "unrecognised dependency section [%s] at line %d" % (section, lineno)
            )
    return r


def parse_toml_lock(text):
    """poetry.lock and Cargo.lock: [[package]] blocks with name and version."""
    r = ParseResult()
    name = version = name_line = None
    in_pkg = False

    def flush():
        if in_pkg and name:
            r.add(name.lower(), version, name_line)

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip()
        m = _TOML_SECTION.match(line)
        if m:
            flush()
            in_pkg = m.group(1).strip() == "package"
            name = version = name_line = None
            continue
        if not in_pkg:
            continue
        km = _TOML_KEY.match(line)
        if not km:
            continue
        key = _unquote_key(km.group(1)).lower()
        if key == "name":
            name = _toml_scalar(km.group(2))
            name_line = lineno
        elif key == "version" and version is None:
            version = _toml_scalar(km.group(2))
    flush()
    return r


def parse_cargo_toml(text):
    r = ParseResult()
    section = None
    subtable = None
    for lineno, stmt in _toml_statements(text):
        m = _TOML_SECTION.match(stmt.strip()) if "\n" not in stmt else None
        if m:
            section = m.group(1).strip()
            subtable = _dep_subtable_name(section)
            if subtable:
                r.add(subtable.lower(), None, lineno)
            continue
        if not section:
            continue
        if subtable:
            km = _TOML_KEY.match(stmt)
            if km and _unquote_key(km.group(1)).lower() == "version":
                name = subtable.lower()
                r.deps.get(name, {}).pop(None, None)
                r.add(name, _toml_scalar(km.group(2)), lineno)
            continue
        if not _is_dep_section(section):
            continue
        km = _TOML_KEY.match(stmt)
        if not km:
            raise ParseError(
                "unreadable statement at line %d in [%s]" % (lineno, section)
            )
        key = _unquote_key(km.group(1))
        # Workspace inheritance is written `serde.workspace = true`. Keyed
        # whole, the package reads as `serde.workspace`, matching nothing in
        # the baseline and reported as a package nobody has heard of.
        if "." in key:
            headk, _, tail = key.rpartition(".")
            if tail.lower() in _DEP_ATTRS:
                if tail.lower() == "version":
                    r.deps.get(headk.lower(), {}).pop(None, None)
                    r.add(headk.lower(), _toml_scalar(km.group(2)), lineno)
                elif not r.deps.get(headk.lower()):
                    r.add(headk.lower(), None, lineno)
                continue
        r.add(key.lower(), _toml_scalar(km.group(2)), lineno)
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
                m = _YARN_HEADER.match(spec.strip() + ":")
                if m:
                    pending.append(m.group(1))
            continue
        m = _YARN_VERSION.match(raw)
        if m and pending:
            for name in pending:
                r.add(name, m.group(1), pending_line)
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
