---
name: feedback-resolution
description: "Address PR review feedback through surgical fixes traceable to specific comments, apply the Boy Scout Rule only to already-modified files (separate `improve:` commits), recover context by code snippet rather than line number, and enforce pushback only when factually incorrect, test-breaking, or CLAUDE.md-violating. Use when resolving reviewer comments on a pull request. This skill MUST be consulted because every untraceable change is out-of-context, and pushback without evidence is just disagreement."
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
context: fork
agent: general-purpose
---

# Feedback Resolution

## Contract

Iron law: **every change traces to a specific review comment or passes the Boy Scout proximity test; anything else is out-of-context and does not belong in this round.** Invoked by `/flow:address` Phase 1 (collect and categorize feedback) through Phase 4 (verify, post the resolution comment, re-request review). Returns one commit per feedback item (`fix(scope): address review — {summary}`), separate `improve:` commits for Boy Scout fixes, a response for every Question or Pushback item, and the resolution comment from `templates/resolution-comment.md` posted before review is re-requested. Permitted skips: none — pushback replaces a fix only with `file:line` evidence, a named breaking test, or a quoted CLAUDE.md rule.

## Collect

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-pr-feedback.sh" "${PR_NUM:?pass the PR number from the invoking command}"
```

## Categorize

- **P1 — Must fix**: code bug, security issue, logic error
- **P2 — Should fix**: convention violation, missing test, unclear code
- **P3 — Consider**: style preference, optimization suggestion
- **Question**: needs a response, not necessarily a code change
- **Resolved**: already fixed or no longer relevant

System One may raise a category, never lower it (`references/feedback-resolution.md`).

## Fix Each Item (one task per item)

1. Locate the code by the comment's quoted snippet and path (`grep -n "quoted_code" $FILE`), never its line number, and read the current file.
2. A fix to documentation, comments, or configuration with no behavior change is exempt from a new test: go to step 4.
3. For a behavior-changing fix, follow `testing.tddMode` as `/flow:start` does (`tdd-patterns`): `enforce` (default): first write a test that reproduces the defect and fails on the current code for the intended reason, with a sourced expected value and an input on which the fixed and unfixed code differ; `suggest` (only with `tddModeOptOut: true`): the same unless the user skips it; `off`: write the test after the fix. Follow existing test patterns, test the specific edge case, and touch only the fix target and its test file.
4. Implement the minimal fix to the literal comment that makes the reproducing test pass. If intent is unclear, check follow-up comments and codebase patterns, take the most conservative reading, and state it in the response.
5. Verify the fix addresses that comment and tests pass.
6. One commit per item (format in the Contract), never batched.

No new features; no formatting changes in files the feedback did not mention.

## Boy Scout Rule

Cleanup is allowed only in files already modified for feedback and only if it passes the `code-quality-principles` proximity test. Boy Scout fixes get separate `improve:` commits, never mixed with feedback fixes. Findings outside the feedback: `references/feedback-resolution.md`.

## Pushback

Valid only when one of these holds, with the evidence in the response:

- **Factually incorrect** — cite `file:line` showing the current state and why the feedback does not apply.
- **Would break existing tests** — name the test and its `file:line`.
- **Contradicts CLAUDE.md** — quote the rule and its location.

"I disagree" is not pushback; preferences resolve in the reviewer's favor. Never ignore feedback silently. Beyond these three grounds, a product or architecture judgment is a six-field escalation; finding triage never is (`references/feedback-resolution.md`).

## Verify and Re-Request

Before re-requesting: all quality commands pass; every item has a commit or response; change-classification shows no out-of-context files; push (Tier 2). Then, as one atomic sequence: post the resolution comment (`gh pr comment $PR_NUM --body "$BODY"`, structure from `templates/resolution-comment.md`) and re-request (`gh pr edit $PR_NUM --add-reviewer @{reviewer}`).
