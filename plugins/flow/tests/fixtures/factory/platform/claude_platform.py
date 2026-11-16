"""A stand-in for `claude -p` for the factory's platform probe scenarios.

It does, in a small way, the parts of Claude Code the platform probes read:

  - the stream-json init event, with session_id, plugins (one per --plugin-dir,
    named from its .claude-plugin/plugin.json) and slash_commands;
  - a prompt that is a slash command (/<plugin>:<command> <arguments>) is
    expanded from the plugin's commands/<command>.md: each ```! block runs
    with bash, $ARGUMENTS replaced, and its output takes the block's place in
    a user event printed before any assistant event;
  - the steps of the prompt (or the expanded command), one per line, each one
    turn: `RUN: <command>` (Bash), `WRITE: <path>` (Write, content `probe`),
    `EDIT: <path>` (Edit, `original` becomes `edited`) and `TASK: <name>` (a
    task marked completed, which fires TaskCompleted). A step prefixed with
    `SUBAGENT ` is made by a subagent: its tool_use event carries a
    parent_tool_use_id. A run with no steps is one text reply: the last RUN
    command the session made (`none` when it made none) to a prompt that asks
    for the last command you ran, else `ok`;
  - hooks from each plugin's hooks/hooks.json: SessionStart, PreToolUse for
    Bash (exit 2, or a permissionDecision of deny or ask, refuses the call:
    -p has no one to ask), TaskCompleted, Stop and SessionEnd, each given its
    JSON input on stdin with CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR set;
  - --disallowedTools rules Bash(<prefix>:*), Bash(<command>), Edit(<glob>)
    and Write(<glob>), globs relative to the working directory; a Write or
    Edit outside the working directory and the --add-dir directories is
    refused;
  - --session-id, --resume (the steps not yet made continue; the prompt is
    not read for steps) and --fork-session; --max-turns (result subtype
    error_max_turns) and --max-budget-usd (error_max_budget_usd, checked
    after each turn); every refused call is in the result's
    permission_denials.

Files beside it:
  claude-launches.log    one line per start: the arguments
  claude-prompt-<n>.txt  the prompt of the nth start
  sessions/<id>.json     each session's steps not yet made, the RUN commands
                         it made, its command file and its cost
  claude-script          when present, run with bash before the first step
  claude-cost-per-turn   the cost of one turn (default 0.05)
  claude-hooks-only      when present, only hook commands that contain one of
                         its lines run (the real flow hooks are slow to run
                         dozens of times; the probe's own hooks wrap the ones
                         it reads)
  claude-bang-match      when present, only ```! blocks containing its text run
  claude-no-bang         ```! blocks do not run and their text stays
  claude-rerun-bang-on-resume  a resumed session runs its command's blocks again
  claude-ignore-deny     a command containing one of its lines runs although a
                         hook refused it
  claude-plugins-extra   a JSON list added to the init event's plugins (the
                         plugins the project's settings enable)
  claude-plugin-dir-overrides  an extra plugin named like a --plugin-dir one is
                         left out, as if --plugin-dir replaced it
  claude-init-no-plugins the init event has no plugins field
  claude-init-tools      a JSON list: the init event's tools field (by default
                         the --tools list, else the --allowedTools list, else
                         Bash, Read, Write, Edit)
  claude-subagent-ignores-disallowed  --disallowedTools does not reach subagents
  claude-cumulative-cost a resumed session reports its whole cost, not this run's
  claude-skip-steps      a step whose line contains one of its lines is not made
  claude-repeat-while    a RUN step is made again, one turn each time, while
                         its output matches this regular expression (a worker
                         told to repeat a call until it prints something else)
  claude-alter-steps     a RUN step whose line contains one of its lines is
                         made with ` # changed` added to its command
  claude-rerun-changed   a RUN step whose line contains one of its lines is
                         made again with ` # changed` added, and that second
                         call runs outside the stand-in sandbox (a changed
                         command that a sandbox rule happens not to cover)
  claude-drop-results    a RUN step whose line contains one of its lines runs,
                         but no tool_result event is printed for it
  claude-result-replace  lines `<text>\t<replacement>`: the text is replaced in
                         every RUN step's tool result. It stands in for output
                         no command in a scenario can produce, such as Python
                         reaching a host on the internet
  claude-model           the model: the init event's model and the result's
                         modelUsage key
  claude-turn-usage      lines `<cost>\t<usage json>`: the nth assistant
                         message carries the nth line's usage and costs its
                         cost (the last line stands for every later message),
                         in place of claude-cost-per-turn. The result then
                         reports the run's own token totals in usage, and,
                         with claude-model, in modelUsage too
  claude-cumulative-usage  a resumed session's modelUsage reports the whole
                         session's tokens, while usage keeps this run's
  claude-since-last      the result also carries model_usage_since_last_result:
                         this run's own cost under the run's model
                         (claude-model's, else --model's, else
                         claude-opus-5-5). A number on its first line is added
                         to a resumed run's total_cost_usd, and to its
                         modelUsage cost, as the spend of the session's
                         earlier runs that Claude Code reports again
  claude-usage-extra     a number of input tokens added to modelUsage, so its
                         totals match neither this run nor the session
  claude-no-cost-when    a run whose prompt contains one of its lines reports
                         no total_cost_usd
  claude-error-when      a run whose prompt contains one of its lines ends with
                         an error_during_execution result that keeps its cost
  claude-no-events       every run exits 1 before printing any event, with one
                         line on stderr, as Claude Code does when it cannot
                         start (no credentials, a refused flag)
  claude-api-error       every run ends at once as Claude Code ends a run the
                         API refused (a usage limit): an is_error result of
                         subtype success with api_error_status 429 and
                         terminal_reason api_error, costing nothing
  claude-api-error-when  the same, for a run whose prompt contains one of its
                         lines only
  claude-resume-fresh    --resume starts a new, empty session, as if the
                         earlier conversation were not carried over
  claude-resume-lost     --resume exits 1 before printing any event, saying
                         no conversation was found with that session id, as
                         Claude Code does when the session was not saved
  claude-split-turns     each assistant message is printed as two events with
                         the same message id and usage, a text block and then
                         its tool use or text, as Claude Code prints a message
                         with several content blocks
  claude-final-text      a run whose steps all ran ends with one more turn, a
                         text reply holding the file's first line
  claude-edit-unread     an EDIT step whose line contains one of its lines
                         fails as an Edit of a file not read first does: an
                         error tool result and no permission_denials entry,
                         whatever the rules say

The sandbox. When the --settings file has sandbox.enabled, each RUN command
runs under a small copy of Claude Code's sandbox, played through the
environment the stand-ins beside it read (curl, touch, security, gh's `auth
token` and git-credential-p16): FIXTURE_SANDBOX_DENY_READ (filesystem.denyRead
and the credentials.files denied, ~ expanded), FIXTURE_SANDBOX_WRITE_ROOTS
(the working directory and filesystem.allowWrite), FIXTURE_SANDBOX_HOSTS
(network.allowedDomains), and the credentials.envVars denied are removed. A
command matching an excludedCommands pattern runs without these. What the
stand-ins refused, and every http(s) host in the command that is off the list,
is added to the tool result as a <sandbox_violations> block. With or without
a sandbox, every proxy variable points at a closed local port, so no command
a scenario runs reaches a network.
  claude-sandbox-ignore  each line is a denied path as the settings write it,
                         a denied variable name, `write` or `network`: that
                         part of the sandbox is not applied
  claude-sandbox-repo-widens  the working directory's .claude/settings.json
                         sandbox block is merged in: its lists added, its
                         allowUnsandboxedCommands taken. When the file has
                         lines, only those keys of the block are merged
                         (excludedCommands, allowUnsandboxedCommands, network,
                         filesystem, credentials)
  claude-retry-unsandboxed  a RUN step whose line contains one of its lines,
                         and whose result has a <sandbox_violations> block, is
                         made once more with dangerouslyDisableSandbox set, as
                         the Bash tool tells a model to do. The retry runs
                         outside the sandbox only when the merged
                         allowUnsandboxedCommands is true
  claude-sandbox-drop-violations  a violation line containing one of its
                         lines is left out of the tool result
  claude-sandbox-extra-violations  lines `<text>\t<violation>`: the violation
                         is added to the result of a sandboxed RUN command
                         containing the text
"""
import fnmatch
import json
import os
import re
import subprocess
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
VALUE_FLAGS = {"--setting-sources", "--mcp-config", "--output-format", "--max-turns", "--max-budget-usd",
               "--permission-prompts", "--permission-mode", "--model", "--session-id", "--resume", "-r",
               "--settings", "--allowedTools", "--allowed-tools", "--tools"}
