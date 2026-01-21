# Brief Template

This template is used by `/ledger-init` to generate `00-brief/BRIEF.md`.

---

# Project Brief

**Created:** {date}
**Last Updated:** {date}

## Core Description

{Maximum 5 sentences describing what is being built. Focus on the what, not the how.}

## Target Users

### Primary Users
{Who will use this product most frequently}

### Secondary Users
{Who else might use this product}

### Non-Users
{Explicitly who this is NOT for}

## Goals

### Must Achieve
{Non-negotiable success criteria}

1. {Goal 1 - specific and measurable}
2. {Goal 2 - specific and measurable}
3. {Goal 3 - specific and measurable}

### Nice to Have
{Additional goals if primary goals are met}

1. {Stretch goal 1}
2. {Stretch goal 2}

## Constraints

### Hard Constraints
{Non-negotiable limitations}

1. {Constraint 1 - e.g., "Must launch within 3 months"}
2. {Constraint 2 - e.g., "Budget under $X"}
3. {Constraint 3 - e.g., "Must integrate with existing system Y"}

### Soft Constraints
{Preferences that can be traded off}

1. {Preference 1}
2. {Preference 2}

## Out of Scope

{Explicit exclusions to prevent scope creep}

- {Exclusion 1 - e.g., "Mobile app (web only for MVP)"}
- {Exclusion 2 - e.g., "Enterprise features"}
- {Exclusion 3 - e.g., "Internationalization"}

## Context

### Domain Background
{Any domain-specific context needed to understand the brief}

### Existing Assets
{What already exists that this builds on}

### Key Assumptions
{Assumptions the brief is built on - these should become evidence targets}

1. {Assumption 1 - will need EV-* validation}
2. {Assumption 2 - will need EV-* validation}

---

## Usage

When generating BRIEF.md:

1. **Parse** - Extract components from user's brief text
2. **Expand** - Add structure where user was informal
3. **Validate** - Ensure all required sections have content
4. **Prompt** - Ask user to fill gaps for incomplete sections

### Quality Checks

| Section | Quality Check |
|---------|---------------|
| Core Description | ≤5 sentences, focuses on what not how |
| Target Users | At least primary users identified |
| Goals | At least 1 "Must Achieve" goal |
| Constraints | At least 1 hard constraint |
| Out of Scope | At least 1 explicit exclusion |

### Common Issues

**Too vague:**
```
BAD: "Build an app that helps people"
GOOD: "Build a task management web app for remote software teams"
```

**Goals not measurable:**
```
BAD: "Make users happy"
GOOD: "Achieve 40% weekly active user retention by month 3"
```

**Missing constraints:**
```
BAD: [No constraints listed]
GOOD: "MVP must launch before Q2, team of 2 engineers"
```

**Scope creep risk:**
```
BAD: [No out-of-scope section]
GOOD: "Out of scope: mobile app, enterprise SSO, API access"
```

---

## Example

### Input Brief
"We want to build a tool that helps developers write better documentation. Target is small to medium dev teams. We need to ship something in 6 weeks."

### Generated BRIEF.md

```markdown
# Project Brief

**Created:** 2026-01-21
**Last Updated:** 2026-01-21

## Core Description

A documentation tool for software developers that improves documentation quality and consistency. The tool will help dev teams create, maintain, and improve their technical documentation. Initial focus on small to medium development teams (5-50 developers).

## Target Users

### Primary Users
Software developers who write and maintain technical documentation

### Secondary Users
Technical writers, engineering managers reviewing documentation

### Non-Users
Non-technical staff, end-users of documented software

## Goals

### Must Achieve
1. Reduce time spent writing documentation by 30%
2. Improve documentation consistency across a codebase
3. Achieve product-market fit signal (10 paying teams) within 3 months of launch

### Nice to Have
1. Integration with popular IDEs
2. Automated documentation generation from code

## Constraints

### Hard Constraints
1. Must ship MVP within 6 weeks
2. Team resources: [needs clarification]
3. Must work with existing developer workflows

### Soft Constraints
1. Prefer web-based over desktop app
2. Prefer integration with GitHub

## Out of Scope

- Mobile application
- Enterprise features (SSO, audit logs)
- Non-English language support
- Self-hosted deployment option

## Context

### Domain Background
Developer documentation is often outdated, inconsistent, or missing. Existing tools focus on generation rather than quality improvement.

### Existing Assets
[Needs input - any existing code, designs, research?]

### Key Assumptions
1. Developers will adopt a new tool if it saves significant time
2. Documentation quality can be measured and improved algorithmically
3. Small teams have budget for productivity tools (~$10-30/user/month)
```
