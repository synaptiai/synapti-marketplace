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
#                                    body was kept as text; BD_BLANK_BODIES=1
#                                    drops more bodies (below);
#                                    BD_LANG_DATA=1 reads a language interpreter's
#                                    script as data (below)
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
#   _bd_command_word <is-target> [<from>] -> sets BD_CMDI to the index in TOK of the
#                                    program a simple command runs, past keywords,
#                                    assignments and wrappers (sudo, time, ...),
#                                    and BD_WRAPI to the wrappers' indices
#   _bd_shell_reads_stdin <index> -> 0 when TOK[index] is a shell that reads its
#                                    script from its input (no -c, no script file)
#   _bd_expand_interpreter_args   -> appends quoted interpreter arguments, and text
#                                    piped into a shell, to BD_CODE; with
#                                    BD_LANG_DATA=1 not those of a language
#                                    interpreter (_bd_is_language)
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
    # The `${NAME:-` of a default read in pieces, printed once the word that
    # holds its last piece has ended.
    function flushmark() { if (pmark != "") { print "W10" pmark; pmark = "" } }
    function emit() {
      if (!inw) { flushmark(); return }
      if (qs && (index(cur, "$@") || cur ~ /[$][{][^}]*@/)) qs = 0
      gsub(/\n/, RSN, cur)
      if (pend == "H" || pend == "I" || pend == "R") print pend cur
      else if (pend == "") print "W" ((xp || inexp || index(cur, "__BD_SUBST__")) ? 1 : 0) (qs ? 1 : 0) cur
      cur = ""; inw = 0; plain = 1; xp = 0; pend = ""; qs = 0
      flushmark()
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
      n = length(s); cur = ""; inw = 0; plain = 1; xp = 0; pend = ""; qs = 0; inexp = 0; pmark = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        # The closing brace of a ${...} read in pieces (splitexp=1, below)
        # ends the expansion and is no part of the last piece.
        # A default read in pieces leaves its `${NAME:-` as a word of its own,
        # after the word its last piece is in (below).
        if (c == "}" && (i in cb)) { if (cb[i] != "1" && pend == "") pmark = cb[i]; delete cb[i]; inexp = 0; continue }
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
        # closing brace is read character by character. With splitexp=1:
        #   - a default, an assigned default or an alternative (`${NAME:-...}`,
        #     `-`, `:=`, `=`, `:+`, `+`) is read as the words bash makes of
        #     what follows the operator, quotes removed and split at
        #     whitespace: the value when the variable is unset (set, for +).
        #     Text before it is glued to the first of those words and text
        #     after it to the last, as bash does (`rm -${X:-rf src}` is rm
        #     -rf src, `git reset --har${X:-d }` is git reset --hard). The
        #     `${NAME:-` is then a word of its own after them, which marks
        #     that a variable is there without standing where the program or
        #     the subcommand is (`git ${X:-reset --hard}` is git reset
        #     --hard `${X:-`).
        #   - any other that holds whitespace is read character by character,
        #     so its pieces are words of their own.
        # The closing brace is dropped, and each piece is flagged as an
        # expansion (inexp).
        if (c == "$" && substr(s, i + 1, 1) == "{") {
          d = 1
          for (k = i + 2; k <= n && d > 0; k++) {
            e = substr(s, k, 1)
            if (e == "$" && substr(s, k + 1, 1) == "{") { d++; k++ }
            else if (e == "}") d--
          }
          if (d == 0 && splitexp == 1 && match(substr(s, i, k - i), /^[$][{][A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?:?[-+=]/)) {
            cb[k - 1] = substr(s, i, RLENGTH); inexp = 1; xp = 1; qs = 0
            i = i + RLENGTH - 1; continue
          }
          if (d == 0 && splitexp == 1 && substr(s, i, k - i) ~ /[ \t\r\n]/) {
            cb[k - 1] = 1; inexp = 1; xp = 1
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
  _bd_is_language "$1" && return 0
  case "${1##*/}" in
    eval|source|.|ssh|su|doas|sudo|env|nohup|timeout|xargs|docker|kubectl|make|at)
      return 0 ;;
  esac
  return 1
}

# The language interpreters, the one list _bd_is_language and the heredoc
# reading of _bd_strip_noncode (langre) use: programs that run their script
# as Python, Perl, Ruby or JavaScript rather than as shell.
_BD_LANGS="python python2 python3 perl ruby node deno bun"

# Does this word name a language interpreter? A hook that sets BD_LANG_DATA=1
# reads such a script as data: its strings are not shell, and markdown
# backquotes in them are not substitutions. What it runs is not read; the
# hooks that set it leave that to a check made when the program runs.
_bd_is_language() {
  case "${1##*/}" in ""|*[[:space:]]*) return 1 ;; esac
  case " $_BD_LANGS " in *" ${1##*/} "*) return 0 ;; esac
  return 1
}

# The shells, the one list every reader of a command uses: _bd_is_shell,
# _bd_shell_reads_stdin, _bd_is_interpreter, and the piped-into-a-shell pass
# of _bd_expand_interpreter_args (_BD_SHELL_RE).
_BD_SHELLS="sh bash zsh ksh dash ash mksh busybox tcsh csh fish yash rbash"
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

# The words in front of a program that are not the program, the one list each
# that every reader looking for a command word uses (_bd_command_word): shell
# keywords after which a command starts (`if x; then cmd; fi`, `{ cmd; }`,
# `! cmd`), and programs that run the rest of their line.
_BD_KEYWORDS="if then elif else while until do ! {"
_BD_WRAPPERS="sudo doas env nohup nice time command builtin exec timeout xargs stdbuf setsid ionice caffeinate chrt taskset flock unbuffer chronic coproc busybox script watch parallel"

# _bd_command_word <is-target> [<from>]
# Reads TOK from index <from> (default 0) and sets BD_CMDI to the index of
# the word the shell runs as the program: past assignments, past the words in
# _BD_KEYWORDS, and past each program in _BD_WRAPPERS, after which the program
# is the first word the function <is-target> accepts, past the wrapper's
# options and their values (`timeout 5 bash`, `sudo -u deploy curl`,
# `ionice -c3 bash`). BD_WRAPI gets the index of each wrapper stepped over.
# BD_CMDI is the number of words when there is no program (`command -v x`
# looks a program up and runs nothing; a wrapper with no target after it).
# The caller declares TOK, BD_CMDI and BD_WRAPI.
_bd_command_word() {
  local is="$1" i="${2:-0}" n=${#TOK[@]} w b
  BD_WRAPI=()
  while [ "$i" -lt "$n" ]; do
    w="${TOK[i]}"
    case "$w" in [A-Za-z_]*=*) i=$((i + 1)); continue ;; esac
    case " $_BD_KEYWORDS " in *" $w "*) i=$((i + 1)); continue ;; esac
    # A program name is never longer than PATH_MAX, and stripping the
    # directory of a long word costs a rescan.
    [ "${#w}" -le 4096 ] || break
    b="${w##*/}"
    if [ "$b" = command ]; then
      case "${TOK[i+1]:-}" in -*[vV]*) i=$n; break ;; esac
    fi
    case " $_BD_WRAPPERS " in
      *" $b "*)
        BD_WRAPI+=("$i")
        i=$((i + 1))
        while [ "$i" -lt "$n" ] && ! "$is" "${TOK[i]}"; do i=$((i + 1)); done
        continue ;;
    esac
    break
  done
  BD_CMDI=$i
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
      # It prints and exits.
      --version|--help) return 1 ;;
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
#   - no odd number of backslashes comes before the `<<`: bash reads
#     `cat \<<'EOF'` as cat given a literal `<` and its input redirected
#     from the file EOF, so the lines after it are commands (`\\<<EOF` is a
#     literal backslash and a heredoc);
#   - when the delimiter is not quoted, the body holds nothing bash runs as
#     it expands it (body_runs): no `$(` or backquote that no backslash
#     escapes, no `$((` or `$[` (an array subscript in arithmetic runs a
#     substitution), and no `${` but a plain `${NAME}`, `${#NAME}` or
#     `${NAME:-word}` with no group, backquote or backslash in the word
#     (`${x@P}` runs the substitutions in x). Bash runs these before cat,
#     tee, echo, printf or gh read anything, so `cat <<EOF` with a
#     `$(rm -rf ~)` line keeps its body in every reading, printed as what
#     bash runs of it (body_code): each substitution as written, each run of
#     other text as one `_` after a `:` that runs nothing, so a quote in the
#     text pairs with nothing. Both read the body as bash expands it, with
#     each backslash-newline removed first (bs_join): `$\` at the end of one
#     line and `(rm -rf ~)` on the next are one substitution. A body the scan
#     cannot follow is printed as written (joined) and again without its
#     quotes. A quoted delimiter's body is never joined or expanded;
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
# BD_BLANK_BODIES=1 changes this for a second reading, the command without
# the data its readers take in, which block-secrets.sh makes to tell a body
# line from a command: it also drops a body whose owner is not a sink when
# nothing on the line runs it (reader_ok: no shell, no interpreter, no
# command word that is a variable or a substitution). It does not drop a
# body when the command sets BASH_ENV or ENV on that line or an earlier one
# (env_named): a shell started with BASH_ENV=/dev/stdin reads the body as
# its startup file. It does not change the first reading, which
# block-destructive.sh, block-unchecked-merge.sh and block-force-push.sh
# judge.
#
# BD_LANG_DATA=1 (tier-gate.sh and block-unchecked-merge.sh) counts a
# language interpreter (_bd_is_language: python, perl, ruby, node, deno, bun)
# as a text sink: its heredoc body is its script, read as data as a cat body
# is, also when the line redirects or pipes the program's output (`python3 -
# <<'PY' 2>&1`, `| tail`). A quoted body is dropped whole; an unquoted body
# keeps what bash runs as it expands the body (body_code). A shell is never a
# sink, so `bash <<'EOF'` keeps its body.
#
# Carriage returns are stripped first, so a CRLF command is read the same way a
# LF one is. Both tokeniser paths then agree about where words end.
_bd_strip_noncode() {
  BD_CODE=$(printf '%s\n' "$1" | awk -v blank="${BD_BLANK_BODIES:-0}" -v langdata="${BD_LANG_DATA:-0}" -v langs="$_BD_LANGS" -v shells="$_BD_SHELLS" '
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
    function owner_name(w,   SQ2) {
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
      return w
    }
    # langdata=1 only (BD_LANG_DATA): is the owner a language interpreter,
    # whose heredoc body is its script? Such a body is data whatever the line
    # does with the output of the program (`2>&1`, `> out.md`, `| tail`).
    function is_lang(w) {
      return (langdata == 1 && owner_name(w) ~ langre)
    }
    function is_sink(w) {
      w = owner_name(w)
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
    # substitution, which may be either. Nor when the command sets BASH_ENV
    # or ENV on this line or an earlier one (envset, env_named): a shell
    # started with BASH_ENV=/dev/stdin reads its input as its startup file,
    # whatever it was asked to run.
    function reader_ok(str,   n, cmds, i, m, w, j, c, x) {
      if (envset) return 0
      n = split(str, cmds, /[;&|(){}`]|[$][(]/)
      for (i = 1; i <= n; i++) {
        m = split(cmds[i], w, /[ \t]+/)
        c = 1
        for (j = 1; j <= m; j++) {
          if (w[j] == "") continue
          x = w[j]
          gsub("[\"" SQ "\\\\]", "", x)
          if (c) {
            if (x ~ /^(if|then|elif|else|while|until|do|!|time)$/) continue
            if (x ~ /^[A-Za-z_][A-Za-z0-9_]*[+]?=/) continue
            if (x == "" || x ~ /^[$]/) return 0
            c = 0
          }
          sub(/^.*\//, "", x)
          x = tolower(x)
          if (x ~ shre) return 0
          if (x ~ runre) return 0
        }
      }
      return 1
    }
    # Does the line s (a line of the command without its comment; q0 is the
    # quote state it starts in) set ENV or BASH_ENV, or may it? A name built
    # with quotes or backslashes is the name (B""ASH_ENV=, export
    # "BASH_ENV=..."), so a word that holds the name once its quotes are
    # removed counts, and so does a string with a space in it that holds an
    # assignment to it (export "BASH_ENV=/tmp/my file"). The name inside a
    # sentence does not (echo "check ENV first"): a string with a space in it
    # is no name bash can set. Every mention counts when the scan may misread
    # the line, or a string on it may be run as code: when the line starts
    # inside a quote, leaves one open, holds a $ or a backquote, or has a
    # word that is a shell, a program that runs its arguments (runre), trap,
    # alias or bind.
    function env_named(s, q0,   x, any, n, i, c, nx, q, w, sp, inw, hit, fc, b) {
      x = s
      gsub("[\"" SQ "\\\\]", "", x)
      if (x !~ /ENV/) return 0
      any = (s ~ /(^|[^A-Za-z0-9_])(BASH_ENV|ENV)([^A-Za-z0-9_]|$)/ ||
             x ~ /(^|[^A-Za-z0-9_])(BASH_ENV|ENV)([^A-Za-z0-9_]|$)/)
      if (!any) return 0
      if (q0 != "" || s ~ /[$`]/) return 1
      n = length(s); q = ""; w = ""; sp = 0; inw = 0; hit = 0; fc = 0
      for (i = 1; i <= n + 1; i++) {
        c = (i <= n) ? substr(s, i, 1) : " "
        nx = substr(s, i + 1, 1)
        if (q == "") {
          if (c == "\\") { w = w nx; i++; inw = 1; continue }
          if (c == "\"" || c == SQ) { q = c; inw = 1; continue }
          if (c ~ /[ \t;&|()<>]/) {
            if (inw) {
              if (!sp && w ~ /(^|[^A-Za-z0-9_])(BASH_ENV|ENV)([^A-Za-z0-9_]|$)/) hit = 1
              if (sp && w ~ /(^|[^A-Za-z0-9_])(BASH_ENV|ENV)(\[[^]]*\])?[+]?=/) hit = 1
              b = w
              sub(/^.*\//, "", b)
              b = tolower(b)
              if (!sp && (b ~ shre || b ~ runre || b ~ /^(trap|alias|bind)$/)) fc = 1
            }
            w = ""; sp = 0; inw = 0
            continue
          }
          w = w c; inw = 1
          continue
        }
        if (c == q) { q = ""; continue }
        if (q == "\"" && c == "\\" && (nx == "\"" || nx == "\\")) { w = w nx; i++; continue }
        if (c == " " || c == "\t") sp = 1
        w = w c
      }
      if (q != "" || fc) return 1
      return hit
    }
    # The body s of a heredoc whose delimiter is not quoted, as bash reads it
    # before it expands anything: each backslash-newline removed, so the two
    # lines are one. An escaped backslash (\\) before a newline is a
    # backslash, and the newline stays.
    function bs_join(s,   n, i, c, out) {
      if (index(s, "\\\n") == 0) return s
      out = ""
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") {
          if (substr(s, i + 1, 1) != "\n") out = out c substr(s, i + 1, 1)
          i++
          continue
        }
        out = out c
      }
      return out
    }
    # May the << that starts at p in s introduce a heredoc? Not when it is the
    # second and third < of a here-string (<<<), and not when an odd number of
    # backslashes comes before it: bash reads \<<EOF as a literal < followed
    # by a < redirection from the file EOF, and the lines after it are
    # commands. An even number (\\<<EOF) is a literal backslash and then a
    # heredoc.
    function intro_at(s, p,   b, k) {
      if (p == 1) return 1
      if (substr(s, p - 1, 1) == "<") return 0
      b = 0
      for (k = p - 1; k >= 1 && substr(s, k, 1) == "\\"; k--) b++
      return (b % 2) == 0
    }
    # Does the body s of a heredoc whose delimiter is not quoted run anything
    # when bash expands it? It does when it holds a command substitution, $(
    # or a backquote not escaped by a backslash; an arithmetic expansion, $((
    # or $[, which may run one through an array subscript; or a ${ that is not
    # a plain ${NAME}, ${#NAME} or ${NAME:-word} whose word holds no group,
    # backquote or backslash (${x@P} runs the substitutions in x). Such a body
    # is kept wherever it goes, cat, tee, echo, printf and gh included, as
    # bash runs those before the program reads anything. The caller has
    # removed each backslash-newline first (bs_join), so a $ at the end of a
    # line and the ( { or [ on the next are read together.
    function body_runs(s,   i, n, c, nx) {
      if (index(s, "$") == 0 && index(s, BT) == 0) return 0
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { i++; continue }
        if (c == BT) return 1
        if (c != "$") continue
        nx = substr(s, i + 1, 1)
        if (nx == "(" || nx == "[") return 1
        if (nx == "{" && !match(substr(s, i, 512), PLAINV)) return 1
      }
      return 0
    }
    # What bash runs of such a body s, for the hooks to judge. Text outside
    # a substitution is data: each run of it becomes one _, and a line that
    # starts outside a substitution starts with ":", the command that runs
    # nothing, so that text is only its argument and its quotes (an
    # apostrophe in prose) pair with nothing. A substitution is kept as
    # written, over as many lines as it spans, so its commands are read as
    # commands: "merged $(gh pr merge 1) today" becomes ": _$(gh pr merge 1)_".
    # Returns UNSURE when the scan cannot follow the body: a substitution
    # still open at its end, a # or a << or the word case inside one (a
    # comment, a heredoc or a case pattern may hold a ) that closes nothing),
    # a ${ inside one other than a plain one with no quote or $ in its word
    # (${x:-)} holds a ) that closes nothing), or a $((, $[ or a ${ other
    # than a plain one outside one. The caller has removed each
    # backslash-newline first (bs_join).
    function body_code(s,   n, i, c, nx, st, top, out, bol, pz) {
      st = "B"; out = ""; bol = 1; pz = 0
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        nx = substr(s, i + 1, 1)
        top = substr(st, length(st), 1)
        if (top == "B") {
          if (c == "\n") { out = out "\n"; bol = 1; pz = 0; continue }
          if (bol) { out = out ": "; bol = 0 }
          if (c == "\\") {
            # A backslash and a newline join two lines; any other escaped
            # character is text.
            i++
            if (nx != "\n" && !pz) { out = out "_"; pz = 1 }
            continue
          }
          if (c == "$" && nx == "(") {
            if (substr(s, i + 2, 1) == "(") return UNSURE
            st = st "S"; out = out "$("; i++; pz = 0
            continue
          }
          if (c == BT) { st = st "T"; out = out BT; pz = 0; continue }
          if (c == "$" && nx == "[") return UNSURE
          if (c == "$" && nx == "{") {
            if (!match(substr(s, i, 512), PLAINV)) return UNSURE
            i += RLENGTH - 1
          }
          if (!pz) { out = out "_"; pz = 1 }
          continue
        }
        out = out c
        # Q: inside single quotes in a substitution; D: double quotes; T: a
        # backquote; S: a substitution; P: a group inside one.
        if (top == "Q") { if (c == SQ) st = substr(st, 1, length(st) - 1); continue }
        if (c == "\\") { out = out nx; i++; continue }
        if (top == "T") { if (c == BT) st = substr(st, 1, length(st) - 1); continue }
        # A ${ inside a substitution ends at its own }: a ) or a quote in its
        # word closes nothing ($(echo ${x:-)}; gh pr merge 1) runs the
        # merge). A plain one is copied whole; any other is one this scan
        # cannot follow.
        if (c == "$" && nx == "{") {
          if (!match(substr(s, i, 512), PLAINS)) return UNSURE
          out = out substr(s, i + 1, RLENGTH - 1)
          i += RLENGTH - 1
          continue
        }
        if (top == "D") {
          if (c == "\"") st = substr(st, 1, length(st) - 1)
          else if (c == "$" && nx == "(") { st = st "S"; out = out nx; i++ }
          else if (c == BT) st = st "T"
          continue
        }
        if (c == SQ) st = st "Q"
        else if (c == "\"") st = st "D"
        else if (c == BT) st = st "T"
        else if (c == "(") st = st "P"
        else if (c == ")") st = substr(st, 1, length(st) - 1)
        else if (c == "#" || (c == "<" && nx == "<")) return UNSURE
        else if (c == "c" && substr(s, i, 4) == "case" && substr(s, i - 1, 1) !~ /[A-Za-z0-9_]/ &&
                 substr(s, i + 4, 1) !~ /[A-Za-z0-9_]/) return UNSURE
      }
      if (st != "B") return UNSURE
      return out
    }
    BEGIN { SQ = sprintf("%c", 39); BT = sprintf("%c", 96); DQ = "$" SQ; inhd = 0; buf = ""; delim = ""; tabs = 0; pend = ""; q = ""; q0 = ""; nos = 0
            hdq = 0; envset = 0; UNSURE = sprintf("%c", 1)
            PLAINV = "^[$][{]#?([A-Za-z_][A-Za-z0-9_]*|[0-9]+)(:?[-=+?][^" BT "{}()\\\\[\n]*)?[}]"
            # The same inside a substitution, where a quote or a $ in the
            # word would pair with text the scan reads past (body_code).
            PLAINS = "^[$][{]#?([A-Za-z_][A-Za-z0-9_]*|[0-9]+)(:?[-=+?][^" BT "{}()\\\\[\n\"" SQ "$]*)?[}]"
            am = 0; pd = 0; bk = 0; am0 = 0; pd0 = 0; bk0 = 0
            shre = shells; gsub(/ +/, "|", shre); shre = "^(" shre ")$"
            runre = "^(python[23]?|perl|ruby|node|deno|bun|eval|source|[.]|exec|ssh|su|doas|sudo|env|nohup|timeout|xargs|docker|kubectl|make|at|script|watch|command|builtin|nice|setsid|stdbuf|caffeinate|parallel|tmux|screen)$"
            # The language interpreters (_BD_LANGS), whose heredoc body is
            # data with langdata=1 (is_lang).
            langre = langs; gsub(/ +/, "|", langre); langre = "^(" langre ")$" }
    {
      line = $0
      sub(/\r$/, "", line)

      if (inhd) {
        cand = line
        if (tabs) sub(/^\t+/, "", cand)
        if (cand == delim) {
          inhd = 0
          # A body whose delimiter is not quoted (hdq 0) and in which bash
          # runs something as it expands it (body_runs) is code, whoever
          # reads it: what bash runs of it is printed (body_code). When the
          # scan cannot follow it, the body is printed as written and again
          # without its quotes, so no quote in its text can pair with another
          # and hide a substitution between them. Both read it with each
          # backslash-newline removed, as bash does before it expands the
          # body (bs_join): $\ and (gh pr merge 1) on the next line are one
          # substitution.
          jb = hdq ? buf : bs_join(buf)
          if (!hdq && body_runs(jb)) {
            bc = body_code(jb)
            if (bc == UNSURE) {
              printf "%s", jb
              bc = jb
              gsub("[\"" SQ "]", "", bc)
              printf "%s", bc
              print line
            } else printf "%s", bc
            kept = 1
          }
          buf = ""
          next
        }
        buf = buf line "\n"
        next
      }

      # A continued line is scanned again with the line it continues, from the
      # quote state that line started in, so nothing is counted twice.
      if (pend == "") { q0 = q; am0 = am; pd0 = pd; bk0 = bk }
      line = pend line
      pend = ""
      q = q0
      am = am0; pd = pd0; bk = bk0

      # --- remove a comment, tracking quotes and backslash escapes ---------
      # Two quote states. `q` carries from one line to the next, as the shell
      # does: `--body "Ready.` then `Closes #12" && gh pr merge 9` has its `#`
      # inside the string. `ql` starts fresh on every line, as this scan always
      # did: a heredoc body kept as text is not quoted text, and one apostrophe
      # in it (the word dont, spelled with an apostrophe) would otherwise leave `q` open and turn the `#` in a
      # later `-m "Refs #12" written with single quotes` into a comment that cuts the command after it.
      # A `#` is a comment only when both say it is outside quotes. Either
      # alone can only be wrong in the direction of keeping text.
      # A `#` opens a comment only when the character before it ends a word:
      # a space, a tab, a separator, or nothing. An ESCAPED space or `;` is
      # part of the word, as the shell reads it, so `ls x\ #y ; rm -rf ~` has
      # no comment and runs the rm. `pe1` and `pe2` say whether the character
      # one and two places back was escaped. A `(` ends a word for this only
      # when it opens one itself: zsh reads the `#` of `ls /(#|tmp) ; rm -rf ~`
      # as part of a glob and runs the rm (bash refuses the line). A `)` ends
      # a word only when it closes a `(` that opened one: a subshell or a
      # `((` arithmetic command. The `)` of a `$( )`, `$(( ))`, `<( )` or any
      # other `(` inside a word leaves the word going on, so
      # `echo $(true)#x ; rm -rf ~` has no comment and runs the rm. `ps`
      # holds one letter per open `(` on the line, s for one that opens a
      # word and w for one inside a word, and `sc` is where the last `)` that
      # closed an s stood. A `)` with no `(` on its line is not known to end
      # a word. Counting parentheses cannot tell which `)` closes what once
      # the line holds a `$` or a backquote (the `)` inside `${x:-)}`, or a
      # case pattern inside a `$( )`, pops the wrong `(`), or a `(` inside a
      # word, so after either (`nos`) no `)` opens a comment and the rest of
      # the line stays code. `nos` is not reset at a line break: a `${`, `$(`
      # or backquote opened on one line can still be open on the next (`${x:-`
      # then `(a)#}` is one word to bash), and quotes nest inside a `$( )` in
      # a way this scan does not follow, so once a line has held one no `)`
      # on a later line opens a comment either. When in doubt the text is
      # kept, which only ever makes a rule see more.
      # Inside `(( ))` or `$(( ))` arithmetic and inside `[[ ]]` (a `=~`
      # regex) a `#` is never a comment: `(( x = (1)#2 )) ; rm -rf ~`,
      # `(( x = 1 #2 )) ; rm -rf ~` and `[[ a =~ (a)#x ]] ; rm -rf ~` all run
      # the rm. `am` is 1 while a `((` is open, `pd` counts the single `(`
      # open inside it, so the `))` of `(1+(2))` closes no `((`, and `bk` is
      # 1 while a `[[` is open; all three carry over a line break (`((` then
      # `(1)#2 ))` on the next line). `lp` is the last character a pair
      # took. While either is open no `#` opens a comment. Counting cannot
      # follow every form, so a line that held either also sets `nos`, and
      # no `)` on it or on a later line opens a comment.
      n = length(line); cut = 0; ql = ""; eq = 0; el = 0; pe1 = 0; pe2 = 0; ps = ""; sc = 0; lp = 0
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
        if ((c == "$" || c == "`") && !bq && !bl) nos = 1
        if (oq && ol && !bq && !bl && lp != i) {
          nx = (i < n) ? substr(line, i + 1, 1) : ""
          if (am) {
            if (c == "(") pd++
            else if (c == ")") { if (pd > 0) pd--; else if (nx == ")") { am = 0; lp = i + 1 } }
          } else if (c == "(" && nx == "(") { am = 1; pd = 0; nos = 1; lp = i + 1 }
          else if (bk) { if (c == "]" && nx == "]") { bk = 0; lp = i + 1 } }
          else if (c == "[" && nx == "[") { bk = 1; nos = 1; lp = i + 1 }
        }
        if (oq && ol && !bq && !bl && (c == "(" || c == ")")) {
          prev = (i == 1) ? "" : substr(line, i - 1, 1)
          if (c == ")") {
            if (ps != "") {
              if (substr(ps, length(ps), 1) == "s") sc = i
              ps = substr(ps, 1, length(ps) - 1)
            }
          } else if (pe1) ps = ps "w"
          else if (prev == "(") ps = ps ((substr(ps, length(ps), 1) == "s") ? "s" : "w")
          else if (prev == "" || prev == " " || prev == "\t" || prev == ";" ||
                   prev == "|" || prev == "&" || prev == ")") ps = ps "s"
          else ps = ps "w"
          if (c == "(" && substr(ps, length(ps), 1) == "w") nos = 1
        }
        if (c == "#" && oq && ol && !bq && !bl && !pe1 && !am && !bk) {
          prev = (i == 1) ? "" : substr(line, i - 1, 1)
          if (prev == "" || prev == " " || prev == "\t" || prev == ";" ||
              prev == "|" || prev == "&" || (prev == ")" && sc == i - 1 && !nos)) { cut = i; break }
          if (prev == "(") {
            pp = (i == 2) ? "" : substr(line, i - 2, 1)
            if (pp == "" || (!pe2 && (pp == " " || pp == "\t" || pp == ";" || pp == "|" ||
                pp == "&" || pp == "(" || pp == ")"))) { cut = i; break }
          }
        }
        pe2 = pe1; pe1 = (bq || bl)
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
      # A command that sets BASH_ENV or ENV may make a shell read its input
      # as a startup file (reader_ok, env_named).
      if (!envset && env_named(out, q0)) envset = 1
      # BASH_ENV can be set out of sight: spelled with ANSI-C escapes
      # ($'BASH_\x45NV'), or by a file the command sources (. ./env.sh,
      # source env.sh). Either counts as setting it.
      if (!envset && (index(out, "$" SQ) ||
          out ~ /(^|[;&|(){}]|then|do|else)[ \t]*(source|\.)[ \t]/)) envset = 1
      probe = out
      hits = gsub(/<</, "<<", probe)
      if (q0 != "") hits = 0
      # With blank=1 (BD_BLANK_BODIES) a heredoc whose owner is not a sink is
      # dropped too, when the line ends outside quotes and reader_ok says
      # nothing on it runs the body: the reading of a command without the
      # data its loops and readers take in.
      if (hits == 1 && (out !~ /[|>]/ || blank == 1 || langdata == 1) &&
          match(out, /<<-?["]?[A-Za-z_][A-Za-z0-9_]*["]?[ \t]*$/) &&
          intro_at(out, RSTART)) {
        intro = substr(out, RSTART)
        owner = owner_word(substr(out, 1, RSTART - 1))
        vq = (intro ~ /^<<-?"[A-Za-z_][A-Za-z0-9_]*"/)
        if ((out !~ /[|>]/ && is_sink(owner)) || is_lang(owner) || (blank == 1 && q == "" && reader_ok(substr(out, 1, RSTART - 1)))) {
          d = intro
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub(/^["]|["][ \t]*$/, "", d)
          gsub(/[ \t]+$/, "", d)
          if (d != "") { inhd = 1; delim = d; buf = ""; hdq = vq }
        }
      }
      # The same shape with a single-quoted delimiter. Written separately
      # because embedding an apostrophe in this program would end it.
      if (!inhd && hits == 1 && (out !~ /[|>]/ || blank == 1 || langdata == 1) &&
          match(out, "<<-?" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ "[ \t]*$") &&
          intro_at(out, RSTART)) {
        intro = substr(out, RSTART)
        owner = owner_word(substr(out, 1, RSTART - 1))
        if ((out !~ /[|>]/ && is_sink(owner)) || is_lang(owner) || (blank == 1 && q == "" && reader_ok(substr(out, 1, RSTART - 1)))) {
          d = intro
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub(SQ, "", d)
          gsub(/[ \t]+$/, "", d)
          if (d != "") { inhd = 1; delim = d; buf = ""; hdq = 1 }
        }
      }
      # A heredoc fed to a text tool whose output goes only to gh (`cat
      # <<'EOF' | gh pr create --body-file -`) is data: gh reads it and runs
      # none of it. Only when nothing before the introducer is quoted,
      # escaped, substituted or redirected, the delimiter is one whole quoted
      # word (bash expands nothing in such a body; with a bare delimiter it
      # runs a `$(...)` in it), and after it comes one pipe into a single gh
      # command and nothing else.
      if (!inhd && hits == 1 && q == "" &&
          (match(out, /<<-?"[A-Za-z_][A-Za-z0-9_]*"/) ||
           match(out, "<<-?" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ)) &&
          intro_at(out, RSTART)) {
        pre = substr(out, 1, RSTART - 1)
        d = substr(out, RSTART, RLENGTH)
        post = substr(out, RSTART + RLENGTH)
        owner = owner_word(pre)
        if (owner != "gh" && is_sink(owner) && pre !~ ("[\"" SQ "\\\\`$()<>|;&]") &&
            post ~ /^[ \t]*[|][ \t]*gh[ \t][^|;&<>`$()]*$/) {
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub("[\"" SQ "]", "", d)
          if (d != "") { inhd = 1; delim = d; buf = ""; hdq = 1 }
        }
      }
      # With blank=1 only: an introducer followed by redirections or a pipe
      # (`cat <<EOF > body.md`, `gh pr comment 5 --body-file - <<EOF
      # >/dev/null`, `cat <<EOF | gh pr create --body-file -`) is dropped too
      # when reader_ok finds no shell, interpreter or variable command word
      # anywhere on the line, the text after the introducer included: `cat
      # <<EOF | bash` and `cat <<EOF > >(bash)` keep their bodies. With
      # langdata=1 (in every reading) the body of a language interpreter is
      # dropped here too (`python3 - <<PY 2>&1`, `node - <<JS | tail`): it
      # is the script of the program, unless the text after the introducer
      # hands the output to a shell or another program that runs it (`| bash`,
      # `> >(sh)`), which reader_ok refuses: what the script prints is then
      # commands, and its body is kept.
      if (!inhd && (blank == 1 || langdata == 1) && hits == 1 && q == "" &&
          (match(out, /<<-?["]?[A-Za-z_][A-Za-z0-9_]*["]?[ \t]*([0-9]*>|&>|[|])/) ||
           match(out, "<<-?" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ "[ \t]*([0-9]*>|&>|[|])")) &&
          intro_at(out, RSTART)) {
        pre = substr(out, 1, RSTART - 1)
        rest = substr(out, RSTART)
        match(rest, "^<<-?[\"" SQ "]?[A-Za-z_][A-Za-z0-9_]*[\"" SQ "]?")
        d = substr(rest, 1, RLENGTH)
        post = substr(rest, RLENGTH + 1)
        vq = (d ~ /^<<-?"[A-Za-z_][A-Za-z0-9_]*"$/ || d ~ ("^<<-?" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ "$"))
        if ((is_lang(owner_word(pre)) && reader_ok(post)) || (blank == 1 && reader_ok(pre " " post))) {
          sub(/^<</, "", d)
          tabs = 0
          if (substr(d, 1, 1) == "-") { tabs = 1; d = substr(d, 2) }
          gsub("[\"" SQ "]", "", d)
          if (d != "") { inhd = 1; delim = d; buf = ""; hdq = vq }
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
  local seg tok base i n found runs h prev
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=() BD_WRAPI=()
  local BD_RIN=0 BD_CMDI=0
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
    runs=0
    for ((i = 0; i < n; i++)); do
      tok="${TOK[i]}"
      # Only the last path component of a word can name an interpreter, and
      # a name longer than sixteen characters is none. With BD_LANG_DATA=1
      # the words after a language interpreter are its script and its
      # arguments, read as data (found=2), until the next interpreter word
      # (`sudo python3 -c '...'` passes sudo first; `python3 -c '...' &&
      # bash -c '...'` reads bash's). runs=1: the line names an interpreter
      # that is not a language one, which may read a here-string anywhere on
      # the line (`bash <<<'...'; echo node`).
      if [ "${#tok}" -le 4096 ]; then
        base="${tok##*/}"
        if [ "${#base}" -le 16 ] && _bd_is_interpreter "$base"; then
          found=1
          if [ "${BD_LANG_DATA:-0}" = 1 ] && _bd_is_language "$base"; then found=2; else runs=1; fi
          continue
        fi
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
    # anywhere (`cat <<<'...' | bash`). Each one is read as a command. With
    # BD_LANG_DATA=1 a line whose only interpreters are language ones
    # (`python3 <<<'...'`) keeps its here-strings as data.
    if [ "$runs" = "1" ] && [ "${#BD_HSTR[@]}" -gt 0 ]; then
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
      # On the text without quotes and backslashes, which bash removes
      # from a word before it runs it (`| bas\h` runs bash).
      local bare="${BD_CODE//\\/}"
      bare="${bare//\"/}"; bare="${bare//\'/}"
      shopt -q nocasematch && nc=1
      shopt -s nocasematch
      [[ "$bare" =~ $_BD_SHELL_RE ]] && piped=1
      [ "$nc" = 1 ] || shopt -u nocasematch ;;
  esac
  case "$piped" in
    1)
      while IFS= read -r seg; do
        case "$seg" in ''|__BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
        case "$seg" in __BD_ALT__*) seg="${seg:10}" ;; esac; case "$seg" in __BD_PIPE__*) seg="${seg:11}" ;; esac
        _bd_words "$seg"
        n=${#TOK[@]}
        # The shell is the command word (_bd_command_word): past assignments,
        # shell keywords (`if true; then bash; fi`), and the programs that run
        # the rest of the line (and their options).
        _bd_command_word _bd_is_shell 0
        i=$BD_CMDI
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
