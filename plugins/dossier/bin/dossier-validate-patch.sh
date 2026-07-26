#!/usr/bin/env bash
# dossier-validate-patch.sh — turn an agent's working-tree edits into a patch,
# or verify a patch someone else produced, refusing both if anything escapes the
# write allowlist or looks like a credential.
#
# This is the prompt-injection backstop. An agent that has been fully talked
# into working for someone else can still only produce a patch; this script is
# what makes that patch worthless to the attacker. Every check here is a hard
# failure, never a silent filter — a silent filter would strip the offending
# hunk and hide the fact that an attempt was made, which is the one outcome that
# leaves nobody any wiser.
#
# Usage: two modes.
#
#   dossier-validate-patch.sh --out <patchfile> [--allowlist <glob,glob>]
#                             [--github-output <file>] [--summary <file>]
#       Stages the working tree and writes a validated patch. Used by the
#       unprivileged refresh job.
#
#   dossier-validate-patch.sh --verify-patch <patchfile> [--allowlist <glob,glob>]
#                             [--github-output <file>] [--summary <file>]
#       Re-runs the allowlist and secret checks against an existing patch,
#       touching no worktree. Used by the privileged publish job, which must not
#       trust the unprivileged job's verdict — only its bytes.
#
# Flags:
#   --out <file>            write the validated patch here (staging mode)
#   --verify-patch <file>   validate an existing patch (verification mode)
#   --allowlist <globs>     comma-separated globs; defaults to
#                           dossier.ci.writeAllowlist from the settings cascade
#   --github-output <file>  append `key=value` lines here as well as to stdout
#   --summary <file>        append a human-readable markdown block here
#
# Output: has_changes, files_changed, lines_changed, size_class
#
# Exit:
#   0 — validated (possibly with has_changes=false)
#   1 — a hard failure: allowlist escape or credential match. No patch written.
#   2 — missing or invalid argument

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -f "${CLAUDE_PLUGIN_ROOT:-}/settings.json" ]; then
  CLAUDE_PLUGIN_ROOT=$(dirname "$SCRIPT_DIR")
  export CLAUDE_PLUGIN_ROOT
fi
# Deliberately the raw file cascade, NOT dossier-resolve-config.sh: this is the
# only config read in the plugin that must ignore the DOSSIER_* environment
# layer. This script runs in the `refresh` job, in the same environment as the
# agent it is meant to contain, and the value it reads is the write allowlist.
# An agent that can set DOSSIER_CI_WRITE_ALLOWLIST could widen its own boundary.
# Every other script honours the env layer; this one must not.
CASCADE="$SCRIPT_DIR/cascade-resolve.sh"

OUT_PATCH=""
VERIFY_PATCH=""
ALLOWLIST_ARG=""
GITHUB_OUTPUT_FILE=""
SUMMARY_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)           [ $# -lt 2 ] && { echo "dossier-validate-patch: --out requires a value" >&2; exit 2; }; OUT_PATCH="$2"; shift 2 ;;
    --verify-patch)  [ $# -lt 2 ] && { echo "dossier-validate-patch: --verify-patch requires a value" >&2; exit 2; }; VERIFY_PATCH="$2"; shift 2 ;;
    --allowlist)     [ $# -lt 2 ] && { echo "dossier-validate-patch: --allowlist requires a value" >&2; exit 2; }; ALLOWLIST_ARG="$2"; shift 2 ;;
    --github-output) [ $# -lt 2 ] && { echo "dossier-validate-patch: --github-output requires a value" >&2; exit 2; }; GITHUB_OUTPUT_FILE="$2"; shift 2 ;;
    --summary)       [ $# -lt 2 ] && { echo "dossier-validate-patch: --summary requires a value" >&2; exit 2; }; SUMMARY_FILE="$2"; shift 2 ;;
    -h|--help)       sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "dossier-validate-patch: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$OUT_PATCH" ] && [ -n "$VERIFY_PATCH" ]; then
  echo "dossier-validate-patch: --out and --verify-patch are mutually exclusive" >&2; exit 2
fi
if [ -z "$OUT_PATCH" ] && [ -z "$VERIFY_PATCH" ]; then
  echo "dossier-validate-patch: one of --out or --verify-patch is required" >&2; exit 2
