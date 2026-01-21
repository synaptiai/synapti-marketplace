---
description: Initialize a Context Ledger workspace with brief parsing, directory structure, and pillar configuration
argument-hint: "[project-name]"
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# Initialize Context Ledger

Create a new Context Ledger workspace for evidence-based product development.

> **Context Isolation**: This command invokes the `initializing-ledger` skill which runs in a forked context. The initialization work is performed in isolation, keeping the main conversation clean.

## Arguments

`$ARGUMENTS`: The project brief - a text description of what you're building.

**Optional flags:**
- `--path <path>` - Custom workspace location (default: `./ledger/`)

## Workflow

1. **Parse Brief**
   - Extract core description (max 5 sentences)
   - Identify target users
   - Extract goals (must be specific/measurable)
   - Extract constraints
   - Identify out-of-scope items

2. **Validate Completeness**
   - Check for required components
   - Prompt for missing critical information
   - Confirm interpretation with user if ambiguous

3. **Create Directory Structure**
   ```
   ledger/
   ├── 00-brief/
   ├── 01-pillars/
   ├── 02-evidence/{market,users,tech,competitors,design,legal,ops,economics}/
   ├── 03-synthesis/
   ├── 04-decisions/
   ├── 05-risks/
   ├── 06-prd/
   ├── 07-architecture/
   ├── 08-plan/
   ├── 09-brand/
   └── 10-gtm-ops/
   ```

4. **Generate Initial Files**
   - `00-brief/BRIEF.md` - Structured brief document
   - `01-pillars/PILLARS.md` - Pillar configuration with priorities

5. **Report Summary**
   - Workspace path
   - Brief summary
   - Pillar priorities
   - Next steps

## Example Usage

### Basic initialization
```
/ledger-init Build a task management app for remote software teams that integrates with Slack and GitHub
```

### With custom path
```
/ledger-init --path ~/projects/taskapp/ledger "Build a task management app for remote teams"
```

### Detailed brief
```
/ledger-init We're building a documentation tool for developers. Target: small dev teams (5-50 people). Must ship MVP in 6 weeks. Web-only for now, no mobile. Key goal is reducing documentation time by 30%.
```

## Output

```markdown
## Ledger Initialized

**Path:** ./ledger/
**Created:** 2026-01-21

### Brief Summary
Building a task management app for remote software teams with Slack and GitHub integration.

### Pillar Priorities

**High Priority:**
- Users (remote team workflows critical)
- Competitors (crowded market)
- Tech (integration requirements)

**Medium Priority:**
- Market, Design, Economics

**Lower Priority:**
- Legal, Ops (MVP phase)

### Next Step
Run `/ledger-research` to begin parallel evidence collection across all pillars.
```

## User Interaction

Use the **AskUserQuestion tool** when:

### Brief is too vague
```
User: /ledger-init Build an app
→ Use AskUserQuestion tool:
  Question: "Your brief needs more detail. What type of app and who is it for?"
  Options:
  - "Let me provide a detailed brief"
  - "Help me structure my idea"
  - "Show me example briefs"
```

### Missing goals
```
User: /ledger-init Build a CRM for small businesses
→ Use AskUserQuestion tool:
  Question: "What are the key goals for this CRM? What does success look like?"
  Options:
  - "Reduce sales cycle time"
  - "Improve customer retention tracking"
  - "Replace spreadsheet-based tracking"
  - "Let me specify goals"
```

### Missing constraints
```
User: /ledger-init [brief without constraints]
→ Use AskUserQuestion tool:
  Question: "What constraints should I know about?"
  Options:
  - "Timeline: Ship within [X] weeks"
  - "Budget: Under $[X]"
  - "Team: [X] engineers available"
  - "No significant constraints"
  - "Let me specify constraints"
```

### Pillar prioritization
```
After parsing brief:
→ Use AskUserQuestion tool:
  Question: "Based on your brief, which research areas are most critical?"
  Options:
  - "Market + Users (validate demand first)" (Recommended)
  - "Tech + Competitors (validate feasibility first)"
  - "All equally important"
  - "Let me specify priorities"
```

## Quality Gates

The initialization will fail if:

| Check | Failure Condition |
|-------|-------------------|
| Core description | Empty or >5 sentences after prompting |
| Target users | Cannot identify any user group |
| Goals | Zero measurable goals after prompting |
| Constraints | Zero constraints after prompting |

## After Initialization

Your ledger is ready for evidence collection. The typical workflow:

1. `/ledger-init` - Initialize (you are here)
2. `/ledger-research` - Collect evidence across pillars
3. `/ledger-synthesize` - Synthesize findings
4. `/ledger-decide` - Make explicit decisions
5. `/ledger-spec` - Generate constrained PRD + architecture
6. `/ledger-plan` - Generate implementation plan
