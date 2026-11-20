---
issue: 355
created: '2026-11-18T09:42:07Z'
artifacts:
- type: workflow-run
  captured_at: '2026-11-18T09:42:07Z'
  workflow: start-issue
  run_id: 2026-11-18T094033Z-issue-355
  status: active
- type: escalation-asked
  captured_at: '2026-11-18T10:46:09Z'
  question_id: q-20261118T104609Z-8246da
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation:
  - 'Malformed intake result: AC4 says one retry'
  - the table allows three runs per stage
- type: escalation-asked
  captured_at: '2026-11-18T10:46:10Z'
  question_id: q-20261118T104610Z-87fcad
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: P8 never ran; GitHub role_name triage unverified
- type: escalation-asked
  captured_at: '2026-11-18T10:46:10Z'
  question_id: q-20261118T104610Z-92e751
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: Design names label re-add as re-vouch but no row does it
- type: escalation-asked
  captured_at: '2026-11-18T10:46:11Z'
  question_id: q-20261118T104611Z-56c2f1
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: P2 stop_caps and task_completed_refusals assigned to 355 but no 1b line
    builds them
- type: escalation-asked
  captured_at: '2026-11-18T10:46:11Z'
  question_id: q-20261118T104611Z-57f301
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: 'P2 re-run blocked by spend cap: 21.11 spent + 4.00 limit > 25 cap'
- type: escalation-asked
  captured_at: '2026-11-18T10:46:12Z'
  question_id: q-20261118T104612Z-27bd5a
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: P9 needs the user to run two interactive sessions with the 1b plugin
- type: escalation-asked
  captured_at: '2026-11-18T10:46:13Z'
  question_id: q-20261118T104612Z-9d0fa7
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: Person subcommands in modes other than default and auto
- type: escalation-asked
  captured_at: '2026-11-18T10:46:13Z'
  question_id: q-20261118T104613Z-051673
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation:
  - issueUpdate list misses close
  - reopen
  - REST and GraphQL issue edit forms
- type: escalation-asked
  captured_at: '2026-11-18T10:46:14Z'
  question_id: q-20261118T104613Z-5edacb
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: Push and draft-PR writes filed as 1b but need the 1e pre-push check
- type: escalation-asked
  captured_at: '2026-11-18T10:46:14Z'
  question_id: q-20261118T104614Z-00a110
  blocking: 'yes'
  class: decision
  command: /flow:start 355 (planning)
  situation: Most new rows are shown only through the test entry point until 1c/1e/1g
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:40Z'
  escalation_field: options
  outcome:
  - Keep three runs; reword AC4
  - design stages L43
  - settings_keys L18
  question_id: q-20261118T104609Z-8246da
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:41Z'
  escalation_field: options
  outcome: 'Design fallback: triage counts as read unless role_name triage; triage
    paths shown with fixtures'
  question_id: q-20261118T104610Z-87fcad
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:42Z'
  escalation_field: options
  outcome: Drop it from the design text
  question_id: q-20261118T104610Z-92e751
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:42Z'
  escalation_field: options
  outcome: Measure in 1b with P2; build warn fallback only on no-go
  question_id: q-20261118T104611Z-56c2f1
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:43Z'
  escalation_field: options
  outcome: Both
  question_id: q-20261118T104611Z-57f301
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:44Z'
  escalation_field: options
  outcome: Before the 1b PR merges
  question_id: q-20261118T104612Z-27bd5a
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:44Z'
  escalation_field: options
  outcome:
  - Deny outside default
  - as designed
  question_id: q-20261118T104612Z-9d0fa7
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:45Z'
  escalation_field: options
  outcome: Add them to issueUpdate
  question_id: q-20261118T104613Z-051673
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:45Z'
  escalation_field: options
  outcome: Move them to 1e; 1b only stops rebuild reading head_sha from the clone
  question_id: q-20261118T104613Z-5edacb
- type: escalation-resolved
  captured_at: '2026-11-18T11:27:46Z'
  escalation_field: options
  outcome: Add one line saying so to issue 355
  question_id: q-20261118T104614Z-00a110
- type: default-taken
  captured_at: '2026-11-18T11:27:46Z'
  command: /flow:start 355 planning
  choice: Q4 shared 1b effect texts handled for needs_human rows too (no table change)
- type: default-taken
  captured_at: '2026-11-18T11:27:47Z'
  command: /flow:start 355 planning
  choice:
  - Q10 row 41p shown through the seam in 1b
  - end to end in 1c
- type: default-taken
  captured_at: '2026-11-18T11:27:48Z'
  command: /flow:start 355 planning
  choice:
  - Q12 notices under issueUpdate confirm stay non-blocking
  - PENDING_CONFIRM printed
- type: default-taken
  captured_at: '2026-11-18T11:27:48Z'
  command: /flow:start 355 planning
  choice: 'Q13 dependency_open reads same-repo #N on Depends on and Blocked by lines'
- type: default-taken
  captured_at: '2026-11-18T11:27:49Z'
  command: /flow:start 355 planning
  choice: Q15 issueUpdate docs parity check covers plugins/flow only
- type: escalation-asked
  captured_at: '2026-11-18T13:04:25Z'
  question_id: q-20261118T130425Z-504b75
  blocking: soft
  class: decision
  command: /flow:start 355 plan
  situation:
  - A needs-info question has no choices
  - so the design's comment form '/flow-factory answer <id> <n>' has no meaning for
    an NI-<k> id. The comment form of answer for needs-info must be chosen.
