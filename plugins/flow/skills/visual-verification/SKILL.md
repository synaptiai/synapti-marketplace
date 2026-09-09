---
name: visual-verification
description: "Verify UI-facing changes by running a screenshot-analyze-verify loop across configured viewports, with a browser-tool priority cascade (Playwright MCP → Chrome DevTools MCP → CLI fallback → external skill fallback) and bounded iteration. Use after build/runtime verification passes and the diff includes `.tsx`/`.jsx`/`.vue`/`.html`/`.css`/`.scss`/`.svelte` files OR the acceptance criteria mention UI/page/render/display/visual. This skill MUST be consulted because UI changes that pass build and unit tests can still ship blank pages, render-blocking console errors, or broken responsive layouts that no other verification phase catches."
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskList, TaskUpdate
agent: Explore
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/*.html"
  - "**/*.css"
  - "**/*.scss"
  - "**/*.sass"
  - "**/*.less"
---

# Visual Verification

## Contract

Iron law: **UI changes are visually verified or explicitly skipped with a structured result — a passing build and test suite do not prove the page renders; never a silent skip.** Invoked alongside `runtime-verification` by `/flow:start` Phase 4 step 2 (retried at step 8) and `/flow:pr` Phase 4 via `Agent(integration-verifier)` when the diff has UI file extensions or UI keywords in acceptance criteria. Returns the Visual Verification table, Visual Evidence table, and P1/P2/P3 findings (`category=visual`), labeled PASS / FAIL / SKIP / SKIP_WARN / SKIP_USER_APPROVED / MANUAL / BLOCKED. Permitted skips: `SKIP` when no UI signal fires or the dev server is unavailable; `SKIP_WARN`, `SKIP_USER_APPROVED`, `MANUAL` only via the cascade.

## UI Relevance

Either signal activates:

1. `git diff --name-only HEAD~1..HEAD | grep -iE '\.(tsx|jsx|vue|html|css|scss|svelte)$'`
2. Acceptance criteria (passed by the invoking command) containing: UI, page, display, render, visual, layout, responsive, component, style.

Neither: `SKIP — no UI-relevant changes detected.` (legitimate, distinct from `SKIP_WARN`).

`visualVerification.requireVisualVerification` (default `false`) controls escalation only; an unattempted UI change always yields at least `SKIP_WARN`.

## Browser Tool Cascade (first available)

1. **Playwright MCP** (`browser_navigate`, `browser_take_screenshot`, `browser_console_logs`)
2. **Chrome DevTools MCP**
3. **CLI**: `npx playwright screenshot http://localhost:$PORT/ $SCREENSHOT_DIR/page.png` (installing chromium first if needed)
4. `Skill(compound-engineering:test-browser)` — if that plugin is installed
5. `Skill(compound-engineering:agent-browser)` — likewise
6. Nothing: `SKIP_WARN` with install guidance ("Install Playwright MCP or use /flow:setup") when `requireVisualVerification` is false; `BLOCKED` when true, escalated per `references/escalation-format.md` (skip = `SKIP_USER_APPROVED`, manual = `MANUAL`, or install).

Never install Playwright silently. Positions 4–5 are documented, not vendored.

## Screenshot-Analyze-Verify Loop

Needs the dev server URL from `runtime-verification`; if the server failed to start, return `SKIP` ("dev server unavailable"); that failure is primary. Bounded by `visualVerification.maxIterations` (default 3); iterate only when fixes land between rounds. `$SCREENSHOT_DIR` = `visualVerification.screenshotDir` (default `.screenshots`).

For each page (root + key routes) and viewport in `visualVerification.viewports` (defaults desktop 1280×720, tablet 768×1024, mobile 375×812):

1. Navigate; screenshot to `$SCREENSHOT_DIR/{page}-{viewport}-{timestamp}.png`.
2. Read the screenshot (Read tool) and analyze it.
3. Classify: blank page or render-blocking console error P1; layout break or missing content P2; minor styling P3 (per-viewport checks in the reference).
4. With MCP tools, grep `browser_console_logs` for JS errors, React warnings, CSP violations.
5. Record the screenshot path in the criterion's evidence bundle.

Findings use the `Finding | Suggested Fix` table (`references/finding-schema.md`), prefix `VIS-` standalone or `INT-` from `integration-verifier`, location = URL path plus viewport (`http://localhost:3000/ @ mobile (375×812)`).

Track three tasks (Visual verification, Browser tool discovery, Responsive check) closed with the result string (wording in [`visual-verification-output.md`](../../references/visual-verification-output.md)); `TaskList` confirms all resolved.

## Result Vocabulary

| Result | Meaning | Passes gate? |
|---|---|---|
| `PASS` | Ran and passed | Yes |
| `FAIL` | Ran and found P1 issues | No |
| `SKIP` | No UI changes, or dev server unavailable | Yes |
| `SKIP_WARN` | UI changed, no tools, `requireVisualVerification` false | Yes, with warning |
| `SKIP_USER_APPROVED` | User chose to skip via escalation | Yes |
| `MANUAL` | User committed to manual verification | Yes |
| `BLOCKED` | `requireVisualVerification` true, no tools; awaiting decision | No; escalate |

## Output Format

```markdown
### Visual Verification

| Check | Status | Details |
|---|---|---|
| Browser tools | {tool name or NONE} | Cascade result |
| Visual check | PASS/FAIL/SKIP/SKIP_WARN/SKIP_USER_APPROVED/MANUAL/BLOCKED | {pages checked, findings} |
| Responsive | PASS/FAIL/SKIP/SKIP_WARN/MANUAL | {viewports tested} |
| Console errors | PASS/FAIL/SKIP | {error count} |
```

Then `### Visual Evidence` and `### Visual Findings` P1/P2/P3 tables (template in the reference), rendered beside runtime-verification's table.
