#!/usr/bin/env bash
# plugins/flow/hooks/scripts/lib/command-parse.sh
#
# Reading a shell command the way the shell reads it: words, quoting, comments,
# heredoc bodies, and where a command word actually sits. Sourced by the hooks
# that have to decide what a command IS rather than what its text looks like.
#
# The alternative is a regex over the raw string, and the record of that
# approach is in issues #167 and #142: a path beginning with a dot read as the
# whole tree, and a command refused because a code block in a bug report quoted
# it. Anything sourcing this file gets one implementation of the hard part,
# which also means one place to fix when the hard part turns out to be wrong.
#
# Contract for callers:
#   _bd_strip_noncode <command>   -> sets BD_CODE
#   _rm_tokenise <simple-command> -> fills TOK
#   _bd_git_parse <simple-command> -> sets GIT_SUB, GIT_ARGS, GIT_ARGN; 1 if not git
#   _bd_is_whole_tree <pathspec>  -> 0 when the pathspec is the whole tree
#   _bd_is_redirection <token>    -> 0 when the token is a redirection
#   _bd_is_opt <token> <full> <min> -> 0 when the token is that long option,
#                                    including any unambiguous abbreviation
#   _bd_is_interpreter <word>     -> 0 when the word names something that runs a script
#
# Every rule that reads BD_CODE inherits its posture: it removes only what is
# unambiguously text, and keeps anything uncertain. See the comments below.

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

# _bd_segments <text>
# Prints one simple command per line.
#
# Splits on `;` `|` `&` where the shell would — outside quotes — and treats a
# command substitution as BOTH things it is: a command in its own right, emitted
# as its own segment, and a word in the command containing it, which therefore
# survives as `__BD_SUBST__` rather than being torn in half.
#
# That second half matters. `tr ';|&()\`' '\n'`, and a first attempt that merely
# respected quoting, both split `gh --repo $(gh repo view -q .n) pr merge 42`
# into a fragment with no `pr merge` and a fragment with no `gh` — so a hook
# looking for a merge found none and allowed it. A separator inside a quoted
# argument did the same to the selector: `gh pr merge -b "a; b" 42` lost the 42,
# and a probe that wants to know WHICH pull request asked about another one.
#
# BD_UNBALANCED is 1 when the text ends inside a quote or an unclosed
# substitution. A caller that cannot afford to guess should treat that as
# "unparsable" rather than as "nothing found".
_bd_segments() {
  BD_UNBALANCED=0
  local out
  out=$(printf '%s\n' "$1" | awk '
    # depth must start as the NUMBER 0. Left uninitialised it is the empty
    # string, so buf[depth] is buf[""] at the outer level and buf["0"] once a
    # substitution has closed — different slots, and everything written before
    # the substitution is silently dropped.
    BEGIN { SQ = sprintf("%c", 39); depth = 0; unbal = 0 }
    function flush(   i) {
      if (buf[depth] != "") { print buf[depth]; buf[depth] = "" }
    }
    {
      line = $0
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)

        # A backslash escapes the next character everywhere but inside single
        # quotes.
        if (c == "\\" && q[depth] != SQ) {
          buf[depth] = buf[depth] c
          i++
          if (i <= n) buf[depth] = buf[depth] substr(line, i, 1)
          continue
        }

        if (q[depth] != "") {
          # `$(` re-opens code inside a double-quoted string.
          if (q[depth] == "\"" && c == "$" && substr(line, i + 1, 1) == "(") {
            depth++; buf[depth] = ""; q[depth] = ""
            i++
            continue
          }
          buf[depth] = buf[depth] c
          if (c == q[depth]) q[depth] = ""
          continue
        }

        if (c == "\"" || c == SQ) { q[depth] = c; buf[depth] = buf[depth] c; continue }

        if (c == "$" && substr(line, i + 1, 1) == "(") {
          depth++; buf[depth] = ""; q[depth] = ""
          i++
          continue
        }
        if (c == "`") {
          if (depth > 0 && tick[depth]) { flush(); depth--; buf[depth] = buf[depth] " __BD_SUBST__ " ; continue }
          depth++; buf[depth] = ""; q[depth] = ""; tick[depth] = 1
          continue
        }
        if (c == ")") {
          if (depth > 0) {
            flush(); depth--
            # The substitution stood where a word stood, so a word goes back.
            buf[depth] = buf[depth] " __BD_SUBST__ "
            continue
          }
          flush()
          continue
        }
        if (c == "(" ) { flush(); continue }
        if (c == ";" || c == "|" || c == "&") { flush(); continue }

        buf[depth] = buf[depth] c
      }
      flush()
    }
    END {
      while (depth > 0) { if (buf[depth] != "") print buf[depth]; depth-- ; unbal = 1 }
      if (buf[0] != "") print buf[0]
      if (unbal || q[0] != "") print "__BD_UNBALANCED__"
    }
  ')
  case "$out" in
    *__BD_UNBALANCED__*)
      BD_UNBALANCED=1
      out=$(printf '%s\n' "$out" | grep -v '^__BD_UNBALANCED__$')
      ;;
  esac
  printf '%s\n' "$out"
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

