#!/usr/bin/env bash
# Verify every plugin in .claude-plugin/marketplace.json advertises the version
# its own plugin.json reports, and that plugins sourced from other repositories
# are pinned to a commit.
#
# Why this exists. The marketplace makes a claim about every plugin it lists:
# this name is at this version. Nothing enforced that claim. Two failures have
# already reached main — a submodule pointer five months behind the tree it
# advertised, and a plugin that shipped eight merged pull requests without a
# version bump. A plugin sourced from another repository is the harder case,
# because nothing here changes when that repository does.
#
# What this catches:
#   - an external source with no `sha`, so the served tree can change silently
#   - a manifest version that disagrees with the source's own plugin.json
#   - a local plugin whose directory or plugin.json is missing
#
# What this does NOT catch, and cannot:
#   - a pin that is stale but self-consistent. The `agent-capability-standard`
#     pointer sat five months behind while both it and upstream reported 1.2.0;
#     no version comparison distinguishes those. Staleness is therefore
#     REPORTED for pinned sources — how far behind the tracked ref each pin
#     sits — so it is visible rather than silent. It is deliberately not a
#     failure: upstream committing something is not this repository's problem
#     until someone decides to move the pin.
#   - a plugin whose version was never bumped despite shipping changes. The
#     manifest and the plugin.json agree with each other and are both wrong.
#     That needs a human, or a release process, not a consistency check.
#
# An entry that cannot be checked is reported as unverifiable and fails. It is
# never reported as a pass: an unevaluated condition must not read as assent.
#
# Usage:
#   scripts/check-plugin-versions.sh [<marketplace.json>] [<repo-root>]
#
# <repo-root> is where a local plugin's `./plugins/...` source is resolved from.
# It defaults to the manifest's parent directory, which is correct for a
# manifest read in place. Pass it explicitly when checking a manifest copied
# elsewhere — otherwise every local entry resolves against the copy's location
# and reports unverifiable, which is how this argument came to exist.
#
# Requires: jq; gh (authenticated) only when external sources are present.
#
# Exits:
#   0 — every entry is consistent, and every external entry is pinned
#   1 — usage or prerequisite failure (missing jq/gh, unreadable manifest)
#   2 — at least one entry is unpinned or advertises the wrong version
#   3 — at least one entry could not be checked

set -uo pipefail

MANIFEST="${1:-.claude-plugin/marketplace.json}"
REPO_ROOT="${2:-}"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(cd "$(dirname "$MANIFEST")/.." 2>/dev/null && pwd)
fi
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  printf 'FATAL: cannot resolve a repository root for %s\n' "$MANIFEST" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'FATAL: jq is required but not on PATH\n' >&2
  exit 1
fi

if [ ! -r "$MANIFEST" ]; then
  printf 'FATAL: cannot read manifest: %s\n' "$MANIFEST" >&2
  exit 1
fi

if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  printf 'FATAL: manifest is not valid JSON: %s\n' "$MANIFEST" >&2
  exit 1
fi

