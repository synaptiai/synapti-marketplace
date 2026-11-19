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
