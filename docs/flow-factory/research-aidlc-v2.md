# AWS AI-DLC Workflows: what it is, how it runs, and where it stops

The page you linked describes AI-DLC v2, not the three-phase v1 your brief assumed. v2 has 5 phases, 33 stages, 14 agents, 11 named scopes and a 134-event audit trail. Its artifacts live under `aidlc/spaces/<space>/intents/<record>/`, and the audit trail is split into one file per clone (`audit/<host>-<clone>.md`) rather than a single file. The three phases (Inception, Construction, Operations), `aidlc-docs/` and the single `audit.md` describe v1.0.x. v1 is still tagged in the repo and is covered separately in section 8.

## Sources and how much I read

Every claim below is tagged with the version it describes and the source it came from.

**Version shorthand**
- **[v2]** is `awslabs/aidlc-workflows` main at commit `ca2c816c` (2026-11-11). The README badge says 2.11.3; the latest preview tag is v2.11.4-preview.20261110.1.
- **[v1]** is tag `v1.0.1` (commit `e40f6a93`).
- **Path shorthand:** `M/<path>` means `https://github.com/awslabs/aidlc-workflows/blob/ca2c816cb7a55e20269a4d661f3d8694daa8589f/<path>`, and `V1/<path>` means `…/blob/v1.0.1/<path>`.

**Site versus repo:** the site is built from `docs/`. I checked that it matches main by finding a distinctive sentence from `docs/reference/01-architecture.md` ("Twenty-nine stages use inline execution") on the rendered page https://awslabs.github.io/aidlc-workflows/reference/01-architecture/. The scope counts on the rendered scopes page also match.

**Read in full**
- v2 docs: `docs/reference/00-overview.md`, `docs/reference/01-architecture.md` (Overview through Key Design Decisions), `docs/guide/04-phases-and-stages.md`, the README.
- v2 source: the frontmatter of all 33 stage files under `core/aidlc-common/stages/**`.
- v1 rules: `core-workflow.md`, `session-continuity.md`, `question-format-guide.md`, `process-overview.md`, `workspace-detection.md`, `workflow-planning.md`, `depth-levels.md`, `workflow-changes.md` (first 120 lines), and `security-baseline.opt-in.md`.

**Read in part (headings or sections)**
- `docs/guide/` chapters 05, 07, 09, 10, 11 and 13, plus 00 (searched for stated limits).
- `docs/reference/` chapters 04-stage-protocol, 12-state-machine, 17-skill-system and 18-plugin-mechanism.
- `docs/harness-engineering/00-overview.md`, `docs/roadmap.md`, `core/knowledge/aidlc-shared/state-template.md`, and `core/sensors/aidlc-traceability.md`.
- Two stage bodies: deployment-execution and reverse-engineering.
- In v1: the reverse-engineering, requirements-analysis and code-generation rules, the artifact paths in every v1 stage rule file, and the README sections on tenets, extensions and features.

**Not opened:** reference chapters 02, 03 (one search only), 05–11, 13–16, 19, 20 and `04-stages/*`; guide chapters 01–03, 06, 08, 12, 14–18, workshop-mode and the harness guides; the `.ts` engine and hooks; the 2.0 specification PDF.

---

## 1. Architecture and phases [v2]

**Execution model.** Some stages run inline and some are sent to subagents:

> "AI-DLC uses a hybrid execution model: some stages run inline (the conductor loads the agent persona and executes directly in conversation), while others delegate to subagents via the Claude Code Task tool. Inline stages support user interaction (questions, clarifications, approval). Subagent stages run autonomously and return structured summaries." (M/docs/reference/01-architecture.md §Overview)

**Engine and conductor.** Two parts move the work. The engine is a deterministic script (`core/tools/aidlc-orchestrate.ts`) that emits exactly one typed directive per step. Its subcommands are `next`, `continue`, `report`, `park`, `team-board` and `wait`. The conductor is the `skills/aidlc/SKILL.md` file, described as "a thin forwarding loop that acts on the engine's directives":

