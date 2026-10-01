# Classification Signals Reference

Complete reference for the change-classification skill's signal evaluation.

## Signal Evaluation Order

1. **Red flags** (always checked first — blocks or warns)
2. **Primary signals** (strong indicators)
3. **Secondary signals** (supporting evidence)
4. **Default** → uncertain (if no signals match)

## Red Flags

| Pattern | Action | Rationale |
|---------|--------|-----------|
| `.env`, `.env.*` | BLOCK | Environment secrets |
| `credentials*`, `*secret*`, `*password*` | BLOCK | Sensitive data |
| `*.pem`, `*.key`, `*.p12` | BLOCK | Cryptographic keys |
| `id_rsa*`, `*.pub` (SSH keys) | BLOCK | SSH credentials |
| `*.lock`, `package-lock.json`, `yarn.lock` | WARN | Verify intentional |
| Files > 1MB | WARN | Large binaries |
| `*.min.js`, `*.min.css` | WARN | Minified/generated |
| `node_modules/`, `vendor/`, `dist/` | WARN | Should be gitignored |

## Primary Signals

| Signal | Weight | Detection Method |
|--------|--------|-----------------|
| File in branch diff | 0.9 | `git diff --name-only $DEFAULT_BRANCH...HEAD` includes file |
| File matches issue title keywords | 0.8 | Tokenize issue title, match against file path components |
| File matches issue body keywords | 0.7 | Tokenize issue body, match against file path |
| File referenced in active task | 0.9 | TaskList descriptions mention file path |
| File in same module as task target | 0.7 | Same top-level directory as task files |

## Secondary Signals

| Signal | Weight | Detection Method |
|--------|--------|-----------------|
| Sibling of in-context file | 0.5 | Same parent directory |
| Test file for changed module | 0.6 | Naming convention: `foo.rb` ↔ `foo_test.rb`, `foo.spec.ts` |
| Import/require of changed file | 0.5 | Grep for import statements |
| Config in project root | 0.3 | Dotfiles, manifest changes |
| README/docs for changed module | 0.4 | Documentation in same package |

## Classification Thresholds

| Total Signal Score | Classification |
|-------------------|---------------|
| >= 0.7 | **in-context** |
| 0.3 - 0.69 | **uncertain** — present to user |
| < 0.3 | **out-of-context** — flag prominently |

**Boy Scout Exception**: Changes that pass the proximity test (see `code-quality-principles`) in files already classified as in-context are always in-context, regardless of signal score. They use the `improve` commit type.

## First-Touch Indicators

A file is first-touch when ALL of:
- `git log $DEFAULT_BRANCH..HEAD -- {file}` returns empty
- File has >50 lines of additions
- File is not a test companion for an existing change

First-touch files always get noted regardless of classification.

## Commit Type Inference

| Change Pattern | Suggested Type |
|---------------|---------------|
| New files only | `feat` |
| Modified existing, same behavior | `refactor` |
| Modified existing, different behavior | `fix` or `feat` |
| Test files only | `test` |
| Documentation only | `docs` |
| Config/build only | `chore` or `ci` |
| Mixed (feat + test) | `feat` (tests support the feature) |
| Cleanup in already-modified file | `improve` (Boy Scout Rule) |
