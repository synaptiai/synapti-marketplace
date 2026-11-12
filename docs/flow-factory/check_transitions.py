#!/usr/bin/env python3
"""Check the flow factory job state machine in transitions.json.

Usage: check_transitions.py [path/to/transitions.json] [--markdown]

Checks, in order:
  1. schema: allowed keys at every level, no duplicate JSON keys, every
     referenced state, event and fact declared, facts read only in the states
     where they are defined (row guards, no_move_ok "when" and
     fact_dependencies), a non-empty "when" on every no_move_ok entry, and
     the occurrence rules: github_change, person_cancel and person_rebuild
     occur in every non-terminal state, and the stage events occur exactly in
     the states whose run_by needs them (RUN_BY_EVENTS);
  2. guard coverage: for every non-terminal state S and every event E that can
     occur in S, every assignment of the facts the rows for (S, E) read that
     the fact dependencies allow is matched by at least one row, and when
     several match the lowest precedence is unique. An unmatched assignment is
     allowed only by a no_move_ok entry of E for S whose "when" agrees with it.
     A pair that the dependencies leave with no assignment at all is an error,
     and so is a row that wins no assignment in one of its from-states;
  3. derives the In, Out and Stays lists of row ids for every state, from the
     rows that win at least one assignment in each from-state;
  4. every state is reachable from queued through winning rows, and every
     non-terminal state can reach a terminal state. A resume row counts as a
     way from its parked state into a target only when a parking row it
     reads wins in a reachable from-state other than that target and records
     the target there, so a park taken in a state is never a way into it;
  5. every parked state has an exit row into an active state on a person
     event and on github_change;
  plus: resume rows list exactly the targets that the parking rows record,
  every recorded target is an active state, and every row that enters a
  parked state records each value that a resume row of that state reads and
  is named by one of those resume rows.

The top-level keys event_order, pass_first, rules and expectations are
required, every rule in "rules" is required, and the expectation ids in
REQUIRED_EXPECTATIONS must all be present, so deleting a rule or an
expectation together with the rows it protects fails. They hold the rules
the prose names, as data:
  - creation: every creation row targets rules.initial_state, and
    reachability starts from the creation targets;
  - goal: every non-terminal state can reach rules.goal_state;
  - person_confirmation: every row on one of its events reads its fact; a
    row that reads it true stays, and no no_move_ok entry of those events
    lets a job stay while it is true;
  - blocking_write: rows declare their blocking GitHub writes in "writes".
    The fact is derived, not free: with it true, an assignment exists only
    when the row that wins with it false declares a write in that state, and
    then a row that parks in park_state recording resume_state must win. A
    row whose guard requires the fact false must declare a write in each of
    its from-states;
  - ready_mark: a row that moves a job out of a state where the PR is marked
    ready, to a non-terminal state where it is not, declares the undo write,
    unless it is a confirm park or its guard says the mark is already gone; a
    row with a fixed target that enters such a state from another declares
    the mark write. Only the rows in READY_RESUME_ROWS may resume a job into
    such a state; a row may record such a state only from such a state; and
    a confirm park taken in such a state records resume_state =
    rules.ready_mark.resume_into;
  - push_check: the pre-push check fact is derived like blocking_write: it
    can be true only when the row that wins with it false lists the push
    write, and then a row that moves the job to push_check.to without a push
    must win;
  - pass_first: in every state where its event occurs, whenever its "when"
    holds, one of its rows wins, because those rows apply before every event
    of event_order;
  - a person event must name the states where it occurs;
  - a no_move_ok "when" must name only literals the fact dependencies leave
    open in each of its states, so an entry cannot hold whatever happens;
  - each expectation names states, events, a "when" and the outcome that the
    winning row must have there (a target, staying, or one of named rows).
    It fails when another outcome wins, when the event cannot occur in a
    named state, or when no allowed assignment agrees with its "when".

With --markdown it writes transitions.md beside the JSON file.
Exit code 0 only when every check passes. Standard library only (Python 3.9+).
"""
import itertools
import json
import os
import re
import sys

KINDS = ("active", "parked", "terminal")
EVENT_KINDS = ("person", "github", "engine")
RUN_BY = ("engine", "directive", "judge", "worker")
COMPUTED = ("resume_state", "blocked_stage")
TOP_REQUIRED = ("facts", "events", "states", "rows", "event_order", "pass_first", "rules", "expectations")
TOP_ALLOWED = set(TOP_REQUIRED) | {"title", "about", "conventions", "fact_dependencies", "creation"}
ROW_ALLOWED = {"id", "from", "event", "guard", "to", "stay", "precedence", "effects",
               "resume", "resume_from", "records", "note", "phase", "writes"}
# Every rule is required: a table without one of them fails, so deleting a
# rule together with the rows it protects cannot pass.
RULES_REQUIRED = ("initial_state", "goal_state", "person_confirmation", "blocking_write",
                  "ready_mark", "push_check", "records_as_if")
RULES_ALLOWED = set(RULES_REQUIRED)
RECORDS_AS_IF_ALLOWED = {"row", "key", "fact", "why"}
PERSON_CONFIRMATION_ALLOWED = {"fact", "events", "why"}
BLOCKING_WRITE_ALLOWED = {"fact", "park_state", "kinds", "why"}
READY_MARK_ALLOWED = {"states", "mark", "undo", "missing_fact", "resume_into", "why"}
PUSH_CHECK_ALLOWED = {"write", "fact", "to", "why"}
PASS_FIRST_ALLOWED = {"event", "when", "rows", "why"}
# The only rows that may resume a job into a state where the PR is marked
# ready. Each resumes after the undo of ready ran or was observed, so the job
# enters ready with ready_mark_missing set and row 36u restores the mark.
READY_RESUME_ROWS = ("41", "41e", "41k")
# Expectation ids the table must hold. They are kept here, not only in the
# table, so an edit that drops an expectation together with the rows it
# protects fails.
REQUIRED_EXPECTATIONS = (
    "cancel_ends_the_job", "merge_by_person_wins", "pr_close_cancels", "cancel_signal_cancels",
    "untrusted_close_parks", "untrusted_close_parks_waiting", "untrusted_edit_parks",
    "issue_change_before_build", "issue_change_after_build", "foreign_push_regates",
    "foreign_push_before_build", "changes_requested_reworks", "rework_request_reworks",
    "feedback_reworks", "reject_rejects", "approval_resumes", "needs_info_answer_reintakes",
    "untrusted_answer_waits", "triage_retry_revouches_only", "triage_retry_revouches_edit",
    "needs_info_triage_retry_revouches_only", "closed_issue_refuses_resume",
    "closed_issue_refuses_answer", "confirm_tier_parks_before_launch",
    "protected_check_before_launch",
    "config_tamper_runs_no_git", "queued_waits_for_slot", "ready_waits_for_slot",
    "ready_mark_restored", "approve_once_per_head", "marker_disagreement_parks",
    "ready_needs_gate_record", "ready_needs_valid_review", "ready_needs_passing_ledger",
    "protected_violation_needs_human", "protected_conflict_needs_human",
    "escalated_review_needs_human", "marker_disagreement_in_ready_parks",
    "person_push_waits_on_untrusted_edit", "person_push_waits_on_untrusted_close",
    "person_push_after_build_regates", "person_push_before_build_waits",
    "resolve_repeat_refused", "merge_success_merges", "worker_park_needs_human",
    "ci_timeout_needs_human", "judge_reject_rejects",
)
EXPECT_ALLOWED = {"id", "states", "events", "when", "expect", "why"}
EXPECT_KINDS = ("to", "stays", "rows")
STATE_ALLOWED = {"kind", "meaning", "phase", "run_by"}
FACT_ALLOWED = {"meaning", "defined_in"}
EVENT_ALLOWED = {"kind", "meaning", "occurs_in", "no_move_ok"}
NO_MOVE_ALLOWED = {"states", "when", "reason"}
DEP_ALLOWED = {"if", "then", "states", "why"}
CREATION_ALLOWED = {"id", "event", "to", "conditions", "effects"}
# Events a person or GitHub can raise at any time: every non-terminal state
# must handle them.
EVERY_NONTERMINAL_EVENTS = ("github_change", "person_cancel", "person_rebuild")
# Events tied to a running stage: they occur in exactly the states whose
# run_by is listed. A state with a lease (directive, judge, worker) can have
# its lease expire, must be launched, and can fail.
RUN_BY_EVENTS = {
    "launch_due": ("directive", "judge", "worker"),
    "lease_expired": ("directive", "judge", "worker"),
    "stage_failed": ("directive", "judge", "worker"),
    "stage_succeeded": ("directive", "worker"),
    "worker_parked": ("worker",),
    "question_stored": ("worker",),
}
MAX_FACTS_PER_PAIR = 20


