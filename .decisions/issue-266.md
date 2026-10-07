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

Decisions (user, 2026-10-01, epic #258): a repository's settings may only lower a site's mode (applied by `bin/flow-s1-mode.sh`, which the client and this command both use); every call passes `--ref`; in `on` mode an "already addressed" answer puts the finding id in the resolution marker's RESOLVED list, with the evidence shown (path, lines, commit checked, confidence); security comments are eligible like any other comment.

Corrections to the accepted spec, made against the code at 85b63bc4:
- The comment is read with `gh api repos/<repo>/pulls/comments/<id>` (one comment), not the list endpoint, which returns 30 comments a page and would miss later ones. The block checks that the returned `id` equals `COMMENT_ID` and that `path` is set.
- The still-applies step runs after the FlowRun is created, not at the place of today's Explore instruction: the run directory `.flow/runs/<RUN_ID>/` exists only after `Skill(run-state-management)` creates it, and records and the saved state file go there only when it exists. With the site off, the Explore instruction is where it was and reads as before.
- A `!` probe, `bin/flow-s1-mode.sh <site>`, prints the site's mode only when a provider is set and the mode is `shadow` or `on`. The mode is the lower of the user's (user settings or plugin default) and the full cascade's (on > shadow > off), so a repository can lower the user's mode and never raise it. The client takes its mode from the same script; when the checked-out head lowers the mode between the probe and the block, the client's answer wins and Flow falls back to Explore.
- The probe finds `flow-s1-mode.sh` with the post-checkout form inside `USER_FILES` markers, because it reads the user settings: a copy inside the repository is never used, and with no install outside it the probe prints nothing. The block resolves the plugin with the post-checkout form, which never uses a copy inside the repository, so run directly it reports `skipped REASON=plugin-missing`, not `settings-refused`.
- `--ref` is `pr:<PR_NUM>/inline:<COMMENT_ID>`, built by the block.

### Non-goals
- Does not change how comments are categorized (#267).
- Does not change the client's request, normalization, threshold or record format.
- Does not ask about review summaries or issue-level comments; only inline comments with a path.
- Does not run System One for a comment whose file is missing, a symlink, outside the repository, not in HEAD or changed since HEAD, or whose location cannot be found; those go to Explore.
- Posts nothing new to GitHub in off or shadow mode, and adds no GitHub call in off mode.
- Does not switch the site on by default; that needs the written shadow comparison.
- Does not replace Phase 3 context recovery for comments that apply.
- Python 3.12 to 3.14 only. No keyword or regex pre-filter.

### Failure modes
- Timeout, connection, redirect, HTTP error, malformed reply, abstention, missing answer, below threshold: `flow-s1.sh` exits 3; the block prints `STILL_APPLIES_STATE=no-answer REASON=<reason>` and Explore runs for that comment. Cost: at most one `timeoutMs` per comment, one after another, only in shadow or on mode.
- Partial failure across comments: each comment is its own call.
- Comment with `line: null` (outdated): the location is the one line of the current file equal to the last non-removed, non-blank line of `diff_hunk`. When that line is nowhere in the file (a fix changed the commented lines), the comment is still asked about: the location is its `original_line` (the last line when the file is now shorter), and the state says `original_lines_present: false` (user, 2026-10-07). Several matches, a hunk with no such line, no `original_line`, or an empty file give `skipped REASON=location-not-found`, no request.
- File deleted, renamed, a symlink, not a regular file, or a path with `..` or a leading `/`: `skipped REASON=file-missing`, no request. A deleted file is never reported as addressed.
- File not in HEAD, or with changes that are not committed: the code read would not be the code at the commit `CHECKED` names, so `skipped REASON=uncommitted`, no request.
- gh failure, empty repository name, or a reply for another id or another pull request: `skipped REASON=gh-unavailable` or `comment-not-found`, exit 0.
- Comment on a removed line (`side` LEFT, whose `line` counts lines of the base file): `skipped REASON=removed-line`, no request. Comment on the whole file (`subject_type` file): `skipped REASON=file-comment`, no request. A reply in a thread (`in_reply_to_id` set): `skipped REASON=reply`, no request.
- A value from a comment in a reply: `CHECKED` starts with the comment's path, which the pull request author chose. Replies and the resolution body are written to a file from `mktemp` with the Write tool; a reply is posted from the file by `INLINE_REPLY_BLOCK` (`gh api -F body=@<file>`). Neither is placed in a double-quoted shell string or in a here-document: reviewer text can hold a line equal to the delimiter, which would end the here-document and run the lines after it as shell.
- Hostile comment text: read with jq into the state file only, never into shell code or a jq program.
- State over the provider limit: the client shortens it; the block prints `TRUNCATED=1`.
- No RUN_ID or no run directory: records go to the per-user state directory; the state file is a temporary file, removed afterwards.
- Plugin inside the repository: the probe skips that copy, and with no other install prints nothing.
- python3 or PyYAML missing: `no-answer REASON=python-missing`.
- Probe and block disagree (the checked-out head lowers the mode): the block's output follows the client; `on` prose falls back to Explore on anything but `answered`.

### Interface contracts
- `bin/flow-s1-mode.sh <site>`: prints `shadow` or `on` on one line when the provider (user tier or plugin default) is `typesafe`, `imajev` or `custom` and the site's effective mode is `shadow` or `on`; prints nothing otherwise, including when cascade-resolve refuses. Exit 0; exit 2 on a malformed site id. Sends nothing.
- `S1_STILL_APPLIES_MODE_BLOCK` (in a `!` fence): prints `S1_STILL_APPLIES=shadow` or `S1_STILL_APPLIES=on`, or nothing.
- `STILL_APPLIES_BLOCK` input (environment): `PR_NUM` (positive integer, no leading zero), `COMMENT_ID` (digits, no leading zero), `RUN_ID` (optional; the shape `flow-s1.sh --run-id` takes), `CURRENT` (optional; `applies` or `addressed`). A bad value: `STATE=blocked`, `ERROR=<reason>`, exit 2, no request.
- `STILL_APPLIES_BLOCK` output: `COMMENT_ID=<id>`, `STILL_APPLIES_STATE=answered|no-answer|skipped`; when answered `STILL_APPLIES=applies|addressed`, `P=`, `CONFIDENCE=`, `MODEL=`, `CHECKED=<path>:<start>-<end>@<short sha>`, `TRUNCATED=0|1`; otherwise `REASON=<reason>`. Exit 0 in all three states. The client's stderr passes through.
- State sent: `{"comment":{"body","path","line","original_line","diff_hunk","outdated"},"code_now":{"path","head","start","end","text","original_lines_present"}}`; window at most 40 lines either side; `original_lines_present` is false when the commented lines are gone and the window is around the original line number; the reviewer's login is not sent.
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
| Location recovery | outdated comment checked at the top of the file | line null, anchor moved 50 lines down: state window holds the anchor with the right start and end; anchor absent and no original line: skipped, 0 requests |
| Commented lines replaced by a fix | the comment is skipped, so a real fix is never recognised; or it is asked without its diff hunk, at the wrong place, without saying the lines are gone, or for a deleted file | line null, anchor absent, original line 10: one request, diff hunk byte for byte, window 1-50, `original_lines_present` false; original line 200 of 120: window 80-120; file deleted by a later commit: `file-missing`, 0 requests; hostile diff hunk sent byte for byte, no file created |
| Wrong place checked | a removed-line, whole-file, reply or other-PR comment is checked against an unrelated window | side LEFT, subject_type file, in_reply_to_id set, pull_request_url of PR 8: each skipped with its reason, 0 requests |
| Path run as shell in the reply | `CHECKED` with `src/$(touch pwned).py` placed in `-f body="..."` | reply written to a file and posted by `INLINE_REPLY_BLOCK`: gh receives the text byte for byte, no file created |
| Injection and data leaving | body run as code; a symlinked path sends a file outside the repository | body with `$(touch pwned)`, quote, newline, U+2028 sent byte for byte, no file created; symlinked path: skipped, 0 requests |

## Shadow comparison

- 2026-10-07. Written from the replay records only, as the user decided on 2026-10-07 for every site of epic #258: 14 records sent to TypeSafe jev-1.13.0 on 2026-10-07 (refs `replay:pr-inline:*`), joined by ref to labels set from the pull-request history before any answer was read. No live records, no Explore verdicts.
- Result: every one of the 14 comments asked about is labelled still present, and all 9 addressed comments in the history were skipped before a request (8 outdated after the fix changed their lines, 1 whole-file). The spec's rule (lowest threshold with no wrong "addressed" answer) needs addressed comments among those asked, so it cannot be applied. The threshold stays 0.9, provisional; questions.yaml is unchanged; the site stays off. The 4 answers leaning "addressed" are all wrong and all at confidence 0.30 or below.
- The comparison is in references/system-one.md under `address.still_applies`; per-item data in evals/results-2026-10-07-address-s1/address-still-applies.jsonl.
