# shellcheck shell=bash
# End-to-end: /flow:watch issue <N> and /flow:watch branch, and the trigger
# templates they read.
#
# Each scenario runs the shipped watch.md fence in a scratch repository with
# the invocation's arguments substituted as Claude Code substitutes them, then
# checks the trigger YAML and the loop-prompt file it wrote: the trigger must
# validate against schemas/v1/trigger.schema.json and pass the trigger-policy
# rules (merge and release forbidden, no recursion). The fence writes files,
# so each shell runs in a fresh repository. One artifact per scenario is
# written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the code:
#   W1 a branch name with '/' or capitals goes into metadata.id unchanged, and
#      the id fails the schema's ^[a-z0-9][a-z0-9-]{0,63}$
#   W2 context.branch holds the slug rather than the real branch name, so the
#      loop watches a branch that does not exist
#   W3 the issue watch allows a write to GitHub or to the files (comment,
#      edit_issue, commit, push, edit_files) although it is read-only
#   W4 the branch watch allows the bare action `merge`, or does not forbid
#      force_push, rebase or delete_branch
#   W5 a closed issue still gets a watch
#   W6 an existing trigger is overwritten
#   W7 the template is read from plugins/flow/... under the working
#      directory, which a consumer repository does not have
#   W8 a branch name holding a quote breaks the YAML, or is written into it
#      unescaped
#   W9 with no setting, /flow:watch stops as if triggers were off
#      (flow.triggers.enabled ships true)
#   W10 the loop prompt leaves out the stop condition or the forbidden actions
#   W11 the branch watch is created on the default branch itself, where it has
#      nothing to merge in
#   W12 a template stops validating once its placeholders are filled
#   W13 a template's target.command is /flow:run itself, which /flow:run step 6
#      would dispatch again and again; the loop prompt must call /flow:run and
#      the target must be the work
#   W14 the issue loop's snapshot folder .flow/watch/ is not ignored, so the
#      working tree turns dirty on the first iteration
#   W15 a write that fails part way leaves a partial loop prompt or trigger
#   W16 a trigger schema that cannot be read or is not a valid schema stops
#      the script with a traceback, or reads as "cannot write", instead of a
#      refusal that names the schema

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

WATCH_MD="$E2E_PLUGIN_DIR/commands/watch.md"
SCHEMA="$E2E_PLUGIN_DIR/schemas/v1/trigger.schema.json"
ALL_SHELLS="$E2E_FENCE_SHELLS"

# _check_trigger <file under repo> <id> <context key=value ...> — the trigger
# validates against the schema and passes the trigger-policy rules; its id
# and context are the ones given. Prints one line per problem, nothing when
# all hold.
_check_trigger() {
  python3 - "$SCHEMA" "$E2E_REPO/$1" "$2" "${@:3}" <<'PY'
import json, sys, yaml
try:
    import jsonschema
except ImportError:
    jsonschema = None
schema_path, path, want_id, *ctx = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    doc = yaml.safe_load(f)
with open(schema_path, encoding="utf-8") as f:
    schema = json.load(f)
if jsonschema is None:
    print("jsonschema is not installed; the schema was not checked")
else:
    v = jsonschema.validators.validator_for(schema)(schema)
    for e in v.iter_errors(doc):
        print("schema: %s: %s" % ("/".join(map(str, e.path)) or "(root)", e.message))
if doc["metadata"]["id"] != want_id:
    print("id is %r, not %r" % (doc["metadata"]["id"], want_id))
forbidden = doc["policy"]["forbidden_actions"]
for a in ("merge", "release"):
    if a not in forbidden:
        print("policy: %s is not forbidden" % a)
if "merge" in doc["policy"]["allowed_actions"] or "release" in doc["policy"]["allowed_actions"]:
    print("policy: merge or release is allowed")
for k, val in (doc.get("recursion_policy") or {}).items():
    if val is not False:
        print("recursion: %s is %r" % (k, val))
if doc.get("target", {}).get("workflow"):
    print("target.workflow is set (%s); trigger-policy then needs that workflow to exist" % doc["target"]["workflow"])
for kv in ctx:
    k, _, val = kv.partition("=")
    got = doc.get("context", {}).get(k)
    if str(got) != val:
        print("context.%s is %r, not %r" % (k, got, val))
PY
}
# _policy <file under repo> <allowed|forbidden> — that list, space-separated.
_policy() {
  python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(" ".join(d["policy"][sys.argv[2] + "_actions"]))' "$E2E_REPO/$1" "$2"
}
_stops() {
  python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); print(" | ".join(d["stop_conditions"]))' "$E2E_REPO/$1"
}
_has_word() { case " $1 " in *" $2 "*) printf yes ;; *) printf no ;; esac; }

