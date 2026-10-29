#!/bin/bash
# [flow] PreToolUse hook: Block destructive operations
# Prevents recursive+force rm, unmerged branch deletion, and destructive resets/cleans

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

# Same posture for awk. Every rule below reads the command through an awk pass;
# without it the scan produces nothing, and nothing scanned would mean nothing
# blocked. A hook that cannot see must not wave things through.
if ! command -v awk >/dev/null 2>&1; then
  echo "BLOCKED: awk not available — cannot verify command safety. Install awk to proceed." >&2
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

# The command parser lives in a library because a second hook needs it too, and
# two copies of a parser this fiddly is two places for the next defect to hide.
_BD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/command-parse.sh"
if [ ! -r "$_BD_LIB" ]; then
  echo "BLOCKED: cannot read $_BD_LIB — the command parser is missing, so command safety cannot be verified." >&2
  exit 2
fi
# shellcheck source=lib/command-parse.sh
. "$_BD_LIB"
# Readable is not the same as loaded: a truncated library defines nothing, and
# the first call to it would exit 127, which lets the command run.
for _bd_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _rm_tokenise _bd_git_parse _bd_is_whole_tree _bd_is_redirection _bd_is_opt; do
  if ! type "$_bd_fn" >/dev/null 2>&1; then
    echo "BLOCKED: the command parser did not load ($_bd_fn is undefined), so command safety cannot be verified." >&2
    exit 2
  fi
done
if [ -z "${_BD_SEG_AWK:-}" ]; then
  echo "BLOCKED: the command parser did not load (its segmenter program is empty), so command safety cannot be verified." >&2
  exit 2
fi

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
    # A command word is a program name, never a 40KB argument. Skipping the
    # basename strip for oversized tokens matters because `${tok##*/}` is a
    # greedy glob: on a long token bash re-scans, and a single 40KB quoted
    # argument cost 1.3 seconds here before this check existed. 4096 is
    # PATH_MAX; nothing runnable is longer.
    [ "${#TOK[i]}" -le 4096 ] || continue
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

# Strip comments and heredoc bodies once; every rule below reads BD_CODE.
_bd_strip_noncode "$COMMAND"

# An interpreter handed its script as a single quoted argument (`bash -c "..."`,
# `eval "..."`) hides that script from the tokeniser; see lib/command-parse.sh.
_bd_expand_interpreter_args

# Segment once; every rule below reads BD_SEGS. A parse that failed says so in a
# marker line, because an empty list would read as "nothing to check".
BD_SEGS=$(_bd_segments "$BD_CODE")
case "$BD_SEGS" in
  *__BD_SEG_FAIL__*)
    echo "BLOCKED: could not split the command into simple commands — refusing rather than guessing." >&2
    exit 2 ;;
esac

RM_DESTRUCTIVE=0
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  if _rm_segment_is_destructive "$SEG"; then RM_DESTRUCTIVE=1; break; fi
done <<< "$BD_SEGS"
if [ "$RM_DESTRUCTIVE" = "1" ]; then
  echo "BLOCKED: Destructive rm -rf (recursive + force) detected. Review the target path and run manually if intended." >&2
  exit 2
fi

# Text as a refusal may show it: control characters replaced (a commit subject
# is written by whoever made the commit, and stderr goes back into a
# transcript), and not so long that the next step after it is lost. Copied
# from block-unchecked-merge.sh. $2 is the length limit.
_bd_show() {
  local v="$1" max="${2:-200}"
  v="${v//[[:cntrl:]]/?}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  if [ "${#v}" -gt "$max" ]; then v="${v:0:$max}..."; fi
  printf '%s' "$v"
}

# A branch name as one shell word, for a command a refusal tells someone to
# type: as it is when every character is plain, otherwise in single quotes. A
# name can hold `$(`, `;` and quotes, and a pasted command must not run them.
_bd_word() {
  local v sq="'" esc="'\\''"
  v=$(_bd_show "$1" 200)
  case "$v" in
    '') printf "''" ;;
    # Each ' becomes '\'' (close, an escaped quote, reopen). The pattern and
    # the replacement are variables: bash 3.2 misreads quotes written inside
    # the expansion.
    *[!A-Za-z0-9._/@+-]*) printf "'%s'" "${v//$sq/$esc}" ;;
    *) printf '%s' "$v" ;;
  esac
}