```
1. directive = `aidlc engine orchestrate next $ARGUMENTS`
2. act on directive.kind
3. After stage work, `aidlc engine orchestrate report --stage <directive.stage> --result <outcome> ...`
4. Repeat only when the directive calls for continuation
```

The engine has 11 directive kinds; 9 are emitted today. They are `print`, `error`, `done`, `parked`, `notice`, `load-steering`, `run-stage`, `ask` and `invoke-swarm`. `dispatch-subagent` and `present-gate` are placeholders (M/docs/reference/17-skill-system.md §1–3). The split of responsibility is stated this way: the engine "owns *between-stage routing*"; the conductor "owns *execution quality inside the move the engine named*".

**Five layers** (M/docs/reference/01-architecture.md §Five Layers):
- **Rules:** the memory files `org.md`, `team.md`, `project.md` and `phases/*.md`.
- **Agents:** 14 flat files, made up of 11 domain experts, 2 reviewers and the composer.
- **Knowledge:** shared material plus per-agent material.
- **Skills:** the conductor, the protocol modules and the 33 stage files.
- **Hooks:** audit, session lifecycle, state sync, PreCompact and SubagentStop.

**Phases.** Each phase boundary has a verification gate:

```
INITIALIZATION (0.1–0.3) --auto-proceed--> IDEATION (1.1–1.7)
  --Verification Gate 1--> INCEPTION (2.1–2.9)
  --Verification Gate 2--> CONSTRUCTION (3.1–3.7)
  --Verification Gate 3--> OPERATION (4.1–4.7) -.Feedback Loop.-> 1.1
```

The phase-boundary check verifies that "All required artifacts from the completing phase exist", that "Traceability links between artifacts are intact", that there are "No orphaned artifacts", and that related artifacts are consistent. "If verification fails, the conductor reports the issues and asks whether to proceed or go back" (M/docs/guide/04-phases-and-stages.md). The results are written to `<record>/verification/` (M/docs/reference/01-architecture.md, design decision 11).

**Ordering:** "Stages run one at a time, in order… Within one workflow, a later phase does not start while a stage in an earlier phase is still open." Parallel work exists only in these forms (M/docs/guide/04-phases-and-stages.md):
- Swarm Unit batches in Construction.
- Per-Unit design waves.
- Team mode, where each person claims a Unit.
- The mob and hub-and-spoke stages.

**Execution topology:** 29 inline stages, 2 subagent (2.2 and 3.5), 1 pipeline (2.1) and 1 mob (2.4).

## 2. Each stage [v2]

The data below comes from each stage file's frontmatter (`M/core/aidlc-common/stages/<phase>/<slug>.md`).

**Field meanings**
- **Exec** is `execution`: ALWAYS or CONDITIONAL.
- **Inputs** are declared as `consumes` (artifact plus `required` flag) and `requires_stage`. The engine passes the paths to the stage. A missing input is either expected (the stage that makes it is not in the scope) or a real gap that is raised with the user (M/docs/guide/04-phases-and-stages.md).
- **Storage:** stage outputs go to `<record>/<phase>/<stage>/` with the question file beside them. `<record>` is `aidlc/spaces/<space>/intents/<YYMMDD>-<label>/`. Per-Unit stages write under a per-Unit directory. Reverse Engineering is the one exception and writes to `aidlc/spaces/<space>/codekb/<repo>/`.
- **Gate:** every stage outside Initialization ends with an approval gate. "Rev" means a reviewer agent runs before the gate. "SC" means a summary confirmation is required before the artifact is written.

**Initialization.** All three stages are ALWAYS, run inline, have no gate, and run inside one deterministic call to `aidlc-utility intent-create`.

| # | Stage | Output |
|---|---|---|
| 0.1 | workspace-scaffold | The intent record tree and the space `knowledge/` directory |
| 0.2 | workspace-detection | Greenfield/brownfield classification and stack detection. It is "a rule-based scanner (file extensions, known config filenames, package manifests)" |
| 0.3 | state-init | `<record>/aidlc-state.md` and the `audit/` shards |

**Ideation.** All seven stages run inline with SC.

