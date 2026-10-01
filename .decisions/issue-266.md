---
issue: 266
created: '2026-10-01T15:37:42Z'
artifacts:
- type: specification
  captured_at: '2026-10-01T15:37:42Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

System One decision point `address.still_applies`: in `/flow:address`, each inline review comment is checked against the current code at the place it refers to. Ships `off`.

Decisions (user, 2026-10-01, epic #258): a repository's settings may only lower a site's mode (enforced by `flow-s1.sh` since #278); every call passes `--ref`; in `on` mode an "already addressed" answer puts the finding id in the resolution marker's RESOLVED list, with the evidence shown (path, lines, commit checked, confidence); security comments are eligible like any other comment.

Corrections to the accepted spec, made against the code at 85b63bc4:
- The comment is read with `gh api repos/<repo>/pulls/comments/<id>` (one comment), not the list endpoint, which returns 30 comments a page and would miss later ones. The block checks that the returned `id` equals `COMMENT_ID` and that `path` is set.
- The still-applies step runs after the FlowRun is created, not at the place of today's Explore instruction: the run directory `.flow/runs/<RUN_ID>/` exists only after `Skill(run-state-management)` creates it, and records and the saved state file go there only when it exists. With the site off, the Explore instruction is where it was and reads as before.
- A `!` probe, `bin/flow-s1-mode.sh <site>`, prints the site's mode only when a provider is set and the mode is `shadow` or `on`; the probe follows the same repository rule as `flow-s1.sh` (a repository's `on` does not count). The client still enforces the rule: when the probe and the client disagree, the client's answer wins and Flow falls back to Explore.
- With the plugin inside the repository, the probe prints nothing (cascade-resolve refuses). The block resolves the plugin with the post-checkout form, which never uses a copy inside the repository, so run directly it reports `skipped REASON=plugin-missing`, not `settings-refused`.
- `--ref` is `pr:<PR_NUM>/inline:<COMMENT_ID>`, built by the block.