fi
if [ -n "$VERIFY_PATCH" ] && [ ! -f "$VERIFY_PATCH" ]; then
  echo "dossier-validate-patch: patch file not found: $VERIFY_PATCH" >&2; exit 2
fi

HAS_CHANGES="false"
FILES_CHANGED=0
LINES_CHANGED=0
SIZE_CLASS="ok"

emit() {
  printf '%s=%s\n' "$1" "$2"
  if [ -n "$GITHUB_OUTPUT_FILE" ]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT_FILE"
  fi
  return 0
}

summary() {
  [ -n "$SUMMARY_FILE" ] || return 0
  printf '%s\n' "$1" >>"$SUMMARY_FILE"
  return 0
}

# Hard-fail rather than fall back to a predictable /tmp path, matching
# dossier-gate.sh, dossier-claim-scan.sh, and dossier-ledger-lint.sh. This
# script is the write-allowlist control; a temp directory an unprivileged
# process on the same host can pre-create is not a place to stage a patch.
TMPD=$(mktemp -d -t dossier-validate.XXXXXX) || {
  echo "::error title=dossier patch validation::cannot create a temporary directory" >&2
  exit 1
}
cleanup() { rm -rf "$TMPD" 2>/dev/null; }
trap cleanup EXIT

hard_fail() {
  echo "::error title=dossier patch validation::$1" >&2
  emit has_changes "false"
  emit files_changed "0"
  emit lines_changed "0"
  emit size_class "rejected"
  summary ""
  summary "### Dossier patch validation: REJECTED"
  summary ""
  summary "$1"
  exit 1
}

command -v git >/dev/null 2>&1 || { echo "dossier-validate-patch: git is not installed." >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "dossier-validate-patch: not inside a git repository." >&2; exit 1; }

# ---------------------------------------------------------------------------
# Allowlist
# ---------------------------------------------------------------------------
glob_to_ere() {
  awk -v g="$1" '
    BEGIN {
      n = length(g); out = ""; inbrace = 0;
      for (i = 1; i <= n; i++) {
        ch = substr(g, i, 1);
        if (ch == "*") {
          if (substr(g, i + 1, 1) == "*") {
            if (substr(g, i + 2, 1) == "/") { out = out "(.*/)?"; i += 2 }
            else { out = out ".*"; i += 1 }
          } else { out = out "[^/]*" }
        }
        else if (ch == "?")                    { out = out "[^/]" }
        else if (ch == "{")                    { out = out "("; inbrace = 1 }
        else if (ch == "}")                    { out = out ")"; inbrace = 0 }
        else if (ch == "," && inbrace)         { out = out "|" }
        else if (index(".[]^$()|+\\", ch) > 0) { out = out "\\" ch }
        else                                   { out = out ch }
      }
      print "^" out "$";
    }'
}

ALLOW_ERE="$TMPD/allow.ere"
: >"$ALLOW_ERE"
ALLOW_GLOBS=""

if [ -n "$ALLOWLIST_ARG" ]; then
  ALLOW_GLOBS=$(printf '%s' "$ALLOWLIST_ARG" | tr ',' '\n')
elif command -v jq >/dev/null 2>&1; then
  ALLOW_GLOBS=$("$CASCADE" --compact --default '["docs/dossier/**"]' '.dossier.ci.writeAllowlist' 2>/dev/null \
                  | jq -r '.[]? // empty' 2>/dev/null)
fi
# An empty allowlist would make every path permitted, which inverts the control
# this script exists to provide. Refuse rather than default to open.
[ -n "$ALLOW_GLOBS" ] || hard_fail "The write allowlist resolved to nothing. Refusing to validate a patch against an empty allowlist, because an empty allowlist permits every path."

printf '%s\n' "$ALLOW_GLOBS" | while IFS= read -r G; do
  G=$(printf '%s' "$G" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$G" ] || continue
  glob_to_ere "$G" >>"$ALLOW_ERE"
  # A bare directory in the allowlist is universally meant as "and everything
  # beneath it"; without this the glob would match the directory entry only and
  # every file inside it would read as an escape.
  case "$G" in
    *'*'*|*'?'*) : ;;
    */)          glob_to_ere "${G}**" >>"$ALLOW_ERE" ;;
    *)           glob_to_ere "${G}/**" >>"$ALLOW_ERE" ;;
  esac
