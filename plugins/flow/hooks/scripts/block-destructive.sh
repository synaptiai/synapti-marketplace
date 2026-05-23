#!/bin/bash
# [flow] PreToolUse hook: Block destructive operations
# Prevents rm -rf, branch deletion, and checkout destructive resets

set -euo pipefail

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block rm -rf (except in safe dirs like node_modules, build artifacts)
# Handles: rm -rf, rm -fr, rm -r -f, rm --recursive --force, and multiple path arguments
SAFE_DIRS="node_modules|\.next|dist|build|tmp|\.cache|__pycache__|coverage|\.turbo|\.parcel-cache|\.vite"
if echo "$COMMAND" | grep -qE 'rm\s+(-[rfRF]+\s+)+|rm\s+(-[a-zA-Z]\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\s+.*-[a-zA-Z]*[fF]|rm\s+(-[a-zA-Z]\s+)*-[a-zA-Z]*[fF][a-zA-Z]*\s+.*-[a-zA-Z]*[rR]|rm\s+.*(--recursive|--force).*\s+(--recursive|--force)'; then
  # Extract paths: remove 'rm' and all flag arguments (short and long flags, use [[:space:]] for macOS sed)
  PATHS=$(echo "$COMMAND" | sed -E 's/^rm[[:space:]]+//; s/--[a-zA-Z-]+[[:space:]]*//g; s/-[a-zA-Z]+[[:space:]]*//g')
  ALL_SAFE=true
  for P in $PATHS; do
    BASENAME=$(basename "$P")
    if ! echo "$BASENAME" | grep -qE "^($SAFE_DIRS)$"; then
      ALL_SAFE=false
      break
    fi
  done
  if [ "$ALL_SAFE" = "false" ]; then
    echo "BLOCKED: Destructive rm -rf detected. Review the target path and run manually if intended." >&2
    exit 2
  fi
fi

# Force branch deletion: allowed ONLY when every target branch is provably
# merged into the default branch. `git branch -d` (the safe form) cannot delete
# squash-merged branches — git doesn't see their commits on the default branch —
# so a blanket force-delete block makes squash-merged cleanup impossible. This
# check distinguishes merged (safe to drop) from unmerged (would lose work) and
# fails safe (blocks) on any uncertainty.
#
# Force-delete is detected in every equivalent form: -D, a combined short
# cluster containing D (-Df, -fD, -rD), or a delete flag (-d/--delete) together
# with a force flag (-f/--force). Plain `git branch -d` (safe delete, no force)
# is NOT matched and passes through.
IS_FORCE_DELETE=0
if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+branch([[:space:]]|$)'; then
  if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])-[A-Za-z]*D[A-Za-z]*([[:space:]]|$)'; then
    IS_FORCE_DELETE=1
  elif printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])(--delete|-[A-Za-z]*d[A-Za-z]*)([[:space:]]|$)' \
    && printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])(--force|-[A-Za-z]*f[A-Za-z]*)([[:space:]]|$)'; then
    IS_FORCE_DELETE=1
  fi
fi