# _enabled — triggers turned on explicitly, as the symlink suites do.
_enabled() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"flow":{"triggers":{"enabled":true}}}' > "$E2E_REPO/.claude/settings.flow.json"
}
# _preflight — the pre-flight fence, which creates .flow/triggers and .claude.
_preflight() {
  e2e_run_fence "$WATCH_MD" 'flow.triggers.enabled' "$1"
}

_flow_test_begin "every shipped trigger template validates once its placeholders are filled (W12)"
TPL_DIR="$E2E_PLUGIN_DIR/triggers/templates"
for name in issue-watch branch-watch; do
  e2e_new "template-$name"
  e2e_describe "$name.trigger.yaml with ISSUE=42, BRANCH=feature/x, BRANCH_SLUG=feature-x"
  e2e_repo main
  mkdir -p "$E2E_REPO/t"
  sed -e 's/\${ISSUE}/42/g' -e 's|\${BRANCH_SLUG}|feature-x|g' -e 's|\${BRANCH}|feature/x|g' \
      -e 's|\${DEFAULT_BRANCH}|main|g' -e 's|\${REPO}|o/r|g' -e 's|\${NOW}|2026-10-29T12:00:00Z|g' \
      "$TPL_DIR/$name.trigger.yaml" > "$E2E_REPO/t/$name.yaml"
  if [ "$name" = issue-watch ]; then
    e2e_expect_equal "" "$(_check_trigger "t/$name.yaml" issue-42-watch issue=42 repo=o/r)" "problems in $name"
  else
    e2e_expect_equal "" "$(_check_trigger "t/$name.yaml" branch-feature-x-watch branch=feature/x repo=o/r default_branch=main)" "problems in $name"
  fi
  e2e_expect_equal "" "$(grep -nE '[$][{][A-Z][A-Z_]*[}]' "$E2E_REPO/t/$name.yaml")" "placeholders left in $name"
done

_flow_test_begin "no shipped template's target.command runs /flow:run (W13)"
e2e_new template-targets
e2e_describe "target.command of every triggers/templates/*.trigger.yaml"
e2e_repo main
TARGETS=$(python3 -c '
import glob, os, sys, yaml
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.trigger.yaml"))):
    d = yaml.safe_load(open(p, encoding="utf-8"))
    print("%s %s" % (os.path.basename(p), d["target"]["command"]))' "$TPL_DIR")
e2e_expect_equal 5 "$(printf '%s\n' "$TARGETS" | grep -c .)" "templates read"
e2e_expect_equal "" "$(printf '%s\n' "$TARGETS" | grep "^[^ ]* /flow:run" )" "templates whose target runs /flow:run"
e2e_expect_equal "pr-watch.trigger.yaml /flow:address \${PR}" "$(printf '%s\n' "$TARGETS" | grep '^pr-watch')" "pr-watch's target"
e2e_expect_equal "issue-watch.trigger.yaml /flow:status" "$(printf '%s\n' "$TARGETS" | grep '^issue-watch')" "issue-watch's target"
e2e_expect_equal "branch-watch.trigger.yaml /flow:resolve \${BRANCH}" "$(printf '%s\n' "$TARGETS" | grep '^branch-watch')" "branch-watch's target"

_flow_test_begin ".flow/watch/ is ignored by /flow:setup's ignore lines and by this repository (W14)"
e2e_new setup-ignores-watch
e2e_describe "the /flow:setup .gitignore block run in a repository with no .gitignore"
e2e_repo main
e2e_run_fence "$E2E_PLUGIN_DIR/commands/setup.md" 'for IGNORE in'
e2e_expect_file_has .gitignore ".flow/watch/"
e2e_expect_equal ".flow/watch/" "$(grep -x '.flow/watch/' "$REPO_ROOT/.gitignore")" "the repository's own .gitignore line"

_flow_test_begin "/flow:watch pre-flight: no setting means triggers are on (W9)"
e2e_new watch-preflight-default
e2e_describe "no flow settings at all, and a plugin settings.json without the key, so the command's own fallback decides"
e2e_repo main
e2e_plugin_copy settings.json '{}'
_preflight 'issue 42'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_no_out "opt-in"
e2e_expect_no_out "is false"
e2e_expect_equal "yes" "$( [ -d "$E2E_REPO/.flow/triggers" ] && printf yes )" ".flow/triggers exists"
e2e_expect_line "TEMPLATE_DIR=$E2E_ACTIVE_PLUGIN/triggers/templates"

e2e_new watch-preflight-off
e2e_describe "flow.triggers.enabled is false in the repository settings"
e2e_repo main
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"triggers":{"enabled":false}}}' > "$E2E_REPO/.claude/settings.flow.json"
_preflight 'issue 42'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "flow.triggers.enabled is false"
e2e_expect_equal "" "$( [ -d "$E2E_REPO/.flow" ] && printf exists )" ".flow afterwards"