done
[ -s "$ALLOW_ERE" ] || hard_fail "The write allowlist produced no usable patterns."

path_allowed() {
  # A traversal segment is refused before the allowlist is consulted, because
  # the allowlist cannot see it: `docs/dossier/**` compiles to `^docs/dossier/.*$`,
  # which `docs/dossier/../../.env` matches while resolving outside the root.
  # `git apply` without --unsafe-paths would also reject it, but this script is
  # the documented control and the publish job's independent re-check — it does
  # not get to rely on a default in a tool someone may later invoke differently.
  case "$1" in
    ..|../*|*/../*|*/..) return 1 ;;
    /*) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -qE -f "$ALLOW_ERE"
}

# ---------------------------------------------------------------------------
# Credential patterns
#
# The first two are flow's block-secrets.sh baseline, kept identical so a fix in
# either place is portable. The rest cover the concrete formats most likely to
# be pasted into a generated document. Novel formats are missed by design and by
# admission; the backstops for those are that the agent has no network egress
# and that the documentation pull request is read by a human before it merges.
# ---------------------------------------------------------------------------
SECRET_CLASSES='generic-assignment
auth-header
anthropic-api-key
github-token
github-fine-grained-pat
aws-access-key-id
private-key-block
slack-token'

secret_ere_for() {
  case "$1" in
    generic-assignment)      printf '%s' '(password|token|api_key|secret|private_key|aws_secret|credentials)[[:space:]]*=[[:space:]]*["'"'"']?[A-Za-z0-9+/=_-]{8,}' ;;
    auth-header)             printf '%s' '(Authorization|X-API-Key):[[:space:]]*(Bearer[[:space:]]+)?[A-Za-z0-9+/=_-]{20,}' ;;
    anthropic-api-key)       printf '%s' 'sk-ant-[A-Za-z0-9_-]{16,}' ;;
    github-token)            printf '%s' 'gh[po]_[A-Za-z0-9]{36}' ;;
    github-fine-grained-pat) printf '%s' 'github_pat_[A-Za-z0-9_]{22,}' ;;
    aws-access-key-id)       printf '%s' 'AKIA[0-9A-Z]{16}' ;;
    private-key-block)       printf '%s' '-----BEGIN [A-Z ]*PRIVATE KEY' ;;
    slack-token)             printf '%s' 'xox[baprs]-[A-Za-z0-9-]{10,}' ;;
  esac
}

scan_added_lines() {
  # $1 = patch file. Prints "path<TAB>pattern-class" for each hit.
  #
  # Only added lines are scanned. Removing a credential that is already in the
  # repository has to stay possible, and scanning context lines would forbid
  # that while catching nothing new.
  #
  # Matching is done with `grep -E` rather than awk regexes because every one of
  # these patterns needs a bounded repetition like {36}, and interval support in
  # awk varies across the mawk/BWK implementations these scripts run on.
  SP_PATCH="$1"
  SP_MAP="$TMPD/linemap.tsv"
  SP_ADDED="$TMPD/added-lines.txt"

  awk '
    /^\+\+\+ / {
      p = substr($0, 5);
      sub(/^b\//, "", p);
      if (p == "/dev/null") p = "(deleted)";
      path = p;
    }
    { print NR "\t" (path == "" ? "(unknown)" : path) }
  ' "$SP_PATCH" >"$SP_MAP" 2>/dev/null

  # `NNN:+text` for every added line, with the original patch line number kept
  # so each hit can be attributed to the file whose hunk it fell in.
  grep -n '^+' "$SP_PATCH" 2>/dev/null | grep -v '^[0-9][0-9]*:+++' >"$SP_ADDED" 2>/dev/null
  [ -f "$SP_ADDED" ] || : >"$SP_ADDED"

  printf '%s\n' "$SECRET_CLASSES" | while IFS= read -r CLASS; do
    [ -n "$CLASS" ] || continue
    SP_RE=$(secret_ere_for "$CLASS")
    [ -n "$SP_RE" ] || continue
    grep -E -e "$SP_RE" "$SP_ADDED" 2>/dev/null | cut -d: -f1 | while IFS= read -r LN; do
      case "$LN" in ''|*[!0-9]*) continue ;; esac
      HIT_PATH=$(awk -F'\t' -v n="$LN" '$1 == n { print $2; exit }' "$SP_MAP" 2>/dev/null)
      printf '%s\t%s\n' "${HIT_PATH:-(unknown)}" "$CLASS"
    done
  done | sort -u
}

report_secret_hits() {
  # $1 = hits (path<TAB>class). Names the file and the pattern class, never the
  # matched text: echoing the value would copy the credential into a build log
  # that is far more widely readable than the patch ever was.
  MSG="A credential pattern matched inside the generated patch. The patch was not written."
  echo "::error title=dossier secret scan::$MSG" >&2
  summary ""
  summary "### Dossier patch validation: REJECTED (credential pattern)"
  summary ""
  summary "$MSG The matched value is deliberately not reproduced here or in any log."
  summary ""
  summary "| File | Pattern class |"
  summary "|---|---|"
  printf '%s\n' "$1" | while IFS=$'\t' read -r P C; do
    [ -n "$P" ] || continue
    summary "| \`$P\` | \`$C\` |"
  done
  summary ""
  summary "Remove the value from the source it was read from, rotate it, then re-run."
  emit has_changes "false"
  emit files_changed "0"
  emit lines_changed "0"
  emit size_class "rejected"
  exit 1
}

MAX_DOC_FILES=30
MAX_DOC_LINES=3000
if command -v jq >/dev/null 2>&1; then
  MAX_DOC_FILES=$("$CASCADE" --default '30' '.dossier.ci.thresholds.maxDocChangedFiles' 2>/dev/null)
  MAX_DOC_LINES=$("$CASCADE" --default '3000' '.dossier.ci.thresholds.maxDocChangedLines' 2>/dev/null)
fi
case "$MAX_DOC_FILES" in ''|*[!0-9]*) MAX_DOC_FILES=30 ;; esac
case "$MAX_DOC_LINES" in ''|*[!0-9]*) MAX_DOC_LINES=3000 ;; esac

# ---------------------------------------------------------------------------
# Verification mode
# ---------------------------------------------------------------------------
if [ -n "$VERIFY_PATCH" ]; then
  # Every path the patch claims to touch, from both sides of every header. The
  # `a/` side matters as much as the `b/` side: a rename out of the allowlist
  # would otherwise pass on its destination alone.
  awk '
    /^diff --git / {
      line = substr($0, 12);
      n = split(line, parts, " ");
      for (i = 1; i <= n; i++) {
        p = parts[i];
        sub(/^[ab]\//, "", p);
        if (p != "" && p != "/dev/null") print p;
      }
    }
    /^--- / || /^\+\+\+ / {
      p = substr($0, 5);
      sub(/^[ab]\//, "", p);
      if (p != "" && p != "/dev/null") print p;
    }
  ' "$VERIFY_PATCH" | sort -u >"$TMPD/patch-paths.txt"

  # A path inside the allowlist can still point outside it. Mode 120000 is a
  # symlink, whose content is its target — so an allowlisted `docs/dossier/x.md`
  # created as a link to `../../.env` escapes by reference rather than by path,
  # and every later reader that follows links discloses the target. Path
  # checking alone cannot see this, so the mode is refused outright.
  if grep -qE '^(new file |old |new )mode 120000$' "$VERIFY_PATCH" 2>/dev/null; then
    summary ""
    summary "### Dossier patch validation: REJECTED (symlink)"
    summary ""
    summary "The patch creates or converts a file to a symbolic link. Documentation is written as regular files; a link inside the allowlist can point outside it."
    hard_fail "The patch contains a symlink mode (120000). It was not applied."
  fi

  VIOLATIONS=""
  while IFS= read -r P; do
    [ -n "$P" ] || continue
    path_allowed "$P" || VIOLATIONS="${VIOLATIONS}${P}
"
  done <"$TMPD/patch-paths.txt"

  if [ -n "$VIOLATIONS" ]; then
    summary ""
    summary "### Dossier patch validation: REJECTED (allowlist escape)"
    summary ""
    summary "The patch touches paths outside \`dossier.ci.writeAllowlist\`:"
    summary ""
    printf '%s\n' "$VIOLATIONS" | while IFS= read -r P; do
      [ -n "$P" ] || continue
      summary "- \`$P\`"
    done
    hard_fail "The patch touches paths outside the write allowlist. It was not applied."
  fi

  HITS=$(scan_added_lines "$VERIFY_PATCH")
  [ -n "$HITS" ] && report_secret_hits "$HITS"

  FILES_CHANGED=$(grep -c '^diff --git ' "$VERIFY_PATCH" 2>/dev/null | tr -d ' ')
  [ -n "$FILES_CHANGED" ] || FILES_CHANGED=0
  # File headers are skipped before counting so a patch touching many files does
  # not inflate its own line count by two per file.
  LINES_CHANGED=$(awk '/^\+\+\+/ || /^---/ { next } /^[+-]/ { n++ } END { print n + 0 }' "$VERIFY_PATCH" 2>/dev/null)
  [ -n "$LINES_CHANGED" ] || LINES_CHANGED=0
  [ "$FILES_CHANGED" -gt 0 ] && HAS_CHANGES="true"
  if [ "$FILES_CHANGED" -gt "$MAX_DOC_FILES" ] || [ "$LINES_CHANGED" -gt "$MAX_DOC_LINES" ]; then
    SIZE_CLASS="oversized"
  fi

  summary ""
  summary "### Dossier patch re-validation (privileged job)"
  summary ""
  summary "| Check | Result |"
  summary "|---|---|"
  summary "| Allowlist | pass — $(grep -c . "$TMPD/patch-paths.txt" 2>/dev/null | tr -d ' ') paths, all inside the allowlist |"
  summary "| Credential scan | pass |"
  summary "| Files changed | $FILES_CHANGED (ceiling $MAX_DOC_FILES) |"
  summary "| Lines changed | $LINES_CHANGED (ceiling $MAX_DOC_LINES) |"
  summary "| Size class | \`$SIZE_CLASS\` |"

  emit has_changes "$HAS_CHANGES"
  emit files_changed "$FILES_CHANGED"
  emit lines_changed "$LINES_CHANGED"
  emit size_class "$SIZE_CLASS"
  exit 0
fi

# ---------------------------------------------------------------------------
# Staging mode
#
# Step 1: refuse before staging anything if the working tree holds a path
# outside the allowlist. Running this before `git add` is what makes it a
# backstop rather than a formality — after a scoped add, an escaped file would
# simply be invisible.
# ---------------------------------------------------------------------------
VIOLATIONS=""
SYMLINKS=""
STATUS_COUNT=0
while IFS= read -r -d '' ENTRY; do
  ST=$(printf '%s' "$ENTRY" | cut -c1-2)
  P=$(printf '%s' "$ENTRY" | cut -c4-)
  case "$ST" in
    R*|C*)
      # Rename and copy entries are followed by their source path as a separate
      # NUL-terminated field. Both sides are checked.
      if IFS= read -r -d '' ORIG; then
        STATUS_COUNT=$((STATUS_COUNT + 1))
        path_allowed "$ORIG" || VIOLATIONS="${VIOLATIONS}${ORIG}
"
      fi
      ;;
  esac
  [ -n "$P" ] || continue
  STATUS_COUNT=$((STATUS_COUNT + 1))
  path_allowed "$P" || VIOLATIONS="${VIOLATIONS}${P}
"
  # Same reasoning as the verify-mode symlink refusal: an allowlisted path that
  # is a link resolves somewhere the allowlist never approved.
  if [ -L "$P" ]; then
    SYMLINKS="${SYMLINKS}${P}
"
  fi
done < <(git status --porcelain -z -uall 2>/dev/null)

if [ -n "$SYMLINKS" ]; then
  summary ""
  summary "### Dossier patch validation: REJECTED (symlink)"
  summary ""
  summary "The working tree stages symbolic links. Documentation is written as regular files; a link inside the allowlist can point outside it."
  printf '%s\n' "$SYMLINKS" | while IFS= read -r P; do
    [ -n "$P" ] || continue
    summary "- \`$P\`"
  done
  hard_fail "The working tree contains staged symbolic links. Nothing was written."
fi

if [ -n "$VIOLATIONS" ]; then
  summary ""
  summary "### Dossier patch validation: REJECTED (allowlist escape)"
  summary ""
  summary "The working tree contains modifications outside \`dossier.ci.writeAllowlist\`:"
  summary ""
  printf '%s\n' "$VIOLATIONS" | while IFS= read -r P; do
    [ -n "$P" ] || continue
    summary "- \`$P\`"
  done
  summary ""
  summary "This is reported rather than filtered on purpose. A filter would drop the"
  summary "offending files and produce a clean-looking patch, leaving no record that"
  summary "anything tried to write outside the documentation package."
  hard_fail "The working tree contains modifications outside the write allowlist. No patch was written."
fi

# Step 2: stage. `-A` over an explicit pathspec picks up new files, which is
# what a cold start produces almost exclusively.
printf '%s\n' "$ALLOW_GLOBS" | while IFS= read -r G; do
  G=$(printf '%s' "$G" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$G" ] || continue
  printf ':(glob)%s\n' "$G"
  case "$G" in
    *'*'*|*'?'*) : ;;
    */)          printf ':(glob)%s**\n' "$G" ;;
    *)           printf ':(glob)%s/**\n' "$G" ;;
  esac
