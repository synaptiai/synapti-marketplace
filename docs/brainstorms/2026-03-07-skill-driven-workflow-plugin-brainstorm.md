# Brainstorm: Skill-Driven Workflow Plugin

**Date**: 2026-03-07
**Status**: Complete
**Inspired by**: [Skill-Driven vs Spec-Driven Development](https://wiki.totto.org/blog/2026/03/07/skill-driven-vs-spec-driven-development/)

---

## What We're Building

A new Claude Code plugin that replaces command-driven GitHub workflow automation with a skill-driven, agent-team-powered approach. Instead of procedural scripts that tell Claude what to do step-by-step, we encode the team's development knowledge as composable skills that Claude internalizes and applies autonomously.

**The core shift**: From "follow these 11 phases when starting work on an issue" to "here's everything our team knows about how to start work on an issue — apply it."

### The Problem with the Current Approach

The current gh-workflow plugin (v1.7.0) encodes both **knowledge** and **procedure** inside 13 command files. This creates three compounding problems:

1. **Session amnesia**: Each session re-reads command files but retains no learning. Correct a mistake in session 1; the same mistake reappears in session 50.

2. **Knowledge imprisonment**: Valuable domain knowledge (e.g., change classification, 5-facet review methodology) is locked inside specific commands. The change-classification logic in `/gh-commit` is powerful — but it only runs when that command is invoked. If Claude commits during `/gh-start`, the same knowledge isn't applied.

3. **Interaction overhead**: ~40 explicit AskUserQuestion decision points create a stop-and-wait workflow. Most of these gates protect reversible actions that a skilled developer would handle autonomously.

### What Changes

| Aspect | gh-workflow (current) | New plugin |
|--------|----------------------|------------|
| Knowledge carrier | Command files (re-read each session) | Skills (loaded, contextually applied) |
| Execution model | Single session + subagents | Agent teams + single session (adaptive) |
| User interaction | ~40 decision points | Three-tier: autonomous / journal-and-proceed / confirm |
| Safety model | Pre-approval AskUserQuestion gates | Hooks (deterministic) + three-tier classification + journal |
| Learning | None | Session-end journal analysis -> skill proposals |
| Invocation | Explicit `/command` required | Auto-triggered by skill descriptions |
| Review model | Subagents report back to main | Adversarial team review (teammates challenge each other) |

---

## Why This Approach

### The Article's Key Insight

> "The spec tells the agent what to build today. The skill library tells the agent everything the team has ever learned about how to build well. Both matter. Only one compounds."

Skills compound across sessions and across contexts. A skill about change classification applies during commits, during PR creation, during addressing review feedback — anywhere Claude encounters code changes. Commands only apply when explicitly invoked.

### Agent Teams as Force Multiplier

Claude Code's agent teams (experimental) allow multiple Claude instances to work in parallel with shared task lists and direct inter-agent messaging. Combined with skills:

- Every teammate loads the same skill library automatically (via CLAUDE.md and plugin skills)
- A security reviewer teammate has the `code-review-methodology` skill — not because someone scripted it, but because the skill is always available
- Teammates can challenge each other's findings (adversarial review), which a single agent cannot do
- The lead coordinates based on `team-coordination` skill knowledge, not rigid command phases

### Trust-but-Verify Safety Model

Instead of ~40 pre-approval gates:
- **Hooks** block genuinely dangerous operations deterministically (force-push, branch deletion, destructive commands)
- **Decision journal** logs every significant decision with reasoning and alternatives
- **Post-hoc review** replaces pre-hoc approval for reversible actions
- Claude acts like a trusted team member who documents their reasoning, not an untrusted tool that needs permission for every action

---

## Key Decisions

### 1. Hybrid A+B Architecture (Skill-First + Agent Teams)

**Skills** are the primary knowledge carrier. **Agent teams** provide parallel execution for complex workflows. **Hooks** enforce deterministic safety. **Commands** are minimal optional entry points.

```
┌──────────────────────────────────────────────────────────────┐
│                      SKILL LIBRARY                           │
│                                                              │
│  Foundation (always loaded, <5KB each)                       │
│  ├─ evidence-based-development                               │
│  ├─ autonomous-workflow                                      │
│  └─ code-quality-principles                                  │
│                                                              │
│  Domain (contextual, max 3 simultaneous)                     │
│  ├─ issue-crafting          ├─ feedback-resolution           │
│  ├─ branch-and-tasks        ├─ merge-and-release             │
│  ├─ change-classification   ├─ convention-enforcement        │
│  ├─ code-review-methodology ├─ runtime-verification          │
│  ├─ pr-lifecycle            └─ team-coordination (opt-in)    │
│  └─ capability-discovery                                     │
└──────────────────────┬───────────────────────────────────────┘
                       │ explicitly invoked by
                       ▼
              ┌─────────────────┐
              │  /flow <verb>   │ ← thin dispatcher
              │  required skills│   with skill manifests
              │  manifest       │
              └────────┬────────┘
                       │ delegates to
        ┌──────────────┼──────────────────┐
        ▼              ▼                  ▼
   ┌─────────┐   ┌──────────┐   ┌──────────────┐
   │  Lead   │   │Teammate  │   │ Single-Session│
   │ (teams  │   │(reviewer)│   │   (primary)   │
   │  opt-in)│──▶│          │   │               │
   └────┬────┘   └──────────┘   └──────────────┘
        │ guarded by
        ▼
   ┌──────────────────────────────────────────────┐
   │              THREE-TIER SAFETY                │
   │                                               │
   │  Tier 1 (Autonomous): commit, branch, edit   │
   │  Tier 2 (Journal+Proceed): push, PR, assign  │
   │  Tier 3 (Confirm): merge, release, force ops │
   │                                               │
   │  Enforced by: PreToolUse + PostToolUse hooks  │
   └──────────────────────────────────────────────┘
```

### 2. Layered Skill Architecture

**Foundation skills** (3, always in context, hard limit: 100 lines / 5KB each):
- `evidence-based-development` — Show before decide, cite file:line, P1/P2/P3, ASSERTION/EVIDENCE/VERIFIED
- `autonomous-workflow` — Trust-but-verify, decision journaling, bounded loops, graceful degradation, sensitivity handling
- `code-quality-principles` — Surgical changes, no secrets, solution-agnostic thinking

**Domain skills** (10, explicitly invoked by `/flow` dispatcher, max 3 simultaneous):
- `issue-crafting` — Solution-agnostic issues, duplicate detection, acceptance criteria patterns
- `branch-and-task-management` — Branching conventions, task decomposition, impact analysis
- `change-classification` — In-context vs out-of-context, primary/secondary signals, first-touch detection, atomic commits
- `code-review-methodology` — 5-facet review (security, quality, conventions, tests, requirements), finding synthesis, reviewer suggestion
- `pr-lifecycle` — PR quality standards, pre-flight checks, PR body structure, comprehension narrative
- `feedback-resolution` — Surgical fixes, interpretation strategies, pushback criteria, re-review
- `merge-and-release` — Merge prerequisites, stale approval detection, semantic versioning, changelog generation
- `convention-enforcement` — Commit format, branch naming, PR format, issue linkage
- `runtime-verification` — Dev server verification, E2E testing, smoke tests, acceptance criteria verification
- `team-coordination` — When to spawn teams, task sizing, delegation, adversarial review protocol, synthesis (loaded only when agent teams enabled)
- `capability-discovery` — Discover agents, skills, quality commands, tech stack (carried over from gh-workflow)

**Safety-critical domain skills** (use `disable-model-invocation: true`):
- `merge-and-release` — Only invoked by `/flow merge` and `/flow release` dispatchers
- `team-coordination` — Only invoked when agent teams are explicitly enabled

### 3. Agent Team Integration Points

**Spawn a team when**:
- Code review (3 reviewers: security, quality, conventions — adversarial, challenging each other)
- Large feature implementation (teammates own separate modules/layers)
- Bug investigation with unclear root cause (competing hypotheses)

**Stay single-session when**:
- Quick commits (change classification + stage + commit)
- Merges (sequential prerequisite verification)
- Releases (sequential versioning)
- Issue creation (dialogue-based)
- Status checks (read-only)

The `/flow` dispatcher decides based on `team-coordination` skill knowledge. Single-session is the primary path. Agent teams are an opt-in enhancement.

**Adversarial review protocol** (when agent teams enabled):
1. Each reviewer teammate produces independent findings in isolation
2. Lead shares all findings with all reviewers
3. Reviewers score or challenge each other's findings (rebuttals with evidence)
4. Lead synthesizes based on consensus and confidence scores
5. Unresolved disagreements are flagged to the human with both perspectives
6. Final review output includes: agreed findings, challenged findings with resolution, and unresolved disputes

### 4. Three-Tier Safety Model with Hooks

**Tier 1 — Autonomous** (local, reversible, private):
Commits, branch creation, file edits, local test runs. Execute immediately, log to decision journal.

**Tier 2 — Journal-and-proceed** (remote, reversible, team-visible):
Push to feature branch, PR creation, issue assignment. Log reasoning to journal, proceed unless hook blocks. Teams can promote these to Tier 3 via configuration.

**Tier 3 — Confirm-before-execute** (irreversible or high-consequence):
Merge to default branch, release creation, force operations, branch deletion. Always require human confirmation, even in the autonomous model.

**Hook implementation**:

| Hook | Type | Purpose | Verified? |
|------|------|---------|-----------|
| PreToolUse: `git push --force*` | Hard block | Prevent force push | Yes |
| PreToolUse: `git branch -D*` | Hard block | Prevent branch deletion | Yes |
| PreToolUse: `rm -rf*` | Hard block | Prevent destructive commands | Yes |
| PreToolUse: secrets patterns | Hard block | Prevent credential exposure | Yes |
| PreToolUse: `gh pr merge*` | Tier 3 gate | Require human confirmation for merge | Yes |
| PreToolUse: `gh release create*` | Tier 3 gate | Require human confirmation for release | Yes |
| PostToolUse: `Edit\|Write` | Auto-log | Append context to decision journal | Yes |
| PostToolUse: `Bash(git commit*)` | Auto-log | Log commit decision with classification | Yes |
| TaskCompleted | Quality gate | Verify acceptance criteria met | Needs verification |
| TeammateIdle | Team coordination | Nudge idle teammates | Needs verification |
| SessionEnd | Learning trigger | Analyze journal for patterns | Needs verification |

Hooks marked "Needs verification" have documented fallbacks (see Risk Mitigations R5).

### 5. Session-Based Learning Loop

```
Session Work → Decision Journal → SessionEnd Hook
                                        │
                                        ▼
                                  Pattern Analysis
                                  (what was corrected twice?
                                   what knowledge was applied?)
                                        │
                                        ▼
                              proposals/YYYY-MM-DD-{topic}.md
                                        │
                                        ▼
                              Human Review (git diff, approve/reject)
                                        │
                                        ▼
                              Promoted to active skill or discarded
```

Skills in `proposals/` are never auto-promoted. They require human review because stale/incorrect skills are worse than no skills.

### 6. Coexistence with gh-workflow

- New plugin lives alongside gh-workflow in the marketplace
- Users choose which approach fits their team (command-driven vs skill-driven)
- Shared reference material possible (review checklists, templates)
- No migration path required — clean alternative, not evolution

### 7. Minimal Commands (Optional Entry Points)

Structured sub-commands provide deterministic dispatch. Natural language fallback with confirmation for ambiguous input.

**Primary (structured)**:
- `/flow start <issue>` — Start work on an issue (branch, implement, test, review)
- `/flow commit [message]` — Classify changes and create atomic commits
- `/flow pr [title]` — Run review, push, create PR
- `/flow review <pr>` — Multi-faceted code review (agent team if enabled)
- `/flow address <pr>` — Address PR review feedback
- `/flow merge <pr>` — Verify prerequisites and merge (Tier 3: requires confirmation)
- `/flow release <type>` — Create release (Tier 3: requires confirmation)
- `/flow status` — Quick read-only overview
- `/flow learn` — Force learning analysis now
- `/flow setup` — Initialize plugin for a repository
- `/flow explain [issue]` — Interactive Q&A about decisions and architecture

**Fallback (natural language)**:
- `/flow [anything else]` — Parse intent with confirmation: "I understood: start work on issue #5. Correct?"
- Bare `/flow` — Show available sub-commands and current workflow state

Unlike gh-workflow's 13 commands, these are thin dispatchers that explicitly invoke required skills. The knowledge lives in skills, not commands. Each sub-command has a "required skills" manifest ensuring deterministic skill loading.

---

## Risk Mitigations

Structured review identified 4 high-risk and 4 medium-risk assumptions. Each is addressed below.

### R1: Skill Auto-Triggering Reliability (HIGH → MITIGATED)

**Risk**: Probabilistic description matching may not activate the right skill, producing silently degraded behavior.

**Mitigation — Deterministic core, probabilistic enrichment**:
- The `/flow` command explicitly invokes required skills per recognized intent (deterministic)
- Auto-triggering provides supplementary enrichment during natural conversation (bonus, not relied upon)
- Each workflow stage has a "required skills" manifest. The `/flow` dispatcher verifies required skills are loaded before proceeding
- Domain skills include `disable-model-invocation: true` for safety-critical ones (merge, release). These ONLY fire when explicitly invoked
- Foundation skills remain auto-triggered (they're always loaded and apply universally)

**Design pattern**: `/flow start 5` → dispatcher identifies intent "start" → explicitly invokes `issue-crafting`, `branch-and-task-management`, `change-classification` → skills provide knowledge, dispatcher provides structure.

### R2: Trust-but-Verify for Team-Visible Actions (HIGH → MITIGATED)

**Risk**: Conflating "technically reversible" with "safe to do autonomously." PR creation, pushing, and issue state changes affect the whole team.

**Mitigation — Three-tier action classification**:

| Tier | Actions | Behavior | Examples |
|------|---------|----------|----------|
| **Autonomous** | Local, reversible, private | Execute immediately, log to journal | Commits, branch creation, file edits, local test runs |
| **Journal-and-proceed** | Remote, reversible, team-visible | Log reasoning to journal, proceed unless hook blocks | Push to feature branch, PR creation, issue assignment |
| **Confirm-before-execute** | Irreversible or high-consequence | Always require human confirmation | Merge to default branch, release creation, force operations, branch deletion |

Teams can promote/demote actions between tiers via configuration (e.g., a security-conscious team can move PR creation to "confirm-before-execute").

### R3: Agent Teams Experimental Status (HIGH → MITIGATED)

**Risk**: Experimental feature with unspecified failure modes enabled by default.

**Mitigation — Opt-in with clear enablement**:
- Agent teams are OFF by default (revised from original "default on" decision)
- Clear opt-in via settings: `"agentTeams": true` in `settings.flow.json`
- When enabled, the plugin sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
- Single-session path is the PRIMARY architecture, not a fallback
- Agent teams are an enhancement layer with documented entry/exit criteria
- `team-coordination` moves from foundation to domain skill (only loaded when teams active)
- **Teammate health protocol**: timeout per teammate (configurable), graceful degradation to single-session on failure, "team review incomplete" status in outputs, maximum retry count

**Failure handling**:
- Teammate crash → Lead continues with available results, marks review as partial
- Contradictory findings → Lead presents both with confidence scores, flags for human judgment
- Teammate timeout → Terminate after configurable limit, fall back to single-session for that facet

### R4: Plugin Coexistence Conflicts (HIGH → MITIGATED)

**Risk**: No mutual exclusion mechanism. Competing skill descriptions between flow and gh-workflow.

**Mitigation — Namespace isolation + conflict documentation**:
- All flow skill descriptions prefixed with "[flow]" marker for disambiguation
- `plugin.json` declares `"conflicts": ["gh-workflow"]` (proposed — document if Claude Code doesn't support this yet)
- README prominently states: "Do not install alongside gh-workflow"
- Foundation skills include a guard: check for gh-workflow presence and warn user
- `/flow-setup` detects gh-workflow installation and offers migration guidance
- Future consideration: propose `conflicts` field to Claude Code plugin spec

### R5: Hook Implementation Feasibility (MEDIUM → MITIGATED)

**Risk**: Only PreToolUse and PostToolUse hooks are established. TaskCompleted, TeammateIdle, and SessionEnd may not work.

**Mitigation — Verify first, design fallbacks**:
- **Phase 0 of implementation**: Prototype each hook type. Verify PreToolUse blocking, PostToolUse logging, and the three experimental hooks
- **PreToolUse + PostToolUse** (verified): Core safety and logging — these are the non-negotiable foundation
- **TaskCompleted** (needs verification): Fallback = quality verification as explicit skill step before task completion
- **TeammateIdle** (needs verification): Fallback = lead agent polls teammate status periodically
- **SessionEnd** (needs verification): Fallback = `/flow-learn` manual command is the primary learning mechanism, SessionEnd is a convenience trigger
- Document which hooks are platform-verified vs. assumed in the implementation plan

### R6: Context Window Budget (MEDIUM → MITIGATED)

**Risk**: ~76KB+ of skill content competing with conversation before any work begins.

**Mitigation — Aggressive compression + lazy loading**:
- Foundation skills: hard limit of 100 lines / 5KB each (not 150 lines). Total foundation: ~20KB
- Domain skill descriptions: ~200 chars each. Full content loads only on invocation
- Maximum simultaneous domain skills: 3 (enforced by dispatcher)
- Learned skills: separate token budget (10KB max total). Overflow triggers skill retirement review
- Instrument context usage in prototypes. Publish actual measurements before finalizing skill sizes
- Agent team teammates: load only relevant domain skills per role, not the full library

### R7: Feature Parity Gaps (MEDIUM → MITIGATED)

**Risk**: Several gh-workflow features not explicitly mapped to flow skills.

**Feature parity matrix**:

| gh-workflow Feature | flow Mapping | Status |
|---|---|---|
| Capability discovery | `capability-discovery` skill (carried over) | Kept |
| Reviewer suggestion | Merged into `pr-lifecycle` skill | Merged |
| Comprehension report | Merged into `autonomous-workflow` (decision journal serves this purpose) | Evolved |
| Self-review (code + test) | `code-review-methodology` covers both facets | Merged |
| First-touch flagging | Merged into `change-classification` | Merged |
| Familiarity prompt | Dropped — autonomous model doesn't need baseline prompts | Intentionally dropped |
| Decision journal | `autonomous-workflow` foundation skill (always active) | Promoted to core |
| gh-explain | New `/flow-explain` command (interactive Q&A about decisions) | Kept |
| gh-security-review | Merged into `code-review-methodology` security facet + dedicated agent team reviewer | Evolved |
| gh-setup | `/flow-setup` command | Kept |
| Config schema | `settings.flow.json` with JSON schema | Kept |
| Sensitivity handling | Merged into `autonomous-workflow` | Merged |

### R8: `/flow` Command Dispatch (MEDIUM → MITIGATED)

**Risk**: Natural language parsing of "review 5" is ambiguous (issue or PR?).

**Mitigation — Structured sub-commands with NL fallback**:
- Primary: `/flow <verb> <target>` — explicit and unambiguous
  - `/flow start 5` — start issue #5
  - `/flow review 12` — review PR #12
  - `/flow release patch` — create patch release
  - `/flow commit` — classify and commit changes
  - `/flow merge 12` — merge PR #12
  - `/flow address 12` — address PR #12 feedback
- Fallback: `/flow [natural language]` — parsed with confirmation: "I understood this as: start work on issue #5. Correct?"
- Bare `/flow` with no arguments: show available sub-commands and current workflow state

---

## Resolved Questions

### Q1: Plugin Name → `flow`
Simple, direct, memorable. No prefix needed — the plugin namespace handles disambiguation.

### Q2: Agent Teams → Opt-in, single-session primary (revised after review)
Agent teams are OFF by default. Opt-in via `"agentTeams": true` in settings. Single-session is the primary architecture. Agent teams enhance review and implementation but aren't required. `team-coordination` is a domain skill (loaded only when teams active), not a foundation skill.

### Q3: Configuration → Hybrid CLAUDE.md + light JSON
- **CLAUDE.md sections**: Human-readable conventions, workflow preferences, team agreements
- **Light JSON settings**: Toggles, thresholds, and machine-readable config (e.g., gate modes, timeouts, branch patterns)
- Simpler than gh-workflow's 50+ settings. Start with ~15 essential settings, expand based on learning.

### Q4: Scope → Full parity + improvements
v1.0 targets complete feature parity with gh-workflow plus improvements:
- All workflow stages covered (issue → implement → commit → PR → review → address → merge → release)
- New: agent team adversarial review, session-based learning loop, trust-but-verify model
- New: skill auto-triggering (no explicit commands needed for most workflows)
- New: decision journal as core primitive (not just comprehension layer add-on)
- Goal: not just on par, but measurably better

### Q5: Knowledge Sharing → Personal proposals, promote to team
- Session-end learning generates proposals to local `~/.claude/flow-proposals/` (personal)
- Developer reviews proposals, promotes good ones to repo's `skills/learned/` directory (shared)
- Team knowledge is version-controlled and reviewed via normal PR process
- Personal proposals that aren't promoted are still useful to that developer

---

## What Success Looks Like

1. **Zero-ceremony workflow**: Developer says "work on issue #5" and Claude autonomously creates branch, implements, tests, reviews, and creates PR — pausing only for genuinely dangerous operations.

2. **Knowledge compounding**: By month 3, the plugin is measurably better than month 1 because 50+ learned skills guide behavior. New team members benefit from accumulated knowledge immediately.

3. **Adversarial review quality**: Agent team reviews with 3 competing perspectives consistently catch issues that single-agent reviews miss.

4. **Full audit trail**: Every autonomous decision is logged with reasoning. Post-hoc review reveals Claude's decision-making process at any point.

5. **Graceful degradation**: Works as a single-session skill-driven workflow even without agent teams. Agent teams enhance but aren't required.
