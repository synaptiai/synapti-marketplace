#!/usr/bin/env bash
# plugins/flow/hooks/scripts/lib/command-parse.sh
# shellcheck disable=SC2034  # BD_CODE, BD_KEPT_BODY, BD_UNBALANCED, GIT_* are outputs read by the sourcing hook
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
#   _bd_strip_noncode <command>   -> sets BD_CODE, and BD_KEPT_BODY=1 when a heredoc
#                                    body was kept as text
#   _rm_tokenise <simple-command> -> fills TOK (quotes removed, backslashes and
#                                    redirections kept); s1-guard's word check
#   _bd_words <text>              -> fills TOK with the words bash hands the program
#                                    (redirections dropped), TOKE with an expansion
#                                    flag per word, TOKQ with 1 for a word that is one
#                                    whole quoted string, BD_HSTR with here-string texts,
#                                    BD_RDIR with redirection targets, and sets
#                                    BD_RIN=1 when the program's input is redirected
#   _bd_git_parse <simple-command> -> sets GIT_SUB, GIT_ARGS, GIT_ARGN; 1 if not git
#   _bd_is_whole_tree <pathspec>  -> 0 when the pathspec is the whole tree
#   _bd_is_opt <token> <full> <min> -> 0 when the token is that long option,
#                                    including any unambiguous abbreviation
#   _bd_is_interpreter <word>     -> 0 when the word names something that runs a script
#   _bd_shell_reads_stdin <index> -> 0 when TOK[index] is a shell that reads its
#                                    script from its input (no -c, no script file)
#   _bd_expand_interpreter_args   -> appends quoted interpreter arguments, and text
#                                    piped into a shell, to BD_CODE
#   _bd_segments <text>           -> one simple command per line, plus marker lines
#                                    (__BD_UNBALANCED__, __BD_SEG_FAIL__)
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

  # The awk output is captured before it is read, not read through `< <(...)`.
  # A process substitution loses awk's exit status, so an awk that died left
  # TOK empty, and an empty TOK reads as a command with nothing in it: under
  # bash 3.2 a few hundred of these calls in one hook run crashed that hook,
  # and the commands after the crash were never checked. Every caller runs in
  # the hook's own shell, so the exit below refuses the command.
  local _tok_line _tok_out
  if ! _tok_out=$(printf '%s\n' "$1" | awk '
    # Does the quote at i open a dollar-quoted string? Only when the character
    # before it is a dollar sign that no backslash escapes.
    function dq_open(s, i,   j, b) {
      if (i < 2 || substr(s, i - 1, 1) != "$") return 0
      b = 0
      for (j = i - 2; j >= 1 && substr(s, j, 1) == "\\"; j--) b++
      return (b % 2) == 0
    }
    BEGIN { SQ = sprintf("%c", 39); DQ = "$" SQ }
    {
      s = $0; n = length(s); q = ""; cur = ""; in_word = 0; pos = 1
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          # In a dollar-quoted string (q is DQ) a backslash escapes the quote.
          if (q == DQ && c == "\\") { i++; continue }
          if (c == q || (q == DQ && c == SQ)) { cur = cur substr(s, pos, i - pos); pos = i + 1; q = "" }
          continue
        }
        if (c == SQ && dq_open(s, i)) {
          cur = cur substr(s, pos, i - pos); pos = i + 1; q = DQ; in_word = 1
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
  '); then
    echo "BLOCKED: could not split a command into words (awk failed) — refusing rather than guessing." >&2
    exit 2
  fi
  [ -n "$_tok_out" ] || return 0
  while IFS= read -r _tok_line; do
    TOK+=("${_tok_line#T}")
  done <<< "$_tok_out"
}

# _bd_words <text>
# Fills the caller's TOK with the words bash would hand the program, TOKE with
# one flag per word (1 when bash would expand something in it: a `$` outside
# single quotes, a backquote, a substitution), BD_HSTR with the text of every
# here-string (`<<<word`), as the program reads it on its input, and BD_RDIR
# with the target of every other redirection (`>> .git/config` gives
# .git/config, `<<EOF` gives EOF). BD_RIN is 1 when the program's input comes
# from one of them (<, <<, <<-, <<<, <>, <&) rather than from a pipe.
#
# Read as bash reads them, not approximated:
#   - quotes are removed; inside single quotes every character is literal;
#     inside double quotes a backslash is removed only before $, `, ", \ and
#     a line end; outside quotes a backslash is removed and the next character
#     kept (`gh\ pr` is one word, `mer\ge` is merge, `\>x` is the word >x)
#   - an unquoted < or > starts a redirection wherever it stands, also inside
#     a word (`--tags>/dev/null` is the word --tags and a redirection); digits
#     or {name} that make up the whole word before it are its file descriptor
#     (`2>&1`), any other text before it is a word of its own (`x2>y` is x2).
#     The operator (<, >, >>, >|, <>, <&, >&, <<, <<-, <<<, &>, &>>) and the
#     word after it are not arguments: they are dropped, and a here-string's
#     word goes to BD_HSTR. A quoted < or > is text.
#   - `$'...'` keeps its `$` and its text as written, so the word still reads
#     as something only a shell can work out.
#   - `$"..."` is a double-quoted string: bash drops the `$` (it only asks for
#     a translation, and there is none), so `gh pr $"merge" 7` is gh pr merge 7.
#   - an unquoted ;, |, &, (, ) or backquote ends a word, so a whole line can
#     be read too (`x=$(bash` is the words `x=$` and `bash`).
#   - a parameter expansion `${...}` is one piece of its word up to its
#     closing brace, spaces and all, as bash reads it (`${CMD//_/ }`). With
#     BD_SPLIT_EXP=1, an unquoted one that holds whitespace is read character
#     by character instead, so its pieces are words of their own, as bash's
#     word splitting makes the expansion (`rm ${X:- -rf} src` is rm -rf src);
#     inside double quotes it stays one word.
# Text with none of the characters that need this is split by the shell
# builtin, with no subprocess. An awk that fails refuses the command (exit 2),
# as _rm_tokenise does.
_bd_words() {
  TOK=(); TOKE=(); TOKQ=(); BD_HSTR=(); BD_RDIR=(); BD_RIN=0
  local _w_out _w_line _w_i
  case "$1" in
    *[\'\"\\\<\>\&\(\)\;\|\`]*|*$'\n'*|*'${'*) ;;
    *)
      read -r -a TOK <<< "$1"
      for ((_w_i = 0; _w_i < ${#TOK[@]}; _w_i++)); do
        case "${TOK[_w_i]}" in *'$'*|*__BD_SUBST__*) TOKE[_w_i]=1 ;; *) TOKE[_w_i]=0 ;; esac
        TOKQ[_w_i]=0
      done
      return 0 ;;
  esac
  if ! _w_out=$(printf '%s' "$1" | LC_ALL=C awk -v splitexp="${BD_SPLIT_EXP:-0}" '
    # qs=1 while the word is one quoted string and nothing else: `"$CMD"`,
    # not `""$CMD` or `"$A"$B`, and not one that expands to several words
    # however it is quoted (`"$@"`, `"${@:2}"`, `"${A[@]}"`, `"${!A[@]}"`).
    function emit() {
      if (!inw) return
      if (qs && (index(cur, "$@") || cur ~ /[$][{][^}]*@/)) qs = 0
      gsub(/\n/, RSN, cur)
      if (pend == "H" || pend == "I" || pend == "R") print pend cur
      else if (pend == "") print "W" ((xp || inexp || index(cur, "__BD_SUBST__")) ? 1 : 0) (qs ? 1 : 0) cur
      cur = ""; inw = 0; plain = 1; xp = 0; pend = ""; qs = 0
    }
    # Does the quote at i open a dollar-quoted string? Only when the character
    # before it is a dollar sign that no backslash escapes.
    function dq_open(s, i,   j, b) {
      if (i < 2 || substr(s, i - 1, 1) != "$") return 0
      b = 0
      for (j = i - 2; j >= 1 && substr(s, j, 1) == "\\"; j--) b++
      return (b % 2) == 0
    }
    BEGIN { SQ = sprintf("%c", 39); RSN = sprintf("%c", 30); s = "" }
    { s = (NR > 1) ? s "\n" $0 : $0 }
    END {
      n = length(s); cur = ""; inw = 0; plain = 1; xp = 0; pend = ""; qs = 0; inexp = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        # The closing brace of a ${...} read in pieces (splitexp=1, below)
        # ends the expansion and is no part of the last piece.
        if (c == "}" && (i in cb)) { delete cb[i]; inexp = 0; continue }
        if (c == " " || c == "\t" || c == "\r" || c == "\n") { emit(); continue }
        if (c == "\\") {
          qs = 0
          if (i == n) { cur = cur c; inw = 1; plain = 0; continue }
          d = substr(s, i + 1, 1); i++
          if (d != "\n") { cur = cur d; inw = 1; plain = 0 }
          continue
        }
        if (c == SQ) {
          qs = inw ? 0 : 1
          inw = 1; plain = 0
          if (dq_open(s, i)) {
            # $'...': kept as written, the $ included; a backslash escapes
            # the quote.
            xp = 1
            for (k = i + 1; k <= n; k++) {
              d = substr(s, k, 1)
              if (d == "\\" && k < n) { cur = cur d substr(s, k + 1, 1); k++; continue }
              if (d == SQ) break
              cur = cur d
            }
            i = k; continue
          }
          k = index(substr(s, i + 1), SQ)
          if (k == 0) { cur = cur substr(s, i + 1); i = n; continue }
          cur = cur substr(s, i + 1, k - 1); i += k; continue
        }
        # $"...": the $ goes, and the string is read as a double-quoted one.
        if (c == "$" && substr(s, i + 1, 1) == "\"") { inw = 1; plain = 0; qs = 0; continue }
        if (c == "\"") {
          qs = inw ? 0 : 1
          inw = 1; plain = 0
          for (k = i + 1; k <= n; k++) {
            d = substr(s, k, 1)
            if (d == "\\" && k < n) {
              e = substr(s, k + 1, 1)
              if (e == "$" || e == "`" || e == "\"" || e == "\\") { cur = cur e; k++; continue }
              if (e == "\n") { k++; continue }
              cur = cur d; continue
            }
            if (d == "\"") break
            if (d == "`") xp = 1
            if (d == "$" && substr(s, k + 1, 1) ~ /[A-Za-z_{(0-9@*#?$!-]/) xp = 1
            cur = cur d
          }
          i = k; continue
        }
        if (c == "<" || c == ">" || (c == "&" && substr(s, i + 1, 1) == ">")) {
          if (inw && plain && pend == "" && (cur ~ /^[0-9]+$/ || cur ~ /^\{[A-Za-z_][A-Za-z0-9_]*\}$/) && c != "&") { cur = ""; inw = 0; xp = 0; qs = 0 }
          else emit()
          t = substr(s, i, 3)
          if (t == "<<<") { op = "H"; l = 3 }
          else if (t == "<<-" || t == "&>>") { op = (c == "<") ? "I" : "R"; l = 3 }
          else {
            t = substr(s, i, 2)
            op = (c == "<") ? "I" : "R"
            l = (t == "<<" || t == "<>" || t == "<&" || t == ">>" || t == ">|" || t == ">&" || t == "&>") ? 2 : 1
          }
          i += l - 1; pend = op; continue
        }
        if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "`") { emit(); pend = ""; continue }
        # ${...}: to its closing brace, nested ${...} counted; one with no
        # closing brace is read character by character. With splitexp=1 one
        # that holds whitespace is read in pieces, the words bash may split
        # it into: `${NAME:-` (or :+ := :? - + = ?) as a word of its own,
        # then the words of the rest up to the closing brace, which is
        # dropped (`${X:- -rf}` is `${X:-` and `-rf`). Each piece is flagged
        # as an expansion (inexp).
        if (c == "$" && substr(s, i + 1, 1) == "{") {
          d = 1
          for (k = i + 2; k <= n && d > 0; k++) {
            e = substr(s, k, 1)
            if (e == "$" && substr(s, k + 1, 1) == "{") { d++; k++ }
            else if (e == "}") d--
          }
          if (d == 0 && splitexp == 1 && substr(s, i, k - i) ~ /[ \t\r\n]/) {
            cb[k - 1] = 1; inexp = 1; xp = 1
            if (match(substr(s, i, k - i), /^[$][{][!#]?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?:?[-+=?]/)) {
              cur = cur substr(s, i, RLENGTH); inw = 1; qs = 0; emit(); i = i + RLENGTH - 1; continue
            }
          }
          else if (d == 0) { cur = cur substr(s, i, k - i); inw = 1; qs = 0; xp = 1; i = k - 1; continue }
        }
        if (c == "$" && substr(s, i + 1, 1) ~ /[A-Za-z_{(0-9@*#?$!-]/) xp = 1
        cur = cur c; inw = 1; qs = 0
      }
      emit()
    }
  '); then
    echo "BLOCKED: could not split a command into words (awk failed) — refusing rather than guessing." >&2
    exit 2
  fi
  [ -n "$_w_out" ] || return 0
  while IFS= read -r _w_line; do
    case "$_w_line" in *$'\036'*) _w_line="${_w_line//$'\036'/$'\n'}" ;; esac
    case "$_w_line" in
      W*) TOKE+=("${_w_line:1:1}"); TOKQ+=("${_w_line:2:1}"); TOK+=("${_w_line:3}") ;;
      H*) BD_HSTR+=("${_w_line:1}"); BD_RIN=1 ;;
      I*) BD_RDIR+=("${_w_line:1}"); BD_RIN=1 ;;
      R*) BD_RDIR+=("${_w_line:1}") ;;
    esac
  done <<< "$_w_out"
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
# Quoting, word splitting and redirections are left to _bd_words above.
# ---------------------------------------------------------------------------
# Does this word name something that will run a script handed to it? Used for
# the quoted-argument expansion below, not for heredoc stripping — the heredoc
# rule asks the opposite question (is the owner a text sink?) and answers it
# with a much shorter list, because there "keep" is the safe default and here
# "examine" is.
_bd_is_interpreter() {
  _bd_is_shell "$1" && return 0
  case "${1##*/}" in
    python|python2|python3|perl|ruby|node|deno|bun)
      return 0 ;;
    eval|source|.|ssh|su|doas|sudo|env|nohup|timeout|xargs|docker|kubectl|make|at)
      return 0 ;;
  esac
  return 1
}

# The shells, the one list every reader of a command uses: _bd_is_shell,
# _bd_shell_reads_stdin, _bd_is_interpreter, and the piped-into-a-shell pass
# of _bd_expand_interpreter_args (_BD_SHELL_RE).
_BD_SHELLS="sh bash zsh ksh dash ash mksh busybox"
_BD_SHELL_RE="(^|[^A-Za-z0-9_.-])(${_BD_SHELLS// /|})([^A-Za-z0-9_.-]|\$)"

# _bd_is_shell <word>
# Is the word a shell, in any case (a case-insensitive filesystem runs
# `BASH`) and with any directory?
_bd_is_shell() {
  local b="${1##*/}" r=1 nc=0
  case "$b" in ''|*[[:space:]]*) return 1 ;; esac
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case " $_BD_SHELLS " in *" $b "*) r=0 ;; esac
  [ "$nc" = 1 ] || shopt -u nocasematch
  return "$r"
}

# _bd_shell_reads_stdin <index>
# Is TOK[index] a shell (_bd_is_shell) that reads its script from its input? It does when it
# is given neither -c nor a script file: `bash`, `bash -s arg`, `sh -x`,
# `bash --`, `sh -`. Its options are read as the shell reads them: c or s
# anywhere in a bundle of short options (`-xc`, `-es`), -o and -O (and +o,
# +O) taking the next word, --rcfile and --init-file taking the next word,
# and any other long option taking none. The first other word is the script.
_bd_shell_reads_stdin() {
  local i="$1" n=${#TOK[@]} t
  [ "$i" -lt "$n" ] || return 1
  [ "${#TOK[i]}" -le 4096 ] || return 1
  _bd_is_shell "${TOK[i]}" || return 1
  i=$((i + 1))
  while [ "$i" -lt "$n" ]; do
    t="${TOK[i]}"
    case "$t" in
      --|-) return 0 ;;
      --rcfile|--init-file) i=$((i + 2)); continue ;;
      --*) i=$((i + 1)); continue ;;
      [-+]*c*) return 1 ;;
      [-+]*s*) return 0 ;;
      [-+]*[oO]*) i=$((i + 2)); continue ;;
      [-+]?*) i=$((i + 1)); continue ;;
    esac
    return 1
  done
  return 0
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
# `<<<` is a here-string, not a heredoc: a match that starts at its second `<`
# (`<<<EOF` read as `<<EOF`) is skipped, so the lines after it stay commands
# rather than becoming a body. `$(( a << b ))`, bare
# `(( a << b ))` and `let x=1<<3` do not match either — a shift operand is not
# a sink and the line does not end with the introducer.
#
# Carriage returns are stripped first, so a CRLF command is read the same way a
# LF one is. Both tokeniser paths then agree about where words end.
_bd_strip_noncode() {
  BD_CODE=$(printf '%s\n' "$1" | awk -v blank="${BD_BLANK_BODIES:-0}" -v shells="$_BD_SHELLS" '
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
    # Does the quote at i open a dollar-quoted string? Only when the character
    # before it is a dollar sign that no backslash escapes.
    function dq_open(s, i,   j, b) {
      if (i < 2 || substr(s, i - 1, 1) != "$") return 0
      b = 0
      for (j = i - 2; j >= 1 && substr(s, j, 1) == "\\"; j--) b++
      return (b % 2) == 0
    }
    # blank=1 only (BD_BLANK_BODIES): may a heredoc introduced on this line,
    # whatever its owner, be read as data? Not when a word of the line before
    # the introducer is a shell (_BD_SHELLS) or a program that runs its input
    # or its arguments, and not when a command word is a variable or a
    # substitution, which may be either.
    function reader_ok(str,   n, cmds, i, m, w, j, c, x) {
      n = split(str, cmds, /[;&|(){}`]|[$][(]/)
      for (i = 1; i <= n; i++) {
        m = split(cmds[i], w, /[ \t]+/)
        c = 1
        for (j = 1; j <= m; j++) {
          if (w[j] == "") continue
          x = w[j]
          gsub("[\"" SQ "\\\\]", "", x)
          if (c) {
            if (x ~ /^(if|then|elif|else|while|until|do|!|time)$/ || x ~ /^[A-Za-z_][A-Za-z0-9_]*[+]?=/) continue
            if (x == "" || x ~ /^[$]/) return 0
            c = 0
          }
          sub(/^.*\//, "", x)
          x = tolower(x)
          if (x ~ shre) return 0
          if (x ~ /^(python[23]?|perl|ruby|node|deno|bun|eval|source|[.]|exec|ssh|su|doas|sudo|env|nohup|timeout|xargs|docker|kubectl|make|at|script|watch|command|builtin|nice|setsid|stdbuf|caffeinate|parallel|tmux|screen)$/) return 0
        }
      }
      return 1
    }
    BEGIN { SQ = sprintf("%c", 39); DQ = "$" SQ; inhd = 0; buf = ""; delim = ""; tabs = 0; pend = ""; q = ""; q0 = ""
            shre = shells; gsub(/ +/, "|", shre); shre = "^(" shre ")$" }
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

      # A continued line is scanned again with the line it continues, from the
      # quote state that line started in, so nothing is counted twice.
      if (pend == "") q0 = q
      line = pend line
      pend = ""
      q = q0

      # --- remove a comment, tracking quotes and backslash escapes ---------
      # Two quote states. `q` carries from one line to the next, as the shell
      # does: `--body "Ready.` then `Closes #12" && gh pr merge 9` has its `#`
      # inside the string. `ql` starts fresh on every line, as this scan always
      # did: a heredoc body kept as text is not quoted text, and one apostrophe
      # in it (the word dont, spelled with an apostrophe) would otherwise leave `q` open and turn the `#` in a
      # later `-m "Refs #12" written with single quotes` into a comment that cuts the command after it.
      # A `#` is a comment only when both say it is outside quotes. Either
      # alone can only be wrong in the direction of keeping text.
      n = length(line); cut = 0; ql = ""; eq = 0; el = 0
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        bq = eq; bl = el; oq = (q == ""); ol = (ql == "")
        # q or ql is DQ inside a dollar-quoted string, where a backslash
        # escapes the quote that would otherwise close it.
        dq = (c == SQ && dq_open(line, i))
        if (eq) eq = 0
        else if (c == "\\" && q != SQ) eq = 1
        else if (q != "") { if (c == q || (q == DQ && c == SQ)) q = "" }
        else if (dq) q = DQ
        else if (c == "\"" || c == SQ) q = c
        if (el) el = 0
        else if (c == "\\" && ql != SQ) el = 1
        else if (ql != "") { if (c == ql || (ql == DQ && c == SQ)) ql = "" }
        else if (dq) ql = DQ
        else if (c == "\"" || c == SQ) ql = c
        if (c == "#" && oq && ol && !bq && !bl) {
          prev = (i == 1) ? "" : substr(line, i - 1, 1)
          if (prev == "" || prev == " " || prev == "\t" || prev == ";" ||
              prev == "|" || prev == "&" || prev == "(" || prev == ")") { cut = i; break }
        }
      }
      out = (cut > 0) ? substr(line, 1, cut - 1) : line

      # A line ending in an odd number of backslashes, outside single quotes,
      # continues on the next line; reading the two as two put `gh pr \` and
      # `merge 9` in different commands. Decided after the comment: a comment
      # ending in a backslash does not continue, in bash or in sh, and joining
      # it swallowed the next line whole.
      if (cut == 0 && q != SQ && match(out, /\\+$/) && (RLENGTH % 2) == 1) {
        pend = substr(out, 1, length(out) - 1)
        next
      }

      # --- is this line a droppable heredoc introducer? --------------------
      # Only on a line that starts outside quotes by both readings: a `<<EOF`
      # inside a string that runs across lines is text, and treating it as an
      # introducer would drop the lines after it as a body.
      probe = out
      hits = gsub(/<</, "<<", probe)
      if (q0 != "") hits = 0
      # With blank=1 (BD_BLANK_BODIES) a heredoc whose owner is not a sink is
      # dropped too, when the line ends outside quotes and reader_ok says
      # nothing on it runs the body: the reading of a command without the
      # data its loops and readers take in.
      if (hits == 1 && (out !~ /[|>]/ || blank == 1) &&
          match(out, /<<-?["]?[A-Za-z_][A-Za-z0-9_]*["]?[ \t]*$/) &&
          (RSTART == 1 || substr(out, RSTART - 1, 1) != "<")) {
        intro = substr(out, RSTART)
        owner = owner_word(substr(out, 1, RSTART - 1))
        if ((out !~ /[|>]/ && is_sink(owner)) || (blank == 1 && q == "" && reader_ok(substr(out, 1, RSTART - 1)))) {
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
      if (!inhd && hits == 1 && (out !~ /[|>]/ || blank == 1) &&
          match(out, "<<-?" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ "[ \t]*$") &&
          (RSTART == 1 || substr(out, RSTART - 1, 1) != "<")) {
        intro = substr(out, RSTART)
        owner = owner_word(substr(out, 1, RSTART - 1))
        if ((out !~ /[|>]/ && is_sink(owner)) || (blank == 1 && q == "" && reader_ok(substr(out, 1, RSTART - 1)))) {
          d = intro
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub(SQ, "", d)
          gsub(/[ \t]+$/, "", d)
          if (d != "") { inhd = 1; delim = d; buf = "" }
        }
      }
      # A heredoc this pass did not drop keeps its body in the output, and that
      # body is text, not shell: its quotes do not pair with anything. Say so,
      # so the segmenter does not read one apostrophe in it as a quote that
      # hides the commands after it. Anything shaped like an introducer counts,
      # including a shift such as 1<<x; that costs only a second reading.
      if (!inhd && (out ~ /(^|[^<])<<-?[ \t]*[\\"]?[A-Za-z_]/ ||
                    out ~ ("(^|[^<])<<-?[ \t]*" SQ "[A-Za-z_]"))) kept = 1
      print out
    }
    END {
      # A continuation with nothing after it is still a command.
      if (pend != "") print pend
      # An unterminated heredoc keeps everything it swallowed. Dropping it would
      # turn one mis-recognised introducer into a hook that sees nothing at all.
      if (inhd && buf != "") { printf "%s", buf; kept = 1 }
      if (kept) print "__BD_KEPT_BODY__"
    }
  ') || {
    echo "BLOCKED: could not scan the command (awk failed) — refusing rather than guessing." >&2
    exit 2
  }
  BD_KEPT_BODY=0
  case "$BD_CODE" in
    __BD_KEPT_BODY__) BD_KEPT_BODY=1; BD_CODE="" ;;
    *$'\n'__BD_KEPT_BODY__) BD_KEPT_BODY=1; BD_CODE="${BD_CODE%$'\n'__BD_KEPT_BODY__}" ;;
  esac
}

# _bd_segments <text>
# Prints one simple command per line.
#
# Splits on `;` `|` `&` where the shell would — outside quotes, and not at the
# `&` of a redirection (`2>&1`, `<&3`, `&>file`) or the `|` of `>|` — and
# treats a command
# substitution (`$(...)`, or backquotes, also inside double quotes) as BOTH
# things it is: a command in its own right, emitted
# as its own segment, and a word in the command containing it, which therefore
# survives as `__BD_SUBST__` rather than being torn in half. The marker takes
# the substitution's place exactly, with no space added around it: `x$(y)z`
# is the one word `x__BD_SUBST__z`, and `D=$(gh repo view)` the one
# assignment `D=__BD_SUBST__`.
#
# That second half matters. `tr ';|&()\`' '\n'`, and a first attempt that merely
# respected quoting, both split `gh --repo $(gh repo view -q .n) pr merge 42`
# into a fragment with no `pr merge` and a fragment with no `gh` — so a hook
# looking for a merge found none and allowed it. A separator inside a quoted
# argument did the same to the selector: `gh pr merge -b "a; b" 42` lost the 42,
# and a probe that wants to know WHICH pull request asked about another one.
#
# A substitution's output can be empty, so a word glued to one may be just
# the text around it: `git reset --hard$(true)` is git reset --hard, and
# `gh pr merge$(x) 7` may be gh pr merge 7. With BD_SEG_ALT=1 a segment in
# which a marker is glued to other text is followed by a second reading of
# it, the same text with those markers removed; a marker that is a whole
# word, or the whole of a double-quoted word, stays, and a segment with only
# such markers has no second reading. The first reading still has every
# marker, for a rule that must treat the word as unreadable (`git push
# origin v1$(x)`), and the second lets a rule match the words as they may
# run. With BD_SEG_MARK=1 that second reading starts with `__BD_ALT__`, for
# a caller that must tell it from a command written that way.
#
# Two marker lines can appear among the segments: `__BD_UNBALANCED__` when the
# text ends inside a quote or an unclosed substitution, and `__BD_SEG_FAIL__`
# when the parse itself failed. BD_UNBALANCED is also set, for a caller that
# runs this in its own shell rather than behind `< <(...)`.
_bd_segments() {
  BD_UNBALANCED=0
  local joined perline
  # How line ends are read.
  #
  # A newline inside a quoted string is part of the string, so the shell reads
  # `gh pr merge --body "Summary` and `Details" 9` as one command. When the text
  # balances, that joined reading is the only one printed: the lines of a
  # multi-line commit message are text, and reading them as commands refused
  # messages that merely mention one.
  #
  # Two things make the joined reading untrustworthy, and both come from the
  # same cause: text that is not shell being scanned as if it were.
  #
  #   - The text does not balance.
  #   - _bd_strip_noncode kept a heredoc body (BD_KEPT_BODY=1). A body is text,
  #     so its quotes pair with nothing, yet this scan pairs them: one apostrophe
  #     in a body glues every later command into a "string", and a second body,
  #     or a comment with an apostrophe in it, closes that string again. The
  #     text then balances with the commands between hidden inside it, which is
  #     how a merge or an rm between two commit bodies went unseen. Balance
  #     alone cannot detect this; only knowing a body was kept can.
  #
  # In either case the per-line reading, which forgets quotes at each line end,
  # is printed too. When the text does not balance, a `__BD_UNBALANCED__` line
  # follows: a caller that cannot afford to guess treats that as "unparsable"
  # rather than as "nothing found".
  #
  # A failed awk prints `__BD_SEG_FAIL__`. The caller reads this through
  # `$(...)`, and an empty result would read as "no commands", so the marker is
  # how a failure reaches it.
  joined=$(printf '%s\n' "$1" | awk -v join=1 -v alt="${BD_SEG_ALT:-0}" -v mark="${BD_SEG_MARK:-0}" "$_BD_SEG_AWK") || { printf '%s\n' "__BD_SEG_FAIL__"; return 0; }
  case "$joined" in
    *__BD_UNBALANCED__*) BD_UNBALANCED=1 ;;
  esac
  if [ "$BD_UNBALANCED" = "1" ] || [ "${BD_KEPT_BODY:-0}" = "1" ]; then
    perline=$(printf '%s\n' "$1" | awk -v join=0 -v alt="${BD_SEG_ALT:-0}" -v mark="${BD_SEG_MARK:-0}" "$_BD_SEG_AWK") || { printf '%s\n' "__BD_SEG_FAIL__"; return 0; }
    { printf '%s\n' "$joined"; printf '%s\n' "$perline"; } | grep -v '^__BD_UNBALANCED__$' | awk '!seen[$0]++' \
      || { printf '%s\n' "__BD_SEG_FAIL__"; return 0; }
    [ "$BD_UNBALANCED" = "1" ] && printf '%s\n' "__BD_UNBALANCED__"
  else
    printf '%s\n' "$joined"
  fi
  return 0
}

_BD_SEG_AWK='
    # depth must start as the NUMBER 0. Left uninitialised it is the empty
    # string, so buf[depth] is buf[""] at the outer level and buf["0"] once a
    # substitution has closed — different slots, and everything written before
    # the substitution is silently dropped.
    # Does the quote at i open a dollar-quoted string? Only when the character
    # before it is a dollar sign that no backslash escapes.
    function dq_open(s, i,   j, b) {
      if (i < 2 || substr(s, i - 1, 1) != "$") return 0
      b = 0
      for (j = i - 2; j >= 1 && substr(s, j, 1) == "\\"; j--) b++
      return (b % 2) == 0
    }
    BEGIN { SQ = sprintf("%c", 39); DQ = "$" SQ; depth = 0; unbal = 0 }
    # One simple command, and with alt=1, when a substitution marker in it is
    # glued to other text, its reading with those markers removed (see
    # _bd_segments). A marker that is a whole word, or the whole of a
    # double-quoted word, hides nothing and stays: `git checkout "$(x)"` has
    # no second reading.
    # With mark=1 a simple command a pipe feeds (after `|` or `|&`, not `||`)
    # starts with `__BD_PIPE__`, and so does its second reading.
    function emit(s,   t, u, pre, post, a, b, keep, cut, p) {
      p = (mark == 1 && pipe[depth]) ? "__BD_PIPE__" : ""
      pipe[depth] = 0
      print p s
      if (alt != 1 || !index(s, "__BD_SUBST__")) return
      t = s; u = ""; cut = 0
      while (match(t, /__BD_SUBST__/)) {
        pre = substr(t, 1, RSTART - 1); post = substr(t, RSTART + RLENGTH)
        a = (length(pre) > 0) ? substr(pre, length(pre), 1) : ""
        b = substr(post, 1, 1)
        if (a == "\"" && b == "\"") {
          a = (length(pre) > 1) ? substr(pre, length(pre) - 1, 1) : ""
          b = substr(post, 2, 1)
        }
        keep = (a == "" || a == " " || a == "\t") && (b == "" || b == " " || b == "\t" || b == "<" || b == ">")
        if (!keep) cut = 1
        u = u pre (keep ? "__BD_SUBST__" : "")
        t = post
      }
      u = u t
      if (cut && u ~ /[^ \t]/) print ((mark == 1) ? "__BD_ALT__" : "") p u
    }
    function flush(   i) {
      if (buf[depth] != "") { emit(buf[depth]); buf[depth] = "" }
    }
    {
      line = $0
      n = length(line)
      # The per-line reading forgets quotes at each line end.
      if (!join) q[depth] = ""
      ra = 0
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        # pra: the character before this one was an unquoted, unescaped < or
        # >, so an & here is part of a redirection (2>&1, <&3, >&-).
        pra = ra; ra = 0

        # A backslash escapes the next character everywhere but inside single
        # quotes.
        if (c == "\\" && q[depth] != SQ) {
          buf[depth] = buf[depth] c
          i++
          if (i <= n) buf[depth] = buf[depth] substr(line, i, 1)
          continue
        }

        if (q[depth] != "") {
          # `$(` re-opens code inside a double-quoted string, and so does a
          # backquote: `x="`gh pr merge 1`"` runs the merge.
          if (q[depth] == "\"" && c == "$" && substr(line, i + 1, 1) == "(") {
            depth++; buf[depth] = ""; q[depth] = ""; tick[depth] = 0; pipe[depth] = 0
            i++
            continue
          }
          if (q[depth] == "\"" && c == "`") {
            depth++; buf[depth] = ""; q[depth] = ""; tick[depth] = 1; pipe[depth] = 0
            continue
          }
          buf[depth] = buf[depth] c
          if (c == q[depth] || (q[depth] == DQ && c == SQ)) q[depth] = ""
          continue
        }

        # A dollar-quoted string is recorded as A: inside it a backslash
        # escapes the quote (the escape rule above already applies, since A is
        # not a single quote), and only a quote closes it.
        if (c == SQ && dq_open(line, i)) { q[depth] = DQ; buf[depth] = buf[depth] c; continue }
        if (c == "\"" || c == SQ) { q[depth] = c; buf[depth] = buf[depth] c; continue }

        if (c == "$" && substr(line, i + 1, 1) == "(") {
          depth++; buf[depth] = ""; q[depth] = ""; tick[depth] = 0; pipe[depth] = 0
          i++
          continue
        }
        if (c == "`") {
          if (depth > 0 && tick[depth]) { flush(); depth--; buf[depth] = buf[depth] "__BD_SUBST__"; continue }
          depth++; buf[depth] = ""; q[depth] = ""; tick[depth] = 1; pipe[depth] = 0
          continue
        }
        if (c == ")") {
          if (depth > 0) {
            flush(); depth--
            # The substitution stood where a word stood, or a part of one, so
            # a word goes back in its place, glued to the text around it as
            # the substitution was: `D=$(gh pr view 1)` stays one assignment
            # word, `D=__BD_SUBST__`, not an assignment and a command word.
            buf[depth] = buf[depth] "__BD_SUBST__"
            continue
          }
          flush()
          continue
        }
        # `>(` and `<(`: a process substitution, whose commands read or
        # write through a pipe, so the first one in it is marked as one a
        # pipe feeds.
        if (c == "(" ) { flush(); if (pra) pipe[depth] = 1; continue }
        # An & right after an unquoted < or > (2>&1, <&3, >&-) or right before
        # a > (&>, &>>) is part of a redirection, not the end of a command:
        # splitting `git push 2>&1 --tags` there made `1 --tags` a command of
        # its own and hid the --tags from the push.
        if (c == "&" && (pra || substr(line, i + 1, 1) == ">")) { buf[depth] = buf[depth] c; continue }
        # A | right after an unquoted > is the clobber redirection >|, not a
        # pipe: splitting `gh pr >| log merge 7` there hid the merge.
        if (c == "|" && pra && substr(line, i - 1, 1) == ">") { buf[depth] = buf[depth] c; continue }
        # `||` and `|&`: one operator each. A pipe (`|`, `|&`) feeds the next
        # simple command; `;`, `&`, `&&` and `||` do not.
        if (c == "|") {
          flush()
          d = substr(line, i + 1, 1)
          if (d == "|") { i++; pipe[depth] = 0; continue }
          if (d == "&") i++
          pipe[depth] = 1
          continue
        }
        if (c == ";" || c == "&") { flush(); pipe[depth] = 0; continue }

        buf[depth] = buf[depth] c
        ra = (c == "<" || c == ">")
      }
      if (join && q[depth] != "") buf[depth] = buf[depth] " "
      else flush()
    }
    END {
      while (depth > 0) { if (buf[depth] != "") emit(buf[depth]); depth-- ; unbal = 1 }
      if (buf[0] != "") emit(buf[0])
      if (unbal || q[0] != "") print "__BD_UNBALANCED__"
    }
