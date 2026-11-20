"""Witnesses for the factory's state table, from the docs checker alone (plan
1a T13): for every row, a (state, fact assignment) under which that row wins
its (state, event) pair, and how a test seeds the factory directory so the
engine's `next` raises that event with those facts.

Usage:
  witness.py [--table <transitions.json>] rows            one witness per row id
  witness.py [--table <transitions.json>] all             one per (row, state) win
  witness.py [--table <transitions.json>] fence <state> <event>
  witness.py [--table <transitions.json>] contradictions
  witness.py [--table <transitions.json>] row <id> [<state>]

`rows` and `all` print one JSON object per line, then a last line
`coverage ids <covered>/<row ids> pairs <witnesses>/<wins>`. `row` prints the
cheapest witness of one row id (in one state when given). `fence` prints the
first unbuilt fact, in sorted order, that the pair reads, and its phase.
`contradictions` prints, for each (state, event) pair, every assignment that
the fact dependencies forbid under which no row matches and no no_move_ok
entry agrees, as one JSON object per line, then `contradictions <n>`.

Nothing here reads the engine (bin/): the winners, the facts a pair reads and
the dependencies come from docs/flow-factory/check_transitions.py's Checker,
run over the table; the split of facts into built (1a) and unbuilt comes from
plan 2.11, written out below. A wrong split shows up in the test, not here:
the test entry point refuses a seam that names a built fact as unbuilt
(SEAM_REFUSED, exit 2), and an unbuilt fact the seam leaves out blocks the
pair (SEAM_MISSING).

The choice among the assignments under which a row wins: an assignment the
engine cannot produce is skipped (both derived facts true; slot_free true with
slot_available false; tree_dirty true with clone_config_changed true; a PR
change fact true for an event other than github_change, because a pending
change raises github_change first in the pass), and of the rest the one with
the lowest seeding cost wins, the first in the checker's order on a tie. The
cost counts what makes a scenario slow or adds a process: a dirty clone, a
changed clone config, a live orphan group, a second job holding the slot, a
stale probe record, and above all a real worker launch.
"""

# Keep the working directory off sys.path before any other import, as the
# plugin's Python units do (tests/syspath-guard.test.sh describes why).
# ruff: noqa: E401, E402
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

# Importing the checker must not write docs/flow-factory/__pycache__ into the
# repository (plan 2.16, Bytecode).
sys.dont_write_bytecode = True

import itertools
import json

