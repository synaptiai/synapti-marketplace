---
description: Thanos rethink of a subsystem - the smallest version that delivers its essence, and a safe path from today's structure to it. Read-only; never edits files.
argument-hint: "<path or description of the subsystem>"
allowed-tools: Agent
---

# /rethink

Rethink mode. The subsystem to rethink is the text Claude Code appends
after `ARGUMENTS:` at the end of this command; with no such line, it is
empty.

## Steps

1. If the subsystem is empty, ask the user which subsystem to rethink (a
   path or a short description) and stop. Do not invoke the subagent.
2. Otherwise invoke the `thanos` subagent with the Agent tool and this
   prompt:

   ```
   RETHINK MODE.
   Target: <the subsystem, verbatim>
   Locate it in the repository (it may be a path or a description), read
   it and its callers, then answer with the thanos-doctrine method: the
   smallest version that delivers the essence, designed without regard to
   the current structure, and a stepwise, safe path from the current state
   to that target. Return it in the doctrine's output format.
   ```

3. Show the subagent's review to the user exactly as returned: no
   preface, summary, or commentary before or after it.

Do not edit files, apply suggestions, or start any of the steps the
review proposes.
