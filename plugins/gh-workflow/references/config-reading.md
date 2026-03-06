# Configuration Reading Reference

How to read gh-workflow plugin configuration from settings files.

## Config File Locations

| Scope | Path | Use Case | Git |
|-------|------|----------|-----|
| User | `~/.claude/settings.gh-workflow.json` | Global defaults across projects | N/A |
| Project | `.claude/settings.gh-workflow.json` | Team-shared config | committed |
| Local | `.claude/settings.gh-workflow.local.json` | Personal overrides, secrets | .gitignored |

**Precedence**: local > project > user > schema defaults.

All files reference the schema for IDE validation:
```json
{
  "$schema": "https://raw.githubusercontent.com/synaptiai/synapti-marketplace/main/plugins/gh-workflow/schema.json"
}
```

## Reading Patterns

### Pattern A — Single Value

Use when a command reads 1-3 keys:

```bash
# Read a single config value (local > project > user > default)
JOURNAL_DIR=$(jq -r '.journal.dir // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
[ -z "$JOURNAL_DIR" ] && JOURNAL_DIR=$(jq -r '.journal.dir // empty' .claude/settings.gh-workflow.json 2>/dev/null)
[ -z "$JOURNAL_DIR" ] && JOURNAL_DIR=$(jq -r '.journal.dir // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
[ -z "$JOURNAL_DIR" ] && JOURNAL_DIR=".decisions"
```

### Pattern B — Bulk Merge

Use when a skill reads many keys. Merges all layers with schema defaults in one pass:

```bash
# Merge all config layers: defaults < user < project < local
GHW_CONFIG=$(jq -n '
  def defaults: {
    gates: {
      newDependencies:"on", securityChanges:"on", schemaChanges:"on",
      apiSurfaceChanges:"on", scopeDeviations:"on", ambiguousRequirements:"on",
      customTriggers:[], customTriggersMode:"on"
    },
    journal: { dir:".decisions", sensitivityDefault:"public" },
    report: { thresholdFull:100 },
    explain: { sessionSave:"ask", includeDiff:true },
    commands: {
      ghStartFamiliarityPrompt:true, ghCommitFirstTouch:true,
      ghPrComprehensionReport:true, ghPrDecisionSummary:true,
      ghReviewComprehensionCheck:true, ghMergeKnowledgeCheckpoint:true
    }
  };
  defaults
    * (try input catch {})
    * (try input catch {})
    * (try input catch {})
' "$HOME/.claude/settings.gh-workflow.json" \
  ".claude/settings.gh-workflow.json" \
  ".claude/settings.gh-workflow.local.json" 2>/dev/null)

# Extract individual values
JOURNAL_DIR=$(echo "$GHW_CONFIG" | jq -r '.journal.dir')
SENSITIVITY=$(echo "$GHW_CONFIG" | jq -r '.journal.sensitivityDefault')
GATE_SECURITY=$(echo "$GHW_CONFIG" | jq -r '.gates.securityChanges')
# ... etc
```

**Error handling**: Each `try input catch {}` expression handles missing or invalid files gracefully — if a file doesn't exist or contains invalid JSON, it falls back to an empty object `{}`, leaving the defaults intact. No config files need to exist for the merge to succeed.

## Zero-Config Behavior

All defaults are embedded in the bulk merge pattern. If no config files exist at any scope, every key resolves to its schema default. No configuration is required for the plugin to function.

## JSON Path Reference

| JSON Path | Type | Default | Description |
|-----------|------|---------|-------------|
| `.gates.newDependencies` | `"on"\|"log"\|"off"` | `"on"` | New dependency gate |
| `.gates.securityChanges` | `"on"\|"log"\|"off"` | `"on"` | Security changes gate |
| `.gates.schemaChanges` | `"on"\|"log"\|"off"` | `"on"` | Schema changes gate |
| `.gates.apiSurfaceChanges` | `"on"\|"log"\|"off"` | `"on"` | API surface changes gate |
| `.gates.scopeDeviations` | `"on"\|"log"\|"off"` | `"on"` | Scope deviations gate |
| `.gates.ambiguousRequirements` | `"on"\|"log"\|"off"` | `"on"` | Ambiguous requirements gate |
| `.gates.customTriggers` | `string[]` | `[]` | Custom glob patterns |
| `.gates.customTriggersMode` | `"on"\|"log"\|"off"` | `"on"` | Custom triggers behavior |
| `.journal.dir` | `string` | `".decisions"` | Journal directory |
| `.journal.sensitivityDefault` | `"public"\|"internal"` | `"public"` | Default sensitivity |
| `.report.thresholdFull` | `integer` | `100` | Full report threshold (lines) |
| `.explain.sessionSave` | `"always"\|"ask"\|"never"` | `"ask"` | Session save behavior |
| `.explain.includeDiff` | `boolean` | `true` | Auto-load diff |
| `.commands.ghStartFamiliarityPrompt` | `boolean` | `true` | Familiarity prompt |
| `.commands.ghCommitFirstTouch` | `boolean` | `true` | First-touch flagging |
| `.commands.ghPrComprehensionReport` | `boolean` | `true` | Comprehension report |
| `.commands.ghPrDecisionSummary` | `boolean` | `true` | Decision summary |
| `.commands.ghReviewComprehensionCheck` | `boolean` | `true` | Comprehension check |
| `.commands.ghMergeKnowledgeCheckpoint` | `boolean` | `true` | Knowledge checkpoint |
