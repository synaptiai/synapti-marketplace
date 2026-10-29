# Goal Evidence Ledger Detail

Detail for `skills/goal-evidence-ledger/SKILL.md`.

## What `bin/flow-record-evidence.sh` guarantees

The helper writes atomically (tempfile + rename via `_journal_atomic.py`), refuses symlinked targets and lockfiles, validates the schema when `jsonschema` is installed, and copies the raw output next to the sidecar, setting the sidecar's `output_ref` to the copy's name; it refuses a sidecar whose `output_ref` names another file, and an id already recorded (a correction is a new id). It copies the raw output whole and synced before it writes the sidecar, so a refused or short copy leaves neither, and a sidecar that cannot be written takes its copy away again; once the sidecar is written, the copy stays; of two overlapping records of one id, the second is refused (exit 2).

## Related

- `plugins/flow/skills/evidence-based-development/SKILL.md` — the ASSERTION/EVIDENCE/VERIFIED discipline this ledger materializes.
- `plugins/flow/references/evidence-bundle-format.md` — the bundle layout the judge consumes.