# _bd_pr_lookup <branch> <default> — was <branch> merged through a pull request
# whose head contains its tip? A local branch can be behind its pull request:
# the PR got more commits after the last pull, and was squash-merged at that
# later head. Every commit on the branch then reached the default branch, but
# neither local check below can see it (#310). Asks GitHub for the pull
# requests merged from the branch's upstream name into <default>, and for each,
# whether its head commit contains the tip: locally when that commit is here,
# otherwise by GitHub's compare (behind_by 0 means the head has every commit on
# the tip). A tip that was never pushed cannot be compared and stays refused.
# Any failure leaves PR_MERGED at 0. Sets PR_MERGED, PR_FAILED (a call to
# GitHub failed), PR_ODD (GitHub answered something that could not be read)
# and PR_NOTE (what GitHub said, one line per finding). Also sets PR_HEAD, the
# branch name GitHub was asked about.
_bd_pr_lookup() {
  local br="$1" base="$2" head tip errf out rc err list n oid behind oid_ok=0
  PR_MERGED=0; PR_FAILED=0; PR_ODD=0; PR_NOTE=""; PR_HEAD="$br"
  if ! command -v gh >/dev/null 2>&1; then
    PR_FAILED=1; PR_NOTE="GitHub: not asked, because gh is not on PATH"; return
  fi
  head=$(git config --get "branch.$br.merge" 2>/dev/null); head="${head#refs/heads/}"
  [ -n "$head" ] || head="$br"
  PR_HEAD="$head"
  tip=$(git rev-parse --verify --quiet "refs/heads/$br^{commit}" 2>/dev/null)
  if [ -z "$tip" ]; then PR_FAILED=1; PR_NOTE="GitHub: not asked, because the tip of '$(_bd_show "$br")' could not be read"; return; fi
  if ! errf=$(mktemp -t flow-bd-err.XXXXXX 2>/dev/null); then
    PR_FAILED=1; PR_NOTE="GitHub: not asked, because a temporary file could not be created"; return
  fi
  out=$(gh pr list --state merged --head "$head" --base "$base" --json number,baseRefName,headRefOid --limit 10 2>"$errf"); rc=$?
  err=$(sed '/^[[:space:]]*$/d' "$errf" 2>/dev/null | head -n 1); rm -f "$errf"
  if [ "$rc" -ne 0 ]; then
    PR_FAILED=1; PR_NOTE="GitHub: the lookup of merged pull requests failed (gh exit $rc: $(_bd_show "${err:-no message}" 300))"; return
  fi
  if ! list=$(printf '%s' "$out" | jq -r --arg b "$base" '
        if type == "array" and all(.[]; type == "object" and (.baseRefName | type) == "string")
        then .[] | select(.baseRefName == $b) | "\(.number) \(.headRefOid)" else error("shape") end' 2>/dev/null); then
    PR_ODD=1; PR_NOTE="GitHub: the lookup of merged pull requests returned an answer that did not parse"; return
  fi
  if [ -z "$list" ]; then
    PR_NOTE="GitHub: no pull request from '$(_bd_show "$head")' merged into '$(_bd_show "$base")'"; return
  fi
  while read -r n oid; do
    case "$n" in
      ''|*[!0-9]*)
        PR_ODD=1
        PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: a merged pull request from '$(_bd_show "$head")' has no readable number"; continue ;;
    esac
    # A full commit id and nothing else: it goes into a git revision and a URL.
    case "${#oid}:$oid" in
      40:*[!0-9a-f]*|40:) ;;
      40:*) oid_ok=1 ;;
    esac
    if [ "${oid_ok:-0}" != 1 ]; then
      PR_ODD=1
      PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: PR #$n has no readable head commit"; continue
    fi
    oid_ok=0
    if git cat-file -e "$oid^{commit}" 2>/dev/null; then
      if git merge-base --is-ancestor "$tip" "$oid" 2>/dev/null; then PR_MERGED=1; return; fi
      PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: PR #$n was merged into '$(_bd_show "$base")' at head ${oid:0:7}, which does not contain ${tip:0:7}"
      continue
    fi
    if ! errf=$(mktemp -t flow-bd-err.XXXXXX 2>/dev/null); then
      PR_FAILED=1; PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: PR #$n was not compared, because a temporary file could not be created"; continue
    fi
    behind=$(gh api "repos/{owner}/{repo}/compare/$tip...$oid" --jq .behind_by 2>"$errf"); rc=$?
    err=$(sed '/^[[:space:]]*$/d' "$errf" 2>/dev/null | head -n 1); rm -f "$errf"
    if [ "$rc" -eq 0 ] && [ "$behind" = "0" ]; then PR_MERGED=1; return; fi
    case "$rc:$behind" in
      0:*[!0-9]*|0:)
        PR_ODD=1
        PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: PR #$n was merged into '$(_bd_show "$base")' at head ${oid:0:7}, but GitHub's compare answer could not be read ($(_bd_show "${behind:-empty}" 60))" ;;
      0:[0-9]*)
        PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: PR #$n was merged into '$(_bd_show "$base")' at head ${oid:0:7}, which does not contain ${tip:0:7} ($(_bd_show "$behind" 20) commit(s) on '$(_bd_show "$br")' are not in it)" ;;
      *)
        PR_FAILED=1
        PR_NOTE="${PR_NOTE:+$PR_NOTE
  }GitHub: PR #$n was merged into '$(_bd_show "$base")' at head ${oid:0:7}, which GitHub could not compare with ${tip:0:7} (gh exit $rc: $(_bd_show "${err:-no message}" 300))" ;;
    esac
  done <<< "$list"
}