MULTI_FLAGS = {"--plugin-dir", "--add-dir", "--disallowedTools", "--disallowed-tools"}
STEP = re.compile(r"^(SUBAGENT )?(RUN|WRITE|EDIT|TASK): (.+)$")
CLOSED_PROXY = "http://127.0.0.1:9"
PROXY_VARS = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")
URL_HOST = re.compile(r"https?://([A-Za-z0-9.-]+)")


TOKEN_KEYS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
MODEL_USAGE_KEYS = ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens")


def knob(name):
    return os.path.exists(os.path.join(HERE, name))


def knob_lines(name):
    try:
        with open(os.path.join(HERE, name), encoding="utf-8") as f:
            return [ln.rstrip("\n") for ln in f if ln.strip()]
    except FileNotFoundError:
        return []


def parse(argv):
    opts = {"multi": {k: [] for k in MULTI_FLAGS}, "fork": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in MULTI_FLAGS:
            i += 1
            while i < len(argv) and not argv[i].startswith("-"):
                opts["multi"][a].append(argv[i])
                i += 1
            continue
        if a in VALUE_FLAGS and i + 1 < len(argv):
            opts[a] = argv[i + 1]
            i += 2
            continue
        if a == "--fork-session":
            opts["fork"] = True
        i += 1
    return opts


def emit(event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def plugin_name(d):
    try:
        with open(os.path.join(d, ".claude-plugin", "plugin.json"), encoding="utf-8") as f:
            return json.load(f).get("name") or os.path.basename(d)
    except (OSError, ValueError):
        return os.path.basename(d)


class Session:
    def __init__(self, opts, cwd):
        self.opts = opts
        self.cwd = cwd
        self.plugins = [os.path.abspath(p) for p in opts["multi"]["--plugin-dir"]]
        self.add_dirs = [os.path.realpath(p) for p in opts["multi"]["--add-dir"]]
        rules = []
        for r in opts["multi"]["--disallowedTools"] + opts["multi"]["--disallowed-tools"]:
            rules += [x.strip() for x in r.split(",") if x.strip()] if "(" not in r else [r]
        self.disallowed = rules
        self.denials = []
        self.turns = 0
        self.messages = 0
        self.cost = 0.0
        self.tokens = dict.fromkeys(TOKEN_KEYS, 0)
        self.sid = None
        self.sandbox = load_sandbox(opts.get("--settings"), cwd)
        self.violation_n = 0

    def hooks(self, event, payload, tool=None):
        """Run each hook for the event; return 'deny' when one refuses."""
        only = knob_lines("claude-hooks-only")
        decision = "allow"
        for root in self.plugins:
            try:
                with open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8") as f:
                    conf = json.load(f).get("hooks", {})
            except (OSError, ValueError):
                continue
            for entry in conf.get(event, []):
                matcher = entry.get("matcher", "")
                if tool is not None and matcher and not re.fullmatch(matcher, tool):
                    continue
                for h in entry.get("hooks", []):
                    cmd = h.get("command", "").replace("${CLAUDE_PLUGIN_ROOT}", root)
                    if only and not any(o in cmd for o in only):
                        continue
                    data = dict(payload, hook_event_name=event, session_id=self.sid or "", cwd=self.cwd,
                                permission_mode=self.opts.get("--permission-mode", "default"))
                    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=root, CLAUDE_PROJECT_DIR=self.cwd)
                    r = subprocess.run(["bash", "-c", cmd], input=json.dumps(data), capture_output=True,
                                       text=True, cwd=self.cwd, env=env, timeout=120, check=False)
                    if r.returncode == 2:
                        decision = "deny"
                        continue
                    try:
                        out = json.loads(r.stdout) if r.stdout.strip() else {}
                    except ValueError:
                        out = {}
                    d = (out.get("hookSpecificOutput") or {}).get("permissionDecision") if isinstance(out, dict) else None
                    if d in ("deny", "ask"):
                        decision = "deny"
        return decision

    def bash_disallowed(self, command):
        for r in self.disallowed:
            m = re.fullmatch(r"Bash\((.*)\)", r)
            if not m:
                continue
            pat = m.group(1)
            if pat.endswith(":*"):
                if command == pat[:-2] or command.startswith(pat[:-2] + " "):
                    return True
            elif command == pat:
                return True
        return False

    def file_disallowed(self, tool, path):
        rel = os.path.relpath(os.path.realpath(path), os.path.realpath(self.cwd))
        for r in self.disallowed:
            m = re.fullmatch(r"(Edit|Write)\((.*)\)", r)
            if not m:
                continue
            if m.group(1) in ("Edit", tool) and fnmatch.fnmatch(rel, m.group(2).removeprefix("./")):
                return True
        return False

    def inside(self, path):
        real = os.path.realpath(path)
        for d in [os.path.realpath(self.cwd)] + self.add_dirs:
            if real == d or real.startswith(d + os.sep):
                return True
        return False

    def command_env(self, command, unsandboxed=False, escape=False):
        """The environment a RUN command runs in, and the file the stand-ins
        log violations to (None when it runs unsandboxed)."""
        env = dict(os.environ)
        for name in PROXY_VARS:
            env[name] = CLOSED_PROXY
        env.pop("NO_PROXY", None)
        env.pop("no_proxy", None)
        sb = self.sandbox
        if escape or not sb or any(fnmatch.fnmatchcase(command, pat) for pat in sb["excluded"]) or (
                unsandboxed and sb["allow_unsandboxed"]):
            return env, None
        ignore = set(knob_lines("claude-sandbox-ignore"))
        home = os.environ.get("HOME", "")
        expand = lambda p: os.path.realpath(home + p[1:]) if p.startswith("~") else os.path.realpath(p)
        # Both spellings of each denied path, since the stand-ins compare
        # $HOME as it is set, which may run through a symbolic link.
        raw = lambda p: os.path.normpath(home + p[1:]) if p.startswith("~") else os.path.normpath(p)
        env["FIXTURE_SANDBOX_DENY_READ"] = ":".join(
            dict.fromkeys(f(p) for p in sb["deny_read"] if p not in ignore for f in (raw, expand)))
        if "write" not in ignore:
            env["FIXTURE_SANDBOX_WRITE_ROOTS"] = ":".join([os.path.realpath(self.cwd)] + [expand(p) for p in sb["allow_write"]])
        if "network" not in ignore:
            env["FIXTURE_SANDBOX_HOSTS"] = ",".join(sb["hosts"])
        for name in sb["deny_env"]:
            if name not in ignore:
                env.pop(name, None)
        self.violation_n += 1
        log = os.path.join(HERE, f"sandbox-violations-{os.getpid()}-{self.violation_n}.log")
        env["FIXTURE_SANDBOX_VIOLATIONS"] = log
        return env, log

    def violations(self, command, log):
        lines = []
        if log is not None:
            try:
                with open(log, encoding="utf-8") as f:
                    lines = [ln.rstrip("\n") for ln in f if ln.strip()]
                os.unlink(log)
            except FileNotFoundError:
                pass
            if "network" not in set(knob_lines("claude-sandbox-ignore")):
                lines += [f"network-outbound {h}" for h in dict.fromkeys(URL_HOST.findall(command))
                          if h not in self.sandbox["hosts"]]
            for ln in knob_lines("claude-sandbox-extra-violations"):
                text, _, violation = ln.partition("\t")
                if text in command:
                    lines.append(violation)
            drop = knob_lines("claude-sandbox-drop-violations")
            lines = [ln for ln in lines if not any(d in ln for d in drop)]
        return "\n<sandbox_violations>\n" + "\n".join(lines) + "\n</sandbox_violations>" if lines else ""

    def step(self, sub, kind, arg, unsandboxed=False, rerun=False):
        self.turns += 1
        tid = f"toolu_{self.turns}"
        parent = "toolu_subagent" if sub else None
        name = {"RUN": "Bash", "WRITE": "Write", "EDIT": "Edit", "TASK": "TaskUpdate"}[kind]
        if kind == "RUN" and (rerun or any(x in arg for x in knob_lines("claude-alter-steps"))):
            arg = arg + " # changed"
        path = arg if os.path.isabs(arg) else os.path.join(self.cwd, arg)
        tool_input = {"RUN": dict({"command": arg}, **({"dangerouslyDisableSandbox": True} if unsandboxed else {})),
                      "WRITE": {"file_path": path, "content": "probe"},
                      "EDIT": {"file_path": path, "old_string": "original", "new_string": "edited"},
                      "TASK": {"subject": arg, "status": "completed"}}[kind]
        self.assistant([{"type": "tool_use", "id": tid, "name": name, "input": tool_input}], parent)
        rules_apply = not (sub and knob("claude-subagent-ignores-disallowed"))
        refused = False
        result = ""
        if kind == "RUN":
            if (rules_apply and self.bash_disallowed(arg)) or (
                    self.hooks("PreToolUse", {"tool_name": "Bash", "tool_input": tool_input}, tool="Bash") == "deny"
                    and not any(x in arg for x in knob_lines("claude-ignore-deny"))):
                refused = True
            else:
                env, log = self.command_env(arg, unsandboxed, escape=rerun)
                r = subprocess.run(["bash", "-c", arg], capture_output=True, text=True, cwd=self.cwd,
                                   stdin=subprocess.DEVNULL, env=env, check=False)
                found = self.violations(arg, log)
                result = r.stdout + r.stderr + found
                if "network-outbound" in found:
                    # Claude Code under -p turns a blocked host into a
                    # network permission request that nobody can answer, and
                    # prints it as a system event whose message is text.
                    emit({"type": "system", "subtype": "permission_denied", "tool_name": "SandboxNetworkAccess",
                          "tool_use_id": f"{tid}-network", "decision_reason_type": "asyncAgent",
                          "message": "Permission for this tool use was denied. It requires approval, and this "
                                     "session has no approval surface."})
                for ln in knob_lines("claude-result-replace"):
                    text, _, replacement = ln.partition("\t")
                    result = result.replace(text, replacement)
        elif kind == "EDIT" and any(x in arg for x in knob_lines("claude-edit-unread")):
            result = "<tool_use_error>File has not been read yet. Read it first before writing to it.</tool_use_error>"
        elif kind in ("WRITE", "EDIT"):
            if (rules_apply and self.file_disallowed(name, path)) or not self.inside(path):
                refused = True
            elif kind == "WRITE":
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write("probe\n")
            else:
                try:
                    with open(path, encoding="utf-8") as f:
                        text = f.read()
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(text.replace("original", "edited"))
                except OSError as e:
                    result = str(e)
        else:
            self.hooks("TaskCompleted", {"task_subject": arg})
        if refused:
            self.denials.append({"tool_name": name, "tool_use_id": tid, "tool_input": tool_input})
            result = "Permission to use this tool was denied."
        if not (kind == "RUN" and any(x in arg for x in knob_lines("claude-drop-results"))):
            emit({"type": "user", "parent_tool_use_id": parent, "session_id": self.sid,
                  "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": result,
                                           "is_error": refused or result.startswith("<tool_use_error>")}]}})
        return result

    def assistant(self, content, parent=None):
        """Print one assistant message and charge its cost."""
        self.messages += 1
        message = {"content": content}
        usage = knob_lines("claude-turn-usage")
        if usage:
            cost, _, data = usage[min(self.messages, len(usage)) - 1].partition("\t")
            self.cost += float(cost)
            message.update(id=f"msg_{self.sid[:8]}_{self.messages}", usage=json.loads(data))
            for k in TOKEN_KEYS:
                self.tokens[k] += int(message["usage"].get(k, 0))
            if knob("claude-model"):
                message["model"] = knob_lines("claude-model")[0]
        else:
            self.cost += float(knob_lines("claude-cost-per-turn")[0]) if knob("claude-cost-per-turn") else 0.05
        if knob("claude-split-turns"):
            emit({"type": "assistant", "parent_tool_use_id": parent, "session_id": self.sid,
                  "message": dict(message, content=[{"type": "text", "text": "working"}])})
        emit({"type": "assistant", "parent_tool_use_id": parent, "session_id": self.sid, "message": message})


