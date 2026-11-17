# shellcheck shell=bash
# Probe staleness against the installed tools (phase 1a, #354, task T10):
# bin/_flow_factory_staleness.py, which `next` (T11), `launch` (T7) and
# `status` (T12) call to decide whether workers may start and which status
# lines to print.
#
# Every scenario calls the module through the isolation driver (fe_py), in
# the scratch repository with the scratch HOME, the factory gh stub and the
# worker claude stand-in on PATH. No shipped subcommand reaches the module
# until T11, so this file is its only test before then.
#
# Ways it can be wrong, written down before the checks:
#   SL1  a partial platform re-run looks fresh: the group carries the installed
#        claude version while one of its entries (P5) is still stamped with
#        the old one, and only the group is compared (journal RM6, plan R21)
#   SL2  a current record looks stale
#   SL3  a gh update pauses launches: the environment re-run compares every
#        keyed_on key, or fails when the gh version moved, instead of
#        recording the new version (plan R20)
#   SL4  a changed interpreter passes the environment re-run
#   SL5  a signer that needs a person passes the re-run, or the re-run waits
#        for it past its time limit
#   SL6  a probe holding its lock blocks the engine lock (plan R19), or the
#        re-run waits behind it longer than 2 s, or writes after giving up
#   SL7  resume is gated on P5's overall result (cost_scope no-go would stop
#        every resume), or not gated on the five session parts
#   SL8  a worker.model that differs from the recorded model is not noticed
#   SL9  the launch gate stops engine directives while the platform is stale
#   SL10 the interactive and GitHub-write status lines are missing, or name
#        another sandbox than the record's
#   SL11 the environment re-run is due again before syncIntervalSeconds has
#        passed, or never due after it
#   SL12 the re-run's state (env_recheck_at, env_failed_check) is not written,
#        so a failed check never pauses launches; or it is written without
#        the global lock held

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# The lines every fe_py program here starts with. st is a settings reader
# with the signature of _flow_factory_jobs.setting; ST_SETTINGS (a JSON
# object of key -> value) gives its answers.
SL_PRE='import os, sys, json, time
import _flow_factory as ff
import _flow_factory_jobs as j
import _flow_factory_staleness as s
p = j.resolve()
F = p.fdir
SETTINGS = json.loads(os.environ.get("SL_SETTINGS") or "{}")
def st(key, default=None):
    return SETTINGS.get(key, default)
def rec():
    with open(os.path.join(F, "probes.json"), encoding="utf-8") as f:
        return json.load(f)
'

# Python statements on the record d: stamp(pid, version) sets the claude
# version of one entry and each of its parts.
SL_STAMP='
def stamp(pid, v):
    e = d["probes"][pid]
    e["keyed_on"]["claude_version"] = v
    for part in (e.get("parts") or {}).values():
        part["keyed_on"]["claude_version"] = v
'
V325="2.1.325 (Claude Code)"
V326="2.1.326 (Claude Code)"

_flow_test_begin "staleness: a platform group re-run that left P5 on the old claude is stale (SL1, RM6, R21)"
fe_new sl-partial-platform
# Source of the expected values: journal RM6; recorded_under (_flow_factory.py:852); plan 2.6 status line.
e2e_describe "claude --version prints 2.1.326; the platform group and P1, P2, P4, P10, P16 are stamped 2.1.326, P5 and its parts 2.1.325: platform_state is stale with the PAUSED line naming 2.1.325 and 2.1.326, and launch_gate refuses worker and judge launches"
e2e_repo main
fe_worker_says "claude-version=$V326"
fe_record "$SL_STAMP
d['groups']['platform']['keyed_on']['claude_version'] = '$V326'
for pid in ('P1', 'P2', 'P4', 'P10', 'P16'):
    stamp(pid, '$V326')
