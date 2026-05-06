---
name: visual-verification
description: "Verify UI-facing changes by running a screenshot-analyze-verify loop across configured viewports, with a browser-tool priority cascade (Playwright MCP → Chrome DevTools MCP → CLI fallback → external skill fallback) and bounded iteration. Use after build/runtime verification passes and the diff includes `.tsx`/`.jsx`/`.vue`/`.html`/`.css`/`.scss`/`.svelte` files OR the acceptance criteria mention UI/page/render/display/visual. This skill MUST be consulted because UI changes that pass build and unit tests can still ship blank pages, render-blocking console errors, or broken responsive layouts that no other verification phase catches."
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskList, TaskUpdate
context: fork
agent: Explore
---

# Visual Verification

You verify that UI-facing changes render correctly through a screenshot-analyze-verify loop. This skill was extracted from `runtime-verification` so the visual workflow has its own home; the two skills compose (runtime-verification handles build/server/smoke/E2E/LSP-diagnostics; visual-verification handles browser-rendered UI).

## Iron Law

**UI CHANGES MUST BE VISUALLY VERIFIED OR EXPLICITLY SKIPPED. A build that succeeds and a test suite that passes do not prove the page actually renders. Every UI-relevant change goes through this loop or surfaces a structured SKIP/BLOCKED result that the completion gate can reason about — never a silent skip.**

The `visualVerification.requireVisualVerification` setting controls escalation behavior, not whether the loop runs. Even when `requireVisualVerification: false`, an unattempted UI change must produce SKIP_WARN with the reason — the completion gate emits the warning so the user knows visual verification was not attempted.

## UI Relevance Detection

Visual verification activates when EITHER signal fires:

```bash
# Signal 1: UI file extensions in the diff
git diff --name-only HEAD~1..HEAD | grep -iE '\.(tsx|jsx|vue|html|css|scss|svelte)$'

# Signal 2: UI keywords in the acceptance criteria
# (The invoking command passes the criterion list as input; check for any of these tokens.)
# Tokens: UI, page, display, render, visual, layout, responsive, component, style
```

If neither signal fires → emit `SKIP — no UI-relevant changes detected.` and exit. This is a legitimate skip, distinct from `SKIP_WARN`.

## Browser Tool Discovery (priority cascade)

Try these in order; use the first available:

1. **Playwright MCP** (`browser_navigate`, `browser_take_screenshot`, `browser_console_logs`) — full capability: navigation, screenshots, console logs, DOM inspection
2. **Chrome DevTools MCP** — screenshot + console + DOM inspection
3. **CLI fallback**: `npx playwright screenshot http://localhost:$PORT/ $SCREENSHOT_DIR/page.png`
4. **External skill fallback**: `Skill(compound-engineering:test-browser)` — if the `compound-engineering` plugin is installed
5. **External skill fallback**: `Skill(compound-engineering:agent-browser)` — if the `compound-engineering` plugin is installed
6. **No tools available** → return SKIP_WARN or BLOCKED based on `visualVerification.requireVisualVerification` (default: false → SKIP_WARN; explicit true → BLOCKED, command-level escalation needed)

The skill does NOT silently install Playwright. Installation is a side effect with footprint; the user is asked via the command-level escalation path when the cascade falls all the way through.

## Screenshot-Analyze-Verify Loop

Bounded by `settings.json` → `visualVerification.maxIterations` (default: 3). Iterate up to the cap when fixes are applied between rounds; halt earlier when verification passes.

```
For each page URL (dev server root + key pages from routes):
  1. Navigate to page URL
  2. Take screenshot → save to $SCREENSHOT_DIR/{page}-{viewport}-{timestamp}.png
  3. Read screenshot with the Read tool (Claude analyzes visually)
  4. Classify findings using the canonical schema in references/finding-schema.md (category=visual):
     - Blank page → P1 (blocks completion)
     - Render-blocking console errors → P1
     - Layout breaks / broken grid → P2
     - Missing content that should be visible → P2
     - Minor styling issues → P3
  5. If MCP tools are available: also fetch browser_console_logs and grep for JS errors / React warnings / CSP violations
  6. Record screenshot path as evidence (referenced from the per-criterion evidence bundle)
```

Findings emit using the canonical row shape (`ID | Category | Location | Problem | Suggested Fix | Confidence`). Use the `INT-` prefix when invoked from `integration-verifier`, the `VIS-` prefix when invoked standalone. Location for visual findings is the URL path (e.g., `http://localhost:3000/login` instead of `file:line`) — the schema accepts non-file locations for renderer-surface findings.

## Responsive Verification

For each viewport in `settings.json` → `visualVerification.viewports`, resize the browser and repeat the screenshot-analyze step:

- **Default viewports**: Desktop (1280×720), Tablet (768×1024), Mobile (375×812)
- **Per-viewport checks**: content cut off, navigation broken at breakpoint, horizontal scroll on mobile, fixed-width elements overflowing the viewport
- Each viewport is a separate finding source — a layout that works on desktop and breaks on mobile produces a P2 with location like `http://localhost:3000/ @ mobile (375×812)`