# Force branch deletion: allowed ONLY when every target branch is provably
# merged into the default branch. `git branch -d` (the safe form) cannot delete
# squash-merged branches — git doesn't see their commits on the default branch —
# so a blanket force-delete block makes squash-merged cleanup impossible. This
# check distinguishes merged (safe to drop) from unmerged (would lose work) and
# fails safe (blocks) on any uncertainty. A refusal names what was compared, and
# ends with a line starting "Next: ": a command the agent can run, or the exact
# command the user must type (`!` runs it without PreToolUse hooks).
#
# Force-delete is detected in every equivalent form: -D, a combined short
# cluster containing D (-Df, -fD, -rD), or a delete flag (-d/--delete) together
# with a force flag (-f/--force). Plain `git branch -d` (safe delete, no force)
# is NOT matched and passes through.
# Detection is per simple command, so the flags and the targets come from the
# same `git branch` rather than from anywhere in the string. Targets are
# collected here, where the parse already knows which words are options.
IS_FORCE_DELETE=0
TARGETS=""
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  _bd_git_parse "$SEG" || continue
  [ "$GIT_SUB" = "branch" ] || continue
  BR_BIG_D=0; BR_SMALL_D=0; BR_FORCE=0; BR_TARGETS=""; BR_SKIP=0
  for ((BI = 0; BI < GIT_ARGN; BI++)); do
    BTOK="${GIT_ARGS[BI]}"
    if [ "$BR_SKIP" = "1" ]; then BR_SKIP=0; continue; fi
    case "$BTOK" in
      '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>') BR_SKIP=1; continue ;;
    esac
    if _bd_is_redirection "$BTOK"; then continue; fi
    if _bd_is_opt "$BTOK" "--delete" "--d"; then BR_SMALL_D=1; continue; fi
    if _bd_is_opt "$BTOK" "--force" "--f"; then BR_FORCE=1; continue; fi
    case "$BTOK" in
      --*) continue ;;
      -?*)
        case "$BTOK" in *D*) BR_BIG_D=1 ;; esac
        case "$BTOK" in *d*) BR_SMALL_D=1 ;; esac
        case "$BTOK" in *f*) BR_FORCE=1 ;; esac
        continue ;;
    esac
    BR_TARGETS="$BR_TARGETS $BTOK"
  done
  if [ "$BR_BIG_D" = "1" ] || { [ "$BR_SMALL_D" = "1" ] && [ "$BR_FORCE" = "1" ]; }; then
    IS_FORCE_DELETE=1
    TARGETS="$TARGETS$BR_TARGETS"
  fi
done <<< "$BD_SEGS"

# A force delete is irreversible and is allowed only on a branch this hook can
# prove is merged. That proof covers the branch, not the rest of the line, so a
# force delete chained to anything else is refused rather than used to greenlight
# the chain. This used to fall out of the target parser by accident: a compound
# left junk words that failed the show-ref check. It is a rule, so it says so.
BD_SEGMENT_COUNT=$(printf '%s\n' "$BD_SEGS" | grep -v '^__BD_' | grep -c '[^[:space:]]' || true)
[ -z "$BD_SEGMENT_COUNT" ] && BD_SEGMENT_COUNT=0

