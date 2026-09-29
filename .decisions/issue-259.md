---
issue: 259
created: '2026-09-28T17:38:34Z'
artifacts:
- type: specification
  captured_at: '2026-09-28T17:38:34Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-28T17:39:22Z'
  goal_id: issue-259
  source: github_issue
- type: goal-evaluation
  captured_at: '2026-09-28T17:39:23Z'
  goal_id: issue-259
  transition: draft-to-active
  trigger: command
- type: workflow-run
  captured_at: '2026-09-28T17:39:40Z'
  workflow: start-issue
  run_id: 2026-09-28T173328Z-issue-259
  status: active
- type: stranger-test
  captured_at: '2026-09-28T17:49:11Z'
  result: PASS
  task_count: 7
---

## Specification


_Captured by specification-capture skill on 2026-09-28. Source: mixed (non-goals and failure modes extracted from issue #259 and epic #258; interface contracts and risk map drafted and user-confirmed)._

### Non-goals

- No Flow decision point calls the client in this issue. Sites are wired in #260-#271, so no command or hook output changes here.
- Flow does not depend at runtime on the TypeSafe plugin, its SDKs, or any other plugin.
- No retries, backoff, or batching across calls: one HTTP request per call.
- No image input: imajev's `images` field is never sent.
- No real tokenizer: the token limit is estimated as characters / 4.
- No questions for real decision points: the shipped questions file has no sites.

### Failure modes

- **Timeouts** — the request exceeds `systemOne.timeoutMs` (default 3000, clamped to 200-30000): no answer, reason `timeout`, exit 3; the caller keeps today's behavior.
- **Partial failures** — one question in a call abstains or is below its threshold while others answer: the whole call is no answer (all-or-nothing). Records still hold every question's answer.
- **Invalid input** — HTTP error (4xx, 5xx, 429, 529), a redirect, a body that is not JSON, a missing answer or an answer of the wrong type: no answer with a named reason. Invalid settings (unknown provider, remote `http://` URL, malformed env var name, unknown mode) mean no answer or mode off, with a WARN on stderr. Invalid arguments: exit 2.
- **Missing context** — provider `none` or unset, a site absent from the questions file, an unset API key for TypeSafe, python3 or PyYAML missing, a refusal by `cascade-resolve.sh`: no answer and no network request.

### Interface contracts

- CLI: `bin/flow-s1.sh ask --site <id> --state-file <path> [--current <decision>] [--run-id <id>]`. Site id matches `^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$`.
- Exit 0: stdout is one JSON line `{"site","provider","model","truncated","answers":{<qid>:{...}}}`. Exit 3: no answer, stdout empty, stderr `flow-s1: no answer: <reason>`. Exit 2: usage error.
- Normalized answers: noul `{type:"noul", p, confidence}` with confidence = |2p-1|; choice `{type:"choice", choice, probabilities, confidence}`; score `{type:"score", score, probabilities, confidence}`; `unknown_probability` is copied when the provider sends it.
- Settings: `systemOne.provider` (`none|typesafe|imajev|custom`), `baseUrl`, `model`, `apiKeyEnv`, `timeoutMs`, `stateTokenCap` are read with `cascade-resolve.sh --no-repo-settings` (user tier and plugin default only). `systemOne.uses.<site>` (`off|shadow|on`, default off) is read from the full cascade.
- Request: `POST <baseUrl>/v1/systemone`, JSON `{state, questions, model}`. `Authorization: Bearer <key>` is sent only when the named env var is set and non-empty. Redirects are never followed. A non-loopback URL must be `https://`.
- Questions file `plugins/flow/system-one/questions.yaml`: `sites.<id>.questions` (sent as-is), `sites.<id>.thresholds.<qid>` = `{default: <0..1>, models: {<model id>: <0..1>}}`, looked up by the model id the response names.
- Shadow mode makes the request, writes records, and exits 3. On mode writes records and exits 0 when answered.
- Records: one JSON line per question, `{ts, site, question, provider, model, result, answer, current, state_sha256}`, appended to `.flow/runs/<run-id>/system-one.jsonl` when `--run-id` names an existing run, else `${FLOW_STATE_DIR:-~/.claude/flow-state}/system-one.jsonl`. The state itself is never recorded. A symlink is never written through.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| settings tier for provider and address | reads `baseUrl` through the full cascade, so the repository's settings win | user settings baseUrl=stub A, repo `.claude/settings.flow.json` baseUrl=stub B → right: A receives the request, B's log is empty; wrong: B receives it |
| noul confidence | uses p itself as the confidence, so a confident "no" is below threshold | noul p=0.05, threshold 0.8 → right: answer with confidence 0.9; wrong: no answer |
| threshold key | looks up the threshold by the configured model name (an alias) rather than the model that answered | configured `jev-latest`, reply model `jev-1.13.0`, thresholds default 0.95 and `jev-1.13.0`: 0.5, choice confidence 0.7 → right: answer; wrong: no answer |
| shadow mode | returns the answer to the caller in shadow mode | mode shadow, stub replies confidently → right: exit 3, empty stdout, one record written; wrong: exit 0 with the JSON |
| redirects | follows a redirect and forwards the bearer key to another host (Python's default opener does this on 301/302/303 and refuses 307/308 for a POST) | stub A replies 302 to stub B → right: no answer, B's log is empty; wrong: B receives a GET with Authorization |
| partial answers | returns the questions that answered when another abstained | two questions, one `abstained: true` → right: exit 3; wrong: exit 0 with one answer |

## Spec Validation Gate

| # | Acceptance criterion | Verification command | Gate |
|---|---|---|---|
| 1 | Provider none: review, address and Stop hook output identical to before | `FLOW_E2E_ARTIFACT_DIR=<dir> plugins/flow/tests/run.sh e2e-system-one.test.sh` (scenario `provider-none`: no request, exit 3, no record) plus the unchanged suites `plugins/flow/tests/run.sh e2e-commands.test.sh`, `e2e-goal-stuck.test.sh`, `review-v3-integration.test.sh`, `address-v3-integration.test.sh` | PASS |
| 2 | TypeSafe and imajev stubs return the same normalized answers | `plugins/flow/tests/run.sh e2e-system-one.test.sh` (scenarios `typesafe-contract`, `imajev-contract`; the normalized stdout of the two is compared) | PASS |
| 3 | Timeout, 5xx, malformed JSON, abstained, below threshold each give no answer | `plugins/flow/tests/run.sh e2e-system-one.test.sh` (scenarios `timeout`, `http-5xx`, `malformed-json`, `abstained`, `below-threshold`) | PASS |
| 4 | Repository settings cannot choose the address or key variable | `plugins/flow/tests/run.sh e2e-system-one.test.sh` (scenario `repo-settings-ignored`: the repository-named stub's request log is empty) | PASS |
| 5 | Shadow mode writes one record per question and changes no output | `plugins/flow/tests/run.sh e2e-system-one.test.sh` (scenario `shadow-mode`) | PASS |
| 6 | Each scenario writes an artifact | `FLOW_E2E_ARTIFACT_DIR=<dir> plugins/flow/tests/run.sh e2e-system-one.test.sh; ls <dir>` (one `.txt` per scenario) | PASS |

Criterion 1 holds by construction in this issue, because no decision point calls the client yet: the existing suites passing unchanged is the evidence. Each site issue (#260-#271) must re-check it with the site wired and the provider unset.

## Plan

Seven tasks, in order (each bundles code, its E2E scenarios and its evidence):

1. E2E harness support (stub server with a self-exit lifetime, port masking, `e2e_run_bin`, `system-one/` in the plugin digest), the failure list S1-S21, the client skeleton, provider none.
2. Settings from the user tier only (`--no-repo-settings`), presets (TypeSafe `https://api.typesafe.ai`, `jev-1.13.0`, `TYPESAFE_API_KEY`; imajev `http://127.0.0.1:8765`), https-or-loopback, key variable checks, `settings.json` and `schema.json`.
3. Request and normalization for both providers, thresholds by the answering model, all-or-nothing, truncation.
4. Total deadline, HTTP errors, malformed bodies, redirects (307 and 302), connection failure.
5. Modes off/shadow/on and per-question records (no symlink on any path component).
6. Reference doc, README, CHANGELOG.
7. Unchanged suites, one mutant per risk row, self-review.

Decisions taken at planning:
- Choice and score confidence come from the provider's `confidence` field; when absent, TypeSafe's documented formula (n*peak-1)/(n-1), which for a noul is |2p-1|.
- Risk row 5 names 302, the redirect Python's default opener follows with the Authorization header.
- Each goal criterion's command runs only its own scenarios (`FLOW_E2E_SCENARIOS`), because warn mode runs a trusted goal's commands on every Stop with a 30 s limit each.

## Stranger Test

PASS — 7 tasks reviewed. Every task names its files, contract, failure modes, risk rows, discriminating scenario with the source of each expected value, Reuses line with searched terms, verification command and expected evidence.

## Scope decisions


- 2026-09-28T18:50Z. Code review round 1 found that the sys.path guard, which filtered "" and ".", missed the working directory when PYTHONPATH had an empty element, so a module planted in the repository ran; the same guard existed at 29 older sites in bin/ and hooks/. The question put to the user (AskUserQuestion) was how to handle those sites, and the user chose "Fix all in this PR".
- Through later review rounds that fix became the plugin-wide rule that tests/syspath-guard.test.sh pins: every Python unit removes the working directory from sys.path before its first import, and every script and command block that runs python3 first keeps in PYTHONPATH only directories outside the repository that are not the working directory or above it, decided in an isolated python3 by directory identity.
- What this changes against main, by design:
  - Command blocks gained lines at the top, so a diagnostic that zsh prints with a line number of the block names a later line.
  - Flow's own Python no longer imports from a PYTHONPATH element inside the repository or at or above the working directory. Where PyYAML is reachable only that way (for example PYTHONPATH=<repo>/vendor), the Stop hook, the goal evaluator and the other hooks that need PyYAML report "PyYAML unavailable" and stand down, where main would import it and go on. Where a planted sitecustomize.py or yaml.py sits in such an element, main runs it and this branch does not; that is the defect being fixed.
  - The reply-style check runs its temporary script with python3 -I.
- Unchanged: a goal's verification commands still get the original PYTHONPATH.
- The specification's non-goal "no command or hook output changes here" concerns System One, whose client no decision point calls yet; the differences above come from this guard.
