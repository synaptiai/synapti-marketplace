# Changelog

## 2.3.1 (2026-05-08)

### Bug fixes

- **Plugin settings cascade unified to standard Claude Code precedence (#101).** Originally reported as "Path A paired-reviewer gate unreachable for marketplace installs": `commands/review.md`'s `agentTeams` gate read `${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json` only, and `CLAUDE_PLUGIN_ROOT` is not exported into the bash subshell that runs the gate, so the fallback resolved to a directory that doesn't exist in the user's repo. The same broken single-source pattern was present in five other consumer sites (`commands/merge.md`, `commands/status.md`, `bin/journal-record.sh`, three hook scripts, and `agents/convention-checker.md`).

  The original threat model justifying the "trimmed cascade" — a hostile fork PR committing `.claude/settings.flow.json` to escalate gates after `gh pr checkout` — was overengineered. Claude Code's standard convention is to honor the full settings cascade and let reviewers see settings changes in the PR diff like any other repo file. The fix replaces the trimmed-cascade pattern with the standard Claude Code precedence (highest first):

  1. `.claude/settings.flow.local.json` — project-local, gitignored (your machine-local pin)
  2. `.claude/settings.flow.json` — project-shared, committed (team defaults)
  3. `$HOME/.claude/settings.flow.json` — user-global, cross-project default
  4. `${CLAUDE_PLUGIN_ROOT}/settings.json` — plugin default

  First non-empty value wins. Applies uniformly to every flow setting — no special-cased exclusion for any key.

  Files updated: `commands/review.md` (agentTeams gate), `commands/merge.md` (markerTrust gate), `commands/status.md` (markerTrust + journal.dir), `commands/learn.md` (journal.dir + learning.proposalDir), `commands/explain.md` (journal.dir), `agents/convention-checker.md` (conventions.commitTypes), `bin/journal-record.sh` (journal.dir), `hooks/scripts/{log-commits,log-file-changes,session-end-learn}.sh` (journal.dir + learning.enabled).

  The two-key gate for `agentTeams` is preserved at the env-var layer: enabling Path A still requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set in the user's shell on top of `agentTeams: true` from any source. The env var alone (no `agentTeams: true` anywhere) cannot enable Path A.

  `agentTeams` gate gained a three-state diagnostic distinguishing (a) plugin not installed, (b) `CLAUDE_PLUGIN_ROOT` set but pointing at a missing path, (c) all four cascade files exist but none sets the key. Each variant names the exact paths checked.

  `merge.md` and `status.md` markerTrust gates now surface JSON parse errors per-source (matching the agentTeams gate pattern) — `WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: ...)` rather than silently swallowing parse errors and treating them identically to "key absent."

- **`commands/setup.md` rewritten to align with the standard cascade.** Previous setup wrote `agentTeams` and `conventions.commitTypes` into the project-shared file but then those keys were excluded by the trimmed-cascade pattern. With the cascade unified, all flow keys are valid in `.claude/settings.flow.json` and team-shareable. Phase 2 now writes the full default set including `agentTeams: false`, `conventions.commitTypes`, `merge.markerTrust.allowedAssociations`, `journal.dir`, and `learning.proposalDir`. Phase 6 summary describes the four-tier override hierarchy users can use to customize.

- **`${HOME:-/nonexistent}` defensive default** applied at every USER_SETTINGS construction site (15+ loops across .md commands, .sh hooks, and bin/ scripts). Catches `set -u` / `env -i` invocations where `$HOME` could otherwise abort the gate with "unbound variable" instead of degrading to the safe "user-tier file does not exist" path.

### Documentation

- `references/gate-configuration.md` — replaced the "Trimmed-Cascade Settings Keys" section with a "Settings Cascade" section documenting the standard four-tier precedence. The `merge.markerTrust.allowedAssociations` row in the gate config table updated. New worked examples for "Persistent personal opt-in" (using `.local.json` or `$HOME`) and "Team-wide opt-in" (using committed `.json`).

### P3 cleanup (cycle 2 review pass — pre-merge)

Address the P3 findings raised during the cycle-2 self-review before landing:

- **F4/ERR-8 — `agentTeams: null` semantic.** A user writing `"agentTeams": null` likely means "use the default", not "definitively no". The gate now treats `null` as absent (falls through to next source) rather than triggering the `non-canonical value` WARN. New test S7b verifies this.
- **F5 — gate-configuration.md ordering inconsistency.** The "Settings File Locations" section listed cascade with plugin first / local last; the new "Settings Cascade" section uses highest-first ordering. Aligned both to the highest-first form so the document is internally consistent.
- **F6 — three-state diagnostic gap.** When `CLAUDE_PLUGIN_ROOT` was set to a missing path AND user-tier files existed without the key, the gate fell into the catchall message and never named the broken plugin root. Now tracks `PLUGIN_ROOT_BROKEN` explicitly and emits a WARN naming the path even when user-tier files are present. New test S9 verifies this.
- **SEC-1 — high-risk markerTrust values warn at gate time.** When the resolved trust list contains `NONE`, `FIRST_TIMER`, `FIRST_TIME_CONTRIBUTOR`, or `MANNEQUIN`, the gate emits `LEDGER_WARN: trust list ... includes high-risk values [...]` on stderr at every merge attempt. PR-diff visibility remains the primary defense; the WARN raises the signal so a maintainer cannot accidentally miss it. New test S4b verifies this.
- **SEC-3/ERR-6 — `journal.dir` path-traversal warn.** When the resolved `journal.dir` contains `..` path segments, `bin/journal-record.sh` emits a WARN to stderr. Defense-in-depth — the cascade visibility is the primary defense, but a `journal.dir: "../../tmp/x"` value would silently write artifacts outside the repo without this WARN.
- **ERR-5 — `gh api` exit-code coverage in `commands/merge.md`.** The untrusted-counting `gh api` calls didn't capture their exit codes via `${PIPESTATUS[0]}`. A network blip during those secondary calls would silently treat as "no untrusted markers" rather than failing closed. Now captures `GH_EXIT_RES_U` and `GH_EXIT_REV_U` and includes them in the fail-closed condition.
- **ERR-9 — `commitTypes` array type-check.** `agents/convention-checker.md` previously crashed jq's `join("|")` step if `commitTypes` was a non-array (e.g., string typo). Now wraps in `if type == "array" then join("|") else empty end` so non-array values silently fall through to the next cascade source.
- **ERR-4 — extracted shared cascade-resolve helper.** New `plugins/flow/bin/cascade-resolve.sh` (with 12 regression tests at `tests/cascade-resolve/test.sh`) reads any settings key from the standard cascade with parse-error WARN surfacing on stderr. Refactored 9 simple cascade-loop sites (3 markdown commands, 1 agent, 1 bin script, 3 hook scripts, 1 hooks site reading two keys) to call the helper. The 2 security-critical gate sites (`commands/review.md` agentTeams gate, `commands/merge.md` markerTrust gate) keep their inline implementations because they need source-tracking and specialized boolean handling. Removes the diagnostic asymmetry where 9 sites silently swallowed parse errors via `2>/dev/null` while the gate sites surfaced them.

### Self-review fix-forward (cycle 2 review pass)

- **P1 — `commands/merge.md` markerTrust fall-through emitted `FINDING_LEDGER_BLOCK:` on stdout.** When one tier had an invalid `markerTrust.allowedAssociations` (e.g., empty array) AND the gate fell through to a valid lower tier with a working trust list, the gate still printed `FINDING_LEDGER_BLOCK:` on stdout. The downstream merge gate scans stdout for that prefix and would treat this as a hard block — even though the cascade fall-through resolved a valid trust list. Fixed: emit `LEDGER_WARN:` on stderr instead of `FINDING_LEDGER_BLOCK:` on stdout when fall-through succeeds. The `FINDING_LEDGER_BLOCK:` prefix is now reserved for cases where the merge gate genuinely cannot proceed (gh API down, ESCALATED markers, untrusted-only markers).
- **P2 — `commands/review.md` agentTeams gate used `jq -r`** which strips JSON string quotes. A typo like `{"agentTeams": "true"}` (quoted string instead of boolean) would silently match the `case true)` arm and enable Path A. Fixed: use `jq -c` so the quoted string remains `"true"` and routes to the catchall `*)` WARN. Updated test S8 verifies this.
- **P2 — `commands/setup.md` did not add `.claude/settings.flow.local.json` to `.gitignore`.** A downstream user running `/flow:setup` in a fresh repo would create their personal-pin file at the documented location and have it staged for commit by default — defeating the cascade's "project-local is gitignored, your machine-local pin" property. Fixed: setup now appends the entry to `.gitignore` (idempotent — only if missing).
- **P2 — `commands/setup.md` could silently override user-global preferences.** Under the unified cascade, project-shared overrides user-global. Setup writing `agentTeams: false` (or any other key matching the plugin default) would silently override a user's `$HOME/.claude/settings.flow.json` preference. Fixed: setup reads user-global first and surfaces conflicts via `AskUserQuestion` before writing, with three options (skip the key / write team baseline anyway / cancel).

### New regression tests

- `tests/agentteams-gate/test.sh` (new, 20 assertions) extracts the gate body from `commands/review.md` via `# AGENTTEAMS_GATE_BEGIN` / `# AGENTTEAMS_GATE_END` markers and runs it against scenarios for: marketplace install with `$HOME` override, upgrade survival, project-tier overrides plugin default (S3), project-local overrides project-shared (S3b), full precedence chain (S3c), three-state diagnostic, malformed-HOME fall-through, env-var double-key requirement, and JSON-string vs boolean coercion (S8). The harness runs `bash -n` against the extracted body so a corrupted END marker FATALs instead of silently partial-eval'ing.
- `tests/markertrust-gate/test.sh` (new, 15 assertions) covers the same scenarios for `merge.markerTrust.allowedAssociations`, including project-local-overrides-project-shared precedence and the empty-array fall-through. S4 specifically asserts the gate emits `LEDGER_WARN` on stderr (not `FINDING_LEDGER_BLOCK` on stdout) when an invalid array falls through to a valid lower tier. S4b verifies the high-risk-trust-value WARN.
- `tests/cascade-resolve/test.sh` (new, 12 assertions) verifies the four-tier cascade behavior, parse-error WARN surfacing, default-value handling, and compact-vs-raw output mode of the new `bin/cascade-resolve.sh` helper.

### Test totals

110 assertions across 9 suites (was 89 in 2.3.0). The cycle-2 cascade work added two new gate-test suites (24 + 15 = 39 assertions) and the new cascade-resolve test suite (12 assertions); the older suites kept their counts.

## 2.3.0 (2026-05-06)

### Post-review hardening — cycle 2 (PR #99 `/flow:review` second pass)

A second adversarial review (parallel `code-reviewer` + `security-reviewer` + `convention-checker` + cross-reference auditor) found four reproducible exploit primitives the cycle-0 and cycle-1 passes missed, all post-`gh pr checkout`-of-hostile-fork. Reproduced inline; fixes shipped here.

- **SEC-1: sys.path injection (RCE).** `python3 -c "import yaml"` and `python3 - <<'PYTHON'` heredocs in `bin/journal-record.sh`, `bin/promote-proposal.sh`, and `bin/validate-skill-input.sh` had `sys.path[0] = ''` (CWD). After `gh pr checkout` of a hostile fork, an attacker-shipped `./yaml.py` (or `./jsonschema.py`) at the repo root would shadow the real package on import — full RCE under the user's UID before any of our other defenses ran. Fix: `export PYTHONSAFEPATH=1` near the top of each script (Python 3.11+ honors the env var), plus a defensive `sys.path[:] = [p for p in sys.path if p not in ("", ".")]` filter inside every inline heredoc as a fallback for older Pythons.
- **SEC-2: journal-file symlink read (file exfiltration).** Cycle 1 added `[ -L "$LOCKFILE" ]` defense on the lockfile but the journal file itself was opened with Python's `open()`, which follows symlinks. Attacker pre-stages `.decisions/issue-N.md` → symlink to `~/.ssh/id_rsa` (or `~/.aws/credentials`, `~/.config/gh/hosts.yml`); user runs `/flow:start N`; secret content is read into the new journal body and committed/pushed. Fix: read via `os.open(O_RDONLY | O_NOFOLLOW)` in the inline Python block — open fails atomically with ELOOP if the path is a symlink.
- **SEC-3: hook symlink append (file tampering).** `hooks/scripts/log-commits.sh` and `log-file-changes.sh` write auto-log lines via `>> "$JOURNAL_FILE"`; bash `>>` follows symlinks. Attacker pre-stages `.decisions/issue-N.md` → symlink to `~/.bashrc` or any user-writable file; PostToolUse fires after every Edit/Write/git-commit Claude makes; each invocation appends `<!-- auto-log: ... -->` to the symlink target. Fix: `[ -L "$JOURNAL_FILE" ] && exit 0` before each `>>` redirect in both hooks.
- **F1: lockfile TOCTOU (regression in cycle-1 fix).** The cycle-1 lockfile defense was `[ -L "$LOCKFILE" ]` followed by `exec 9>"$LOCKFILE"` — a TOCTOU window an attacker could exploit by planting a symlink between the check and the redirect. Fix: move the lockfile open into Python and use `os.open(LOCKFILE, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)` for atomic ELOOP rejection; use `fcntl.flock` on the resulting fd. The bash-layer `[ -L ]` check is now redundant and removed.

Defense-in-depth and quality fixes shipped alongside:

- **SEC-7: HTML-comment injection via attacker-controlled commit subject.** `hooks/scripts/log-commits.sh` interpolated `$LAST_MSG` (latest commit subject from a hostile fork) into an `<!-- auto-log: ... -->` comment. A subject containing `-->` would close the comment early; subsequent markdown would land in the journal that `/flow:explain` and `/flow:review` later feed back to Claude — prompt injection. Same pattern in `log-file-changes.sh` for `$TOOL_NAME` and `$FILE_PATH`. Fix: substitute `-->` → `-- >` and `<!--` → `< !--` before embedding in both hooks.
- **SEC-5: `bin/promote-proposal.sh` dangling-symlink write.** `[ -e "$TARGET" ]` follows symlinks, so a *dangling* attacker-pre-staged symlink at `plugins/flow/skills/learned/<name>/SKILL.md` passes the existence check; subsequent `cp` writes through to an arbitrary user-writable path. Fix: explicit `[ -L "$TARGET" ]` check before the existence check, refusing both states.
- **SEC-8: YAML newline injection in journal metadata.** `bin/journal-record.sh --metadata key=$'value\nline2'` would let `yaml.safe_dump` emit a multi-line block scalar; with a `:` in the value, downstream readers could re-parse as multiple keys. Fix: bash-level `case` to reject newline/CR in metadata pairs at parse time, with a corresponding regression test.
- **F1 atomic-write durability (related).** Added `f.flush() + os.fsync(f.fileno())` before `os.rename` and a best-effort directory `os.fsync` after, so a power loss between rename and durable write cannot leave a zero-length journal behind. Comment updated to match.
- **F2: `runtime-verification` documentation orphan.** `visualVerification.maxIterations` was documented in both `runtime-verification/SKILL.md` and `visual-verification/SKILL.md`. Removed from the runtime skill (which delegates to visual when both run together); single source of truth restored.
- **F4: trimmed-cascade keys not documented.** Added a "Trimmed-Cascade Settings Keys" subsection to `references/gate-configuration.md` listing `journal.dir`, `learning.proposalDir`, and `conventions.commitTypes` with their threat models — the same treatment `merge.markerTrust` already had.
- **F6: `commands/status.md` cascade-coverage gap.** `JOURNAL_DIR` was hardcoded `.decisions`. Now reads the same trimmed cascade as the other eight consumers; users with a non-default `journal.dir` will see correct counts.

### New regression tests (cycle 2)

- `tests/journal-orchestration/test.sh` grew 16 → 22 assertions covering SEC-1 (attacker yaml.py at CWD does not load), SEC-2 (journal symlink rejected with secret-content non-leak verified), SEC-8 (newline metadata rejected), and F1 (lockfile symlink rejected atomically).
- `tests/hooks-symlink/test.sh` (new, 6 assertions) covers SEC-3 (both hooks refuse symlink writes; symlink target content unchanged) and SEC-7 (`-->` neutralized in commit subject before journal embedding).

### Test totals

89 assertions across 8 suites (cycle 0: 75; cycle 1: 77; cycle 2: 89). All pass. The cycle-2 totals replace earlier "75" and "77" references in the PR body.

### New helper scripts (`plugins/flow/bin/`)

- `flow-escalate.sh` — CLI utility that formats canonical six-field Proactive-Autonomy escalations (Situation, What I tried, Options, Recommendation, Time sensitivity, Risk) per `references/escalation-format.md`. Output is a markdown body suitable for `AskUserQuestion`. Validates required fields and option grammar (`<n>: <text>`); exits 0/1/2 with clear stderr. Available for ad-hoc human use; commands continue to inline the escalation prose so the structure stays inspectable in each command body.
- `validate-skill-input.sh` — validates a skill's input payload against its JSON Schema at `${CLAUDE_PLUGIN_ROOT}/schemas/<name>/input-schema.json` (schemas ship inside the plugin payload so end-users get them at install time; `tests/skills/<name>/` continues to hold the test fixtures only). Tries `import jsonschema` for full Draft-07 validation; falls back to a shape-check (required, types, enums, patterns, minItems, minLength) implemented in the standard library so the script works on any Python 3.x install. Exits 0 (valid), 1 (validation failure with path + reason), or 2 (infrastructure error).
- `journal-record.sh` — atomically updates the YAML frontmatter manifest in `.decisions/issue-{N}.md` with a new artifact entry (specification, stranger-test, review-cycle, dropped-finding, design-decision, brainstorm-decision, verdict, escalation-resolved). Idempotent across runs; preserves legacy bodies when the journal lacks a manifest. Atomic via temp file + rename.
- `promote-proposal.sh` — promotes a `/flow:learn` proposal to an active skill at `plugins/flow/skills/learned/{name}/SKILL.md` via a **draft** PR. Validates frontmatter (required fields, status=proposal, kebab-case name) and body sections (`## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist`). Tier 2 by design: opens a draft PR and never marks it ready or merges. `--dry-run` flag for non-mutating validation.

### New repo-level test suites

- `tests/skills/holdout-validation/`, `tests/skills/criterion-verification-map/`, `tests/skills/specification-capture/` — six assertions per skill (valid input, invalid input, missing required, non-JSON input, edge-case validation), plus an extra trailing-newline regression test on `holdout-validation` that pins the `(?!\n)$` anchor in the ID pattern. 19 total; all pass.
- `tests/finding-schema/` — 14 assertions (7 valid fixtures + 7 invalid, the latter including a trailing-newline ID rejection) covering the canonical finding row shape (ID grammar, priority/confidence/disposition enums, required fields). Catches drift between `references/finding-schema.md` and the actual rows reviewer agents emit.
- `tests/status-parser/` — 10 assertions verifying that `status.md`'s ledger parser stays in lockstep with `merge.md`'s parser across legacy 5-field, extended 7-field, mixed-cycles, and review+resolution markers. Includes hostile-ID and malformed-priority rejection tests that mirror the production ID grammar.
- `tests/journal-orchestration/` — 16 assertions exercising the full `bin/journal-record.sh` lifecycle for a synthetic issue. Covers all 9 documented artifact types, manifest top-level fields, captured_at presence, type-order preservation, per-type required-field assertions, and append-on-rerun (multi-cycle review-cycle entries).

### New canonical reference documents

- `references/skill-contracts.md` — explains what JSON Schema input contracts exist, the validator strategy (jsonschema if installed, shape-check fallback), the test-fixture convention, and how to add a contract for a new skill.
- `references/decision-journal-schema.md` — extended with the **YAML frontmatter manifest schema**. Documents the required top-level fields, the artifact-type vocabulary (specification, stranger-test, review-cycle, dropped-finding, etc.), per-type required metadata, compatibility with the legacy structured-entry format, and the tradeoff between YAML and JSON for the manifest.

### Tier classification (gate 19 of the plan)

Every command in `plugins/flow/commands/` now carries a `## Tier Classification` section at the bottom listing the actions it takes and the tier for each (1 = autonomous, 2 = journaled, 3 = confirm). Coverage: 17/17 commands. `grep -L "^## Tier Classification" plugins/flow/commands/*.md` returns nothing.

### Frontmatter sweeps

- `disable-model-invocation: true` added to `pr-lifecycle/SKILL.md` and `preflight-checks/SKILL.md` (matching the existing flag on `merge-and-release/SKILL.md` and `team-coordination/SKILL.md`). All four reference-only skills now disable autonomous invocation by the model — they are policy documents consumed by commands, not skills the orchestrator invokes on its own.
- `paths:` declarations added to `tdd-patterns/SKILL.md` (test-file globs across JS/TS/Python/Ruby/Go/Rust) and `visual-verification/SKILL.md` (UI file extensions). Future Claude Code versions that respect the `paths:` field will scope auto-discovery for these skills to relevant file changes only, reducing context-budget pressure when many skills are loaded.

### compound-engineering vendor-or-document decision (gate 20)

**Decision: document, do not vendor.** The `visual-verification` skill's browser-tool cascade includes two entries from the `compound-engineering` plugin (`compound-engineering:test-browser`, `compound-engineering:agent-browser`) at fallback positions 4 and 5. The cascade gracefully handles their absence (Playwright MCP, Chrome DevTools MCP, and the CLI fallback are all viable for the production loop); vendoring would fork the behavior and create maintenance debt for code flow did not author. The `visual-verification/SKILL.md` "External dependency" section documents the rationale, the in-practice behavior (with/without compound-engineering installed), and the BLOCKED escalation path when no browser tools are available.

### `/flow:learn` integration

`commands/learn.md` Phase 5 (Promotion Workflow) now points at `bin/promote-proposal.sh` as the canonical promotion path, replacing the previous "Copy to plugins/flow/skills/learned/{name}/SKILL.md / Commit and create PR" manual instructions. Includes documentation of the `--dry-run` flag for validation without filesystem effects.

### Post-review hardening (PR #99 review pass)

Fixes surfaced by the pre-landing review:

- **Plugin version sync**: `plugins/flow/.claude-plugin/plugin.json` and the flow entry in `.claude-plugin/marketplace.json` bumped from `2.1.0` → `2.3.0` to match this CHANGELOG. The CLAUDE.md "Versioning" rule (bump both files on release) was missed when the 2.1.1/2.2.0/2.3.0 entries landed.
- **Schemas now ship inside the plugin payload.** Moved `tests/skills/<name>/input-schema.json` → `plugins/flow/schemas/<name>/input-schema.json` and updated `bin/validate-skill-input.sh` to resolve via `${CLAUDE_PLUGIN_ROOT}/schemas/...`. The previous `tests/skills/...` location was repo-only — end-users installing the marketplace plugin via Claude Code did not get the schemas, so any runtime call to the validator (per `references/skill-contracts.md`) would have failed with exit 2. Test fixtures (`valid-input.json`, `invalid-input.json`, `test.sh`) stay at repo level.
- **Concurrency lock on `bin/journal-record.sh`.** Two parallel writers (e.g. paired-reviewer dispatch under Path A) could both read the manifest, both append in-memory, and the second `rename` would clobber the first writer's append. Added a per-journal `flock` (with `shlock` fallback for macOS without coreutils, and a one-line warning when neither is present). Doc updated: "Idempotent and atomic" → "Append-only with atomic per-record writes" because re-running with identical args produces a duplicate `artifacts[]` entry by design (callers dedupe).
- **`bin/promote-proposal.sh` cleanup hardening.** Cleanup trap now registers BEFORE the `mkdir`/`cp`/python rewrite of the target SKILL.md, so a failure in those steps no longer leaves an orphan `plugins/flow/skills/learned/<name>/` in the working tree. Newline/CR in `--proposal` paths is rejected upfront; previously a path like `evil\nname` would fall through to the `sed` substitution at the end of the script (after `git push -u`), strand a remote branch with no PR, and leave `.bak` artifacts behind.
- **`journal.dir` cascade trimmed (security).** `bin/journal-record.sh`, `hooks/scripts/{session-end-learn,log-commits,log-file-changes}.sh` no longer read `journal.dir` from the repo-local sources `.claude/settings.flow.local.json` and `.claude/settings.flow.json`. After `gh pr checkout` of a hostile fork PR, those files would otherwise let an attacker redirect every hook write to an attacker-controlled path. User-global (`$HOME/.claude/settings.flow.json`) and plugin defaults are preserved — same defense pattern as `merge.markerTrust` and the `agentTeams` plugin pin in `review.md`.
- **JSON Schema regex portability.** `\Z` anchor (Python-only) replaced with `(?!\n)$` lookahead in `plugins/flow/schemas/holdout-validation/input-schema.json` and `tests/finding-schema/row-schema.json`. The lookahead form is portable across Python `re` and ECMA-262 validators (ajv, etc.), unblocking future use of the schemas in non-Python tooling. The two trailing-newline regression assertions (`tests/skills/holdout-validation/test.sh` and `tests/finding-schema/fixtures.json`'s `F1\n` invalid fixture) both still reject correctly.
- **`commands/merge.md` `$TRUST_REGEX` fix.** Replaced the dead reference (a leftover from PR #93 that produced "trusted authors ()" or aborted under `set -u`) with a `TRUST_LIST_DISPLAY` rendered from `$TRUST_LIST` via `jq -r 'join(",")'`.
- **`bin/flow-escalate.sh` numbered-list rendering + duplicate-option rejection.** Output is now a real Markdown numbered list (`1. ...`) rather than bullets with the user-supplied `<n>:` embedded as text — matches the docstring claim. Duplicate option numbers (`1: A;1: B`) are now rejected with a clear error rather than rendered ambiguously.

### Post-review hardening — cycle 2 (PR #99 `/flow:review`)

The first hardening pass left three sister sites still reading the unsafe cascade and a few ancillary issues. Cycle 2 closes them:

- **Cascade trim now covers all 7 consumers.** `commands/learn.md` (`journal.dir` + `learning.proposalDir`), `commands/explain.md` (`journal.dir`), and `agents/convention-checker.md` (`conventions.commitTypes`) were still reading `.claude/settings.flow.{local.,}json` despite executing inside Claude Code at command time after `gh pr checkout`. Trimmed to user-global + plugin only, matching the four `.sh` scripts. Without this, a fork PR could redirect proposal writes to `/tmp/attacker` (then have them picked up by `/flow:learn`) or relax `commitTypes` to `.*` defeating commit-message validation.
- **`bin/promote-proposal.sh` git commit reads from stdin via `git commit -F -`.** The previous `git commit -m "...$PROPOSAL..."` would have evaluated backticks or `$(...)` inside `$PROPOSAL` (a user-supplied path) at message-construction time. The earlier newline rejection covered LF/CR but not the substitution metacharacters; switching to stdin removes the risk by construction.
- **`bin/validate-skill-input.sh` charset-guards `$SKILL`.** `$SKILL` is interpolated directly into the schema path; combined with `jsonschema`'s default `$ref` resolver (which honors `file://` URLs), an unsanitized value like `../../etc/passwd` was a theoretical local-file-read primitive. Now rejects anything outside `^[a-z][a-z0-9-]*$` (same charset as `bin/promote-proposal.sh`'s `PROPOSAL_NAME`). Two new regression tests in `tests/skills/holdout-validation/test.sh` (path-traversal name, non-kebab-case name) — total assertions for that suite 7 → 9.
- **`bin/promote-proposal.sh` cleanup safety.** Pre-flight refuses when `$TARGET_DIR` exists with content (not just when `SKILL.md` exists). Without this, a contributor's half-finished hand-promotion (e.g., `references/foo.md` placed manually before adding `SKILL.md`) would be silently wiped by the cleanup trap's `rm -rf "$TARGET_DIR"` on a python rewrite failure.
- **`bin/journal-record.sh` lockfile symlink check.** Refuses `[ -L "$LOCKFILE" ]` upfront. `exec 9>"$LOCKFILE"` would otherwise truncate a symlink target chosen by an attacker (low severity since the journal directory is no longer attacker-controlled, but defense-in-depth).
- **Stale `\Z` anchor doc cleanup** in `tests/skills/holdout-validation/test.sh` (assertion label + comment) so the canonical anchor is the `(?!\n)$` lookahead everywhere.
- **Schema `$id` URIs corrected.** All three relocated schemas had `$id` URIs still pointing at `tests/skills/<name>/...`; updated to `plugins/flow/schemas/<name>/...`. JSON Schema Draft-07 treats `$id` as the canonical identifier — incorrect URIs would break `$ref` resolution if any tooling does cross-schema lookups.
- **CHANGELOG totals fixed.** Cycle-1 entry overcounted "21 trailing-newline regression assertions" — actual count is 2 (one in `tests/skills/holdout-validation/test.sh`, one in `tests/finding-schema/fixtures.json`'s `F1\n` invalid fixture). Updated.

### Verification

Test totals on this release: 77 assertions across `tests/issue-86/` (16), `tests/skills/{holdout-validation,criterion-verification-map,specification-capture}/` (21 — holdout-validation grew from 7 → 9 with the path-traversal regressions), `tests/finding-schema/` (14), `tests/status-parser/` (10), and `tests/journal-orchestration/` (16). All pass — including after the schema relocation, the `(?!\n)$` lookahead migration, the journal-record concurrency lock + symlink check, and the `validate-skill-input.sh` charset guard. The synthetic-issue end-to-end manifest journey via Claude Code's prompt layer is a manual integration check exercised by maintainers running `/flow:start` after the helper scripts ship.

## 2.2.0 (2026-05-06)

### New Reference Documents

- `references/finding-schema.md` — canonical 6-field reviewer output row (`ID | Category | Location | Problem | Suggested Fix | Confidence`) plus the marker-only `status` and `disposition` fields. Compatible with the existing `FLOW_REVIEW_CYCLE` 7-field marker grammar.
- `references/escalation-format.md` — canonical six-field Proactive-Autonomy structure (Situation, What I tried, Options, Recommendation, Time sensitivity, Risk) delivered via `AskUserQuestion`. Implementation field names adopted as canonical because they were already 4× consistent across commands.
- `references/evidence-bundle-format.md` — canonical markdown shape `verdict-judge` consumes. Per-criterion sections with mandatory `### Does NOT promise` plus three completeness subsections (`### What was NOT tested`, `### Known limitations of this evidence`, `### Negative/adversarial cases covered`); `none` is a valid positive-statement answer; bare blank triggers auto-FAIL.

### New Skills

- `specification-capture` — owns the lifecycle for non-goals, failure modes, and interface contracts. Reads journal first, extracts from issue body, prompts for missing elements via `AskUserQuestion` with the canonical six-field structure, writes to `.decisions/issue-{N}.md` under a `## Specification` heading. Invoked by `/flow:start` Phase 1, `/flow:design` Phase 1, and `/flow:brainstorm` Phase 1.
- `visual-verification` — extracted from `runtime-verification` (which dropped from 399 → 242 lines). Owns the screenshot-analyze-verify loop, browser-tool priority cascade (Playwright MCP → Chrome DevTools MCP → CLI → external skill fallback), responsive viewport checks, and the result vocabulary (PASS / FAIL / SKIP / SKIP_WARN / SKIP_USER_APPROVED / MANUAL / BLOCKED). Total skill count is now 24 (3 foundation + 21 domain).

### Migrations

- All 4 reviewer agents (`code-reviewer`, `security-reviewer`, `error-handler-inspector`, `integration-verifier`) emit findings using the canonical schema in `references/finding-schema.md`. The previous ASSERTION/EVIDENCE/VERIFIED-vs-table inconsistency between agents is resolved. Reviewer ID prefixes (`F`, `SEC-`, `ERR-`, `INT-`) make finding provenance recoverable from the ID alone.
- `agents/verdict-judge.md` Step 1 cites `references/evidence-bundle-format.md` as the input contract. Auto-FAIL rules now reference the exact canonical headings; producer non-conformance surfaces as a producer bug rather than an opaque judge failure.
- `commands/start.md` Phase 4 step 5 produces evidence bundles in the canonical format; the journal-write-to-judge-input chain is now traceable through one document.
- All 6 escalating commands (`start`, `pr`, `merge`, `commit`, `address`, `resolve`) cite `references/escalation-format.md` in their References section. Situation-specific escalation prose stays in the commands; the structural contract is canonical.
- `commands/start.md` Phase 1 replaces ~30 lines of inline specification-capture prose with `Skill(specification-capture)` invocation; `commands/design.md` and `commands/brainstorm.md` invoke the same skill so the journal is the single source of truth across all three commands.
- `commands/start.md` Phase 4 and `commands/pr.md` Phase 4 invoke `Skill(visual-verification)` in parallel with `Skill(runtime-verification)` when the diff is UI-relevant. `agents/integration-verifier.md` Step 6 delegates the screenshot-analyze-verify loop to the new skill rather than re-implementing it inline.

### Documentation

- `commands/review.md` Path A note + `skills/team-coordination/SKILL.md` Phase 3 + `skills/holdout-validation/SKILL.md` Integration Points: the holdout-validation challenge-round exclusion is now documented as a principled design decision (objective claim verification vs subjective judgment) rather than a tooling workaround. Holdout findings emit with `consensus` (both lenses raised the finding) or `unchallenged` (one lens only — itself a useful divergence signal); they NEVER carry `validated` / `refined` / `kept` because those are challenge-round outputs.
- README adds a "Canonical Reference Documents" section listing the three new docs plus the existing reference library, so contributors can find the source of truth without grepping.
- README skill-library count updated from 22 to 24 (architecture diagram).

## 2.1.1 (2026-05-06)

### Documentation

- All 22 skill descriptions rewritten to lead with the artifact, name 2-3 specific triggers, and add either "MUST be consulted because…" (verification, safety, and gate-enforcing skills) or "Proactively suggest when…" (creative and exploratory skills) — bringing the active skills into the same trigger pattern that drove `holdout-validation`'s invocation rate from ~0% to the high 90s.
- README adds a Hook Compatibility table noting that `TaskCompleted` and `TeammateIdle` hooks require Claude Code v2.1.33+ and treat their JSON payloads as best-effort because the schema is undocumented.
- `code-review-methodology` skill now cites `references/test-review-checklist.md` for the Tests facet.
- `pr-lifecycle` skill now cites `references/gate-configuration.md#quality-gates` for the canonical map of the eight gates flow enforces.
- `merge.markerTrust` is now documented in `schema.json` with an inline rationale explaining the security-driven decision to read it from `plugins/flow/settings.json` only (no settings cascade).

### Bug Fixes

- `/flow:address` Phase 4 fan-out now explicitly enumerates all 5 reviewer agents (added `security-reviewer`); previously claimed pr.md parity by reference but the dispatch block only listed 4 agents — security review was silently skipped on every re-review.
- `session-end-learn.sh` no longer false-matches today's date string when it appears inside journal content (e.g. due-date references in older entries). Switched from `grep -q "$TODAY"` to `find -mtime -1` for portable, content-agnostic detection of recent journal activity.
- Removed unused `journal.sensitivityDefault` setting from `settings.json` and `schema.json` (no consumer existed). Related references in `gate-configuration.md` and `decision-journal-schema.md` updated.

## 2.1.0 (2026-05-05)

### New Features

- `/flow:address` re-review now matches `/flow:pr` fan-out parity, running the full reviewer set on resolved feedback (#64, #75)
- `/flow:pr` and `/flow:review` default fan-out now wires `security-reviewer` for security-aware coverage on every PR (#61, #70)

### Bug Fixes

- `/flow:pr` review depth brought to parity with `/flow:review` (#62, #71)
- Skill bodies that duplicated command bash are now deduped; commands stay the canonical source (#65, #67)
- Three inaccurate gate descriptions in `gate-configuration.md` corrected (#60, #69)
- `schema.json` defaults synced with post-v2.0 settings (#59, #68)

### Documentation

- Required Skills vs `Skill()` invocation convention documented (#66, #74)
- Settings cascade direction unified across all docs (#63, #73)
- Three source-of-truth drifts in README and `criterion-verification-map` corrected (#58, #72)
- Flow plugin team workshop materials added (#57)

## 2.0.1 (2026-05-05)

### Bug Fixes

- `log-commits.sh` PostToolUse hook no longer leaves the worktree permanently dirty. Two idempotency guards added: skip when the last commit message starts with `chore(decisions):`, and skip when the most recent commit only modified the journal file itself. The `auto-log → commit → auto-log` infinite append loop is now bounded. (#56, closes #55)

## 2.0.0 (2026-04-16)

### Breaking Changes

- `tddMode` default changed from `suggest` to `enforce`
- `verdict.requireAllPass` default changed from `false` to `true`
- P3 findings are no longer deferrable -- fix in-PR or file a Proactive-Autonomy escalation
- Pre-existing findings in touched files keep natural priority (no longer capped at P3)
- Merge gate now blocks on unresolved findings in FLOW_RESOLUTION_CYCLE markers
- "DEFERRED" markers renamed to "ESCALATED" in FLOW_RESOLUTION_CYCLE comments

### New Features

- Spec Validation Gate: acceptance criteria must have concrete automated verification commands before PLAN phase
- Specification capture: non-goals, failure modes, and interface contracts required in EXPLORE phase
- Stranger Test: mandatory end-of-PLAN gate ensuring zero-context executability
- Per-task verification gate: tests must pass and evidence captured before TaskUpdate(completed)
- Holdout-validation skill: cross-references agent self-review claims against actual file state
- Evidence bundle completeness: "What was NOT tested", "Known limitations", "Negative/adversarial cases" required per criterion
- Missing-criterion scan: verdict-judge Step 1 checks every criterion has evidence before evaluation
- Proactive Autonomy with Prepared Escalation: codified six-field structure, anti-pattern list
- Finding-ledger merge gate: blocks merge on non-empty ESCALATED array

### Migration Guide

- To keep old TDD behavior: set `testing.tddMode: "suggest"` and `testing.tddModeOptOut: true` in settings.json
- To keep old verdict behavior: set `verdict.requireAllPass: false` in settings.json
- "DEFERRED" markers renamed to "ESCALATED" in FLOW_RESOLUTION_CYCLE comments
