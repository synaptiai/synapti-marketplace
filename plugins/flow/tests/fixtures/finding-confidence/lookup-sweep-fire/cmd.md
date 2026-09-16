# Planted retired lookups

Every line below parses an issue number out of pull request text; the sweep must count each,
in whichever quoting a re-introduction happens to use.

```bash
LINKED=$(gh pr view "$PR_NUM" --repo "$REPO" --json body --jq '.body' 2>/dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#')
ISSUE=$(printf '%s\n' "$PR_BODY" | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]+' | head -1 | grep -oE '[0-9]+')
ISSUE=$(printf '%s\n' "$PR_BODY" | grep -oE "#[0-9]+" | head -1 | tr -d '#')
ISSUE=$(printf '%s\n' "$PR_BODY" | sed -n 's/.*[Cc]loses #\([0-9][0-9]*\).*/\1/p' | head -1)
```
