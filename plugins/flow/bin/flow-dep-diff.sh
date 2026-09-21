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
#   DEP_BASELINE=<name>                       (each package present at the base)
#   DEP_INSTALL_HOOK=<name> manifest=<path>:<line>
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
# code. Exits 1 on a usage error, 2 when git itself could not be read.

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

PYTHONSAFEPATH=1 FLOW_DEP_BASE="$BASE" FLOW_DEP_HEAD="$HEAD_REF" \
  FLOW_DEP_BIN="$BIN_DIR" python3 - <<'PYEOF'
import os
import subprocess
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, os.environ["FLOW_DEP_BIN"])

from _flow_dep_parse import (  # noqa: E402
    ParseError,
    classify,
    edit_distance,
    safe_scalar,
)

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

# -c core.quotePath=off keeps a non-ASCII path printable as itself rather than
# as C-style escapes, which would not match the path `git show` then wants.
ok, listing = git(
    ["-c", "core.quotePath=off", "diff", "--name-only", BASE, HEAD]
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
baseline_names = set()
examined = 0

for path, parser in manifests:
    examined += 1
    base_text = read_at(BASE, path)
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

    for name in base_deps:
        safe = safe_scalar(name)
        if safe:
            baseline_names.add(safe)

    if head_res:
        for name, line in head_res.hooks:
            safe = safe_scalar(name)
            if safe:
                hooks.append((safe, path, line))

    for name, (version, line) in head_deps.items():
        safe_name = safe_scalar(name)
        if not safe_name:
            unparsed.append((path, "a dependency name is not a printable scalar"))
            continue
        if name not in base_deps:
            added.append((safe_name, safe_scalar(version), path, line))
        else:
            old = base_deps[name][0]
            if old != version:
                changed.append(
                    (safe_name, safe_scalar(old), safe_scalar(version), path, line)
                )

    for name, (version, line) in base_deps.items():
        if name not in head_deps:
            safe_name = safe_scalar(name)
            if safe_name:
                removed.append((safe_name, path, line))


def loc(path, line):
    safe_path = safe_scalar(path)
    if not safe_path:
        return "manifest=(unprintable)"
    if line is None:
        return "manifest=%s" % safe_path
    return "manifest=%s:%d" % (safe_path, line)


for name, version, path, line in sorted(added):
    emit("DEP_ADDED=%s@%s %s" % (name, version or "(unpinned)", loc(path, line)))
for name, old, new, path, line in sorted(changed):
    emit(
        "DEP_CHANGED=%s %s->%s %s"
        % (name, old or "(unpinned)", new or "(unpinned)", loc(path, line))
    )
for name, path, line in sorted(removed):
    emit("DEP_REMOVED=%s %s" % (name, loc(path, line)))
for name in sorted(baseline_names):
    emit("DEP_BASELINE=%s" % name)
for name, path, line in sorted(hooks):
    emit("DEP_INSTALL_HOOK=%s %s" % (name, loc(path, line)))

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