stamp('P5', '$V325')"
fe_py "$SL_PRE
r = s.platform_state(F, st)
print('stale=%s' % str(r['stale']).lower())
print('line=%s' % r['line'])
print('recorded=%s current=%s' % (r['recorded'], r['current']))
print('worker gate=%s' % s.launch_gate(F, 'worker', st))
print('judge gate=%s' % s.launch_gate(F, 'judge', st))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "stale=true"
e2e_expect_line "line=PAUSED probes_stale=platform recorded=$V325 current=$V326 next: flow-factory.sh probe --platform"
e2e_expect_line "recorded=$V325 current=$V326"
e2e_expect_line "worker gate=PROBES_STALE=platform"
e2e_expect_line "judge gate=PROBES_STALE=platform"

_flow_test_begin "staleness: one stale P5 part under a current entry is stale too (SL1)"
fe_new sl-partial-part
# Source of the expected values: recorded_under (_flow_factory.py:852) requires every part's own stamp to match.
e2e_describe "every entry and the group are stamped 2.1.326, but P5's cost_scope part still 2.1.325: stale, the line names the part's 2.1.325"
e2e_repo main
fe_worker_says "claude-version=$V326"
fe_record "$SL_STAMP
d['groups']['platform']['keyed_on']['claude_version'] = '$V326'
for pid in ('P1', 'P2', 'P4', 'P5', 'P10', 'P16'):
    stamp(pid, '$V326')
d['probes']['P5']['parts']['cost_scope']['keyed_on']['claude_version'] = '$V325'"
fe_py "$SL_PRE
r = s.platform_state(F, st)
print('stale=%s' % str(r['stale']).lower())
print('line=%s' % r['line'])"
e2e_expect_line "stale=true"
e2e_expect_line "line=PAUSED probes_stale=platform recorded=$V325 current=$V326 next: flow-factory.sh probe --platform"

_flow_test_begin "staleness: a record stamped with the installed claude is current (SL2)"
fe_new sl-current
# Source of the expected values: design phasing L27 (stale when claude --version differs from the record).
e2e_describe "every platform stamp is 2.1.326 and claude --version prints 2.1.326: not stale, no line, every launch kind passes the gate, and status_lines is empty"
e2e_repo main
fe_worker_says "claude-version=$V326"
fe_record "$SL_STAMP
for g in ('platform', 'interactive'):
    d['groups'][g]['keyed_on']['claude_version'] = '$V326'
for pid in ('P1', 'P2', 'P4', 'P5', 'P10', 'P16'):
    stamp(pid, '$V326')"
fe_py "$SL_PRE
r = s.platform_state(F, st)
print('stale=%s line=%s' % (str(r['stale']).lower(), r['line']))
print('gates=%s' % [s.launch_gate(F, k, st) for k in ('worker', 'judge', 'directive')])
print('status_lines=%s' % s.status_lines(F, st))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "stale=false line=None"
e2e_expect_line "gates=[None, None, None]"
e2e_expect_line "status_lines=[]"

_flow_test_begin "staleness: a new gh version is recorded by the environment re-run and pauses nothing (SL3, R20)"
fe_new sl-gh-update
# Source of the expected values: design phasing L27, L29 (the automatic re-run records a new gh or git version).
e2e_describe "the gh stub prints gh version 2.200.0; claude is unchanged. Under the global lock environment_recheck is ok and recorded; the record's environment gh_version is the new one; state.json has env_recheck_at and env_failed_check null; no status line"
e2e_repo main
fe_record
fe_gh --version 'gh version 2.200.0 (2026-11-01)'
fe_py "$SL_PRE
print('platform stale=%s' % str(s.platform_state(F, st)['stale']).lower())
with j.global_lock(p, 5):
    r = s.environment_recheck(F, time.time() + 30)
