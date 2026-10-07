# Only bin/cascade-resolve.sh decides where Flow keeps the user's own state and
# which settings file is the user's (#274): FLOW_STATE_DIR and
# FLOW_USER_SETTINGS are taken only when the user, not the repository, chose
# them. A script that read either variable itself would skip that rule, so
# this test fails when any code outside the resolver expands one. The
# behaviour itself is shown end to end by e2e-goal-stuck.test.sh
# (state-dir-from-repo, state-dir-from-user), e2e-system-one.test.sh
# (user-settings-from-repo) and cascade-resolve.test.sh.

FLOW_DIR="$REPO_ROOT/plugins/flow"

_flow_test_begin "no script outside cascade-resolve.sh reads FLOW_STATE_DIR or FLOW_USER_SETTINGS"
# Code lines only: a comment may name the variables. _repo_dir.py asks the
# resolver, and only looks at whether FLOW_STATE_DIR is set.
# A function, not a $( ) around the heredoc: bash 3.2 reads the text of a
# $( ) as shell to find its closing parenthesis, heredoc body included.
_uss_scan() {
python3 - "$FLOW_DIR" <<'PY'
import os, re, sys
root = sys.argv[1]
use = re.compile(r'(?<!\\)\$\{?!?(FLOW_STATE_DIR|FLOW_USER_SETTINGS)\b|(environ\.get|getenv)\(\s*["\'](FLOW_STATE_DIR|FLOW_USER_SETTINGS)|environ\[["\'](FLOW_STATE_DIR|FLOW_USER_SETTINGS)|printenv\s+(FLOW_STATE_DIR|FLOW_USER_SETTINGS)')
allowed = {"bin/cascade-resolve.sh"}
out = []
for sub in ("bin", "hooks", "commands", "skills", "agents"):
    for dirpath, _, names in os.walk(os.path.join(root, sub)):
        for n in names:
            path = os.path.join(dirpath, n)
            rel = os.path.relpath(path, root)
            if rel in allowed or not n.endswith((".sh", ".py", ".md")):
                continue
            fenced = False
            for i, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                # In a command or skill file only a bash, sh or ! fence is code;
                # the prose and the output templates around it may name the
                # variables.
                if n.endswith(".md"):
                    s = line.strip()
                    if s.startswith("```"):
                        fenced = (not fenced) and s[3:].strip() in ("bash", "sh", "!")
                        continue
                    if not fenced:
                        continue
                # A comment starts at a # at the line's start or after a space;
                # ${x#...} and "#" in a string are code.
                code = re.split(r"(?:^|\s)#", line, maxsplit=1)[0] if n.endswith((".sh", ".py")) else line
                if use.search(code):
                    if rel == "bin/_repo_dir.py" and 'os.environ.get("FLOW_STATE_DIR")' in code and "if " in code:
                        continue
                    out.append("%s:%d: %s" % (rel, i, line.strip()[:120]))
print("\n".join(out))
PY
}
READERS=$(_uss_scan)
assert_equal "" "$READERS" "code that expands FLOW_STATE_DIR or FLOW_USER_SETTINGS outside the resolver"

_flow_test_begin "no script outside cascade-resolve.sh reads HOME through \$HOME, getenv, expanduser or Path.home"
# A repository can set HOME through its settings' env block, so Flow's own
# per-user files are found under the home cascade-resolve.sh --user-home gives.
# Allowed: the resolver; _repo_dir.py comparing HOME with the user database's
# home before it asks the resolver; and the plugin lookup
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/..., which finds the plugin, not
# the user's files, and tries the repository's own plugins/flow first anyway.
_uss_home_scan() {
python3 - "$FLOW_DIR" <<'PY'
import os, re, sys
root = sys.argv[1]
use = re.compile(r'(?<![\\A-Za-z_])\$\{?HOME\b|(environ\.get|getenv)\(\s*["\']HOME["\']|environ\[["\']HOME["\']|expanduser|Path\.home')
lookup = "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
out = []
for sub in ("bin", "hooks", "commands", "skills", "agents"):
    for dirpath, _, names in os.walk(os.path.join(root, sub)):
        for n in names:
            path = os.path.join(dirpath, n)
            rel = os.path.relpath(path, root)
            if rel == "bin/cascade-resolve.sh" or not n.endswith((".sh", ".py", ".md")):
                continue
            fenced = False
            for i, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                if n.endswith(".md"):
                    s = line.strip()
                    if s.startswith("```"):
                        fenced = (not fenced) and s[3:].strip() in ("bash", "sh", "!")
                        continue
                    if not fenced:
                        continue
                # Comments are prose here, in a fence as in a script.
                code = re.split(r"(?:^|\s)#", line, maxsplit=1)[0]
                code = code.replace(lookup, "")
                if not use.search(code):
                    continue
                if rel == "bin/_repo_dir.py" and code.strip() == 'home = os.environ.get("HOME")':
                    continue
                out.append("%s:%d: %s" % (rel, i, line.strip()[:120]))
print("\n".join(out))
PY
}
HOME_READERS=$(_uss_home_scan)
assert_equal "" "$HOME_READERS" "code that reads HOME that way outside the resolver (~ and a bare cd are not scanned)"

