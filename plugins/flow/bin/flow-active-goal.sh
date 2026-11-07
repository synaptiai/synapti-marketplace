#!/usr/bin/env bash
# [flow] Find the active FlowGoal and inspect it.
#
# Used by /flow:pr, /flow:merge, /flow:status, /flow:learn, and any other
# command that needs to know whether a FlowGoal is in flight and what its
# state is. Centralized so changes to the goals layout or YAML schema only
# touch one reader. Goals are read from <runtime dir>/goals/, the runtime
# directory being flow.runtime.stateDir (bin/flow-runtime-dir.sh, default
# .flow), under the repository top wherever below it this runs: the directory
# bin/flow-goal-record.sh writes (from_repo_top() in bin/_repo_dir.py).
#
# Output modes (exactly one allowed, default --status):
#   --path             path to <runtime dir>/goals/<id>.goal.yaml: relative at
#                      the repository top, absolute below it; with --commit
#                      <rev>, <rev>:<path relative to the top>
#   --id               metadata.id
#   --status           lifecycle.status (e.g., active, waiting_for_user)
#   --reason           lifecycle.last_evaluation.reason on one line (empty when
#                      the goal records none)
#   --json             full goal as JSON, sorted keys (jq-compatible)
#   --ac-summary       one line per AC: <id>|<status>|<evidence_ref>|<last_result>
#   --verifiable-count <total>/<verifiable> — AC count and the subset carrying a
#                      non-empty verification_command (feeds the compact-summary
#                      degenerate marker)
#
# Branch scoping:
#   Selection is branch-first — a goal that owns the current git branch always
#   wins over a cross-branch goal regardless of lifecycle status. If no goal owns
#   the current branch (or the branch is unknown, e.g. detached HEAD / legacy
#   goals predating scope.branch), the most-recently-modified ACTIVE goal is
#   returned. Exit 3 (degenerate) fires ONLY when >1 active goal share the
#   current branch — concurrent goals on different branches/worktrees each
#   resolve cleanly.
#   Exit codes: 0 resolved · 1 no applicable goal · 2 refused (a symlink on the
#   way to a goal, bad arguments) · 3 degenerate (>1 active on this branch) · 4 a goal file exists
#   but could not be read, and no other goal answered. 4 is distinct from 1
#   because callers gate on existence: the merge gate treats 1 as "no goal, not
#   applicable" and proceeds, which is the wrong answer when a goal is sitting
#   there unreadable. Unreadable goals are still skipped when some other goal
#   does answer, so one corrupt file never blocks a legitimate sibling.
#   --branch <name>    override the detected current branch: the branch whose
#                      goal is wanted (/flow:merge passes the pull request's
#                      head branch; tests and scripts use it too)
#   --allow-terminal   also consider a terminal `achieved` goal, but ONLY when it
#                      owns the current branch (never cross-branch) — lets the
#                      merge/pr gate observe a goal that already left the active
#                      window. Active goals on the current branch still take
#                      precedence. Stop hook + /flow:status omit the flag to keep
#                      their narrow active-only semantics.
#   --any-status       consider a goal on the current branch whatever its
#                      status: draft, waiting_for_user, waiting_for_ci, blocked,
#                      failed, cancelled as well as achieved (implies
#                      --allow-terminal). Like --allow-terminal, a goal that is
#                      not active is only selected when it owns the current
#                      branch. An active goal on the branch still wins; then a
#                      goal that is neither active nor achieved, so a branch
#                      carrying a failed goal and an achieved one is judged by
#                      the failed one (fail closed). The merge gate uses it: a
#                      goal that failed, was cancelled, or waits on a person is
#                      still this branch's goal, not "no goal".
#   --branch-strict    when the current branch is KNOWN and owns no goal, exit 1
#                      (not applicable) instead of falling back to a goal on
#                      another branch. Used by callers that must act on the
#                      current branch's goal and never a stale goal elsewhere
#                      (the merge/pr gate, the Stop-hook evaluator). When the
#                      branch is UNKNOWN (detached HEAD / CI / not a repo) there
#                      is nothing to discriminate on, so it still falls back to
#                      the most-recent active goal. Lenient callers (status/learn)
#                      omit the flag.
#   --runtime-dir <dir> the runtime directory the caller already resolved (a
#                      hook asks once per run); otherwise it is resolved here
#   --commit <rev>     read the goals committed in <rev> (a commit the local
#                      repository has) instead of the working tree: the goals
#                      directory at the same path, relative to the repository
#                      top. /flow:merge uses it, with --branch set to the pull
#                      request's head branch, to judge the goal the pull
#                      request carries when another branch is checked out.
#                      The same symlink rule applies inside the commit: a
#                      directory on the way to the goals, or a goal file,
#                      committed as a symlink is refused with exit 2. A <rev>
#                      that git cannot resolve to a commit is exit 2 as well.
#                      No goal has a modification time there, so ties go to
#                      the alphabetically first path.
#
# Exit codes:
#   0  active goal found; output on stdout
#   1  no active goal (caller decides whether this is OK)
#   2  infrastructure error (python3 / PyYAML missing) or refused: a directory
#      on the way to <runtime dir>/goals, or a goal file, is a symlink, or a
#      directory on the way is not a directory
#   3  degenerate state (>1 active goal on the current branch)
#
# Symlink defense: refuses to read, exit 2 with a note on stderr, when a
# directory on the way to <runtime dir>/goals or any *.goal.yaml is a symlink, wherever it points. A repository
# can commit one to a directory outside the checkout, and a goal read through
# it belongs to the link's target. The directory rule is ensure_repo_dir() in
# bin/_journal_atomic.py, the one every flow writer applies; the gates read the
# 2 as blocked, and the Stop hook's evaluator as no active goal.

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# Paths handed to python3 are converted for a native Windows python3 (#246).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/py-path.sh" 2>/dev/null || py_path() { printf '%s' "$1"; }
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
export PYTHONSAFEPATH=1

