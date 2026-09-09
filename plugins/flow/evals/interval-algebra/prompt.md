---
name: interval-algebra
tags: [correctness, seeded-bugs, python]
runs: 3
max_turns: 60
timeout_seconds: 1800
allowed_tools: [Bash, Read, Write, Edit, Glob, Grep, Skill, Agent, TodoWrite, TaskCreate, TaskList, TaskUpdate, TaskGet]
---
Implement the feature described in `ISSUE.md` in the current directory. The directory is a fresh git repository containing `ISSUE.md`, the skeleton module named there, and an empty `tests/` package.

<!-- flow-only -->
The flow plugin is installed and configured through `.claude/settings.flow.json`. Before writing any production code, load and follow the flow plugin's `specification-capture` skill (journal path `.decisions/issue-1.md`, invocation reason `start`, issue context = the contents of `ISSUE.md`) and then its `tdd-patterns` skill, honouring `testing.tddMode` and `specFirst.riskMap` exactly as configured. This session is non-interactive: where a skill would ask a question, take its recommended option and note that in the journal.
<!-- /flow-only -->

Write your own tests under `tests/` in the file named in `ISSUE.md`, using only the standard-library `unittest` module; no third-party packages are available. Work autonomously and do not ask questions. Stop when your own tests and every acceptance-criteria verification command in `ISSUE.md` pass, and end your final message with the exact phrase: IMPLEMENTATION COMPLETE