if [ "$IS_FORCE_DELETE" = "1" ]; then
  set +e          # this block is fully conditional and always exits explicitly
  set -f          # no pathname expansion of parsed tokens

  # TARGETS was collected above, per simple command, from the same parse that
  # decided this is a force delete. A force-delete chained into a compound
  # command no longer contributes the other command's words as branch names:
  # each simple command is judged on the branches it actually names, and the
  # other commands in the chain are judged by their own rules.

  if [ "$BD_SEGMENT_COUNT" -gt 1 ]; then
    echo "BLOCKED: Force branch deletion chained into a compound command. The merged-branch check covers the branch, not the rest of the line." >&2
    BD_WORDS=""
    for BT in $TARGETS; do BD_WORDS="$BD_WORDS $(_bd_word "$BT")"; done
    echo "Next: run the delete on its own: git branch -D${BD_WORDS}" >&2
    exit 2
  fi
  if [ -z "$TARGETS" ]; then
    echo "BLOCKED: Force branch deletion with no resolvable target." >&2
    echo "Next: name the branch literally: git branch -D <branch>" >&2
    exit 2
  fi
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "BLOCKED: Force branch deletion — cannot verify merge status (not a git repo / git unavailable)." >&2
    echo "Next: run the delete from inside the repository the branch belongs to." >&2
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
    echo "BLOCKED: Force branch deletion — cannot resolve a default branch to verify against (no origin/HEAD, no local main or master)." >&2
    echo "Next: run git remote set-head origin --auto, then run the delete again." >&2
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
      echo "BLOCKED: Refusing to force-delete the default branch '$(_bd_show "$DEFAULT")'." >&2
      echo "Next: leave it in place. If deleting it is really intended, the user must type: ! git branch -D $(_bd_word "$BR")" >&2
      exit 2
    fi
    if ! git show-ref --verify --quiet "refs/heads/$BR"; then
      echo "BLOCKED: Force branch deletion — '$(_bd_show "$BR")' is not a local branch (cannot verify merge status)." >&2
      echo "Next: check the name with git branch --list, then run the delete again with the exact name." >&2
      exit 2
    fi

    MERGED=0
    SQUASH_RAN=" "     # the refs the squash check ran against, for a refusal
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
          SQUASH_RAN="$SQUASH_RAN$REF "
          case "$(git cherry "$REF" "$SYNTH" 2>/dev/null | head -n1)" in
            -*) MERGED=1; break ;;
          esac
        fi
      fi
    done

    # (3) Merged through a pull request whose head is ahead of the branch.
    # Asked only when both local checks failed, so a branch they prove merged
    # never waits on the network.
    if [ "$MERGED" != "1" ]; then
      _bd_pr_lookup "$BR" "$DEFAULT"
      [ "$PR_MERGED" = "1" ] && MERGED=1
    fi

    if [ "$MERGED" != "1" ]; then
      echo "BLOCKED: '$(_bd_show "$BR")' is not merged into '$(_bd_show "$DEFAULT")' — force-delete would lose the commits below. Compared with:" >&2
      for REF in $DEFAULT_REFS; do
        CNT=$(git rev-list --count "$REF..$BR" 2>/dev/null)
        case "$CNT" in
          ''|*[!0-9]*) echo "  '$(_bd_show "$REF")': could not be compared" >&2; continue ;;
          1) echo "  '$(_bd_show "$REF")': 1 commit on '$(_bd_show "$BR")' is not in it:" >&2 ;;
          *) echo "  '$(_bd_show "$REF")': $CNT commits on '$(_bd_show "$BR")' are not in it:" >&2 ;;
        esac
        git log --format='%H %s' -n 5 "$REF..$BR" 2>/dev/null | while read -r H SUBJ; do
          echo "    ${H:0:7} $(_bd_show "$SUBJ" 120)" >&2
        done
        [ "$CNT" -gt 5 ] && echo "    and $((CNT - 5)) more" >&2
        case "$SQUASH_RAN" in
          *" $REF "*) echo "    and no commit on it has the same change as the whole branch (the squash-merge check)" >&2 ;;
          *) echo "    and the squash-merge check could not run against it (no merge base, or the branch's tree could not be read)" >&2 ;;
        esac
      done
      echo "  $PR_NOTE" >&2
      if [ "$PR_ODD" = "1" ]; then
        [ "$PR_FAILED" = "1" ] && echo "A call to GitHub also failed, so running the delete again may help." >&2
        echo "Next: run gh pr list --state merged --head $(_bd_word "$PR_HEAD") --base $(_bd_word "$DEFAULT") --json number,baseRefName,headRefOid and check what GitHub reports. If this work is not needed, the user must type: ! git branch -D $(_bd_word "$BR")" >&2
      elif [ "$PR_FAILED" = "1" ]; then
        echo "Next: read what GitHub said above. If it was a connection failure, run the delete again; otherwise, if this work is not needed, the user must type: ! git branch -D $(_bd_word "$BR")" >&2
      else
        echo "Next: push the work and open a pull request if it is needed. If it is not, the user must type: ! git branch -D $(_bd_word "$BR")" >&2
      fi
      exit 2
    fi
  done

  # Every target is merged into the default branch — safe to drop.
  exit 0
fi