_flow_test_begin "/flow:watch issue 42: trigger and loop prompt, read-only on GitHub (W3, W7, W10)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "watch-issue-$E2E_FENCE_SHELLS"
  e2e_describe "issue 42 is open; run under $E2E_FENCE_SHELLS from a repository with no plugins/flow"
  e2e_repo main
  _enabled
  _preflight 'issue 42'
  e2e_gh_fixture repo '{"nameWithOwner":"octo/demo","defaultBranchRef":{"name":"main"}}'
  e2e_gh_fixture issue-42 '{"number":42,"state":"OPEN","title":"Search fails"}'
  e2e_run_fence "$WATCH_MD" 'WATCH_ISSUE_BLOCK_BEGIN' 'issue 42'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "WATCH_STATE=created"
  e2e_expect_line "TRIGGER_FILE=.flow/triggers/issue-42-watch.trigger.yaml"
  e2e_expect_line "LOOP_FILE=.claude/flow-loop-issue-42-watch.md"
  e2e_expect_equal "" "$(_check_trigger .flow/triggers/issue-42-watch.trigger.yaml issue-42-watch issue=42 repo=octo/demo)" "problems in the trigger"
  forb=$(_policy .flow/triggers/issue-42-watch.trigger.yaml forbidden)
  allow=$(_policy .flow/triggers/issue-42-watch.trigger.yaml allowed)
  for a in comment edit_issue commit push edit_files; do
    e2e_expect_equal "yes no" "$(_has_word "$forb" "$a") $(_has_word "$allow" "$a")" "$a forbidden and not allowed"
  done
  e2e_expect_equal "issue_state == closed" "$(_stops .flow/triggers/issue-42-watch.trigger.yaml)" "the stop condition"
  e2e_expect_file_has .flow/watch/.gitignore "*"
  e2e_expect_equal "" "$( _e2e_git_env; cd "$E2E_REPO" && printf '{}\n' > .flow/watch/issue-42.json && git status --porcelain -- .flow/watch)" "untracked files under .flow/watch"
  e2e_expect_file_has .claude/flow-loop-issue-42-watch.md "/flow:run trigger issue-42-watch"
  e2e_expect_file_has .claude/flow-loop-issue-42-watch.md "issue #42"
  e2e_expect_file_has .claude/flow-loop-issue-42-watch.md "/flow:start 42"
  e2e_expect_file_has .claude/flow-loop-issue-42-watch.md "Stop when the issue is closed"
  e2e_expect_file_has .claude/flow-loop-issue-42-watch.md "read-only on GitHub"
  e2e_expect_equal "" "$(grep -nE '[$][{][A-Z][A-Z_]*[}]' "$E2E_REPO/.claude/flow-loop-issue-42-watch.md")" "placeholders left in the loop prompt"
  e2e_expect_clean_edges
done
E2E_FENCE_SHELLS="$ALL_SHELLS"

_flow_test_begin "/flow:watch issue: a second run keeps the existing trigger (W6)"
e2e_new watch-issue-exists
e2e_describe "a trigger for issue 42 already exists with a marker line"
e2e_repo main
_enabled
_preflight 'issue 42'
printf '# kept\n' > "$E2E_REPO/.flow/triggers/issue-42-watch.trigger.yaml"
e2e_gh_fixture repo '{"nameWithOwner":"octo/demo","defaultBranchRef":{"name":"main"}}'
e2e_gh_fixture issue-42 '{"number":42,"state":"OPEN","title":"Search fails"}'
e2e_run_fence "$WATCH_MD" 'WATCH_ISSUE_BLOCK_BEGIN' 'issue 42'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "WATCH_STATE=exists"
e2e_expect_file_has .flow/triggers/issue-42-watch.trigger.yaml "# kept"