MODE="--status"
SAW_MODE=0
OVERRIDE_BRANCH=""
ALLOW_TERMINAL=0
ANY_STATUS=0
BRANCH_STRICT=0
RUNTIME_DIR_ARG=""
COMMIT_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --path|--id|--status|--reason|--json|--ac-summary|--verifiable-count)
      [ "$SAW_MODE" = "1" ] && { echo "flow-active-goal.sh: only one mode flag allowed (got both $MODE and $1)" >&2; exit 2; }
      MODE="$1"
      SAW_MODE=1
      shift
      ;;
    --branch)
      [ $# -lt 2 ] && { echo "flow-active-goal.sh: --branch requires a value" >&2; exit 2; }
      OVERRIDE_BRANCH="$2"
      shift 2
      ;;
    --allow-terminal)
      ALLOW_TERMINAL=1
      shift
      ;;
    --any-status)
      ANY_STATUS=1
      ALLOW_TERMINAL=1
      shift
      ;;
    --branch-strict)
      BRANCH_STRICT=1
      shift
      ;;
    --runtime-dir)
      [ $# -lt 2 ] && { echo "flow-active-goal.sh: --runtime-dir requires a value" >&2; exit 2; }
      RUNTIME_DIR_ARG="$2"
      shift 2
      ;;
    --commit)
      [ $# -lt 2 ] && { echo "flow-active-goal.sh: --commit requires a value" >&2; exit 2; }
      case "$2" in
        ''|-*) echo "flow-active-goal.sh: --commit needs a revision, not '$2'" >&2; exit 2 ;;
      esac
      COMMIT_ARG="$2"
      shift 2
      ;;
    -h|--help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
    *)
      echo "flow-active-goal.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-active-goal.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; import yaml" >/dev/null 2>&1; then
  echo "flow-active-goal.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

