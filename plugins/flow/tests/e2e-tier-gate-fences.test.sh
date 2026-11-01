# shellcheck shell=bash
# End-to-end: every ```bash and ```! fence in flow's own commands, skills and
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
# A ```! fence is run by Claude Code itself when the command loads, with
# $ARGUMENTS replaced by the command's arguments (12 here). The PreToolUse
# hook may not see those runs at all; they are read here as a guard that
# flow's own load-time blocks would not ask if it did.
#
# Ways it can be wrong, written down before the scenario:
#   F1 a fence that only reads (gh pr view, gh repo view, cat release.md) or
#      assigns a substitution (`D=$(gh repo view ...)`) asks
#   F2 a fence that merges, creates a release or pushes a possible tag does
#      not ask
#   F3 the fences are not found (a broken extractor reads none, and "every
#      fence silent" passes on nothing)
#   F4 an expected ask names the wrong fence: the list below goes stale when a
#      fence is added before it, and the ask then pins a different block
#
# The expected asks are listed by file and the fence's ordinal in that file
# among fences of its kind (#1 for its first ```bash fence, !1 for its first
# ```! fence), each with text the fence must hold (F4). Each is a merge, a
# release, a push that may send a tag, or a call the hook cannot read:
#   commands/merge.md#1       gh pr merge
#   commands/release.md#4     pushes the release tag (git push origin "$TAG")
#   commands/release.md#5     gh release create, for a tag already on origin
#   commands/merge.md!2       a GraphQL query of review threads written in
#                             double quotes with $OWNER, $NAME and $PR_NUM in
#                             it: what bash expands there could make it a
#                             mutation, so the hook cannot read it and asks
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
# <fence key>|<text the fence holds>
TGF_EXPECT_ASK="
commands/merge.md#1|gh pr merge
commands/release.md#4|git push origin \"\$TAG\"
commands/release.md#5|gh release create
commands/merge.md!2|gh api graphql -f query=\"query {
"

_flow_test_begin "tier-gate-fences"
e2e_new tier-gate-fences
e2e_describe "every bash and ! fence in flow's commands, skills and references through the tier hook: the four that merge, release, may push a tag or cannot be read ask, each holding its action, and every other fence is silent (F1, F2, F3, F4)"
e2e_repo feature/fences

# One file per fence, named <relative path>#<ordinal> for a ```bash fence
# and <relative path>!<ordinal> for a ```! fence: the text from the fence's
# line end to the next "```", indented fences included, as it is run.
TGF_DIR="$E2E_DIR/fences"
mkdir -p "$TGF_DIR"
python3 -I - "$E2E_ACTIVE_PLUGIN" "$TGF_DIR" <<'PY' || _flow_assert_fail "tier-gate-fences: could not read the fences"
import glob, os, re, sys
root, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(root + "/commands/*.md") + glob.glob(root + "/skills/*/SKILL.md")
               + glob.glob(root + "/references/*.md"))
for f in files:
    rel = os.path.relpath(f, root).replace("/", "%")
    text = open(f).read()
    for kind, sep in (("bash", "#"), ("!", "!")):
        for i, m in enumerate(re.finditer(r"```" + re.escape(kind) + r"\n(.*?)```", text, re.S), 1):
            body = m.group(1)
            if kind == "!":
                body = body.replace("$ARGUMENTS", "12")
            with open(os.path.join(out, "%s%s%d" % (rel, sep, i)), "w") as w:
                w.write(body)
PY

TGF_N=0; TGF_NB=0; TGF_ASKED=""
for TGF_P in "$TGF_DIR"/*; do
  [ -f "$TGF_P" ] || continue
  TGF_KEY=$(basename "$TGF_P" | tr '%' '/')
  case "$TGF_KEY" in *'!'*) TGF_NB=$((TGF_NB + 1)) ;; *) TGF_N=$((TGF_N + 1)) ;; esac
  e2e_run_hook "$HOOK_TG" "$(jq -cn --rawfile c "$TGF_P" --arg cwd "$E2E_REPO" '{cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
  e2e_expect_equal 0 "$E2E_RC" "exit status for $TGF_KEY"
  TGF_GOT=$(printf '%s' "$E2E_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null)
  [ -n "$E2E_OUT" ] || TGF_GOT=silent
  TGF_LINE=$(printf '%s\n' "$TGF_EXPECT_ASK" | grep -F -- "$TGF_KEY|" | head -n 1)
  if [ -n "$TGF_LINE" ]; then
    e2e_expect_equal ask "$TGF_GOT" "decision for $TGF_KEY"
    TGF_ACT="${TGF_LINE#*|}"
    e2e_expect_equal yes "$(grep -qF -- "$TGF_ACT" "$TGF_P" && echo yes || echo no)" "$TGF_KEY holds: $TGF_ACT"
  else
    e2e_expect_equal silent "$TGF_GOT" "decision for $TGF_KEY"
  fi
  [ "$TGF_GOT" = ask ] && TGF_ASKED="$TGF_ASKED $TGF_KEY"
done
# Each expected ask was found among the fences.
while IFS='|' read -r TGF_KEY TGF_ACT; do
  [ -n "$TGF_KEY" ] || continue
  case " $TGF_ASKED " in *" $TGF_KEY "*) TGF_FOUND=yes ;; *) TGF_FOUND=no ;; esac
  e2e_expect_equal yes "$TGF_FOUND" "an ask for $TGF_KEY"
done <<EOF
$TGF_EXPECT_ASK
EOF
# F3: flow ships well over a hundred bash fences and dozens of ! fences;
# finding a handful means the extractor broke, not that the hook is quiet.
e2e_expect_equal yes "$([ "$TGF_N" -ge 100 ] && echo yes || echo no)" "bash fences found ($TGF_N)"
e2e_expect_equal yes "$([ "$TGF_NB" -ge 40 ] && echo yes || echo no)" "! fences found ($TGF_NB)"
printf 'fences: %s bash, %s !; asked:%s\n' "$TGF_N" "$TGF_NB" "$TGF_ASKED" | _e2e_art
e2e_expect_clean_edges
