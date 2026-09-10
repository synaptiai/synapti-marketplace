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
#
# Cost. This runs on every simple command of every Bash call the hook sees, so
# it has to be linear in the length of the command. An earlier version walked
# characters in bash and appended one at a time; a 20KB argument that merely
# contained the letters "rm" — the word "perform" is enough — took fourteen
# seconds before the command it was guarding could start. Two paths avoid that:
# a segment with no quote in it is split by the shell builtin, and a segment
# with quotes goes through one awk pass that copies substring slices rather than
# characters. Neither allocates per character.
_rm_tokenise() {
  TOK=()
  case "$1" in
    *'"'*|*"'"*) ;;
    *)
      # No quotes: the shell splits on IFS exactly the way this function
      # defines words, with no subprocess. -r keeps backslashes, so `\rm`
      # stays one token, and -a never globs.
      read -r -a TOK <<< "$1"
      return 0 ;;
  esac

  local _tok_line
  while IFS= read -r _tok_line; do
    TOK+=("${_tok_line#T}")
  done < <(printf '%s\n' "$1" | awk '
    BEGIN { SQ = sprintf("%c", 39) }
    {
      s = $0; n = length(s); q = ""; cur = ""; in_word = 0; pos = 1
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == q) { cur = cur substr(s, pos, i - pos); pos = i + 1; q = "" }
          continue
        }
        if (c == "\"" || c == SQ) {
          cur = cur substr(s, pos, i - pos); pos = i + 1; q = c; in_word = 1
          continue
        }
        if (c == " " || c == "\t" || c == "\r") {
          cur = cur substr(s, pos, i - pos); pos = i + 1
          if (in_word) { print "T" cur; in_word = 0 }
          cur = ""
          continue
        }
        in_word = 1
      }
      # An unterminated quote runs to the end of the segment; the partial word
      # is still a token, which is what makes it fail safe rather than vanish.
      cur = cur substr(s, pos, n - pos + 1)
      if (in_word) print "T" cur
    }
  ')
}

