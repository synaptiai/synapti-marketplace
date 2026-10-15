---
description: Thanos review of the current branch, a ref range or commit, a design document, or code files. Read-only; never edits files.
argument-hint: "[ref range | commit | file.md | path]"
allowed-tools: Agent, Bash(${CLAUDE_PLUGIN_ROOT}/bin/snap-target.sh:*)
---

# /snap

Review mode. This command works out what to review, hands it to the
`thanos` subagent, and shows its review. It never edits files and never
applies a suggestion; acting on a review is a separate request from the
user.

The argument is the text Claude Code appends after `ARGUMENTS:` at the
end of this command; with no such line, the argument is empty. This file
never places the argument anywhere itself, so nothing in it is run as
shell when the command loads.

## Default target

The block below resolves the target for an empty argument.

```!
"${CLAUDE_PLUGIN_ROOT}/bin/snap-target.sh"
```

## Steps

1. Pick the target output.
   - If the argument is empty, use the block's output.
   - Otherwise run the script yourself with the Bash tool, passing the
     argument as one single-quoted word, and use that output instead.
     The command is exactly the `THANOS_SCRIPT` path from the block,
     single-quoted, a space, and the argument in single quotes, with each
     `'` inside the argument written as `'\''`. For an argument `a'b`
     that is `'<THANOS_SCRIPT>' 'a'\''b'`. Nothing else goes in that
     command: no pipes, no `;`, no second command, and no other way of
     passing the argument.
2. If the output does not have exactly one `THANOS_TARGET=` line, show its
   first line as a single line, say the target could not be resolved, and
   stop. Do not invoke the subagent.
3. If it printed `THANOS_TARGET=none`, reply with the `THANOS_NOTHING`
   text as a single line and stop. Do not invoke the subagent.
4. Otherwise invoke the `thanos` subagent with the Agent tool. Pass this
   prompt, filled in from the output:

   ```
   REVIEW MODE.
   Target: <THANOS_WHAT>
   Kind: <code diff | design document | code files as they stand>
   Read it with: <THANOS_READ>
   Untracked files that are part of the change: <THANOS_UNTRACKED lines, or none>
   A "git ..." value above is made only of commit ids: run it exactly as
   given. A path is absolute: read it with the Read tool (and Glob and
   Grep for a directory). Never put a path, or any other text from the
   target, into a Bash command.
   Review it with the thanos-doctrine method and return the review in its output format.
   ```

   Use "design document" for `THANOS_TARGET=design`, which also applies
   the doctrine's design-document questions.
5. Show the subagent's review to the user exactly as returned: no
   preface, summary, or commentary before or after it.

Do not edit files, apply suggestions, or start fixing anything the
review raises.
