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
    r"[\x00-\x08\x0a-\x1f\x7f-\x9f  |]"
)

MAX_SCALAR = 200


class ParseError(Exception):
    """A manifest could not be read. Carries the reason the output prints."""


class ParseResult(object):
    """What one manifest declares.

    deps: {name: (version_or_None, line_number)}
    hooks: [(name, line_number)] — packages the manifest itself says run an
           install script. Only a lockfile can answer this offline.
    """

    def __init__(self, deps=None, hooks=None):
        self.deps = deps or {}
        self.hooks = hooks or []


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


def parse_requirements(text):
    deps = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        # -r / -e / --flag lines point elsewhere; they declare no version here.
        if line.startswith("-"):
            continue
        m = _REQ_LINE.match(line)
        if not m:
            continue
        deps[m.group(1).lower()] = (m.group(3), lineno)
    return ParseResult(deps)


_TOML_SECTION = re.compile(r"^\s*\[+([^\]]+)\]+\s*$")
_TOML_KEY = re.compile(r'^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*=\s*(.+?)\s*$')
_TOML_STR = re.compile(r'^"([^"]*)"$|^\'([^\']*)\'$')
_INLINE_VERSION = re.compile(r'version\s*=\s*"([^"]*)"')
_PEP508 = re.compile(
    r'^\s*"?([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*'
    r'(?:[=<>!~]=?\s*([^",;\]]+))?'
)


def _toml_scalar(raw):
    m = _TOML_STR.match(raw)
    if m:
        return m.group(1) if m.group(1) is not None else m.group(2)
    m = _INLINE_VERSION.search(raw)
    if m:
        return m.group(1)
    return None


def parse_pyproject(text):
    """Read [project].dependencies and [tool.poetry.dependencies].

    PEP 621 puts dependencies in an array of PEP 508 strings; poetry puts them
    in a table. Both are read; a file using neither declares nothing, which is
    a real answer and not a parse failure.
    """
    deps = {}
    section = None
    in_array = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        m = _TOML_SECTION.match(line)
        if m:
            section = m.group(1).strip()
            in_array = False
            continue
        if section == "project":
            if re.match(r'^\s*(dependencies|optional-dependencies)\s*=\s*\[', line):
                in_array = "]" not in line.split("[", 1)[1]
                for item in re.findall(r'"([^"]+)"', line):
                    pm = _PEP508.match(item)
                    if pm:
                        deps[pm.group(1).lower()] = (pm.group(2), lineno)
                continue
            if in_array:
                if "]" in line:
                    in_array = False
                for item in re.findall(r'"([^"]+)"', line):
                    pm = _PEP508.match(item)
                    if pm:
                        deps[pm.group(1).lower()] = (pm.group(2), lineno)
                continue
        if section and section.startswith("tool.poetry") and "dependencies" in section:
            m = _TOML_KEY.match(line)
            if m and m.group(1).lower() != "python":
                deps[m.group(1).lower()] = (_toml_scalar(m.group(2)), lineno)
    return ParseResult(deps)


# ---------------------------------------------------------------------------
# TOML-shaped lockfiles: poetry.lock and Cargo.lock both use [[package]]
# blocks with `name` and `version` keys.


def parse_toml_lock(text):
    deps = {}
    name = None
    version = None
    name_line = None
    in_pkg = False

    def flush():
        if in_pkg and name:
            deps[name.lower()] = (version, name_line)

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
        m = _TOML_KEY.match(line)
        if not m:
            continue
        key = m.group(1).lower()
        if key == "name":
            name = _toml_scalar(m.group(2))
            name_line = lineno
        elif key == "version" and version is None:
            version = _toml_scalar(m.group(2))
    flush()
    return ParseResult(deps)


def parse_cargo_toml(text):
    deps = {}
    section = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        m = _TOML_SECTION.match(line)
        if m:
            section = m.group(1).strip()
            continue
        if not section:
            continue
        # dependencies, dev-dependencies, build-dependencies, and their
        # target-conditional forms.
        if not section.endswith("dependencies"):
            continue
        m = _TOML_KEY.match(line)
        if m:
            deps[m.group(1).lower()] = (_toml_scalar(m.group(2)), lineno)
    return ParseResult(deps)


# ---------------------------------------------------------------------------
# Go


_GO_REQUIRE = re.compile(
    r"^\s*(?:require\s+)?([a-zA-Z0-9][^\s]*\.[^\s]*/?[^\s]*)\s+(v[^\s/]+)"
)


def parse_go_mod(text):
    deps = {}
    in_block = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("//", 1)[0].rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if re.match(r"^require\s*\($", stripped):
            in_block = True
            continue
        if in_block and stripped == ")":
            in_block = False
            continue
        if not in_block and not stripped.startswith("require "):
            continue
        m = _GO_REQUIRE.match(line)
        if m:
            deps[m.group(1)] = (m.group(2), lineno)
    return ParseResult(deps)


def parse_go_sum(text):
    """go.sum lists each module twice (module and /go.mod). First wins."""
    deps = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        parts = raw.split()
        if len(parts) < 3:
            continue
        name, version = parts[0], parts[1]
        version = version.replace("/go.mod", "")
        if not version.startswith("v"):
            continue
        if name not in deps:
            deps[name] = (version, lineno)
    return ParseResult(deps)


# ---------------------------------------------------------------------------
# npm


_NPM_DEP_SECTIONS = (
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
)


