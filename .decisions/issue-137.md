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
- type: goal-evaluation
  captured_at: '2026-07-28T21:09:59Z'
  goal_id: issue-137
  result: achieved
  evidence_bundle: .flow/runs/2026-07-28T172831Z-issue-137
  failures: none
- type: review-cycle
  captured_at: '2026-07-29T09:43:40Z'
  cycle: 1
  path: B
  findings_count: 10
  pr: 144
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

## Resolved: AC6 contract defect (goal-evaluator-judge, five NEEDS-HUMAN-REVIEW/incomplete passes)

`AC6`'s `verification_command` in `.flow/goals/issue-137.goal.yaml` was originally authored as descriptive prose with a command embedded inline (`osv-scanner --version && pyscn --version (both actually installed; real local run captured as evidence, per resolved non-goal on live-CI requirement)`) rather than a literal, mechanically re-runnable command. Five successive `goal-evaluator-judge` passes on AC6 returned `incomplete`/`needs_human_review`, each time against progressively stronger evidence (real version banners → real wrapper invocations → raw JSON artifact excerpts with real CVE ids). The first four passes were interpreted as an evidence-quality gap and answered by improving the evidence; the fifth pass instead surfaced the actual defect directly: "AC6's `verification_command` is not a runnable command — it embeds non-goal prose inline... Nobody can mechanically re-derive this evidence from that string as written," alongside bundle-assembly defects (hand-rolled prompts had not used the canonical `flow-run-deterministic-checks.sh` / `bin/_flow_evidence_bundle.py` pipeline, so the judge's expected `### Evidence coverage analysis` header and per-AC deterministic JSON were absent).

**Fix**: `AC6.verification_command` corrected to `bash plugins/dossier/tests/run.sh vuln-scan-execution.test.sh quality-scan-execution.test.sh` — a real, already-passing command. This is not a scope change: AC6's text ("at least one real end-to-end run against the actual scanning tools... confirms the capability works in practice") is exactly what those two test files' own tripwire assertions exercise when a real `osv-scanner`/`pyscn` binary is on `PATH` (as it is on this machine), which is what the four prior evidence submissions were independently trying to demonstrate by hand. Re-evaluated via the canonical `flow-run-deterministic-checks.sh` → `bin/_flow_evidence_bundle.py` pipeline rather than a hand-assembled prompt, closing both the contract gap and the bundle-format gap in one fix.

**Sixth-pass follow-on (same session)**: a full 7-AC canonical-pipeline judge pass caught the same class of contract mismatch on `AC5` — its `verification_command` named only `hooks.test.sh`, while the actual evidence proving AC5's "existing security boundaries" claim (the CI scan job's read-only permissions, no-credential-exposure, and pinned-tool-install assertions) lives in `workflow-template.test.sh`. Corrected to `bash plugins/dossier/tests/run.sh hooks.test.sh workflow-template.test.sh`, matching the sidecar command that had already been evidencing it in practice. The same pass also flagged AC5's own limitations text (citing the pre-existing, documented-not-patched `find -exec`/`xargs -I{}` hook bypass, issue #143) as overlapping AC5's scope. On inspection this was an imprecise disclosure, not a real gap: the bypass grants command execution when a capability flag denies it — never the network, credential, or write access AC5's parenthetical actually enumerates — and it is a property of the pre-existing `enforce-allowed-actions.sh` script shared identically by `runTests`/`runBuild`/`network`, not something this issue's two new deny-blocks introduced or widened. The CI-boundary claim itself rests on the job permission model (`contents: read`, no write, no LLM credential, `persist-credentials: false`), which the bypass cannot touch — the refresh job's own tool allowlist contains neither `find` nor `xargs`. Limitation text rewritten to state this precisely rather than the prior wording, which invited the overlap reading by omission.

## Resolved: holdout validation findings (/flow:pr Phase 3, 1 P1 + 2 P2 + 2 P3)

The `holdout-validation` skill, run alongside the 5-agent review fan-out and `integration-verifier` in `/flow:pr` Phase 3, cross-referenced the code-reviewer's self-review claims and the evidence bundle against actual file state and surfaced five findings the prior review passes had not caught — all now fixed, TDD RED→GREEN verified, and re-confirmed by a full 23-file/1670-assertion targeted suite run (the two pre-existing, out-of-diff files with the known local-git-fixture-leak bug from issue #135 excluded, per the standing decision to not exercise them this session).

