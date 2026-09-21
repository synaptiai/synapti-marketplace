---
issue: 217
created: '2026-09-21T11:55:18Z'
artifacts:
- type: specification
  captured_at: '2026-09-21T11:55:18Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---
# Decision Journal — Issue #217

feat(flow): security-reviewer judges new and bumped dependencies, and those findings enter the ledger

## Specification

### Non-goals

- A network-dependent judgment. `bin/flow-dep-diff.sh` is deterministic and offline: it reads the
  diff and the base commit through `git` and nothing else. The license read in the agent may reach
  the network, and a read that fails reports that it failed (see Interface contracts) rather than
  answering as though the package declared nothing.
- A vulnerability database. The advisory signal keeps coming from the tools already in Step 4
  (`npm audit`, `bundle audit`, `pip-audit`). This issue does not add, vendor, or cache one.
- Removing the Dependency Audit table. It stays exactly as it is, as telemetry. What changes is that
  a judgment about an added or bumped package also becomes a `DEP-` finding the ledger can see.
- A dependency policy file. There is no allowlist, no denylist, and no configurable license matrix.
  The project's declared license is read from `LICENSE` or a manifest field; a conflict is escalated
  to a human because it is not the agent's decision.
- Resolving transitive dependencies. Only packages named in a manifest or lockfile the diff touches
  are judged. A transitively-introduced package is out of scope.
- A seventh fan-out agent. The judgment is a conditional step inside `security-reviewer`, which
  already runs the audits, so it costs nothing on a pull request that touches no manifest.

### Failure modes

- **Timeouts**: the helper makes no network call, so it cannot hang on one. The agent's license read
  can (`npm view`, `go list -m`). A read that times out or fails is reported as
  `license undetermined` at P2/MEDIUM — never as `no license`, which is a P1 escalation.
- **Partial failures**: a diff touching four manifests where one does not parse reports the three it
  read, plus `MANIFEST_UNPARSED=<path>` for the fourth and `STATE=unavailable` with a `REASON=`.
  The packages it did read are not withheld, and the file it could not read is named.
- **Invalid input**: a package name or version carrying a control character, a newline, or a `|` is
  refused rather than printed — the manifest is author-controlled content inside the pull request
  under review. A malformed manifest line is reported as `MANIFEST_UNPARSED`, not silently skipped.
- **Missing context**: a base ref that does not resolve is `STATE=unavailable` with the reason, not
  `STATE=none`. `git show <base>:<path>` failing for a manifest added by this pull request is the
  normal added-file case and yields an empty baseline, not an error.

### Interface contracts

- `bin/flow-dep-diff.sh --base <ref> --head <ref>` prints, per
  `references/command-output-format.md`:
  - `STATE=ok|none|unavailable`, `REASON=<why>` (on `unavailable` and `none`)
  - `MANIFESTS_EXAMINED=<n>` — manifests in the diff the helper attempted to read
  - `DEP_ADDED=<name>@<version> manifest=<path>:<line>`
  - `DEP_CHANGED=<name> <old>→<new> manifest=<path>:<line>`
  - `DEP_REMOVED=<name> manifest=<path>:<line>`
  - `DEP_BASELINE=<name>` — one per package present in the manifest at the BASE commit, so the
    near-name check has a baseline the pull request does not control
  - `MANIFEST_UNPARSED=<path> reason=<why>` — one per manifest in the diff that could not be read
  - Ecosystems: npm (`package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`), Python
    (`requirements*.txt`, `pyproject.toml`, `poetry.lock`), Go (`go.mod`, `go.sum`), Rust
    (`Cargo.toml`, `Cargo.lock`), Ruby (`Gemfile`, `Gemfile.lock`).
  - Every printed value is collapsed to one line and refused if it carries a control character,
    following `bin/cascade-resolve.sh --scalar` and `bin/flow-review-exceptions.sh`.
