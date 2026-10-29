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
| `.env`, `.env.<environment>` (`.env.local`, `.env.production`, ...) | BLOCK | Environment secrets |
| `.env.example`, `.env.sample`, `.env.template` | WARN when a value looks like a real secret; otherwise classify as usual | Committable templates. A value looks real when it is neither empty nor a placeholder (`changeme`, `your-key-here`, `<...>`, `xxx`): a known key prefix (`sk-`, `ghp_`, `github_pat_`, `AKIA`, `xox`), a private-key block, or a long random-looking string |
| `credentials*`, `*secret*`, `*password*` | BLOCK | Sensitive data |
| `*.pem`, `*.key`, `*.p12` | BLOCK | Cryptographic keys |
| `id_rsa*`, `*.pub` (SSH keys) | BLOCK | SSH credentials |
| `*.lock`, `package-lock.json`, `yarn.lock` | WARN | Verify intentional |
| Files > 1MB | WARN | Large binaries |
| `*.min.js`, `*.min.css` | WARN | Minified/generated |
| `node_modules/`, `vendor/`, `dist/` | WARN | Should be gitignored |

## Primary Signals

| Signal | Detection Method |
|--------|-----------------|
| File in branch diff | `git diff --name-only $DEFAULT_BRANCH...HEAD` includes file |
| File matches issue title keywords | Tokenize issue title, match against file path components |
| File matches issue body keywords | Tokenize issue body, match against file path |
| File referenced in active task | TaskList descriptions mention file path |
| File in same module as task target | Same top-level directory as task files |

## Secondary Signals

| Signal | Detection Method |
|--------|-----------------|
| Sibling of in-context file | Same parent directory |
| Test file for changed module | Naming convention: `foo.rb` ↔ `foo_test.rb`, `foo.spec.ts` |
| Import/require of changed file | Grep for import statements |
| Config in project root | Dotfiles, manifest changes |
| README/docs for changed module | Documentation in same package |

## Classification

| Signals present | Classification |
|-----------------|---------------|
| Any primary signal | **in-context** |
| Secondary signals only | **uncertain** — present to user; a sibling or test companion of an in-context file leans in-context |
| Unrelated directory, no link to the issue or tasks | **out-of-context** — flag prominently |
| None of the above | **uncertain** (default) |

**Boy Scout Exception**: Changes that pass the proximity test (see `code-quality-principles`) in files already classified as in-context are always in-context, regardless of other signals. They use the `improve` commit type.

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