_flow_test_begin "/flow:watch issue: a closed issue, or no number, gets no watch (W5)"
e2e_new watch-issue-closed
e2e_describe "issue 42 is closed"
e2e_repo main
_enabled
_preflight 'issue 42'
e2e_gh_fixture repo '{"nameWithOwner":"octo/demo","defaultBranchRef":{"name":"main"}}'
e2e_gh_fixture issue-42 '{"number":42,"state":"CLOSED","title":"Search fails"}'
e2e_run_fence "$WATCH_MD" 'WATCH_ISSUE_BLOCK_BEGIN' 'issue 42'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "WATCH_STATE=refused"
e2e_expect_out "closed"
e2e_expect_equal "" "$(ls "$E2E_REPO/.flow/triggers")" "files in .flow/triggers"

e2e_new watch-issue-no-number
e2e_describe "run as /flow:watch issue abc"
e2e_repo main
_enabled
_preflight 'issue abc'
e2e_run_fence "$WATCH_MD" 'WATCH_ISSUE_BLOCK_BEGIN' 'issue abc'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "WATCH_STATE=refused"
e2e_expect_clean_edges

_flow_test_begin "/flow:watch branch: slug id, real branch in context, merge-in without force (W1, W2, W4, W8, W10)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "watch-branch-$E2E_FENCE_SHELLS"
  e2e_describe "on branch Feature/Issue-7_it's-x under $E2E_FENCE_SHELLS; default branch main"
  e2e_repo "Feature/Issue-7_it's-x"
  _enabled
  _preflight 'branch'
  e2e_gh_fixture repo '{"nameWithOwner":"octo/demo","defaultBranchRef":{"name":"main"}}'
  e2e_run_fence "$WATCH_MD" 'WATCH_BRANCH_BLOCK_BEGIN' 'branch'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "WATCH_STATE=created"
  e2e_expect_line "TRIGGER_FILE=.flow/triggers/branch-feature-issue-7-it-s-x-watch.trigger.yaml"
  e2e_expect_line "LOOP_FILE=.claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md"
  e2e_expect_equal "" "$(_check_trigger .flow/triggers/branch-feature-issue-7-it-s-x-watch.trigger.yaml branch-feature-issue-7-it-s-x-watch "branch=Feature/Issue-7_it's-x" repo=octo/demo default_branch=main)" "problems in the trigger"
  forb=$(_policy .flow/triggers/branch-feature-issue-7-it-s-x-watch.trigger.yaml forbidden)
  allow=$(_policy .flow/triggers/branch-feature-issue-7-it-s-x-watch.trigger.yaml allowed)
  for a in merge release delete_branch force_push rebase create_trigger; do
    e2e_expect_equal "yes no" "$(_has_word "$forb" "$a") $(_has_word "$allow" "$a")" "$a forbidden and not allowed"
  done
  for a in update_from_default_branch run_quality_checks edit_files commit push; do
    e2e_expect_equal "yes" "$(_has_word "$allow" "$a")" "$a allowed"
  done
  e2e_expect_equal "branch_merged_or_deleted == true" "$(_stops .flow/triggers/branch-feature-issue-7-it-s-x-watch.trigger.yaml)" "the stop condition"
  e2e_expect_file_has .claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md "Feature/Issue-7_it's-x"
  e2e_expect_file_has .claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md 'git merge --no-edit "origin/main"' 
  e2e_expect_file_has .claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md "Never rebase"
  e2e_expect_file_has .claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md "/flow:run trigger branch-feature-issue-7-it-s-x-watch"
  e2e_expect_equal "/flow:resolve Feature/Issue-7_it's-x" "$(python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["target"]["command"])' "$E2E_REPO/.flow/triggers/branch-feature-issue-7-it-s-x-watch.trigger.yaml")" "the generated target"
  e2e_expect_file_has .claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md "Stop when the branch is merged or deleted"
  e2e_expect_equal "" "$(grep -nE '[$][{][A-Z][A-Z_]*[}]' "$E2E_REPO/.claude/flow-loop-branch-feature-issue-7-it-s-x-watch.md")" "placeholders left in the loop prompt"
  e2e_expect_clean_edges