print('recheck=%s' % json.dumps(r, sort_keys=True))
print('gh_version=%s' % rec()['groups']['environment']['keyed_on']['gh_version'])
state = j.read_state(p)
print('env_recheck_at set=%s failed=%s' % (bool(state.get('env_recheck_at')), state.get('env_failed_check')))
print('due now=%s' % s.environment_due(state, st, time.time()))
print('status_lines=%s' % s.status_lines(F, st))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "platform stale=false"
e2e_expect_line 'recheck={"check": null, "ok": true, "recorded": true}'
e2e_expect_line "gh_version=gh version 2.200.0 (2026-11-01)"
e2e_expect_line "env_recheck_at set=True failed=None"
e2e_expect_line "due now=False"
e2e_expect_line "status_lines=[]"

_flow_test_begin "staleness: an unchanged environment takes no probe lock and writes no record (SL3)"
fe_new sl-env-unchanged
# Source of the expected values: plan 2.12 (no change: no lock and no write).
e2e_describe "gh and git print the recorded versions while a background process holds F/probes.lock: environment_recheck returns ok at once, the record file is byte for byte the same, and state.json is written"
e2e_repo main
fe_record
fe_bg holder fe_py "$SL_PRE
with ff.factory_lock(F):
    print('locked', flush=True)
    time.sleep(20)"
fe_wait_for 10 'grep -qx locked "$E2E_DIR/bg-holder.out"'
fe_py "$SL_PRE
before = open(os.path.join(F, 'probes.json'), 'rb').read()
t = time.monotonic()
r = s.environment_recheck(F, time.time() + 30)
e = time.monotonic() - t
print('recheck=%s' % json.dumps(r, sort_keys=True))
print('under_1s=%s' % ('yes' if e < 1 else 'no %.2f' % e))
print('record same=%s' % (open(os.path.join(F, 'probes.json'), 'rb').read() == before))
print('env_recheck_at set=%s' % bool(j.read_state(p).get('env_recheck_at')))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line 'recheck={"check": null, "ok": true, "recorded": true}'
e2e_expect_line "under_1s=yes"
e2e_expect_line "record same=True"
e2e_expect_line "env_recheck_at set=True"

_flow_test_begin "staleness: an interpreter other than the recorded one fails the environment re-run (SL4, SL12)"
fe_new sl-interpreter-changed
# Source of the expected values: design phasing L29 (the re-run compares the interpreter's realpath and version); plan 2.6 status line.
e2e_describe "the record's interpreter names a second interpreter, a script that runs fe_python and so answers the recorded version, whose realpath is not the recorded one: environment_recheck is ok false, check interpreter; state.json records the check; status_lines prints the PAUSED probes_failed line and launch_gate refuses every kind with PROBES_STALE=environment"
e2e_repo main
mkdir -p "$E2E_DIR/py2"
printf '#!/bin/sh\nexec %s "$@"\n' "$(fe_python)" > "$E2E_DIR/py2/python3.14"
chmod +x "$E2E_DIR/py2/python3.14"
fe_record "d['interpreter'] = '$E2E_DIR/py2/python3.14'"
fe_py "$SL_PRE
r = s.environment_recheck(F, time.time() + 30)
print('recheck=%s' % json.dumps(r, sort_keys=True))
print('env_failed_check=%s' % j.read_state(p).get('env_failed_check'))
for ln in s.status_lines(F, st):
    print('status=' + ln)
print('gates=%s' % [s.launch_gate(F, k, st) for k in ('worker', 'judge', 'directive')])"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line 'recheck={"check": "interpreter", "ok": false, "recorded": true}'
e2e_expect_line "env_failed_check=interpreter"
e2e_expect_line "status=PAUSED probes_failed=environment check=interpreter next: flow-factory.sh probe --environment (from a terminal when check=signing)"
e2e_expect_line "gates=['PROBES_STALE=environment', 'PROBES_STALE=environment', 'PROBES_STALE=environment']"

_flow_test_begin "staleness: an interpreter whose version moved fails the environment re-run (SL4)"
fe_new sl-interpreter-version
# Source of the expected values: design phasing L29 (the interpreter's realpath or version).
e2e_describe "the record names fe_python but its environment interpreter_version is 3.14.0rc0: ok false, check interpreter"
e2e_repo main
fe_record "d['groups']['environment']['keyed_on']['interpreter_version'] = '3.14.0rc0'"
fe_py "$SL_PRE
print('recheck=%s' % json.dumps(s.environment_recheck(F, time.time() + 30), sort_keys=True))"
e2e_expect_line 'recheck={"check": "interpreter", "ok": false, "recorded": true}'

