---
description: Use to perform a dedicated security review of current branch changes before pushing
argument-hint: [scope]
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, scans, API calls),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Security Review

Dedicated security review of current branch changes. Scans for secrets, injection vectors, auth gaps, data exposure, and dependency vulnerabilities.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** for severity confirmation and remediation decisions, and **TaskCreate/TaskUpdate** for tracking findings.

## Contract

**GOAL**: Identify all security-relevant issues in current diff with actionable findings. Testable: every finding has a CWE reference and file:line location.

**CONSTRAINTS**:
- Must check for hardcoded secrets in every review
- Must analyze injection vectors for any user-input handling code
- All findings must include file:line references
- Never auto-fix security issues without user approval

**FORMAT**: P1/P2/P3 findings table with CWE references, file:line locations, and suggested fixes.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Completed without checking for hardcoded secrets
- Injection vectors not analyzed for code handling user input
- Findings lack file:line references
- CWE references missing from findings
- Security issues auto-fixed without user approval
- Review completed without scanning dependency vulnerabilities (when package manager exists)

## Phase 1: Scope Detection

**Execute in parallel**:

1. **Get the diff to review**:
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git diff origin/$DEFAULT_BRANCH..HEAD --name-only
   ```

2. **Get full diff content**:
   ```bash
   git diff origin/$DEFAULT_BRANCH..HEAD
   ```

3. **Detect tech stack** for targeted scans:
   ```bash
   ls pyproject.toml package.json go.mod Cargo.toml Gemfile 2>/dev/null
   ```

4. **Check for security-relevant config files**:
   ```bash
   ls .env* *.pem *.key *.cert docker-compose*.yml Dockerfile 2>/dev/null
   ```

### Scope Determination

If `$ARGUMENTS` is provided, limit scan to that scope:
- `all` - Full diff (default)
- `secrets` - Only secrets scan
- `injection` - Only injection analysis
- `auth` - Only auth/authz checks
- `deps` - Only dependency audit

## Phase 2: Secrets Scan

### Step 2.1: Pattern-Based Detection

Scan the diff for high-entropy strings and known secret patterns:

```bash
# Check diff for common secret patterns
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(password|passwd|pwd)\s*[:=]' 2>/dev/null

git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(api[_-]?key|apikey|secret[_-]?key|access[_-]?token|auth[_-]?token)\s*[:=]' 2>/dev/null

git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(AWS_ACCESS_KEY|AWS_SECRET|GITHUB_TOKEN|SLACK_TOKEN|STRIPE_KEY)' 2>/dev/null

# Check for private keys
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY' 2>/dev/null

# Check for connection strings
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(mongodb|postgres|mysql|redis)://[^"]+@' 2>/dev/null
```

### Step 2.2: File-Based Detection

Check if any sensitive files are being committed:

```bash
# Check for sensitive file patterns in the diff
git diff origin/$DEFAULT_BRANCH..HEAD --name-only | grep -iE \
  '\.env|\.pem|\.key|\.cert|\.p12|\.pfx|id_rsa|credentials|\.htpasswd' 2>/dev/null
```

### Step 2.3: .gitignore Verification

```bash
# Verify .gitignore covers sensitive patterns
grep -E '\.env|\.pem|\.key|credentials' .gitignore 2>/dev/null || echo "WARNING: .gitignore may not cover sensitive files"
```

**CWE Reference**: CWE-798 (Hard-coded Credentials), CWE-312 (Cleartext Storage)

## Phase 3: Injection Analysis

For each changed file that handles user input:

### Step 3.1: SQL Injection

```bash
# String concatenation in SQL queries
grep -rn "execute\|query\|cursor" --include="*.py" --include="*.ts" --include="*.js" --include="*.go" . 2>/dev/null | \
  grep -v "node_modules" | head -20
