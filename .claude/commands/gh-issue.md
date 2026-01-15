# Create GitHub Issue

Create a new GitHub issue following solution-agnostic principles.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** extensively for interactive dialogues. Use it to clarify ambiguity, offer choices with tradeoffs, and gather missing context.

## Phase 1: Gather Requirements

1. **Use the AskUserQuestion tool** to gather missing information:
   - **Context**: What's the background? Why is this needed?
   - **Current State**: What's the problem? (describe behavior, not implementation)
   - **Objective**: What should be achieved? (outcomes, not methods)
   - **Acceptance Criteria**: How do we know it's complete? (observable behavior)

2. **Extract keywords** from the user's description for duplicate detection

## Phase 2: Search for Existing Issues

Before creating a new issue, check for potential duplicates:

1. **Search open issues** using relevant keywords:
   ```bash
   gh issue list --state open --search "RELEVANT_KEYWORDS"
   ```

2. **Search closed issues** (may have already been solved):
   ```bash
   gh issue list --state closed --search "RELEVANT_KEYWORDS"
   ```

3. **If matches found, use the AskUserQuestion tool**:

   Present the findings and offer choices:
   - **Option 1: Proceed** - "Create new issue (these are different enough)"
   - **Option 2: View existing** - "View issue #{number} instead"
   - **Option 3: Cancel** - "This is a duplicate, don't create"

   Include in the question: issue numbers, titles, and states of potential duplicates.

4. **If no matches found**: Inform user and proceed to validation

## Phase 3: Validate Solution-Agnostic Principles

**Validate** the issue is solution-agnostic:
- NO specific file paths
- NO specific code structures
- NO technology-specific implementation details
- Acceptance criteria describe BEHAVIOR, not implementation changes

**If implementation details detected**, use the **AskUserQuestion tool** to clarify:
- Quote the specific implementation detail found
- Explain why it should be rephrased
- Offer options:
  - **Option 1**: "Help me rephrase as a requirement"
  - **Option 2**: "Keep it (I understand the tradeoff)"
  - **Option 3**: "Remove this section entirely"

## Phase 4: Select Labels

1. **List available labels**:
   ```bash
   gh label list
   ```

2. **Use the AskUserQuestion tool** to confirm labels:

   Present recommended labels based on issue content with option to modify:
   - **Option 1**: "Apply suggested labels: [bug, enhancement]"
   - **Option 2**: "Let me choose different labels"
   - **Option 3**: "Add additional labels"

   Available labels:
   - `bug` - Something isn't working
   - `enhancement` - New feature or improvement
   - `documentation` - Documentation improvements
   - `security` - Security related issues
   - `plugin` - Plugin-specific changes

## Phase 5: Preview & Approve

Before creating, show the user a complete preview, then **use the AskUserQuestion tool** to get explicit approval:

First, display the preview:
```
**Issue Preview**

Title: [TITLE]
Labels: [label1, label2]

---
## Context
[rendered context section]

## Current State
[rendered current state section]

## Objective
[rendered objective section]

[...rest of body...]
---
```

Then **invoke the AskUserQuestion tool** with these options:
- **Option 1**: "Create this issue" (Recommended)
- **Option 2**: "Edit title or labels first"
- **Option 3**: "Edit body content first"
- **Option 4**: "Cancel"

**Do not create the issue without explicit approval via the AskUserQuestion tool.**

If user chooses option 2 or 3, gather their changes and show updated preview, then ask again.

## Phase 6: Create the Issue

After user approves (option 1):

```bash
gh issue create --title "TITLE" --body "BODY" --label "label1" --label "label2"
```

## Phase 7: Verification

After creation, verify the issue was created correctly:

1. **Fetch the issue** to confirm:
   ```bash
   gh issue view {issue-number} --json number,title,labels,state
   ```

2. **Verify checklist**:
   - [ ] Issue exists and is OPEN
   - [ ] Title matches what was previewed
   - [ ] Labels applied correctly

3. **Report success** with:
   - Issue URL
   - Issue number
   - Next step: `/gh-start {issue-number}` to begin work

## Issue Template

Use this exact structure for the issue body:

```markdown
## Context
<!-- What's the background? Why is this needed? -->

[USER INPUT]

## Current State
<!-- What's happening now? What's the problem? Describe behavior, not implementation. -->

[USER INPUT]

## Objective
<!-- What should be achieved? What's the desired end state? Focus on outcomes, not methods. -->

[USER INPUT]

## Proposed Solution (Optional)
<!--
FOCUS ON "WHAT" NOT "HOW":
- Describe required functionality or behaviors
- List data requirements and success criteria
- Explain business logic and requirements
- Avoid specific file paths
- Avoid specific code structures that may change during refactoring

Why? Implementation details belong in the PR, not issues. Issues should survive refactoring.
-->

[USER INPUT IF PROVIDED]

## Tasks
<!-- High-level functional outcomes, not implementation steps -->
- [ ] [Task 1 - Example: "Add new agent for X analysis" NOT "Create agents/x-analyzer.md"]
- [ ] [Task 2 - Example: "Update command documentation" NOT "Edit commands/foo.md line 42"]

## Benefits
<!-- What are the advantages of doing this? -->
- [Benefit 1]
- [Benefit 2]

## Acceptance Criteria
<!-- How do we know this is complete? Describe observable behavior, not file changes. -->
- [ ] [Criterion 1 - Example: "Agent produces accurate analysis" NOT "File created in agents/"]
- [ ] [Criterion 2 - Example: "Command accessible via /plugin:command" NOT "Entry added to plugin.json"]

## Related
<!-- Links to related issues, PRs, or discussions -->
- [Any related links]
```

## Validation Checklist

Before creating, verify:
- [ ] Issue focuses on WHY (business need, problem) and WHAT (outcomes, requirements)
- [ ] No file paths mentioned
- [ ] No specific code structures mentioned
- [ ] Acceptance criteria describe observable behavior, not file changes
- [ ] Proposed solution (if any) describes WHAT is needed, not HOW to build it
- [ ] Duplicate check completed
- [ ] Labels selected and confirmed

## Workflow Context

After issue creation:
1. Use `/gh-start {issue-number}` to begin work
2. Issues describe WHAT to achieve (requirements, goals)
3. Implementation details go in the PR description

This separation ensures issues remain valid even when implementation details change during refactoring.

## Rules

- Issues must be solution-agnostic
- Implementation details belong in PRs, not issues
- Always search for duplicates before creating
- Always assign at least one relevant label
- Always preview before creating
- Always verify after creation
- **Use the AskUserQuestion tool** at every decision point:
  - Duplicate detection results
  - Implementation detail validation
  - Label selection
  - Final approval before creation

## Success Criteria

Before completing, verify:
- [ ] User requirements gathered (context, current state, objective, acceptance criteria)
- [ ] Duplicate search completed
- [ ] Solution-agnostic principles validated
- [ ] Labels selected and confirmed
- [ ] Preview shown and user explicitly approved
- [ ] Issue created via `gh issue create`
- [ ] Issue verified to exist via `gh issue view`
- [ ] User informed of issue URL and next steps
