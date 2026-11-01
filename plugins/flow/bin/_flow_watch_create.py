"""Write a watch-mode trigger and its loop prompt from a shipped template.

Usage (through bin/flow-watch-create.sh, from the repository root, after the
/flow:watch pre-flight created <runtime dir>/triggers; the runtime directory is
flow.runtime.stateDir, bin/flow-runtime-dir.sh, default .flow):
  flow-watch-create.sh --kind issue  --repo OWNER/NAME --now TIME --issue N
  flow-watch-create.sh --kind branch --repo OWNER/NAME --now TIME
                       --branch NAME --default-branch NAME

The template is <plugin>/triggers/templates/<kind>-watch.trigger.yaml and the
prompt <kind>-watch.loop.md, found next to this script, never under the
working directory. Each ${NAME} placeholder is filled (${RUNTIME_DIR} with
the runtime directory); a value going into a
single-quoted YAML scalar has its quotes doubled. The trigger is checked
before anything is written: it must parse, carry the expected id and
context, forbid merge and release, deny recursion, and validate against
schemas/v1/trigger.schema.json (when jsonschema is installed; a WARN line
says when it is not).

Output, one KEY=value per line:
  WATCH_STATE=created   TRIGGER_ID, TRIGGER_FILE and LOOP_FILE follow (exit 0)
  WATCH_STATE=exists    the trigger file is already there; nothing written (exit 1)
  WATCH_STATE=refused   REFUSED="<reason>"; nothing written (exit 1)
Exit 2 is a usage error, 3 a check that could not run (PyYAML missing).
Neither file is written through a symbolic link: a directory on the way to
<runtime dir>/triggers, .claude and the files themselves are refused when they
are links. For an issue watch it also creates <runtime dir>/watch/ with a
.gitignore of `*`, where the loop keeps each iteration's snapshot.
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

# PYTHONSAFEPATH keeps this script's own directory off sys.path; the helpers
# it imports live there.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _repo_dir import runtime_dir

ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
NOW = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
ISSUE = re.compile(r"^[1-9][0-9]{0,9}$")
PLACEHOLDER = re.compile(r"\$\{([A-Z][A-Z_]*)\}")
# Characters a branch name may not carry here: git refuses most of them
# already; $, ` and " are refused too, because the loop prompt quotes the
# name in double quotes in the commands it gives.
BAD_BRANCH = re.compile(r"[\x00-\x20\x7f$`\"\\~^:?*\[]")
SLUG_MAX = 64 - len("branch-") - len("-watch")
PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Refused(Exception):
    pass


def usage(msg):
    sys.stderr.write("flow-watch-create: %s\n" % msg)
    sys.exit(2)


def out(state, **kv):
    print("WATCH_STATE=%s" % state)
    for k, v in kv.items():
        if k == "REFUSED":
            v = '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
        print("%s=%s" % (k, v))


def slug(branch):
    s = re.sub(r"[^a-z0-9]+", "-", branch.lower()).strip("-")
    s = s[:SLUG_MAX].rstrip("-")
    if not s:
        raise Refused("the branch name %s has no letter or digit to make an id from" % branch)
    return s


def fill(text, values, quote_yaml):
    def one(m):
        name = m.group(1)
        if name not in values:
            raise Refused("the template uses ${%s}, which /flow:watch does not fill" % name)
        v = values[name]
        return v.replace("'", "''") if quote_yaml else v
    return PLACEHOLDER.sub(one, text)


def no_link(path):
    """Refuse when path, or a directory on the way to it under the working
    directory, is a symbolic link."""
    parts = path.split("/")
    for i in range(1, len(parts) + 1):
        p = "/".join(parts[:i])
        if os.path.islink(p):
            raise Refused("%s is a symbolic link; nothing is written through it" % p)


def check(doc, want_id, want_ctx):
    if not isinstance(doc, dict):
        raise Refused("the filled template is not a mapping")
    meta = doc.get("metadata") or {}
    if meta.get("id") != want_id or not ID.match(str(meta.get("id"))):
        raise Refused("the filled template's id is %r, not %r" % (meta.get("id"), want_id))
    ctx = doc.get("context") or {}
    for k, v in want_ctx.items():
        if ctx.get(k) != v:
            raise Refused("the filled template's context.%s is %r, not %r" % (k, ctx.get(k), v))
    policy = doc.get("policy") or {}
    forbidden = policy.get("forbidden_actions") or []
    allowed = policy.get("allowed_actions") or []
    for a in ("merge", "release"):
        if a not in forbidden or a in allowed:
            raise Refused("the template does not forbid %s" % a)
    for k, v in (doc.get("recursion_policy") or {}).items():
        if v is not False:
            raise Refused("the template sets recursion_policy.%s" % k)
    try:
        import jsonschema
    except ImportError:
        print("WARN=\"jsonschema is not installed; the trigger was checked without the schema\"")
        return
    # The schema ships with the plugin; one that cannot be read, is not JSON
    # or is not a valid schema stops the check with a refusal that says so,
    # not a traceback or a "cannot write".
    where = "schemas/v1/trigger.schema.json"
    try:
        with open(os.path.join(PLUGIN, "schemas", "v1", "trigger.schema.json"), encoding="utf-8") as f:
            schema = json.load(f)
        cls = jsonschema.validators.validator_for(schema)
        cls.check_schema(schema)
    except OSError as e:
        raise Refused("cannot read the trigger schema %s: %s" % (where, e.strerror))
    except ValueError as e:
        raise Refused("the trigger schema %s is not valid JSON: %s" % (where, str(e).splitlines()[0]))
    except jsonschema.exceptions.SchemaError as e:
        raise Refused("the trigger schema %s is not a valid JSON Schema: %s" % (where, e.message))
    errors = list(cls(schema).iter_errors(doc))
    if errors:
        e = errors[0]
        raise Refused("the trigger does not match the schema at %s: %s"
                      % ("/".join(map(str, e.path)) or "(root)", e.message))


def write_new(path, text):
    """Create path; refuse a link and an existing file (O_EXCL). A write that
    fails after the file was created removes it: O_EXCL means this call made
    it, and a partial trigger or loop prompt must not be left behind."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
    except BaseException:
        try:
            os.unlink(path)
        except OSError:
            pass
        raise