# ---------------------------------------------------------------------------
# Non-code stripping.
#
# Every rule in this file judges the command that is being run. Two parts of a
# command string are text rather than code, and matching them is how this hook
# came to refuse a grep over example strings, a heredoc carrying those strings,
# and the `gh issue create` call that reported the problem (issues #167, #142):
#
#   - a `#` comment, when the `#` opens a word and is not inside quotes
#   - a heredoc body, from the line after the introducer to its terminator
#
# A heredoc body IS code when the heredoc is fed to something that runs it, so a
# line naming an interpreter anywhere keeps its bodies. That is deliberately
# generous — `cat <<EOF | bash` keeps the body too. Examining something harmless
# costs a comparison; skipping something real costs the tree.
#
# Quoting, word splitting and redirections are left to _rm_tokenise below.
# ---------------------------------------------------------------------------
# The scanner runs in awk, not in bash. It has to look at every character of
# every Bash command the hook sees, and a bash loop doing that pays a string
# concatenation per character: a 40KB quoted argument took 22 seconds, on a hook
# that runs before every command. The same pass in awk is one process and one
# linear walk. It also keeps the shell out of the business of comparing single
# characters, which is where the quoting gets delicate.
#
# The pass removes exactly two things and copies everything else through:
#   - from an unquoted `#` that opens a word, to the end of that line
#   - a heredoc body and its terminator, unless the introducing line names an
#     interpreter, in which case the body is code and is kept
#
# Output is assembled from substring slices around the removed ranges rather
# than character by character, so a long line costs a few concatenations.
_bd_strip_noncode() {
  BD_CODE=$(printf '%s\n' "$1" | awk '
    function is_interp(w,   b) {
      b = w
      sub(/^.*\//, "", b)
      sub(/^\\/, "", b)
      return (b == "sh" || b == "bash" || b == "zsh" || b == "ksh" || b == "dash" ||
              b == "ash" || b == "busybox" || b == "python" || b == "python2" ||
              b == "python3" || b == "perl" || b == "ruby" || b == "node" ||
              b == "deno" || b == "bun" || b == "eval" || b == "source" || b == "." ||
              b == "ssh" || b == "su" || b == "doas")
    }
    function is_break(c) {
      return (c == " " || c == "\t" || c == ";" || c == "|" || c == "&" ||
              c == "<" || c == ">" || c == "(" || c == ")")
    }
    function opens_word(c) {
      return (c == "" || c == " " || c == "\t" || c == ";" || c == "|" ||
              c == "&" || c == "(" || c == ")")
    }
    BEGIN { hd_n = 0; hd_i = 0; SQ = sprintf("%c", 39) }
    {
      line = $0
      if (hd_i < hd_n) {
        cand = line
        if (hd_tabs[hd_i]) sub(/^\t+/, "", cand)
        if (cand == hd_delim[hd_i]) { hd_i++; next }
        if (hd_keep[hd_i]) print line
        next
      }

      n = length(line)
      q = ""; prev = ""; cut = 0; nr = 0; first_new = hd_n
      paren = 0; outer_q = ""
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q != "") {
          # `$(` inside a double-quoted string opens code again. This is the
          # shape almost every PR body and commit message takes:
          #   gh pr create --body "$(cat <<EOF ... EOF)"
          # Without this, the heredoc introducer is inside quotes, no heredoc is
          # recorded, and the body lines are read as commands — which is exactly
          # how writing the issue that asked for this fix got refused three times.
          if (q == "\"" && c == "$" && substr(line, i + 1, 1) == "(") {
            outer_q = q; q = ""; paren = 1; i++; prev = "("
            continue
          }
          if (c == q) q = ""
          prev = c
          continue
        }
        if (paren > 0) {
          if (c == "(") paren++
          else if (c == ")") {
            paren--
            if (paren == 0) { q = outer_q; outer_q = ""; prev = c; continue }
          }
        }
        if (c == "\"" || c == SQ) { q = c; prev = c; continue }
        if (c == "#" && opens_word(prev)) { cut = i; break }
        if (c == "<" && substr(line, i + 1, 1) == "<" && substr(line, i + 2, 1) != "<") {
          j = i + 2; tabs = 0; dq = ""; word = ""
          if (substr(line, j, 1) == "-") { tabs = 1; j++ }
          while (substr(line, j, 1) == " " || substr(line, j, 1) == "\t") j++
          cc = substr(line, j, 1)
          if (cc == "\"" || cc == SQ) { dq = cc; j++ }
          while (j <= n) {
            cc = substr(line, j, 1)
            if (dq != "") { if (cc == dq) { j++; break } }
            else if (is_break(cc)) break
            word = word cc
            j++
          }
          if (word != "") {
            hd_delim[hd_n] = word; hd_tabs[hd_n] = tabs; hd_keep[hd_n] = 0; hd_n++
          }
          nr++; rs[nr] = i; re[nr] = j - 1
          i = j - 1
          prev = " "
          continue
        }
        prev = c
      }

      end = (cut > 0) ? cut - 1 : n
      out = ""
      pos = 1
      for (k = 1; k <= nr; k++) {
        if (rs[k] > end) break
        out = out substr(line, pos, rs[k] - pos) " "
        pos = re[k] + 1
        if (pos > end + 1) pos = end + 1
      }
      out = out substr(line, pos, end - pos + 1)

      if (hd_n > first_new) {
        tmp = out
        gsub(/["]/, " ", tmp)
        gsub(SQ, " ", tmp)
        # Split on the characters that separate a command word from the syntax
        # around it, so `$(bash` and `OUT=$(sh` are seen as bash and sh.
        m = split(tmp, parts, /[ \t()`;|&]+/)
        keep = 0
        for (k = 1; k <= m; k++) if (is_interp(parts[k])) { keep = 1; break }
        if (keep) for (k = first_new; k < hd_n; k++) hd_keep[k] = 1
      }
      print out
    }
  ')
}

# ---------------------------------------------------------------------------
# git command parsing.
#
# _bd_git_parse reads one simple command and, when that command IS git, sets
# GIT_SUB to the subcommand and GIT_ARGS to everything after it. `git` is
# recognised the way `rm` is: as a command word, never as a substring, so
# `npm run git-reset-helper` and the word `digit` are not git. Global options
# taking a value (-C, -c, --git-dir, ...) are stepped over so the subcommand
# behind them is still found.
# ---------------------------------------------------------------------------
_bd_git_parse() {
  GIT_SUB=""; GIT_ARGS=(); GIT_ARGN=0
  case "$1" in *git*) ;; *) return 1 ;; esac
  local -a TOK=()
  _rm_tokenise "$1"
  local n=${#TOK[@]} i base idx=-1
  for ((i = 0; i < n; i++)); do
    # A command word is a program name, never a 40KB argument. Skipping the
    # basename strip for oversized tokens matters because `${tok##*/}` is a
    # greedy glob: on a long token bash re-scans, and a single 40KB quoted
    # argument cost 1.3 seconds here before this check existed. 4096 is
    # PATH_MAX; nothing runnable is longer.
    [ "${#TOK[i]}" -le 4096 ] || continue
    base="${TOK[i]##*/}"
    base="${base#\\}"
    if [ "$base" = "git" ]; then idx=$i; break; fi
  done
  [ "$idx" -lt 0 ] && return 1
  i=$((idx + 1))
  while [ $i -lt $n ]; do
    case "${TOK[i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env)
        i=$((i + 2)); continue ;;
      -*) i=$((i + 1)); continue ;;
      *) break ;;
    esac
  done
  [ $i -ge $n ] && return 1
  GIT_SUB="${TOK[i]}"
  i=$((i + 1))
  while [ $i -lt $n ]; do
    GIT_ARGS[$GIT_ARGN]="${TOK[i]}"; GIT_ARGN=$((GIT_ARGN + 1)); i=$((i + 1))
  done
  return 0
}

# A pathspec naming the whole working tree. A path that merely begins with a dot
# — .github/workflows/ci.yml, .decisions/issue-749.md — is an ordinary path, and
# reading it as the whole tree was the defect reported in issue #167.
_bd_is_whole_tree() {
  case "$1" in
    .|./|:/|:/.) return 0 ;;
  esac
  return 1
}

# A redirection is not an argument to the command.
_bd_is_redirection() {
  case "$1" in
    '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>'|'>'*|'<'*|[0-9]'>'*) return 0 ;;
  esac
  return 1
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

RM_DESTRUCTIVE=0
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  if _rm_segment_is_destructive "$SEG"; then RM_DESTRUCTIVE=1; break; fi
done < <(printf '%s\n' "$BD_CODE" | tr ';|&()`' '\n')
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
# Detection is per simple command, so the flags and the targets come from the
# same `git branch` rather than from anywhere in the string. Targets are
# collected here, where the parse already knows which words are options.
IS_FORCE_DELETE=0
TARGETS=""
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  _bd_git_parse "$SEG" || continue
  [ "$GIT_SUB" = "branch" ] || continue
  BR_BIG_D=0; BR_SMALL_D=0; BR_FORCE=0; BR_TARGETS=""
  for ((BI = 0; BI < GIT_ARGN; BI++)); do
    BTOK="${GIT_ARGS[BI]}"
    if _bd_is_redirection "$BTOK"; then continue; fi
    case "$BTOK" in
      --delete) BR_SMALL_D=1; continue ;;
      --force) BR_FORCE=1; continue ;;
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
done < <(printf '%s\n' "$BD_CODE" | tr ';|&()`' '\n')

# A force delete is irreversible and is allowed only on a branch this hook can
# prove is merged. That proof covers the branch, not the rest of the line, so a
# force delete chained to anything else is refused rather than used to greenlight
# the chain. This used to fall out of the target parser by accident: a compound
# left junk words that failed the show-ref check. It is a rule, so it says so.
BD_SEGMENT_COUNT=$(printf '%s\n' "$BD_CODE" | tr ';|&()`' '\n' | grep -c '[^[:space:]]' || true)
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
    echo "BLOCKED: Force branch deletion chained into a compound command. The merged-branch check covers the branch, not the rest of the line. Run the delete on its own if intended." >&2
    exit 2
  fi
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
      SEEN_SEP=0; WHOLE=0
      for ((GI = 0; GI < GIT_ARGN; GI++)); do
        GTOK="${GIT_ARGS[GI]}"
        _bd_is_redirection "$GTOK" && continue
        if [ "$SEEN_SEP" = "0" ]; then
          [ "$GTOK" = "--" ] && { SEEN_SEP=1; continue; }
          continue
        fi
        _bd_is_whole_tree "$GTOK" && WHOLE=1
      done
      if [ "$SEEN_SEP" = "1" ] && [ "$WHOLE" = "1" ]; then
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
            --staged) STAGED=1; continue ;;
            --worktree) WORKTREE=1; continue ;;
            --source|-s) GI=$((GI + 1)); continue ;;
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
        if [ "${GIT_ARGS[GI]}" = "--hard" ]; then
          echo "BLOCKED: Hard reset detected. This discards uncommitted work. Run manually if intended." >&2
          exit 2
        fi
      done
      ;;

    clean)
      for ((GI = 0; GI < GIT_ARGN; GI++)); do
        GTOK="${GIT_ARGS[GI]}"
        _bd_is_redirection "$GTOK" && continue
        case "$GTOK" in
          --force) exit_clean=1 ;;
          --*) continue ;;
          -?*) case "$GTOK" in *f*) exit_clean=1 ;; *) continue ;; esac ;;
          *) continue ;;
        esac
        if [ "${exit_clean:-0}" = "1" ]; then
          echo "BLOCKED: Force clean detected. This removes untracked files permanently. Run manually if intended." >&2
          exit 2
        fi
      done
      ;;
  esac
done < <(printf '%s\n' "$BD_CODE" | tr ';|&()`' '\n')

exit 0