_flow_test_begin "staleness: a signer that waits for a person fails the environment re-run within its time limit (SL5)"
fe_new sl-signer-hangs
# Source of the expected values: design phasing L29 ("a signed commit that needs a terminal fails the re-run"); plan 2.12 (CALL_TIMEOUT max(1, min(10, left - 2))).
e2e_describe "signing is turned on in the scratch HOME's git config with a signer that waits 60 s; SSH_AUTH_SOCK unset; environment_recheck(F, now + 30) is ok false, check signing, in under 15 s, and CALL_TIMEOUT is None again afterwards. Without the wait the same call is ok"
e2e_repo main
fe_record
cp "$REPO_ROOT/plugins/flow/tests/fixtures/factory/bin/signer" "$E2E_BIN/"
: > "$E2E_BIN/signer-hangs"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
SL_SIGN='os.environ.pop("SSH_AUTH_SOCK", None)
t = time.monotonic()
r = s.environment_recheck(F, time.time() + 30)
e = time.monotonic() - t
print("recheck=%s" % json.dumps(r, sort_keys=True))
print("under_15s=%s" % ("yes" if e < 15 else "no %.2f" % e))
print("call_timeout=%s" % ff.CALL_TIMEOUT["seconds"])'
fe_py "$SL_PRE
$SL_SIGN"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line 'recheck={"check": "signing", "ok": false, "recorded": true}'
e2e_expect_line "under_15s=yes"
e2e_expect_line "call_timeout=None"
rm -f "$E2E_BIN/signer-hangs"
fe_py "$SL_PRE
$SL_SIGN"
e2e_expect_line 'recheck={"check": null, "ok": true, "recorded": true}'

_flow_test_begin "staleness: a probe holding the probe lock does not block the engine lock (SL6, R19)"
fe_new sl-probe-lock
# Source of the expected values: plan 2.5 ("Probe lock": probes take F/probes.lock, the engine F/.lock).
e2e_describe "a background process holds factory_lock(F) for 20 s; global_lock(timeout=2) in another process is acquired in under 1 s"
e2e_repo main
fe_record
fe_bg holder fe_py "$SL_PRE
with ff.factory_lock(F):
    print('locked', flush=True)
    time.sleep(20)"
fe_wait_for 10 'grep -qx locked "$E2E_DIR/bg-holder.out"'
fe_py "$SL_PRE
from _flow_factory import Refused
t = time.monotonic()
try:
    with j.global_lock(p, 2):
        print('global acquired')
except Refused as r:
    print('global refused=%s' % r)
e = time.monotonic() - t
print('under_1s=%s' % ('yes' if e < 1 else 'no %.2f' % e))"
e2e_expect_line "global acquired"
e2e_expect_line "under_1s=yes"

_flow_test_begin "staleness: a re-run that cannot take the probe lock in 2 s gives up and writes nothing (SL6, NX13)"
fe_new sl-probe-lock-timeout
# Source of the expected values: plan 2.12 (wait at most min(2, left - 1) s; on a timeout no record, env_recheck_at unchanged, ok from the checks, recorded false).
e2e_describe "the gh stub prints a new version while a background process holds F/probes.lock for 20 s: environment_recheck(F, now + 30) returns in 2-3.5 s with ok true and recorded false; the record keeps the old gh version and state.json has no env_recheck_at. With a deadline 1.5 s away it waits only 0.5 s"
e2e_repo main
fe_record
fe_gh --version 'gh version 2.200.0 (2026-11-01)'
fe_bg holder fe_py "$SL_PRE
with ff.factory_lock(F):
    print('locked', flush=True)
    time.sleep(20)"