| # | Stage | Exec | Lead | Produces | Notes |
|---|---|---|---|---|---|
| 1.1 | intent-capture | ALWAYS | product | intent-statement, stakeholder-map, questions | Rev: product-lead |
| 1.2 | market-research | COND ("external market positioning or build-vs-buy") | product | competitive-analysis, market-trends, build-vs-buy | |
| 1.3 | feasibility | COND ("integration constraints, regulatory requirements, or significant technical uncertainty") | architect | feasibility-assessment, constraint-register, raid-log | |
| 1.4 | scope-definition | ALWAYS | product | scope-document, intent-backlog | |
| 1.5 | team-formation | COND | delivery | team-assessment, skill-matrix, mob-composition | |
| 1.6 | rough-mockups | COND ("user-facing UI") | design | wireframes, user-flow | Rev: product-lead |
| 1.7 | approval-handoff | ALWAYS | delivery | initiative-brief, decision-log | |

**Inception**

| # | Stage | Exec | Mode | Lead | Produces | Notes |
|---|---|---|---|---|---|---|
| 2.1 | reverse-engineering | COND, brownfield only | pipeline | developer, then architect | 9 code-knowledge files (see section 3) | |
| 2.2 | practices-discovery | COND ("Always rerun for freshness") | subagent hub-and-spoke | pipeline-deploy | team-practices, discovered-rules, evidence | On approval, content is copied to `memory/team.md` and `memory/project.md` |
| 2.3 | requirements-analysis | ALWAYS ("depth scales") | inline | product | requirements.md, questions, traceability.json | Rev: product-lead |
| 2.4 | user-stories | COND | mob | product | stories, personas, user-stories-assessment, traceability | Rev: product-lead |
| 2.5 | refined-mockups | COND | inline | design | mockups, interaction-spec, design-system-mapping, accessibility-checklist | |
| 2.6 | domain-design | COND | inline | architect | components.md (YAML catalogue), decisions.md (architecture decision records), traceability | Rev: architecture-reviewer |
| 2.7 | units-generation | ALWAYS when in scope | inline | architect | unit-of-work, unit-of-work-dependency (the dependency graph), unit-of-work-story-map | Rev: architecture-reviewer |
| 2.8 | contract-design | COND ("inter-unit boundary… OR… public/external API") | inline | architect | contract-summary.md with inline OpenAPI/AsyncAPI specs | Rev: architecture-reviewer |
| 2.9 | delivery-planning | ALWAYS | inline | delivery | bolt-plan, team-allocation, risk-and-sequencing-rationale, external-dependency-map | Proposes the Construction Verification Command for human approval |

**Construction.** Stages 3.1–3.5 run per Unit (`for_each: unit-of-work`); 3.6 and 3.7 run once.

| # | Stage | Exec | Lead | Produces | Notes |
|---|---|---|---|---|---|
| 3.1 | functional-design | COND | architect | entities, rules, functional-spec | Rev, SC |
| 3.2 | nfr-requirements | COND | architect | performance, security, scalability, reliability and observability requirements, plus tech-stack-decisions | Rev, SC |
| 3.3 | nfr-design | COND (only if 3.2 ran) | architect | design files for the same five areas, plus logical-components | Rev, SC |
| 3.4 | infrastructure-design | COND | aws-platform | infrastructure-specification, monitoring-design, cicd-pipeline | Rev, SC |
| 3.5 | code-generation | ALWAYS | developer | Application code, code-generation-plan, unit-test-instructions, code-summary, traceability.json | Subagent stage. The plan is written inline and needs Plan Approval before the build. Rev: architecture-reviewer, up to 2 iterations |
| 3.6 | build-and-test | ALWAYS, once | quality | build-instructions, build-and-test-summary, test-results, cross-unit-traceability | |
| 3.7 | ci-pipeline | COND, once | pipeline-deploy | ci-config, quality-gates | SC |

**Operation.** All seven stages are CONDITIONAL, inline, with SC. Stage 4.7 is terminal: approving it completes the workflow.