class DuplicateKey(ValueError):
    pass


def no_duplicates(pairs):
    out = {}
    for k, v in pairs:
        if k in out:
            raise DuplicateKey("duplicate key '%s' in one JSON object" % k)
        out[k] = v
    return out


def id_key(rid):
    m = re.match(r"^(\d+)(.*)$", rid)
    if m:
        return (0, int(m.group(1)), m.group(2))
    return (1, 0, rid)


def fmt_ids(ids):
    return ", ".join(sorted(set(ids), key=id_key)) or "-"


def fmt_assign(a):
    return "{" + ", ".join("%s=%s" % (k, "true" if a[k] else "false") for k in sorted(a)) + "}"


class Checker(object):
    def __init__(self, data):
        self.d = data
        self.errors = []
        self.pairs = 0
        self.assignments = 0
        self.wins = set()
        self.unchecked = set()
        self.pair_info = {}

    def err(self, check, msg):
        self.errors.append("[%s] %s" % (check, msg))

    def keys_ok(self, obj, allowed, where):
        if isinstance(obj, dict):
            for k in obj:
                if k not in allowed:
                    self.err("schema", "%s has unknown key '%s'" % (where, k))

    def defined_in(self, fact):
        f = self.d["facts"].get(fact)
        if isinstance(f, dict):
            return f.get("defined_in")
        return None

    def check_defined(self, facts, states, where):
        for f in facts:
            dfn = self.defined_in(f)
            if dfn is None:
                continue
            for s in states:
                if s not in dfn:
                    self.err("schema", "%s reads fact '%s' in state '%s', where it is not defined" % (where, f, s))

    # ---------------- 1. schema ----------------
    def schema(self):
        d = self.d
        if not isinstance(d, dict):
            self.err("schema", "top level is not an object")
            return False
        for k in TOP_REQUIRED:
            if k not in d:
                self.err("schema", "missing top-level key '%s'" % k)
        for k in d:
            if k not in TOP_ALLOWED:
                self.err("schema", "unknown top-level key '%s'" % k)
        if self.errors:
            return False
        states, facts, events = d["states"], d["facts"], d["events"]
        for name, s in states.items():
            if not isinstance(s, dict) or s.get("kind") not in KINDS:
                self.err("schema", "state '%s' needs kind in %s" % (name, "|".join(KINDS)))
                continue
            self.keys_ok(s, STATE_ALLOWED, "state '%s'" % name)
            if not isinstance(s.get("meaning"), str) or not s["meaning"].strip():
                self.err("schema", "state '%s' has no meaning" % name)
            if s["kind"] == "active":
                if s.get("run_by") not in RUN_BY:
                    self.err("schema", "active state '%s' needs run_by in %s" % (name, "|".join(RUN_BY)))
            elif "run_by" in s:
                self.err("schema", "%s state '%s' has run_by; only active states run anything" % (s["kind"], name))
        if "queued" not in states:
            self.err("schema", "state 'queued' is not declared")
        self.nonterm = [s for s, v in states.items() if isinstance(v, dict) and v.get("kind") != "terminal"]
        self.terminal = [s for s, v in states.items() if isinstance(v, dict) and v.get("kind") == "terminal"]
        self.parked = [s for s, v in states.items() if isinstance(v, dict) and v.get("kind") == "parked"]

        for name, f in facts.items():
            if not isinstance(f, dict) or not isinstance(f.get("meaning"), str) or not f["meaning"].strip():
                self.err("schema", "fact '%s' has no meaning" % name)
                continue
            self.keys_ok(f, FACT_ALLOWED, "fact '%s'" % name)
            if "defined_in" in f and (not isinstance(f["defined_in"], list) or not f["defined_in"]):
                self.err("schema", "fact '%s' defined_in must be a non-empty list" % name)
                f["defined_in"] = []
            for s in f.get("defined_in", []):
                if s not in states:
                    self.err("schema", "fact '%s' defined_in names undeclared state '%s'" % (name, s))

        for name, e in events.items():
            if not isinstance(e, dict):
                self.err("schema", "event '%s' is not an object" % name)
                continue
            self.keys_ok(e, EVENT_ALLOWED, "event '%s'" % name)
            if e.get("kind") not in EVENT_KINDS:
                self.err("schema", "event '%s' needs kind in %s" % (name, "|".join(EVENT_KINDS)))
            if not isinstance(e.get("meaning"), str) or not e["meaning"].strip():
                self.err("schema", "event '%s' has no meaning" % name)
            occ = e.get("occurs_in")
            if not isinstance(occ, list):
                self.err("schema", "event '%s' has no occurs_in list" % name)
                e["occurs_in"] = []
                occ = []
            if e.get("kind") == "person" and not occ:
                self.err("schema", "person event '%s' has an empty occurs_in list; a person event names the states where it acts, and is refused elsewhere" % name)
            for s in occ:
                if s not in states:
                    self.err("schema", "event '%s' occurs_in names undeclared state '%s'" % (name, s))
                elif states[s].get("kind") == "terminal":
                    self.err("schema", "event '%s' occurs_in names terminal state '%s'" % (name, s))
            for i, nm in enumerate(e.get("no_move_ok", [])):
                where = "event '%s' no_move_ok[%d]" % (name, i)
                if not isinstance(nm, dict):
                    self.err("schema", where + " is not an object")
                    continue
                self.keys_ok(nm, NO_MOVE_ALLOWED, where)
                if not isinstance(nm.get("reason"), str) or not nm["reason"].strip():
                    self.err("schema", where + " has no written reason")
                for s in nm.get("states", []):
                    if s not in occ:
                        self.err("schema", where + " names state '%s' where the event does not occur" % s)
                if not nm.get("states"):
                    self.err("schema", where + " names no states")
                when = nm.get("when")
                if not isinstance(when, dict) or not when:
                    self.err("schema", where + " has an empty or missing \"when\"; an entry must name the facts under which staying is right")
                    nm["when"] = {"__empty__": True}
                    continue
                self._check_guard(when, where + " when")
                self.check_defined(when, nm.get("states", []), where + " when")

        for name in EVERY_NONTERMINAL_EVENTS:
            e = events.get(name)
            if not isinstance(e, dict):
                self.err("schema", "event '%s' must be declared: every non-terminal state handles it" % name)
                continue
            for s in self.nonterm:
                if s not in e.get("occurs_in", []):
                    self.err("occurrence", "event '%s' does not occur in state '%s'; it must occur in every non-terminal state" % (name, s))
        for name, kinds in sorted(RUN_BY_EVENTS.items()):
            e = events.get(name)
            if not isinstance(e, dict):
                self.err("schema", "event '%s' must be declared" % name)
                continue
            want = set(s for s, v in states.items() if isinstance(v, dict) and v.get("run_by") in kinds)
            have = set(e.get("occurs_in", []))
            for s in sorted(want - have):
                self.err("occurrence", "event '%s' does not occur in state '%s', which is run by %s" % (name, s, states[s].get("run_by")))
            for s in sorted(have - want):
                self.err("occurrence", "event '%s' occurs in state '%s', which is not run by %s" % (name, s, " or ".join(kinds)))

        order = d.get("event_order")
        if not isinstance(order, list):
            self.err("schema", "event_order must be a list")
        else:
            occurring = [n for n, e in events.items() if isinstance(e, dict) and e.get("occurs_in")]
            for n in order:
                if n not in events:
                    self.err("schema", "event_order names undeclared event '%s'" % n)
            if len(order) != len(set(order)):
                self.err("schema", "event_order lists an event twice")
            for n in occurring:
                if n not in order:
                    self.err("schema", "event_order does not list event '%s'" % n)

        for i, dep in enumerate(d.get("fact_dependencies", [])):
            where = "fact_dependencies[%d]" % i
            if not isinstance(dep, dict) or "if" not in dep or "then" not in dep:
                self.err("schema", where + " needs 'if' and 'then'")
                continue
            self.keys_ok(dep, DEP_ALLOWED, where)
            self._check_guard(dep["if"], where + " if")
            self._check_guard(dep["then"], where + " then")
            if not isinstance(dep["then"], dict) or not dep["then"]:
                self.err("schema", where + " has an empty 'then'")
            for s in dep.get("states", []):
                if s not in states:
                    self.err("schema", where + " names undeclared state '%s'" % s)
            dep_facts = list(dep["if"]) + list(dep["then"]) if isinstance(dep["if"], dict) and isinstance(dep["then"], dict) else []
            if dep.get("states"):
                self.check_defined(dep_facts, dep["states"], where)
            else:
                for f in dep_facts:
                    if self.defined_in(f) is not None:
                        self.err("schema", where + " reads fact '%s', which is defined only in some states; list the states it applies in" % f)

        for c in d.get("creation", []):
            self.keys_ok(c, CREATION_ALLOWED, "creation row '%s'" % c.get("id"))
            if c.get("to") not in states:
                self.err("schema", "creation row '%s' targets undeclared state '%s'" % (c.get("id"), c.get("to")))
            if c.get("event") not in events:
                self.err("schema", "creation row '%s' names undeclared event '%s'" % (c.get("id"), c.get("event")))

        seen = set()
        for c in d.get("creation", []):
            seen.add(c.get("id"))
        used_facts = set()
        used_events = set(c.get("event") for c in d.get("creation", []))
        for r in d["rows"]:
            rid = r.get("id")
            where = "row '%s'" % rid
            if not isinstance(rid, str) or not rid:
                self.err("schema", "a row has no string id: %s" % json.dumps(r)[:80])
                continue
            if rid in seen:
                self.err("schema", "duplicate row id '%s'" % rid)
            seen.add(rid)
            for k in r:
                if k not in ROW_ALLOWED:
                    self.err("schema", where + " has unknown key '%s'" % k)
            frm = r.get("from")
            if not isinstance(frm, list) or not frm:
                self.err("schema", where + " needs a non-empty 'from' list")
                r["from"] = []
            for s in r["from"]:
                if s not in states:
                    self.err("schema", where + " from names undeclared state '%s'" % s)
                elif states[s].get("kind") == "terminal":
                    self.err("schema", where + " starts from terminal state '%s'" % s)
            ev = r.get("event")
            if ev not in events:
                self.err("schema", where + " names undeclared event '%s'" % ev)
            else:
                used_events.add(ev)
                for s in r["from"]:
                    if s in states and s not in events[ev].get("occurs_in", []):
                        self.err("schema", where + " reads event '%s' in state '%s', where the event does not occur" % (ev, s))
            g = r.get("guard", {})
            self._check_guard(g, where + " guard")
            if isinstance(g, dict):
                used_facts.update(g)
                self.check_defined(g, r["from"], where)
            has_to = "to" in r
            has_stay = r.get("stay") is True
            if has_to == has_stay:
                self.err("schema", where + " needs exactly one of 'to' or \"stay\": true")
            if has_to:
                to = r["to"]
                if to in COMPUTED:
                    if not isinstance(r.get("resume"), list) or not r["resume"]:
                        self.err("schema", where + " moves to computed '%s' but has no 'resume' target list" % to)
                        r["resume"] = []
                    for t in r["resume"]:
                        if t not in states:
                            self.err("schema", where + " resume names undeclared state '%s'" % t)
                        elif states[t].get("kind") != "active":
                            self.err("resume", where + " resume names '%s', a %s state; a job resumes only into an active state" % (t, states[t].get("kind")))
                    if "resume_from" not in r:
                        self.err("schema", where + " moves to computed '%s' but has no 'resume_from'" % to)
                elif to not in states:
                    self.err("schema", where + " targets undeclared state '%s'" % to)
                elif "resume" in r:
                    self.err("schema", where + " has 'resume' but a fixed target")
            if not isinstance(r.get("precedence"), int) or isinstance(r.get("precedence"), bool):
                self.err("schema", where + " needs an integer precedence")
            eff = r.get("effects")
            if not isinstance(eff, list) or not all(isinstance(x, str) for x in eff):
                self.err("schema", where + " needs an 'effects' list of strings")
            rec = r.get("records")
            if rec is not None:
                if not isinstance(rec, dict):
                    self.err("schema", where + " records is not an object")
                else:
                    for k, m in rec.items():
                        if k not in COMPUTED:
                            self.err("schema", where + " records unknown key '%s'" % k)
                        if not isinstance(m, dict) or not m:
                            self.err("schema", where + " records '%s' needs a from-state map" % k)
                            continue
                        for fs, v in m.items():
                            if fs != "default" and fs not in r["from"]:
                                self.err("schema", where + " records '%s' maps '%s', which is not in from" % (k, fs))
                            vals = v if isinstance(v, list) else [v]
                            for x in vals:
                                if x != "$from" and x not in states:
                                    self.err("schema", where + " records '%s' names undeclared state '%s'" % (k, x))
                                elif x != "$from" and states[x].get("kind") != "active":
                                    self.err("resume", where + " records %s = '%s', a %s state; a job resumes only into an active state" % (k, x, states[x].get("kind")))
                    if not has_to or r.get("to") not in self.parked:
                        self.err("schema", where + " has 'records' but does not enter a parked state")
        for f in facts:
            if f not in used_facts:
                self.err("schema", "fact '%s' is declared but no row reads it" % f)
        for e in events:
            if e not in used_events:
                self.err("schema", "event '%s' is declared but no row uses it" % e)
        self.rows = [r for r in d["rows"] if isinstance(r.get("id"), str)]
        self.by_id = dict((r["id"], r) for r in self.rows)
        self.schema_rules()
        return not self.errors

    def schema_rules(self):
        d = self.d
        states, facts, events = d["states"], d["facts"], d["events"]
        rules = d.get("rules", {})
        if not isinstance(rules, dict):
            self.err("schema", "rules is not an object")
            rules = {}
        self.keys_ok(rules, RULES_ALLOWED, "rules")
        for k in RULES_REQUIRED:
            if k not in rules:
                self.err("schema", "rules.%s is missing; the checker requires every rule" % k)
        self.rules = rules
        self.initial = rules.get("initial_state", "queued")
        if self.initial not in states or states[self.initial].get("kind") != "active":
            self.err("schema", "rules.initial_state '%s' is not a declared active state" % self.initial)
        for c in d.get("creation", []):
            if c.get("to") != self.initial:
                self.err("creation", "creation row '%s' targets '%s'; a new job starts in '%s'" % (c.get("id"), c.get("to"), self.initial))
        self.goal = rules.get("goal_state")
        if self.goal is not None and self.goal not in states:
            self.err("schema", "rules.goal_state '%s' is not a declared state" % self.goal)

        pf = d.get("pass_first")
        self.pass_first = None
        if not isinstance(pf, dict):
            self.err("schema", "pass_first must be an object")
        else:
            self.keys_ok(pf, PASS_FIRST_ALLOWED, "pass_first")
            if pf.get("event") not in events:
                self.err("schema", "pass_first names undeclared event '%s'" % pf.get("event"))
            when = pf.get("when")
            if not isinstance(when, dict) or not when:
                self.err("schema", "pass_first needs a non-empty \"when\"")
            else:
                self._check_guard(when, "pass_first when")
            prows = pf.get("rows")
            if not isinstance(prows, list) or not prows:
                self.err("schema", "pass_first needs a non-empty rows list")
            else:
                for rid in prows:
                    r = self.by_id.get(rid)
                    if r is None:
                        self.err("schema", "pass_first names unknown row '%s'" % rid)
                    elif r.get("event") != pf.get("event"):
                        self.err("schema", "pass_first names row '%s', which is not on event '%s'" % (rid, pf.get("event")))
            if not self.errors:
                self.pass_first = pf

        pc = rules.get("person_confirmation")
        self.pc_fact, self.pc_events = None, []
        if pc is not None:
            self.keys_ok(pc, PERSON_CONFIRMATION_ALLOWED, "rules.person_confirmation")
            self.pc_fact = pc.get("fact")
            self.pc_events = pc.get("events", [])
            if self.pc_fact not in facts:
                self.err("schema", "rules.person_confirmation names undeclared fact '%s'" % self.pc_fact)
            for en in self.pc_events:
                if en not in events:
                    self.err("schema", "rules.person_confirmation names undeclared event '%s'" % en)
            for r in self.rows:
                if r.get("event") not in self.pc_events:
                    continue
                g = r.get("guard", {})
                if self.pc_fact not in g:
                    self.err("confirmation", "row '%s' handles %s, which needs a person's confirmation, but its guard does not read %s"
                             % (r["id"], r.get("event"), self.pc_fact))
                elif g[self.pc_fact] is True and not r.get("stay"):
                    self.err("confirmation", "row '%s' acts on %s while %s is true; such a row must stay and refuse"
                             % (r["id"], r.get("event"), self.pc_fact))
            for en in self.pc_events:
                for i, nm in enumerate(events.get(en, {}).get("no_move_ok", [])):
                    if nm.get("when", {}).get(self.pc_fact) is not False:
                        self.err("confirmation", "event '%s' no_move_ok[%d] can let a job stay while %s is true; only a refusing row may"
                                 % (en, i, self.pc_fact))

        bw = rules.get("blocking_write")
        self.bw_fact, self.bw_park, self.bw_kinds = None, None, []
        if bw is not None:
            self.keys_ok(bw, BLOCKING_WRITE_ALLOWED, "rules.blocking_write")
            self.bw_fact, self.bw_park = bw.get("fact"), bw.get("park_state")
            self.bw_kinds = bw.get("kinds", [])
            if self.bw_fact not in facts:
                self.err("schema", "rules.blocking_write names undeclared fact '%s'" % self.bw_fact)
            if self.bw_park not in self.parked:
                self.err("schema", "rules.blocking_write.park_state '%s' is not a parked state" % self.bw_park)
        for r in self.rows:
            w = r.get("writes")
            if w is None:
                continue
            maps = w if isinstance(w, dict) else {"default": w}
            for fs, kinds in maps.items():
                if fs != "default" and fs not in r["from"]:
                    self.err("schema", "row '%s' writes maps '%s', which is not in from" % (r["id"], fs))
                if not isinstance(kinds, list):
                    self.err("schema", "row '%s' writes for '%s' is not a list" % (r["id"], fs))
                    continue
                for k in kinds:
                    if k not in self.bw_kinds:
                        self.err("schema", "row '%s' writes '%s', which rules.blocking_write.kinds does not list" % (r["id"], k))

        rm = rules.get("ready_mark")
        self.rm = None
        if rm is not None:
            self.keys_ok(rm, READY_MARK_ALLOWED, "rules.ready_mark")
            for s in rm.get("states", []):
                if s not in states:
                    self.err("schema", "rules.ready_mark names undeclared state '%s'" % s)
            for k in ("mark", "undo"):
                if rm.get(k) not in self.bw_kinds:
                    self.err("schema", "rules.ready_mark.%s '%s' is not a blocking write kind" % (k, rm.get(k)))
            if rm.get("missing_fact") is not None and rm["missing_fact"] not in facts:
                self.err("schema", "rules.ready_mark names undeclared fact '%s'" % rm["missing_fact"])
            if rm.get("resume_into") not in rm.get("states", []):
                self.err("schema", "rules.ready_mark.resume_into '%s' is not one of its states" % rm.get("resume_into"))
            self.rm = rm

        pk = rules.get("push_check")
        self.pk = None
        if pk is not None:
            self.keys_ok(pk, PUSH_CHECK_ALLOWED, "rules.push_check")
            if pk.get("write") not in self.bw_kinds:
                self.err("schema", "rules.push_check.write '%s' is not a blocking write kind" % pk.get("write"))
            if pk.get("fact") not in facts:
                self.err("schema", "rules.push_check names undeclared fact '%s'" % pk.get("fact"))
            if pk.get("to") not in self.parked:
                self.err("schema", "rules.push_check.to '%s' is not a parked state" % pk.get("to"))
            self.pk = pk

        self.as_if = []
        for i, x in enumerate(rules.get("records_as_if", [])):
            where = "rules.records_as_if[%d]" % i
            self.keys_ok(x, RECORDS_AS_IF_ALLOWED, where)
            r = self.by_id.get(x.get("row"))
            if r is None:
                self.err("schema", where + " names unknown row '%s'" % x.get("row"))
                continue
            if x.get("key") not in r.get("records", {}):
                self.err("schema", where + " names '%s', which row '%s' does not record" % (x.get("key"), r["id"]))
                continue
            if r.get("guard", {}).get(x.get("fact")) is not True:
                self.err("schema", where + " names fact '%s', which row '%s' does not require true" % (x.get("fact"), r["id"]))
                continue
            self.as_if.append(x)

        self.expectations = []
        for i, x in enumerate(d.get("expectations", [])):
            where = "expectation '%s'" % (x.get("id") if isinstance(x, dict) and x.get("id") else i)
            if not isinstance(x, dict):
                self.err("schema", where + " is not an object")
                continue
            self.keys_ok(x, EXPECT_ALLOWED, where)
            evs = x.get("events")
            if not isinstance(evs, list) or not evs:
                self.err("schema", where + " needs a non-empty events list")
                continue
            ok = True
            for en in evs:
                if en not in events:
                    self.err("schema", where + " names undeclared event '%s'" % en)
                    ok = False
            when = x.get("when", {})
            self._check_guard(when, where + " when")
            exp = x.get("expect")
            if not isinstance(exp, dict) or len(exp) != 1 or list(exp)[0] not in EXPECT_KINDS:
                self.err("schema", where + " needs an expect object with exactly one of %s" % ", ".join(EXPECT_KINDS))
                ok = False
            else:
                kind, val = list(exp.items())[0]
                if kind == "to":
                    for t in val:
                        if t not in states:
                            self.err("schema", where + " expects undeclared state '%s'" % t)
                elif kind == "rows":
                    for rid in val:
                        if rid not in self.by_id:
                            self.err("schema", where + " names unknown row '%s'" % rid)
            if not isinstance(x.get("why"), str) or not x["why"].strip():
                self.err("schema", where + " has no written why")
            if not ok:
                continue
            per = {}
            for en in evs:
                occ = events[en].get("occurs_in", [])
                sts = x.get("states") or occ
                for s in sts:
                    if s not in states:
                        self.err("schema", where + " names undeclared state '%s'" % s)
                    elif s not in occ:
                        self.err("expectation", where + " names state '%s', where event '%s' does not occur" % (s, en))
                    else:
                        per.setdefault(en, []).append(s)
                        self.check_defined(when, [s], where + " when")
            self.expectations.append({"where": where, "per": per, "when": when, "kind": list(exp)[0], "val": list(exp.values())[0], "hits": {}})

    def writes_for(self, r, s):
        w = r.get("writes")
        if w is None:
            return []
        if isinstance(w, dict):
            return w.get(s, w.get("default", [])) or []
        return w

    def is_confirm_park(self, r):
        return (self.bw_fact is not None and r.get("to") == self.bw_park
                and r.get("guard", {}).get(self.bw_fact) is True
                and "resume_state" in r.get("records", {}))

    def _check_guard(self, g, where):
        if not isinstance(g, dict):
            self.err("schema", where + " is not an object")
            return
        for f, v in g.items():
            if f not in self.d["facts"]:
                self.err("schema", "%s reads undeclared fact '%s'" % (where, f))
            if not isinstance(v, bool):
                self.err("schema", "%s gives fact '%s' a non-boolean value" % (where, f))

    # ---------------- 2. coverage ----------------
    def deps_for(self, state):
        out = []
        for dep in self.d.get("fact_dependencies", []):
            sts = dep.get("states")
            if sts is None or state in sts:
                out.append(dep)
        return out

    @staticmethod
    def agrees(guard, a):
        for f, v in guard.items():
            if a.get(f) != v:
                return False
        return True

    def consistent(self, a, deps):
        for dep in deps:
            cond = dep["if"]
            if all(f in a for f in cond) and self.agrees(cond, a):
                for f, v in dep["then"].items():
                    if f in a and a[f] != v:
                        return False
        return True

    def closure(self, facts, deps):
        facts = set(facts)
        changed = True
        while changed:
            changed = False
            for dep in deps:
                fs = set(dep["if"]) | set(dep["then"])
                if dep["if"] and (fs & facts) and not fs <= facts:
                    facts |= fs
                    changed = True
        return sorted(facts)

    def assignments_of(self, facts, deps):
        for bits in itertools.product((False, True), repeat=len(facts)):
            a = dict(zip(facts, bits))
            if self.consistent(a, deps):
                yield a

    def top_rows(self, rows, a):
        match = [r for r in rows if self.agrees(r.get("guard", {}), a)]
        if not match:
            return []
        best = min(r["precedence"] for r in match)
        return [r for r in match if r["precedence"] == best]

    def outcome_ok(self, x, w):
        kind, val = x["kind"], x["val"]
        if kind == "stays":
            return w is None or bool(w.get("stay"))
        if w is None:
            return False
        if kind == "rows":
            return w["id"] in val
        if w.get("stay"):
            return False
        return set(self.targets(w)) <= set(val)

    def coverage(self):
        events = self.d["events"]
        bwf = self.bw_fact
        for s in self.nonterm:
            for en, e in events.items():
                if s not in e.get("occurs_in", []):
                    continue
                self.pairs += 1
                rows = [r for r in self.rows if s in r["from"] and r.get("event") == en]
                nmo = [nm for nm in e.get("no_move_ok", []) if s in nm.get("states", [])]
                exps = [x for x in self.expectations if s in x["per"].get(en, [])]
                facts = set()
                for r in rows:
                    facts.update(r.get("guard", {}).keys())
                for nm in nmo:
                    facts.update(nm.get("when", {}).keys())
                for x in exps:
                    facts.update(x["when"].keys())
                    x["hits"][(s, en)] = 0
                if bwf and any(self.writes_for(r, s) for r in rows):
                    facts.add(bwf)
                pkf = self.pk["fact"] if self.pk else None
                if pkf and any(self.pk["write"] in self.writes_for(r, s) for r in rows):
                    facts.add(pkf)
                pf = self.pass_first
                if pf and en == pf["event"]:
                    facts.update(pf["when"].keys())
                deps = self.deps_for(s)
                facts = self.closure(facts, deps)
                if len(facts) > MAX_FACTS_PER_PAIR:
                    self.err("coverage", "(%s, %s) reads %d facts, more than %d" % (s, en, len(facts), MAX_FACTS_PER_PAIR))
                    self.unchecked.add((s, en))
                    continue
                if not rows and not nmo:
                    self.err("coverage", "(%s, %s): the event can occur but no row handles it and no no_move_ok entry allows staying" % (s, en))
                    continue
                self.pair_info[(s, en)] = (rows, facts, deps)
                count = 0
                for a in self.assignments_of(facts, deps):
                    wants_park = None
                    if bwf in a and a[bwf]:
                        # blocking_write_confirm is derived: it can be true only
                        # when the row that wins with it false makes a write.
                        a0 = dict(a)
                        a0[bwf] = False
                        if not self.consistent(a0, deps):
                            continue
                        top0 = self.top_rows(rows, a0)
                        if len(top0) != 1 or not self.writes_for(top0[0], s):
                            continue
                        wants_park = top0[0]
                    wants_freeze = None
                    if pkf in a and a[pkf]:
                        # The pre-push check is derived the same way: it can
                        # fail only when the row that wins with it false pushes.
                        a1 = dict(a)
                        a1[pkf] = False
                        if not self.consistent(a1, deps):
                            continue
                        top1 = self.top_rows(rows, a1)
                        if len(top1) != 1 or self.pk["write"] not in self.writes_for(top1[0], s):
                            continue
                        wants_freeze = top1[0]
                    count += 1
                    self.assignments += 1
                    top = self.top_rows(rows, a)
                    w = top[0] if len(top) == 1 else None
                    if not top:
                        if not any(self.agrees(nm.get("when", {}), a) for nm in nmo):
                            self.err("coverage", "(%s, %s) has no matching row when %s" % (s, en, fmt_assign(a)))
                            continue
                    else:
                        for r in top:
                            self.wins.add((r["id"], s))
                        if len(top) > 1:
                            self.err("precedence", "(%s, %s) tie at precedence %d between rows %s when %s"
                                     % (s, en, top[0]["precedence"], fmt_ids([r["id"] for r in top]), fmt_assign(a)))
                            continue
                    if wants_park is not None and (w is None or not self.is_confirm_park(w)):
                        self.err("blocking_write", "(%s, %s): row '%s' makes the blocking write(s) %s, but when %s is true %s instead of a row that parks in %s recording resume_state; when %s"
                                 % (s, en, wants_park["id"], ", ".join(self.writes_for(wants_park, s)), bwf,
                                    "no row matches" if w is None else "row '%s' wins" % w["id"], self.bw_park, fmt_assign(a)))
                    if wants_freeze is not None and (w is None or w.get("stay") or self.targets(w) != [self.pk["to"]]
                                                     or self.pk["write"] in self.writes_for(w, s)):
                        self.err("push_check", "(%s, %s): row '%s' pushes, but when %s is true %s instead of a row that moves the job to %s without a push; when %s"
                                 % (s, en, wants_freeze["id"], pkf,
                                    "no row matches" if w is None else "row '%s' wins (%s)" % (w["id"], to_text(w)),
                                    self.pk["to"], fmt_assign(a)))
                    if pf and en == pf["event"] and self.agrees(pf["when"], a) and (w is None or w["id"] not in pf["rows"]):
                        self.err("pass_first", "(%s, %s): %s, but pass_first applies only rows %s before every event of event_order; when %s"
                                 % (s, en, "no row matches" if w is None else "row '%s' wins" % w["id"],
                                    fmt_ids(pf["rows"]), fmt_assign(a)))
                    for x in exps:
                        if self.agrees(x["when"], a):
                            x["hits"][(s, en)] += 1
                            if not self.outcome_ok(x, w):
                                self.err("expectation", "%s: in (%s, %s) %s, but %s; when %s"
                                         % (x["where"], s, en, self.expect_text(x),
                                            "no row matches and the job stays" if w is None else
                                            "row '%s' wins (%s)" % (w["id"], to_text(w)), fmt_assign(a)))
                if count == 0:
                    self.err("coverage", "(%s, %s) has no fact assignment that the fact dependencies allow, so nothing is checked; the dependencies for %s contradict each other" % (s, en, s))
                    self.unchecked.add((s, en))
                    continue
                for x in exps:
                    if x["hits"].get((s, en)) == 0:
                        self.err("expectation", "%s never applies in (%s, %s): no fact assignment the dependencies allow agrees with its when" % (x["where"], s, en))

    @staticmethod
    def expect_text(x):
        if x["kind"] == "stays":
            return "the job must stay"
        if x["kind"] == "rows":
            return "one of rows %s must win" % fmt_ids(x["val"])
        return "the job must move to %s" % " or ".join(x["val"])

    # ---------------- records as if ----------------
    def records_as_if(self):
        # A row that parks because of one fact records, for each from-state,
        # exactly the targets that the rows winning with that fact false would
        # have entered, so the resume lands where the stage's own row would.
        for x in self.as_if:
            r = self.by_id[x["row"]]
            f, key = x["fact"], x["key"]
            m = r["records"][key]
            for s in r["from"]:
                info = self.pair_info.get((s, r.get("event")))
                if info is None:
                    continue
                rows, facts, deps = info
                want = set()
                for a in self.assignments_of(facts, deps):
                    if self.bw_fact in a and a[self.bw_fact]:
                        continue
                    top = self.top_rows(rows, a)
                    if len(top) != 1 or top[0]["id"] != r["id"]:
                        continue
                    a0 = dict(a)
                    a0[f] = False
                    if not self.consistent(a0, deps):
                        continue
                    top0 = self.top_rows(rows, a0)
                    if len(top0) != 1 or top0[0].get("stay"):
                        self.err("records_as_if", "row '%s' in %s: with %s false no single row moves the job, so there is nothing to record; when %s"
                                 % (r["id"], s, f, fmt_assign(a)))
                        continue
                    want |= set(self.targets(top0[0]))
                v = m.get(s, m.get("default"))
                have = set(s if t == "$from" else t for t in (v if isinstance(v, list) else [v]))
                if have != want:
                    self.err("records_as_if", "row '%s' records %s = %s for %s, but with %s false the winning rows enter %s"
                             % (r["id"], key, sorted(have), s, f, sorted(want)))

    # ---------------- no_move_ok literals ----------------
    def no_move_literals(self):
        for en, e in self.d["events"].items():
            for i, nm in enumerate(e.get("no_move_ok", [])):
                when = nm.get("when", {})
                if not isinstance(when, dict) or "__empty__" in when:
                    continue
                for s in nm.get("states", []):
                    deps = self.deps_for(s)
                    facts = self.closure(when.keys(), deps)
                    if len(facts) > MAX_FACTS_PER_PAIR:
                        continue
                    open_lits = set()
                    for a in self.assignments_of(facts, deps):
                        for f, v in when.items():
                            if a.get(f) != v:
                                open_lits.add(f)
                    for f in sorted(when):
                        if f not in open_lits:
                            self.err("no_move_ok", "event '%s' no_move_ok[%d] reads %s=%s in state '%s', which the fact dependencies force there, so that literal names no condition"
                                     % (en, i, f, "true" if when[f] else "false", s))

    # ---------------- declared writes ----------------
    def declared_writes(self):
        # A row that requires blocking_write_confirm false does so because it
        # writes; it must list that write, or the derived fact never parks it.
        if not self.bw_fact:
            return
        for r in self.rows:
            if r.get("guard", {}).get(self.bw_fact) is not False:
                continue
            for s in r["from"]:
                if not self.writes_for(r, s):
                    self.err("blocking_write", "row '%s' requires %s false but lists no write for %s; list the blocking writes it makes in 'writes'"
                             % (r["id"], self.bw_fact, s))

    # ---------------- ready mark ----------------
    def ready_mark(self):
        rm = self.rm
        if not rm:
            return
        marked = set(rm.get("states", []))
        missing = rm.get("missing_fact")
        for r in self.rows:
            if r.get("stay"):
                continue
            for s in r["from"]:
                if not self.live(r, s):
                    continue
                for t in self.targets(r):
                    tk = self.d["states"].get(t, {}).get("kind")
                    if s in marked:
                        if tk == "terminal" or t in marked or self.is_confirm_park(r):
                            continue
                        if missing and r.get("guard", {}).get(missing) is True:
                            continue
                        if rm["undo"] not in self.writes_for(r, s):
                            self.err("ready_mark", "row '%s' moves a job from %s, where the PR is marked ready, to %s without '%s' in its writes"
                                     % (r["id"], s, t, rm["undo"]))
                    elif t in marked and r.get("to") == t:
                        if rm["mark"] not in self.writes_for(r, s):
                            self.err("ready_mark", "row '%s' moves a job from %s into %s, where the PR is marked ready, without '%s' in its writes"
                                     % (r["id"], s, t, rm["mark"]))
            # A computed target is checked too: only the resume rows that
            # follow the undo of ready may resume a job into a marked state.
            if r.get("to") in COMPUTED:
                into = sorted(set(self.targets(r)) & marked)
                if into and r["id"] not in READY_RESUME_ROWS:
                    self.err("ready_mark", "row '%s' can resume a job into %s, where the PR is marked ready; only rows %s may, after the undo of ready"
                             % (r["id"], ", ".join(into), fmt_ids(READY_RESUME_ROWS)))
            # A row may record a marked state only from a marked from-state:
            # a park taken where the PR is a draft never resumes into ready.
            for key, m in r.get("records", {}).items():
                for fs in r["from"]:
                    v = m.get(fs, m.get("default"))
                    if v is None or fs in marked:
                        continue
                    got = set(fs if x == "$from" else x for x in (v if isinstance(v, list) else [v]))
                    for t in sorted(got & marked):
                        self.err("ready_mark", "row '%s' records %s %s for %s, where the PR is not marked ready; only a park from %s may record a state where it is"
                                 % (r["id"], key, t, fs, ", ".join(sorted(marked))))
            # A confirm park taken where the PR is marked ready resumes into
            # rules.ready_mark.resume_into, where the held event is replayed.
            if self.is_confirm_park(r):
                for s in r["from"]:
                    if s not in marked or not self.live(r, s):
                        continue
                    m = r["records"]["resume_state"]
                    v = m.get(s, m.get("default"))
                    got = set(s if x == "$from" else x for x in (v if isinstance(v, list) else [v]))
                    if got != {rm["resume_into"]}:
                        self.err("ready_mark", "row '%s' parks a job from %s, where the PR is marked ready, recording resume_state %s; it must resume into %s"
                                 % (r["id"], s, sorted(got), rm["resume_into"]))

    def dead_rows(self):
        for r in self.rows:
            for s in r["from"]:
                if (s, r.get("event")) in self.unchecked:
                    continue
                if (r["id"], s) not in self.wins:
                    self.err("dead", "row '%s' never wins in state '%s': for every fact assignment the dependencies allow, another row with a lower precedence matches or its guard contradicts the dependencies; remove the state from the row or fix the guard" % (r["id"], s))

    def live(self, r, s):
        return (r["id"], s) in self.wins or (s, r.get("event")) in self.unchecked

    # ---------------- 3. derived In / Out ----------------
    def targets(self, r):
        if r.get("stay"):
            return []
        to = r.get("to")
        if to in COMPUTED:
            return list(r.get("resume", []))
        return [to]

    def derive(self):
        st = self.d["states"]
        self.inl = dict((s, []) for s in st)
        self.outl = dict((s, []) for s in st)
        self.stays = dict((s, []) for s in st)
        for c in self.d.get("creation", []):
            if c.get("to") in self.inl:
                self.inl[c["to"]].append(c["id"])
        for r in self.rows:
            live_from = [s for s in r["from"] if self.live(r, s)]
            for s in live_from:
                if r.get("stay"):
                    self.stays.setdefault(s, []).append(r["id"])
                else:
                    self.outl.setdefault(s, []).append(r["id"])
            if live_from:
                for t in self.targets(r):
                    if t in self.inl:
                        self.inl[t].append(r["id"])

    # ---------------- resume consistency ----------------
    def recorded_values(self, r, key):
        m = r.get("records", {}).get(key)
        if not m:
            return None
        out = set()
        for fs in r["from"]:
            v = m.get(fs, m.get("default"))
            if v is None:
                self.err("resume", "row '%s' records no '%s' for from-state '%s'" % (r["id"], key, fs))
                continue
            for x in (v if isinstance(v, list) else [v]):
                t = fs if x == "$from" else x
                if x == "$from" and self.d["states"].get(t, {}).get("kind") != "active":
                    self.err("resume", "row '%s' records %s = $from for from-state '%s', a %s state; a job resumes only into an active state"
                             % (r["id"], key, t, self.d["states"].get(t, {}).get("kind")))
                out.add(t)
        return out

    def resume_check(self):
        self.resume_srcs = {}
        consumed = set()
        named = {}
        for r in self.rows:
            to = r.get("to")
            if to not in COMPUTED:
                continue
            key = to
            frm = r["from"]
            if len(frm) != 1 or frm[0] not in self.parked:
                self.err("resume", "row '%s' moves to '%s' but does not start from exactly one parked state" % (r["id"], key))
                continue
            p = frm[0]
            entering = [x for x in self.rows if x.get("to") == p and not x.get("stay")]
            rf = r.get("resume_from")
            if rf == "*":
                srcs = []
                for x in entering:
                    if key in x.get("records", {}):
                        srcs.append(x)
                    else:
                        self.err("resume", "row '%s' enters %s without recording %s, which row '%s' reads" % (x["id"], p, key, r["id"]))
            elif isinstance(rf, list):
                srcs = []
                for i in rf:
                    x = self.by_id.get(i)
                    if x is None:
                        self.err("resume", "row '%s' resume_from names unknown row '%s'" % (r["id"], i))
                    elif x.get("to") != p or key not in x.get("records", {}):
                        self.err("resume", "row '%s' resume_from names row '%s', which does not enter %s recording %s" % (r["id"], i, p, key))
                    else:
                        srcs.append(x)
            else:
                self.err("resume", "row '%s' resume_from must be a list of row ids or \"*\"" % r["id"])
                continue
            named.setdefault((p, key), set()).update(x["id"] for x in srcs)
            self.resume_srcs[r["id"]] = srcs
            want = set()
            for x in srcs:
                consumed.add((x["id"], key))
                v = self.recorded_values(x, key)
                if v:
                    want |= v
            have = set(r.get("resume", []))
            if have != want:
                self.err("resume", "row '%s' resume lists %s, but rows %s record %s (missing %s, extra %s)"
                         % (r["id"], sorted(have), fmt_ids([x["id"] for x in srcs]), sorted(want),
                            sorted(want - have) or "-", sorted(have - want) or "-"))
        for x in self.rows:
            for key in x.get("records", {}):
                if (x["id"], key) not in consumed:
                    self.err("resume", "row '%s' records %s on entering %s, but no row of that state reads it" % (x["id"], key, x.get("to")))
        for (p, key), ids in sorted(named.items()):
            for x in self.rows:
                if x.get("to") != p or x.get("stay"):
                    continue
                if key not in x.get("records", {}):
                    self.err("resume", "row '%s' enters %s without recording %s, which a resume row of %s reads" % (x["id"], p, key, p))
                elif x["id"] not in ids:
                    self.err("resume", "row '%s' enters %s recording %s, but no resume row of %s names it in resume_from" % (x["id"], p, key, p))

    # ---------------- 4. reachability ----------------
    def reach(self):
        # Forward reachability counts an edge from a parked state p to a
        # resume target t only when a parking row that p's resume row reads
        # wins in a reachable from-state other than t and records t there. A
        # park taken in t itself is not a way into t. The backward checks
        # (terminal and goal) use every resume target.
        st = self.d["states"]
        fixed = dict((s, set()) for s in st)
        full = dict((s, set()) for s in st)
        resume = []
        for r in self.rows:
            for s in r["from"]:
                if not self.live(r, s) or s not in st:
                    continue
                for t in self.targets(r):
                    if t in st:
                        full[s].add(t)
                        if r.get("to") not in COMPUTED:
                            fixed[s].add(t)
                if r.get("to") in COMPUTED:
                    resume.append((s, r))
        starts = sorted(set(c.get("to") for c in self.d.get("creation", []) if c.get("to") in st)) or [self.initial]
        succ = dict((s, set(ts)) for s, ts in fixed.items())
        seen = set()
        changed = True
        while changed:
            seen = set(starts)
            todo = list(starts)
            while todo:
                s = todo.pop()
                for t in succ.get(s, ()):
                    if t not in seen:
                        seen.add(t)
                        todo.append(t)
            changed = False
            for p, r in resume:
                if p not in seen:
                    continue
                key = r["to"]
                for x in self.resume_srcs.get(r["id"], []):
                    m = x.get("records", {}).get(key, {})
                    for fs in x["from"]:
                        if fs not in seen or not self.live(x, fs):
                            continue
                        v = m.get(fs, m.get("default"))
                        if v is None:
                            continue
                        for y in (v if isinstance(v, list) else [v]):
                            t = fs if y == "$from" else y
                            if t != fs and t in r.get("resume", []) and t not in succ[p]:
                                succ[p].add(t)
                                changed = True
        self.forward_seen = seen
        for s in st:
            if s not in seen:
                self.err("reachability", "state '%s' is unreachable from the creation target %s" % (s, " or ".join(starts)))
        pred = dict((s, set()) for s in st)
        for s, ts in full.items():
            for t in ts:
                pred[t].add(s)

        def back(goals):
            can = set(goals)
            todo = list(goals)
            while todo:
                s = todo.pop()
                for p in pred.get(s, ()):
                    if p not in can:
                        can.add(p)
                        todo.append(p)
            return can
        can = back(self.terminal)
        for s in self.nonterm:
            if s not in can:
                self.err("reachability", "state '%s' cannot reach a terminal state" % s)
        if self.goal in st:
            can = back([self.goal])
            for s in self.nonterm:
                if s not in can:
                    self.err("reachability", "state '%s' cannot reach %s, so a job there can only end, never finish its work" % (s, self.goal))

    # ---------------- required expectations ----------------
    def required_expectations(self):
        have = set(x.get("id") for x in self.d.get("expectations", []) if isinstance(x, dict))
        for i in REQUIRED_EXPECTATIONS:
            if i not in have:
                self.err("expectation", "required expectation '%s' is missing from the table" % i)

    # ---------------- 5. parked exits ----------------
    def parked_exits(self):
        ev = self.d["events"]
        st = self.d["states"]
        for p in self.parked:
            exits = [r for r in self.rows if p in r["from"] and not r.get("stay") and self.live(r, p)
                     and any(st.get(t, {}).get("kind") == "active" for t in self.targets(r))]
            if not any(ev.get(r.get("event"), {}).get("kind") == "person" for r in exits):
                self.err("parked", "parked state '%s' has no exit row into an active state on a person event" % p)
            if not any(r.get("event") == "github_change" for r in exits):
                self.err("parked", "parked state '%s' has no exit row into an active state on github_change" % p)

    def run(self):
        if not self.schema():
            return False
        self.no_move_literals()
        self.coverage()
        self.required_expectations()
        self.dead_rows()
        self.derive()
        self.resume_check()
        self.reach()
        self.parked_exits()
        self.ready_mark()
        self.declared_writes()
        self.records_as_if()
        return not self.errors

    # ---------------- output ----------------
    def table_lines(self):
        st = self.d["states"]
        w = max(len(s) for s in st)
        lines = []
        for s, v in st.items():
            lines.append("%-*s  %-8s  In: %s" % (w, s, v["kind"], fmt_ids(self.inl[s])))
            lines.append("%-*s  %-8s  Out: %s" % (w, "", "", fmt_ids(self.outl[s])))
            if self.stays[s]:
                lines.append("%-*s  %-8s  Stays: %s" % (w, "", "", fmt_ids(self.stays[s])))
        return lines


