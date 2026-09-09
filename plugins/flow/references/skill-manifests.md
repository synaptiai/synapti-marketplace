# Skill Manifests

Mapping of each `/flow` command to the skills it loads. Generated from the command files' `## Required Skills` bullets and `bin/flow-load-skills.sh --list`; regenerate when either changes (`tests/flow-load-skills.test.sh` fails if the bullets and the loader block drift apart).

## How loading works

Commands cannot preload skills from frontmatter, so each command with Required Skills carries a `!` block that calls `bin/flow-load-skills.sh <names...>`. Claude Code pre-executes it at invocation and injects the output. **Ambient** skills (no `context: fork` / `agent:`) are inlined whole. **Dispatched** skills (`context: fork` or `agent:`) contribute only their `## Contract` section (first H2, at most 120 words); their body runs when the command invokes `Skill(<name>)`. Every skill body is at most 600 words.

## Command → loaded skills

| Command | Required skills | Ambient | Contracts | Words inlined |
|---------|-----------------|---------|-----------|---------------|
| `/flow:address` | llm-operator-principles, feedback-resolution, change-classification, capability-discovery, tdd-patterns, holdout-validation, goal-evidence-ledger, run-state-management | 1 | 7 | 1275 |
| `/flow:brainstorm` | brainstorming, capability-discovery, specification-capture | 0 | 3 | 289 |
| `/flow:commit` | llm-operator-principles, change-classification, convention-enforcement | 1 | 2 | 787 |
| `/flow:debug` | debugging-patterns, change-classification, goal-contract-capture, goal-evaluator, goal-lifecycle, run-state-management | 0 | 6 | 587 |
| `/flow:design` | architecture-patterns, capability-discovery, specification-capture | 0 | 3 | 303 |
| `/flow:explain` | (none) | 0 | 0 | 0 |
| `/flow:flow` | (none) | 0 | 0 | 0 |
| `/flow:goal` | goal-contract-capture, goal-evaluator, goal-lifecycle, goal-evidence-ledger | 0 | 4 | 396 |
| `/flow:issue` | issue-crafting | 0 | 1 | 108 |
| `/flow:learn` | (none) | 0 | 0 | 0 |
| `/flow:merge` | llm-operator-principles, merge-and-release, run-state-management | 1 | 2 | 791 |
| `/flow:pr` | llm-operator-principles, pr-lifecycle, code-review-methodology, capability-discovery, holdout-validation, run-state-management, runtime-verification, visual-verification | 1 | 7 | 1272 |
| `/flow:release` | merge-and-release, run-state-management | 0 | 2 | 192 |
| `/flow:resolve` | merge-conflict-resolution, capability-discovery, debugging-patterns | 0 | 3 | 300 |
| `/flow:resume` | run-state-management | 0 | 1 | 91 |
| `/flow:review` | llm-operator-principles, code-review-methodology, holdout-validation, run-state-management | 1 | 3 | 871 |
| `/flow:run` | trigger-policy | 0 | 1 | 98 |
| `/flow:setup` | capability-discovery | 0 | 1 | 105 |
| `/flow:start` | llm-operator-principles, branch-and-task-management, change-classification, capability-discovery, debugging-patterns, preflight-checks, criterion-verification-map, holdout-validation, issue-crafting, specification-capture, tdd-patterns, goal-contract-capture, goal-lifecycle, run-state-management, runtime-verification, visual-verification | 1 | 15 | 2048 |
| `/flow:status` | (none) | 0 | 0 | 0 |
| `/flow:trigger` | trigger-policy | 0 | 1 | 98 |
| `/flow:watch` | trigger-policy | 0 | 1 | 98 |
| `/flow:workflow` | workflow-validation | 0 | 1 | 94 |

## Skills inventory

