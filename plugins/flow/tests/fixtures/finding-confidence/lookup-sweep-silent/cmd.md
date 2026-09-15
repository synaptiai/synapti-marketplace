# Look-alikes the sweep must not count

The pull request body says `Closes #12`, and issue #212 is mentioned here in prose.

```bash
ISSUE=$("$RESOLVER/bin/flow-pr-linked-issue.sh" --pr "$PR_NUM" --repo "$REPO")
grep -oE '[0-9]+' <<<"$COUNT"
gh issue view "#12"
```