**P1 — offline staleness guard keyed on the wrong file.** `dossier-scan-security.sh`'s AC4 staleness check (added earlier this session, see the AC4 entry above) computed the cache's age from the *newest* file across the whole `~/Library/Caches/osv-scanner` tree, not the ecosystem subdirectory the scan target actually needs. osv-scanner's cache is laid out per ecosystem (`osv-scanner/PyPI/all.zip`, `osv-scanner/npm/all.zip`, ...), so a single fresh file in any unrelated ecosystem masked an arbitrarily stale database in the ecosystem genuinely in use — reproduced live against real osv-scanner 2.4.0 (a 2020-dated PyPI database plus a fresh sibling npm file returned `status: ok` with an unearned `age-checked before this scan ran` claim; the identical database with no fresh sibling correctly refused). First fix attempt keyed the guard on the *oldest* file in the whole tree instead, reasoning it was the fail-closed choice.

**P1 follow-on, caught by advisor consultation before `/flow:review`**: the whole-tree-oldest fix traded one wrong failure mode for another, worse one — a machine with a genuinely long-lived, multi-ecosystem cache (e.g. one ecosystem scanned eight months ago, another refreshed this morning) would have its `--offline` capability permanently refuse the fresh, actively-used ecosystem forever, the moment any unrelated sibling ecosystem's cache aged past the threshold. Confirmed as a real defect (not merely theoretical) by writing the inverse regression case — fresh PyPI db, stale unrelated npm sibling, PyPI target — and observing it RED against the whole-tree-oldest code (`expected 'ok', got 'unavailable'`). A false "permanently unavailable" is a milder failure than the original bug's false "clean," but a capability that always reports unavailable in practice is indistinguishable from one that was never shipped.

