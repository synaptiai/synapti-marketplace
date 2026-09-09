# Visual Verification Output and Task Tracking

Supporting reference for `skills/visual-verification/SKILL.md`. The skill states the rules (detection, browser-tool cascade, loop bounds, result vocabulary); this file holds the full output template, the task-tracking wording, the viewport table, and the rationale for the external-plugin cascade entries.

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
# ... for each page: screenshot → analyze → record findings ...
TaskUpdate(visualVerificationTaskId, status: "completed", result: "PASS/FAIL — {pages} checked, P1:{n} P2:{n} P3:{n}")

TaskUpdate(responsiveTaskId, status: "in_progress")
# ... for each viewport: resize → screenshot → analyze ...
TaskUpdate(responsiveTaskId, status: "completed", result: "PASS/FAIL — {viewports} tested, findings: {summary}")
```

Run `TaskList` afterwards to confirm every visual sub-task reached a terminal state.

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

Cascade positions 4 and 5 (`compound-engineering:test-browser`, `compound-engineering:agent-browser`) come from the `compound-engineering` plugin in the same Synapti marketplace.

- Without it installed: positions 1–3 (Playwright MCP, Chrome DevTools MCP, CLI fallback) carry the loop; positions 4–5 are skipped silently.
- With it installed: positions 4–5 become fallbacks when 1–3 are unavailable.
- Why not vendor: a copied implementation would diverge silently from the upstream plugin's browser-tool surface, and flow would inherit maintenance for code it did not author. Documenting the dependency lets users in tooling-constrained environments install it as a remediation step instead of discovering the gap at verification time.

The README lists `compound-engineering` as a recommended companion plugin in the Hook Compatibility / Dependencies section.
