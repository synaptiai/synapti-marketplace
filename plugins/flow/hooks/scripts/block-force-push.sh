#!/bin/bash
# [flow] PreToolUse hook: Block force-push operations
# Exit 2 = block the tool call with feedback message

set -euo pipefail

# Fail-safe: if the tools the decision depends on are unavailable, block rather
# than allow. jq parses the payload and awk makes the decision; a missing awk
# would otherwise exit 127, and the harness reads anything that is not 2 as an
# allow — the guard would vanish silently, which is what this check prevents.
if ! command -v jq &>/dev/null || ! command -v awk &>/dev/null; then
  echo "BLOCKED: jq and awk are both required to verify command safety. Install them to proceed." >&2
  exit 2
fi

# Read tool input from stdin. `printf`, not `echo`: the payload is a JSON
# document relayed to a parser, and an interpreting builtin rewrites backslash
# escapes inside it before jq ever sees it.
INPUT=$(cat)

# The command is what the decision is about, so a payload that cannot be parsed
# cannot be inspected — and jq's own exit status is not 2, which the harness
# would read as an allow. Block instead of falling through.
if ! COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty'); then
  echo "BLOCKED: the hook payload could not be parsed, so this command could not be inspected." >&2
  exit 2
fi

# The scan walks the command a character at a time, so its cost grows faster than
# the input, and a command large enough to matter would stall the tool call
# instead of being decided. Measured on this machine's awk, against the cap below:
# a 100 KB command takes about 0.8 s and a 128 KB one about 1.2 s.
#
# A command past the cap is refused rather than truncated. Truncating and
# scanning the head would silently drop whatever the tail contained, and a
# dropped tail is the direction that lets a force-push through.
MAX_CHARS=131072
if [ "${#COMMAND}" -gt "$MAX_CHARS" ]; then
  echo "BLOCKED: this command is larger than the ${MAX_CHARS}-character limit this guard can verify." >&2
  echo "Write it to a script file and run the file instead." >&2
  exit 2
fi