Redesigned to check staleness **per ecosystem, after invocation**, using osv-scanner's own JSON output as ground truth for which ecosystem(s) it actually resolved from the target's lockfiles (`results[].packages[].package.ecosystem` — verified live against real osv-scanner 2.4.0 for both a PyPI and an npm target, and matches this machine's real cache layout exactly: `osv-scanner/PyPI/all.zip`, `osv-scanner/npm/all.zip`). This needed no new manifest-to-ecosystem mapping to guess at, since osv-scanner already resolves ecosystem from the lockfile without touching the network or the vulnerability cache — the wrapper just reads its answer. The pre-invocation check is now narrower: it only refuses when the cache directory is missing entirely or holds no files at all (a state no per-ecosystem check could ever rescue); everything else runs the tool and validates the specific ecosystem(s) it actually consulted afterward, discarding the results and refusing retroactively if any of them is stale or has no corresponding cache subdirectory at all. Test fixtures for these cases moved from placeholder cache files (sufficient under the old pre-invocation design, where content was never read) to a stub `osv-scanner` binary, since the post-hoc design means the real tool would otherwise have to actually load the placeholder — and a real database aged past the threshold loads and scans cleanly per the AC4 investigation, so a fake/corrupt placeholder no longer exercises the same code path. Six regression cases (stale-relevant-ecosystem refuses, fresh-relevant-ecosystem passes, MAX_AGE_DAYS override widens the window, stale-target-with-fresh-sibling still refuses, fresh-target-with-stale-sibling now passes, missing-cache-subdirectory-for-the-consulted-ecosystem refuses) all RED→GREEN verified against the prior (whole-tree-oldest) code where applicable, full targeted suite re-confirmed clean (1673/1673) afterward.

**P2 — CI raw-file deletion broke the one downstream consumer that needs it.** The SEC-5 fix (see above) deleted both scanners' raw tool output before artifact upload, reasoning that "nothing in this repo currently reads these raw files directly." That premise was false for the security half specifically: `dossier-scan-security.sh`'s envelope embeds no findings of its own (unlike `dossier-scan-quality.sh`'s, which inlines `dead_code`/`complexity`), only `artifact_path` naming the raw file — and `dossier-vuln-evidence.sh --scan`'s documented input shape (`results[]`/`packages[]`/`groups[]`/`vulnerabilities[]`) *is* that raw file's shape. Deleting it left the envelope's own `artifact_path` pointing at a file the uploaded bundle no longer contained, and left the refresh job's agent with zero citable vulnerability content for the CI path — contradicting AC1's evidence-citation outcome and the goal's own "agent reads scan output" interface contract. Fixed by dropping only `pyscn-scan-raw.json`; the security raw file now survives to the artifact.

**P2 — the test covering that cleanup step wasn't actually anchored to it.** `workflow-template.test.sh`'s three SEC-5 assertions matched the *first* occurrence of a raw-output filename anywhere in the scan job's YAML block, which was the explanatory comment above the real step, not the `run:` line itself — so deleting the step, moving it after the upload, or widening it to remove the security raw file too would all still have passed. Fixed by anchoring on the literal `run: rm -f ...` line and adding a positive assertion that the security raw filename is absent from it. RED→GREEN verified against the pre-fix template.

**P3 — stale diagnostic text.** The AC1 end-to-end test's comment and failure message still named an earlier fixture (`axios 0.21.1` / `lodash 4.17.15`) after the fixture itself was changed to `django==2.0.1` / `requests==2.6.0` / `pyyaml==5.3` earlier in the session; only the wording was wrong, not the assertions. Corrected.

**P3 — silent fallthrough on an empty-but-existing cache directory.** When the offline cache directory exists but contains zero stat-able files, the guard fell through to invocation rather than refusing, relying on the real tool's own downstream failure to catch the case — which happens to hold for the real binary but is not something this wrapper's own honesty guarantee should depend on. A stub binary that succeeds regardless of cache contents would have produced `status: ok` carrying the same unearned `age-checked` claim as the P1 case. Resolved as a side effect of the P1 fix (the guard now refuses explicitly when no stat-able file is found), closed with a tripwire test (fake `osv-scanner` on `PATH`, RED→GREEN verified) proving the real binary is never invoked in that state.

## Resolved: /flow:review paired-reviewer findings (PR #144, 2 P1 + 5 P2 + 3 P3 + git-history integrity)

`/flow:review`'s Path A paired-reviewer protocol (10 agent invocations across 5 facets + 2 holdout-validation lenses) ran against PR #144 and surfaced ten findings the prior two review rounds had not caught, plus a serious out-of-band discovery in the branch's own git history. All fixed, all TDD RED→GREEN verified, full targeted suite re-confirmed clean after every commit: **1703/1703** (23 files, same two pre-existing out-of-diff files from #135 excluded).

**Git-history integrity (found by conv-skeptic-144 and conv-verifier-144 independently, both flagging the same three defects).** 11 of the branch's 24 commits were authored `Test <test@example.com>` instead of the real contributor identity. Root cause traced to this actual repository's `.git/config` carrying a local `[user]` override (`name = Test`, `email = test@example.com`) that shadowed the global identity — very likely the same unexplained isolation failure behind the earlier-session git-corruption incident (a test fixture writing against the real repo instead of an isolated copy), though the exact code path that set the local override was not conclusively identified. One commit (`f040a74`) also had a literal heredoc `EOF` delimiter leaked into its message body — a `cat <<'EOF' ... EOF` terminator that was never stripped before being passed to `git commit`. One commit (`79209de`) broke the `type(scope):` convention every other commit on the branch follows. Resolved: user manually unset the local git config override; the 11 misattributed commits were rebased with the correct author (`git rebase <base> --exec 'git commit --amend --no-edit --author=...'`), and the scope/EOF defects were fixed via a scripted `git rebase -i` (`GIT_SEQUENCE_EDITOR`/`GIT_EDITOR` set to non-interactive scripts, since this was performed by the agent after explicit user authorization for that specific step) targeting only those two commits. Verified via `git log --format='%an <%ae>'` across the full range before force-pushing with `--force-with-lease`. A stale `.git/rebase-merge` directory from an interrupted attempt was cleanly recovered with `git rebase --abort` (git's own designed-for-this recovery command; no commit had actually been rewritten yet). Separately, mid-session, the working tree ended up on a detached HEAD (most likely from a teammate review agent running `git checkout origin/<branch>` in this same shared working directory during its own re-sync) — caught before pushing, verified as a clean fast-forward from the real branch tip, and repaired with `git branch -f <branch> HEAD && git checkout <branch>` (no history rewritten, no data at risk).

**P1 — offline staleness check never fires on a clean scan (found independently by code-skeptic-144, code-verifier-144, holdout-skeptic-144, and holdout-verifier-144 — four independent reproductions against the real osv-scanner binary).** The per-ecosystem staleness redesign (see the P1 follow-on entry above) extracted consulted ecosystems from `results[].packages[]`, but real osv-scanner only lists packages that have at least one finding there — a genuinely clean scan (the majority real-world case) produces `results: []`, so the staleness loop's ecosystem list was empty and the check silently never ran, falling through to `status: ok` with a false "age-checked" claim. Every reviewer's reproduction matched: a real cache aged to 2020 plus a target with zero known vulnerabilities returned `ok` with the unearned caveat. The test suite's own stub fixtures could not have caught this — every stub fabricated a `packages[]` entry even for clean results, a shape real osv-scanner never produces (confirmed by reviewers checking the real binary directly, not assumed). **Fix**: added `--all-packages` to the offline scan invocation, which forces osv-scanner to list every resolved package regardless of vulnerability status — verified live that this changes nothing else observable (exit-code semantics and vulnerability data for genuinely-vulnerable packages are identical with or without it). Closed with both a stub-based argv-capture tripwire (proving the flag reaches the tool) and a real end-to-end test against a genuinely clean, currently-unpatched dependency (`tomli==2.0.1`) scanned against a real, artificially-aged cache.

**P1 — `emit()`'s `--out` write failure suppressed the whole JSON envelope (found and reproduced independently by err-skeptic-144 and err-verifier-144).** Both wrapper scripts computed and validated `$RESULT` before attempting to also write a copy to `--out`; a failed write (bad path, permissions, disk full) `exit 1`'d without ever printing the already-computed result to stdout, contradicting the documented "exit 0 for every reported case" contract and reachable even on the "disabled" (default-config, safest) status path. Fixed by printing `$RESULT` unconditionally before the `--out` write attempt; a failed write is now a stderr warning, not a fatal, envelope-suppressing exit.

**P2s (5, several found by multiple reviewers independently):** malformed `DOSSIER_SCAN_TIMEOUT_SECONDS` silently disabled the timeout guard (comparison error read as false); malformed `DOSSIER_SCAN_OFFLINE_MAX_AGE_DAYS` crashed under `set -u` with no JSON envelope at all — both now validated with a fallback to their documented defaults. The CI `scan` job's four steps (security-scan, quality-scan, cleanup, upload) had no `always()`/`continue-on-error` between them, so a hard failure in one silently skipped the rest — even though the two capabilities are explicitly designed to be independent; fixed by adding `if: always()` to all four, matching the `refresh` job's own existing reasoning one level up. `enforce-allowed-actions.sh`'s `WRAPPER` token list was missing `python`/`python3`, so `python3 -m pyscn ...` (an ordinary invocation shape for a pip-installed tool) bypassed the `runCodeQualityScan` deny check while `env`/`sudo`-wrapped forms were correctly caught — added both tokens. `dossier-vuln-evidence.sh`'s alias-summary lookup took the first array-order matching id's summary rather than the first *non-empty* one — reproduced against this issue's own real e2e fixture (django/requests/pyyaml): 4 of 12 real findings shipped a blank summary because a PYSEC-prefixed id with a null summary sorted before a GHSA-prefixed alias with a real one; fixed to filter out no-summary candidates before selecting first. `skills/evidence-ledger/SKILL.md` still said "Dossier never executes a scanner" and never referenced the new `.dossier/scan/` bundle — the doc that actually drives the refresh agent's behavior, unlike the reference doc which was already updated — corrected to point at both the CI-produced bundle and pre-existing project artifacts.

**P3s (3):** `dossier-scan-security.sh`'s `--help` range had gone out of sync with its own header (widened across this session's earlier edits without the `sed` range following) and was truncating before the exit-code contract — the other two scripts had been kept in sync, this one hadn't. The `mktemp -d` fallback path in both scripts (only reached when `mktemp` itself fails) now `chmod 700`s the resulting directory rather than leaving a predictable, unrestricted path in shared `/tmp`. Neither script trapped `INT`/`TERM`, so a locally-interrupted wrapper never signaled its backgrounded tool child, orphaning it — both now trap and clear on normal exit.

**Test coverage additions (no bug, already-correct code per independent read-throughs by test-verifier-144, err-skeptic-144, and sec-skeptic-144):** a plain file (not a directory) as `--target`; a readable-but-not-enterable directory as `--target` (the exact case the scripts' own header comments call out `-x` for, checked separately from `-r`); each script's own malformed-tool-output branch (non-JSON osv-scanner stdout at exit 0; an invalid-JSON pyscn report file). One of these (the noexec-directory check) was spot-verified as genuinely discriminating, not vacuous, by neutering the underlying `-x` check in a scratch copy and confirming the new test fails against it.

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

<!-- auto-log: 2026-07-28 21:56 commit "fix(dossier): detect offline vulnerability-DB staleness (AC4)" -->

<!-- auto-log: 2026-07-28 22:02 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T172831Z-issue-137/run.yaml -->

<!-- auto-log: 2026-07-28 22:33 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-137.goal.yaml -->

<!-- auto-log: 2026-07-28 22:33 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->

<!-- auto-log: 2026-07-28 22:39 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac6-eval-5.evidence.yaml -->

<!-- auto-log: 2026-07-28 22:48 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-137.goal.yaml -->

<!-- auto-log: 2026-07-28 22:49 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->

<!-- auto-log: 2026-07-28 22:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac4-eval-2.evidence.yaml -->

<!-- auto-log: 2026-07-28 22:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac5-eval-2.evidence.yaml -->

<!-- auto-log: 2026-07-28 22:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac7-eval-2.evidence.yaml -->

<!-- auto-log: 2026-07-28 22:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac5-eval-2.evidence.yaml -->

<!-- auto-log: 2026-07-28 22:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-07-28 23:02 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac5-eval-3.evidence.yaml -->

<!-- auto-log: 2026-07-28 23:02 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/evidence-ac7-eval-3.evidence.yaml -->

<!-- auto-log: 2026-07-28 23:09 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue137-verdict.json -->

<!-- auto-log: 2026-07-28 23:28 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue137-lifecycle.yaml -->

<!-- auto-log: 2026-07-28 23:28 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue137-lifecycle.yaml -->

<!-- auto-log: 2026-07-28 23:29 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/issue137-lifecycle.yaml -->

<!-- auto-log: 2026-07-28 23:30 commit "test(dossier): assert CI refresh job's tool allowlist excludes find/xargs/scanners (AC5)" -->

<!-- auto-log: 2026-07-29 10:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 10:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 10:48 commit "fix(dossier): refuse --offline scans when the cache directory is wholly missing (ERR-1)" -->

<!-- auto-log: 2026-07-29 10:48 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-29 10:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/quality-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 10:50 commit "fix(dossier): kill the real pyscn process on timeout, not the wrapping subshell (ERR-2)" -->

<!-- auto-log: 2026-07-29 10:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 10:51 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 10:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 10:54 commit "fix(dossier): defense-in-depth for offline-DB-unavailable detection (ERR-3)" -->

<!-- auto-log: 2026-07-29 10:55 Edit /Users/danielbentes/synapti-marketplace/.github/workflows/dossier-tests.yml -->

<!-- auto-log: 2026-07-29 10:55 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-29 10:55 Edit /Users/danielbentes/synapti-marketplace/.github/workflows/dossier-tests.yml -->

<!-- auto-log: 2026-07-29 10:56 commit "fix(dossier): pin pyscn install to --no-deps, verify osv-scanner before it lands on PATH" -->

<!-- auto-log: 2026-07-29 10:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/hooks/scripts/enforce-allowed-actions.sh -->

<!-- auto-log: 2026-07-29 10:56 commit "docs(dossier): remove agent-memory cross-link syntax from a shipped comment" -->

<!-- auto-log: 2026-07-29 10:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-29 10:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-07-29 10:58 commit "fix(dossier): drop un-annotated raw scan output from the uploaded CI artifact (SEC-5)" -->

<!-- auto-log: 2026-07-29 10:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 10:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 10:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-29 10:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 10:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-quality.sh -->

<!-- auto-log: 2026-07-29 11:00 commit "fix(dossier): canonicalize target paths, check -x, surface setup failures, fix --help ranges" -->

<!-- auto-log: 2026-07-29 11:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 11:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 11:23 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 11:24 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 11:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 11:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 11:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/ci/dossier-docs-refresh.yml -->

<!-- auto-log: 2026-07-29 11:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/workflow-template.test.sh -->

<!-- auto-log: 2026-07-29 11:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 11:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 11:37 commit "fix(dossier): key offline staleness guard on oldest cache file, not newest" -->

<!-- auto-log: 2026-07-29 11:40 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-msg-p2.txt -->

<!-- auto-log: 2026-07-29 11:40 commit "fix(dossier): retain osv-scanner raw output for downstream evidence citation" -->

<!-- auto-log: 2026-07-29 11:41 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->

<!-- auto-log: 2026-07-29 11:43 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr-body-137.md -->

<!-- auto-log: 2026-07-29 11:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 11:49 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 11:50 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scan-security.sh -->

<!-- auto-log: 2026-07-29 11:52 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-scan-execution.test.sh -->

<!-- auto-log: 2026-07-29 11:58 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->

<!-- auto-log: 2026-07-29 11:58 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-msg-p1-followon.txt -->

<!-- auto-log: 2026-07-29 11:58 commit "fix(dossier): check offline staleness per ecosystem, after invocation" -->

<!-- auto-log: 2026-07-29 12:00 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/pr-body-137.md -->

<!-- auto-log: 2026-07-29 13:07 commit "fix(dossier): close the python3 -m pyscn bypass on the deny backstop" -->

<!-- auto-log: 2026-07-29 13:07 commit "fix(dossier): use the first alias summary that actually has one" -->

<!-- auto-log: 2026-07-29 13:07 commit "docs(dossier): point evidence-ledger at the new isolated-scan capability" -->

<!-- auto-log: 2026-07-29 13:08 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-137.md -->
