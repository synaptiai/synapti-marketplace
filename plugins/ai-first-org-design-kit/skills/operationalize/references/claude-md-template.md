# CLAUDE.md Section Template

The operationalize skill appends this section to the project's CLAUDE.md.
The section uses version markers for clean re-runs: the opening marker
`<!-- ai-first-kit-operationalize: ... -->` and closing marker
`<!-- /ai-first-kit-operationalize -->` allow the section to be replaced
without affecting the rest of the CLAUDE.md.

## Template

```markdown
<!-- ai-first-kit-operationalize: {YYYY-MM-DD-HHMM} -->
## Organizational Governance

This project follows an organizational genome and governance framework.
Agents operating in this repository must follow the rules below.

### Hard Boundaries (Non-Negotiable)
[For each boundary from governance/HARD-BOUNDARIES.md, one compact line:]
1. **{Boundary Name}** — {One-sentence prohibition from "Prohibited" field}

[Example:]
1. **No Ungrounded Claims** — Never make factual claims without verification against current sources.
2. **No Irreversible Actions Without Approval** — Never delete data, force-push, or drop resources without explicit approval.
3. **No Unauthorized External Communication** — Never send messages or post content visible to others without approval.
4. **No Incomplete Shipments** — Never ship work containing mocks, placeholders, or TODOs.
5. **No Assumption-Driven Decisions** — Never act on assumed state without verification.

Priority: {Boundary hierarchy from HARD-BOUNDARIES.md, e.g., "Safety > Reputation > Trust > Quality > Completeness"}

### Values
[One line per value from genome/00-identity/VALUES.md:]
- **{Value Name}:** {One-sentence decision rule}

### Full Operating Primer
For complete operating instructions including authority tiers, quality gates,
voice norms, escalation protocols, and anti-patterns, read:
`$HOME/.ai-first-kit/projects/{slug}/AGENT-PRIMER.md`

### Quality Gates
This project uses automated quality gates. Self-review against gate criteria
before presenting work. See `$HOME/.ai-first-kit/projects/{slug}/gates/INDEX.md`.
<!-- /ai-first-kit-operationalize -->
```

## Design Decisions

- **Hard boundaries inline:** These are the most critical rules — always in context.
- **Values compact:** One line per value. The full decision rules are in the primer.
- **Everything else by reference:** Keeps the CLAUDE.md lean (~30-40 lines added).
- **Version markers:** Enable clean re-runs without manual editing.
- **$HOME path references:** Uses `$HOME` for portability across machines.
- **Conditional primer pointer:** If the user selected "CLAUDE.md only" and no AGENT-PRIMER.md exists, omit the "Full Operating Primer" subsection to avoid referencing a nonexistent file.
