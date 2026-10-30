# shellcheck shell=bash
# End-to-end: every ```bash fence in flow's own commands, skills and
# references, through the tier hook (hooks/scripts/tier-gate.sh), as an agent
# following those documents would run it.
#
# Flow's commands are run block by block from these fences. A tier hook that
# asks about a fence that merges nothing, releases nothing and pushes no tag
# makes every flow command prompt: a rule meant for commands an agent writes
# by hand lands on the plugin's own code. This file pins the decision for
# every fence, so a change to the hook that makes a quiet fence ask, or an
# asking one quiet, fails here first.
#
# Ways it can be wrong, written down before the scenario:
#   F1 a fence that only reads (gh pr view, gh repo view, cat release.md) or
#      assigns a substitution (`D=$(gh repo view ...)`) asks
#   F2 a fence that merges, creates a release or pushes a possible tag does
#      not ask
#   F3 the fences are not found (a broken extractor reads none, and "every
#      fence silent" passes on nothing)
#
# The expected asks are listed by file and the fence's ordinal in that file
# (1 for its first ```bash fence). Each is a merge, a release, or a push that
# may send a tag:
#   commands/merge.md#1                    gh pr merge
#   commands/release.md#2                  pushes the release branch (git push -u origin $RELEASE_BRANCH)
#   commands/release.md#3                  pushes the release tag
#   commands/release.md#4                  gh release create
#   references/flow-triggers-quickstart.md#3  pushes a branch the command creates
# Every other fence must be silent: no decision, exit 0. The scratch
# repository has no tier settings, so Tier 2 actions take their default
# (journal) and, with no journal directory, write nothing.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "tier gate fences: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

HOOK_TG=hooks/scripts/tier-gate.sh
TGF_EXPECT_ASK="
commands/merge.md#1
commands/release.md#2
commands/release.md#3
commands/release.md#4
references/flow-triggers-quickstart.md#3
"

_flow_test_begin "tier-gate-fences"
e2e_new tier-gate-fences
e2e_describe "every bash fence in flow's commands, skills and references through the tier hook: the five that merge, release or may push a tag ask, every other fence is silent (F1, F2, F3)"
e2e_repo feature/fences

# One file per fence, named <relative path>#<ordinal>: the text from a
# "```bash" line end to the next "```", indented fences included, as an agent
# copies it.
TGF_DIR="$E2E_DIR/fences"
mkdir -p "$TGF_DIR"
python3 -I - "$E2E_ACTIVE_PLUGIN" "$TGF_DIR" <<'PY' || _flow_assert_fail "tier-gate-fences: could not read the fences"
import glob, os, re, sys
root, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(root + "/commands/*.md") + glob.glob(root + "/skills/*/SKILL.md")
               + glob.glob(root + "/references/*.md"))
for f in files:
    rel = os.path.relpath(f, root).replace("/", "%")
    for i, m in enumerate(re.finditer(r"```bash\n(.*?)```", open(f).read(), re.S), 1):
        with open(os.path.join(out, "%s#%d" % (rel, i)), "w") as w:
            w.write(m.group(1))
PY

TGF_N=0; TGF_ASKED=""
for TGF_P in "$TGF_DIR"/*; do
  [ -f "$TGF_P" ] || continue
  TGF_N=$((TGF_N + 1))
  TGF_KEY=$(basename "$TGF_P" | tr '%' '/')
  e2e_run_hook "$HOOK_TG" "$(jq -cn --rawfile c "$TGF_P" --arg cwd "$E2E_REPO" '{cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
  e2e_expect_equal 0 "$E2E_RC" "exit status for $TGF_KEY"
  TGF_GOT=$(printf '%s' "$E2E_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null)
  [ -n "$E2E_OUT" ] || TGF_GOT=silent
  case "$TGF_EXPECT_ASK" in
    *"
$TGF_KEY
"*) e2e_expect_equal ask "$TGF_GOT" "decision for $TGF_KEY" ;;
    *) e2e_expect_equal silent "$TGF_GOT" "decision for $TGF_KEY" ;;
  esac
  [ "$TGF_GOT" = ask ] && TGF_ASKED="$TGF_ASKED $TGF_KEY"
done
# F3: flow ships well over a hundred fences; finding a handful means the
# extractor broke, not that the hook is quiet.
e2e_expect_equal yes "$([ "$TGF_N" -ge 100 ] && echo yes || echo no)" "fences found ($TGF_N)"
printf 'fences: %s; asked:%s\n' "$TGF_N" "$TGF_ASKED" | _e2e_art
e2e_expect_clean_edges