'

# _bd_expand_interpreter_args
# Appends to BD_CODE the contents of every quoted argument handed to something
# that runs it, and of every here-string on a line that names one.
#
# An interpreter handed its script as a single quoted argument — `bash -c "git
# reset --hard"`, `sh -c '...'`, `ssh host "..."`, `eval "..."` — is one word to
# the tokeniser, so no rule could see the command inside it. Append the contents
# of those arguments as further lines, which the segmenting then treats as
# ordinary commands. One level deep is enough for every real form; deeper
# nesting arrives here as its own quoted argument on the next pass anyway.
# Shared because every hook that reads commands has the same blind spot: the
# merge gate let `bash -c 'gh pr merge 9'` through until it called this too.
_bd_expand_interpreter_args() {
  local seg tok base i n found h prev
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=()
  local BD_RIN=0
  local extra=""
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    # A word with a space in it comes from quotes or a backslash, and a
    # here-string from <<<; a line with none of them has nothing to add.
    case "$seg" in *[\'\"\\]*|*'<<<'*) ;; *) continue ;; esac
    # The words as bash hands them over (_bd_words): `ba\sh -c '...'` runs
    # bash, `x=$(bash -c '...')` has bash as a word of its own, and
    # `bash -c gh\ pr\ merge\ 1` hands bash one word with spaces in it.
    _bd_words "$seg"
    n=${#TOK[@]}
    found=0
    for ((i = 0; i < n; i++)); do
      tok="${TOK[i]}"
      # Only the last path component of a word can name an interpreter, and
      # a name longer than sixteen characters is none.
      if [ "${#tok}" -le 4096 ]; then
        base="${tok##*/}"
        if [ "${#base}" -le 16 ] && _bd_is_interpreter "$base"; then found=1; continue; fi
      fi
      if [ "$found" = "1" ]; then
        case "$tok" in
          *[[:space:]]*) extra="$extra
$tok" ;;
        esac
      fi
    done
    # A here-string is the input of the command it is written on, and an
    # interpreter reads its input as a script: `bash <<<'...'`, `<<<'...'
    # bash`, and, as with a heredoc body, a line that names an interpreter
    # anywhere (`cat <<<'...' | bash`). Each one is read as a command.
    if [ "$found" = "1" ] && [ "${#BD_HSTR[@]}" -gt 0 ]; then
      for h in "${BD_HSTR[@]}"; do
        extra="$extra
$h"
      done
    fi
  done <<BD_EXPAND_EOF
$BD_CODE
BD_EXPAND_EOF
  # Text printed into a pipe that a shell reads as its script (`echo '...' |
  # bash`, `printf ... | { read -r _; sudo sh -s; }`, `echo '...' >
  # >(bash)`): when a shell that reads its script from its input is anywhere
  # in a text with a pipe or a process substitution, the quoted words of
  # every simple command in it are read as commands too, as a here-string to
  # it is. Where the shell stands (a group, a subshell, a loop, after `;`)
  # does not matter; that is only a second look at text, never a missed one.
  # Started only when a shell's name is a whole word in such a text
  # (_BD_SHELL_RE, any case): this pass segments the whole text again, and a
  # long text piped into tee or grep that holds the letters sh (push,
  # should) paid for it on every call.
  local nc=0 piped=0 quoted="" fed=0
  case "$BD_CODE" in
    *'|'*|*'>('*|*'<('*)
      shopt -q nocasematch && nc=1
      shopt -s nocasematch
      [[ "$BD_CODE" =~ $_BD_SHELL_RE ]] && piped=1
      [ "$nc" = 1 ] || shopt -u nocasematch ;;
  esac
  case "$piped" in
    1)
      while IFS= read -r seg; do
        case "$seg" in ''|__BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
        case "$seg" in __BD_ALT__*) seg="${seg:10}" ;; esac; case "$seg" in __BD_PIPE__*) seg="${seg:11}" ;; esac
        _bd_words "$seg"
        n=${#TOK[@]}
        # The shell is the command word: past assignments, shell keywords
        # (`if true; then bash; fi`), and the programs that run the rest of
        # the line (and their options).
        i=0
        while [ "$i" -lt "$n" ]; do
          case "${TOK[i]}" in
            [A-Za-z_]*=*|if|then|elif|else|while|until|do|'!'|'{') i=$((i + 1)); continue ;;
          esac
          case "${TOK[i]##*/}" in
            sudo|doas|env|nohup|nice|time|command|builtin|exec|timeout|xargs)
              i=$((i + 1))
              while [ "$i" -lt "$n" ]; do case "${TOK[i]}" in -*) i=$((i + 1)) ;; *) break ;; esac; done
              continue ;;
          esac
          break
        done
        if [ "$BD_RIN" = 0 ] && _bd_shell_reads_stdin "$i"; then fed=1; fi
        for ((i = 0; i < n; i++)); do
          case "${TOK[i]}" in *[[:space:]]*) quoted="$quoted