if [ "$IS_FORCE_DELETE" = "1" ]; then
  set +e          # this block is fully conditional and always exits explicitly
  set -f          # no pathname expansion of parsed tokens

  # Targets = every non-flag token that isn't `git`/`branch`. A force-delete
  # chained into a compound command (`&& rm ...`, `; ...`, `| ...`) leaves
  # junk tokens that fail the show-ref check below, so compounds always fall
  # through to BLOCK rather than being allowed on a merged target.
  TARGETS=$(printf '%s' "$COMMAND" | awk '{
    for (i=1;i<=NF;i++) {
      if ($i == "git" || $i == "branch") continue
      if ($i ~ /^-/) continue
      print $i
    }
  }')

  if [ -z "$TARGETS" ]; then
    echo "BLOCKED: Force branch deletion with no resolvable target. Run it manually if intended." >&2
    exit 2
  fi
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "BLOCKED: Force branch deletion — cannot verify merge status (not a git repo / git unavailable). Run it manually if intended." >&2
    exit 2
  fi

  # Resolve the default branch: origin/HEAD, else local main/master.
  DEFAULT=""
  if DH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    DEFAULT="${DH#origin/}"
  fi
  if [ -z "$DEFAULT" ]; then
    for cand in main master; do
      if git show-ref --verify --quiet "refs/heads/$cand"; then DEFAULT="$cand"; break; fi
    done
  fi
  if [ -z "$DEFAULT" ]; then
    echo "BLOCKED: Force branch deletion — cannot resolve a default branch to verify against. Run it manually if intended." >&2
    exit 2
  fi

  # Candidate "merged into" refs: the local default branch plus, if present, the
  # remote-tracking default. Accepting origin/<default> means a branch already
  # merged on the remote is deletable even when the local default is behind
  # (un-pulled) — the work is preserved on the remote, so this is safe and only
  # ever turns a false-block into a correct allow (never a false allow).
  DEFAULT_REFS="$DEFAULT"
  if git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT"; then
    DEFAULT_REFS="$DEFAULT_REFS origin/$DEFAULT"
  fi

  for BR in $TARGETS; do
    if [ "$BR" = "$DEFAULT" ]; then
      echo "BLOCKED: Refusing to force-delete the default branch '$DEFAULT'." >&2
      exit 2
    fi
    if ! git show-ref --verify --quiet "refs/heads/$BR"; then
      echo "BLOCKED: Force branch deletion — '$BR' is not a local branch (cannot verify merge status). Run it manually if intended." >&2
      exit 2
    fi

    MERGED=0
    for REF in $DEFAULT_REFS; do
      # (1) Regular / fast-forward merge: branch tip is an ancestor of the default.
      if git merge-base --is-ancestor "$BR" "$REF" 2>/dev/null; then
        MERGED=1; break
      fi
      # (2) Squash merge: the branch's *combined* change is patch-equivalent to a
      # commit already in the default branch. Synthesize a single commit of the
      # branch's tree atop the merge-base, then ask `git cherry` whether the
      # default already contains an equivalent patch ('-' prefix == present).
      # Author/committer identity is forced inline so commit-tree never depends
      # on (possibly unset) git config.
      MB=$(git merge-base "$REF" "$BR" 2>/dev/null)
      TREE=$(git rev-parse --quiet --verify "$BR^{tree}" 2>/dev/null)
      if [ -n "$MB" ] && [ -n "$TREE" ]; then
        SYNTH=$(GIT_AUTHOR_NAME=_ GIT_AUTHOR_EMAIL=_@_ GIT_COMMITTER_NAME=_ GIT_COMMITTER_EMAIL=_@_ \
                git commit-tree "$TREE" -p "$MB" -m _ 2>/dev/null)
        if [ -n "$SYNTH" ]; then
          case "$(git cherry "$REF" "$SYNTH" 2>/dev/null | head -n1)" in
            -*) MERGED=1; break ;;
          esac
        fi
      fi
    done

    if [ "$MERGED" != "1" ]; then
      echo "BLOCKED: '$BR' is not merged into '$DEFAULT' — force-delete would lose unmerged work. Run it manually if intended." >&2
      exit 2
    fi
  done

  # Every target is merged into the default branch — safe to drop.
  exit 0
fi

# Block git checkout -- . (discard all changes)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+\.'; then
  echo "BLOCKED: Discarding all changes detected. Use selective checkout or stash instead." >&2
  exit 2
fi

# Block git restore . (modern equivalent of git checkout -- .)
if echo "$COMMAND" | grep -qE 'git\s+restore\s+\.'; then
  echo "BLOCKED: Discarding all changes detected (git restore). Use selective restore or stash instead." >&2
  exit 2
fi

# Block git reset --hard
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  echo "BLOCKED: Hard reset detected. This discards uncommitted work. Run manually if intended." >&2
  exit 2
fi

# Block git clean -f / --force (force clean untracked files)
if echo "$COMMAND" | grep -qE 'git\s+clean\s+.*(-f|--force)'; then
  echo "BLOCKED: Force clean detected. This removes untracked files permanently. Run manually if intended." >&2
  exit 2
fi

exit 0
