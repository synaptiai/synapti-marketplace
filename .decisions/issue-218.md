---
issue: 218
created: '2026-09-21T19:59:32Z'
artifacts:
- type: specification
  captured_at: '2026-09-21T19:59:32Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---
# Decision Journal — Issue #218

feat(flow): visual-verification drives the changed user flow, not only the page load

## Specification

### Non-goals

- A hosted service. The external spec proposed a product that clicks through preview
  deployments and posts recordings. Flow verifies locally, inside the developer's session,
  against the dev server `runtime-verification` already started; the MCP tools in the existing
  cascade are the instrument.
- A new agent or a new fan-out call. Flows run inside `Skill(visual-verification)`, which
  `integration-verifier` already invokes. A pull request that changes no UI pays nothing.
- Installing a browser. The cascade never installs Playwright silently today and does not start
  now. A run with no interactive tool reports `SKIP_WARN`, or `BLOCKED` when
  `requireVisualVerification` is true.
- Guessed selectors. Element targets come from `browser_snapshot`'s accessibility tree. A
  selector invented from the criterion text would pass or fail for reasons unrelated to the code.
- Replacing the page-load check. Step blocks are additional evidence, not a substitute: the
  render check across every configured viewport is what visual verification existed to do.
- Proving the interaction path on a real browser **in this repository**. There is no UI here and
  no dev server, so nothing in this repository can execute a click. What ships is the contract and
  its mechanical checks; the gap is stated in the pull request rather than discovered at review.

### Failure modes

- **Timeouts**: a step that does not settle is bounded by `visualVerification.maxFlowSteps`
  (default 8) per scenario and by the existing `maxIterations`. A scenario that exceeds the step
  bound stops and reports the steps it completed rather than silently truncating.
- **Partial failures**: a step whose `expect` is not met is a finding, and the steps already run
  keep their `Observed:` blocks. A scenario abandoned midway reports `Step: <n>/<m>` for the steps
  that ran, so a reader can see where it stopped.
- **Invalid input**: an element target `browser_snapshot` does not offer is not guessed at. The
  step reports that the target was not found, which is a finding about the page, not a skip.
- **Missing context**: no interactive tool in the cascade is `SKIP_WARN` with the reason named,
  never a silent pass. The CLI screenshot fallback cannot click, so it is explicitly not an
  interactive tool.

### Interface contracts

- `skills/visual-verification/SKILL.md` gains: the scenario-derivation rule (one to three
  scenarios per UI criterion carrying an interaction verb, or a risk-map row naming a UI state),
  the interaction verb list (click, submit, type, select, toggle, open, navigate, drag), the step
  grammar (`navigate <route>`, `click <element>`, `type <element> <text>`,
  `expect <element or text>`), and the interactive-only cascade rule.
- The `### Visual analysis` block gains one line: `Step: <n>/<m> <action>`. Everything else —
  `Viewport:`, `Screenshot:`, `Result:`, `Observed:` — is unchanged, so a page-load block and a
  step block have the same shape and the judge reads both the same way.
- `settings.json`: `visualVerification.flows` (`"on" | "off"`, default `"on"`) and
  `visualVerification.maxFlowSteps` (integer, default 8). `schema.json` constrains both.
- `agents/verdict-judge.md`: rule (d) is **unchanged** — every configured viewport still needs a
  `Result: PASS` page-load block. A new rule covers steps: a `ui` criterion whose text carries an
  interaction verb and whose bundle has neither a `Step:` block nor a `Flows: none — {reason}`
  line is `incomplete evidence — missing interaction steps on a ui criterion` — a distinct
  rationale from the viewport one, because the two failures need different fixes. Any step
  reporting `Result: FAIL` fails the criterion whatever triggered the flow.
- Findings keep `category=visual`. A step whose `expect` is not met is P1 when the criterion under
  test is the one that failed, P2 otherwise.
- `browser_console_logs` is not a tool Playwright MCP exposes. Verified against the server's own
  README on 2026-09-21: the name is `browser_console_messages`. The wrong name appears twice in
  `SKILL.md` and nowhere else under `plugins/flow/`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Judge rule collision | Step blocks are treated as viewport blocks, so a desktop-only flow fails rule (d)'s "every configured viewport" requirement and every interaction criterion fails | The judge's rule (d) text is unchanged and a separate rule names the `Step:` case; a test asserts both rules exist and that rule (d) still says every configured viewport |
| Silent non-interaction | A criterion describing an interaction is verified by a screenshot of the page before it, and the judge passes it because the form is visible | The bundle format and the judge both state that a criterion carrying an interaction verb needs a `Step:` block, with a named auto-FAIL rationale; a test asserts the rationale string |
| Tool name drift | The skill names a tool the server does not expose, so the console check silently never runs | No file under `plugins/flow/` contains `browser_console_logs`; the interactive tools named are the ones the server's README lists |
| Fallback that cannot click | The CLI screenshot fallback is treated as an interactive tool, so a flow "runs" and reports a pass having performed no interaction | The cascade states which entries are interactive; a test asserts the CLI entry is excluded and that the absence of an interactive tool yields `SKIP_WARN` or `BLOCKED` |
| Settings shape | `flows` accepts a boolean, so `true` reads as enabled in one place and as an invalid enum in another | `schema.json` constrains `flows` to `["on", "off"]`; a test asserts `true` is rejected and `"off"` accepted, placed with the other settings-schema assertions |
| Unverifiable capability | Video recording is specified as required, and its absence turns into a skip or a finding on every run | Video is conditional in the text and absent from the result vocabulary; a test asserts no result value mentions it |

## Decisions (AskUserQuestion, 2026-09-21)

- **AC2 named the wrong test file.** `tests/flow-schemas.test.sh` validates the `.flow/` artifact
  schemas under `schemas/v1/` and never reads `schema.json`. The issue body was corrected, with
  approval, to require the assertion where settings-schema assertions live, following
  `tests/flow-agentteam-model.test.sh`. Same shape as #217's AC3.
- **Steps are an additional block type.** Rule (d) is untouched, so page-load coverage across
  every configured viewport does not regress; a new rule covers the interaction case. Rejected:
  requiring flows on every viewport (three times the browser work); replacing page-load blocks
  (loses the render check on the viewports the flow did not run).
- **Derivation stays model work, the verb list is asserted.** No new `bin/` helper. #217 spent
  four review cycles stabilising new helper surface, and detecting an interaction verb does not
  justify a fourteenth helper. Rejected: `bin/flow-ui-scenarios.sh`; leaving the trigger
  unstated.
- **Video is conditional and never required.** `browser_start_video` and `browser_stop_video`
  exist but sit in the server's DevTools section rather than its core set, so they are probably
  behind a capability flag that cannot be confirmed from this repository. Its absence is not a
  skip, a warning or a finding.
- **Shape of the whole issue**: implement and mechanically test the contract; state plainly in
  the pull request that the interaction path has never driven a real browser, because this
  repository has no UI to drive. Declared up front rather than discovered at review.