## Task Tracking

Create the visual-verification task suite upfront and update status as the loop progresses:

```
# Setup — create all visual verification tasks upfront
TaskCreate("Visual verification", "Screenshot-analyze-verify for UI-facing changes")
TaskCreate("Browser tool discovery", "Detect available browser automation (Playwright MCP, Chrome DevTools, CLI)")
TaskCreate("Responsive check", "Verify UI across configured viewports (desktop, tablet, mobile)")

# Browser tool discovery
TaskUpdate(browserToolTaskId, status: "in_progress")
# ... detect tools ...
TaskUpdate(browserToolTaskId, status: "completed", result: "{tool} detected")

# If not applicable (no UI files, no UI criteria) — legitimate skip:
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP — no UI-relevant changes")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP")

# If no browser tools found — check requireVisualVerification setting:
#   requireVisualVerification: false (default) → SKIP_WARN
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP_WARN — no browser tools. Install Playwright MCP or use /flow:setup.")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP_WARN — no browser tools")

#   requireVisualVerification: true → BLOCKED (command-level escalation)
TaskUpdate(visualVerificationTaskId, status: "completed", result: "BLOCKED — requireVisualVerification is true but no browser tools available")
TaskUpdate(responsiveTaskId, status: "completed", result: "BLOCKED")

# Screenshot-analyze-verify loop (when tools ARE available)
TaskUpdate(visualVerificationTaskId, status: "in_progress")
# ... for each page: screenshot → analyze → record findings ...
TaskUpdate(visualVerificationTaskId, status: "completed", result: "PASS/FAIL — {pages} checked, P1:{n} P2:{n} P3:{n}")

# Responsive verification
TaskUpdate(responsiveTaskId, status: "in_progress")
# ... for each viewport: resize → screenshot → analyze ...
TaskUpdate(responsiveTaskId, status: "completed", result: "PASS/FAIL — {viewports} tested, findings: {summary}")
```

Use `TaskList` after all visual verification completes to confirm all sub-tasks resolved.

## Result Vocabulary

| Result | Meaning | Passes Completion Gate? |
|---|---|---|
| `PASS` | Ran and passed | Yes |
| `FAIL` | Ran and found P1 issues | No |
| `SKIP` | No UI files changed (legitimate) | Yes |
| `SKIP_WARN` | UI files changed, no tools, `requireVisualVerification` is false | Yes (with warning) |
| `SKIP_USER_APPROVED` | User explicitly chose to skip via command-level escalation | Yes |
| `MANUAL` | User committed to manual verification | Yes |
| `BLOCKED` | Awaiting user decision (`requireVisualVerification` is true, no browser tools) | No — requires command-level escalation per `references/escalation-format.md` |

## Output Format

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
| ID | Category | Location | Problem | Suggested Fix | Confidence |
|----|----------|----------|---------|---------------|------------|

#### P2 — Should Fix
| ID | Category | Location | Problem | Suggested Fix | Confidence |
|----|----------|----------|---------|---------------|------------|

#### P3 — Consider
| ID | Category | Location | Problem | Suggested Fix | Confidence |
|----|----------|----------|---------|---------------|------------|
```

## Active Problem Solving

Do NOT silently skip visual verification. Actively solve tooling problems:

| Problem | Action |
|---|---|
| No Playwright MCP | Try Chrome DevTools MCP |
| No Chrome DevTools MCP | Try `npx playwright install chromium && npx playwright screenshot` |
| No `npx playwright` | Try `Skill(compound-engineering:test-browser)` or `Skill(compound-engineering:agent-browser)` |
| No browser tools at all | If `requireVisualVerification` is true, return BLOCKED for command-level escalation per `references/escalation-format.md`. Otherwise, SKIP_WARN with tool installation guidance. |
| Dev server not running | Coordinate with `runtime-verification` skill — it owns dev-server lifecycle. Visual verification cannot run without a server URL. |

## Compatibility note: external dependency

The browser-tool cascade includes two external skills (`compound-engineering:test-browser`, `compound-engineering:agent-browser`) from the `compound-engineering` plugin. These are optional fallbacks — visual-verification works without them when Playwright MCP, Chrome DevTools MCP, or the CLI fallback is available. The `compound-engineering` dependency is documented as optional in the plugin README; the decision to vendor or replace these external entries is deferred to Landing 3 (per the comprehensive review plan).

## Integration with runtime-verification

`runtime-verification` is the parent verification skill — it owns build, dev server, smoke tests, E2E, LSP diagnostics, and acceptance-criteria verification. When the diff is UI-relevant, the consumer (`commands/start.md` Phase 4 step 8 / `commands/pr.md` Phase 4 step 4) invokes BOTH skills:

- `Skill(runtime-verification)` for build + server + smoke + E2E + LSP diagnostics
- `Skill(visual-verification)` for the browser-rendered UI loop

The two run in parallel when the dev server is up; if the dev server fails to start (a `runtime-verification` failure), `visual-verification` returns SKIP with the reason "dev server unavailable". The completion gate treats the dev-server failure as the primary finding.
