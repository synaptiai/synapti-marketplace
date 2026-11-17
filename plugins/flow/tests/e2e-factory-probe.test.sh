# shellcheck shell=bash
# The factory wrapper and its probe command, run in a scratch repository the
# way a flow command block runs them.
#
# Ways it can be wrong, written down before the checks:
#   W1 `context --mode` starts Python or reads the probe record, so an ordinary
#      flow run on a machine without Python 3.14 or without a probe record
#      fails instead of printing FACTORY_MODE=off
#   W2 `context --mode` prints off while a factory job variable is set, so a
#      worker would run flow's commands as if no factory were driving them
#   W3 a subcommand run with no probe record exits 0, or with a message a
#      caller cannot parse, instead of exit 5 and FACTORY_REFUSED=<reason>
#   W4 a temporary folder that cannot be made is reported as a missing
#      interpreter, sending the person to install Python

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# The factory test helpers: the masks that keep each artifact the same from
# run to run (fe_mask_text, fe_mask_back, fe_mask_output, fe_mask_random), and
# fe_bg, fe_py and fe_person_terminal for the scenarios near the end, which
# start background holders and a terminal. The scenarios still start with
# this file's own helpers.
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

_flow_test_begin "factory wrapper: context --mode is off with no Python on PATH (W1)"
e2e_new fp-context-no-python
e2e_describe "with no factory variable set and every python removed from PATH, context --mode prints FACTORY_MODE=off and exits 0"
e2e_repo main
FP_PATH=$(e2e_path_without python3 python python3.14 python3.13 python3.12)
e2e_run_bin PATH="$FP_PATH" bin/flow-factory.sh context --mode
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "FACTORY_MODE=off"
assert_equal "FACTORY_MODE=off" "$E2E_OUT" "stdout is exactly the one line"

_flow_test_begin "factory wrapper: context --mode does not read a probe record (W1)"
e2e_new fp-context-bad-record
e2e_describe "an unreadable probe record in the factory state folder does not change context --mode"
e2e_repo main
mkdir -p "$E2E_REPO/.flow/factory"
printf 'not json' > "$E2E_REPO/.flow/factory/probes.json"
chmod 000 "$E2E_REPO/.flow/factory/probes.json"
e2e_run_bin bin/flow-factory.sh context --mode
chmod 600 "$E2E_REPO/.flow/factory/probes.json"
e2e_expect_equal "0" "$E2E_RC" "exit status"
assert_equal "FACTORY_MODE=off" "$E2E_OUT" "stdout is exactly the one line"

_flow_test_begin "factory wrapper: a factory variable without a probe record is refused (W2)"
e2e_new fp-context-job-set
e2e_describe "with FLOW_FACTORY_JOB set and no probe record, context --mode is refused, not reported off"
e2e_repo main
e2e_run_bin FLOW_FACTORY_JOB=issue-7-j1 bin/flow-factory.sh context --mode
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_line "FACTORY_REFUSED=no_probe_record next: run the phase 0 probes"
e2e_expect_no_line "FACTORY_MODE=off"

_flow_test_begin "factory wrapper: other subcommands are refused with exit 5 (W3)"
for FP_SUB in next run status answer; do
  e2e_new "fp-refuse-$FP_SUB"
  e2e_describe "flow-factory.sh $FP_SUB has no probe record: exit 5 with a FACTORY_REFUSED line"
  e2e_repo main
  e2e_run_bin bin/flow-factory.sh "$FP_SUB"
  e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_SUB"
  e2e_expect_out "FACTORY_REFUSED="
done

_flow_test_begin "factory wrapper: a temporary folder that cannot be made is refused as such, never as a missing interpreter (W4)"
e2e_new fp-probe-tmp-unwritable
e2e_describe "with TMPDIR naming a folder that does not exist, probe refuses with scratch_unwritable and exit 5, not python_missing"
e2e_repo main
e2e_run_bin TMPDIR="$E2E_DIR/no-such-folder" bin/flow-factory.sh probe --resolve-python
fe_mask_output 'flow-factory-py\.[A-Za-z0-9]+' flow-factory-py.XXXXXX
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_line "FACTORY_REFUSED=scratch_unwritable (mktemp -d in $E2E_DIR/no-such-folder failed)"
e2e_expect_no_out "python_missing"

# The probe record checker, `probe --verify-record <file>`.
#
# Ways it can be wrong, written down before the checks:
#   R1 a record missing one of the fifteen probes, or with a group whose tool
#      versions are empty, passes
#   R2 a probe run against a stand-in is accepted as go
#   R3 --dispositions passes a deferred probe with no phase issue, or a no-go
#      that names neither a fallback nor the phases it stops
#   R4 --writes-only-to passes a record whose gh call log shows a write to
#      another repository
#   R4b --writes-only-to reads only the shim's call log, so a gh or git run
#      by its full path, or an HTTP client sending to GitHub, in a command a
#      recorded run made, passes unseen; or a read made that way fails
#   R5 a probe recorded under other tool versions than its group's, which
#      has run again since without it, passes, so a result recorded under
#      older tools is taken as current
#   R6 a part kept from an earlier run takes the tool versions of the run that
#      kept it, so a part recorded under older tools is never stale
#   R7 a probe other than P13 is stale because P13 ran in another launch
#      context
#   R8 an entry or part with no keyed_on of its own, in a group that has one,
#      passes, so a result recorded under tools no one can name is never
#      found stale; or a part with none, carried over when its probe is
#      recorded again, is given its entry's keyed_on, so it passes under
#      versions it was never recorded under; or an entry that never ran
#      (not_run, nothing spent, no evidence) fails for having none
#   R9 a probe whose result disagrees with its parts (go while a part is
#      no-go) passes

# The wrapper runs Python with -E, so PYTHONPATH (which run.sh uses to keep a
# --user PyYAML visible under a scratch HOME) does not reach it. Give the
# scratch HOME the user site-packages a real home has, as a link, resolved
# here while HOME is still the real one.
FP_USER_SITE=$(cd / && python3 -m site --user-site 2>/dev/null || true)
_fp_link_user_site() {
  [ -n "$FP_USER_SITE" ] && [ -d "$FP_USER_SITE" ] || return 0
  local rel="${FP_USER_SITE#"$FP_REAL_HOME"/}"
  [ "$rel" != "$FP_USER_SITE" ] || return 0
  mkdir -p "$E2E_HOME/$(dirname -- "$rel")"
  ln -s "$FP_USER_SITE" "$E2E_HOME/$rel"
}
FP_REAL_HOME="$HOME"

# _fp_inject <fault>... — run tests/fixtures/factory/inject/usercustomize.py in
# every Python the scenario starts with its HOME, with these faults, one per
# argument (that file lists them). The scratch HOME's user site-packages
# becomes a folder of its own holding the fixture, inject.txt and a .pth
# naming the real user site-packages, so PyYAML and jsonschema still load.
_fp_inject() {
  local site
  site=$(cd / && HOME="$E2E_HOME" python3 -E -m site --user-site 2>/dev/null) || site=""
  if [ -z "$site" ]; then
    _flow_assert_fail "$E2E_NAME: no user site-packages folder for the scratch HOME"
    return 0
  fi
  if [ -L "$site" ]; then rm "$site"; fi
  mkdir -p "$site"
  cp "$FP_FIXTURES/inject/usercustomize.py" "$site/"
  if [ -n "$FP_USER_SITE" ] && [ -d "$FP_USER_SITE" ]; then printf '%s\n' "$FP_USER_SITE" > "$site/fp-real-site.pth"; fi
  printf '%s\n' "$@" > "$site/inject.txt"
  printf 'faults injected into the probe: %s\n' "$*" | _e2e_art
}

# _fp_record <file> [python statements applied to the dict d] [stamp] — write a
# valid record, then apply the edits. With stamp, each entry and part the
# edits left without a keyed_on gets its group's, as a probe writes them. An
# entry or part whose keyed_on the edits set to None is left without one.
_fp_record() {
  python3 - "$1" "${2:-}" "${3:-}" <<'PY'
import json, sys
path, edits, stamp = sys.argv[1], sys.argv[2], sys.argv[3]
ids = "P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P13 P14 P15 P16".split()
d = {
  "apiVersion": "flow.synapti.ai/v1",
  "kind": "FlowFactoryProbes",
  "interpreter": "/opt/python/bin/python3.14",
  "groups": {
    "platform": {"keyed_on": {"claude_version": "2.1.322"}, "ran_at": "2026-11-12T13:00:00Z"},
    "environment": {"keyed_on": {"gh_version": "2.80.0", "git_version": "2.55.0"}, "ran_at": "2026-11-12T13:00:00Z"},
  },
  "probes": {i: {"group": "platform", "result": "go", "reason": "checked", "stand_in": False,
                 "evidence": "evidence/%s.txt" % i, "cost_usd": 0.0, "github_writes": []} for i in ids},
  "spend": {"cap_usd": 25, "spent_usd": 3.5},
}
d["probes"]["P8"].update(result="not_run", reason="no second GitHub account")
d["probes"]["P2"].update(result="deferred", reason="deny rule is a stand-in", stand_in=True,
                         deferred_to="synaptiai/synapti-marketplace#355")
d["probes"]["P6"].update(group="github_write", github_writes=[
  {"repo": "danielbentes/flow-factory-sandbox", "call": "POST repos/danielbentes/flow-factory-sandbox/pulls/1/reviews"}])
exec(edits)
for p in d["probes"].values():
  keyed = (d["groups"].get(p.get("group")) or {}).get("keyed_on")
  for item in [p] + list((p.get("parts") or {}).values()):
    if "keyed_on" not in item and stamp == "stamp" and keyed:
      item["keyed_on"] = dict(keyed)
    elif "keyed_on" in item and item["keyed_on"] is None:
      del item["keyed_on"]
with open(path, "w") as f:
  json.dump(d, f, indent=1)
PY
}

_fp_verify_case() {   # <scenario> <description> <edits> <expected rc> <expected line or text> [extra args]
  local name="$1" desc="$2" edits="$3" rc="$4" text="$5"; shift 5
  e2e_new "$name"
  e2e_describe "$desc"
  e2e_repo main
  _fp_link_user_site
  _fp_record "$E2E_REPO/probes.json" "$edits" stamp
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/probes.json" "$@"
  e2e_expect_equal "$rc" "$E2E_RC" "exit status"
  e2e_expect_out "$text"
}

_flow_test_begin "probe record: a complete record passes (R1)"
_fp_verify_case fp-verify-ok "a record with all fifteen probes and keyed groups passes" "" 0 "PROBES_RECORD=ok"

_flow_test_begin "probe record: a missing probe fails (R1)"
_fp_verify_case fp-verify-missing "a record without P7 fails and names P7" 'del d["probes"]["P7"]' 1 "PROBES_CHECK_FAIL=missing_probe P7"

_flow_test_begin "probe record: a record without P16, the worker sandbox, fails (R1)"
_fp_verify_case fp-verify-missing-p16 "a record without P16 fails and names P16" 'del d["probes"]["P16"]' 1 "PROBES_CHECK_FAIL=missing_probe P16"

_flow_test_begin "probe record: a group with no tool versions fails (R1)"
_fp_verify_case fp-verify-unkeyed "a group whose keyed_on is empty fails the schema" 'd["groups"]["platform"]["keyed_on"] = {}' 1 "PROBES_CHECK_FAIL=schema"

_flow_test_begin "probe record: an unknown result fails (R1)"
_fp_verify_case fp-verify-badresult "a result outside go, no-go, deferred and not_run fails" 'd["probes"]["P4"]["result"] = "maybe"' 1 "PROBES_CHECK_FAIL=schema"

_flow_test_begin "probe record: a stand-in is never go (R2)"
_fp_verify_case fp-verify-standin-go "P2 run against a stand-in and recorded go fails" \
  'd["probes"]["P2"].update(result="go"); d["probes"]["P2"].pop("deferred_to")' 1 "PROBES_CHECK_FAIL=stand_in_go P2"

_flow_test_begin "probe record: dispositions name a phase, a fallback or a reason (R3)"
_fp_verify_case fp-disp-ok "a deferred probe with a phase issue and a not_run with a reason pass" "" 0 "PROBES_RECORD=ok" --dispositions
_fp_verify_case fp-disp-deferred "a deferred probe with no phase issue fails" 'd["probes"]["P2"].pop("deferred_to")' 1 "PROBES_CHECK_FAIL=deferred_without_phase P2" --dispositions
_fp_verify_case fp-disp-nogo "a no-go with neither a fallback nor stopped phases fails" 'd["probes"]["P5"]["result"] = "no-go"' 1 "PROBES_CHECK_FAIL=no_go_without_fallback P5" --dispositions
_fp_verify_case fp-disp-nogo-ok "a no-go that names its fallback passes" 'd["probes"]["P5"].update(result="no-go", fallback="the engine sums costs itself")' 0 "PROBES_RECORD=ok" --dispositions

_flow_test_begin "probe record: GitHub writes go only to the sandbox (R4)"
_fp_verify_case fp-writes-ok "writes only to the sandbox pass" "" 0 "PROBES_RECORD=ok" --writes-only-to danielbentes/flow-factory-sandbox
_fp_verify_case fp-writes-other "a write to another repository fails and names it" \
  'd["probes"]["P3"]["github_writes"] = [{"repo": "synaptiai/synapti-marketplace", "call": "POST repos/synaptiai/synapti-marketplace/pulls"}]' \
  1 "PROBES_CHECK_FAIL=write_outside_sandbox P3 synaptiai/synapti-marketplace" --writes-only-to danielbentes/flow-factory-sandbox
# A write the probe's shim or gh stand-in refused never reached GitHub: it is
# listed, not failed. Wrong versions: a refused attempt fails the check (the
# criterion is about writes made), or a made write marked refused: false, or
# with no refused field, passes.
_fp_verify_case fp-writes-refused "a refused attempt outside the sandbox is listed and passes" \
  'd["probes"]["P1"]["github_writes"] = [{"repo": "unresolved/unresolved", "call": "gh pr create", "refused": True}]' \
  0 "PROBES_REFUSED_WRITE=P1 unresolved/unresolved gh pr create" --writes-only-to danielbentes/flow-factory-sandbox
e2e_expect_out "PROBES_RECORD=ok"
_fp_verify_case fp-writes-not-refused "a write marked refused: false outside the sandbox fails" \
  'd["probes"]["P1"]["github_writes"] = [{"repo": "other/repo", "call": "gh pr create", "refused": False}]' \
  1 "PROBES_CHECK_FAIL=write_outside_sandbox P1 other/repo" --writes-only-to danielbentes/flow-factory-sandbox

# The commands a recorded run made, from its stream-json, as P16's evidence
# folder holds them. FP_STREAM_EDIT writes one Bash call with the command in
# FP_CMD into evidence/P16-1/run-a/stream.jsonl beside the record.
FP_STREAM_EDIT='import os, json
ev = os.path.join(os.path.dirname(path), "evidence", "P16-1", "run-a")
os.makedirs(ev, exist_ok=True)
with open(os.path.join(ev, "stream.jsonl"), "w") as f:
  f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": os.environ["FP_CMD"]}}]}}) + "\n")
d["probes"]["P16"]["evidence"] = "evidence/P16-1"'
_flow_test_begin "probe record: a GitHub write a recorded run made around the shim fails the writes check (R4b)"
export FP_CMD="/opt/homebrew/bin/gh pr create --repo other/repo --title t --body b"
_fp_verify_case fp-writes-unlogged-gh "a gh pr create run by its full path in P16's recorded commands fails and is listed as a write" \
  "$FP_STREAM_EDIT" 1 "PROBES_CHECK_FAIL=unlogged_github_write P16" --writes-only-to danielbentes/flow-factory-sandbox
e2e_expect_out "PROBES_UNLOGGED_CALL=P16 write /opt/homebrew/bin/gh pr create --repo other/repo --title t --body b"
export FP_CMD="curl -s -X POST https://api.github.com/repos/other/repo/issues -d '{\"title\": \"x\"}'"
_fp_verify_case fp-writes-unlogged-curl "a curl POST to api.github.com in P16's recorded commands fails" \
  "$FP_STREAM_EDIT" 1 "PROBES_CHECK_FAIL=unlogged_github_write P16" --writes-only-to danielbentes/flow-factory-sandbox
export FP_CMD="printf '%s' \"\$(/opt/homebrew/bin/gh auth token | wc -c)\"; curl -s -o /dev/null -w '%{http_code}' https://api.github.com/zen"
_fp_verify_case fp-writes-unlogged-reads "a gh auth token by full path and a curl GET to api.github.com are listed as reads and pass" \
  "$FP_STREAM_EDIT" 0 "PROBES_UNLOGGED_CALL=P16 read /opt/homebrew/bin/gh auth token" --writes-only-to danielbentes/flow-factory-sandbox
e2e_expect_out "PROBES_RECORD=ok"
unset FP_CMD

# The gh and git shim's call log, which --writes-only-to reads. Each row of
# tests/fixtures/factory/shim-calls.jsonl is one call made through the shim
# with probe-fixture/sandbox as the one repository it may write to: the row
# says whether the log records it as a read or as a write and to which
# repository, and a write anywhere else must also be refused (exit 1).
#
# Ways it can be wrong, written down before the checks:
#   S1 a gh command the shim does not know (gist, ssh-key, an extension, an
#      alias, a flag before the verb) is logged as a read
#   S2 a gh write is credited to the default repository while it goes to the
#      repository a URL argument, a positional repository or another remote
#      names, so the shim lets it through
#   S3 a GraphQL document with a mutation after a query, or read from a file
#      the shim cannot read, is logged as a read
#   S4 a git push is missed or credited to the wrong repository when the
#      address comes from -c, --config-env, an alias, url.*.insteadOf, a
#      port or another github.com host
#   S5 the reads probes make (gh auth status, gh api user, gh pr view, a GET,
#      git fetch, git ls-remote, a push to a local path) become writes
#   S6 gh api one-letter flags bundled or written with = (-iX DELETE,
#      -iXDELETE, -if title=x, -f=query=mutation...), or a flag gh api does
#      not have, hide a write
#   S7 a ! alias is searched for the word push, which shell quoting and the
#      call's own arguments hide
#   S8 a git push option abbreviated (--rep=, --push-opt), bundled (-qo) or
#      unknown moves the push to the wrong repository or to a local path
#   S9 a mistyped command, which help.autocorrect can run as push, is a read
#   S10 an ssh Host alias, a proxy, an IP address or another ssh program
#      takes an ssh push to GitHub while the address names another host
#   S11 rebase --exec, bisect run, submodule foreach or filter-branch runs a
#      command that pushes, and the call is a read
#   S12 a push to a host that is not one of GitHub's is let through as a push
#      somewhere else: another host, an ssh alias, an IP address written in
#      any radix, a scheme or a <helper>:: prefix git hands to another
#      program; or GitHub's own host is missed when written with percent
#      escapes, upper case or a trailing dot
#   S13 a git command, subcommand or helper that is not known to make no
#      GitHub write is a read: submodule--helper, lfs lock, a config write, a
#      builtin an alias of the same name cannot stand in for
#   S14 a program the remote side is told to run (--upload-pack, --exec, -u,
#      remote.<name>.receivepack, uploadpack or vcs from -c or a config file)
#      does not make the fetch or push unresolved
#   S15 a read command told on its command line to run a program is a read:
#      grep -O, a merge strategy git does not have (git runs
#      git-merge-<name>), a template folder whose hooks clone runs
#   S16 a fetch, pull, clone, ls-remote or remote reaching its remote through
#      a program git runs for the address (a <helper>:: prefix, a scheme git
#      has no transport of its own for, ext::), from the call or from a
#      remote's URL in the config, is a read; or a call made while
#      --exec-path or GIT_EXEC_PATH names another folder than git's own,
#      from which git runs its helpers, is a read
#   S17 a GraphQL call is judged on its arguments as typed while gh sends
#      something else: a -F/--field value gh fills in ({branch} on a branch
#      named mutation, :owner) or reads from a file or stdin (@file, @-), or
#      an --input body, is logged as a read; or a mutation under another key
#      than query (query[]=...) is missed
#   S18 a REST endpoint with only some segments as placeholders
#      (repos/{owner}/other-repo), a placeholder inside a segment, or a . or
#      .. segment (plain or percent-escaped) is credited to the default
#      repository, so a write elsewhere is let through
#   S19 a repository name the record's schema refuses (:owner/:repo,
#      {branch}/issues) is logged, so the record write is refused later
_flow_test_begin "shim: the call log records every GitHub write and only those (S1-S19)"
e2e_new fp-shim-table
e2e_describe "each row of shim-calls.jsonl run through shim-log in a scratch repository: read or write, the repository, and exit 1 for a write outside the sandbox"
e2e_repo main
(
  _e2e_git_env
  cd "$E2E_DIR" && git init -q --bare local.git || exit 1
  for FP_W in two chosen packs; do git init -q "$FP_W" || exit 1; done
  git init -q --initial-branch=mutation mutation || exit 1
  git -C mutation remote add origin https://github.com/probe-fixture/sandbox.git || exit 1
  git -C packs remote add origin "$E2E_DIR/local.git" || exit 1
  git -C packs config remote.origin.uploadpack git-upload-pack || exit 1
  git -C packs config remote.origin.receivepack git-receive-pack || exit 1
  cd "$E2E_REPO" || exit 1
  git remote add origin https://github.com/probe-fixture/sandbox.git
  git remote add local "$E2E_DIR/local.git"
  git remote add gl https://gitlab.com/o/r.git
  git config alias.pp push
  git config alias.p2 pp
  git config alias.pf "push --force"
  git config alias.st status
  git config alias.lg "log --oneline"
  git config alias.sp "!git push origin"
  git config alias.hi "!echo hello"
  for FP_W in two chosen; do
    git -C "$E2E_DIR/$FP_W" remote add origin https://github.com/probe-fixture/sandbox.git
    git -C "$E2E_DIR/$FP_W" remote add upstream https://github.com/other/upstream.git
  done
  git -C "$E2E_DIR/chosen" config remote.upstream.gh-resolved base
) || _flow_assert_fail "$E2E_NAME: could not create the scratch repositories"
printf 'query A { viewer { login } }\n' > "$E2E_DIR/q-read.graphql"
printf 'query A { viewer { login } }\n\nmutation B { addStar(input: {starrableId: "x"}) { clientMutationId } }\n' > "$E2E_DIR/q-mut.graphql"
printf '{"title": "x"}\n' > "$E2E_DIR/body.json"
printf '{"query": "{ viewer { login } }"}\n' > "$E2E_DIR/q-read.json"
# Host aliases leading to GitHub, to another host through a jump host, and to
# an IP address, for the rows that set HOME. The shim does not read ssh's
# configuration, so a push to any of these aliases is unresolved.
mkdir -p "$E2E_DIR/sshhome/.ssh"
printf '%s\n' 'Host gh-alias' '  HostName github.com' 'Host gh-alias2' '  HostName ssh.github.com' '  Port 443' \
  'Host pj-alias' '  HostName gitlab.com' '  ProxyJump jump.example' 'Host ip-alias' '  HostName 140.82.121.3' \
  > "$E2E_DIR/sshhome/.ssh/config"
FP_SHIM_ROWS=$(env -u GH_REPO -u GIT_DIR -u GIT_WORK_TREE -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
  -u GIT_SSH_COMMAND -u GIT_SSH \
  HOME="$E2E_HOME" GIT_CONFIG_NOSYSTEM=1 FLOW_SHIM_TEST_URL=https://github.com/other/repo.git \
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/factory/shim-calls.jsonl" "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" "$(command -v git)" "$E2E_DIR" "$E2E_REPO" <<'PY'
import json, os, subprocess, sys
table, module, git, top, repo = sys.argv[1:6]
# {exec} in a row is git's own folder of helper programs.
own = subprocess.run([git, "--exec-path"], capture_output=True, text=True,
                     env={k: v for k, v in os.environ.items() if k != "GIT_EXEC_PATH"}).stdout.strip()
where = {"one": repo, "two": os.path.join(top, "two"), "chosen": os.path.join(top, "chosen"),
         "packs": os.path.join(top, "packs"), "mutation": os.path.join(top, "mutation")}
log = os.path.join(top, "shim-calls.log")
for n, line in enumerate(open(table, encoding="utf-8"), 1):
    row = json.loads(line)
    argv = [a.replace("{dir}", top).replace("{exec}", own) for a in row["argv"]]
    env = {k: v.replace("{dir}", top).replace("{exec}", own) for k, v in row.get("env", {}).items()}
    before = os.path.getsize(log) if os.path.exists(log) else 0
    rc = subprocess.run([sys.executable, "-E", module, "shim-log", "--tool", row["tool"], "--log", log,
                         "--git", git, "--allow-repo", "probe-fixture/sandbox", "--"] + argv,
                        cwd=where[row["where"]], stdin=subprocess.DEVNULL, capture_output=True,
                        env=dict(os.environ, **env)).returncode
    with open(log, encoding="utf-8") as f:
        f.seek(before)
        got = f.read().splitlines()
    if len(got) != 1:
        got_text = f"{len(got)} log lines, rc={rc}"
    else:
        e = json.loads(got[0])
        got_text = (f"write {e.get('repo')}" if e.get("write") else "read") + f" rc={rc}"
    want_rc = 1 if row["expect"].startswith("write ") and row["expect"] != "write probe-fixture/sandbox" else 0
    env_text = "".join(f"{k}={v} " for k, v in row.get("env", {}).items())
    what = f"row {n} ({row['where']}): {env_text}{row['tool']} {' '.join(argv)}".replace("\n", "\\n").replace("\t", " ")
    print(f"{what}\t{row['expect']} rc={want_rc}\t{got_text}")
PY
)
FP_SHIM_COUNT=0
while IFS="$(printf '\t')" read -r FP_WHAT FP_WANT FP_GOT; do
  [ -n "$FP_WHAT" ] || continue
  FP_SHIM_COUNT=$((FP_SHIM_COUNT + 1))
  e2e_expect_equal "$FP_WANT" "$FP_GOT" "$FP_WHAT"
done <<EOF
$FP_SHIM_ROWS
EOF
e2e_expect_equal "$(wc -l < "$REPO_ROOT/plugins/flow/tests/fixtures/factory/shim-calls.jsonl" | tr -d ' ')" "$FP_SHIM_COUNT" "rows checked"

# S20 A config read that fails is taken for an empty config: the push
# is judged on the address as typed, so a pushInsteadOf or core.sshCommand
# the read would have found, sending it elsewhere, is missed and the push is
# let through as a write to the sandbox. The stand-in git below fails only
# those two reads (exit 128, as git does for a config it cannot parse), so
# every other lookup the shim makes still works.
_flow_test_begin "shim: a git config read that fails makes a push unresolved, never a write to the sandbox (S20)"
e2e_new fp-shim-config-unreadable
e2e_describe "with git config failing for insteadOf and core.sshCommand, a push to the sandbox address that config would send elsewhere is logged unresolved and refused"
e2e_repo main
FP_REAL_GIT=$(command -v git)
mkdir -p "$E2E_DIR/badgit"
cat > "$E2E_DIR/badgit/git" <<EOF
#!/bin/sh
case " \$* " in
  *" config "*insteadof*|*" config "*core.sshCommand*) echo "fatal: bad config line 1" >&2; exit 128 ;;
esac
exec "$FP_REAL_GIT" "\$@"
EOF
chmod +x "$E2E_DIR/badgit/git"
FP_S20=$(env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_SSH_COMMAND -u GIT_SSH \
  HOME="$E2E_HOME" GIT_CONFIG_NOSYSTEM=1 \
  python3 - "$E2E_ACTIVE_PLUGIN/bin/_flow_factory.py" "$FP_REAL_GIT" "$E2E_DIR/badgit/git" "$E2E_DIR" "$E2E_REPO" <<'PY'
import json, os, subprocess, sys
module, real, bad, top, repo = sys.argv[1:6]
log = os.path.join(top, "s20.log")
cases = [
    ("pushInsteadOf, config readable", real,
     ["-c", "url.https://elsewhere.example/x/.pushInsteadOf=https://github.com/", "push",
      "https://github.com/probe-fixture/sandbox.git", "HEAD:refs/heads/x"]),
    ("pushInsteadOf, config read fails", bad,
     ["-c", "url.https://elsewhere.example/x/.pushInsteadOf=https://github.com/", "push",
      "https://github.com/probe-fixture/sandbox.git", "HEAD:refs/heads/x"]),
    ("core.sshCommand, config read fails", bad,
     ["-c", "core.sshCommand=ssh -o ProxyCommand=elsewhere", "push",
      "git@github.com:probe-fixture/sandbox.git", "HEAD:refs/heads/x"]),
]
for name, git, argv in cases:
    before = os.path.getsize(log) if os.path.exists(log) else 0
    rc = subprocess.run([sys.executable, "-E", module, "shim-log", "--tool", "git", "--log", log, "--git", git,
                         "--allow-repo", "probe-fixture/sandbox", "--"] + argv,
                        cwd=repo, stdin=subprocess.DEVNULL, capture_output=True).returncode
    with open(log, encoding="utf-8") as f:
        f.seek(before)
        got = f.read().splitlines()
    e = json.loads(got[0]) if len(got) == 1 else {}
    print(f"{name}\t{'write ' + str(e.get('repo')) if e.get('write') else 'read'} rc={rc}")
PY
)
while IFS="$(printf '\t')" read -r FP_WHAT FP_GOT; do
  [ -n "$FP_WHAT" ] || continue
  e2e_expect_equal "write unresolved/unresolved rc=1" "$FP_GOT" "$FP_WHAT"
done <<EOF
$FP_S20
EOF
e2e_expect_equal "3" "$(printf '%s\n' "$FP_S20" | grep -c .)" "cases checked"

# Each probe entry carries the keyed_on and ran_at it was recorded under. A
# probe whose group ran again on other tools without it is stale. Wrong
# versions: the per-entry fields fail the schema, a probe recorded under an
# older claude passes, or a key the group gained later (launch_context from
# P13) or the interactive group's growing permission_modes reads as stale.
_flow_test_begin "probe record: a probe recorded under other tool versions than its group is stale (R5)"
_fp_verify_case fp-verify-stale "P4 was recorded under claude 2.1.300 and the platform group has since run on 2.1.322 without it: stale, naming P4 and the key" \
  'd["probes"]["P4"].update(keyed_on={"claude_version": "2.1.300"}, ran_at="2026-11-10T09:00:00Z")' \
  1 "PROBES_STALE=P4 claude_version"
e2e_expect_no_out "PROBES_RECORD=ok"
_fp_verify_case fp-verify-current "entries whose keyed_on agrees with their group on every key both hold pass, although the environment group has since gained launch_context and the interactive group's permission_modes grew" \
  'd["groups"]["environment"]["keyed_on"]["launch_context"] = "launchd"; d["groups"]["interactive"] = {"keyed_on": {"claude_version": "2.1.322", "permission_modes": "auto,default"}, "ran_at": "2026-11-12T14:00:00Z"}; d["probes"]["P4"].update(keyed_on={"claude_version": "2.1.322"}, ran_at="2026-11-12T13:00:00Z"); d["probes"]["P3"].update(group="environment", keyed_on={"gh_version": "2.80.0", "git_version": "2.55.0"}, ran_at="2026-11-12T13:00:00Z"); d["probes"]["P14"].update(group="interactive", keyed_on={"claude_version": "2.1.322", "permission_modes": "default"}, ran_at="2026-11-12T13:30:00Z")' \
  0 "PROBES_RECORD=ok"
e2e_expect_no_out "PROBES_STALE"

# An entry or part with no keyed_on of its own, in a group that has one, was
# recorded under tools no one can name, so it is listed and fails. Wrong
# versions: it passes, an entry whose group has no keyed_on fails, an entry
# that never ran fails, or a not_run entry that holds evidence passes.
_flow_test_begin "probe record: an entry or part with no keyed_on of its own in a keyed group fails (R8)"
_fp_verify_case fp-verify-unstamped "P4 carries no keyed_on while the platform group has one, and so does P9's \
hook_mode_auto part: each is listed as unstamped and the record fails" \
  'd["probes"]["P4"]["keyed_on"] = None; d["probes"]["P9"]["parts"] = {"hook_mode_auto": {"result": "go", "reason": "seen", "keyed_on": None}, "hook_mode_default": {"result": "go", "reason": "seen"}}' \
  1 "PROBES_UNSTAMPED=P4"
e2e_expect_line "PROBES_UNSTAMPED=P4"
e2e_expect_line "PROBES_UNSTAMPED=P9/hook_mode_auto"
e2e_expect_no_out "PROBES_UNSTAMPED=P9/hook_mode_default"
e2e_expect_no_line "PROBES_UNSTAMPED=P9"
e2e_expect_no_out "PROBES_RECORD=ok"
_fp_verify_case fp-verify-unstamped-never-ran "P8 never ran (not_run, cost 0, no evidence) and P6's group has no \
keyed_on; neither carries one of its own: the record passes" \
  'd["probes"]["P8"].update(evidence="", keyed_on=None); d["probes"]["P6"]["keyed_on"] = None' \
  0 "PROBES_RECORD=ok"
e2e_expect_no_out "PROBES_UNSTAMPED"
_fp_verify_case fp-verify-unstamped-ran "P11 is not_run but holds evidence, so it ran, and carries no keyed_on: it \
is listed" \
  'd["probes"]["P11"].update(result="not_run", reason="a call got no answer", keyed_on=None)' \
  1 "PROBES_UNSTAMPED=P11"

# The probe runner, `probe --launch <probe id>`: one `claude -p` run through
# the launcher every model probe uses, with the stand-in claude, gh and
# timeout from tests/fixtures/factory/bin.
#
# Ways it can be wrong, written down before the checks:
#   L1 the spend cap is checked after the model starts, so a run that would
#      pass the cap starts and spends
#   L2 the guard refuses a run that fits exactly, or reads what was spent from
#      somewhere other than the record, so the cap is not the one recorded
#   L3 a run that outlives its time limit is left running, recorded as
#      anything but no-go with reason timeout, or charged nothing, although
#      what it spent is unknown
#   L4 a missing tool is found only once a probe needs it, or the refusal does
#      not name it
#   L5 the launched claude inherits the caller's environment, loses the
#      provider settings it needs, runs without its turn and budget limits, or
#      runs without the logging shim first on PATH
#   L6 a GitHub write made through gh or git during a run does not reach the
#      record, a read is listed as a write, or the shim does not pass the call
#      on to the real program
#   L7 the record is written outside the main checkout's runtime directory
#      (a linked worktree's), is not ignored by git, loses another group's
#      results when it merges, or does not validate against the schema
#   L8 keyed_on lacks a tool version or the interpreter
#   L9 a GitHub write the run may not make reaches the real gh or git, so the
#      only defence is reading the record afterwards; or a refused write is
#      left out of github_writes
#   L10 a git push whose option value comes before the remote (-o ci.skip,
#      --push-option x), or whose remote cannot be resolved, is not logged as
#      a GitHub write
#   L11 a GraphQL mutation read from a file (-F query=@file, --input) or
#      behind a leading # comment is logged as a read
#   L12 --cap-usd above the recorded cap lifts the cap for this run or for
#      every later one
#   L13 a run that exits before printing any event is charged its budget
#       limit or given any outcome but not_started; or a run whose process
#       could not be started at all is charged, or ends in a traceback
#       instead of a refusal
#   L14 a run is charged the cost its result reports for the whole session
#       (total_cost_usd), which a resumed run reports again, rather than what
#       it spent since the session's last result (the costUSD of each model
#       in model_usage_since_last_result); or a since-last figure it cannot
#       read (a model with no cost, none at all) is charged instead of the
#       total
#   L15 an interrupt that lands while the run's process is being started,
#       before subprocess.Popen returns, leaves the run uncharged although
#       its claude was started and runs on

FP_FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/factory"

# _fp_runner_scenario <name> <description> — a scratch repository whose stub
# bin holds the stand-in claude, gh and timeout, and a prompt file.
_fp_runner_scenario() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
  _fp_link_user_site
  cp "$FP_FIXTURES/bin/claude" "$FP_FIXTURES/bin/gh" "$FP_FIXTURES/bin/timeout" "$E2E_BIN/"
  printf 'Say hello.\n' > "$E2E_DIR/prompt.txt"
  _fp_epic_journal
}

# _fp_epic_journal — the factory epic's decision journal with no decisions
# yet: the probe records results only where this file is.
_fp_epic_journal() {
  mkdir -p "$E2E_REPO/.decisions"
  printf '## Phase 0 decisions\n\n- budget: $25 cap on total model spend\n' > "$E2E_REPO/.decisions/issue-353.md"
}

# _fp_get <json file> <python expression on d> — print the value.
_fp_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
v = eval(sys.argv[2])
print(json.dumps(v) if isinstance(v, (dict, list, bool)) or v is None else v)
PY
}

# _fp_launches — how many times the stand-in claude was started with -p.
_fp_launches() {
  if [ -f "$E2E_BIN/claude-launches.log" ]; then
    local n; n=$(wc -l < "$E2E_BIN/claude-launches.log"); printf '%s' "${n// /}"
  else
    printf '0'
  fi
}

# _fp_schema_valid <record> — print ok, or the first schema error.
_fp_schema_valid() {
  python3 - "$1" "$REPO_ROOT/plugins/flow/schemas/v1/factory-probes.schema.json" <<'PY'
import json, sys, jsonschema
rec = json.load(open(sys.argv[1], encoding="utf-8"))
schema = json.load(open(sys.argv[2], encoding="utf-8"))
errs = list(jsonschema.Draft202012Validator(schema).iter_errors(rec))
print("ok" if not errs else errs[0].message)
PY
}

FP_REC=".flow/factory/probes.json"

_flow_test_begin "probe runner: a run that would pass the spend cap is not started (L1)"
_fp_runner_scenario fp-run-budget "with \$24 spent of \$25 and a \$2 run limit, P5 is recorded not_run with reason budget and claude never starts"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24'
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 2 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out '"outcome": "budget"'
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["result"]')" "P5 result"
e2e_expect_equal "budget" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["reason"]')" "P5 reason"
e2e_expect_equal "24" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"

_flow_test_begin "probe runner: a run that fits the cap exactly starts and is charged its cost (L2)"
_fp_runner_scenario fp-run-fits "with \$24 spent of \$25 and a \$1 run limit, the run starts once and the stand-in's \$0.42 is added"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24'
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out '"outcome": "completed"'
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "24.42" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["result"]')" "P5 result left as it was (the run gives no verdict)"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P1"]["result"]')" "another probe's result is kept"

_flow_test_begin "probe runner: the cap is the one given (L2)"
_fp_runner_scenario fp-run-cap-arg "with \$3 spent and --cap-usd 4, a \$2 run is not started"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" ''
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 2 --cap-usd 4
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P4"]["result"]')" "P4 result"
e2e_expect_equal "4" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["cap_usd"]')" "cap_usd"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"

_flow_test_begin "probe runner: an existing record that fails the schema is refused before the run (L2, L7)"
_fp_runner_scenario fp-run-bad-record "a record whose P4 result is not one of the four is refused before the guard: nothing starts and the file is left as it was"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P4"]["result"] = "maybe"'
FP_SUM=$(cksum < "$E2E_REPO/$FP_REC")
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=record_invalid probes/P4/result"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "$FP_SUM" "$(cksum < "$E2E_REPO/$FP_REC")" "the record's checksum"

_flow_test_begin "probe runner: a run past its time limit is killed and recorded no-go timeout (L3, L6, L7)"
# The stand-in's calls go through the shim, one Python start each, before it
# sleeps: the 8 s limit leaves room for them on a loaded machine.
_fp_runner_scenario fp-run-timeout "the stand-in makes GitHub calls, then sleeps 30 s against an 8 s limit: it is killed, P5 is no-go with reason timeout, charged its \$0.5 limit, and the writes are in the record"
printf 'sleep 30\n' > "$E2E_BIN/claude-behaviour"
cat > "$E2E_BIN/claude-script" <<'SH'
gh api --method POST repos/danielbentes/flow-factory-sandbox/labels -f name=probe
gh api repos/danielbentes/flow-factory-sandbox
gh pr create --repo other/elsewhere --title t --body b
gh issue view 3 --repo other/elsewhere
gh api -XPATCH repos/danielbentes/flow-factory-sandbox/issues/1 -ftitle=x
gh pr --repo other/elsewhere merge 2
SH
FP_T0=$(date +%s)
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 0.5 --timeout-seconds 8 --kill-after-seconds 1
FP_T1=$(date +%s)
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out '"outcome": "timeout"'
e2e_expect_equal "yes" "$([ $((FP_T1 - FP_T0)) -lt 25 ] && echo yes || echo no)" "returned well before the stand-in's 30 s"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["result"]')" "P5 result"
e2e_expect_equal "timeout" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["reason"]')" "P5 reason"
e2e_expect_equal "0.5" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["cost_usd"]')" "P5 cost is its budget limit"
e2e_expect_equal "0.5" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
e2e_expect_equal '[{"repo": "danielbentes/flow-factory-sandbox", "call": "POST repos/danielbentes/flow-factory-sandbox/labels", "refused": true}, {"repo": "other/elsewhere", "call": "gh pr create", "refused": true}, {"repo": "danielbentes/flow-factory-sandbox", "call": "PATCH repos/danielbentes/flow-factory-sandbox/issues/1", "refused": true}, {"repo": "other/elsewhere", "call": "gh pr merge", "refused": true}]' \
  "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["github_writes"]')" "github_writes (reads left out; probe --launch may write nowhere, so every write is refused)"
e2e_expect_equal "api repos/danielbentes/flow-factory-sandbox|issue view 3 --repo other/elsewhere" "$(paste -sd'|' - < "$E2E_BIN/gh-real.log")" "gh calls passed on to the real gh: the two reads"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_expect_equal "*" "$(cat "$E2E_REPO/.flow/factory/.gitignore" 2>/dev/null)" "factory/.gitignore"
e2e_expect_equal "" "$(cd "$E2E_REPO" && git status --porcelain --untracked-files=all .flow/factory)" "git status shows nothing under .flow/factory"
FP_EV=$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P5"]["evidence"]')
e2e_expect_equal "evidence/P5-1" "$FP_EV" "the evidence directory"
e2e_expect_equal "6" "$(wc -l < "$E2E_REPO/.flow/factory/$FP_EV/calls.jsonl" | tr -d ' ')" "the call log in the evidence has every call"
e2e_expect_equal '{"argv": ["gh", "api", "repos/danielbentes/flow-factory-sandbox"], "repo": "danielbentes/flow-factory-sandbox", "method": "GET", "write": false}' \
  "$(sed -n 2p "$E2E_REPO/.flow/factory/$FP_EV/calls.jsonl")" "a read is logged as GET"

_flow_test_begin "probe runner: GitHub writes through the shim are logged and refused before the real gh or git (L6, L9, L10, L11)"
# The remote names a made-up GitHub repository, and the scratch HOME's git
# config refuses the network transports, so even a push the shim let through
# could not leave the machine. The stand-in sleeps after its script until the
# runner stops it at its time limit, which writes P3's entry; the 60 s limit
# is far above the script's 15 calls through the shim, one Python start each,
# so a loaded machine does not stop the script part way.
_fp_runner_scenario fp-run-git-push "the stand-in pushes to a GitHub remote in three forms (plain, -o ci.skip, --push-option x) and to a remote with no URL, makes three GraphQL mutations (inline behind a comment, from a file, from --input), a GraphQL read, and a gh issue create and a gh issue new (its alias) on another repository, and pushes to a local path: every GitHub write is in github_writes marked refused, none reaches the real gh or git, the read and the local push do, and --writes-only-to flags the writes"
printf '[protocol "https"]\n\tallow = never\n[protocol "ssh"]\n\tallow = never\n[protocol "git"]\n\tallow = never\n' > "$E2E_HOME/.gitconfig"
printf 'sleep 600\n' > "$E2E_BIN/claude-behaviour"
cat > "$E2E_BIN/claude-script" <<'SH'
git init -q pushrepo && cd pushrepo || exit 1
git -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m one
git remote add origin https://github.com/probe-fixture/no-such-repo.git
git init -q --bare ../other.git
git push -q origin HEAD:refs/heads/probe
git push -q -o ci.skip origin HEAD:refs/heads/probe2
git push -q --push-option x origin HEAD:refs/heads/probe3
git push -q nosuchremote HEAD:refs/heads/probe4
git push -q ../other.git HEAD:refs/heads/probe
gh api graphql -f query='# a comment first
mutation { addStar(input: {starrableId: "x"}) { clientMutationId } }'
gh api graphql -F query=@mutation.graphql
gh api graphql --input query.json
gh api graphql -f query='{ viewer { login } }'
gh issue create --repo other/repo --title t --body b
gh issue new --repo other/repo --title t --body b
SH
e2e_run_bin bin/flow-factory.sh probe --launch P3 --group github_write --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 0.5 --timeout-seconds 60 --kill-after-seconds 1
e2e_expect_out '"outcome": "timeout"'
e2e_expect_equal "15" "$(wc -l < "$E2E_REPO/.flow/factory/evidence/P3-1/calls.jsonl" | tr -d ' ')" \
  "the call log holds every one of the script's 15 shim calls"
e2e_expect_equal '[{"repo": "probe-fixture/no-such-repo", "call": "git push -q origin HEAD:refs/heads/probe", "refused": true}, {"repo": "probe-fixture/no-such-repo", "call": "git push -q -o ci.skip origin HEAD:refs/heads/probe2", "refused": true}, {"repo": "probe-fixture/no-such-repo", "call": "git push -q --push-option x origin HEAD:refs/heads/probe3", "refused": true}, {"repo": "unresolved/unresolved", "call": "git push -q nosuchremote HEAD:refs/heads/probe4", "refused": true}, {"repo": "unresolved/unresolved", "call": "POST graphql", "refused": true}, {"repo": "unresolved/unresolved", "call": "POST graphql", "refused": true}, {"repo": "unresolved/unresolved", "call": "POST graphql", "refused": true}, {"repo": "other/repo", "call": "gh issue create", "refused": true}, {"repo": "other/repo", "call": "gh issue new", "refused": true}]' \
  "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["github_writes"]')" "github_writes"
e2e_expect_equal "api graphql -f query={ viewer { login } }" "$(cat "$E2E_BIN/gh-real.log" 2>/dev/null)" "calls that reached the real gh: the GraphQL read alone"
e2e_expect_equal "0" "$(grep -c 'protocol .https. is not allowed\|transport .https. not allowed' "$E2E_BIN/claude-script.out")" "GitHub pushes that reached the real git (refused there by the scratch HOME's transport rule)"
e2e_expect_equal "probe" "$(cd "$E2E_REPO/.flow/factory/evidence/P3-1/work/other.git" 2>/dev/null && command git for-each-ref --format='%(refname:short)' refs/heads)" "the local-path push reached the real git"
e2e_expect_equal "4" "$(grep -c 'refused git push -q' "$E2E_BIN/claude-script.out")" "the shim's refusals of the four pushes reached the worker"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --writes-only-to probe-fixture/sandbox
e2e_expect_out "PROBES_REFUSED_WRITE=P3 probe-fixture/no-such-repo git push -q origin HEAD:refs/heads/probe"
e2e_expect_out "PROBES_REFUSED_WRITE=P3 unresolved/unresolved POST graphql"
e2e_expect_no_out "write_outside_sandbox"

# L16 probe --launch into a group replaces the group's keyed_on with its own
# keys, dropping the launch context and the sandbox, and gives a group whose
# probes run no model a model key, so the group's other probes read as
# stale on the model and are never run again to clear it.
_flow_test_begin "probe runner: a --launch into the environment group keeps its other keys and adds no model (L16)"
_fp_runner_scenario fp-run-launch-env "the environment group holds a launch context, and a --launch P11 --group environment is killed at its time limit: the group keeps launch_context, gains no model key, and no probe is stale on the model or the launch context"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["groups"]["environment"]["keyed_on"]["launch_context"] = "launchd"; d["probes"]["P13"]["group"] = "environment"' stamp
printf 'sleep 30\n' > "$E2E_BIN/claude-behaviour"
e2e_run_bin bin/flow-factory.sh probe --launch P11 --group environment --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 0.5 --timeout-seconds 3 --kill-after-seconds 1
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out '"outcome": "timeout"'
e2e_expect_equal "launchd no-model" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["groups"]["environment"]["keyed_on"].get("launch_context"),
  "model" if "model" in d["groups"]["environment"]["keyed_on"] else "no-model")')" "the environment group's launch_context and model key"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_no_out "PROBES_STALE=P13 model"
e2e_expect_no_out "PROBES_STALE=P13 launch_context"

_flow_test_begin "probe runner: --cap-usd above the recorded cap does not lift it (L12)"
_fp_runner_scenario fp-run-cap-above "with \$24 spent of a recorded \$25 cap, --cap-usd 30 and a \$2 run limit, the run is not started and the record keeps cap_usd 25"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24'
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 2 --cap-usd 30 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run budget" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P5"]["result"], d["probes"]["P5"]["reason"])')" "P5"
e2e_expect_equal "25" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["cap_usd"]')" "cap_usd"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
e2e_describe "a later call with no --cap-usd keeps a lower cap recorded earlier"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"].update(spent_usd=3, cap_usd=4)'
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 2 --timeout-seconds 10
e2e_expect_equal "not_run 4" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P4"]["result"], d["spend"]["cap_usd"])')" "P4 and cap_usd with no --cap-usd"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts with no --cap-usd"

_flow_test_begin "probe runner: the launch environment is cleaned and limited (L5)"
_fp_runner_scenario fp-run-env "a variable the caller sets does not reach claude, the provider settings do, and the limits and stream-json output are on the command"
e2e_run_bin FP_PRIVATE=leaked ANTHROPIC_BASE_URL=http://127.0.0.1:9 bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1 --max-turns 3 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "" "$(grep '^FP_PRIVATE=' "$E2E_BIN/claude-env.txt")" "FP_PRIVATE in claude's environment"
e2e_expect_equal "ANTHROPIC_BASE_URL=http://127.0.0.1:9" "$(grep '^ANTHROPIC_BASE_URL=' "$E2E_BIN/claude-env.txt")" "ANTHROPIC_BASE_URL in claude's environment"
FP_FIRST=$(grep '^PATH=' "$E2E_BIN/claude-env.txt" | sed 's/^PATH=//; s/:.*//')
e2e_expect_equal "shim" "${FP_FIRST##*/}" "the first PATH entry is the shim directory"
e2e_expect_equal "yes" "$([ -x "$FP_FIRST/gh" ] && [ -x "$FP_FIRST/git" ] && echo yes || echo no)" "the shim directory holds gh and git"
FP_ARGS=$(cat "$E2E_BIN/claude-launches.log")
FP_HAS=no
case "$FP_ARGS" in *"-p "*"--output-format stream-json --verbose"*"--max-turns 3 --max-budget-usd 1"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the command has -p, stream-json and both limits ($FP_ARGS)"
e2e_expect_equal "Say hello." "$(cat "$E2E_BIN/claude-prompt.txt")" "the prompt arrives on stdin"
e2e_expect_out '"cost_usd": 0.42'

_flow_test_begin "probe runner: every run names its model, claude-opus-5-5 unless --model names another (L3)"
_fp_runner_scenario fp-run-model "claude's own default model changes between releases, so the runner passes \
--model claude-opus-5-5, or the model --model gives"
FP_LAUNCH=(bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt"
  --max-budget-usd 1 --timeout-seconds 10)
e2e_run_bin "${FP_LAUNCH[@]}"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "1" "$(grep -c -- '--model claude-opus-5-5\( \|$\)' "$E2E_BIN/claude-launches.log")" \
  "--model claude-opus-5-5 on the run"
e2e_run_bin "${FP_LAUNCH[@]}" --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status with --model ($E2E_ERR)"
e2e_expect_equal "--model claude-sonnet-5-5" "$(sed -n 2p "$E2E_BIN/claude-launches.log" | grep -o -- '--model [^ ]*')" \
  "the model --model gives, alone"

_flow_test_begin "probe runner: a run is charged what it spent since the session's last result (L14)"
FP_D="the result reports \$0.42 in total_cost_usd and, in model_usage_since_last_result, \$0.03 on one model"
FP_D+=" and \$0.01 on another: the run is charged \$0.04; then results whose since-last figures cannot be read"
FP_D+=" (a model with no cost, a cost that is not a number, a negative cost, no model at all) are each charged"
FP_D+=" the \$0.42 total"
_fp_runner_scenario fp-run-since-last "$FP_D"
FP_LAUNCH=(bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt"
  --max-budget-usd 1 --timeout-seconds 30)
printf '%s\n' '{"claude-opus-5-5": {"costUSD": 0.03, "inputTokens": 2}, "claude-haiku-5-5": {"costUSD": 0.01}}' \
  > "$E2E_BIN/claude-since-last"
e2e_run_bin "${FP_LAUNCH[@]}"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_out '"cost_usd": 0.04,'
e2e_expect_equal "0.04" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
FP_SPENT=0.04
for FP_SINCE in '{"claude-opus-5-5": {"costUSD": 0.03}, "claude-haiku-5-5": {"inputTokens": 5}}' \
    '{"claude-opus-5-5": {"costUSD": "0.03"}}' '{"claude-opus-5-5": {"costUSD": -0.03}}' '{}'; do
  e2e_describe "model_usage_since_last_result is $FP_SINCE: the run is charged its total"
  printf '%s\n' "$FP_SINCE" > "$E2E_BIN/claude-since-last"
  e2e_run_bin "${FP_LAUNCH[@]}"
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
  e2e_expect_out '"cost_usd": 0.42,'
  FP_SPENT=$(python3 -c 'import sys; from decimal import Decimal
print((Decimal(sys.argv[1]) + Decimal("0.42")).normalize())' "$FP_SPENT")
  e2e_expect_equal "$FP_SPENT" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
done

_flow_test_begin "probe runner: a run the API refused has the outcome api_error and costs what it reports (L3)"
_fp_runner_scenario fp-run-apierror "the stand-in ends as Claude Code does at a usage limit: an is_error \
result of subtype success with api_error_status 429 and no cost: the outcome is api_error, not error, and \
nothing is charged"
printf 'apierror\n' > "$E2E_BIN/claude-behaviour"
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" \
  --max-budget-usd 1 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_out '"outcome": "api_error"'
e2e_expect_out '"cost_usd": 0,'
e2e_expect_equal "0" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"

_flow_test_begin "probe runner: a run with no result event is charged its budget limit (L3)"
_fp_runner_scenario fp-run-noresult "the stand-in exits without a result event: the run is charged its \$0.7 limit"
printf 'noresult\n' > "$E2E_BIN/claude-behaviour"
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 0.7 --timeout-seconds 10
e2e_expect_out '"outcome": "no_result"'
e2e_expect_equal "0.7" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"

_flow_test_begin "probe runner: a run that never started is charged nothing (L13)"
_fp_runner_scenario fp-run-noevent "the stand-in exits 1 before printing any event, as claude does when it cannot \
start: the outcome is not_started, nothing is charged although the run's limit is \$0.7, and P4 is given no result"
printf 'noevent\n' > "$E2E_BIN/claude-behaviour"
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" \
  --max-budget-usd 0.7 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_out '"outcome": "not_started"'
e2e_expect_out '"cost_usd": 0,'
e2e_expect_equal "0 no 1" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["spend"]["spent_usd"],
  "yes" if "P4" in d["probes"] else "no")') $(_fp_launches)" "spent_usd, a P4 entry and claude -p starts"
_fp_runner_scenario fp-run-nolaunch "the timeout program answers --version and then can no longer be run, so the \
run's process is never started: the launch is refused with launch_failed, claude never starts and no record or \
spend is written"
cat > "$E2E_BIN/timeout" <<'SH'
#!/bin/bash
# Answers --version once, then takes away its own permission to run.
if [ "${1:-}" = --version ]; then printf '%s\n' "timeout (GNU coreutils) 9.5"; chmod -x "$0"; exit 0; fi
exit 125
SH
chmod +x "$E2E_BIN/timeout"
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" \
  --max-budget-usd 0.7 --timeout-seconds 10
e2e_expect_equal "5" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "FACTORY_REFUSED=launch_failed"
e2e_expect_equal "0 no" "$(_fp_launches) $([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" \
  "claude -p starts and a record written"

_flow_test_begin "probe runner: an interrupt while the run's process is being started charges the run's limit (L15)"
_fp_runner_scenario fp-run-start-interrupt "the inject fixture raises KeyboardInterrupt in subprocess.Popen once it \
has started the run's process, as an interrupt that lands before Popen returns does: the probe stops, and the run, \
whose claude was started, is charged its \$0.7 limit"
_fp_inject 'popen --max-budget-usd'
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" \
  --max-budget-usd 0.7 --timeout-seconds 10
FP_I=0
while [ "$(_fp_launches)" = 0 ] && [ "$FP_I" -lt 50 ]; do sleep 0.1; FP_I=$((FP_I + 1)); done
e2e_expect_err "KeyboardInterrupt"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "0.7" "$(if [ -e "$E2E_REPO/$FP_REC" ]; then _fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]'; \
  else echo "no record"; fi)" "spent_usd"

_flow_test_begin "probe runner: the stream's last result event is the run's result; other lines are skipped (L3)"
_fp_runner_scenario fp-run-tworesult "the stand-in prints a plain-text line, a line starting with { that is not JSON (cost 0.99), a result costing 0.11 and then one costing 0.37: the run costs 0.37"
printf 'tworesult 0.37\n' > "$E2E_BIN/claude-behaviour"
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out '"outcome": "completed"'
e2e_expect_out '"cost_usd": 0.37'
e2e_expect_equal "0.37" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"

_flow_test_begin "probe runner: a missing tool is refused by name before anything runs (L4)"
for FP_TOOL in jq claude gh; do
  _fp_runner_scenario "fp-run-missing-$FP_TOOL" "with $FP_TOOL off PATH, probe --launch refuses and names it"
  FP_PATH=$(e2e_path_without "$FP_TOOL")
  e2e_run_bin PATH="$FP_PATH" bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1
  e2e_expect_equal "5" "$E2E_RC" "exit status"
  e2e_expect_line "FACTORY_REFUSED=tool_missing $FP_TOOL"
  e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
  e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
done
_fp_runner_scenario fp-run-missing-timeout "with neither timeout nor gtimeout on PATH, probe --launch refuses and names both"
FP_PATH=$(e2e_path_without timeout gtimeout)
e2e_run_bin PATH="$FP_PATH" bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_line "FACTORY_REFUSED=tool_missing timeout (or gtimeout)"

_flow_test_begin "probe runner: an empty prompt is refused (L5)"
_fp_runner_scenario fp-run-empty-prompt "an empty prompt file is never handed to a paid run"
: > "$E2E_DIR/prompt.txt"
e2e_run_bin bin/flow-factory.sh probe --launch P4 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=prompt_empty"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"

_flow_test_begin "probe runner: a new record is created in the main checkout and keyed on tool versions (L7, L8)"
_fp_runner_scenario fp-run-worktree "run from a linked worktree with no record: the record lands in the main checkout, validates, and keys the group on every tool version"
printf 'sleep 30\n' > "$E2E_BIN/claude-behaviour"
(cd "$E2E_REPO" && git worktree add -q "$E2E_DIR/wt" -b wt-branch) >/dev/null 2>&1
FP_MAIN="$E2E_REPO"
E2E_REPO="$E2E_DIR/wt"
e2e_run_bin bin/flow-factory.sh probe --launch P1 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 0.25 --timeout-seconds 1 --kill-after-seconds 1
E2E_REPO="$FP_MAIN"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "no" "$([ -e "$E2E_DIR/wt/$FP_REC" ] && echo yes || echo no)" "a record in the worktree"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the main checkout's record validates against the schema"
e2e_expect_equal "2.1.322 (Claude Code)" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["platform"]["keyed_on"]["claude_version"]')" "claude_version"
e2e_expect_equal "gh version 2.80.0 (2026-10-01)" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["platform"]["keyed_on"]["gh_version"]')" "gh_version"
e2e_expect_equal "timeout (GNU coreutils) 9.5" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["platform"]["keyed_on"]["timeout_version"]')" "timeout_version"
e2e_expect_equal "ok" "$(_fp_get "$E2E_REPO/$FP_REC" '"ok" if all(d["groups"]["platform"]["keyed_on"].get(k) for k in ("git_version", "jq_version", "interpreter_version", "timeout_path")) and d["groups"]["platform"]["keyed_on"]["interpreter"].startswith("/") else d["groups"]["platform"]["keyed_on"]')" "git, jq, timeout path and interpreter recorded"
e2e_expect_equal "25" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["cap_usd"]')" "default cap_usd"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_line "PROBES_CHECK_FAIL=missing_probe P2"
e2e_expect_no_line "PROBES_CHECK_FAIL=schema"

_flow_test_begin "probe record: a probe whose result disagrees with its parts fails (R9)"
_fp_verify_case fp-verify-parts-ok "P3 recorded no-go with a no-go part passes" \
  'd["probes"]["P3"].update(result="no-go", fallback="the factory refuses to start workers", parts={"gh_auth_status": {"result": "go", "reason": "ok"}, "worker_token": {"result": "no-go", "reason": "token can write"}})' \
  0 "PROBES_RECORD=ok"
_fp_verify_case fp-verify-parts-mismatch "P3 recorded go while a part is no-go fails" \
  'd["probes"]["P3"]["parts"] = {"gh_auth_status": {"result": "go", "reason": "ok"}, "worker_token": {"result": "no-go", "reason": "token can write"}}' \
  1 "PROBES_CHECK_FAIL=parts_mismatch P3 no-go"

# The environment group, `probe --environment --sandbox <owner/repo>`: P11,
# P3 without the sandbox writes, P7 and P15, and with --launch-context, P13.
# Every scenario stubs the Keychain (security) and points the token check at
# a local stub server, so no scenario reads a real Keychain or reaches GitHub.
#
# Ways it can be wrong, written down before the checks:
#   E1 P11 records a shim, an interpreter older than 3.14, or one chosen by a
#      .python-version or PYENV_VERSION; or it records the interpreter without
#      saying which candidates it turned down and why
#   E2 the token check reads any 4xx as "cannot write", so a token that gets
#      422 (it had the permission; only the body was refused) is recorded go
#   E3 the token check is go without every one of the three writes answering
#      403, or sends them to a repository other than the sandbox
#   E4 the token reaches the record, the evidence, stdout or stderr
#   E5 a missing Keychain item stops the other P3 parts, is recorded as
#      anything but not_run with reason token-missing, or still sends requests
#   E6 a P3 part ignores its command's exit status (a failing gh auth status
#      is go), or P3's result is not computed from its parts
#   E7 signing is checked only when no signing is set up, or a signer that
#      works only with the SSH agent is go, or the config is read where an
#      includeIf that holds in the main checkout's worktrees does not apply
#   E8 P7's two jobs share a ledger, an append is lost under 50 concurrent
#      calls, an entry lands in the default ledger, or P7 is go although its
#      go condition needs the phase 1 launcher
#   E9 P15's comparison runs a git command in the job clone first (the planted
#      fsmonitor fires), misses a planted key, or P15 is go although its go
#      condition needs the engine
#   E10 the probe changes the scratch repository's HEAD or git config
#   E11 --launch-context records P13 from an ordinary shell instead of only
#      printing what to load, records P13 as go although its go condition
#      needs the scheduled runner, or starts a paid claude -p on every load
#      or cron tick although nothing P13 is keyed on has changed; or a load
#      or tick skips P13 as current because the environment group's keyed_on
#      matches, while P13's own keyed_on, or one of its parts', does not or
#      is missing
#   E12 flow's own git or gh wrapper, first on PATH in a Claude Code session,
#      is taken for the real program, so it and the logging shim run each
#      other
#   E13 a --sandbox the decision journal does not approve still gets the
#      Keychain token sent to it, or is stored as keyed_on.sandbox
#   E14 the push check proves only that origin can be read: a credential that
#      reads origin but cannot push to it is go, or the dry run creates the
#      branch, or git fetch is never tried
#   E15 --github-api accepts a host that is not GitHub, so the worker token is
#      sent off GitHub
#   E16 a P3 that is not run (P11 no-go) or that stops part way replaces the
#      whole entry with a bare not_run, losing the GitHub write group's
#      sandbox parts, its sandbox writes and the earlier evidence
#   E17 a check whose git, gh or HTTP call got no answer, or whose clone or
#      config read failed, is recorded go or no-go with a fallback, as if
#      what it checks had been seen; or a launch-context claude -p the API
#      refused is no-go or charged
#   E18 P15's comparison names only the keys on a list, or reads only
#      .git/config, so a key off the list, or a key in .git/config.worktree
#      (which git reads once extensions.worktreeConfig is set), goes unnamed
#   E19 P15 does not check that a worker-style git config in the job clone
#      leaves the main checkout's config byte for byte unchanged, or that the
#      job clone still reads every object after the main checkout runs git gc
#      --prune=now; or it calls the prune check go although the main checkout
#      lost nothing the clone holds; or the moved origin ref, which needs the
#      engine's gate, is left out instead of deferred to its phase
#   E20 P13's claude -p ignores --model and runs on claude-opus-5-5, or the
#      launchd plist and cron line that run P13 leave the model out
#   E21 a launch-context claude -p that exits before printing any event (no
#      credentials there) is recorded not_run, or charged, so P13 names no
#      fallback although claude cannot run in that context
#   E22 a signer that waits for input no worker can give (git commit -S
#      outlives its time limit) is recorded not_run, as if nothing had been
#      seen, instead of no-go naming the wait
#   E23 the signing check goes on when it cannot find the main checkout's
#      objects (its git rev-parse --git-common-dir got no answer or failed),
#      so the commit fails to read HEAD and signing is recorded no-go
#      although no signature was tried
#   E24 a P13 check that cannot make its scratch repository (the planted
#      worktree, the push source) stops the launch-context run with exit 5
#      and records no P13, losing the parts it had already seen
#   E25 P7's record calls are each waited for in turn up to 600 s whatever
#      --call-timeout-seconds says, so stuck calls hold the run for hours; or
#      a call stopped at its time limit, a record call or a trust check, has
#      its children left running
#   E26 the Keychain read of P3's token check waits its own 60 s whatever
#      --call-timeout-seconds says, and a read that outlived its limit is
#      said not to have run
#   E27 a dry-run push that moved a ref on origin and then got no answer is
#      recorded not_run, as if nothing had been seen, although git ls-remote
#      shows the branch it created
#   E29 a command that exited, while a program it started in a session of
#      its own still holds its output, is taken for one that got no answer
#   E30 a P13 that raises loses the parts it had already seen, or records
#      its stopped run with no cost, or charges its budget limit twice
#   E28 a git call in P3 that gets no answer part way (the rev-parse that
#      reads the pushed commit, the git init of its scratch repository) stops
#      P3 after other parts were seen, so their results (a no-go gh auth
#      status) are dropped and the token check never runs

FP_KEYCHAIN_VALUE="fp-fixture-keychain-value-7c1d0e"
# The launch-context runs start tests/fixtures/factory/detach.py with the
# interpreter the wrapper resolves, never with python3: a version manager's
# python3 shim puts its own bin directory first on PATH for the program it
# starts, so the launch-context run would resolve another interpreter than the
# ordinary runs and every environment probe would read as stale.
FP_DETACH_PY=$(cd "$REPO_ROOT" && plugins/flow/bin/flow-factory.sh probe --resolve-python 2>/dev/null | sed -n 's/^PYTHON=//p')
FP_DETACH_PY=${FP_DETACH_PY:-python3}
FP_SANDBOX="probe-fixture/sandbox"
FP_API_403='{"replies": [{"status": 200, "body": {"full_name": "probe-fixture/sandbox"}}, {"status": 403, "body": {"message": "Resource not accessible by personal access token"}}]}'

# _fp_journal <sandbox or empty> — a decision journal whose ## Phase 0
# decisions section approves that sandbox (or approves none). A sandbox line
# outside the section names someone/else.
_fp_journal() {
  mkdir -p "$E2E_REPO/.decisions"
  {
    printf '## Specification\n\n- sandbox: someone/else (outside the decisions section)\n\n## Phase 0 decisions\n\n'
    [ -n "$1" ] && printf -- '- sandbox: %s (public, created for the probes)\n' "$1"
    printf -- '- budget: $25 cap on total model spend\n\n## Plan\n\n1. Run the probes.\n'
  } > "$E2E_REPO/.decisions/issue-353.md"
}

# _fp_env_scenario <name> <description> [stub config] — a runner scenario with
# a journal approving the fixture sandbox, the security stand-in holding a
# fake token, a local bare origin, and a stub API server answering with the
# config (default: the GET succeeds and every write gets 403).
_fp_env_scenario() {
  _fp_runner_scenario "$1" "$2"
  _fp_journal "$FP_SANDBOX"
  cp "$FP_FIXTURES/bin/security" "$E2E_BIN/"
  printf '%s\n' "$FP_KEYCHAIN_VALUE" > "$E2E_BIN/security-token"
  (
    _e2e_git_env
    cd "$E2E_DIR" && git init -q --bare origin.git || exit 1
    cd "$E2E_REPO" && git remote add origin "$E2E_DIR/origin.git" && git push -q origin HEAD:refs/heads/main
  ) || _flow_assert_fail "$E2E_NAME: could not give the scratch repository an origin"
  e2e_stub_start api "${3:-$FP_API_403}"
  FP_HEAD_BEFORE=$(cd "$E2E_REPO" && command git rev-parse HEAD)
  FP_CONFIG_BEFORE=$(cksum < "$E2E_REPO/.git/config")
  fe_mask_text "$FP_HEAD_BEFORE" '<scratch HEAD>'
  fe_mask_text "$FP_CONFIG_BEFORE" '<checksum> <size>'
}

# _fp_env_run [NAME=value ...] -- [probe arguments] — probe --environment
# against the stub API and the fixture sandbox.
_fp_env_run() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  e2e_run_bin ${envs[@]+"${envs[@]}"} bin/flow-factory.sh probe --environment --sandbox "$FP_SANDBOX" \
    --github-api "$(e2e_stub_url api)" "$@"
}

# _fp_env_after — the checks every environment scenario ends with (E4, E10).
_fp_env_after() {
  e2e_expect_equal "$FP_HEAD_BEFORE" "$(cd "$E2E_REPO" && command git rev-parse HEAD)" "the scratch repository's HEAD"
  e2e_expect_equal "$FP_CONFIG_BEFORE" "$(cksum < "$E2E_REPO/.git/config")" "the scratch repository's git config"
  e2e_expect_equal "" "$(grep -rlF "$FP_KEYCHAIN_VALUE" "$E2E_REPO/.flow" 2>/dev/null)" "files under .flow holding the token"
  e2e_expect_equal "no" "$(printf '%s\n%s' "$E2E_OUT" "$E2E_ERR" | grep -qF "$FP_KEYCHAIN_VALUE" && echo yes || echo no)" "the token in stdout or stderr"
}

# _fp_stub_calls — "METHOD path" for each request the stub API received.
_fp_stub_calls() {
  python3 - "$(e2e_stub_log api)" <<'PY'
import json, sys
for ln in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(ln)
    print(r["method"], r["path"])
PY
}

# _fp_stub_bearers — the distinct Authorization headers the stub API saw.
_fp_stub_bearers() {
  python3 - "$(e2e_stub_log api)" <<'PY'
import json, sys
seen = sorted({json.loads(ln)["headers"].get("authorization", "") for ln in open(sys.argv[1], encoding="utf-8")})
print("|".join(seen))
PY
}

_flow_test_begin "environment: P11 records a native 3.14 interpreter, not a shim on PATH (E1)"
# An interpreter older than 3.14, found here so the fake shim can run it.
FP_OLD_PY=""
for FP_CAND in python3.13 python3.12 python3.11 python3.10 /usr/bin/python3; do
  FP_V=$(cd / && "$FP_CAND" -E -c 'import os, sys; print("%d %s" % (sys.version_info >= (3, 14), os.path.realpath(sys.executable)))' 2>/dev/null) || continue
  case "$FP_V" in "0 /"*) FP_OLD_PY="${FP_V#0 }"; break ;; esac
done
if [ -z "$FP_OLD_PY" ]; then
  printf '%s\n' "SKIP environment P11 shim scenario: no Python older than 3.14 is installed to stand behind the fake shim"
else
  _fp_env_scenario fp-env-p11-shim "fake pyenv shims are first on PATH: python3 always runs a Python older than 3.14, and python3.14 runs it too whenever PYENV_VERSION is set or the working directory holds a .python-version, as pyenv does, and otherwise runs the interpreter the resolver chose before the shims were planted. With PYENV_VERSION=3.12.9 and a planted worktree naming 3.12.9, P11 records that interpreter and turns the python3 shim down with its reason"
  e2e_run_bin bin/flow-factory.sh probe --resolve-python
  FP_REAL_PY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PYTHON=//p')
  mkdir -p "$E2E_DIR/shims"
  printf '#!/bin/bash\nexec %s "$@"\n' "$FP_OLD_PY" > "$E2E_DIR/shims/python3"
  printf '#!/bin/bash\nif [ -n "${PYENV_VERSION:-}" ] || [ -f .python-version ]; then exec %s "$@"; fi\nexec %s "$@"\n' \
    "$FP_OLD_PY" "$FP_REAL_PY" > "$E2E_DIR/shims/python3.14"
  chmod +x "$E2E_DIR/shims/python3" "$E2E_DIR/shims/python3.14"
  _fp_env_run PATH="$E2E_DIR/shims:$E2E_BIN:$PATH" PYENV_VERSION=3.12.9 -- --only P11 \
    --plant-python-version 3.12.9 --plant-pyenv-version 3.12.9
  e2e_expect_equal "0" "$E2E_RC" "exit status"
  FP_INTERP=$(_fp_get "$E2E_REPO/$FP_REC" 'd["interpreter"]')
  e2e_expect_equal "$FP_REAL_PY" "$FP_INTERP" "the recorded interpreter is the one chosen before the shims were planted"
  e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P11"]["result"]')" "P11 result"
  e2e_expect_equal "yes" "$(cd / && "$FP_INTERP" -E -c 'import sys; print("yes" if sys.version_info >= (3, 14) else "no")' 2>/dev/null)" "the recorded interpreter runs 3.14 or later"
  e2e_expect_equal "no" "$([ "$FP_INTERP" = "$FP_OLD_PY" ] && echo yes || echo no)" "the recorded interpreter is the one the shim runs"
  FP_HAS=no
  case "$FP_INTERP" in */shims/*) FP_HAS=yes ;; esac
  e2e_expect_equal "no" "$FP_HAS" "the recorded interpreter is in a shims directory"
  e2e_expect_equal "$FP_INTERP" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["environment"]["keyed_on"]["interpreter"]')" "keyed_on interpreter"
  e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P11"]["parts"]["planted_worktree"]["result"]')" "the planted worktree part"
  FP_EV=$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P11"]["evidence"]')
  FP_TAB=$(printf '\t')
  FP_SHIMLINE=$(grep -F "${FP_TAB}python3${FP_TAB}rejected${FP_TAB}$E2E_DIR/shims/python3${FP_TAB}" "$E2E_REPO/.flow/factory/$FP_EV/resolution.txt" | head -1)
  FP_HAS=no
  case "$FP_SHIMLINE" in *rejected*shim*"older than 3.14"*) FP_HAS=yes ;; esac
  e2e_expect_equal "yes" "$FP_HAS" "the shim is turned down as a shim running a Python older than 3.14 ($FP_SHIMLINE)"
  e2e_expect_equal "yes" "$(grep -q '^planted' "$E2E_REPO/.flow/factory/$FP_EV/resolution.txt" && echo yes || echo no)" "the resolution from the planted worktree is in the evidence"
  e2e_expect_equal "absent" "$(_fp_get "$E2E_REPO/$FP_REC" '"present" if "P7" in d["probes"] else "absent"')" "P7 with --only P11"
  _fp_env_after
fi

_flow_test_begin "environment: a worker token that gets 422 can write, so P3 is no-go (E2, E4)"
_fp_env_scenario fp-env-token-422 "the GET succeeds, labels gets 403, pulls and contents get 422: the token part and P3 are no-go, token can write" \
  '{"replies": [{"status": 200, "body": {"full_name": "probe-fixture/sandbox"}}, {"status": 403, "body": {"message": "Resource not accessible by personal access token"}}, {"status": 422, "body": {"message": "Validation Failed"}}, {"status": 422, "body": {"message": "Validation Failed"}}]}'
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]')" "token part result"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "token can write" in d["probes"]["P3"]["parts"]["worker_token"]["reason"] else d["probes"]["P3"]["parts"]["worker_token"]["reason"]')" "token part reason says the token can write"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "the factory refuses to start workers" in d["probes"]["P3"].get("fallback", "") else d["probes"]["P3"]')" "P3 fallback"
e2e_expect_equal "GET /repos/probe-fixture/sandbox
POST /repos/probe-fixture/sandbox/labels
POST /repos/probe-fixture/sandbox/pulls
PUT /repos/probe-fixture/sandbox/contents/flow-factory-probe-write-check.txt" "$(_fp_stub_calls)" "the requests the stub API received"
e2e_expect_equal "Bearer $FP_KEYCHAIN_VALUE" "$(_fp_stub_bearers)" "every request carries the Keychain token"
e2e_expect_equal "find-generic-password -s flow-factory-gh-token -w" "$(cat "$E2E_BIN/security-calls.log")" "the Keychain lookup"
_fp_env_after
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_no_out "PROBES_CHECK_FAIL=parts_mismatch"
e2e_expect_no_out "PROBES_CHECK_FAIL=schema"

_flow_test_begin "environment: a worker token that gets 403 on all three writes cannot write (E3, E6)"
_fp_env_scenario fp-env-token-403 "the GET succeeds and labels, pulls and contents all get 403: the token part is go, and so is P3"
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]')" "token part result"
e2e_expect_equal '{"gh_api_user": "go", "gh_auth_status": "go", "git_fetch": "go", "git_ls_remote": "go", "git_push_dry_run": "go", "git_push_local": "go", "signing": "go", "worker_token": "go"}' \
  "$(_fp_get "$E2E_REPO/$FP_REC" '{k: v["result"] for k, v in sorted(d["probes"]["P3"]["parts"].items())}')" "every P3 part"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
e2e_expect_equal "4" "$(e2e_stub_requests api)" "requests to the stub API"
e2e_expect_equal "[]" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["github_writes"]')" "github_writes"
_fp_env_after

# E31 A server error on the token check is read as the token's answer: a
# GET answered 503 records "token cannot read", and a write answered 502
# among 403s records "did not tell the cases apart", both no-go.
_flow_test_begin "environment: a token check answered 5xx is not run, never no-go (E31)"
_fp_env_scenario fp-env-token-503 "the GET answers 503: the token part is not_run and no write is tried" \
  '{"replies": [{"status": 503, "body": {"message": "Service Unavailable"}}]}'
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run 1" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]') $(e2e_stub_requests api)" \
  "token part result and requests to the stub API"
e2e_expect_equal "no" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if d["probes"]["P3"].get("fallback") else "no"')" "P3 names a fallback"
_fp_env_after
_fp_env_scenario fp-env-token-502 "labels and contents answer 403 and pulls 502: the token part is not_run, never no-go" \
  '{"replies": [{"status": 200, "body": {"full_name": "probe-fixture/sandbox"}}, {"status": 403, "body": {"message": "Resource not accessible by personal access token"}}, {"status": 502, "body": {"message": "Bad Gateway"}}, {"status": 403, "body": {"message": "Resource not accessible by personal access token"}}]}'
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]')" "token part result"
_fp_env_after

# E32 --github-api takes any https://<host>/api/v3, so a mistyped or
# suggested host receives the worker token from the Keychain.
_flow_test_begin "environment: a GitHub Enterprise address the journal does not approve is refused before the token is read (E32)"
_fp_env_scenario fp-env-api-unapproved "--github-api https://127.0.0.1:1/api/v3 with no github_api: line in the journal: refused github_api_not_approved with exit 5, the Keychain is not read and no request is sent"
e2e_run_bin bin/flow-factory.sh probe --environment --sandbox "$FP_SANDBOX" --github-api https://127.0.0.1:1/api/v3 --only P3
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=github_api_not_approved"
e2e_expect_equal "no" "$([ -s "$E2E_BIN/security-calls.log" ] && echo yes || echo no)" "the Keychain was read"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests to the stub API"
e2e_describe "with - github_api: https://127.0.0.1:1/api/v3 under the decisions heading, the address is taken: the run passes the check, and the token part is not run because nothing answers there"
printf -- '- github_api: https://127.0.0.1:1/api/v3\n' > "$E2E_DIR/api-line"
python3 - "$E2E_REPO/.decisions/issue-353.md" "$E2E_DIR/api-line" <<'PY'
import sys
path, line = sys.argv[1], open(sys.argv[2]).read()
text = open(path).read().replace("## Phase 0 decisions\n\n", "## Phase 0 decisions\n\n" + line, 1)
open(path, "w").write(text)
PY
e2e_run_bin bin/flow-factory.sh probe --environment --sandbox "$FP_SANDBOX" --github-api https://127.0.0.1:1/api/v3 --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_no_out "github_api_not_approved"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]')" "token part result"

_flow_test_begin "environment: a missing Keychain item leaves the token part not run and the rest running (E5)"
_fp_env_scenario fp-env-token-missing "security exits 44: the token part is not_run with reason token-missing, no request is sent, the other parts still run, and P3 is not go"
printf 'missing\n' > "$E2E_BIN/security-behaviour"
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]')" "token part result"
e2e_expect_equal "token-missing" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["reason"]')" "token part reason"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests to the stub API"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["gh_auth_status"]["result"]')" "gh auth status part"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["git_push_local"]["result"]')" "local push part"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
_fp_env_after

_flow_test_begin "environment: a failing gh auth status makes its part and P3 no-go (E6)"
_fp_env_scenario fp-env-gh-fails "gh auth status exits 1: that part is no-go, and P3 is no-go although the token cannot write"
printf 'auth status\n' > "$E2E_BIN/gh-fail"
_fp_env_run -- --only P3
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["gh_auth_status"]["result"]')" "gh auth status part"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["worker_token"]["result"]')" "token part"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
_fp_env_after

_flow_test_begin "environment: signing set up with a signer that needs no agent is go (E7)"
_fp_env_scenario fp-env-sign-ok "the global git config signs every commit with the stand-in signer: the signing part makes a signed commit with no agent and no terminal"
cp "$FP_FIXTURES/bin/signer" "$E2E_BIN/"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
_fp_env_run SSH_AUTH_SOCK="$E2E_DIR/agent.sock" -- --only P3
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["signing"]["result"]')" "signing part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "signed" in d["probes"]["P3"]["parts"]["signing"]["reason"] and "not set up" not in d["probes"]["P3"]["parts"]["signing"]["reason"] else d["probes"]["P3"]["parts"]["signing"]["reason"]')" "the reason says a signed commit was made"
_fp_env_after

_flow_test_begin "environment: a signer that needs the SSH agent is no-go (E7)"
_fp_env_scenario fp-env-sign-agent "the signer works only with SSH_AUTH_SOCK set: the signing part is no-go and names the agent"
cp "$FP_FIXTURES/bin/signer" "$E2E_BIN/"
: > "$E2E_BIN/signer-needs-agent"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
_fp_env_run SSH_AUTH_SOCK="$E2E_DIR/agent.sock" -- --only P3
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["signing"]["result"]')" "signing part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "SSH_AUTH_SOCK" in d["probes"]["P3"]["parts"]["signing"]["reason"] else d["probes"]["P3"]["parts"]["signing"]["reason"]')" "the reason names SSH_AUTH_SOCK"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
_fp_env_after

_flow_test_begin "environment: signing whose worktree cannot name the main checkout's objects is not_run (E23)"
FP_D="signing is set up with a signer that needs no agent, and git rev-parse in the throwaway signing worktree gets"
FP_D+=" no answer (it sleeps past --call-timeout-seconds 8): the signing part is not_run naming that call, never"
FP_D+=" no-go, and P3 names no fallback"
_fp_env_scenario fp-env-sign-common-dir "$FP_D"
cp "$FP_FIXTURES/bin/signer" "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'signing rev-parse\n' > "$E2E_BIN/git-no-answer-in"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
_fp_env_run SSH_AUTH_SOCK= -- --only P3 --call-timeout-seconds 8
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes none" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (
  p["parts"]["signing"]["result"], "yes" if "git rev-parse --git-common-dir in the throwaway worktree did not answer"
  in p["parts"]["signing"]["reason"] else p["parts"]["signing"]["reason"],
  "fallback" if p.get("fallback") else "none"))(d["probes"]["P3"])')" "the signing part, its reason and P3's fallback"
_fp_env_after

_flow_test_begin "environment: a signer that waits for input no worker can give is no-go, never not_run (E22)"
FP_D="the signer waits 60 s before doing anything, as one waiting for a passphrase or a touch does, so git commit"
FP_D+=" -S outlives --call-timeout-seconds 8: the signing part is no-go naming the time limit and the wait, and P3"
FP_D+=" is no-go naming the signing fallback"
_fp_env_scenario fp-env-sign-hangs "$FP_D"
cp "$FP_FIXTURES/bin/signer" "$E2E_BIN/"
: > "$E2E_BIN/signer-hangs"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
_fp_env_run SSH_AUTH_SOCK= -- --only P3 --call-timeout-seconds 8
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda s: "%s %s" % (s["result"], "yes"
  if "git commit -S did not answer (timed out after 8 s)" in s["reason"] and "the signer waits for input" in s["reason"]
  else s["reason"]))(d["probes"]["P3"]["parts"]["signing"])')" "the signing part and its reason"
e2e_expect_equal "no-go yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"], "yes"
  if "names the signing cause" in (p.get("fallback") or "") else p.get("fallback")))(d["probes"]["P3"])')" \
  "P3's result and fallback"
_fp_env_after

# _fp_no_local_signing — drop the commit.gpgsign false the e2e library sets
# in the scratch repository's own config, which a worktree of it reads and
# which would otherwise hide what the global config turns on.
_fp_no_local_signing() {
  (cd "$E2E_REPO" && command git config --unset commit.gpgsign)
  FP_CONFIG_BEFORE=$(cksum < "$E2E_REPO/.git/config")
  fe_mask_text "$FP_CONFIG_BEFORE" '<checksum> <size>'
}

# git config --global does not follow [include] unless asked to, so a check
# that reads only the global file sees signing as off and records go.
_flow_test_begin "environment: signing turned on only through an included config file is checked (E7)"
_fp_env_scenario fp-env-sign-include "the global git config sets nothing itself and includes a file that turns on commit.gpgsign with a signing key and a signer that needs the SSH agent: the signing part tries a signed commit and is no-go naming SSH_AUTH_SOCK, never go as not set up"
cp "$FP_FIXTURES/bin/signer" "$E2E_BIN/"
: > "$E2E_BIN/signer-needs-agent"
printf '[include]\n\tpath = %s\n' "$E2E_HOME/signing.inc" > "$E2E_HOME/.gitconfig"
_fp_no_local_signing
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/signing.inc"
_fp_env_run SSH_AUTH_SOCK="$E2E_DIR/agent.sock" -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["signing"]["result"]')" "signing part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "SSH_AUTH_SOCK" in d["probes"]["P3"]["parts"]["signing"]["reason"] else d["probes"]["P3"]["parts"]["signing"]["reason"]')" "the reason names SSH_AUTH_SOCK"
FP_EV=$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["evidence"]')
e2e_expect_equal "true true" "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" \
  '"%s %s" % (str(d["signing"]["commit_gpgsign"]).lower(), str(d["signing"]["signing_key_set"]).lower())')" \
  "commit.gpgsign and the signing key, as facts"
_fp_env_after

_flow_test_begin "environment: a recorded P11 no-go stops P3 when --only leaves P11 out (E1)"
_fp_env_scenario fp-env-p11-recorded "the record holds P11 no-go from an earlier run and the call is --only P3: P3 is not_run on the P11 prerequisite, the Keychain is not read and no request reaches the stub API"
mkdir -p "$E2E_REPO/.flow/factory"
# The seeded record names no interpreter: replacing a recorded one needs a
# person at a terminal (person_channels L19), which this scenario is not about.
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P11"].update(group="environment", result="no-go", reason="no Python 3.14", fallback="Refuse to enable, and name the missing tool."); del d["interpreter"]'
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "P11" in d["probes"]["P3"]["reason"] else d["probes"]["P3"]["reason"]')" "the reason names P11"
e2e_expect_equal "" "$(cat "$E2E_BIN/security-calls.log" 2>/dev/null)" "Keychain lookups"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests to the stub API"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P11"]["result"]')" "the recorded P11 is kept"
_fp_env_after

_flow_test_begin "environment: P7 keeps two jobs' trust ledgers apart under 50 concurrent appends each (E8)"
_fp_env_scenario fp-env-p7 "two fake jobs, each with its own FLOW_STATE_DIR, record a goal 50 times at once: each ledger holds its own 50 entries, the default ledger none, and P7 is deferred to the launcher's phase"
_fp_env_run -- --only P7
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "deferred" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["result"]')" "P7 result"
e2e_expect_equal "synaptiai/synapti-marketplace#356" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["deferred_to"]')" "P7 deferred_to"
e2e_expect_equal "true" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["stand_in"]')" "P7 stand_in"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["parts"]["isolation"]["result"]')" "isolation part"
FP_EV=$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["evidence"]')
e2e_expect_equal "50 50" "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" '"%d %d" % (d["jobs"]["a"]["own_entries"], d["jobs"]["b"]["own_entries"])')" "entries each job's ledger holds for its own goal"
e2e_expect_equal "0 0" "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" '"%d %d" % (d["jobs"]["a"]["other_entries"], d["jobs"]["b"]["other_entries"])')" "entries for the other job's goal"
e2e_expect_equal "no" "$([ -e "$E2E_HOME/.claude/flow-state/goal-trust.jsonl" ] && echo yes || echo no)" "a default ledger in the scratch HOME"
_fp_env_after

_flow_test_begin "environment: P7 is no-go when the ledger ignores the job's state directory (E8)"
_fp_env_scenario fp-env-p7-shared "the trust script is replaced by one that appends to one file in HOME whatever FLOW_STATE_DIR says: P7 is no-go with its fallback"
e2e_plugin_copy bin/flow-goal-trust.sh '#!/bin/bash
mkdir -p "$HOME/shared-state" && printf "{\"goal_id\": \"x\"}\n" >> "$HOME/shared-state/goal-trust.jsonl"'
_fp_env_run -- --only P7
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["result"]')" "P7 result"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P7"]["parts"]["isolation"]["result"]')" "isolation part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "No shared dir above concurrency 1" in d["probes"]["P7"].get("fallback", "") else d["probes"]["P7"]')" "P7 fallback"
_fp_env_after

_flow_test_begin "environment: P15 catches each planted key before git runs in the clone, and its job clone keeps the main checkout's config and survives a prune (E9, E18, E19)"
FP_D="core.fsmonitor, core.hooksPath, credential.helper, url.<x>.insteadOf, remote.origin.pushurl, a key on no"
FP_D+=" list (submodule.<name>.update) and core.fsmonitor in .git/config.worktree are planted one at a time in a"
FP_D+=" scratch job clone: the comparison names each, with the file it is in, and the fsmonitor marker is absent"
FP_D+=" until git status runs; a worker-style git config in a job clone made with git clone --no-checkout leaves"
FP_D+=" the scratch main checkout's config byte for byte unchanged, and the job clone still reads every object"
FP_D+=" after the main checkout drops a branch and prunes it; the moved origin ref is deferred to the engine's"
FP_D+=" phase, P15 is deferred, and the person's repository is unchanged"
_fp_env_scenario fp-env-p15 "$FP_D"
FP_GIT_SUM=$(cd "$E2E_REPO/.git" && find objects refs -type f -print | LC_ALL=C sort | xargs cksum | cksum)
_fp_env_run -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "deferred" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P15"]["result"]')" "P15 result"
e2e_expect_equal "synaptiai/synapti-marketplace#358" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P15"]["deferred_to"]')" "P15 deferred_to"
e2e_expect_equal "true" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P15"]["stand_in"]')" "P15 stand_in"
FP_EV=$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P15"]["evidence"]')
e2e_expect_equal "config.worktree core.fsmonitor core.hookspath credential.helper remote.origin.pushurl submodule.update url.insteadof" \
  "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" '" ".join(sorted(k for k, v in d["plants"].items() if v["caught"]))')" "the planted keys the comparison caught"
e2e_expect_equal '["config extensions.worktreeconfig", "config.worktree core.fsmonitor"] ["config submodule.probe.update"]' \
  "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" 'd["plants"]["config.worktree"]["violations"]') $(_fp_get \
  "$E2E_REPO/.flow/factory/$FP_EV/facts.json" 'd["plants"]["submodule.update"]["violations"]')" \
  "what the comparison named for the config.worktree and unlisted-key plants"
e2e_expect_equal '{"comparison": "go", "engine_check": "deferred", "main_config_unchanged": "go", "moved_ref": "deferred", "objects_after_prune": "go"}' \
  "$(_fp_get "$E2E_REPO/$FP_REC" '{k: v["result"] for k, v in sorted(d["probes"]["P15"]["parts"].items())}')" "every P15 part"
e2e_expect_equal "synaptiai/synapti-marketplace#358" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P15"]["parts"]["moved_ref"]["deferred_to"]')" \
  "the moved ref part's phase"
e2e_expect_equal "true true true" "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" '" ".join(str(d["job_clone"][k]).lower()
  for k in ("write_seen_in_clone", "main_lost_side_commit", "clone_reads_side_file"))')" \
  "the job clone saw the worker's write, the main checkout lost the dropped commit, and the clone still read it"
fe_mask_text "$FP_GIT_SUM" '<checksum> <size>'
e2e_expect_equal "$FP_GIT_SUM" "$(cd "$E2E_REPO/.git" && find objects refs -type f -print | LC_ALL=C sort | xargs cksum | cksum)" \
  "the person's repository's objects and refs"
e2e_expect_equal "false true" "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" '"%s %s" % (str(d["plants"]["core.fsmonitor"]["marker_before_git"]).lower(), str(d["plants"]["core.fsmonitor"]["marker_after_git_status"]).lower())')" \
  "the fsmonitor marker: absent after the comparison, present once git status runs in the clone"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/.flow/factory/$FP_EV/facts.json" '"yes" if d["git_version"].startswith("git version") else d["git_version"]')" "the git version in the facts"
_fp_env_after

_flow_test_begin "environment: P15 is no-go when the job clone borrows the main checkout's objects and loses them to a prune (E19)"
FP_D="git is a stand-in that makes every clone with --shared, so the job clone borrows the scratch main checkout's"
FP_D+=" objects: after the main checkout drops a branch and prunes it, the clone cannot read the branch's commit;"
FP_D+=" objects_after_prune is no-go, the config parts stay go, and P15 is no-go with the clone fallback"
_fp_env_scenario fp-env-p15-shared "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'shared\n' > "$E2E_BIN/git-clone-mode"
_fp_env_run -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "go go no-go no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: " ".join([p["parts"][k]["result"]
  for k in ("comparison", "main_config_unchanged", "objects_after_prune")] + [p["result"]]))(d["probes"]["P15"])')" \
  "the comparison, the config and prune parts, and P15"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '("yes" if "--no-hardlinks" in d["probes"]["P15"].get("fallback", "")
  else d["probes"]["P15"])')" "P15's fallback names the clone that holds its own objects"
_fp_env_after

_flow_test_begin "environment: P15 is no-go when a worker's git config in the job clone reaches the main checkout (E19)"
FP_D="git is a stand-in that makes every clone a linked worktree of its source, so a worker-style git config"
FP_D+=" in the job clone writes the scratch main checkout's .git/config: main_config_unchanged is no-go naming that"
FP_D+=" file, and P15 is no-go; the worktree's HEAD keeps the dropped branch's commit in the main checkout through"
FP_D+=" the prune, so objects_after_prune is not_run saying so, never go"
_fp_env_scenario fp-env-p15-worktree "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'worktree\n' > "$E2E_BIN/git-clone-mode"
_fp_env_run -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go yes no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (
  p["parts"]["main_config_unchanged"]["result"], "yes" if ".git/config" in p["parts"]["main_config_unchanged"]["reason"]
  else p["parts"]["main_config_unchanged"]["reason"], p["result"]))(d["probes"]["P15"])')" \
  "the config part, its reason naming the file, and P15"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda o: "%s %s" % (o["result"], "yes"
  if "still held the dropped branch" in o["reason"] else o["reason"]))(d["probes"]["P15"]["parts"]["objects_after_prune"])')" \
  "the prune part, when the main checkout lost nothing the clone holds"
_fp_env_after

_flow_test_begin "environment: --launch-context from an ordinary shell prints what to load and records nothing (E11)"
_fp_env_scenario fp-env-lc-print "with no launch context, --launch-context prints a launchd plist and a cron line that run it with the context set, and writes no record"
_fp_env_run -- --launch-context
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_line "LAUNCH_CONTEXT=none"
printf '%s\n' "$E2E_OUT" | sed -n '/^LAUNCHD_PLIST_BEGIN$/,/^LAUNCHD_PLIST_END$/p' | sed '1d;$d' > "$E2E_DIR/agent.plist"
FP_MAIN_REAL=$(cd "$E2E_REPO" && pwd -P)
e2e_expect_equal "launchd --launch-context $FP_MAIN_REAL" "$(python3 - "$E2E_DIR/agent.plist" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
print(p["EnvironmentVariables"]["FLOW_FACTORY_LAUNCH_CONTEXT"], "--launch-context" if "--launch-context" in p["ProgramArguments"] else "-", p["WorkingDirectory"])
PY
)" "the plist sets the context, runs --launch-context, in the main checkout"
FP_CRON=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^CRON_LINE=//p')
FP_HAS=no
case "$FP_CRON" in *FLOW_FACTORY_LAUNCH_CONTEXT=cron*--launch-context*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the cron line sets the context and runs --launch-context ($FP_CRON)"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
_fp_env_after

_flow_test_begin "environment: --launch-context in a launchd context records P13, deferred to the scheduled runner's phase (E11)"
_fp_env_scenario fp-env-lc-run "detached from any terminal with FLOW_FACTORY_LAUNCH_CONTEXT=launchd, P13's checks run, a trivial claude -p is charged, and P13 is deferred"
e2e_describe "run through tests/fixtures/factory/detach.py, which starts it in a new session with no controlling terminal"
_e2e_exec env FLOW_FACTORY_LAUNCH_CONTEXT=launchd "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment \
  --sandbox "$FP_SANDBOX" --github-api "$(e2e_stub_url api)" --launch-context
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "deferred" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P13"]["result"]')" "P13 result"
e2e_expect_equal "synaptiai/synapti-marketplace#356" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P13"]["deferred_to"]')" "P13 deferred_to"
e2e_expect_equal '{"claude_p": "go", "gh_auth_status": "go", "git_fetch": "go", "git_ls_remote": "go", "git_push_dry_run": "go", "interpreter": "go", "signing": "go", "tools": "go", "unmatched_context_refused": "deferred"}' \
  "$(_fp_get "$E2E_REPO/$FP_REC" '{k: v["result"] for k, v in sorted(d["probes"]["P13"]["parts"].items())}')" "every P13 part"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "0.42" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
e2e_expect_equal "launchd" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["environment"]["keyed_on"]["launch_context"]')" "keyed_on launch_context"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if len(d["groups"]["environment"]["keyed_on"]["launch_context_sha256"]) == 64 else "no"')" "keyed_on holds the plist's hash"
_fp_env_after
e2e_describe "the same launchd context runs it again, as each load or tick does: P13 is current, so nothing runs and nothing is spent"
_e2e_exec env FLOW_FACTORY_LAUNCH_CONTEXT=launchd "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment \
  --sandbox "$FP_SANDBOX" --github-api "$(e2e_stub_url api)" --launch-context
e2e_expect_equal "0" "$E2E_RC" "second run's exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out '"current": ["P13"]'
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts after the second run"
e2e_expect_equal "0.42" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd after the second run"

_flow_test_begin "environment: P13's claude_p part is not_run when the API refused the run (E11)"
_fp_env_scenario fp-env-lc-apierror "in a launchd context the trivial claude -p ends as Claude Code ends a \
run refused for a usage limit: the claude_p part is not_run with the API's answer, never no-go, and nothing is charged"
printf 'apierror\n' > "$E2E_BIN/claude-behaviour"
_e2e_exec env FLOW_FACTORY_LAUNCH_CONTEXT=launchd "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" \
  "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment \
  --sandbox "$FP_SANDBOX" --github-api "$(e2e_stub_url api)" --launch-context
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_API_SAID="the API refused the run (usage_limit_reached, HTTP 429)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"],
  "yes" if "'"$FP_API_SAID"'" in p["reason"] else p["reason"]))(d["probes"]["P13"]["parts"]["claude_p"])')" \
  "claude_p part"
e2e_expect_equal "0" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
_fp_env_after

_flow_test_begin "environment: P13's claude -p is on the model --model names, and the plist and cron line carry it (E20)"
FP_D="--launch-context --model claude-sonnet-5-5 from an ordinary shell prints a plist and a cron line that both"
FP_D+=" pass --model claude-sonnet-5-5; run so in a launchd context, P13's claude -p names that model and not"
FP_D+=" claude-opus-5-5"
_fp_env_scenario fp-env-lc-model "$FP_D"
_fp_env_run -- --launch-context --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
printf '%s\n' "$E2E_OUT" | sed -n '/^LAUNCHD_PLIST_BEGIN$/,/^LAUNCHD_PLIST_END$/p' | sed '1d;$d' > "$E2E_DIR/agent.plist"
e2e_expect_equal "claude-sonnet-5-5" "$(python3 - "$E2E_DIR/agent.plist" <<'PY'
import plistlib, sys
a = plistlib.load(open(sys.argv[1], "rb"))["ProgramArguments"]
print(a[a.index("--model") + 1] if "--model" in a else "none")
PY
)" "the model the plist passes"
FP_CRON=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^CRON_LINE=//p')
FP_HAS=no
case "$FP_CRON" in *" --model claude-sonnet-5-5"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the cron line passes the model ($FP_CRON)"
_e2e_exec env FLOW_FACTORY_LAUNCH_CONTEXT=launchd "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" \
  "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment \
  --sandbox "$FP_SANDBOX" --github-api "$(e2e_stub_url api)" --launch-context --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status in the launchd context ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "1 0" "$(grep -c -- '--model claude-sonnet-5-5\( \|$\)' "$E2E_BIN/claude-launches.log") $(grep -c -- \
  '--model claude-opus-5-5' "$E2E_BIN/claude-launches.log")" "P13's launches naming claude-sonnet-5-5, and claude-opus-5-5"
_fp_env_after

_flow_test_begin "environment: flow's own git wrapper first on PATH is passed over for the real git (E12)"
# In a Claude Code session flow puts its tier wrapper first on PATH. The
# wrapper runs the first git on PATH outside a wrapper directory, which would
# be the probe's logging shim, which would run the wrapper again.
_fp_env_scenario fp-env-flow-wrapper "a stand-in flow wrapper directory (hooks/shims beside scripts/lib/tier-runtime.sh) is first on PATH; like flow's, its git runs the first git on PATH outside its own directory, and it refuses to be run again from inside itself: the probe uses the real git, so the wrapper is never run twice in one chain"
mkdir -p "$E2E_DIR/flowplugin/hooks/shims" "$E2E_DIR/flowplugin/hooks/scripts/lib"
: > "$E2E_DIR/flowplugin/hooks/scripts/lib/tier-runtime.sh"
cat > "$E2E_DIR/flowplugin/hooks/shims/git" <<'SH'
#!/bin/bash
own=$(cd "$(dirname "$0")" && pwd -P)
if [ -n "${FP_WRAPPER_SEEN:-}" ]; then
  printf 'loop: %s\n' "$*" >> "$own/../../../wrapper-loops.log"
  exit 98
fi
export FP_WRAPPER_SEEN=1
kept=""
IFS=:
for d in $PATH; do
  [ "$(cd "$d" 2>/dev/null && pwd -P)" = "$own" ] || kept="$kept${kept:+:}$d"
done
unset IFS
PATH="$kept" exec git "$@"
SH
chmod +x "$E2E_DIR/flowplugin/hooks/shims/git"
_fp_env_run PATH="$E2E_DIR/flowplugin/hooks/shims:$E2E_BIN:$PATH" -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT)"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
e2e_expect_equal "0" "$(cat "$E2E_DIR/wrapper-loops.log" 2>/dev/null | wc -l | tr -d ' ')" "times the wrapper was run from inside itself"
_fp_env_after

_flow_test_begin "environment: a full run records P3, P7, P11 and P15 in a record that validates (E10)"
_fp_env_scenario fp-env-full "probe --environment with no --only: the four probes are recorded, the record validates, and dispositions pass"
_fp_env_run
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out "PROBE_ENV="
e2e_expect_equal '{"P11": "go", "P15": "deferred", "P3": "go", "P7": "deferred"}' \
  "$(_fp_get "$E2E_REPO/$FP_REC" '{k: v["result"] for k, v in sorted(d["probes"].items())}')" "the recorded probes"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_expect_equal "$FP_SANDBOX" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["environment"]["keyed_on"]["sandbox"]')" "keyed_on sandbox"
_fp_env_after
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --dispositions
e2e_expect_no_out "deferred_without_phase"
e2e_expect_no_out "no_go_without_fallback"
e2e_expect_no_out "parts_mismatch"
e2e_expect_no_out "stand_in_go"
e2e_expect_equal "refs/heads/main" "$(cd "$E2E_DIR/origin.git" && command git for-each-ref --format='%(refname)')" "the origin's branches after the dry run (no probe branch)"

_flow_test_begin "environment: a sandbox the journal does not approve is refused before the Keychain and the API (E13)"
_fp_env_scenario fp-env-other-sandbox "the journal approves probe-fixture/sandbox and the call names someone/else: refused with exit 5 naming the approved sandbox, the Keychain is not read, no request reaches the stub API, and no record is written"
e2e_run_bin bin/flow-factory.sh probe --environment --sandbox someone/else --github-api "$(e2e_stub_url api)" --only P3
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=sandbox_not_approved"
e2e_expect_out "approved: probe-fixture/sandbox"
e2e_expect_equal "" "$(cat "$E2E_BIN/security-calls.log" 2>/dev/null)" "Keychain lookups"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests to the stub API"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
e2e_describe "with no sandbox: line under ## Phase 0 decisions the approved sandbox is refused too"
_fp_journal ""
_fp_env_run -- --only P3
e2e_expect_equal "5" "$E2E_RC" "exit status with no approval"
e2e_expect_out "FACTORY_REFUSED=sandbox_not_approved"
e2e_expect_equal "" "$(cat "$E2E_BIN/security-calls.log" 2>/dev/null)" "Keychain lookups with no approval"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests to the stub API with no approval"

_flow_test_begin "environment: an origin that can be read but not pushed to makes the dry-run push no-go (E14)"
_fp_env_scenario fp-env-push-refused "the scratch HOME's git config sends pushes to origin to a path that is not a repository, as a read-only credential would refuse them: git fetch and ls-remote of origin are go, the dry-run push to origin is no-go, the local bare push is still go, and P3 is no-go"
printf '[url "%s/no-push-here.git"]\n\tpushInsteadOf = %s/origin.git\n' "$E2E_DIR" "$E2E_DIR" > "$E2E_HOME/.gitconfig"
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"git_fetch": "go", "git_ls_remote": "go", "git_push_dry_run": "no-go", "git_push_local": "go"}' \
  "$(_fp_get "$E2E_REPO/$FP_REC" '{k: v["result"] for k, v in sorted(d["probes"]["P3"]["parts"].items()) if k.startswith("git_")}')" "the git parts"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "origin" in d["probes"]["P3"]["parts"]["git_push_dry_run"]["reason"] else d["probes"]["P3"]["parts"]["git_push_dry_run"]["reason"]')" "the dry-run reason names origin"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
e2e_expect_equal "refs/heads/main" "$(cd "$E2E_DIR/origin.git" && command git for-each-ref --format='%(refname)')" "the origin's branches"
_fp_env_after

_flow_test_begin "environment: --github-api takes only GitHub's API hosts or this machine (E15)"
_fp_env_scenario fp-env-api-host "an https host that is not GitHub's API is a usage error before anything runs; a GitHub Enterprise /api/v3 address is accepted as an address (and then refused because the journal does not approve it, so nothing is sent)"
e2e_run_bin bin/flow-factory.sh probe --environment --sandbox "$FP_SANDBOX" --github-api https://api.example.com --only P3
e2e_expect_equal "2" "$E2E_RC" "exit status for https://api.example.com"
e2e_expect_err "https://api.example.com"
e2e_expect_equal "" "$(cat "$E2E_BIN/security-calls.log" 2>/dev/null)" "Keychain lookups"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
e2e_run_bin bin/flow-factory.sh probe --environment --sandbox someone/else --github-api https://ghe.example.com/api/v3 --only P3
e2e_expect_equal "5" "$E2E_RC" "exit status for a GitHub Enterprise address"
e2e_expect_out "FACTORY_REFUSED=github_api_not_approved"

# _fp_closed_api — an http address on this machine where nothing listens, so
# a request sent there gets no answer; masked in the artifact.
_fp_closed_api() {
  FP_CLOSED=$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print("http://127.0.0.1:%d" % s.getsockname()[1]); s.close()')
  printf '%s\t<closed port>\n' "${FP_CLOSED#http://}" >> "$E2E_DIR/masks"
}

# _fp_lc_unanswered — P13 in a launchd context, every command limited to 3 s.
_fp_lc_unanswered() {
  _e2e_exec env FLOW_FACTORY_LAUNCH_CONTEXT=launchd "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" \
    "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment --sandbox "$FP_SANDBOX" \
    --github-api "$FP_CLOSED" --launch-context --call-timeout-seconds 3
  e2e_expect_equal "0" "$E2E_RC" "exit status of P13 ($E2E_OUT $E2E_ERR)"
}

_flow_test_begin "environment: a check whose git, gh or HTTP call got no answer is not_run, never go or no-go (E17)"
FP_D="gh auth and gh api, and git ls-remote, fetch, push and clone get no answer (each sleeps past"
FP_D+=" --call-timeout-seconds 3), and the worker token's GET goes to a port where nothing listens: each P3 part"
FP_D+=" those calls decide is not_run naming what did not answer, P15's comparison is not_run naming the clone, no"
FP_D+=" part of P3, P11 or P15 is no-go, none names a fallback, and nothing is charged; then P13 in a launchd"
FP_D+=" context: when its claude exits before printing any event, as it does with no credentials there, claude_p"
FP_D+=" is no-go naming claude's exit and P13 names its fallback (E21); when the API refuses the run, claude_p is"
FP_D+=" not_run and no P13 part is no-go; nothing is charged either time"
_fp_env_scenario fp-env-no-answer "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf '%s\n' ls-remote fetch push clone > "$E2E_BIN/git-no-answer"
printf '%s\n' auth api > "$E2E_BIN/gh-no-answer"
_fp_closed_api
e2e_run_bin bin/flow-factory.sh probe --environment --sandbox "$FP_SANDBOX" --github-api "$FP_CLOSED" \
  --only P11,P3,P15 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_UNSEEN='lambda p: [k for k, v in sorted(p.get("parts", {}).items()) if v["result"] == "no-go"]
  + (["fallback"] if p.get("fallback") else []) + (["result"] if p["result"] == "no-go" else [])'
# Built outside the command substitution, where bash 3.2 would expand its braces.
FP_EXPR="{pid: ($FP_UNSEEN)(d['probes'][pid]) for pid in ('P11', 'P3', 'P15')}"
e2e_expect_equal '{"P11": [], "P3": [], "P15": []}' "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_EXPR")" \
  "no-go parts, fallbacks and no-go results"
FP_KEYS='("gh_auth_status", "gh_api_user", "git_ls_remote", "git_fetch", "git_push_dry_run", "git_push_local",
  "worker_token")'
e2e_expect_equal "not_run not_run not_run not_run not_run not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" \
  '" ".join(d["probes"]["P3"]["parts"][k]["result"] for k in '"$FP_KEYS"')')" "the P3 parts the calls decide"
e2e_expect_equal "[]" "$(_fp_get "$E2E_REPO/$FP_REC" '[k for k in '"$FP_KEYS"'
  if not any(t in d["probes"]["P3"]["parts"][k]["reason"] for t in ("did not answer", "got no answer"))]')" \
  "P3 parts whose reason does not say what got no answer"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda c: "%s %s" % (c["result"],
  "yes" if "git clone did not answer" in c["reason"] else c["reason"]))(d["probes"]["P15"]["parts"]["comparison"])')" \
  "P15's comparison part"
e2e_expect_equal "0" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
_fp_env_after
FP_P13='(lambda p: "%s %s %s" % (p["parts"]["claude_p"]["result"], ('"$FP_UNSEEN"')(p),
  d["spend"]["spent_usd"]))(d["probes"]["P13"])'
FP_P13_SAID='d["probes"]["P13"]["parts"]["claude_p"]["reason"]'
e2e_describe "P13 in a launchd context: claude exits before printing any event (E21)"
printf 'noevent\n' > "$E2E_BIN/claude-behaviour"
_fp_lc_unanswered
e2e_expect_equal "no-go ['claude_p', 'fallback', 'result'] 0" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_P13")" \
  "claude_p, P13's no-go parts and fallback, and spent_usd"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '("yes" if "If credentials are missing"
  in (d["probes"]["P13"].get("fallback") or "") else d["probes"]["P13"].get("fallback"))')" "P13's fallback"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "before printing any event: Invalid API key" in '"$FP_P13_SAID"' else '"$FP_P13_SAID")" "claude_p's reason"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts"
e2e_describe "P13 in a launchd context: the API refuses claude's run"
printf 'apierror\n' > "$E2E_BIN/claude-behaviour"
_fp_lc_unanswered
e2e_expect_equal "not_run [] 0" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_P13")" \
  "claude_p, P13's no-go parts and fallback, and spent_usd"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "the API refused the run" in '"$FP_P13_SAID"' else '"$FP_P13_SAID")" "claude_p's reason"
e2e_expect_equal "2" "$(_fp_launches)" "claude -p starts"
_fp_env_after

_flow_test_begin "environment: P13 whose planted worktree cannot be made records that part not_run (E24)"
FP_D="in a launchd context, git init in P13's planted worktree gets no answer (it sleeps past"
FP_D+=" --call-timeout-seconds 3): the run exits 0, P13 is recorded, its interpreter part is not_run naming the"
FP_D+=" planted worktree, and its other parts are recorded"
_fp_env_scenario fp-env-lc-planted "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'planted-worktree init\n' > "$E2E_BIN/git-no-answer-in"
_fp_closed_api
_fp_lc_unanswered
e2e_expect_equal "not_run yes present" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (
  p["parts"]["interpreter"]["result"], "yes" if "the planted worktree could not be made" in
  p["parts"]["interpreter"]["reason"] else p["parts"]["interpreter"]["reason"],
  "present" if "claude_p" in p["parts"] else "absent"))(d["probes"]["P13"])')" \
  "the interpreter part, its reason, and the claude_p part"

_flow_test_begin "environment: a P13 that raises is recorded not_run, and the launch-context run goes on (E24)"
FP_D="in a launchd context, git init in the push-source repository P13's auth checks make gets no answer, so"
FP_D+=" P13 raises: the run exits 0, P13 is recorded not_run naming the refusal, and stderr names where it stopped"
_fp_env_scenario fp-env-lc-raises "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'push-source init\n' > "$E2E_BIN/git-no-answer-in"
_fp_closed_api
_fp_lc_unanswered
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"],
  "yes" if "the probe stopped with Refused: scratch_repo_failed git init did not answer" in p["reason"]
  else p["reason"]))(d["probes"]["P13"])')" "P13's result and reason"
e2e_expect_err "PROBE_STOPPED=P13 Refused"
e2e_expect_equal "go present not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (
  p["parts"]["tools"]["result"], "present" if "interpreter" in p["parts"] else "absent",
  p["parts"]["stopped"]["result"]))(d["probes"]["P13"])')" "the parts P13 saw before it stopped (E30)"

_flow_test_begin "environment: a P13 whose claude run raised after it started is charged its limit once (E30)"
FP_D="in a launchd context, an error is injected into P13 just after its claude -p starts: P13 is recorded with"
FP_D+=" the parts it saw and a not_run part naming the error, its cost is the run's \$0.5 budget limit, and the"
FP_D+=" spend holds that limit once"
_fp_env_scenario fp-env-lc-run-error "$FP_D"
_fp_inject 'popen-error --max-budget-usd'
_fp_closed_api
_fp_lc_unanswered
e2e_expect_equal "not_run yes 0.5 0.5 go" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s %s %s" % (
  p["result"], "yes" if "the probe stopped with RuntimeError" in p["parts"]["stopped"]["reason"]
  else p["parts"]["stopped"]["reason"], p["cost_usd"], d["spend"]["spent_usd"], p["parts"]["tools"]["result"]))(
  d["probes"]["P13"])')" "P13's result, its stopped part, its cost, the spend and its tools part"

_flow_test_begin "environment: a git command that exited while a detached program holds its output answered (E29)"
FP_D="git fetch in P3's checks ends and leaves a program in a session of its own holding its output for 60 s;"
FP_D+=" with --call-timeout-seconds 3, the fetch part is go, never not_run as a call that did not answer"
_fp_env_scenario fp-env-held-output "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'fetch\n' > "$E2E_BIN/git-leaves-child"
_fp_env_run -- --only P3 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["git_fetch"]["result"]')" \
  "the fetch part ($(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["parts"]["git_fetch"]["reason"]'))"
_fp_env_after

_flow_test_begin "environment: a dry-run push that created a branch on origin and then got no answer is no-go (E27)"
FP_D="git push --dry-run to origin moves a ref and then gets no answer (the git stand-in drops --dry-run, pushes,"
FP_D+=" then sleeps past --call-timeout-seconds 3): git ls-remote then lists the probe's branch on origin, so"
FP_D+=" git_push_dry_run is no-go saying it created the branch, never not_run, and P3 is no-go"
_fp_env_scenario fp-env-dry-run-moves "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
: > "$E2E_BIN/git-dry-run-pushes"
_fp_env_run -- --only P3 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"], "yes" if
  "created the branch" in p["reason"] else p["reason"]))(d["probes"]["P3"]["parts"]["git_push_dry_run"])')" \
  "the dry-run push part and its reason"
e2e_expect_equal "1" "$(cd "$E2E_DIR/origin.git" && command git for-each-ref --format='%(refname)' \
  'refs/heads/flow-factory-probe-dry-run-*' | wc -l | tr -d ' ')" "probe branches the dry run left on origin"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
_fp_env_after

_flow_test_begin "environment: a git call that gets no answer part way through P3 drops none of the parts it saw (E28)"
FP_D="gh auth status exits 1, and git rev-parse --verify gets no answer (it sleeps past --call-timeout-seconds 3)"
FP_D+=" when P3 reads the commit it pushed to the local bare remote: git_push_local is not_run naming git rev-parse,"
FP_D+=" gh_auth_status stays no-go, the token check still runs and is go, and P3 is no-go; then git init of P3's"
FP_D+=" scratch repository gets no answer: P3 is not run naming git init, and no gh call was made before it"
FP_D+=" stopped, so no result it saw is dropped"
_fp_env_scenario fp-env-p3-part-way "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'auth status\n' > "$E2E_BIN/gh-fail"
printf 'rev-parse --verify\n' > "$E2E_BIN/git-no-answer"
_fp_env_run -- --only P3 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go not_run go" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"]["P3"]["parts"][k]["result"]
  for k in ("gh_auth_status", "git_push_local", "worker_token"))')" "gh auth status, the local push and the token check"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda r: "yes" if "git rev-parse did not answer" in r
  else r)(d["probes"]["P3"]["parts"]["git_push_local"]["reason"])')" "the local push part names git rev-parse"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
_fp_env_after
e2e_describe "git init of P3's scratch repository gets no answer"
printf 'init\n' > "$E2E_BIN/git-no-answer"
: > "$E2E_BIN/gh-real.log"
_fp_env_run -- --only P3 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"],
  "yes" if "git init did not answer" in p["reason"] else p["reason"]))(d["probes"]["P3"])')" "P3 result and reason"
e2e_expect_equal "" "$(cat "$E2E_BIN/gh-real.log")" "gh calls made before P3 stopped"
_fp_env_after

_flow_test_begin "environment: P7's record calls share one time limit, --call-timeout-seconds, and leave no process behind (E25)"
FP_D="flow-goal-trust.sh, replaced in a copy of the plugin, starts a 20 s sleep and waits for it on every call, as"
FP_D+=" a call stuck on a lock does: with --call-timeout-seconds 3, P7's 100 record calls are stopped together once"
FP_D+=" 3 s have passed, its isolation part is not_run naming the calls that did not answer, never no-go, and no"
FP_D+=" process a record call or a trust check started is left running; then the trust check answers at once that"
FP_D+=" the goal is not trusted: as no record call answered, that is no finding, and the part is still not_run"
_fp_env_scenario fp-env-p7-stuck "$FP_D"
e2e_plugin_copy bin/flow-goal-trust.sh "#!/bin/bash
if [ \"\$1\" = check ] && [ -f '$E2E_DIR/check-answers' ]; then echo TRUSTED=no; exit 0; fi
sleep 20 &
printf '%s\\n%s\\n' \"\$\$\" \"\$!\" >> '$E2E_DIR/trust-pids'
wait"
# _fp_trust_left — the stand-in's processes still running, which are then
# stopped.
_fp_trust_left() {
  FP_LEFT=""
  for FP_PID in $(cat "$E2E_DIR/trust-pids" 2>/dev/null); do
    kill -0 "$FP_PID" 2>/dev/null && FP_LEFT="$FP_LEFT $FP_PID"
  done
  for FP_PID in $FP_LEFT; do kill -KILL "$FP_PID" 2>/dev/null; done
}
FP_ISOLATION='(lambda p: "%s %s" % (p["result"], "yes" if "50 of 50 record calls did not answer in 3 s" in p["reason"]
  else p["reason"]))(d["probes"]["P7"]["parts"]["isolation"])'
_fp_env_run -- --only P7 --call-timeout-seconds 3
_fp_trust_left
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_ISOLATION")" "P7's isolation part"
e2e_expect_equal "yes" "$([ -s "$E2E_DIR/trust-pids" ] && echo yes || echo no)" "the stand-in wrote its pids"
e2e_expect_equal "" "$FP_LEFT" "processes the record calls and trust checks started, running after the probe ended"
_fp_env_after
e2e_describe "the trust check answers at once that the goal is not trusted"
: > "$E2E_DIR/check-answers"
: > "$E2E_DIR/trust-pids"
_fp_env_run -- --only P7 --call-timeout-seconds 3
_fp_trust_left
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_ISOLATION")" "P7's isolation part"
e2e_expect_equal "" "$FP_LEFT" "processes the record calls started, running after the probe ended"
_fp_env_after

_flow_test_begin "environment: the Keychain read of P3's token check is held to --call-timeout-seconds (E26)"
_fp_env_scenario fp-env-keychain-hangs "security, the Keychain stand-in, never answers: with --call-timeout-seconds \
3 the token check is not_run naming security as not answering within that limit, and no request reaches the API"
printf 'hang\n' > "$E2E_BIN/security-behaviour"
_fp_env_run -- --only P3 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"], "yes" if
  "security did not answer (timed out after 3 s)" in p["reason"] else p["reason"]))(d["probes"]["P3"]["parts"]["worker_token"])')" \
  "the token part"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests the API stub received"
_fp_env_after

# The platform group, `probe --platform [--only P1,P2,P4,P5,P10,P16]`, keyed on
# claude --version. Every scenario runs the stand-in claude from
# tests/fixtures/factory/platform, which runs the plugin copy's hooks and
# ```! blocks the way Claude Code does, so no scenario runs a model or
# reaches GitHub. XDG_STATE_HOME points into the scenario, so the probe's
# scratch area is never the real ~/.local/state.
#
# Ways it can be wrong, written down before the checks:
#   PL1 P2 is recorded go although the deny that fired is a stand-in rule
#       written into the scratch copy, or tier-gate is not the real one
#   PL2 a person subcommand in a wrapped form that the hooks let through is
#       not named, or P2 is still deferred
#   PL3 a form the worker never ran is counted as denied, so P2 is deferred
#       on fewer than all 72 forms
#   PL13 the python3 <plugin>/bin/_flow_factory.py form, which skips the
#       wrapper, is never offered, or runs unseen because only flow-factory.sh
#       is a canary
#   PL14 a P2 go condition that cannot be checked yet (Stop caps, SessionEnd
#       writes, TaskCompleted refusals) is left out of the record instead of
#       recorded deferred with its phase; AskUserQuestion offered to the
#       worker, or a config-loading .claude file it created, passes
#   PL4 P4 is go with two flows loaded, or with an init event that names no
#       plugins at all
#   PL5 a gh write in P1's call log is not in github_writes or not flagged,
#       or P1's gh stand-in passes a call on to the real gh
#   PL6 P1's block check is go although no block ran, or its output did not
#       reach the first turn
#   PL7 P1's worktree, io and leftover checks are not recorded, or its
#       scratch repository is not under ${XDG_STATE_HOME}/flow-factory/probe
#   PL8 P5's deliberate kill is recorded as a timeout, a limit the resumed
#       run never reached counts as enforced, a block run again on resume
#       or a resumed run reporting the whole session's cost is go, or the
#       cost scope is judged from a run that did not finish or gave no cost,
#       or from a resume that ended in an error, started a new session
#       instead of carrying the earlier one, or charged nothing
#   PL9 P10 counts a call the worker never made as refused, or misses a
#       subagent that is not held to --disallowedTools
#   PL10 a platform run starts a model run that would pass the spend cap
#   PL11 the probe edits the plugin's own hooks instead of a scratch copy
#   PL12 the group is not keyed on claude --version
#   PL17 a run that exits before printing any event, or a git status that
#       does not answer, leaves a part no-go with a fallback (a block, a
#       write, a session id, a limit) or go on nothing seen (no GitHub
#       write, no leftover path, no .claude file), or charges the run's
#       budget limit; or a Write or Edit the worker never made is no-go, as
#       if it had been refused
#   PL18 a probe entry the record's schema refuses (a GitHub write logged
#       under a name that is not owner/repo) stops the whole group, so the
#       probes after it never run; or the probe's spend or writes are lost
#       with the entry
#   PL15 a probe that stops part way, because it raised or because the API
#       refused one of its runs, stops the group, or is recorded anything but
#       not_run naming why (the exception's type, the API's answer)
#   PL16 SIGTERM, SIGHUP, SIGQUIT or an interrupt while a run is waited for
#       leaves the run's processes running, or the command exits without
#       charging the run's budget limit
#   PL19 P5 charges a resumed run the whole session's cost its result reports,
#       or compares that cost with the fork's own --max-budget-usd, so a fork
#       that finished within its limit is no-go; or its facts keep only one
#       of the two figures
#   PL20 a platform run ignores --model and runs on claude-opus-5-5, or the
#       record does not say which model a probe ran on, so a probe recorded
#       on one model passes --verify-record after its group ran on another,
#       or a probe recorded before the model was kept passes it too
#   PL21 a fork that cannot resume the first launch's session (it exits
#       before printing any event, although the first launch started and
#       reported its --session-id) leaves P5's session id part not_run
#       instead of no-go, or is charged

FP_HOOKS_SUM_BEFORE=$(cd "$REPO_ROOT/plugins/flow/hooks" && find . -type f -print | LC_ALL=C sort | xargs cksum | cksum)

# _fp_platform_scenario <name> <description> — a runner scenario whose claude
# is the platform stand-in. Only the probe's own hooks run in it (the real
# tier-gate.sh runs inside the probe's recording hook).
_fp_platform_scenario() {
  _fp_runner_scenario "$1" "$2"
  cp "$FP_FIXTURES/platform/claude" "$FP_FIXTURES/platform/claude_platform.py" "$E2E_BIN/"
  printf 'factory-probe-\n' > "$E2E_BIN/claude-hooks-only"
  printf 'FLOW_FACTORY_PROBE_BANG\n' > "$E2E_BIN/claude-bang-match"
}

# _fp_platform_run [NAME=value ...] -- [probe arguments]
_fp_platform_run() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  e2e_run_bin XDG_STATE_HOME="$E2E_DIR/state" ${envs[@]+"${envs[@]}"} bin/flow-factory.sh probe --platform "$@"
}

_fp_p() {   # <python expression on the probe entry p> [probe id]
  _fp_get "$E2E_REPO/$FP_REC" "(lambda p: $1)(d['probes']['${2:-$FP_PID}'])"
}

_flow_test_begin "platform: P4 with one flow, the --plugin-dir copy, is go (PL4, PL11, PL12)"
_fp_platform_scenario fp-plat-p4 "the project's flow loads in the run without --plugin-dir, and the copy takes its place in the run with it: P4 is go, the group is keyed on claude --version, and the copy has no tests/"
FP_PID=P4
printf '[{"name": "flow", "path": "/Users/someone/.claude/plugins/cache/synapti-marketplace/flow/3.16.0"}]\n' > "$E2E_BIN/claude-plugins-extra"
: > "$E2E_BIN/claude-plugin-dir-overrides"
_fp_platform_run -- --only P4
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "PROBE_PLATFORM="
e2e_expect_equal "go" "$(_fp_p 'p["result"]')" "P4 result"
e2e_expect_equal '{"flow_once": "go", "project_flow": "go"}' "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items())}')" "every P4 part"
e2e_expect_equal "2.1.322 (Claude Code)" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["platform"]["keyed_on"]["claude_version"]')" "keyed_on claude_version"
e2e_expect_equal "2" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "0 1" "$(sed -n 1p "$E2E_BIN/claude-launches.log" | grep -c -- --plugin-dir) $(sed -n 2p "$E2E_BIN/claude-launches.log" | grep -c -- --plugin-dir)" "--plugin-dir on the first run and the second"
FP_PLUGIN_COPY=$(sed -n 's/.*--plugin-dir \([^ ]*\).*/\1/p' "$E2E_BIN/claude-launches.log" | head -1)
FP_HAS=no
case "$FP_PLUGIN_COPY" in "$(cd "$E2E_DIR" && pwd -P)/state/flow-factory/probe/"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the plugin copy is under XDG_STATE_HOME/flow-factory/probe ($FP_PLUGIN_COPY)"
e2e_expect_equal "no yes" "$([ -e "$FP_PLUGIN_COPY/tests" ] && echo yes || echo no) $([ -x "$FP_PLUGIN_COPY/hooks/scripts/tier-gate.sh" ] && echo yes || echo no)" "tests/ and tier-gate.sh in the copy"
FP_HAS=no
case "$(cat "$E2E_BIN/claude-launches.log")" in *"--setting-sources project,local"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "P4 runs with project settings, where the scratch project enables flow"
FP_PROJECT=$(_fp_get "$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json" 'd["project"]')
e2e_expect_equal "true" "$(_fp_get "$FP_PROJECT/.claude/settings.json" 'd["enabledPlugins"]["flow@synapti-marketplace"]')" "the scratch project enables flow"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"

_flow_test_begin "platform: with XDG_STATE_HOME unset the scratch area is under the user's home (PL7)"
_fp_platform_scenario fp-plat-p4-home "XDG_STATE_HOME is empty: the plugin copy lands under <home>/.local/state/flow-factory/probe, the home cascade-resolve.sh gives"
_fp_platform_run XDG_STATE_HOME= HOME="$E2E_HOME" -- --only P4
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_PLUGIN_COPY=$(sed -n 's/.*--plugin-dir \([^ ]*\).*/\1/p' "$E2E_BIN/claude-launches.log" | head -1)
FP_HAS=no
case "$FP_PLUGIN_COPY" in "$(cd "$E2E_HOME" && pwd -P)/.local/state/flow-factory/probe/P4-"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the plugin copy is under the home's .local/state ($FP_PLUGIN_COPY)"

_flow_test_begin "platform: P4 with two flows loaded is no-go with its fallback (PL4)"
_fp_platform_scenario fp-plat-p4-two "the init event lists a second flow, the one the project enables: P4 is no-go and names the fallback"
FP_PID=P4
printf '[{"name": "flow", "path": "/Users/someone/.claude/plugins/cache/synapti-marketplace/flow/3.16.0"}]\n' > "$E2E_BIN/claude-plugins-extra"
_fp_platform_run -- --only P4
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P4 result"
e2e_expect_equal "a --settings override, else refuse such repositories" "$(_fp_p 'p["fallback"]')" "P4 fallback"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "2" in p["parts"]["flow_once"]["reason"] else p["parts"]["flow_once"]["reason"]')" "the reason gives the count"

_flow_test_begin "platform: P4 is not go when the project's own flow never loads (PL4)"
_fp_platform_scenario fp-plat-p4-noproject "the run without --plugin-dir shows no flow, so the project's setting had no effect and a second flow could not have shown: P4 is not_run although the copy loaded once"
FP_PID=P4
_fp_platform_run -- --only P4
e2e_expect_equal "go" "$(_fp_p 'p["parts"]["flow_once"]["result"]')" "flow_once part"
e2e_expect_equal "not_run" "$(_fp_p 'p["parts"]["project_flow"]["result"]')" "project_flow part"
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]')" "P4 result"

_flow_test_begin "platform: P4 whose runs end abnormally is not go (PL4)"
_fp_platform_scenario fp-plat-p4-killed "each run of the stand-in is killed right after its init event: P4 has a no-go run part and is no-go"
FP_PID=P4
printf '[{"name": "flow", "path": "/Users/someone/.claude/plugins/cache/synapti-marketplace/flow/3.16.0"}]\n' > "$E2E_BIN/claude-plugins-extra"
: > "$E2E_BIN/claude-plugin-dir-overrides"
printf 'kill -TERM "$PPID"\n' > "$E2E_BIN/claude-script"
_fp_platform_run -- --only P4
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["run"]["result"]')" "run part"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P4 result"
e2e_expect_equal "run the probe again with a larger turn, budget or time limit" "$(_fp_p 'p["fallback"].split("; ")[0]')" "the run part's fallback"

_flow_test_begin "platform: P4 with no plugins in the init event is not go (PL4)"
_fp_platform_scenario fp-plat-p4-noinit "the init event has no plugins field: P4 cannot count flows, so it is not_run, never go"
FP_PID=P4
: > "$E2E_BIN/claude-init-no-plugins"
_fp_platform_run -- --only P4
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]')" "P4 result"

_flow_test_begin "platform: every platform run is on the model --model names, and the record keeps it (PL20)"
_fp_platform_scenario fp-plat-model "P4's two runs with --model claude-sonnet-5-5: both launches name that model \
and none names claude-opus-5-5; with no --model, both name claude-opus-5-5 and P4 is keyed on it; then P10 alone \
on claude-sonnet-5-5: --verify-record names P4 and its parts as stale on the model, and not P10"
FP_PID=P4
printf '[{"name": "flow", "path": "/Users/someone/.claude/plugins/cache/synapti-marketplace/flow/3.16.0"}]\n' > "$E2E_BIN/claude-plugins-extra"
: > "$E2E_BIN/claude-plugin-dir-overrides"
_fp_platform_run -- --only P4 --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "2 0" "$(grep -c -- '--model claude-sonnet-5-5\( \|$\)' "$E2E_BIN/claude-launches.log") $(grep -c -- \
  '--model claude-opus-5-5' "$E2E_BIN/claude-launches.log")" "launches naming claude-sonnet-5-5, and claude-opus-5-5"
e2e_describe "with no --model, both runs are on claude-opus-5-5"
: > "$E2E_BIN/claude-launches.log"
_fp_platform_run -- --only P4
e2e_expect_equal "0" "$E2E_RC" "exit status without --model ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "2" "$(grep -c -- '--model claude-opus-5-5\( \|$\)' "$E2E_BIN/claude-launches.log")" \
  "launches naming claude-opus-5-5 with no --model"
e2e_expect_equal "claude-opus-5-5 claude-opus-5-5" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (
  d["groups"]["platform"]["keyed_on"]["model"], d["probes"]["P4"]["keyed_on"]["model"])')" \
  "the platform group's and P4's model"
e2e_describe "P10 alone on claude-sonnet-5-5 leaves P4, recorded on claude-opus-5-5, stale"
_fp_platform_run -- --only P10 --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status of the P10 run ($E2E_OUT $E2E_ERR)"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_line "PROBES_STALE=P4 model"
e2e_expect_line "PROBES_STALE=P4/flow_once model"
e2e_expect_no_out "PROBES_STALE=P10"
e2e_describe "P4 recorded before the model was kept, then P10 alone: P4 is stale on the model it cannot show"
python3 - "$E2E_REPO/$FP_REC" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
p4 = d["probes"]["P4"]
p4["keyed_on"].pop("model")
for part in p4["parts"].values():
    part["keyed_on"].pop("model")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2)
PYEOF
_fp_platform_run -- --only P10 --model claude-sonnet-5-5
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_line "PROBES_STALE=P4 model"
e2e_expect_line "PROBES_STALE=P4/flow_once model"
e2e_expect_no_out "PROBES_STALE=P10"

_flow_test_begin "platform: P2 with the stand-in deny firing on all 72 forms is deferred, not go (PL1, PL13, PL14)"
_fp_platform_scenario fp-plat-p2 "nine person subcommands in eight wrapped forms and three worker forms run in the stand-in worker: the real tier-gate fires on every one, the stand-in deny refuses all 72 person forms, the worker forms run, the Stop, SessionEnd and TaskCompleted hooks fire, AskUserQuestion is not among the worker's tools, no .claude file is created, the go conditions that need phase 1 are recorded deferred with their phase, and P2 is deferred to phase 1b"
FP_PID=P2
_fp_platform_run -- --only P2
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "deferred" "$(_fp_p 'p["result"]')" "P2 result"
e2e_expect_equal "synaptiai/synapti-marketplace#355" "$(_fp_p 'p["deferred_to"]')" "P2 deferred_to"
e2e_expect_equal "true" "$(_fp_p 'p["stand_in"]')" "P2 stand_in"
e2e_expect_equal '{"ask_user_question_absent": "go", "claude_files_allowlist": "go", "coverage": "go", "person_forms_denied": "deferred", "session_end_hook": "go", "session_end_writes": "deferred", "stop_caps": "deferred", "stop_hook": "go", "task_completed_hook": "go", "task_completed_refusals": "deferred", "tier_gate_fires": "go", "worker_forms_allowed": "go"}' \
  "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items())}')" "every P2 part"
e2e_expect_equal "synaptiai/synapti-marketplace#355 synaptiai/synapti-marketplace#356 synaptiai/synapti-marketplace#355" "$(_fp_p '" ".join(p["parts"][k].get("deferred_to", "none") for k in ("stop_caps", "session_end_writes", "task_completed_refusals"))')" "the phase each go condition not yet checkable is deferred to"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "72 of 72" in p["parts"]["person_forms_denied"]["reason"] else p["parts"]["person_forms_denied"]["reason"]')" "the deny part counts 72 of 72"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json"
e2e_expect_equal "72 3" "$(_fp_get "$FP_FACTS" '"%d %d" % (sum(1 for f in d["forms"].values() if f["kind"] == "person"), sum(1 for f in d["forms"].values() if f["kind"] == "worker"))')" "person and worker forms"
e2e_expect_equal "bash -c|env -u|nohup|plain|python3 _flow_factory.py|sh -c|timeout|variable path" "$(_fp_get "$FP_FACTS" '"|".join(sorted(f["form"] for f in d["forms"].values() if f["kind"] == "person" and f["subcommand"] == "answer"))')" "the eight wrapped forms"
e2e_expect_equal "yes" "$(_fp_get "$FP_FACTS" '"yes" if any(f["command"].startswith("python3 ") and f["command"].split()[1].endswith("/bin/_flow_factory.py") for f in d["forms"].values()) else "no"')" "a form runs python3 <copy>/bin/_flow_factory.py"
e2e_expect_equal "0" "$(_fp_get "$FP_FACTS" 'sum(1 for f in d["forms"].values() if f["kind"] == "person" and f["ran"])')" "person forms that ran"
e2e_expect_equal "3" "$(_fp_get "$FP_FACTS" 'sum(1 for f in d["forms"].values() if f["kind"] == "worker" and f["ran"])')" "worker forms that ran"
FP_COPY=$(_fp_get "$FP_FACTS" 'd["plugin_copy"]')
e2e_expect_equal "$(cksum < "$REPO_ROOT/plugins/flow/hooks/scripts/tier-gate.sh")" "$(cksum < "$FP_COPY/hooks/scripts/tier-gate.sh")" "the copy's tier-gate.sh is the plugin's own"
e2e_expect_equal "75" "$(_fp_get "$FP_FACTS" 'sum(1 for f in d["forms"].values() if "tier-gate" in f["hooks"])')" "forms tier-gate saw"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_no_out "PROBES_CHECK_FAIL=stand_in_go"
e2e_expect_no_out "PROBES_CHECK_FAIL=parts_mismatch"
e2e_expect_no_out "PROBES_CHECK_FAIL=schema"

_flow_test_begin "platform: P2 with one wrapped form let through is no-go and names it (PL2)"
_fp_platform_scenario fp-plat-p2-leak "the worker runs reject under nohup although the hook refused it: P2 is no-go, names that form, and gives the fallback"
FP_PID=P2
printf 'p2-reject-nohup\n' > "$E2E_BIN/claude-ignore-deny"
_fp_platform_run -- --only P2
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P2 result"
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["person_forms_denied"]["result"]')" "person deny part"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "reject (nohup)" in p["parts"]["person_forms_denied"]["reason"] and "answer" not in p["parts"]["person_forms_denied"]["reason"] else p["parts"]["person_forms_denied"]["reason"]')" "the reason names reject (nohup) alone"
e2e_expect_equal "warn-only hooks; the engine refusal stays; residual risk" "$(_fp_p 'p["fallback"]')" "P2 fallback"
e2e_expect_equal "absent" "$(_fp_p 'p.get("deferred_to", "absent")')" "P2 deferred_to"

_flow_test_begin "platform: P2 with a form the worker never ran is not deferred (PL3)"
_fp_platform_scenario fp-plat-p2-skip "the worker skips cancel in its sh -c form: that form is not counted as denied, so P2 is not_run, not deferred"
FP_PID=P2
printf 'p2-cancel-shc\n' > "$E2E_BIN/claude-skip-steps"
_fp_platform_run -- --only P2
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]')" "P2 result"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "cancel (sh -c)" in p["parts"]["coverage"]["reason"] else p["parts"]["coverage"]["reason"]')" "the coverage part names the form"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "71 of 72" in p["parts"]["person_forms_denied"]["reason"] else p["parts"]["person_forms_denied"]["reason"]')" "the deny part counts 71 of 72"

_flow_test_begin "platform: P2 whose worker marks no task completed does not blame TaskCompleted (PL3)"
_fp_platform_scenario fp-plat-p2-notask "the worker skips the task step: the TaskCompleted part is not_run, not no-go"
FP_PID=P2
printf 'TASK:\n' > "$E2E_BIN/claude-skip-steps"
_fp_platform_run -- --only P2
e2e_expect_equal "not_run" "$(_fp_p 'p["parts"]["task_completed_hook"]["result"]')" "TaskCompleted part"
e2e_expect_equal "go" "$(_fp_p 'p["parts"]["stop_hook"]["result"]')" "Stop part"

_flow_test_begin "platform: P2 whose deny misses the python3 _flow_factory.py form is no-go (PL13)"
_fp_platform_scenario fp-plat-p2-python "the worker runs every python3 <copy>/bin/_flow_factory.py form although the hook refused it, as a deny that only knows flow-factory.sh would let it: the _flow_factory.py canary logs each run, and the deny part and P2 are no-go and name the form"
FP_PID=P2
printf '_flow_factory.py\n' > "$E2E_BIN/claude-ignore-deny"
_fp_platform_run -- --only P2
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["person_forms_denied"]["result"]')" "person deny part"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "reject (python3 _flow_factory.py)" in p["parts"]["person_forms_denied"]["reason"] and "(nohup)" not in p["parts"]["person_forms_denied"]["reason"] else p["parts"]["person_forms_denied"]["reason"]')" "the reason names the python3 forms alone"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P2 result"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json"
e2e_expect_equal "9" "$(_fp_get "$FP_FACTS" 'sum(1 for f in d["forms"].values() if f["form"] == "python3 _flow_factory.py" and f["ran"])')" "python3 forms the canary logged"

_flow_test_begin "platform: P2 whose worker is offered AskUserQuestion or creates a config-loading .claude file is no-go (PL14)"
_fp_platform_scenario fp-plat-p2-config "the worker's init event lists AskUserQuestion, and the worker writes .claude/settings.local.json and .claude/probe.lock in its worktree: the AskUserQuestion part is no-go, the .claude part is no-go and names the settings file but not the lock file"
FP_PID=P2
printf '["Bash", "TaskUpdate", "AskUserQuestion"]\n' > "$E2E_BIN/claude-init-tools"
printf 'mkdir -p .claude && printf "{}" > .claude/settings.local.json && : > .claude/probe.lock\n' > "$E2E_BIN/claude-script"
_fp_platform_run -- --only P2
e2e_expect_equal "no-go no-go" "$(_fp_p '"%s %s" % (p["parts"]["ask_user_question_absent"]["result"], p["parts"]["claude_files_allowlist"]["result"])')" "AskUserQuestion and .claude parts"
e2e_expect_equal "yes" "$(_fp_p '"yes" if ".claude/settings.local.json" in p["parts"]["claude_files_allowlist"]["reason"] and "probe.lock" not in p["parts"]["claude_files_allowlist"]["reason"] else p["parts"]["claude_files_allowlist"]["reason"]')" "the .claude part names the settings file alone"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P2 result"

_flow_test_begin "platform: P2 whose worker is killed does not blame the hooks (PL3)"
_fp_platform_scenario fp-plat-p2-killed "the worker is killed right after its init event: the run part is no-go, and the Stop, SessionEnd and TaskCompleted parts are not_run"
FP_PID=P2
printf 'kill -TERM "$PPID"\n' > "$E2E_BIN/claude-script"
_fp_platform_run -- --only P2
e2e_expect_equal '{"run": "no-go", "session_end_hook": "not_run", "stop_hook": "not_run", "task_completed_hook": "not_run"}' \
  "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items()) if k in ("run", "stop_hook", "session_end_hook", "task_completed_hook")}')" "run and hook parts"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P2 result"

_flow_test_begin "platform: P1 runs the four commands with a gh stand-in in the default worker area (PL6, PL7)"
_fp_platform_scenario fp-plat-p1 "P1 runs /flow:start 1, /flow:pr, /flow:review 1 and /flow:address 1 and a write run: each command's probe block output reaches the first turn, writes land in the worktree and the io directory, no GitHub write is made, and P1 is deferred to phase 1d"
FP_PID=P1
_fp_platform_run -- --only P1
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "deferred" "$(_fp_p 'p["result"]')" "P1 result"
e2e_expect_equal "synaptiai/synapti-marketplace#357" "$(_fp_p 'p["deferred_to"]')" "P1 deferred_to"
e2e_expect_equal '{"bang_first_turn_address": "go", "bang_first_turn_pr": "go", "bang_first_turn_review": "go", "bang_first_turn_start": "go", "factory_mode": "deferred", "gh_log": "go", "io_write": "go", "leftover_paths": "go", "runs": "go", "worktree_edit": "go", "worktree_write": "go"}' \
  "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items())}')" "every P1 part"
e2e_expect_equal "5" "$(_fp_launches)" "claude -p starts"
FP_HAS=no
case "$(sed -n 1p "$E2E_BIN/claude-launches.log")" in *"--plugin-dir "*"--add-dir "*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the worker command has --plugin-dir and --add-dir"
e2e_expect_equal "/flow:start 1|/flow:pr|/flow:review 1|/flow:address 1" "$(for n in 1 2 3 4; do cat "$E2E_BIN/claude-prompt-$n.txt"; printf '|'; done | sed 's/|$//')" "the four prompts"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json"
FP_SCRATCH=$(_fp_get "$FP_FACTS" 'd["worktree"]')
FP_HAS=no
case "$FP_SCRATCH" in "$(cd "$E2E_DIR" && pwd -P)/state/flow-factory/probe/"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the worktree is under XDG_STATE_HOME/flow-factory/probe ($FP_SCRATCH)"
e2e_expect_equal "" "$(cat "$FP_SCRATCH/.gitignore")" "the worktree's .gitignore is empty"
e2e_expect_equal "[]" "$(_fp_p 'p["github_writes"]')" "github_writes"
e2e_expect_equal "0" "$(cat "$E2E_BIN/gh-real.log" 2>/dev/null | wc -l | tr -d ' ')" "calls that reached the gh on PATH"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"

_flow_test_begin "platform: P1 records a gh pr create in its call log as a GitHub write and flags it (PL5)"
_fp_platform_scenario fp-plat-p1-write "the stand-in worker runs gh pr create: it is in github_writes, the gh log part is no-go, and the gh stand-in refuses it without passing it on"
FP_PID=P1
printf 'gh pr create --title probe --body probe\n' > "$E2E_BIN/claude-script"
_fp_platform_run -- --only P1
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P1 result"
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["gh_log"]["result"]')" "gh log part"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "gh pr create" in p["parts"]["gh_log"]["reason"] else p["parts"]["gh_log"]["reason"]')" "the gh log part names the write"
e2e_expect_equal "yes" "$(_fp_p '"yes" if p["github_writes"] and all(w["call"] == "gh pr create" for w in p["github_writes"]) else p["github_writes"]')" "github_writes holds gh pr create"
e2e_expect_equal "yes" "$(_fp_p '"yes" if p.get("fallback") else "no"')" "P1 names a fallback"
e2e_expect_equal "0" "$(cat "$E2E_BIN/gh-real.log" 2>/dev/null | wc -l | tr -d ' ')" "calls that reached the gh on PATH"
e2e_expect_equal "yes" "$(grep -q 'gh pr create' "$E2E_BIN/claude-script.out" && echo yes || echo no)" "the stand-in's refusal reached the worker"

# PL22 The write run refused by the API makes the whole of P1 not_run,
# dropping the four command runs' parts.
_flow_test_begin "platform: P1's write run refused by the API leaves its own parts not run and keeps the command runs' (PL22)"
_fp_platform_scenario fp-plat-p1-api-writes "the write run ends as a run the API refused: the four block parts stay go, the three write parts are not_run with the API's answer, and P1 is not_run"
FP_PID=P1
printf 'factory-probe-write.txt\n' > "$E2E_BIN/claude-api-error-when"
_fp_platform_run -- --only P1
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "5" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "go go go go" "$(_fp_p '" ".join(p["parts"]["bang_first_turn_" + c]["result"] for c in ("start", "pr", "review", "address"))')" "the four block parts"
e2e_expect_equal "not_run not_run not_run yes" "$(_fp_p '"%s %s %s %s" % (p["parts"]["worktree_write"]["result"],
  p["parts"]["worktree_edit"]["result"], p["parts"]["io_write"]["result"],
  "yes" if p["parts"]["worktree_write"]["reason"].startswith("writes: the run ") else p["parts"]["worktree_write"]["reason"])')" \
  "the three write parts and the reason of one"
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]')" "P1 result"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"

_flow_test_begin "platform: P1's block check is no-go when no block runs (PL6)"
_fp_platform_scenario fp-plat-p1-nobang "the stand-in leaves every \`\`\`! block unrun: each block part is no-go, and P1 names the run-each-block-with-Bash fallback"
FP_PID=P1
: > "$E2E_BIN/claude-no-bang"
_fp_platform_run -- --only P1
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["bang_first_turn_start"]["result"]')" "start block part"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P1 result"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "run each block with Bash" in p.get("fallback", "") else p')" "P1 fallback"

_flow_test_begin "platform: P5 resumes a killed session within new limits (PL8)"
FP_D="the first launch is killed during its first tool call; two forks resume it, one stopped by --max-turns and"
FP_D+=" one by --max-budget-usd; a fresh session and its fork show per-run costs; the block ran once: every session"
FP_D+=" part and cost_scope are go. The stand-in's resume reports its own cost as total_cost_usd and no since-last"
FP_D+=" cost, so the engine, charging a resumed run the increase in the session total, charges it nothing:"
FP_D+=" engine_charge, and with it P5, is no-go (issue #354 G1)"
_fp_platform_scenario fp-plat-p5 "$FP_D"
FP_PID=P5
_fp_platform_run -- --only P5
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"budget_limit": "go", "cost_scope": "go", "engine_charge": "no-go", "kill": "go", "no_block_rerun": "go", "session_id": "go", "turn_limit": "go"}' \
  "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items())}')" "every P5 part"
e2e_expect_equal "no-go yes" "$(_fp_p '(lambda c: "%s %s" % (p["result"], "yes" if "its resume 0 (session_increase)"
  in c["reason"] else c["reason"]))(p["parts"]["engine_charge"])')" "P5 result, and engine_charge naming the resume's charge of 0"
e2e_expect_equal "5" "$(_fp_launches)" "claude -p starts"
FP_SID=$(sed -n '1s/.*--session-id \([^ ]*\).*/\1/p' "$E2E_BIN/claude-launches.log")
e2e_expect_equal "2" "$(grep -c -- "--resume $FP_SID --fork-session" "$E2E_BIN/claude-launches.log")" "resumes of the killed session with --fork-session"

_flow_test_begin "platform: P5 is no-go when a block runs again on resume or costs are cumulative (PL8)"
_fp_platform_scenario fp-plat-p5-bad "a resumed session runs its command's block again and reports the whole session's cost: those two parts are no-go"
FP_PID=P5
: > "$E2E_BIN/claude-rerun-bang-on-resume"
: > "$E2E_BIN/claude-cumulative-cost"
_fp_platform_run -- --only P5
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["no_block_rerun"]["result"]')" "block re-run part"
e2e_expect_equal "no-go" "$(_fp_p 'p["parts"]["cost_scope"]["result"]')" "cost scope part"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "The engine records the increase in a session" in p.get("fallback", "") and "between its runs, since a resumed run reports the whole session" in p.get("fallback", "") else p')" "P5 fallback names recording the increase between runs"

# P5's cost check: a four-step session, then a one-turn resume of it asked
# for the session's last command. Its result is judged only when the
# four-step run ran every step and completed, the resume completed and named
# that command, and both runs charged a cost above 0. The token totals decide
# when the results give them (Claude Code's modelUsage covers the session,
# its usage the run).
FP_P5_USAGE='{"input_tokens": 3, "output_tokens": 20, "cache_read_input_tokens": 3000,'
FP_P5_USAGE+=' "cache_creation_input_tokens": 400}'
# _fp_p5_cost <name> <description> <cost_scope result> <text in its reason>
# [knob or knob=content ...] — content is read with printf %b.
_fp_p5_cost() {
  _fp_platform_scenario "$1" "$2"
  local want="$3" text="$4" k fb=no
  shift 4
  for k in "$@"; do
    case "$k" in
      *=*) printf '%b\n' "${k#*=}" > "$E2E_BIN/${k%%=*}" ;;
      *) : > "$E2E_BIN/$k" ;;
    esac
  done
  FP_PID=P5
  _fp_platform_run -- --only P5
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  export FP_TEXT="$text"
  e2e_expect_equal "$want yes" "$(_fp_p '(lambda c: "%s %s" % (c["result"], "yes"
    if __import__("os").environ["FP_TEXT"] in c["reason"] else c["reason"]))(p["parts"]["cost_scope"])')" \
    "the cost scope part and its reason"
  [ "$want" = no-go ] && fb=yes
  e2e_expect_equal "$fb" "$(_fp_p '"yes" if "records the increase in a session" in p.get("fallback", "") else "no"')" \
    "the cumulative-cost fallback is given"
}

_flow_test_begin "platform: P5 reads cost scope from token totals when the result gives them (PL8)"
FP_TOK=(claude-model=claude-opus-5-5 "claude-turn-usage=0.05\t$FP_P5_USAGE")
_fp_p5_cost fp-plat-p5-tokens-own \
  "the resume's cost is the session's, but its modelUsage tokens are its own usage: cost_scope is go" \
  go "own" "${FP_TOK[@]}" claude-cumulative-cost
FP_D="the resume's cost is its own, but its modelUsage tokens are the first run's plus its own usage:"
FP_D+=" cost_scope is no-go with the fallback"
_fp_p5_cost fp-plat-p5-tokens-session "$FP_D" no-go "whole session" "${FP_TOK[@]}" claude-cumulative-usage
FP_D="the resume's modelUsage tokens match neither its own usage nor the session's: cost_scope is not_run"
_fp_p5_cost fp-plat-p5-tokens-neither "$FP_D" not_run "neither" "${FP_TOK[@]}" claude-usage-extra=7

_flow_test_begin "platform: P5's cost scope is not judged from a cost run that did not finish or gave no cost (PL8)"
_fp_p5_cost fp-plat-p5-cost-skip "the four-step session skips its third step: cost_scope is not_run, never go" \
  not_run "3 of its 4" claude-skip-steps=p5-cost-3
FP_D="every turn costs \$0.30, so the four-step session stops at its \$0.50 limit: cost_scope is not_run"
_fp_p5_cost fp-plat-p5-cost-budget "$FP_D" not_run "did not complete" claude-cost-per-turn=0.3
FP_D="the resume reports no total_cost_usd: cost_scope is not_run, and the cumulative-cost fallback is not given"
_fp_p5_cost fp-plat-p5-cost-none "$FP_D" not_run "resume of the four-step session did not complete" \
  "claude-no-cost-when=Reply with the" claude-cumulative-cost
_fp_p5_cost fp-plat-p5-cost-none-first "the four-step session reports no total_cost_usd: cost_scope is not_run" \
  not_run "did not complete" "claude-no-cost-when=p5-cost-1"

_flow_test_begin "platform: P5's cost scope is not judged from a resume that failed, started afresh or was free (PL8)"
# Each case runs once comparing costs and once comparing the token totals.
# The first turn of every run is free under FP_FREE, which the four-step
# session pays for with its later three.
FP_FREE="claude-turn-usage=0\t$FP_P5_USAGE\n0.05\t$FP_P5_USAGE"
for FP_T in costs tokens; do
  FP_K=()
  [ "$FP_T" = tokens ] && FP_K=("${FP_TOK[@]}")
  FP_D="the resume ends with an error result whose cost is below the four-step session's, comparing $FP_T:"
  FP_D+=" cost_scope is not_run, never go"
  _fp_p5_cost "fp-plat-p5-resume-error-$FP_T" "$FP_D" not_run "resume of the four-step session did not complete" \
    ${FP_K[@]+"${FP_K[@]}"} "claude-error-when=Reply with the"
  FP_D="--resume starts a new, empty session, which cannot name the four-step session's last command, comparing"
  FP_D+=" $FP_T: cost_scope is not_run, never go"
  _fp_p5_cost "fp-plat-p5-resume-fresh-$FP_T" "$FP_D" not_run "did not carry that session" \
    ${FP_K[@]+"${FP_K[@]}"} claude-resume-fresh
  FP_D="the resume's one turn costs nothing while the four-step session costs \$0.15, comparing $FP_T:"
  FP_D+=" cost_scope is not_run, never go"
  _fp_p5_cost "fp-plat-p5-resume-free-$FP_T" "$FP_D" not_run "charged nothing" ${FP_K[@]+"${FP_K[@]}"} "$FP_FREE"
done

_flow_test_begin "platform: P5 charges each run what it spent since the session's last result and judges its budget fork on that (PL19)"
FP_D="every result also reports model_usage_since_last_result, the run's own cost, and a resumed run's"
FP_D+=" total_cost_usd adds the \$0.15 the session spent before it; every turn costs \$0.003: the budget fork spends"
FP_D+=" \$0.015 of its \$0.02 limit and finishes, reporting \$0.165 in total, so budget_limit is not_run, never"
FP_D+=" no-go; P5 is charged \$0.536 (the killed first launch's \$0.50 limit and each other run's own cost), and"
FP_D+=" the facts keep both figures of each run"
_fp_platform_scenario fp-plat-p5-since-last "$FP_D"
FP_PID=P5
printf '0.15\n' > "$E2E_BIN/claude-since-last"
printf '0.003\n' > "$E2E_BIN/claude-cost-per-turn"
_fp_platform_run -- --only P5
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_p '(lambda b: "%s %s" % (b["result"], "yes" if "finished within its budget"
  in b["reason"] else b["reason"]))(p["parts"]["budget_limit"])')" "the budget limit part"
e2e_expect_equal "0.536 0.536" "$(_fp_p 'p["cost_usd"]') $(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" \
  "P5's cost and spent_usd"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json"
e2e_expect_equal '{"charged_usd": 0.015, "since_last_result_usd": 0.015, "total_cost_usd": 0.165}' \
  "$(_fp_get "$FP_FACTS" 'dict(sorted(d["costs"]["resume-budget"].items()))')" "the budget fork's figures in the facts"
e2e_expect_equal '{"charged_usd": 0.003, "since_last_result_usd": 0.003, "total_cost_usd": 0.153}' \
  "$(_fp_get "$FP_FACTS" 'dict(sorted(d["costs"]["cost-resume"].items()))')" "the cost resume's figures in the facts"
e2e_expect_equal '{"charged_usd": 0.5, "since_last_result_usd": null, "total_cost_usd": null}' \
  "$(_fp_get "$FP_FACTS" 'dict(sorted(d["costs"]["first"].items()))')" "the killed first launch's figures in the facts"

_flow_test_begin "platform: a fork that cannot resume the first launch's session makes P5's session id no-go (PL21)"
FP_D="every --resume run exits 1 before printing any event, saying no conversation was found with that session"
FP_D+=" id, while the first launch starts and reports its --session-id: the session id part is no-go naming both"
FP_D+=" forks and claude's line, the turn and budget limit parts are not_run, P5 is no-go naming the session id"
FP_D+=" fallback, and neither fork is charged"
_fp_platform_scenario fp-plat-p5-resume-lost "$FP_D"
FP_PID=P5
: > "$E2E_BIN/claude-resume-lost"
_fp_platform_run -- --only P5
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go 2 yes" "$(_fp_p '(lambda s: "%s %d %s" % (s["result"],
  s["reason"].count("before printing any event: No conversation found with session ID"), "yes"
  if "resume-turns could not resume" in s["reason"] and "resume-budget could not resume" in s["reason"]
  else s["reason"]))(p["parts"]["session_id"])')" "the session id part and its reason"
e2e_expect_equal "not_run not_run" "$(_fp_p 'p["parts"]["turn_limit"]["result"] + " "
  + p["parts"]["budget_limit"]["result"]')" "the turn and budget limit parts"
e2e_expect_equal "no-go yes" "$(_fp_p '"%s %s" % (p["result"], "yes" if "every relaunch is fresh"
  in (p.get("fallback") or "") else p.get("fallback"))')" "P5's result and fallback"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json"
e2e_expect_equal "0 0" "$(_fp_get "$FP_FACTS" '"%s %s" % (d["costs"]["resume-turns"]["charged_usd"],
  d["costs"]["resume-budget"]["charged_usd"])')" "what each fork was charged"

_flow_test_begin "platform: P10 holds the main run and a subagent to --disallowedTools (PL9)"
_fp_platform_scenario fp-plat-p10 "the worker and its subagent each try a touch, a write and an edit the rules forbid, and one allowed write: the forbidden ones are refused and P10 is go"
FP_PID=P10
_fp_platform_run -- --only P10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"main_bash": "go", "main_edit": "go", "main_write": "go", "subagent_bash": "go", "subagent_edit": "go", "subagent_write": "go"}' \
  "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items())}')" "every P10 part"
FP_HAS=no
case "$(cat "$E2E_BIN/claude-launches.log")" in *"--disallowedTools Bash(touch:*) Edit(denied/**) Write(denied/**)"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the rules are on the command"

_flow_test_begin "platform: P10 is no-go when a subagent is not held to the rules (PL9)"
_fp_platform_scenario fp-plat-p10-sub "the subagent's touch, write and edit go through: those parts are no-go and P10 names its fallback"
FP_PID=P10
: > "$E2E_BIN/claude-subagent-ignores-disallowed"
_fp_platform_run -- --only P10
e2e_expect_equal "go no-go" "$(_fp_p '"%s %s" % (p["parts"]["main_write"]["result"], p["parts"]["subagent_write"]["result"])')" "main and subagent write parts"
e2e_expect_equal "The read-only token and the protected check." "$(_fp_p 'p["fallback"]')" "P10 fallback"

_flow_test_begin "platform: P10 does not count a call the worker never made as refused (PL9)"
_fp_platform_scenario fp-plat-p10-skip "the worker skips the subagent's edit: that part is not_run, not go"
FP_PID=P10
printf 'SUBAGENT EDIT\n' > "$E2E_BIN/claude-skip-steps"
_fp_platform_run -- --only P10
e2e_expect_equal "not_run" "$(_fp_p 'p["parts"]["subagent_edit"]["result"]')" "subagent edit part"

_flow_test_begin "platform: P10 does not count a call that failed for another reason as refused (PL9)"
_fp_platform_scenario fp-plat-p10-unread "the worker's Edit of denied/main-edit.txt fails because the file was not read first, and no permission denial names it: that part is not_run with the error, while the subagent's refused edit stays go"
FP_PID=P10
printf 'main-edit\n' > "$E2E_BIN/claude-edit-unread"
_fp_platform_run -- --only P10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run go" "$(_fp_p '"%s %s" % (p["parts"]["main_edit"]["result"], p["parts"]["subagent_edit"]["result"])')" "main and subagent edit parts"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "File has not been read yet" in p["parts"]["main_edit"]["reason"] else p["parts"]["main_edit"]["reason"]')" "the main edit part gives the error"
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]')" "P10 result"

_flow_test_begin "platform: P10 whose run ends with an error result is not go (PL9)"
_fp_platform_scenario fp-plat-p10-error "every turn costs \$0.10, so the worker makes all eight calls and its run then ends error_max_budget_usd past its \$0.75 limit: each call part is go, the run part is no-go and names the subtype, and P10 is no-go"
FP_PID=P10
printf '0.1\n' > "$E2E_BIN/claude-cost-per-turn"
_fp_platform_run -- --only P10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"main_bash": "go", "main_edit": "go", "main_write": "go", "run": "no-go", "subagent_bash": "go", "subagent_edit": "go", "subagent_write": "go"}' \
  "$(_fp_p '{k: v["result"] for k, v in sorted(p["parts"].items())}')" "every P10 part"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "error_max_budget_usd" in p["parts"]["run"]["reason"] else p["parts"]["run"]["reason"]')" "the run part names the subtype"
e2e_expect_equal "no-go" "$(_fp_p 'p["result"]')" "P10 result"

_flow_test_begin "platform: a run that would pass the spend cap is not started (PL10)"
_fp_platform_scenario fp-plat-budget "with \$24.95 spent of \$25, P4 and P10 are recorded not_run with reason budget and claude never starts"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24.95'
_fp_platform_run -- --only P4,P10
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run budget not_run budget" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s %s" % (d["probes"]["P4"]["result"], d["probes"]["P4"]["reason"], d["probes"]["P10"]["result"], d["probes"]["P10"]["reason"])')" "P4 and P10"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "24.95" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"

# A probe that raises part way must not leave its earlier entry standing under
# the group's new keyed_on. The trigger is an init event whose extra flow has
# a number for a path, which P4 cannot join into its reason.
_flow_test_begin "platform: a probe that raises is recorded not_run with the exception type (PL15)"
_fp_platform_scenario fp-plat-raises "the record holds P4 go from an earlier claude; this run's init events list a flow whose path is a number, and P4 raises: P4 is recorded not_run naming TypeError under this run's claude version, the command still exits 0, and --verify-record finds nothing stale"
FP_PID=P4
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" ''
printf '[{"name": "flow", "path": 5}]\n' > "$E2E_BIN/claude-plugins-extra"
_fp_platform_run -- --only P4
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]')" "P4 result"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "TypeError" in p["reason"] else p["reason"]')" "the reason names the exception type"
e2e_expect_equal "2.1.322 (Claude Code)" "$(_fp_p 'p["keyed_on"]["claude_version"]')" "P4's own keyed_on"
e2e_expect_out '"P4": "not_run"'
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_no_out "PROBES_STALE"
e2e_expect_no_out "PROBES_CHECK_FAIL=schema"

# gh fills :owner and :repo from the default repository before it sends the
# call, so the shim logs the write under that repository or, with none to
# fill from (the run's folder has no remote), as unresolved: never under the
# typed ':owner/:repo', which the record's schema refuses.
_flow_test_begin "platform: a gh api write to repos/:owner/:repo is recorded and the next probe runs (PL18)"
_fp_platform_scenario fp-plat-placeholder-write "P4's and P10's workers run gh api repos/:owner/:repo/issues/1/comments -f body=x: the probe exits 0, P4 and P10 are both recorded from this run, P4's github_writes hold the call under a name the schema takes, and the record validates"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" ''
printf 'gh api repos/:owner/:repo/issues/1/comments -f body=x\n' > "$E2E_BIN/claude-script"
_fp_platform_run -- --only P4,P10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "evidence/P4-1 evidence/P10-1" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P4"]["evidence"], d["probes"]["P10"]["evidence"])')" "P4 and P10 recorded from this run"
e2e_expect_equal "yes" "$(_fp_p '"yes" if p["github_writes"] and all(w["call"] == "POST repos/:owner/:repo/issues/1/comments" and w["repo"] == "unresolved/unresolved" and w.get("refused") for w in p["github_writes"]) else p["github_writes"]' P4)" "P4's github_writes"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"

# An entry the schema refuses must not stop the group: the worker of P4's
# first run adds a line to its own call log naming a repository the schema
# refuses, as nothing the shim logs can. P4 is recorded not_run naming the
# refusal, with the write kept as unresolved, and P10 still runs.
_flow_test_begin "platform: a probe entry the record refuses is recorded not_run and the next probe runs (PL18)"
_fp_platform_scenario fp-plat-entry-refused "a line in P4's call log names the repository 'not a repo': the probe exits 0, P4 is recorded not_run naming the refusal under this run's claude version with its cost and the write kept as unresolved/unresolved, P10 runs and is recorded, and the record validates"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" ''
cat > "$E2E_BIN/claude-script" <<'SH'
log="$(dirname "$(dirname "$(command -v gh)")")/calls.jsonl"
case "$log" in
  */evidence/P4-*) printf '%s\n' '{"argv": ["gh", "forged"], "repo": "not a repo", "method": "WRITE", "write": true, "call": "gh forged"}' >> "$log" ;;
esac
SH
_fp_platform_run -- --only P4,P10
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run" "$(_fp_p 'p["result"]' P4)" "P4 result"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "record_invalid" in p["reason"] and "github_writes" in p["reason"] else p["reason"]' P4)" "P4's reason names the refusal"
e2e_expect_equal "2.1.322 (Claude Code)" "$(_fp_p 'p["keyed_on"]["claude_version"]' P4)" "P4's own keyed_on"
e2e_expect_equal "evidence/P4-1" "$(_fp_p 'p["evidence"]' P4)" "P4's evidence"
e2e_expect_equal "yes" "$(_fp_p '"yes" if p["cost_usd"] > 0 else p["cost_usd"]' P4)" "P4's cost is kept"
e2e_expect_equal "yes" "$(_fp_p '"yes" if {"repo": "unresolved/unresolved", "call": "gh forged"} in p["github_writes"] else p["github_writes"]' P4)" "the write is kept as unresolved/unresolved"
e2e_expect_equal "evidence/P10-1" "$(_fp_p 'p["evidence"]' P10)" "P10 recorded from this run"
e2e_expect_equal "yes" "$(_fp_p '"yes" if p["result"] != "not_run" or "record" not in p["reason"] else p["reason"]' P10)" "P10's entry is its own, not a refusal"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_expect_err "PROBE_ENTRY_REFUSED=P4 "

# SIGTERM to the probe while claude runs: the run's process group is stopped
# and its budget limit charged before the probe exits. The stand-in's script
# writes its own pid, its parent's (the stand-in claude) and a sleep's, so the
# check reads those processes and no other claude on the machine.
_flow_test_begin "platform: SIGTERM while a run waits stops its processes and charges its limit (PL16)"
_fp_platform_scenario fp-plat-sigterm "P4's first run sleeps; the probe is sent SIGTERM: it exits 143, none of the run's processes is left, and spent_usd holds the run's \$0.10 limit"
printf '[{"name": "flow", "path": "/Users/someone/.claude/plugins/cache/synapti-marketplace/flow/3.16.0"}]\n' > "$E2E_BIN/claude-plugins-extra"
printf 'sleep 20 &\nprintf "%%s\\n%%s\\n%%s\\n" "$$" "$PPID" "$!" >> %s\nwait\n' "$E2E_DIR/run-pids" > "$E2E_BIN/claude-script"
e2e_describe "the probe runs in the background; once the stand-in's three pids are written it is sent SIGTERM"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  export CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" PATH="$E2E_BIN:$PATH" XDG_STATE_HOME="$E2E_DIR/state"
  exec "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --platform --only P4 > "$E2E_DIR/sigterm.out" 2> "$E2E_DIR/sigterm.err"
) &
FP_PROBE=$!
FP_I=0
while [ "$(cat "$E2E_DIR/run-pids" 2>/dev/null | wc -l | tr -d ' ')" -lt 3 ] && [ "$FP_I" -lt 300 ]; do sleep 0.1; FP_I=$((FP_I + 1)); done
kill -TERM "$FP_PROBE" 2>/dev/null
wait "$FP_PROBE"
FP_RC=$?
FP_LEFT=""
for FP_RUN_PID in $(cat "$E2E_DIR/run-pids" 2>/dev/null); do
  kill -0 "$FP_RUN_PID" 2>/dev/null && FP_LEFT="$FP_LEFT $FP_RUN_PID"
done
for FP_RUN_PID in $FP_LEFT; do kill -KILL "$FP_RUN_PID" 2>/dev/null; done
e2e_expect_equal "3" "$(cat "$E2E_DIR/run-pids" 2>/dev/null | wc -l | tr -d ' ')" "pids the stand-in wrote before the signal"
e2e_expect_equal "143" "$FP_RC" "the probe's exit status ($(cat "$E2E_DIR/sigterm.err" 2>/dev/null))"
e2e_expect_equal "" "$FP_LEFT" "the run's processes still running after the probe exited"
e2e_expect_equal "0.1" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]' 2>/dev/null)" "spent_usd"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts"


# SIGHUP (the terminal closing), SIGQUIT and SIGINT stop the probe as SIGTERM
# does. _fp_signal_run <signal> — as above, P4's first run sleeps and the
# probe is sent the signal once the stand-in's three pids are written. The
# probe starts with SIGQUIT and SIGINT at their defaults, as from an
# interactive shell; a script's background job starts with them ignored, and
# the probe leaves an ignored SIGHUP or SIGQUIT alone.
_fp_signal_run() {
  printf '[{"name": "flow", "path": "/Users/someone/.claude/plugins/cache/synapti-marketplace/flow/3.16.0"}]\n' \
    > "$E2E_BIN/claude-plugins-extra"
  printf 'sleep 20 &\nprintf "%%s\\n%%s\\n%%s\\n" "$$" "$PPID" "$!" >> %s\nwait\n' "$E2E_DIR/run-pids" \
    > "$E2E_BIN/claude-script"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    export CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" PATH="$E2E_BIN:$PATH" XDG_STATE_HOME="$E2E_DIR/state"
    exec python3 -c 'import os, signal, sys
signal.signal(signal.SIGQUIT, signal.SIG_DFL)
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])' "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --platform --only P4 \
      > "$E2E_DIR/signal.out" 2> "$E2E_DIR/signal.err"
  ) &
  FP_PROBE=$!
  FP_I=0
  while [ "$(cat "$E2E_DIR/run-pids" 2>/dev/null | wc -l | tr -d ' ')" -lt 3 ] && [ "$FP_I" -lt 300 ]; do
    sleep 0.1; FP_I=$((FP_I + 1))
  done
  kill -"$1" "$FP_PROBE" 2>/dev/null
  wait "$FP_PROBE"
  FP_RC=$?
  FP_LEFT=""
  for FP_RUN_PID in $(cat "$E2E_DIR/run-pids" 2>/dev/null); do
    kill -0 "$FP_RUN_PID" 2>/dev/null && FP_LEFT="$FP_LEFT $FP_RUN_PID"
  done
  for FP_RUN_PID in $FP_LEFT; do kill -KILL "$FP_RUN_PID" 2>/dev/null; done
}

_flow_test_begin "platform: SIGHUP, SIGQUIT or SIGINT while a run waits stops its processes and charges its limit (PL16)"
for FP_SIG in HUP:129 QUIT:131 INT:130; do
  FP_D="P4's first run sleeps; the probe is sent SIG${FP_SIG%%:*}: it exits ${FP_SIG#*:}, none of the run's"
  FP_D+=" processes is left, and spent_usd holds the run's \$0.10 limit"
  _fp_platform_scenario "fp-plat-sig${FP_SIG%%:*}" "$FP_D"
  _fp_signal_run "${FP_SIG%%:*}"
  e2e_expect_equal "3" "$(cat "$E2E_DIR/run-pids" 2>/dev/null | wc -l | tr -d ' ')" \
    "pids the stand-in wrote before the signal"
  e2e_expect_equal "${FP_SIG#*:}" "$FP_RC" "the probe's exit status ($(cat "$E2E_DIR/signal.err" 2>/dev/null))"
  e2e_expect_equal "" "$FP_LEFT" "the run's processes still running after the probe exited"
  e2e_expect_equal "0.1" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]' 2>/dev/null)" "spent_usd"
done


# P16, the worker sandbox, in the platform group. The stand-in claude plays
# Claude Code's sandbox from the --settings file the engine passes: it hides
# the denied files from the gh, security and git credential stand-ins, drops
# the denied variables, refuses writes outside the clone through the touch
# stand-in, answers curl only for the allowed hosts, and points every proxy
# variable at a closed port, so no command reaches a network. A knob makes it
# honour the clone's .claude/settings.json as well, as a Claude Code that let a
# repository widen the sandbox would.
#
# Ways it can be wrong, written down before the checks:
#   SB1 a token part is go although nothing was there to protect: the
#       engine's own reading outside the sandbox found no token
#   SB2 a part is counted from a command the worker changed, or from a call
#       whose tool result never came
#   SB3 the worker's "blocked" is believed although the marker is on disk
#       outside the clone
#   SB4 the settings passed are not the worker sandbox settings, or are not
#       passed with --settings, or the run is not limited to Bash and $1
#   SB5 a repository .claude/settings.json that widens the sandbox goes
#       unnoticed
#   SB6 P16 is go although refusing to start without a sandbox is a launcher
#       behaviour phase 1c builds, or it is marked as run against a stand-in
#   SB7 a token value reaches the record, the evidence or the output
#   SB8 a GH_TOKEN that reaches the worker is missed, or the check runs with
#       no token set at all
#   SB9 P16 starts a run that would pass the spend cap, or is left out of
#       probe --platform
#   SB10 the gh check reads the factory's gh stand-in instead of the real gh
#   SB11 only the first call of a command is read, so a retry that escapes the
#       sandbox (dangerouslyDisableSandbox, allowed by the repository) is
#       missed, or a call made with dangerouslyDisableSandbox counts as go
#   SB12 run B's curl cannot match the repository's excludedCommands pattern,
#       so a Claude Code that honours only that key goes unnoticed
#   SB13 a refusal counts as the sandbox's when the result has no violation
#       block, or a block that does not name example.com
#   SB14 api.github.com failing is blamed on the sandbox when it fails outside
#       the sandbox as well; or allowed_host is go whatever it answered
#   SB15 the commit is believed from the worker's ok without the clone's log
#   SB16 a budget stop before run B throws away run A's parts
#   SB17 the runs have more tools than Bash: --allowedTools only pre-approves

FP_P16_GH_VALUE="p16-fake-gh-keyring-value-3c9e1f"
FP_P16_KEYCHAIN_VALUE="p16-fake-keychain-value-81d2aa"
FP_P16_GIT_VALUE="p16-fake-git-password-5b07c4"

# _fp_p16_scenario <name> <description> — a platform scenario whose gh,
# security and git credential helper hold fake tokens, with the touch and curl
# stand-ins on PATH.
_fp_p16_scenario() {
  _fp_platform_scenario "$1" "$2"
  cp "$FP_FIXTURES/bin/security" "$FP_FIXTURES/platform/curl" "$FP_FIXTURES/platform/touch" \
    "$FP_FIXTURES/platform/git-credential-p16" "$E2E_BIN/"
  printf '%s\n' "$FP_P16_GH_VALUE" > "$E2E_BIN/gh-token"
  printf '%s\n' "$FP_P16_KEYCHAIN_VALUE" > "$E2E_BIN/security-token"
  printf '%s\n' "$FP_P16_GIT_VALUE" > "$E2E_BIN/git-credential-password"
  # The empty helper clears the helpers set before it, such as the system
  # config's osxkeychain, which the cleaned launch environment would read.
  printf '[credential]\n\thelper =\n\thelper = %s\n' "$E2E_BIN/git-credential-p16" > "$E2E_HOME/.gitconfig"
  FP_PID=P16
}

_fp_p16_parts() {   # {part: result} of P16
  _fp_get "$E2E_REPO/$FP_REC" "{k: v['result'] for k, v in sorted(d['probes']['P16']['parts'].items())}"
}

_fp_p16_no_secrets() {   # SB7: no fake token value in the record, evidence, probe area or output
  local v hits=""
  for v in "$FP_P16_GH_VALUE" "$FP_P16_KEYCHAIN_VALUE" "$FP_P16_GIT_VALUE"; do
    hits="$hits$(grep -rlF "$v" "$E2E_REPO/.flow" "$E2E_DIR/state" 2>/dev/null)"
    printf '%s\n%s' "$E2E_OUT" "$E2E_ERR" | grep -qF "$v" && hits="$hits stdout-or-stderr"
  done
  e2e_expect_equal "" "$hits" "files or output holding a token value"
  e2e_expect_equal "" "$(grep -rl 'flow-factory-p16-canary' "$E2E_REPO/.flow" "$E2E_DIR/state" "$E2E_BIN"/claude-* 2>/dev/null)" "files holding the GH_TOKEN canary"
}

FP_P16_ALL_GO='{"allowed_host": "go", "commit_inside": "go", "env_token": "go", "gh_token": "go", "git_credential": "go", "keychain_token": "go", "offlist_curl": "go", "offlist_python": "go", "repo_settings_widen": "go", "unavailable_refused": "deferred", "write_outside": "go"}'

_flow_test_begin "platform: P16 with every sandbox check holding is deferred to 1c, not go (SB4, SB6, SB7, SB10)"
_fp_p16_scenario fp-plat-p16 "the sandboxed worker reads no token, sees no GH_TOKEN, cannot write outside its clone, commits inside it, reaches api.github.com and not example.com, and a widening repository file changes nothing: every part is go but unavailable_refused, so P16 is deferred to 1c"
_fp_platform_run -- --only P16
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "PROBE_PLATFORM="
e2e_expect_equal "$FP_P16_ALL_GO" "$(_fp_p16_parts)" "every P16 part"
e2e_expect_equal "deferred synaptiai/synapti-marketplace#356 False" "$(_fp_p '"%s %s %s" % (p["result"], p.get("deferred_to"), p["stand_in"])')" "P16 result, deferred_to and stand_in"
e2e_expect_equal "synaptiai/synapti-marketplace#356" "$(_fp_p 'p["parts"]["unavailable_refused"]["deferred_to"]')" "unavailable_refused deferred_to"
e2e_expect_equal "2" "$(_fp_launches)" "claude -p starts (run A and run B)"
FP_EV="$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')"
e2e_expect_equal '{"sandbox": {"allowUnsandboxedCommands": false, "credentials": {"envVars": [{"mode": "deny", "name": "GH_TOKEN"}, {"mode": "deny", "name": "GITHUB_TOKEN"}, {"mode": "deny", "name": "GH_ENTERPRISE_TOKEN"}, {"mode": "deny", "name": "GITHUB_ENTERPRISE_TOKEN"}], "files": [{"mode": "deny", "path": "~/.config/gh"}, {"mode": "deny", "path": "~/Library/Keychains"}, {"mode": "deny", "path": "~/.git-credentials"}, {"mode": "deny", "path": "~/.ssh"}, {"mode": "deny", "path": "~/.netrc"}]}, "enabled": true, "excludedCommands": [], "failIfUnavailable": true, "filesystem": {"denyRead": ["~/Library/Keychains"]}, "network": {"allowedDomains": ["api.github.com", "github.com"]}}}' \
  "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$FP_EV/sandbox-settings.json")" "sandbox-settings.json"
e2e_expect_equal "2 2 2 2" "$(grep -c -- "--settings [^ ]*/\.flow/factory/$(_fp_p 'p["evidence"]')/sandbox-settings\.json" "$E2E_BIN/claude-launches.log") $(grep -c -- '--allowedTools Bash ' "$E2E_BIN/claude-launches.log") $(grep -c -- '--tools Bash\( \|$\)' "$E2E_BIN/claude-launches.log") $(grep -c -- '--max-budget-usd ' "$E2E_BIN/claude-launches.log")" "--settings, --allowedTools Bash, --tools Bash (SB17) and a budget limit on both launches"
e2e_expect_equal "1.0" "$(sed -n 1p "$E2E_BIN/claude-launches.log" | sed 's/.*--max-budget-usd \([^ ]*\).*/\1/')" "run A's budget limit"
e2e_expect_equal "2" "$(grep -cx 'auth token' "$E2E_BIN/gh-real.log")" "gh auth token calls that reached the real gh (the baseline and the worker)"
FP_P16_FACTS="$FP_EV/facts.json"
e2e_expect_equal "$((${#FP_P16_GH_VALUE} + 1)) $((${#FP_P16_KEYCHAIN_VALUE} + 1)) 1 200" "$(_fp_get "$FP_P16_FACTS" '"%s %s %s %s" % (d["baseline"]["gh_token"], d["baseline"]["keychain_token"], d["baseline"]["git_credential"], d["baseline"]["allowed_host"])')" "baselines measured outside the sandbox, api.github.com's from the curl stand-in"
e2e_expect_equal "no" "$([ -e "$(_fp_get "$FP_P16_FACTS" 'd["outside_marker"]')" ] && echo yes || echo no)" "the outside marker on disk"
e2e_expect_equal "true" "$(_fp_get "$E2E_DIR/state/flow-factory/probe/P16-1/work-b/.claude/settings.json" 'd["sandbox"]["allowUnsandboxedCommands"]')" "run B's clone holds the widening settings"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
_fp_p16_no_secrets

_flow_test_begin "platform: P16 is no-go when the Keychain stays readable, and names the fallback (SB7)"
_fp_p16_scenario fp-plat-p16-keychain "the stand-in sandbox does not deny ~/Library/Keychains: the Keychain read and git's credential helper return the token, those parts are no-go and P16 names the accepted risk as its fallback"
printf '%s\n' '~/Library/Keychains' > "$E2E_BIN/claude-sandbox-ignore"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go no-go go" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["keychain_token"]["result"], p["parts"]["git_credential"]["result"], p["parts"]["gh_token"]["result"])')" "P16, keychain_token, git_credential and gh_token"
e2e_expect_equal "the risk accepted on 2026-11-12 stays in place: workers can reach the person's write token; residual_risks says so" "$(_fp_p 'p["fallback"]')" "P16 fallback"
_fp_p16_no_secrets

_flow_test_begin "platform: a P16 token part with nothing to protect is not_run, never go (SB1)"
_fp_p16_scenario fp-plat-p16-zero "gh auth token prints nothing outside the sandbox on this machine: gh_token is not_run, so P16 is not_run"
rm -f "$E2E_BIN/gh-token"
: > "$E2E_BIN/gh-no-token"
_fp_platform_run -- --only P16
e2e_expect_equal "not_run not_run" "$(_fp_p '"%s %s" % (p["result"], p["parts"]["gh_token"]["result"])')" "P16 and gh_token"
e2e_expect_out "PROBE_PLATFORM="
FP_HAS=no
case "$(_fp_p 'p["parts"]["gh_token"]["reason"]')" in *"nothing to protect"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "gh_token's reason says there is nothing to protect"

_flow_test_begin "platform: a P16 command the worker changed, or whose result never came, is not_run (SB2)"
_fp_p16_scenario fp-plat-p16-changed "the worker changes the Keychain command and gets no result for the Python check: keychain_token and offlist_python are not_run, and P16 is not go"
printf '%s\n' 'P16 keychain_token' > "$E2E_BIN/claude-alter-steps"
printf '%s\n' 'P16 offlist_python' > "$E2E_BIN/claude-drop-results"
_fp_platform_run -- --only P16
e2e_expect_equal "not_run not_run not_run go" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["keychain_token"]["result"], p["parts"]["offlist_python"]["result"], p["parts"]["gh_token"]["result"])')" "P16, keychain_token, offlist_python and gh_token"
FP_HAS=no
case "$(_fp_p 'p["parts"]["keychain_token"]["reason"]')" in *"changed"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "keychain_token's reason says the worker changed the command"

_flow_test_begin "platform: a P16 outside marker found on disk is no-go although the worker printed blocked (SB3)"
_fp_p16_scenario fp-plat-p16-marker "something else in the run writes the outside marker while the worker's own touch is refused: write_outside is no-go"
printf '%s\n' "p=\$(sed -n 's/^RUN: if [^ ]*touch \\([^ ;]*\\);.*/\\1/p' '$E2E_BIN/claude-prompt-1.txt' | head -1); [ -n \"\$p\" ] && : > \"\$p\"" > "$E2E_BIN/claude-script"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go" "$(_fp_p '"%s %s" % (p["result"], p["parts"]["write_outside"]["result"])')" "P16 and write_outside"
FP_HAS=no
case "$(_fp_p 'p["parts"]["write_outside"]["reason"]')" in *"on disk"*"printed blocked"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "write_outside's reason ($(_fp_p 'p["parts"]["write_outside"]["reason"]'))"

_flow_test_begin "platform: P16 is no-go when the repository's settings widen the sandbox (SB5)"
_fp_p16_scenario fp-plat-p16-widen "the stand-in honours the clone's .claude/settings.json: curl reaches example.com in run B, so repo_settings_widen is no-go, while run A's parts stay go"
: > "$E2E_BIN/claude-sandbox-repo-widens"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go go go" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["repo_settings_widen"]["result"], p["parts"]["offlist_curl"]["result"], p["parts"]["write_outside"]["result"])')" "P16, repo_settings_widen, offlist_curl and write_outside"

_flow_test_begin "platform: P16 reads every call of a command, so a retry with dangerouslyDisableSandbox counts (SB11)"
_fp_p16_scenario fp-plat-p16-retry "the worker retries the refused curl with dangerouslyDisableSandbox; the stand-in honours only the repository's allowUnsandboxedCommands: in run A the retry is refused again, so offlist_curl is not_run, and in run B it reaches example.com, so repo_settings_widen is no-go"
printf '%s\n' allowUnsandboxedCommands > "$E2E_BIN/claude-sandbox-repo-widens"
printf '%s\n' 'P16 offlist_curl' > "$E2E_BIN/claude-retry-unsandboxed"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go not_run no-go go" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["offlist_curl"]["result"], p["parts"]["repo_settings_widen"]["result"], p["parts"]["offlist_python"]["result"])')" "P16, offlist_curl, repo_settings_widen and offlist_python"
FP_HAS=no
case "$(_fp_p 'p["parts"]["offlist_curl"]["reason"]')" in *dangerouslyDisableSandbox*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "offlist_curl's reason names dangerouslyDisableSandbox ($(_fp_p 'p["parts"]["offlist_curl"]["reason"]'))"
FP_HAS=no
case "$(_fp_p 'p["parts"]["repo_settings_widen"]["reason"]')" in *"example.com from curl was reached (200)"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "repo_settings_widen's reason says curl reached example.com ($(_fp_p 'p["parts"]["repo_settings_widen"]["reason"]'))"

_flow_test_begin "platform: a changed re-run of a P16 command that gets out counts as no-go (SB13)"
# Wrong versions: changed commands are ignored once the exact command ran, so
# a re-run that a sandbox rule does not cover (an excludedCommands pattern
# matched by the changed spelling) leaves offlist_curl go; or a changed
# command that stayed refused is allowed to count as go.
_fp_p16_scenario fp-plat-p16-rerun "the worker runs the exact curl, which is refused, then a changed curl that runs outside the stand-in sandbox and reaches example.com: offlist_curl is no-go"
printf '%s\n' 'P16 offlist_curl' > "$E2E_BIN/claude-rerun-changed"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go go" "$(_fp_p '"%s %s %s" % (p["result"], p["parts"]["offlist_curl"]["result"], p["parts"]["offlist_python"]["result"])')" "P16, offlist_curl and offlist_python"
FP_HAS=no
case "$(_fp_p 'p["parts"]["offlist_curl"]["reason"]')" in *"changed"*"200"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "offlist_curl's reason names the changed command that reached example.com ($(_fp_p 'p["parts"]["offlist_curl"]["reason"]'))"

_flow_test_begin "platform: P16 is no-go when the repository's excludedCommands alone lets curl out (SB12)"
_fp_p16_scenario fp-plat-p16-excluded "the stand-in merges only the clone's excludedCommands: run B's curl matches curl * and runs outside the sandbox, so repo_settings_widen is no-go while run A's curl stays refused"
printf '%s\n' excludedCommands > "$E2E_BIN/claude-sandbox-repo-widens"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go go go" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["repo_settings_widen"]["result"], p["parts"]["offlist_curl"]["result"], p["parts"]["write_outside"]["result"])')" "P16, repo_settings_widen, offlist_curl and write_outside"

_flow_test_begin "platform: a refusal of example.com with no violation block is not_run, never go (SB13)"
_fp_p16_scenario fp-plat-p16-noviolations "the stand-in sandbox refuses example.com but reports no network violation: offlist_curl and offlist_python are not_run, so P16 is not_run"
printf '%s\n' network-outbound > "$E2E_BIN/claude-sandbox-drop-violations"
_fp_platform_run -- --only P16
e2e_expect_equal "not_run not_run not_run go" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["offlist_curl"]["result"], p["parts"]["offlist_python"]["result"], p["parts"]["allowed_host"]["result"])')" "P16, offlist_curl, offlist_python and allowed_host"
FP_HAS=no
case "$(_fp_p 'p["parts"]["offlist_curl"]["reason"]')" in *"has no <sandbox_violations> block"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "offlist_curl's reason ($(_fp_p 'p["parts"]["offlist_curl"]["reason"]'))"

_flow_test_begin "platform: a violation block that does not name example.com does not make a refusal the sandbox's (SB13)"
_fp_p16_scenario fp-plat-p16-otherviolation "the curl result's only violation is a file read: offlist_curl is not_run and says no violation names example.com"
printf '%s\n' network-outbound > "$E2E_BIN/claude-sandbox-drop-violations"
printf 'P16 offlist_curl\tfile-read-data /private/etc/ssl/openssl.cnf\n' > "$E2E_BIN/claude-sandbox-extra-violations"
_fp_platform_run -- --only P16
e2e_expect_equal "not_run not_run" "$(_fp_p '"%s %s" % (p["result"], p["parts"]["offlist_curl"]["result"])')" "P16 and offlist_curl"
FP_HAS=no
case "$(_fp_p 'p["parts"]["offlist_curl"]["reason"]')" in *"no sandbox violation names example.com"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "offlist_curl's reason ($(_fp_p 'p["parts"]["offlist_curl"]["reason"]'))"

_flow_test_begin "platform: P16 is no-go when the sandbox lets example.com through from curl and from Python (SB13)"
_fp_p16_scenario fp-plat-p16-network "the stand-in sandbox does not limit the network: curl reaches example.com, and Python's line is rewritten to reached since no test can reach a host: offlist_curl and offlist_python are no-go"
printf '%s\n' network > "$E2E_BIN/claude-sandbox-ignore"
printf 'P16 offlist_python=refused\tP16 offlist_python=reached\n' > "$E2E_BIN/claude-result-replace"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go no-go" "$(_fp_p '"%s %s %s" % (p["result"], p["parts"]["offlist_curl"]["result"], p["parts"]["offlist_python"]["result"])')" "P16, offlist_curl and offlist_python"

_flow_test_begin "platform: allowed_host is no-go when api.github.com fails only inside the sandbox (SB14)"
_fp_p16_scenario fp-plat-p16-github-refused "api.github.com answers 403 inside the sandbox and 200 outside: allowed_host is no-go"
printf 'inside api.github.com 403\n' > "$E2E_BIN/curl-codes"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go" "$(_fp_p '"%s %s" % (p["result"], p["parts"]["allowed_host"]["result"])')" "P16 and allowed_host"

_flow_test_begin "platform: allowed_host is not_run when api.github.com fails outside the sandbox as well (SB14)"
_fp_p16_scenario fp-plat-p16-offline "every host answers 000, inside the sandbox and out, as on a machine with no network: allowed_host is not_run, so P16 is not_run"
printf 'any * 000\n' > "$E2E_BIN/curl-codes"
_fp_platform_run -- --only P16
e2e_expect_equal "not_run not_run" "$(_fp_p '"%s %s" % (p["result"], p["parts"]["allowed_host"]["result"])')" "P16 and allowed_host"
FP_HAS=no
case "$(_fp_p 'p["parts"]["allowed_host"]["reason"]')" in *"outside the sandbox either"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "allowed_host's reason ($(_fp_p 'p["parts"]["allowed_host"]["reason"]'))"

_flow_test_begin "platform: commit_inside is no-go when the worker printed ok but the commit is not in the clone (SB15)"
_fp_p16_scenario fp-plat-p16-commit "a post-commit hook in run A's clone undoes the probe's commit, so git commit exits 0 and the worker prints ok: commit_inside is no-go"
cat > "$E2E_BIN/claude-script" <<'EOF'
case "$PWD" in */work-a)
  hooks=$(git rev-parse --git-path hooks) && mkdir -p "$hooks" &&
    printf '#!/bin/sh\ngit reset -q --soft HEAD^\n' > "$hooks/post-commit" && chmod +x "$hooks/post-commit" ;;
esac
EOF
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go" "$(_fp_p '"%s %s" % (p["result"], p["parts"]["commit_inside"]["result"])')" "P16 and commit_inside"
FP_HAS=no
case "$(_fp_p 'p["parts"]["commit_inside"]["reason"]')" in *"not in the clone"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "commit_inside's reason ($(_fp_p 'p["parts"]["commit_inside"]["reason"]'))"

_flow_test_begin "platform: a budget stop before run B keeps run A's parts (SB16)"
_fp_p16_scenario fp-plat-p16-budget-b "with \$23.50 spent of \$25, run A overshoots its \$1 limit to \$1.08 and ends error_max_budget_usd, so run B would pass the cap: run B never starts, repo_settings_widen is not_run budget, run A's parts and facts are kept, and its error result makes the run_a part and P16 no-go"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 23.5'
printf '0.12\n' > "$E2E_BIN/claude-cost-per-turn"
_fp_platform_run -- --only P16
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "not_run budget go go" "$(_fp_p '"%s %s %s %s" % (p["parts"]["repo_settings_widen"]["result"], p["parts"]["repo_settings_widen"]["reason"], p["parts"]["gh_token"]["result"], p["parts"]["offlist_curl"]["result"])')" "repo_settings_widen, gh_token and offlist_curl"
e2e_expect_equal "no-go 1.08" "$(_fp_p '"%s %s" % (p["result"], p["cost_usd"])')" "P16 result and cost"
e2e_expect_equal "yes" "$(_fp_p '"yes" if "error_max_budget_usd" in p["parts"]["run_a"]["reason"] else p["parts"]["run_a"]["reason"]')" "the run_a part names the subtype"
e2e_expect_equal "error None" "$(_fp_get "$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')/facts.json" '"%s %s" % (d["outcomes"]["run_a"], d["outcomes"]["run_b"])')" "facts outcomes"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"

# SB18 Run B refused by the API makes the whole of P16 not_run, dropping
# what run A saw, a no-go among it.
_flow_test_begin "platform: run B refused by the API keeps run A's parts, a no-go among them (SB18)"
_fp_p16_scenario fp-plat-p16-api-b "run A writes the outside marker, so write_outside is no-go, and run B ends as a run the API refused: P16 stays no-go with run A's parts, and repo_settings_widen alone is not_run with the API's answer"
printf '%s\n' "p=\$(sed -n 's/^RUN: if [^ ]*touch \\([^ ;]*\\);.*/\\1/p' '$E2E_BIN/claude-prompt-1.txt' | head -1); [ -n \"\$p\" ] && : > \"\$p\"" > "$E2E_BIN/claude-script"
printf 'p16-widen-\n' > "$E2E_BIN/claude-api-error-when"
_fp_platform_run -- --only P16
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "2" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "no-go no-go not_run yes" "$(_fp_p '"%s %s %s %s" % (p["result"], p["parts"]["write_outside"]["result"],
  p["parts"]["repo_settings_widen"]["result"], "yes" if p["parts"]["repo_settings_widen"]["reason"].startswith("the run ")
  else p["parts"]["repo_settings_widen"]["reason"])')" "P16, write_outside, repo_settings_widen and its reason"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"

_flow_test_begin "platform: P16 is no-go when GH_TOKEN reaches the worker (SB8)"
_fp_p16_scenario fp-plat-p16-env "the stand-in sandbox does not drop GH_TOKEN: the worker sees the canary, env_token is no-go, and gh auth token prints it"
printf '%s\n' 'GH_TOKEN' > "$E2E_BIN/claude-sandbox-ignore"
_fp_platform_run -- --only P16
e2e_expect_equal "no-go no-go no-go" "$(_fp_p '"%s %s %s" % (p["result"], p["parts"]["env_token"]["result"], p["parts"]["gh_token"]["result"])')" "P16, env_token and gh_token"
_fp_p16_no_secrets

_flow_test_begin "platform: P16 is part of probe --platform and is not started past the spend cap (SB9)"
_fp_p16_scenario fp-plat-p16-budget "with \$24.95 spent of \$25 and no --only, every platform probe including P16 is not_run with reason budget, and neither claude nor the baselines run"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24.95; del d["probes"]["P16"]'
_fp_platform_run --
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run budget" "$(_fp_p '"%s %s" % (p["result"], p["reason"])')" "P16"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "0" "$(cat "$E2E_BIN/gh-real.log" 2>/dev/null | grep -cx 'auth token')" "baseline gh auth token calls"
e2e_expect_equal "24.95" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"

_flow_test_begin "platform: P16 with \$0.40 left of the cap is not started (SB9)"
_fp_p16_scenario fp-plat-p16-budget-only "with \$24.60 spent of \$25, --only P16 records P16 not_run with reason budget"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24.6'
_fp_platform_run -- --only P16
e2e_expect_equal "not_run budget 0" "$(_fp_p '"%s %s" % (p["result"], p["reason"])') $(_fp_launches)" "P16 and claude -p starts"


_flow_test_begin "platform: a run the API refused makes its probe not_run with the API's answer, never no-go (PL15)"
_fp_platform_scenario fp-plat-apierror "every run of the stand-in ends as Claude Code ends a run refused for \
a usage limit: each of the six probes stops at its first run and is not_run with the API's answer, none is \
no-go and nothing is charged"
: > "$E2E_BIN/claude-api-error"
_fp_platform_run
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_SIX='("P1", "P2", "P4", "P5", "P10", "P16")'
e2e_expect_equal "not_run not_run not_run not_run not_run not_run" \
  "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"][p]["result"] for p in '"$FP_SIX"')')" "each probe's result"
e2e_expect_equal "6" "$(_fp_get "$E2E_REPO/$FP_REC" \
  'sum("the API refused the run (usage_limit_reached, HTTP 429)" in d["probes"][p]["reason"] for p in '"$FP_SIX"')')" \
  "probes whose reason gives the API's answer"
e2e_expect_equal "6 0" "$(_fp_launches) $(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" \
  "claude -p starts and spent_usd"

_flow_test_begin "platform: a run that never started, or a git status that got no answer, makes no part no-go and charges nothing (PL17)"
FP_D="every claude -p exits 1 before printing any event, as claude does without credentials: each of the six"
FP_D+=" probes is not_run, none has a no-go part or names a fallback, P1's gh log and leftover paths and P2's .claude"
FP_D+=" files are not_run since no run started, each of the 16 runs starts and nothing is charged; then every run"
FP_D+=" ends as one the API refused: the same, and each probe stops at its first run; then P1's runs complete but git"
FP_D+=" status in its worktree gets no answer (it sleeps past --call-timeout-seconds 3): its leftover paths part is"
FP_D+=" not_run naming it, and P1 has no no-go part and names no fallback"
_fp_platform_scenario fp-plat-no-events "$FP_D"
: > "$E2E_BIN/claude-no-events"
FP_SIX='("P1", "P2", "P4", "P5", "P10", "P16")'
FP_UNSEEN='{pid: [k for k, v in sorted(d["probes"][pid].get("parts", {}).items()) if v["result"] == "no-go"]
  + (["fallback"] if d["probes"][pid].get("fallback") else []) for pid in '"$FP_SIX"'}'
FP_NONE='{"P1": [], "P2": [], "P4": [], "P5": [], "P10": [], "P16": []}'
_fp_platform_run
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run not_run not_run not_run not_run not_run" \
  "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"][p]["result"] for p in '"$FP_SIX"')')" "each probe's result"
e2e_expect_equal "$FP_NONE" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_UNSEEN")" "no-go parts and fallbacks"
e2e_expect_equal "16 0" "$(_fp_launches) $(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" \
  "claude -p starts and spent_usd"
e2e_expect_equal "6" "$(_fp_get "$E2E_REPO/$FP_REC" 'sum("before printing any event: Invalid API key"
  in d["probes"][p]["reason"] for p in '"$FP_SIX"')')" "probes whose reason gives claude's exit and its stderr line"
e2e_expect_equal "not_run not_run not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"]["P1"]["parts"][k]["result"]
  for k in ("bang_first_turn_start", "worktree_write", "gh_log", "leftover_paths"))')" \
  "P1's block, write, gh log and leftover parts"
e2e_expect_equal "not_run not_run not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"]["P5"]["parts"][k]["result"]
  for k in ("session_id", "turn_limit", "budget_limit", "run"))')" "P5's session id, limit and run parts"
e2e_expect_equal "yes yes yes" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join("yes" if t in r else r for t, r in (
  ("no run printed any event", d["probes"]["P1"]["parts"]["gh_log"]["reason"]),
  ("no run printed any event", d["probes"]["P1"]["parts"]["leftover_paths"]["reason"]),
  ("so the worker created nothing to check", d["probes"]["P2"]["parts"]["claude_files_allowlist"]["reason"])))')" \
  "P1's gh log and leftover paths and P2's .claude files say no run started"
e2e_describe "every run ends as one the API refused"
rm "$E2E_BIN/claude-no-events"
: > "$E2E_BIN/claude-api-error"
_fp_platform_run
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run not_run not_run not_run not_run not_run" \
  "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"][p]["result"] for p in '"$FP_SIX"')')" "each probe's result"
e2e_expect_equal "$FP_NONE" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_UNSEEN")" "no-go parts and fallbacks"
e2e_expect_equal "22 0" "$(_fp_launches) $(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" \
  "claude -p starts and spent_usd"
e2e_describe "P1's runs complete, and git status in its worktree gets no answer"
rm "$E2E_BIN/claude-api-error"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'status\n' > "$E2E_BIN/git-no-answer"
_fp_platform_run -- --only P1 --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes [] none 27" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s %s" % (
  p["parts"]["leftover_paths"]["result"], "yes" if "git status could not be read" in p["parts"]["leftover_paths"]["reason"]
  else p["parts"]["leftover_paths"]["reason"], [k for k, v in sorted(p["parts"].items()) if v["result"] == "no-go"],
  "fallback" if p.get("fallback") else "none"))(d["probes"]["P1"])') $(_fp_launches)" \
  "P1's leftover paths part, its reason, P1's no-go parts and fallback, and claude -p starts"

_flow_test_begin "platform: a Write the worker never made is not_run, never no-go (PL17)"
FP_D="the write run skips its Write into the worktree: the worktree write part is not_run naming the call that was"
FP_D+=" never made, not no-go with the phase-1-stops fallback, and the edit and io write parts are still go"
_fp_platform_scenario fp-plat-p1-skip-write "$FP_D"
FP_PID=P1
printf 'factory-probe-write.txt\n' > "$E2E_BIN/claude-skip-steps"
_fp_platform_run -- --only P1
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes go go" "$(_fp_p '"%s %s %s %s" % (p["parts"]["worktree_write"]["result"],
  "yes" if "made no Write call" in p["parts"]["worktree_write"]["reason"] else p["parts"]["worktree_write"]["reason"],
  p["parts"]["worktree_edit"]["result"], p["parts"]["io_write"]["result"])')" "the write parts"
e2e_expect_equal "no" "$(_fp_p '"yes" if p.get("fallback") or p["result"] == "no-go" else "no"')" \
  "P1 no-go or naming a fallback"

# The GitHub write group, `probe --github-write --sandbox <owner/repo>`: P3's
# push and draft pull request on the sandbox, and P6 on that pull request.
# gh is tests/fixtures/factory/github/gh, a stand-in that keeps what is posted
# to it and exits 99 on any call it does not know; the scratch HOME's git
# config rewrites the sandbox's GitHub address to a local bare repository and
# refuses the network transports, so nothing can leave the machine.
#
# Ways it can be wrong, written down before the checks:
#   G1 a sandbox other than the one the decision journal approves is written
#      to, or gh runs before the name is compared (a refusal with calls in
#      the gh log)
#   G2 the approval is read from anywhere but the sandbox: line under
#      ## Phase 0 decisions, or a name that only starts with the approved one
#      passes
#   G3 a sandbox gh repo view cannot find is written to
#   G4 P6 is go although COMMENT failed, or its association is outside
#      /flow:merge's default trust list; a COMMENT refusal is recorded without
#      the issue-comment fallback
#   G5 an APPROVE or REQUEST_CHANGES on one's own PR that GitHub allows is
#      not flagged
#   G6 a posted marker that the lookup cannot find again passes
#   G7 a GitHub write goes to another repository, or a write is missing from
#      the record
#   G8 P3's sandbox writes run although gh is not signed in, or although the
#      environment group recorded gh auth status no-go
#   G9 the GitHub write run drops P3's environment parts, or an environment
#      run drops P3's sandbox parts and writes
#   G10 whether ready or --undo started or cancelled CI decides P6's result
#   G11 P6 is recorded deferred (it has no stand-in) or loses the marker
#      agreement that phase 1f must check
#   G12 any 422 to APPROVE or REQUEST_CHANGES counts as GitHub's refusal of a
#      review of one's own pull request, or GitHub's errors are not kept
#   G13 a push or draft pull request the probe's own shim refuses is recorded
#      no-go, as if GitHub or the sandbox had refused it, or the refusal's
#      text is lost
#   G14 a P6 review, comment, list call or gh pr ready, or the sandbox push,
#      that got no answer, or a list call that failed, is recorded no-go with
#      a fallback, as if GitHub had refused it
#   G15 a sandbox push that reaches the sandbox but whose answer comes after
#      its time limit is recorded no-go, and the draft pull request part says
#      no branch was pushed, although the sandbox holds the commit
#   G16 a gh repo view that got no answer is refused as sandbox_not_found,
#      saying the approved sandbox does not exist
#   G17 a call that got no answer is followed by a reason that says what it
#      would have made was not made: P6 not run because the draft pull request
#      "was not opened" after gh pr create got no answer, or the association
#      part saying "no review was posted" after the COMMENT review got none
#   G18 a sandbox push that exited non-zero is recorded not_run when the git
#      ls-remote after it gets no answer, which hides a refusal that was seen;
#      or its no-go says the sandbox does not hold the commit, which nothing
#      showed

FP_GW_SANDBOX="probe-fixture/sandbox"

# _fp_gw_scenario <name> <description> [gh stand-in config] — a runner
# scenario with the sandbox gh stand-in, a journal approving the fixture
# sandbox, and a local bare repository holding main where the sandbox's
# address leads.
_fp_gw_scenario() {
  local cfg='{}'
  [ $# -ge 3 ] && cfg=$3
  _fp_runner_scenario "$1" "$2"
  cp "$FP_FIXTURES/github/gh" "$FP_FIXTURES/github/gh_sandbox.py" "$E2E_BIN/"
  printf '%s\n' "$cfg" > "$E2E_BIN/gh-config.json"
  printf 'gh stand-in config: %s\n' "$cfg" | _e2e_art
  _fp_journal "$FP_GW_SANDBOX"
  (
    _e2e_git_env
    cd "$E2E_DIR" && git init -q --bare sandbox.git && git init -q seed || exit 1
    cd seed && git -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m seed \
      && git push -q ../sandbox.git HEAD:refs/heads/main
  ) || _flow_assert_fail "$E2E_NAME: could not create the sandbox's bare repository"
  printf '[url "%s"]\n\tinsteadOf = https://github.com/%s.git\n[protocol "https"]\n\tallow = never\n[protocol "ssh"]\n\tallow = never\n[protocol "git"]\n\tallow = never\n' \
    "$E2E_DIR/sandbox.git" "$FP_GW_SANDBOX" > "$E2E_HOME/.gitconfig"
}

# _fp_gw_run <sandbox> [arguments] — probe --github-write.
_fp_gw_run() {
  local sb="$1"; shift
  e2e_run_bin bin/flow-factory.sh probe --github-write --sandbox "$sb" --ci-wait-seconds 0 "$@"
}

_fp_gh_calls() {   # how many calls reached the gh stand-in
  if [ -f "$E2E_BIN/gh-calls.jsonl" ]; then wc -l < "$E2E_BIN/gh-calls.jsonl" | tr -d ' '; else printf '0'; fi
}

_fp_probe_branches() {   # the probe branches the sandbox's bare repository holds
  (cd "$E2E_DIR/sandbox.git" && command git for-each-ref --format='%(refname:short)' 'refs/heads/flow-factory-probe-*' | wc -l | tr -d ' ')
}

_fp_parts() {   # <probe id> — {part: result} of a recorded probe
  _fp_get "$E2E_REPO/$FP_REC" "{k: v['result'] for k, v in sorted(d['probes']['$1']['parts'].items())}"
}

_flow_test_begin "github write: a sandbox other than the approved one is refused before gh runs (G1)"
_fp_gw_scenario fp-gw-other "the journal approves probe-fixture/sandbox and the call names someone/else: refused with exit 5, naming the approved sandbox, no gh call and no record"
_fp_gw_run someone/else
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=sandbox_not_approved"
e2e_expect_out "approved: probe-fixture/sandbox"
e2e_expect_equal "0" "$(_fp_gh_calls)" "calls that reached gh"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
e2e_expect_equal "0" "$(_fp_probe_branches)" "probe branches in the sandbox"

_flow_test_begin "github write: a name that only starts with the approved one is refused (G2)"
_fp_gw_scenario fp-gw-suffix "the call names probe-fixture/sandbox2: refused, no gh call"
_fp_gw_run probe-fixture/sandbox2
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=sandbox_not_approved"
e2e_expect_equal "0" "$(_fp_gh_calls)" "calls that reached gh"

_flow_test_begin "github write: a sandbox line outside ## Phase 0 decisions approves nothing (G2)"
_fp_gw_scenario fp-gw-outside "the decisions section approves no sandbox and the specification above it names someone/else: a call naming someone/else is refused"
_fp_journal ""
_fp_gw_run someone/else
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=sandbox_not_approved"
e2e_expect_out "no sandbox: line"
e2e_expect_equal "0" "$(_fp_gh_calls)" "calls that reached gh"

_flow_test_begin "github write: no decision journal approves nothing (G2)"
_fp_gw_scenario fp-gw-nojournal "the journal file is missing: refused as a repository this epic's probe does not record for, no gh call"
rm -f "$E2E_REPO/.decisions/issue-353.md"
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=not_this_epic"
e2e_expect_equal "0" "$(_fp_gh_calls)" "calls that reached gh"

_flow_test_begin "github write: an approved sandbox gh repo view cannot find is refused (G3)"
_fp_gw_scenario fp-gw-notfound "gh repo view fails for the approved sandbox: refused with sandbox_not_found after that one call, and nothing is written" '{"repo_view_fails": true}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=sandbox_not_found"
e2e_expect_equal "1" "$(_fp_gh_calls)" "calls that reached gh"
e2e_expect_equal '["repo", "view", "probe-fixture/sandbox"]' "$(head -1 "$E2E_BIN/gh-calls.jsonl" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[:3]))')" "the one call"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
e2e_expect_equal "0" "$(_fp_probe_branches)" "probe branches in the sandbox"

_flow_test_begin "github write: P3 pushes and opens a draft PR, and P6 is go with writes only to the sandbox (G4, G7, G10, G11)"
_fp_gw_scenario fp-gw-go "the stand-in answers COMMENT with review id 1 as OWNER and refuses APPROVE and REQUEST_CHANGES with 422; ready starts a run and --undo cancels it: P3's sandbox parts are go, P6 is go, every write names the sandbox" \
  '{"ready_starts_run": true, "undo_cancels": true}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "PROBE_GITHUB_WRITE="
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["result"]')" "P6 result"
e2e_expect_equal '{"approve_refused": "go", "comment_review": "go", "marker_lookup": "go", "ready_undo": "go", "request_changes_refused": "go", "review_association": "go"}' "$(_fp_parts P6)" "every P6 part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "review id 1" in d["probes"]["P6"]["parts"]["comment_review"]["reason"] else d["probes"]["P6"]["parts"]["comment_review"]["reason"]')" "the COMMENT part names the review id"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "OWNER" in d["probes"]["P6"]["parts"]["review_association"]["reason"] else d["probes"]["P6"]["parts"]["review_association"]["reason"]')" "the association part names OWNER"
e2e_expect_equal "synaptiai/synapti-marketplace#359" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["parts"]["marker_lookup"].get("deferred_to")')" "the marker part carries the agreement with /flow:merge to phase 1f"
e2e_expect_equal "false absent" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (str(d["probes"]["P6"]["stand_in"]).lower(), d["probes"]["P6"].get("deferred_to", "absent"))')" "P6 stand_in and probe deferred_to"
e2e_expect_equal "github_write" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["group"]')" "P6 group"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if {w["call"] for w in d["probes"]["P6"]["github_writes"]} >= {"POST repos/probe-fixture/sandbox/pulls/7/reviews", "POST repos/probe-fixture/sandbox/issues/7/comments", "gh pr ready"} else d["probes"]["P6"]["github_writes"]')" "P6's writes: the reviews, the marker comment and gh pr ready"
e2e_expect_equal '{"environment_checks": "not_run", "sandbox_draft_pr": "go", "sandbox_push": "go"}' "$(_fp_parts P3)" "P3 parts with no environment run"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result while its environment checks have not run"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if [w["call"].split(" ")[:2] for w in d["probes"]["P3"]["github_writes"]] == [["git", "push"], ["gh", "pr"]] else d["probes"]["P3"]["github_writes"]')" "P3's writes: the push, then gh pr create"
e2e_expect_equal "probe-fixture/sandbox" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(sorted({w["repo"] for p in d["probes"].values() for w in p["github_writes"]}))')" "the repositories written to"
e2e_expect_equal "1" "$(_fp_probe_branches)" "probe branches in the sandbox"
e2e_expect_equal "" "$(cat "$E2E_BIN/gh-unhandled.log" 2>/dev/null)" "calls the gh stand-in did not know"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_expect_equal "probe-fixture/sandbox" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["github_write"]["keyed_on"]["sandbox"]')" "keyed_on sandbox"
e2e_expect_equal "gh version 2.80.0 (2026-10-01)" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["github_write"]["keyed_on"]["gh_version"]')" "keyed_on gh_version"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["evidence"]')/facts.json"
e2e_expect_equal "[9000] [9000]" "$(_fp_get "$FP_FACTS" '"%s %s" % (d["ci"]["started_by_ready"], d["ci"]["cancelled_by_undo"])')" "CI started by ready and cancelled by --undo, as facts"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --dispositions --writes-only-to "$FP_GW_SANDBOX"
e2e_expect_no_out "write_outside_sandbox"
e2e_expect_no_out "stand_in_go"
e2e_expect_no_out "parts_mismatch"
e2e_expect_no_out "deferred_without_phase"
e2e_expect_no_out "not_run_without_reason"

_flow_test_begin "github write: a COMMENT refused with 422 makes P6 no-go with the issue-comment fallback (G4)"
_fp_gw_scenario fp-gw-comment-422 "the stand-in answers COMMENT with 422: P6 is no-go, its fallback moves markers to issue comments, and the association part is not run" '{"status_COMMENT": 422}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["result"]')" "P6 result"
e2e_expect_equal "no-go not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P6"]["parts"]["comment_review"]["result"], d["probes"]["P6"]["parts"]["review_association"]["result"])')" "COMMENT and association parts"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "markers move to issue comments; /flow:merge will not see them" in d["probes"]["P6"].get("fallback", "") else d["probes"]["P6"]')" "P6 fallback"
e2e_expect_equal "" "$(cat "$E2E_BIN/gh-unhandled.log" 2>/dev/null)" "calls the gh stand-in did not know"

_flow_test_begin "github write: an association outside the default trust list makes P6 no-go (G4)"
_fp_gw_scenario fp-gw-assoc "the review is posted as CONTRIBUTOR, which /flow:merge's default trust list leaves out: the association part and P6 are no-go" '{"association": "CONTRIBUTOR"}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "go no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P6"]["parts"]["comment_review"]["result"], d["probes"]["P6"]["parts"]["review_association"]["result"])')" "COMMENT and association parts"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["result"]')" "P6 result"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "CONTRIBUTOR" in d["probes"]["P6"]["parts"]["review_association"]["reason"] else d["probes"]["P6"]["parts"]["review_association"]["reason"]')" "the reason names the association"

_flow_test_begin "github write: an APPROVE GitHub allows on one's own PR is flagged (G5)"
_fp_gw_scenario fp-gw-approve "the stand-in accepts APPROVE: that part is no-go and the fallback keeps the rework departure" '{"status_APPROVE": 200}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "no-go go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P6"]["parts"]["approve_refused"]["result"], d["probes"]["P6"]["parts"]["request_changes_refused"]["result"])')" "APPROVE and REQUEST_CHANGES parts"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "rework departure is still kept" in d["probes"]["P6"].get("fallback", "") else d["probes"]["P6"]')" "P6 fallback"

# GitHub refuses a review of one's own pull request with 422. A 403 says the
# token could not post a review at all, which shows nothing about that rule.
_flow_test_begin "github write: an APPROVE answered 403 is not taken for GitHub's own-PR refusal (G5)"
_fp_gw_scenario fp-gw-approve-403 "the stand-in answers APPROVE with 403 and REQUEST_CHANGES with 422: the APPROVE part is not_run naming 403, the REQUEST_CHANGES part is go, P6 is not go, and the facts keep GitHub's message" \
  '{"status_APPROVE": 403, "message_APPROVE": "Resource not accessible by integration"}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P6"]["parts"]["approve_refused"]["result"], d["probes"]["P6"]["parts"]["request_changes_refused"]["result"])')" "APPROVE and REQUEST_CHANGES parts"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "403" in d["probes"]["P6"]["parts"]["approve_refused"]["reason"] else d["probes"]["P6"]["parts"]["approve_refused"]["reason"]')" "the APPROVE part names 403"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["result"]')" "P6 result"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["evidence"]')/facts.json"
e2e_expect_equal "403 Resource not accessible by integration|422 Unprocessable Entity" "$(_fp_get "$FP_FACTS" '"%s %s|%s %s" % (d["approve"]["status"], d["approve"]["message"], d["request_changes"]["status"], d["request_changes"]["message"])')" "each answer's status and message, as facts"

# GitHub refuses a review of one's own pull request with 422 and an errors
# entry saying so. A 422 for another reason shows nothing about that rule.
# _fp_p6_errors <name> <description> <gh stand-in config> <APPROVE part>
# <REQUEST_CHANGES part> (G12)
_fp_p6_errors() {
  _fp_gw_scenario "$1" "$2" "$3"
  _fp_gw_run "$FP_GW_SANDBOX"
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  e2e_expect_equal "$4 $5" "$(_fp_get "$E2E_REPO/$FP_REC" \
    '"%s %s" % tuple(d["probes"]["P6"]["parts"][k]["result"]
                     for k in ("approve_refused", "request_changes_refused"))')" \
    "APPROVE and REQUEST_CHANGES parts"
  FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["evidence"]')/facts.json"
}

_flow_test_begin "github write: only GitHub's own-pull-request refusal counts as one (G12)"
FP_D="APPROVE is refused with 422 for a closed pull request, and REQUEST_CHANGES with 422 and APPROVE's own-PR"
FP_D+=" text: both parts are not_run with GitHub's text, and the facts keep the errors"
_fp_p6_errors fp-gw-p6-other "$FP_D" \
  '{"errors_APPROVE": ["Pull request is closed"], "errors_REQUEST_CHANGES": ["Can not approve your own pull request"]}' \
  not_run not_run
e2e_expect_equal "yes yes" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join("yes" if t in d["probes"]["P6"]["parts"][k]["reason"]
  else d["probes"]["P6"]["parts"][k]["reason"] for k, t in (("approve_refused", "Pull request is closed"),
  ("request_changes_refused", "Can not approve your own pull request")))')" "each reason gives GitHub's text"
e2e_expect_equal '["Pull request is closed"]' "$(_fp_get "$FP_FACTS" 'd["approve"]["errors"]')" \
  "APPROVE's errors, as facts"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["result"]')" "P6 result"
FP_D="APPROVE is refused with 422 and no errors list; REQUEST_CHANGES's errors are objects whose message, in"
FP_D+=" lower case, is GitHub's own-PR text: APPROVE is not_run, REQUEST_CHANGES is go"
FP_CFG='{"errors_APPROVE": null, "errors_REQUEST_CHANGES": [{"resource": "PullRequestReview", "code": "custom",'
FP_CFG+=' "message": "can not request changes on your own pull request"}]}'
_fp_p6_errors fp-gw-p6-noerrors "$FP_D" "$FP_CFG" not_run go
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda r: "yes" if "Unprocessable Entity" in r else r)(
  d["probes"]["P6"]["parts"]["approve_refused"]["reason"])')" "the APPROVE reason gives GitHub's message"
FP_D="both events are refused with GitHub's own-PR texts: both parts are go and the facts keep the errors"
_fp_p6_errors fp-gw-p6-own "$FP_D" '{}' go go
e2e_expect_equal '["Can not request changes on your own pull request"]' \
  "$(_fp_get "$FP_FACTS" 'd["request_changes"]["errors"]')" "REQUEST_CHANGES's errors, as facts"
e2e_expect_equal "gh version 2.80.0 (2026-10-01)" "$(_fp_get "$E2E_REPO/$FP_REC" \
  'd["probes"]["P3"]["parts"]["sandbox_push"]["keyed_on"]["gh_version"]')" \
  "the gh version the sandbox part was recorded under (R6)"

_flow_test_begin "github write: a marker the lookup cannot find again is no-go (G6)"
_fp_gw_scenario fp-gw-lookup "the stand-in lists no reviews or comments: the marker part is no-go and the fallback looks for the effect itself" '{"lookup_loses": true}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["parts"]["marker_lookup"]["result"]')" "marker part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "effect itself" in d["probes"]["P6"].get("fallback", "") else d["probes"]["P6"]')" "P6 fallback"

_flow_test_begin "github write: a failing gh pr ready is no-go, and CI never decides (G10)"
_fp_gw_scenario fp-gw-ready "gh pr ready exits 1: the ready part is no-go with its reason" '{"ready_fails": true}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["parts"]["ready_undo"]["result"]')" "ready part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if d["probes"]["P6"].get("fallback") else d["probes"]["P6"]')" "P6 names a fallback"

_flow_test_begin "github write: with gh not signed in nothing is written (G8)"
_fp_gw_scenario fp-gw-noauth "gh auth status exits 1: the sandbox parts and P6 are not run, no branch is pushed, and no write is recorded" '{"auth_fails": true}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P3"]["parts"]["sandbox_push"]["result"], d["probes"]["P3"]["parts"]["sandbox_draft_pr"]["result"])')" "sandbox parts"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["result"]')" "P6 result"
e2e_expect_equal "0" "$(_fp_probe_branches)" "probe branches in the sandbox"
e2e_expect_equal "[] []" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P3"]["github_writes"], d["probes"]["P6"]["github_writes"])')" "github_writes"
e2e_expect_equal "repo view|auth status" "$(python3 -c 'import json,sys; print("|".join(" ".join(json.loads(l)[:2]) for l in open(sys.argv[1])))' "$E2E_BIN/gh-calls.jsonl")" "the gh calls made"

# The main checkout's origin is an ssh address, so the sandbox is pushed to
# over ssh, and the user's git config sets core.sshCommand: the shim cannot
# tell where that push goes, so it refuses it. The scratch HOME's config
# leads the sandbox's ssh address to the local bare repository, so the fetch
# before the push still works.
_flow_test_begin "github write: a sandbox push the probe's own shim refuses is not run, never no-go (G13)"
FP_D="core.sshCommand in the user's git config makes the shim refuse the ssh push to the sandbox: sandbox_push is"
FP_D+=" not_run with the shim's refusal as its reason, the draft pull request and P6 are not run, P3 has no"
FP_D+=" fallback, no branch reaches the sandbox, and the refused write is listed"
_fp_gw_scenario fp-gw-shim-refused "$FP_D"
(
  _e2e_git_env
  cd "$E2E_REPO" && git remote add origin git@github.com:probe-fixture/main-checkout.git
) || _flow_assert_fail "$E2E_NAME: could not give the main checkout an ssh origin"
printf '[url "%s"]\n\tinsteadOf = git@github.com:%s.git\n[core]\n\tsshCommand = ssh\n' \
  "$E2E_DIR/sandbox.git" "$FP_GW_SANDBOX" >> "$E2E_HOME/.gitconfig"
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"environment_checks": "not_run", "sandbox_draft_pr": "not_run", "sandbox_push": "not_run"}' \
  "$(_fp_parts P3)" "P3 parts"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda r: "yes" if r.startswith(
  "flow factory probe: refused git push -q git@github.com:probe-fixture/sandbox.git HEAD:refs/heads/flow-factory-probe-")
  and "(writes to unresolved/unresolved)" in r else r)(d["probes"]["P3"]["parts"]["sandbox_push"]["reason"])')" \
  "sandbox_push's reason is the shim's refusal"
e2e_expect_equal "not_run absent not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s" % (d["probes"]["P3"]["result"],
  d["probes"]["P3"].get("fallback") or "absent", d["probes"]["P6"]["result"])')" "P3 result, P3 fallback and P6 result"
e2e_expect_equal "0" "$(_fp_probe_branches)" "probe branches in the sandbox"
e2e_expect_equal "unresolved/unresolved git push True" "$(_fp_get "$E2E_REPO/$FP_REC" '" | ".join("%s %s %s" % (
  w["repo"], " ".join(w["call"].split(" ")[:2]), w.get("refused")) for w in d["probes"]["P3"]["github_writes"])')" \
  "P3's writes: the refused push alone"
e2e_expect_equal "repo view|auth status" "$(python3 -c 'import json,sys
print("|".join(" ".join(json.loads(l)[:2]) for l in open(sys.argv[1])))' "$E2E_BIN/gh-calls.jsonl")" "the gh calls made"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --writes-only-to "$FP_GW_SANDBOX"
fe_mask_output 'flow-factory-probe-[0-9]{8}T[0-9]{6}Z-[0-9a-f]+' 'flow-factory-probe-<time>-<id>'
e2e_expect_out "PROBES_REFUSED_WRITE=P3 unresolved/unresolved git push -q git@github.com:probe-fixture/sandbox.git"
e2e_expect_no_out "write_outside_sandbox"

_flow_test_begin "github write: a recorded no-go gh auth status stops the writes, and the environment parts are kept (G8, G9)"
_fp_gw_scenario fp-gw-recorded-noauth "the record holds P3 from the environment group with gh auth status no-go: nothing is pushed, and that part is kept"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P3"].update(group="environment", result="no-go", fallback="add the missing variables through extraEnv", parts={"gh_auth_status": {"result": "no-go", "reason": "gh auth status exited 1"}, "signing": {"result": "go", "reason": "ok"}})'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal '{"gh_auth_status": "no-go", "sandbox_draft_pr": "not_run", "sandbox_push": "not_run", "signing": "go"}' "$(_fp_parts P3)" "P3 parts"
e2e_expect_equal "environment no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P3"]["group"], d["probes"]["P3"]["result"])')" "P3 group and result"
e2e_expect_equal "0" "$(_fp_probe_branches)" "probe branches in the sandbox"

_flow_test_begin "github write: P3's environment parts are kept and decide its result with the sandbox parts (G9)"
_fp_gw_scenario fp-gw-keep-env "the record holds P3 from the environment group with every part go: the sandbox parts join them and P3 is go"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P3"].update(group="environment", parts={"gh_auth_status": {"result": "go", "reason": "ok"}, "worker_token": {"result": "go", "reason": "ok"}})'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal '{"gh_auth_status": "go", "sandbox_draft_pr": "go", "sandbox_push": "go", "worker_token": "go"}' "$(_fp_parts P3)" "P3 parts"
e2e_expect_equal "go environment" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P3"]["result"], d["probes"]["P3"]["group"])')" "P3 result and group"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --dispositions --writes-only-to "$FP_GW_SANDBOX"
e2e_expect_no_out "parts_mismatch"
e2e_expect_no_out "write_outside_sandbox"

_flow_test_begin "github write: a P6 or sandbox call that gets no answer, or a list call that fails, is not_run, never no-go (G14, G15)"
FP_D="the reviews, the marker comment and gh pr ready get no answer (each sleeps past --call-timeout-seconds 3):"
FP_D+=" P3's push and pull request are go, and each P6 part those calls decide is not_run, none no-go and no"
FP_D+=" fallback; then the lists the lookup reads fail with GitHub's 502: the marker part is not_run naming the list"
FP_D+=" call, and the facts keep gh's error; then git push gets no answer: P3's sandbox parts are not_run naming it,"
FP_D+=" and P6 is not run; nothing is charged; then git push reaches the sandbox and answers after the time limit:"
FP_D+=" the push part is go naming the late answer, and the pull request is opened"
_fp_gw_scenario fp-gw-no-answer "$FP_D" '{"no_answer": ["api --include --method POST", "pr ready"]}'
FP_UNSEEN='{pid: [k for k, v in sorted(d["probes"][pid].get("parts", {}).items()) if v["result"] == "no-go"]
  + (["fallback"] if d["probes"][pid].get("fallback") else []) for pid in ("P3", "P6")}'
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"approve_refused": "not_run", "comment_review": "not_run", "marker_lookup": "not_run", "ready_undo": "not_run", "request_changes_refused": "not_run", "review_association": "not_run"}' \
  "$(_fp_parts P6)" "every P6 part"
e2e_expect_equal '{"environment_checks": "not_run", "sandbox_draft_pr": "go", "sandbox_push": "go"}' "$(_fp_parts P3)" \
  "P3 parts"
e2e_expect_equal '{"P3": [], "P6": []}' "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_UNSEEN")" "no-go parts and fallbacks"
e2e_expect_equal "yes yes yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % tuple("yes" if t in p[k]["reason"]
  else p[k]["reason"] for k, t in (("comment_review", "no HTTP answer"), ("marker_lookup", "no HTTP answer"),
  ("ready_undo", "did not answer"))))(d["probes"]["P6"]["parts"])')" "what each part names as getting no answer"
e2e_describe "the lists the marker lookup reads fail with GitHub's 502"
printf '{"list_fails": true}\n' > "$E2E_BIN/gh-config.json"
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"],
  "yes" if "gh api repos/probe-fixture/sandbox/issues/7/comments?per_page=100 exited 1" in p["reason"]
  else p["reason"]))(d["probes"]["P6"]["parts"]["marker_lookup"])')" "the marker part names the failed list call"
e2e_expect_equal '{"P3": [], "P6": []}' "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_UNSEEN")" "no-go parts and fallbacks"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P6"]["evidence"]')/facts.json"
e2e_expect_equal "gh: Bad Gateway (HTTP 502)" "$(_fp_get "$FP_FACTS" 'd["lookup_failures"][0]["error"]')" \
  "gh's error in the facts"
e2e_describe "git push to the sandbox gets no answer"
printf '{}\n' > "$E2E_BIN/gh-config.json"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'push\n' > "$E2E_BIN/git-no-answer"
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s %s" % (
  p["parts"]["sandbox_push"]["result"], "yes" if "did not answer" in p["parts"]["sandbox_push"]["reason"]
  else p["parts"]["sandbox_push"]["reason"], p["parts"]["sandbox_draft_pr"]["result"],
  d["probes"]["P6"]["result"]))(d["probes"]["P3"])')" "the push part, its reason, the pull request part and P6"
e2e_expect_equal '{"P3": [], "P6": []}' "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_UNSEEN")" "no-go parts and fallbacks"
e2e_expect_equal "0" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"
e2e_describe "git push reaches the sandbox, and its answer comes after the time limit (G15)"
rm "$E2E_BIN/git-no-answer"
printf 'push\n' > "$E2E_BIN/git-answer-late"
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "go yes go" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (
  p["parts"]["sandbox_push"]["result"], "yes" if "did not answer" in p["parts"]["sandbox_push"]["reason"]
  and "the sandbox holds the commit" in p["parts"]["sandbox_push"]["reason"] else p["parts"]["sandbox_push"]["reason"],
  p["parts"]["sandbox_draft_pr"]["result"]))(d["probes"]["P3"])')" "the push part, its reason and the pull request part"
e2e_expect_equal '{"P3": [], "P6": []}' "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_UNSEEN")" "no-go parts and fallbacks"

_flow_test_begin "github write: a sandbox push that exited non-zero is no-go although the ls-remote after it got no answer (G18)"
FP_D="git push to the sandbox exits 128, as for a token that may not push, and the git ls-remote after it gets no"
FP_D+=" answer (it sleeps past --call-timeout-seconds 3): sandbox_push is no-go naming the exit and the ls-remote"
FP_D+=" that did not answer, never not_run, and does not say the sandbox lacks the commit; P3 names its fallback,"
FP_D+=" and P6 is not run"
_fp_gw_scenario fp-gw-push-fails-unlisted "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'push\n' > "$E2E_BIN/git-fail"
printf 'ls-remote\n' > "$E2E_BIN/git-no-answer"
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go yes no" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (p["result"], "yes" if
  all(t in p["reason"] for t in ("exited 128", "ls-remote", "did not answer")) else p["reason"],
  "yes" if "does not hold" in p["reason"] else "no"))(d["probes"]["P3"]["parts"]["sandbox_push"])')" \
  "the push part, what its reason names, and whether it says the sandbox lacks the commit"
e2e_expect_equal "yes not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % ("yes" if d["probes"]["P3"].get("fallback")
  else "no", d["probes"]["P6"]["result"])')" "P3's fallback and P6's result"
e2e_expect_equal "0" "$(_fp_probe_branches)" "probe branches in the sandbox"

# G19-G21 A server error, a rate limit or a network failure is read as
# GitHub refusing the request: the part is no-go and brings a fallback that
# changes the design, although nothing about GitHub's rules was seen. Only a
# 4xx other than 429, or gh printing GitHub's refusal, is a no-go.
_flow_test_begin "github write: a COMMENT and a marker comment answered 5xx, and gh pr ready failing on the network, are not run, never no-go (G19)"
FP_D="the COMMENT review answers 502, the marker comment 503, and gh pr ready exits 1 printing a network error:"
FP_D+=" comment_review, marker_lookup and ready_undo are not_run, P6 is not no-go and names no fallback"
_fp_gw_scenario fp-gw-server-errors "$FP_D" \
  '{"status_COMMENT": 502, "status_comment": 503, "ready_fails": true, "ready_stderr": "error connecting to api.github.com"}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s" % tuple(
  d["probes"]["P6"]["parts"][k]["result"] for k in ("comment_review", "marker_lookup", "ready_undo"))')" \
  "comment_review, marker_lookup and ready_undo"
e2e_expect_equal "not no-go, no fallback" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s, %s" % (
  "no-go" if d["probes"]["P6"]["result"] == "no-go" else "not no-go",
  "a fallback" if d["probes"]["P6"].get("fallback") else "no fallback")')" "P6 result and fallback"

_flow_test_begin "github write: gh pr ready and --undo succeeding with the workflow runs unreadable is not run, never go (G20)"
_fp_gw_scenario fp-gw-runs-unreadable "the workflow runs GET fails with 502: ready_undo is not_run, naming that the CI effect was not seen, and every other P6 part is go" \
  '{"runs_fail": true}'
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '{"approve_refused": "go", "comment_review": "go", "marker_lookup": "go", "ready_undo": "not_run", "request_changes_refused": "go", "review_association": "go"}' \
  "$(_fp_parts P6)" "every P6 part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '("yes" if "effect on CI was not seen" in
  d["probes"]["P6"]["parts"]["ready_undo"]["reason"] else d["probes"]["P6"]["parts"]["ready_undo"]["reason"])')" \
  "ready_undo's reason"

_flow_test_begin "github write: a push that exited 0 whose ls-remote failed is not run, never no-go (G21)"
FP_D="git push to the sandbox exits 0 and the git ls-remote that checks it exits 128: sandbox_push is not_run naming"
FP_D+=" the ls-remote, P3 names no fallback, and the draft pull request is not run"
_fp_gw_scenario fp-gw-listing-fails "$FP_D"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'ls-remote\n' > "$E2E_BIN/git-fail"
_fp_gw_run "$FP_GW_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes not_run no" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s %s" % (
  p["parts"]["sandbox_push"]["result"], "yes" if "ls-remote" in p["parts"]["sandbox_push"]["reason"]
  else p["parts"]["sandbox_push"]["reason"], p["parts"]["sandbox_draft_pr"]["result"],
  "yes" if p.get("fallback") else "no"))(d["probes"]["P3"])')" "the push part, its reason, the pull request part and P3's fallback"

FP_D="gh repo view of the approved sandbox gets no answer (it sleeps past --call-timeout-seconds 3): refused with"
FP_D+=" sandbox_unreachable naming the call that did not answer, never sandbox_not_found, and nothing is written"
_fp_gw_scenario fp-gw-view-no-answer "$FP_D" '{"no_answer": ["repo view"]}'
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "5" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_line "FACTORY_REFUSED=sandbox_unreachable (probe-fixture/sandbox: gh repo view did not answer (timed out after 3 s))"
e2e_expect_no_out "sandbox_not_found"
e2e_expect_equal "no 0" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no) $(_fp_probe_branches)" \
  "a record written, and probe branches in the sandbox"

_flow_test_begin "github write: a call that gets no answer is never followed by a reason saying what it would make was not made (G17)"
FP_D="gh pr create gets no answer (it sleeps past --call-timeout-seconds 3): sandbox_draft_pr is not_run naming it,"
FP_D+=" P6 is not run with a reason that says whether the pull request was opened is unknown, never that it was not"
FP_D+=" opened, and P3's facts say so; then only the COMMENT review gets no answer: the association part says"
FP_D+=" whether a review was posted is unknown, never that none was"
_fp_gw_scenario fp-gw-unknown-after "$FP_D" '{"no_answer": ["pr create"]}'
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "go not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P3"]["parts"]["sandbox_push"]["result"],
  d["probes"]["P3"]["parts"]["sandbox_draft_pr"]["result"])')" "the push and draft pull request parts"
e2e_expect_equal "not_run yes no" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (p["result"], "yes" if
  "gh pr create --draft did not answer" in p["reason"] and "unknown" in p["reason"] else p["reason"],
  "yes" if "was not opened" in p["reason"] else "no"))(d["probes"]["P6"])')" \
  "P6's result, what its reason names, and whether it says the pull request was not opened"
FP_FACTS="$E2E_REPO/.flow/factory/$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["evidence"]')/facts.json"
e2e_expect_equal "yes" "$(_fp_get "$FP_FACTS" '("yes" if "did not answer" in (d.get("pull_request_unknown") or "")
  else d)')" "P3's facts say whether the pull request was opened is unknown"
e2e_describe "only the COMMENT review gets no answer"
printf '%s\n' '{"no_answer": ["api --include --method POST repos/probe-fixture/sandbox/pulls/7/reviews -f event=COMMENT"]}' \
  > "$E2E_BIN/gh-config.json"
_fp_gw_run "$FP_GW_SANDBOX" --call-timeout-seconds 3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes no" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s %s" % (p["result"], "yes" if
  "unknown" in p["reason"] else p["reason"], "yes" if "no review was posted" in p["reason"]
  else "no"))(d["probes"]["P6"]["parts"]["review_association"])')" \
  "the association part, whether its reason says unknown, and whether it says no review was posted"

_flow_test_begin "environment: an environment run keeps P3's sandbox parts and writes (G9)"
_fp_env_scenario fp-env-keep-sandbox "the record holds P3's sandbox parts and writes from the GitHub write group: probe --environment --only P3 keeps both and drops the not-run environment placeholder"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P3"].update(group="github_write", result="not_run", parts={"environment_checks": {"result": "not_run", "reason": "not yet"}, "sandbox_push": {"result": "go", "reason": "pushed"}, "sandbox_draft_pr": {"result": "go", "reason": "opened"}}, github_writes=[{"repo": "probe-fixture/sandbox", "call": "git push -q https://github.com/probe-fixture/sandbox.git HEAD:refs/heads/flow-factory-probe-x"}, {"repo": "probe-fixture/sandbox", "call": "gh pr create"}]); del d["interpreter"]'
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "go go absent" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s" % (d["probes"]["P3"]["parts"]["sandbox_push"]["result"], d["probes"]["P3"]["parts"]["sandbox_draft_pr"]["result"], "present" if "environment_checks" in d["probes"]["P3"]["parts"] else "absent")')" "sandbox parts and the placeholder"
e2e_expect_equal "git push|gh pr" "$(_fp_get "$E2E_REPO/$FP_REC" '"|".join(" ".join(w["call"].split(" ")[:2]) for w in d["probes"]["P3"]["github_writes"])')" "P3's sandbox writes"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["result"]')" "P3 result"
_fp_env_after

# _fp_p3_keep <name> <description> <env or placeholder> <blocked or raises> —
# P3 recorded with its sandbox parts and three sandbox writes (one of them,
# against the rules, to someone/else) and, with env, two environment parts.
# The seeded record names no interpreter, so the run records its own without
# the terminal a replacement needs (person_channels L19).
# Then probe --environment --only P3 does not finish P3's checks: the
# record's P11 is no-go, or the scratch push-source repository's git config
# cannot be read, so P3 stops part way (E16).
_fp_p3_keep() {
  _fp_env_scenario "$1" "$2"
  mkdir -p "$E2E_REPO/.flow/factory/evidence/P3-1"
  local group=github_write parts='"environment_checks": {"result": "not_run", "reason": "not yet"}' p11=''
  if [ "$3" = env ]; then
    group=environment
    parts='"gh_auth_status": {"result": "go", "reason": "ok"}, "signing": {"result": "go", "reason": "ok"}'
  fi
  [ "$4" = blocked ] && p11="d['probes']['P11'].update(group='environment', result='no-go', reason='no 3.14')"
  _fp_record "$E2E_REPO/$FP_REC" "
d['probes']['P3'].update(group='$group', result='not_run', evidence='evidence/P3-1', parts={$parts,
  'sandbox_push': {'result': 'go', 'reason': 'pushed'}, 'sandbox_draft_pr': {'result': 'go', 'reason': 'opened'}},
  github_writes=[
    {'repo': 'probe-fixture/sandbox', 'call': 'git push -q https://github.com/probe-fixture/sandbox.git HEAD:fp-x'},
    {'repo': 'probe-fixture/sandbox', 'call': 'gh pr create'},
    {'repo': 'someone/else', 'call': 'git push -q https://github.com/someone/else.git HEAD:fp-x'}])
del d['interpreter']
$p11
"
  if [ "$4" = raises ]; then
    printf '[includeIf "gitdir:**/p3/push-source/"]\n\tpath = %s\n' "$E2E_HOME/broken.inc" > "$E2E_HOME/.gitconfig"
    printf '[broken\n' > "$E2E_HOME/broken.inc"
  fi
  _fp_env_run -- --only P3
  rm -f "$E2E_HOME/.gitconfig"
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  e2e_expect_equal "not_run go go" "$(_fp_get "$E2E_REPO/$FP_REC" \
    '" ".join(d["probes"]["P3"][k] if k == "result" else d["probes"]["P3"]["parts"][k]["result"]
              for k in ("result", "sandbox_push", "sandbox_draft_pr"))')" "P3 result and its sandbox parts"
  local why=P11 want='environment_checks=ok' ev='' got
  [ "$4" = raises ] && why=scratch_repo_failed ev=evidence/P3-2
  [ "$3" = env ] && want='gh_auth_status=ok signing=ok'
  got=$(_fp_get "$E2E_REPO/$FP_REC" "' '.join(sorted(k + ('=ok' if v['result'] == 'not_run' and '$why' in v['reason']
    else '=' + v['result'] + ' ' + v['reason']) for k, v in d['probes']['P3']['parts'].items()
    if not k.startswith('sandbox_')))")
  e2e_expect_equal "$want" "$got" "the environment's parts, each not_run naming why"
  e2e_expect_equal "probe-fixture/sandbox git push|probe-fixture/sandbox gh pr|someone/else git push" \
    "$(_fp_get "$E2E_REPO/$FP_REC" '"|".join(w["repo"] + " " + " ".join(w["call"].split(" ")[:2])
                                       for w in d["probes"]["P3"]["github_writes"])')" "P3's kept sandbox writes"
  e2e_expect_equal "$ev ['evidence/P3-1']" "$(_fp_get "$E2E_REPO/$FP_REC" \
    '"%s %s" % (d["probes"]["P3"]["evidence"], d["probes"]["P3"].get("evidence_history"))')" \
    "P3's evidence and the earlier folder it still draws on"
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --dispositions \
    --writes-only-to "$FP_SANDBOX"
  e2e_expect_out "PROBES_CHECK_FAIL=write_outside_sandbox P3 someone/else"
  e2e_expect_no_out "parts_mismatch P3"
  _fp_env_after
}

_flow_test_begin "environment: P3 not run on a recorded P11 no-go keeps its sandbox parts and writes (E16)"
FP_D="P3 holds environment and sandbox parts; the record's P11 is no-go: the environment parts are not_run naming"
FP_D+=" P11, the sandbox parts and writes stay, and the earlier folder is listed"
_fp_p3_keep fp-env-p3-blocked-env "$FP_D" env blocked
FP_D="P3 holds the GitHub write group's parts and the placeholder; the record's P11 is no-go: the placeholder is"
FP_D+=" not_run naming P11, the sandbox parts and writes stay"
_fp_p3_keep fp-env-p3-blocked-gw "$FP_D" placeholder blocked

_flow_test_begin "environment: P3 that stops part way keeps its sandbox parts and writes (E16)"
FP_D="P3 holds environment and sandbox parts; the scratch repository's git config is unreadable, so P3 stops: the"
FP_D+=" environment parts are not_run naming the refusal, the sandbox parts and writes stay, and the evidence is"
FP_D+=" the new folder"
_fp_p3_keep fp-env-p3-raises-env "$FP_D" env raises
FP_D="P3 holds the GitHub write group's parts and the placeholder; P3 stops part way: the placeholder is not_run"
FP_D+=" naming the refusal, the sandbox parts and writes stay"
_fp_p3_keep fp-env-p3-raises-gw "$FP_D" placeholder raises

# _fp_sign_cond <name> <description> <includeIf condition> <expected signing
# result> — the global git config includes the signing file only under the
# condition, in which @MAIN@ stands for the main checkout's path and
# @ORIGIN@ for its origin's address; the signer needs the SSH agent. Workers
# commit in linked worktrees of the main checkout, where such a condition
# applies; a new scratch repository is outside it (E7).
_fp_sign_cond() {
  _fp_env_scenario "$1" "$2"
  cp "$FP_FIXTURES/bin/signer" "$E2E_BIN/"
  : > "$E2E_BIN/signer-needs-agent"
  local cond="${3//@MAIN@/$(cd "$E2E_REPO" && pwd -P)}"
  cond="${cond//@ORIGIN@/$(cd "$E2E_REPO" && command git remote get-url origin)}"
  printf '[includeIf "%s"]\n\tpath = %s\n' "$cond" "$E2E_HOME/signing.inc" > "$E2E_HOME/.gitconfig"
  printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' \
    "$E2E_BIN/signer" > "$E2E_HOME/signing.inc"
  printf 'includeIf condition: %s\n' "$cond" | _e2e_art
  _fp_no_local_signing
  _fp_env_run SSH_AUTH_SOCK="$E2E_DIR/agent.sock" -- --only P3
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  local want="SSH_AUTH_SOCK"
  [ "$4" = go ] && want="not set up"
  e2e_expect_equal "$4 yes" "$(_fp_get "$E2E_REPO/$FP_REC" \
    '(lambda s: "%s %s" % (s["result"], "yes" if "'"$want"'" in s["reason"] else s["reason"]))(
       d["probes"]["P3"]["parts"]["signing"])')" "the signing part and its reason"
  local on=true
  [ "$4" = go ] && on=false
  e2e_expect_equal "$on" "$(_fp_get "$E2E_REPO/.flow/factory/$(_fp_get "$E2E_REPO/$FP_REC" \
    'd["probes"]["P3"]["evidence"]')/facts.json" 'str(d["signing"]["commit_gpgsign"]).lower()')" \
    "commit.gpgsign as the worktree reads it, as a fact"
  e2e_expect_equal "1" "$(cd "$E2E_REPO" && command git worktree list | wc -l | tr -d ' ')" \
    "worktrees of the main checkout after the probe"
  _fp_env_after
}

_flow_test_begin "environment: signing turned on by an includeIf that holds in a worker's worktree is checked (E7)"
FP_D="the global git config includes the signing file under includeIf gitdir: the main checkout's path, which a"
FP_D+=" linked worktree of it matches: the signing part is no-go naming SSH_AUTH_SOCK"
_fp_sign_cond fp-env-sign-gitdir "$FP_D" "gitdir:@MAIN@/" no-go
FP_D="the global git config includes the signing file under includeIf hasconfig:remote.*.url: the main"
FP_D+=" checkout's origin: the signing part is no-go naming SSH_AUTH_SOCK"
_fp_sign_cond fp-env-sign-hasconfig "$FP_D" "hasconfig:remote.*.url:@ORIGIN@" no-go
FP_D="the includeIf gitdir: names another folder: signing is not set up for the main checkout's worktrees, so"
FP_D+=" the part is go"
_fp_sign_cond fp-env-sign-gitdir-other "$FP_D" "gitdir:@MAIN@-elsewhere/" go
_fp_sign_cond fp-env-sign-hasconfig-other "the includeIf hasconfig:remote.*.url: names another address: the part is go" \
  "hasconfig:remote.*.url:https://example.invalid/other.git" go

# Each part carries the keyed_on it was recorded under, so a part kept from
# an earlier run on other tools is stale although its entry was written
# again (R6). _fp_p3_stale <name> <description> <part or entry> — P3's
# sandbox parts recorded under gh 2.79.0, the stamp on each part or only on
# the entry; then an environment run on gh 2.80.0. The seeded record names no
# interpreter, so the run records its own without the terminal a replacement
# needs (person_channels L19).
_fp_p3_stale() {
  _fp_env_scenario "$1" "$2"
  local old='{"gh_version": "gh version 2.79.0 (2026-09-01)", "sandbox": "probe-fixture/sandbox"}' p='' e=''
  if [ "$3" = part ]; then p=", 'keyed_on': $old, 'ran_at': '2026-11-10T09:00:00Z'"
  else e=", keyed_on=$old, ran_at='2026-11-10T09:00:00Z'"; fi
  mkdir -p "$E2E_REPO/.flow/factory"
  _fp_record "$E2E_REPO/$FP_REC" "
d['groups']['github_write'] = {'keyed_on': $old, 'ran_at': '2026-11-10T09:00:00Z'}
d['probes']['P3'].update(group='github_write', result='go', parts={
  'sandbox_push': {'result': 'go', 'reason': 'pushed'$p}, 'sandbox_draft_pr': {'result': 'go', 'reason': 'opened'$p}}$e)
del d['interpreter']
"
  _fp_env_run -- --only P3
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  local sandbox="gh version 2.79.0 (2026-09-01)" said=stale
  if [ "$3" = entry ]; then sandbox=absent said=unstamped; fi
  e2e_expect_equal "$sandbox|gh version 2.80.0 (2026-10-01)" "$(_fp_get "$E2E_REPO/$FP_REC" \
    '"|".join(d["probes"]["P3"]["parts"][k].get("keyed_on", {}).get("gh_version", "absent")
      for k in ("sandbox_push", "gh_auth_status"))')" \
    "the gh version a sandbox part and an environment part were recorded under"
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
  e2e_expect_equal "1" "$E2E_RC" "--verify-record exit status"
  if [ "$said" = stale ]; then
    e2e_expect_line "PROBES_STALE=P3/sandbox_draft_pr gh_version"
    e2e_expect_line "PROBES_STALE=P3/sandbox_push gh_version"
  else
    e2e_expect_line "PROBES_UNSTAMPED=P3/sandbox_draft_pr"
    e2e_expect_line "PROBES_UNSTAMPED=P3/sandbox_push"
    e2e_expect_no_out "PROBES_STALE=P3/sandbox"
  fi
  e2e_expect_no_out "PROBES_STALE=P3/gh_auth_status"
  e2e_expect_no_out "PROBES_STALE=P3 "
  _fp_env_after
}

_flow_test_begin "probe record: P3's sandbox parts recorded under older tools are stale after an environment run, or unstamped (R6, R8)"
FP_D="the sandbox parts carry their own keyed_on with gh 2.79.0; probe --environment --only P3 runs on gh 2.80.0:"
FP_D+=" each sandbox part is stale, the environment parts and the entry are not"
_fp_p3_stale fp-stale-p3-part "$FP_D" part
FP_D="the sandbox parts carry no keyed_on of their own and the entry holds gh 2.79.0: the parts are kept"
FP_D+=" without one, never given the entry's, so each is listed as unstamped after the environment run (R8)"
_fp_p3_stale fp-stale-p3-entry "$FP_D" entry

# Only P13 runs in a launch context, so only P13's result depends on it
# (R7). _fp_lc_run <launchd or cron> — P13 in that context.
_fp_lc_run() {
  _e2e_exec env FLOW_FACTORY_LAUNCH_CONTEXT="$1" "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" \
    "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment --sandbox "$FP_SANDBOX" \
    --github-api "$(e2e_stub_url api)" --launch-context
  e2e_expect_equal "0" "$E2E_RC" "exit status of P13 in $1 ($E2E_OUT $E2E_ERR)"
}

_flow_test_begin "probe record: P13 in another launch context makes no other environment probe stale (R7)"
for FP_ORDER in "launchd cron" "cron launchd"; do
  FP_A=${FP_ORDER% *} FP_B=${FP_ORDER#* }
  FP_D="P13 under $FP_A, then P11, P3, P7 and P15, then P13 under $FP_B with the same tools: only P13's entry"
  FP_D+=" holds a launch context, it holds $FP_B, and nothing is stale"
  _fp_env_scenario "fp-stale-lc-$FP_A-$FP_B" "$FP_D"
  _fp_lc_run "$FP_A"
  _fp_env_run
  e2e_expect_equal "0" "$E2E_RC" "exit status of the environment run ($E2E_OUT $E2E_ERR)"
  _fp_lc_run "$FP_B"
  e2e_expect_equal "$FP_B" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P13"]["keyed_on"]["launch_context"]')" \
    "P13's launch context"
  e2e_expect_equal "P13" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(sorted(p for p, e in d["probes"].items()
    if any(k.startswith("launch_context") for k in e.get("keyed_on", {}))))')" "the entries holding a launch context"
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
  e2e_expect_no_out "PROBES_STALE"
  _fp_env_after
done

# A load or tick skips P13 only when P13's own keyed_on, and each of its
# parts', holds what this context would record (E11). _fp_lc_again <stale
# line --verify-record prints, or none> <claude -p starts after the second
# tick> — run after a launchd P13 and a change to the record: --verify-record
# first, then the second launchd tick, then --verify-record again.
_fp_lc_again() {
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
  if [ "$1" = none ]; then e2e_expect_no_out "PROBES_STALE"; else e2e_expect_line "$1"; fi
  _fp_lc_run launchd
  e2e_expect_equal "$2" "$(_fp_launches)" "claude -p starts after the second tick"
  if [ "$2" = 1 ]; then e2e_expect_out '"current": ["P13"]'; else e2e_expect_out '"current": []'; fi
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
  e2e_expect_no_out "PROBES_STALE"
  e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "yes" if all(isinstance(v.get("keyed_on"), dict)
    for v in [p] + list(p["parts"].values())) else p)(d["probes"]["P13"])')" "P13 and each of its parts carry a keyed_on"
  _fp_env_after
}

# _fp_record_edit <python statements on the record d> — change the record.
_fp_record_edit() {
  python3 - "$E2E_REPO/$FP_REC" "$1" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
exec(sys.argv[2])
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2)
PY
}

_flow_test_begin "environment: a launchd tick runs P13 again when P13's own keyed_on is stale (E11)"
FP_D="P13 under launchd on claude 2.1.322; claude becomes 2.1.330 and probe --environment --only P15 records the group"
FP_D+=" under it; P13 is stale, and the next tick runs it again although the group's keyed_on matches the tick"
_fp_env_scenario fp-env-lc-stale-entry "$FP_D"
_fp_lc_run launchd
printf '2.1.330 (Claude Code)\n' > "$E2E_BIN/claude-version"
_fp_env_run -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status of the environment run ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "2.1.330 (Claude Code)" "$(_fp_get "$E2E_REPO/$FP_REC" \
  'd["groups"]["environment"]["keyed_on"]["claude_version"]')" "the group's claude_version"
_fp_lc_again "PROBES_STALE=P13 claude_version" 2

_flow_test_begin "environment: a launchd tick runs P13 again when one of its parts is stale (E11)"
FP_D="P13 under launchd, then its claude_p part's keyed_on is set to claude 2.1.300 while the entry keeps 2.1.322:"
FP_D+=" the part is stale, and the next tick runs P13 again"
_fp_env_scenario fp-env-lc-stale-part "$FP_D"
_fp_lc_run launchd
_fp_record_edit 'd["probes"]["P13"]["parts"]["claude_p"]["keyed_on"]["claude_version"] = "2.1.300 (Claude Code)"'
_fp_lc_again "PROBES_STALE=P13/claude_p claude_version" 2

_flow_test_begin "environment: a launchd tick runs P13 again when P13 carries no keyed_on of its own (E11)"
FP_D="P13 under launchd, then its entry and parts lose their keyed_on and ran_at, as one written before they"
FP_D+=" existed: nothing shows it current, so the next tick runs it again and stamps it"
_fp_env_scenario fp-env-lc-unstamped "$FP_D"
_fp_lc_run launchd
_fp_record_edit '
for v in [d["probes"]["P13"]] + list(d["probes"]["P13"]["parts"].values()):
    v.pop("keyed_on", None)
    v.pop("ran_at", None)'
_fp_lc_again none 2

_flow_test_begin "environment: a launchd tick after an environment run on the same tools still finds P13 current (E11)"
FP_D="P13 under launchd, then probe --environment --only P15 on the same tools, which adds sandbox to the group:"
FP_D+=" the next tick lists P13 as current and spends nothing"
_fp_env_scenario fp-env-lc-same-tools "$FP_D"
_fp_lc_run launchd
_fp_env_run -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status of the environment run ($E2E_OUT $E2E_ERR)"
FP_SPENT=$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')
_fp_lc_again none 1
e2e_expect_equal "$FP_SPENT" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd after the tick"

# The interactive group, `probe --interactive`: P9 and P14, recorded from the
# person's session. A scenario plays the session: it runs the capture hook the
# probe's scratch plugin installs, with the hook input Claude Code would give
# it, and the steps the probe prints. P14's worker is the platform stand-in
# claude, which repeats its await call while the call prints WAITING.
#
# Ways it can be wrong, written down before the checks:
#   I1 the printing call writes a record, or puts its capture plugin anywhere
#      but the default worker area, or changes the plugin's own hooks
#   I2 PreToolUse input without permission_mode is go, or with nothing
#      captured P9 is anything but not_run
#   I3 a wake is go although the person prompted the session between the end
#      of the wait and the session's next step, or the wait did not run in the
#      background
#   I4 a run in one permission mode drops the other mode's parts
#   I5 P9 or P14 is go although tier-gate's mode handling, the executor and
#      the real await are built in phase 1, or a deferred part names no issue
#   I6 P14's cost per poll is not its dearest turn after the first, priced
#      from the turn's usage and projected to 30 minutes at one poll per 100 s,
#      so a run that would pass $1 per 30 minutes is go; or the first turn,
#      which writes the system prompt to the cache, is charged to every poll;
#      or the second turn, the last turn or the mean of the turns after the
#      first stands for a poll, so one dear poll among cheap ones is hidden;
#      or the part of the bill the turns' usage does not price is left out of
#      the poll's cost, so a run just over the limit is go
#   I7 P14 starts claude -p when its budget would pass the spend cap
#   I8 a worker that parks without an answer is go
#   I9 a session set up for one permission mode whose hooks report another is
#      go, so tier-gate could not tell the modes apart and P9 would not show
#      it; or a change of mode is reported as a change to the set-up mode
#   I10 P14 holds the factory lock for its whole run, so --step record from
#      the session fails with record_locked; or P14 writes back the record it
#      read before the run and loses what --step record wrote meanwhile; or
#      --step record run while P14's worker holds its question leaves P14 out
#      of its output without saying it is still running, or names an older
#      P14 entry as this run's; or a p14 step that ended without writing its
#      entry (killed, or failed after it started its worker) is named as
#      running forever and hides the older entry behind it
#   I11 the task notification Claude Code delivers when a background call
#      ends is counted as the person prompting, so a real wake is no-go; or a
#      person's prompt that mentions the tag anywhere but at its start is
#      taken for a notification; or the capture keeps the prompt's text
#   I12 a capture taken before the hook told notifications apart is go or
#      no-go, when the two cannot be told apart
#   I13 a turn Claude Code prints as several events (one per content block)
#      is priced once per event; cache writes are priced at the wrong
#      duration, or the 5-minute price is not used when the usage does not
#      split them
#   I14 the cost part is go when the model has no price, when no turn came
#      after the first, or when the priced turns do not explain the run's
#      total cost: more than 25% under it or more than 25% over it
#   I17 a P14 worker that exits before printing any event is no-go or keeps
#      its budget limit charged; or a scratch worktree whose git push gets no
#      answer leaves P14 no-go or charged
#   I18 a P9 part names no evidence folder, or one other than the session's
#      that recorded it: a part kept from an earlier session takes the folder
#      of the session that kept it
#   I21 --step p14 ignores --model, so the worker runs on claude-opus-5-5; or
#      the steps the setup prints leave out the model it was given
#   I22 --step record prints the P9 parts it worked out, not the ones the
#      record holds, so when the record refuses P9's entry and records it
#      not_run in its place, the printed line names parts the record has not

_fp_int() {   # probe --interactive [arguments], with the worker area in the scenario
  e2e_run_bin XDG_STATE_HOME="$E2E_DIR/state" bin/flow-factory.sh probe --interactive "$@"
}

# _fp_capture <plugin> <event> <hook input json> — run the plugin's hook for
# the event with that input, as Claude Code runs it.
_fp_capture() {
  (cd "$E2E_REPO" && python3 - "$1" "$2" "$3" <<'PY'
import json, subprocess, sys
root, event, data = sys.argv[1:4]
conf = json.load(open(root + "/hooks/hooks.json", encoding="utf-8"))
for entry in conf["hooks"].get(event, []):
    for h in entry["hooks"]:
        cmd = h["command"].replace("${CLAUDE_PLUGIN_ROOT}", root)
        r = subprocess.run(["bash", "-c", cmd], input=data, text=True, capture_output=True)
        sys.exit(r.returncode)
sys.exit(3)
PY
  ) || _flow_assert_fail "$E2E_NAME: the capture hook for $2 did not run"
}

# _fp_bash_input <mode or empty> <command> [true] — PreToolUse input for Bash.
_fp_bash_input() {
  python3 -c 'import json, sys
d = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[2]}}
if sys.argv[1]:
    d["permission_mode"] = sys.argv[1]
if len(sys.argv) > 3:
    d["tool_input"]["run_in_background"] = True
print(json.dumps(d))' "$@"
}

# _fp_session <mode as hook input gives it, or empty> [prompt] — play the
# session's P9 steps: the wait in the background, then (with a prompt, the
# person typing it after the wait ended) the --step woke call.
_fp_session() {
  local mode="$1" ff="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
  _fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input "$mode" "$ff probe --interactive --step wait --seconds 1" true)"
  _fp_int --step wait --seconds 1
  if [ -n "${2:-}" ]; then
    _fp_capture "$FP_COPY" UserPromptSubmit "$(python3 -c 'import json, sys
d = {"hook_event_name": "UserPromptSubmit", "prompt": sys.argv[2]}
if sys.argv[1]:
    d["permission_mode"] = sys.argv[1]
print(json.dumps(d))' "$mode" "$2")"
  fi
  _fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input "$mode" "$ff probe --interactive --step woke")"
  _fp_int --step woke
}

_flow_test_begin "interactive: the printing call sets up the capture plugin and records nothing (I1)"
_fp_runner_scenario fp-int-setup "probe --interactive --mode default prints the session's steps and a capture plugin under the worker area, and writes no record"
_fp_int --mode default
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_line "INTERACTIVE_RECORD=none"
e2e_expect_line "INTERACTIVE_MODE=default"
e2e_expect_out "INTERACTIVE_STEP=1 "
e2e_expect_out " --permission-mode default --model claude-opus-5-5"
e2e_expect_out "--step wait"
e2e_expect_out "--step woke"
e2e_expect_out "--step p14"
e2e_expect_out "--step record"
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
FP_HAS=no
case "$FP_COPY" in "$(cd "$E2E_DIR" && pwd -P)/state/flow-factory/probe/P9-"*) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the capture plugin is under XDG_STATE_HOME/flow-factory/probe ($FP_COPY)"
e2e_expect_equal "PreToolUse UserPromptSubmit" "$(_fp_get "$FP_COPY/hooks/hooks.json" '" ".join(sorted(d["hooks"]))')" "the capture plugin's hook events"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"

_flow_test_begin "interactive: P9 records the permission mode and a wake, in each mode, deferred to phase 1 (I4, I5, I18)"
_fp_runner_scenario fp-int-p9 "a default-mode session: its hook input carries permission_mode and the background wait wakes it with no prompt between, so both parts are go; P9 is deferred to 1b; a second session in auto mode adds its parts and keeps the default ones"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session default
_fp_int --step record
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "PROBE_INTERACTIVE="
e2e_expect_equal '{"background_wake_default": "go", "executor": "deferred", "hook_mode_default": "go", "tier_gate_by_mode": "deferred"}' "$(_fp_parts P9)" "every P9 part"
e2e_expect_equal "deferred synaptiai/synapti-marketplace#355" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["result"], d["probes"]["P9"].get("deferred_to"))')" "P9 result and deferred_to"
e2e_expect_equal "synaptiai/synapti-marketplace#355 synaptiai/synapti-marketplace#356" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["parts"]["tier_gate_by_mode"]["deferred_to"], d["probes"]["P9"]["parts"]["executor"]["deferred_to"])')" "each deferred part's issue"
e2e_expect_equal "interactive" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["group"]')" "P9 group"
e2e_expect_equal "default" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["interactive"]["keyed_on"]["permission_modes"]')" "keyed_on permission_modes"
e2e_expect_equal "evidence/P9-1 none" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["evidence"], d["probes"]["P9"].get("evidence_history", "none"))')" "P9 evidence and earlier folders after one session"
FP_PART_EV='" ".join("%s=%s" % (k, v.get("evidence")) for k, v in sorted(d["probes"]["P9"]["parts"].items()))'
e2e_expect_equal "background_wake_default=evidence/P9-1 executor=evidence/P9-1 hook_mode_default=evidence/P9-1 \
tier_gate_by_mode=evidence/P9-1" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_PART_EV")" "each part's folder after one session"
e2e_describe "the same steps in a session started in auto mode"
_fp_int --mode auto
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session auto
_fp_int --step record
e2e_expect_equal '{"background_wake_auto": "go", "background_wake_default": "go", "executor": "deferred", "hook_mode_auto": "go", "hook_mode_default": "go", "tier_gate_by_mode": "deferred"}' "$(_fp_parts P9)" "P9 parts after both modes"
e2e_expect_equal "auto,default" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["interactive"]["keyed_on"]["permission_modes"]')" "keyed_on permission_modes after both"
e2e_expect_equal "evidence/P9-2 ['evidence/P9-1']" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["evidence"], d["probes"]["P9"].get("evidence_history", "none"))')" "P9 evidence and earlier folders after the second session (its default parts came from the first)"
e2e_describe "recording the auto session again lists neither its own folder nor the first one twice"
_fp_int --step record
e2e_expect_equal "evidence/P9-2 ['evidence/P9-1']" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["evidence"], d["probes"]["P9"].get("evidence_history", "none"))')" "P9 evidence and earlier folders after recording the same session again"
e2e_expect_equal "background_wake_auto=evidence/P9-2 background_wake_default=evidence/P9-1 executor=evidence/P9-2 \
hook_mode_auto=evidence/P9-2 hook_mode_default=evidence/P9-1 tier_gate_by_mode=evidence/P9-2" \
  "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_PART_EV")" "each part's folder: the default parts keep the first session's"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC" --dispositions
e2e_expect_no_out "deferred_without_phase P9"
e2e_expect_no_out "parts_mismatch"

_flow_test_begin "interactive: hook input without permission_mode is no-go with the terminal fallback (I2)"
_fp_runner_scenario fp-int-p9-nomode "the session's PreToolUse input has no permission_mode: that part is no-go and P9 names the deny-everywhere fallback"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session ""
_fp_int --step record
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["parts"]["hook_mode_default"]["result"]')" "hook mode part"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["result"]')" "P9 result"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "tier-gate denies the always-ask subcommands in every session" in d["probes"]["P9"].get("fallback", "") else d["probes"]["P9"]')" "P9 fallback"

_flow_test_begin "interactive: a session set up for auto whose hooks report default is not go (I9)"
_fp_runner_scenario fp-int-p9-wrongmode "the session was set up with --mode auto, but every PreToolUse hook input gives permission_mode default: the auto hook-mode part is not_run, names both modes, and P9 is not go"
_fp_int --mode auto
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session default
_fp_int --step record
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["parts"]["hook_mode_auto"]["result"]')" "hook mode part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "auto" in d["probes"]["P9"]["parts"]["hook_mode_auto"]["reason"] and "default" in d["probes"]["P9"]["parts"]["hook_mode_auto"]["reason"] else d["probes"]["P9"]["parts"]["hook_mode_auto"]["reason"]')" "the reason names both modes"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["result"]')" "P9 result"

# As the session recorded on 2026-11-13 did: set up for default, its wait's
# hook input gave default, and from the task notification's turn on every
# input gave auto. Neither default part was observed throughout.
_flow_test_begin "interactive: a session whose mode changes between the wait and --step woke is not go for its mode (I9)"
_fp_runner_scenario fp-int-p9-mixed "the session was set up for default and its background wait's hook input gives default, but the task notification's turn and the --step woke call give auto: both default parts are not_run, each names both modes and the notification's turn, and P9 is not go"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
FP_FF="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
_fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input default "$FP_FF probe --interactive --step wait --seconds 1" true)"
_fp_int --step wait --seconds 1
_fp_capture "$FP_COPY" UserPromptSubmit '{"hook_event_name": "UserPromptSubmit", "permission_mode": "auto", "prompt": "<task-notification><task-id>bk3</task-id><status>completed</status></task-notification>"}'
_fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input auto "$FP_FF probe --interactive --step woke")"
_fp_int --step woke
_fp_int --step record
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["parts"]["hook_mode_default"]["result"], d["probes"]["P9"]["parts"]["background_wake_default"]["result"])')" "hook mode and wake parts"
e2e_expect_equal "yes yes" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join("yes" if all(w in d["probes"]["P9"]["parts"][k]["reason"] for w in ("auto", "default", "notification")) else d["probes"]["P9"]["parts"][k]["reason"] for k in ("hook_mode_default", "background_wake_default"))')" "each reason names both modes and the notification's turn"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["result"]')" "P9 result"

# _fp_p9_turn <name> <description> <wait's mode> <later mode> — a session set
# up for default whose wait call gives one mode and whose notification turn
# and --step woke give the other: the reason names the mode reported first,
# where it was last reported, and the mode after it (I9).
_fp_p9_turn() {
  _fp_runner_scenario "$1" "$2"
  _fp_int --mode default
  FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
  local ff="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
  _fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input "$3" "$ff probe --interactive --step wait --seconds 1" true)"
  _fp_int --step wait --seconds 1
  _fp_capture "$FP_COPY" UserPromptSubmit '{"hook_event_name": "UserPromptSubmit", "permission_mode": "'"$4"'",
    "prompt": "<task-notification><task-id>bk3</task-id></task-notification>"}'
  _fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input "$4" "$ff probe --interactive --step woke")"
  _fp_int --step woke
  _fp_int --step record
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  local said="the session was set up for default, but reported permission_mode $3 up to the background wait's"
  said+=" Bash call, then $4 from the turn the background-task notification started on"
  e2e_expect_equal "$said; default-mode hook input not observed throughout" \
    "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["parts"]["hook_mode_default"]["reason"]')" \
    "the hook mode part's reason"
  e2e_expect_equal "$said; default-mode wake not observed" \
    "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["parts"]["background_wake_default"]["reason"]')" \
    "the wake part's reason"
}

_flow_test_begin "interactive: a mode change names the mode reported before it and the one after (I9)"
FP_D="set up for default; the wait gives default, the notification's turn and --step woke give auto: the reason"
FP_D+=" says default up to the wait, then auto"
_fp_p9_turn fp-int-p9-turn-auto "$FP_D" default auto
FP_D="set up for default; the wait gives auto, the notification's turn and --step woke give default: the reason"
FP_D+=" says auto up to the wait, then default, not that the session changed to auto"
_fp_p9_turn fp-int-p9-turn-default "$FP_D" auto default

# Each of P9's parts carries the claude it was recorded under, so the parts
# one mode's session recorded are stale once the other mode's session ran on
# a newer claude (R6).
_flow_test_begin "probe record: a P9 part recorded under an older claude is stale after the other mode's session (R6)"
FP_D="a default-mode session on claude 2.1.322, then an auto-mode session on 2.1.330: the default parts keep"
FP_D+=" 2.1.322 and are stale, the auto parts and the entry are not"
_fp_runner_scenario fp-stale-p9 "$FP_D"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session default
_fp_int --step record
printf '2.1.330 (Claude Code)\n' > "$E2E_BIN/claude-version"
_fp_int --mode auto
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session auto
_fp_int --step record
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "2.1.322 (Claude Code)|2.1.330 (Claude Code)" "$(_fp_get "$E2E_REPO/$FP_REC" \
  '"|".join(d["probes"]["P9"]["parts"][k]["keyed_on"]["claude_version"]
            for k in ("hook_mode_default", "hook_mode_auto"))')" \
  "the claude each mode's part was recorded under"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
e2e_expect_line "PROBES_STALE=P9/background_wake_default claude_version"
e2e_expect_line "PROBES_STALE=P9/hook_mode_default claude_version"
e2e_expect_no_out "PROBES_STALE=P9/hook_mode_auto"
e2e_expect_no_out "PROBES_STALE=P9 "

_flow_test_begin "probe record: P9 parts kept from before parts carried keyed_on are listed as unstamped, never given the entry's keyed_on (R8)"
# _fp_p9_legacy <name> <description> <entry keyed_on, as Python, or None> —
# P9 recorded with default-mode parts that carry no keyed_on of their own,
# then an auto session on claude 2.1.322.
_fp_p9_legacy() {
  _fp_runner_scenario "$1" "$2"
  mkdir -p "$E2E_REPO/.flow/factory"
  _fp_record "$E2E_REPO/$FP_REC" "
d['groups']['interactive'] = {'keyed_on': {'claude_version': '2.1.300 (Claude Code)'}, 'ran_at': '2026-11-10T09:00:00Z'}
d['probes']['P9'].update(group='interactive', parts={'hook_mode_default': {'result': 'go', 'reason': 'seen'},
  'background_wake_default': {'result': 'go', 'reason': 'woke'}})
k = $3
if k: d['probes']['P9'].update(keyed_on=k, ran_at='2026-11-10T09:00:00Z')
"
  _fp_int --mode auto
  FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
  _fp_session auto
  _fp_int --step record
  e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
  e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_REPO/$FP_REC"
}

FP_D="the default parts carry no keyed_on and the entry was recorded under claude 2.1.300; an auto session on"
FP_D+=" 2.1.322: the default parts are kept without a keyed_on, never given the entry's, and are listed as"
FP_D+=" unstamped, so the record fails until a default session is recorded again"
_fp_p9_legacy fp-stale-p9-legacy "$FP_D" "{'claude_version': '2.1.300 (Claude Code)'}"
e2e_expect_equal "absent absent 2.1.322 (Claude Code)" "$(_fp_get "$E2E_REPO/$FP_REC" \
  '"%s %s %s" % (d["probes"]["P9"]["parts"]["hook_mode_default"].get("keyed_on", "absent"),
                 d["probes"]["P9"]["parts"]["hook_mode_default"].get("ran_at", "absent"),
                 d["probes"]["P9"]["parts"]["hook_mode_auto"]["keyed_on"]["claude_version"])')" \
  "the default part's keyed_on and ran_at, and the auto part's claude_version"
e2e_expect_line "PROBES_UNSTAMPED=P9/background_wake_default"
e2e_expect_line "PROBES_UNSTAMPED=P9/hook_mode_default"
e2e_expect_no_out "PROBES_STALE=P9/hook_mode_default"
e2e_expect_no_out "PROBES_STALE=P9/hook_mode_auto"
e2e_expect_equal "1" "$E2E_RC" "--verify-record exit status"
FP_D="neither the default parts nor the entry carry keyed_on: the parts are kept without one, so they are"
FP_D+=" listed as unstamped rather than compared; the auto parts are stamped"
_fp_p9_legacy fp-stale-p9-unkeyed "$FP_D" None
e2e_expect_equal "absent 2.1.322 (Claude Code)" "$(_fp_get "$E2E_REPO/$FP_REC" \
  '"%s %s" % (d["probes"]["P9"]["parts"]["hook_mode_default"].get("keyed_on", "absent"),
              d["probes"]["P9"]["parts"]["hook_mode_auto"]["keyed_on"]["claude_version"])')" \
  "the default part's and the auto part's keyed_on"
e2e_expect_no_out "PROBES_STALE=P9"
e2e_expect_line "PROBES_UNSTAMPED=P9/background_wake_default"
e2e_expect_line "PROBES_UNSTAMPED=P9/hook_mode_default"
e2e_expect_no_out "PROBES_UNSTAMPED=P9/hook_mode_auto"
e2e_expect_no_line "PROBES_UNSTAMPED=P9"
e2e_expect_equal "1" "$E2E_RC" "--verify-record exit status"

_flow_test_begin "interactive: --step record prints the parts the record holds when the record refuses P9's entry (I22)"
_fp_runner_scenario fp-int-p9-refused "a copy of the plugin whose record schema takes part reasons of at most 10 \
characters, so the record refuses P9's entry and records it not_run with no parts in its place: the \
PROBE_INTERACTIVE line --step record prints names no parts, as the record holds none"
FP_SCHEMA=$(python3 - "$REPO_ROOT/plugins/flow/schemas/v1/factory-probes.schema.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
s["$defs"]["part"]["properties"]["reason"]["maxLength"] = 10
print(json.dumps(s, indent=1))
PY
)
e2e_plugin_copy schemas/v1/factory-probes.schema.json "$FP_SCHEMA"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session default
_fp_int --step record
# Every part's reason is over the limit, and which one the refusal names
# changes from run to run: the artifact names none of them.
fe_mask_output 'P9/parts/[a-z_]+/reason: .* is too long' 'P9/parts/<part>/reason: <reason> is too long'
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_err "PROBE_ENTRY_REFUSED=P9"
e2e_expect_equal "not_run none" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["result"],
  d["probes"]["P9"].get("parts", "none"))')" "P9's result and parts in the record"
e2e_expect_equal "{}" "$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PROBE_INTERACTIVE=//p' \
  | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["parts"]))')" \
  "the parts the PROBE_INTERACTIVE line names"

_flow_test_begin "interactive: a prompt between the wait's end and the next step is not a wake (I3)"
_fp_runner_scenario fp-int-p9-prompt "the person types a prompt after the wait ended and before the session's --step woke: the wake part is no-go with the /loop fallback"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session default "did the <task-notification> arrive?"
_fp_int --step record
e2e_expect_equal "go no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["parts"]["hook_mode_default"]["result"], d["probes"]["P9"]["parts"]["background_wake_default"]["result"])')" "hook mode and wake parts"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "/loop prompt" in d["probes"]["P9"].get("fallback", "") else d["probes"]["P9"]')" "P9 fallback"

_flow_test_begin "interactive: the task notification that ends a background call is not the person prompting (I3, I11)"
_fp_runner_scenario fp-int-p9-notification "between the wait's end and --step woke the only prompt is Claude Code's task notification for the background wait, after a newline: the wake part is go, and the capture holds whether a prompt was a notification but not its text"
_fp_int --mode auto
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
_fp_session auto "
<task-notification><task-id>bk7f2</task-id><status>completed</status><summary>wait exited 0</summary></task-notification>"
_fp_int --step record
e2e_expect_equal "go go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["parts"]["hook_mode_auto"]["result"], d["probes"]["P9"]["parts"]["background_wake_auto"]["result"])')" "hook mode and wake parts"
FP_HOOKS="$E2E_REPO/.flow/factory/evidence/P9-1/hooks.jsonl"
e2e_expect_equal "[true]" "$(python3 -c 'import json, sys
print(json.dumps([d["task_notification"] for d in map(json.loads, open(sys.argv[1], encoding="utf-8")) if d["event"] == "UserPromptSubmit"]))' "$FP_HOOKS")" "the captured prompt's task_notification"
e2e_expect_equal "" "$(grep -E 'task-id|bk7f2|"prompt"' "$FP_HOOKS")" "prompt text or a prompt key in the capture"

_flow_test_begin "interactive: a capture that does not tell notifications apart leaves the wake not run (I12)"
_fp_runner_scenario fp-int-p9-oldcapture "the capture's prompt between the wait's end and --step woke has no task_notification field, as an older capture hook wrote it: the wake part is not_run, never go or no-go"
_fp_int --mode auto
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
FP_FF="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
_fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input auto "$FP_FF probe --interactive --step wait --seconds 1" true)"
_fp_int --step wait --seconds 1
python3 -c 'import json, sys, time
print(json.dumps({"event": "UserPromptSubmit", "permission_mode": "auto", "tool": None, "command": None,
                  "run_in_background": False, "at": time.time()}))' >> "$E2E_REPO/.flow/factory/evidence/P9-1/hooks.jsonl"
_fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input auto "$FP_FF probe --interactive --step woke")"
_fp_int --step woke
_fp_int --step record
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["parts"]["background_wake_auto"]["result"]')" "wake part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "notification" in d["probes"]["P9"]["parts"]["background_wake_auto"]["reason"] else d["probes"]["P9"]["parts"]["background_wake_auto"]["reason"]')" "the reason says notifications cannot be told apart"

_flow_test_begin "interactive: a wait not run in the background cannot show a wake (I3)"
_fp_runner_scenario fp-int-p9-foreground "the wait runs as an ordinary Bash call: the wake part is not_run"
_fp_int --mode default
FP_COPY=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^INTERACTIVE_PLUGIN=//p')
FP_FF="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"
_fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input default "$FP_FF probe --interactive --step wait --seconds 1")"
_fp_int --step wait --seconds 1
_fp_capture "$FP_COPY" PreToolUse "$(_fp_bash_input default "$FP_FF probe --interactive --step woke")"
_fp_int --step woke
_fp_int --step record
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P9"]["parts"]["background_wake_default"]["result"]')" "wake part"

_flow_test_begin "interactive: with nothing captured P9 is not run (I2)"
_fp_runner_scenario fp-int-p9-none "the session never loaded the capture plugin: both parts are not_run and so is P9"
_fp_int --mode default
_fp_int --step record
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s" % (d["probes"]["P9"]["parts"]["hook_mode_default"]["result"], d["probes"]["P9"]["parts"]["background_wake_default"]["result"], d["probes"]["P9"]["result"])')" "hook mode part, wake part and P9"

# --step p14 alone writes interactive.json holding only its own worker, with
# no session mode or evidence directory to record into.
_flow_test_begin "interactive: wait, woke and record with no session set up are refused (I2)"
_fp_runner_scenario fp-int-nosetup "interactive.json names only a p14 worker, as --step p14 run before any setup leaves it: --step wait, woke and record each exit 5 with FACTORY_REFUSED=no_interactive_session and write no record"
mkdir -p "$E2E_REPO/.flow/factory"
printf '{"p14": "evidence/P14-1", "p14_pid": 1}\n' > "$E2E_REPO/.flow/factory/interactive.json"
for FP_STEP in wait woke record; do
  _fp_int --step "$FP_STEP" --seconds 1
  e2e_expect_equal "5" "$E2E_RC" "exit status of --step $FP_STEP ($E2E_ERR)"
  e2e_expect_out "FACTORY_REFUSED=no_interactive_session"
done
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"

# _fp_p14_scenario <name> <description> <cost per turn> — a platform scenario
# whose worker repeats its await call while it prints WAITING.
_fp_p14_scenario() {
  _fp_platform_scenario "$1" "$2"
  printf 'WAITING\n' > "$E2E_BIN/claude-repeat-while"
  printf '%s\n' "$3" > "$E2E_BIN/claude-cost-per-turn"
}

# _fp_answer_later <seconds> [record] — in the background, play the session:
# once the worker's question is held, (with record, run --step record while
# it is held,) wait, then answer it.
_fp_answer_later() {
  local hold="$E2E_REPO/.flow/factory/evidence/P14-1/hold.json" i=0 record="${2:-}"
  (
    while [ ! -f "$hold" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
    cd "$E2E_REPO" || exit 1
    if [ -n "$record" ]; then
      env HOME="$E2E_HOME" PATH="$E2E_BIN:$PATH" XDG_STATE_HOME="$E2E_DIR/state" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --interactive --step record > "$E2E_DIR/record.out" 2>&1
    fi
    sleep "$1"
    env HOME="$E2E_HOME" PATH="$E2E_BIN:$PATH" XDG_STATE_HOME="$E2E_DIR/state" \
      "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --interactive --step answer --text yes > "$E2E_DIR/answer.out" 2>&1
  ) &
  FP_ANSWERER=$!
}

# _fp_answer_after_polls <polls> — in the background, answer once the worker
# has made that many await calls, so the number of turns does not depend on
# how fast each turn runs on a loaded machine.
_fp_answer_after_polls() {
  local polls="$E2E_REPO/.flow/factory/evidence/P14-1/polls.jsonl" i=0
  (
    while { [ ! -f "$polls" ] || [ "$(wc -l < "$polls")" -lt "$1" ]; } && [ "$i" -lt 1200 ]; do
      sleep 0.1; i=$((i + 1))
    done
    cd "$E2E_REPO" || exit 1
    env HOME="$E2E_HOME" PATH="$E2E_BIN:$PATH" XDG_STATE_HOME="$E2E_DIR/state" \
      "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --interactive --step answer --text yes > "$E2E_DIR/answer.out" 2>&1
  ) &
  FP_ANSWERER=$!
}

# Usage of the real worker's two turns, Claude Code 2.1.322 under Opus 5.5:
# the first writes the system prompt to the cache, the second is one poll.
# Each line is <cost charged>\t<message usage>; the costs add up to that
# run's total_cost_usd, which priced the output tokens the result event
# counts rather than the fewer the assistant events show.
FP_U1='{"input_tokens": 2, "cache_creation_input_tokens": 9619, "cache_read_input_tokens": 11382, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 9619}, "output_tokens": 16}'
FP_U2='{"input_tokens": 2, "cache_creation_input_tokens": 245, "cache_read_input_tokens": 21001, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 245}, "output_tokens": 4}'
FP_TAB=$(printf '\t')

# _fp_p14_priced <name> <description> <model> <line>... — a P14 scenario
# whose stand-in reports the model and gives its nth message the nth line's
# cost and usage, and replies continued after its last call.
_fp_p14_priced() {
  _fp_p14_scenario "$1" "$2" 0.01
  printf '%s\n' "$3" > "$E2E_BIN/claude-model"
  printf 'continued\n' > "$E2E_BIN/claude-final-text"
  shift 3
  printf '%s\n' "$@" > "$E2E_BIN/claude-turn-usage"
}

_fp_facts() {   # <expression over d> — of P14's facts.json
  _fp_get "$E2E_REPO/.flow/factory/evidence/P14-1/facts.json" "$1"
}

_fp_polls() {   # what each await call printed, in order
  python3 -c 'import json, sys
print(" ".join(json.loads(l)["printed"] for l in open(sys.argv[1], encoding="utf-8")))' "$E2E_REPO/.flow/factory/evidence/P14-1/polls.jsonl" 2>/dev/null
}

_flow_test_begin "interactive: P14's stand-in worker continues after the answer within \$1 per 30 minutes, deferred to 1c (I5, I6, I10)"
_fp_p14_priced fp-int-p14 "the worker holds its question and polls every 3 s; while it is held the session runs --step record, which gets the lock at once and names P14 as still running; the session answers 4 s after that; each poll after the first turn prices at \$0.006248, \$0.11 per 30 minutes at one poll per 100 s: every checked part is go, P14 is deferred to the real await, the P9 entry --step record wrote is kept, and a later --step record names P14's result" claude-opus-5-5 "0.0795564$FP_TAB$FP_U1" "0.0062482$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 4 record
_fp_int --step p14 --poll-seconds 3 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "yes" "$(grep -q '^PROBE_INTERACTIVE=' "$E2E_DIR/record.out" && echo yes || echo no)" "--step record ran while P14 held its question ($(cat "$E2E_DIR/record.out"))"
e2e_expect_equal '["P14"] no' "$(sed -n 's/^PROBE_INTERACTIVE=//p' "$E2E_DIR/record.out" | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get("running")), "yes" if "P14" in d["probes"] else "no")')" "--step record during the hold: P14 running, and no P14 result"
e2e_expect_equal "not_run default" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["result"], d["groups"]["interactive"]["keyed_on"].get("permission_modes"))')" "the P9 entry and permission_modes --step record wrote, after P14"
fe_mask_back "$(sed -n 's/^ANSWER_RECORDED question=\([0-9a-f][0-9a-f]*\).*/\1/p' "$E2E_DIR/answer.out")" '<question id>'
e2e_expect_equal "yes" "$(grep -q '^ANSWER_RECORDED' "$E2E_DIR/answer.out" && echo yes || echo no)" "the session's answer was taken ($(cat "$E2E_DIR/answer.out"))"
e2e_expect_equal '{"continues_after_answer": "go", "cost_per_30_minutes": "go", "polls_within_limit": "go", "real_await": "deferred"}' "$(_fp_parts P14)" "every P14 part"
e2e_expect_equal "deferred synaptiai/synapti-marketplace#356 true" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s" % (d["probes"]["P14"]["result"], d["probes"]["P14"].get("deferred_to"), str(d["probes"]["P14"]["stand_in"]).lower())')" "P14 result, deferred_to and stand_in"
FP_POLLS=$(_fp_polls)
FP_HAS=no
case "$FP_POLLS" in WAITING*ANSWERED) FP_HAS=yes ;; esac
e2e_expect_equal "yes" "$FP_HAS" "the polls: WAITING first, ANSWERED last ($FP_POLLS)"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts (no relaunch)"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if d["spend"]["spent_usd"] > 0 and d["probes"]["P14"]["cost_usd"] == d["spend"]["spent_usd"] else d["spend"]')" "the run's cost is charged to P14 and the spend"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "per poll" in d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["reason"] else d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["reason"]')" "the cost part gives the cost per poll"
e2e_expect_equal "0.006248 0.112468" "$(_fp_facts '"%s %s" % (d["pricing"]["per_poll_usd"], d["pricing"]["per_30_minutes_usd"])')" "the priced cost per poll and per 30 minutes"
_fp_int --step record
e2e_expect_equal '[] deferred evidence/P14-1' "$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PROBE_INTERACTIVE=//p' | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get("running")), d["probes"].get("P14"), d["evidence"].get("P14"))')" "--step record after P14 ended: nothing running, and P14's result"
e2e_expect_equal "not_run deferred" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P9"]["result"], d["probes"]["P14"]["result"])')" "the record holds both P9 and P14"

_flow_test_begin "interactive: P14 priced from the real worker's turns: the first turn's cache write is not a poll's cost (I6, I13)"
_fp_p14_priced fp-int-p14-real "the real numbers: Opus 5.5, one poll answered at once and a closing reply, \$0.089585 for the run, each message printed as two events; the first turn writes 9619 tokens to the 1-hour cache, the second reads 21001 and prices at \$0.006248; the \$0.00378 of the bill the usage does not price (output the assistant events under-report) is added to the one poll after the first turn: the poll costs \$0.010028, \$0.181 per 30 minutes, and the cost part is go" claude-opus-5-5 "0.0795564$FP_TAB$FP_U1" "0.0100282$FP_TAB$FP_U2"
: > "$E2E_BIN/claude-split-turns"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "ANSWERED" "$(_fp_polls)" "the polls"
e2e_expect_equal "go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]')" "cost part ($(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["reason"]'))"
e2e_expect_equal "claude-opus-5-5 [0.079556, 0.006248] 0.085805 0.089585 0.006248 0.00378 0.010028 0.180508" "$(_fp_facts '"%s %s %s %s %s %s %s %s" % (d["pricing"]["model"], json.dumps(d["pricing"]["turn_costs_usd"]), d["pricing"]["priced_usd"], d["pricing"]["total_cost_usd"], d["pricing"]["dearest_turn_usd"], d["pricing"]["unpriced_usd"], d["pricing"]["per_poll_usd"], d["pricing"]["per_30_minutes_usd"])')" "the pricing facts: per turn, their sum, the run's total, the dearest turn after the first, the bill the turns do not price, per poll and per 30 minutes"
e2e_expect_equal "deferred true" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P14"]["result"], str(d["probes"]["P14"]["stand_in"]).lower())')" "P14 result and stand_in"

_flow_test_begin "interactive: cache writes the usage does not split are priced as 5-minute writes (I13)"
_fp_p14_priced fp-int-p14-5m "Sonnet 5.5, and usage with no cache_creation split: the poll's 1000 written tokens price at \$2.50 per million, so the poll costs \$0.004604" claude-sonnet-5-5 "0.021404$FP_TAB{\"input_tokens\": 2, \"cache_creation_input_tokens\": 8000, \"cache_read_input_tokens\": 12000, \"output_tokens\": 20}" "0.004604$FP_TAB{\"input_tokens\": 2, \"cache_creation_input_tokens\": 1000, \"cache_read_input_tokens\": 20000, \"output_tokens\": 10}"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "[0.021404, 0.004604] go" "$(_fp_facts 'json.dumps(d["pricing"]["turn_costs_usd"])') $(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]')" "the turns' prices and the cost part"

_flow_test_begin "interactive: P14 cannot be priced: an unknown model, a bill the turns do not explain, or no turn after the first (I14)"
_fp_p14_priced fp-int-p14-unpriced "the run reports a model with no price row: the cost part is not_run and names the model, and P14 is not_run" claude-unknown-1-0 "0.0795564$FP_TAB$FP_U1" "0.0100282$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "not_run not_run" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"], d["probes"]["P14"]["result"])')" "cost part and P14"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "claude-unknown-1-0" in d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["reason"] else d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["reason"]')" "the reason names the model"
_fp_p14_priced fp-int-p14-unexplained "each turn is charged twice what its usage prices at, so the priced turns are half the run's total: the cost part is not_run, and facts keep both sums" claude-opus-5-5 "0.1591128$FP_TAB$FP_U1" "0.0124964$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "not_run" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]')" "cost part"
e2e_expect_equal "0.085805 0.171609" "$(_fp_facts '"%s %s" % (d["pricing"]["priced_usd"], d["pricing"]["total_cost_usd"])')" "the priced sum and the run's total"
_fp_p14_priced fp-int-p14-over "each turn is charged 0.7 times what its usage prices at, so the priced turns are 43% over the run's total: the cost part is not_run" claude-opus-5-5 "0.0556895$FP_TAB$FP_U1" "0.0043737$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "not_run 0.085805 0.060063" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]') $(_fp_facts '"%s %s" % (d["pricing"]["priced_usd"], d["pricing"]["total_cost_usd"])')" "cost part, the priced sum and the run's total"
_fp_p14_priced fp-int-p14-under30 "each turn is charged its price over 0.7, so the priced turns are 30% under the run's total: the cost part is not_run" claude-opus-5-5 "0.113652$FP_TAB$FP_U1" "0.008926$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "not_run 0.085805 0.122578" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]') $(_fp_facts '"%s %s" % (d["pricing"]["priced_usd"], d["pricing"]["total_cost_usd"])')" "cost part, the priced sum and the run's total"
_fp_p14_priced fp-int-p14-oneturn "the worker's only turn is the poll that got the answer, with no reply after it: there is no turn after the first to price, so the cost part is not_run" claude-opus-5-5 "0.0795564$FP_TAB$FP_U1"
rm -f "$E2E_BIN/claude-final-text"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "ANSWERED not_run not_run" "$(_fp_polls) $(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"], d["probes"]["P14"]["result"])')" "the polls, the cost part and P14"

_flow_test_begin "interactive: priced turns within 25% of the run's total either way are used (I14)"
_fp_p14_priced fp-int-p14-under20 "each turn is charged its price over 0.8, so the priced turns are 20% under the run's total: the cost part is go, and the \$0.021451 the turns do not price is added to the one poll, \$0.027699 a poll" claude-opus-5-5 "0.0994455$FP_TAB$FP_U1" "0.0078103$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "go 0.021451 0.027699 0.498589" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]') $(_fp_facts '"%s %s %s" % (d["pricing"]["unpriced_usd"], d["pricing"]["per_poll_usd"], d["pricing"]["per_30_minutes_usd"])')" "cost part, the bill the turns do not price, per poll and per 30 minutes"
_fp_p14_priced fp-int-p14-over20 "each turn is charged its price over 1.2, so the priced turns are 20% over the run's total: the cost part is go, and the poll costs its own price, \$0.006248" claude-opus-5-5 "0.066297$FP_TAB$FP_U1" "0.0052068$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_later 1
_fp_int --step p14 --poll-seconds 20 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "go 0 0.006248" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"]') $(_fp_facts '"%s %s" % (d["pricing"]["unpriced_usd"], d["pricing"]["per_poll_usd"])')" "cost part, the bill the turns do not price and per poll"

_flow_test_begin "interactive: --step record tells this p14 step's entry from an older one, and a refused p14 step is not running (I10)"
_fp_p14_scenario fp-int-record-running "the record holds a P14 entry from evidence/P14-1 while the session's p14 step, a live process, runs as evidence/P14-2: record names P14 as running and gives no result; then a p14 step refused for budget leaves nothing running, and record names its not_run" 0.01
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P14"].update(group="interactive", result="no-go", evidence="evidence/P14-1", fallback="holding off")'
_fp_int --step setup --mode default
_fp_p14_marker() {   # <evidence dir> <pid> — the session's p14 step, as p14_launch writes it
  python3 -c 'import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); d.update(p14=sys.argv[2], p14_pid=int(sys.argv[3]))
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"))' "$E2E_REPO/.flow/factory/interactive.json" "$1" "$2"
}
_fp_p14_marker evidence/P14-2 $$
_fp_int --step record
e2e_expect_equal '["P14"] no' "$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PROBE_INTERACTIVE=//p' | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get("running")), "yes" if "P14" in d["probes"] else "no")')" "record while P14-2 runs: running, and no P14 result"
_fp_record "$E2E_REPO/$FP_REC" 'd.update(json.load(open("'"$E2E_REPO/$FP_REC"'"))); d["spend"]["spent_usd"] = 24.5'
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4
e2e_expect_equal "0 0" "$E2E_RC $(_fp_launches)" "exit status of the refused p14 step and claude -p starts"
_fp_int --step record
e2e_expect_equal '[] not_run' "$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PROBE_INTERACTIVE=//p' | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get("running")), d["probes"].get("P14"))')" "record after the refused p14 step: nothing running, and P14's not_run"

_flow_test_begin "interactive: --step record names a p14 step that ended without its entry as not_run, not running (I10)"
_fp_p14_scenario fp-int-record-dead "the record holds a no-go P14 entry from evidence/P14-1 and spent \$4.50, of which \$1 is the budget limit the p14 step running as evidence/P14-2 charged; that step's process has ended without writing its entry: record names nothing running, writes P14 not_run for evidence/P14-2 with the reason, keeps the \$1 charged since the run's cost is unknown, and forgets the step, so a second record gives the same and wait-question waits on nothing" 0.01
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["probes"]["P14"].update(group="interactive", result="no-go", evidence="evidence/P14-1", fallback="holding off"); d["spend"]["spent_usd"] = 4.5'
_fp_int --step setup --mode default
( exit 0 ) &
FP_DEAD=$!
wait "$FP_DEAD"
_fp_p14_marker evidence/P14-2 "$FP_DEAD"
_fp_int --step record
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '[] not_run evidence/P14-2' "$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PROBE_INTERACTIVE=//p' | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get("running")), d["probes"].get("P14"), d["evidence"].get("P14"))')" "record after the p14 step died: nothing running, and P14 not_run for the dead step"
e2e_expect_equal "not_run evidence/P14-2 yes 4.5" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s %s %s" % (d["probes"]["P14"]["result"], d["probes"]["P14"]["evidence"], "yes" if "ended without writing its entry" in d["probes"]["P14"]["reason"] else d["probes"]["P14"]["reason"], d["spend"]["spent_usd"])')" "the recorded P14 entry, its reason, and the spend kept"
e2e_expect_equal "none none" "$(_fp_get "$E2E_REPO/.flow/factory/interactive.json" '"%s %s" % (d.get("p14", "none"), d.get("p14_pid", "none"))')" "the session forgets the dead step"
_fp_int --step record
e2e_expect_equal '[] not_run' "$(printf '%s\n' "$E2E_OUT" | sed -n 's/^PROBE_INTERACTIVE=//p' | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(json.dumps(d.get("running")), d["probes"].get("P14"))')" "a second record: nothing running, and P14's not_run"
_fp_int --step wait-question --seconds 1
e2e_expect_line "QUESTION_NONE"

_flow_test_begin "interactive: P14 polls that would pass \$1 per 30 minutes are no-go (I6)"
_fp_p14_priced fp-int-p14-cost "every turn after the first writes 10000 tokens to the 1-hour cache, \$0.0802 a poll and \$1.44 per 30 minutes: the cost part and P14 are no-go, and the fallback turns holding off" claude-opus-5-5 "0.0795564$FP_TAB$FP_U1" "0.0802$FP_TAB{\"input_tokens\": 0, \"cache_creation_input_tokens\": 10000, \"cache_read_input_tokens\": 1000, \"cache_creation\": {\"ephemeral_5m_input_tokens\": 0, \"ephemeral_1h_input_tokens\": 10000}, \"output_tokens\": 0}"
_fp_int --step setup --mode default
_fp_answer_later 4
_fp_int --step p14 --poll-seconds 3 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "go no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P14"]["parts"]["continues_after_answer"]["result"], d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"])')" "continue and cost parts"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["result"]')" "P14 result"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '"yes" if "Holding is off" in d["probes"]["P14"].get("fallback", "") else d["probes"]["P14"]')" "P14 fallback"

_flow_test_begin "interactive: one dear poll among cheap ones is the poll's cost (I6)"
# The dear turn is the third, so neither the second turn, nor the last (the
# closing reply), nor the mean of the turns after the first is \$0.0802.
FP_UX='{"input_tokens": 0, "cache_creation_input_tokens": 10000, "cache_read_input_tokens": 1000, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 10000}, "output_tokens": 0}'
_fp_p14_priced fp-int-p14-dearest "the worker polls every 3 s and is answered once two await calls have come back, so it makes three await calls and a closing reply; the third call writes 10000 tokens to the 1-hour cache (\$0.0802) and the second call and the reply are cheap (\$0.006248), each charged what it prices at: the poll costs \$0.0802, \$1.44 per 30 minutes, and the cost part and P14 are no-go" claude-opus-5-5 "0.0795564$FP_TAB$FP_U1" "0.0062482$FP_TAB$FP_U2" "0.0802$FP_TAB$FP_UX" "0.0062482$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_after_polls 2
_fp_int --step p14 --poll-seconds 3 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "2 no" "$(_fp_facts '"%s %s" % (d["pricing"]["turn_costs_usd"].index(0.0802), "yes" if d["pricing"]["turn_costs_usd"][-1] == 0.0802 else "no")')" "the dear turn is the third and not the last ($(_fp_facts 'json.dumps(d["pricing"]["turn_costs_usd"])'))"
e2e_expect_equal "0.0802 0 0.0802 1.4436" "$(_fp_facts '"%s %s %s %s" % (d["pricing"]["dearest_turn_usd"], d["pricing"]["unpriced_usd"], d["pricing"]["per_poll_usd"], d["pricing"]["per_30_minutes_usd"])')" "the dearest turn, the bill the turns do not price, per poll and per 30 minutes"
e2e_expect_equal "no-go no-go" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P14"]["parts"]["cost_per_30_minutes"]["result"], d["probes"]["P14"]["result"])')" "cost part and P14"

_flow_test_begin "interactive: the bill the turns do not price is shared among the turns after the first (I6)"
# Only the first turn is overcharged, so the remainder is the same whatever
# the number of polls, and adding all of it to one poll gives another price.
_fp_p14_priced fp-int-p14-share "the worker polls every 3 s and is answered once two await calls have come back: three await calls and a closing reply; the first turn is charged \$0.006 more than its usage prices at and the rest exactly: the poll costs \$0.006248 plus the \$0.006 shared among the turns after the first" claude-opus-5-5 "0.0855564$FP_TAB$FP_U1" "0.0062482$FP_TAB$FP_U2"
_fp_int --step setup --mode default
_fp_answer_after_polls 2
_fp_int --step p14 --poll-seconds 3 --hold-seconds 120
wait "$FP_ANSWERER"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "yes 0.006248 0.006 yes" "$(_fp_facts '"%s %s %s %s" % ("yes" if len(d["pricing"]["turn_costs_usd"]) >= 4 else len(d["pricing"]["turn_costs_usd"]), d["pricing"]["dearest_turn_usd"], d["pricing"]["unpriced_usd"], "yes" if abs(d["pricing"]["per_poll_usd"] - (d["pricing"]["dearest_turn_usd"] + d["pricing"]["unpriced_usd"] / (len(d["pricing"]["turn_costs_usd"]) - 1))) <= 0.000002 else d["pricing"])')" "four turns or more, the dearest turn, the unpriced bill, and per poll is the dearest turn plus the unpriced bill over the turns after the first"

_flow_test_begin "interactive: a P14 worker that parks without an answer is no-go (I8)"
_fp_p14_scenario fp-int-p14-park "no one answers and the hold time is 4 s: the stand-in await prints PARK, the worker stops, and the continue part is no-go" 0.01
_fp_int --step setup --mode default
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4
# How many 2 s polls fit in the 4 s hold before PARK depends on timing, and
# the spend follows the polls: the artifact names neither count.
fe_mask_output '"spent_usd": [0-9.]+' '"spent_usd": <spent>'
FP_POLLS=$(_fp_polls)
fe_mask_text "($FP_POLLS)" '(<polls>)'
e2e_expect_equal "PARK" "${FP_POLLS##* }" "the last poll ($FP_POLLS)"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["parts"]["continues_after_answer"]["result"]')" "continue part"
e2e_expect_equal "no-go" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["result"]')" "P14 result"

_flow_test_begin "interactive: a P14 worker the API refused is not_run, never no-go (I8)"
_fp_p14_scenario fp-int-p14-apierror "the worker's run ends as Claude Code ends a run refused for a usage \
limit, before any await call: the continue part is not_run with the API's answer, and P14 is not no-go" 0.01
: > "$E2E_BIN/claude-api-error"
_fp_int --step setup --mode default
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda p: "%s %s" % (p["result"],
  "yes" if "usage_limit_reached" in p["reason"] else p["reason"]))(
  d["probes"]["P14"]["parts"]["continues_after_answer"])')" "continue part"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" \
  '"yes" if d["probes"]["P14"]["result"] != "no-go" else d["probes"]["P14"]["reason"]')" "P14 is not no-go"

_flow_test_begin "interactive: a P14 worker that never started, or one the API refused, or a worktree whose git push got no answer, leaves P14 not no-go and costs nothing (I17)"
FP_D="the worker's claude exits before printing any event: P14 is not_run, its continue part names claude's exit"
FP_D+=" and its stderr line, no part is no-go, no fallback is named and its \$1 limit is given back; then the API"
FP_D+=" refuses the worker's run: the same; then the scratch worktree's git push gets no answer (it sleeps past"
FP_D+=" --call-timeout-seconds 3): the step is refused naming it, P14 is not changed and nothing is charged"
_fp_p14_scenario fp-int-p14-no-events "$FP_D" 0.01
FP_P14='(lambda p: "%s %s %s %s" % (p["result"], [k for k, v in sorted(p["parts"].items()) if v["result"] == "no-go"],
  "fallback" if p.get("fallback") else "none", d["spend"]["spent_usd"]))(d["probes"]["P14"])'
: > "$E2E_BIN/claude-no-events"
_fp_int --step setup --mode default
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run [] none 0" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_P14")" \
  "P14, its no-go parts, its fallback and spent_usd"
e2e_expect_equal "yes" "$(_fp_get "$E2E_REPO/$FP_REC" '(lambda r: "yes" if "before printing any event: Invalid API key"
  in r else r)(d["probes"]["P14"]["parts"]["continues_after_answer"]["reason"])')" "the continue part's reason"
e2e_describe "the API refuses the worker's run"
rm "$E2E_BIN/claude-no-events"
: > "$E2E_BIN/claude-api-error"
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run [] none 0" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_P14")" \
  "P14, its no-go parts, its fallback and spent_usd"
e2e_describe "the scratch worktree's git push gets no answer"
rm "$E2E_BIN/claude-api-error"
cp "$FP_FIXTURES/bin/git" "$E2E_BIN/"
printf 'push\n' > "$E2E_BIN/git-no-answer"
FP_EV=$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P14"]["evidence"]')
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4 --call-timeout-seconds 3
e2e_expect_equal "5" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "FACTORY_REFUSED=scratch_repo_failed git push did not answer"
e2e_expect_equal "not_run [] none 0 $FP_EV 2" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_P14") $(_fp_get "$E2E_REPO/$FP_REC" \
  'd["probes"]["P14"]["evidence"]') $(_fp_launches)" "P14, spent_usd, P14's evidence and claude -p starts"

_flow_test_begin "interactive: P14's worker is on the model --model names, and the setup's steps pass it on (I21)"
FP_D="the setup run with --model claude-sonnet-5-5 prints a p14 step that passes it; --step p14 with --model"
FP_D+=" claude-sonnet-5-5 starts its worker on that model and not on claude-opus-5-5 (the worker exits before"
FP_D+=" printing any event, so P14 costs nothing)"
_fp_p14_scenario fp-int-p14-model "$FP_D" 0.01
: > "$E2E_BIN/claude-no-events"
_fp_int --step setup --mode default --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status of the setup ($E2E_OUT $E2E_ERR)"
e2e_expect_out "--step p14 --model claude-sonnet-5-5 "
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4 --model claude-sonnet-5-5
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "1 0" "$(grep -c -- '--model claude-sonnet-5-5\( \|$\)' "$E2E_BIN/claude-launches.log") $(grep -c -- \
  '--model claude-opus-5-5' "$E2E_BIN/claude-launches.log")" "the worker's launches naming claude-sonnet-5-5, and claude-opus-5-5"

_flow_test_begin "interactive: P14 is not started when its budget would pass the spend cap (I7)"
_fp_p14_scenario fp-int-p14-budget "with \$24.50 spent of \$25 and P14's \$1 limit, P14 is not_run with reason budget and claude never starts" 0.01
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"] = 24.5'
_fp_int --step setup --mode default
_fp_int --step p14 --poll-seconds 2 --hold-seconds 4
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_equal "not_run budget" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P14"]["result"], d["probes"]["P14"]["reason"])')" "P14"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "24.5" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["spend"]["spent_usd"]')" "spent_usd"

# More ways --step await and --step answer can be wrong. --step await runs
# without the epic check, so:
#   I19 a --state naming the probe record or another file in the factory
#       directory, directly, through a linked file or through a linked
#       folder, is read and written back, and the record is changed
#   I20 a --state file that is not a hold this step stored is overwritten
#   I15 a link at <state>.tmp (the hold is written there, then moved over the
#       state file) or at polls.jsonl beside the state file, symbolic or hard,
#       there when the call starts or put at polls.jsonl while the call waits
#       for an answer, sends the step's write into the file the link names,
#       the probe record included, or creates the missing file a symbolic link
#       names; or a plain <state>.tmp an earlier call left behind stops every
#       later call
#   I16 a link at answer.json or answer.json.tmp beside the held question,
#       symbolic or hard, sends --step answer's write into the file the link
#       names, the probe record included, or creates the missing file a
#       symbolic link names; or a session file naming a folder that is not a
#       P14 evidence folder gets the answer; or a plain answer.json.tmp left
#       behind stops the answer

_fp_await() {   # [arguments] — one --step await call that waits 1 s for an answer
  e2e_run_bin bin/flow-factory.sh probe --interactive --step await --poll-seconds 1 --hold-seconds 60 "$@"
}

_flow_test_begin "interactive: --step await refuses a --state in the factory directory and changes nothing there (I19)"
_fp_runner_scenario fp-int-await-factory "--state names the probe record (relative, absolute, through a linked file, \
through a linked folder), the session file, or a new file in the factory directory or in another probe's evidence \
folder: each is refused with await_state_in_factory and the factory directory is unchanged byte for byte; a P14 \
evidence folder's hold.json and a file outside any repository still work"
mkdir -p "$E2E_REPO/.flow/factory/evidence/P5-1" "$E2E_REPO/.flow/factory/evidence/P14-1" "$E2E_DIR/free"
_fp_record "$E2E_REPO/$FP_REC"
printf '{"mode": "default"}\n' > "$E2E_REPO/.flow/factory/interactive.json"
ln -s "$E2E_REPO/$FP_REC" "$E2E_DIR/hold.json"
ln -s "$E2E_REPO/.flow/factory" "$E2E_DIR/lnk"
_fp_factory_sum() {
  (cd "$E2E_REPO/.flow/factory" && find . -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s %s\n' "$f" "$(cksum < "$f")"; else printf '%s\n' "$f"; fi
  done)
}
FP_SUM=$(_fp_factory_sum)
FP_STATES=("$FP_REC" "$E2E_REPO/$FP_REC" "$E2E_DIR/hold.json" "$E2E_DIR/lnk/probes.json"
  .flow/factory/interactive.json .flow/factory/hold.json .flow/factory/evidence/P5-1/hold.json)
# A file system that ignores case (macOS's default) reaches the factory
# directory under another spelling too.
if [ -d "$E2E_REPO/.flow/FACTORY" ]; then
  FP_STATES+=(.flow/FACTORY/hold.json .flow/Factory/evidence/P14-1/../hold.json .flow/factory/EVIDENCE/P14-1/hold.json)
fi
for FP_STATE in "${FP_STATES[@]}"; do
  _fp_await --state "$FP_STATE"
  e2e_expect_equal "5" "$E2E_RC" "exit status for --state $FP_STATE ($E2E_OUT $E2E_ERR)"
  e2e_expect_out "FACTORY_REFUSED=await_state_in_factory"
  e2e_expect_equal "$FP_SUM" "$(_fp_factory_sum)" "the factory directory after --state $FP_STATE"
done
e2e_describe "a P14 evidence folder's hold.json and a file outside any repository are held and polled"
for FP_STATE in .flow/factory/evidence/P14-1/hold.json "$E2E_DIR/free/hold.json"; do
  _fp_await --state "$FP_STATE"
  e2e_expect_equal "0 WAITING" "$E2E_RC $E2E_OUT" "first call with --state $FP_STATE ($E2E_ERR)"
  _fp_await --state "$FP_STATE"
  e2e_expect_equal "0 WAITING" "$E2E_RC $E2E_OUT" "second call with --state $FP_STATE ($E2E_ERR)"
  e2e_expect_equal "2" "$(cd "$E2E_REPO" && _fp_get "$FP_STATE" 'd["polls"]')" "polls in $FP_STATE"
done

_flow_test_begin "interactive: --step await refuses a --state file that is not a hold and leaves it as it was (I20)"
_fp_runner_scenario fp-int-await-nothold "--state names a file outside any repository that holds other JSON, a list, \
text, or a hold whose held_since is not a number: each is refused with await_state_not_a_hold, the file is unchanged \
and no poll is logged"
mkdir -p "$E2E_DIR/s"
printf '{"name": "something else"}\n' > "$E2E_DIR/s/other.json"
printf '[1, 2]\n' > "$E2E_DIR/s/list.json"
printf 'plain text\n' > "$E2E_DIR/s/notes.txt"
printf '{"question_id": "q1", "held_since": "yesterday", "polls": 1}\n' > "$E2E_DIR/s/bad-hold.json"
for FP_FILE in other.json list.json notes.txt bad-hold.json; do
  FP_BEFORE=$(cksum < "$E2E_DIR/s/$FP_FILE")
  _fp_await --state "$E2E_DIR/s/$FP_FILE"
  e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_FILE ($E2E_OUT $E2E_ERR)"
  e2e_expect_out "FACTORY_REFUSED=await_state_not_a_hold"
  e2e_expect_equal "$FP_BEFORE" "$(cksum < "$E2E_DIR/s/$FP_FILE")" "$FP_FILE after the refusal"
done
e2e_expect_equal "no" "$([ -e "$E2E_DIR/s/polls.jsonl" ] && echo yes || echo no)" "a poll was logged"

_flow_test_begin "interactive: --step await refuses a link where it writes and changes nothing (I15)"
_fp_runner_scenario fp-int-await-links "a symbolic link to the probe record or to a missing file, or a hard link to \
the record, at hold.json.tmp or at polls.jsonl beside --state, in a P14 evidence folder and outside any repository, \
on the first call and on a later one: each is refused with await_linked_file, the factory directory is unchanged \
byte for byte, the missing file is not created and the hold is not polled; a plain hold.json.tmp left behind by an \
earlier call is replaced"
mkdir -p "$E2E_REPO/.flow/factory/evidence/P14-1" "$E2E_DIR/free" "$E2E_DIR/saved"
_fp_record "$E2E_REPO/$FP_REC"
cp "$E2E_REPO/$FP_REC" "$E2E_DIR/record.orig"
# _fp_unlink <path> — remove the file or link at path, if there is one.
_fp_unlink() { if [ -L "$1" ] || [ -e "$1" ]; then rm "$1"; fi; }
# _fp_mask_hold_sums — mask the checksum and size of each hold.json and
# polls.jsonl line of FP_SUM in the artifact: a hold records when it was
# held and each poll when it ran, so both change from run to run.
_fp_mask_hold_sums() {
  local l
  while IFS= read -r l; do
    fe_mask_text "$l" "${l%% *} <checksum> <size>"
  done < <(printf '%s\n' "$FP_SUM" | grep -E '/(hold\.json|polls\.jsonl) [0-9]+ [0-9]+$')
}
# _fp_polls <state> — the polls the hold at state holds, or none.
_fp_polls() { if [ -f "$1" ]; then _fp_get "$1" 'd["polls"]'; else echo none; fi; }
for FP_DIR in "$E2E_REPO/.flow/factory/evidence/P14-1" "$E2E_DIR/free"; do
  FP_STATE="$FP_DIR/hold.json"
  for FP_CALL in first later; do
    if [ "$FP_CALL" = later ]; then
      _fp_await --state "$FP_STATE"
      e2e_expect_equal "0 WAITING" "$E2E_RC $E2E_OUT" "the call before the later ones in $FP_DIR ($E2E_ERR)"
    fi
    FP_POLLS=$(_fp_polls "$FP_STATE")
    for FP_NAME in hold.json.tmp polls.jsonl; do
      for FP_LINK in "symbolic|$E2E_REPO/$FP_REC" "symbolic|$E2E_DIR/missing.json" \
          "symbolic|$E2E_REPO/.flow/factory/missing.json" "hard|$E2E_REPO/$FP_REC"; do
        FP_HOW="${FP_LINK%%|*}"; FP_TARGET="${FP_LINK#*|}"
        if [ -f "$FP_DIR/$FP_NAME" ]; then mv "$FP_DIR/$FP_NAME" "$E2E_DIR/saved/$FP_NAME"; fi
        if [ "$FP_HOW" = symbolic ]; then ln -s "$FP_TARGET" "$FP_DIR/$FP_NAME"
        else ln "$FP_TARGET" "$FP_DIR/$FP_NAME"; fi
        FP_SUM=$(_fp_factory_sum)
        _fp_mask_hold_sums
        FP_CASE="a $FP_HOW link to $FP_TARGET at $FP_NAME, $FP_CALL call, in $FP_DIR"
        _fp_await --state "$FP_STATE"
        e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_CASE ($E2E_OUT $E2E_ERR)"
        e2e_expect_out "FACTORY_REFUSED=await_linked_file ($FP_DIR/$FP_NAME"
        e2e_expect_equal "$FP_SUM" "$(_fp_factory_sum)" "the factory directory after $FP_CASE"
        e2e_expect_equal "no no" "$([ -e "$E2E_DIR/missing.json" ] && echo yes || echo no) \
$([ -e "$E2E_REPO/.flow/factory/missing.json" ] && echo yes || echo no)" "a missing file created by $FP_CASE"
        e2e_expect_equal "$FP_POLLS" "$(_fp_polls "$FP_STATE")" "the hold's polls after $FP_CASE"
        # Put things back, so one wrong write does not change the next case.
        _fp_unlink "$FP_DIR/$FP_NAME"; _fp_unlink "$E2E_DIR/missing.json"
        _fp_unlink "$E2E_REPO/.flow/factory/missing.json"
        cp "$E2E_DIR/record.orig" "$E2E_REPO/$FP_REC"
        if [ -L "$FP_STATE" ] || { [ "$FP_CALL" = first ] && [ -e "$FP_STATE" ]; }; then rm "$FP_STATE"; fi
        if [ -f "$E2E_DIR/saved/$FP_NAME" ]; then mv "$E2E_DIR/saved/$FP_NAME" "$FP_DIR/$FP_NAME"; fi
      done
    done
  done
  e2e_describe "a plain hold.json.tmp an earlier call left behind in $FP_DIR is replaced and the hold is polled"
  printf '{"question_id": "partial' > "$FP_DIR/hold.json.tmp"
  _fp_await --state "$FP_STATE"
  e2e_expect_equal "0 WAITING" "$E2E_RC $E2E_OUT" "the call with a hold.json.tmp left in $FP_DIR ($E2E_ERR)"
  e2e_expect_equal "2 no" "$(_fp_polls "$FP_STATE") $([ -e "$FP_DIR/hold.json.tmp" ] && echo yes || echo no)" \
    "the hold's polls and a hold.json.tmp left in $FP_DIR"
done
e2e_describe "a link put at polls.jsonl while the call waits for an answer is refused when the call logs its poll"
FP_DIR="$E2E_DIR/free"; FP_STATE="$FP_DIR/hold.json"
for FP_HOW in symbolic hard; do
  _fp_unlink "$FP_DIR/polls.jsonl"
  FP_BEFORE=$(cksum < "$FP_STATE")
  FP_SUM=$(_fp_factory_sum)
  _fp_mask_hold_sums
  # Once the call has written the hold it waits 4 s for an answer: the link
  # goes in then.
  (
    FP_I=0
    while [ "$(cksum < "$FP_STATE")" = "$FP_BEFORE" ] && [ "$FP_I" -lt 300 ]; do sleep 0.1; FP_I=$((FP_I + 1)); done
    if [ "$FP_HOW" = symbolic ]; then ln -s "$E2E_REPO/$FP_REC" "$FP_DIR/polls.jsonl"
    else ln "$E2E_REPO/$FP_REC" "$FP_DIR/polls.jsonl"; fi
  ) &
  FP_PLANTER=$!
  e2e_run_bin bin/flow-factory.sh probe --interactive --step await --poll-seconds 4 --hold-seconds 60 --state "$FP_STATE"
  wait "$FP_PLANTER"
  e2e_expect_equal "5" "$E2E_RC" "exit status with a $FP_HOW link put at polls.jsonl during the call ($E2E_OUT $E2E_ERR)"
  e2e_expect_out "FACTORY_REFUSED=await_linked_file ($FP_DIR/polls.jsonl"
  e2e_expect_equal "$FP_SUM" "$(_fp_factory_sum)" "the factory directory after a $FP_HOW link put at polls.jsonl"
  _fp_unlink "$FP_DIR/polls.jsonl"
  cp "$E2E_DIR/record.orig" "$E2E_REPO/$FP_REC"
done

_flow_test_begin "interactive: --step answer refuses a link where it writes and changes nothing (I16)"
_fp_runner_scenario fp-int-answer-links "a symbolic link to the probe record or to a missing file, or a hard link to \
the record, at answer.json or answer.json.tmp beside the held question: each is refused with await_linked_file, the \
factory directory is unchanged byte for byte and the missing file is not created; a session file naming a folder \
that is not a P14 evidence folder is refused with no_question_held; a plain answer.json.tmp left behind is replaced \
and the answer is written"
FP_DIR="$E2E_REPO/.flow/factory/evidence/P14-1"
mkdir -p "$FP_DIR" "$E2E_DIR/saved"
_fp_record "$E2E_REPO/$FP_REC"
cp "$E2E_REPO/$FP_REC" "$E2E_DIR/record.orig"
# The first call writes factory/.gitignore; it is there before any sum is taken.
printf '*\n' > "$E2E_REPO/.flow/factory/.gitignore"
printf '{"p14": "evidence/P14-1", "p14_pid": 1}\n' > "$E2E_REPO/.flow/factory/interactive.json"
printf '{"question_id": "q-answer", "held_since": 1, "polls": 1}\n' > "$FP_DIR/hold.json"
for FP_NAME in answer.json answer.json.tmp; do
  for FP_LINK in "symbolic|$E2E_REPO/$FP_REC" "symbolic|$E2E_DIR/missing.json" "hard|$E2E_REPO/$FP_REC"; do
    FP_HOW="${FP_LINK%%|*}"; FP_TARGET="${FP_LINK#*|}"
    if [ "$FP_HOW" = symbolic ]; then ln -s "$FP_TARGET" "$FP_DIR/$FP_NAME"; else ln "$FP_TARGET" "$FP_DIR/$FP_NAME"; fi
    FP_SUM=$(_fp_factory_sum)
    FP_CASE="a $FP_HOW link to $FP_TARGET at $FP_NAME"
    _fp_int --step answer --text yes
    e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_CASE ($E2E_OUT $E2E_ERR)"
    # The path is shown as the main checkout resolves, which on macOS is under /private.
    e2e_expect_out "/.flow/factory/evidence/P14-1/$FP_NAME is a link or not a plain file)"
    e2e_expect_out "FACTORY_REFUSED=await_linked_file ("
    e2e_expect_equal "$FP_SUM" "$(_fp_factory_sum)" "the factory directory after $FP_CASE"
    e2e_expect_equal "no" "$([ -e "$E2E_DIR/missing.json" ] && echo yes || echo no)" "a missing file created by $FP_CASE"
    rm "$FP_DIR/$FP_NAME"
    if [ -e "$E2E_DIR/missing.json" ]; then rm "$E2E_DIR/missing.json"; fi
    cp "$E2E_DIR/record.orig" "$E2E_REPO/$FP_REC"
  done
done
e2e_describe "a session file whose p14 folder is not a P14 evidence folder is refused"
for FP_P14 in ../.. evidence/P5-1 /tmp; do
  printf '{"p14": "%s", "p14_pid": 1}\n' "$FP_P14" > "$E2E_REPO/.flow/factory/interactive.json"
  _fp_int --step answer --text yes
  e2e_expect_equal "5" "$E2E_RC" "exit status with p14 $FP_P14 ($E2E_OUT $E2E_ERR)"
  e2e_expect_out "FACTORY_REFUSED=no_question_held"
done
e2e_describe "a plain answer.json.tmp an earlier call left behind is replaced and the answer is written"
printf '{"p14": "evidence/P14-1", "p14_pid": 1}\n' > "$E2E_REPO/.flow/factory/interactive.json"
printf '{"question_id": "partial' > "$FP_DIR/answer.json.tmp"
_fp_int --step answer --text yes
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "ANSWER_RECORDED question=q-answer"
e2e_expect_equal "q-answer yes no" "$(_fp_get "$FP_DIR/answer.json" '"%s %s" % (d["question_id"], d["text"])') \
$([ -e "$FP_DIR/answer.json.tmp" ] && echo yes || echo no)" "the answer written and a answer.json.tmp left"

# The committed copy, `probe --export <dir>`.
#
# Ways it can be wrong, written down before the checks:
#   X1 the copy keeps the home path, in the record or in an evidence file
#      (also as the home's realpath)
#   X2 a token-shaped string in the record reaches the copy
#   X3 a token found in the evidence is copied instead of refused, or a
#      refusal leaves a partial copy behind
#   X4 a home path or token in a file that is not text (so cannot be
#      rewritten) is copied
#   X5 the copy's evidence paths still point into the runtime directory, or
#      the copy fails the schema
#   X6 the runtime record is changed
#   X7 an export into a directory that holds an unrelated evidence/ or
#      probes.json deletes or overwrites it; or an export over an earlier
#      export is refused

FP_TOKEN_TAIL="AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"

# _fp_export_scenario <name> <description> — a runtime record whose
# interpreter and keyed_on sit under the scenario's HOME, whose P4 reason
# holds a token-shaped string, and whose P5 evidence is a directory of text
# files naming HOME.
_fp_export_scenario() {
  _fp_runner_scenario "$1" "$2"
  local ev="$E2E_REPO/.flow/factory/evidence/P5-1"
  mkdir -p "$ev/shim"
  _fp_record "$E2E_REPO/$FP_REC" "
for p in d['probes'].values(): p['evidence'] = ''
d['interpreter'] = '$E2E_HOME/.pyenv/versions/3.14.7/bin/python3.14'
d['groups']['environment']['keyed_on']['interpreter'] = d['interpreter']
d['probes']['P5']['evidence'] = 'evidence/P5-1'
d['probes']['P4']['reason'] = 'a log line held ghp_$FP_TOKEN_TAIL'
" stamp
  printf '{"cwd": "%s/work", "real": "%s/work"}\n' "$E2E_HOME" "$(cd "$E2E_HOME" && pwd -P)" > "$ev/stream.jsonl"
  printf '#!/bin/bash\nexec %s/.pyenv/bin/python3 "$@"\n' "$E2E_HOME" > "$ev/shim/gh"
}

_flow_test_begin "export: the copy holds no home path or token and validates (X1, X2, X5, X6)"
_fp_export_scenario fp-export "probe --export docs/flow-factory: the record and the evidence are copied, HOME becomes ~, the record's token is removed, and evidence paths point into the copy"
FP_SUM=$(cksum < "$E2E_REPO/$FP_REC")
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_out "PROBE_EXPORT="
FP_OUTDIR="$E2E_REPO/docs/flow-factory"
e2e_expect_equal "docs/flow-factory/evidence/P5-1" "$(_fp_get "$FP_OUTDIR/probes.json" 'd["probes"]["P5"]["evidence"]')" "P5's evidence path in the copy"
e2e_expect_equal "yes yes" "$([ -f "$FP_OUTDIR/evidence/P5-1/stream.jsonl" ] && echo yes || echo no) $([ -f "$FP_OUTDIR/evidence/P5-1/shim/gh" ] && echo yes || echo no)" "the evidence files in the copy"
e2e_expect_equal "" "$(grep -rlF "$E2E_HOME" "$FP_OUTDIR")" "files in the copy holding HOME"
e2e_expect_equal "" "$(grep -rlF "$(cd "$E2E_HOME" && pwd -P)" "$FP_OUTDIR")" "files in the copy holding HOME's realpath"
e2e_expect_equal "" "$(grep -rlE 'ghp_|gho_|ghs_|github_pat_' "$FP_OUTDIR")" "files in the copy holding a token prefix"
e2e_expect_equal "~/.pyenv/versions/3.14.7/bin/python3.14" "$(_fp_get "$FP_OUTDIR/probes.json" 'd["interpreter"]')" "the interpreter in the copy"
e2e_expect_equal '{"cwd": "~/work", "real": "~/work"}' "$(cat "$FP_OUTDIR/evidence/P5-1/stream.jsonl")" "the evidence text in the copy"
e2e_expect_equal "yes" "$(_fp_get "$FP_OUTDIR/probes.json" '"yes" if "[token removed]" in d["probes"]["P4"]["reason"] else d["probes"]["P4"]["reason"]')" "the record's token is replaced"
fe_mask_text "$FP_SUM" '<checksum> <size>'
e2e_expect_equal "$FP_SUM" "$(cksum < "$E2E_REPO/$FP_REC")" "the runtime record's checksum"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$FP_OUTDIR/probes.json"
e2e_expect_equal "0" "$E2E_RC" "the copy passes --verify-record ($E2E_OUT)"
e2e_describe "a second export into the same directory replaces the earlier export"
printf 'from the earlier export\n' > "$FP_OUTDIR/evidence/P5-1/stale.txt"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status of the second export ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no" "$([ -e "$FP_OUTDIR/evidence/P5-1/stale.txt" ] && echo yes || echo no)" "a file only the earlier export held"

# X26 Exporting into a linked worktree writes evidence paths relative to the
# main checkout (.worktrees/<name>/docs/flow-factory/...), so the paths are
# wrong once the worktree's branch is merged; or a linked worktree outside
# the main checkout is refused although it is the same repository.
_flow_test_begin "export: an export into a linked worktree records paths from that worktree's top (X26)"
_fp_export_scenario fp-export-worktree "probe --export into a linked worktree inside the main checkout and into one outside it: P5's evidence path is docs/flow-factory/evidence/P5-1 in both, the files are there, and a separate repository is still refused"
(
  _e2e_git_env
  cd "$E2E_REPO" && git worktree add -q "$E2E_REPO/.wt/w1" -b x26-in && git worktree add -q "$E2E_DIR/wt-out" -b x26-out
  cd "$E2E_DIR" && git init -q other-repo
) || _flow_assert_fail "$E2E_NAME: could not create the worktrees"
for FP_WT in "$E2E_REPO/.wt/w1" "$E2E_DIR/wt-out"; do
  e2e_run_bin bin/flow-factory.sh probe --export "$FP_WT/docs/flow-factory"
  e2e_expect_equal "0" "$E2E_RC" "exit status for $FP_WT ($E2E_OUT $E2E_ERR)"
  e2e_expect_equal "docs/flow-factory/evidence/P5-1" "$(_fp_get "$FP_WT/docs/flow-factory/probes.json" 'd["probes"]["P5"]["evidence"]')" "P5's evidence path in the copy in $FP_WT"
  e2e_expect_equal "yes" "$([ -f "$FP_WT/docs/flow-factory/evidence/P5-1/stream.jsonl" ] && echo yes || echo no)" "the evidence file in $FP_WT"
done
e2e_run_bin bin/flow-factory.sh probe --export "$E2E_DIR/other-repo/docs/flow-factory"
e2e_expect_equal "5" "$E2E_RC" "exit status for a separate repository"
e2e_expect_out "FACTORY_REFUSED=export_outside_repository"

_flow_test_begin "export: a token in the evidence is refused and nothing is copied (X3)"
_fp_export_scenario fp-export-token "an evidence file holds a ghp_ token: export refuses, names the file, and leaves no copy"
printf 'Authorization: token ghp_%s\n' "$FP_TOKEN_TAIL" >> "$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl (GitHub token)"
e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds"
e2e_expect_no_out "$FP_TOKEN_TAIL"

_flow_test_begin "export: a home path in a file that is not text is refused (X4)"
_fp_export_scenario fp-export-binary "an evidence file that is not UTF-8 text holds HOME: it cannot be rewritten, so export refuses and names it"
printf '\377\376%s/.ssh\000' "$E2E_HOME" > "$E2E_REPO/.flow/factory/evidence/P5-1/blob.bin"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_line "FACTORY_REFUSED=export_home_path evidence/P5-1/blob.bin"
e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds"

_flow_test_begin "export: a directory holding an unrelated evidence/ is refused and left as it was (X7)"
_fp_export_scenario fp-export-unrelated "docs/flow-factory already holds evidence/keep.txt and no probe record: export refuses with export_target_not_empty and deletes nothing"
mkdir -p "$E2E_REPO/docs/flow-factory/evidence"
printf 'keep me\n' > "$E2E_REPO/docs/flow-factory/evidence/keep.txt"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=export_target_not_empty"
e2e_expect_equal "keep me" "$(cat "$E2E_REPO/docs/flow-factory/evidence/keep.txt" 2>/dev/null)" "the unrelated file"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/docs/flow-factory/probes.json" ] && echo yes || echo no)" "a probes.json was written"
e2e_describe "a probes.json there that is not a probe record is refused too"
printf '{"name": "something else"}\n' > "$E2E_REPO/docs/flow-factory/probes.json"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status with an unrelated probes.json"
e2e_expect_out "FACTORY_REFUSED=export_target_not_empty"
e2e_expect_equal '{"name": "something else"}' "$(cat "$E2E_REPO/docs/flow-factory/probes.json")" "the unrelated probes.json"
e2e_expect_equal "keep me" "$(cat "$E2E_REPO/docs/flow-factory/evidence/keep.txt" 2>/dev/null)" "the unrelated file after the second refusal"

_flow_test_begin "export: a directory outside the main checkout is refused (X5)"
_fp_export_scenario fp-export-outside "export to a directory outside the repository is refused"
e2e_run_bin bin/flow-factory.sh probe --export "$E2E_DIR/elsewhere"
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "FACTORY_REFUSED=export_outside_repository"
e2e_expect_equal "no" "$([ -e "$E2E_DIR/elsewhere" ] && echo yes || echo no)" "the directory was created"

# More ways the copy can be wrong:
#   X8 a credential that is not a GitHub token (an Anthropic key, a keyring
#      entry, an AWS key id, a private key, a Slack token) is copied, or a
#      refusal does not say which kind it found
#   X9 the value of a credential variable in the environment is copied, or
#      printed in the refusal; or a value too short to tell from ordinary text
#      is refused
#   X10 the home written the way Claude Code names its project folders (each
#      / a -), or a temporary folder, reaches the copy
#   X11 an entry whose parts came from an earlier run keeps only its latest
#      evidence folder in the copy

_flow_test_begin "export: each credential form in the evidence is refused and named by kind (X8)"
_fp_export_scenario fp-export-forms "an evidence file holds an Anthropic key, a keyring entry, an AWS key id (AKIA and ASIA), a private key header or a Slack token: each is refused with its kind and nothing is copied"
FP_EV_FILE="$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
cp "$FP_EV_FILE" "$E2E_DIR/stream.orig"
# Each value is put together here, so this file holds none of the forms.
FP_FORMS=(
  "sk-""ant-api03-$FP_TOKEN_TAIL|Anthropic key"
  "go-keyring-""base64:c2VjcmV0LXZhbHVlLWZvci1lMmU=|keyring entry"
  "AK""IAQWERTYUIOPASDFGH|AWS access key id"
  "AS""IAZXCVBNMLKJHGFDSA|AWS access key id"
  "-----BEGIN OPENSSH PRIV""ATE KEY-----|private key"
  "xo""xb-1234567890-abcdefghij|Slack token"
  "go-keyring-""encoded:7365637265742d76616c75652d666f722d653265|keyring entry"
  "xo""xe-1-fakeE2Evalue0123456789abcdef|Slack token"
  "xo""xs-0000000000-fakeE2Evalue|Slack token"
)
for FP_FORM in "${FP_FORMS[@]}"; do
  FP_VALUE="${FP_FORM%%|*}"; FP_KIND="${FP_FORM#*|}"
  cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
  printf 'output: %s\n' "$FP_VALUE" >> "$FP_EV_FILE"
  e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
  e2e_expect_equal "5" "$E2E_RC" "exit status for the $FP_KIND form ${FP_VALUE:0:6}"
  e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl ($FP_KIND)"
  e2e_expect_no_out "${FP_VALUE:4}"
  e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds after the $FP_KIND form"
done

_flow_test_begin "export: the value of a credential variable is refused, a value under 12 characters is not (X9)"
_fp_export_scenario fp-export-envvalue "an evidence file holds the 12-character value of each credential variable the export is run with: refused, naming the variable; an 11-character value is copied"
FP_EV_FILE="$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
cp "$FP_EV_FILE" "$E2E_DIR/stream.orig"
FP_N=0
for FP_VAR in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN GH_TOKEN GITHUB_TOKEN FLOW_FACTORY_GH_TOKEN; do
  FP_N=$((FP_N + 1))
  FP_VALUE="fpliteral-$FP_N$FP_N"
  cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
  printf 'echo %s\n' "$FP_VALUE" >> "$FP_EV_FILE"
  e2e_run_bin "$FP_VAR=$FP_VALUE" bin/flow-factory.sh probe --export docs/flow-factory
  e2e_expect_equal "5" "$E2E_RC" "exit status with $FP_VAR"
  e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl (value of $FP_VAR)"
  e2e_expect_no_out "$FP_VALUE"
done
e2e_describe "the same value in a file name is refused with the name shown masked"
cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
FP_VALUE="fpliteral-66"
printf 'x\n' > "$E2E_REPO/.flow/factory/evidence/P5-1/note-$FP_VALUE.txt"
e2e_run_bin "GH_TOKEN=$FP_VALUE" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status for the value in a file name"
e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/note-[token].txt (value of GH_TOKEN)"
e2e_expect_no_out "$FP_VALUE"
rm -f "$E2E_REPO/.flow/factory/evidence/P5-1/note-$FP_VALUE.txt"
e2e_describe "an 11-character value is ordinary text and is copied"
FP_VALUE="fpliteral-7"
printf 'echo %s\n' "$FP_VALUE" >> "$FP_EV_FILE"
e2e_run_bin "GH_TOKEN=$FP_VALUE" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status with an 11-character value ($E2E_OUT)"
e2e_expect_equal "1" "$(grep -c "$FP_VALUE" "$E2E_REPO/docs/flow-factory/evidence/P5-1/stream.jsonl")" "the short value in the copy"
e2e_describe "a credential value and an AWS key id in the record are removed from the copy, not refused"
rm -rf "$E2E_REPO/docs/flow-factory"
FP_VALUE="fpliteral-99"
python3 - "$E2E_REPO/$FP_REC" "$FP_VALUE" "AK""IAQWERTYUIOPASDFGH" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["probes"]["P4"]["reason"] = "saw %s and %s" % (sys.argv[2], sys.argv[3])
json.dump(d, open(sys.argv[1], "w"), indent=1)
PY
e2e_run_bin "ANTHROPIC_API_KEY=$FP_VALUE" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status with credentials in the record ($E2E_OUT)"
e2e_expect_equal "saw [token removed] and [token removed]" "$(_fp_get "$E2E_REPO/docs/flow-factory/probes.json" 'd["probes"]["P4"]["reason"]')" "P4's reason in the copy"

_flow_test_begin "export: the home in Claude Code's project-folder form and temporary folders are rewritten (X10)"
_fp_export_scenario fp-export-scrub "an evidence file names the home with each / written as -, the temporary folder Python finds and its realpath, and another macOS per-user temporary folder: each is rewritten, the home before the temporary folder"
FP_H="$E2E_HOME"; FP_HR=$(cd "$E2E_HOME" && pwd -P)
FP_DH=$(printf '%s' "$FP_H" | tr / -); FP_DHR=$(printf '%s' "$FP_HR" | tr / -)
mkdir -p "$E2E_DIR/tmpsub"
FP_T="$E2E_DIR/tmpsub"; FP_TR=$(cd "$FP_T" && pwd -P)
{
  printf '%s/.claude/projects/%s-repo/s.jsonl\n' "$FP_H" "$FP_DH"
  printf 'projects/%s-repo\n' "$FP_DHR"
  printf '%s/flow-factory-probe-abc/p3\n' "$FP_TR"
  printf '%s/x\n' "$FP_T"
  printf '/private/var/folders/zq/k9other0000gn/T/claude-1/y\n'
  printf '/var/folders/zq/k9other0000gn/T/z\n'
} > "$E2E_REPO/.flow/factory/evidence/P5-1/paths.txt"
e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal '~/.claude/projects/~-repo/s.jsonl|projects/~-repo|$TMPDIR/flow-factory-probe-abc/p3|$TMPDIR/x|$TMPDIR/claude-1/y|$TMPDIR/z' \
  "$(paste -sd'|' - < "$E2E_REPO/docs/flow-factory/evidence/P5-1/paths.txt")" "the rewritten paths"

_flow_test_begin "export: the home's dash form or a temporary folder in a file that is not text is refused (X10, X4)"
_fp_export_scenario fp-export-scrub-binary "a file that is not UTF-8 text holds the home with each / written as -, then a macOS per-user temporary folder: each is refused and named"
printf '\377\376%s-repo\000' "$(printf '%s' "$E2E_HOME" | tr / -)" > "$E2E_REPO/.flow/factory/evidence/P5-1/blob.bin"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status for the dash form"
e2e_expect_line "FACTORY_REFUSED=export_home_path evidence/P5-1/blob.bin"
printf '\377\376/private/var/folders/zq/k9other0000gn/T/q\000' > "$E2E_REPO/.flow/factory/evidence/P5-1/blob.bin"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status for the temporary folder"
e2e_expect_line "FACTORY_REFUSED=export_temp_path evidence/P5-1/blob.bin"
e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds"

_flow_test_begin "export: P3 recorded by the environment group, then the GitHub write group, exports both evidence folders (X11, X20)"
_fp_env_scenario fp-export-history "probe --environment --only P3, then probe --github-write, then probe --export: P3's entry lists the environment run's folder as earlier evidence, and the copy holds both folders"
_fp_env_run -- --only P3
e2e_expect_equal "0" "$E2E_RC" "environment exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "evidence/P3-1" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["probes"]["P3"]["evidence"]')" "P3's evidence after the environment run"
cp "$FP_FIXTURES/github/gh" "$FP_FIXTURES/github/gh_sandbox.py" "$E2E_BIN/"
printf '{}\n' > "$E2E_BIN/gh-config.json"
(
  _e2e_git_env
  cd "$E2E_DIR" && git init -q --bare sandbox.git && git init -q seed || exit 1
  cd seed && git -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m seed \
    && git push -q ../sandbox.git HEAD:refs/heads/main
) || _flow_assert_fail "$E2E_NAME: could not create the sandbox's bare repository"
printf '[url "%s"]\n\tinsteadOf = https://github.com/%s.git\n' "$E2E_DIR/sandbox.git" "$FP_SANDBOX" >> "$E2E_HOME/.gitconfig"
_fp_gw_run "$FP_SANDBOX"
e2e_expect_equal "0" "$E2E_RC" "github write exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "evidence/P3-2 ['evidence/P3-1']" "$(_fp_get "$E2E_REPO/$FP_REC" '"%s %s" % (d["probes"]["P3"]["evidence"], d["probes"]["P3"].get("evidence_history"))')" "P3's evidence and earlier folders"
FP_P3_EV='"%s %s" % tuple(sorted({v.get("evidence") for k, v in d["probes"]["P3"]["parts"].items()
                                 if k.startswith("sandbox_") == s}) for s in (False, True))'
e2e_expect_equal "['evidence/P3-1'] ['evidence/P3-2']" "$(_fp_get "$E2E_REPO/$FP_REC" "$FP_P3_EV")" \
  "the folders P3's environment parts and its sandbox parts name"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "export exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "yes yes" "$([ -f "$E2E_REPO/docs/flow-factory/evidence/P3-1/facts.json" ] && echo yes || echo no) $([ -f "$E2E_REPO/docs/flow-factory/evidence/P3-2/facts.json" ] && echo yes || echo no)" "both P3 folders' facts in the copy"
e2e_expect_equal "docs/flow-factory/evidence/P3-2 ['docs/flow-factory/evidence/P3-1']" "$(_fp_get "$E2E_REPO/docs/flow-factory/probes.json" '"%s %s" % (d["probes"]["P3"]["evidence"], d["probes"]["P3"].get("evidence_history"))')" "P3's folders in the copy"
e2e_expect_equal "['docs/flow-factory/evidence/P3-1'] ['docs/flow-factory/evidence/P3-2']" \
  "$(_fp_get "$E2E_REPO/docs/flow-factory/probes.json" "$FP_P3_EV")" "the folders P3's parts name in the copy"

# More ways the copy can be wrong:
#   X12 an evidence path with a linked folder on the way (a folder inside
#       evidence/, or evidence/ itself) copies files from outside the runtime
#       directory, for evidence or for evidence_history
#   X13 a temporary folder in a dashed form (Claude Code's project-folder
#       names) reaches the copy, as text or in a file that is not text
#   X14 the home is rewritten inside a longer name it is a prefix of, so
#       another user's path is mangled; or the export refuses it as a home
#   X15 a keyring entry in its hex form or a Slack token outside xoxa, xoxb,
#       xoxp and xoxr is copied
#   X16 a home or temporary folder followed by a character that ends a name
#       other than /, a space or a quote (a sentence's full stop, a comma, a
#       closing bracket, a colon, a backtick, a semicolon, a >), or by the end
#       of the text, is copied, as text, in the record or in a file that is
#       not text; or a . that starts the rest of a longer name (T.old) no
#       longer keeps that name whole
#   X17 a home or temporary folder written in another case than the one
#       found (git writes a folder inside a config key name in lower case) is
#       copied, as text or in a file that is not text

_flow_test_begin "export: an evidence path through a linked folder is refused and nothing is copied (X12)"
_fp_export_scenario fp-export-linkdir "P5's evidence, then an earlier folder P3 lists, is evidence/lnk/sub where \
evidence/lnk links to a folder outside the runtime directory; then evidence/ itself is a link: each is refused with \
export_evidence_outside and the copy's directory stays empty"
mkdir -p "$E2E_DIR/outside/sub"
printf 'outside the runtime directory\n' > "$E2E_DIR/outside/sub/note.txt"
ln -s "$E2E_DIR/outside" "$E2E_REPO/.flow/factory/evidence/lnk"
_fp_record "$E2E_REPO/$FP_REC" "
for p in d['probes'].values(): p['evidence'] = ''
d['probes']['P5']['evidence'] = 'evidence/lnk/sub'
"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status for a linked folder in evidence"
e2e_expect_line "FACTORY_REFUSED=export_evidence_outside (P5 evidence/lnk/sub)"
e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds"
_fp_record "$E2E_REPO/$FP_REC" "
for p in d['probes'].values(): p['evidence'] = ''
d['probes']['P5']['evidence'] = 'evidence/P5-1'
d['probes']['P3']['evidence'] = 'evidence/P5-1'
d['probes']['P3']['evidence_history'] = ['evidence/lnk/sub']
"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status for a linked folder in evidence_history"
e2e_expect_line "FACTORY_REFUSED=export_evidence_outside (P3 evidence/lnk/sub)"
e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" \
  "what the copy's directory holds after evidence_history"
e2e_describe "evidence/ itself a link to a folder outside the runtime directory"
rm "$E2E_REPO/.flow/factory/evidence/lnk"
mv "$E2E_REPO/.flow/factory/evidence" "$E2E_DIR/evstore"
ln -s "$E2E_DIR/evstore" "$E2E_REPO/.flow/factory/evidence"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status with evidence/ a link"
e2e_expect_line "FACTORY_REFUSED=export_evidence_outside (P3 evidence/P5-1)"
_fp_record "$E2E_REPO/$FP_REC" "
for p in d['probes'].values(): p['evidence'] = ''
d['probes']['P3']['evidence_history'] = ['evidence/P5-1']
"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status with evidence/ a link, for evidence_history"
e2e_expect_line "FACTORY_REFUSED=export_evidence_outside (P3 evidence/P5-1)"
e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" \
  "what the copy's directory holds with evidence/ a link"

# _fp_dashed <path> — the path with each / written as -, then with every
# character but a letter or digit written as -.
_fp_dashed() { printf '%s\n' "$1" | tr / -; printf '%s\n' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

_flow_test_begin "export: a temporary folder in a dashed form is rewritten (X13)"
_fp_export_scenario fp-export-tempdash "TMPDIR is a folder under /tmp, outside macOS's per-user folders; an evidence \
file names it and its realpath in both dashed forms, and macOS per-user temporary folders in dashed forms: each is \
rewritten as \$TMPDIR"
FP_T=$(mktemp -d /tmp/fp-tmp_dash.XXXXXX); FP_TR=$(cd "$FP_T" && pwd -P)
fe_mask_random "$FP_T"
{
  _fp_dashed "$FP_T" | sed 's/$/-repo\/s.jsonl/; s/^/projects\//'
  _fp_dashed "$FP_TR" | sed 's/$/-repo/; s/^/projects\//'
  printf -- '-private-var-folders-ab-xyz123-T-flow-factory-probe-k1\n'
  printf -- '-var-folders-7h-2x-lb9bx5m3-q8m00000gn-T-x\n'
  printf -- 'p -var-folders-7h-2x_lb9-q8m00000gn-T\n'
} > "$E2E_REPO/.flow/factory/evidence/P5-1/paths.txt"
e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_WANT='projects/$TMPDIR-repo/s.jsonl|projects/$TMPDIR-repo/s.jsonl|projects/$TMPDIR-repo|projects/$TMPDIR-repo'
e2e_expect_equal "$FP_WANT"'|$TMPDIR-flow-factory-probe-k1|$TMPDIR-x|p $TMPDIR' \
  "$(paste -sd'|' - < "$E2E_REPO/docs/flow-factory/evidence/P5-1/paths.txt")" "the rewritten paths"
e2e_describe "the same forms in a file that is not text are refused and named"
rm -r "$E2E_REPO/docs/flow-factory"
for FP_FORM in $(_fp_dashed "$FP_T") $(_fp_dashed "$FP_TR") -private-var-folders-ab-xyz123-T-flow-factory-probe-k1 \
    -var-folders-7h-2x-lb9bx5m3-q8m00000gn-T-x; do
  printf '\377\376%s-repo\000' "$FP_FORM" > "$E2E_REPO/.flow/factory/evidence/P5-1/blob.bin"
  e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
  e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_FORM in a file that is not text"
  e2e_expect_line "FACTORY_REFUSED=export_temp_path evidence/P5-1/blob.bin"
  e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" \
    "what the copy's directory holds after $FP_FORM"
done
rm -r "$FP_T"

_flow_test_begin "export: the home and the temporary folder are rewritten only as whole names (X14)"
_fp_export_scenario fp-export-prefix "HOME is <dir>/home and TMPDIR <dir>/tmpq; an evidence file names \
<dir>/homeless, <dir>/home.old, <dir>/home-old, <dir>/homeé, <dir>/tmpq2, <dir>/tmpq-2, and the dashed forms of \
<dir>/homeless and of the home followed by й: those are left with their own names and the export is not refused, \
while the home's and the temporary folder's own paths are rewritten"
FP_T="$E2E_DIR/tmpq"; mkdir -p "$FP_T"
FP_DH=$(printf '%s' "$E2E_HOME" | tr / -)
{
  printf '%s/x\n' "$E2E_HOME"
  printf '"%s"\n' "$E2E_HOME"
  printf '%s\n' "$E2E_HOME"
  printf 'projects/%s-proj\n' "$FP_DH"
  printf '%s/y\n' "$FP_T"
  printf '%s/x\n' "${E2E_HOME}less"
  printf '%s/x\n' "${E2E_HOME}.old"
  printf '%s/x\n' "${FP_T}2"
  _fp_dashed "${E2E_HOME}less" | sed 's/$/-proj/; s/^/projects\//'
  printf '%s/x\n' "${E2E_HOME}-old" "${E2E_HOME}é" "${FP_T}-2"
  _fp_dashed "$E2E_HOME" | sed 's/$/й-proj/; s/^/projects\//'
} > "$E2E_REPO/.flow/factory/evidence/P5-1/paths.txt"
e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_COPY="$E2E_REPO/docs/flow-factory/evidence/P5-1/paths.txt"
e2e_expect_equal '~/x|"~"|~|projects/~-proj|$TMPDIR/y' "$(head -5 "$FP_COPY" | paste -sd'|' -)" \
  "the home's and the temporary folder's own paths"
# What comes before the other names depends on where the scratch root is (a
# macOS per-user temporary folder is rewritten too), so each line is checked
# for the name it must keep and for no ~.
FP_KEPT="homeless/x home.old/x tmpq2/x homeless-proj homeless-proj home-old/x homeé/x tmpq-2/x homeй-proj homeй-proj"
e2e_expect_equal "$FP_KEPT" "$(tail -n +6 "$FP_COPY" | python3 -c '
import re, sys
sys.stdout.reconfigure(encoding="utf-8")
for ln in sys.stdin.buffer.read().decode("utf-8").splitlines():
    m = re.search(r"(?:home|tmpq).*$", ln)
    print(m.group(0) if m and "~" not in ln else "BAD:" + ln)' | paste -sd' ' -)" "the other names, each kept whole"
e2e_describe "in a file that is not text, a longer name the home is a prefix of is not taken for the home"
rm -r "$E2E_REPO/docs/flow-factory"
for FP_FORM in "${E2E_HOME}-old/x" "${E2E_HOME}é/x" "${FP_DH}й-proj" "${FP_DH}less-proj"; do
  printf '\377\376%s\000' "$FP_FORM" > "$E2E_REPO/.flow/factory/evidence/P5-1/blob.bin"
  e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
  # Under a macOS per-user temporary folder the file is refused for that
  # folder instead, so only a home refusal is wrong here.
  e2e_expect_no_line "FACTORY_REFUSED=export_home_path evidence/P5-1/blob.bin"
  if [ -d "$E2E_REPO/docs/flow-factory" ]; then rm -r "$E2E_REPO/docs/flow-factory"; fi
done

_flow_test_begin "export: a home or temporary folder before punctuation or the end of text is rewritten or refused (X16)"
_fp_export_scenario fp-export-ends "HOME, a TMPDIR under /tmp and another macOS per-user temporary folder, each as \
it is and with each / written as -, are followed by . , ) ] : \` ; > and by the end of the text: in an evidence file \
and in the record each is rewritten, and in a file that is not text each is refused and named; a . that starts the \
rest of a longer name keeps that name whole"
FP_T=$(mktemp -d /tmp/fp-tmpend.XXXXXX)
fe_mask_random "$FP_T"
fe_mask_random "$E2E_ROOT"
FP_DH=$(printf '%s' "$E2E_HOME" | tr / -); FP_DT=$(printf '%s' "$FP_T" | tr / -)
# Each row is <path>|<what the copy holds instead>|<the kind a refusal names>.
FP_KINDS=("$E2E_HOME|~|home" "projects/$FP_DH|projects/~|home" "$FP_T|\$TMPDIR|temp"
  "projects/$FP_DT|projects/\$TMPDIR|temp" "/private/var/folders/zq/k9other0000gn/T|\$TMPDIR|temp"
  "/var/folders/zq/k9other0000gn/T|\$TMPDIR|temp" "projects/-var-folders-zq-k9other0000gn-T|projects/\$TMPDIR|temp")
FP_ENDS=(. , ')' ']' : '`' ';' '>')
FP_EV="$E2E_REPO/.flow/factory/evidence/P5-1"
: > "$E2E_DIR/want.txt"
FP_N=0
for FP_KIND in "${FP_KINDS[@]}"; do
  IFS='|' read -r FP_P FP_NEW FP_WHAT <<< "$FP_KIND"
  for FP_END in "${FP_ENDS[@]}"; do
    printf 'in %s%s next\n' "$FP_P" "$FP_END" >> "$FP_EV/paths.txt"
    printf 'in %s%s next\n' "$FP_NEW" "$FP_END" >> "$E2E_DIR/want.txt"
  done
  FP_N=$((FP_N + 1))
  printf 'in %s' "$FP_P" > "$FP_EV/end-$FP_N.txt"
done
# A . followed by a character that continues a name starts the rest of a
# longer name, which is kept as it is.
for FP_P in "$FP_T.old/x" "/var/folders/zq/k9other0000gn/T.old/x" "projects/-var-folders-zq-k9other0000gn-T.old"; do
  printf 'in %s next\n' "$FP_P" | tee -a "$E2E_DIR/want.txt" >> "$FP_EV/paths.txt"
done
python3 - "$E2E_REPO/$FP_REC" "$E2E_HOME" "$FP_T" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["probes"]["P7"]["reason"] = "ran in %s. Then /var/folders/zq/k9other0000gn/T, and %s" % (sys.argv[2], sys.argv[3])
json.dump(d, open(sys.argv[1], "w"), indent=1)
PY
e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "$(cat "$E2E_DIR/want.txt")" "$(cat "$E2E_REPO/docs/flow-factory/evidence/P5-1/paths.txt" 2>&1)" \
  "the paths followed by each character"
FP_N=0
for FP_KIND in "${FP_KINDS[@]}"; do
  IFS='|' read -r FP_P FP_NEW FP_WHAT <<< "$FP_KIND"
  FP_N=$((FP_N + 1))
  e2e_expect_equal "in $FP_NEW" "$(cat "$E2E_REPO/docs/flow-factory/evidence/P5-1/end-$FP_N.txt" 2>&1)" \
    "$FP_P at the end of the text"
done
e2e_expect_equal 'ran in ~. Then $TMPDIR, and $TMPDIR' \
  "$(_fp_get "$E2E_REPO/docs/flow-factory/probes.json" 'd["probes"]["P7"]["reason"]' 2>&1)" "P7's reason in the copy"
e2e_describe "the same paths followed by each character, or ending it, in a file that is not text are refused and named"
if [ -d "$E2E_REPO/docs/flow-factory" ]; then rm -r "$E2E_REPO/docs/flow-factory"; fi
rm "$FP_EV/paths.txt" "$FP_EV"/end-*.txt
for FP_KIND in "${FP_KINDS[@]}"; do
  IFS='|' read -r FP_P FP_NEW FP_WHAT <<< "$FP_KIND"
  for FP_END in "${FP_ENDS[@]}" ''; do
    if [ -n "$FP_END" ]; then printf '\377\376%s%s\000' "$FP_P" "$FP_END"; else printf '\377\376%s' "$FP_P"; fi \
      > "$FP_EV/blob.bin"
    e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
    e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_P followed by '${FP_END:-the end}' in a file that is not text"
    e2e_expect_line "FACTORY_REFUSED=export_${FP_WHAT}_path evidence/P5-1/blob.bin"
    if [ -d "$E2E_REPO/docs/flow-factory" ]; then rm -r "$E2E_REPO/docs/flow-factory"; fi
  done
done
rm -r "$FP_T"

_flow_test_begin "export: a home or temporary folder written in another case is rewritten or refused (X17)"
_fp_export_scenario fp-export-case "HOME and a TMPDIR under /tmp in lower and upper case, and another macOS per-user \
temporary folder ending in a lower-case t, as git writes it inside a config key name: in an evidence file each is \
rewritten, and in a file that is not text each is refused and named"
FP_T=$(mktemp -d /tmp/fp-tmpcase.XXXXXX)
fe_mask_random "$FP_T"
fe_mask_random "$E2E_ROOT"
FP_LOW() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
FP_UP() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
FP_KINDS=("$(FP_LOW "$E2E_HOME")/x|~/x|home" "$(FP_UP "$E2E_HOME")/x|~/x|home"
  "$(FP_LOW "$(printf '%s' "$E2E_HOME" | tr / -)")-x|~-x|home" "$(FP_UP "$FP_T")/x|\$TMPDIR/x|temp"
  "url./private/var/folders/zq/k9other0000gn/t/flow-x.insteadof|url.\$TMPDIR/flow-x.insteadof|temp"
  "-var-folders-zq-k9other0000gn-t-x|\$TMPDIR-x|temp")
FP_EV="$E2E_REPO/.flow/factory/evidence/P5-1"
: > "$E2E_DIR/want.txt"
for FP_KIND in "${FP_KINDS[@]}"; do
  IFS='|' read -r FP_P FP_NEW FP_WHAT <<< "$FP_KIND"
  printf 'in %s next\n' "$FP_P" >> "$FP_EV/paths.txt"
  printf 'in %s next\n' "$FP_NEW" >> "$E2E_DIR/want.txt"
done
e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "$(cat "$E2E_DIR/want.txt")" "$(cat "$E2E_REPO/docs/flow-factory/evidence/P5-1/paths.txt" 2>&1)" \
  "the paths in another case"
e2e_describe "the same paths in a file that is not text are refused and named"
if [ -d "$E2E_REPO/docs/flow-factory" ]; then rm -r "$E2E_REPO/docs/flow-factory"; fi
rm "$FP_EV/paths.txt"
for FP_KIND in "${FP_KINDS[@]}"; do
  IFS='|' read -r FP_P FP_NEW FP_WHAT <<< "$FP_KIND"
  printf '\377\376%s\000' "$FP_P" > "$FP_EV/blob.bin"
  e2e_run_bin TMPDIR="$FP_T" bin/flow-factory.sh probe --export docs/flow-factory
  e2e_expect_equal "5" "$E2E_RC" "exit status for $FP_P in a file that is not text"
  e2e_expect_line "FACTORY_REFUSED=export_${FP_WHAT}_path evidence/P5-1/blob.bin"
  if [ -d "$E2E_REPO/docs/flow-factory" ]; then rm -r "$E2E_REPO/docs/flow-factory"; fi
done
rm -r "$FP_T"

# More ways the copy can be wrong:
#   X18 the value of a credential variable the launch environment gives a
#       worker (AWS_BEARER_TOKEN_BEDROCK, ANTHROPIC_FOUNDRY_API_KEY,
#       ANTHROPIC_CUSTOM_HEADERS, or one header's value among several) is
#       copied, because only a fixed list of names is looked at; or a
#       variable that holds no credential (ANTHROPIC_MODEL, AWS_REGION), or
#       one the workers are not given, is refused
#   X19 an export that fails part way (a move refused) leaves the earlier
#       copy's evidence deleted, or a mix of the earlier copy and the new one;
#       or leaves its working folder beside the copy
#   X20 a part kept from an earlier run names the folder of the run that kept
#       it, or none; a part whose folder its entry no longer lists is copied
#       without that folder, or its path in the copy still points into the
#       runtime directory; or a part with no folder of its own, as an older
#       record holds, stops the export
#   X21 a credential written after a scheme word (Authorization: Bearer
#       <token>) is looked for only with the word, so the token alone, or the
#       header with the word in another case, is copied
#   X22 the password in a URL the workers are given (a proxy address with
#       user:password@, ANTHROPIC_BASE_URL) is never looked for, because the
#       variable's name holds none of the credential words
#   X23 a second interrupt while an interrupted export moves the earlier
#       evidence back leaves the copy without its evidence, and nothing says
#       which folder holds it

_flow_test_begin "export: the value of a credential variable the workers are given is refused (X18)"
_fp_export_scenario fp-export-launchenv "an evidence file holds the value of AWS_BEARER_TOKEN_BEDROCK, \
ANTHROPIC_FOUNDRY_API_KEY or ANTHROPIC_CUSTOM_HEADERS, which the launch environment gives every worker: each is \
refused naming the variable; one header's value from several is refused too; ANTHROPIC_MODEL, AWS_REGION and a \
token variable the workers are not given are copied"
FP_EV_FILE="$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
cp "$FP_EV_FILE" "$E2E_DIR/stream.orig"
FP_N=0
for FP_VAR in AWS_BEARER_TOKEN_BEDROCK ANTHROPIC_FOUNDRY_API_KEY ANTHROPIC_CUSTOM_HEADERS; do
  FP_N=$((FP_N + 1))
  FP_VALUE="fplaunch-value-$FP_N$FP_N"
  cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
  printf 'echo %s\n' "$FP_VALUE" >> "$FP_EV_FILE"
  e2e_run_bin "$FP_VAR=$FP_VALUE" bin/flow-factory.sh probe --export docs/flow-factory
  e2e_expect_equal "5" "$E2E_RC" "exit status with $FP_VAR"
  e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl (value of $FP_VAR)"
  e2e_expect_no_out "$FP_VALUE"
  e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds after $FP_VAR"
done
e2e_describe "one header's value, written as a worker's request log writes it, from a variable holding two headers"
cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
printf '{"headers": {"x-fp-auth": "fpheader-value-77"}}\n' >> "$FP_EV_FILE"
e2e_run_bin "ANTHROPIC_CUSTOM_HEADERS=X-Fp-Auth: fpheader-value-77
X-Fp-Org: fp-org" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status with a header's value"
e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl (value of ANTHROPIC_CUSTOM_HEADERS)"
e2e_expect_no_out "fpheader-value-77"
e2e_describe "the model, the region and a token variable the workers are not given are copied as they are"
cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
printf 'model claude-opus-5-5 region fp-region-east-1 other fpother-value-12\n' >> "$FP_EV_FILE"
e2e_run_bin ANTHROPIC_MODEL=claude-opus-5-5 AWS_REGION=fp-region-east-1 FP_OTHER_TOKEN=fpother-value-12 \
  bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status with values that are not credentials ($E2E_OUT)"
e2e_expect_equal "1" "$(grep -c 'claude-opus-5-5 region fp-region-east-1 other fpother-value-12' \
  "$E2E_REPO/docs/flow-factory/evidence/P5-1/stream.jsonl" 2>&1)" "the values in the copy"
e2e_describe "a worker's credential value in the record is removed from the copy, not refused"
rm -r "$E2E_REPO/docs/flow-factory"
cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
_fp_record_edit 'd["probes"]["P4"]["reason"] = "saw fplaunch-value-88"'
e2e_run_bin AWS_BEARER_TOKEN_BEDROCK=fplaunch-value-88 bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status with the value in the record ($E2E_OUT)"
e2e_expect_equal "saw [token removed]" "$(_fp_get "$E2E_REPO/docs/flow-factory/probes.json" 'd["probes"]["P4"]["reason"]')" \
  "P4's reason in the copy"

_flow_test_begin "export: an export that cannot finish leaves the earlier copy as it was (X19)"
_fp_export_scenario fp-export-partial "an earlier export is in docs/flow-factory, then the runtime record and evidence \
change; the next export cannot move anything into docs/flow-factory (the folder is read-only): refused with \
export_unwritable, the earlier record and evidence whole, and no working folder left in docs/. Where chflags exists, \
the earlier probes.json then cannot be replaced: the new evidence, already moved in, is moved back out and the \
earlier evidence back in. With nothing in the way the next export replaces the copy"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status of the earlier export ($E2E_OUT $E2E_ERR)"
FP_OUTDIR="$E2E_REPO/docs/flow-factory"
FP_OLD_SUM=$(cksum < "$FP_OUTDIR/probes.json")
FP_OLD_EV=$(cat "$FP_OUTDIR/evidence/P5-1/stream.jsonl")
printf 'a later line\n' >> "$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
printf 'later\n' > "$E2E_REPO/.flow/factory/evidence/P5-1/later.txt"
_fp_record_edit 'd["probes"]["P4"]["reason"] = "checked again"'
# _fp_partial_kept <how> — the copy is still the earlier export's, and docs/
# holds nothing but the copy.
_fp_partial_kept() {
  fe_mask_output '\.flow-factory-export-[A-Za-z0-9_]+' .flow-factory-export-XXXXXXXX
  e2e_expect_equal "5" "$E2E_RC" "exit status $1 ($E2E_OUT $E2E_ERR)"
  e2e_expect_out "FACTORY_REFUSED=export_unwritable"
  e2e_expect_equal "$FP_OLD_SUM" "$(cksum < "$FP_OUTDIR/probes.json")" "the earlier record $1"
  e2e_expect_equal "$FP_OLD_EV|no" "$(cat "$FP_OUTDIR/evidence/P5-1/stream.jsonl" 2>&1)|$([ -e \
    "$FP_OUTDIR/evidence/P5-1/later.txt" ] && echo yes || echo no)" "the earlier evidence, without the later file, $1"
  e2e_expect_equal "flow-factory" "$(ls -A "$E2E_REPO/docs")" "what docs/ holds $1"
}
if [ "$(id -u)" = 0 ]; then
  e2e_describe "running as root, a read-only folder stops no move, so that case is not checked"
else
  chmod 555 "$FP_OUTDIR"
  e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
  chmod 755 "$FP_OUTDIR"
  _fp_partial_kept "with the copy's folder read-only"
fi
if command -v chflags >/dev/null 2>&1; then
  chflags uchg "$FP_OUTDIR/probes.json"
  e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
  chflags nouchg "$FP_OUTDIR/probes.json"
  _fp_partial_kept "with the earlier probes.json immutable"
else
  e2e_describe "no chflags here, so a probes.json that cannot be replaced is not checked"
fi
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status with nothing in the way ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "checked again|yes" "$(_fp_get "$FP_OUTDIR/probes.json" 'd["probes"]["P4"]["reason"]')|$([ -e \
  "$FP_OUTDIR/evidence/P5-1/later.txt" ] && echo yes || echo no)" "the new record and evidence in the copy"
e2e_expect_equal "flow-factory" "$(ls -A "$E2E_REPO/docs")" "what docs/ holds after the export"

_flow_test_begin "export: a part kept from an earlier session exports that session's folder (X20)"
_fp_export_scenario fp-export-parts "P9's entry is evidence/P9-4 and lists only evidence/P9-3 as earlier, as the \
record of 2026-11-15 does; its auto parts were recorded in evidence/P9-2 and name it, its default parts name \
evidence/P9-4: the copy holds all three folders and each part's path points into the copy. A part naming a folder \
outside evidence/ is refused; a part with no folder of its own, as an older record holds, falls back to the folders \
its entry lists"
for FP_N in 2 3 4; do
  mkdir -p "$E2E_REPO/.flow/factory/evidence/P9-$FP_N"
  printf '{"session": %s}\n' "$FP_N" > "$E2E_REPO/.flow/factory/evidence/P9-$FP_N/hooks.jsonl"
done
FP_P9_EDITS="
for p in d['probes'].values(): p['evidence'] = ''
d['probes']['P5']['evidence'] = 'evidence/P5-1'
d['probes']['P9'].update(evidence='evidence/P9-4', evidence_history=['evidence/P9-3'], parts={
  'hook_mode_auto': {'result': 'go', 'reason': 'seen', 'evidence': 'evidence/P9-2'},
  'background_wake_auto': {'result': 'go', 'reason': 'woke', 'evidence': 'evidence/P9-2'},
  'hook_mode_default': {'result': 'go', 'reason': 'seen', 'evidence': 'evidence/P9-4'},
  'background_wake_default': {'result': 'go', 'reason': 'woke', 'evidence': 'evidence/P9-4'}})
"
_fp_record "$E2E_REPO/$FP_REC" "$FP_P9_EDITS" stamp
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_OUTDIR="$E2E_REPO/docs/flow-factory"
e2e_expect_equal "P9-2 P9-3 P9-4" "$(cd "$FP_OUTDIR/evidence" 2>/dev/null && ls -d P9-* | xargs)" "P9's folders in the copy"
e2e_expect_equal '{"session": 2}' "$(cat "$FP_OUTDIR/evidence/P9-2/hooks.jsonl" 2>&1)" "the auto session's capture in the copy"
FP_PART_EV='" ".join("%s=%s" % (k, v.get("evidence")) for k, v in sorted(d["probes"]["P9"]["parts"].items()))'
e2e_expect_equal "background_wake_auto=docs/flow-factory/evidence/P9-2 \
background_wake_default=docs/flow-factory/evidence/P9-4 hook_mode_auto=docs/flow-factory/evidence/P9-2 \
hook_mode_default=docs/flow-factory/evidence/P9-4" "$(_fp_get "$FP_OUTDIR/probes.json" "$FP_PART_EV")" \
  "each part's folder in the copy"
e2e_run_bin bin/flow-factory.sh probe --verify-record "$FP_OUTDIR/probes.json"
e2e_expect_equal "0" "$E2E_RC" "the copy passes --verify-record ($E2E_OUT)"
e2e_describe "a part naming a folder outside evidence/ is refused and the earlier copy is kept"
_fp_record "$E2E_REPO/$FP_REC" "$FP_P9_EDITS
d['probes']['P9']['parts']['hook_mode_auto']['evidence'] = '../outside'" stamp
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status for a part outside evidence/"
e2e_expect_line "FACTORY_REFUSED=export_evidence_outside (P9/hook_mode_auto ../outside)"
e2e_expect_equal "P9-2 P9-3 P9-4" "$(cd "$FP_OUTDIR/evidence" 2>/dev/null && ls -d P9-* | xargs)" \
  "P9's folders in the copy after the refusal"
e2e_describe "parts with no folder of their own fall back to the folders the entry lists"
_fp_record "$E2E_REPO/$FP_REC" "$FP_P9_EDITS
for v in d['probes']['P9']['parts'].values(): v.pop('evidence')" stamp
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status for parts without a folder ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "P9-3 P9-4" "$(cd "$FP_OUTDIR/evidence" 2>/dev/null && ls -d P9-* | xargs)" \
  "P9's folders in the copy: the entry's own and the one it lists"

_flow_test_begin "export: the credential after a header's scheme word is refused alone and in another case (X21)"
_fp_export_scenario fp-export-header-scheme "ANTHROPIC_CUSTOM_HEADERS holds Authorization: Bearer <token>, which the \
launch environment gives every worker: an evidence file holding the token alone, or the header in lower case, is \
refused naming the variable, and nothing is copied"
FP_EV_FILE="$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
cp "$FP_EV_FILE" "$E2E_DIR/stream.orig"
for FP_FORM in 'token=fpbearer-value-4242' 'authorization: bearer fpbearer-value-4242'; do
  cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
  printf '%s\n' "$FP_FORM" >> "$FP_EV_FILE"
  e2e_run_bin "ANTHROPIC_CUSTOM_HEADERS=Authorization: Bearer fpbearer-value-4242" \
    bin/flow-factory.sh probe --export docs/flow-factory
  e2e_expect_equal "5" "$E2E_RC" "exit status with $FP_FORM in the evidence"
  e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl (value of ANTHROPIC_CUSTOM_HEADERS)"
  e2e_expect_no_out "fpbearer-value-4242"
  e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds"
done

_flow_test_begin "export: the password in a URL the workers are given is refused (X22)"
_fp_export_scenario fp-export-url-password "HTTPS_PROXY, all_proxy and ANTHROPIC_BASE_URL hold an address with \
user:password@, which the launch environment gives every worker: an evidence file holding the address, or the \
password alone, is refused naming the variable; a proxy address with no password is copied as it is"
FP_EV_FILE="$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
cp "$FP_EV_FILE" "$E2E_DIR/stream.orig"
for FP_VAR in HTTPS_PROXY all_proxy ANTHROPIC_BASE_URL; do
  for FP_FORM in "connect via http://fpuser:fpproxy-pass-5150@proxy.example:3128 failed" "pw fpproxy-pass-5150"; do
    cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
    printf '%s\n' "$FP_FORM" >> "$FP_EV_FILE"
    e2e_run_bin "$FP_VAR=http://fpuser:fpproxy-pass-5150@proxy.example:3128" \
      bin/flow-factory.sh probe --export docs/flow-factory
    e2e_expect_equal "5" "$E2E_RC" "exit status with $FP_VAR and '$FP_FORM' in the evidence"
    e2e_expect_line "FACTORY_REFUSED=export_secret evidence/P5-1/stream.jsonl (password in $FP_VAR)"
    e2e_expect_no_out "fpproxy-pass-5150"
    e2e_expect_equal "" "$(ls -A "$E2E_REPO/docs/flow-factory" 2>/dev/null)" "what the copy's directory holds"
  done
done
e2e_describe "a proxy address with no password is copied as it is"
cp "$E2E_DIR/stream.orig" "$FP_EV_FILE"
printf 'connect via http://proxy.example:3128 failed\n' >> "$FP_EV_FILE"
e2e_run_bin "HTTPS_PROXY=http://proxy.example:3128" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status with a proxy address with no password ($E2E_OUT)"
e2e_expect_equal "1" "$(grep -c 'connect via http://proxy.example:3128 failed' \
  "$E2E_REPO/docs/flow-factory/evidence/P5-1/stream.jsonl" 2>&1)" "the address in the copy"

# X24 The export rewrites the home but not the local account's name, which
# ls -l, stat, id and whoami print, so it is published when it differs from
# the GitHub login the record already shows.
_flow_test_begin "export: the local account's name is written as [user], and the record's repository owner is kept (X24)"
_fp_export_scenario fp-export-account "with USER and LOGNAME fpacct-x, an evidence line from ls -l naming fpacct-x is exported with [user] in its place, fpacct-xy and fpacct-x.old are kept, and the sandbox owner danielbentes the record names is kept"
printf 'drwxr-xr-x  3 fpacct-x  staff  96 Nov 16 10:00 work\nfpacct-xy fpacct-x.old\ndanielbentes/flow-factory-sandbox\n' \
  > "$E2E_REPO/.flow/factory/evidence/P5-1/ls.txt"
e2e_run_bin USER=fpacct-x LOGNAME=fpacct-x bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "drwxr-xr-x  3 [user]  staff  96 Nov 16 10:00 work
fpacct-xy fpacct-x.old
danielbentes/flow-factory-sandbox" "$(cat "$E2E_REPO/docs/flow-factory/evidence/P5-1/ls.txt")" "the exported ls.txt"
e2e_describe "the same name in a file that is not text is refused, as it cannot be rewritten there"
printf 'owner\377 fpacct-x\n' > "$E2E_REPO/.flow/factory/evidence/P5-1/blob.bin"
e2e_run_bin USER=fpacct-x LOGNAME=fpacct-x bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status"
e2e_expect_out "export_account_name"

# X25 The export looks for the credential values set in its own
# environment, so a value the probes ran with and the export's shell lacks
# (a gateway token set for the probe session only) is never looked for.
_flow_test_begin "export: evidence holding a credential value the probe ran with is refused, although the export's environment lacks it (X25)"
_fp_runner_scenario fp-export-cred-unset "a probe --launch with ANTHROPIC_AUTH_TOKEN set writes its value into its evidence and is killed at its limit: the scan made when the entry is recorded flags the folder by kind, holds no value, and an export run without the variable is refused naming the folder"
FP_GATEWAY="fp-gateway-token-0123456789"
printf 'sleep 30\n' > "$E2E_BIN/claude-behaviour"
printf 'mkdir -p %q && printf "%%s\\n" %q > %q\n' "$E2E_REPO/.flow/factory/evidence/P5-1" "$FP_GATEWAY" \
  "$E2E_REPO/.flow/factory/evidence/P5-1/worker-note.txt" > "$E2E_BIN/claude-script"
e2e_run_bin ANTHROPIC_AUTH_TOKEN="$FP_GATEWAY" bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 0.5 --timeout-seconds 3 --kill-after-seconds 1
e2e_expect_equal "0" "$E2E_RC" "exit status of the launch ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "evidence/P5-1 value of ANTHROPIC_AUTH_TOKEN no" "$(_fp_get "$E2E_REPO/.flow/factory/credential-scan.json" '" ".join("%s %s" % kv for kv in sorted(d.items())) + (" yes" if "'"$FP_GATEWAY"'" in open("'"$E2E_REPO/.flow/factory/credential-scan.json"'").read() else " no")')" \
  "the scan's folders and kinds, and whether the value is in the scan file"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status of the export without the variable"
e2e_expect_out "FACTORY_REFUSED=export_secret evidence/P5-1 (value of ANTHROPIC_AUTH_TOKEN, found when the probe recorded it)"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/docs/flow-factory/probes.json" ] && echo yes || echo no)" "a copy was written"

_flow_test_begin "export: an interrupt while an interrupted export moves the earlier evidence back names its folder (X23)"
_fp_export_scenario fp-export-undo-interrupt "an earlier export is in docs/flow-factory; the next export is \
interrupted just before it replaces probes.json, after its evidence was moved in, and again as it moves the \
earlier evidence back (the inject fixture raises KeyboardInterrupt at both moves): docs/flow-factory keeps the \
earlier probes.json, and stderr names the folder that holds the earlier evidence, which holds it whole"
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status of the earlier export ($E2E_OUT $E2E_ERR)"
FP_OUTDIR="$E2E_REPO/docs/flow-factory"
FP_OLD_SUM=$(cksum < "$FP_OUTDIR/probes.json")
FP_OLD_EV=$(cat "$FP_OUTDIR/evidence/P5-1/stream.jsonl")
printf 'a later line\n' >> "$E2E_REPO/.flow/factory/evidence/P5-1/stream.jsonl"
_fp_record_edit 'd["probes"]["P4"]["reason"] = "checked again"'
_fp_inject 'rename */.flow-factory-export-*/probes.json */docs/flow-factory/probes.json' \
  'rename */.flow-factory-export-*/earlier-evidence */docs/flow-factory/evidence'
e2e_run_bin bin/flow-factory.sh probe --export docs/flow-factory
FP_KEPT=$(printf '%s\n' "$E2E_ERR" | sed -n 's/^PROBE_EXPORT_EARLIER_EVIDENCE=//p')
fe_mask_output '\.flow-factory-export-[A-Za-z0-9_]+' .flow-factory-export-XXXXXXXX
e2e_expect_err "KeyboardInterrupt"
e2e_expect_equal "$FP_OLD_SUM" "$(cksum < "$FP_OUTDIR/probes.json")" "the earlier record in the copy"
e2e_expect_equal "$FP_OLD_EV" "$(if [ -n "$FP_KEPT" ]; then cat "$FP_KEPT/P5-1/stream.jsonl" 2>&1; \
  else echo "no folder named"; fi)" "the earlier evidence in the folder stderr names"

# The probe records results for this repository's factory epic: the phase
# issues its deferred checks name and the journal that approves the sandbox
# are this repository's.
#   J1 a probe in a repository without the epic's journal records results that
#      name this repository's issues; or reading a record, or the help, is
#      refused there too
#   J2 journal-dir.sh getting no answer is refused as not_this_epic, saying
#      the repository holds no epic journal, which nothing showed

_flow_test_begin "probe: without the epic's decision journal a probe records nothing (J1)"
_fp_runner_scenario fp-epic-nojournal "the scratch repository has no .decisions/issue-353.md: --launch and --skip are refused with not_this_epic and nothing is started or written; --verify-record and --help still answer"
rm -f "$E2E_REPO/.decisions/issue-353.md"
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1 --timeout-seconds 10
e2e_expect_equal "5" "$E2E_RC" "exit status for --launch"
e2e_expect_out "FACTORY_REFUSED=not_this_epic"
e2e_expect_equal "0" "$(_fp_launches)" "claude -p starts"
e2e_expect_equal "no" "$([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" "a record was written"
e2e_run_bin bin/flow-factory.sh probe --skip P8 --reason r --fallback f
e2e_expect_equal "5" "$E2E_RC" "exit status for --skip"
e2e_expect_out "FACTORY_REFUSED=not_this_epic"
mkdir -p "$E2E_DIR/rec"
_fp_record "$E2E_DIR/rec/probes.json" '' stamp
e2e_run_bin bin/flow-factory.sh probe --verify-record "$E2E_DIR/rec/probes.json"
e2e_expect_equal "0" "$E2E_RC" "exit status for --verify-record ($E2E_OUT)"
e2e_run_bin bin/flow-factory.sh probe --help
e2e_expect_equal "0" "$E2E_RC" "exit status for --help"
e2e_expect_out "synaptiai/synapti-marketplace"
e2e_expect_out "issue-353.md"
e2e_describe "with the journal back, --launch runs"
_fp_epic_journal
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" --max-budget-usd 1 --timeout-seconds 10
e2e_expect_equal "0" "$E2E_RC" "exit status for --launch with the journal ($E2E_OUT)"
e2e_expect_equal "1" "$(_fp_launches)" "claude -p starts with the journal"

_flow_test_begin "probe: a journal-dir.sh that gets no answer is refused as unreadable, never as another epic's repository (J2)"
_fp_runner_scenario fp-epic-journal-no-answer "journal-dir.sh, replaced in a copy of the plugin, sleeps past \
--call-timeout-seconds 3: probe --launch is refused with journal_dir_unreadable naming the call that did not answer, \
never not_this_epic, and nothing is started or written"
e2e_plugin_copy bin/journal-dir.sh "#!/bin/bash
exec sleep 30"
e2e_run_bin bin/flow-factory.sh probe --launch P5 --group platform --prompt-file "$E2E_DIR/prompt.txt" \
  --max-budget-usd 1 --timeout-seconds 10 --call-timeout-seconds 3
e2e_expect_equal "5" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_line "FACTORY_REFUSED=journal_dir_unreadable (journal-dir.sh did not answer (timed out after 3 s))"
e2e_expect_no_out "not_this_epic"
e2e_expect_equal "0 no" "$(_fp_launches) $([ -e "$E2E_REPO/$FP_REC" ] && echo yes || echo no)" \
  "claude -p starts and a record written"

# probe --skip records a probe the person decided not to run.
#
# Ways it can be wrong, written down before the checks:
#   K1 it records anything but not_run, or writes the group's keyed_on or
#      ran_at (a skipped probe ran against no tool versions, and the
#      github_write group's real values would be lost)
#   K2 it skips any probe, so a probe that must run could be skipped instead;
#      or it accepts no reason or fallback
_fp_skip_scenario() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
  _fp_link_user_site
  _fp_epic_journal
  mkdir -p "$E2E_REPO/.flow/factory"
  _fp_record "$E2E_REPO/.flow/factory/probes.json" "$3"
}

_flow_test_begin "skip: P8 is recorded not_run with the person's reason and fallback, and no group changes (K1)"
_fp_skip_scenario fp-skip-p8 "P8 is skipped by the person's decision: not_run, reason and fallback kept, the github_write group's keyed values unchanged" 'del d["probes"]["P8"]; d["groups"]["github_write"] = {"keyed_on": {"sandbox": "danielbentes/flow-factory-sandbox"}, "ran_at": "2026-11-12T21:25:42Z"}'
FP_GROUPS_BEFORE=$(_fp_get "$E2E_REPO/.flow/factory/probes.json" 'd["groups"]')
e2e_run_bin bin/flow-factory.sh probe --skip P8 --reason "no second GitHub account to edit as" --fallback "comments from unknown editors are treated as untrusted"
e2e_expect_equal "0" "$E2E_RC" "exit status"
e2e_expect_out "PROBE_SKIP=P8"
e2e_expect_equal "not_run|no second GitHub account to edit as|comments from unknown editors are treated as untrusted|github_write|False" "$(_fp_get "$E2E_REPO/.flow/factory/probes.json" '"|".join(str(x) for x in (d["probes"]["P8"]["result"], d["probes"]["P8"]["reason"], d["probes"]["P8"]["fallback"], d["probes"]["P8"]["group"], d["probes"]["P8"]["stand_in"]))')" "P8's entry"
e2e_expect_equal "$FP_GROUPS_BEFORE" "$(_fp_get "$E2E_REPO/.flow/factory/probes.json" 'd["groups"]')" "the groups after the skip"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/.flow/factory/probes.json")" "schema"

_flow_test_begin "skip: only P8 can be skipped, and a reason and fallback are required (K2)"
_fp_skip_scenario fp-skip-other "skipping P3, or P8 without a reason or fallback, is refused and the record is unchanged" ''
FP_REC_BEFORE=$(cat "$E2E_REPO/.flow/factory/probes.json")
e2e_run_bin bin/flow-factory.sh probe --skip P3 --reason "r" --fallback "f"
e2e_expect_equal "2" "$E2E_RC" "exit status for P3"
e2e_run_bin bin/flow-factory.sh probe --skip P8 --fallback "f"
e2e_expect_equal "2" "$E2E_RC" "exit status without a reason"
e2e_run_bin bin/flow-factory.sh probe --skip P8 --reason "r"
e2e_expect_equal "2" "$E2E_RC" "exit status without a fallback"
e2e_expect_equal "$FP_REC_BEFORE" "$(cat "$E2E_REPO/.flow/factory/probes.json")" "the record after the refusals"

# The phase 1a changes to the probe command (#354, task T10): the probe lock,
# re-recording the interpreter, `probe --environment` without --sandbox, the
# factory_path pointer, and P5's engine_charge part.
#
# Ways it can be wrong, written down before the checks:
#   PR1 `probe --environment` still demands --sandbox, or without it still
#       reads the Keychain token and sends the token check's writes, or
#       records a sandbox it was never given (a record the schema refuses)
#   PR2 the interpreter is re-recorded without a person: a run with no
#       controlling terminal replaces a recorded interpreter with another, or
#       a person at a terminal who does not type probe still gets it
#       replaced; or a first recording (no interpreter yet) needs a terminal
#   PR3 factory_path is not recorded, or the pointer under the git common
#       directory is not written; or the probe schema's pattern for it refuses
#       the ~ form probe --export writes, so a record whose factory directory
#       is under the home cannot be exported
#   PR4 probes still take F/.lock, the engine's lock, so a long probe blocks
#       `next`
#   PR5 engine_charge is go when the engine's charge double counts (a resumed
#       run charged the whole session's total), or is judged from runs that
#       cannot be compared


FP_NO_SANDBOX_REASON="the token check reads the sandbox and sends it three writes built to be refused, and this run was given no sandbox (flow-factory.sh probe --environment --sandbox <owner/repo>)"

_flow_test_begin "environment: probe --environment without --sandbox records the group and leaves the token check not_run (PR1)"
_fp_env_scenario fp-env-no-sandbox "probe --environment with no --sandbox: exit 0; P3's worker token part is not_run naming --sandbox, its other parts run; the Keychain is not read, no request reaches the stub API, no sandbox is keyed and the record validates"
e2e_run_bin bin/flow-factory.sh probe --environment --github-api "$(e2e_stub_url api)" --only P3
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "not_run|$FP_NO_SANDBOX_REASON" \
  "$(_fp_get "$E2E_REPO/$FP_REC" '"|".join((d["probes"]["P3"]["parts"]["worker_token"]["result"], d["probes"]["P3"]["parts"]["worker_token"]["reason"]))')" \
  "the worker token part"
e2e_expect_equal "go go" "$(_fp_get "$E2E_REPO/$FP_REC" '" ".join(d["probes"]["P3"]["parts"][k]["result"] for k in ("gh_auth_status", "git_push_local"))')" \
  "two of P3's other parts"
e2e_expect_equal "" "$(cat "$E2E_BIN/security-calls.log" 2>/dev/null)" "Keychain lookups"
e2e_expect_equal "0" "$(e2e_stub_requests api)" "requests to the stub API"
e2e_expect_equal "absent" "$(_fp_get "$E2E_REPO/$FP_REC" '"present" if "sandbox" in d["groups"]["environment"]["keyed_on"] else "absent"')" "keyed_on sandbox"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
_fp_env_after
e2e_describe "--launch-context from an ordinary shell without --sandbox prints a plist and cron line with no --sandbox"
e2e_run_bin bin/flow-factory.sh probe --environment --launch-context
e2e_expect_equal "0" "$E2E_RC" "exit status of the printing call ($E2E_OUT $E2E_ERR)"
e2e_expect_out "--launch-context"
e2e_expect_no_out "None"
e2e_expect_no_out "--sandbox"

# _fp_detached_env [probe arguments] — probe --environment --only P15 run
# through detach.py, so it has no controlling terminal even when the suite
# runs in one.
_fp_detached_env() {
  _e2e_exec "$FP_DETACH_PY" "$FP_FIXTURES/detach.py" "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment \
    --sandbox "$FP_SANDBOX" --github-api "$(e2e_stub_url api)" --only P15 "$@"
}

_flow_test_begin "environment: another interpreter is recorded over a recorded one only from a terminal where the person types probe (PR2)"
_fp_env_scenario fp-env-rerecord "the record names /opt/python/bin/python3.14, which is not the interpreter the wrapper resolves"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" "d['groups']['environment']['keyed_on']['interpreter'] = d['interpreter']" stamp
FP_SUM=$(cksum < "$E2E_REPO/$FP_REC")
e2e_describe "(a) with no controlling terminal: exit 5 with the needs-terminal refusal, and the record is unchanged"
_fp_detached_env
e2e_expect_equal "5" "$E2E_RC" "exit status with no terminal ($E2E_OUT $E2E_ERR)"
e2e_expect_line "FACTORY_REFUSED=interpreter_rerecord_needs_terminal next: run flow-factory.sh probe --environment in a terminal"
e2e_expect_equal "$FP_SUM" "$(cksum < "$E2E_REPO/$FP_REC")" "the record after the refusal"
e2e_describe "(b) at a terminal where the person types no: exit 5, and the record is unchanged"
fe_person_terminal nope "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment --sandbox "$FP_SANDBOX" \
  --github-api "$(e2e_stub_url api)" --only P15
e2e_expect_equal "5" "$E2E_RC" "exit status after typing nope ($E2E_OUT)"
e2e_expect_out "type probe to re-record the interpreter /opt/python/bin/python3.14 -> "
e2e_expect_out "FACTORY_REFUSED=interpreter_rerecord_not_confirmed"
e2e_expect_equal "$FP_SUM" "$(cksum < "$E2E_REPO/$FP_REC")" "the record after the unconfirmed prompt"
e2e_describe "(c) at a terminal where the person types probe: exit 0, and the record names the resolved interpreter"
fe_person_terminal probe "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" probe --environment --sandbox "$FP_SANDBOX" \
  --github-api "$(e2e_stub_url api)" --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status after typing probe ($E2E_OUT)"
FP_INTERP=$(_fp_get "$E2E_REPO/$FP_REC" 'd["interpreter"]')
e2e_expect_equal "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$(fe_python)")" "$FP_INTERP" "the recorded interpreter"
e2e_expect_equal "$FP_INTERP" "$(_fp_get "$E2E_REPO/$FP_REC" 'd["groups"]["environment"]["keyed_on"]["interpreter"]')" "keyed_on interpreter"
e2e_describe "(d) again with no terminal, now that the record names the same interpreter: exit 0"
_fp_detached_env
e2e_expect_equal "0" "$E2E_RC" "exit status with the same interpreter and no terminal ($E2E_OUT $E2E_ERR)"
_fp_env_after

_flow_test_begin "environment: a first interpreter is recorded with no terminal (PR2)"
_fp_env_scenario fp-env-first-interp "the record holds no interpreter; probe --environment runs with no controlling terminal: exit 0 and the interpreter is recorded"
mkdir -p "$E2E_REPO/.flow/factory"
_fp_record "$E2E_REPO/$FP_REC" "del d['interpreter']" stamp
_fp_detached_env
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$(fe_python)")" "$(_fp_get "$E2E_REPO/$FP_REC" 'd.get("interpreter")')" "the recorded interpreter"
_fp_env_after

_flow_test_begin "environment: probe --environment records factory_path and the pointer beside the git common directory (PR3)"
_fp_env_scenario fp-env-factory-path "after probe --environment, the record's factory_path is the factory directory and <git common dir>/flow-factory-path holds it with one newline"
_fp_env_run -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_OUT $E2E_ERR)"
FP_COMMON=$(cd "$E2E_REPO" && command git rev-parse --path-format=absolute --git-common-dir)
FP_F="$(dirname "$FP_COMMON")/.flow/factory"
e2e_expect_equal "$FP_F" "$(_fp_get "$E2E_REPO/$FP_REC" 'd.get("factory_path")')" "factory_path"
e2e_expect_equal "$(printf '%s\nEND' "$FP_F")" "$(cat "$FP_COMMON/flow-factory-path"; printf END)" "the pointer file"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/$FP_REC")" "the record validates against the schema"
_fp_env_after

_flow_test_begin "export: a factory directory under the home exports factory_path as ~ and validates (PR3)"
_fp_env_scenario fp-export-factory-path "HOME is the scenario folder, which holds the repository: probe --environment, then probe --export docs/flow-factory; the copy's factory_path is ~/repo/.flow/factory and validates. With the schema's pattern ^/ (a plugin copy), the export is refused naming factory_path"
fe_user_site "$E2E_DIR"
_fp_env_run HOME="$E2E_DIR" -- --only P15
e2e_expect_equal "0" "$E2E_RC" "exit status of the probe ($E2E_OUT $E2E_ERR)"
e2e_run_bin HOME="$E2E_DIR" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "0" "$E2E_RC" "exit status of the export ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "~/repo/.flow/factory" "$(_fp_get "$E2E_REPO/docs/flow-factory/probes.json" 'd.get("factory_path")')" "the exported factory_path"
e2e_expect_equal "ok" "$(_fp_schema_valid "$E2E_REPO/docs/flow-factory/probes.json")" "the copy validates against the schema"
FP_SCHEMA=$(python3 - "$E2E_PLUGIN_DIR/schemas/v1/factory-probes.schema.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["properties"]["factory_path"]["pattern"] = "^/"
print(json.dumps(s, indent=2))
PY
)
e2e_plugin_copy schemas/v1/factory-probes.schema.json "$FP_SCHEMA"
e2e_run_bin HOME="$E2E_DIR" bin/flow-factory.sh probe --export docs/flow-factory
e2e_expect_equal "5" "$E2E_RC" "exit status of the export with ^/ ($E2E_OUT $E2E_ERR)"
e2e_expect_out "FACTORY_REFUSED=export_invalid factory_path: "

_flow_test_begin "probe lock: a probe holds F/probes.lock and leaves F/.lock free (PR4)"
_fp_runner_scenario fp-probe-lock "a background process holds the probe lock (factory_lock) for 8 s; a non-blocking flock of F/probes.lock fails and one of F/.lock succeeds"
mkdir -p "$E2E_REPO/.flow/factory"
fe_bg holder fe_py "import os, sys, time
import _flow_factory as ff
with ff.factory_lock(os.path.realpath('.flow/factory')):
    print('locked', flush=True)
    time.sleep(8)"
fe_wait_for 10 'grep -qx locked "$E2E_DIR/bg-holder.out"'
fe_py "import fcntl, os
for name in ('probes.lock', '.lock'):
    fd = os.open(os.path.join('.flow/factory', name), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(name + ' free')
    except BlockingIOError:
        print(name + ' held')
    finally:
        os.close(fd)"
e2e_expect_line "probes.lock held"
e2e_expect_line ".lock free"
fe_bg_wait holder 15

# _fp_p5_results <evidence dir> — "a b t" of P5's cost check from the two
# result events the stand-in printed: the four-step session's total_cost_usd
# (a fresh run's own cost), the resume's model_usage_since_last_result sum
# (its own cost) and the resume's total_cost_usd (the session's).
_fp_p5_results() {
  python3 - "$1" <<'PY'
import json, os, sys
def result(name):
    last = None
    for ln in open(os.path.join(sys.argv[1], name, "stream.jsonl"), encoding="utf-8"):
        try:
            e = json.loads(ln)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("type") == "result":
            last = e
    return last
first, resume = result("cost-first"), result("cost-resume")
since = sum(m["costUSD"] for m in resume["model_usage_since_last_result"].values())
print(first["total_cost_usd"], round(since, 7), resume["total_cost_usd"])
PY
}

_flow_test_begin "platform: P5's engine_charge is go when the engine charges each run its own cost, and no-go when it charges a session total (PR5, RM4, G1)"
FP_D="every result carries model_usage_since_last_result and every turn costs \$0.003. A first P5 run reads the"
FP_D+=" four-step session's own cost a from its result; the stand-in then adds a to a resumed run's total, so a"
FP_D+=" second P5 run's resume reports since-last b and total t = a + b: engine_charge is go naming a, b and t."
FP_D+=" With a plugin copy whose charge_run charges a run its total_cost_usd, engine_charge is no-go"
_fp_platform_scenario fp-plat-p5-engine-charge "$FP_D"
FP_PID=P5
printf '0\n' > "$E2E_BIN/claude-since-last"
printf '0.003\n' > "$E2E_BIN/claude-cost-per-turn"
_fp_platform_run -- --only P5
e2e_expect_equal "0" "$E2E_RC" "exit status of the first run ($E2E_OUT $E2E_ERR)"
read -r FP_A FP_B0 FP_T0 <<< "$(_fp_p5_results "$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')")"
printf '%s\n' "$FP_A" > "$E2E_BIN/claude-since-last"
_fp_platform_run -- --only P5
e2e_expect_equal "0" "$E2E_RC" "exit status of the second run ($E2E_OUT $E2E_ERR)"
read -r FP_A FP_B FP_T <<< "$(_fp_p5_results "$E2E_REPO/.flow/factory/$(_fp_p 'p["evidence"]')")"
e2e_expect_equal "yes" "$(python3 -c 'import sys; from decimal import Decimal as D; a, b, t = map(D, sys.argv[1:4]); print("yes" if abs(a + b - t) <= D("0.000001") and b < t else "no")' "$FP_A" "$FP_B" "$FP_T")" \
  "the stand-in's figures: a ($FP_A) + b ($FP_B) = t ($FP_T), b < t"
e2e_expect_equal "go yes" "$(FP_FIG="$FP_A $FP_B $FP_T" _fp_p '(lambda c: "%s %s" % (c["result"], "yes"
  if all(x in c["reason"] for x in __import__("os").environ["FP_FIG"].split()) else c["reason"]))(p["parts"]["engine_charge"])')" \
  "engine_charge and its reason naming a, b and t"
e2e_describe "the same with a plugin copy whose charge_run charges every run its total_cost_usd"
FP_JOBS=$(python3 - "$E2E_PLUGIN_DIR/bin/_flow_factory_jobs.py" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = 'return {"charged_usd": since, "basis": "since_last"'
assert s.count(old) == 1
print(s.replace(old, 'return {"charged_usd": total, "basis": "since_last"'), end="")
PY
)
e2e_plugin_copy bin/_flow_factory_jobs.py "$FP_JOBS"
chmod 644 "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_jobs.py"
_fp_platform_run -- --only P5
e2e_expect_equal "0" "$E2E_RC" "exit status of the run with the copy ($E2E_OUT $E2E_ERR)"
e2e_expect_equal "no-go yes" "$(_fp_p '(lambda c: "%s %s" % (c["result"], "yes"
  if "increase in the session" in (p.get("fallback") or "") and "total_cost_usd since the run before" in (p.get("fallback") or "") else p.get("fallback")))(p["parts"]["engine_charge"])')" \
  "engine_charge and P5's fallback"

_flow_test_begin "platform: the plugin's own hooks are unchanged by every platform scenario (PL11)"
e2e_new fp-plat-hooks-unchanged
e2e_describe "the checksum of plugins/flow/hooks after the platform scenarios equals the one before"
e2e_expect_equal "$FP_HOOKS_SUM_BEFORE" "$(cd "$REPO_ROOT/plugins/flow/hooks" && find . -type f -print | LC_ALL=C sort | xargs cksum | cksum)" "hooks checksum"
