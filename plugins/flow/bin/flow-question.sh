#!/usr/bin/env bash
# [flow] Stored escalation questions: every escalation is a record with an id
# and a status, kept whether or not a person is at the session (#340).
#
# Subcommands:
#   add      --situation T --tried T --option T --option T [--option T]
#            --recommendation T --blocking yes|soft|no --risk T
#            --command <who asked, e.g. "/flow:pr step 7a">
#            [--issue N] [--pr N] [--run <FlowRun id>] [--journal]
#            Stores an open question and prints QUESTION_ID=<id>. The first
#            --option is the recommended one (escalation-format.md: two or
#            three options, the recommendation first). A missing field, more
#            than three options or fewer than two, or a blocking level other
#            than yes, soft or no is refused with the field named.
#   answer   <id> --choice <option number or its exact text> [--by T] [--journal]
#            Records the answer; only an open question can be answered, and
#            only with one of its options.
#   withdraw <id> --reason T [--journal]
#            Withdraws an open question (asked again in another form, or no
#            longer relevant).
#   list     [--status open|answered|withdrawn|all] [--issue N] [--pr N] [--run ID]
#            One line per question, oldest first:
#            <id>|<status>|<blocking>|<issue>|<pr>|<command>|<situation>
#            Default --status open.
#   get      <id> [--json|--prompt]   the record (YAML, JSON with --json), or
#            with --prompt the six-field body for AskUserQuestion's question
#            (the shape of references/escalation-format.md, as
#            bin/flow-escalate.sh prints it), followed by the question id
#
# --journal also writes the decision-journal artifact: escalation-asked on
# add, escalation-resolved on answer (escalation_field: options) and on
# withdraw (escalation_field: situation), to the issue journal with --issue, or
# today's session journal without it (bin/journal-record.sh).
#
# Records are <runtime dir>/questions/<id>.yaml (bin/flow-runtime-dir.sh,
# default .flow), not committed: the directory carries a .gitignore of `*`,
# written on first use. Writes take the directory's lock and go through
# bin/_journal_atomic.py (O_NOFOLLOW, flock, temp file + rename + fsync), the
# rules the decision journal follows; a new record is created exclusively, so
# two concurrent adds never share an id or overwrite each other. Nothing is
# read or written through a symlink.
#
# FLOW_QUESTION_ID_HINT, when set to a well-formed id, is the id `add` tries
# first (scripts and tests); one that is taken is passed over for a fresh id,
# as any id is.
#
# Exit codes: 0 done · 1 refused input (the reason names the field) ·
# 2 infrastructure or refused path (python3/PyYAML missing, a symlink, a
# lock that cannot be taken) · 3 no such question · 4 the question is not
# open (answer or withdraw on an answered or withdrawn question)

set -uo pipefail
unset CDPATH
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-question.sh: python3 required but not installed" >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

python3 - "$SCRIPT_DIR" "$@" <<'PYEOF'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import json, re, secrets, datetime
sys.path.insert(0, sys.argv[1])
try:
    import yaml
except ImportError:
    print("flow-question.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)", file=sys.stderr)
    sys.exit(2)
from _journal_atomic import (JournalAtomicError, TargetExists, acquire_lock, ensure_repo_dir,
                             write_yaml_file)
from _flow_cli import open_regular
from _repo_dir import runtime_dir

ARGS = sys.argv[2:]
PLUGIN_BIN = sys.argv[1]
ID_RE = re.compile(r"^q-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$")
STATUSES = ("open", "answered", "withdrawn")
FIELD_LIMIT = 4000


def die(msg, code):
    print(f"flow-question.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def one_line(v):
    return " ".join(str(v).split())


def parse(args, flags, multi=(), switches=()):
    opts, pos = {}, []
    i = 0
    while i < len(args):
        a = args[i]
        if a in switches:
            opts[a] = True
            i += 1
        elif a in flags or a in multi:
            if i + 1 >= len(args):
                die(f"{a} requires a value", 1)
            if a in multi:
                opts.setdefault(a, []).append(args[i + 1])
            else:
                if a in opts:
                    die(f"{a} given twice", 1)
                opts[a] = args[i + 1]
            i += 2
        elif a.startswith("--"):
            die(f"unknown argument: {a}", 1)
        else:
            pos.append(a)
            i += 1
    return opts, pos


def text(opts, flag, name):
    v = opts.get(flag)
    if v is None or not str(v).strip():
        die(f"missing required field: {name} ({flag})", 1)
    if len(v) > FIELD_LIMIT:
        die(f"{name} is longer than {FIELD_LIMIT} characters", 1)
    return v.strip()


def number(opts, flag):
    v = opts.get(flag)
    if v is None:
        return None
    if not re.fullmatch(r"[1-9][0-9]{0,9}", v):
        die(f"{flag} must be a positive integer, not {v!r}", 1)
    return int(v)


def run_id(opts):
    v = opts.get("--run")
    if v is None:
        return None
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,99}", v):
        die(f"--run must be a FlowRun id, not {v!r}", 1)
    return v


