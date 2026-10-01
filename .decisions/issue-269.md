# Decision Journal — Issue #269

**Title**: feat(flow): a quality run that executed zero tests or skipped every test is not recorded as passing
**Epic**: #258
**Branch**: feature/issue-269-quality-run-s1
**Created**: 2026-10-01

## Summary

After a Bash call that Flow already records as a passing built-in test run, `hooks/scripts/record-quality-run.sh` can ask System One (site `quality.tests-ran`) whether the output shows at least one test actually executing. With the site `on`, a confident `none_ran` or `all_skipped` answer records the run as not passing, with that reason, and the task-completion gate names it. The site ships `off`. Off, no provider, or no answer: the ledger entry and the gate behave exactly as before, and Bash calls that are not passing built-in test runs start no process and make no request.

## Specification

### Non-goals

- Recognizing runners missing from the built-in list (`uv run pytest`, `./gradlew test`, `tox`). System One may only add caution, so it cannot create passing records; extending the list is a deterministic pattern change for another issue.
- Judging lint, typecheck, build, or the `project` kinds (the built-in `verify.sh`/`check.sh` pattern and `testing.qualityCommandPatterns`). Only `kind=test` from the built-in list is asked.
- Upgrading anything. A PostToolUseFailure payload, a non-zero or null exit code (as derived below), a masked command or an interrupted call never reaches the ask.
- Telling Claude at PostToolUse time. The hook still always exits 0 with empty stdout; the reason reaches Claude through the TaskCompleted gate message.
- Changing the gate beyond reading the new field: dirty/clean rules, digest, and block/warn/off are unchanged.
- Storing test output anywhere new. The client records only the state's sha256; the ledger keeps the command's first 200 characters, as before.
- A deterministic keyword or regex reading of the output, as fallback or replacement.
- Python older than 3.12.

### Failure modes

| Condition | Behavior |
|---|---|
| Timeout (`timeoutMs`, default 3000, clamped 200-30000) | flow-s1.sh exits 3; the entry is appended unchanged and stays passing. Claude Code's default command-hook timeout is 600 s (code.claude.com/docs/en/hooks, read 2026-10-01), well above 30 s plus overhead, so hooks.json needs no explicit `timeout`. |
| HTTP error, connection failure, redirect, malformed reply, abstention, missing answer, below threshold | exit 3; entry unchanged; the client still writes a record with the reason. |
| Provider none (the default) | The hook's own mode check sees `off` (the plugin default) and starts nothing. With the mode `shadow`/`on` but provider none, flow-s1.sh exits 3 `provider-none` before any request. Entry unchanged apart from `s1_state_sha256`. |
| `settings-refused` (plugin inside the repository) | No answer; the run stays passing. |
| Repository sets `on` where the user did not | The hook mirrors flow-s1.sh: the mode falls back to the user's own (`off` when unset), so nothing starts and no digest is stamped. |
| Missing stdout/stderr in tool_response | Empty lists; still asked. Non-UTF-8 bytes are replaced by jq when the payload is read. |
| mktemp fails, the state cannot be written, or no sha256 tool | The ask is skipped and the entry is appended as before. Every step that can fail is checked with `||`, never inside a `$(...)` whose failure could exit the hook before the append. |
| No jq, no session_id, no ledger helper | Exit 0 before the ask, as before. No python3/PyYAML gives `python-missing`; a missing questions entry gives `unknown-site`; both leave the entry unchanged. |
| Exit 0 with a choice outside {none_ran, all_skipped}, or stdout jq cannot parse | Entry unchanged. A parse failure never downgrades. |
| Record written, ledger append fails | The ledger fails as before (`|| true`); the orphaned record has no ledger line with its sha256 and drops out of the comparison. |
| One tool_use_id fires PostToolUse and PostToolUseFailure | Only the PostToolUse branch asks; the ledger keeps the first append. |
| Hook stopped (SIGINT, SIGTERM, SIGHUP) while the client waits | A trap removes the state file once the client exits, and the hook exits 0 without an entry. SIGKILL cannot be handled and leaves the file. |

### Interface contracts