def load_sandbox(settings_path, cwd):
    """The sandbox the --settings file asks for, with the working directory's
    .claude/settings.json merged in under claude-sandbox-repo-widens; None
    when the sandbox is off."""
    def block(path):
        try:
            with open(path, encoding="utf-8") as f:
                return (json.load(f) or {}).get("sandbox") or {}
        except (OSError, ValueError):
            return {}
    sb = block(settings_path) if settings_path else {}
    if not sb.get("enabled"):
        return None
    blocks = [sb]
    if knob("claude-sandbox-repo-widens"):
        repo = block(os.path.join(cwd, ".claude", "settings.json"))
        keys = knob_lines("claude-sandbox-repo-widens")
        blocks.append({k: v for k, v in repo.items() if not keys or k in keys})
    out = {"deny_read": [], "allow_write": [], "hosts": [], "excluded": [], "deny_env": [],
           "allow_unsandboxed": False}
    for b in blocks:
        if "allowUnsandboxedCommands" in b:
            out["allow_unsandboxed"] = bool(b["allowUnsandboxedCommands"])
        fs, net, cred = b.get("filesystem") or {}, b.get("network") or {}, b.get("credentials") or {}
        out["deny_read"] += fs.get("denyRead") or []
        out["deny_read"] += [f["path"] for f in cred.get("files") or [] if f.get("mode") == "deny"]
        out["allow_write"] += fs.get("allowWrite") or []
        out["hosts"] += net.get("allowedDomains") or []
        out["excluded"] += b.get("excludedCommands") or []
        out["deny_env"] += [v["name"] for v in cred.get("envVars") or [] if v.get("mode") == "deny"]
    return out


