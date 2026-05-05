# Walkthrough Script — Flow Plugin 90-min Workshop

**Format**: pre-recorded asciinema (terminal) + screen capture (GitHub PR view), composited to ≤20 minutes. Live narration during the 25-min slot. **No voiceover on the recording** — the room can interrupt at pause beats.

**Recording path**: `docs/flow-team-session/recordings/flow-walkthrough.cast` + `flow-walkthrough-pr.mp4`. Composite output at `flow-walkthrough.mp4`.

---

## Scenario

A synthetic issue against a fictional `sync-cli` repo. Nothing in the recording references the team's real codebase — that's deliberate, so the lifecycle stays visible and nobody drags the demo into a tangent.

> **Issue title**: Add `--json` flag to `/sync` command emitting structured output for CI.
>
> **Body** (uses `plugins/flow/templates/issue-body.md` structure):
>
> **Context**: CI consumers want to gate deploys on sync results. Today they parse human-readable output, which breaks every time the message text changes.
>
> **Current State**: `sync` prints status lines like `Synced 3 items, 0 errors` to stdout and exits 0 on success.
>
> **Objective**: A machine-readable output mode that downstream tools can rely on without parsing prose.
>
> **Acceptance Criteria**
> - [ ] AC1: `sync --json` exits 0 and emits valid JSON with keys `{ status, items, errors }` against a healthy remote.
> - [ ] AC2: `sync --json` exits non-zero and emits `{ status: "error", message }` JSON on auth failure.
> - [ ] AC3: `sync --help` lists `--json` with its description.
> - [ ] AC4: Existing non-JSON output unchanged when `--json` is absent.

The four criteria deliberately span four verification types from `criterion-verification-map/SKILL.md`: behavioral (AC1), error handling (AC2), contract (AC3), regression/behavioral (AC4).

## Recording shotlist

Total target: **19:30**. Hard cap: **20:00**.

| Phase | Command | Recorded | Cumulative | Cut order |
|-------|---------|----------|------------|-----------|
| A | `/flow:issue` | 2:30 | 2:30 | **Cut first** if slot is tight (use a pre-existing issue) |
| B | `/flow:start` | 4:00 | 6:30 | NEVER cut |
| C | CODE (TDD cycle) | 3:00 | 9:30 | NEVER cut |
| D | VERIFY | 4:00 | 13:30 | NEVER cut |
| E | `/flow:pr` | 2:30 | 16:00 | Cut to static screenshot if slot is tight |
| F | `/flow:address` | 2:30 | 18:30 | Keep |
| G | `/flow:merge` | 1:30 | 20:00 | NEVER cut |

### Phase A — `/flow:issue` (00:00–02:30)

What to show:

- 00:00 — Type `/flow:issue Add --json flag to sync command`.
- 00:20 — Duplicate detection: agent searches existing issues, finds none.
- 00:40 — Label discovery: lists candidate labels (`enhancement`, `cli`).
- 01:00 — First-pass acceptance criteria draft includes "works correctly" — **Spec Validation Gate fires**, blocks. Show the rejection message.
- 01:20 — Re-draft with concrete criteria (AC1–AC4 above).
- 01:50 — Issue created. Visible URL.
- 02:10 — `gh issue view N` showing the body matches `plugins/flow/templates/issue-body.md`.

**Why this matters for narration**: this is where Excellence Principle #2 (Spec-as-Eval) bites. The room sees the gate reject "works correctly" before they hear the principle.

### Phase B — `/flow:start <issue-N>` (02:30–06:30)

- 02:30 — Phase 0 PRE-FLIGHT bash block runs (the exact one quoted on slide 33, from `plugins/flow/commands/start.md` lines 38–62). Show clean `PREFLIGHT: PASSED`.
- 03:00 — EXPLORE: parallel `gh issue view`, `gh issue ... comments`, `git status`, `Skill(capability-discovery)`. Output stacks fast — let it scroll.
- 03:40 — PLAN: `Skill(criterion-verification-map)` produces, for each AC, a `Verification command` and an `Expected evidence` shape. Highlight one row on screen.
- 04:30 — TaskCreate × 4 (one per criterion). TaskList renders.
- 05:00 — Stranger Test gate runs against the plan output. Passes.
- 05:30 — Branch created (`feature/issue-N-sync-json-flag`), journal initialized at `.decisions/issue-N.md`.
- 06:00 — TaskUpdate(in_progress) on the first task. Buffer.

