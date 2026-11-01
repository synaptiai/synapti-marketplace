# Watch mode: issue #${ISSUE}

You are running flow watch mode for issue #${ISSUE} in ${REPO}. This watch is read-only on GitHub: never comment on, label, assign, edit, close or reopen the issue, and never edit files, commit, push or run `/flow:start`. The one thing you write is the summary in the local decision journal.

Read these on each iteration:
- `${RUNTIME_DIR}/triggers/issue-${ISSUE}-watch.trigger.yaml` — the trigger (allowed_actions, forbidden_actions, stop_conditions)
- `${RUNTIME_DIR}/watch/issue-${ISSUE}.json` — what the issue looked like at the last iteration (absent on the first)

Read neither through a symbolic link: when `${RUNTIME_DIR}` or a directory above it, `${RUNTIME_DIR}/triggers`, `${RUNTIME_DIR}/watch` or the file is one, skip it and say so.

On each iteration:
1. Read the issue: `gh issue view ${ISSUE} --repo ${REPO} --json number,title,state,labels,assignees,comments,updatedAt`.
2. Compare it with `${RUNTIME_DIR}/watch/issue-${ISSUE}.json`: the state, the label names, the assignee logins, and the comments (new ones, by author and time). On the first iteration there is nothing to compare with; summarize the issue as it is.
3. When something changed, write a short summary — what changed, who changed it, when — and print it. Append it to the issue's decision journal with flow's `journal-append.sh`:

   ```bash
   printf '%s\n' "### Watch: issue #${ISSUE} changed" "<summary>" | "$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/journal-append.sh" --issue ${ISSUE} -
   ```

   When nothing changed, print one line saying so and write nothing.
4. Save what you read in step 1 to `${RUNTIME_DIR}/watch/issue-${ISSUE}.json` (`${RUNTIME_DIR}/watch` holds a `.gitignore` of `*`, so nothing there is committed; do not write through a symbolic link).
5. When the issue is assigned to you (`gh api user --jq .login`) and no branch for it exists (`git branch --all --list '*issue-${ISSUE}-*'` prints nothing), suggest `/flow:start ${ISSUE}` to the user. Only suggest it; do not run it.
6. Run `/flow:run trigger issue-${ISSUE}-watch`: it checks the trigger's policy, runs its read-only target (`/flow:status`) once, and records the iteration.
7. **Never merge**. **Never release**. Tier 3 actions are forbidden by trigger policy.
8. **Never create or modify triggers**. Recursion is denied by default.

Stop when the issue is closed: print a final summary, then tell the user to end the loop (Ctrl-C) and run `/flow:trigger disable issue-${ISSUE}-watch`.