done >"$TMPD/pathspecs.txt"

if [ -s "$TMPD/pathspecs.txt" ]; then
  # Read pathspecs from a file so a glob containing whitespace stays one
  # argument, and so `set -u` never meets an unset array under bash 3.2.
  tr '\n' '\0' <"$TMPD/pathspecs.txt" | xargs -0 git add -A -- 2>/dev/null
fi

if git diff --cached --quiet 2>/dev/null; then
  summary ""
  summary "### Dossier patch validation"
  summary ""
  summary "The refresh produced no documentation changes. Nothing to publish."
  emit has_changes "false"
  emit files_changed "0"
  emit lines_changed "0"
  emit size_class "ok"
  exit 0
fi

# Step 3: build the patch in a temporary location. --out is written only after
# every check has passed, so a rejected run leaves no artifact behind for a
# later step to pick up by mistake.
STAGED_PATCH="$TMPD/staged.patch"
if ! git diff --cached --binary >"$STAGED_PATCH" 2>/dev/null; then
  hard_fail "git diff --cached failed; no patch could be produced."
fi

# Step 4: credential scan, before the patch reaches its destination and
# therefore before any artifact upload can carry it off the runner.
HITS=$(scan_added_lines "$STAGED_PATCH")
[ -n "$HITS" ] && report_secret_hits "$HITS"