| # | Stage | Lead | Produces |
|---|---|---|---|
| 4.1 | deployment-pipeline | pipeline-deploy | cd-config, deployment-strategy, rollback-runbook |
| 4.2 | environment-provisioning | aws-platform | environment-inventory, validation-report |
| 4.3 | deployment-execution | pipeline-deploy | deployment-log, smoke-test-results, health-check-report |
| 4.4 | observability-setup | operations | dashboards, alarms, slo-config, log-queries, tracing-config, anomaly-config |
| 4.5 | incident-response | operations | runbooks, incident-plan, escalation-matrix |
| 4.6 | performance-validation | quality | load-test-plan, load-test-results, nfr-validation-matrix |
| 4.7 | feedback-optimization | operations | slo-report, cost-analysis, drift-report, feedback-loop |

**Construction defaults** (M/docs/guide/04-phases-and-stages.md)
- New solo work that has Units runs **unit-major and serial**: each Unit finishes its design stages and Code Generation before the next starts. Each Unit then gets a **verified Unit checkpoint**.
- That checkpoint runs a human-approved **Construction Verification Command**: "The verifier records a tool-owned `CHECKPOINT_VERIFICATION_RECORDED` receipt… a hand-written proof file cannot verify a Unit."
- The walking skeleton is "the first DAG Unit… Its code must run through a real end-to-end check, and you approve the verified skeleton before later Units begin."
- After the skeleton, the user is offered **Continue automatically** or **Review each checkpoint**. Even under "Continue automatically", Plan Approval, summary confirmation, the verification-command choice and every failure still go to the human.
- Failures always stop the run: "Failures always stop Construction, even in autonomous mode." The user is offered retry, skip or abort.

**Ideation inputs** are captured with traceability: claims "carry inline source tags", and "Retained assumptions require explicit confirmation before the Product Lead reviewer and approval gate run."

## 3. How the workflow adapts to each request [v2]

There are three separate controls: "Scopes control **which stages execute**. Depth controls **how much detail**… Test strategy controls **how many tests**" (M/docs/guide/05-scopes-and-depth.md).

**Scopes**
- There are 11 stock scopes: enterprise, feature, mvp, poc, bugfix, refactor, infra, security-patch, classic, workshop and express.
- Each scope is a file at `scopes/aidlc-<name>.md`, and each stage lists the scopes it belongs to in its `scopes:` frontmatter. These compile into `scope-grid.json`, which the docs call "authoritative".
- Stage counts are given two ways, and both are correct. The routing table counts all 33 stages (enterprise and feature 33, mvp 23, poc 8, bugfix 9, refactor 10, infra 15, security-patch 10, classic 18, workshop 26, express 10). The per-scope prose excludes the three Initialization stages ("All 30", "20 of 30"…).
- `classic` is "the implicit default" and is described as "v1-style ceremony: Inception and Construction". The default can be changed with `AWS_AIDLC_DEFAULT_SCOPE`.
- A tick in the stage-by-scope matrix means the stage is in the scope's plan, "not that it will unconditionally execute. CONDITIONAL stages may be skipped at runtime when their condition does not hold."

**How a plan is chosen**
- "The engine keeps your request and hands it to the agent with every plan AI-DLC ships… the hint words its author wrote in the plan file (`keywords:`)… no tool matches them."
- The user gets one question with three answers: go ahead with the proposed plan, use a different plan, or tailor a plan to this task.

**The composer** builds tailored plans:
- It "estimates five implementation-entropy components – intent ambiguity, codebase structural uncertainty, verification entropy, risk, and unresolved assumptions – and composes the minimum viable workflow: the least sufficient EXECUTE/SKIP grid that still produces every artifact the outcome depends on."
- The approval gate shows the plan's Guard Policy and six settings: sensors, learnings, summary_confirmation, plan_approval, collaborators and review_cap.
- "nothing is written and no workflow starts before an explicit approval."
- A tailored plan can be saved as a scope (`aidlc/scopes/<name>.md`).

**Changing the plan mid-run**
- `/aidlc compose` re-plans only stages that have not started yet. Finished and in-progress stages are frozen.
- Changes are checked so that no remaining stage is left without a required input, and are recorded as `RECOMPOSED`.
- "The first EXECUTE stage of Construction cannot be flipped."