python3 - "$MODE" "${OVERRIDE_BRANCH:-}" "$ALLOW_TERMINAL" "$BRANCH_STRICT" "$SCRIPT_DIR" "$RUNTIME_DIR_ARG" "$ANY_STATUS" "$COMMIT_ARG" <<'PYEOF'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import sys, glob, os, json, subprocess
sys.path.insert(0, sys.argv[5])
import yaml
from _flow_cli import open_regular
from _journal_atomic import JournalAtomicError, ensure_repo_dir
from _repo_dir import from_repo_top, runtime_dir

mode = sys.argv[1]
override_branch = sys.argv[2] if len(sys.argv) > 2 else ""
allow_terminal = (sys.argv[3] if len(sys.argv) > 3 else "0") == "1"
branch_strict = (sys.argv[4] if len(sys.argv) > 4 else "0") == "1"
any_status = (sys.argv[7] if len(sys.argv) > 7 else "0") == "1"
commit = sys.argv[8] if len(sys.argv) > 8 else ""

GOALS_REL = os.path.join(runtime_dir(sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else None), "goals")
# The runtime directory is relative to the repository top. Run from a
# subdirectory, the goals are still the top's: from_repo_top() joins them to
# it (the path stays relative when the working directory is the top, so what
# callers print does not change there), as bin/flow-goal-record.sh does for
# the goals it writes. A --commit lookup keeps the relative path, which is
# what git's tree is keyed by.
GOALS_DIR = from_repo_top(GOALS_REL)

# Symlink defense — no goal is read through a symlinked runtime directory or goals.
READ_NOTE = "goals are not read through it"


def _git(args, text=True):
    return subprocess.run(["git"] + args, capture_output=True, text=text, timeout=30)