def expand(command_file, arguments, cwd, root):
    with open(command_file, encoding="utf-8") as f:
        text = f.read()
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        text = text[end + 5:] if end >= 0 else text
    text = text.replace("$ARGUMENTS", arguments)
    match = (knob_lines("claude-bang-match") or [None])[0]
    out, pos = [], 0
    for m in re.finditer(r"^```!\n(.*?)^```\n?", text, re.DOTALL | re.MULTILINE):
        out.append(text[pos:m.start()])
        body = m.group(1)
        if knob("claude-no-bang") or (match and match not in body):
            out.append(m.group(0))
        else:
            r = subprocess.run(["bash", "-c", body], capture_output=True, text=True, cwd=cwd,
                               env=dict(os.environ, CLAUDE_PLUGIN_ROOT=root), stdin=subprocess.DEVNULL, check=False)
            out.append(r.stdout)
        pos = m.end()
    out.append(text[pos:])
    return "".join(out)


def main(argv):
    if argv[:1] == ["--version"]:
        print("2.1.322 (Claude Code)")
        return 0
    with open(os.path.join(HERE, "claude-launches.log"), "a", encoding="utf-8") as f:
        f.write(" ".join(argv) + "\n")
    with open(os.path.join(HERE, "claude-launches.log"), encoding="utf-8") as f:
        n = sum(1 for _ in f)
    prompt = sys.stdin.read()
    with open(os.path.join(HERE, f"claude-prompt-{n}.txt"), "w", encoding="utf-8") as f:
        f.write(prompt)
    if knob("claude-no-events"):
        print("Invalid API key · Please run /login", file=sys.stderr)
        return 1
    opts = parse(argv)
    cwd = os.getcwd()
    s = Session(opts, cwd)
    sessions = os.path.join(HERE, "sessions")
    os.makedirs(sessions, exist_ok=True)
    state = {"steps": [], "ran": [], "command": None, "arguments": "", "root": None, "cost": 0.0}
    resumed = opts.get("--resume") or opts.get("-r")
    if resumed and knob("claude-resume-lost"):
        print(f"No conversation found with session ID: {resumed}", file=sys.stderr)
        return 1
    if resumed and knob("claude-resume-fresh"):
        resumed = None
        s.sid = str(uuid.uuid4())
    elif resumed:
        try:
            with open(os.path.join(sessions, resumed + ".json"), encoding="utf-8") as f:
                state = json.load(f)
        except OSError:
            print(f"No conversation found with session ID: {resumed}", file=sys.stderr)
            return 1
        s.sid = str(uuid.uuid4()) if opts["fork"] else resumed
    else:
        s.sid = opts.get("--session-id") or str(uuid.uuid4())
    init = {"type": "system", "subtype": "init", "session_id": s.sid, "cwd": cwd,
            "permissionMode": opts.get("--permission-mode", "default")}
    if knob("claude-model"):
        init["model"] = knob_lines("claude-model")[0]
    if knob("claude-init-tools"):
        with open(os.path.join(HERE, "claude-init-tools"), encoding="utf-8") as f:
            init["tools"] = json.load(f)
    else:
        allowed = (opts.get("--tools") or opts.get("--allowedTools") or opts.get("--allowed-tools")
                   or "Bash,Read,Write,Edit")
        init["tools"] = [t.strip() for t in allowed.split(",") if t.strip()]
    if not knob("claude-init-no-plugins"):
        plugins, commands = [], []
        for root in s.plugins:
            name = plugin_name(root)
            plugins.append({"name": name, "path": root})
            cdir = os.path.join(root, "commands")
            if os.path.isdir(cdir):
                commands += [f"{name}:{c[:-3]}" for c in sorted(os.listdir(cdir)) if c.endswith(".md")]
        if knob("claude-plugins-extra"):
            with open(os.path.join(HERE, "claude-plugins-extra"), encoding="utf-8") as f:
                extra = json.load(f)
            if knob("claude-plugin-dir-overrides"):
                taken = {p["name"] for p in plugins}
                extra = [p for p in extra if p.get("name") not in taken]
            plugins += extra
        init["plugins"] = plugins
        init["slash_commands"] = commands
    emit(init)
    s.hooks("SessionStart", {"source": "resume" if resumed else "startup"})
    if knob("claude-api-error") or any(x in prompt for x in knob_lines("claude-api-error-when")):
        # Claude Code 2.1.323's own events when the account's usage limit is
        # reached: a synthetic assistant message and an is_error result of
        # subtype success that cost nothing.
        said = "You've hit your limit · resets 4pm. Switch to another model to continue."
        emit({"type": "assistant", "session_id": s.sid, "error": "rate_limit", "is_api_error_message": True,
              "api_error_status": 429, "api_error": "usage_limit_reached",
              "message": {"model": "<synthetic>", "role": "assistant", "content": [{"type": "text", "text": said}]}})
        emit({"type": "result", "subtype": "success", "is_error": True, "num_turns": 1, "session_id": s.sid,
              "total_cost_usd": 0, "usage": {}, "modelUsage": {}, "permission_denials": [],
              "terminal_reason": "api_error", "api_error_status": 429, "api_error_origin": "first_party",
              "api_error": "usage_limit_reached", "result": said})
        s.hooks("SessionEnd", {"reason": "other"})
        return 0
    if os.path.exists(os.path.join(HERE, "claude-script")):
        with open(os.path.join(HERE, "claude-script.out"), "a", encoding="utf-8") as out:
            subprocess.run(["bash", os.path.join(HERE, "claude-script")], stdout=out, stderr=out, cwd=cwd, check=False)
    if resumed:
        if knob("claude-rerun-bang-on-resume") and state.get("command"):
            expand(state["command"], state["arguments"], cwd, state["root"])
        if knob("claude-cumulative-cost"):
            s.cost = state.get("cost", 0.0)
        steps = state["steps"]
    else:
        text = prompt
        m = re.match(r"^/([A-Za-z0-9_-]+):([A-Za-z0-9_-]+)\s*(.*)$", prompt.strip(), re.DOTALL)
        if m:
            for root in s.plugins:
                path = os.path.join(root, "commands", m.group(2) + ".md")
                if plugin_name(root) == m.group(1) and os.path.isfile(path):
                    text = expand(path, m.group(3), cwd, root)
                    state.update(command=path, arguments=m.group(3), root=root)
                    emit({"type": "user", "session_id": s.sid,
                          "message": {"content": [{"type": "text", "text": text}]}})
                    break
        steps = [ln.strip() for ln in text.splitlines() if STEP.match(ln.strip())]
    start_cost = s.cost
    max_turns = int(opts.get("--max-turns", "1000"))
    budget = float(opts.get("--max-budget-usd", "1000"))
    subtype = "success"
    base_tokens = state.get("tokens") or {}
    path = os.path.join(sessions, s.sid + ".json")

    def save(rest):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(dict(state, steps=rest, cost=s.cost,
                           tokens={k: base_tokens.get(k, 0) + s.tokens[k] for k in TOKEN_KEYS}), f)

    rest = list(steps)
    save(rest)
    while rest:
        if s.turns >= max_turns:
            subtype = "error_max_turns"
            break
        line = rest.pop(0)
        save(rest)
        if any(x in line for x in knob_lines("claude-skip-steps")):
            continue
        sub, kind, arg = STEP.match(line).groups()
        result = s.step(bool(sub), kind, arg)
        if kind == "RUN":
            state["ran"] = state.get("ran", []) + [arg]
        if (kind == "RUN" and "<sandbox_violations>" in result
                and any(x in line for x in knob_lines("claude-retry-unsandboxed"))):
            result = s.step(bool(sub), kind, arg, unsandboxed=True)
        if kind == "RUN" and any(x in line for x in knob_lines("claude-rerun-changed")):
            s.step(bool(sub), kind, arg, rerun=True)
        repeat = knob_lines("claude-repeat-while")
        if kind == "RUN" and repeat and re.search(repeat[0], result):
            rest.insert(0, line)
        save(rest)
        if s.cost > budget:
            subtype = "error_max_budget_usd"
            break
    if not steps:
        s.turns = 1
        reply = (state.get("ran") or ["none"])[-1] if "last command you ran" in prompt else "ok"
        s.assistant([{"type": "text", "text": reply}])
        save(rest)
    elif subtype == "success" and knob("claude-final-text"):
        s.turns += 1
        s.assistant([{"type": "text", "text": knob_lines("claude-final-text")[0]}])
        save(rest)
    s.hooks("Stop", {"stop_hook_active": False})
    if any(x in prompt for x in knob_lines("claude-error-when")):
        subtype = "error_during_execution"
    result = {"type": "result", "subtype": subtype, "is_error": subtype != "success", "num_turns": s.turns,
              "session_id": s.sid, "total_cost_usd": round(s.cost, 7), "permission_denials": s.denials}
    if any(x in prompt for x in knob_lines("claude-no-cost-when")):
        del result["total_cost_usd"]
    usage = knob("claude-turn-usage")
    if usage:
        result["usage"] = dict(s.tokens)
    if knob("claude-model"):
        result["modelUsage"] = {knob_lines("claude-model")[0]: {"costUSD": round(s.cost, 7)}}
        if usage:
            total = dict(s.tokens)
            if resumed and knob("claude-cumulative-usage"):
                total = {k: base_tokens.get(k, 0) + s.tokens[k] for k in TOKEN_KEYS}
            if knob("claude-usage-extra"):
                total["input_tokens"] += int(knob_lines("claude-usage-extra")[0])
            result["modelUsage"][knob_lines("claude-model")[0]].update(
                {m: total[k] for k, m in zip(TOKEN_KEYS, MODEL_USAGE_KEYS)})
    if knob("claude-since-last"):
        model = (knob_lines("claude-model") or [opts.get("--model") or "claude-opus-5-5"])[0]
        result["model_usage_since_last_result"] = {model: {"costUSD": round(s.cost - start_cost, 7)}}
        earlier = knob_lines("claude-since-last")
        if resumed and earlier:
            reported = round(s.cost + float(earlier[0]), 7)
            if "total_cost_usd" in result:
                result["total_cost_usd"] = reported
            if model in result.get("modelUsage", {}):
                result["modelUsage"][model]["costUSD"] = reported
    emit(result)
    s.hooks("SessionEnd", {"reason": "other"})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