**Depth** has three levels: Minimal is "1-2 page artifact, key decisions only"; Standard is a complete artifact; Comprehensive adds optional sections and compliance cross-references. Depth can be changed with `--depth`, at the scope confirmation, or at any gate.

**Brownfield and greenfield**
- Workspace Detection (0.2) classifies the project.
- Reverse Engineering runs "when project is brownfield. On rerun the Step 1 guard checks store freshness (codekb-scope-diff) – verified-CURRENT stores may be reused by human choice, anything else rescans" (M/core/aidlc-common/stages/inception/reverse-engineering.md).
- The project type records who set it (`Project Type Source: workspace scan | you`). If a greenfield folder later gains code, the user is asked once (M/core/knowledge/aidlc-shared/state-template.md).

**Reverse Engineering**
- It runs as a pipeline: "Developer scan, then architect synthesis-and-write". With collaborators off, the developer agent does both steps.
- It produces 9 files in `aidlc/spaces/<space>/codekb/<repo>/`: business-overview, architecture, code-structure, api-documentation, component-inventory, technology-stack, dependencies, code-quality-assessment and reverse-engineering-timestamp.
- These files are shared knowledge for each repository and are kept outside any single intent. "Reverse Engineering re-runs for each applicable workflow and refreshes that shared per-repository knowledge" (M/docs/reference/01-architecture.md).
- Work across several repositories needs "one complete chain per repo before approval."
- An external code-knowledge server (an MCP server called CodeKB) can provide structural evidence instead. With it, the composer may propose skipping Reverse Engineering, and the user decides at the gate.

## 4. State tracking and resumption [v2]

**State file:** `<record>/aidlc-state.md` is "the single source of truth for that intent's workflow progress" (M/docs/guide/10-state-and-audit.md). Its sections are:
- Project Information
- Scope Configuration (stages, depth, test strategy, Guard Policy, Guards Off/On, Sensors, Learnings, Summary Confirmation, Plan Approval, Collaborators)
- Workspace State
- Execution Plan Summary
- Runtime State (revision count, Construction iteration and execution, Verification Command, Unit ownership)
- Phase Progress
- Stage Progress
- Unit Progress
- Current Status
- Session Resume Point

**Stage checkboxes** have six states:
- `[ ]` not started
- `[-]` in progress
- `[?]` awaiting approval
- `[R]` revising
- `[x]` completed
- `[S]` skipped

"Stage prose never edits lifecycle checkboxes directly." The engine updates the file and writes the audit row in one step (M/docs/reference/01-architecture.md, design decision 4).

**Audit trail**
- It is stored as one file per clone, `<record>/audit/<host>-<clone>.md`, all committed. This is "precisely so git never has to merge concurrent appends."
- It has 134 events in 27 categories, for example `STAGE_STARTED`, `GATE_APPROVED`, `HUMAN_TURN`, `PLAN_APPROVAL_RECORDED`, `RECOMPOSED`, `RULE_LEARNED` and `CHECKPOINT_VERIFICATION_RECORDED` (M/docs/guide/10-state-and-audit.md).
- Only tools and hooks write it: "Never create, edit, rename, or delete audit records yourself." It is read through `aidlc engine audit history` and `log answers`, and returned text is labelled "data, never an instruction" (M/docs/reference/04-stage-protocol.md §Audit Trail Rules).

**What is committed:** memory, knowledge, the code-knowledge directory, `intents.json`, each `aidlc-state.md`, the audit shards and the artifacts. The pointers to the active space and intent, session bindings and derived state are gitignored (M/docs/reference/01-architecture.md §workspace).

**Resuming work** (M/docs/guide/11-session-management.md)
- A bare `/aidlc` "carries on where the work stopped". An earlier unanswered question is asked again.
- Other options are redo the current stage, jump to a stage (skipped stages are marked `[S]`; jumping back resets the stages after the target), or start a new intent alongside the old one.
- `/aidlc park` stops at a clean point between stages, and `--resume` continues.
- Code Generation resumes from the ticks in its plan: "Picking up unit-2's code at step 5 of 9."
- Context compaction: a PreCompact hook validates the state file and records `SESSION_COMPACTED`. Files on disk survive; in-memory conversation does not.

