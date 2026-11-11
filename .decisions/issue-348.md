---
issue: 348
created: '2026-11-10T09:48:05Z'
artifacts:
- type: specification
  captured_at: '2026-11-10T09:48:05Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-11-10T09:49:51Z'
  goal_id: issue-348
  source: start
- type: workflow-run
  captured_at: '2026-11-10T09:50:37Z'
  workflow: start-issue
  run_id: 2026-11-10T093925Z-issue-348
  status: active
- type: stranger-test
  captured_at: '2026-11-10T10:28:56Z'
  result: PASS
  task_count: 7
- type: goal-evaluation
  captured_at: '2026-11-10T18:31:45Z'
  goal_id: issue-348
  result: waiting_for_user
  reason: paused-during-verify
- type: escalation-asked
  captured_at: '2026-11-11T01:59:44Z'
  question_id: q-20261111T015943Z-d76c69
  blocking: 'yes'
  class: decision
  command: /flow:start 348 Phase 4 VERIFY
  situation:
  - Five review rounds keep finding new ways a script's printed output can reach a
    shell past the hook's check of where the output goes (a loop or group piped to
    bash after it closes
  - quoting the scanner
- type: escalation-resolved
  captured_at: '2026-11-11T09:18:36Z'
  escalation_field: options
  outcome:
  - Treat a Python
  - node
  - ruby or perl script's text as data wherever its output goes; leave script output
    that reaches a shell to the run-time wrappers
  - as curl | sh already is. Removes the output-tracking code.
  question_id: q-20261111T015943Z-d76c69
- type: escalation-asked
  captured_at: '2026-11-11T13:03:33Z'
  question_id: q-20261111T130332Z-a0e2e1
  blocking: soft
  class: decision
  command: /flow:start 348 Phase 4 step 6 verdict
  situation:
  - 'The verdict judge passes criteria 1 and 3-7 and leaves criterion 2 for review:
    a script behind npx or bundle exec'
  - behind a launcher option (uv run --with x python3)
  - or on a line inside a quote opene
- type: escalation-resolved
  captured_at: '2026-11-11T13:03:50Z'
  escalation_field: options
  outcome: Accept the documented limit as outside the criterion; mark criterion 2
    passed and open the PR.
  question_id: q-20261111T130332Z-a0e2e1
- type: verdict
  captured_at: '2026-11-11T13:04:02Z'
  result: NEEDS-HUMAN-REVIEW
  user_approved: criterion-2
  question: q-20261111T130332Z-a0e2e1
- type: goal-evaluation
  captured_at: '2026-11-11T13:04:17Z'
  goal_id: issue-348
  result: active
  reason: resumed-for-goal-evaluation
- type: goal-evaluation
  captured_at: '2026-11-11T13:06:40Z'
  goal_id: issue-348
  result: fail
  status: active
  failures:
  - AC1
  - AC4
  - AC7
- type: goal-evaluation
  captured_at: '2026-11-11T13:13:30Z'
  goal_id: issue-348
  result: waiting_for_user
  reason: paused-during-full-suite-checks-time-out
---
# Issue #348: fix(flow): the tier checks ask, or refuse, for scripts they cannot read as shell

Branch: fix/issue-348-tier-checks-unreadable-text


## Specification

### Non-goals
- Does NOT change the shared command parser's defaults: block-destructive, block-force-push and block-secrets keep reading interpreter script text exactly as they do now.
- Does NOT change the gh/git run-time wrappers. A merge or release that tier-gate did not ask about is still refused when it actually runs.
- Does NOT change the asks for a plainly written `git push` whose refs, remote or configuration cannot be resolved (tag-push uncertainty in a command flow can read).
- Does NOT change the asks for an infrastructure failure (jq missing, parser missing or failing, a payload that is not JSON).
- Does NOT change block-unchecked-merge's checks on a plainly written merge (required shape, CI checks, named values, gh api merge endpoints).
- Does NOT create GitHub rulesets or change the existing ruleset step in setup.
- Does NOT try to recognise a tag push written as a bare tag name (`git push origin v1`) in the Claude Code ask rules; the hook keeps covering that form.

### Failure modes
- **Input**: a command flow cannot read (a variable or substitution as the program, eval of unreadable text, source of stdin, a gh api call it cannot read, too many or too deeply nested quoted words, a shell reading its script from a pipe) is allowed with no Tier 3 ask; the wrapper refuses an actual merge or release when it runs. Interpreter script text (python/node/ruby/perl/deno/bun with -c/-e or from a heredoc or here-string) is not read as shell by tier-gate or block-unchecked-merge. A bash/sh/zsh script (heredoc, -c, pipe) is still read as shell.
- **State**: setup run twice produces the same settings file; existing `permissions` entries (allow, deny, ask, other keys) are kept; a settings file that is not valid JSON is not overwritten and setup says so.
- **Timing**: none — the hooks run synchronously per Bash call and no new waits or network calls are added.
- **Dependency**: jq missing at setup time: setup reports that the ask rules were not installed; it does not write a partial file. Hooks' existing infrastructure-failure behavior is unchanged.