fe_wait_for 10 'grep -qx locked "$E2E_DIR/bg-holder.out"'
fe_py "$SL_PRE
for left, lo, hi in ((30, 2, 3.5), (1.5, 0.4, 1.4)):
    t = time.monotonic()
    r = s.environment_recheck(F, time.time() + left)
    e = time.monotonic() - t
    print('left %s recheck=%s' % (left, json.dumps(r, sort_keys=True)))
    print('left %s elapsed_ok=%s' % (left, 'yes' if lo <= e < hi else 'no %.2f' % e))
print('gh_version=%s' % rec()['groups']['environment']['keyed_on']['gh_version'])
print('env_recheck_at=%s' % j.read_state(p).get('env_recheck_at'))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line 'left 30 recheck={"check": null, "ok": true, "recorded": false}'
e2e_expect_line "left 30 elapsed_ok=yes"
e2e_expect_line 'left 1.5 recheck={"check": null, "ok": true, "recorded": false}'
e2e_expect_line "left 1.5 elapsed_ok=yes"
e2e_expect_line "gh_version=gh version 2.101.0 (2026-09-15)"
e2e_expect_line "env_recheck_at=None"

_flow_test_begin "staleness: resume follows P5's five session parts, not its overall result (SL7, amendment A.2)"
fe_new sl-resume-allowed
# Source of the expected values: amendment A.2 (resume depends on session_id, kill, turn_limit, budget_limit, no_block_rerun); probes.json P5 (cost_scope no-go, five go).
e2e_describe "(i) P5 no-go with only cost_scope no-go: resume allowed. (ii) kill no-go: not allowed. (iii) the five go but P5's turn_limit part stamped with an older claude than the group: not allowed. (iv) no P5 entry: not allowed"
e2e_repo main
fe_record "d['probes']['P5']['parts']['cost_scope']['result'] = 'no-go'; d['probes']['P5']['result'] = 'no-go'"
fe_py "$SL_PRE
import copy
r = rec()
print('i=%s' % s.resume_allowed(r))
r2 = copy.deepcopy(r); r2['probes']['P5']['parts']['kill']['result'] = 'no-go'
print('ii=%s' % s.resume_allowed(r2))
r3 = copy.deepcopy(r); r3['probes']['P5']['parts']['turn_limit']['keyed_on']['claude_version'] = '2.1.300 (Claude Code)'
print('iii=%s' % s.resume_allowed(r3))
r4 = copy.deepcopy(r); del r4['probes']['P5']
print('iv=%s' % s.resume_allowed(r4))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "i=True"
e2e_expect_line "ii=False"
e2e_expect_line "iii=False"
e2e_expect_line "iv=False"

_flow_test_begin "staleness: a worker.model other than the recorded model is stale (SL8, amendment B.2)"
fe_new sl-worker-model
# Source of the expected values: amendment B.2; plan 2.6 status line.
e2e_describe "the user setting flow.factory.worker.model is claude-fable-5-2 and the record's platform model claude-opus-5-5: platform_state, read with the engine's own setting reader, is stale with the recorded_model line; with the setting unset it is not stale"
e2e_repo main
fe_record
fe_settings '{"flow":{"factory":{"worker":{"model":"claude-fable-5-2"}}}}'
fe_py "$SL_PRE
r = s.platform_state(F, j.setting)
print('stale=%s' % str(r['stale']).lower())
print('line=%s' % r['line'])
print('worker gate=%s' % s.launch_gate(F, 'worker', j.setting))
r = s.platform_state(F, st)
print('unset stale=%s' % str(r['stale']).lower())"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "stale=true"
e2e_expect_line "line=PAUSED probes_stale=platform recorded_model=claude-opus-5-5 worker_model=claude-fable-5-2 next: flow-factory.sh probe --platform --model claude-fable-5-2"
e2e_expect_line "worker gate=PROBES_STALE=platform"
e2e_expect_line "unset stale=false"