_flow_test_begin "the documentation says who may set FLOW_STATE_DIR and FLOW_USER_SETTINGS"
README=$(cat "$FLOW_DIR/README.md")
assert_contains "### Per-user locations" "$README" "the README has the section the other documents link to"
assert_contains "A repository cannot set them" "$README" "and says a repository cannot set them"
assert_contains "prints one warning naming the variable and the reason, never the value or what it names, and uses the default" "$README" "and what happens when one does"
assert_contains "Set them yourself, in your shell or in \`~/.claude/settings.json\`'s \`env\` block" "$README" "and which sources may set them"
assert_contains "is ignored ([README: Per-user locations]" "$(cat "$FLOW_DIR/references/stop-hook-goal-enforcement.md")" "the Stop hook reference points there for the trust ledger"

_flow_test_begin "_repo_dir.py: a HOME the repository sets is not a per-user root, also for a user the user database has no entry for"
# A container run under a bare uid has no user database entry. The bash
# resolver then ignores a HOME the repository set; the Python side must agree,
# or <repo>/h/.claude would be per-user and exempt from the repository rule.
USS_R=$(mktemp -d "${TMPDIR:-/tmp}/uss-home.XXXXXX")
USS_R=$(cd "$USS_R" && pwd -P)
mkdir -p "$USS_R/repo/.claude" "$USS_R/repo/h/.claude"
( cd "$USS_R/repo" && git init -q . ) >/dev/null 2>&1
# _uss_roots: the per-user roots _repo_dir.py gives from the repository, with
# HOME at h/ and pwd.getpwuid raising KeyError.
# The interpreter itself, not the python3 found on PATH: a version manager's
# shim is a bash script, which cannot start once PATH holds no bash.
USS_PY=$(python3 -c 'import sys; print(sys.executable)')
_uss_roots() {
  (cd "$USS_R/repo" && env -u FLOW_STATE_DIR -u CLAUDE_PROJECT_DIR HOME="$USS_R/repo/h" ${USS_PATH:+PATH="$USS_PATH"} "$USS_PY" -I -c '
import pwd, sys
def _no_entry(uid):
    raise KeyError(uid)
pwd.getpwuid = _no_entry
sys.path.insert(0, sys.argv[1])
import _repo_dir
print("\n".join(_repo_dir._per_user_roots()))
' "$FLOW_DIR/bin")
}
OUT=$(_uss_roots)
assert_contains "$USS_R/repo/h/.claude" "$OUT" "control: a HOME the repository did not set is a per-user root"
# With no bash on PATH the resolver is still reached, as the shell scripts
# reach it through their own bash.
OUT=$(USS_PATH="$USS_R/nobin" _uss_roots)
assert_contains "$USS_R/repo/h/.claude" "$OUT" "and so it is with no bash on PATH"
printf '{"env":{"HOME":"%s"}}\n' "$USS_R/repo/h" > "$USS_R/repo/.claude/settings.json"
OUT=$(_uss_roots)
assert_not_contains "$USS_R/repo/h/.claude" "$OUT" "a HOME the repository set is not, though the user database has no entry"
chmod -R u+rwx "$USS_R" && rm -r "$USS_R"
