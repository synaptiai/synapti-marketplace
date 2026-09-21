#!/usr/bin/env bash
# [flow] Print the dependency changes between two commits, from the manifests.
#
# Answers one question for `agents/security-reviewer.md`: which packages does
# this change add, bump or drop, and where is each one declared. Deterministic
# and offline — it reads the diff and the two commits through `git` and makes
# no network call, so the same range always prints the same thing.
#
# The baseline is read at the BASE commit on purpose. The near-name check needs
# to know what the project already depends on, and reading that from the head
# would let a pull request introduce both a typosquat and the name it mimics,
# then compare one against the other. The base is what the change merges into.
#
# Usage:
#   flow-dep-diff.sh --base <ref> --head <ref>
#   flow-dep-diff.sh <base>..<head>
#
# Output (per references/command-output-format.md):
#   STATE=ok|none|unavailable
#   REASON=<why>                              (none and unavailable)
#   MANIFESTS_EXAMINED=<n>
#   DEP_ADDED=<name>@<version> manifest=<path>:<line>
#   DEP_CHANGED=<name> <old>-><new> manifest=<path>:<line>
#   DEP_REMOVED=<name> manifest=<path>:<line>
#   DIFF_BASE=<sha>                           (the merge base actually compared)
#   DEP_BASELINE=<name>                       (each package at the merge base,
#     from the manifests THIS RANGE TOUCHES — a near-name to a package declared
#     only in a manifest the range leaves alone is therefore not reported)
#   DEP_BASELINE_TRUNCATED=<n> name(s) not printed
#   DEP_INSTALL_HOOK=<name> manifest=<path>:<line>
#   DEP_REPLACED=<module> -> <target>@<version> manifest=<path>:<line>
#     a go.mod replace: the named module no longer comes from upstream
#   DEP_NEAR_NAME=<added> ~ <baseline> distance=<n>
#   MANIFEST_UNPARSED=<path> reason=<why>
#
# MANIFESTS_EXAMINED=0 with STATE=none means no manifest was in the diff.
# MANIFESTS_EXAMINED=1 with no DEP_ lines means a manifest was read and nothing
# about its dependencies changed. Those are different answers, and a caller
# that cannot tell them apart will report a clean dependency review it never
# performed. A manifest that could not be read is MANIFEST_UNPARSED and makes
# the whole run STATE=unavailable — the packages it did read are still printed,
# because withholding them helps nobody, but the answer is incomplete and says so.
#
# Exits 0 in every reported state: the section is the contract, not the exit
# code. Exits 1 on a usage error, and 2 when the helper itself could not run
# — git unreadable, or the parser module unimportable — in which case it
# still prints STATE=unavailable so a caller reading only stdout is not left
# to infer silence.

set -uo pipefail

PROG="flow-dep-diff.sh"

usage() {
  printf '%s\n' "usage: $PROG --base <ref> --head <ref>" >&2
  printf '%s\n' "       $PROG <base>..<head>" >&2
}

BASE=""
HEAD_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || { usage; exit 1; }; BASE="$2"; shift 2 ;;
    --head) [ $# -ge 2 ] || { usage; exit 1; }; HEAD_REF="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) printf '%s\n' "$PROG: unknown option" >&2; usage; exit 1 ;;
    *)
      # Positional `<base>..<head>`. Only accepted when neither flag was given,
      # so a caller cannot half-specify the range two ways and get a silent
      # winner.
      case "$1" in
        *..*)
          [ -z "$BASE" ] && [ -z "$HEAD_REF" ] || { usage; exit 1; }
          BASE="${1%%..*}"
          HEAD_REF="${1##*..}"
          ;;
        *) printf '%s\n' "$PROG: expected <base>..<head>" >&2; usage; exit 1 ;;
      esac
      shift ;;
  esac
done

[ -n "$BASE" ] && [ -n "$HEAD_REF" ] || { usage; exit 1; }