**Pause beat 1** (live narration, ~75 sec): scroll back to the criterion verification map. Read AC1's verification command aloud. "This command was decided right now, at plan time. We're not going to write the test and then claim it covers the criterion — we're committing to a check before any code is written. That's eval-as-spec."

### Phase C — CODE / TDD cycle (06:30–09:30)

- 06:30 — RED: write failing test for AC1 (JSON shape on healthy sync). Run it, watch it fail. Output is on screen.
- 07:15 — GREEN: minimal `--json` output emission in `cmd/sync.go`. Run test, passes.
- 08:00 — REFACTOR: extract a small `formatJSON` helper. Tests still pass.
- 08:30 — Commit. PostToolUse log-commits hook fires, journal entry appears.
- 08:50 — Show `cat .decisions/issue-N.md` — auto-log entry visible.
- 09:10 — Repeat the loop in 20 seconds for AC2 (error JSON). Just show the commit log, not the full cycle.

**No pause beat here** — keep momentum. The TDD principle was set in section 1; this is the proof.

### Phase D — VERIFY (09:30–13:30)

All four layers from `autonomous-workflow/SKILL.md` lines 24–28.

- 09:30 — **Static**: `Skill(test-runner)` dispatches lint + test + typecheck in parallel. All green.
- 10:15 — **Runtime**: `runtime-verification` skill builds the binary, runs `./sync --json` against a stub server, captures output. Show the JSON on screen.
- 11:00 — **Review**: self-review with fix-forward. The agent finds **one P2** — a missing test for AC4 (regression case). It fixes it inline, doesn't escalate.
- 11:45 — **Verdict**: `Agent(verdict-judge)` dispatched. Show the prompt construction — the agent sees only the AC list and the evidence bundle. Show that the diff and journal are NOT in the prompt.
- 12:30 — Verdict-judge returns: AC1 PASS, AC2 PASS, AC3 PASS, AC4 PASS. Per-criterion evidence summarized.
- 13:15 — Self-review summary uses `plugins/flow/templates/self-review-comment.md` format.

**Pause beat 2** (live narration, ~75 sec): pause on the verdict-judge prompt. Point at the black box around it. "Read what the judge sees. Acceptance criteria. Evidence bundle. That's it. No diff. No journal. No 'here's why we chose this approach.' If your evidence doesn't prove the AC, the judge will say FAIL — and that's the point. The judge is independent because it can be."

### Phase E — `/flow:pr` (13:30–16:00)

