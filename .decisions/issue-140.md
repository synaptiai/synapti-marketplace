---
issue: 140
created: '2026-08-03T14:45:00Z'
---
# Issue #140 — evaluate support for the Open Knowledge Format (OKF)

**Title**: dossier: evaluate support for the Open Knowledge Format (OKF)
**Labels**: enhancement, plugin

## Decision

**Defer.** Dossier does not adopt OKF interoperability at this time, and does not decline it
outright. This is a documentation-only decision — no code, branch, or PR follows from it.

## Reasoning

Verified directly against the current codebase before deciding, not assumed from the issue's
own description:

- **Evidence-model comparison holds up.** Dossier's six claim states (V/C/R/I/U/N/A), seven
  source-authority levels, `EV-####` append-only evidence ledger, and actively-enforced
  staleness trigger are substantially more rigorous than OKF's three-tier trust (derived from a
  single `verified` field) and passive `stale_after` date comparison. OKF solves a different,
  lighter-weight problem (generic knowledge-catalog browsability) than dossier's investor-grade
  evidence rigor.
- **The flat-scalar-header incompatibility is real, not assumed.** Confirmed by direct search:
  the only place any dossier bash script imports a YAML library (`import yaml` /
  `yaml.safe_load`) is `plugins/dossier/tests/workflow-template.test.sh`, and that use is
  test-only — parsing the CI workflow config, unrelated to document-header parsing. Dossier's
  actual production document-header parsing (`dossier-staleness-check.sh`,
  `dossier-validate-patch.sh`, `dossier-package-check.sh`, `dossier-managed-file.sh`, and
  others) is genuinely awk/shell-only, with no YAML-library dependency anywhere. Adopting OKF's
  nested `generated`/`verified`/`sources` frontmatter as dossier's *own* header format would
  introduce a new parsing dependency dossier has deliberately avoided everywhere else — this
  claim in the issue body is accurate, not overstated.
- **The export-sidecar approach is technically low-risk, but that isn't the blocker.** An
  optional OKF-conformant sidecar emitted alongside dossier's own authoritative header would not
  touch dossier's own evidence model at all — the technical path is genuinely available if ever
  needed. The reason not to build it now is that there is no confirmed consumer: no tool,
  integration, or user request anywhere in this project currently wants OKF-conformant output,
  and OKF itself is pre-1.0 (v0.2), so committing engineering effort now risks rework against a
  moving target with no offsetting demand.
- **No prior art in this repo.** A repo-wide search for "OKF", "Open Knowledge Format", and
  "knowledge-catalog" found zero references outside this issue — this is a fresh evaluation, not
  revisiting a prior partial implementation.

## Re-evaluation trigger

Re-evaluate this decision when **either** of the following becomes true (not both required):

1. A specific tool, integration, or user names a concrete need to browse a generated
   `docs/dossier` package via OKF-aware generic tooling (a search index, graph viewer, Obsidian
   vault, MkDocs site, etc.) — demand-driven, not speculative.
2. OKF reaches a stable v1.0 release — reducing the risk that adopting its frontmatter shape
   today means reworking against a still-moving format.

## Confirmation

- This work is not inserted into the active dossier initiative sequence (issues #135–#138 and
  their follow-ons) and does not block it — per the issue's own AC4, restated here for the
  record.
- Decided via a direct interview with the user (three alternatives presented: adopt an export
  layer now, decline outright, defer with a named trigger), grounded in the codebase research
  above rather than the issue body's claims alone.
