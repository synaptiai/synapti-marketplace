---
dossier-header: internal-v1
title: {fill}
purpose: {fill}
audience: {fill}
confidentiality: Internal
owner: {fill}
status: draft
project-version: {fill}
last-verified: {fill}
review-trigger: {fill}
related: []
---
# Onboarding and Local Development
<!-- contract: references/package-contract-04-operating.md#onboarding-and-local-development -->

Every command in this document carries a verification mark — `verified`, `partially verified`, or `not executed` — with the environment and date it was checked on. Production credentials and production data are never used for local development, and no instruction here asks for them.

## Onboarding routes

| Role | Route | First meaningful contribution | Time to it |
|---|---|---|---|
| Engineering | {fill} | {fill} | {fill} |
| Product | {fill} | {fill} | {fill} |
| Design | {fill} | {fill} | {fill} |
| Data / AI | {fill} | {fill} | {fill} |
| Operations | {fill} | {fill} | {fill} |
| Security | {fill} | {fill} | {fill} |
| Leadership | {fill} | {fill} | {fill} |

## Prerequisites

| Prerequisite | Supported version | How to install or obtain | Required for | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

| Access needed | Requested from | Approval required | Typical lead time |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

**Expected setup time from a clean machine:** {fill} — measured on {fill} at {fill}

## Setup

From a clean checkout. Each step states what it changes and how to tell it worked.

```bash
{fill}
```

| Step | Command | Verifies success by | Verification | Environment | Date |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill — verified \| partially verified \| not executed} | {fill} | {fill} |

## Configuration and secrets

Names, purposes, and how to obtain a value. Never a value.

| Setting | Purpose | Required | How to obtain a development value | Safe default |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

Development values come from the development secret source. Production credentials are not valid input to any step in this document.

## Local dependencies and data

| Dependency | Run locally how | Alternative | Seed or synthetic data | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

Seed data is synthetic or anonymised at source. A dataset described as anonymised names the technique and its known limits.

## Daily operations

| Task | Command | Expected result | Verification | Date |
|---|---|---|---|---|
| Build | {fill} | {fill} | {fill} | {fill} |
| Run | {fill} | {fill} | {fill} | {fill} |
| Test | {fill} | {fill} | {fill} | {fill} |
| Lint / type-check | {fill} | {fill} | {fill} | {fill} |
| Debug | {fill} | {fill} | {fill} | {fill} |
| Reset to clean state | {fill} | {fill} | {fill} | {fill} |
| Clean up | {fill} | {fill} | {fill} | {fill} |

## Development workflow

| Stage | Practice | Tooling | Evidence |
|---|---|---|---|
| Branching | {fill} | {fill} | {fill} |
| Commit conventions | {fill} | {fill} | {fill} |
| Review | {fill} | {fill} | {fill} |
| CI | {fill} | {fill} | {fill} |
| Release | {fill} | {fill} | {fill} |
| Feature flags | {fill} | {fill} | {fill} |

## Reading order

| Order | Document or code path | Why it comes here | Time |
|---:|---|---|---|
| 1 | {fill} | {fill} | {fill} |

## First day, week, and month

| Horizon | Outcome | How it is demonstrated |
|---|---|---|
| First day | {fill} | {fill} |
| First week | {fill} | {fill} |
| First month | {fill} | {fill} |

## Starter task

A real, small, verified change. Not a hypothetical.

**Task:** {fill}

**Why it is safe:** {fill}

| Step | Action | Expected result |
|---:|---|---|
| 1 | {fill} | {fill} |

**Verification:** {fill — verified \| partially verified \| not executed}, on {fill}, at {fill}

### Guided code trace

{fill — an alternative for readers who will not be writing code: follow one request or job through the system, naming the files at each hop.}

## Troubleshooting

| Symptom | Likely cause | Resolution | Verified |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

## Proposing changes

| Change kind | Where to propose it | Who decides | What the proposal must contain |
|---|---|---|---|
| Product | {fill} | {fill} | {fill} |
| Architecture | {fill} | {fill} | {fill} |
| Security | {fill} | {fill} | {fill} |
| Documentation | {fill} | {fill} | {fill} |

## Definition of done

| Work type | Done means |
|---|---|
| Engineering | {fill} |
| Product | {fill} |

## Getting help

| Need | Contact | Channel | Hours |
|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} |

**Current ownership gaps a newcomer will hit:** {fill — the areas where no one is assigned, stated plainly so a new teammate does not spend a week looking for an owner who does not exist}