### Non-goals
- Does not change how comments are categorized (#267).
- Does not change the client's request, normalization, threshold or record format.
- Does not ask about review summaries or issue-level comments; only inline comments with a path.
- Does not run System One for a comment whose file is missing, a symlink, outside the repository, or whose location cannot be found; those go to Explore.
- Posts nothing new to GitHub in off or shadow mode, and adds no GitHub call in off mode.
- Does not switch the site on by default; that needs the written shadow comparison.
- Does not replace Phase 3 context recovery for comments that apply.
- Python 3.12 to 3.14 only. No keyword or regex pre-filter.

### Failure modes
- Timeout, connection, redirect, HTTP error, malformed reply, abstention, missing answer, below threshold: `flow-s1.sh` exits 3; the block prints `STILL_APPLIES_STATE=no-answer REASON=<reason>` and Explore runs for that comment. Cost: at most one `timeoutMs` per comment, one after another, only in shadow or on mode.
- Partial failure across comments: each comment is its own call.
- Comment with `line: null` (outdated): the location is the one line of the current file equal to the last non-removed, non-blank line of `diff_hunk`; none or several matches give `skipped REASON=location-not-found`, no request.
- File deleted, renamed, a symlink, not a regular file, or a path with `..` or a leading `/`: `skipped REASON=file-missing`, no request. A deleted file is never reported as addressed.
- gh failure, empty repository name, or a reply for another id or another pull request: `skipped REASON=gh-unavailable` or `comment-not-found`, exit 0.
- Comment on a removed line (`side` LEFT, whose `line` counts lines of the base file): `skipped REASON=removed-line`, no request. Comment on the whole file (`subject_type` file): `skipped REASON=file-comment`, no request. A reply in a thread (`in_reply_to_id` set): `skipped REASON=reply`, no request.
- A value from a comment in a reply: `CHECKED` starts with the comment's path, which the pull request author chose. Replies and the resolution body are written to a file with a quoted here-document and posted from the file (`INLINE_REPLY_BLOCK`, `gh api -F body=@<file>`), never placed in a double-quoted shell string.
- Hostile comment text: read with jq into the state file only, never into shell code or a jq program.
- State over the provider limit: the client shortens it; the block prints `TRUNCATED=1`.
- No RUN_ID or no run directory: records go to the per-user state directory; the state file is a temporary file, removed afterwards.
- Plugin inside the repository: the probe prints nothing.
- python3 or PyYAML missing: `no-answer REASON=python-missing`.
- Probe and block disagree (the checked-out head lowers the mode): the block's output follows the client; `on` prose falls back to Explore on anything but `answered`.

### Interface contracts
- `bin/flow-s1-mode.sh <site>`: prints `shadow` or `on` on one line when the provider (user tier or plugin default) is `typesafe`, `imajev` or `custom` and the site's effective mode is `shadow` or `on`; prints nothing otherwise, including when cascade-resolve refuses. Exit 0; exit 2 on a malformed site id. Sends nothing.
- `S1_STILL_APPLIES_MODE_BLOCK` (in a `!` fence): prints `S1_STILL_APPLIES=shadow` or `S1_STILL_APPLIES=on`, or nothing.
- `STILL_APPLIES_BLOCK` input (environment): `PR_NUM` (positive integer, no leading zero), `COMMENT_ID` (digits, no leading zero), `RUN_ID` (optional; the shape `flow-s1.sh --run-id` takes), `CURRENT` (optional; `applies` or `addressed`). A bad value: `STATE=blocked`, `ERROR=<reason>`, exit 2, no request.
- `STILL_APPLIES_BLOCK` output: `COMMENT_ID=<id>`, `STILL_APPLIES_STATE=answered|no-answer|skipped`; when answered `STILL_APPLIES=applies|addressed`, `P=`, `CONFIDENCE=`, `MODEL=`, `CHECKED=<path>:<start>-<end>@<short sha>`, `TRUNCATED=0|1`; otherwise `REASON=<reason>`. Exit 0 in all three states. The client's stderr passes through.
- State sent: `{"comment":{"body","path","line","original_line","diff_hunk","outdated"},"code_now":{"path","head","start","end","text"}}`; window at most 40 lines either side; the reviewer's login is not sent.
- State file kept at `.flow/runs/<RUN_ID>/system-one-state/<COMMENT_ID>.json` when that run directory exists (no symlink on the way) and a request was sent; otherwise a temporary file, removed.
- Records: `site=address.still_applies`, `question=concern_present`, `current` (`applies`/`addressed` in shadow), `ref=pr:<PR>/inline:<id>`.
- `on` mode: `addressed` gets no Explore and no fix task, and appears in the inline reply, the Thread Status table and the summary with `CHECKED` and the confidence; its finding id, when it has one, goes in RESOLVED. `applies` enters Phase 2 like an Explore "applies".
- Probe silent: Explore instruction, resolution comment and summary unchanged; the block is not run.
- Questions and threshold live only in `system-one/questions.yaml`; threshold `0.9` is provisional.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Direction of the noul | p >= 0.5 read as addressed | on, p=0.03 prints `addressed`; on, p=0.97 prints `applies`; mutant swapping the comparison fails both |
| Repository raising the mode | head's settings set `on` and comments are skipped | user `shadow`, repo `on`, p=0.03: no `STILL_APPLIES=` line, probe prints `shadow`, record mode `shadow` |
| Shadow changes behaviour | shadow output read as an answer, or `current` not recorded | shadow, CURRENT=applies, p=0.03: `REASON=shadow`, no `STILL_APPLIES=` line, record `current=applies`, `answer.p=0.03` |
| Off is not identical | probe prints `off`, or the stub is reached | off, provider none, plugin in repository: probe empty, 0 requests, no records |
| Location recovery | outdated comment checked at the top of the file | line null, anchor moved 50 lines down: state window holds the anchor with the right start and end; anchor absent: skipped, 0 requests |
| Wrong place checked | a removed-line, whole-file, reply or other-PR comment is checked against an unrelated window | side LEFT, subject_type file, in_reply_to_id set, pull_request_url of PR 8: each skipped with its reason, 0 requests |
| Path run as shell in the reply | `CHECKED` with `src/$(touch pwned).py` placed in `-f body="..."` | reply written to a file and posted by `INLINE_REPLY_BLOCK`: gh receives the text byte for byte, no file created |
| Injection and data leaving | body run as code; a symlinked path sends a file outside the repository | body with `$(touch pwned)`, quote, newline, U+2028 sent byte for byte, no file created; symlinked path: skipped, 0 requests |
