---
issue: 205
title: "fix(dossier): scaffold's CWD-relative template fallback can source content from the repo being documented"
branch: fix/issue-205-scaffold-template-fallback
artifacts:
- type: specification
  by: manual-orchestrator
  captured_at: '2026-09-15T17:23:53Z'
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
created: '2026-09-15T17:23:53Z'
---

## Specification

### Non-goals

- Not fixing the same three-tier `CLAUDE_PLUGIN_ROOT` / `SCRIPT_DIR` / CWD-relative pattern in `dossier-package-check.sh` (`references/` resolution) — a distinct call site with its own risk profile (references are read-only reference material, not copied into the output package), out of scope for this issue and not mentioned in its acceptance criteria.
- Not changing the symlink/type-confusion/atomic-write guards added by #178/PR #204 — this fix only removes a resolution candidate; the guards around it are untouched.
- Not adding a generic "verify this is a real plugin install" marker-file mechanism — removal of the CWD-relative candidate is sufficient and simpler than gating it, per the AC3 audit (below) finding no legitimate caller depends on it.
- Not touching `--templates`/`--readme-template` explicit-override behavior — those are caller-supplied and already trusted the same way they were before.

### Failure modes

- **Before the fix**: `CLAUDE_PLUGIN_ROOT` unset *and* the script's own location can't produce a valid `../templates/package` (e.g. the script was copied/symlinked elsewhere, or invoked in a way that breaks `$0`-relative resolution) → silently falls through to a bare `plugins/dossier/templates/package` read from the *current working directory*, which is normally the project repo being documented, not the plugin install. A project repo that happens to contain (accidentally or maliciously) a tree at that exact path gets its content copied into the generated documentation package with no origin check.
- **After the fix**: the same unset/unresolvable condition now falls through to the existing `[ -z "$TEMPLATE_DIR" ]` infra-error path — exit 2, `"template directory not found"` — rather than silently trusting an unverified CWD path. This is a stricter failure (fail closed instead of fail open), matching the sibling scripts' pattern (`dossier-evidence.sh`, `dossier-policy.sh`, `dossier-rotation-check.sh`, `dossier-validate-patch.sh`), which derive `CLAUDE_PLUGIN_ROOT` purely from `SCRIPT_DIR` with no CWD-relative fallback at all.
- **Partial failures**: unaffected — the per-file symlink/type/copy handling inside the main loop is untouched by this fix.

### Interface contracts

- CLI contract unchanged: same flags, same exit codes (0 success, 1 file-level failure, 2 infra error). The only externally observable change is that the specific failure mode "no `CLAUDE_PLUGIN_ROOT`, no resolvable `SCRIPT_DIR`-relative templates, *and* no `--templates` override" now reliably exits 2 with `"template directory not found"` instead of possibly succeeding by reading an unverified CWD-relative tree. No legitimate caller was found (AC3 audit below) that relies on the removed fallback succeeding, so this is not expected to break any real invocation.
- Error message text on the exit-2 path drops the now-inapplicable "and plugins/dossier" clause from both the template-dir and README-template lookup failures, since that path is no longer consulted.
- AC3 audit: grepped `plugins/dossier/commands/*.md` and `.github/workflows/*.yml` for `dossier-scaffold`/`scaffold` invocations. Only `commands/init.md` Phase 3 invokes the scaffolder (`bin/dossier-scaffold.sh --output-root "$OUTPUT_ROOT"`), and only after Phase 0 has already resolved a plugin root (`$__dr`) whose `bin/dossier-resolve-config.sh` exists and is executable — so `SCRIPT_DIR` (derived from `$0`, the resolved `$__dr/bin/dossier-scaffold.sh` path) reliably yields a valid `$SCRIPT_DIR/../templates/package`; the CWD-relative candidate is never reached in that flow. No CI workflow invokes the scaffolder directly. `commands/baseline.md` and `commands/status.md` only reference `/dossier:init` in prose, they don't invoke the scaffolder. Conclusion: no legitimate caller depends on the fallback being removed — AC3 is satisfied by removal.
