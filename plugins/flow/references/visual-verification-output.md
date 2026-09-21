# Visual Verification Output and Task Tracking

Supporting reference for `skills/visual-verification/SKILL.md`. The skill states the rules (detection, browser-tool cascade, loop bounds, result vocabulary); this file holds the full output template, the per-viewport `Observed:` block the evidence bundle copies, the task-tracking wording, the viewport table, and the rationale for the external-plugin cascade entries.

## Viewports

Read from `settings.json` → `visualVerification.viewports`. Defaults:

| Name | Size | Per-viewport checks |
|------|------|---------------------|
| desktop | 1280×720 | Layout, navigation, console errors |
| tablet | 768×1024 | Navigation at the breakpoint, content cut off |
| mobile | 375×812 | Horizontal scroll, fixed-width elements overflowing the viewport |

Each viewport is a separate finding source. A layout that works on desktop and breaks on mobile is a P2 with location `http://localhost:3000/ @ mobile (375×812)`.

Screenshots are saved under `visualVerification.screenshotDir` (default `.screenshots`) as `{page}-{viewport}-{timestamp}.png`.

## Task tracking

Create all three tasks upfront and close each with the result string the completion gate reads.

```
# Setup
TaskCreate("Visual verification", "Screenshot-analyze-verify for UI-facing changes")
TaskCreate("Browser tool discovery", "Detect available browser automation (Playwright MCP, Chrome DevTools, CLI)")
TaskCreate("Responsive check", "Verify UI across configured viewports (desktop, tablet, mobile)")

# Browser tool discovery
TaskUpdate(browserToolTaskId, status: "in_progress")
# ... detect tools ...
TaskUpdate(browserToolTaskId, status: "completed", result: "{tool} detected")

# Not applicable (no UI files, no UI criteria) — legitimate skip:
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP — no UI-relevant changes")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP")

# No browser tools, requireVisualVerification: false (default):
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP_WARN — no browser tools. Install Playwright MCP or use /flow:setup.")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP_WARN — no browser tools")

# No browser tools, requireVisualVerification: true (command-level escalation):
TaskUpdate(visualVerificationTaskId, status: "completed", result: "BLOCKED — requireVisualVerification is true but no browser tools available")
TaskUpdate(responsiveTaskId, status: "completed", result: "BLOCKED")

# Loop ran:
TaskUpdate(visualVerificationTaskId, status: "in_progress")
# ... for each page: screenshot → analyze → write the Observed: block → record findings ...
TaskUpdate(visualVerificationTaskId, status: "completed", result: "PASS/FAIL — {pages} checked, P1:{n} P2:{n} P3:{n}\n{one Viewport/Screenshot/Result/Observed block per page and viewport}")

TaskUpdate(responsiveTaskId, status: "in_progress")
# ... for each viewport: resize → screenshot → analyze → write the Observed: block ...
TaskUpdate(responsiveTaskId, status: "completed", result: "PASS/FAIL — {viewports} tested, findings: {summary}\n{one Viewport/Screenshot/Result/Observed block per viewport}")
```

Run `TaskList` afterwards to confirm every visual sub-task reached a terminal state. The `Observed:` blocks live in the task result so the evidence-bundle producer (`commands/start.md` Phase 4 step 5) copies them into `### Visual analysis` without re-deriving anything from the image.

## Per-viewport `Observed:` block