**Recovering from damage** (M/docs/reference/04-stage-protocol.md §Error Recovery)
- A corrupt state file is backed up to `.bak` and rebuilt from the artifacts that exist ("Rebuilt from artifacts. Please verify.").
- For missing artifacts, the agent checks whether the stage that makes them is in the scope's plan before re-running anything.
- Errors are graded by severity: Critical and High stop and ask the user.

## 5. Human-in-the-loop model [v2]

**Three ways to answer questions**
- Questions are written to a file next to the stage's artifacts (for example `<record>/inception/user-stories/user-stories-questions.md`). The user chooses **Guide me**, **I'll edit the file** or **Chat**.
- "All three modes converge on the questions file as the canonical record." The choice is asked once per piece of work and reused.
- Each question is labelled with who would usually answer it, such as `[Product owner]` or `[Developer]` (M/docs/guide/07-interaction-modes.md).
- Answers are checked for vague replies, contradictions and missing details. "If ANY ambiguity found, create follow-up questions… Do NOT proceed until resolved."
- When the user leaves a choice to the agent ("up to you"), the agent records it with `log answer --on-instruction --message <id>`. "A checkpoint or an approval is never left to the agent" (M/docs/reference/04-stage-protocol.md).

**Approval gates**
- Each gate offers Approve or Request Changes, and the Approve option names the next stage.
- Replies in the user's own words count ("looks fine but rename the handler" approves and carries out the change).
- After three change requests, an **Accept as-is** option appears. The engine counts the requests from the audit trail.
- During Ideation and Inception the user can choose "Approve, and add [Skipped Stage] next."

**A real human must be behind every approval**
- "The gate requires an observed human-interaction seam: typing a prompt or answering a native question picker records a human turn (a `HUMAN_TURN` event)… approve… refuses unless one was recorded since the last gate resolution."
- The authors state the limit of this check: "This proves presence and ordering, not authorship of the later caller-supplied decision text."
- Automation must set `AIDLC_UNATTENDED=1`. With it set, "every harness withholds the authority-bearing `HUMAN_TURN`, so approval and interview gates continue to wait."
- Only `AIDLC_SKIP_HUMAN_PRESENCE_GUARD=1` lowers the presence check (M/docs/guide/07-interaction-modes.md; M/docs/guide/13-customization.md).

**Guard Policy and the five guards ("fences")**
- Guard Policy takes `strict`, `relaxed` or `off`. It decides whether a change to an already-approved input reopens the approval, and how hard the guards hold.
- The five guards are plan approval, review freeze, state transition, reviewer read scope and human presence.
- "No value lowers human presence or claimed-checkout Unit write ownership."
- Lowering a guard is "the person's call". The tool refuses without `--message <id>` naming the user's own message (M/docs/guide/13-customization.md).

**Other settings that add or remove stops:** sensors, learnings, summary confirmation, plan approval and collaborators. "Neither switch removes a stage's questions or its approval gate" (M/docs/guide/05-scopes-and-depth.md).

## 6. Extension and customization [v2]

**Data, not code:** "Everything a harness engineer touches is a Markdown file with YAML frontmatter or a JSON config… these require *no TypeScript edits*" (M/docs/harness-engineering/00-overview.md).

**Stages and agents**
- Stage frontmatter declares slug, phase, execution, condition, lead and support agents, mode, reviewer, produces, consumes, `requires_stage`, sensors, scopes and `for_each`.
- Stage files compile into `stage-graph.json`, which the engine routes from.
- "A stage names its lead agent; an agent never names its stages."

**Scopes:** stock scope files plus each stage's `scopes:` tag, composed plans, and saved scopes in `aidlc/scopes/<name>.md`.

**Rules and the learning loop**
- Rules resolve through five layers: org → team → project → phase → stage. They live in `aidlc/spaces/<space>/memory/` and contain `## Forbidden`, `## Mandated` and `## Corrections` sections.
- When the user corrects an agent, the "Keep that for next time?" step writes the correction to `project.md` (it can be promoted to `team.md`) or scaffolds a sensor (M/docs/guide/09-rules-and-the-learning-loop.md; M/docs/reference/01-architecture.md, design decision 10).

