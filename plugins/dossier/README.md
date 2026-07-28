# Dossier: Evidence-First Documentation Plugin

Evidence-first project documentation. Produces an audit-ready 23-file package for technical due diligence, engineering and product onboarding, and partner or customer communication — then keeps it current with a post-merge job that opens a documentation pull request.

The point is not to make a project look complete. It is to make the truth about a project clear, navigable, useful, and safe to disclose.

## What you get

A fixed package under `docs/dossier/` (configurable):

```
00-control/       documentation-index · evidence-ledger · assumptions-questions-and-contradictions
                  claim-and-disclosure-register · terminology-and-ownership
01-project/       executive-project-brief · product-and-domain
02-architecture/  system-architecture · components-and-codebase · data-and-ai
                  interfaces-and-integrations · infrastructure-and-deployment
03-assurance/     security-privacy-and-compliance · reliability-performance-and-observability
                  testing-quality-and-delivery
04-operating/     onboarding-and-local-development · operations-and-incident-response
                  decisions-technical-debt-and-risks
05-due-diligence/ technical-due-diligence-report · assets-dependencies-and-licenses
06-public/        technical-partner-guide · customer-product-and-trust-guide
07-verification/  documentation-verification-report
```

All 23 exist for every project. A library still gets `infrastructure-and-deployment.md`; a project with no AI still gets `data-and-ai.md`, with the AI sections marked `N/A` and the evidence for that. Content adapts; structure never — a package whose shape varies per project cannot be diffed, audited, or compared, and "we dropped that file, it did not apply" is indistinguishable from "we ran out of time" six months later.

## What makes it different from a docs generator

**Every material claim carries an evidence ID and a claim state.** `V` verified · `C` corroborated · `R` reported · `I` inferred · `U` unknown · `N/A`. Only `V` and `C` may appear unqualified in a public document. If a claim cannot be traced, the package writes `Unknown` rather than the confident unsourced sentence.

**Three verification passes that genuinely cannot see each other.** Independence is architectural, not instructed: separate agent dispatches, `memory: none`, a skill firewall that keeps reconciliation logic out of every verifier's context, single-message dispatch, and per-pass model configuration. A regression test enforces all five properties, because a verifier that quietly gained access to the merge logic still produces a plausible-looking findings table and nothing else would catch it.

**A gate that cannot be faked.** Nineteen conditions, conjunctive. Twelve are mechanical; seven need a model to read the package. `bin/dossier-gate.sh` structurally refuses to emit `PASS` without a scorer verdict — because link-checking and header parsing certifying a package whose security claims nobody read is exactly the theater this system exists to prevent. A package can score 96/100 and be `not ready` on one unapproved public claim.

**The findings table is published before any repair.** A package that quietly fixes what it found and reports only the clean end state has destroyed its own audit trail.

## Install

```bash
/plugin marketplace add synaptiai/synapti-marketplace
/plugin install dossier@synapti-marketplace
```

## Commands (9)

| Command | Purpose |
|---|---|
| `/dossier:init` | Scaffold the package, write settings, seed the five registers |
| `/dossier:baseline` | Inventory evidence, model the project, draft all 23 documents |
| `/dossier:refresh` | Targeted refresh for a range of changes. The CI entry point |
| `/dossier:audit` | Three independent verification passes |
| `/dossier:reconcile` | Merge findings, publish before repair, apply corrections |
| `/dossier:gate` | Score and issue the release verdict |
| `/dossier:claim` | Adjudicate whether one sentence may be said publicly |
| `/dossier:status` | Package health, staleness, and automation state |
| `/dossier:setup` | Wire the post-merge documentation refresh |

Typical first run:

```
/dossier:init  →  /dossier:baseline  →  /dossier:audit  →  /dossier:reconcile  →  /dossier:gate
```

Then `/dossier:setup` once, and the package maintains itself.

## Skills (10)

`engagement-scoping` · `evidence-ledger` · `gap-and-contradiction-register` · `project-modeling` · `doc-package-contract` · `disclosure-gating` · `verification-protocol` · `finding-reconciliation` · `scoring-and-release-gate` · `prose-clarity`

Each carries one Iron Law. The per-document content contracts — over 500 requirements and hard rules — live in `references/package-contract-*.md`, one file per directory, so a drafting agent loads exactly the one it needs.

## Agents (6)

