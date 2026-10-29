# Capability Discovery Output

The report `skills/capability-discovery/SKILL.md` returns: six sections, each filled from its detection step.

```markdown
### Agents Available
| Agent | Source | Description |
|-------|--------|-------------|

### Skills Available
| Skill | Source | Description |
|-------|--------|-------------|

### Quality Commands
| Command | Purpose | Source |
|---------|---------|--------|

### Tech Stack
- {language} ({indicator file})

### Verification Capabilities
| Capability | Command | Source |
|-----------|---------|--------|

### LSP Capabilities
| Feature | Status | Use Case |
|---------|--------|----------|
| documentSymbol | {Available/Unavailable} | Symbol navigation in files |
| hover | {Available/Unavailable} | Type info and documentation during CODE phase |
| goToDefinition | {Available/Unavailable} | Trace code paths during EXPLORE phase |
| findReferences | {Available/Unavailable} | Impact analysis during EXPLORE, caller verification during REVIEW |
| goToImplementation | {Available/Unavailable} | Interface resolution |
| diagnostics | {Available/Unavailable} | Quality signal during VERIFY phase (errors→P1, warnings→P2) |
```