- type: escalation-resolved
  captured_at: '2026-11-18T13:43:56Z'
  escalation_field: options
  outcome: '''/flow-factory answer NI-<k> <text>'': the rest of line 1 after the id
    is the answer (recommended)'
  question_id: q-20261118T130425Z-504b75
- type: escalation-asked
  captured_at: '2026-11-18T13:43:57Z'
  question_id: q-20261118T134357Z-76be86
  blocking: 'no'
  class: default
  command: /flow:start 355 plan
  situation: 'Q16: what a terminal confirm of a notice waiting under issueUpdate:
    confirm does.'
- type: escalation-resolved
  captured_at: '2026-11-18T13:43:58Z'
  escalation_field: options
  outcome: Mark it confirmed so the next drain sends it (follows the design)
  question_id: q-20261118T134357Z-76be86
- type: escalation-asked
  captured_at: '2026-11-18T15:31:09Z'
  question_id: q-20261118T153108Z-54e604
  blocking: 'yes'
  class: decision
  command: /flow:start 355 specification-capture
  situation:
  - The issue's specification (non-goals
  - failure modes
  - interface contracts
  - 6-row risk map) is drafted from the reviewed plan and needs confirming before
    the goal is created.
- type: escalation-resolved
  captured_at: '2026-11-18T21:12:02Z'
  escalation_field: options
  outcome: Accept the draft
  question_id: q-20261118T153108Z-54e604
- type: specification
  captured_at: '2026-11-18T21:12:19Z'
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: stranger-test
  captured_at: '2026-11-18T21:12:33Z'
  result: PASS
  task_count: 19
  rounds: 6
  note:
  - outside reader passed at round 6; coverage critic blocked at round 6
  - its findings were fixed and a fix-confirmation pass (not a full review) passed;
    then two hand edits (unknown-command rule copied to all places
  - intent_effect_observed qualifier)
- type: goal-created
  captured_at: '2026-11-18T21:13:37Z'
  goal_id: issue-355
  source: issue
---

## Specification

_Captured by specification-capture skill on 2026-11-18. Source: mixed (issue #355, design.json, and the reviewed plan at ~/.claude/plans/factory-1b/plan.md sections 1.2 and 5)._

### Non-goals

- No change to `/flow:start` or any other command's issue read (1d).
- No in-session confirm past tier-gate: in-session always-ask subcommands are still refused with `PERSON_CONFIRM_REQUIRED` until 1c's heartbeat; no `executor_can_confirm` and no `confirm <intent>` items from `next` (1c).
- No push, `gh pr create`, PR body edit, PR adoption or PR record by the engine (1e, Q11). 1b only makes `rebuild` take head_sha from a `pushed` or `pr_recorded` events line.
- No re-vouch by re-adding the queue label (Q3).
- No P8 run: the triage role is shown with recorded permission fixtures only (Q2).
- No read guard on a worker's own `gh issue view` (design trust_and_untrusted_text L40).
- No claim that comment commands are person-only: a comment posted with the person's token counts as the person (design person_channels L59-L65).
- No change to flow behaviour outside a factory except the new `tiers.issueUpdate` key.
- No fault-injection key in a shipped module.
- No release and no version change (AC13).

### Failure modes

- **Timeouts** — the intake judge's run is ended by flow-judge.sh's own `timeout` at the intake timeout (exit 124, no reply → stage_failed, one of the three runs); a judge that hangs past the launcher's limit falls to the lease-expiry rows; a sync over its budget leaves later jobs waiting with no partial facts.
- **Partial failures** — a POST that fails leaves the intent `recorded` and the next drain looks for its marker first, then retries; a POST that succeeds but whose record is lost is found by its marker; an effect that fails after `kill_current` keeps the kill fields (carry item 2); the process dying after a command's `store_pending` or after rows 41/41e/41k is recovered on the next pass with one event applied.
- **Invalid input** — an unparsable or schema-invalid judge reply is stage_failed; an edited outbox body, argv or hash refuses with `INTENT_CHANGED` (exit 3) and nothing runs; a command from an untrusted login raises no event (`UNTRUSTED_COMMAND`); a seam that supplies a built fact refuses with `SEAM_REFUSED`.
- **Missing context** — a failed permission read counts that login untrusted for the sync; a failed GraphQL edit read, dependency read or `gh api user` makes the sync incomplete, so issue facts raise `FactFailed` and the row waits; an unresolvable base ref or failed fetch counts as confirm (fail closed); no jq where tier-factory applies denies person subcommands; a missing `in/sync/issue-set.json` at row 66i is `issue_set_stale`, nothing launched.

### Interface contracts

- `bin/_flow_factory_text.py`: `spec_input_set(snapshot, needs_info, revouched) -> list`, `render_issue_md(items, others) -> str`, `digest(items) -> str` (sha256 over the canonical JSON form of plan 5.3), `command_of(body) -> (name, rest) | None`, `is_command_line(body)`, `is_engine_marker(line)`; untrusted text fenced as `<<<UNTRUSTED_ISSUE_*>>>` with runs of three `<` or `>` neutralised to ‹‹‹ / ›››.
- Outbox item schema `schemas/v1/factory-outbox.schema.json` (kind `FlowFactoryOutboxItem`): `id`, `job`, `row`, `state_at_write`, `ref`, `kind` (comment, label_add, label_remove, assign_label, pr_close), `blocking`, `key[]`, `argv[]`, `body_file`, `sha256`, `status` (recorded, pending_confirm, confirmed, sent, dropped), `effect`.
- job.json gains optional nullable fields (`base`, `write_seq`, `pending_intent`, `confirmed_intent`, `held_result`, `vouch_at`, `issue_digest`, `baseline_digest`, `needs_info`, `revouched_replies`, `priority_high`, ...); a pending event's `channel` widens to `^(terminal|launcher|session:.+|comment:[0-9]+)$`.
- `tiers.issueUpdate` (autonomous | journal | confirm) in settings.json, schema.json, tier-gate.sh and tier-runtime.sh; covers issue comment, label edit, close, reopen and the REST and GraphQL issue edit forms (Q9).
- Comment commands: line 1 `/flow-factory (answer|approve-spec|rework|reject|cancel|spec|retry) ...` from a login with triage access or higher; `/flow-factory answer NI-<k> <text>` for needs-info (Q17).
- Terminal `confirm <intent>` prints the literal, body and sha256 and exits 3 with `INTENT_CHANGED=<id> recorded=<hex> current=<hex>` or `INTENT_NOT_PENDING=<id> pending=<id>`; a `pending_confirm` notice becomes `confirmed` (Q16).
- Intake judge reply: `{decision: ACCEPT|NEEDS_INFO|REJECT, risk, surfaces, scope, criteria, questions}`, charged from `total_cost_usd`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| untrusted_edit window | counts edits before vouch_at, or reads only the last editor | edit history [outsider t2, trusted t3] after vouch_at t1 → right: untrusted_edit true, row 51b; wrong (last editor only): false, job stays |
| vouch_at source | takes the first label event or `updated_at` | queue label added at t0 and again at t1 by write logins, outsider edit at t2 → right: vouch_at t1 and the edit counts (51b); wrong (first event t0 or updated_at t3): differs |
| digest input | hashes rendered issue.md or every trusted comment | a trusted "thanks" comment added → right: issue_digest unchanged; wrong: changed |
| command comment in the spec-input set | an `/flow-factory answer NI-1 x` comment counted as a reply and as an answer | that comment plus its answers-file entry → right: the set holds `["answer","NI-1","x"]` once, no comment item; wrong: two fenced copies and a different digest |
| first-line matching | marker or command matched anywhere in the body | an engine notice with `/flow-factory reject` on line 2 → right: no event; wrong: a reject event |
| notice dedupe | the T:8u notice posted on every pass that re-applies the stay row | two passes with one untrusted reply and an unrelated comment in pass 2 → right: one post; wrong: two |

## Stranger Test


_2026-11-18. Plan: ~/.claude/plans/factory-1b/plan.md (tasks B1-B19)._

- Rounds 1-3: the outside reader and the coverage critic both blocked each round; findings were fixed after each.
- Q16 closed by the design (github_writes_and_tiers L74); Q17 answered by the user (`/flow-factory answer NI-<k> <text>`).
- Rounds 4-6: at round 6 the outside reader passed with four non-blocking notes; the coverage critic blocked on one finding (an `answer` comment counted twice in the spec-input set) and four non-blocking notes.
- A fix pass applied all round 6 findings; a fix-confirmation pass (checking only those findings, not a full review) passed with two non-blocking notes.
- Those two notes and the advisor's consistency note were applied by hand: the unknown `/flow-factory` word rule (`is_command_line`, Inferred) is now stated in 3.1, 5.3, B3 and B4, with a B3 test case; `intent_effect_observed` raises FactFailed only for a job with a pending_intent.
- Result: PASS (no open blocking finding).

## Inferred readings (wave 1)

_2026-11-19. Choices the plan and design leave open, made while building B1, B3, B7 and B8. Later tasks build on them._

### Tiers (B7, `bin/_flow_factory_tiers.py`)

- **`path_keys` covers every blocking write still ahead on the path to ready**, each key once, in stage order. It does not cover only the current stage. The grounds are design github_writes_and_tiers L68 ("with push at confirm a job parks before spending its spec and build budget") and AC8, where an intake job parks on `[issueAssign]`. Design execution_model L46-L53 does not name intake, spec, build or gate:
  - intake and prepare: `[issueAssign, issueUpdate, push, prCreate]`
  - spec, build and open_pr: `[push, prCreate, issueUpdate]`
  - gate, review, rework, sync and resolve: `[push, issueUpdate]`
  - ready and approve: `[issueUpdate]`
  - As a result, a headless job with `tiers.push=confirm` parks by row 40b before its intake judge runs.
- **A parked job (`waiting_operator`) uses its `resume_state`'s path.** A missing or unknown resume state reads every key.
- **A key that no source sets resolves to confirm.** An intent with an empty key list makes `intent_key_not_confirm` false.
- **Signatures as built**, which differ from plan 5.3:
  - `confirm_writes(writes, job, tiers, fdir=None)`;
  - `confirm_path_keys`, `tier_confirm_blocking` and `intent_key_not_confirm` take optional `tiers=` and `fdir=`;
  - `fdir` defaults to the factory directory.
- **The base fetch uses the refspec `+refs/heads/<base>:refs/remotes/origin/<base>`**, with `--no-recurse-submodules --no-auto-gc`. It retries once when the ref lock is held.
- **The engine reads the base-branch project file itself**, through rev-parse, ls-tree and cat-file. A symbolic link or other non-regular entry counts as confirm. `cascade-resolve --repo-settings-ref` is a separate view and the engine does not call it.

### Text (B3, `bin/_flow_factory_text.py`)

- **Functions added beyond 5.3:**
  - `is_reply_to(comment, round)`: id named, created strictly after `asked_at`, line 1 neither a marker nor a non-spec command. Trust is left to the caller.
  - `body_sha256`
  - `other_comments`
  - `issue_set`
- **A re-vouched reply stays in the set only while sha256 of its current body equals the stored hash.** Otherwise it is listed under Other comments.
- **`command_of` returns the rest of line 1 unchanged, leading space included.**
- **Adding a thanks, marker or command comment leaves the digest and the quoted part unchanged**, but adds an Other comments line (design trust_and_untrusted_text L21). The B3 test plan's "equal issue.md" is read that way.

### Gate (B8, `tier-gate.sh` and `lib/tier-runtime.sh`)

- **These forms are not classified as `tiers.issueUpdate`:**
  - `gh pr reopen`;
  - `gh pr edit --add-assignee`;
  - `gh issue edit --remove-assignee` and `--milestone`;
  - `PUT issues/{n}`;
  - `PATCH pulls/{n}` with `--input`;
  - `DELETE pulls/{n}/requested_reviewers`.
- **Removing one label (`DELETE issues/{n}/labels/{name}`) is classified as issueUpdate.** It is the engine's own label-removal write.
- **The shared key list and phrases live in `lib/tier-runtime.sh`, which `tier-gate.sh` sources.** If that file fails to load, the gate reads no command.
- **`lib/tier-factory.sh` holds only `_tg_factory_rules`.** If it fails to load, the hook denies the command.

### Schemas (B1)

- **An outbox item id is `issue-N-j<seq>-<row>-<k>` or `probe-p9-<n>`.** A probe item may have a null job, row and state. `pending_intent.id` and `confirmed_intent` accept the issue form only.
- **Some rules are enforced by the writers, because the stdlib validator lacks propertyNames, patternProperties, minItems and if/then:**
  - the comment-id keys of `revouched_replies`;
  - a comment object on every comment-channel event;
  - non-empty `proposed_criteria` for ACCEPT and non-empty `questions` for NEEDS_INFO.

## Inferred readings (wave 2)

_2026-11-19. Choices made while building B4 and B6 and fixing their reviews. Later tasks (B5, B9, B12, B13, B14) build on them._

### Issue reads (B4, `bin/_flow_factory_issue.py`)

These signatures differ from plan 5.3:
- **`Permissions(gh, repo, settings=None)`** has these methods:
  - `.of(login)`;
  - `.trusted(login, type)`: write or higher, raised by `trustedPermission`;
  - `.triage(login, type)`: triage or higher, the vouch bar (design trust_and_untrusted_text L2);
  - `.write(login, type)`: write or higher with the bot rule, not raised by `trustedPermission`;
  - `.open_pulls()`: read once per object.
  - `repo` is passed because the gh callable carries no repository. `settings` is a callable `setting(key, default)`.
  - The sync makes one object per pass, so each login's permission and the open pulls are read once per sync. A failed read is cached as untrusted for that object.
- **`.triage` means triage or higher.** For B5's retry: a retry counts when `.trusted or .triage`, and `triage_only = .triage and not .trusted`.
- **`read_issue(gh, repo, n, job, perms) -> snapshot or None`.**
  - The snapshot has the plan 5.3 keys.
  - `closed_by` and each event carry `trusted`.
  - Each edit is `{editor, editor_type, edited_at, trusted}`.
  - Two keys are added: `dependencies` (`{"<m>": state}`, read only for a queued job) and `pr_merged` (read when the job has a PR).
  - Any failed read gives None and the caller computes no fact. That covers the issue, events, comments, GraphQL edits, a named dependency and the job's PR. It also covers:
    - a REST comment missing from the GraphQL answer;
    - a `hasNextPage` that is not true or false;
    - a GraphQL answer that carries errors alongside its data.
- **`read_unjobbed(gh, repo, n, perms, settings=None)`** returns `{number, state, labels, label_event, closing_prs: [{number, head_ref, cross, author, author_type, write}]}` or None.
- **`creation_conditions(unjobbed, local, settings=None) -> bool`.** `local` is `{"open_job": bool, "terminal_vouch_at": [time or None]}`.
- **Other entry points:** `needs_info_answers(snapshot, job) -> (trusted ids, untrusted ids)`, `untrusted_edit(snapshot, job)` and `facts(snapshot, job, settings=None)`.

Choices:
- **Repository role.**
  - Only `role_name` is read. A custom role counts as none (design person_channels item 5, plan B4 outline 2).
  - The legacy `permission` field is read only when `role_name` is absent, with triage mapped to read (R55).
- **Edit times.**
  - An edit at exactly vouch_at counts. An unreadable time or a missing vouch_at also counts (trust_and_untrusted_text L5).
  - A truncated edit history adds an unknown editor at the node's `lastEditedAt`, or with no time when that cannot be read. This holds whatever order GitHub lists edits in.
- **`cancel_signal`** reads the latest queue-label removal or close strictly after vouch_at, and is true when that actor is trusted. It stays true after a reopen.
- **`untrusted_close`** is true when the issue is still closed, `closed_by` is not trusted, and the job's PR is not merged.
- **Creation row 1.**
  - A closing PR uses GitHub's closing keywords and an exact `#N`.
  - A same-repository `feature/issue-N-` head is a factory branch.
  - A non-factory PR blocks queueing when its author has write or higher. An unlisted bot has none.
  - A terminal job with an unreadable vouch_at blocks a new job.
- **Dependencies** come from lines that start `Depends on` or `Blocked by`, with bare `#N` only. A reference to the issue itself is ignored.

Open, for later tasks:
- **R7 is not closed by B4.** The revouch handler (B13/B14) knows the retry comment's time. It must compare that time with `snapshot["edits"]["comment:<id>"]`, so a reply edited between the retry and the re-vouching sync is not trusted.
- **Real GitHub has not been checked.** The GraphQL query text, and whether `userContentEdits` can be null, are still to be checked against it; the B15 probes or a person run can check them.

### GitHub writes (B6, `bin/_flow_factory_github.py`, `bin/flow-tier-crumb.sh`)

These signatures differ from plan 5.3. The plan's B6 line now points here.
- **`record_job_intent(paths, job, row, kind, argv, body, key, blocking, ref=None, state=None, *, repo)`.**
  - `state` is state_at_write and defaults to `job["state"]`.
  - `repo` is required: the pass's owner/name, compared ignoring case. The literal must target that repository and the job's issue, or the job's pr for `pr_close`.
  - It cleans a comment body and adds the engine marker itself, so callers pass plain text.
  - It returns None for a `pr_close` on a job with no pr.
  - The dedupe reads the `intent_recorded` lines whose items still exist, never the item fields.
- **`drain(paths, job, gh_real, tiers, login, enough=None)`.** `enough()` is asked before every gh call. When it answers no, the drain prints `WRITE_DEFERRED job= intent= reason=budget` and stops.
- **`run_literal(paths, job, id, gh_real, login, tiers=None, lines=None)`.** `tiers` writes the breadcrumbs, and `lines` collects `WRITE_SKIPPED`.
- **`lookup(gh_real, job, id, login, paths=None)`.** It checks the item against the events file first and raises `ReadFailed` on any mismatch, so the fact fails rather than reads true.
- **New entry points:**
  - `check_item(events_path, item)`: B12's `confirm` and `status --intent` use it, never their own hash.
  - `sent_item(job_dir, id, job_key)`: B7's `_covered` uses it.
  - `drop_intent(paths, job, id)`: B14 step 7 uses it for every table drop.
- **Literal forms:**
  - comment: `gh api --method POST repos/O/R/issues/N/comments -F body=@<abs J/outbox/<id>.body.md>`. When the comment is run, gh gets exactly the hashed bytes on standard input (`-F body=@-`); the stored literal keeps the path.
  - label_add: `gh api --method POST .../labels -f labels[]=X`.
  - label_remove: `gh api --method DELETE .../labels/<percent-encoded X>`.
  - assign_label: `gh issue edit N --repo O/R --add-assignee L --add-label X`.
  - pr_close: `gh api --method PATCH repos/O/R/pulls/N -f state=closed`.

**The events file is the record.** The item file can be edited, so each status it holds must be backed by an events line. Every line is appended before the item is saved.

| Status | Backed by | Written by |
|---|---|---|
| recorded | the last `intent_recorded` line for the id. It carries job, row, kind, state_at_write, ref, blocking, key and sha256, and every field must match the item | `_write_intent`: body file, then the line, then the item |
| pending_confirm | `intent_pending_confirm` of the same job, after the last record. Notices only | the drain |
| confirmed | `intent_confirmed` of the same job, after the last record. Notices only | B12's terminal `confirm`, which must append the line before it saves the item |
| dropped | `intent_dropped` | `drop_intent` and the drain |
| sent | `write_recorded`. The line decides: an item it names is never run again and is saved as sent whatever the file says | `_sent` |

- A file status with no line behind it is refused with `INTENT_CHANGED=<id> ... field=<name>`, and nothing runs.
- A `recorded` file that has a park or confirm line is acted on by the line, so a process death between the line and the save does not leave a stuck item.
- A confirmed notice is sent even after its job leaves state_at_write; only a terminal state drops it. A person confirmed it (Q16).
- The events file itself is the root of trust: an edited or appended events line is outside what these checks can catch.

**Status lines added to plan 2.3:**
- `WRITE_SENT`, `WRITE_DROPPED`, `WRITE_FAILED` (the reason starts `lookup:` when the read failed) and `WRITE_DEFERRED`;
- `OUTBOX_ITEM_INVALID` and `OUTBOX_UNREADABLE reason=symlink|not_a_folder|unlisted`;
- an ` field=<name>` suffix on `INTENT_CHANGED`.

**Other choices:**
- **Breadcrumb.** One breadcrumb is written per journal key after a run. A write found by the look-first step gets none (design github_writes_and_tiers L50: "run, plus one breadcrumb"). `flow-tier-crumb.sh` writes into issue N's trail whatever branch is checked out.
- **`clean_post`:**
  - `<!--` becomes `< !--`;
  - mentions go into code spans;
  - a `/flow-factory` line goes into a code span longer than any backtick run in it;
  - the 60,000-character cap is applied last.
- **Probe items.** `record_probe_intent` refuses a missing probe folder, and a folder, outbox or events file that is a symbolic link.
- **Timeout.** `GH_TIMEOUT` is 15 s per gh call.

**Open for later tasks:**
- B14 must pass `repo` to `record_job_intent`.
- B14 must drop through `drop_intent`.
- B12 must write `intent_confirmed` before it saves the item.

## Inferred readings (wave 3)

_2026-11-19. Choices made while building B5, B11 and B12 and fixing their reviews. B9, B13 and B14 build on them._

### Plan conflict: where an NI answer applies

Plan 2.3 says `answer NI-<k>` (terminal) and `/flow-factory answer NI-<k> <text>` (comment) apply in needs_info only. transitions.json, which the design names as the only source for states and events, has person_answer rows from needs_human that record the answer (44q, 44u, 44v, 44w, 44x). Both channels therefore accept an NI answer in needs_info and needs_human. The comment channel imports the state set (`NI_STATES`) from the person module.

**Open for B14:** row 44 (needs_human, person_answer, no guard) is the fallback when none of 44q–44x holds. It resumes to blocked_stage, and its effects do not say "record the answer". Its effects do say the answer reaches a fresh session through the questions store. B14 must record an NI answer through `effect_answer` before row 44 resumes the job. Otherwise an answer given after row 9a parks a job (needs_info_exhausted) would restart intake without the answer.

### Comment commands (B5, `bin/_flow_factory_commands.py`)

These signatures differ from plan 5.3:
- **`scan(snapshot, job, perms, engine_login, table=None) -> [command]`** only reads. Pass the pass's own table. It raises ValueError for an empty `engine_login`. Each command is `{comment_id, name, event, args, trusted, triage_only, raise, note, author, author_type, created_at, length, permission}`. `trusted` means the command counts, so it is true for a triage-only retry.
- **`store(paths, job, command, *, repo, caller=None) -> [status line]`** runs under the job lock for every command, trusted or not. It changes `job` in place (`commands_seen`, `write_seq`, `updated_at`) and writes job.json.
- **`label_notes(snapshot, job, label)`** and **`store_label_note(paths, job, note, *, repo) -> intent id`** (under the job lock).
- **`jobs.store_pending(..., comment=None)`**: a `comment:<id>` channel must carry that comment object, and no other channel may carry one.

Choices:
- **Floor.** A command counts only when created strictly after the later of vouch_at and the newest marker the engine login posted (person_channels L57, R58). An unreadable vouch_at, marker time or command time raises nothing. A comment by the engine login with no marker is still a command (L59–L60).
- **Untrusted commands.** They are not added to commands_seen, so trust is judged by each sync's permission read (person_channels L54; plan 2.2 caches permissions for one sync only). A failed read therefore cannot drop a later trusted reading. One consequence: a command from an author later raised to write is raised then, limited by the marker floor. The `UNTRUSTED_COMMAND` line is printed once per job and comment, recorded by an events line `{type: untrusted_command, job, comment, time, pass}` written before the status line. That line has no `id`, so the write module and rebuild ignore it.
- **Refusal order:** trust, then the state (occurs_in), then the form, then the answer's state, then whether the job asked the question. A SPEC answer applies in needs_spec_approval only (person_channels L11).
- **Note text** is built from fixed words, ids, the label and logins; no comment text is copied in. A label-note ref is the removal's event id.
- **Unreadable pending file:** `store` refuses with `pending_unreadable` and leaves the comment unseen. A missing, unreadable or non-UTF-8 template gives `Refused(template_unreadable)`.

### Actor types (B4 change, `bin/_flow_factory_issue.py`)

Only `User` and `Bot` are kept. A missing type counts as User (plan 5.3). Any other value (Organization, Mannequin) becomes `Unknown`, which is untrusted whatever the role or trustedBots says (plan AC2: an unknown account fails closed). This applies to comment authors, event actors, closers, pull authors and GraphQL editors.

### Intake judge (B11, `bin/_flow_factory_intake.py`, `bin/_flow_factory_launch.py`, `flow-judge.sh --judge intake`)

Effect signatures add keywords to plan 5.3; B14 passes `repo=`, and `row=` for needs-human and tier-confirm:
- `effect_accept(paths, job, result, *, repo) -> {"intake_inputs", "intake"}`: the caller puts these into the transition line's fields.
- `effect_needs_info(paths, job, result, now, *, repo) -> needs_info`: the caller writes `job["needs_info"]`.
- `effect_reject(...)`, `effect_revouch_notice(paths, job, comment_id, *, repo)`, `effect_answer(paths, job, qid, text)`, `effect_needs_human(paths, job, *, repo, row)`, `effect_tier_confirm(paths, job, keys, *, repo, row)`, `next_question_id(paths)`, `fact_sheet(job)`, `intake_stdin(issue_md, sheet)`, `map_result(stdout) -> (event, judge|None)`, `reply_envelope(stdout)`, `FAILED = "stage_failed"`.

Choices:
- Every effect checks the job lock and loads its template before it changes anything, so a retry after EFFECT_FAILED uses up no question id. Each changes `write_seq`; the caller writes job.json.
- state_at_write is passed explicitly: prepare for row 6, needs_info for row 4, rejected for row 5, the job's own state for row 8u, needs_human for needs-human, waiting_operator for tier-confirm.
- `intake_inputs` comes from the comment and answer fence lines of `J/in-copies/issue.md`, which is what the judge read (stages L44). `J/in-copies/intake.json` holds the whole validated reply (stages L80).
- Questions: `J/questions/NI-<k>.json {job, id, text, round}`; the counter `F/questions.json {next}` under `F/questions.lock` (30 s). An unreadable counter is refused and left as it is. `needs_info.round` starts at 1.
- Launcher: a judge has no clone, io folder, stage budget or `--max-budget-usd`, and records no session. Its environment is built from the keep list. cwd is the main checkout. A reply over 4 MiB is malformed and its cost is not charged, because the reply is not read. A launcher-side timeout gives outcome timeout; any other failure gives error. The judge result is applied in the launcher's own process, because apply_report drops a directive whose max_budget_usd is null.
- flow-judge.sh intake: `--model` must match `[A-Za-z0-9._:[]-]+` and `--timeout-seconds` must be 1 to 9 digits, else exit 2.

### Person commands (B12, `bin/_flow_factory_person.py`)

- **confirm** checks the intent through the write module's check against its intent_recorded line, before showing anything and again under the job lock after the prompt. The literal, the body and both hashes go to the terminal with the prompt; stdout holds one outcome line (1a plan 2.6). Hashes are shown as `SHA256 recorded=<hex> current=<hex>`.
- **Display:** argv and body inside `<<<UNTRUSTED_INTENT>>>` fences, every line prefixed `> `. Control characters other than tab show as `\xNN`, and format characters (bidi controls, zero-width characters, U+2028/U+2029) as `\u{xxxx}`. Text-mode status lines carrying such characters are escaped the same way.
- **Linked folders:** a symbolic link for J/outbox, or a folder on the way to it, is treated as not found (`INTENT_UNKNOWN`, `FACTORY_REFUSED=intent_unknown`), as plan 2.2's lookup rule says.
- **Notice confirm** is allowed when the job has an intent_pending_confirm line after the last record, with no confirmed, sent or dropped line, the item is not blocking, and the job is not terminal. A second confirm gets EVENT_REFUSED. An unknown id keeps 1a's `FACTORY_REFUSED=intent_unknown` (exit 5).
- **answer NI-<k>** requires `--text`. QUESTION_AMBIGUOUS also applies to 1a q-ids.
- **status** takes each item's status from the events lines, not the item file.
- **rebuild** replays only `REPLAYED_FIELDS` (vouch_at, vouch_event_id, base, revouched_replies, baseline_digest, baseline_pending, intake_inputs, intake, needs_info, pending_keys, pending_intent, held_result, confirmed_intent). A pr_recorded line also restores `pr`. B13 and B14 must add any new field they put in a line's `fields`. `LOGGED_LISTS` gains commands_seen and labels_set.
- usage prints four lines (`usage:`, `Person: …`, `Engine: …`, `Worker: …`); B9 compares the Person line.

## Inferred readings (wave 4)

### Factory rules in tier-gate and the state guard (B9)

- **Worker:** a session with FLOW_FACTORY_JOB or FLOW_FACTORY_DIRECTIVE set (design L35, person_channels L21). FLOW_FACTORY_IO alone does not make a worker for the hook, although the wrapper's own refusal also counts it. A worker may run only `[path/]flow-factory.sh context --mode` and `[path/]flow-factory.sh await <qid> [--max-seconds <n>]`, each as the whole command. B8's scenario tg-fac-sourcing was changed to run `context --mode` under each worker variable, because the rules deny `status` there.
- **Person subcommands outside a worker:** default mode asks; any other mode, or no mode, denies with `run it in a terminal outside Claude Code: <command>`. A command the hook cannot read (a variable subcommand word, an open quote, a parser that does not load) is denied in every mode, because no ask could show what would run. A confirm is denied when `status --intent` (run in the payload cwd, stdin from /dev/null) exits non-zero or does not print `INTENT id=<id> `.
- **approve-spec:** the ask prints `spec file: none recorded`, because the 1b job schema has no spec-file field. Hand-off to 1d: when the field is added, the ask must read it, and a test must pin it.
- **Comment posts** are denied while flow.factory.enabled is true when the command names /flow-factory and posts to a comments or reviews endpoint. GraphQL mutations are not covered; design L40 names only the endpoints.
- **State guard:** applies `.` and `..`, takes the physical path of the longest existing part, follows a link at the end of the path, and checks the /private spelling. It has no fast exit: a custom runtime directory makes a fixed `.flow/factory` check wrong, so it always resolves the directory (about 80 ms per call). Design L48's "exits at once" is not met; this is the reason.
- **A person call is asked only when it is the whole command** (decided 2026-11-19 after the wave 4 review). In a chain, after cd, pushd, env -C or another --chdir option, after a variable assignment, or next to another command, it is denied with the terminal text in every mode. This replaces plan R72's default-mode ask for `true && flow-factory.sh confirm x`. It fails closed, and it keeps the confirm ask's literal (read in the payload cwd) about the same factory the call would use. The P9 sessions (B15 step 3) must give the commands by full path, as the whole command, with no assignment, cd or chain; otherwise G4's default half reads as no-go for the wrong reason.
- **Without jq, outside a worker,** any command naming flow-factory.sh, _flow_factory.py or `-m _flow_factory` is denied with the terminal text, unless it is exactly `[plain path/]flow-factory.sh` with status, next, wait, question, probe, or answer without a word starting `--t`, followed by plain words only. This replaces plan 2.4's jq-free word match, which a quoted subcommand word could pass.
- **Directory checks compare identity:** besides the spelling checks, the state guard and the Bash directory rule compare each existing ancestor of an absolute path with the factory directory by device and inode (`[ -ef ]`), so another letter case or a link cannot pass on a case-insensitive volume.
- **What the text match does not cover** (decided 2026-11-19 after the third wave 4 review). tier-gate's factory rules read the program and subcommand words bash would see for the shell forms plan 2.4 lists and for eval, source, find -exec, xargs, nested -c scripts, stdin shells and quoted, escaped or patterned spellings of the script name. They do not follow a program that runs code from its own text or arguments (awk system, osascript, expect, trap, arch, gtimeout, tmux, ssh and the like), a link to the factory directory under another name, or, without jq, `x/../factory` and `factory/x` from inside the runtime directory or a JSON `\u` escape in a written path. Nor does it read a program word that is a pattern matching any name (`*`, `*.sh`): sending every such command to the factory rules would cost about 60 ms per hook call in a repository with no factory. These belong to the residual of design person_channels L25 and L46: layer (b) matches on command text. Layer (a) still stops them in 1b, because the engine refuses every always-ask subcommand and `answer --text` inside a session (person_channels L38, rows 69a-69h): 1b writes no heartbeat record, so no session counts as default mode.
- **Wrapper options** (decided 2026-11-20, fifth wave 4 review). After a wrapper, the rules move the program position past its options only when they know every option, from each program's documented grammar: a value option, a no-value option, a `--name=value` word, or an unambiguous prefix of one long option. An option they cannot classify keeps the script word as the program, so a call is counted. A mention after an option the program does not have (`timeout --foo grep flow-factory.sh cancel`) is therefore denied; a test pins this. A false deny of such a mention is accepted; a missed call is not.
- **Hook time on long commands** (measured 2026-11-20 at 69c12a2d, bash 3.2, macOS). Commands the factory pre-filter passes cost one awk per line that names an interpreter. A 32 KB commit message with quoted lines takes about 0.9 s (8.5 s before the fifth fix round). A message whose every line holds an interpreter word such as `at` or `make` still takes about 9 s for 32 KB and 2.3 s for 8 KB, the same as before that round. The decision is right; only the time is long. Batching that awk across lines is a change to the shared parser and is left for the PR review to weigh.
- **Later call sites:** nothing calls `context --mode` or `await` yet. When 1d adds them, they must use the plain whole-command form, or rule 1 denies them.

### Table facts and the seam (B13)

- A callable in `Context.built` wins over the four facts the job computes, as 1a's `_FROM_JOB` rule says.
- `pending_intent_stale` is true when the pending intent's kind is push or comment and `foreign_head_change` is in pending_changes (T:facts.pending_intent_stale). assign_label is not tied to a head.
- `intake_rounds_exhausted` reads `flow.factory.intake.maxRounds` (default 3). A value that is not a whole number of at least 1 counts as 3.
- Row 50's "from waiting_operator" text acts only when the job leaves waiting_operator. `intent_clear` nulls pending_intent, held_result and pending_keys on rows 41b and 41p too.
- `issue_changed` is false when either digest is missing, and while baseline_pending is set.
- revouch and the transition line share one timestamp.
- **For B14:** next builds no 1b callables, confirm_writes or ctx.sync yet, so files that run `next` fail with FactUnavailable until B14 step 0 (the person file's ps8a and ps13a-c). B14 must also supply `ctx.sync["revouch"]` (comment id to sha256) with replies edited after the retry filtered out (R7), and a non-empty `ctx.sync["pending_keys"]`; move the fixtures off confirm_keys; and add the `bodies["judge:intake"]` refusal (step 11).

### Linked job folders in person commands (B12 follow-up)

- A linked J/outbox or J/directives is treated as absent at every read in `_flow_factory_person.py`: write_seq, the directives read, the context lease and status's directive check. A linked J/jobs gets `factory_dir_refused`; a job folder that is itself a link gets `job_unreadable` (exit 5), matching what status and the other person subcommands say.
- Left as they are: `directive_open` in next reads J/results with `os.path.lexists`, so a linked J/results can mark a directive finished (B14 owns next); and a factory directory configured outside the repository is not checked for links by the job lock (`_flow_factory_jobs.py`).

## Inferred readings (wave 5)

### Docs (B10)

- **Parity check scope:** every file of the plugin that names issueAssign must also name issueUpdate, except files under tests/ and evals/results-*. Design github_writes_and_tiers L23-L28 lists only shipped code, settings and docs, and e2e_copy_plugin leaves the same folders out of a copy. Two test files (tests/cascade-resolve.test.sh and a schema fixture) name only issueAssign.
- **What the docs claim:** only what the hook does when run. `gh pr reopen` is not classified, so reopening is documented for issues only. GraphQL comment mutations are named as not caught by the comment-post deny (wave 4).
- **Changelog:** the issueUpdate entries go under "Changed" in Unreleased, because posts that ran with no setting now follow one. The Unreleased preface's "no GitHub writes" is B18's to correct.

### Next integration (B14)

- **Test placement:** the B14 W and E scenarios are in e2e-factory-engine-next.test.sh (NX12 onward), not split across e2e-factory-text, -commands, -intake and -github as plan 2.6 has them. They run `next` end to end, which is that file's subject; the four module files keep testing their modules.
- **Issue reads:** a job whose own issue read fails gets no entry and one `ISSUE_READ_FAILED job=<key> <reason>` line; it does not hold back last_sync_at. A missing engine login or running out of time still does (plan 3.1, per-job entries). A write failure in the sync's phase B prints `SYNC_WRITE_FAILED job=<key> <reason>`.
- **Lines and records:** row 8's answer handler appends `{"type":"answer_comments","job","pass","comments":[ids]}`. refuse_note prints `EVENT_REFUSED=<event> job=<key> row=<row> <text>` and records a non-blocking issueUpdate comment, with the comment id as ref when the event came from a comment. pr_close is recorded under issueUpdate, non-blocking, with the row's target as state_at_write (the Q9 forms). `BASE_REF_UNRESOLVED` prints `ref=origin/-` for a job with no base. The row 40b park line is printed on every pass from the drain step, like row 40's.
- **Confirm with a wrong id (R68)** is a refusal: exit 3, its event dropped.
- **R7 extended:** a waiting reply created, as well as one edited, at or after the retry time is left out of the re-vouch; a reply whose times cannot be read is also left out.
- **Row 44** records an NI answer through effect_answer before it resumes (wave 3 open item). The issue-set file is deleted after the re-vouch rows and after person_answer rows that wrote the answers file.
- **hold_intent** holds an assign_label intent only; any other blocking write raises `Refused(intent_kind_not_built)`, because 1b builds no push or comment intent.
- **Linked results:** the linked-results rule (wave 4) also applies to apply_pending's result check and the lost-run charge.

### Probe code (B15)

- **P2 limits** (decided by the user 2026-11-20): 120 turns, $1.50, 1200 s. The prompt asks for 74 command forms and 5 edit-and-task pairs, about 96-100 turns; the last real P2 run used 79 turns for 78 tool calls, so 90 turns would have ended the run before the stop sequence.
- **Ledger:** only log-file-changes.sh (PostToolUse on Edit, Write, NotebookEdit) adds file_change entries, so after the worker's first edit with no quality run, every task completion is refused. P2's task_completed_refusals is expected to be no-go, which leads to B16's TaskCompleted half.
- **B16 marker:** a copy's hook counts as having the factory warn fallback when the hook script's own text names FLOW_FACTORY_DIRECTIVE. B16 must name that variable in flow-goal-stop.sh and verify-task-completion.sh themselves, not only in a sourced lib, or the counts stay not_run.
- **Worker variables:** FLOW_FACTORY_JOB=issue-0-j1 and FLOW_FACTORY_DIRECTIVE=<area>/directive.json; the file is never created, because tier-gate reads only whether each is set (design L35).
- **P9 per mode:** each mode's tier_gate finding is kept in F/interactive.json, because the record schema allows only fixed part fields. Each mode's finding stores the Claude Code version it ran under; a finding from another version counts as missing. The part is no-go if either mode is no-go, not_run while one is missing, and go otherwise. The printed P9 steps leave out p14, wait-question and answer.
- **Probe warning:** printed on stdout as the first line of each probe invocation except --verify-record, --export and --step await, which read or export a record and start no session.
