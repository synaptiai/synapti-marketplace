# Create Release v$ARGUMENTS

Create a new release for the marketplace or a specific plugin.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** extensively to determine release type, target, and get explicit approval before creating irreversible releases.

## Arguments

- `$ARGUMENTS`: Version bump type - `patch`, `minor`, or `major`
  - `patch` (1.2.0 → 1.2.1): Bug fixes only
  - `minor` (1.2.0 → 1.3.0): New features
  - `major` (1.2.0 → 2.0.0): Breaking changes

If no argument provided, analyze commits to suggest the appropriate bump type.

## Phase 1: Preparation

1. **Ensure on latest main**:
   ```bash
   git checkout main && git pull origin main
   ```

2. **Check what's changed since last release**:
   ```bash
   git log $(git describe --tags --abbrev=0)..HEAD --oneline
   ```

3. **Get current versions**:
   ```bash
   # Marketplace version
   cat .claude-plugin/marketplace.json | grep '"version"'

   # Plugin versions
   cat plugins/*/.claude-plugin/plugin.json | grep '"version"'
   ```

4. **If no argument provided, use the AskUserQuestion tool** to determine release type:

   Analyze commits and present recommendation:
   - **Option 1**: "patch (X.Y.Z → X.Y.Z+1)" - Bug fixes only (Recommended if all fix: commits)
   - **Option 2**: "minor (X.Y.Z → X.Y+1.0)" - New features (Recommended if feat: commits)
   - **Option 3**: "major (X.Y.Z → X+1.0.0)" - Breaking changes

5. **Use the AskUserQuestion tool** to determine release target:
   - **Option 1**: "Marketplace only" - Bump marketplace.json version
   - **Option 2**: "Plugin: [name]" - Bump plugin.json AND marketplace.json entry
   - **Option 3**: "Both" - Changes span marketplace and plugin

## Phase 1.5: Impact Assessment & Approval

Before making any changes, present a complete impact assessment, then **use the AskUserQuestion tool** to get explicit approval:

First, display the assessment:
```
**Release Impact Assessment**

Release type: [patch/minor/major]
Target: [Marketplace / Plugin: {name} / Both]

**Current versions:**
- Marketplace: X.Y.Z
- Plugin ({name}): X.Y.Z

**Proposed changes:**
- [ ] plugins/{name}/.claude-plugin/plugin.json: X.Y.Z → X.Y.Z+1
- [ ] .claude-plugin/marketplace.json plugins[].version: X.Y.Z → X.Y.Z+1
- [ ] .claude-plugin/marketplace.json metadata.version: X.Y.Z → X.Y.Z+1 (if marketplace release)

**Commits included in this release:**
- abc1234 feat: add new analysis capability
- def5678 fix: correct link in documentation
- ghi9012 docs: update README

**Breaking changes:** None / [list if any]
```

Then **invoke the AskUserQuestion tool** with these options:
- **Option 1**: "Proceed with release" (Recommended)
- **Option 2**: "Change release type (patch/minor/major)"
- **Option 3**: "Change release target"
- **Option 4**: "Cancel release"

**Do not proceed without explicit approval via the AskUserQuestion tool.**

## Phase 2: Version Bump

### For Plugin Release

1. **Update plugin version** in `plugins/{name}/.claude-plugin/plugin.json`:
   - Edit the `"version": "X.Y.Z"` field

2. **Update marketplace entry** in `.claude-plugin/marketplace.json`:
   - Find the plugin in the `plugins` array
   - Update its `"version": "X.Y.Z"` field to match

### For Marketplace Release

1. **Update marketplace version** in `.claude-plugin/marketplace.json`:
   - Edit `metadata.version` field

## Phase 3: Commit & Push

1. **Commit version bump**:
   ```bash
   git add .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json
   git commit -m "chore: bump version to X.Y.Z"
   ```

2. **Push to main**:
   ```bash
   git push origin main
   ```

## Phase 4: Create Tag & Release

1. **Create git tag**:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

2. **Create GitHub Release**:
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "RELEASE_NOTES"
   ```

   Release notes format:
   ```markdown
   ## What's Changed

   ### Bug Fixes
   - Description (#PR)

   ### New Features
   - Description (#PR)

   ### Plugin Updates
   - [plugin-name] vX.Y.Z: [brief description]

   ### Other Changes
   - Description (#PR)

   **Full Changelog**: https://github.com/synaptiai/synapti-marketplace/compare/vPREVIOUS...vX.Y.Z
   ```

## Version Files Reference

| File | Field | Purpose |
|------|-------|---------|
| `.claude-plugin/marketplace.json` | `metadata.version` | Marketplace version |
| `.claude-plugin/marketplace.json` | `plugins[].version` | Plugin version (must match plugin.json) |
| `plugins/{name}/.claude-plugin/plugin.json` | `version` | Plugin canonical version |

## Category Icons Reference

| Category | Icon |
|----------|------|
| Bug Fixes | :bug: |
| New Features | :sparkles: |
| Plugin Updates | :package: |
| Documentation | :books: |
| Breaking Changes | :warning: |

## Examples

### Plugin Patch Release
```bash
/gh-release patch

# For decipon plugin:
# - plugins/decipon/.claude-plugin/plugin.json: 1.3.1 → 1.3.2
# - .claude-plugin/marketplace.json plugins[0].version: 1.3.1 → 1.3.2
# - Tag: v1.3.2
```

### Marketplace Minor Release
```bash
/gh-release minor

# For marketplace:
# - .claude-plugin/marketplace.json metadata.version: 2.0.0 → 2.1.0
# - Tag: v2.1.0
```

## Phase 5: Verification

After release creation, verify everything completed successfully:

1. **Check tag exists**:
   ```bash
   git tag -l "vX.Y.Z"
   ```

2. **Check GitHub Release exists**:
   ```bash
   gh release view vX.Y.Z --json tagName,name,publishedAt
   ```

3. **Verify version files updated**:
   ```bash
   cat .claude-plugin/marketplace.json | grep '"version"'
   cat plugins/*/.claude-plugin/plugin.json | grep '"version"'
   ```

4. **Verify checklist**:
   - [ ] Version files updated correctly
   - [ ] Git tag created and pushed
   - [ ] GitHub Release published
   - [ ] Release notes accurate

5. **If verification fails**, report specific issue and remediation steps

## Rules

- Always verify versions are in sync before releasing
- Tag format: `vX.Y.Z` (with 'v' prefix)
- Version bump commits use `chore:` prefix
- Create GitHub Release with changelog
- Plugin version in marketplace.json must match plugin.json
- Always show impact assessment before making changes
- Always verify release after creation
- **Use the AskUserQuestion tool** for:
  - Release type selection (when not specified)
  - Release target selection
  - Impact assessment approval (required before proceeding)

## Success Criteria

Before completing, verify:
- [ ] Current versions identified
- [ ] Commits since last release analyzed
- [ ] Impact assessment shown and user approved
- [ ] Version files updated correctly
- [ ] Changes committed and pushed
- [ ] Git tag created and pushed
- [ ] GitHub Release created with changelog
- [ ] All verifications passed
- [ ] User informed of release URL
