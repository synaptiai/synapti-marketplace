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

## Target

```!
"${CLAUDE_PLUGIN_ROOT}/bin/snap-target.sh" <<'THANOS_ARGUMENTS'
$ARGUMENTS
THANOS_ARGUMENTS
```

## Steps

1. If the block above printed `THANOS_TARGET=none`, reply with the
   `THANOS_NOTHING` text as a single line and stop. Do not invoke the
   subagent.
2. Otherwise invoke the `thanos` subagent with the Agent tool. Pass this
   prompt, filled in from the block's output:

   ```
   REVIEW MODE.
   Target: <THANOS_WHAT>
   Kind: <code diff | design document | code files as they stand>
   Read it with: <THANOS_READ> (a git command to run, or a path to read)
   Untracked files that are part of the change: <THANOS_UNTRACKED lines, or none>
   Review it with the thanos-doctrine method and return the review in its output format.
   ```

   Use "design document" for `THANOS_TARGET=design`, which also applies
   the doctrine's design-document questions.
3. Show the subagent's review to the user exactly as returned: no
   preface, summary, or commentary before or after it.

Do not edit files, apply suggestions, or start fixing anything the
review raises.