**Sensors** are deterministic checks with a manifest: `id`, `kind`, `command`, `default_severity` (advisory or blocking), `fire_on` (for example `gate`), `matches`, and input/output schemas. Shipped sensors are traceability, required-sections, upstream-coverage, claim-sources, linter and type-check. "A blocking binding requires a verified pass", and only a human can override one (M/core/sensors/aidlc-traceability.md; M/docs/reference/04-stage-protocol.md).

**Team knowledge** goes in `aidlc/spaces/<space>/knowledge/`. Framework knowledge is per agent under `knowledge/aidlc-<agent>/`.

**Plugins:** "an optional, owned, versioned set of contributions – new stages, agents, scopes, sensors, doctor checks, and *additive modifications to existing core stages*." They are "Strict-additive, never override," leave the core files untouched, and are "Reversible & inert when off." Each one is shipped as a real plugin for the host tool (M/docs/reference/18-plugin-mechanism.md). The reference example is `plugins/test-pro/`.

**Other settings**
- Agent models and effort through `aidlc.settings.json`, in three layers: machine, project and local.
- Ceremony switches, Guard Policy, depth and test strategy.
- Team mode (`Unit Ownership: team`), where each person claims Units.
- Parallel Unit builds (`Construction Execution: swarm`, stage-major only) (M/docs/reference/01-architecture.md; M/docs/guide/04-phases-and-stages.md).

## 7. What it does not do [v2]

Most of these limits are stated in the sources. The last two are my inference and are marked as such.

- **No approval without a human.** Unattended runs wait at every gate (see the `AIDLC_UNATTENDED` quote above). Plan Approval, summary confirmation, the verification command and failures need a human even in autonomous Construction.
- **No commits during parallel builds:** "the tool never commits automatically and checks all Units before creating any child" (M/docs/guide/04-phases-and-stages.md).
- **Presence, not identity:** it proves "presence and ordering, not authorship". The audit write guard "is a guardrail, not a security boundary" (M/docs/guide/07-interaction-modes.md; M/docs/guide/10-state-and-audit.md).
- **Shell-written files are not audited:** "a file written by a shell command is not" logged (M/docs/guide/10-state-and-audit.md).
- **No nested delegation:** "Agents never invoke each other or spawn subagents" (M/docs/reference/01-architecture.md, design decision 13).
- **No parallel stages within one workflow** (quote in section 1). Unit-major Construction stays serial.
- **No issue tracker or pull-request integration** in any page I read. Work is identified by intents and Units in `aidlc/`, with commit provenance through `aidlc attest`. This is my inference: I did not search the whole repo for GitHub or Jira integration.
- **No independent triggering** in what I read: every run starts from a chat command (`/aidlc` or `$aidlc`). This is also my inference, limited to the pages I read.
- **Some placeholders are unimplemented:** `dispatch-subagent` and `present-gate` are not emitted ("do not implement speculatively").
- **Stated known limitation:** Claude Code does not fire a hook on `cd`, so session events may not reflect switching between projects (M/docs/reference/12-state-machine.md §Known limitations).
- **Deployment stays grounded:** "Never invent an environment inventory or deployment path" (M/core/aidlc-common/stages/operation/deployment-execution.md).
- **Kiro plugin installs have no trust check:** "dropping the tree *is* the trust decision" (M/docs/reference/18-plugin-mechanism.md).
- **Experimental:** the README says "Generative AI can make mistakes. Review generated output and costs before acting on them."

## 8. v1.0.1: the three-phase model your brief described