# Step 5: size gates.
FILES_CHANGED=$(git diff --cached --name-only 2>/dev/null | grep -c . | tr -d ' ')
[ -n "$FILES_CHANGED" ] || FILES_CHANGED=0
LINES_CHANGED=$(git diff --cached --numstat 2>/dev/null \
  | awk '{ a = ($1 == "-" ? 0 : $1); d = ($2 == "-" ? 0 : $2); s += a + d } END { print s + 0 }')
[ -n "$LINES_CHANGED" ] || LINES_CHANGED=0
HAS_CHANGES="true"

if [ "$FILES_CHANGED" -gt "$MAX_DOC_FILES" ] || [ "$LINES_CHANGED" -gt "$MAX_DOC_LINES" ]; then
  SIZE_CLASS="oversized"
fi

OUT_DIR=$(dirname "$OUT_PATCH")
mkdir -p "$OUT_DIR" 2>/dev/null
cp "$STAGED_PATCH" "$OUT_PATCH" || hard_fail "could not write the patch to '${OUT_PATCH}'."

summary ""
summary "### Dossier patch validation"
summary ""
summary "| Check | Result |"
summary "|---|---|"
summary "| Working-tree allowlist | pass — $STATUS_COUNT modified paths, all inside the allowlist |"
summary "| Credential scan | pass |"
summary "| Files changed | $FILES_CHANGED (ceiling $MAX_DOC_FILES) |"
summary "| Lines changed | $LINES_CHANGED (ceiling $MAX_DOC_LINES) |"
summary "| Size class | \`$SIZE_CLASS\` |"
if [ "$SIZE_CLASS" = "oversized" ]; then
  summary ""
  summary "The generated diff is larger than the configured ceilings. The work is kept:"
  summary "an oversized diff is the correct output of a cold start or a large refactor,"
  summary "so the documentation pull request opens as a draft for a closer read."
fi

emit has_changes "$HAS_CHANGES"
emit files_changed "$FILES_CHANGED"
emit lines_changed "$LINES_CHANGED"
emit size_class "$SIZE_CLASS"
exit 0