def main(argv):
    args = {}
    it = iter(argv)
    for a in it:
        if a in ("--kind", "--repo", "--now", "--issue", "--branch", "--default-branch"):
            v = next(it, None)
            if v is None:
                usage("%s needs a value" % a)
            args[a[2:]] = v
        else:
            usage("unknown argument %s" % a)
    kind = args.get("kind")
    if kind not in ("issue", "branch"):
        usage("--kind takes issue or branch")
    for k in ("repo", "now"):
        if k not in args:
            usage("--%s is required" % k)
    try:
        import yaml
    except ImportError:
        sys.stderr.write("flow-watch-create: PyYAML is not installed; nothing was written\n")
        sys.exit(3)

    try:
        if not REPO.match(args["repo"]):
            raise Refused("the repository %s is not OWNER/NAME" % args["repo"])
        if not NOW.match(args["now"]):
            raise Refused("the time %s is not YYYY-MM-DDTHH:MM:SSZ" % args["now"])
        rt = runtime_dir()
        values = {"REPO": args["repo"], "NOW": args["now"], "RUNTIME_DIR": rt}
        if kind == "issue":
            if not ISSUE.match(args.get("issue", "")):
                raise Refused("the issue number %r is not a number" % args.get("issue", ""))
            values["ISSUE"] = args["issue"]
            tid = "issue-%s-watch" % args["issue"]
            want_ctx = {"repo": args["repo"], "issue": int(args["issue"])}
        else:
            branch = args.get("branch", "")
            default = args.get("default-branch", "")
            for what, name in (("branch", branch), ("default branch", default)):
                if not name:
                    raise Refused("no %s name" % what)
                if BAD_BRANCH.search(name) or name.startswith("-") or ".." in name:
                    raise Refused("the %s name %r holds a character /flow:watch does not quote" % (what, name))
            if branch == default:
                raise Refused("%s is the default branch; a branch watch merges the default branch into another branch" % branch)
            values.update({"BRANCH": branch, "BRANCH_SLUG": slug(branch), "DEFAULT_BRANCH": default})
            tid = "branch-%s-watch" % values["BRANCH_SLUG"]
            want_ctx = {"repo": args["repo"], "branch": branch, "default_branch": default}

        tdir = os.path.join(PLUGIN, "triggers", "templates")
        with open(os.path.join(tdir, "%s-watch.trigger.yaml" % kind), encoding="utf-8") as f:
            trigger = fill(f.read(), values, quote_yaml=True)
        with open(os.path.join(tdir, "%s-watch.loop.md" % kind), encoding="utf-8") as f:
            loop = fill(f.read(), values, quote_yaml=False)
        try:
            doc = yaml.safe_load(trigger)
        except yaml.YAMLError as e:
            raise Refused("the filled template is not valid YAML: %s" % str(e).splitlines()[0])
        check(doc, tid, want_ctx)

        tdir_out = rt + "/triggers"
        wdir = rt + "/watch"
        tfile = "%s/%s.trigger.yaml" % (tdir_out, tid)
        lfile = ".claude/flow-loop-%s.md" % tid
        no_link(tfile)
        no_link(lfile)
        if not os.path.isdir(tdir_out):
            raise Refused("%s does not exist; run the /flow:watch pre-flight first" % tdir_out)
        if os.path.lexists(tfile):
            out("exists", TRIGGER_ID=tid, TRIGGER_FILE=tfile,
                REFUSED="%s already exists; disable or delete it with /flow:trigger first" % tfile)
            return 1
        if kind == "issue":
            # The issue loop keeps each iteration's snapshot in
            # <runtime dir>/watch/, which ignores itself, as the journal's
            # auto-log folder does: a repository that never ran /flow:setup
            # has no ignore line for it.
            no_link(wdir + "/.gitignore")
            if not os.path.isdir(wdir):
                os.mkdir(wdir)
            if not os.path.lexists(wdir + "/.gitignore"):
                write_new(wdir + "/.gitignore", "*\n")
        if not os.path.isdir(".claude"):
            os.mkdir(".claude")
        if os.path.lexists(lfile):
            os.unlink(lfile)  # a prompt left by an earlier, deleted trigger; checked not a link above
        write_new(lfile, loop)
        try:
            write_new(tfile, trigger)
        except OSError:
            os.unlink(lfile)
            raise
    except Refused as e:
        out("refused", REFUSED=str(e))
        return 1
    except OSError as e:
        out("refused", REFUSED="cannot write: %s" % e)
        return 1
    out("created", TRIGGER_ID=tid, TRIGGER_FILE=tfile, LOOP_FILE=lfile)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
