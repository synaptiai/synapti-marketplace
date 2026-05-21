# Skill Manifests

Mapping of each `/flow` command to its required domain skills.

## Foundation Skills (Always Loaded)

These three skills are always active when the flow plugin is enabled:

| Skill | Purpose | Size |
|-------|---------|------|
| evidence-based-development | Show evidence, cite file:line, P1/P2/P3 | <=100 lines |
| autonomous-workflow | E>P>C>V loop, Task tools, three-tier safety | <=100 lines |
| code-quality-principles | Surgical changes, no secrets, atomic commits | <=100 lines |

## Command → Domain Skills

| Command | Required Domain Skills | Max Concurrent |
|---------|----------------------|----------------|
| `/flow:start` | branch-and-task-management, change-classification, capability-discovery | 3 |
| `/flow:commit` | change-classification, convention-enforcement | 2 |
| `/flow:pr` | pr-lifecycle, code-review-methodology, capability-discovery | 3 |
| `/flow:review` | code-review-methodology | 1 |
| `/flow:address` | feedback-resolution, change-classification, capability-discovery | 3 |
| `/flow:merge` | merge-and-release | 1 |
| `/flow:release` | merge-and-release | 1 |
| `/flow:status` | (none) | 0 |
| `/flow:learn` | (none) | 0 |
| `/flow:setup` | capability-discovery | 1 |
| `/flow:explain` | (none) | 0 |
| `/flow:debug` | debugging-patterns, change-classification | 2 |
| `/flow:design` | architecture-patterns, capability-discovery | 2 |
| `/flow:brainstorm` | brainstorming, capability-discovery | 2 |
| `/flow:issue` | issue-crafting | 1 |

## Domain Skills Inventory

The "Invocation" column reflects each skill's frontmatter posture: `context: fork` (runs in an isolated subagent), `disable-model-invocation` (policy/reference doc; never autonomously invoked), or `inline` (runs in the parent's context). Cycles 10 and 11 of PR #109 unforked 15 skills (3 previously-broken Pattern A + 12 broader audit); the table below reflects the post-cycle-11 state.

| Skill | Type | Invocation | Key Knowledge |
|-------|------|-----------|---------------|
| issue-crafting | domain | inline | Solution-agnostic issues, duplicate detection |
| branch-and-task-management | domain | context: fork | Branch creation, task decomposition |
| change-classification | domain | context: fork | Signal-based change analysis |
| convention-enforcement | domain | context: fork | Commit/branch validation |
| capability-discovery | domain | inline | Environment detection, LSP capability probing |
| code-review-methodology | domain | context: fork | 6-facet review, finding synthesis |
| pr-lifecycle | domain | disable-model-invocation | PR creation policy (reference) |
| feedback-resolution | domain | context: fork | Surgical feedback fixes |
| merge-and-release | domain | disable-model-invocation | Merge prereqs, release policy (reference) |
| preflight-checks | domain | disable-model-invocation | Phase 0 PRE-FLIGHT policy (reference) |
| runtime-verification | domain | inline | Dev server, E2E, smoke tests, LSP diagnostics |
| visual-verification | domain | inline | Screenshot-analyze-verify loop |
| team-coordination | domain | disable-model-invocation | Agent team orchestration (reference) |
| debugging-patterns | domain | context: fork | Root cause methodology, hypothesis testing |
| architecture-patterns | domain | context: fork | C4 design, coupling analysis |
| tdd-patterns | domain | context: fork | Red-Green-Refactor, test quality |
| brainstorming | domain | context: fork | Multi-option exploration |
| specification-capture | domain | inline | Non-goals, failure modes, interface contracts |
| holdout-validation | domain | inline | Cross-reference self-claims against file state |
| criterion-verification-map | domain | context: fork | AC → verification command mapping |
| merge-conflict-resolution | domain | context: fork | Conflict analysis + resolution |
| goal-contract-capture | domain (v3) | inline | FlowGoal YAML capture |
| goal-evaluator | domain (v3) | inline | Deterministic + judge dispatch |
| goal-evidence-ledger | domain (v3) | context: fork | Evidence sidecar atomic writes |
| goal-lifecycle | domain (v3) | inline | State machine enforcement |
| run-state-management | domain (v3) | context: fork | FlowRun + FlowActivity ledger |
| trigger-policy | domain (v3) | inline | Trigger ACL + recursion deny |
| workflow-validation | domain (v3) | inline | Schema + cross-reference validation |

## Context Window Budget

| Layer | Count | Max Size | Total Budget |
|-------|-------|----------|-------------|
| Foundation | 3 | 5KB each | 15KB |
| Domain (concurrent) | max 3 | varies | ~25KB |
| **Total** | **6** | | **~40KB** |

Rule: Never load more than 3 domain skills simultaneously. The dispatcher ensures this by mapping commands to fixed skill sets.
