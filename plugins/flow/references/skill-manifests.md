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
| `/flow start` | branch-and-task-management, change-classification, capability-discovery | 3 |
| `/flow commit` | change-classification, convention-enforcement | 2 |
| `/flow pr` | pr-lifecycle, code-review-methodology, capability-discovery | 3 |
| `/flow review` | code-review-methodology | 1 |
| `/flow address` | feedback-resolution, change-classification, capability-discovery | 3 |
| `/flow merge` | merge-and-release | 1 |
| `/flow release` | merge-and-release | 1 |
| `/flow status` | (none) | 0 |
| `/flow learn` | (none) | 0 |
| `/flow setup` | capability-discovery | 1 |
| `/flow explain` | (none) | 0 |
| `/flow debug` | debugging-patterns, change-classification | 2 |
| `/flow design` | architecture-patterns, capability-discovery | 2 |
| `/flow brainstorm` | brainstorming, capability-discovery | 2 |

## Domain Skills Inventory

| Skill | Type | Invocation | Key Knowledge |
|-------|------|-----------|---------------|
| issue-crafting | domain | context: fork | Solution-agnostic issues, duplicate detection |
| branch-and-task-management | domain | context: fork | Branch creation, task decomposition |
| change-classification | domain | context: fork | Signal-based change analysis |
| convention-enforcement | domain | context: fork | Commit/branch validation |
| capability-discovery | domain | context: fork | Environment detection |
| code-review-methodology | domain | context: fork | 5-facet review, finding synthesis |
| pr-lifecycle | domain | context: fork | PR creation, reviewer suggestion |
| feedback-resolution | domain | context: fork | Surgical feedback fixes |
| merge-and-release | domain | disable-model-invocation | Merge prereqs, release process |
| runtime-verification | domain | context: fork | Dev server, E2E, smoke tests, visual verification |
| team-coordination | domain | disable-model-invocation | Agent team orchestration |
| debugging-patterns | domain | context: fork | Root cause methodology, hypothesis testing |
| architecture-patterns | domain | context: fork | C4 design, coupling analysis |
| tdd-patterns | domain | context: fork | Red-Green-Refactor, test quality |
| brainstorming | domain | context: fork | Multi-option exploration |

## Context Window Budget

| Layer | Count | Max Size | Total Budget |
|-------|-------|----------|-------------|
| Foundation | 3 | 5KB each | 15KB |
| Domain (concurrent) | max 3 | varies | ~25KB |
| **Total** | **6** | | **~40KB** |

Rule: Never load more than 3 domain skills simultaneously. The dispatcher ensures this by mapping commands to fixed skill sets.
