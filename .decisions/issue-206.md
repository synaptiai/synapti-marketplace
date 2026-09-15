---
issue: 206
created: '2026-09-15T00:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-09-15T00:00:00Z'
  by: manual
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---
# Issue #206 — `--help` hardcoded-range truncation (`sed -n '2,Np'`) across 16 bin scripts

## Specification

### Non-goals

- Not touching `dossier-scaffold.sh` or `dossier-prose-lint.sh` — both already carry the self-terminating
  `sed -n '2,/^$/p' "$0"` fix (issues #178 and #180) and serve as the reference pattern here.
- Not rewriting or restyling any header comment block — only the `-h|--help` extraction range changes.
- Not changing any other flag, output format, or exit code in the 16 scripts.
- Not adding a generic shared "print my own header" helper function — each script keeps its own inline
  `-h|--help)` case arm, matching the existing per-script style (including `dossier-package-check.sh`'s
  piped `sed 's/^# \{0,1\}//'` filter, preserved as-is).

### Failure modes

- **Truncation regression re-introduced later** — a future header edit could again drift past a
  hardcoded bound; the self-terminating `2,/^$/p` range removes the failure mode structurally (it
  always reads to the header's first blank line) rather than requiring a maintainer to keep a magic
  number in sync.
- **Over-read past the header** — if a script's header comment block does not end with a body-adjacent
  blank line before code, `2,/^$/p` could read further than intended. Verified not to occur in any of
  the 16 scripts: every header's first post-line-1 blank line lands immediately before `set -uo
  pipefail` (or, for `dossier-package-check.sh`, before the variable declarations), never mid-header.
- **Piped-filter case mishandled** — `dossier-package-check.sh` pipes the extracted range through
  `sed 's/^# \{0,1\}//'` to strip the leading `# ` comment marker. Only the `sed -n` range changes;
  the pipe and filter are left untouched, mirroring `dossier-scaffold.sh`'s already-fixed identical
  pattern exactly.

### Interface contracts

- CLI contract unchanged for all 16 scripts: same flags, same exit codes, same stdout/stderr contract
  for every non-help invocation.
- `--help` (or `-h`) output changes only in that it now reliably prints the *entire* header comment
  block through its first blank line, instead of stopping at a hardcoded line number that may or may
  not still match the header's true length. For all 16 scripts as of this change, the hardcoded bound
  either already matched the header end or under-shot it (silent truncation, the bug this closes); in
  two cases (`dossier-gate.sh`, `dossier-validate-patch.sh`) the hardcoded bound had drifted *past* the
  header into leading code lines (`set -uo pipefail`, blank, first variable assignment) — the fix also
  corrects that direction of drift, since `--help` printing code lines was never intended output either.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Wrong line touched | an edit to the `-h\|--help)` line accidentally changes an adjacent flag's parsing (e.g. merges into the next case arm) | `bash -n` on every changed script, plus the full `run.sh` suite's existing usage-error assertions (exit 2 on unknown flag) for each of the 16 |
| Piped-filter case dropped | `dossier-package-check.sh`'s fix drops the `\| sed 's/^# \{0,1\}//'` filter, changing its `--help` output to include leading `# ` markers | diff review of that one line; regression assertion checks the *rendered* (post-filter) last line, which would fail if markers leaked through |
| Header not fully reached | the self-terminating range still stops early because of an unexpected blank line mid-header (e.g. inside a "NOTE:" paragraph) in one of the 16 scripts | regression assertion per script asserts the header's actual LAST documented line (not an early line) appears in `--help` output — this would have caught the original bug and catches this failure mode identically |
| Unrelated line altered | a find-replace across 16 files accidentally touches an unrelated `sed -n` invocation elsewhere in the same script (several scripts use `sed` internally for non-help purposes) | per-file diff reviewed individually; each diff is a single-line change (two lines for the one piped-filter case) |