# Decide on the arguments of the push invocation itself.
#
# Scanning the whole line for a push followed anywhere by a force flag reads a
# flag belonging to a different command as the push's own: `git push && pgrep -f
# x` was refused as a force-push, and so was any command whose *text* described
# one — including the `gh issue create` that filed this defect. The direction was
# safe, never under-blocking, but the cost is a legitimate push refused with a
# message telling the operator to force-push by hand: advice that, followed, is
# the action this hook exists to prevent.
#
# So the line is split into simple commands and each is asked whether it invokes
# a push carrying a force flag of its own. The details that carry weight, each
# with a case in the test file:
#
#   * a quoted flag is still a flag. `git push '--force'` hands that word to git
#     unchanged, so words are read the way the shell reads them — quotes group
#     and are removed, a backslash escapes, ANSI-C quoting is a quoted span — rather
#     than skipped. The same rule keeps `echo 'git push'` from reading as a push:
#     its words are `echo` and `git push`, and only the first can be the command.
#   * only an unquoted separator splits commands, so `grep -q 'x ; git push'` is
#     one command, not two.
#   * `git` may carry global options first, so `git -C repo push` is a push.
#   * a launcher, an assignment prefix or a shell keyword leaves the next word in
#     command position, so `sudo git push --force` and `if git push ...; then`
#     both count — and a launcher's own options, and the value of those that take
#     one, are stepped over.
#   * a heredoc body is text being written to a file, not commands being run.
#   * input that ends mid-construct — an unclosed quote, a heredoc with no
#     terminator — is not vouched for, so it blocks.
VERDICT=$(printf '%s\n' "$COMMAND" | awk '
  BEGIN {
    SQ = sprintf("%c", 39)
    hd = ""; q = ""; buf = ""; verdict = 0; depth = 0
    MAX_DEPTH = 6
  }

  # Prefixes that leave the next word in command position: the launcher words,
  # and the shell keywords that introduce a command list.
  function is_launcher(w) {
    return (w == "command" || w == "env" || w == "sudo" || w == "doas" ||
            w == "xargs" || w == "nice" || w == "nohup" || w == "exec" ||
            w == "builtin" || w == "time" || w == "timeout" || w == "stdbuf" ||
            w == "setsid" || w == "ionice" || w == "chrt" || w == "strace" ||
            w == "if" || w == "then" || w == "elif" || w == "else" ||
            w == "while" || w == "until" || w == "do" || w == "done" ||
            w == "fi")
  }

  # A shell with -c runs its payload as a command line of its own.
  function is_shell(w) {
    return (w == "sh" || w == "bash" || w == "zsh" || w == "dash" || w == "ksh")
  }

  # /usr/bin/git is still git.
  function cmd_base(w) { sub(/^.*\//, "", w); return w }

  # git global options that consume the word after them.
  function takes_value(w) {
    return (w == "-C" || w == "-c" || w == "--git-dir" || w == "--work-tree" ||
            w == "--namespace" || w == "--exec-path" || w == "--config-env")
  }

  # A launcher option that consumes the word after it. Getting one of these
  # wrong in the "does not take a value" direction would leave the option word
  # standing where the command word belongs and hide a push behind it.
  function launcher_value(l, o) {
    if (l == "sudo")
      return (o == "-u" || o == "-g" || o == "-C" || o == "-D" || o == "-h" ||
              o == "-p" || o == "-r" || o == "-t" || o == "-R" || o == "-T" ||
              o == "-U" || o == "--user" || o == "--group" || o == "--close-from" ||
              o == "--chdir" || o == "--host" || o == "--prompt" || o == "--role" ||
              o == "--type" || o == "--command-timeout" || o == "--other-user")
    if (l == "env")
      return (o == "-u" || o == "-C" || o == "-S" || o ~ /^--unset/)
    if (l == "nice")    return (o == "-n" || o ~ /^--adjustment/)
    if (l == "xargs")
      return (o == "-n" || o == "-I" || o == "-i" || o == "-s" || o == "-P" ||
              o == "-a" || o == "-d" || o == "-E" || o == "-L" ||
              o ~ /^--(max-args|replace|max-chars|max-procs|arg-file|delimiter|eof|max-lines)/)
    if (l == "ionice")  return (o == "-c" || o == "-n" || o == "-p")
    if (l == "chrt")    return (o == "-p" || o == "-P" || o == "-T" || o == "-a")
    if (l == "timeout") return (o == "-k" || o == "-s" || o == "--signal" || o == "--kill-after")
    if (l == "stdbuf")  return (o == "-i" || o == "-o" || o == "-e" || o ~ /^--(input|output|error)/)
    if (l == "strace")
      return (o == "-o" || o == "-e" || o == "-p" || o == "-s" || o == "-f" || o == "-E")
    return 0
  }

  # Read a string into words the way the shell does: quotes group and are
  # removed, a backslash escapes, only unquoted whitespace separates. Returns
  # the word count and fills words[].
  #
  # The word is assembled by slicing runs out of the input rather than by
  # appending one character at a time. Appending per character makes the cost
  # grow with the square of the length, and a command long enough to matter
  # would then stall the tool call rather than be decided: measured before this
  # change, a 262 KB command took 23 seconds.
  function tokenize(s, words,   n, i, c, esc, qq, out, nw, ws) {
    n = length(s); nw = 0; out = ""; esc = 0; qq = ""; ws = 1; i = 1
    while (i <= n) {
      c = substr(s, i, 1)
      if (esc) {
        out = out substr(s, ws, i - ws) c
        esc = 0; ws = i + 1; i++; continue
      }
      if (qq != "") {
        if (c == "\\" && qq == "\"") {
          out = out substr(s, ws, i - ws)
          esc = 1; ws = i + 1; i++; continue
        }
        if (c == qq) {
          out = out substr(s, ws, i - ws)
          qq = ""; ws = i + 1; i++; continue
        }
        i++; continue
      }
      if (c == "\\") {
        out = out substr(s, ws, i - ws)
        esc = 1; ws = i + 1; i++; continue
      }
      # ANSI-C quoting (dollar then a single quote) comes off the same way.
      if (c == "$" && substr(s, i + 1, 1) == SQ) {
        out = out substr(s, ws, i - ws)
        qq = SQ; ws = i + 2; i += 2; continue
      }
      if (c == "\"" || c == SQ) {
        out = out substr(s, ws, i - ws)
        qq = c; ws = i + 1; i++; continue
      }
      if (c == " " || c == "\t") {
        out = out substr(s, ws, i - ws)
        if (out != "") { words[++nw] = out; out = "" }
        ws = i + 1; i++; continue
      }
      i++
    }
    out = out substr(s, ws, n - ws + 1)
    if (out != "") words[++nw] = out
    return nw
  }

  # Tokenise, then decide. Recursion depth is bounded because a payload can nest
  # shells and evals; past the bound the answer is "block", the safe direction.
  function decide_str(s,   W, n, r) {
    if (depth >= MAX_DEPTH) return 1
    n = tokenize(s, W)
    depth++
    r = decide(W, n)
    depth--
    return r
  }

  # Is one simple command a force-push?
  function decide(words, nw,   i, j, w, lw, rest) {
    i = 1
    while (i <= nw) {
      w = words[i]
      if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }   # assignment prefix
      if (w == "!") { i++; continue }
      if (!is_launcher(w)) break
      lw = cmd_base(w)
      i++
      while (i <= nw && substr(words[i], 1, 1) == "-") {
        if (launcher_value(lw, words[i])) i += 2; else i++
      }
      # A launcher may also take a bare positional of its own before the command
      # (`timeout 10 git ...`). Bounded, so an unrecognised wrapper cannot hide a
      # push behind an arbitrary number of words; the ones known to take one are
      # in launcher_value above.
      j = 0
      while (i <= nw && j < 3 && !is_launcher(words[i]) &&
             !is_shell(cmd_base(words[i])) && cmd_base(words[i]) != "git" &&
             cmd_base(words[i]) != "eval") {
        i++; j++
      }
    }
    if (i > nw) return 0

    w = cmd_base(words[i])

    if (is_shell(w)) {
      for (j = i + 1; j <= nw; j++) {
        if (words[j] == "-c" && j < nw) return decide_str(words[j + 1])
      }
      return 0
    }

    if (w == "eval") {
      rest = ""
      for (j = i + 1; j <= nw; j++) rest = rest (rest == "" ? "" : " ") words[j]
      if (rest == "") return 0
      return decide_str(rest)
    }

    if (w != "git") return 0
    i++
    while (i <= nw && substr(words[i], 1, 1) == "-") {
      if (takes_value(words[i])) i += 2; else i++
    }
    if (i > nw || words[i] != "push") return 0
    i++
    for (; i <= nw; i++) {
      # `--force` exactly, or a short-flag cluster containing f. Deliberately
      # not a substring test: `--force-with-lease` contains `--force` and is the
      # safe alternative this hook exists to recommend.
      if (words[i] == "--force") return 1
      if (words[i] ~ /^-[a-zA-Z]*f[a-zA-Z]*$/) return 1
      # A `+`-prefixed refspec is the other spelling of a forced update.
      if (words[i] ~ /^\+/) return 1
    }
    return 0
  }

  {
    # Inside a heredoc body every line is text, up to the delimiter line.
    if (hd != "") {
      t = $0
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t == hd) hd = ""
      next
    }

    # A quoted string may span lines, so a line that starts inside one has no
    # command of its own: segstart 0 means "nothing decidable on this line yet".
    line = buf $0
    buf = ""
    segstart = (q == "") ? 1 : 0

    # A line ending in an unescaped backslash continues onto the next: the shell
    # removes the backslash-newline before it parses anything.
    nb = 0; k = length(line)
    while (k - nb >= 1 && substr(line, k - nb, 1) == "\\") nb++
    if (nb % 2 == 1) { buf = substr(line, 1, k - 1); next }

    n = length(line); i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      if (q != "") {
        if (c == "\\" && q == "\"") { i += 2; continue }
        if (c == q) { q = ""; if (segstart == 0) segstart = i + 1 }
        i++; continue
      }
      if (c == "\\") { i += 2; continue }
      if (c == "$" && substr(line, i + 1, 1) == SQ) { q = SQ; i += 2; continue }
      if (c == "\"" || c == SQ) { q = c; i++; continue }
      # A `#` where a command could start begins a comment; a `#` inside a word
      # does not. Everything after it is prose about the command.
      if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;|&(]/)) {
        if (segstart > 0 && decide_str(substr(line, segstart, i - segstart))) verdict = 1
        segstart = 0
        break
      }
      if (c == "<" && substr(line, i + 1, 1) == "<") {
        # `<<<` is a here-string: it has no body, so it opens nothing.
        if (substr(line, i + 2, 1) == "<") { i += 3; continue }
        rest = substr(line, i + 2)
        sub(/^-/, "", rest)
        sub(/^[ \t]*/, "", rest)
        d = rest
        # The delimiter word ends at the first shell metacharacter, and quote
        # removal leaves the bare word the terminator line must match.
        sub(/[ \t;&|()<>].*$/, "", d)
        gsub(/\\/, "", d)
        while (d != "" && (substr(d, 1, 1) == SQ || substr(d, 1, 1) == "\"")) d = substr(d, 2)
        while (d != "" && (substr(d, length(d), 1) == SQ || substr(d, length(d), 1) == "\"")) d = substr(d, 1, length(d) - 1)
        if (d != "") hd = d
        i += 2; continue
      }
      if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" ||
          c == "{" || c == "}") {
        if (segstart > 0 && decide_str(substr(line, segstart, i - segstart))) verdict = 1
        segstart = i + 1
        i++
        continue
      }
      i++
    }
    if (segstart > 0 && segstart <= n) {
      if (decide_str(substr(line, segstart, n - segstart + 1))) verdict = 1
    }
  }

  END {
    # Reaching the end mid-construct means the scan did not see the whole command
    # line and cannot vouch for it. An unterminated heredoc and an unclosed quote
    # are both malformed input, and a malformed command is not one to allow.
    if (hd != "") verdict = 1
    if (q != "") verdict = 1
    if (buf != "") { if (decide_str(buf)) verdict = 1 }
    print verdict
  }
')

if [ "$VERDICT" = "1" ]; then
  echo "BLOCKED: Force-push detected. This is a Tier 3 action that requires manual execution." >&2
  echo "If you need to force-push, ask the user to run the command directly." >&2
  echo "Note: --force-with-lease is allowed as a safe alternative." >&2
  exit 2
fi

exit 0
