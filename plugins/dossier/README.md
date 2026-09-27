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

**Three verification passes that genuinely cannot see each other.** Independence is architectural, not instructed: separate agent dispatches, `memory: none`, a skill firewall that keeps reconciliation logic out of every verifier's context, single-message dispatch, and per-pass model configuration. A regression test checks that each pass has `memory: none`, that no pass can load the reconciliation skill, that each pass loads a different second skill, that no pass names another, that `/dossier:audit` dispatches all three, and that each pass's model setting resolves through the settings cascade. Single-message dispatch is required by `/dossier:audit` itself; no test checks it.

**A gate that cannot be faked.** Nineteen conditions, conjunctive. Twelve are mechanical; seven need a model to read the package. `bin/dossier-gate.sh` structurally refuses to emit `PASS` without a scorer verdict — because link-checking and header parsing certifying a package whose security claims nobody read is exactly the theater this system exists to prevent. A package can score 96/100 and be `not ready` on one unapproved public claim.

**Dependency vulnerabilities count.** Gate condition G19 fails when a Critical or High dependency vulnerability recorded in the evidence ledger has no recorded disposition: an owner and a `mitigating` or `closed` status in the risk register, or a named accepter, dates, and a basis in the accepted-risks table. When the ledger holds no vulnerability evidence at all, G19 is `INCONCLUSIVE`, and the package is `not ready` until scan output is ingested. See [Vulnerability and code-quality scans](#vulnerability-and-code-quality-scans).

**The findings table is published before any repair.** A package that quietly fixes what it found and reports only the clean end state has destroyed its own audit trail.

## Install

```bash
/plugin marketplace add synaptiai/synapti-marketplace
/plugin install dossier@synapti-marketplace
```

Requires `bash`, `git`, and `jq`. On Windows, run Claude Code with Git Bash. Without `jq`, the public-document hook blocks every Write and Edit tool call in any repository where the plugin is enabled, because it cannot check the content.

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

**Four jobs, split by privilege.** The `policy` job decides and builds evidence with no agent. The `scan` job runs the optional dependency and code-quality scans with `contents: read`, no agent, and no persisted git credentials. The `refresh` job runs the agent with `contents: read`, no write token, and no persisted git credentials; its entire output is a patch artifact. It runs even when the `scan` job fails, so a scan failure never stops a range from being documented. The `publish` job holds the write token and runs no agent code. A fully prompt-injected agent's maximum achievable outcome is a patch that the privileged job rejects against a path allowlist.

**Range-based against a durable cursor**, not against the triggering PR's diff. That single decision makes concurrent merges, dropped runs, retries, and the weekly sweep all compose safely — a lost run is never a lost change, the next run's range just widens.

**Four loop guards** evaluated before a runner is allocated, so a loop costs nothing: head-ref prefix, generated label, skip label, bot actor. The docs directory is also in the path-filter exclusions, so a merged docs PR fails the policy check even if every other guard were removed.

**No force-push anywhere.** Merge-forward, never rebase.

**Fails loudly when credentials are missing.** Not silently — stale documentation must never masquerade as current. The one soft path is a fork-originated PR, where GitHub withholds secrets by design; that emits a notice and the scheduled sweep covers the range.

Default trigger policy is path-filtered merges plus a weekly sweep. Label-gating is available and not recommended: its failure mode is quietly stale documentation that looks current, which is the exact thing this plugin exists to prevent.

**Rolling-branch rotation is reported, not performed.** Each run of the `policy` job records whether the documentation branch would be due for rotation: `true`, `false`, or `unknown` when its age or size could not be measured. The rule reads `ci.rollingBranchRotation` (`none`, `weekly` for 7 days, `monthly` for 30 days) and `ci.thresholds.rotationMaxAccumulatedLines` (default 5000). The branch age and accumulated size are recorded in every case, including when rotation is `none`. Nothing closes the pull request, deletes the branch, or recreates it.

### Vulnerability and code-quality scans

Two scans are available, each off by default and each switched on by its own setting. Turning one on never turns on the other.

| Setting | Tool | What happens to the result |
|---|---|---|
| `engagement.allowedActions.runSecurityScan` | `osv-scanner` | Cited as evidence-ledger rows, which G19 reads |
| `engagement.allowedActions.runCodeQualityScan` | `pyscn` (Python) | Kept as a job artifact only. Not cited, and no gate condition reads it |

In CI the `scan` job runs both through `bin/dossier-scan-security.sh` and `bin/dossier-scan-quality.sh`. Each script reports one status: `ok`, `disabled`, `unavailable`, `timeout`, or `error`. A scan that did not run is never reported as a clean result.

No command runs the scanners locally. To produce the same input yourself, run `bin/dossier-scan-security.sh --target . --out .dossier/scan`. `bin/dossier-vuln-evidence.sh --scan <file>` turns scan output into ledger rows. It reads SARIF, `osv-scanner` JSON (from the scan script or from the project's own tooling), or a Dependabot alerts export, and it never runs a scanner itself. Critical and High findings get one row each; Medium and Low are counted. A finding whose severity cannot be read is recorded as unresolved, never as Low.

While a run's scope file exists, the action-ceiling hook blocks a direct `osv-scanner` or `pyscn` command unless the matching setting is on.

### After setup, you must still

- Add `ANTHROPIC_API_KEY` (or `CLAUDE_CODE_OAUTH_TOKEN`) as a repository secret. Setup cannot — secrets are write-only via the API.
- Enable **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to create and approve pull requests"**. This is the most common setup failure: without it the branch pushes cleanly and PR creation is refused, so you get a successful push and no PR. If your repository is org-owned, the org-level setting must be enabled first — until then the repository checkbox is greyed out and the API call returns 200 with no effect.
- Commit and push the workflow. Scheduled workflows only run from the default branch.

`/dossier:setup` preflights all of these and prints the exact commands.

## Configuration

`.claude/settings.dossier.json`, resolved through a cascade, highest first: `DOSSIER_*` environment variables, a file named by `$DOSSIER_CONFIG`, `.claude/settings.dossier.local.json`, `.claude/settings.dossier.json`, `$HOME/.claude/settings.dossier.json`, and the plugin default. The environment layer is what lets a CI job run with zero interaction. A `.local.json` file that is tracked by git is skipped with a warning, because a pull request could otherwise change the highest-ranked settings file.

Conditional and cross-field rules live in `bin/dossier-validate-config.sh`, not in `schema.json`. The documented fallback validator ignores `if`/`then` when `jsonschema` is absent, so a schema conditional would report success and enforce nothing on exactly the machines that need it most.

See `references/config-resolution.md`.

## Safety model

| Tier | Actions |
|---|---|
| **1 Autonomous** | Read sources, run checks the action ceiling permits, write registers, draft internal documents inside the output root, dispatch collector, drafter, verifier, and scorer agents |
| **2 Journal** | Write `06-public/**`, modify the claim register, apply a correction to a public document |
| **3 Confirm** | Write or publish outside the output root, approve a public claim, accept a Critical or High finding as a risk, override a gate condition, overwrite an existing canonical document, commit or push |

Hooks enforce these limits rather than trusting instructions:

- `enforce-output-root.sh` blocks writes outside the output root, and `enforce-allowed-actions.sh` blocks shell commands the action ceiling forbids. Both act only while `<outputRoot>/00-control/.scope.json` exists, which is the file a run writes when it freezes its scope.
- `block-unregistered-claim.sh` blocks credentials, internal paths and hostnames, private IP addresses, register IDs, and configured redaction patterns in content bound for any path under `06-public/`. It runs whether or not a run is active.
- `stale-header-stamp.sh` warns when a canonical document is edited and its `last-verified` date is not today, or when the date is missing or malformed. It never blocks.
- `detect-local-merge.sh` suggests `/dossier:refresh` after a local merge lands on the default branch. `local.onLocalMerge` sets this to `suggest` (default), `run` for a stronger prompt, or `off`. It never blocks.

`bin/dossier-claim-scan.sh` checks the whole of `06-public/`. It reads paragraphs, list items, blockquotes, and table cells, and skips headings and fenced code. A sentence counts as registered only when it matches approved wording in the claim register exactly. Under the gate, leakage fails G06, and a scan that could not run or could not finish makes G06 `INCONCLUSIVE`. An unregistered sentence does not fail G06. Deciding whether each public sentence is a registered claim belongs to G04, which the scorer checks.

## Known limitations

Stated here rather than discovered later:

- **`plugin_marketplaces` accepts no ref.** A CI run always executes the skill text from marketplace `main`, even when the helper scripts are pinned to a tag. Set `ci.instructionSource: vendored` for reproducible CI or a private marketplace.
- **The circuit breaker bounds loops, not cost.** GitHub Actions has no spend cap for third-party API calls. Set a budget in the Anthropic console.
- **Secret-scan patterns miss novel formats.** The agent has no network egress and the documentation PR is human-reviewed; those are the backstops.
- **Windows is not tested.** The plugin declares Git Bash as its Windows requirement, but its test suite runs only on Linux in CI, and no automated check runs its hooks or scripts on Windows.
- **A plugin cannot guarantee a different model** for verification. In-plugin passes give independent context with a configurable model; `/dossier:audit --external` renders a self-contained prompt for genuinely cross-model review. Which tier was used is recorded in the verification report.

## Development

```bash
plugins/dossier/tests/run.sh                          # all tests
plugins/dossier/tests/run.sh agent-independence.test.sh  # one file
```

Run the suites through `tests/run.sh`. A suite started on its own exits without running, because the runner loads the guard that keeps every test's git commands inside the run's temporary directory, so a test cannot change, commit to, or push from the repository it was started in.

`agent-independence.test.sh` is the load-bearing one. If it fails, the three verification passes are no longer independent and the audit result is worth less than it appears to be.

## License

Apache-2.0