_flow_test_begin "staleness: a stale platform does not stop engine directives (SL9)"
fe_new sl-gate-directive
# Source of the expected values: T:66c's from list lacks prepare, gate and sync; design phasing L27 (engine directives keep running).
e2e_describe "claude --version prints 2.1.326 while the record holds 2.1.325: launch_gate for kind directive is None, for worker PROBES_STALE=platform"
e2e_repo main
fe_worker_says "claude-version=$V326"
fe_record
fe_py "$SL_PRE
print('directive gate=%s' % s.launch_gate(F, 'directive', st))
print('worker gate=%s' % s.launch_gate(F, 'worker', st))
print('status_lines=%s' % s.status_lines(F, st))"
e2e_expect_line "directive gate=None"
e2e_expect_line "worker gate=PROBES_STALE=platform"
e2e_expect_out "PAUSED probes_stale=platform recorded=$V325 current=$V326 next: flow-factory.sh probe --platform"

_flow_test_begin "staleness: the interactive and GitHub-write status lines (SL10)"
fe_new sl-other-lines
# Source of the expected values: design phasing L28, L32; plan 2.6 (the sandbox from groups.github_write.keyed_on.sandbox, else the literal <owner/repo>).
e2e_describe "(i) the interactive group holds claude 2.1.300 and (ii) the GitHub-write group gh 1.9.0 against the stub's 2.101.0: status_lines prints the DEGRADED and REMINDER lines, the REMINDER with the literal <owner/repo>; with the record's sandbox set, the REMINDER names it. A gh minor change prints no REMINDER"
e2e_repo main
fe_record "d['groups']['interactive']['keyed_on']['claude_version'] = '2.1.300 (Claude Code)'
d['groups']['github_write']['keyed_on']['gh_version'] = 'gh version 1.9.0 (2020-01-01)'"
fe_py "$SL_PRE
for ln in s.status_lines(F, st):
    print('status=' + ln)
r = rec()
r['groups']['github_write']['keyed_on']['sandbox'] = 'someone/sandbox'
ff.write_record(os.path.join(F, 'probes.json'), r)
for ln in s.status_lines(F, st):
    print('with sandbox=' + ln)
r['groups']['github_write']['keyed_on']['gh_version'] = 'gh version 2.90.0 (2026-01-01)'
ff.write_record(os.path.join(F, 'probes.json'), r)
print('minor=%s' % [ln for ln in s.status_lines(F, st) if ln.startswith('REMINDER')])"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "status=DEGRADED probes_stale=interactive next: /flow:factory probe"
e2e_expect_line "status=REMINDER probes_stale=github_write next: flow-factory.sh probe --github-write --sandbox <owner/repo> (asks for sandbox approval)"
e2e_expect_line "with sandbox=REMINDER probes_stale=github_write next: flow-factory.sh probe --github-write --sandbox someone/sandbox (asks for sandbox approval)"
e2e_expect_line "minor=[]"

_flow_test_begin "staleness: the environment re-run is due once per syncIntervalSeconds (SL11)"
fe_new sl-env-due
# Source of the expected values: design phasing L29 (at most once per syncIntervalSeconds); plan 2.13 (default 60).
e2e_describe "never run: due. Run 30 s ago with the default 60: not due. Run 61 s ago: due. With syncIntervalSeconds 0: due at once"
e2e_repo main
fe_py "$SL_PRE
from datetime import datetime, timezone
now = time.time()
def at(ago):
    return datetime.fromtimestamp(now - ago, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
print('never=%s' % s.environment_due({'env_recheck_at': None}, st, now))
print('30s=%s' % s.environment_due({'env_recheck_at': at(30)}, j.setting, now))
print('61s=%s' % s.environment_due({'env_recheck_at': at(61)}, j.setting, now))
SETTINGS['flow.factory.syncIntervalSeconds'] = 0
print('zero=%s' % s.environment_due({'env_recheck_at': at(0)}, st, now + 1))"
e2e_expect_equal "0" "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "never=True"
e2e_expect_line "30s=False"
e2e_expect_line "61s=True"
e2e_expect_line "zero=True"