| Skill | Loading | Body words | Purpose |
|-------|---------|------------|---------|
| architecture-patterns | dispatched | 589 | Document system design decisions with mapped user flows, coupling analysis, failure modes, and explicit non... |
| autonomous-workflow | ambient | 599 | Execute development workflows through Explore-Plan-Code-Verify phases with task-driven tracking, Tier 1/2/3... |
| brainstorming | dispatched | 437 | Generate 2-4 distinct approaches with trade-off analysis across simplicity, flexibility, performance, effor... |
| branch-and-task-management | dispatched | 400 | Create feature branches with naming conventions, load full issue context and impact analysis, and decompose... |
| capability-discovery | dispatched | 503 | Discover available agents, skills, quality commands (lint, test, typecheck), tech stack, verification capab... |
| change-classification | dispatched | 443 | Classify code changes as in-context, uncertain, or out-of-context using primary signals (branch diff, issue... |
| code-quality-principles | ambient | 590 | Enforce code quality through the Boy Scout Rule (leave code better than found), secret-free commits, produc... |
| code-review-methodology | dispatched | 596 | Conduct two-stage code review: Stage 1 verifies spec compliance (criterion-to-code mapping), Stage 2 evalua... |
| convention-enforcement | dispatched | 432 | Validate git conventions (commit messages, branch naming, PR format, issue linkage) by detecting project-sp... |
| criterion-verification-map | dispatched | 600 | Transform acceptance criteria into plan-time runnable verification commands (behavioral, API, UI, error, pe... |
| debugging-patterns | dispatched | 574 | Isolate root causes through structured evidence gathering, pattern analysis, hypothesis testing (max 3 at a... |
| evidence-based-development | ambient | 451 | Enforce evidence-based claims through file:line citations, P1/P2/P3 prioritization proportional to evidence... |
| feedback-resolution | dispatched | 590 | Address PR review feedback through surgical fixes traceable to specific comments, apply the Boy Scout Rule... |
| goal-contract-capture | dispatched | 593 | Capture a FlowGoal contract as `.flow/goals/<id>.goal.yaml` — outcome, acceptance criteria with verificatio... |
| goal-evaluator | dispatched | 598 | Evaluate a FlowGoal against its evidence ledger: run every deterministic verification command first, dispat... |
| goal-evidence-ledger | dispatched | 469 | Maintain the append-only evidence ledger: `.flow/runs/<run-id>/evidence/*.evidence.yaml` sidecars plus matc... |
| goal-lifecycle | dispatched | 498 | Enforce the FlowGoal state machine: every `lifecycle.status` transition (draft → active → {waiting_for_user... |
| holdout-validation | dispatched | 597 | Cross-reference agent self-review claims and evidence-bundle entries against actual file state using hidden... |
| issue-crafting | dispatched | 425 | Craft well-structured GitHub issues with solution-agnostic outcomes, duplicate detection (open and closed),... |
| llm-operator-principles | ambient | 599 | Frame Claude's identity as an LLM operator that does not tire, treats convergence as zero findings (not exh... |
| merge-and-release | dispatched · reference-only | 585 | Reference document describing merge prerequisites (approval, CI checks, mergeable, conversations resolved,... |
| merge-conflict-resolution | dispatched | 551 | Detect, classify (porcelain status; complexity: trivial, semantic, structural, delete-modify), and resolve... |
| pr-lifecycle | dispatched · reference-only | 585 | Reference document describing PR lifecycle: pre-flight gates (4 conditions), verification gate (5 condition... |
| preflight-checks | dispatched · reference-only | 543 | Reference document describing six pre-flight checks (clean git state, not detached HEAD, gh auth, issue exi... |
| run-state-management | dispatched | 514 | Manage FlowRun state at `.flow/runs/<ISO-timestamp-id>/run.yaml` — create runs at command entry, write acti... |
| runtime-verification | dispatched | 594 | Verify code works at runtime through build verification (mandatory), LSP diagnostics, ad-hoc verification f... |
| specification-capture | dispatched | 600 | Capture the four specification elements (non-goals, failure modes, interface contracts, risk map) for an is... |
| tdd-patterns | dispatched | 595 | Guide test-driven development through the mandatory Red-Green-Refactor cycle: a test is RED only when it fa... |
| team-coordination | dispatched · reference-only | 586 | Coordinate agent teams for adversarial review (paired skeptic/verifier per facet, disposition-only challeng... |
| trigger-policy | dispatched | 495 | Enforce FlowTrigger safety rules — no autonomous merge, no recursive trigger creation, max active triggers,... |
| visual-verification | dispatched | 590 | Verify UI-facing changes by running a screenshot-analyze-verify loop across configured viewports, with a br... |
| workflow-validation | dispatched | 502 | Validate a FlowWorkflow YAML at `plugins/flow/workflows/<id>.workflow.yaml` against `schemas/v1/workflow.sc... |

## Budget

Skill bodies are capped at 600 words and contracts at 120 (enforced by `tests/flow-load-skills.test.sh`). The largest command load today is `/flow:start` at 2048 words; the sum across all commands is 9803. Agents load skills through their own `skills:` frontmatter (see `agents/*.md`), which is unaffected by this mechanism.