HERE = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.realpath(os.path.join(HERE, "..", "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "docs", "flow-factory"))
import check_transitions as ct  # noqa: E402

DEFAULT_TABLE = os.path.join(REPO_ROOT, "plugins", "flow", "references", "factory-transitions.json")

# Plan 2.11 "Built providers in 1a": every other fact of the table, except the
# two derived ones, is unbuilt in 1a and comes from the seam.
BUILT_1A = (
    "probes_stale", "group_gone", "orphan_group_alive", "attempts_exhausted", "slot_free", "slot_available",
    "tree_dirty", "clone_config_changed", "unvouched_session_action", "build_started", "blocked_before_spec",
    "reason_needs_info_exhausted", "round_limit_reached", "pr_exists", "pr_merged_by_person",
    "pr_closed_by_person", "foreign_head_change",
)
# Plan 1b (B13, B14 step 0): the facts phase 1b builds. A witness gives each
# one through the inputs the engine reads: the gh stand-in's world (the issue
# facts), job.json fields, the stored event's facts, or a settings file (the
# tier facts and the confirm input of blocking_write_confirm), never the seam.
BUILT_1B = (
    "issue_changed", "untrusted_edit", "needs_info_answer", "untrusted_needs_info_answer",
    "intake_rounds_exhausted", "cancel_signal", "untrusted_close", "via_comment", "retry_by_triage_only",
    "tier_confirm_blocking", "park_tier_confirm", "intent_effect_observed", "intent_key_not_confirm",
    "pending_intent_stale", "dependency_open", "creation_allowed",
)
# The issue facts: read from the sync's issue reads, so a pair that reads one
# needs a world for the gh stand-in (plan 3.1).
ISSUE_FACTS = ("untrusted_edit", "needs_info_answer", "untrusted_needs_info_answer", "cancel_signal",
               "untrusted_close", "dependency_open")
# Journal wave 1, Tiers: the keys of the blocking writes left on the path to
# ready from each state.
PATH_KEYS = {}
for _s in ("intake", "prepare"):
    PATH_KEYS[_s] = ("issueAssign", "issueUpdate", "push", "prCreate")
for _s in ("spec", "build", "open_pr"):
    PATH_KEYS[_s] = ("push", "prCreate", "issueUpdate")
for _s in ("gate", "review", "rework", "sync", "resolve"):
    PATH_KEYS[_s] = ("push", "issueUpdate")
for _s in ("ready", "approve"):
    PATH_KEYS[_s] = ("issueUpdate",)
# Plan 5.3, write kind to tier key (PR create or edit is prCreate with no PR).
WRITE_KEYS = {"assignment": "issueAssign", "in-progress label": "issueUpdate", "push": "push",
              "PR create or edit": "prCreate", "review marker": "issueUpdate", "resolution marker": "issueUpdate",
              "replies": "issueUpdate", "ready mark": "issueUpdate", "undo of ready": "issueUpdate"}
VOUCH_AT = "2026-11-16T00:00:00Z"
# The id record_job_intent gives the first intent a fresh job records for
# row 40 (plan 2.2: issue-N-j<seq>-<row>-<k>, k = 1).
INTENT_ID = "issue-%d-j1-40-1"
# An intake judge reply that passes plan 5.3's output schema, per decision.
JUDGE = {
    "judge_accept": {"decision": "ACCEPT", "risk": "low", "surfaces": ["config"], "scope": "one setting",
                     "proposed_criteria": ["the port is read from the settings file"], "questions": [],
                     "reason": "clear"},
    "judge_needs_info": {"decision": "NEEDS_INFO", "risk": "low", "surfaces": [], "scope": "unclear",
                         "proposed_criteria": [], "questions": ["Which port?"], "reason": "a port is not named"},
    "judge_reject": {"decision": "REJECT", "risk": "high", "surfaces": [], "scope": "none",
                     "proposed_criteria": [], "questions": [], "reason": "out of scope"},
}
# Plan 2.11 seam kind 3: the built facts a seam may give.
SEAM_BUILT = ("group_gone", "unvouched_session_action")
# Plan 3.2, through plan 2.11: the phase that builds each unbuilt fact, for the
# fence's expected line. Only the facts a fence scenario can name are needed;
# the test checks the one it uses against the engine's output.
UNBUILT_PHASE = {
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
PR_CHANGE_FACTS = ("pr_merged_by_person", "pr_closed_by_person", "foreign_head_change")
# Job.json facts the plan's github_change seed leaves out of pending_changes.
JOB_FACTS = ("build_started", "round_limit_reached", "blocked_before_spec", "reason_needs_info_exhausted")
COMPUTED = ("resume_state", "blocked_stage")
ISSUE = 7
HEAD = "a" * 40
FOREIGN_HEAD = "b" * 40
PR = 12
# The arguments a person subcommand stores with its event (plan T13 seeds;
# plan B14 step 11: a current NI id with text, and the pending intent's id).
PERSON_ARGS = {"person_answer": {"qid": "NI-1", "text": "use port 8080"},
               "person_confirm": {"intent": INTENT_ID % ISSUE}}


def load(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f, object_pairs_hook=ct.no_duplicates)
    c = ct.Checker(data)
    if not c.run():
        raise SystemExit("witness.py: the checker refuses the table: %s" % "; ".join(c.errors[:3]))
    return data, c


def unbuilt_facts(data, c):
    derived = {c.bw_fact, c.pk["fact"] if c.pk else None}
    return set(f for f in data["facts"] if f not in BUILT_1A and f not in BUILT_1B and f not in derived)


def reads(data, c, state, event):
    """The facts the pair reads, as plan 2.11 defines facts_read: the guard
    facts of its rows, its no_move_ok "when" facts and, for the pass_first
    event, pass_first's "when" facts, closed under fact_dependencies, less
    the derived facts. Computed from the table with the checker's own
    closure, not from the engine."""
    rows = [r for r in c.rows if state in r["from"] and r.get("event") == event]
    facts = set()
    for r in rows:
        facts.update(r.get("guard", {}))
    for nm in data["events"][event].get("no_move_ok", []):
        if state in nm.get("states", []):
            facts.update(nm.get("when", {}))
    pf = data.get("pass_first") or {}
    if pf.get("event") == event:
        facts.update(pf.get("when", {}))
    facts = set(c.closure(facts, c.deps_for(state)))
    return sorted(facts - {c.bw_fact, c.pk["fact"] if c.pk else None})


def forced(c, state):
    """Facts a dependency with an empty "if" fixes in this state."""
    out = {}
    for dep in c.deps_for(state):
        if not dep["if"]:
            out.update(dep["then"])
    return out


def is_launch(row):
    """A launching row (T6: 66, 66b, 66bp, 66i, 66m, 66p): a launch_due row
    with an effect that starts with "launch"."""
    return row["event"] == "launch_due" and any(e.startswith("launch") for e in row.get("effects", []))


def recorded_values(c, row, key):
    """The values the parking rows a computed-target row resumes from record
    for key (the checker's records, read from the table)."""
    parked = row["from"][0]
    rf = row.get("resume_from")
    if rf == "*":
        srcs = [x for x in c.rows if x.get("to") == parked and not x.get("stay") and key in x.get("records", {})]
    else:
        srcs = [c.by_id[i] for i in (rf or []) if i in c.by_id]
    out = set()
    for x in srcs:
        m = x.get("records", {}).get(key)
        if m is None:
            continue
        for fs in x["from"]:
            v = m.get(fs, m.get("default")) if isinstance(m, dict) else m
            if v is None:
                continue
            for y in (v if isinstance(v, list) else [v]):
                out.add(fs if y == "$from" else y)
    return out


def resume_seed(c, row, a):
    """The value a computed-target row moves to: the first of its resume list
    that a parking row records and that agrees with blocked_before_spec when
    the pair reads it. None when no value fits."""
    key = row["to"]
    values = recorded_values(c, row, key)
    for v in row.get("resume", []):
        if v not in values:
            continue
        if key == "blocked_stage" and "blocked_before_spec" in a and (v in ("intake", "prepare")) != a["blocked_before_spec"]:
            continue
        return v
    return None


def realizable(c, row, state, event, a, rd):
    """Why the engine cannot produce this assignment, or None."""
    bwf, pkf = c.bw_fact, (c.pk["fact"] if c.pk else None)
    if a.get(bwf) and a.get(pkf):
        return "both derived facts true"
    if a.get("slot_free") is True and a.get("slot_available") is False:
        return "slot_free true needs a free slot, which makes slot_available true"
    if a.get("tree_dirty") is True and a.get("clone_config_changed") is True:
        return "tree_dirty reads false when clone_config_changed is true"
    if event != "github_change" and any(a.get(f) for f in PR_CHANGE_FACTS if f in rd):
        return "a pending PR change raises github_change first"
    if row is not None and row.get("to") in COMPUTED and resume_seed(c, row, a) is None:
        return "no recorded resume value agrees with the facts"
    return None


def cost(data, c, row, state, event, a, rd):
    k = 0
    if "tree_dirty" in rd or "clone_config_changed" in rd:
        k += 2
    k += 3 * bool(a.get("tree_dirty")) + 3 * bool(a.get("clone_config_changed"))
    k += 4 * bool(a.get("orphan_group_alive"))
    k += 2 * (a.get("slot_free") is False) + 2 * (a.get("slot_available") is False)
    k += 1 * bool(a.get("probes_stale"))
    if event == "lease_expired":
        k += 1
    if row is not None and is_launch(row) and data["states"][state].get("run_by") == "worker":
        k += 20
    return k


def derived_inputs(c, rows, state, a):
    bwf, pkf = c.bw_fact, (c.pk["fact"] if c.pk else None)
    if not (a.get(bwf) or a.get(pkf)):
        return {}
    a0 = dict(a)
    a0[bwf] = False
    if pkf:
        a0[pkf] = False
    top0 = c.top_rows(rows, a0)
    if a.get(pkf):
        return {"prepush_fails": True}
    # The confirm input comes from the tier keys of the winner's writes, set
    # to confirm in a settings file (plan 3.3); the seam gives none.
    return {}


def confirm_tiers(c, rows, state, a):
    """{tier key: "confirm"} for each write of the row that wins with
    blocking_write_confirm false, when the witness needs it true (plan 3.3,
    witness.py)."""
    bwf = c.bw_fact
    if not a.get(bwf):
        return {}
    a0 = dict(a)
    a0[bwf] = False
    if c.pk:
        a0[c.pk["fact"]] = False
    top0 = c.top_rows(rows, a0)
    return {WRITE_KEYS[w]: "confirm" for w in c.writes_for(top0[0], state)}


def candidates(data, c):
    """Every (row id, state) win as (cost, order, witness), in the checker's
    pair order and assignment order."""
    order = 0
    for (state, event), (rows, facts, deps) in c.pair_info.items():
        rd = reads(data, c, state, event)
        bwf, pkf = c.bw_fact, (c.pk["fact"] if c.pk else None)
        for a in c.assignments_of(facts, deps):
            # The checker's derived-fact filters (check_transitions.py, the
            # blocking_write and push_check blocks of coverage()).
            if bwf in a and a[bwf]:
                a0 = dict(a)
                a0[bwf] = False
                if not c.consistent(a0, deps):
                    continue
                top0 = c.top_rows(rows, a0)
                if len(top0) != 1 or not c.writes_for(top0[0], state):
                    continue
            if pkf in a and a[pkf]:
                a1 = dict(a)
                a1[pkf] = False
                if not c.consistent(a1, deps):
                    continue
                top1 = c.top_rows(rows, a1)
                if len(top1) != 1 or c.pk["write"] not in c.writes_for(top1[0], state):
                    continue
            top = c.top_rows(rows, a)
            if len(top) != 1:
                continue
            row = top[0]
            order += 1
            if realizable(c, row, state, event, a, rd) is not None:
                continue
            yield (cost(data, c, row, state, event, a, rd), order,
                   witness(data, c, rows, row, state, event, a, rd))


def witness(data, c, rows, row, state, event, a, rd, issue=ISSUE):
    """The witness of row (None for a contradiction: no row wins) in state
    for event under assignment a, with its seeds for job issue-<issue>-j1."""
    key = "issue-%d-j1" % issue
    unbuilt = unbuilt_facts(data, c)
    read_a = {f: a[f] for f in rd}
    w = {"id": row["id"] if row is not None else None, "issue": issue, "key": key, "state": state, "event": event,
         "assignment": read_a,
         "unbuilt": {f: v for f, v in read_a.items() if f in unbuilt},
         "built": {f: v for f, v in read_a.items() if f in BUILT_1A},
         "built_1b": {f: v for f, v in read_a.items() if f in BUILT_1B},
         "derived_inputs": derived_inputs(c, rows, state, a),
         "built_inputs": {}}
    run_by = data["states"][state].get("run_by")
    built = w["built"]
    # The seam gives group_gone (the kill-and-confirm result) and, for an
    # engine event, unvouched_session_action; a person event carries the
    # latter in its pending file, as the person subcommand stores it.
    if "group_gone" in built:
        w["built_inputs"]["group_gone"] = built["group_gone"]
    person = event.startswith("person_")
    if "unvouched_session_action" in built and not person:
        w["built_inputs"]["unvouched_session_action"] = built["unvouched_session_action"]

    job = {}
    fix = dict(forced(c, state))
    fix.update(read_a)
    if "build_started" in fix:
        job["build_started"] = bool(fix["build_started"])
    if fix.get("attempts_exhausted") is True:
        job["attempt"] = 2
    if "round_limit_reached" in fix:
        job["round"], job["round_limit"] = (1, 1) if fix["round_limit_reached"] else (0, 3)
    if fix.get("reason_needs_info_exhausted") is True:
        job["reason"] = "needs_info_exhausted"
    if "blocked_before_spec" in fix:
        job["blocked_stage"] = "intake" if fix["blocked_before_spec"] else "build"
    pr_facts = {f: bool(read_a.get(f)) for f in PR_CHANGE_FACTS}
    pr_fixture = None
    if read_a.get("pr_exists") is True or any(pr_facts.values()):
        job["pr"] = PR
        job["head_sha"] = HEAD
        merged, closed = pr_facts["pr_merged_by_person"], pr_facts["pr_closed_by_person"]
        pr_fixture = {"key": "api_repos_flow-e2e_scratch_pulls_%d" % PR,
                      "json": {"number": PR, "state": "closed" if (merged or closed) else "open",
                               "merged": merged, "merged_at": "2026-11-16T09:00:00Z" if merged else None,
                               "head": {"sha": FOREIGN_HEAD if pr_facts["foreign_head_change"] else HEAD}}}
    elif "pr_exists" in fix and fix["pr_exists"] is False:
        job["pr"] = None
    slot = None
    if "slot_free" in read_a or "slot_available" in read_a:
        if read_a.get("slot_available") is False or (read_a.get("slot_free") is False
                                                       and "slot_available" not in read_a):
            slot = "other_job"
            job["holds_slot"] = False
        elif read_a.get("slot_free") is False:
            slot = "own"
            job["holds_slot"] = True
        else:
            job["holds_slot"] = False
    expect = {"row": row["id"] if row is not None else None}
    if row is None:
        expect["refused"] = "TRANSITION_REFUSED=%s->?: no row wins for event %s" % (state, event)
    elif row.get("stay"):
        expect["stay"] = True
    elif row["to"] in COMPUTED:
        v = resume_seed(c, row, a)
        job[row["to"]] = v
        expect["to"] = v
        expect["resume_seed"] = {row["to"]: v}
    else:
        expect["to"] = row["to"]
    if expect.get("to") is not None:
        kind = data["states"][expect["to"]]["kind"]
        if expect["to"] == data["rules"].get("goal_state") or kind in ("parked", "terminal"):
            expect["holds_slot"] = False

    did = "%s-%s-1" % (key, state) if state in data["events"]["launch_due"]["occurs_in"] else None
    seed = {"job": job, "slot": slot, "pr_fixture": pr_fixture,
            "clone": "tree_dirty" in rd or "clone_config_changed" in rd,
            "dirty": read_a.get("tree_dirty") is True,
            "config_change": read_a.get("clone_config_changed") is True,
            "orphan": read_a.get("orphan_group_alive") is True,
            "stale_probes": read_a.get("probes_stale") is True,
            "pending": None, "directive": None, "result": None, "lease": False,
            "bodies": {}, "worker_launch": False, "judge_launch": None, "issue_md": False,
            "world": None, "tiers": {}, "pending_intent": None, "question": None}
    if event == "github_change":
        guard = row.get("guard", {}) if row is not None else a
        names = [f for f, v in guard.items() if v is True and f in rd and f not in JOB_FACTS
                 and f not in PR_CHANGE_FACTS and f != "pr_exists" and f in unbuilt]
        if not names and not any(pr_facts.values()):
            names = ["issue_changed"]
        job["pending_changes"] = names
    elif person:
        args = {"intent": INTENT_ID % issue} if event == "person_confirm" else PERSON_ARGS.get(event, {})
        seed["pending"] = {"event": event, "channel": "terminal", "args": args,
                           "facts": {"unvouched_session_action": bool(read_a.get("unvouched_session_action", False)),
                                     "via_comment": bool(read_a.get("via_comment", False)),
                                     "retry_by_triage_only": bool(read_a.get("retry_by_triage_only", False))}}
    elif event.startswith("judge_") or event in ("stage_succeeded", "stage_failed"):
        seed["directive"] = {"id": did, "kind": run_by, "stage": state, "max_budget_usd": 0.5}
        ok = event != "stage_failed"
        seed["result"] = {"outcome": "completed" if ok else "error",
                          "event": event if event in ("stage_succeeded", "stage_failed") else None}
        if event in JUDGE and state == "intake":
            # Rows 4, 5 and 6 read the judge reply from the result file (plan
            # 5.3 Context); row 6 reads the comment and answer ids from the
            # issue.md the judge read (B14 step 11).
            seed["result"]["judge"] = JUDGE[event]
            seed["issue_md"] = event == "judge_accept"
        seed["pending"] = {"event": event, "channel": "launcher", "args": {"directive": did}, "facts": {}}
        job["directive"] = did
        job["holds_slot"] = job.get("holds_slot", True)
    elif event == "lease_expired":
        seed["directive"] = {"id": did, "kind": run_by, "stage": state, "max_budget_usd": 0.5}
        seed["lease"] = True
        job["directive"] = did
        job["holds_slot"] = job.get("holds_slot", True)
    elif event in ("worker_parked", "question_stored"):
        seed["pending"] = {"event": event, "channel": "launcher", "args": {}, "facts": {}}
    elif event == "launch_due":
        job["directive"] = None
        if row is not None and is_launch(row):
            if run_by == "worker":
                # A worker runs in the job clone (the launcher's cwd).
                seed["worker_launch"] = True
                seed["clone"] = True
            elif run_by == "judge" and state == "intake":
                # The intake judge is launched for real (B14 step 11): the
                # sync writes the issue set row 66i reads, and the judge
                # stand-in answers ACCEPT.
                seed["judge_launch"] = JUDGE["judge_accept"]
            else:
                seed["bodies"] = {"%s:%s" % (run_by, state): "judge_approve" if run_by == "judge" else "succeeded"}
    seed_1b(c, rows, row, state, event, read_a, job, seed, a)
    # sync_tick needs nothing beyond the state: the pass raises it in every
    # state where it occurs.
    w["seed"] = seed
    w["expect"] = expect
    w["fixture"] = {"unbuilt": {key: w["unbuilt"]}}
    if w["derived_inputs"]:
        w["fixture"]["derived_inputs"] = w["derived_inputs"]
    if w["built_inputs"]:
        w["fixture"]["built_inputs"] = w["built_inputs"]
    if seed["bodies"]:
        w["fixture"]["bodies"] = seed["bodies"]
    w["to_text"] = "refused" if row is None else "stay" if expect.get("stay") else expect["to"]
    return w


def seed_1b(c, rows, row, state, event, a, job, seed, full):
    """The inputs of the 1b facts the witness reads (plan 3.3, witness.py):
    seed["world"] for the gh stand-in when the pair reads an issue fact or
    needs GitHub (the sync of row 66i, a pending intent's lookup and run);
    seed["tiers"] for the settings file; job.json fields for the facts the
    table computes; seed["pending_intent"] and seed["question"] for the
    records the caller handlers read."""
    tiers = confirm_tiers(c, rows, state, full)
    world = None
    if set(a) & set(ISSUE_FACTS) or seed.get("judge_launch"):
        world = {}
    if "needs_info_answer" in a or "untrusted_needs_info_answer" in a or event == "person_answer":
        job["needs_info"] = {"asked_at": "2026-11-16T00:30:00Z", "questions": ["NI-1"], "round": 1, "earlier": []}
        seed["question"] = "NI-1"
    if "issue_changed" in a:
        if a["issue_changed"]:
            job.update(baseline_pending=False, baseline_digest="0" * 64, issue_digest="1" * 64)
        else:
            job["baseline_pending"] = True
    if "intake_rounds_exhausted" in a:
        job["intake_round"] = 3 if a["intake_rounds_exhausted"] else 0
    if state == "waiting_operator" and "park_tier_confirm" in a:
        job["reason"] = "tier_confirm" if a["park_tier_confirm"] else "write_confirm"
    if a.get("tier_confirm_blocking"):
        path = state if state != "waiting_operator" else job.get("resume_state")
        keys = PATH_KEYS.get(path, PATH_KEYS["intake"])
        tiers[keys[-1]] = "confirm"
    intent = state == "waiting_operator" and a.get("park_tier_confirm") is not True and (
        set(a) & {"intent_effect_observed", "intent_key_not_confirm", "pending_intent_stale"}
        or event == "person_confirm")
    if intent:
        kind = "comment" if a.get("pending_intent_stale") else "assign_label"
        seed["pending_intent"] = {"kind": kind, "observed": bool(a.get("intent_effect_observed"))}
        if a.get("intent_key_not_confirm") is False:
            tiers["issueUpdate" if kind == "comment" else "issueAssign"] = "confirm"
        if a.get("pending_intent_stale"):
            changes = list(job.get("pending_changes") or [])
            if "foreign_head_change" not in changes:
                job["pending_changes"] = changes + ["foreign_head_change"]
        world = world if world is not None else {}
    if world is not None:
        world.update({"untrusted_edit": bool(a.get("untrusted_edit")),
                      "trusted_reply": bool(a.get("needs_info_answer")),
                      "untrusted_reply": bool(a.get("untrusted_needs_info_answer")),
                      "cancel": bool(a.get("cancel_signal")), "untrusted_close": bool(a.get("untrusted_close")),
                      "blocker_open": bool(a.get("dependency_open")),
                      "observed": bool(a.get("intent_effect_observed"))})
        job["vouch_at"] = VOUCH_AT
    seed["world"] = world
    seed["tiers"] = tiers


def best_per(cands, keyfn):
    best = {}
    for k, order, w in cands:
        key = keyfn(w)
        if key not in best or (k, order) < best[key][:2]:
            best[key] = (k, order, w)
    return best


def summary(data, c, covered, count):
    ids = sorted(set(r["id"] for r in c.rows), key=ct.id_key)
    return "coverage ids %d/%d pairs %d/%d" % (len(covered), len(ids), count, len(c.wins))


def first_unbuilt(data, c, state, event):
    rd = reads(data, c, state, event)
    unbuilt = unbuilt_facts(data, c)
    for f in rd:
        if f in unbuilt:
            for phase, facts in UNBUILT_PHASE.items():
                if f in facts:
                    return f, phase
            return f, "?"
    return None, None


def contradictions(data, c):
    """Per (state, event) pair, the cheapest assignment of the facts the pair
    reads that the fact dependencies forbid, under which no row matches and
    no no_move_ok entry agrees, and that the engine can still be given; as a
    witness with row None for job issue-<101 + i>."""
    out = []
    for (state, event), (rows, facts, deps) in c.pair_info.items():
        nmo = [nm for nm in data["events"][event].get("no_move_ok", []) if state in nm.get("states", [])]
        rd = reads(data, c, state, event)
        best = None
        for order, bits in enumerate(itertools.product((False, True), repeat=len(rd))):
            a = dict(zip(rd, bits))
            if c.consistent(a, deps):
                continue
            a2 = dict(a)
            a2[c.bw_fact] = False
            if c.pk:
                a2[c.pk["fact"]] = False
            if c.top_rows(rows, a2):
                continue
            if any(c.agrees(nm.get("when", {}), a2) for nm in nmo):
                continue
            if realizable(c, None, state, event, a, rd) is not None:
                continue
            k = cost(data, c, None, state, event, a, rd)
            if best is None or (k, order) < best[:2]:
                best = (k, order, a)
        if best is not None:
            out.append(witness(data, c, rows, None, state, event, best[2], rd, issue=101 + len(out)))
    return out


def main(argv):
    table = DEFAULT_TABLE
    if argv[:1] == ["--table"]:
        table, argv = argv[1], argv[2:]
    data, c = load(table)
    cmd = argv[0] if argv else "rows"
    if cmd in ("rows", "all"):
        cands = list(candidates(data, c))
        pairs = best_per(cands, lambda w: (w["id"], w["state"]))
        best = pairs if cmd == "all" else best_per(cands, lambda w: w["id"])
        items = sorted(best.values(), key=lambda t: (ct.id_key(t[2]["id"]), t[2]["state"]))
        for _, _, w in items:
            print(json.dumps(w, sort_keys=True, separators=(",", ":")))
        print(summary(data, c, set(w["id"] for _, _, w in items), len(pairs)))
        return 0
    if cmd == "row":
        rid = argv[1]
        state = argv[2] if len(argv) > 2 else None
        best = None
        for k, order, w in candidates(data, c):
            if w["id"] == rid and (state is None or w["state"] == state) and (best is None or (k, order) < best[:2]):
                best = (k, order, w)
        if best is None:
            print("no witness for row %s%s" % (rid, " in " + state if state else ""), file=sys.stderr)
            return 1
        print(json.dumps(best[2], sort_keys=True, separators=(",", ":")))
        return 0
    if cmd == "fence":
        f, phase = first_unbuilt(data, c, argv[1], argv[2])
        print("%s %s" % (f, phase))
        return 0
    if cmd == "contradictions":
        found = contradictions(data, c)
        for x in found:
            print(json.dumps(x, sort_keys=True, separators=(",", ":")))
        print("contradictions %d" % len(found))
        return 0
    print("witness.py: unknown command %s" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
