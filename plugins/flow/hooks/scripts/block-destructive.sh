#!/bin/bash
# [flow] PreToolUse hook: Block destructive operations
# Prevents recursive+force rm, unmerged branch deletion, and destructive resets/cleans

set -euo pipefail

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# ---------------------------------------------------------------------------
# rm: block only when BOTH a recursive flag AND a force flag are present.
#
# `rm -f file` and `rm -r dir` are ordinary, bounded operations and pass. The
# destructive shape is recursive+force together, in any spelling: -rf, -fr,
# -Rf, -rF, -r -f, -f -r, -rv -f, --recursive --force, --force --recursive,
# -r --force, --recursive -f, plus GNU unambiguous long-option prefixes
# (--rec, --forc). Flags are recognised anywhere among the rm's arguments
# (GNU rm permutes options), up to a `--` terminator.
#
# Command-position anchoring: the command is split into simple commands on
# `;`, `|`, `&`, `(`, `)`, backtick and newline, and each is tokenised on
# unquoted whitespace (see Quoting below). The rule fires on a token that IS
# rm — `rm`, `/bin/rm`, `\rm` — never on rm as a substring of another word
# (`npm run rm-cache`, `perform`). Wrappers such as `sudo rm`, `xargs rm`,
# `env rm` are examined because rm still runs against the filesystem.
#
# Deliberate exemption: `git rm` (the token immediately before rm is `git`).
# `git rm -r --cached dir` only unstages, and even `git rm -rf` removes
# tracked files that remain recoverable from history — it is not
# filesystem-destructive in the sense this hook guards, so it is NOT blocked.
# (The previous regex matched it via `rm -r`, a false block.) Only the
# immediate `git rm` form is exempt; `git -C dir rm -rf x` is still examined.
#
# Targets: every target must be a SAFE_DIRS basename for the command to pass;
# one unsafe target (`rm -rf node_modules src`) blocks, and so does a
# recursive+force rm with no visible target (`ls | xargs rm -rf`) because the
# targets cannot be verified. Redirections (`2>/dev/null`, `> out`) are not
# targets.
#
# Quoting: each simple command is tokenised the way the shell does, on
# unquoted whitespace, with single and double quotes removed and their
# contents kept as part of the token. So `rm "-rf" src`, `rm '-fr' src` and
# `rm "--recursive" --force src` carry the same flags as `rm -rf src`, and
# `rm -rf "my dir"` has the one target `my dir`. (An earlier version split on
# bare whitespace and let a quoted flag through unseen.) Variable targets
# (`"$DIR"`) are not expanded and therefore count as unsafe (fail-safe), as
# does a target with an unterminated quote.
# ---------------------------------------------------------------------------
SAFE_DIRS="node_modules|\.next|dist|build|tmp|\.cache|__pycache__|coverage|\.turbo|\.parcel-cache|\.vite"

# _rm_tokenise <simple-command>
# Fills the caller's TOK array with the words of the command: split on
# unquoted whitespace, single/double quote pairs removed, quoted text kept
# verbatim (whitespace included) inside its word. Pure string handling — no
# pathname expansion, so `rm -rf *` is inspected literally. An unterminated
# quote runs to the end of the segment; the partial word is still a token.
_rm_tokenise() {
  local s="$1" i c q="" cur="" in_word=0
  TOK=()
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; else cur+="$c"; fi
      continue
    fi
    case "$c" in
      \"|\') q="$c"; in_word=1 ;;
      [[:space:]]) if [ "$in_word" = "1" ]; then TOK+=("$cur"); cur=""; in_word=0; fi ;;
      *) cur+="$c"; in_word=1 ;;
    esac
  done
  if [ "$in_word" = "1" ]; then TOK+=("$cur"); fi
}

# _rm_segment_is_destructive <simple-command>
# Returns 0 when the segment runs rm with recursive+force and at least one
# target outside SAFE_DIRS; 1 otherwise.
_rm_segment_is_destructive() {
  # Fast path: a segment without the letters "rm" cannot name rm; skip the
  # character-level tokeniser (hooks run on every Bash call, commands can be
  # long heredocs).
  case "$1" in *rm*) ;; *) return 1 ;; esac
  local -a TOK=()
  _rm_tokenise "$1"
  local n=${#TOK[@]} i idx=-1 base tok
  for ((i = 0; i < n; i++)); do
    base="${TOK[i]##*/}"     # /bin/rm -> rm
    base="${base#\\}"        # \rm -> rm
    if [ "$base" = "rm" ]; then idx=$i; break; fi
  done
  if [ "$idx" -lt 0 ]; then return 1; fi
  if [ "$idx" -gt 0 ]; then
    base="${TOK[idx-1]##*/}"
    if [ "$base" = "git" ]; then return 1; fi   # git rm exemption (see above)
  fi

  local REC=0 FORCE=0 END_OPTS=0 SKIP_NEXT=0
  local -a RM_TARGETS=()
  for ((i = idx + 1; i < n; i++)); do
    tok="${TOK[i]}"
    if [ "$SKIP_NEXT" = "1" ]; then SKIP_NEXT=0; continue; fi   # target of a bare redirection operator
    if [ "$END_OPTS" = "0" ]; then
      case "$tok" in
        --) END_OPTS=1; continue ;;
        --r|--re|--rec|--recu|--recur|--recurs|--recursi|--recursiv|--recursive) REC=1; continue ;;
        --f|--fo|--for|--forc|--force) FORCE=1; continue ;;
        --*) continue ;;                                   # other long options (--verbose, --preserve-root, ...)
        -?*)
          case "$tok" in *[rR]*) REC=1 ;; esac
          case "$tok" in *[fF]*) FORCE=1 ;; esac
          continue ;;
      esac
    fi
    case "$tok" in
      '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>') SKIP_NEXT=1; continue ;;   # bare redirection: next token is its file
      '>'*|'<'*|[0-9]'>'*) continue ;;                            # attached redirection (2>/dev/null)
    esac
    RM_TARGETS+=("$tok")
  done

  if [ "$REC" = "1" ] && [ "$FORCE" = "1" ]; then
    # No literal target means the targets come from somewhere the hook cannot
    # see (`ls | xargs rm -rf`, `rm -rf $(...)` split by the tokeniser). That
    # is "cannot verify", so it blocks; a bare `rm -rf` with no operand is a
    # no-op nobody runs on purpose, so nothing legitimate is lost.
    if [ "${#RM_TARGETS[@]}" -eq 0 ]; then return 0; fi
    local P
    for P in "${RM_TARGETS[@]}"; do
      if ! printf '%s\n' "$(basename -- "$P")" | grep -qE "^($SAFE_DIRS)$"; then
        return 0
      fi
    done
  fi
  return 1
}

RM_DESTRUCTIVE=0
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  if _rm_segment_is_destructive "$SEG"; then RM_DESTRUCTIVE=1; break; fi
done < <(printf '%s\n' "$COMMAND" | tr ';|&()`' '\n')
if [ "$RM_DESTRUCTIVE" = "1" ]; then
  echo "BLOCKED: Destructive rm -rf (recursive + force) detected. Review the target path and run manually if intended." >&2
  exit 2
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