# Refs reach `git` as argv entries, never a shell string, so a ref cannot run a
# command. This check refuses the shapes git itself treats as options or as
# pathspec separators, which would otherwise change what the command means.
for _ref in "$BASE" "$HEAD_REF"; do
  case "$_ref" in
    -*|*' '*|'') printf '%s\n' "$PROG: invalid ref" >&2; exit 1 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=python3 is not available, so no manifest could be read"
  printf '%s\n' "MANIFESTS_EXAMINED=0"
  exit 0
fi

BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
# An empty BIN_DIR would become sys.path.insert(0, ""), which is the current
# directory — during a review, the repository under review. The sys.path
# filter below exists to keep that out; this keeps it from being handed back.
if [ -z "$BIN_DIR" ] || [ ! -d "$BIN_DIR" ]; then
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=cannot resolve the directory holding this script"
  printf '%s\n' "MANIFESTS_EXAMINED=0"
  exit 2
fi

# Git Bash hands this script a POSIX path (/d/a/proj/...) while `python3` on
# Windows is a native build that reads it as a different location, so the
# import of the parser module beside this script fails before any work starts.
# `cygpath -m` renders a path in the one form bash, git and a native Python all
# resolve. On POSIX this is the identity and the conversion is unreachable.
# Shape copied from bin/journal-append.sh; issue #246 consolidates the copies.
py_path() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
      else
        printf '%s' "$1"
      fi ;;
    *) printf '%s' "$1" ;;
  esac
}

PYTHONSAFEPATH=1 FLOW_DEP_BASE="$BASE" FLOW_DEP_HEAD="$HEAD_REF" \
  FLOW_DEP_BIN="$(py_path "$BIN_DIR")" python3 - <<'PYEOF'
import os
import subprocess
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, os.environ["FLOW_DEP_BIN"])

try:
    from _flow_dep_parse import (  # noqa: E402
        ParseError,
        classify,
        edit_distance,
        safe_name,
        safe_scalar,
    )
except ImportError as e:
    # Loud, not silent. A caller that sees STATE=unavailable knows the
    # dependency read did not happen; one that saw STATE=none would be told
    # the change touches no dependency, which is a different claim.
    sys.stderr.write(
        "flow-dep-diff.sh: cannot import _flow_dep_parse from %s: %s\n"
        % (os.environ.get("FLOW_DEP_BIN", "?"), e)
    )
    print("STATE=unavailable")
    print("REASON=the manifest parser module could not be imported")
    print("MANIFESTS_EXAMINED=0")
    sys.exit(2)

BASE = os.environ["FLOW_DEP_BASE"]
HEAD = os.environ["FLOW_DEP_HEAD"]

out = []


def emit(line):
    out.append(line)


def flush(state, reason=None, examined=0):
    print("STATE=%s" % state)
    if reason:
        print("REASON=%s" % reason)
    print("MANIFESTS_EXAMINED=%d" % examined)
    for line in out:
        print(line)
    sys.exit(0)


