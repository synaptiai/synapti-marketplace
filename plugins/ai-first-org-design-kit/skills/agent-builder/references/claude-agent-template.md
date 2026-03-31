# Claude Code Agent Template

When the user selects "Register as Claude Code sub-agent" in Phase 6, generate a `.claude/agents/{role-slug}.md` file in the target project using this template.

## Template

```markdown
---
name: {ROLE_SLUG}
description: "{ROLE_DESCRIPTION}. Use proactively for {PRIMARY_TASKS}."
tools: {TOOLS_CSV}
model: inherit
memory: project
skills: {SKILLS_CSV}
---
<!-- generated-by: ai-first-kit v{VERSION} | generated: {TIMESTAMP} -->

{SYSTEM_PROMPT_CONTENT}
```

## Field Mapping

| Template Field | Source |
|---------------|--------|
| `{ROLE_SLUG}` | From Phase 1 role selection — sanitized with `tr/sed` (lowercase, hyphens, max 50 chars) |
| `{ROLE_DESCRIPTION}` | From Phase 2 — one-sentence summary of specification responsibility |
| `{PRIMARY_TASKS}` | From Phase 2 Q4 — top 2-3 representative tasks, comma-separated |
| `{TOOLS_CSV}` | From Phase 3 — mapped from tool-permissions.md to Claude Code tool names |
| `{SKILLS_CSV}` | From Phase 4 — governance skills relevant to this role, comma-separated (see mapping below) |
| `{VERSION}` | Current plugin version |
| `{TIMESTAMP}` | ISO 8601 timestamp |
| `{SYSTEM_PROMPT_CONTENT}` | Full system prompt from Phase 5 — inlined verbatim (100+ lines) |

## Skill Mapping by Agent Type

Map the agent's role to relevant governance skills:

### Development Agents (code, implementation, specification)
```yaml
skills: org-record-decision, org-novel-situation, org-gate-review
```

### Assistant Agents — Content/Voice
```yaml
skills: org-voice-check, org-record-decision, org-gate-review
```

### Assistant Agents — Research/Strategy
```yaml
skills: org-record-decision, org-values-check
```

### All Agents (minimum)
```yaml
skills: org-record-decision
```

## Tool Name Mapping

Map from tool-permissions.md descriptions to Claude Code tool names:

| Permission Description | Claude Code Tool |
|----------------------|-----------------|
| File reading | Read |
| File writing/creation | Write |
| File editing | Edit |
| Shell commands | Bash |
| File search by name | Glob |
| Content search | Grep |
| Web browsing/fetching | WebFetch |
| Web search | WebSearch |
| User questions | AskUserQuestion |
| Spawning sub-agents | Agent |

## Update Detection

When generating, first check if `.claude/agents/{ROLE_SLUG}.md` already exists:

1. If exists: read it, extract the `generated-by` comment
2. Compare current system prompt content hash against existing
3. If identical: "Agent '{role}' is already registered and up to date."
4. If different: show what changed, ask "Update the registered agent?"
5. If user confirms: overwrite with new content

## Notes

- Agent system prompts are INLINED (not referenced via @import — agents don't support it)
- The `memory: project` field creates `.claude/agent-memory/{ROLE_SLUG}/MEMORY.md` on first run
- Skills listed in `skills:` have their FULL content injected at agent startup
- The `<!-- generated-by -->` comment enables version tracking and update detection
- Agents do NOT get CLAUDE.md automatically — but the project's CLAUDE.md with @imports handles foundation context for the main session