- 13:30 — `/flow:pr`. Push happens (Tier 2 — journal entry, no prompt).
- 13:50 — Parallel agent fan-out (Phase 3): `code-reviewer`, `convention-checker`, `test-runner`, `security-reviewer`, `error-handler-inspector`, plus a re-run of `holdout-validation`.
- 14:30 — Agents return. Findings table renders, sorted P1 → P2 → P3.
- 15:00 — One P3 surfaces: "missing example in README." Agent fixes inline (P3 fix-or-escalate — Excellence Principle #6).
- 15:30 — PR body assembled from `plugins/flow/templates/pr-body.md` + public journal entries. URL visible.

**Cut option**: if slot is tight, replace 13:30–16:00 with a single screenshot of the assembled PR body. Recording drops to 16:30 cumulative.

### Phase F — `/flow:address` (16:00–18:30)

A reviewer (a second persona, off-screen) drops two comments:
- Comment 1: "What if the server returns a 5xx? Should that emit `{status: 'error'}` too?" (P1 — gap in AC2 coverage)
- Comment 2: "Consider naming the helper `marshalSyncResult` to match other helpers." (P2 — convention)

- 16:00 — `/flow:address`. Categorizes both comments.
- 16:30 — Surgical fix for P1: add 5xx branch + test. Commit.
- 17:15 — P2: rename helper, update callers. Commit.
- 17:50 — `feedback-resolution` skill drafts a re-review request comment.
- 18:15 — Reviewer is re-requested. FLOW_RESOLUTION_CYCLE marker visible in the PR body.

**Pause beat 3** (live narration, ~60 sec): pause on the FLOW_RESOLUTION_CYCLE marker. "Two states for any P3: resolved or escalated. Both are auditable; neither is silent. Escalation means the engineer wrote the six-field structure into the PR comment and the reviewer accepted it. The merge gate reads this marker — unresolved or unaccepted items block merge. That's the policy: a finding worth mentioning is a finding worth acting on."

### Phase G — `/flow:merge` (18:30–20:00)

- 18:30 — `/flow:merge <pr>`. Prerequisite check runs.
- 18:50 — Display: approval ✓, checks ✓, conversations resolved ✓, finding-ledger empty ✓ (no unresolved or ESCALATED items in FLOW_RESOLUTION_CYCLE).
- 19:10 — **Tier 3 confirmation prompt** via AskUserQuestion. Show the structured options panel.

**Pause beat 4** (live narration, ~45 sec): freeze on the confirmation prompt. "This is Tier 3. Merge is hard to reverse — once it's on the default branch, getting it off is a revert commit visible to everyone. The plugin will not auto-merge. The hooks will not auto-merge. Even if you somehow wrote a command that tried, `block-force-push` and `block-destructive` would catch the recovery attempt. Confirmation here is structural. The user has to say yes."

- 19:30 — User confirms. Squash merge per `merge.strategy: squash`. Branch deleted per `merge.deleteBranch: true`.
- 19:55 — Done. Final shot of the closed PR + closed issue.

## Pre-recording checklist (run before hitting record)

```bash
# Scratch dir — do not record from inside the marketplace repo
mkdir -p /tmp/flow-demo && cd /tmp/flow-demo

# 1. Plugin installed and active (real output format: "  ❯ flow@<source>")
claude plugins list 2>&1 | grep -qE 'flow@' || { echo "FAIL: flow not installed"; exit 1; }

# 2. Demo repo prepared
test -d sync-cli || git clone <synthetic-sync-cli-repo> sync-cli
cd sync-cli && git status --porcelain && [ -z "$(git status --porcelain)" ] || { echo "FAIL: dirty worktree"; exit 1; }

# 3. gh CLI authenticated
gh auth status >/dev/null 2>&1 || { echo "FAIL: gh not authenticated"; exit 1; }

# 4. Asciinema configured
asciinema --version >/dev/null 2>&1 || { echo "FAIL: asciinema missing"; exit 1; }

# 5. Stub remote for AC2 auth-failure scenario reachable
#    (Set up separately — provision a small local HTTP server returning 401 for
#    `/sync` and 200 for `/health`. Any tool works: `python -m http.server` with a
#    reverse proxy, or a 30-line Express/Bottle/Flask script. Document the chosen
#    setup at recordings/stub-server-README.md before recording day.)
curl -sf http://localhost:9999/health || { echo "FAIL: stub server not running — see recordings/stub-server-README.md"; exit 1; }

# 6. Dry-run /flow:setup and /flow:status from cold (per hands-on slide)
/flow:setup
/flow:status
```

If any check fails, the slide is wrong, not the engineer. Update the slide before recording.

## Live-narration timing budget

| Beat | Duration | Cumulative wall-clock |
|------|----------|----------------------|
| Pre-roll setup | 30s | 0:00–0:30 |
| Phase A play | 2:30 | 0:30–3:00 |
| Phase B play | 4:00 | 3:00–7:00 |
| **Pause beat 1** | 75s | 7:00–8:15 |
| Phase C play | 3:00 | 8:15–11:15 |
| Phase D play | 4:00 | 11:15–15:15 |
| **Pause beat 2** | 75s | 15:15–16:30 |
| Phase E play | 2:30 | 16:30–19:00 |
| Phase F play | 2:30 | 19:00–21:30 |
| **Pause beat 3** | 60s | 21:30–22:30 |
| Phase G play | 1:30 | 22:30–24:00 |
| **Pause beat 4** | 45s | 24:00–24:45 |
| Recap on slide 30 | 15s | 24:45–25:00 |

**Total**: 25:00 — fits the 25-min slot exactly. Recording itself: 19:30–20:00.

## What the room must take away (in order)

1. **Eval-as-spec** — verification commands are decided at plan time, not verify time. (Pause beat 1)
2. **Independent judgment** — verdict-judge sees outcomes, not process. (Pause beat 2)
3. **No incomplete shipments** — P3 is fix or escalate. (Pause beat 3)
4. **Structural safety** — Tier 3 confirmation is enforced; force-push is hook-blocked. (Pause beat 4)

If only one lands, it should be #2. That's the question PM/design will ask, and the answer that justifies the rest of the architecture.