${TOK[i]}" ;; esac
        done
      done <<BD_EXPAND_EOF
$(_bd_segments "$BD_CODE")
BD_EXPAND_EOF
      [ "$fed" = 1 ] && extra="$extra$quoted"
      ;;
  esac
  if [ -n "$extra" ]; then BD_CODE="$BD_CODE$extra"; fi
}

# ---------------------------------------------------------------------------
# git command parsing.
#
# _bd_git_parse reads one simple command and, when that command IS git, sets
# GIT_SUB to the subcommand and GIT_ARGS to everything after it, redirections
# left out. `git` is
# recognised the way `rm` is: as a command word, never as a substring, so
# `npm run git-reset-helper` and the word `digit` are not git. Global options
# taking a value (-C, -c, --git-dir, ...) are stepped over so the subcommand
# behind them is still found.
# ---------------------------------------------------------------------------
_bd_git_parse() {
  GIT_SUB=""; GIT_ARGS=(); GIT_ARGN=0
  # git, in any case (a case-insensitive filesystem runs `GIT`), or with a
  # quote or a backslash inside the name (`g"it"`, `gi\t`).
  case "$1" in
    *[Gg][Ii][Tt]*|*[Gg][\\\'\"]*|*[Gg][Ii][\\\'\"]*|*[\\\'\"][Ii][Tt]*) ;;
    *) return 1 ;;
  esac
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=()
  local BD_RIN=0
  # The words as bash hands them to git (_bd_words): a redirection is not an
  # argument even when it is glued to one (`--hard&>/dev/null` is --hard),
  # and `\git` or `g"it"` is git.
  _bd_words "$1"
  local n=${#TOK[@]} i base idx=-1
  for ((i = 0; i < n; i++)); do
    # A command word is a program name, never a 40KB argument. Skipping the
    # basename strip for oversized tokens matters because `${tok##*/}` is a
    # greedy glob: on a long token bash re-scans, and a single 40KB quoted
    # argument cost 1.3 seconds here before this check existed. 4096 is
    # PATH_MAX; nothing runnable is longer.
    [ "${#TOK[i]}" -le 4096 ] || continue
    base="${TOK[i]##*/}"
    case "$base" in [Gg][Ii][Tt]) idx=$i; break ;; esac
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
    ''|.|/|:|:/|:/.|:/\*|'*'|'**'|':(top)') return 0 ;;
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