- **Exit code** (record-quality-run.sh, computed once and used by the pre-filter, the state and the ledger entry): 130 when `tool_response.interrupted` or `is_interrupt` is true; else `tool_response.exit_code` when it is a number; else, on a failure payload, the N of the leading `Exit code N` of `error`/`tool_error`; else, when `hook_event_name == "PostToolUse"` and `tool_response` is an object with none of `backgroundTaskId`, `timedOutAfterMs`, `returnCodeInterpretation`, 0; else null. Claude Code sends no `exit_code` for Bash: the result keys in Claude Code 2.1.283 transcripts (read 2026-10-01) are `interrupted`, `isImage`, `noOutputExpected`, `stdout`, `stderr`, and optionally `backgroundTaskId`, `backgroundCwdHint`, `bashEditDiff`, `gitOperation`, `returnCodeInterpretation`, `timedOutAfterMs`. The user's real ledgers on 2026-10-01 held 9,099 PostToolUse quality runs, all with a null exit code, and 123 PostToolUseFailure runs, 101 of them with the exit code read from `error`. `returnCodeInterpretation` marks a non-zero exit that Claude Code delivered as PostToolUse because it reads it as informational (seen: "No matches found", "Files differ"). These keys come from the transcript's record of the tool result, not from a captured hook payload.
- **Pre-filter** (record-quality-run.sh): ask only when `hook_event_name == "PostToolUse"`, KIND is `test` from the built-in list, the exit code above is 0, MASKED=false, FAILED=false, and the effective mode for `quality.tests-ran` is `shadow` or `on`. The effective mode is resolved the way flow-s1.sh resolves it: `cascade-resolve.sh --default off '.systemOne.uses["quality.tests-ran"]'`, and when that is `on`, the user-tier value (`--no-repo-settings`) unless it is also `on`. Any other value is `off`.
- **State** (JSON, built by the hook with one `jq -c`): `{"command": <first 2000 chars>, "exit_code": <the exit code above, always 0 here>, "output_head": [first 40 stdout lines], "output_tail": [last 200 stdout lines], "stderr_tail": [last 40 stderr lines]}`, each line cut to 400 characters, one trailing newline removed before splitting. Lines, not one string, because the client shortens a too-long state by cutting each string from its end, which keeps every line, including the runner's summary at the end.
- **Client call**: `flow-s1.sh ask --site quality.tests-ran --state-file <mktemp> --state-format json --current pass --ref <ref>`, no `--run-id`, stdout and stderr captured, stderr discarded. The temporary file is removed whatever the exit status, and by a trap if the hook is stopped while the client runs.
- **Ref** (not in the spec; the foundation PR made `--ref` required for every call site): `quality-run:<tool_use_id>` when the tool_use_id matches the client's ref shape (`[A-Za-z0-9][A-Za-z0-9._:/#@+-]*`, at most 200 characters with the prefix); otherwise `quality-run:session:<session_id>` under the same check; otherwise `quality-run:unknown`. A ref the client would refuse would end the call as a usage error with no record, so the hook never passes one.
- **Ledger entry additions**: when the hook called flow-s1.sh: `"s1_state_sha256": "<sha256 of the state file bytes>"` (the same bytes the client hashes). Only when flow-s1.sh exits 0 (which happens only in effective `on` mode) and `answers.outcome.choice` is `none_ran` or `all_skipped`: `"output_check": {"verdict", "site": "quality.tests-ran", "model", "confidence"}`. Otherwise the entry is byte-for-byte the shape it had before.
- **Ledger reader**: `Run.passing` is `exit_code == 0 and not masked and not failed and output_check is None`. `output_check` is read only when it is an object whose `verdict` is one of the two values; anything else is ignored. `status` prints `LAST_RUN_OUTPUT_CHECK=none_ran|all_skipped` when the most recent run carries one.
- **Gate**: a new RUN_TEXT branch after the failed branch: "the last quality run exited 0 but its output showed no tests ran; no passing run this session" (or "... showed every test was skipped ..."). Exit codes and modes are unchanged.
- **Repository control**: since PR #278 a repository's settings can switch the site to `shadow` but not `on`. Shadow sends the output of built-in-recognized test runs to the user's provider; `project` kinds are never asked, so a repository pattern such as `.` cannot widen what is sent.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| State versus client shortening | Output sent as one string, or the head kept: the summary is cut away | 5,000-line output, summary on the last line, trailing newline, `stateTokenCap` 1000: the stub's logged `output_tail` ends with the summary line |
| Pre-filter scope | Asks on lint, on `project` patterns, on masked or failed runs, or before the mode check | Zero-request scenarios: non-test command, `ruff check`, `pytest \|\| true`, interrupted pytest, repository pattern `.` with `uses=shadow`, site off with a provider, repository-only `on` |
| Direction rule | An answer upgrades a failure, or `unclear` / shadow downgrades | Failing payload + stub `executed`: 0 requests, entry failed; shadow + `none_ran`: passing; on + `unclear`: passing |
| Off and no-answer identity | A stray field or a lost entry when off, provider none, timeout, http 500 | Ledger line compared with the line the hook at origin/main (85b63bc4) writes for the same payload, `at`, `s1_state_sha256` and `exit_code` removed; `exit_code` is checked on its own: null from that hook, 0 from this one |
| Exit code from the real payload | The hook waits for a `tool_response.exit_code` Claude Code does not send, so nothing is asked and no run passes; or a background, timed-out or informational non-zero call counts as 0 | Every scenario's payload has the keys Claude Code sends and no `exit_code`; the pre-filter scenario adds `backgroundTaskId`, `timedOutAfterMs` and `returnCodeInterpretation` cases (no request, exit code null); a real-shape run followed by TaskCompleted passes the gate |
| Reader backward compatibility | A malformed `output_check` downgrades or crashes the reader | Hand-written entries with `output_check` a string, an unknown verdict, null: status equals the same ledger without the field |
| Comparison join | `s1_state_sha256` computed over other bytes than the client hashes | Shadow scenario: the entry's `s1_state_sha256` equals the record's `state_sha256` |

### Threshold

`outcome` default 0.9, provisional. It satisfies the stated constraints: only `none_ran`/`all_skipped` at or above it downgrade, it is high because a wrong downgrade blocks a real pass, and it takes effect only when a user switches the site on. No `models:` entry until the shadow comparison measures one for jev-1.13.0.

### Open, to confirm during shadow collection

Whether the hook's `tool_response` has the same keys as the transcript's tool result (the exit-code rule above rests on that): check against a captured hook payload in the collection session.

Claude Code's hooks documentation (read 2026-10-01) does not say whether `tool_response.stdout` for Bash is shortened for long runs. The state takes the tail of what the hook receives; whether that is the runner's real tail is to be checked against a long run's transcript in the collection session.
