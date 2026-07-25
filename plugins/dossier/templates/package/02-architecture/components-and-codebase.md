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
# Components and Codebase
<!-- contract: references/package-contract-02-architecture.md#components-and-codebase -->

This document explains structure and decision-relevant hotspots. It does not reproduce the file tree — a reader who wants the tree can run `ls`, and a pasted tree is stale on the next commit.

## Repository and module map

| Repository | Purpose | Language / runtime | Build system | Owner | Criticality | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

| Module or package | Repository | Responsibility | Depends on | Depended on by | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Component catalog

| Component | Purpose | Owner | Language / runtime | Entry point | Interfaces exposed | Dependencies | State owned | Deployment unit | Criticality | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

## Directory and package conventions

Only conventions a reader must know to place a change correctly.

| Convention | Rule | Enforced by | Consequence of ignoring it | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill — linter \| review \| unenforced} | {fill} | {fill} |

## Lifecycle through the code

The path a unit of work takes from entry to completion, named by the files that handle each stage.

| Stage | Handled by | Input | Output | Errors surfaced how | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

### Trace

{fill — a concrete walkthrough of one request, job, event, or device interaction, from entry point to persisted result, citing files and symbols. This is the trace a new engineer follows on day one and the one a verification pass re-runs against the sources.}

## Extension points and common change paths

| Change a teammate commonly makes | Where to make it | What else must change | Tests to run | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |

## Generated and vendored code

| Path | Kind | Generated or vendored from | Regeneration command | Edited by hand | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — generated \| vendored \| copied} | {fill} | {fill} | {fill — yes \| no} | {fill} |

Hand-edited generated code is a finding: the next regeneration silently discards the edit.

## Configuration model

| Setting | Purpose | Sources in precedence order | Default | Validated where | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

No secret values appear in this table — only the setting name, its purpose, and where it is read from.

## Feature flags and rollout controls

| Flag | Controls | Default | Current state per environment | Owner | Removal condition | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

A flag with no removal condition is technical debt and is cross-referenced in `04-operating/decisions-technical-debt-and-risks.md`.

## Build and artifact production

| Artifact | Produced by | Command | Inputs | Output location | Reproducible | Evidence |
|---|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill — yes \| no \| unknown} | {fill} |

## Legacy, deprecated, experimental, and orphaned areas

| Area | Classification | Still executed | Safe to remove | What blocks removal | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill — legacy \| deprecated \| experimental \| orphaned} | {fill — yes \| no \| unknown} | {fill} | {fill} | {fill} |

"Unknown whether still executed" is a legitimate and common value, and is more useful than a guess.

## Code ownership and bus factor

| Area | Owner | Contributors in inspected history | Bus factor | Consequence | Evidence |
|---|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} | {fill} |

Contributor counts are evidence about the inspected history window, not about who understands the code today. State the window.

## Where to make this change

Concrete task-to-location mappings for the changes this project actually receives.

| Task | Start here | Then | Verify with | Evidence |
|---|---|---|---|---|
| {fill} | {fill} | {fill} | {fill} | {fill} |