One block per page and viewport, in exactly this shape (the bundle's `### Visual analysis` subsection in `references/evidence-bundle-format.md` consumes it verbatim):

```
Viewport: {name} {width}x{height}
Screenshot: {path under visualVerification.screenshotDir}
Result: {PASS | FAIL}
Observed: {two to four plain sentences describing what is on screen relative to the criterion — element present, text, state, layout, console errors}
```

`Result:` is `FAIL` when the viewport produced a P1 or P2 finding, `PASS` otherwise. `Observed:` names the element the criterion asks for (or states that it is absent), quotes visible text, and mentions console errors or their absence. `Screenshot:` is a path only — the verdict-judge has no file tools and reads the sentences, never the image.

## Full output template

```markdown
### Visual Verification

| Check | Status | Details |
|---|---|---|
| Browser tools | {tool name or NONE} | Cascade result |
| Visual check | PASS/FAIL/SKIP/SKIP_WARN/SKIP_USER_APPROVED/MANUAL/BLOCKED | {pages checked, findings} |
| Responsive | PASS/FAIL/SKIP/SKIP_WARN/MANUAL | {viewports tested} |
| Console errors | PASS/FAIL/SKIP | {error count} |

### Visual Evidence
| Page | Viewport | Screenshot | Status | Findings |
|---|---|---|---|---|

### Visual analysis

Viewport: {name} {width}x{height}
Screenshot: {path}
Result: {PASS | FAIL}
Observed: {two to four sentences}

### Visual Findings (canonical finding-schema)

#### P1 — Critical (Blocks Completion)
| Finding | Suggested Fix |
|---------|---------------|

#### P2 — Should Fix
| Finding | Suggested Fix |
|---------|---------------|

#### P3 — Consider
| Finding | Suggested Fix |
|---------|---------------|
```

Finding rows follow `references/finding-schema.md`: bold `{ID} · {category} · `{location}`` on the first line, problem prose after a `<br>`. Prefix `VIS-` standalone, `INT-` when invoked from `integration-verifier`; `category=visual`; location is a URL path (the schema accepts non-file locations for renderer-surface findings).

The consumer (`commands/start.md` Phase 4, `commands/pr.md` Phase 4 via `integration-verifier`) renders this block beside the runtime-verification table rather than merging them, so each skill's output stays attributable.

## BLOCKED escalation options

When `visualVerification.requireVisualVerification: true` and no cascade position succeeds, the skill returns `BLOCKED` and the consumer escalates per `references/escalation-format.md` with three options:

1. Skip with a note → result `SKIP_USER_APPROVED`
2. The user verifies manually → result `MANUAL`
3. Install browser tools (Playwright MCP, Chrome DevTools MCP, or `npx playwright install chromium`) and re-run

## External dependency: compound-engineering (documented, not vendored)

Cascade positions 4 and 5 (`compound-engineering:test-browser`, `compound-engineering:agent-browser`) come from the third-party `compound-engineering` plugin, which is not part of this marketplace; both positions are skipped when it is not installed.

- Without it installed: positions 1–3 (Playwright MCP, Chrome DevTools MCP, CLI fallback) carry the loop; positions 4–5 are skipped silently.
- With it installed: positions 4–5 become fallbacks when 1–3 are unavailable.
- Why not vendor: a copied implementation would diverge silently from the upstream plugin's browser-tool surface, and flow would inherit maintenance for code it did not author. Documenting the dependency lets users in tooling-constrained environments install it as a remediation step instead of discovering the gap at verification time.


## A completed interaction flow

What the `visual-verification` skill produces for a criterion whose text carries an interaction
verb, when `visualVerification.flows` is `on` and the cascade found an interactive tool.

Criterion: *"Submitting the sign-up form with an empty email shows an inline error."* The verb is
`submit`, so the criterion gets a scenario. Targets come from `browser_snapshot`; none is guessed
from the criterion's wording.

Scenario `signup-empty-email`, three steps, run on the desktop viewport (the criterion mentions
neither responsive nor mobile):

```
Viewport: desktop 1280x720
Screenshot: .screenshots/signup-empty-email-desktop-1.png
Step: 1/3 navigate /signup
Result: PASS
Observed: The sign-up form is shown with fields for name, email and password, and a "Sign up"
button. The email field is empty. No console errors.

Viewport: desktop 1280x720
Screenshot: .screenshots/signup-empty-email-desktop-2.png
Step: 2/3 type "Name" "Ada Lovelace"
Result: PASS
Observed: The name field reads "Ada Lovelace". The email field is still empty and no error text is
shown yet. No console errors.

Viewport: desktop 1280x720
Screenshot: .screenshots/signup-empty-email-desktop-3.png
Step: 3/3 click "Sign up"
Result: PASS
Observed: The form is still shown and was not submitted. An inline error reading "Email is
required" appears directly below the email field, and the field is outlined in red. No console
errors.
Video: .screenshots/signup-empty-email-desktop.webm
```

Points worth taking from the example:

- **Every step gets a block**, not just the last one. The judge reads the sentences and cannot see
  the screen, so a flow that reported only its final state would leave it unable to tell an inline
  error that appeared on submit from one that was on the page all along.
- **`Observed:` describes the page AFTER the step.** Step 2's block says the error is *not yet*
  shown; step 3's says it is. That contrast is the evidence.
- **The step blocks do not replace the page-load blocks.** The same `### Visual analysis` section
  still carries a `Viewport:` block for desktop, tablet and mobile proving the page renders. Rule
  (d) reads those; rule (e) reads these.
- **`Video:` is present only when `browser_start_video` was available.** It cites a path and
  nothing reads it but a human. Its absence changes no result and raises no finding.

A criterion carrying an interaction verb whose section has no `Step:` block at all is an auto-FAIL
at the judge — `incomplete evidence — missing interaction steps on a ui criterion` — because a
picture of the form before it was submitted says nothing about what submitting it does.

## Result vocabulary

The value the skill reports, and what each means. Only `FAIL` and `BLOCKED` fail the completion
gate; no value depends on whether video recording was available.

| Result | Meaning | Passes gate? |
|---|---|---|
| `PASS` | Ran and passed | Yes |
| `FAIL` | Ran and found P1 issues | No |
| `SKIP` | No UI changes, or the dev server was unavailable | Yes |
| `SKIP_WARN` | UI changed, no browser tool, `requireVisualVerification` false | Yes, with warning |
| `SKIP_USER_APPROVED` | The user skipped it via escalation | Yes |
| `MANUAL` | The user verifies by hand | Yes |
| `BLOCKED` | `requireVisualVerification` true and no browser tool | No; escalate |

## Browser tool cascade, in order

Only an interactive tool can run an interaction flow. The others take pictures.

| # | Tool | Interactive |
|---|---|---|
| 1 | Playwright MCP | Yes |
| 2 | Chrome DevTools MCP | Yes |
| 3 | CLI `npx playwright screenshot` | No |
| 4 | `Skill(compound-engineering:test-browser)` | No |
| 5 | `Skill(compound-engineering:agent-browser)` | No |

## Running an interaction flow

The skill states the rule — which criteria qualify, the step grammar, the `Step:` block shape.
This is the procedure.

1. **Snapshot before targeting.** `browser_snapshot` returns the accessibility tree. Every
   `click` and `type` target is a node from it. A selector invented from the criterion's wording
   passes or fails for reasons unrelated to the change, which is worse than not running.
2. **One step at a time.** Perform the step with `browser_click` or `browser_type`, take a
   screenshot, then write the block. Do not batch steps and screenshot once at the end: the judge
   reads sentences and cannot see the screen, so a flow reporting only its final state cannot
   distinguish an error that appeared *because* of the interaction from one that was always there.
3. **The step bound.** A scenario performs at most `visualVerification.maxFlowSteps` steps
   (default 8). On reaching the bound the scenario STOPS and reports the steps it completed, with
   their blocks. It does not silently truncate, and it does not keep going: a flow that needs more
   than the bound is a signal about the scenario, not a reason to raise the limit mid-run.
4. **A target that is not there.** If the snapshot offers no matching node, the step reports that
   the target was not found. That is a finding about the page, not a reason to skip the flow —
   the element the criterion names being absent is exactly what the check is for.
5. **Console after the last step.** Read `browser_console_messages` once per scenario, after its
   final step, and fold what it reports into that step's `Observed:` sentences.
6. **Video, when available.** `browser_start_video` and `browser_stop_video` live in Playwright
   MCP's DevTools set rather than its core set, so they may not be reachable in every
   configuration. When they are, record the scenario to
   `$SCREENSHOT_DIR/{scenario}-{viewport}.webm` and add a `Video:` line citing the path. Nothing
   reads it but a human. Its absence changes no result and raises no finding.

## Severity classification

For a page-load block: a blank page or a render-blocking console error is **P1**; a layout break
or missing content is **P2**; minor styling is **P3**. For a step block: a step whose `expect` is
not met is **P1** when it belongs to the criterion under test and **P2** otherwise.