# ---------------------------------------------------------------------------
# The whole-tree discard rules: checkout, restore, reset --hard, clean --force.
#
# Each is decided from a parsed `git` invocation rather than from a regex over
# the command text. What changes in practice:
#
#   - `git checkout -- .decisions/x.md` and `git restore .github/workflows/ci.yml`
#     are allowed. A dotted path is a path.
#   - `git checkout -- .` and `git restore .` are blocked, with or without
#     further arguments after them.
#   - `git restore --staged .` is allowed: it rewrites the index and leaves every
#     working-tree change in place, so nothing is lost. Adding `--worktree`
#     makes it a working-tree discard and it blocks.
#   - Text that names one of these commands without running it is allowed.
#
# One form moves from allowed to blocked: `git checkout <options> -- .`, where an
# option sits between the subcommand and the separator. It is the same discard
# the rule already names, and the old regex missed it only because it required
# `--` to follow `checkout` immediately.
# ---------------------------------------------------------------------------
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  _bd_git_parse "$SEG" || continue

  case "$GIT_SUB" in
    checkout)
      # No `--` is required. `git checkout .` discards every working-tree change
      # exactly as `git checkout -- .` does, and the old regex demanded the
      # separator, so the commoner and shorter spelling went through. A
      # whole-tree pathspec is never a branch name, so `git checkout main` and
      # `git checkout -b feature/x` are unaffected.
      SEEN_SEP=0; WHOLE=0
      for ((GI = 0; GI < GIT_ARGN; GI++)); do
        GTOK="${GIT_ARGS[GI]}"
        _bd_is_redirection "$GTOK" && continue
        if [ "$SEEN_SEP" = "0" ]; then
          [ "$GTOK" = "--" ] && { SEEN_SEP=1; continue; }
          case "$GTOK" in -*) continue ;; esac
        fi
        _bd_is_whole_tree "$GTOK" && WHOLE=1
      done
      if [ "$WHOLE" = "1" ]; then
        echo "BLOCKED: Discarding all changes detected. Use selective checkout or stash instead." >&2
        exit 2
      fi
      ;;

    restore)
      SEEN_SEP=0; WHOLE=0; STAGED=0; WORKTREE=0
      for ((GI = 0; GI < GIT_ARGN; GI++)); do
        GTOK="${GIT_ARGS[GI]}"
        _bd_is_redirection "$GTOK" && continue
        if [ "$SEEN_SEP" = "0" ]; then
          case "$GTOK" in
            --) SEEN_SEP=1; continue ;;
            --source=*) continue ;;
            --source|-s) GI=$((GI + 1)); continue ;;
          esac
          if _bd_is_opt "$GTOK" "--staged" "--st"; then STAGED=1; continue; fi
          if _bd_is_opt "$GTOK" "--worktree" "--w"; then WORKTREE=1; continue; fi
          case "$GTOK" in
            --*) continue ;;
            -?*)
              case "$GTOK" in *S*) STAGED=1 ;; esac
              case "$GTOK" in *W*) WORKTREE=1 ;; esac
              continue ;;
          esac
        fi
        _bd_is_whole_tree "$GTOK" && WHOLE=1
      done
      # --staged alone rewrites the index only; the working tree is untouched.
      if [ "$WHOLE" = "1" ] && ! { [ "$STAGED" = "1" ] && [ "$WORKTREE" = "0" ]; }; then
        echo "BLOCKED: Discarding all changes detected (git restore). Use selective restore or stash instead." >&2
        exit 2
      fi
      ;;

    reset)
      for ((GI = 0; GI < GIT_ARGN; GI++)); do
        if _bd_is_opt "${GIT_ARGS[GI]}" "--hard" "--ha"; then
          echo "BLOCKED: Hard reset detected. This discards uncommitted work. Run manually if intended." >&2
          exit 2
        fi
      done
      ;;

    clean)
      exit_clean=0
      for ((GI = 0; GI < GIT_ARGN; GI++)); do
        GTOK="${GIT_ARGS[GI]}"
        _bd_is_redirection "$GTOK" && continue
        if _bd_is_opt "$GTOK" "--force" "--f"; then
          exit_clean=1
        else
          case "$GTOK" in
            --*) continue ;;
            -?*) case "$GTOK" in *f*) exit_clean=1 ;; *) continue ;; esac ;;
            *) continue ;;
          esac
        fi
        if [ "${exit_clean:-0}" = "1" ]; then
          echo "BLOCKED: Force clean detected. This removes untracked files permanently. Run manually if intended." >&2
          exit 2
        fi
      done
      ;;
  esac
done <<< "$BD_SEGS"

exit 0
