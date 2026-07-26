# Validate Plugin: $ARGUMENTS

Validate plugin structure and configuration before committing changes.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** to clarify which plugins to validate and determine how to handle validation issues.

## Arguments

- `$ARGUMENTS`: Plugin name (optional)
  - If provided, validates the specified plugin
  - If omitted, validates all plugins in the marketplace

## Process

1. **Identify plugins to validate**:
   ```bash
   # List all plugins
   ls -d plugins/*/
   ```

   **If multiple plugins exist and no argument provided, use the AskUserQuestion tool**:
   - **Option 1**: "Validate all plugins"
   - **Option 2**: "Validate specific plugin: [name]" (for each plugin)

2. **For each plugin, run validation checks** (see checklist below)

3. **Report results** with clear pass/fail status for each check

4. **If issues found, use the AskUserQuestion tool** to determine action:
   - **Option 1**: "Fix these issues automatically" (if auto-fixable)
   - **Option 2**: "Show me how to fix manually"
   - **Option 3**: "Ignore and continue" (for non-critical issues)
   - **Option 4**: "Cancel validation"

## Validation Checklist

### 1. Plugin Structure

Verify required directories and files exist:

```bash
# Required: plugin.json
ls plugins/{name}/.claude-plugin/plugin.json

# Required: README.md
ls plugins/{name}/README.md

# At least one of these must exist:
ls plugins/{name}/agents/    # Agent definitions
ls plugins/{name}/commands/  # User-facing commands
ls plugins/{name}/skills/    # Skill implementations
```

**Pass criteria**: plugin.json + README.md + at least one content directory

### 2. Plugin.json Validation

Read and validate `plugins/{name}/.claude-plugin/plugin.json`:

**Required fields**:
- `name` - Plugin identifier (string, non-empty)
- `version` - Semantic version (string, format: X.Y.Z)
- `description` - Plugin description (string, non-empty)

**Optional but recommended**:
- `author` - Author information (object with `name`)
- `license` - License identifier (string, e.g., "Apache-2.0")
- `keywords` - Search keywords (array of strings)
- `repository` - GitHub repository URL

**Validation**:
```bash
# Parse JSON and check fields
cat plugins/{name}/.claude-plugin/plugin.json
```

### 3. Marketplace.json Sync

Verify plugin is registered in `.claude-plugin/marketplace.json`:

```bash
cat .claude-plugin/marketplace.json
```

**Check**:
- Plugin entry exists in `plugins` array
- `name` matches plugin directory name
- `version` matches plugin.json version
- `source` points to correct path (`./plugins/{name}`)

### 4. Content File Validation

For each Markdown file in agents/, commands/, skills/:

#### Enhanced Agent Validation

For each agent file (`plugins/{name}/agents/*.md`):
- [ ] Has `# Title` heading
- [ ] Has `## Purpose` or `## Description` section
- [ ] Has `## Instructions` or `## Process` section
- [ ] Has `## Examples` section (if applicable)
- [ ] No `TODO`, `FIXME`, or `[PLACEHOLDER]` markers
- [ ] No broken internal links

#### Enhanced Command Validation

For each command file (`plugins/{name}/commands/*.md`):
- [ ] Has `# Command Name` heading with `$ARGUMENTS` if parameterized
- [ ] Has clear process/workflow section
- [ ] Documents all `$ARGUMENTS` usage
- [ ] Has `## Examples` section
- [ ] Has `## Rules` section

#### Enhanced Skill Validation

For each skill (`plugins/{name}/skills/*/SKILL.md`):
- [ ] Has `# Skill Name` heading
- [ ] Has `description:` frontmatter or section
- [ ] Has `## Instructions` section
- [ ] All `references/` files exist and are valid
- [ ] No duplicate reference files

### 5. Link Validation

Check all internal links resolve:
- Links to other files in the plugin
- References to agents/commands/skills
- Image references (if any)

**Link validation script**:
```bash
# Extract all markdown links and verify they resolve
grep -oE '\[([^\]]+)\]\(([^)]+)\)' {file} | while read link; do
  path=$(echo "$link" | grep -oE '\(([^)]+)\)' | tr -d '()')
  if [[ "$path" != http* ]] && [[ ! -f "$path" ]]; then
    echo "Broken link: $path"
  fi
done
```

## Output Format

### All Passing
```
## Plugin Validation: {name}

✓ Plugin structure valid
✓ plugin.json valid (v{version})
✓ Registered in marketplace.json
✓ All content files valid
✓ All links resolve

**Status**: PASS
```

### With Issues
```
## Plugin Validation: {name}

✓ Plugin structure valid
✓ plugin.json valid (v{version})
✗ marketplace.json version mismatch
  - plugin.json: 1.3.2
  - marketplace.json: 1.3.1
✓ All content files valid
✓ All links resolve

**Status**: FAIL

### Issues to Fix
1. Update marketplace.json plugin version to 1.3.2
```

## Quick Commands

```bash
# Validate specific plugin
/gh-plugin decipon

# Validate all plugins
/gh-plugin
```

## Common Issues

| Issue | Fix |
|-------|-----|
| Version mismatch | Update marketplace.json to match plugin.json |
| Missing README | Create plugins/{name}/README.md |
| Invalid JSON | Fix syntax in plugin.json |
| Empty content dir | Add at least one agent, command, or skill |
| Broken link | Update link path or create missing file |

## Rules

- Run validation before creating PRs that modify plugins
- Fix all critical issues before committing
- Version in plugin.json is the source of truth
- Marketplace.json must stay in sync with plugin.json
- **Use the AskUserQuestion tool** for:
  - Plugin selection (when multiple exist and none specified)
  - Deciding how to handle validation issues
  - Confirming auto-fixes before applying