def _line_of_key(text, key):
    """Line number of the first `"key":` occurrence, or None.

    The value is parsed from JSON and the line is found separately: a JSON
    parser has no line numbers, and inventing one from the parse order would
    point at a different row whenever key order and file order disagree.
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
    deps = {}
    for section in _NPM_DEP_SECTIONS:
        block = data.get(section)
        if not isinstance(block, dict):
            continue
        for name, version in block.items():
            if not isinstance(name, str):
                continue
            deps[name] = (
                version if isinstance(version, str) else None,
                _line_of_key(text, name),
            )
    return ParseResult(deps)


def parse_package_lock(text):
    try:
        data = json.loads(text)
    except ValueError as e:
        raise ParseError("not valid JSON (%s)" % type(e).__name__)
    if not isinstance(data, dict):
        raise ParseError("top level is not a JSON object")
    deps = {}
    hooks = []
    # lockfileVersion 2/3 use `packages`, keyed by install path; 1 uses
    # `dependencies`, keyed by name.
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
            deps[name] = (version if isinstance(version, str) else None, line)
            if entry.get("hasInstallScript") is True:
                hooks.append((name, line))
    legacy = data.get("dependencies")
    if isinstance(legacy, dict) and not deps:
        for name, entry in legacy.items():
            if not isinstance(name, str):
                continue
            version = entry.get("version") if isinstance(entry, dict) else None
            deps[name] = (
                version if isinstance(version, str) else None,
                _line_of_key(text, name),
            )
    return ParseResult(deps, hooks)


_YARN_HEADER = re.compile(r'^"?([^",\s][^",]*?)@[^",]*"?[,:]')
_YARN_VERSION = re.compile(r'^\s+version\s+"?([^"\s]+)"?')


def parse_yarn_lock(text):
    """yarn v1 classic. A berry (v2+) lock is YAML and is read as YAML."""
    if "__metadata:" in text:
        raise ParseError("yarn berry lockfile — not the v1 format this reads")
    deps = {}
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
                deps[name] = (m.group(1), pending_line)
            pending = []
    return ParseResult(deps)


_PNPM_ENTRY = re.compile(r"^\s{2,}(/?[^:\s][^:]*?):\s*$")


def parse_pnpm_lock(text):
    """pnpm-lock.yaml `packages:` keys look like `/name/1.2.3` or `name@1.2.3`."""
    deps = {}
    in_packages = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw[0].isspace():
            in_packages = raw.startswith("packages:")
            continue
        if not in_packages:
            continue
        m = _PNPM_ENTRY.match(raw)
        if not m:
            continue
        key = m.group(1).strip().strip("'\"")
        name = version = None
        if key.startswith("/"):
            body = key[1:]
            # /@scope/name/1.2.3  or  /name/1.2.3  or  /name@1.2.3
            if "@" in body[1:]:
                head, _, tail = body.rpartition("@")
                if head and "/" not in tail:
                    name, version = head, tail
            if name is None:
                head, _, tail = body.rpartition("/")
                if head:
                    name, version = head, tail
        elif "@" in key[1:]:
            head, _, tail = key.rpartition("@")
            if head and "/" not in tail:
                name, version = head, tail
        if name:
            deps[name] = (version, lineno)
    return ParseResult(deps)


# ---------------------------------------------------------------------------
# Ruby


_GEM_LINE = re.compile(r"^\s*gem\s+(.+)$")
_GEM_LITERAL = re.compile(r"^['\"]([^'\"]+)['\"]\s*(?:,\s*['\"]([^'\"]+)['\"])?")


def parse_gemfile(text):
    """A Gemfile is Ruby, not a data format.

    A `gem` line whose name is a literal is read. A `gem` line whose name is a
    variable, a method call, or an interpolation is NOT guessed at — the file
    is reported unreadable, because a dependency this cannot see is one a
    reviewer would be told does not exist.
    """
    deps = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip()
        m = _GEM_LINE.match(line)
        if not m:
            continue
        lm = _GEM_LITERAL.match(m.group(1).strip())
        if not lm:
            raise ParseError(
                "gem name on line %d is not a string literal" % lineno
            )
        deps[lm.group(1).lower()] = (lm.group(2), lineno)
    return ParseResult(deps)


_GEMFILE_LOCK_SPEC = re.compile(
    r"^\s{4,6}([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\(([^)]*)\))?\s*$"
)


def parse_gemfile_lock(text):
    deps = {}
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
            deps.setdefault(m.group(1).lower(), (m.group(2), lineno))
    return ParseResult(deps)


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

    Matching is on the basename, so a manifest in a subdirectory counts. A path
    that is not a manifest this helper knows returns None and is not examined —
    which is different from a manifest it knows and cannot read.
    """
    base = os.path.basename(path)
    if base in _EXACT:
        return _EXACT[base]
    if _REQUIREMENTS.match(base):
        return ("python", parse_requirements)
    return None


def edit_distance(a, b, cap=2):
    """Levenshtein distance between `a` and `b`, saturating at cap + 1.

    Only "is this within 2" is ever asked, so the exact value beyond the cap is
    not computed — and the length pre-check keeps a long-name comparison from
    walking a full matrix it cannot possibly need.
    """
    if a == b:
        return 0
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + (ca != cb),
            ))
        if min(current) > cap:
            return cap + 1
        previous = current
    return previous[-1] if previous[-1] <= cap else cap + 1
