---
dossier-header: internal-v1
title: Security, Privacy, and Compliance
purpose: Lets a reviewer decide whether to install software that will execute on their machine, by naming what protects them and what does not.
audience: Reviewer, Installing operator, Maintainer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A hook is added or changed; repository access controls change; a dependency or third-party action is added; a vulnerability scan is run for the first time
related: [02-architecture/system-architecture.md, 02-architecture/data-and-ai.md, 05-due-diligence/assets-dependencies-and-licenses.md, 00-control/terminology-and-ownership.md, 00-control/evidence-ledger.md]
---
# Security, Privacy, and Compliance
<!-- contract: references/package-contract-03-assurance.md#security-privacy-and-compliance -->

The security question for this project is not the usual one. There is no server to attack, no database to exfiltrate, and no session to hijack [EV-0044]. One thing is worth an attacker's attention. **This repository ships shell scripts that a Claude Code client executes on other people's machines** [EV-0040]. It executes them at lifecycle points those people did not invoke. Everything below is organized around that.

Two facts a reader should carry into every section. First, **no dependency-vulnerability scan has ever been run against this repository** — see [No vulnerability scan exists](#no-vulnerability-scan-exists). Second, CodeQL is not that scan. Its matrix analyses `actions` and `python` only, and the repository's shell sits outside every configured language [EV-0134], [EV-0140].

## Scope

This is a documentation assessment. It is not a penetration test, not a code audit, and not a certification exercise.

| Field | Value |
|---|---|
| Systems in scope | This repository at `7ee4923`, its 5 tracked GitHub Actions workflows [EV-0123], its live GitHub settings, the 6 in-tree plugin trees [EV-0058], and the hooks the pinned external plugin registers [EV-0168] |
| Systems explicitly out of scope | The Claude Code plugin client, which this project does not build or control [EV-0043]; the Anthropic API; the `prompt-decorators` tree at pinned sha `9c792fe`, whose contents are not present here (AQ-0005); the `agent-capability-standard` tree beyond its pinned sha `9e2f65b` (AQ-0006) |
| Evidence classes inspected | Tracked source, hook and `bin/` scripts, workflow definitions, dependency manifests, live repository settings, both shell test suites executed, and the resolved action ceiling |
| Evidence classes unavailable | Any dependency-vulnerability scan output [EV-0121]; any observation of the Claude Code client honouring a non-zero hook exit (AQ-0025); Windows execution results (AQ-0008); GitHub audit logs; install telemetry (AQ-0004) |
| Assessment date | 2026-09-10 |
| Assessed against project version | `7ee4923` on `docs/dossier-refresh`, not `main` (AQ-0010). `plugins/` is blob-identical from `af6e632` forward, so the executed suite results describe this tree [EV-0143] |

### What was re-checked at this version, and what was not

| Claim class | Last observed | Evidence |
|---|---|---|
| Test suite results, both plugins, on macOS | 2026-09-10 | [EV-0098], [EV-0107] |
| GitHub Actions conclusions on Linux | 2026-09-10 | [EV-0126] |
| Workflow inventory, and the absence of a docs-refresh workflow | 2026-09-10 | [EV-0123] |
| Marketplace manifest check, existence and executed result | 2026-09-10 | [EV-0080], [EV-0081], [EV-0127] |
| Absence of any vulnerability-scan artifact | 2026-09-10 | [EV-0121] |
| Resolved action ceiling | 2026-09-10 | [EV-0077] |
| Prompt-injection scan over the untrusted evidence bundle | 2026-09-10 | [EV-0120] |
| Artifact counts per plugin | 2026-09-10 | [EV-0129] |
| Branch protection, rulesets, and repository Actions secrets | 2026-09-10 | [EV-0131] |
| CodeQL language matrix, job permissions, and finding count | 2026-09-10 | [EV-0134], [EV-0140] |
| The five dossier security fixes, read at HEAD and exercised | 2026-09-10 | [EV-0145] to [EV-0161] |
| shellcheck coverage of shell scripts | 2026-09-10 | [EV-0165] |
| Commit and tag signing | 2026-09-10 | [EV-0138] |
| Tracked-file secret sweep, and workflow permission scoping for the four non-CodeQL workflows | **2026-07-26** | [EV-0037], [EV-0013] |

Unknown: the two controls in the last row were observed at `06b1586` and were not re-observed at `7ee4923`. AQ-0022 records what remains, and it is now narrow. Branch protection, rulesets and repository secrets were re-read live and had not changed [EV-0131].

## No vulnerability scan exists

This section states an absence. Read it as an absence, not as a result.

| Question | Answer | Evidence |
|---|---|---|
| Does a scan artifact exist? | No. No `.dossier/scan/` directory exists, and no SARIF, osv-scanner or Dependabot artifact is tracked anywhere in the repository | [EV-0121] |
| Why not? | `dossier.engagement.allowedActions.runSecurityScan` resolves false for this repository, so `bin/dossier-scan-security.sh` emits status `disabled` and never invokes a scanner | [EV-0073], [EV-0077] |
| Is a scanner available? | Yes. The dossier refresh CI template defines a separate `scan` job that installs osv-scanner and pyscn. That template is not installed in this repository's workflows | [EV-0075], [EV-0123] |
| Would the release gate call this a pass? | No. Release-gate condition G19 records `INCONCLUSIVE` — never `PASS` — when the ledger holds no vulnerability-scan evidence, and also when a scan artifact cannot be parsed | [EV-0072] |
| Is there a dependency-alerting fallback? | No `dependabot.yml` exists | [EV-0036] |
| Is the code-quality scan any different? | No. `runCodeQualityScan` also resolves false, and `bin/dossier-scan-quality.sh` emits `disabled` on the same terms | [EV-0074], [EV-0077] |

**Nothing here supports any statement about this project's vulnerability status.** The declared dependency surface bounds the exposure. That surface is one package, `pyyaml>=6.0` [EV-0041]. Evidence does not bound it, because none was gathered.

CodeQL is not a substitute, and its scope is now measured rather than assumed. Its matrix analyses `actions` and `python` with `build-mode: none` [EV-0134]. Three analyses across this range each report 0 results, and the repository holds 0 open code-scanning alerts [EV-0140].

Read that as narrow rather than reassuring. Every shell script the marketplace ships sits outside every configured CodeQL language [EV-0140]. Shell static analysis exists in one place only: `dossier-tests.yml` runs shellcheck v0.11.0 over dossier's `bin/` and `hooks/scripts/` [EV-0165]. Flow's 20 `bin/` scripts and 14 hook scripts are unlinted, which AQ-0019 records.

## The action ceiling, and how this package was produced

The action ceiling is this project's own control over what an agent may do in a documentation engagement. It is also a fact about this document's own production, so it belongs here rather than only in the control register.

| Allowed action | Resolved value | Evidence |
|---|---|---|
| `runTests` | true | [EV-0077] |
| `runBuild` | false | [EV-0077] |
| `networkAccess` | false | [EV-0077] |
| `runSecurityScan` | false | [EV-0077] |
| `runCodeQualityScan` | false | [EV-0077] |
| `readSecrets` | false | [EV-0077] |
| `writeOutsideOutputRoot` | false | [EV-0077] |

`runSecurityScan` and `runCodeQualityScan` are absent from `.claude/settings.dossier.json` and fall to their false defaults [EV-0077]. The ceiling was resolved through `bin/dossier-resolve-config.sh`, not by reading a settings file directly.

At least three rows this document cites were observed outside that ceiling. They are the Linux Actions conclusions [EV-0126], the marketplace manifest check result [EV-0127], and the live repository-settings read [EV-0131]. The session operator produced each by running GitHub commands directly. The dispatched collectors could not, because `networkAccess` is false.

Each row names that provenance. AQ-0012 records the open question, with a decision due before the next refresh. Several of this document's strongest claims bypassed the control the document otherwise describes.

## Assets, actors, and trust boundaries

| Asset | Value to an attacker | Where it lives | Protected by | Evidence |
|---|---|---|---|---|
| Write access to `main` | Total. Anything pushed here reaches every installer's machine on their next client sync, as executable code | GitHub | A GitHub account with write access. **Nothing else — no branch protection, no rulesets, no required review, no required checks** | [EV-0131], [EV-0051] |
| flow's 14 hook scripts and dossier's 5 | High. They execute on operator machines with the operator's full privileges, without being invoked | `plugins/flow/hooks/`, `plugins/dossier/hooks/` | Being readable plain text before install. 2336 flow assertions and 1951 dossier assertions, green on both macOS and Linux. shellcheck covers dossier's only | [EV-0129], [EV-0040], [EV-0098], [EV-0107], [EV-0126], [EV-0165] |
| The pinned external plugin's own hooks | High, and easy to miss. `hooks.json` plus a `pretooluse` and a `posttooluse` script live at sha `9e2f65b`, outside this repository | `synaptiai/agent-capability-standard` | Whatever protects that repository. Nothing here | [EV-0168] |
| dossier's 20 `bin/` scripts | Medium. Executed when a command calls them, on the operator's machine | `plugins/dossier/bin/` | Same as above | [EV-0129] |
| `marketplace.json` | High. It controls what every installer resolves and from where | the repository | The marketplace manifest check, which compares every entry's advertised version against its source and runs in CI | [EV-0080], [EV-0081], [EV-0127] |
| The `agent-capability-standard` and `prompt-decorators` sources | High. They reach installers under this marketplace's name with no commit here | external repositories | A pinned `sha` on each entry, which the manifest check requires and verifies | [EV-0058], [EV-0080], [EV-0127] |
| Third-party GitHub Actions | Medium. They execute in this repository's CI, including in the `contents: write` release job | GitHub, third-party | GitHub's tag protections for those orgs. Pinned by major tag, **not by commit SHA** | [EV-0042] |
| Release assets | Low. Desktop skill ZIPs downloaded by Claude Desktop users | GitHub Releases | Write access | [EV-0012] |
| Credentials | No credential matching the project's own detector pattern set appears in tracked files, outside detector definitions and their fixtures | — | — | [EV-0037] |

| Actor | Motivation | Access they start with | Capability assumed | Evidence |
|---|---|---|---|---|
| External researcher | Disclosure | Public read | Can read everything. **Has no private channel to report through** | [EV-0036] |
| Opportunistic supply-chain attacker | Reach operator machines through a trusted-looking plugin | Public read | Could open a pull request. Could not merge it without write access | [EV-0131] |
| Compromised maintainer account | Total control | Write access to `main` | Push directly, bypassing every check, reaching every installer | [EV-0131], [EV-0163] |
| Compromised external plugin source | Reach installers of one plugin, including through hooks that execute unprompted | Write to a different repository | Bounded by the pinned sha, which the manifest check verifies against the advertised version. Moving the pin is a commit here | [EV-0058], [EV-0127], [EV-0168] |
| Malicious content in a repository a plugin reads | Prompt injection against an operator's session | Ability to place text where the operator's agent reads it | Influence model behaviour inside the operator's session | [EV-0097], [EV-0120] |

## Threat model

| Threat | Asset | Actor | Path | Control | Control state | Residual risk | Evidence |
|---|---|---|---|---|---|---|---|
| Malicious hook reaches operator machines | Operator machines | Compromised maintainer account, or a merged malicious change | Push to `main`, client `autoUpdate` sync, hook executes | Code review by convention. Both test suites, green on Linux | **policy-only.** Review is not required, checks are not required, and neither suite would detect malice. They test portability and structure | **High.** One compromised account is sufficient, and no second reviewer exists at any point | [EV-0131], [EV-0163], [EV-0126] |
| Manifest tampering redirects a plugin source | All installers | Same as above | Edit one `source` or `sha` field | The marketplace manifest check, on pull requests, on manifest pushes, weekly, and on demand | **implemented and executed.** 8 plugins checked, 0 failed, 0 unverifiable. It parses no prose, so a stale README passes it | Medium. The check runs, but it is advisory: no status check is required on `main` | [EV-0080], [EV-0081], [EV-0127], [EV-0170] |
| A pinned external source becomes stale rather than wrong | Installers of 2 plugins | not adversarial | A pin stays self-consistent while upstream moves | The manifest check reports staleness rather than failing on it | implemented, with a stated limit | Medium. The pin is verified consistent, never verified current | [EV-0080], [EV-0127], AQ-0006 |
| Third-party action tag is moved | This repository's CI, including a `contents: write` job | Whoever controls the action's repository | `@v4` or `@v3` resolves to a moved tag | none | **not implemented** — no SHA pinning | Low-to-medium. Requires compromising a major GitHub org | [EV-0042] |
| A known vulnerability ships in a dependency | Operator machines | not adversarial, then adversarial | A published advisory against `pyyaml` or a transitive package goes unnoticed | none. No scan, no `dependabot.yml` | **not implemented** | Medium. One declared dependency bounds the surface, but nothing would detect a change to that | [EV-0121], [EV-0036], [EV-0041] |
| Prompt injection through content an agent reads | The operator's session and repository | Anyone who can place text where an agent reads it | Untrusted text is interpreted as instruction | dossier marks untrusted evidence explicitly and passes paths rather than content. flow's hooks block destructive commands and force-pushes at `PreToolUse` | implemented in 2 plugins. The other 4 in-tree plugins state no injection posture | Medium | [EV-0120], [EV-0129], [EV-0058] |
| Credential exfiltration by an agent's own output | The operator's secrets | An injected or mistaken agent | Agent writes a secret into a file, a commit, or a public document | flow's `block-secrets.sh` at `PreToolUse`. dossier's claim scan gates `06-public/**` behind an approved register | implemented in 2 of 8 published plugins | Medium | [EV-0038], [EV-0039] |
| Destructive command executed by an agent | The operator's filesystem and git history | An injected or mistaken agent | `rm -rf`, force-push, history rewrite | flow's `block-destructive.sh` and `block-force-push.sh`, registered at `PreToolUse` | registered, and asserted by the suite. Whether the client honours the exit code is AQ-0025 | Low, for operators who installed flow | [EV-0038] |
| An agent runs a denied action through a disguised spelling | The action ceiling itself | An injected or mistaken agent | Quoting, backslashes, ANSI-C escapes, or a `find` exec-family wrapper | `enforce-allowed-actions.sh` rejects eleven disguised spellings and the four `find` exec-family flags | implemented and executed | **High. Three shell expansion forms are still permitted** — same severity as the gaps table | [EV-0148] to [EV-0153] |
| A published release ships a known runtime defect | Operators who installed at that release | not adversarial | A release is cut before a fix merges | none. Releases are cut on demand with no gate | **not implemented.** v4.9.0 and v4.10.0 both predate `16b4dc4` and carry the pre-fix flow scripts | Medium, bounded to macOS operators | [EV-0144] |
| Test-suite state escapes into the repository | This repository | not adversarial | A suite writes outside its fixture root | dossier's `mktemp` guard aborts a fixture whose scratch directory is invalid | implemented in dossier, 128 guarded call sites. **flow's suite leaked two branches and 3 commits into this repository** | Low for the repository, Medium as a signal about flow's isolation | [EV-0145], [EV-0146], [EV-0147], [EV-0164] |
| Secret committed to this repository | This repository | maintainer error | `git commit` | flow's `block-secrets.sh`, only when flow is active in the session | implemented in-session. **No CI secret scan exists** | Low | [EV-0037], [EV-0038] |
| Shell script fails on the operator's platform | Operator sessions | not adversarial | A bash 4 construct, or a Windows path | Both suites run on macOS locally and on `ubuntu-latest` in CI, and forbid bash 4 constructs | implemented for macOS and Linux. **not implemented for Windows** | Medium — 2 open issues report real failures | [EV-0098], [EV-0107], [EV-0126], AQ-0008 |

## Identity and access controls

| Control | Mechanism | Applies to | Enforcement point | State | Last verified | Evidence |
|---|---|---|---|---|---|---|
| Authentication | GitHub accounts for writes. The operating-system user for execution | maintainer, CI | GitHub, the operator's OS | implemented | 2026-07-26 | [EV-0035] |
| Authorization | GitHub repository write permission | pushes, merges, tags, releases | GitHub | **implemented but ungated.** Write permission alone is sufficient for every operation | 2026-09-10 | [EV-0131] |
| Agent action ceiling | `dossier.engagement.allowedActions`, resolved per repository | agents running dossier engagements here | `bin/dossier-resolve-config.sh` and `enforce-allowed-actions.sh` | implemented. 6 of 7 actions resolve false, and the hook rejects eleven disguised spellings of a denied word | 2026-09-10 | [EV-0077], [EV-0150], [EV-0151] |
| Tenancy separation | N/A | — | — | N/A — the project has no tenants and no server-side identity | — | [EV-0044] |
| Isolation | **None.** Hook and `bin/` scripts run with the operator's full privileges. This project applies no sandbox | operator machines | none | not implemented | 2026-09-10 | [EV-0040], [EV-0129] |
| Session management | N/A | — | — | N/A — the project holds no sessions | — | [EV-0044] |
| Administrative access | GitHub repository admin | branch protection, rulesets, secrets | GitHub | implemented, held by one person. The repository holds 0 Actions secrets | 2026-09-10 | [EV-0131], [EV-0035] |

`Inferred:` every hook described in this document as a control depends on the Claude Code client refusing a tool call when the hook exits non-zero. The chain is the hooks' own exit codes, the suites that assert them, and the client's documented `PreToolUse` contract. No evidence in this package establishes the client's behaviour, and AQ-0025 records that. Read every hook row as *registered to block*, not as *observed blocking*.

## Secrets, keys, and encryption

| Aspect | Practice | Scope it covers | Scope it does not cover | State | Evidence |
|---|---|---|---|---|---|
| Secret storage | No credential matching the project's detector pattern set appears in tracked files | Tracked files, and only the enumerated formats | Untracked files. A fully populated, untracked and gitignored `agent-capability-standard` directory sits in the working tree on the assessment machine | implemented, narrowly | [EV-0037], [EV-0060] |
| Secret distribution | N/A. The only secret the codebase anticipates is an API key in a *consuming* repository that installs dossier's refresh workflow. That workflow is not installed here | — | — | N/A | [EV-0123], [EV-0075] |
| Key management | N/A — no keys are held or issued | — | — | N/A | [EV-0044] |
| Transport protection | HTTPS for all git and API traffic, provided by GitHub | distribution | Anything after the artifact reaches the operator's disk | implemented, inherited | [EV-0051] |
| Storage protection at rest | GitHub's, for a public repository holding public content | hosting | Nothing else, and nothing that matters — the content is public | implemented, inherited, immaterial | [EV-0044] |
| Certificate management | N/A — no certificate is issued or terminated by this project | — | — | N/A | [EV-0044] |
| Rotation | N/A for this repository — nothing to rotate. Where dossier's rotation check does handle a token, it passes a Basic `AUTHORIZATION` header through `GIT_CONFIG_*`, scoped to origin's scheme and host, strips control characters, and never places the token in argv | dossier's own network calls | This repository, which holds no secret | implemented in the plugin, N/A here | [EV-0158], [EV-0131] |
| Artifact signing | Partial, and not by the author. Locally authored commits carry no signature. GitHub's own key signs the squash-merge commits it creates, and those verify as `valid`. No tag is signed, and no release asset carries a provenance attestation | The merge path only | The author's commits, every tag, and every published ZIP | partially implemented | [EV-0138], [EV-0043] |

The secret-scan result is narrower than it reads. It proves that none of the enumerated credential formats appears in tracked files [EV-0037]. It does not prove that no credential exists, and it did not cover untracked files. The working tree carries at least one large untracked directory [EV-0060].

The signing row is the one that matters for a distribution channel. Plugins arrive by a git read performed by the client, with no signature and no checksum [EV-0043]. Signing is a property of the merge path, not of the author [EV-0138]. An installer's only integrity guarantee is GitHub's transport and account security.

## Control layers

| Layer | Controls present | State | Gaps | Evidence |
|---|---|---|---|---|
| Network | HTTPS via GitHub | inherited | Nothing this project controls | [EV-0051] |
| Application | flow's 14 hook scripts, of which `block-destructive.sh`, `block-secrets.sh` and `block-force-push.sh` are restrictive by design. dossier's 5 hook scripts cover output-root containment, the action ceiling, claim registration, header staleness, and local-merge detection | implemented in 2 plugins, plus the pinned external plugin's own two hooks | The other 4 in-tree plugins ship no controls and state no posture | [EV-0129], [EV-0038], [EV-0039], [EV-0166], [EV-0168] |
| Infrastructure | Workflow `permissions` blocks. `marketplace-manifest.yml` declares `contents: read`. `codeql.yml` declares no top-level block, but its `analyze` job scopes to `actions: read`, `contents: read`, `security-events: write` | partially implemented | `release-desktop-skills.yml` is the one workflow requesting `contents: write`, and it still interpolates a release tag name into a `run:` body | [EV-0081], [EV-0134], [EV-0133], CT-0004 |
| Supply chain | 1 declared dependency. 2 third-party action sources. 2 external plugin sources, each pinned to a sha and checked in CI | partially implemented | No SHA pinning of actions. No `dependabot.yml`. **No dependency scanning of any kind** | [EV-0041], [EV-0042], [EV-0058], [EV-0080], [EV-0121], [EV-0036] |
| Endpoint | N/A for the project. The operator's machine is the endpoint and is outside its control | not applicable | The project ships code that runs there and can constrain nothing about it | [EV-0040] |
| Physical | N/A — GitHub-hosted | inherited | — | [EV-0044] |

## Secure development and vulnerability management

| Practice | Current state | Enforced by | Coverage | Evidence |
|---|---|---|---|---|
| Threat modelling | This document is the package's threat model. `.decisions/` holds 21 tracked decision records | nothing | this document only | [EV-0169] |
| Security review in code review | Pull requests are used by habit, but review is not required, and all 214 commits on `main` carry one author identity | nothing | none guaranteed | [EV-0131], [EV-0163] |
| Dependency scanning | **Absent.** No scan artifact, no `dependabot.yml`, no scanning workflow installed | nothing | none | [EV-0121], [EV-0036], [EV-0123] |
| Static analysis, CodeQL | Matrix of `actions` and `python`, `build-mode: none`. Job scope is `actions: read`, `contents: read`, `security-events: write` | `codeql.yml` | **Covers no shell.** All 53 tracked `.py` files sit under `plugins/`, so the language matrix is not vestigial | [EV-0134], [EV-0140] |
| Static-analysis findings | Three analyses across this range, each `results_count` 0. The repository holds 0 open code-scanning alerts | GitHub code scanning | Bounded by the matrix above. A green run and a zero finding count are separate facts, and both are now observed | [EV-0140] |
| Static analysis, shell | shellcheck v0.11.0, pinned by release URL, `-S warning` | `dossier-tests.yml` | dossier's 20 `bin/` and 5 hook scripts only. **flow's 20 `bin/` and 14 hook scripts are unlinted**, and flow's are the blocking `PreToolUse` ones. AQ-0019 | [EV-0165], [EV-0162] |
| Secret scanning | flow's `block-secrets.sh` at `PreToolUse` in a maintainer's session. Neither this nor any equivalent runs in CI | the flow plugin, when active | Session-time only. A commit made without flow active is unscanned | [EV-0037], [EV-0038] |
| Manifest and version validation | The marketplace manifest check, on pull requests, on manifest pushes, weekly at 06:00 UTC Monday, and on manual dispatch | `marketplace-manifest.yml` | Advertised versions and the presence of a `sha` on every external source. It reports a stale-but-consistent pin rather than failing on it | [EV-0080], [EV-0081], [EV-0127] |
| Release-gate handling of missing scan evidence | G19 records `INCONCLUSIVE`, never `PASS`, when no vulnerability evidence exists | `bin/dossier-gate.sh` | 1 of 19 gate conditions | [EV-0072], [EV-0071] |
| Vulnerability triage and SLA | **None defined** | nothing | none | [EV-0036] |
| Patch cadence | Ad hoc, and no gate orders a release against a pending fix. v4.9.0 and v4.10.0 were both published hours before `16b4dc4` merged, so both carry the pre-fix flow runtime scripts | nothing | — | [EV-0144], [EV-0066] |
| Disclosure process | **None.** No `SECURITY.md`, no contact address, no private channel. A researcher's only option is a public issue | nothing | none | [EV-0036] |

The static-analysis rows deserve emphasis. CodeQL passes with 0 findings, which reads as coverage of the project. It analyses no shell [EV-0134], [EV-0140]. Shell is where this project's risk lives, and shellcheck reaches half of it [EV-0165].

### What dossier's hardened controls now reject

Five security fixes merged into the dossier plugin in this range. Each is described below from the script at HEAD and from the shipped test that exercises it, not from its commit message.

| Control | What it rejects now | State | Evidence |
|---|---|---|---|
| Fixture scratch-directory guard | A test fixture whose `RUN_TMPDIR` is unset or not a directory, or whose `mktemp -d` fails, aborts the test process with `exit 2`. 128 guarded call sites across 11 test files. The only bare capture left is inside the guard itself, followed by its own exit-2 check | implemented, 14 of 14 assertions pass | [EV-0145], [EV-0146], [EV-0147] |
| `find` exec-family wrapper | `find` widens the deny scan only when it co-occurs with `-exec`, `-execdir`, `-ok` or `-okdir`. Eight disguised shapes exit 2. A bare `find . -type f -name "*.md"` still exits 0 | implemented and executed | [EV-0148], [EV-0149] |
| Disguised spellings of a denied word | Eleven spellings exit 2: whole-word quoting, leading and mid-word backslash, adjacent single- and double-quote fragments, backslash-newline continuation, ANSI-C octal, hex, 4-digit and 8-digit Unicode escapes, a backslash-disguised wrapper token, and a backslash-escaped `find` with `-exec` | implemented and executed | [EV-0150] |
| Deliberate over-blocks | Two commands a person would call harmless are refused, because dequoting can leave a boundary character beside a denied word. Both are pinned by assertion, so silently removing them fails the suite | implemented by design | [EV-0151] |
| Fail-closed normalization | A command already carrying the script's internal placeholder byte, a 9000-byte command, and a command with 100 ANSI-C spans against a limit of 64 all exit 2. The two size cases return in under 3 seconds | implemented and executed | [EV-0152] |
| Fork-PR hijack in the refresh pipeline | The open-PR lookup selects only same-repository pull requests, passes an explicit `--limit` so the real PR cannot be paginated away, and returns empty rather than a fork decoy's number | implemented and executed | [EV-0154] |
| Failed-lookup honesty | A `gh` lookup that fails reports `existing_pr_lookup_failed=true` and renders as "unknown (lookup failed)", never as a confirmed none. An empty result would otherwise license deleting and recreating the docs branch | implemented and executed | [EV-0155] |
| Guard ordering in the shipped template | The template reads that signal into branch preparation and places the guard strictly before the branch-recreate fallback. It also captures `git rev-list`'s exit status before consuming its output | implemented, asserted by YAML parse rather than by a run | [EV-0156] |
| Rotation-check credential handling | Credentials attach as a Basic `AUTHORIZATION` header through `GIT_CONFIG_*`, scoped to origin's scheme and host. Nothing attaches for an empty token or an SSH origin. Control characters are stripped, and the token never enters argv | implemented and executed against a stubbed `git` | [EV-0158] |
| Disclosure-gate regression detection | The gate's own test now writes its fixture register in place and pins three named scan outputs rather than the exit code alone. No production code changed | test coverage only, 48 of 48 assertions pass | [EV-0160] |

Three shell expansion forms of a denied word are still permitted: brace expansion, default-value expansion and command substitution. Each exits 0 under the all-false ceiling, where the plain and quoted forms exit 2 [EV-0153]. The script documents the class in-file as a tracked residual. This is a live bypass class, and the gaps table carries it. The literal spellings stay in the evidence row.

Two of the five commit bodies describe controls that do not ship. `c5808cc` opens by saying `find` was added to the wrapper list. At HEAD there is no `find` in that list. A later commit inside the same squash replaced that design with the narrower co-occurrence test [EV-0148]. `90b7172` has the same shape.

A squash body's earlier bullet can be superseded by a later one. Reading the subject line yields a wrong description of the control. That is why this package requires a row and not a commit message.

Reported: each of these spellings executed the denied command for real against the pre-fix scripts [EV-0161, R]. The same account says the Unicode-escape gap failed live on CI's Linux bash. The tree carries no pinned pre-fix copy of either script. A failing-before run is therefore not reproducible from it.

Reported: a real GitHub private repository rejects the Bearer spelling of the header [EV-0159, R]. It accepts only the Basic spelling, which is why the shipped form is Basic. The suite's stubbed `git` exercises no HTTP transport, so this cannot be checked here.

The rest of dossier's enforcement surface, unchanged by those fixes:

| Control | What it does now | Evidence |
|---|---|---|
| Action ceiling resolution | `bin/dossier-resolve-config.sh` resolves 7 allowed actions per repository. 6 resolve false here | [EV-0077] |
| Release gate | `bin/dossier-gate.sh` implements 19 conjunctive conditions, G01 through G19 | [EV-0071] |
| Missing-evidence handling | G19 refuses to pass on absent or unparseable vulnerability evidence | [EV-0072] |
| Scan isolation | Security and quality scans live in a separate CI job that installs its own tooling, never in the drafting agent's own shell | [EV-0075] |
| Rotation telemetry | The refresh template declares seven `rotation_*` job outputs, each asserted by the template test. At HEAD nothing consumes them | [EV-0157] |
| Ledger lint | `bin/dossier-ledger-lint.sh` parses only rows inside the evidence table section | [EV-0115], [EV-0116] |
| Local-merge detection | `detect-local-merge.sh` is a `PostToolUse` hook that offers a refresh after a merge-shaped command, gated by a setting | [EV-0166] |

## Logging, detection, auditability, and incident response

| Capability | What is captured | Retention | Who can read it | Tamper resistance | Evidence |
|---|---|---|---|---|---|
| Application logging | N/A — no application runs | — | — | — | [EV-0044] |
| Audit logging | git history, GitHub's audit log, and the Actions run history | GitHub's retention | public for history, admin for the audit log | git history is tamper-evident but **rewritable, because `main` has no protection against force-push** | [EV-0131], [EV-0034] |
| Detection and alerting | CodeQL alerts only, scoped to `actions` and `python`. 0 open alerts | GitHub | maintainer | — | [EV-0140], [EV-0134] |
| Evidence preservation | Actions run logs and release records | GitHub's retention | public | — | [EV-0126], [EV-0066] |
| Incident response | **No process, no owner, no runbook.** Security disclosure handling is `unassigned` and no path is published | — | — | — | [EV-0036] |

**Does sensitive data reach logs?** No. The project runs no service and emits no application log [EV-0044]. Actions run logs are public, and the only data in them is public repository content. The determination rests on the absence of any runtime process, not on a log inspection.

There is no detection capability for the threat that matters. If a malicious hook were merged, nothing in this project would notice. The first signal would be an operator reporting it through a channel that does not exist [EV-0036].

## Data protection and privacy

The project has no user data, no personal-data processing beyond public git metadata, no regulated data of any kind, and no compliance certification. That is stated here so a reader does not have to infer it.

| Data class | Purpose | Legal basis | Consent mechanism | Minimization | Retention | Deletion path | Residency | Evidence |
|---|---|---|---|---|---|---|---|---|
| none | The project collects, stores, and transmits no personal data | N/A | N/A | Complete — there is nothing to minimize | N/A | N/A | N/A | [EV-0044] |
| Contributor identity | git commit metadata: name and email in public history | Necessary to operate a public git repository | Implicit in contributing | git's minimum | indefinite | Rewriting history, which is destructive | GitHub | [EV-0035] |

| Data-subject right | Supported | Mechanism | Time to fulfil | Verified | Evidence |
|---|---|---|---|---|---|
| Access | N/A — no personal data is held beyond public git metadata | — | — | — | [EV-0044] |
| Erasure | Partially, for commit metadata only, and only by rewriting public history | manual | undefined | no | [EV-0034] |
| Portability | N/A | — | — | — | [EV-0044] |

No privacy regulation attaches to this project's own operations, because it processes no personal data [EV-0044]. That is a justified `N/A`, not an uninspected one. What the operator's own Claude Code session sends to Anthropic is governed by the operator's agreement, not by this project [EV-0043].

## Subprocessors and third-party risk

| Party | Function | Data shared | Location | Contractual basis | Assessed | Evidence |
|---|---|---|---|---|---|---|
| GitHub | Hosting, distribution, CI, releases | Public repository content only | GitHub | Standard terms | no | [EV-0051] |
| Anthropic | The Claude Code client that executes every artifact | Nothing by this project. The operator's session data goes to Anthropic under the operator's own agreement | — | The operator's own | no | [EV-0043] |
| `synaptiai/prompt-decorators` | One published plugin, resolved from a `git-subdir` source pinned to sha `9c792fe` | none | GitHub | Same owner | **no** — contents never inspected from here (AQ-0005). The pin is verified consistent with the advertised version | [EV-0058], [EV-0127] |
| `synaptiai/agent-capability-standard` | One published plugin, resolved from a `github` source pinned to sha `9e2f65b` | none | GitHub | Same owner | partially. The pinned tree reports the advertised 1.2.0. What separates that sha from tag `v1.2.0` is unexamined (AQ-0006) | [EV-0058], [EV-0127] |
| `actions/checkout`, `github/codeql-action` | CI steps | Repository contents during a run | GitHub | Open source | no | [EV-0042] |
| `pyyaml` | Runtime dependency of one plugin | none | PyPI | Open source | **no.** No vulnerability scan has ever covered it | [EV-0041], [EV-0121] |

## Applicable requirements

| Requirement | Source | Applicability | Basis for the applicability determination | Compliance state | Evidence |
|---|---|---|---|---|---|
| GDPR and equivalent privacy law | statutory | **Not applicable** to the project's own processing | It processes no personal data. It has no runtime, no accounts, and no store | N/A | [EV-0044] |
| SOC 2, ISO 27001 | contractual | Not applicable | No customer contract exists. The project is an unmonetized public repository. **No certification is held or sought** | N/A | [EV-0044] |
| Open-source licence obligations | statutory | **Applicable and met** | The project distributes source publicly under Apache-2.0. The licence text is at the repository root, and every plugin manifest and marketplace entry declares the same identifier | met as of 2026-07-26 | [EV-0019], [EV-0020], [EV-0021] |
| Apache-2.0 attribution obligations | statutory | Applicable | The whole distribution is Apache-2.0 | met as of 2026-07-26 | [EV-0019], [EV-0021] |

No regulatory applicability above was assumed from the project's category. Each rests on the absence of a runtime and of personal data [EV-0044].

## Control evidence and test dates

| Control | Last tested | Tested by | Method | Result | Next due | Evidence |
|---|---|---|---|---|---|---|
| flow hook and script behaviour, macOS | 2026-09-10 | this assessment | `plugins/flow/tests/run.sh` | 2336 pass, 0 fail, exit 0 | on change | [EV-0098] |
| dossier hook and script behaviour, macOS | 2026-09-10 | this assessment | `plugins/dossier/tests/run.sh` | 1951 pass, 0 fail, exit 0 | on change | [EV-0107] |
| Both suites plus CodeQL, Linux | 2026-09-10 | the session operator, outside the action ceiling (AQ-0012) | GitHub Actions run history | All six runs `conclusion: success` | every merge | [EV-0126] |
| Marketplace manifest check | 2026-09-10 | the session operator, outside the action ceiling (AQ-0012) | `scripts/check-plugin-versions.sh` | 8 plugins, 0 failed, 0 unverifiable, exit 0 | on manifest change and weekly | [EV-0127] |
| Prompt injection in the untrusted evidence bundle | 2026-09-10 | this assessment | Pattern scan over all 11 untrusted files | 2 hits, both descriptive prose, neither a directive | every refresh | [EV-0120] |
| Dossier configuration validity | 2026-09-10 | this assessment | `bin/dossier-validate-config.sh` | pass, 0 findings | on config change | [EV-0086] |
| The five dossier security fixes | 2026-09-10 | this assessment | 6 shipped suites, `mktemp-guard`, `hooks`, `dossier-policy`, `workflow-template`, `rotation-check`, `disclosure-gate` | all passing | on change to any hardened script | [EV-0147], [EV-0149] to [EV-0152], [EV-0154], [EV-0156], [EV-0158], [EV-0160] |
| CodeQL findings | 2026-09-10 | not recorded in the check row | Code-scanning analyses and alerts, read through the GitHub REST API | 3 analyses, `results_count` 0 each, 0 open alerts | every merge | [EV-0140] |
| Branch protection, rulesets, Actions secrets | 2026-09-10 | the session operator, outside the action ceiling (AQ-0012) | GitHub REST reads | **404 not protected**, empty rulesets, 0 secrets | on settings change | [EV-0131] |
| Commit and tag signing | 2026-09-10 | this assessment | `git log --format=%G?` and the REST verification field | Author commits unsigned, GitHub merge commits `valid`, tags unsigned | on release | [EV-0138] |
| Vulnerability scan | **never** | — | — | **not executed.** `runSecurityScan` is false | before any release claim | [EV-0121], [EV-0073] |
| Code-quality scan | **never** | — | — | not executed. `runCodeQualityScan` is false | — | [EV-0074] |
| No credentials in tracked files | 2026-07-26 | the July baseline | `git grep` over the project's own detector pattern set | no match outside detector definitions and fixtures | every commit | [EV-0037] |
| Workflow permission scoping, the 4 non-CodeQL workflows | 2026-07-26 | the July baseline | YAML parse of the workflows then present | 3 of 4 scoped at that commit | on workflow change | [EV-0013], AQ-0022 |
| Untrusted interpolation in a workflow `run:` body | 2026-09-10 | this assessment | Read of `release-desktop-skills.yml` at HEAD | **still present** — the release tag name is interpolated directly | on workflow change | [EV-0133], CT-0004 |
| `agent-capability-standard` Python suite | never | — | — | not executed (AQ-0001) | — | [EV-0011] |
| Hook behaviour on a live operator machine | never | — | — | never observed. Whether a non-zero exit blocks a tool call is unestablished (AQ-0025) | — | [EV-0040] |
| Windows execution | never | — | — | not executed (AQ-0008) | — | AQ-0008 |

## Gaps

| Gap | Severity | Likelihood | Impact | Affected assets | Remediation | Owner | Evidence |
|---|---|---|---|---|---|---|---|
| **No vulnerability scan has ever been run** | **High** | Certain — it is a present-state fact | Nothing in this package supports any statement about the project's vulnerability status. The release gate correctly refuses to pass on it | Supply chain, every operator machine | Enable `runSecurityScan`, or install the refresh template's `scan` job, or add `dependabot.yml` | Daniel Bentes | [EV-0121], [EV-0073], [EV-0072], [EV-0036] |
| No gate on `main`: no protection, no rulesets, no required checks, no required review | **High** | Medium | Any change reaches every installer's machine as executable code, with no check having to pass. Every green workflow is advisory | Every operator machine | Enable branch protection requiring both test workflows and the manifest check | Daniel Bentes | [EV-0131], [EV-0126] |
| No security disclosure channel | **High** | Medium | A researcher who finds a flaw in a hook that runs on operator machines must disclose publicly or not at all | Every operator machine | Add `SECURITY.md` with one contact address | Daniel Bentes | [EV-0036] |
| **Three shell expansion forms bypass the action ceiling** | **High** | Medium | Brace expansion, default-value expansion and command substitution each pass the hook that rejects eleven other disguises. The control reads as comprehensive and is not | The action ceiling, on any machine running a dossier engagement | Extend the normalizer to those three forms, or state the residual in the hook's own operator-facing output | Daniel Bentes | [EV-0153], [EV-0150] |
| flow's shell is not statically analysed | Medium | Medium | shellcheck covers dossier's 25 scripts. flow's 34 are unlinted, and flow's hooks are the blocking `PreToolUse` ones | flow's `bin/` and hook scripts | Add the same shellcheck step to `flow-tests.yml` | Daniel Bentes | [EV-0165], [EV-0162], AQ-0019 |
| Both published releases carry known runtime defects | Medium | Certain | v4.9.0 and v4.10.0 were cut hours before the fix merged, so an operator installing today gets the pre-fix flow scripts | Operators on macOS | Cut a release, or state the defect on the existing ones | Daniel Bentes | [EV-0144] |
| Hook blocking is assumed, not observed | Medium | Certain | Every hook-based control in this document rests on the client refusing a tool call on a non-zero exit, and nothing establishes it | The whole control-point argument | One observed hook rejection, or a citation to client documentation | Daniel Bentes | AQ-0025 |
| flow's test suite leaks state into the repository | Low | Certain | Two branches and 3 commits authored by a test identity reached this repository. The branches were deleted; the suite defect was not fixed | This repository, and any repository running flow's suite | Scope the suite's git fixtures to a scratch root, as dossier's `mktemp` guard does | Daniel Bentes | [EV-0164], [EV-0146] |
| Two evidence rows were observed outside the action ceiling | Medium | Certain | The package's two strongest CI claims did not come through the control the package describes | This package's own integrity | Decide whether to raise `networkAccess` for read-only reads, or to accept operator-observed rows as a distinct class | Daniel Bentes | AQ-0012, [EV-0126], [EV-0127] |
| External pins are verified consistent, never verified current | Medium | Medium | A stale pin ships to installers and the check reports rather than fails | Installers of 2 plugins | Decide whether staleness should fail the check | Daniel Bentes | [EV-0080], [EV-0127], AQ-0006 |
| Third-party actions pinned by tag, not SHA | Medium | Low | A moved tag executes in CI, including in the `contents: write` release job | This repository's CI | Pin to commit SHAs | Daniel Bentes | [EV-0042] |
| Four of six in-tree plugins have no tests and state no security posture | Medium | Medium | A change to them is unverified by anything, including their structural validity | Installers of those 4 | Add a structural suite per plugin | Daniel Bentes | [EV-0010], [EV-0058] |
| Windows portability is unmeasured | Medium | Medium | Two open issues report real failures, and no CI job runs on Windows | Windows operators | Add a `windows-latest` job to both test workflows | Daniel Bentes | AQ-0008 |
| Two July-observed checks were not re-run at `7ee4923` | Low | Certain | The tracked-file secret sweep and the workflow-permission scan for the four non-CodeQL workflows are carried forward from the July tree | This assessment's currency | Re-run both at HEAD | Daniel Bentes | AQ-0022, [EV-0037], [EV-0013] |
| `release-desktop-skills.yml` interpolates event data into a `run:` body | Low | Low | Injection via a release tag name, in the one workflow holding `contents: write`. It requires release-publishing access, so an attacker who could do it already has more direct paths. The repository fails a rule it ships to others | CI | Bind to `env:` and reference the variable | Daniel Bentes | [EV-0133], CT-0004 |
| No commit or tag is signed by the author | Low | Low | Signing is a property of GitHub's merge path only. An installer cannot attribute a tree to the maintainer | The distribution channel | Enable commit signing and sign release tags | Daniel Bentes | [EV-0138] |

## Control state summary

| Control state | Count | Notes |
|---|---|---|
| Implemented and evidenced by an executed check | 14 | Both test suites [EV-0098], [EV-0107], [EV-0126]. The marketplace manifest check [EV-0127]. CodeQL, matrix-bounded [EV-0134], [EV-0140]. shellcheck over dossier [EV-0165]. Nine hardened dossier controls [EV-0145] to [EV-0158] |
| Registered to block, blocking behaviour unobserved | 5 | flow's `block-destructive.sh`, `block-secrets.sh` and `block-force-push.sh` [EV-0038]. dossier's output-root containment and its action ceiling hook [EV-0129], [EV-0077]. Each is asserted by its suite. Whether the client honours a non-zero exit is AQ-0025 |
| Implemented, evidenced by a file read rather than a run | 4 | Release gate G01–G19 [EV-0071]. G19's inconclusive handling [EV-0072]. Scan isolation in the CI template [EV-0075]. Guard ordering in that template [EV-0156] |
| Test coverage improved, control unchanged | 1 | The disclosure-gate fix changed no production code. It made the suite able to detect a regression it previously passed through [EV-0160] |
| Policy-only — documented, implementation not evidenced | 3 | Code review, commit and branch conventions, and the flow/gh-workflow coexistence rule. Each is stated in `.claude/CLAUDE.md` and enforced by nothing [EV-0131], [EV-0163] |
| Planned | 0 | No evidence row in this package records committed security work. The remediations below are proposals, not schedule [EV-0169] |
| Unknown | 5 | Whether a non-zero hook exit blocks a tool call (AQ-0025). The four in-tree plugins that state no posture [EV-0010]. Windows behaviour (AQ-0008). Hook behaviour on a live operator machine [EV-0040]. The `prompt-decorators` contents (AQ-0005) |
| Not implemented | 5 | Dependency scanning [EV-0121]. Author-side signing [EV-0138]. Action SHA pinning [EV-0042]. Any merge gate on `main` [EV-0131]. Coverage of three expansion spellings by the action ceiling [EV-0153] |

## Recommendations

Recommendation: run one vulnerability scan before this package is used to support any security decision. Until then, the honest statement is that the project's vulnerability status is unknown [EV-0121].

Recommendation: extend the action ceiling's normalizer to brace expansion, default-value expansion and command substitution. Three spellings pass a hook that rejects eleven others [EV-0153].

Recommendation: add `SECURITY.md` with one contact address. It is the cheapest of the three High gaps and the only one an external party depends on [EV-0036].

Recommendation: enable branch protection on `main` requiring both test suites and the manifest check. All three are green and all three are advisory [EV-0126], [EV-0131].

Recommendation: run shellcheck over flow's `bin/` and hook scripts in `flow-tests.yml`, on the same terms `dossier-tests.yml` already uses [EV-0165].

Recommendation: settle AQ-0012 before the next refresh. Either raise `networkAccess` for read-only GitHub queries, or record operator-observed rows as a named class in the ledger schema.

Recommendation: settle AQ-0025 before the next refresh. Every hook-based control in this document rests on an unestablished client behaviour.

None of the above is implemented. Each is a proposal.

## Public claims and prohibited disclosures

| Safe to state publicly | Scope it holds within | Claim ID |
|---|---|---|
| Plugins run inside the operator's own Claude Code session. The marketplace operates no service and collects no telemetry | The marketplace itself, not the client or the model provider | CL-0007 |
| Three plugins register hooks — shell scripts the client runs on the operator's machine at defined lifecycle points | All 8 published plugins | CL-0008 |
| The only declared third-party runtime dependency is `pyyaml` | Declared dependencies, not what the client itself requires | CL-0009 |
| No credential matching the project's own detector pattern set appears in any tracked file | Tracked files, enumerated patterns. **Must ship with that qualification** | CL-0016 |
| The `main` branch carries no branch protection and no rulesets | Live repository settings, as read 2026-07-26 | CL-0013 |
| The repository publishes no security policy and no private disclosure channel | Current state | CL-0015 |
| The marketplace holds no personal data — no accounts, no server, no database | The marketplace itself | CL-0019 |
| Hooks execute without the operator invoking them, with the operator's privileges, with no sandbox | The hook mechanism. **Must ship adjacent to the hook inventory** | CL-0020 |

**No approved claim covers the vulnerability-scan position.** A public statement that this project has no known vulnerabilities would be false. No scan has run [EV-0121]. Publishing the absence itself needs a new `CL-` row, which is not proposed here.

| Must not be disclosed | Why |
|---|---|
| The literal spellings the action ceiling permits [EV-0153] | An exploitation condition against a control that ships to operators. The class is named in this document; the spellings stay in the evidence row and in the script's own in-file note |
| Any characterization of a hardened control taken from a commit message | Two of the five commit bodies in this range describe controls that do not ship [EV-0148]. A public sentence built on one would be false |
| Everything else in this document may be disclosed | The disclosure policy for this engagement is `public`, the repository is public, and every other fact above is independently checkable. Publishing the controls while withholding the gaps would misrepresent the posture, which is the failure mode this documentation standard exists to prevent |