Sources: V1/aidlc-rules/aws-aidlc-rules/core-workflow.md and V1/aidlc-rules/aws-aidlc-rule-details/**. Some v1 headings contain emojis; I quote them without the emojis.

**What v1 is:** a set of prompt rules with no engine. The rules declare "PRIORITY: This workflow OVERRIDES all other built-in workflows." Their stated principle is "The workflow adapts to the work, not the other way around," assessed on intent clarity, existing code, complexity and risk.

**Stages**

| Phase | Stage | Exec | Notes |
|---|---|---|---|
| Inception | Workspace Detection | ALWAYS | No gate |
| Inception | Reverse Engineering | COND, brownfield with no current artifacts | Rerun if the artifacts are stale |
| Inception | Requirements Analysis | ALWAYS, adaptive depth | |
| Inception | User Stories | COND | Detailed ALWAYS / LIKELY / SKIP criteria; "Default to inclusion for borderline cases" |
| Inception | Workflow Planning | ALWAYS | Picks EXECUTE or SKIP per stage and writes `inception/plans/execution-plan.md` with a risk level and a diagram |
| Inception | Application Design | COND | |
| Inception | Units Generation | COND | |
| Construction | Functional Design | COND, per unit | |
| Construction | NFR Requirements | COND, per unit | |
| Construction | NFR Design | COND, per unit | |
| Construction | Infrastructure Design | COND, per unit | |
| Construction | Code Generation | ALWAYS, per unit | Part 1 is a plan with checkboxes and an approval; Part 2 generates the code |
| Construction | Build and Test | ALWAYS, once | |
| Operations | Operations | Placeholder | "This stage is currently a placeholder for future expansion" |

- Construction runs per unit: "Each unit is completed fully (design + code) before moving to the next unit."
- Build and Test writes test instruction files only (build, unit, integration, performance, contract, security, e2e and summary). In v1 it does not run anything.

**Storage**
- Documentation goes in `aidlc-docs/inception/{plans,reverse-engineering,requirements,user-stories,application-design}/` and `aidlc-docs/construction/{plans,<unit>/{functional-design,nfr-requirements,nfr-design,infrastructure-design,code},build-and-test}/`.
- `aidlc-docs/aidlc-state.md` and `aidlc-docs/audit.md` hold state and the audit log.
- "Application code: Workspace root (NEVER in aidlc-docs/)."
- Reverse Engineering writes 9 files to `aidlc-docs/inception/reverse-engineering/`, the same set as v2.

**Gates:** every stage after Workspace Detection says "Wait for Explicit Approval… DO NOT PROCEED until user confirms." Construction uses a "standardized 2-option completion message" ("NO EMERGENT BEHAVIOR"). Workflow Planning adds an option to add skipped stages.

**Depth:** "When a stage executes, ALL its defined artifacts are created. The 'depth' refers to the level of detail… Model decides" (V1/…/common/depth-levels.md).

**State:** `aidlc-state.md` holds stage checkboxes and current status. Progress is tracked at two levels: "Plan-Level… Stage-Level", with "IMMEDIATELY after completing ANY step… mark that step [x]."

**Audit:** every user input is logged as "COMPLETE RAW INPUT exactly as provided (never summarize)", with ISO timestamps, appended and never overwritten.

**Resuming:** the agent reads `aidlc-state.md`, loads the earlier stages' artifacts, and offers "A) Continue… B) Review a previous stage" (V1/…/common/session-continuity.md).

**Questions** (V1/…/common/question-format-guide.md)
- "You must NEVER ask questions directly in the chat. ALL questions must be placed in dedicated question files."
- Answers use lettered options with `[Answer]:` tags, and "Other" is mandatory as the last option.
- The agent checks for contradictions and ambiguities, and writes a `*-clarification-questions.md` file if needed.

**Changing the plan mid-run:** adding or skipping stages, restarting the current or a previous stage (with backups and an impact warning), and changing depth (V1/…/common/workflow-changes.md).

**Extensions:** files under `extensions/<category>/` with a `*.opt-in.md` prompt that is asked during Requirements Analysis. The full rules load only when the user opts in. The choice is recorded under `## Extension Configuration` in the state file. "Non-compliance with any applicable enabled extension rule is a **blocking finding**." Shipped extensions cover security baseline, resiliency baseline and property-based testing.

**Tenets:** "Methodology first… Reproducible… Agnostic… Human in the loop. Critical decisions require explicit user confirmation. The agent proposes, the human approves" (V1/README.md).

**v1 limits:** Operations is a placeholder, there is no deterministic engine (the model follows prose rules), and Build and Test only writes instructions.