# Emit one record per plugin entry.
#
# Fields are separated by US (0x1f), not by tab: tab counts as IFS whitespace,
# so `IFS=$'\t' read` collapses runs of tabs into one delimiter and an entry
# with an empty field (a `github` source has no `url` or `path`) silently
# shifts every later value into the wrong variable. US is not IFS whitespace,
# so empty fields survive.
ENTRIES=$(jq -r '
  .plugins[]
  | [ .name,
      (.version // ""),
      (if (.source | type) == "object" then (.source.source // "?") else "local" end),
      (.source.repo? // ""),
      (.source.url? // ""),
      (.source.path? // ""),
      (.source.sha? // ""),
      (.source.ref? // ""),
      (if (.source | type) == "string" then .source else "" end)
    ] | join("\u001f")
' "$MANIFEST")
if [ $? -ne 0 ]; then
  printf 'FATAL: could not read plugin entries from %s\n' "$MANIFEST" >&2
  exit 1
fi

if [ -z "$ENTRIES" ]; then
  printf 'FATAL: %s declares no plugins\n' "$MANIFEST" >&2
  exit 1
fi

FAILED=0
UNVERIFIABLE=0
CHECKED=0

# Derive "owner/repo" from a github.com clone URL. Prints nothing and returns 1
# for any other host, which the caller reports as unverifiable.
github_slug_from_url() {
  local url="$1" slug
  case "$url" in
    https://github.com/*) slug="${url#https://github.com/}" ;;
    git@github.com:*)     slug="${url#git@github.com:}" ;;
    *) return 1 ;;
  esac
  slug="${slug%.git}"
  slug="${slug%/}"
  [ -n "$slug" ] || return 1
  printf '%s' "$slug"
}

while IFS=$'\037' read -r NAME VERSION STYPE REPO URL SUBPATH SHA REF LOCALPATH; do
  [ -n "${NAME:-}" ] || continue
  CHECKED=$((CHECKED + 1))

  # ---- Local plugin: read its plugin.json off disk -----------------------
  if [ "$STYPE" = "local" ]; then
    REL="${LOCALPATH#./}"
    PJ="${REPO_ROOT}/${REL}/.claude-plugin/plugin.json"
    if [ ! -r "$PJ" ]; then
      printf 'UNVERIFIABLE %s: no readable plugin.json at %s\n' "$NAME" "${REL}/.claude-plugin/plugin.json"
      UNVERIFIABLE=$((UNVERIFIABLE + 1))
      continue
    fi
    LOCAL_VERSION=$(jq -r '.version // empty' "$PJ" 2>/dev/null)
    if [ -z "$LOCAL_VERSION" ]; then
      printf 'UNVERIFIABLE %s: %s has no readable "version"\n' "$NAME" "${REL}/.claude-plugin/plugin.json"
      UNVERIFIABLE=$((UNVERIFIABLE + 1))
      continue
    fi
    if [ "$LOCAL_VERSION" != "$VERSION" ]; then
      printf 'FAIL %s: marketplace advertises %s, but %s reports %s\n' \
        "$NAME" "$VERSION" "${REL}/.claude-plugin/plugin.json" "$LOCAL_VERSION"
      FAILED=$((FAILED + 1))
      continue
    fi
    printf 'ok %s: %s (local)\n' "$NAME" "$VERSION"
    continue
  fi

  # ---- External plugin: must be pinned, and must agree at that pin -------
  if ! command -v gh >/dev/null 2>&1; then
    printf 'FATAL: gh is required to check external source %s but is not on PATH\n' "$NAME" >&2
    exit 1
  fi

  if [ -z "$SHA" ]; then
    printf 'FAIL %s: external source has no "sha" — the served tree can change without this manifest changing\n' "$NAME"
    FAILED=$((FAILED + 1))
    continue
  fi

  case "$STYPE" in
    github)
      SLUG="$REPO"
      PLUGIN_JSON=".claude-plugin/plugin.json"
      ;;
    git-subdir)
      if ! SLUG=$(github_slug_from_url "$URL"); then
        printf 'UNVERIFIABLE %s: source url is not on github.com (%s) — cannot resolve its plugin.json from here\n' "$NAME" "$URL"
        UNVERIFIABLE=$((UNVERIFIABLE + 1))
        continue
      fi
      PLUGIN_JSON="${SUBPATH%/}/.claude-plugin/plugin.json"
      ;;
    url)
      if ! SLUG=$(github_slug_from_url "$URL"); then
        printf 'UNVERIFIABLE %s: source url is not on github.com (%s) — cannot resolve its plugin.json from here\n' "$NAME" "$URL"
        UNVERIFIABLE=$((UNVERIFIABLE + 1))
        continue
      fi
      PLUGIN_JSON=".claude-plugin/plugin.json"
      ;;
    *)
      printf 'UNVERIFIABLE %s: source type "%s" is not one this check knows how to resolve\n' "$NAME" "$STYPE"
      UNVERIFIABLE=$((UNVERIFIABLE + 1))
      continue
      ;;
  esac

  if [ -z "$SLUG" ]; then
    printf 'UNVERIFIABLE %s: could not determine the source repository\n' "$NAME"
    UNVERIFIABLE=$((UNVERIFIABLE + 1))
    continue
  fi

  # Raw media type returns the file body directly. Decoding the API's base64
  # field would need `base64 -d`/`-D`, which differ between GNU and BSD.
  REMOTE_JSON=$(gh api \
    -H "Accept: application/vnd.github.raw" \
    "repos/${SLUG}/contents/${PLUGIN_JSON}?ref=${SHA}" 2>/dev/null)
  GH_STATUS=$?
  if [ "$GH_STATUS" -ne 0 ] || [ -z "$REMOTE_JSON" ]; then
    printf 'UNVERIFIABLE %s: could not fetch %s at %s from %s (gh exit %d)\n' \
      "$NAME" "$PLUGIN_JSON" "${SHA:0:7}" "$SLUG" "$GH_STATUS"
    UNVERIFIABLE=$((UNVERIFIABLE + 1))
    continue
  fi

  REMOTE_VERSION=$(printf '%s' "$REMOTE_JSON" | jq -r '.version // empty' 2>/dev/null)
  if [ -z "$REMOTE_VERSION" ]; then
    printf 'UNVERIFIABLE %s: %s at %s has no readable "version"\n' \
      "$NAME" "$PLUGIN_JSON" "${SHA:0:7}"
    UNVERIFIABLE=$((UNVERIFIABLE + 1))
    continue
  fi

  if [ "$REMOTE_VERSION" != "$VERSION" ]; then
    printf 'FAIL %s: marketplace advertises %s, but %s at %s reports %s\n' \
      "$NAME" "$VERSION" "$PLUGIN_JSON" "${SHA:0:7}" "$REMOTE_VERSION"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Staleness is reported, never failed. See the header for why.
  DRIFT=""
  if [ -n "$REF" ]; then
    BEHIND=$(gh api "repos/${SLUG}/compare/${SHA}...${REF}" --jq '.ahead_by' 2>/dev/null)
    if [ -n "$BEHIND" ] && [ "$BEHIND" != "0" ]; then
      DRIFT=" — pin is ${BEHIND} commit(s) behind ${REF}"
    fi
  fi

  printf 'ok %s: %s pinned at %s, version matches%s\n' "$NAME" "$VERSION" "${SHA:0:7}" "$DRIFT"
done <<EOF
$ENTRIES
EOF

printf '\n%d plugin(s) checked, %d failed, %d unverifiable\n' \
  "$CHECKED" "$FAILED" "$UNVERIFIABLE"

if [ "$FAILED" -gt 0 ]; then
  exit 2
fi
if [ "$UNVERIFIABLE" -gt 0 ]; then
  exit 3
fi
exit 0