def _committed_goals(rev):
    """[(display path, loader)] for the *.goal.yaml files directly in the goals
    directory of commit `rev`, sorted by path. Exits 2 when `rev` is not a
    commit, or when a directory on the way or a goal file is committed as a
    symlink (mode 120000) or is not what it should be: the working-tree rule,
    applied to the tree git would check out."""
    r = _git(["rev-parse", "--verify", "--quiet", "--end-of-options", rev + "^{commit}"])
    oid = r.stdout.strip() if r.returncode == 0 else ""
    if not oid:
        print(f"flow-active-goal.sh: --commit {rev} is not a commit in this repository; {READ_NOTE}", file=sys.stderr)
        sys.exit(2)
    rel = os.path.normpath(GOALS_REL).replace(os.sep, "/")
    parts = [n for n in rel.split("/") if n and n != "."]
    # Each directory on the way, as git stores it: 040000 is a tree, 120000 a
    # symlink. A missing component means the commit has no goals.
    for i in range(1, len(parts) + 1):
        sub = "/".join(parts[:i])
        r = _git(["ls-tree", "--full-tree", "-z", oid, "--", sub])
        if r.returncode != 0:
            print(f"flow-active-goal.sh: cannot list {sub} in {rev}: {r.stderr.strip()}", file=sys.stderr)
            sys.exit(2)
        entry = next((e for e in r.stdout.split("\0") if e.endswith("\t" + sub)), "")
        if not entry:
            return []
        mode = entry.split(" ", 1)[0]
        if mode == "120000":
            print(f"flow-active-goal.sh: refusing — {sub} is a symlink in {rev}; {READ_NOTE}", file=sys.stderr)
            sys.exit(2)
        if mode != "040000":
            print(f"flow-active-goal.sh: refusing — {sub} is not a directory in {rev}; {READ_NOTE}", file=sys.stderr)
            sys.exit(2)
    r = _git(["ls-tree", "--full-tree", "-z", oid, "--", "/".join(parts) + "/"])
    if r.returncode != 0:
        print(f"flow-active-goal.sh: cannot list {rel} in {rev}: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    found = []
    for e in r.stdout.split("\0"):
        if "\t" not in e:
            continue
        meta, name = e.split("\t", 1)
        if not name.endswith(".goal.yaml") or "/" in name[len("/".join(parts)) + 1:]:
            continue
        mode, typ, blob = meta.split(" ")
        shown = f"{rev}:{name}"
        if mode == "120000":
            print(f"flow-active-goal.sh: refusing — {shown} is a symlink; {READ_NOTE}", file=sys.stderr)
            sys.exit(2)
        if typ != "blob":
            continue
        def _load(blob=blob):
            out = _git(["cat-file", "blob", blob], text=False)
            if out.returncode != 0:
                raise OSError(f"git cat-file failed for {blob}")
            return yaml.safe_load(out.stdout.decode("utf-8")) or {}
        found.append((shown, _load))
    return sorted(found, key=lambda t: t[0])


if commit:
    SOURCES = [(shown, load, 0.0) for shown, load in _committed_goals(commit)]
    if not SOURCES:
        sys.exit(1)
else:
    try:
        ensure_repo_dir(GOALS_DIR)
    except JournalAtomicError as exc:
        # "refusing — .flow is a symlink", which names the component: the
        # summary set where the rule refused, never the message cut at a "; ".
        print(f"flow-active-goal.sh: {exc.summary}; {READ_NOTE}", file=sys.stderr)
        sys.exit(2)

    if not os.path.isdir(GOALS_DIR):
        sys.exit(1)

    def _load_file(path):
        # Never waits on, or reads, anything but a regular file: a FIFO named
        # like a goal is opened at once and refused, and counted unreadable.
        with open_regular(path) as f:
            return yaml.safe_load(f) or {}

    SOURCES = []
    for path in sorted(glob.glob(os.path.join(glob.escape(GOALS_DIR), "*.goal.yaml"))):
        if os.path.islink(path):
            print(f"flow-active-goal.sh: refusing — {path} is a symlink; {READ_NOTE}", file=sys.stderr)
            sys.exit(2)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            mtime = 0.0
        SOURCES.append((path, (lambda p=path: _load_file(p)), mtime))

# Determine the current branch for branch-first selection. An
# explicit --branch override wins (test-only / scripting); otherwise ask git,
# tolerating any failure (not a repo, detached HEAD, git missing) by treating
# the branch as unknown ("").
current_branch = override_branch
if not current_branch:
    try:
        r = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            current_branch = r.stdout.strip()
    except Exception:
        current_branch = ""

active = []
# Terminal `achieved` goals, collected only when --allow-terminal is set, so the
# merge/pr gate can observe a goal that already left the `active` window. They
# are only ever selected when their scope.branch matches the current branch —
# never via a cross-branch fallback. The sole --allow-terminal caller (the gate)
# always runs on the goal's own branch, and a cross-branch terminal pick would
# both answer the gate with an unrelated goal and be influenceable through file
# mtime.
terminal = []
# Goals that are neither active nor achieved (draft, waiting_for_user,
# waiting_for_ci, blocked, failed, cancelled, or a status nobody recognises),
# collected only with --any-status, and like `terminal` selected only on the
# current branch.
other = []
unreadable = []
for path, load, mtime in SOURCES:
    try:
        data = load()
        status = (data.get("lifecycle") or {}).get("status")
        branch = (data.get("scope") or {}).get("branch") or ""
        if status == "active":
            active.append((path, data, branch, mtime))
        elif allow_terminal and status == "achieved":
            terminal.append((path, data, branch, mtime))
        elif any_status:
            other.append((path, data, branch, mtime))
    except Exception as exc:
        # Tolerate unparseable goals — they would block lookup of a sibling
        # legitimate goal. The Stop hook + status subcommand follow the same
        # tolerate-and-continue pattern. But remember that it happened: a goal
        # skipped here is not a goal that does not exist, and the difference
        # decides a merge. `except Exception` also catches every wrong shape —
        # `lifecycle: active` as a scalar raises AttributeError on .get — so
        # this arm is much wider than "unparseable".
        unreadable.append((path, exc))
        continue

# Nothing matched. Whether that means "no goal" or "a goal nobody could read"
# is the whole question for a caller that gates on existence: the merge gate
# reads exit 1 as "not applicable" and proceeds. Say the second thing when it
# is true, and let the caller decide.
if not active and not terminal and not other and unreadable:
    for path, exc in unreadable:
        print(f"flow-active-goal.sh: {path} could not be read: {exc}", file=sys.stderr)
    sys.exit(4)

if not active and not terminal and not other:
    sys.exit(1)

# Branch-first selection. A goal that owns the current branch always wins over a
# cross-branch goal, regardless of lifecycle status. Priority:
#   1. active goal(s) on the current branch  (>1 -> exit 3, degenerate)
#   2. a goal on the current branch that is neither active nor achieved
#      (only with --any-status): it fails closed over an achieved sibling
#   3. achieved goal on the current branch    (only with --allow-terminal)
#   4. most-recently-modified ACTIVE goal on any branch (legacy goals predating
#      scope.branch, detached HEAD, or a caller run from main)
# Terminal goals are never selected cross-branch (no tier-3 equivalent): if only
# achieved goals exist and none own the current branch, there is no applicable
# goal for this caller.
def _branch_matches(t):
    return bool(current_branch) and t[2] == current_branch

active_here = [t for t in active if _branch_matches(t)]
terminal_here = [t for t in terminal if _branch_matches(t)]
other_here = [t for t in other if _branch_matches(t)]

if active_here:
    if len(active_here) > 1:
        paths = [t[0] for t in active_here]
        print(
            f"flow-active-goal.sh: degenerate state — {len(active_here)} active goals "
            f"on branch '{current_branch}': {', '.join(paths)}",
            file=sys.stderr,
        )
        sys.exit(3)
    chosen = active_here[0]
elif other_here:
    # A goal on this branch that failed, was cancelled, is blocked, a draft, or
    # waits on a person or CI. Most-recent wins; equal mtime -> alphabetically
    # first path. It is chosen over an achieved goal on the same branch so the
    # caller is told about the goal that is not done.
    chosen = max(other_here, key=lambda t: t[3])
elif terminal_here:
    # Achieved goal on the current branch (e.g. the gate after evaluation).
    # Most-recent wins; equal mtime -> alphabetically-first path (sorted glob
    # order), deterministic across re-runs.
    chosen = max(terminal_here, key=lambda t: t[3])
elif active and (not branch_strict or not current_branch):
    # Fall back to the most-recently-modified ACTIVE goal (equal mtime ->
    # alphabetically-first path). This fires for lenient callers (status/learn
    # run from main, legacy goals without scope.branch), AND for --branch-strict
    # callers when the current branch is UNKNOWN ("" — detached HEAD / CI / not a
    # repo): with no branch to discriminate on, the most-recently-modified
    # active goal is the only sensible resolution (a more principled pick than
    # the pre-branch-scoping scan, which returned the alphabetically-first).
    # --branch-strict only bites when the branch IS known and no goal owns it —
    # that is the case where grabbing a cross-branch goal would be wrong (the
    # gate would false-block; the evaluator would mutate another branch's goal).
    chosen = max(active, key=lambda t: t[3])
else:
    # Either only terminal goals exist and none own the current branch, or
    # --branch-strict with a KNOWN current branch that owns no goal -> the
    # caller must treat this as "no applicable goal for this branch".
    # A goal skipped as unreadable could have been the one that owns this
    # branch; nobody can say it did not. Report that rather than "no goal",
    # which the merge gate reads as "not applicable" and proceeds on.
    if unreadable:
        for path, exc in unreadable:
            print(f"flow-active-goal.sh: {path} could not be read: {exc}", file=sys.stderr)
        sys.exit(4)
    sys.exit(1)

path, data = chosen[0], chosen[1]

def _one_line(value):
    """Collapse a value to a single line.

    Every consumer of --id and --status embeds the result in a `KEY=value`
    output grammar, and the command fences that do so run under zsh, whose
    builtin echo rewrites the argument. A goal YAML is a tracked file, so a fork
    pull request chooses it: `lifecycle.status` written with a backslash-n in a
    double-quoted scalar becomes a REAL newline here, and a real newline forges a
    whole extra line in /flow:start, /flow:status, /flow:merge and /flow:pr —
    including the FLOW_GOAL_LIFECYCLE line that merge.md gates on. Collapsing in
    the producer fixes every consumer at once; a caller cannot forget it, which
    is the lesson this whole class has taught four times.
    """
    return " ".join(str(value).split())


if mode == "--path":
    # Also one line: callers interpolate it into a path and into KEY=value lines.
    print(_one_line(path))
elif mode == "--id":
    print(_one_line((data.get("metadata") or {}).get("id", "")))
elif mode == "--status":
    print(_one_line((data.get("lifecycle") or {}).get("status", "")))
elif mode == "--reason":
    _lc = data.get("lifecycle") or {}
    _ev = _lc.get("last_evaluation") if isinstance(_lc, dict) else None
    print(_one_line((_ev or {}).get("reason", "") if isinstance(_ev, dict) else ""))
elif mode == "--json":
    print(json.dumps(data, sort_keys=True))
elif mode == "--ac-summary":
    # sanitize ALL emitted fields for
    # both newlines (line-break contract) and pipes (column-separator
    # contract). A goal YAML with a pipe character in any field would
    # silently inject extra columns into the documented
    # `<id>|<status>|<evidence_ref>|<last_result>` format. Replace pipe
    # with U+2502 (box drawings light vertical) so the visual intent is
    # preserved without breaking parsers.
    def _sanitize(value):
        s = " ".join(str(value).split())  # collapse all whitespace incl. newlines
        return s.replace("|", "│")
    acs_raw = (data.get("objective") or {}).get("acceptance_criteria")
    acs = acs_raw if isinstance(acs_raw, list) else []
    if acs_raw is not None and not isinstance(acs_raw, list):
        # A non-list acceptance_criteria would raise TypeError on iteration —
        # outside the parse loop's try. Printing nothing was the other half of
        # the bug: a goal naming three criteria in the wrong shape rendered as
        # a goal naming none, under a status line that says the goal is fine.
        print(f"?|unreadable|-|acceptance_criteria is {type(acs_raw).__name__}, not a list")
    for idx, ac in enumerate(acs):
        if not isinstance(ac, dict):
            # Tolerate a malformed AC shape rather than crashing, but say that
            # one was skipped — a criterion nobody could read is not a
            # criterion that is not there.
            print(f"?|unreadable|-|criterion at index {idx} is {type(ac).__name__}, not a mapping")
            continue
        ac_id = _sanitize(ac.get("id", "?"))
        status = _sanitize(ac.get("status", "pending"))
        evidence_ref = _sanitize(ac.get("evidence_ref") or "-")
        last_result = _sanitize(ac.get("last_result") or "-")
        print(f"{ac_id}|{status}|{evidence_ref}|{last_result}")
elif mode == "--verifiable-count":
    # Emit "<total>/<verifiable>" so the compact summary can flag a degenerate
    # goal (0 ACs, or 0 ACs carrying a non-empty verification_command) without
    # re-parsing the YAML. A verification_command of "" or whitespace is not
    # verifiable.
    acs_raw = (data.get("objective") or {}).get("acceptance_criteria")
    acs = acs_raw if isinstance(acs_raw, list) else []
    unreadable_acs = 0
    if acs_raw is not None and not isinstance(acs_raw, list):
        unreadable_acs = 1
    total = 0
    verifiable = 0
    for ac in acs:
        if not isinstance(ac, dict):
            unreadable_acs += 1
            continue
        total += 1
        vc = ac.get("verification_command")
        if isinstance(vc, str) and vc.strip():
            verifiable += 1
    # The caller flags a degenerate goal on a zero here. "0/0 because the
    # criteria could not be read" and "0/0 because there are none" are
    # different facts, and the count alone cannot carry that, so say it
    # alongside rather than letting the zero speak for both.
    if unreadable_acs:
        print(f"{total}/{verifiable} ({unreadable_acs} unreadable)")
    else:
        print(f"{total}/{verifiable}")
else:
    print(f"flow-active-goal.sh: unknown mode {mode}", file=sys.stderr)
    sys.exit(2)
PYEOF
