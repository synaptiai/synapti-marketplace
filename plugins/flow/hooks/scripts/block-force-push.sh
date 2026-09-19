#!/bin/bash
# [flow] PreToolUse hook: Block force-push operations
# Exit 2 = block the tool call with feedback message

set -euo pipefail

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

# Read tool input from stdin. `printf`, not `echo`: the payload is a JSON
# document relayed to a parser, and an interpreting builtin rewrites backslash
# escapes inside it before jq ever sees it.
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

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
# So the line is split into simple commands and each is asked whether it starts
# with `git push` and carries a force flag of its own. Two details carry most of
# the weight, and both directions are tested:
#
#   * a quoted flag is still a flag. `git push '--force'` hands that word to git
#     unchanged, so words are read the way the shell reads them — quotes group
#     and are removed, a backslash escapes — rather than skipped. The same rule
#     is what keeps `echo 'git push'` from reading as a push: its words are
#     `echo` and `git push`, and only the first can be the command.
#   * `git` takes global options before its subcommand, so `git -C repo push` is
#     a push and those options have to be stepped over.
#
# A heredoc body is text being written to a file, not commands being run.
VERDICT=$(printf '%s\n' "$COMMAND" | awk '
  BEGIN { SQ = sprintf("%c", 39); hd = ""; verdict = 0 }

  # The prefixes that leave the next word in command position: assignments, the
  # launcher words, and the shell keywords that introduce a command list.
  # `sudo git push --force` and `if git push --force; then` both force a push.
  function is_launcher(w) {
    return (w == "command" || w == "env" || w == "sudo" || w == "xargs" ||
            w == "nice" || w == "nohup" || w == "exec" || w == "eval" ||
            w == "builtin" || w == "time" || w == "if" || w == "then" ||
            w == "elif" || w == "else" || w == "while" || w == "until" ||
            w == "do" || w == "done" || w == "fi" || w == "!")
  }

  # Git global options that consume the word after them.
  function takes_value(w) {
    return (w == "-C" || w == "-c" || w == "--git-dir" || w == "--work-tree" ||
            w == "--namespace" || w == "--exec-path" || w == "--config-env")
  }

  # Is one simple command a force-push?
  function is_force_push(seg,   n, i, c, q, esc, out, nw, words) {
    # Read the segment into words the way the shell does: quotes group and are
    # removed, a backslash escapes the next character, and only unquoted
    # whitespace separates words.
    n = length(seg); q = ""; esc = 0; out = ""; nw = 0
    split("", words)
    for (i = 1; i <= n; i++) {
      c = substr(seg, i, 1)
      if (esc) { out = out c; esc = 0; continue }
      if (q != "") {
        if (c == "\\" && q == "\"") { esc = 1; continue }
        if (c == q) { q = ""; continue }
        out = out c; continue
      }
      if (c == "\\") { esc = 1; continue }
      if (c == "\"" || c == SQ) { q = c; continue }
      if (c == " " || c == "\t") {
        if (out != "") { words[++nw] = out; out = "" }
        continue
      }
      out = out c
    }
    if (out != "") words[++nw] = out

    i = 1
    while (i <= nw) {
      if (words[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
      if (is_launcher(words[i])) { i++; continue }
      break
    }
    if (i > nw || words[i] != "git") return 0
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

    line = $0
    n = length(line); q = ""; cur = ""; i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      if (q != "") {
        if (c == "\\" && q == "\"") { cur = cur c substr(line, i + 1, 1); i += 2; continue }
        if (c == q) q = ""
        cur = cur c; i++; continue
      }
      if (c == "\\") { cur = cur c substr(line, i + 1, 1); i += 2; continue }
      if (c == "\"" || c == SQ) { q = c; cur = cur c; i++; continue }
      # A `#` a command could start at begins a comment; a `#` inside a word
      # does not. Everything after it is prose about the command.
      if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;|&(]/)) break
      # `<<`/`<<-` opens a heredoc: take the delimiter and stop treating the
      # following lines as commands.
      if (c == "<" && substr(line, i + 1, 1) == "<") {
        rest = substr(line, i + 2)
        sub(/^-/, "", rest)
        sub(/^[ \t]*/, "", rest)
        d = rest; sub(/[ \t].*$/, "", d)
        gsub(/^["'"'"']|["'"'"']$/, "", d)
        if (d != "") hd = d
        i += 2; continue
      }
      if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" ||
          c == "{" || c == "}") {
        if (is_force_push(cur)) verdict = 1
        cur = ""
        i += 2
        continue
      }
      cur = cur c; i++
    }
    if (is_force_push(cur)) verdict = 1
  }

  END { print verdict }
')

if [ "$VERDICT" = "1" ]; then
  echo "BLOCKED: Force-push detected. This is a Tier 3 action that requires manual execution." >&2
  echo "If you need to force-push, ask the user to run the command directly." >&2
  echo "Note: --force-with-lease is allowed as a safe alternative." >&2
  exit 2
fi

exit 0