done
E2E_FENCE_SHELLS="$ALL_SHELLS"

_flow_test_begin "/flow:watch branch on the default branch is refused (W11)"
e2e_new watch-branch-default
e2e_describe "on main, which is the default branch"
e2e_repo main
_enabled
_preflight 'branch'
e2e_gh_fixture repo '{"nameWithOwner":"octo/demo","defaultBranchRef":{"name":"main"}}'
e2e_run_fence "$WATCH_MD" 'WATCH_BRANCH_BLOCK_BEGIN' 'branch'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "WATCH_STATE=refused"
e2e_expect_out "default branch"
e2e_expect_equal "" "$(ls "$E2E_REPO/.flow/triggers")" "files in .flow/triggers"

_flow_test_begin "/flow:watch writes no trigger through a symlinked .claude"
e2e_new watch-branch-claude-link
e2e_describe ".claude is a link to a directory outside the repository"
e2e_repo feature/x
_preflight 'branch'
mkdir -p "$E2E_DIR/elsewhere"
rm -rf "$E2E_REPO/.claude"
ln -s "$E2E_DIR/elsewhere" "$E2E_REPO/.claude"
e2e_gh_fixture repo '{"nameWithOwner":"octo/demo","defaultBranchRef":{"name":"main"}}'
e2e_run_fence "$WATCH_MD" 'WATCH_BRANCH_BLOCK_BEGIN' 'branch'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "WATCH_STATE=refused"
e2e_expect_equal "" "$(ls "$E2E_DIR/elsewhere")" "files written through the link"
e2e_expect_equal "" "$(ls "$E2E_REPO/.flow/triggers")" "files in .flow/triggers"

# _create_branch [wrapper words...] — bin/flow-watch-create.sh for branch
# feature/x, run in the scratch repository with .flow/triggers present.
_create_branch() {
  mkdir -p "$E2E_REPO/.flow/triggers"
  _e2e_exec "$@" "$E2E_ACTIVE_PLUGIN/bin/flow-watch-create.sh" --kind branch --repo octo/demo \
    --now 2026-10-29T00:00:00Z --branch feature/x --default-branch main
  printf -- '--- expectations\n' | _e2e_art
}
_no_files() {
  e2e_expect_equal "" "$(ls -A "$E2E_REPO/.flow/triggers" 2>/dev/null)" "files in .flow/triggers"
  e2e_expect_equal "" "$(ls -A "$E2E_REPO/.claude" 2>/dev/null | grep '^flow-loop-')" "loop prompts in .claude"
}

_flow_test_begin "bin/flow-watch-create.sh: a write that fails part way leaves no partial file (W15)"
e2e_new watch-create-write-fails
e2e_describe "the script runs under ulimit -f 1 (1024 bytes); the branch loop prompt is longer, so its write fails part way"
e2e_repo feature/x
_create_branch bash -c 'ulimit -f 1; exec "$@"' _
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "WATCH_STATE=refused"
e2e_expect_out "cannot write"
_no_files

if python3 -c 'import jsonschema' >/dev/null 2>&1; then
  _flow_test_begin "bin/flow-watch-create.sh: a trigger schema that is not JSON is a refusal naming the schema (W16)"
  e2e_new watch-create-schema-not-json
  e2e_describe "the plugin copy's schemas/v1/trigger.schema.json holds '{'"
  e2e_repo feature/x
  e2e_plugin_copy schemas/v1/trigger.schema.json '{'
  _create_branch
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "WATCH_STATE=refused"
  e2e_expect_out "schemas/v1/trigger.schema.json"
  e2e_expect_err_lacks "Traceback"
  _no_files

  _flow_test_begin "bin/flow-watch-create.sh: a trigger schema that is not a valid schema is a refusal naming the schema (W16)"
  e2e_new watch-create-schema-invalid
  e2e_describe "the plugin copy's schemas/v1/trigger.schema.json holds {\"type\": 12}"
  e2e_repo feature/x
  e2e_plugin_copy schemas/v1/trigger.schema.json '{"type": 12}'
  _create_branch
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "WATCH_STATE=refused"
  e2e_expect_out "schemas/v1/trigger.schema.json"
  e2e_expect_err_lacks "Traceback"
  _no_files
else
  _flow_test_begin "bin/flow-watch-create.sh: a trigger schema that cannot be used is a refusal (W16)"
  _flow_assert_pass "SKIP: jsonschema not installed"
fi