Three verification lenses (`dossier-pass-a-evidence`, `dossier-pass-b-falsification`, `dossier-pass-c-audience`), plus `dossier-scorer`, `dossier-evidence-collector`, and `dossier-doc-drafter`.

## The post-merge job

`/dossier:setup` renders a workflow into your repository that regenerates the affected documents after a pull request merges and opens a documentation PR.

**Three jobs, split by privilege.** The `policy` job decides and builds evidence with no agent. The `refresh` job runs the agent with `contents: read`, no write token, and no persisted git credentials; its entire output is a patch artifact. The `publish` job holds the write token and runs no agent code. A fully prompt-injected agent's maximum achievable outcome is a patch that the privileged job rejects against a path allowlist.

**Range-based against a durable cursor**, not against the triggering PR's diff. That single decision makes concurrent merges, dropped runs, retries, and the weekly sweep all compose safely — a lost run is never a lost change, the next run's range just widens.

**Four loop guards** evaluated before a runner is allocated, so a loop costs nothing: head-ref prefix, generated label, skip label, bot actor. The docs directory is also in the path-filter exclusions, so a merged docs PR fails the policy check even if every other guard were removed.

**No force-push anywhere.** Merge-forward, never rebase.

**Fails loudly when credentials are missing.** Not silently — stale documentation must never masquerade as current. The one soft path is a fork-originated PR, where GitHub withholds secrets by design; that emits a notice and the scheduled sweep covers the range.

Default trigger policy is path-filtered merges plus a weekly sweep. Label-gating is available and not recommended: its failure mode is quietly stale documentation that looks current, which is the exact thing this plugin exists to prevent.

### After setup, you must still

- Add `ANTHROPIC_API_KEY` (or `CLAUDE_CODE_OAUTH_TOKEN`) as a repository secret. Setup cannot — secrets are write-only via the API.
- Enable **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to create and approve pull requests"**. This is the most common setup failure: without it the branch pushes cleanly and PR creation is refused, so you get a successful push and no PR. If your repository is org-owned, the org-level setting must be enabled first — until then the repository checkbox is greyed out and the API call returns 200 with no effect.
- Commit and push the workflow. Scheduled workflows only run from the default branch.

`/dossier:setup` preflights all of these and prints the exact commands.

## Configuration

`.claude/settings.dossier.json`, resolved through the standard cascade (`.local.json` > project > `$HOME` > plugin default) with `DOSSIER_*` environment overrides — which is what lets a CI job run with zero interaction.

Conditional and cross-field rules live in `bin/dossier-validate-config.sh`, not in `schema.json`. The documented fallback validator ignores `if`/`then` when `jsonschema` is absent, so a schema conditional would report success and enforce nothing on exactly the machines that need it most.

See `references/config-resolution.md`.

## Safety model

| Tier | Actions |
|---|---|
| **1 Autonomous** | Read sources, write registers, draft internal documents inside the output root, dispatch verifiers |
| **2 Journal** | Write `06-public/**`, modify the claim register, mark a contradiction resolved, change delivery mode |
| **3 Confirm** | Publish outside the output root, approve a public claim, override a gate condition, delete or rename a canonical file, widen the action ceiling |

Hooks enforce the action ceiling at `PreToolUse` rather than trusting instructions: writes outside the output root are blocked, disclosure patterns bound for `06-public/` are blocked, and commands the ceiling forbids are blocked. All are inert unless a run is active.

## Known limitations

Stated here rather than discovered later:

- **`plugin_marketplaces` accepts no ref.** A CI run always executes the skill text from marketplace `main`, even when the helper scripts are pinned to a tag. Set `ci.instructionSource: vendored` for reproducible CI or a private marketplace.
- **The circuit breaker bounds loops, not cost.** GitHub Actions has no spend cap for third-party API calls. Set a budget in the Anthropic console.
- **Secret-scan patterns miss novel formats.** The agent has no network egress and the documentation PR is human-reviewed; those are the backstops.
- **A plugin cannot guarantee a different model** for verification. In-plugin passes give independent context with a configurable model; `/dossier:audit --external` renders a self-contained prompt for genuinely cross-model review. Which tier was used is recorded in the verification report.

## Development

```bash
plugins/dossier/tests/run.sh                          # all tests
plugins/dossier/tests/run.sh agent-independence.test.sh  # one file
```

`agent-independence.test.sh` is the load-bearing one. If it fails, the three verification passes are no longer independent and the audit result is worth less than it appears to be.

## License

Apache-2.0