def md_escape(t):
    return str(t).replace("|", "\\|").replace("\n", " ")


def guard_text(g):
    if not g:
        return "(always)"
    return ", ".join(("%s" if v else "not %s") % k for k, v in g.items())


def to_text(r):
    if r.get("stay"):
        return "(stays)"
    if r["to"] in ("resume_state", "blocked_stage"):
        return "%s: %s" % (r["to"], ", ".join(r["resume"]))
    return r["to"]


def writes_text(r):
    w = r.get("writes")
    if not w:
        return ""
    if isinstance(w, dict):
        return "; ".join("%s: %s" % (fs, ", ".join(k)) for fs, k in w.items())
    return ", ".join(w)


def expect_md(x):
    (kind, val), = x["expect"].items()
    if kind == "stays":
        return "the job stays"
    if kind == "rows":
        return "row %s wins" % " or ".join(val)
    return "the job moves to %s" % " or ".join(val)


def write_markdown(c, json_path, md_path):
    d = c.d
    L = []
    L.append("# %s" % d.get("title", "Job state machine"))
    L.append("")
    L.append("> Generated by `check_transitions.py --markdown` from `%s`. Do not edit this file by hand; edit the JSON and run the checker again." % os.path.basename(json_path))
    L.append("")
    if d.get("about"):
        L.append(d["about"])
        L.append("")
    if d.get("conventions"):
        L.append("## How to read the table")
        L.append("")
        for k, v in d["conventions"].items():
            L.append("- **%s.** %s" % (k, v))
        L.append("")
    L.append("## States, with derived entry and exit rows")
    L.append("")
    L.append("In lists every row that can move a job into the state, including resume rows for each target they list. Out lists every row that moves a job out of it. Stays lists rows that apply effects and leave the job where it is. A row is listed for a from-state only when it wins at least one fact assignment there.")
    L.append("")
    L.append("| State | Kind | Run by | Meaning | In | Out | Stays |")
    L.append("|---|---|---|---|---|---|---|")
    for s, v in d["states"].items():
        kind = v["kind"] + (" (phase %d)" % v["phase"] if v.get("phase") else "")
        L.append("| %s | %s | %s | %s | %s | %s | %s |" % (s, kind, v.get("run_by", "-"), md_escape(v["meaning"]), fmt_ids(c.inl[s]), fmt_ids(c.outl[s]), fmt_ids(c.stays[s])))
    L.append("")
    L.append("## Rows")
    L.append("")
    L.append("Rows are grouped by event. Within one state and event, the lowest precedence number applies.")
    L.append("")
    for c0 in d.get("creation", []):
        L.append("Row %s (creation, event %s) moves a new job to %s when: %s. Effects: %s." % (
            c0["id"], c0["event"], c0["to"], "; ".join(c0.get("conditions", [])), "; ".join(c0.get("effects", []))))
        L.append("")
    order = d.get("event_order") or list(d["events"].keys())
    for en in order:
        rs = [r for r in c.rows if r.get("event") == en]
        if not rs:
            continue
        L.append("### %s" % en)
        L.append("")
        L.append(md_escape(d["events"][en]["meaning"]))
        L.append("")
        L.append("| Row | From | Guard | To | Prec. | Effects | Writes | Records |")
        L.append("|---|---|---|---|---|---|---|---|")
        for r in sorted(rs, key=lambda x: (x["precedence"], id_key(x["id"]))):
            rec = []
            for k, m in r.get("records", {}).items():
                rec.append("%s: %s" % (k, ", ".join("%s=%s" % (fs, v if not isinstance(v, list) else "/".join(v)) for fs, v in m.items())))
            eff = "; ".join(r.get("effects", []))
            if r.get("note"):
                eff = (eff + ". " if eff else "") + "Note: " + r["note"]
            frm = r["from"]
            frm_t = ", ".join(frm) if len(frm) <= 6 else "%d states: %s" % (len(frm), ", ".join(frm))
            pid = r["id"] + (" (phase %d)" % r["phase"] if r.get("phase") else "")
            L.append("| %s | %s | %s | %s | %d | %s | %s | %s |" % (
                pid, md_escape(frm_t), md_escape(guard_text(r.get("guard", {}))), md_escape(to_text(r)),
                r["precedence"], md_escape(eff), md_escape(writes_text(r)) or "-", md_escape("; ".join(rec)) or "-"))
        nmo = d["events"][en].get("no_move_ok", [])
        if nmo:
            L.append("")
            L.append("When no row matches, the job stays only in these cases:")
            L.append("")
            for nm in nmo:
                L.append("- %s, when %s: %s" % (", ".join(nm["states"]), guard_text(nm.get("when", {})), nm["reason"]))
        L.append("")
    rules = d.get("rules", {})
    if rules or d.get("expectations"):
        L.append("## Rules the checker enforces")
        L.append("")
        if rules.get("initial_state"):
            L.append("- **Creation.** Every creation row targets %s, and reachability starts there." % rules["initial_state"])
        if rules.get("goal_state"):
            L.append("- **Goal.** Every non-terminal state can reach %s through winning rows, not only end the job." % rules["goal_state"])
        pc = rules.get("person_confirmation")
        if pc:
            L.append("- **Person confirmation.** Every row on %s reads %s. A row that reads it true stays and refuses, and no no_move_ok entry of those events lets a job stay while it is true. %s"
                     % (", ".join(pc["events"]), pc["fact"], pc.get("why", "")))
        bw = rules.get("blocking_write")
        if bw:
            L.append("- **Blocking writes.** %s is derived: it can be true only when the row that wins with it false lists a write (%s), and then a row that parks in %s recording resume_state must win. %s"
                     % (bw["fact"], ", ".join(bw.get("kinds", [])), bw["park_state"], bw.get("why", "")))
        rm = rules.get("ready_mark")
        if rm:
            L.append("- **Ready mark.** A row that moves a job out of %s to a non-terminal state outside them lists '%s', unless it is a confirm park or its guard reads %s true; a row that enters one of them from elsewhere lists '%s'. Only rows %s may resume a job into one of them, a row may record one of them only from one of them, and a confirm park taken in one of them records resume_state %s. %s"
                     % (", ".join(rm["states"]), rm["undo"], rm.get("missing_fact", "-"), rm["mark"],
                        ", ".join(READY_RESUME_ROWS), rm.get("resume_into", "-"), rm.get("why", "")))
        pk = rules.get("push_check")
        if pk:
            L.append("- **Push check.** %s is derived: it can be true only when the row that wins with it false lists '%s', and then a row that moves the job to %s without a push must win. %s"
                     % (pk["fact"], pk["write"], pk["to"], pk.get("why", "")))
        pf = d.get("pass_first")
        if pf:
            L.append("- **Pass first.** On %s, whenever %s, one of rows %s wins in every state where the event occurs; these rows apply before every event of event_order. %s"
                     % (pf["event"], guard_text(pf["when"]), ", ".join(pf["rows"]), pf.get("why", "")))
        for x in rules.get("records_as_if", []):
            L.append("- **Records as if.** Row %s records %s, for each from-state, as the targets the rows winning with %s false enter. %s" % (x["row"], x["key"], x["fact"], x.get("why", "")))
        L.append("- **no_move_ok literals.** Every literal of a no_move_ok \"when\" is left open by the fact dependencies in each of its states.")
        L.append("")
        if d.get("expectations"):
            L.append("Expected outcomes. The checker requires every id below to be present. In each listed state, for every fact assignment the dependencies allow that agrees with \"When\", the winning row must give the outcome; each must apply at least once in each state.")
            L.append("")
            L.append("| Id | Events | States | When | Outcome | Why |")
            L.append("|---|---|---|---|---|---|")
            for x in d["expectations"]:
                sts = x.get("states")
                sts_t = "every state where the event occurs" if not sts else (", ".join(sts) if len(sts) <= 6 else "%d states: %s" % (len(sts), ", ".join(sts)))
                L.append("| %s | %s | %s | %s | %s | %s |" % (x["id"], ", ".join(x["events"]), md_escape(sts_t), md_escape(guard_text(x.get("when", {}))), md_escape(expect_md(x)), md_escape(x.get("why", ""))))
            L.append("")
    L.append("## Facts")
    L.append("")
    L.append("| Fact | Meaning | Defined in |")
    L.append("|---|---|---|")
    for f, v in d["facts"].items():
        L.append("| %s | %s | %s |" % (f, md_escape(v["meaning"]), ", ".join(v.get("defined_in", [])) or "every non-terminal state"))
    L.append("")
    L.append("## Fact dependencies")
    L.append("")
    for dep in d.get("fact_dependencies", []):
        where = " (in %s)" % ", ".join(dep["states"]) if dep.get("states") else ""
        cond = guard_text(dep["if"]) if dep["if"] else "always"
        L.append("- %s%s implies %s. %s" % (cond, where, guard_text(dep["then"]), dep.get("why", "")))
    L.append("")
    L.append("## Events")
    L.append("")
    L.append("| Event | Kind | Can occur in |")
    L.append("|---|---|---|")
    for en in order:
        e = d["events"][en]
        L.append("| %s | %s | %s |" % (en, e["kind"], ", ".join(e["occurs_in"]) or "(creation only)"))
    for en, e in d["events"].items():
        if en not in order:
            L.append("| %s | %s | %s |" % (en, e["kind"], ", ".join(e["occurs_in"]) or "(creation only)"))
    L.append("")
    L.append("## Check result")
    L.append("")
    L.append("%d states, %d events, %d facts, %d rows, %d expectations; %d (state, event) pairs and %d fact assignments checked; 0 errors." % (
        len(d["states"]), len(d["events"]), len(d["facts"]), len(c.rows) + len(d.get("creation", [])), len(d.get("expectations", [])), c.pairs, c.assignments))
    L.append("")
    with open(md_path, "w") as f:
        f.write("\n".join(L))


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = [a for a in argv[1:] if a.startswith("--")]
    for f in flags:
        if f != "--markdown":
            print("unknown option %s" % f)
            return 2
    path = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "transitions.json")
    try:
        with open(path) as fh:
            data = json.load(fh, object_pairs_hook=no_duplicates)
    except (IOError, OSError, ValueError) as exc:
        print("FAIL: cannot read %s: %s" % (path, exc))
        return 1
    c = Checker(data)
    ok = c.run()
    if hasattr(c, "inl"):
        print("Entry and exit lists (derived from the rows):")
        for line in c.table_lines():
            print("  " + line)
        print("")
    if not ok:
        for e in c.errors:
            print("ERROR " + e)
        print("")
        print("FAIL: %d error(s) in %s" % (len(c.errors), path))
        return 1
    print("Checks passed: 1 schema and occurrence rules, 2 guard coverage, precedence and winning rows, 3 derived entry and exit lists, 4 reachability from the creation target and to the goal state, 5 parked exits into active states, resume targets; rules: person confirmation, blocking writes, ready mark, push check, pass first, records as if, no_move_ok literals; %d expectations (%d required by id)."
          % (len(c.expectations), len(REQUIRED_EXPECTATIONS)))
    print("Summary: %d states (%d parked, %d terminal), %d events, %d facts, %d rows; %d (state, event) pairs, %d fact assignments checked."
          % (len(c.d["states"]), len(c.parked), len(c.terminal), len(c.d["events"]), len(c.d["facts"]),
             len(c.rows) + len(c.d.get("creation", [])), c.pairs, c.assignments))
    if "--markdown" in flags:
        md = os.path.join(os.path.dirname(os.path.abspath(path)), "transitions.md")
        write_markdown(c, path, md)
        print("Wrote %s" % md)
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
