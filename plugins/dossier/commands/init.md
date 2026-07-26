---
description: "Initialize a dossier documentation package. Resolves the engagement inputs, classifies the project from evidence, writes .claude/settings.dossier.json, scaffolds the 23 canonical files, and seeds the five control registers."
argument-hint: [project-name] [--output-root <path>] [--mode full|targeted|verification-only] [--non-interactive]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, AskUserQuestion
---

# Initialize Documentation Package: $ARGUMENTS

Create the package skeleton and its configuration. Writes structure and registers — never prose. Drafting is `/dossier:baseline`.

## Required Skills

- `engagement-scoping` — resolve and freeze the twelve engagement inputs, the action ceiling, and the delivery mode
- `doc-package-contract` — the 23-file structure, headers, and the scaffold contract
- `evidence-ledger` — seed the ledger and its executed-checks section
- `gap-and-contradiction-register` — seed the assumptions, questions, and contradiction registers
- `disclosure-gating` — seed the claim and disclosure register with the resolved policy

## References

- [`config-resolution.md`](../references/config-resolution.md)
- [`document-headers.md`](../references/document-headers.md)
- [`project-type-adaptation.md`](../references/project-type-adaptation.md)
- [`register-schemas.md`](../references/register-schemas.md)

## Phase 0 — Preflight

```!
_RAW="$ARGUMENTS"
echo "### Init Arguments"
echo "ARGS=$_RAW"

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-resolve-config.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-resolve-config.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Plugin"
if [ -x "$__dr/bin/dossier-resolve-config.sh" ]; then
  echo "DOSSIER_ROOT=$__dr"
else
  echo "DOSSIER_STATE=blocked"
  echo "DOSSIER_ERROR=dossier-resolve-config.sh not found — reinstall or upgrade the dossier plugin"
  true; exit 0
fi

echo "### Existing State"
OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "SETTINGS_EXISTS=$([ -f .claude/settings.dossier.json ] && echo true || echo false)"
echo "USER_SETTINGS_EXISTS=$([ -f "$HOME/.claude/settings.dossier.json" ] && echo true || echo false)"
echo "PACKAGE_EXISTS=$([ -d "$OUTPUT_ROOT/00-control" ] && echo true || echo false)"
if [ -d "$OUTPUT_ROOT" ]; then
  echo "EXISTING_FILES=$(find "$OUTPUT_ROOT" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
else
  echo "EXISTING_FILES=0"
fi

echo "### Repo"
echo "REPO=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || echo unknown)"
echo "COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "IS_GIT=$([ -d .git ] && echo true || echo false)"
true
```

If `PACKAGE_EXISTS=true`, this is a re-initialization. Never overwrite an existing document — report what exists and offer to fill only the gaps.

## Phase 1 — Classify the project

Invoke `Skill(engagement-scoping)`.

Classify from evidence before asking anything: manifests, entry points, deployment definitions, published packages, model artifacts, firmware sources. Record the classification with its supporting evidence IDs — the classification changes emphasis, so a wrong one produces a subtly wrong package.

Detect and report: languages and frameworks · package manifests and registries · services and deployment units · schemas and migrations · interface definitions · CI workflows · test suites · existing documentation.

## Phase 2 — Resolve engagement inputs

For each unresolved input, use `AskUserQuestion` with 2–4 concrete options and a stated recommendation. Never open-ended prompts.

Ask only about what is genuinely blocking for the chosen delivery mode:

| Input | Blocking in | Never infer |
|---|---|---|
| `project.name` | `full`, `targeted` | Yes — it propagates into every header and every public document |
| `project.sources` | `full`, `targeted` | Yes |
| `disclosure.policy` | all | Yes — defaults to `internal-only`, which is safe, not a guess |
| `engagement.dueDiligenceContext` | none | Absent produces a general readiness assessment |

`--mode full|targeted|verification-only` presets `engagement.deliveryMode` and skips the question. `--output-root <path>` does the same for `project.outputRoot`. A flag-supplied value is a deliberate operator choice: record it and do not re-ask.

With `--non-interactive`, take defaults for everything non-blocking and record each blocking gap as an `AQ-####` row rather than asking.

Read `$HOME/.claude/settings.dossier.json` first and **skip any key the user already set there** — project-shared beats user-global in the cascade, and silently overriding a user's global preference is the kind of surprise that makes people distrust setup commands. On conflict, `AskUserQuestion`.

Write `.claude/settings.dossier.json`, then validate:

```bash
bin/dossier-validate-config.sh --config .claude/settings.dossier.json
```

Resolve every finding before scaffolding. A config whose containment guarantees do not hold produces a package that cannot be trusted, and finding that out in Phase 5 wastes the run.

## Phase 3 — Scaffold

```bash
bin/dossier-scaffold.sh --output-root "$OUTPUT_ROOT"
bin/dossier-package-check.sh --output-root "$OUTPUT_ROOT"
```

The scaffold is idempotent and never overwrites. `dossier-package-check.sh` will report unfilled headers — expected at this stage, since nothing has been drafted.

Append to `.gitignore`, idempotently:

```bash
for IGNORE in '.dossier/' '.claude/settings.dossier.local.json' '.claude/*.lock'; do
  if [ -f .gitignore ]; then
    grep -qxF "$IGNORE" .gitignore || echo "$IGNORE" >> .gitignore
  else
    echo "$IGNORE" > .gitignore
  fi
done
```

## Phase 4 — Seed the registers

Invoke `Skill(evidence-ledger)`, `Skill(gap-and-contradiction-register)`, and `Skill(disclosure-gating)` to write the register headers and their column schemas into the four control documents.

Seed with what Phase 1 established: the project classification and its evidence, the source inventory, and every blocking gap from Phase 2 as an `AQ-####` row. The registers are never empty after init — an empty register and an unpopulated register look identical, and only one of them is honest.

Invoke `Skill(doc-package-contract)` to write `00-control/documentation-index.md` from the actual file list.

## Phase 5 — Report

```markdown
### Package initialized

OUTPUT_ROOT={path}  PROJECT_TYPE={type}  DELIVERY_MODE={mode}
FILES_CREATED={n}  FILES_SKIPPED={n}  BLOCKING_GAPS={n}

| Register | Seeded rows |
|---|---|

### Next
1. `/dossier:baseline` — inventory evidence and draft the package
2. `/dossier:setup` — wire the post-merge documentation refresh
```

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read project sources for classification | 1 | Autonomous, read-only |
| Read `$HOME/.claude/settings.dossier.json` for cascade-conflict detection | 1 | Autonomous, read-only |
| `mkdir -p` the output root and `.claude/` | 1 | Autonomous |
| Write `.claude/settings.dossier.json` | 1 | Autonomous, project file |
| Skip a key the user already set in user-global settings | 2 | `AskUserQuestion` per conflict; default preserves the user's preference |
| Append `.gitignore` entries (idempotent `grep -qxF`) | 1 | Autonomous |
| Scaffold the 23 canonical files | 1 | Autonomous, never overwrites |
| Seed the five control registers | 1 | Autonomous |
| Overwrite an existing canonical document | 3 | **Never automated.** Report and offer gap-filling only |
| Committing anything init wrote | 3 | **Never automated.** The user reviews the diff and commits |
