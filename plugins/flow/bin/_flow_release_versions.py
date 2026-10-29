"""Find the version files a release bumps, report the plan, and write it.

Usage (through bin/flow-release-versions.sh, from the repository root):
  flow-release-versions.sh (--plan | --write)
                           [--bump patch|minor|major | --to VERSION]
                           [--plugin NAME
                            [--market-bump patch|minor|major | --market-to V]]
                           [--root DIR]

Without --plugin, the files are the repository's own: package.json,
pyproject.toml ([project] version, else [tool.poetry] version), Cargo.toml
([package] version, else [workspace.package] version) and
.claude-plugin/plugin.json. With --plugin NAME, they are that plugin's
plugin.json (at the entry's "source" in .claude-plugin/marketplace.json,
plugins/NAME by default) and that plugin's entry in marketplace.json, which
must agree, and the marketplace's own metadata.version, which has its own
number and is bumped separately: by --market-bump, or by --market-to, or
when neither is given, by minor for a minor or major --bump and by patch for
a patch. The release tag carries the marketplace version.

Every file is reported on one line:
  VERSION_FILE=bump path=P [entry=NAME | field=metadata.version] current=X new=Y
  VERSION_FILE=skip path=P reason="..."
then CURRENT_VERSION and NEW_VERSION (the files that must agree),
MARKETPLACE_VERSION and NEW_MARKETPLACE_VERSION (with --plugin),
CURRENT_TAG_VERSION and TAG_VERSION (the marketplace version with --plugin,
otherwise the version), and VERSIONS_STATE:
  planned   --plan found files to bump (nothing written)
  written   --write bumped every file listed as bump
  none      no file to bump (exit 0)
  unchanged every file to bump already holds the new version; nothing is
            written (exit 0), so a release re-run after its bump commit
            does not bump twice
  mismatch  the files to bump disagree on the current version (exit 1)
  refused   a file cannot be bumped safely, or the new version cannot be
            worked out (exit 1); the reason is on a REFUSED= line
Nothing is written unless every file can be: each new text is built and
re-parsed first, and only a change to that one value passes. Exit 2 is a
usage error.
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
import re
import tempfile

try:
    import tomllib
except ImportError:  # python3 < 3.11; flow supports 3.12 and later
    tomllib = None

PLAIN = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$"
)
PLUGIN_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
SOURCE_PATH = re.compile(r"^(\./)?[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*/?$")

# Files that hold a version this script does not edit. Each is listed as
# skipped so the release summary shows what still needs a hand.
UNKNOWN = [
    ("setup.py", "setup.py is code; update its version by hand"),
    ("setup.cfg", "setup.cfg is not a recognised version file; update it by hand"),
    ("VERSION", "a plain VERSION file is not a recognised version file; update it by hand"),
    ("version.txt", "version.txt is not a recognised version file; update it by hand"),
    ("composer.json", "composer.json is not a recognised version file; update it by hand"),
    ("pom.xml", "pom.xml is not a recognised version file; update it by hand"),
    ("build.gradle", "build.gradle is not a recognised version file; update it by hand"),
    ("build.gradle.kts", "build.gradle.kts is not a recognised version file; update it by hand"),
    ("mix.exs", "mix.exs is not a recognised version file; update it by hand"),
    ("pubspec.yaml", "pubspec.yaml is not a recognised version file; update it by hand"),
    ("Chart.yaml", "Chart.yaml is not a recognised version file; update it by hand"),
    ("package-lock.json", "a lockfile; run npm install after the bump to refresh it"),
    ("npm-shrinkwrap.json", "a lockfile; run npm install after the bump to refresh it"),
    ("Cargo.lock", "a lockfile; run cargo update --workspace after the bump to refresh it"),
]


class Refused(Exception):
    pass


def usage(msg):
    sys.stderr.write("flow-release-versions: %s\n" % msg)
    sys.exit(2)


def quote(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


# --- JSON: find the exact span of one value, so the edit touches nothing else


_WS = re.compile(r"[ \t\n\r]*")


def json_span(text, path):
    """Return (start, end) of the string value at path (keys and list
    indexes), the last one when a key repeats, as json.loads would read it."""
    decoder = json.JSONDecoder()
    found = []

    def skip(i):
        return _WS.match(text, i).end()

    def value(i, rest):
        i = skip(i)
        c = text[i : i + 1]
        if c == "{":
            i = skip(i + 1)
            if text[i : i + 1] == "}":
                return i + 1
            while True:
                i = skip(i)
                if text[i : i + 1] != '"':
                    raise ValueError("expected a key at %d" % i)
                key, i = json.decoder.scanstring(text, i + 1)
                i = skip(i)
                if text[i : i + 1] != ":":
                    raise ValueError("expected ':' at %d" % i)
                sub = rest[1:] if rest and rest[0] == key else None
                i = value(i + 1, sub)
                i = skip(i)
                if text[i : i + 1] == ",":
                    i += 1
                    continue
                if text[i : i + 1] == "}":
                    return i + 1
                raise ValueError("expected ',' or '}' at %d" % i)
        if c == "[":
            i = skip(i + 1)
            if text[i : i + 1] == "]":
                return i + 1
            n = 0
            while True:
                sub = rest[1:] if rest and rest[0] == n else None
                i = value(i, sub)
                i = skip(i)
                n += 1
                if text[i : i + 1] == ",":
                    i += 1
                    continue
                if text[i : i + 1] == "]":
                    return i + 1
                raise ValueError("expected ',' or ']' at %d" % i)
        _, end = decoder.raw_decode(text, i)
        if rest == [] and c == '"':
            found.append((i, end))
        return end

    value(0, list(path))
    return found[-1] if found else None


def json_get(doc, path):
    for p in path:
        doc = doc[p]
    return doc


def json_edit(text, path, new):
    span = json_span(text, path)
    if span is None:
        raise Refused("the version value could not be found in the text")
    out = text[: span[0]] + json.dumps(new) + text[span[1] :]
    want = json.loads(text)
    target = want
    for p in path[:-1]:
        target = target[p]
    target[path[-1]] = new
    if json.loads(out) != want:
        raise Refused("editing the version would change more than the version")
    return out


# --- TOML: edit the one `version = "..."` line of a table


def toml_edit(text, table, old, new):
    lines = text.splitlines(keepends=True)
    header = re.compile(r"^\s*\[\s*" + re.escape(table) + r"\s*\]\s*(#.*)?$")
    any_header = re.compile(r"^\s*\[")
    line_re = re.compile(r"""^(\s*version\s*=\s*)(["'])([^"'\n]*)(\2)(.*)$""", re.S)
    inside = False
    hit = None
    for n, line in enumerate(lines):
        if header.match(line):
            inside = True
            continue
        if inside and any_header.match(line):
            break
        if inside:
            m = line_re.match(line)
            if m:
                if m.group(3) != old:
                    raise Refused("the [%s] version line does not hold %s" % (table, old))
                hit = (n, m)
                break
    if hit is None:
        raise Refused("no version line in the [%s] table to edit in place" % table)
    n, m = hit
    lines[n] = m.group(1) + m.group(2) + new + m.group(4) + m.group(5)
    out = "".join(lines)
    want = tomllib.loads(text)
    target = want
    for p in table.split("."):
        target = target[p]
    target["version"] = new
    if tomllib.loads(out) != want:
        raise Refused("editing the version would change more than the version")
    return out


# --- what each recognised file says


def inside(root, rel):
    """The file's path, refused when it or a directory on the way is a link
    that leads out of the repository, or the file itself is a link."""
    path = os.path.join(root, rel)
    if os.path.islink(path):
        raise Refused("%s is a symbolic link; it is not written through" % rel)
    top = os.path.realpath(root)
    real = os.path.realpath(path)
    if not real.startswith(top.rstrip(os.sep) + os.sep):
        raise Refused("%s resolves outside the repository; it is not written through" % rel)
    return path


def read_text(root, rel):
    path = inside(root, rel)
    with open(path, encoding="utf-8") as f:
        return f.read()


def json_file(root, rel, path, label):
    """A bump record, or a skip record with its reason."""
    text = read_text(root, rel)
    try:
        doc = json.loads(text)
        value = json_get(doc, path)
    except (ValueError, KeyError, IndexError, TypeError):
        return {"skip": True, "path": rel, "reason": "%s has no %s field" % (rel, label)}
    if not isinstance(value, str):
        return {"skip": True, "path": rel, "reason": "%s %s is not a string" % (rel, label)}
    return {"path": rel, "current": value, "kind": "json", "jpath": path, "text": text}


def pyproject(root):
    rel = "pyproject.toml"
    text = read_text(root, rel)
    doc = tomllib.loads(text)
    project = doc.get("project") or {}
    if "version" in (project.get("dynamic") or []):
        return {"skip": True, "path": rel,
                "reason": "the version is dynamic (set by the build backend); bump its source by hand"}
    if isinstance(project.get("version"), str):
        return {"path": rel, "current": project["version"], "kind": "toml", "table": "project", "text": text}
    poetry = (doc.get("tool") or {}).get("poetry") or {}
    if isinstance(poetry.get("version"), str):
        return {"path": rel, "current": poetry["version"], "kind": "toml", "table": "tool.poetry", "text": text}
    return {"skip": True, "path": rel, "reason": "no [project] or [tool.poetry] version"}


def cargo(root):
    rel = "Cargo.toml"
    text = read_text(root, rel)
    doc = tomllib.loads(text)
    package = doc.get("package") or {}
    v = package.get("version")
    if isinstance(v, dict) and v.get("workspace") is True:
        return {"skip": True, "path": rel,
                "reason": "the package inherits its version from the workspace; bump [workspace.package] there"}
    if isinstance(v, str):
        return {"path": rel, "current": v, "kind": "toml", "table": "package", "text": text}
    wp = (doc.get("workspace") or {}).get("package") or {}
    if isinstance(wp.get("version"), str):
        return {"path": rel, "current": wp["version"], "kind": "toml", "table": "workspace.package", "text": text}
    return {"skip": True, "path": rel, "reason": "no [package] or [workspace.package] version"}


def exists(root, rel):
    return os.path.lexists(os.path.join(root, rel))


def root_files(root):
    out = []
    if exists(root, "package.json"):
        out.append(json_file(root, "package.json", ["version"], "top-level version"))
    if exists(root, "pyproject.toml"):
        out.append(pyproject(root))
    if exists(root, "Cargo.toml"):
        out.append(cargo(root))
    if exists(root, ".claude-plugin/plugin.json"):
        out.append(json_file(root, ".claude-plugin/plugin.json", ["version"], "version"))
    if exists(root, ".claude-plugin/marketplace.json"):
        out.append({"skip": True, "path": ".claude-plugin/marketplace.json",
                    "reason": "a marketplace: name a plugin to bump that plugin and its entry"})
    for rel, reason in UNKNOWN:
        if exists(root, rel):
            out.append({"skip": True, "path": rel, "reason": reason})
    return out


def plugin_files(root, name):
    mrel = ".claude-plugin/marketplace.json"
    if not exists(root, mrel):
        raise Refused("no %s: --plugin needs a marketplace" % mrel)
    mtext = read_text(root, mrel)
    try:
        market = json.loads(mtext)
        entries = market["plugins"]
    except (ValueError, KeyError, TypeError):
        raise Refused("%s has no plugins list" % mrel)
    idx = [i for i, e in enumerate(entries) if isinstance(e, dict) and e.get("name") == name]
    if not idx:
        raise Refused("%s has no entry named %s" % (mrel, name))
    if len(idx) > 1:
        raise Refused("%s has %d entries named %s" % (mrel, len(idx), name))
    i = idx[0]
    entry = entries[i]
    source = entry.get("source")
    pdir = "plugins/%s" % name
    if isinstance(source, str):
        if not SOURCE_PATH.match(source) or ".." in source.split("/"):
            raise Refused("the %s entry's source %s is not a path inside the repository" % (name, source))
        pdir = source[2:] if source.startswith("./") else source
        pdir = pdir.rstrip("/")
    prel = "%s/.claude-plugin/plugin.json" % pdir
    out = []
    if exists(root, prel):
        out.append(json_file(root, prel, ["version"], "version"))
    else:
        raise Refused("no %s for plugin %s" % (prel, name))
    rec = json_file(root, mrel, ["plugins", i, "version"], "version in its %s entry" % name)
    rec["entry"] = name
    out.append(rec)
    meta = market.get("metadata") if isinstance(market, dict) else None
    if isinstance(meta, dict) and isinstance(meta.get("version"), str):
        out.append({"path": mrel, "field": "metadata.version", "group": "market",
                    "current": meta["version"], "kind": "json",
                    "jpath": ["metadata", "version"], "text": mtext})
    else:
        out.append({"skip": True, "path": mrel,
                    "reason": "the marketplace has no metadata.version; the tag carries the plugin's version"})
    return out


def bumped(current, kind):
    m = PLAIN.match(current)
    if not m:
        raise Refused("the current version %s is not MAJOR.MINOR.PATCH; pass --to with the version to release" % current)
    a, b, c = (int(x) for x in m.groups())
    if kind == "major":
        return "%d.0.0" % (a + 1)
    if kind == "minor":
        return "%d.%d.0" % (a, b + 1)
    return "%d.%d.%d" % (a, b, c + 1)


def write_atomic(root, rel, text):
    path = inside(root, rel)
    mode = os.stat(path).st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".flow-version.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv):
    mode = bump = to = plugin = market_bump = market_to = None
    root = "."
    it = iter(argv)
    for a in it:
        if a in ("--plan", "--write"):
            if mode:
                usage("give one of --plan and --write")
            mode = a[2:]
        elif a in ("--bump", "--to", "--plugin", "--root", "--market-bump", "--market-to"):
            v = next(it, None)
            if v is None:
                usage("%s needs a value" % a)
            if a == "--bump":
                bump = v
            elif a == "--to":
                to = v
            elif a == "--plugin":
                plugin = v
            elif a == "--market-bump":
                market_bump = v
            elif a == "--market-to":
                market_to = v
            else:
                root = v
        else:
            usage("unknown argument %s" % a)
    if not mode:
        usage("give --plan or --write")
    if bump and to:
        usage("give --bump or --to, not both")
    if market_bump and market_to:
        usage("give --market-bump or --market-to, not both")
    for kind in (bump, market_bump):
        if kind and kind not in ("patch", "minor", "major"):
            usage("--bump and --market-bump take patch, minor or major")
    for v in (to, market_to):
        if v and not SEMVER.match(v):
            usage("--to and --market-to take a version such as 1.4.0")
    if (market_bump or market_to) and plugin is None:
        usage("--market-bump and --market-to need --plugin")
    if mode == "write" and not (bump or to):
        usage("--write needs --bump or --to")
    if plugin is not None and not PLUGIN_NAME.match(plugin):
        usage("--plugin takes a plugin name such as flow")
    if tomllib is None:
        sys.stderr.write("flow-release-versions: python3 3.11 or later is needed to read TOML\n")
        sys.exit(3)

    info = {"current": "none", "new": "", "mcurrent": "", "mnew": ""}

    def finish(state, refused=None, code=0):
        print("CURRENT_VERSION=%s" % info["current"])
        if info["new"]:
            print("NEW_VERSION=%s" % info["new"])
        if info["mcurrent"]:
            print("MARKETPLACE_VERSION=%s" % info["mcurrent"])
            if info["mnew"]:
                print("NEW_MARKETPLACE_VERSION=%s" % info["mnew"])
        print("CURRENT_TAG_VERSION=%s" % (info["mcurrent"] or info["current"]))
        tag = info["mnew"] if info["mcurrent"] else info["new"]
        if tag:
            print("TAG_VERSION=%s" % tag)
        if refused:
            print("REFUSED=%s" % quote(refused))
        print("VERSIONS_STATE=%s" % state)
        sys.exit(code)

    try:
        records = plugin_files(root, plugin) if plugin else root_files(root)
    except Refused as e:
        finish("refused", refused=str(e), code=1)
    except (OSError, UnicodeDecodeError, ValueError) as e:
        finish("refused", refused="a version file cannot be read: %s" % e, code=1)

    bumps = [r for r in records if not r.get("skip") and r.get("group") != "market"]
    markets = [r for r in records if not r.get("skip") and r.get("group") == "market"]
    market = markets[0] if markets else None
    currents = sorted({r["current"] for r in bumps})
    if len(currents) > 1:
        for r in bumps:
            entry = " entry=%s" % r["entry"] if r.get("entry") else ""
            print("VERSION_FILE=disagrees path=%s%s current=%s" % (r["path"], entry, r["current"]))
        finish("mismatch",
               refused="the files to bump disagree (%s); make them agree first" % ", ".join(currents), code=1)
    current = currents[0] if currents else "none"
    info["current"] = current
    if market:
        info["mcurrent"] = market["current"]

    new = to or ""
    mnew = market_to or ""
    error = None
    if bumps and bump:
        try:
            new = bumped(current, bump)
        except Refused as e:
            error = str(e)
    if market and not mnew and not error:
        kind = market_bump or ({"patch": "patch"}.get(bump, "minor") if bump else None)
        if kind:
            try:
                mnew = bumped(market["current"], kind)
            except Refused as e:
                error = "metadata.version: %s" % e
        elif mode == "write":
            error = "the marketplace version needs --market-to or --market-bump alongside --to"
    info["new"] = new
    info["mnew"] = mnew

    # Build every new text before writing any of them.
    texts = {}
    if bumps and not error:
        for r in bumps + markets:
            probe = (mnew or r["current"]) if r.get("group") == "market" else (new or current)
            try:
                base = texts.get(r["path"], r["text"])
                if r["kind"] == "json":
                    texts[r["path"]] = json_edit(base, r["jpath"], probe)
                else:
                    texts[r["path"]] = toml_edit(base, r["table"], r["current"], probe)
            except Refused as e:
                error = "%s: %s" % (r["path"], e)
                break
            except (ValueError, KeyError, TypeError) as e:
                error = "%s: cannot be edited in place (%s)" % (r["path"], e)
                break

    for r in records:
        if r.get("skip"):
            print("VERSION_FILE=skip path=%s reason=%s" % (r["path"], quote(r["reason"])))
        else:
            if r.get("group") == "market":
                label, value = " field=%s" % r["field"], mnew
            else:
                label, value = (" entry=%s" % r["entry"] if r.get("entry") else ""), new
            tail = " new=%s" % value if value else ""
            print("VERSION_FILE=bump path=%s%s current=%s%s" % (r["path"], label, r["current"], tail))

    if error:
        finish("refused", refused=error, code=1)
    if not bumps:
        finish("none")
    if new == current and (market is None or mnew == market["current"]):
        finish("unchanged")
    if mode == "plan":
        finish("planned")
    try:
        for path, text in texts.items():
            write_atomic(root, path, text)
    except (OSError, Refused) as e:
        finish("refused", refused="writing failed: %s" % e, code=1)
    finish("written")


if __name__ == "__main__":
    main(sys.argv[1:])
