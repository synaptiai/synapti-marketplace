#!/bin/bash
# [flow] PreToolUse hook: Block destructive operations
# Prevents recursive+force rm, unmerged branch deletion, and destructive resets/cleans

set -euo pipefail

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
# Does this word name something that will run a script handed to it? Used for
# the quoted-argument expansion below, not for heredoc stripping — the heredoc
# rule asks the opposite question (is the owner a text sink?) and answers it
# with a much shorter list, because there "keep" is the safe default and here
# "examine" is.
_bd_is_interpreter() {
  case "${1##*/}" in
    sh|bash|zsh|ksh|dash|ash|busybox|python|python2|python3|perl|ruby|node|deno|bun)
      return 0 ;;
    eval|source|.|ssh|su|doas|sudo|env|nohup|timeout|xargs|docker|kubectl|make|at)
      return 0 ;;
  esac
  return 1
}

# Non-code stripping, rebuilt.
#
# Every rule below judges BD_CODE, so anything this pass removes is a thing no
# rule can see. That makes each removal a potential false allow, and a false
# allow on this hook costs the tree. The design is therefore: remove only what
# is unambiguously text, and when anything at all is uncertain, keep it.
#
# Two things are removed.
#
# A `#` comment, from an unquoted `#` that opens a word to end of line. The
# scan tracks quotes and backslash escapes, so `HEAD#1`, a URL fragment, and a
# `#` inside a string are arguments rather than comments.
#
# A heredoc body, and only when every one of these holds:
#   - the line ends with the introducer, so the body starts on the next line;
#   - exactly one `<<` introducer is on that line;
#   - the delimiter is a plain word, optionally quoted with ' or ". A
#     backslash-quoted `<<\EOF` is not recognised, so its body is kept;
#   - the word immediately before `<<` is a text sink — cat, tee, echo, printf
#     or gh. This is the owner of the heredoc, not the first word of the line,
#     which is what makes `gh pr create --body "$(cat <<EOF" ` a sink while
#     `git commit -m "$(cat <<EOF" ` is one too, and `bash <<EOF`,
#     `ssh host <<EOF`, `sudo -s <<EOF`, `docker exec -i c1 <<EOF`,
#     `make -f - <<EOF` and `$SHELL <<EOF` are not;
#   - the line carries no `|` and no `>`, so the body is not piped into an
#     interpreter and not written to a file that something later runs;
#   - and the terminator is actually found. A heredoc that never terminates
#     keeps every line it consumed, because "I lost track" must never mean "so
#     nothing here counts".
#
# `<<<` is a here-string, not a heredoc: the delimiter pattern requires a word
# character after the `<<`, so `<<<word` never matches. `$(( a << b ))`, bare
# `(( a << b ))` and `let x=1<<3` do not match either — a shift operand is not
# a sink and the line does not end with the introducer.
#
# Carriage returns are stripped first, so a CRLF command is read the same way a
# LF one is. Both tokeniser paths then agree about where words end.
_bd_strip_noncode() {
  BD_CODE=$(printf '%s\n' "$1" | awk '
    function owner_word(str,   n, parts, seg) {
      # The heredoc belongs to the innermost command, which is the first word
      # after the last separator. Reading the word immediately before the `<<`
      # gets `tee notes.txt <<EOF` wrong (the owner is tee, not the filename),
      # and reading the first word of the line gets `echo x && bash <<EOF`
      # wrong in the dangerous direction.
      n = split(str, parts, /[;&|(`]/)
      seg = (n > 0) ? parts[n] : str
      gsub(/^[ \t]+/, "", seg)
      gsub(/[ \t]+$/, "", seg)
      if (seg == "") return ""
      n = split(seg, parts, /[ \t]+/)
      return (n > 0) ? parts[1] : ""
    }
    function is_sink(w,   SQ2) {
      SQ2 = sprintf("%c", 39)
      # The owner of a heredoc is commonly reached through a substitution:
      # `gh pr create --body "$(cat <<EOF` has `"$(cat` as the word before the
      # introducer. Strip the syntax that leads up to the command word, then
      # its directory, before comparing.
      gsub(/^[("`$]+/, "", w)
      gsub(/^["]+/, "", w)
      gsub("^" SQ2 "+", "", w)
      gsub(/^[($`]+/, "", w)
      sub(/^.*\//, "", w)
      return (w == "cat" || w == "tee" || w == "echo" || w == "printf" || w == "gh")
    }
    BEGIN { SQ = sprintf("%c", 39); inhd = 0; buf = ""; delim = ""; tabs = 0 }
    {
      line = $0
      sub(/\r$/, "", line)

      if (inhd) {
        cand = line
        if (tabs) sub(/^\t+/, "", cand)
        if (cand == delim) { inhd = 0; buf = ""; next }
        buf = buf line "\n"
        next
      }

      # --- is this line a droppable heredoc introducer? --------------------
      probe = line
      hits = gsub(/<</, "<<", probe)
      if (hits == 1 && line !~ /[|>]/ &&
          match(line, /<<-?["]?[A-Za-z_][A-Za-z0-9_]*["]?[ \t]*$/)) {
        intro = substr(line, RSTART)
        owner = owner_word(substr(line, 1, RSTART - 1))
        if (is_sink(owner)) {
          d = intro
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub(/^["]|["][ \t]*$/, "", d)
          gsub(/[ \t]+$/, "", d)
          if (d != "") { inhd = 1; delim = d; buf = "" }
        }
      }
      # The same shape with a single-quoted delimiter. Written separately
      # because embedding an apostrophe in this program would end it.
      if (!inhd && hits == 1 && line !~ /[|>]/ &&
          match(line, "<<-?" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ "[ \t]*$")) {
        intro = substr(line, RSTART)
        owner = owner_word(substr(line, 1, RSTART - 1))
        if (is_sink(owner)) {
          d = intro
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub(SQ, "", d)
          gsub(/[ \t]+$/, "", d)
          if (d != "") { inhd = 1; delim = d; buf = "" }
        }
      }

      # --- remove a comment, tracking quotes and backslash escapes ---------
      n = length(line); q = ""; cut = 0
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (c == "\\" && q != SQ) { i++; continue }
        if (q != "") { if (c == q) q = ""; continue }
        if (c == "\"" || c == SQ) { q = c; continue }
        if (c == "#") {
          prev = (i == 1) ? "" : substr(line, i - 1, 1)
          if (prev == "" || prev == " " || prev == "\t" || prev == ";" ||
              prev == "|" || prev == "&" || prev == "(" || prev == ")") { cut = i; break }
        }
      }
      print (cut > 0) ? substr(line, 1, cut - 1) : line
    }
    END {
      # An unterminated heredoc keeps everything it swallowed. Dropping it would
      # turn one mis-recognised introducer into a hook that sees nothing at all.
      if (inhd && buf != "") printf "%s", buf
    }
  ') || {
    echo "BLOCKED: could not scan the command (awk failed) — refusing rather than guessing." >&2
    exit 2
  }
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
  local p="$1"
  # Normalise before comparing. `./.` and `.//` are the same tree as `.`, and
  # comparing against a list of literals missed both.
  while :; do
    case "$p" in
      */) p="${p%/}"; [ -z "$p" ] && p="/" ;;
      ./*) p="${p#./}" ;;
      *//*) p="$(printf '%s' "$p" | sed 's#//*#/#g')" ;;
      *) break ;;
    esac
  done
  case "$p" in
    ''|.|/|:|:/|:/.|:/\*|'*'|'**'|:\(top\)|':(top)'|'.') return 0 ;;
  esac
  # An absolute path naming the repository root is the whole tree too.
  if [ "${p#/}" != "$p" ] && command -v git >/dev/null 2>&1; then
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$top" ] && [ "$p" = "$top" ]; then return 0; fi
  fi
  return 1
}

# git accepts any unambiguous abbreviation of a long option: `git reset --har`
# performs a hard reset and `git clean --forc` deletes untracked files. Matching
# the full spelling only is how both got through. The rm rule already matched
# prefixes; this brings the git rules onto the same footing.
# _bd_is_opt <token> <full-option> <shortest-accepted>
_bd_is_opt() {
  local tok="${1%%=*}" full="$2" min="$3"
  case "$tok" in
    --*) ;;
    *) return 1 ;;
  esac
  [ "${#tok}" -ge "${#min}" ] || return 1
  [ "${#tok}" -le "${#full}" ] || return 1
  case "$full" in
    "$tok"*) return 0 ;;
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

# An interpreter handed its script as a single quoted argument — `bash -c "git
# reset --hard"`, `sh -c '...'`, `ssh host "..."`, `eval "..."` — is one word to
# the tokeniser, so no rule could see the command inside it. Append the contents
# of those arguments as further lines, which the segmenting below then treats as
# ordinary commands. One level deep is enough for every real form; deeper
# nesting arrives here as its own quoted argument on the next pass anyway.
_bd_expand_interpreter_args() {
  local seg tok i n found
  local -a TOK=()
  local extra=""
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    case "$seg" in *[\'\"]*) ;; *) continue ;; esac
    _rm_tokenise "$seg"
    n=${#TOK[@]}
    found=0
    for ((i = 0; i < n; i++)); do
      tok="${TOK[i]}"
      if [ "${#tok}" -le 4096 ] && _bd_is_interpreter "${tok#\\}"; then found=1; continue; fi
      if [ "$found" = "1" ]; then
        case "$tok" in
          *[[:space:]]*) extra="$extra
$tok" ;;
        esac
      fi
    done
  done <<BD_EXPAND_EOF
$BD_CODE
BD_EXPAND_EOF
  if [ -n "$extra" ]; then BD_CODE="$BD_CODE$extra"; fi
}
_bd_expand_interpreter_args

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
done < <(printf '%s\n' "$BD_CODE" | tr ';|&()`' '\n')

exit 0
