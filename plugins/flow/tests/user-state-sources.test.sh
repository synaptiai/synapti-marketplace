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
use = re.compile(r'(?<!\\)\$\{?(FLOW_STATE_DIR|FLOW_USER_SETTINGS)\b|environ(\.get)?\(\s*["\'](FLOW_STATE_DIR|FLOW_USER_SETTINGS)|environ\[["\'](FLOW_STATE_DIR|FLOW_USER_SETTINGS)')
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
                # In a command or skill file only a bash or sh fence is code;
                # the prose and the output templates around it may name the
                # variables.
                if n.endswith(".md"):
                    s = line.strip()
                    if s.startswith("```"):
                        fenced = (not fenced) and s[3:].strip() in ("bash", "sh")
                        continue
                    if not fenced:
                        continue
                code = line.split("#", 1)[0] if n.endswith((".sh", ".py")) else line
                if use.search(code):
                    if rel == "bin/_repo_dir.py" and 'os.environ.get("FLOW_STATE_DIR")' in code and "if " in code:
                        continue
                    out.append("%s:%d: %s" % (rel, i, line.strip()[:120]))
print("\n".join(out))
PY
}
READERS=$(_uss_scan)
assert_equal "" "$READERS" "code that expands FLOW_STATE_DIR or FLOW_USER_SETTINGS outside the resolver"

_flow_test_begin "the documentation says who may set FLOW_STATE_DIR and FLOW_USER_SETTINGS"
README=$(cat "$FLOW_DIR/README.md")
assert_contains "### Per-user locations" "$README" "the README has the section the other documents link to"
assert_contains "A repository cannot set them" "$README" "and says a repository cannot set them"
assert_contains "prints one warning naming the variable and the reason, never the value or what it names, and uses the default" "$README" "and what happens when one does"
assert_contains "Set them yourself, in your shell or in \`~/.claude/settings.json\`'s \`env\` block" "$README" "and which sources may set them"
assert_contains "is ignored ([README: Per-user locations]" "$(cat "$FLOW_DIR/references/stop-hook-goal-enforcement.md")" "the Stop hook reference points there for the trust ledger"