def git(args):
    """Run git, returning (ok, stdout). Never raises on a non-zero exit."""
    try:
        proc = subprocess.run(
            ["git"] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as e:
        return False, str(e)
    if proc.returncode != 0:
        return False, proc.stderr.decode("utf-8", "replace").strip()
    return True, proc.stdout.decode("utf-8", "replace")


for ref in (BASE, HEAD):
    ok, _ = git(["rev-parse", "--verify", "--quiet", ref + "^{commit}"])
    if not ok:
        flush("unavailable", "ref %s does not resolve to a commit" % safe_scalar(ref))

# Compare against the merge base, not the tip of the base branch. With a
# two-dot diff, everything the base branch did after the fork reads as a
# reversal: a package main added while this change was open prints
# DEP_REMOVED, and lands in the near-name baseline as though the change had
# seen it. Neither is true of the change under review.
ok, merge_base = git(["merge-base", BASE, HEAD])
if not ok or not merge_base.strip():
    flush(
        "unavailable",
        "no merge base between %s and %s" % (safe_scalar(BASE), safe_scalar(HEAD)),
    )
DIFF_BASE = merge_base.strip()
emit("DIFF_BASE=%s" % safe_scalar(DIFF_BASE))

# -c core.quotePath=off keeps a non-ASCII path printable as itself rather than
# as C-style escapes, which would not match the path `git show` then wants.
ok, listing = git(
    ["-c", "core.quotePath=off", "diff", "--name-only", DIFF_BASE, HEAD]
)
if not ok:
    flush("unavailable", "git diff failed: %s" % (safe_scalar(listing) or "unknown"))

manifests = []
for path in listing.splitlines():
    path = path.strip()
    if not path:
        continue
    hit = classify(path)
    if hit:
        manifests.append((path, hit[1]))

if not manifests:
    flush("none", "no dependency manifest in the diff", 0)

manifests.sort()


def read_at(ref, path):
    """Content of `path` at `ref`, or None when it does not exist there.

    A file absent at the base is an added manifest and a file absent at the
    head is a deleted one. Both are ordinary, so neither is an error.
    """
    ok, content = git(["show", "%s:%s" % (ref, path)])
    return content if ok else None


added = []
changed = []
removed = []
hooks = []
unparsed = []
replaced = []
baseline_names = set()
examined = 0

for path, parser in manifests:
    examined += 1
    base_text = read_at(DIFF_BASE, path)
    head_text = read_at(HEAD, path)

    base_res = None
    head_res = None
    failed = False
    for label, text in (("base", base_text), ("head", head_text)):
        if text is None:
            continue
        try:
            result = parser(text)
        except ParseError as e:
            unparsed.append((path, "%s at %s" % (str(e), label)))
            failed = True
            break
        except Exception as e:  # a parser bug must not be read as "no deps"
            unparsed.append(
                (path, "%s while reading %s" % (type(e).__name__, label))
            )
            failed = True
            break
        if label == "base":
            base_res = result
        else:
            head_res = result
    if failed:
        continue

    base_deps = base_res.deps if base_res else {}
    head_deps = head_res.deps if head_res else {}

    def usable(name, side):
        """A name that cannot be printed as a field makes the file unreadable.

        Dropping it instead would leave the run claiming STATE=ok with a
        package missing from the report — and a base-side name dropped
        quietly also loses the removal and the baseline entry.
        """
        safe = safe_name(name)
        if safe is None:
            unparsed.append(
                (path, "a dependency name in the %s is not a printable field" % side)
            )
            return None
        return safe

    bad = False
    for name in base_deps:
        if usable(name, "base") is None:
            bad = True
            break
    if not bad:
        for name in head_deps:
            if usable(name, "head") is None:
                bad = True
                break
    if bad:
        continue

    for name in base_deps:
        baseline_names.add(safe_name(name))

    if head_res:
        base_replaces = set(
            (m, t, v) for m, t, v, _l in (base_res.replaces if base_res else [])
        )
        for module, target, version, line in head_res.replaces:
            if (module, target, version) in base_replaces:
                continue
            m_safe = safe_name(module)
            t_safe = safe_scalar(target)
            if m_safe and t_safe:
                replaced.append((m_safe, t_safe, version, path, line))
        for name, line in head_res.hooks:
            safe = safe_name(name)
            if safe:
                hooks.append((safe, path, line))

    for name, hvers in head_deps.items():
        safe = safe_name(name)
        if name not in base_deps:
            for version, line in sorted(hvers.items(), key=lambda kv: str(kv[0])):
                added.append((safe, version, path, line))
            continue
        bvers = base_deps[name]
        if set(bvers) == set(hvers):
            continue
        # One version on each side is a bump. Anything else is a lockfile
        # holding several versions of the package at once — normal in Rust
        # and pnpm — and collapsing that into a single bump would report one
        # version and hide the rest.
        gone = sorted(set(bvers) - set(hvers), key=str)
        fresh = sorted(set(hvers) - set(bvers), key=str)
        # One version out and one in is a bump, whether the package has one
        # version or five. Without this, a package declared in two sections at
        # different versions — typescript in dependencies and devDependencies
        # is routine — turns an ordinary bump into a false DEP_ADDED plus a
        # false DEP_REMOVED, and each false add costs a full per-package
        # judgment downstream.
        if len(gone) == 1 and len(fresh) == 1:
            changed.append((safe, gone[0], fresh[0], path, hvers[fresh[0]]))
            continue
        for version in fresh:
            added.append((safe, version, path, hvers[version]))
        for version in gone:
            removed.append((safe, version, path, bvers[version]))

    for name, bvers in base_deps.items():
        if name not in head_deps:
            safe = safe_name(name)
            for version in sorted(bvers, key=str):
                removed.append((safe, version, path, bvers[version]))


def field(value):
    """Render one output field, sanitising as it goes.

    This is the single boundary every value crosses on its way out, so a
    caller cannot forget to sanitise one. Three outcomes, and they are
    deliberately distinguishable:

      (unpinned)  the manifest declared no version
      (refused)   it declared one this will not print — a value carrying a
                  record separator, a quote or a control character. Printing
                  the same marker for both would let a forged value read as
                  an ordinary unpinned dependency.
      "quoted"    the value carries whitespace, which would otherwise end the
                  field early (npm ">=1.0.0 <2.0.0", Gemfile "~> 7.0").
    """
    if value is None:
        return "(unpinned)"
    safe = safe_scalar(value)
    if safe is None:
        return "(refused)"
    if any(c.isspace() for c in safe):
        return '"%s"' % safe
    return safe


def loc(path, line):
    safe_path = safe_scalar(path)
    if not safe_path:
        return "manifest=(unprintable)"
    if line is None:
        return "manifest=%s" % field(safe_path)
    return "manifest=%s" % field("%s:%s" % (safe_path, line))


for name, version, path, line in sorted(added, key=lambda t: (t[0], str(t[1]), t[2])):
    emit("DEP_ADDED=%s@%s %s" % (name, field(version), loc(path, line)))
for name, old, new, path, line in sorted(changed, key=lambda t: (t[0], str(t[1]), str(t[2]), t[3])):
    emit(
        "DEP_CHANGED=%s %s->%s %s"
        % (name, field(old), field(new), loc(path, line))
    )
for name, version, path, line in sorted(
        removed, key=lambda t: (t[0], str(t[1]), t[2])):
    emit("DEP_REMOVED=%s@%s %s" % (name, field(version), loc(path, line)))
# The baseline goes into a reviewer's prompt. A lockfile bump can carry
# thousands of names, which would crowd out the findings they are there to
# support, so the list is capped and says when it was.
MAX_BASELINE = 500
_sorted_baseline = sorted(baseline_names)
for name in _sorted_baseline[:MAX_BASELINE]:
    emit("DEP_BASELINE=%s" % name)
if len(_sorted_baseline) > MAX_BASELINE:
    emit(
        "DEP_BASELINE_TRUNCATED=%d name(s) not printed"
        % (len(_sorted_baseline) - MAX_BASELINE)
    )
for name, path, line in sorted(hooks, key=lambda t: (t[0], t[1], str(t[2]))):
    emit("DEP_INSTALL_HOOK=%s %s" % (name, loc(path, line)))
for module, target, version, path, line in sorted(
        replaced, key=lambda t: (t[0], t[1], str(t[2]), t[3])):
    emit(
        "DEP_REPLACED=%s -> %s@%s %s"
        % (module, field(target), field(version), loc(path, line))
    )

# Near-name runs added names against the BASE baseline only. An added name is
# never compared with another added name: two packages arriving together are
# not evidence that one is mimicking the other.
near = set()
for name, _version, _path, _line in added:
    for existing in baseline_names:
        if existing == name:
            continue
        distance = edit_distance(name.lower(), existing.lower())
        if distance <= 2:
            near.add((name, existing, distance))
for name, existing, distance in sorted(near):
    emit("DEP_NEAR_NAME=%s ~ %s distance=%d" % (name, existing, distance))

for path, reason in sorted(unparsed):
    emit(
        "MANIFEST_UNPARSED=%s reason=%s"
        % (safe_scalar(path) or "(unprintable)", safe_scalar(reason) or "unknown")
    )

if unparsed:
    flush(
        "unavailable",
        "%d of %d manifest(s) could not be read" % (len(unparsed), examined),
        examined,
    )

flush("ok", None, examined)
PYEOF
