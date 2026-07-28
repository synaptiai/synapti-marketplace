---
issue: 137
created: '2026-07-28T17:28:31Z'
artifacts:
- type: specification
  captured_at: '2026-07-28T17:51:30Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: goal-created
  captured_at: '2026-07-28T17:52:41Z'
  goal_id: issue-137
  source: github_issue:137
- type: workflow-run
  captured_at: '2026-07-28T17:53:03Z'
  workflow: start-issue
  run_id: 2026-07-28T172831Z-issue-137
  status: active
- type: stranger-test
  captured_at: '2026-07-28T18:09:21Z'
  result: PASS
  task_count: 8
---
# Decision Journal — Issue #137

**Title**: dossier: execute dependency-vulnerability and Python code-quality scans, isolated within the automated refresh pipeline's security boundaries
**Branch**: feature/issue-137-isolated-scanner-execution
**Started**: 2026-07-28

Part 3 of 4 in the dossier post-merge/investor-doc-gap initiative (plan: `the-dossier-plugin-is-federated-toucan`). Part 1 (#135, PR #139) and Part 2 (#136, PR #141) are shipped and merged. Epic 4 (#138) is separate, sequential work.

## Specification

_Captured by specification-capture skill on 2026-07-28. Source: mixed — extracted from issue body + governing plan doc (`the-dossier-plugin-is-federated-toucan`, Epic 3) + user-confirmed via `AskUserQuestion` on the one materially ambiguous point (AC2 scope) + empirical verification against actually-installed real tools (osv-scanner 2.4.0, pyscn 1.10.2) performed directly this session, not assumed from training-data familiarity._

### Non-goals

- **Ledger citation for code-quality findings** — confirmed via `AskUserQuestion` (2026-07-28): pyscn output is normalized into an artifact only (the refresh agent `Read`s it). No `dossier-quality-evidence.sh`, no new evidence-ledger `Notes`-tag vocabulary for quality findings, no `EV-####` rows for quality findings, no new gate condition (no G20). This deliberately diverges from AC1's vulnerability path, which does require ledger citation via the already-shipped `dossier-vuln-evidence.sh` (issue #136). Rationale: AC1 says "correctly cited as evidence"; AC2 does not — the drafter used that exact phrase one bullet earlier and chose not to repeat it for AC2, and the governing plan doc's Epic 3 description only names two scan flags, not a second citation pipeline.
- **A single combined wrapper script** — two separate scripts (`dossier-scan-security.sh`, `dossier-scan-quality.sh`), not one script with a `--type` flag. Matches dossier's one-script-per-concern convention and keeps the two `allowedActions` flags architecturally non-conflatable at the code level, not just by convention.
- **Any change to G01–G19's existing logic, order, or precedence computation** in `dossier-gate.sh` — this issue's only gate-adjacent change is the severity-extraction bug fix inside `dossier-vuln-evidence.sh` (see Interface contracts), which changes G19's *inputs*, never G19's own logic.
- **Live GitHub Actions execution as a completion requirement** — AC6 ("real end-to-end run... not a substitute/stand-in") is satisfied by a local run against the actually-installed real tools, contrasted with a fake/stub binary — not by deploying and triggering the CI workflow. Resolved via advisor consultation (2026-07-28); the disclosure that a local run does not prove GitHub Actions' actual permission/egress isolation belongs in the Phase 4 evidence bundle's "Known limitations" field, not as unfinished scope here.
- **Reimplementing CVSS scoring math** — severity comes from osv-scanner's own precomputed `.groups[].max_severity` field, never from hand-parsing a CVSS vector string (`CVSS:3.0/AV:N/...`) into a base score. osv-scanner already does that computation; duplicating it in jq would be redundant and error-prone across CVSS v3.0/v3.1/v4.0's differing formulas.
- **`pyscn check`'s CI-oriented exit-code mode** — confirmed empirically that `check` has no `--json` output at all ("unknown flag: --json"). This issue uses `pyscn analyze --json` exclusively for machine-readable output; `check`'s fast exit-code semantics are not used.
- **Widening `engagement.allowedActions` beyond the two new flags** — no new action class beyond `runSecurityScan`/`runCodeQualityScan`; scanner execution does not imply broader `networkAccess`/`writeOutsideOutputRoot`/`contactHumans` grants.
- **Offline-vulnerability-database provisioning/refresh tooling** — this issue defines the fail-closed *contract* for a stale/missing offline cache (age ceiling, ownership/digest fields, honest `unavailable`/`stale_advisory_data` reporting) but does not build a scheduled downloader or rotation job for that cache; that's future work if offline mode is adopted in practice.

### Failure modes

- **Timeouts** — both wrapper scripts (`dossier-scan-security.sh`, `dossier-scan-quality.sh`) run their underlying tool under an explicit timeout (exact bound decided in PLAN, per the issue's "defined, bounded cost" requirement). A timeout is reported as a distinct "did not complete" status, never as "0 findings" — same honesty rule as tool-absence below.
- **Partial failures** — osv-scanner's own per-record fault isolation (already handled downstream by the shipped `dossier-vuln-evidence.sh`: `unparseable_records`) is preserved end-to-end; the new wrapper scripts must not introduce a second point where one malformed record silently drops the rest of a scan. For pyscn, a `warnings`/`errors` array present in the `analyze --json` report body (confirmed present as top-level keys in real output, currently `null` in the clean-fixture run) must be surfaced, not discarded.
- **Invalid input** — a target path that doesn't exist, isn't readable, or (for the quality scanner) contains no Python files is reported as an explicit error, never as a clean zero-issues result. Mirrors the ERR-3 delegate-failure pattern already shipped in `dossier-policy.sh`/`dossier-evidence.sh`/`dossier-vuln-evidence.sh`.
- **Missing context** —
  (a) **Capability disabled** (`runSecurityScan`/`runCodeQualityScan` unset or `false`): the wrapper reports "scan not run — capability disabled" and exits without invoking the underlying tool at all. Verified by construction: each script reads only its own flag via `dossier-resolve-config.sh`'s bare dotted key with `--default "false"` (no `//` fallback — the documented falsy-`false` pitfall in `config-resolution.md:51-70`), so AC3 (enabling one never enables the other) holds by construction, not just by test.
  (b) **Tool unavailable** (`osv-scanner`/`pyscn` not on `PATH`, or present but wrong/incompatible version): reported as a distinct "tool unavailable" status, never as "0 vulnerabilities"/"0 issues". Tested via the existing `PATH=/nonexistent` fail-closed technique already used in `hooks.test.sh`.
  (c) **Stale or missing offline vulnerability database** (security scan, offline mode only): the cache must carry ownership, producer, digest, created/updated timestamps, and a maximum acceptable age. An expired or unverifiable local database reports `unavailable`/`stale_advisory_data`, fail-closed — never `clean`. This is the AC4 case with the highest stakes: a stale-DB "clean" result is actively misleading (looks identical to "genuinely no vulnerabilities"), unlike the other missing-context cases which are more visibly "nothing happened."
  (d) **`.pyscn/` report-directory ambiguity** — empirically confirmed the report directory follows the invoking process's CWD, not the analyzed target path. The wrapper must `cd` into a dedicated scratch directory before invoking `pyscn analyze --json <target>`, so the target repo is never touched (no cleanup, no `.gitignore` changes needed), and must select the produced report by snapshotting the scratch reports directory immediately before and after the run (set difference) — never by "newest `analyze_*.json`" filename, which would silently return a stale report from a prior run sharing the same scratch directory.

### Interface contracts

- **`dossier-scan-security.sh`** (new): `--target <path> [--out <dir>] [--offline]`. Resolves `dossier.engagement.allowedActions.runSecurityScan` (bare dotted key, `--default "false"`, no `//`); if false, emits `{"status":"disabled", ...}` and exits without invoking `osv-scanner`. Otherwise invokes `osv-scanner scan source --format json -r <target>` under a bounded timeout, capturing stdout/stderr/exit code separately. **Success determination is "valid JSON was produced on stdout,"never "exit code == 0"** — empirically verified osv-scanner 2.4.0 semantics: exit `0` = clean scan (valid JSON, empty `results`); exit `1` = vulnerabilities found (valid JSON, non-empty `results` — a SUCCESS case, not a failure); exit `127`/`128` = genuine failure (bad path / no package sources found), both with **empty stdout**. The wrapper's own output feeds directly into the existing `dossier-vuln-evidence.sh --scan <path>` ingestion path (issue #136) — it must produce (or point to) a file matching one of that script's three recognized shapes; osv-scanner's native `--format json` output already matches the `osv-scanner` shape `dossier-vuln-evidence.sh` detects.
- **`dossier-vuln-evidence.sh` severity-extraction fix** (existing file, bug fix in scope for this issue — its own docstring at lines 14-21 explicitly defers this exact re-verification to issue #137): change the osv-scanner extraction path from `.results[].packages[].vulnerabilities[].severity[0].score` (a CVSS **vector string** in real output, e.g. `"CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N"` — never a bare score, confirmed empirically: a fixture with multiple Critical/High CVEs including two at CVSS 9.8 produced `findings: 0, unresolved_severity: 39` against the currently-shipped code) to `.results[].packages[].groups[].max_severity` (a bare numeric CVSS string, e.g. `"9.8"` — confirmed this resolves severity even for records where the per-vulnerability `.severity` field is `null`). A `groups[]` entry with null/absent `max_severity` still falls through to `unresolved_severity`, never defaults to Low. One evidence-ledger row per **group** (not per raw vulnerability id) — a group merges aliases (e.g. `ids: [PYSEC-2018-2, GHSA-5hg3-6c2f-f3wr]` under one group is one logical vulnerability). The primary id representing a group is chosen deterministically: prefer the `CVE-`-prefixed alias if present in the group's `aliases[]`, else the lexicographically-first id in `ids[]` — never "whichever id the tool happened to list first" (tool-output order is not a stable contract). **Resolved design decision** (same treatment as the `accepted`-status change in `.decisions/issue-136.md`): this is a behavior change, not a pure bug fix. Once severity resolves correctly, osv-scanner-sourced evidence that previously produced only `vuln-finding-unresolved` rows (→ G19 `INCONCLUSIVE`) will start producing real `Critical`/`High` rows (→ G19 can now `FAIL`) for any installation that already ingested osv-scanner output before this fix. Accepted knowingly: an INCONCLUSIVE that was actually masking a real Critical/High finding is a worse outcome than the gate now correctly failing.
- **`evidence-ledger-schema.md:129`** — the sentence "Dossier reads the scan tool's output; it does not independently execute or re-verify the finding" (justifying `State: R` for every vulnerability row) must be revised: `State` remains `R` (Reported) for both ingestion paths — dossier still reports what the scanner found, it does not independently re-verify the CVE itself against a second source — but the rationale sentence is updated to distinguish "citing a pre-existing scan artifact" (issue #136) from "dossier having just executed the scan itself" (issue #137) as two sub-cases of `R`, both correctly NOT promoted to a higher-confidence state, since executing a scanner is not the same as independently verifying a finding's accuracy.
- **`dossier-scan-quality.sh`** (new): `--target <path> [--out <dir>]`. Resolves `dossier.engagement.allowedActions.runCodeQualityScan` (bare dotted key, `--default "false"`, no `//`, independent of `runSecurityScan`); if false, emits `{"status":"disabled", ...}` and exits without invoking `pyscn`. Otherwise `cd`s into a dedicated scratch directory, invokes `pyscn analyze --json <target>` under a bounded timeout (writes to `<scratch>/.pyscn/reports/analyze_<timestamp>.json` per confirmed real behavior — target path is never touched), selects the produced report via before/after directory snapshot (never "newest file"), and normalizes it into the wrapper's own output artifact. Must read across both casing conventions actually present in real `analyze --json` output (confirmed empirically): the `dead_code` section uses snake_case keys (`file_path`, `severity`, `total_findings`), while the `complexity` section uses PascalCase keys (`FilePath`, `RiskLevel`, `TotalFunctions`) — the parser must not assume one casing convention applies to the whole document. Output artifact schema (new, this issue): `{"schema":"dossier.quality-scan/v1", "scan":{"tool":"pyscn","version","target","retrieved"}, "dead_code":{...}, "complexity":{...}, "status":"ok|disabled|unavailable|timeout|error", "note":"<untrusted-content warning, matching dossier-vuln-evidence.sh's existing note field pattern — this is scan output derived from repository content>"}`. No evidence-ledger row grammar (per the confirmed non-goal above) — this is an artifact schema, not a ledger schema.
- **`schema.json` / `settings.json`**: two new boolean properties under `dossier.engagement.allowedActions` — `runSecurityScan` (default `false`) and `runCodeQualityScan` (default `false`), each with a `description` explaining the off-state consequence, following the exact pattern of the existing `runTests`/`runBuild` properties (`schema.json:122-162`).
- **`enforce-allowed-actions.sh`**: two new deny-blocks (defense-in-depth backstop, following the exact structure of the existing `RUN_TESTS`/`RUN_BUILD`/`NETWORK` blocks at lines 96-133) matching direct `osv-scanner`/`pyscn` invocations at a real command boundary (reusing the existing `BOUND`/`WRAPPER` anchoring so `bash -c`/`env`/`timeout`/etc. indirection can't bypass it), denying when the corresponding flag resolves `false`.
- **CI template (`plugins/dossier/templates/ci/dossier-docs-refresh.yml`)**: a new job/step, architecturally a sibling of the already-shipped `policy` job — `permissions: {contents: read}` only (no `pull-requests`/`contents: write`), no `ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN` exposure, `persist-credentials: false` on checkout, resource/timeout limits, pinned tool versions (`osv-scanner`/`pyscn` install step pins an exact version, not a floating tag). Output normalized and uploaded as a build artifact (matching the existing `dossier-evidence` artifact pattern) for the `refresh` job's agent to `Read` — the agent never executes either scanner directly.

## Resolved: AC4 offline-staleness gap (verdict-judge NEEDS-HUMAN-REVIEW, PR review cycle)

The independent verdict judge in `/flow:start` Phase 4 returned `NEEDS-HUMAN-REVIEW` on AC4, catching a genuine, self-contradictory gap in the evidence bundle: "What was tested" claimed stale/missing offline-DB coverage, but "What was NOT tested" and "Known limitations" retracted that for the *stale* (present-but-expired) case specifically — only the *missing* (absent-entirely) case had real test evidence. Investigated directly rather than escalated to the user, since it was answerable by empirical fact-check (the judge's own recommended Option 1): does osv-scanner itself treat an expired local cache the same as a missing one?

**Confirmed empirically: no.** A real cached PyPI database, artificially aged to 2020 via `touch`, was loaded and scanned by real osv-scanner 2.4.0 with zero warning, zero error, and output content-identical to a genuinely fresh fetch — osv-scanner performs no staleness check on its own local cache whatsoever. The existing stderr-pattern-match detection (`could not load db`) only fires on a *load failure*, never on a stale-but-loadable cache, so it could never have closed this gap regardless of test coverage.

**Fix**: `dossier-scan-security.sh` now checks the cached database's own file age *before* invoking osv-scanner at all, whenever `--offline` is set — refusing with `status: unavailable`, `detail` containing `stale_advisory_data`, if the newest file under osv-scanner's cache directory is older than `DOSSIER_SCAN_OFFLINE_MAX_AGE_DAYS` (default 7, overridable for testing). This is a separate check from the existing "no cache at all" detection; either can fire independently.

**Second-order discovery during this fix, itself worth recording**: osv-scanner's cache-directory resolution (Go's `os.UserCacheDir()`) does **not** consult `XDG_CACHE_HOME` on Darwin — it always uses `$HOME/Library/Caches`, confirmed by moving the real cache aside and observing osv-scanner report "no offline version of the OSV database is available" despite a populated `XDG_CACHE_HOME`-based fake cache being present. Only non-Darwin Unix (the actual CI runner platform) honors `XDG_CACHE_HOME`. The wrapper's own cache-path detection was written to check `XDG_CACHE_HOME` unconditionally first — silently wrong on macOS — and was corrected to match Go's real precedence (platform check first, `XDG_CACHE_HOME` only consulted on non-Darwin). This bug was caught by re-running the test suite immediately after the fix and finding the *pre-existing* "no cached DB" test now failing (it was silently relying on this repo-author's own real, populated system cache), not by static reasoning — a live regression against this machine's own manual testing earlier in the session, surfaced only by actually re-running everything.

## Stranger Test

_Recorded after Phase 2 task decomposition, 2026-07-28._

**Verdict: PASS**, after resolving five gaps a zero-context executing agent could not have resolved on its own. `TaskCreate`/`TaskUpdate` were unavailable in the planning agent's tool set this session, so the 8 tasks below are **not registered in the task system** — the calling agent must register them (or re-run planning with those tools present) before dispatch.

### Plan-level decisions made during decomposition (binding on the tasks below, not re-litigated by an executor)

- **Timeout bound**: both wrapper scripts use a hardcoded `TIMEOUT_SECONDS=300` (5 minutes) constant, not a new config key — the issue's interface contract only names `--target`/`--out`/`--offline` and the two `allowedActions` booleans; adding a timeout config key is new scope. Chosen as a round, generous-but-bounded default; not benchmarked against a large corpus, flagged as a judgment call.
- **Timeout mechanism**: neither `timeout` nor `gtimeout` exists on this machine (macOS, no coreutils) — confirmed by `which timeout gtimeout` returning nothing. Both wrappers implement their own bash-3.2-safe timeout guard: background the tool invocation, poll `kill -0 "$pid"` against `$SECONDS - start`, `TERM` then `KILL` on expiry, and treat that path as `status: timeout` — never as a partial/clean result, and any partial output file from a killed run is discarded, not read.
- **Exit-code contract for both new wrappers** (not stated in the issue's interface contract; resolved here so `dossier-scan-security.sh --target . --out x` is safe inside a CI `run:` block without `|| true`): exit 0 whenever the wrapper itself completed and emitted valid, well-formed JSON — including `status: disabled`, `unavailable`, `timeout`, and `error` (the tool ran but produced no usable output). Exit 2 is reserved for a caller/usage error (bad or missing `--target`), exit 1 for an internal bug (the wrapper's own JSON output fails its own well-formedness self-check, mirroring `dossier-vuln-evidence.sh`'s pattern at lines 318-323). This mirrors the plugin's "not executed is an honest, first-class outcome" posture: a disabled/unavailable/timeout status must never fail the CI step that invoked it.
- **Tool-availability check precedes invocation**: `command -v osv-scanner` / `command -v pyscn` is checked *before* attempting the timeout-wrapped run, giving `status: unavailable` immediately rather than via a slow failed exec. This is the same technique `hooks.test.sh` already uses (`PATH=/nonexistent`) to test fail-closed behavior without needing the real tool.
- **Success determination**: "valid JSON on stdout," never "exit code == 0" — empirically re-confirmed this session (not just trusted from the earlier capture): a fixture scan of `axios@0.21.1`/`lodash@4.17.15` against real osv-scanner 2.4.0 exits 1 (vulnerabilities found) with well-formed JSON on stdout. That JSON is captured to a file; `jq -e . <file>` decides success, not `$?`.
- **`--offline` scope, resolved narrowly against the non-goal**: osv-scanner exposes no queryable cache-freshness signal (confirmed via `--help`; no cache directory exists on this machine because `--download-offline-databases` has never been run here) and dossier explicitly does not build DB provisioning/rotation tooling (non-goal, already recorded above). The wrapper therefore passes `--offline-vulnerabilities` only (read-only, confirmed via `--help` text — never `--download-offline-databases`, which would need network access the isolated CI job does not have). An `ok` result under `--offline` carries an explicit `offline_caveat` string stating dossier does not verify the cached DB's age or provenance in this release — a zero-finding offline result is never presented identically to a network-verified clean scan. The implementing agent must empirically confirm, before finalizing the "no cached DB" detection string, what osv-scanner actually prints on stderr/exit code when `--offline-vulnerabilities` is run with no DB ever downloaded — not asserted here since it was not run this session.
- **Severity-fix defensive fallback (closes a gap the captured spec is silent on)**: the spec covers a `groups[]` entry with null/absent `max_severity` (→ `unresolved_severity`). It does not say what happens when a package has `vulnerabilities[]` but no `groups[]` array at all. Empirically, real osv-scanner 2.4.0 output always populates `groups[]` in lockstep with `vulnerabilities[]` when there are findings (re-confirmed this session against a live axios/lodash fixture — group count equaled vulnerability count, with several groups carrying >1 `ids[]` entry from alias merging). Defensively, if `$p.groups` is ever absent/non-array/empty while `$p.vulnerabilities` is non-empty, every vulnerability in that package must land in `unresolved_severity` — never silently dropped, never defaulted Low. Grouping design (confirmed empirically): `groups[].ids[]` values match `vulnerabilities[].id` values 1:1, so a group's `summary` is looked up via `vulnerabilities[] | select(.id as $v | $group.ids | index($v))`.
- **Tool-missing test policy, precedented in this exact codebase**: `workflow-template.test.sh:17,44` already implements "degrade to an honest, named `_dossier_assert_pass` skip locally; CI installs the real dependency so the skip path is never exercised there" for `python3`/`pyyaml`. `.github/workflows/dossier-tests.yml`'s own comment states the rationale verbatim ("the skip is exactly what would hide a broken schema"). The two new test files adopt the identical idiom for `osv-scanner`/`pyscn`, and `.github/workflows/dossier-tests.yml` gains a pinned-version install step for both tools (placed in the cross-cutting Task 6, after both wrapper scripts exist, to avoid two parallel tasks editing the same CI step). This resolves AC7 ("full suite passes") on a machine without either tool without making the skip silent, and satisfies AC1/AC2/AC6 for real on this machine and in this repo's own CI, where both tools are/will be present.
- **CI template job wiring** (Task 7): one new job `scan`, sibling to `policy` in privilege shape (`permissions: {contents: read}` only, no agent, no Anthropic credential), but `needs: policy` and gated on `needs.policy.outputs.should_run == 'true'` — "sibling of policy" describes matching privilege architecture, not scheduling order; running scanners on every trigger including ones the loop guard rejects would be wasted runner time. Two steps (security, quality) inside the one job, each self-gated by its own wrapper (the YAML does **not** duplicate the `allowedActions` gate — that would violate the template's own documented principle #4 of calling the plugin's scripts rather than reimplementing policy in YAML). Output uploaded as one `dossier-scan` artifact. `refresh`'s `needs:` changes from `policy` to `[policy, scan]` and downloads the new artifact for the agent to `Read`; `refresh`'s own `if:` is unchanged (it must proceed even if `scan` reports disabled/unavailable/timeout — a scan job that ran but found nothing to do must never block the pipeline). Verified against the two existing greppable invariants the template's own tests pin: `assert_match '^permissions: \{\}'` (unaffected, `scan` sets its own job-level `permissions:`) and the no-force-push invariant (irrelevant to this job, must not be introduced).

### Gaps closed before this verdict (would otherwise have failed the Stranger Test)

1. No concrete timeout bound or mechanism was specified in the captured spec — resolved above.
2. No policy existed for what the new tests do when the real tool is absent — resolved above using an exact precedent already in this codebase.
3. The severity-fix spec was silent on `vulnerabilities[]` with no matching `groups[]` — resolved above with a defensive, non-dropping fallback, grounded in a live re-run against real osv-scanner 2.4.0 this session.
4. `dossier-resolve-config.sh` was read in full (not assumed from `config-resolution.md` alone) to derive the exact `DOSSIER_*` environment variable name for the two new flags, needed for Task 5's flag-*true* permit-path test, which no existing `hooks.test.sh` case demonstrates: `DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true` / `..._RUN_CODE_QUALITY_SCAN=true`, traced by hand through `dossier-resolve-config.sh`'s own sed pipeline.
5. `--offline` was verified against the real installed binary (`osv-scanner scan source --help`) rather than asserted from the spec text alone — confirmed present, and confirmed `--offline-vulnerabilities` (read-only) is the correct sub-flag versus `--download-offline-databases` (network-fetching, wrong for an isolated CI job).

No item remains open under "Needs Clarification" — every gap the advisor raised was planner-resolvable and is resolved above, not deferred.

<!-- auto-log: 2026-07-28 19:52 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-137.goal.yaml -->

<!-- auto-log: 2026-07-28 19:52 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T172831Z-issue-137/run.yaml -->

<!-- auto-log: 2026-07-28 20:04 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->

<!-- auto-log: 2026-07-28 20:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/config-schema.test.sh -->

<!-- auto-log: 2026-07-28 20:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/schema.json -->

<!-- auto-log: 2026-07-28 20:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/settings.json -->

<!-- auto-log: 2026-07-28 20:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/config.example.json -->

<!-- auto-log: 2026-07-28 20:13 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 20:13 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 20:13 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/evidence-ledger-schema.md -->

<!-- auto-log: 2026-07-28 20:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 20:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 20:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 20:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 20:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 20:22 commit "feat(dossier): add runSecurityScan/runCodeQualityScan action-ceiling flags" -->

<!-- auto-log: 2026-07-28 20:22 commit "fix(dossier): extract osv-scanner severity from groups[].max_severity" -->

<!-- auto-log: 2026-07-28 20:25 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 20:27 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 20:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 20:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 20:34 commit "feat(dossier): add dossier-scan-security.sh, isolated osv-scanner execution" -->

<!-- auto-log: 2026-07-28 20:35 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-28 20:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-28 20:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-28 20:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-28 20:38 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/quality-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:38 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 20:38 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 20:38 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 20:42 commit "feat(dossier): add dossier-scan-quality.sh, isolated pyscn execution" -->

<!-- auto-log: 2026-07-28 20:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-07-28 20:42 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-07-28 20:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/hooks.test.sh -->

<!-- auto-log: 2026-07-28 20:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/engagement-scoping/SKILL.md -->

<!-- auto-log: 2026-07-28 20:47 commit "feat(dossier): backstop scanner execution with deny-blocks in the action ceiling" -->

<!-- auto-log: 2026-07-28 20:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/quality-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 20:48 Edit /Users/danielbentes/synapti-marketplace/.github/workflows/dossier-tests.yml -->

<!-- auto-log: 2026-07-28 20:52 commit "test(dossier): joint AC3/AC4 verification + pin osv-scanner/pyscn in CI" -->

<!-- auto-log: 2026-07-28 20:53 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 20:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 20:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-07-28 20:58 commit "feat(dossier): wire isolated scan job into the CI refresh pipeline template" -->

<!-- auto-log: 2026-07-28 20:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-07-28 21:02 commit "docs(dossier): CHANGELOG entry for isolated scanner execution (#137)" -->

<!-- auto-log: 2026-07-28 21:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 21:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 21:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 21:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-28 21:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-07-28 21:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-28 21:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-07-28 21:23 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue-find-exec-bypass.md -->

<!-- auto-log: 2026-07-28 21:29 commit "fix: address self-review findings (P1/P2/P3) on issue #137 branch" -->

<!-- auto-log: 2026-07-28 21:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 21:39 commit "test(dossier): non-ASCII coverage for osv-scanner group extraction" -->

<!-- auto-log: 2026-07-28 21:46 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:46 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:46 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 21:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 21:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 21:50 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:50 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-28 21:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-28 21:56 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->