```

Look for:
- String concatenation in SQL: `"SELECT * FROM users WHERE id=" + user_id`
- f-strings/template literals in SQL: `f"SELECT * FROM {table}"`
- Missing parameterized queries

**CWE Reference**: CWE-89 (SQL Injection)

### Step 3.2: Command Injection

```bash
# Shell execution patterns
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(exec|spawn|system|popen|subprocess|child_process|os\.system|eval\()' 2>/dev/null
```

Look for:
- User input passed to shell commands
- `eval()` with dynamic content
- Template injection in command strings

**CWE Reference**: CWE-78 (OS Command Injection), CWE-94 (Code Injection)

### Step 3.3: XSS / Template Injection

```bash
# Unsafe HTML rendering patterns
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(innerHTML|dangerouslySetInnerHTML|v-html|__html|Markup\(|safe\|)' 2>/dev/null
```

**CWE Reference**: CWE-79 (Cross-site Scripting)

### Step 3.4: Path Traversal

```bash
# File operations with user-controlled paths
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(readFile|writeFile|open\(|fopen|os\.path\.join|path\.join)' 2>/dev/null
```

**CWE Reference**: CWE-22 (Path Traversal)

## Phase 4: Authentication & Authorization

### Step 4.1: Endpoint Auth Check

For web applications, verify new endpoints have auth:

```bash
# Find new route/endpoint definitions in diff
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(@app\.(get|post|put|delete|patch)|@router\.|app\.(get|post|put|delete)|router\.(get|post|put|delete))' 2>/dev/null
```

For each new endpoint, check:
- Is authentication middleware applied?
- Is authorization (role/permission) checked?
- Are admin-only endpoints properly protected?

**CWE Reference**: CWE-306 (Missing Authentication), CWE-862 (Missing Authorization)

### Step 4.2: Auth Bypass Patterns

```bash
# Check for auth bypass patterns
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(skip.*auth|no.*auth|disable.*auth|bypass|@public|@anonymous|AllowAnonymous)' 2>/dev/null
```

### Step 4.3: Session Management

```bash
# Session/token configuration
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(session|cookie|jwt|token)' 2>/dev/null | grep -iE '(expire|max.age|secure|httponly|samesite)' 2>/dev/null
```

**CWE Reference**: CWE-613 (Insufficient Session Expiration)

## Phase 5: Data Exposure

### Step 5.1: Logging Sensitive Data

```bash
# Check for PII/sensitive data in logs
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(log\.|logger\.|console\.(log|error|warn)|print\()' 2>/dev/null | \
  grep -iE '(password|token|secret|ssn|credit.card|email|phone)' 2>/dev/null
```

**CWE Reference**: CWE-532 (Information in Log Files)

### Step 5.2: Error Response Exposure

```bash
# Stack traces or internal details in error responses
git diff origin/$DEFAULT_BRANCH..HEAD | grep -nE \
  '(traceback|stack.*trace|internal.*error|debug.*true)' 2>/dev/null
```

**CWE Reference**: CWE-209 (Information Exposure Through Error Message)

### Step 5.3: Sensitive Data in API Responses

Read changed API handler files and check:
- Are all fields explicitly selected (whitelist), or is `SELECT *` / full model returned?
- Are internal IDs, timestamps, or admin fields exposed?
- Is PII returned in list endpoints without pagination limits?

**CWE Reference**: CWE-200 (Exposure of Sensitive Information)

## Phase 6: Dependency Audit

### Step 6.1: Run Package Audit

```bash
# Python
pip audit 2>/dev/null || pip-audit 2>/dev/null || echo "pip-audit not available"

# Node.js
npm audit --production 2>/dev/null || echo "npm audit not available"

# Go
govulncheck ./... 2>/dev/null || echo "govulncheck not available"

# Rust
cargo audit 2>/dev/null || echo "cargo-audit not available"

# Ruby
bundle audit check 2>/dev/null || echo "bundle-audit not available"
```

### Step 6.2: New Dependencies Check

```bash
# Check if new dependencies were added
git diff origin/$DEFAULT_BRANCH..HEAD -- package.json pyproject.toml go.mod Cargo.toml Gemfile 2>/dev/null | \
  grep "^+" | grep -v "^+++" 2>/dev/null
```

For new dependencies, flag:
- Is the package well-maintained (stars, last update)?
- Any known vulnerabilities?
- Is it a typosquat risk (similar name to popular package)?

**CWE Reference**: CWE-1104 (Use of Unmaintained Third Party Components)

## Phase 7: Findings Report

### Output Format

```markdown
## Security Review Findings

**Branch**: {branch}
**Files scanned**: {N} changed files
**Scope**: {full/limited}

### P1 - Critical (Must Fix Before Push)
| # | CWE | Category | Location | Issue | Suggested Fix |
|---|-----|----------|----------|-------|---------------|
| 1 | CWE-798 | Secrets | file.py:42 | API key hardcoded | Move to environment variable |

### P2 - Important (Should Fix)
| # | CWE | Category | Location | Issue | Suggested Fix |
|---|-----|----------|----------|-------|---------------|
| 1 | CWE-89 | Injection | api.py:15 | SQL string concat | Use parameterized query |

### P3 - Informational
| # | CWE | Category | Location | Issue | Suggested Fix |
|---|-----|----------|----------|-------|---------------|
| 1 | CWE-532 | Exposure | handler.py:30 | Email in debug log | Remove PII from log |

### Scan Coverage
| Phase | Status | Findings |
|-------|--------|----------|
| Secrets | Scanned | {N} findings |
| Injection | Scanned | {N} findings |
| Auth/Authz | Scanned | {N} findings |
| Data Exposure | Scanned | {N} findings |
| Dependencies | Scanned | {N} findings |

### Summary
- **P1 (Critical)**: {N} findings - MUST fix before push
- **P2 (Important)**: {N} findings - should fix
- **P3 (Informational)**: {N} findings - consider fixing

### No Issues Found
If clean: "No security issues found in {N} changed files across {M} scan phases."
```

## Phase 8: Remediation

If P1 findings exist:

1. **Create tasks** for each P1 finding:
   ```
   TaskCreate:
     subject: "Fix: [CWE-XXX] [brief description]"
     description: "[Full finding details with file:line and suggested fix]"
     activeForm: "Fixing [security issue]"
   ```

2. **Ask user** how to proceed using **AskUserQuestion tool**:
   - **Option 1**: "Fix all P1 issues now" (Recommended) - Address critical findings immediately
   - **Option 2**: "Fix selected issues" - Choose which to address
   - **Option 3**: "Acknowledge and defer" - Document risk acceptance

3. **After fixes**, re-run affected scan phases to verify remediation

## Arguments

- `$ARGUMENTS`: Optional scope limiter
  - `all` (default) - Run all scan phases
  - `secrets` - Only run secrets scan
  - `injection` - Only run injection analysis
  - `auth` - Only run auth/authz checks
  - `deps` - Only run dependency audit

## Rules

- **Never auto-fix** - Security changes require user understanding and approval
- **Always show findings before asking** - Display the full report before remediation questions
- **CWE references required** - Every finding must map to a CWE identifier
- **File:line required** - Every finding must have a specific location
- **No false confidence** - If a scan couldn't run (tool not installed), report it clearly
- **Read the actual code** - Don't just grep; read changed files to understand context

## Integration

- **Before `/gh-pr`**: Run security review as a quality gate
- **After `/gh-start`**: Run during implementation for early detection
- **Standalone**: Run anytime to audit current changes

## Related Commands

- **`/gh-pr`**: Creates PR (can run security review as pre-check)
- **`/gh-review`**: Reviews PRs (includes security facet)
- **`/gh-commit`**: Commits changes (flags secrets)
- **`/gh-start`**: Implementation workflow (can integrate security review)
