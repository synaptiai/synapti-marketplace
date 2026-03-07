---
name: code-quality-principles
description: "[flow] Code quality principles for surgical, safe development. Only change what's needed. No secrets in commits. Solution-agnostic thinking. No mocks/stubs/TODOs in production. Parallel quality execution."
allowed-tools: Bash, Read, Grep, Glob
---

# Code Quality Principles

Foundation skill governing code quality standards during autonomous development.

## Surgical Changes

Only modify what the task requires. Measure every edit against: "Does this directly serve the current task?"

- Don't refactor adjacent code while fixing a bug
- Don't add features while addressing review feedback
- Don't update formatting in files you're not changing
- If you notice something worth improving, log it — don't fix it now

## No Secrets in Code

Never commit secrets, credentials, or sensitive values:

- Use environment variables for API keys, tokens, passwords
- Use `.env` files (gitignored) for local development
- Reference secrets by name, never by value
- If you spot a hardcoded secret, flag it as P1 immediately

## Solution-Agnostic Thinking

When crafting issues and acceptance criteria:

- Describe **what** should happen, not **how** to implement it
- Write criteria that can be verified without knowing the implementation
- Avoid prescribing specific libraries, patterns, or architectures in requirements
- The implementation phase decides the "how"

## Production Code Standards

Code that ships must be complete:

- No `TODO` comments in committed code — track in issues instead
- No `console.log` / `puts` / `print` debugging statements
- No mocked or stubbed implementations ("implement later")
- No commented-out code blocks — delete or use version control
- No placeholder error messages ("Something went wrong")

## Quality Command Execution

Run quality checks in parallel when possible:

```
# Good: parallel independent commands
Bash: npm run lint
Bash: npm run test
Bash: npm run typecheck

# Bad: sequential when independent
Bash: npm run lint && npm run test && npm run typecheck
```

After quality checks:
- P1 failures: fix immediately
- P2 failures: fix before PR
- P3 warnings: note and proceed

## First-Touch Awareness

When a file has 0 prior commits on the branch and you're making large additions:

- Flag it as "first touch" in change classification
- Give it extra review attention — new files have no established patterns
- Ensure it follows the project's conventions (naming, structure, style)

## Atomic Commits

Each commit should be a complete, valuable change:

- Can you describe it without saying "WIP" or "partial"?
- Does it leave the codebase in a working state?
- Would reverting it cleanly undo one logical change?

If yes to all three, commit. Otherwise, keep working.

## Self-Review Checklist

Before marking any task complete:

1. `git diff` — only intended changes present?
2. No debug code or temporary files?
3. New code follows existing patterns in the project?
4. Edge cases considered (null, empty, boundary values)?
5. Error messages are helpful and specific?