- `MANIFESTS_EXAMINED=0` with `STATE=none` means no manifest was in the diff. `MANIFESTS_EXAMINED=1`
  with zero `DEP_` lines means a manifest was read and nothing about its dependencies changed. These
  are different answers and neither is spelled as the other.
- `DEP-` findings use the canonical schema in `references/finding-schema.md` with
  `category=dependency` and `location=<manifest>:<line>`:

  | Condition | Priority | Confidence |
  |---|---|---|
  | Critical or high advisory with a fix available | P1 | HIGH |
  | License the project's declared license cannot include, or the package declares none | P1 + six-field escalation | HIGH |
  | License could not be determined (lookup failed, offline, package not installed) | P2 | MEDIUM |
  | Install hooks (`preinstall`/`postinstall`, `build.rs`) | P2 | HIGH |
  | Added name within edit distance 2 of an existing `DEP_BASELINE=` name | P2 | MEDIUM |
  | Added but no file in the diff imports it | P3 | LOW |

- `references/finding-schema.md` gains `dependency` in the category vocabulary and `DEP-` in the ID
  prefix table.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Absent vs unreadable | A manifest the parser cannot read prints `STATE=none`, telling the reviewer no dependency changed when the pull request added one | A fixture whose diff touches a Gemfile the parser cannot read prints `STATE=unavailable`, a `REASON=`, and `MANIFEST_UNPARSED=Gemfile`; it never prints `STATE=none` |
| Examined vs absent | "A manifest changed but no dependency did" and "no manifest changed" collapse to the same output | `92fd253..4519858` prints `MANIFESTS_EXAMINED=1` with two `DEP_ADDED=` lines; a comment-only manifest edit prints `MANIFESTS_EXAMINED=1` with zero `DEP_` lines; `4519858..HEAD` prints `MANIFESTS_EXAMINED=0` |
| Undetermined vs unlicensed | A failed license lookup raises the P1 "no license" escalation, so an offline run blocks every pull request | A fixture with an unresolvable package yields a P2/MEDIUM `license undetermined` row and no P1 escalation row |
| Import-name aliasing | `pyyaml` is reported as never imported because the code writes `import yaml`, so every Python pull request carries a false P3 | The `pyyaml` case is asserted to carry confidence LOW, which `bin/flow-finding-route.sh` keeps out of the review decision |
| Baseline trust | The near-name baseline is read from the pull request head, so a pull request can introduce both the typosquat and the name it mimics | The baseline is read with `git show <base>:<path>`; a fixture whose head adds a package to the manifest does not see it in `DEP_BASELINE=` |
| Value forgery | A package name or version carrying a newline or `|` splits the output into forged extra records | A fixture manifest whose version field holds a newline and a `|` is refused, and the refusal names the manifest rather than printing the value |

## Decisions (AskUserQuestion, 2026-09-21)

- Unreadable manifest: `STATE=unavailable` + `REASON=` + per-file `MANIFEST_UNPARSED=`, mirroring
  `bin/flow-review-exceptions.sh`. Rejected: refusing the whole run; the issue's `STATE=none`-only
  shape.
- Failed license lookup: a separate P2/MEDIUM `license undetermined` finding, distinct from the P1
  "declares no license" escalation. Rejected: folding both into P1; skipping silently.
- Added-but-unimported: emitted at LOW confidence, so `bin/flow-finding-route.sh` keeps it out of the
  review decision. `pyyaml`/`import yaml` is the discriminating fixture. Rejected: an alias table
  (a list that is wrong the first time it meets a package it does not know); dropping the check.
- Near-name baseline: the helper prints `DEP_BASELINE=` rows parsed from the manifest at the BASE
  commit. Rejected: leaving the comparison to the agent, where nothing can test that it ran.
- Issue body: AC3 was rewritten to name `agents/security-reviewer.md`, the only file carrying the
  claim it asked to remove. Verified live before the branch was created.