QDIR = os.path.join(runtime_dir(), "questions")
LOCK = os.path.join(QDIR, ".lock")
RMW_LOCK = os.path.join(QDIR, ".update.lock")


def prepare(create):
    try:
        ensure_repo_dir(QDIR, create=create)
    except JournalAtomicError as exc:
        die(f"{exc.summary}; questions are not read or written through it", 2)
    if not create:
        return
    gi = os.path.join(QDIR, ".gitignore")
    if os.path.islink(gi):
        die(f"refusing — {gi} is a symlink", 2)
    if not os.path.lexists(gi):
        try:
            fd = os.open(gi, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write("*\n")
        except FileExistsError:
            pass
        except OSError as exc:
            die(f"cannot write {gi}: {exc}", 2)


def path_of(qid):
    if not ID_RE.match(qid or ""):
        die(f"not a question id: {qid!r}", 1)
    return os.path.join(QDIR, qid + ".yaml")


def load(path):
    if os.path.islink(path):
        die(f"refusing — {path} is a symlink", 2)
    if not os.path.lexists(path):
        return None
    try:
        with open_regular(path) as f:
            data = yaml.safe_load(f)
    except Exception as exc:
        die(f"{path} could not be read: {exc}", 2)
    if not isinstance(data, dict):
        die(f"{path} is not a question record", 2)
    return data


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def journal(rec, jtype, meta):
    import subprocess
    scope = ["--issue", str(rec["issue"])] if rec.get("issue") else ["--session"]
    cmd = [os.path.join(PLUGIN_BIN, "journal-record.sh")] + scope + ["--type", jtype]
    for k, v in meta:
        cmd += ["--metadata", f"{k}={one_line(v)}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"flow-question.sh: the journal artifact {jtype} could not be written: {one_line(r.stderr)[:300]}", file=sys.stderr)
        print("JOURNAL=failed")
    else:
        print("JOURNAL=recorded")


def cmd_add(args):
    opts, pos = parse(args, ("--situation", "--tried", "--recommendation", "--blocking", "--risk",
                             "--command", "--issue", "--pr", "--run"), multi=("--option",), switches=("--journal",))
    if pos:
        die(f"unexpected argument: {pos[0]}", 1)
    rec = {
        "situation": text(opts, "--situation", "situation"),
        "tried": text(opts, "--tried", "what was tried"),
    }
    options = [o.strip() for o in opts.get("--option", [])]
    if any(not o for o in options):
        die("an option is empty", 1)
    if len(options) < 2:
        die(f"options: two or three are required, the recommended one first (got {len(options)})", 1)
    if len(options) > 3:
        die(f"options: at most three (got {len(options)})", 1)
    if len(set(options)) != len(options):
        die("options: two options have the same text", 1)
    for o in options:
        if len(o) > FIELD_LIMIT:
            die(f"an option is longer than {FIELD_LIMIT} characters", 1)
    rec["options"] = options
    rec["recommendation"] = text(opts, "--recommendation", "recommendation")
    blocking = text(opts, "--blocking", "blocking").lower()
    if blocking not in ("yes", "soft", "no"):
        die(f"blocking must be yes, soft or no, not {opts['--blocking']!r}", 1)
    rec["blocking"] = blocking
    rec["risk"] = text(opts, "--risk", "risk")
    rec["command"] = text(opts, "--command", "the command that asked")
    rec["issue"] = number(opts, "--issue")
    rec["pr"] = number(opts, "--pr")
    rec["run"] = run_id(opts)
    prepare(create=True)
    hint = os.environ.get("FLOW_QUESTION_ID_HINT", "")
    for attempt in range(20):
        if attempt == 0 and ID_RE.match(hint):
            qid = hint
        else:
            qid = "q-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(3)
        record = {"id": qid, "status": "open", "asked_at": now()}
        record.update(rec)
        record.update({"answer": None, "answered_at": None, "answered_by": None,
                       "withdrawn_at": None, "withdraw_reason": None})
        try:
            write_yaml_file(path_of(qid), LOCK, record, exclusive=True)
        except TargetExists:
            continue
        except JournalAtomicError as exc:
            die(str(exc), 2)
        print(f"QUESTION_ID={qid}")
        print("STATUS=open")
        if opts.get("--journal"):
            journal(record, "escalation-asked", [("question_id", qid), ("blocking", blocking),
                    ("command", rec["command"]), ("situation", rec["situation"][:200])])
        return 0
    die("could not find a free question id", 2)


def update(qid, change):
    prepare(create=False)
    path = path_of(qid)
    try:
        fd = acquire_lock(RMW_LOCK, timeout=30)
    except JournalAtomicError as exc:
        die(str(exc), 2)
    try:
        rec = load(path)
        if rec is None:
            die(f"no question {qid}", 3)
        if rec.get("status") != "open":
            die(f"question {qid} is {rec.get('status')}, not open", 4)
        change(rec)
        try:
            write_yaml_file(path, LOCK, rec)
        except JournalAtomicError as exc:
            die(str(exc), 2)
        return rec
    finally:
        os.close(fd)


def cmd_answer(args):
    opts, pos = parse(args, ("--choice", "--by"), switches=("--journal",))
    if len(pos) != 1:
        die("answer takes one question id", 1)
    choice = text(opts, "--choice", "choice")
    def change(rec):
        options = rec.get("options") or []
        picked = None
        if re.fullmatch(r"[1-9][0-9]*", choice) and int(choice) <= len(options):
            picked = options[int(choice) - 1]
        elif choice in options:
            picked = choice
        if picked is None:
            die(f"the choice {choice!r} is not one of the question's options; it stays open", 1)
        rec.update({"status": "answered", "answer": picked, "answered_at": now(),
                    "answered_by": one_line(opts.get("--by") or "person")})
    rec = update(pos[0], change)
    print(f"QUESTION_ID={rec['id']}")
    print("STATUS=answered")
    print(f"ANSWER={one_line(rec['answer'])}")
    if opts.get("--journal"):
        journal(rec, "escalation-resolved", [("escalation_field", "options"), ("outcome", rec["answer"]),
                ("question_id", rec["id"])])
    return 0


def cmd_withdraw(args):
    opts, pos = parse(args, ("--reason",), switches=("--journal",))
    if len(pos) != 1:
        die("withdraw takes one question id", 1)
    reason = text(opts, "--reason", "reason")
    rec = update(pos[0], lambda r: r.update({"status": "withdrawn", "withdrawn_at": now(),
                                             "withdraw_reason": reason}))
    print(f"QUESTION_ID={rec['id']}")
    print("STATUS=withdrawn")
    if opts.get("--journal"):
        journal(rec, "escalation-resolved", [("escalation_field", "situation"),
                ("outcome", "withdrawn: " + reason), ("question_id", rec["id"])])
    return 0


def all_records():
    prepare(create=False)
    if not os.path.isdir(QDIR):
        return []
    out = []
    for name in sorted(os.listdir(QDIR)):
        if not name.endswith(".yaml") or not ID_RE.match(name[:-5]):
            continue
        rec = load(os.path.join(QDIR, name))
        if rec is not None:
            out.append(rec)
    return sorted(out, key=lambda r: (str(r.get("asked_at") or ""), str(r.get("id"))))


def cmd_list(args):
    opts, pos = parse(args, ("--status", "--issue", "--pr", "--run"))
    if pos:
        die(f"unexpected argument: {pos[0]}", 1)
    st = opts.get("--status", "open")
    if st not in STATUSES + ("all",):
        die(f"--status must be open, answered, withdrawn or all, not {st!r}", 1)
    issue, pr, run = number(opts, "--issue"), number(opts, "--pr"), run_id(opts)
    n = 0
    for r in all_records():
        if st != "all" and r.get("status") != st:
            continue
        if issue is not None and r.get("issue") != issue:
            continue
        if pr is not None and r.get("pr") != pr:
            continue
        if run is not None and r.get("run") != run:
            continue
        cells = [r.get("id"), r.get("status"), r.get("blocking"), r.get("issue") or "-", r.get("pr") or "-",
                 r.get("command"), r.get("situation")]
        print("|".join(one_line(c).replace("|", "\u2502") for c in cells))
        n += 1
    return 0


def cmd_get(args):
    opts, pos = parse(args, (), switches=("--json", "--prompt"))
    if len(pos) != 1:
        die("get takes one question id", 1)
    prepare(create=False)
    rec = load(path_of(pos[0]))
    if rec is None:
        die(f"no question {pos[0]}", 3)
    if opts.get("--json"):
        print(json.dumps(rec, sort_keys=True))
    elif opts.get("--prompt"):
        opts_md = "\n".join(f"{i}. {o}" for i, o in enumerate(rec.get("options") or [], 1))
        print(f"**Situation** — {rec.get('situation')}\n\n**What I tried** — {rec.get('tried')}\n\n"
              f"**Options**:\n{opts_md}\n\n**Recommendation** — {rec.get('recommendation')}\n\n"
              f"**Blocking?** — {rec.get('blocking')}\n\n**Risk** — {rec.get('risk')}\n\n"
              f"(question {rec.get('id')})")
    else:
        sys.stdout.write(yaml.safe_dump(rec, sort_keys=False, allow_unicode=True))
    return 0


if not ARGS or ARGS[0] in ("-h", "--help"):
    print("usage: flow-question.sh add|answer|withdraw|list|get ... (see the header of this script)", file=sys.stderr)
    sys.exit(0 if ARGS else 1)
sub, rest = ARGS[0], ARGS[1:]
handlers = {"add": cmd_add, "answer": cmd_answer, "withdraw": cmd_withdraw, "list": cmd_list, "get": cmd_get}
if sub not in handlers:
    die(f"unknown subcommand: {sub}", 1)
sys.exit(handlers[sub](rest))
PYEOF
