"""The factory's state-table evaluator: the fact registry, the effect registry,
the row choice for one (state, event), applying the winning row to a job, and
the replay check rebuild uses.

The table is the plugin's own references/factory-transitions.json and nothing
else; this module keeps no copy of it. The logic follows the rules the table
states as data (conventions, rules, pass_first, fact_dependencies) the way the
design's checker reads them, reimplemented here because an installed plugin
does not ship the checker.

Facts. Every fact of the table has a provider:
  built    computed in phase 1a or 1b, through the callables the caller passes
           in Context.built; the job.json facts (and the four 1b facts
           computed from the job and the settings) fall back to the job
           itself
  derived  blocking_write_confirm and prepush_protected_failed, which choose()
           sets from their inputs (Context.confirm_writes and, under a seam,
           the pre-push input); no provider computes them
  unbuilt  a later phase computes it; outside a registered seam, a (state,
           event) pair that reads one is not evaluated (Blocked), so the
           engine never moves a job on a guessed value
The pseudo-fact creation_allowed stands for creation row 1's conditions; it
is built in 1b and read from Context.built.

Effects. Every effect string of every row, and of the creation row, is
classified as handled in 1a (with the name of its handler) or deferred to the
phase that builds it. A table holding an effect string that is not classified
is refused as table_unreadable, so a table edit cannot add an effect nothing
handles. apply() runs the handlers that only change job.json fields, puts
the 1b fields they set into the transition line's fields object, and returns
the others for the caller to run.

The seam registers inputs for unbuilt facts, for the pre-push derived input
and for two built facts, plus outcomes of directive and judge bodies a later
phase builds. It never supplies a built fact or the confirm input. Only
the test entry point registers one; nothing in the shipped
engine does, and no file, variable or setting turns it on.
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

import copy
import json
import re
from collections import namedtuple

from _flow_factory import Refused, utc_now

TABLE_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "references", "factory-transitions.json")

BWC = "blocking_write_confirm"
PPF = "prepush_protected_failed"
DERIVED = (BWC, PPF)
CREATION_FACT = "creation_allowed"
COMPUTED = ("resume_state", "blocked_stage")
PHASES = ("1b", "1c", "1d", "1e", "1f", "1g", "2")
TABLE_KEYS = ("rows", "facts", "events", "states", "event_order", "pass_first", "rules",
              "fact_dependencies", "creation", "conventions")


class TransitionRefused(Exception):
    """A move outside the table: .line is the TRANSITION_REFUSED line (exit 3)."""

    def __init__(self, line):
        Exception.__init__(self, line)
        self.line = line


class SeamRefused(Exception):
    """A seam input naming a fact that no unbuilt provider has: .line is
    SEAM_REFUSED=<fact> provider=<built|derived|unknown_key> (exit 2)."""

    def __init__(self, fact, kind):
        self.line = "SEAM_REFUSED=%s provider=%s" % (fact, kind)
        Exception.__init__(self, self.line)


class FactUnavailable(Exception):
    """A built fact the pair reads has no input: the caller passed no callable
    for it, or the callable did not return a bool. A caller bug, never a value
    to guess."""


# ---------------------------------------------------------------- decisions

class Winner(object):
    """The row that applies, with the facts it was chosen on. to is the row's
    own "to" (a state, or resume_state or blocked_stage, which apply resolves);
    None for a stay row."""

    def __init__(self, row, state, event, facts):
        self.row = row["id"]
        self.state = state
        self.event = event
        self.facts = dict(facts)
        self.stay = bool(row.get("stay"))
        self.to = None if self.stay else row.get("to")
        self.effects = list(row.get("effects", []))
        self.records = copy.deepcopy(row.get("records", {}))
        self.writes = writes_for(row, state) if state is not None else []
        self.precedence = row.get("precedence")


class NoMove(object):
    """No row matched, and the event's no_move_ok entry (.entry) lets the job
    stay."""

    def __init__(self, entry):
        self.entry = entry


class Blocked(object):
    """The pair reads a fact (.fact) that no 1a or 1b provider computes, built in
    phase .phase. .missing is True when a seam is registered but gives no
    value for it."""

    def __init__(self, fact, phase, missing=False):
        self.fact = fact
        self.phase = phase
        self.missing = missing


class Refusal(object):
    """The table refuses the event: .line is the EVENT_REFUSED or
    TRANSITION_REFUSED line (exit 3). Named Refusal, not Refused, because
    Refused is the FACTORY_REFUSED exception every engine module imports."""

    def __init__(self, line):
        self.line = line


# ---------------------------------------------------------------- facts

Provider = namedtuple("Provider", "kind phase compute")


def _round_limit_reached(job):
    r, lim = job.get("round"), job.get("round_limit")
    return r is not None and lim is not None and r >= lim


# The facts whose 1a value is a job.json field. The caller may still pass a
# callable for each in Context.built, which then wins.
_FROM_JOB = {
    "attempts_exhausted": lambda job: (job.get("attempt") or 0) >= 2,
    "build_started": lambda job: job.get("build_started") is True,
    "blocked_before_spec": lambda job: job.get("blocked_stage") in ("intake", "prepare"),
    "reason_needs_info_exhausted": lambda job: job.get("reason") == "needs_info_exhausted",
    "round_limit_reached": _round_limit_reached,
}

def _issue_changed(ctx, job):
    # T:facts.issue_changed: false while baseline_pending is set or no
    # baseline exists; otherwise issue_digest against baseline_digest.
    if job.get("baseline_pending") is True:
        return False
    base, cur = job.get("baseline_digest"), job.get("issue_digest")
    if not isinstance(base, str) or not isinstance(cur, str):
        return False
    return base != cur


def _max_intake_rounds(ctx):
    v = _setting(ctx, "flow.factory.intake.maxRounds", 3)
    return v if isinstance(v, int) and not isinstance(v, bool) and v >= 1 else 3


def _intake_rounds_exhausted(ctx, job):
    r = job.get("intake_round")
    r = r if isinstance(r, int) and not isinstance(r, bool) else 0
    return r >= _max_intake_rounds(ctx)


def _park_tier_confirm(ctx, job):
    return job.get("state") == "waiting_operator" and job.get("reason") == "tier_confirm"


# The pending intent kinds tied to a head (T:facts.pending_intent_stale: a
# push, or a marker, reply or comment written for the head before a foreign
# push). Markers and replies are outbox comments; push is 1e's kind.
HEAD_BOUND_KINDS = ("push", "comment")


def _pending_intent_stale(ctx, job):
    pi = job.get("pending_intent")
    changes = job.get("pending_changes")
    return (isinstance(pi, dict) and pi.get("kind") in HEAD_BOUND_KINDS
            and isinstance(changes, list) and "foreign_head_change" in changes)


# The four 1b facts the table computes from the job and ctx.setting (plan 5.3
# Fact inputs), so they have a value in every Context, rebuild's and
# creation's included. As for _FROM_JOB, a callable in Context.built wins.
_FROM_JOB_1B = {
    "issue_changed": _issue_changed,
    "intake_rounds_exhausted": _intake_rounds_exhausted,
    "park_tier_confirm": _park_tier_confirm,
    "pending_intent_stale": _pending_intent_stale,
}

# The facts computed in 1a by the caller: the staleness check, the kill and
# liveness checks, the slot counts, the job clone checks, the stored event's
# confirmation, and the sync.
_BUILT_BY_CALLER = ("probes_stale", "group_gone", "orphan_group_alive", "slot_free", "slot_available",
                    "tree_dirty", "clone_config_changed", "unvouched_session_action", "pr_exists",
                    "pr_merged_by_person", "pr_closed_by_person", "foreign_head_change")

# The 1b facts read only from a callable in Context.built (plan 5.3 Fact
# inputs): next's JobPass.built() gives one in every decision, raising its
# own FactFailed when the input is missing; creation's Context gives
# creation_allowed. Without a callable they raise FactUnavailable.
_BUILT_BY_CALLER_1B = ("untrusted_edit", "needs_info_answer", "untrusted_needs_info_answer", "cancel_signal",
                       "untrusted_close", "dependency_open", "via_comment", "retry_by_triage_only",
                       "tier_confirm_blocking", "intent_key_not_confirm", "intent_effect_observed", CREATION_FACT)

# The phase that builds each fact 1a and 1b do not compute.
_UNBUILT = {
    "1c": ("interactive_presence", "held_question", "executor_can_confirm", "failure_needs_person"),
    "1d": ("spec_approval_required", "spec_change_needs_approval", "approval_matches_current",
           "spec_rounds_exhausted"),
    "1e": ("protected_change", "gate_commands_missing", "gate_pass", "diff_risk_needs_approval", "gate_at_head",
           "prelaunch_protected_failed"),
    "1f": ("valid_review_at_head", "ledger_passes", "marker_agreement", "escalated", "unresolved_findings",
           "head_moved"),
    "1g": ("base_moved", "merge_conflict", "conflict_protected", "question_already_answered",
           "resolve_repeat_blocked", "ready_mark_missing", "pending_undo_ready", "trusted_changes_requested",
           "open_questions_remaining", "cost_cap_reached"),
    "2": ("automerge_enabled", "automerge_switch_off", "automerge_tried_at_head", "precheck_passes",
          "checks_pending", "merge_done", "checks_all_success", "check_failed", "approval_valid_at_head",
          "ci_timeout"),
}


def _built_compute(fact):
    def compute(ctx, job):
        fn = ctx.built.get(fact)
        if fn is None:
            if fact in _FROM_JOB:
                return _FROM_JOB[fact](job)
            if fact in _FROM_JOB_1B:
                return _FROM_JOB_1B[fact](ctx, job)
            raise FactUnavailable("no input for built fact %s" % fact)
        value = fn()
        if not isinstance(value, bool):
            raise FactUnavailable("built fact %s gave %r, not a bool" % (fact, value))
        return value
    return compute


def _providers():
    out = {}
    for fact in tuple(_FROM_JOB) + _BUILT_BY_CALLER:
        out[fact] = Provider("built", "1a", _built_compute(fact))
    for fact in tuple(_FROM_JOB_1B) + _BUILT_BY_CALLER_1B:
        out[fact] = Provider("built", "1b", _built_compute(fact))
    out[BWC] = Provider("derived", "1b", None)
    out[PPF] = Provider("derived", "1e", None)
    for phase, facts in _UNBUILT.items():
        for fact in facts:
            if fact in out:
                raise RuntimeError("fact %s has two providers" % fact)
            out[fact] = Provider("unbuilt", phase, None)
    return out


PROVIDERS = _providers()

# The two built facts whose result a seam may supply instead: the
# kill-and-confirm result and the person-confirmation result.
SEAM_BUILT = ("group_gone", "unvouched_session_action")
SEAM_KEYS = ("unbuilt", "default_unbuilt", "derived_inputs", "built_inputs", "bodies")


# ---------------------------------------------------------------- effects

# Handlers that change only job.json fields, run by apply(); every other
# handled effect is returned to the caller in effects_to_run:
#   kill         revoke the lease and kill the stage's process group (a group
#                not confirmed gone goes to orphan_groups)
#   terminal     terminal cleanup: copy the job's refs to the main checkout
#   snapshot     snapshot the job clone's tree to a snapshot ref
#   reset        reset and clean the job clone's tree
#   launch       create the stage's directive and start its launcher
#   no_launch    no directive this pass
#   write_in     write the engine's in/ files (1a writes only job.env)
#   status_line  print the row's status line
#   rebuild      rebuild job.json from events.jsonl (cmd_rebuild's own work)
#   refuse       PERSON_CONFIRM_REQUIRED, printed by the person subcommand
#   create       write the new job.json (creation row 1)
#   noop         the effect states what is not done, or what a later row does
#   records      the row's records, which apply() writes from the row itself
# The 1b job handlers (plan B13 table) read only the job, the decision,
# ctx.now and ctx.sync, do no I/O, and change nothing when ctx.sync is None
# (rebuild, which applies the line's fields instead):
#   intent_clear  pending_intent, held_result and pending_keys to null
#   baseline      set or clear baseline_pending
#   revouch       vouch_at = now; revouched_replies gains ctx.sync["revouch"]
#   pending_keys  pending_keys = ctx.sync["pending_keys"]
# The 1b caller handlers, which B14 runs in next's Job.apply:
#   pr_close      record the PR close intent in the outbox
#   answer        record the answer (answers file, or row 8's comment ids)
#   notice        record a notice comment intent
#   refuse_note   the refusal's status line and status note
#   issue_md      write in-copies/issue.md and baseline_digest from the
#                 persisted issue set
#   intake_record record intake_inputs, risk, surfaces and scope
#   hold_intent   record the pending intent and the held result (row 40)
#   write         record, run or observe the blocking write
#   replay        replay the held result after the release (rows 41, 41e, 41k)
JOB_HANDLERS = ("reason", "build_started", "counter", "round_limit", "attempt_add", "attempt_reset",
                "paused_reason", "relaunch_fresh", "relaunch_resume", "records", "noop",
                "intent_clear", "baseline", "revouch", "pending_keys")
CALLER_HANDLERS = ("kill", "terminal", "snapshot", "reset", "launch", "no_launch", "write_in", "status_line",
                   "rebuild", "refuse", "create",
                   "pr_close", "answer", "notice", "refuse_note", "issue_md", "intake_record", "hold_intent",
                   "write", "replay")

_EFFECT_GROUPS = {
    ('handled', 'kill'): [
        'kill a live worker first',
        'kill a live judge or directive first (approve, merging)',
        'kill a live worker or directive first; the stage relaunches on the new head through launch_due, and no attempt is counted; a judge runs on, because it does not use the worktree',
        'revoke the lease, kill the process group and confirm it gone',
        'revoke the lease and kill the process group; a group that is not confirmed gone is recorded, and row 43g holds the next launch while it lives',
        'revoke the lease and kill the process group first, as rows 43o and 43l do; a group that is not confirmed gone is recorded, and row 43g holds the next launch while it lives',
    ],
    ('handled', 'terminal'): [
        'terminal cleanup',
    ],
    ('handled', 'noop'): [
        'keep a dirty worktree',
        'do not close the PR',
        'keep branch and worktree for reuse',
        'keep resume_state: after approval the job resumes into the recorded stage, which runs on the new head',
        'the job stays: an untrusted edit, an untrusted close or an issue change still needs a retry, or the job has not reached build',
        'keep resume_state and the pending intent: the job resumes into the recorded stage, which runs on the new head, and gate or sync re-gate it',
        'the switch is off, so the job returns through sync to ready for a person',
        'after the confirm the job resumes into ready; the launch is not replayed there',
        'nothing is spent',
        'the stage launches when a slot frees',
        'no engine git command runs in the clone: a merge in progress is not aborted, and the tree is neither snapshotted nor reset',
        'freeze the job: no push; the local commits stay on the job branch and the remote branch is unchanged',
        'after the confirm the job resumes into ready; the expiry is not replayed',
        'after the confirm the job resumes into ready, where a person decides; the failure is named in the ready summary and not replayed',
        'the worker stops; worker_parked follows',
        'gate routes to review (row 22)',
        'gate routes the failing ledger (rows 23c, 23d)',
        'no undo is needed: it already ran',
        'sync re-checks the job, and row 31 marks the PR ready again',
        'the job stays ready for a person to merge',
        'keep branches',
        'the untrusted edit still needs a trusted retry',
        'the issue change still needs a retry',
        'row 66i records the new baseline',
        'keep the result: after the confirm the job resumes into ready, where a person decides; the ready summary names the escalation',
        'after the confirm the job resumes into ready; the tick is not replayed',
        'no baseline_digest yet',
        "the notice says that a reply counts when it names a question id, and that '/flow-factory spec' adds spec input",
    ],
    ('handled', 'reason'): [
        'reason issue_closed_untrusted',
        'reason untrusted_edit',
        'reason issue_changed',
        'reason needs_info_exhausted',
        'reason cost_cap',
        'reason protected',
        'reason orphan_worker',
        'reason tier_confirm',
        'reason prepare_failed',
        'reason attempts_exhausted',
        'reason merge_refused',
        'reason resolve_repeat',
        'reason question',
        'reason gate_commands_missing',
        'reason gate_failed_at_round_limit',
        'reason ledger_failed_at_round_limit',
        'reason escalated',
        'reason findings_at_round_limit',
        'reason protected_conflict',
        'reason conflict_at_round_limit',
        'reason marker_disagreement',
        'reason spec_rounds_exhausted',
        'reason approver_escalated',
        'reason ci_failed_at_round_limit',
        'reason ci_timeout',
    ],
    ('handled', 'counter'): [
        'intake_round += 1',
        'round += 1',
        'spec_round += 1',
        'intake_round = 0',
    ],
    ('handled', 'no_launch'): [
        'do not launch',
        'do not launch: only the outside-session runner launches the approver and the merge; the job waits for it',
    ],
    ('handled', 'status_line'): [
        'status prints the orphan process group',
        'one status and runner.log line',
        "status prints how to restore the clone's .git/config from the prepare copy",
    ],
    ('handled', 'paused_reason'): [
        'set paused_reason=probes_stale',
    ],
    ('handled', 'launch'): [
        'launch the intake judge',
        "launch: a first launch, and a relaunch after rows 39d, 39ld and 52e, are fresh: a new --session-id and the stage's first-launch prompt, and before a fresh launch a dirty worktree is snapshotted to refs/flow-factory/issue-N/snapshot-<k> and reset. A relaunch after rows 39, 39l, 44 and 44r resumes a worker stage with --resume <previous session_id> --fork-session and resume.prompt.md while P5 passes, and only when the stage has a recorded session_id; a stage parked at launch_due by rows 43c, 43p or 43g before its first launch has none and starts fresh on a clean tree. It is fresh under the P5 fallback. A judge has no session to resume and is always started fresh",
        'launch the engine directive',
        'launch the merge directive (auto_merge_phase2 item 5): it first checks whether the PR is already MERGED at H, so a relaunch after row 39l reports merge_done',
    ],
    ('handled', 'write_in'): [
        'write in/ files',
    ],
    ('handled', 'snapshot'): [
        'snapshot the tree to refs/flow-factory/issue-N/snapshot-<k>',
    ],
    ('handled', 'reset'): [
        'reset the tree',
    ],
    ('handled', 'attempt_add'): [
        'attempt += 1',
    ],
    ('handled', 'relaunch_fresh'): [
        "relaunch FRESH: a worker stage gets a new --session-id and the stage's first-launch prompt, never --resume, because the reset removed edits the old session remembers; an engine directive (prepare, gate, sync) starts again from its start",
        'relaunch FRESH: a worker stage gets a new --session-id and the first-launch prompt, never --resume; an engine directive (prepare, gate, sync, merging) starts again from its start',
    ],
    ('handled', 'relaunch_resume'): [
        'relaunch: a worker stage resumes with --resume <previous session_id> --fork-session and resume.prompt.md while P5 passes, and starts fresh under the P5 fallback; a judge or engine directive is started again from its start (judges and directives have no session to resume)',
        'relaunch: a worker stage resumes with --resume <previous session_id> --fork-session and resume.prompt.md while P5 passes, and starts fresh under the P5 fallback; a judge or engine directive is started again from its start',
        "a worker stage relaunches with --resume <session_id> --fork-session and resume.prompt.md while P5 passes and the stage has a recorded session_id, and fresh on a clean tree otherwise: under the P5 fallback, and when the park came from rows 43c, 43p or 43g before the stage's first launch (the answer reaches a fresh session through the questions store); a judge or directive starts again from its start",
        'a worker stage relaunches as row 44 says: --resume only when the stage has a recorded session_id, otherwise fresh on a clean tree',
    ],
    ('handled', 'build_started'): [
        'set build_started',
        'set build_started when resume_state is build',
    ],
    ('handled', 'records'): [
        "resume_state = the state the stage's own row would have entered",
    ],
    ('handled', 'round_limit'): [
        'round_limit = round + maxRounds',
    ],
    ('handled', 'attempt_reset'): [
        'fresh attempts (attempt = 0)',
        'fresh attempts',
    ],
    ('handled', 'rebuild'): [
        'rebuild job.json from events.jsonl, the branch and GitHub',
        'keep a .bak',
        "record a 'rebuilt' event",
    ],
    ('handled', 'refuse'): [
        'refuse with PERSON_CONFIRM_REQUIRED; nothing changes',
        "run the subcommand in a terminal outside any Claude session, post a trusted comment, or, in a session in default permission mode, answer tier-gate's ask",
        "run the subcommand in a terminal outside any Claude session (it has no comment form), or, in a session in default permission mode, answer tier-gate's ask",
    ],
    ('handled', 'create'): [
        'set vouch_at = the label event time',
        'write job.json',
    ],
    ('handled', 'pr_close'): [
        'close a factory PR through the outbox',
        'close any PR through the outbox',
    ],
    ('handled', 'intent_clear'): [
        'drop the pending intent',
        'from waiting_operator: drop the pending intent and clear pending_keys',
        'drop the pending intent: it was written for the head before the push',
        'clear pending_keys',
    ],
    ('handled', 'baseline'): [
        'set baseline_pending',
        'when the target is intake: set baseline_pending',
        'clear baseline_pending',
    ],
    ('handled', 'answer'): [
        'record the answer comment ids in events.jsonl; they are already in the spec-input set',
        "record the answer in the job's answers file, which is in the spec-input set",
        'record the answer',
    ],
    ('handled', 'notice'): [
        'post a notice that a trusted /flow-factory retry is needed before the reply counts',
        'post the intake notice',
        'post the reject notice',
        'post the needs-info notice with the factory marker and question ids NI-<k>',
    ],
    ('handled', 'revouch'): [
        're-vouch: untrusted needs-info answers now count',
        're-vouch',
        're-vouch: vouch_at = now',
    ],
    ('handled', 'refuse_note'): [
        'refuse: a retry from triage access only re-vouches a needs-info reply from someone without write access, and none waits; this park needs a needs-info answer or a retry from write access or higher',
        'refuse: a retry from triage access only re-vouches text from someone without write access; this park needs a retry from write access or higher',
        'refuse: a tier_confirm park has no intent; change the key or start an interactive executor that can confirm',
        'refuse to resume: the issue is closed; reopen it and retry, or cancel',
        'refuse: the issue is closed; reopen it and retry, or cancel',
        'refuse: the untrusted edit needs a trusted retry first',
        'refuse: the issue change needs a retry first',
    ],
    ('handled', 'pending_keys'): [
        'record pending_keys',
    ],
    ('handled', 'issue_md'): [
        'write in/issue.md from the spec-input set',
        'set baseline_digest = issue_digest (the only place baseline_digest is written)',
    ],
    ('handled', 'intake_record'): [
        'record intake_inputs (its only writer), risk, surfaces and scope',
    ],
    ('handled', 'hold_intent'): [
        'record pending_intent and the held stage result',
    ],
    ('handled', 'write'): [
        'assignment and label written',
        'run exactly the stored literal with the real binary',
        'record the effect',
        'record the observed effect',
        'the engine runs the write',
    ],
    ('handled', 'replay'): [
        'replay the held stage result or event',
    ],
    ('deferred', '1c'): [
        "emit 'confirm <intent>' only to an executor that can confirm (executor_can_confirm)",
        "emit 'confirm <intent>' only to an interactive executor that can confirm (executor_can_confirm); otherwise list it for a terminal confirm",
        "an interactive executor that can confirm (default permission mode) asks for each confirm-tier write in the session, through tier-gate's always-ask on 'flow-factory.sh confirm <intent>'",
        "the interactive executor that can confirm (default permission mode) asks for each write through tier-gate's always-ask on 'flow-factory.sh confirm <intent>'",
        'prepare: before it reuses a job clone (row 50, and the paths into prepare after rows 44c, 44d, 51 and 51b), snapshot a dirty worktree to refs/flow-factory/issue-N/snapshot-<k> and reset it, as before a fresh worker launch; then fetch and fast-forward the reused branch to the PR head when a PR exists',
        'branch, goal id, worktree, ignore rules, io directory and job.env written',
        're-bootstrap on rerunOn',
        'set the blocked question ids',
        'mark the question held',
        "emit 'ask <qid>' to the interactive executor",
        'suspend the stage timeout up to askHoldSeconds',
        'await prints PARK',
        'store the answer with flow-question.sh answer --journal',
        'await prints ANSWERED; the worker continues in the same context',
        'refuse: no held question with that id',
        'wait for the remaining questions',
    ],
    ('deferred', '1d'): [
        'recompute spec_hash at the new head; an approval must name the new spec_hash (row 15s refuses an old one)',
        'post a new spec-approval notice with the factory marker and the new spec_hash; a /flow-factory approve-spec comment posted before it no longer counts, and one must name the new hash',
        'record spec_commit and spec_hash',
        'post the spec-approval notice',
        'record the new spec_hash',
        'when spec_hash changed with no approval required: record the new hash and set spec_changed_unapproved',
        'record goal_freeze',
        'record the approval with its channel',
        'refuse: the approval names an old spec_hash or, when resume_state is gate, a head that is not the current H; approve-spec carries --head <sha> for a gate-origin approval in every form',
        'pass the change request to the spec worker',
    ],
    ('deferred', '1e'): [
        'push',
        'create the draft PR (prCreate) or edit its body (issueUpdate)',
        'record the PR number and head',
        'invalidate the gate record',
        'before the push: the protected and config-loading check (rules.push_check); on a violation row 21f applies instead and nothing is pushed',
        'a held push runs only after the protected and config-loading check passes (rules.push_check); on a violation the held push is not run, the job resumes into the recorded stage, and the replayed stage result meets row 21f',
        'post the approval notice with the diff summary',
        'record the gate result for H',
        'the gate record at H is reused; gate routes the failing ledger (rows 23c, 23d)',
        'no review carry-over',
        'carry the review when the carry-over rule holds',
        're-run the gate at HEAD',
    ],
    ('deferred', '1f'): [
        "from review, rework or resolve: the stage's writes are made first, as for the stage's own row (stages)",
        'write review-context.env and pr-feedback.md',
        'record the markers with head_end == HEAD',
        'record the markers',
        'post the resolution marker and replies to trusted ids',
        'list the foreign markers',
    ],
    ('deferred', '1g'): [
        'record merged_by and the merge SHA',
        'record the undo of ready as pending_intent and keep the event for replay after the confirm',
        'keep the event for replay after the undo of ready is confirmed (rows 41, 41k), or after a person runs it (row 41e)',
        'the PR stays marked ready until then, because the undo is the write that waits',
        'undo ready when leaving ready, approve, merging or waiting_ci',
        'undo ready when leaving approve or merging',
        'undo ready when leaving approve',
        'undo ready when leaving merging',
        'abort any merge',
        'before the branch moves, snapshot the old branch tip and a dirty worktree to refs/flow-factory/issue-N/snapshot-<k>, so commits the new head does not contain (such as unpushed build or rework commits) and uncommitted edits are kept',
        'fetch and move the worktree branch to the new PR head',
        'record the foreign head',
        'before the branch moves, snapshot the old branch tip and a dirty worktree to refs/flow-factory/issue-N/snapshot-<k>, so commits the new head does not contain (such as unpushed build or rework commits) and uncommitted edits are kept; fetch and move the worktree branch to the new PR head',
        'before the branch moves, snapshot the old branch tip and a dirty worktree to refs/flow-factory/issue-N/snapshot-<k>; fetch and move the worktree branch to the foreign head',
        'from resolve: abort the merge, restore HEAD, record conflict_base_sha and the answered-question ids (row 35 entry steps)',
        'from resolve: abort the merge, restore HEAD, record conflict_base_sha (row 35 entry steps)',
        'from resolve: the reset removed the merge in progress, so the engine redoes the base merge (stages item 10, step 1) and writes in/conflict-answers.md before the relaunch',
        'gh pr ready --undo and remove the flow:ready label',
        'record the undo of ready as pending_intent',
        'from approve: undo ready (a key that is confirm and unconfirmed for that undo parks through row 40l instead)',
        'abort the merge',
        'abort the merge and restore HEAD',
        'record conflict_base_sha',
        'leave the merge in progress',
        'write in/conflict-answers.md',
        'commit and push the merge',
        'gh pr ready and the flow:ready label',
        'post the ready summary',
        'the review text goes into pr-feedback.md',
        'record the undo as pending_intent and keep the request for replay',
        'the comment text goes into pr-feedback.md',
        'the text goes into pr-feedback.md',
        'record the undo as pending_intent and keep the feedback for replay',
        'the feedback goes into pr-feedback.md',
        'record the undo as pending_intent',
        'after a park from ready, approve, merging or waiting_ci the job resumes into ready with the PR no longer marked ready; a held github_change, person_rework or person_feedback is replayed there with the confirmation it had when it arrived, and a held launch, stage result, judge result, lease expiry or tick is not; if nothing moves the job, row 36u sends it to sync',
        'refuse to resume: resolve by hand and push (row 52h), feedback, reject or cancel',
        'blocked_stage sync: redo the merge and give the resolve worker in/conflict-answers.md',
        'refuse: reason resolve_repeat and the base has not moved past conflict_base_sha',
        'pass the feedback to the spec worker',
        'pass the feedback to the build worker',
        'refuse: intake has not accepted the current issue, or prepare has not finished; use retry',
    ],
    ('deferred', '2'): [
        'from merging: the pending intent is the undo of ready that row 65 needs',
        'phase 2',
        'write the approve-entry record for H, so automerge_tried_at_head is true at this head from now on',
        'record the failed pre-check for this head',
        'post a notice naming the failed items',
        'write approve-<H>.json',
        'post the policy comment',
        'approval not carried to the new head',
        'write the approve-entry record for the new head, so automerge_tried_at_head is true at it from now on',
    ],
}


def _effects():
    out = {}
    for cls, strings in _EFFECT_GROUPS.items():
        kind, name = cls
        if kind == "handled" and name not in JOB_HANDLERS + CALLER_HANDLERS:
            raise RuntimeError("unknown handler %s" % name)
        if kind == "deferred" and name not in PHASES:
            raise RuntimeError("unknown phase %s" % name)
        for s in strings:
            if s in out:
                raise RuntimeError("effect classified twice: %s" % s)
            out[s] = cls
    return out


EFFECTS = _effects()


# ---------------------------------------------------------------- the table

class Table(object):
    """The loaded table: .data is the JSON, .rows the rows in file order,
    .by_id the rows by id."""

    def __init__(self, data):
        self.data = data
        self.rows = data["rows"]
        self.by_id = dict((r["id"], r) for r in self.rows)
        self.facts = data["facts"]
        self.events = data["events"]
        self.states = data["states"]
        self.rules = data["rules"]
        self.pass_first = data["pass_first"]
        self.creation = data["creation"]
        self._pairs = {}
        for r in self.rows:
            for s in r["from"]:
                self._pairs.setdefault((s, r["event"]), []).append(r)
        self._as_if = dict(((x["row"], x["key"]), x["fact"]) for x in self.rules.get("records_as_if", []))
        self._reads = {}

    def rows_for(self, state, event):
        """The rows whose from holds state and whose event is event, in file order."""
        return list(self._pairs.get((state, event), []))

    def kind(self, state):
        return self.states.get(state, {}).get("kind")


def _bool_map(m):
    return isinstance(m, dict) and all(isinstance(k, str) and isinstance(v, bool) for k, v in m.items())


def table_problems(d):
    """Why the table cannot be used, as a list of lines; empty when it can."""
    if not isinstance(d, dict):
        return ["the table is not an object"]
    out = ["missing or malformed %s" % k for k in TABLE_KEYS
           if not isinstance(d.get(k), list if k in ("rows", "event_order", "fact_dependencies", "creation") else dict)]
    if out:
        return out
    states, events, facts = d["states"], d["events"], d["facts"]
    for f in facts:
        if f not in PROVIDERS:
            out.append("fact %s has no provider" % f)
    seen = set()
    for i, r in enumerate(d["rows"] + d["creation"]):
        rid = r.get("id") if isinstance(r, dict) else None
        where = "row %s" % (rid if isinstance(rid, str) else "#%d" % i)
        if not isinstance(rid, str):
            out.append(where + " has no id")
            continue
        if rid in seen:
            out.append(where + " is listed twice")
        seen.add(rid)
        effects = r.get("effects")
        if not isinstance(effects, list) or not all(isinstance(e, str) for e in effects):
            out.append(where + " has no effects list")
            effects = []
        for e in effects:
            if e not in EFFECTS:
                out.append("%s effect not classified: %s" % (where, e))
        if i >= len(d["rows"]):
            continue
        frm = r.get("from")
        if not isinstance(frm, list) or not frm or any(s not in states for s in frm):
            out.append(where + " has a from list naming no known state")
        if r.get("event") not in events:
            out.append(where + " names an unknown event")
        p = r.get("precedence")
        if not isinstance(p, int) or isinstance(p, bool):
            out.append(where + " has no integer precedence")
        g = r.get("guard", {})
        if not _bool_map(g) or any(f not in facts for f in g):
            out.append(where + " has a guard naming an unknown fact or a value that is not a bool")
        if not r.get("stay"):
            to = r.get("to")
            if to in COMPUTED:
                if not isinstance(r.get("resume"), list) or not (r.get("resume_from") == "*"
                                                                  or isinstance(r.get("resume_from"), list)):
                    out.append(where + " moves to a computed target without resume and resume_from")
            elif to not in states:
                out.append(where + " moves to an unknown state")
        w = r.get("writes")
        if w is not None and not isinstance(w, (list, dict)):
            out.append(where + " has writes that are neither a list nor a map")
        rec = r.get("records", {})
        if not isinstance(rec, dict) or any(k not in COMPUTED for k in rec):
            out.append(where + " records a key other than resume_state or blocked_stage")
    for name, e in events.items():
        if not isinstance(e, dict) or not isinstance(e.get("occurs_in", []), list):
            out.append("event %s has no occurs_in list" % name)
    rules = d["rules"]
    pc, bw = rules.get("push_check"), rules.get("blocking_write")
    if not isinstance(pc, dict) or pc.get("fact") != PPF or not isinstance(pc.get("write"), str):
        out.append("rules.push_check is not the pre-push check on %s" % PPF)
    if not isinstance(bw, dict) or bw.get("fact") != BWC:
        out.append("rules.blocking_write is not the confirm park on %s" % BWC)
    for x in rules.get("records_as_if", []):
        if not isinstance(x, dict) or x.get("fact") not in facts or x.get("key") not in COMPUTED:
            out.append("rules.records_as_if has an entry naming no fact or key")
    return out


def load_table(path=None):
    """The table at path, by default the plugin's own
    references/factory-transitions.json. A missing, unparsable or unusable
    table raises Refused("table_unreadable"); the exception's .problems lists
    why, when the JSON parsed."""
    try:
        with open(path or TABLE_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        raise Refused("table_unreadable")
    problems = table_problems(data)
    if problems:
        e = Refused("table_unreadable")
        e.problems = problems
        raise e
    return Table(data)


def writes_for(row, state):
    """The blocking writes a row makes from state: its writes list, or the
    entry for state (else "default") of a per-from-state map; [] for none."""
    w = row.get("writes")
    if w is None:
        return []
    if isinstance(w, dict):
        return list(w.get(state, w.get("default", [])) or [])
    return list(w)


def _deps_for(table, state):
    return [dep for dep in table.data.get("fact_dependencies", []) if dep.get("states") is None
            or state in dep["states"]]


def _closure(facts, deps):
    # As the docs checker closes a pair's facts: a dependency with a
    # non-empty "if" that shares a fact with the set brings in all its facts.
    facts = set(facts)
    changed = True
    while changed:
        changed = False
        for dep in deps:
            fs = set(dep["if"]) | set(dep["then"])
            if dep["if"] and (fs & facts) and not fs <= facts:
                facts |= fs
                changed = True
    return facts


def facts_read(table, state, event):
    """The facts a (state, event) pair reads: the guard facts of its rows, the
    "when" facts of its no_move_ok entries and, for the pass_first event, the
    pass_first "when" facts, closed under fact_dependencies. The derived facts
    are left out: choose() sets them."""
    key = (state, event)
    if key not in table._reads:
        facts = set()
        for r in table.rows_for(state, event):
            facts.update(r.get("guard", {}))
        for nm in table.events.get(event, {}).get("no_move_ok", []):
            if state in nm.get("states", []):
                facts.update(nm.get("when", {}))
        if table.pass_first.get("event") == event:
            facts.update(table.pass_first.get("when", {}))
        table._reads[key] = frozenset(_closure(facts, _deps_for(table, state)) - set(DERIVED))
    return table._reads[key]


def winners(table, state, event, facts):
    """The matching rows with the lowest precedence number (one row, or a
    tie). A row matches when every fact of its guard has that value in facts;
    a fact missing from facts matches nothing."""
    match = [r for r in table.rows_for(state, event)
             if all(facts.get(f) is v for f, v in r.get("guard", {}).items())]
    if not match:
        return []
    best = min(r["precedence"] for r in match)
    return [r for r in match if r["precedence"] == best]


# ---------------------------------------------------------------- the seam

_seam = None


def set_seam(seam):
    """Register (a dict) or clear (None) the seam inputs."""
    global _seam
    if seam is None:
        _seam = None
        return
    if not isinstance(seam, dict):
        raise ValueError("the seam is not an object")
    for k in seam:
        if k not in SEAM_KEYS:
            raise ValueError("unknown seam key %s" % k)
    unbuilt = seam.get("unbuilt", {})
    if not isinstance(unbuilt, dict) or not all(_bool_map(m) for m in unbuilt.values()):
        raise ValueError("seam unbuilt is not {job key or *: {fact: bool}}")
    for m in unbuilt.values():
        for fact in m:
            p = PROVIDERS.get(fact)
            if p is None:
                raise SeamRefused(fact, "unknown_key")
            if p.kind != "unbuilt":
                raise SeamRefused(fact, p.kind)
    if "default_unbuilt" in seam and not isinstance(seam["default_unbuilt"], bool):
        raise ValueError("seam default_unbuilt is not a bool")
    built = seam.get("built_inputs", {})
    if not _bool_map(built):
        raise ValueError("seam built_inputs is not {fact: bool}")
    for fact in built:
        if fact not in SEAM_BUILT:
            p = PROVIDERS.get(fact)
            raise SeamRefused(fact, "unknown_key" if p is None else p.kind)
    derived = seam.get("derived_inputs", {})
    if isinstance(derived, dict) and "confirm_keys" in derived:
        # The confirm input comes from the tier resolver through
        # Context.confirm_writes; a seam value would skip it (plan B13 step 3).
        raise SeamRefused(BWC, "derived")
    if not isinstance(derived, dict) or any(k != "prepush_fails" for k in derived) \
            or not isinstance(derived.get("prepush_fails", False), bool):
        raise ValueError("seam derived_inputs is not {prepush_fails: bool}")
    bodies = seam.get("bodies", {})
    if not isinstance(bodies, dict) or not all(isinstance(v, str) for v in bodies.values()):
        raise ValueError("seam bodies is not {kind:stage: outcome}")
    if "judge:intake" in bodies:
        # The intake judge is launched for real in 1b (plan B14 step 11); a
        # seam body would skip the launch and the judge's reply.
        raise SeamRefused("bodies:judge:intake", "built")
    _seam = copy.deepcopy(seam)


def current_seam():
    """The registered seam inputs, or None (always None in the shipped engine)."""
    return _seam


def _seam_unbuilt(seam, key, fact):
    unbuilt = seam.get("unbuilt", {})
    for k in (key, "*"):
        if fact in unbuilt.get(k, {}):
            return unbuilt[k][fact]
    return seam.get("default_unbuilt")


# ---------------------------------------------------------------- choose

class Context(object):
    """What the caller gives choose() and apply():
    built     {fact: callable returning bool} for the built facts
    setting   setting(key, default) -> value; by default _flow_factory_jobs.setting
    pass_id, channel, caller, now   written into the transition line
    confirm_writes  confirm_writes(writes) -> [tier key]: the keys of the
              winner's blocking writes that resolve to confirm with no
              confirmation; choose() sets blocking_write_confirm when it is
              not empty
    sync      the pass's values for the 1b job handlers, a dict in every
              decision next makes (pending_keys, and revouch, answers and
              untrusted_replies when the job's sync completed); None only in
              rebuild and creation, where every 1b job handler does nothing.
              Kept by reference: the tier callable writes pending_keys into it
    args, facts, result   the pending record's args and facts, and the parsed
              result file of a stage or judge result; read by caller
              handlers only"""

    def __init__(self, built=None, setting=None, pass_id=None, channel=None, caller=None, now=None,
                 confirm_writes=None, sync=None, args=None, facts=None, result=None):
        self.built = dict(built or {})
        self.setting = setting
        self.pass_id = pass_id
        self.channel = channel
        self.caller = caller
        self.now = now
        self.confirm_writes = confirm_writes
        self.sync = sync
        self.args = args
        self.facts = facts
        self.result = result

    @property
    def seam(self):
        return _seam


def _decide(table, state, event, facts):
    top = winners(table, state, event, facts)
    if len(top) == 1:
        return Winner(top[0], state, event, facts)
    if len(top) > 1:
        return Refusal("TRANSITION_REFUSED=%s->?: rows %s tie for event %s"
                       % (state, ",".join(sorted(r["id"] for r in top)), event))
    for nm in table.events.get(event, {}).get("no_move_ok", []):
        if state in nm.get("states", []) and all(facts.get(f) is v for f, v in nm.get("when", {}).items()):
            return NoMove(nm)
    return Refusal("TRANSITION_REFUSED=%s->?: no row wins for event %s" % (state, event))


def choose(table, job, event, ctx):
    """The decision for event on job: Winner, NoMove, Blocked or Refusal.

    1. An event outside its occurs_in list for the job's state is refused.
    2. With no seam, a pair that reads an unbuilt fact is Blocked on the first
       one in sorted order.
    3. The facts are computed, and the rows evaluated with both derived facts
       false.
    4. When that winner's writes from this state include the push
       (rules.push_check): with no seam it is Blocked on the pre-push input
       (1e); under a seam whose prepush_fails is true,
       prepush_protected_failed is set and the rows evaluated again. The
       pre-push check comes first, so a push it refuses is never parked as a
       push intent. Then, for a winner that still has writes,
       ctx.confirm_writes(writes) gives the keys that resolve to confirm with
       no confirmation; when it is not empty, blocking_write_confirm is set
       and the rows evaluated again (rules.blocking_write). This holds with
       or without a seam; a missing confirm_writes, or one that does not
       return a list of strings, raises FactUnavailable.
    5. The lowest precedence wins; a tie, or no row with no agreeing
       no_move_ok entry, is refused."""
    state = job["state"]
    ev = table.events.get(event)
    if ev is None or state not in ev.get("occurs_in", []):
        return Refusal("EVENT_REFUSED=%s state=%s" % (event, state))
    seam = _seam
    reads = sorted(facts_read(table, state, event))
    if seam is None:
        for f in reads:
            if PROVIDERS[f].kind == "unbuilt":
                return Blocked(f, PROVIDERS[f].phase)
    facts = {}
    for f in reads:
        p = PROVIDERS[f]
        if p.kind == "unbuilt":
            v = _seam_unbuilt(seam, job.get("key"), f)
            if v is None:
                return Blocked(f, p.phase, missing=True)
        elif seam is not None and f in seam.get("built_inputs", {}):
            v = seam["built_inputs"][f]
        else:
            v = p.compute(ctx, job)
        facts[f] = v
    facts[BWC] = False
    facts[PPF] = False
    d = _decide(table, state, event, facts)
    if not isinstance(d, Winner) or not d.writes:
        return d
    push = table.rules["push_check"]["write"]
    if push in d.writes:
        if seam is None:
            return Blocked(PPF, PROVIDERS[PPF].phase)
        # Under a seam, a pre-push input it does not give means the check passes.
        if seam.get("derived_inputs", {}).get("prepush_fails", False):
            facts[PPF] = True
            return _decide(table, state, event, facts)
    if ctx.confirm_writes is None:
        raise FactUnavailable("no confirm_writes for the writes of row %s" % d.row)
    keys = ctx.confirm_writes(list(d.writes))
    if not isinstance(keys, list) or not all(isinstance(k, str) for k in keys):
        raise FactUnavailable("confirm_writes gave %r, not a list of tier keys" % (keys,))
    if keys:
        facts[BWC] = True
        return _decide(table, state, event, facts)
    return d


def choose_creation(table, key, ctx):
    """The decision for creation row 1 for a new job key: Winner when
    creation_allowed holds, NoMove when it does not, with or without a seam.
    creation_allowed is built: its callable in ctx.built computes it, and a
    Context without one raises FactUnavailable (a caller defect)."""
    v = PROVIDERS[CREATION_FACT].compute(ctx, None)
    if not v:
        return NoMove({"states": [], "when": {CREATION_FACT: False}, "reason": "creation conditions do not hold"})
    return Winner(table.creation[0], None, table.creation[0]["event"], {CREATION_FACT: True})


# ---------------------------------------------------------------- apply

def _recorded_values(table, row, key):
    out = set()
    m = row.get("records", {}).get(key)
    if m is None:
        return out
    for fs in row["from"]:
        v = m.get(fs, m.get("default")) if isinstance(m, dict) else m
        if v is None:
            continue
        for x in (v if isinstance(v, list) else [v]):
            out.add(fs if x == "$from" else x)
    return out


def recordable(table, row):
    """The targets a computed-target row may move to: its resume list, kept
    to the values the parking rows it names (resume_from; "*" for every row
    entering the parked state) record."""
    key, parked = row["to"], row["from"][0]
    rf = row.get("resume_from")
    if rf == "*":
        srcs = [x for x in table.rows if x.get("to") == parked and not x.get("stay") and key in x.get("records", {})]
    else:
        srcs = [table.by_id[i] for i in rf if i in table.by_id]
    values = set()
    for x in srcs:
        values |= _recorded_values(table, x, key)
    return set(row.get("resume", [])) & values


def _setting(ctx, key, default):
    if ctx.setting is not None:
        return ctx.setting(key, default)
    import _flow_factory_jobs
    return _flow_factory_jobs.setting(key, default)


_COUNTER = re.compile(r"^([a-z_]+) (\+= 1|= 0)$")


def _run_job_handler(name, effect, new, old, decision, ctx, fields=None, target=None, now=None):
    if name == "reason":
        new["reason"] = effect[len("reason "):]
    elif name == "build_started":
        if effect == "set build_started" or old.get("resume_state") == "build":
            new["build_started"] = True
    elif name == "counter":
        field, op = _COUNTER.match(effect).groups()
        new[field] = (new.get(field) or 0) + 1 if op == "+= 1" else 0
    elif name == "round_limit":
        new["round_limit"] = (new.get("round") or 0) + int(_setting(ctx, "flow.factory.maxRounds", 3))
    elif name == "attempt_add":
        new["attempt"] = (new.get("attempt") or 0) + 1
    elif name == "attempt_reset":
        new["attempt"] = 0
    elif name == "paused_reason":
        new["paused_reason"] = effect.split("=", 1)[1]
    elif name in ("relaunch_fresh", "relaunch_resume"):
        new["relaunch"] = {"cause_row": decision.row, "mode": "fresh" if name == "relaunch_fresh" else "resume"}
    elif name in _1B_JOB_HANDLERS:
        # In rebuild ctx.sync is None: the line's fields carry the values.
        if getattr(ctx, "sync", None) is None:
            return
        _1B_JOB_HANDLERS[name](effect, new, old, decision, ctx, fields if fields is not None else {}, target, now)


def _set(new, fields, field, value):
    new[field] = copy.deepcopy(value)
    fields[field] = copy.deepcopy(value)


def _intent_clear(effect, new, old, decision, ctx, fields, target, now):
    if effect.startswith("from waiting_operator:") and getattr(decision, "state", None) != "waiting_operator":
        return
    for field in ("pending_intent", "held_result", "pending_keys"):
        _set(new, fields, field, None)


def _baseline(effect, new, old, decision, ctx, fields, target, now):
    if effect == "clear baseline_pending":
        _set(new, fields, "baseline_pending", False)
    elif effect == "set baseline_pending" or target == "intake":
        _set(new, fields, "baseline_pending", True)


_COMMENT_ID = re.compile(r"^[1-9][0-9]*$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _revouch(effect, new, old, decision, ctx, fields, target, now):
    given = ctx.sync.get("revouch")
    if not isinstance(given, dict):
        raise FactUnavailable("re-vouch without ctx.sync['revouch']")
    replies = dict(new.get("revouched_replies") or {})
    for cid, digest in given.items():
        cid = str(cid) if isinstance(cid, int) and not isinstance(cid, bool) else cid
        if not isinstance(cid, str) or not _COMMENT_ID.match(cid) or not isinstance(digest, str) \
                or not _SHA256.match(digest):
            raise FactUnavailable("re-vouch input %r: %r is not a comment id and sha256" % (cid, digest))
        replies[cid] = digest
    _set(new, fields, "vouch_at", now)
    _set(new, fields, "revouched_replies", replies)


TIER_KEYS = ("push", "prCreate", "issueAssign", "issueCreate", "issueUpdate", "merge", "release")


def _pending_keys(effect, new, old, decision, ctx, fields, target, now):
    keys = ctx.sync.get("pending_keys")
    if not isinstance(keys, list) or not keys or any(k not in TIER_KEYS for k in keys):
        raise FactUnavailable("record pending_keys without the confirm keys in ctx.sync: %r" % (keys,))
    _set(new, fields, "pending_keys", list(keys))


_1B_JOB_HANDLERS = {"intent_clear": _intent_clear, "baseline": _baseline, "revouch": _revouch,
                    "pending_keys": _pending_keys}


def _as_if_target(table, decision, fact):
    facts = dict(decision.facts)
    facts[fact] = False
    facts[BWC] = False
    facts[PPF] = False
    top = winners(table, decision.state, decision.event, facts)
    if len(top) != 1 or top[0].get("stay") or top[0].get("to") in COMPUTED:
        return None
    return top[0]["to"]


def apply(table, job, decision, ctx):
    """Apply a Winner to job. Returns (new_job, event_line, effects_to_run,
    effects_deferred):
      new_job          a copy of job with the move, the records, the
                       job-field effects, the attempt reset on entering a
                       different stage, the cleared pending changes and the slot
      event_line       the events.jsonl transition line; its fields object
                       holds every 1b field a job handler set, which rebuild
                       applies, and the caller adds the fields its caller
                       handlers set
      effects_to_run   [(handler, effect)] for the caller to run, in row order
      effects_deferred [{"effect", "phase"}] for the effects a later phase builds
    Raises TransitionRefused for a computed target no parking row records."""
    if not isinstance(decision, Winner) or decision.state is None:
        raise TypeError("apply takes the Winner of a (state, event) pair")
    row = table.by_id[decision.row]
    frm = decision.state
    new = copy.deepcopy(job)
    if decision.stay:
        to = frm
    elif decision.to in COMPUTED:
        to = job.get(decision.to)
        if to not in recordable(table, row):
            raise TransitionRefused("TRANSITION_REFUSED=%s->%s: %s not recorded by a parking row"
                                    % (frm, to if isinstance(to, str) else "?", decision.to))
    else:
        to = decision.to

    records = {}
    for key, m in sorted(row.get("records", {}).items()):
        v = m.get(frm, m.get("default")) if isinstance(m, dict) else m
        if v is None:
            continue
        values = [frm if x == "$from" else x for x in (v if isinstance(v, list) else [v])]
        fact = table._as_if.get((row["id"], key))
        if fact is not None:
            target = _as_if_target(table, decision, fact)
            if target not in values:
                raise TransitionRefused("TRANSITION_REFUSED=%s->%s: %s %s is not one row %s records"
                                        % (frm, to, key, target, row["id"]))
            value = target
        elif len(values) == 1:
            value = values[0]
        else:
            raise TransitionRefused("TRANSITION_REFUSED=%s->%s: row %s lists %s values with no rule to choose"
                                    % (frm, to, row["id"], key))
        new[key] = value
        records[key] = value

    # attempt counts the runs of one stage: it is reset when the job enters a
    # stage other than the one it last ran (from an active state, that state;
    # from a parked one, the stage the park recorded), and kept on a park, a
    # stay, a self-move and a resume into the recorded stage. Rows that start
    # a stage afresh from a park say so ("fresh attempts").
    if not decision.stay and table.kind(to) == "active":
        last = frm if table.kind(frm) == "active" else (job.get("blocked_stage") or job.get("resume_state"))
        if to != last:
            new["attempt"] = 0
    now = ctx.now or utc_now()
    applied, deferred, to_run, fields = [], [], [], {}
    for e in decision.effects:
        kind, name = EFFECTS[e]
        if kind == "deferred":
            deferred.append({"effect": e, "phase": name})
            continue
        applied.append(e)
        if name in JOB_HANDLERS:
            _run_job_handler(name, e, new, job, decision, ctx, fields=fields, target=to, now=now)
        else:
            to_run.append((name, e))

    pending = new.get("pending_changes")
    if isinstance(pending, list):
        cleared = set(f for f, v in row.get("guard", {}).items() if v is True)
        new["pending_changes"] = [f for f in pending if f not in cleared]

    new["state"] = to
    if not decision.stay and (to == table.rules.get("goal_state") or table.kind(to) in ("parked", "terminal")):
        new["holds_slot"] = False

    line = {"type": "transition", "job": job.get("key"), "time": now, "pass": ctx.pass_id,
            "event": decision.event, "from": frm, "row": decision.row, "to": None if decision.stay else to,
            "stay": decision.stay, "effects_applied": applied, "effects_deferred": deferred,
            "attempt": new.get("attempt"), "channel": ctx.channel, "caller": ctx.caller, "records": records,
            "fields": fields}
    return new, line, to_run, deferred


# ---------------------------------------------------------------- replay

def check_move(table, from_state, to_state, event=None):
    """Raise TransitionRefused unless a row moves from_state to to_state on
    event (any event when None). to_state None, or equal to from_state, is
    also met by a stay row; a computed-target row meets any state in its
    resume list."""
    for r in table.rows:
        if from_state not in r["from"] or (event is not None and r["event"] != event):
            continue
        if r.get("stay"):
            if to_state is None or to_state == from_state:
                return
        elif r.get("to") in COMPUTED:
            if to_state in r.get("resume", []):
                return
        elif r.get("to") == to_state:
            return
    raise TransitionRefused("TRANSITION_REFUSED=%s->%s: no row moves %s to %s"
                            % (from_state, to_state, from_state, to_state))
