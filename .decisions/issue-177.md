# Issue #177 — agentTeams gate failures, unreached root tests, undeclared PyYAML

Branch: `feature/issue-177-agentteams-gate-ci-coverage`
Closes #177, #130, #175.

Three reports grouped into one change because two of them edit the same block of
`plugins/flow/commands/review.md` and the third is the dependency half of the same
"nothing runs it / nothing declares it" gap.

## Specification

### Non-goals

- Changing what the agentTeams gate decides for a well-formed settings file. The
  precedence order, the two-key requirement (`agentTeams: true` plus the env var) and the
  treatment of a JSON string as non-canonical all stay exactly as they are.
- Changing the shared plugin-root resolver in `references/plugin-root-resolution.md` or the
  eighteen other command files that use it. The resolver's contract — a root is a directory
  holding an executable `bin/cascade-resolve.sh` — is correct for finding flow's binaries
  and stays untouched.
- Porting the root `tests/` scripts onto the `plugins/flow/tests/` assert harness, or
  deleting any of them.
- Vendoring PyYAML, or adding an installer that fetches it.
- Rewording anything in `review.md` outside the gate block.

### Failure modes

- **A settings file the gate cannot parse.** Warn naming the file, skip that source, keep
  going. A typo in one tier must not silently disable the feature when a lower tier has a
  definitive value.
- **`CLAUDE_PLUGIN_ROOT` set to a path with no `settings.json`.** Warn naming the path and
  fall through to Path B, rather than silently treating the tier as absent.
- **`CLAUDE_PLUGIN_ROOT` unset.** Fall back to discovery, unchanged from today.
- **A root test script that hangs.** The CI job carries a timeout so a hung script fails the
  build rather than burning the runner's whole budget.
- **A root test script that is not executable.** The job finds scripts by name, not by the
  executable bit, so a lost `chmod +x` cannot silently drop a check.
- **PyYAML absent at runtime.** Every entry point already preflights and degrades; this
  change only adds the declaration and the documentation. No new failure path.

### Interface contracts

- The gate block stays delimited by `# AGENTTEAMS_GATE_BEGIN` / `# AGENTTEAMS_GATE_END`,
  because `tests/agentteams-gate/test.sh` extracts it by those markers.
- The gate keeps emitting `USE_PATH_A=0|1` and keeps sending diagnostics for states (a) and
  (b) to stderr and state (c) to stdout — the test asserts each channel.
- `PLUGIN_SETTINGS` becomes `${CLAUDE_PLUGIN_ROOT:-<discovered root>}/settings.json`, which
  is what the block's own header comment has always documented.
- The PyYAML constraint is written once, in a manifest, and both workflows read the same
  string. A test compares them.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Plugin-tier path resolution | Honour `CLAUDE_PLUGIN_ROOT` unconditionally, including when it points at a directory with no `settings.json` — the broken-install warning then stops firing | S4b and S9 both set `CLAUDE_PLUGIN_ROOT` to a non-existent path and require the warning to name it |
| Plugin-tier path resolution | Keep the resolver and merely append `CLAUDE_PLUGIN_ROOT` as one more candidate — a cache root holding an older flow would still win over the caller's explicit choice | S6 sets `CLAUDE_PLUGIN_ROOT` to a directory holding only `settings.json` and requires that file's value to be the one used |
| Apostrophe removal | Reword the five comments but leave an apostrophe in a comment somewhere else in the block, so the count stays odd | The test counts every `'` in the extracted block and requires an even total, rather than checking the five known lines |
| Root-test CI job | Run only `tests/*/test.sh` and miss `validate.sh` and `verify.sh`, so two checks stay unreached | The job's discovery is asserted against the actual file list, and the test names the count it found |
| PyYAML pin agreement | Assert the manifest and the workflows are equal by reading the same variable twice, so a drifted pin still passes | The test parses each of the three files independently and compares the three parsed strings |

## Stranger Test

PASS — 5 tasks reviewed.

<!-- auto-log: 2026-09-10 22:22 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-177.md -->

<!-- auto-log: 2026-09-10 22:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-10 22:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-10 22:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-10 22:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-10 22:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-10 22:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-10 22:23 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-gate-portability.test.sh -->

<!-- auto-log: 2026-09-10 22:24 Write /Users/danielbentes/synapti-marketplace/tests/run-all.sh -->

<!-- auto-log: 2026-09-10 22:25 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/root-tests-runner.test.sh -->

<!-- auto-log: 2026-09-10 22:25 Edit /Users/danielbentes/synapti-marketplace/tests/run-all.sh -->

<!-- auto-log: 2026-09-10 22:25 Edit /Users/danielbentes/synapti-marketplace/tests/run-all.sh -->

<!-- auto-log: 2026-09-10 22:25 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/root-tests-runner.test.sh -->

<!-- auto-log: 2026-09-10 22:25 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/root-tests-runner.test.sh -->

<!-- auto-log: 2026-09-10 22:26 Write /Users/danielbentes/synapti-marketplace/plugins/flow/requirements.txt -->

<!-- auto-log: 2026-09-10 22:26 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/README.md -->

<!-- auto-log: 2026-09-10 22:27 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/python-requirements.test.sh -->

<!-- auto-log: 2026-09-10 22:28 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/dc7f4a8b-35f7-421a-bb8a-d409456c7eb7/scratchpad/pr-a-body.md -->

<!-- auto-log: 2026-09-10 22:30 commit "fix(flow): the agentTeams gate lost its plugin tier, and its block would not parse on Windows" -->

<!-- auto-log: 2026-09-10 22:30 commit "test(flow): run the repository-root checks in CI" -->

<!-- auto-log: 2026-09-10 22:30 commit "docs(flow): declare the PyYAML runtime requirement" -->

<!-- auto-log: 2026-09-10 22:37 Edit /Users/danielbentes/synapti-marketplace/tests/run-all.sh -->
