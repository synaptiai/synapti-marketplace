# Decision Journal — Issue #90

**Title**: feat(journal): add tier tagging to auto-log hooks (prerequisite for Tier Summary)
**Branch**: feature/issue-90-journal-tier-tagging
**Started**: 2026-05-06

## Specification

### Non-goals
- Don't change journal-file naming or directory configuration logic.
- Don't modify the three blocking hooks (block-force-push, block-destructive, block-secrets).
- Don't break the existing chore-commit guard or journal-only guard in log-commits.sh.
- Don't add tier tagging for tools outside the explicit T2/T3 list (push, PR create, issue assign, merge, release).
- Don't change the journal entry naming convention (`issue-N.md` or `session-YYYY-MM-DD.md`).

### Failure modes
- **jq unavailable** → graceful exit 0 (existing pattern in log-* hooks).
- **Journal file missing** → skip silently (existing pattern).
- **Detached HEAD or no branch** → fall back to `session-{date}.md` (existing pattern).
- **Mixed-tier command** (e.g. `git push && gh pr create`) → tag the first detected match. Document this as a known limitation.
- **False positives on non-targeted gh commands** (e.g. `gh pr view`, `gh pr list`, `gh release list`) → regex must specifically match `create`/`merge` actions, not arbitrary substrings.
- **New hook fires on its own journal write** → hook is PostToolUse Bash; it only matches command-execution events, not file writes. Self-recursion not possible.

### Interface contracts
- **Journal entry format (new)**: `<!-- auto-log: YYYY-MM-DD HH:MM T{1,2,3} {action} {target} -->`
- **Backwards-compat format (old)**: `<!-- auto-log: YYYY-MM-DD HH:MM {action} {target} -->` — downstream consumers must accept both; un-tagged entries default to T1.
- **hooks.json schema**: unchanged (existing JSON shape, new entry under PostToolUse Bash matcher).
- **Hook input contract**: stdin JSON with `tool_name` and `tool_input.command`/`tool_input.file_path` — same as existing hooks.

## Spec Validation Gate

| # | Acceptance Criterion | Verification Command | Gate Status |
|---|---|---|---|
| 1 | log-file-changes.sh emits T1 tag | `echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x"}}' \| bash plugins/flow/hooks/scripts/log-file-changes.sh && grep "T1 Edit" .decisions/*.md` | PASS |
| 2 | log-commits.sh emits T1 tag | `echo '{"tool_input":{"command":"git commit -m test"}}' \| bash plugins/flow/hooks/scripts/log-commits.sh && grep "T1 commit" .decisions/*.md` | PASS |
| 3 | New hook captures T2 events | `echo '{"tool_input":{"command":"git push origin x"}}' \| bash plugins/flow/hooks/scripts/log-tier-events.sh && grep "T2 push" .decisions/*.md` | PASS |
| 4 | New hook captures T3 events | `echo '{"tool_input":{"command":"gh pr merge 88 --squash"}}' \| bash plugins/flow/hooks/scripts/log-tier-events.sh && grep "T3 merge" .decisions/*.md` | PASS |
| 5 | autonomous-workflow/SKILL.md documents tier tag convention | `grep -A2 "tier tag" plugins/flow/skills/autonomous-workflow/SKILL.md` returns the convention section | PASS |
| 6 | Backwards-compat: old format still parses | `grep -E "auto-log: [0-9-]+ [0-9:]+ (T[123] )?(Edit\|Write\|commit\|push\|create\|merge\|release\|assign)" .decisions/*.md \| wc -l` matches every auto-log line | PASS |
| 7 | Idempotency: chore-guard intact, no log loops | `git diff plugins/flow/hooks/scripts/log-commits.sh` shows the chore-commit and journal-only guards unchanged | PASS |
| 8 | hooks.json registers new hook | `jq '.hooks.PostToolUse[] \| select(.matcher == "Bash") \| .hooks[] \| .command' plugins/flow/hooks/hooks.json` includes log-tier-events.sh | PASS |

All ACs PASS.

## Stranger Test

A zero-context agent could execute the plan: 2 file edits with explicit before/after content, 1 new file with explicit content, 1 hooks.json edit (add entry), 1 markdown doc-section addition. Each verification command is shell-runnable. **PASS**.

## Atomic tasks

Three atomic tasks, in dependency-free order:

1. **T1 tagging** — modify `log-file-changes.sh` and `log-commits.sh` to emit `T1` between timestamp and action. Verify with sample stdin.
2. **T2/T3 capture** — create `log-tier-events.sh` (new PostToolUse Bash hook) + register in `hooks.json`. Verify with sample stdin per command type.
3. **Convention doc** — add tier-tag convention section to `autonomous-workflow/SKILL.md`. Verify by grep.

Tasks are independent (no shared file beyond hooks.json which is touched only by task 2). Could be done in parallel commits, but I'll do them as a single coherent commit since the system makes sense as a whole.

<!-- auto-log: 2026-05-06 00:39 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-90.md -->

<!-- auto-log: 2026-05-06 00:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/log-file-changes.sh -->

<!-- auto-log: 2026-05-06 00:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/log-commits.sh -->

<!-- auto-log: 2026-05-06 00:40 Write /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/log-tier-events.sh -->

<!-- auto-log: 2026-05-06 00:40 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/hooks.json -->

<!-- auto-log: 2026-05-06 00:41 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/autonomous-workflow/SKILL.md -->

<!-- auto-log: 2026-05-06 00:41 T1 Edit /tmp/ac1-test -->

<!-- auto-log: 2026-05-06 00:41 T1 commit "fix(verdict-judge): tighten tool budget to Read-only (#89)" -->

<!-- auto-log: 2026-05-06 00:41 T2 push -->

<!-- auto-log: 2026-05-06 00:41 T2 pr-create -->

<!-- auto-log: 2026-05-06 00:41 T2 issue-assign -->

<!-- auto-log: 2026-05-06 00:41 T3 merge -->

<!-- auto-log: 2026-05-06 00:41 T3 release -->

<!-- auto-log: 2026-05-06 00:41 commit "fix(verdict-judge): tighten tool budget to Read-only (#89)" -->

<!-- auto-log: 2026-05-06 00:41 T3 merge -->

<!-- auto-log: 2026-05-06 00:42 commit "feat(journal): add tier tagging to auto-log hooks" -->

<!-- auto-log: 2026-05-06 00:43 commit "feat(journal): add tier tagging to auto-log hooks" -->

<!-- auto-log: 2026-05-06 00:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/log-tier-events.sh -->

<!-- auto-log: 2026-05-06 00:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/log-commits.sh -->

<!-- auto-log: 2026-05-06 00:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/skills/autonomous-workflow/SKILL.md -->

<!-- auto-log: 2026-05-06 00:46 T1 commit "feat(journal): add tier tagging to auto-log hooks" -->

<!-- auto-log: 2026-05-06 00:46 T3 merge -->

<!-- auto-log: 2026-05-06 00:46 T2 push -->

<!-- auto-log: 2026-05-06 00:46 commit "feat(journal): add tier tagging to auto-log hooks" -->