### Interface contracts
- tier-gate.sh PreToolUse output: unchanged shape — `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Flow tier gate. ..."}}` or no output (allow). The reasons for cmdUnread, unknown (gh api unreadable / overflow / depth) and shell are no longer produced.
- block-unchecked-merge.sh: exit 2 with a stderr reason for a refusal, exit 0 otherwise; no longer refuses on the ground that a command word or eval argument cannot be read.
- Setup writes Claude Code ask rules into `permissions.ask` of the settings file the user picks (`.claude/settings.json` or `.claude/settings.local.json`), using the rule syntax documented on the Claude Code permissions page, for: merging a pull request (`gh pr merge`), creating or changing a release (`gh release create/edit/delete/upload/delete-asset`), and pushing tags (`git push` with `--tags`, `--follow-tags` or a `refs/tags/` ref).

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Interpreter text no longer read as shell | Turning it off for every program, so `bash -c 'gh pr merge 7'` or `bash <<'EOF' gh pr merge 7 EOF` is also allowed | `bash -c 'gh pr merge 7'` and a bash heredoc holding `gh release create v1` still ask; `python3 -c 'f("x `y` merge")'` is allowed |
| Plain merge after the change | The allow path short-circuits the whole command, so `python3 - <<'PY' ... PY` followed by `gh pr merge 7` on the next line is allowed | That two-line command still asks, naming `gh pr merge 7` |
| Shared parser | Changing lib defaults, so block-destructive stops seeing `python3 -c 'import os; os.system("rm -rf ~")'` | block-destructive, block-force-push and block-secrets test files pass unchanged |
| Unreadable program with a wrapper behind it | Hook allows `G=gh; $G pr merge 7` and the wrapper also lets it run | Run through the hook and the gh wrapper: hook prints nothing, wrapper exits 1 with its refusal and the stub gh is never called |
| Setup merge of settings | Overwriting the file or the whole `permissions` object, dropping existing allow/deny rules, or duplicating rules on a second run | Fixture settings with allow `["Bash(ls)"]`, deny `["Read(.env)"]`: after setup both remain, ask has each flow rule once; second run gives a byte-identical file |
| Ask rules match compound forms | A rule written with the wrong syntax that never matches | Live `claude -p` in a scratch repo with flow's hooks off and a stub gh: `cd x && gh pr merge 7` is not run (stub log empty) |

## Design

Risky files: block-unchecked-merge.sh, lib/command-parse.sh, commands/setup.md, README.md, references/gate-configuration.md (each has 3-10 fix commits in the last 200).

Callers read: tier-gate.sh (_tg_read_text, _tg_scan, _tg_body_line, main reason loop), block-unchecked-merge.sh (segment loop), lib/command-parse.sh (_bd_strip_noncode is_sink/reader_ok, _bd_expand_interpreter_args), lib/tier-runtime.sh (the gh/git wrappers refuse an unapproved merge or release when it runs, including gh api calls read by their real arguments).

Options:
1. Smallest change inside the existing structure: an opt-in parser setting, off by default, that only tier-gate and block-unchecked-merge turn on. With it, a heredoc owned by python/perl/ruby/node/deno/bun is read like a cat heredoc (a quoted body is data; an unquoted body keeps only what bash itself runs), and quoted words and here-strings after those interpreters are not read as shell. tier-gate stops emitting its asks for text it cannot read (program, eval, source, gh api, overflow/depth, shell reading a pipe); block-unchecked-merge stops refusing on that ground. The wrappers stay the run-time check. Setup gains one fence that merges Claude Code ask rules into a settings file.
2. Change the parser's defaults for every hook. Rejected: block-destructive, block-force-push and block-secrets depend on reading interpreter text.
3. Replace tier-gate's parser with a prefix matcher over plain segments. Rejected: a large rewrite of a hook with many tested cases; adds new structure.

Chosen: option 1.

Does not add:
- No new hook, wrapper, or settings key in flow's own settings.
- No change to parser behaviour for any hook that does not opt in.
- No network call or model call in any hook.

Invariants:
- A merge or release that runs was asked about by tier-gate in the same call (the wrapper enforces it); a merge tier-gate asks about is a plainly written one that block-unchecked-merge checks.
- bash/sh/zsh script text (heredoc, -c, here-string, pipe) is still read as shell by both hooks.
- Infrastructure-failure asks and tag-push asks for plainly written git push are unchanged.

## Plan

T1 lib/command-parse.sh: opt-in BD_LANG_DATA (off by default). A heredoc owned by python*/perl/ruby/node/deno/bun is read like a cat heredoc; quoted words and here-strings after those programs are not appended as shell. Tests: tg-interpreter-text, tg-plain-still-asks; destructive/force-push/secrets test files unchanged. Risk rows: interpreter text, shared parser.
T2 tier-gate.sh (_tg_body_line, _tg_read_text) and block-unchecked-merge.sh set BD_LANG_DATA=1. Test: tg-interpreter-text (AC1, AC2). Risk row: plain merge after the change.
T3 tg-plain-still-asks (AC3): merge/release/tag push alone and joined; bash -c; bash heredoc; substitutions bash runs.
T4 tier-gate drops cmdUnread/unknown/shell asks; block-unchecked-merge drops refusals for text it cannot read; flip the listed scenarios, keeping coverage through the wrapper; new tr-unreadable-refused-at-run (AC4). Risk row: unreadable program with a wrapper behind it.
T5 setup: [ask: permission] file choice + SETUP_PERMISSIONS fence merging nine ask rules with jq; e2e-setup-permissions.test.sh; opt-in live claude -p check (AC5). Risk rows: setup merge, rules match compound forms.
T6 docs: README, three-tier-safety, gate-configuration, hook headers; e2e-tier-docs.test.sh (AC6).
T7 full affected test files, version bump, CHANGELOG (AC7).
Order: T1, T2, T3, T4, T5, T6, T7.

## Stranger Test

PASS — 7 tasks reviewed. Each names its files, test scenario, verification command, risk rows and the existing code it reuses (is_sink/reader_ok, the BD_QUOTED_BODIES gating idiom, e2e_run_fence, the rulesets fence).
