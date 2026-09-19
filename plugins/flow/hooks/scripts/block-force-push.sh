#!/bin/bash
# [flow] PreToolUse hook: Block force-push operations
# Exit 2 = block the tool call with feedback message

set -euo pipefail

# Fail-safe: every tool the decision passes through is required, and a missing
# one blocks rather than allows. The harness reads exit 2 as a block and ANY
# other status as permission, so a command that never ran — a missing binary
# exiting 127, a killed process exiting 137 — is a silent bypass unless it is
# converted into a refusal here.
#
# `cat` is on the list because the payload read is part of the decision: an
# unread payload yields an empty command, and an empty command is allowed.
MISSING=""
for t in jq awk cat grep sed wc tr; do
  command -v "$t" &>/dev/null || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
  echo "BLOCKED: the guard needs these tools to verify command safety, and they are missing:$MISSING" >&2 || true
  exit 2
fi

# Read tool input from stdin. `printf`, not `echo`: the payload is a JSON
# document relayed to a parser, and an interpreting builtin rewrites backslash
# escapes inside it before jq ever sees it.
if ! INPUT=$(cat); then
  echo "BLOCKED: the hook payload could not be read, so this command could not be inspected." >&2 || true
  exit 2
fi

# The command field must be present AND a string. `// empty` alone treats a
# missing field, a null and a number as "no command", and an empty command is
# allowed — so a payload the guard cannot inspect would be waved through. A
# present empty string is still a string, and stays allowed.
if ! COMMAND=$(printf '%s' "$INPUT" | jq -er '.tool_input.command | strings'); then
  echo "BLOCKED: the hook payload carries no command to inspect." >&2 || true
  exit 2
fi

# The scan is per-character, so its cost grows faster than the input, and a
# command large enough would stall the tool call rather than be decided. The cap
# counts BYTES, not characters: awk walks bytes, so a multi-byte command costs
# more than its character count suggests.
#
# A command past the cap is refused rather than truncated. Truncating and
# scanning the head would silently drop whatever the tail contained, and a
# dropped tail is the direction that lets a force-push through.
MAX_BYTES=131072
if ! NB=$(LC_ALL=C printf '%s' "$COMMAND" | wc -c | tr -d '[:space:]'); then
  echo "BLOCKED: the size of this command could not be measured, so it could not be scanned." >&2 || true
  exit 2
fi
# An empty or non-numeric count would make the comparison below error, and `if`
# would swallow it — skipping the cap silently.
case "$NB" in
  ""|*[!0-9]*) echo "BLOCKED: the size of this command could not be measured, so it could not be scanned." >&2 || true; exit 2 ;;
esac
if [ "$NB" -gt "$MAX_BYTES" ]; then
  echo "BLOCKED: this command is ${NB} bytes, larger than the ${MAX_BYTES}-byte limit this guard can verify." >&2 || true
  echo "Write it to a script file and run the file instead." >&2 || true
  exit 2
fi

# Decide whether the command can be shown NOT to force-push.
#
# The guard blocks by default. It allows only what it can positively account
# for, and the accounting is deliberately narrow: find each force flag, work out
# which simple command it belongs to, and ask whether that command can execute
# its arguments. `pgrep -f x` cannot — the flag is pgrep's own, and the push
# beside it is untouched. `caffeinate git push --force` can, so the flag reaches
# git and the command blocks. Neither command needs to be on a list of
# wrappers: only the ones that CANNOT run a command need naming, and a name the
# list is missing blocks rather than allows.
#
# This is the shape the previous whole-line scan lacked. It read any `-f` after
# a push as the push's own, so `git push origin main && pgrep -f x` — a fast-
# forward, not a force-push — was refused with a message telling the operator to
# force-push by hand: advice that, followed, is the action the guard exists to
# prevent. It also refused any command whose text merely described the flags,
# including the `gh issue create` that filed this defect.
#
# Three things the guard will not vouch for, each of which blocks:
#
#   * a substitution — `$( )`, backticks, `${ }`, ANSI-C quoting — because what
#     it expands to is a command the guard cannot see. A quoted string is text
#     only while it holds no substitution: `gh issue create --body 'git push
#     --force'` is data, and `echo "$(git push --force)"` is not.
#   * a push that runs through any command not on the cannot-execute list.
#   * arithmetic, whose `<<` is a shift rather than a heredoc opener.
#
# MAIN_FIRES reproduces the whole-line scan this hook used before: a push
# followed anywhere on the line by a force flag. It is consulted only where the
# accounting named no flag at all, which in practice is text it read as a
# non-push command own flag — so it is a backstop against a spelling the
# accounting has not been taught, not a second opinion on every line.
MAIN_FIRES=0
if ! STRIPPED=$(printf '%s' "$COMMAND" | sed 's/--force-with-lease//g'); then
  echo "BLOCKED: this command could not be prepared for scanning, so it could not be scanned." >&2 || true
  exit 2
fi
# `grep -c`, not `grep -q`: -q exits the moment it matches while the writer is
# still producing, and pipefail then reports the pipeline as failed. Measured on
# the -q form, MAIN_FIRES stayed 0 for commands over 64 KB, which disarms the
# floor for exactly the large commands it is the last resort for.
# The tail is the same class the accounting uses, not `\b`: `\b` matches inside
# `--force-if-includes`, which forces nothing, and would make the floor fire on a
# line with no force flag the accounting can name.
# Exit 1 means no match. Any other non-zero status means grep could not read,
# and an unread command is not one to allow — the floor is the last resort, so
# its absence has to be a refusal rather than a silence.
FLOOR_STATUS=0
printf '%s' "$STRIPPED" | grep -cE 'git[^A-Za-z0-9]*push.*(-f|--force)([^A-Za-z0-9_-]|$)' >/dev/null || FLOOR_STATUS=$?
case "$FLOOR_STATUS" in
  0) MAIN_FIRES=1 ;;
  1) MAIN_FIRES=0 ;;
  *) echo "BLOCKED: this command could not be scanned for a force-push." >&2 || true; exit 2 ;;
esac

VERDICT=$(printf '%s\n' "$COMMAND" | awk -v main_fires="$MAIN_FIRES" '
  BEGIN {
    SQ = sprintf("%c", 39)
    BT = sprintf("%c", 96)          # backtick
    verdict = 0; unmodelled = 0; any_token = 0; hd = ""; hd_safe = 1
    pushforce = 0; risky = 0; q_owner = ""; push_word = 0; unverified = 0
    push_via_other = 0
    delete assign
    # Commands that cannot execute their arguments as a command. A force flag
    # inside one of these is that command own flag, or its text — never a push.
    #
    # Membership is earned, not assumed: nothing belongs here that has a flag
    # which runs a program. `sed` and `awk` are absent because both can execute
    # one from a script; `find` is absent because of -exec; `sort` is absent
    # because of --compress-program, which runs the program it names; `xargs`,
    # `env`, `timeout` and the rest of the wrappers are absent because running a
    # command is the whole of what they do. Anything not here blocks.
    safe = " echo printf grep egrep fgrep pgrep gh cat ls head tail wc rm mkdir" \
           " rmdir cp mv touch chmod ln true false test [ sleep cd pwd which" \
           " basename dirname date uname kill ps df du jq diff stat uniq" \
           " cut tr tee file numfmt readlink realpath "
  }

  # /usr/bin/echo is still echo.
  function base(w) { sub(/^.*\//, "", w); return w }

  function is_safe(w) { return (index(safe, " " w " ") > 0) }

  # A word that git would read as a force flag: the long flag, a short cluster
  # containing f, or a `+`-prefixed refspec — git other spelling of a forced
  # update. Deliberately not a substring test, so `--force-with-lease`, which
  # contains `--force`, is not one.
  function is_force(w) {
    if (w == "--force") return 1
    if (w ~ /^-[a-zA-Z]*f[a-zA-Z]*$/) return 1
    if (w ~ /^\+/) return 1
    return 0
  }

  # Read a string into words the way the shell does: quotes group and are
  # removed, a backslash escapes, only unquoted whitespace separates. Returns
  # the word count and fills words[].
  #
  # Runs are sliced out of the input rather than appended a character at a time;
  # per-character appending makes the cost grow with the square of the length,
  # which is what kept the cap necessary in the first place.
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

  # Classify one simple command. A force flag in it belongs either to a push,
  # or to the command word itself:
  #
  #   * the segment runs a push — `git` with `push` among its words — so the
  #     flag reaches git. Blocks, whatever the rest of the line says.
  #   * the command word cannot execute a command, so the flag is that command
  #     own flag or its text. Accounted for.
  #   * anything else could be running a push the guard cannot see. Recorded as
  #     risky, which blocks if a push shares the line at all.
  #
  # A force flag on `git` with no `push` — `git branch -f` — is none of these
  # and stays allowed, because no push is being forced.
  function judge(seg,   W, n, i, w, has, ispush, v, nm, ispush_word) {
    n = tokenize(seg, W)
    has = 0; ispush = 0; ispush_word = 0
    for (i = 1; i <= n; i++) {
      if (is_force(W[i])) has = 1
      if (W[i] == "push") { ispush = 1; ispush_word = 1; push_word = 1 }
      # Remember a same-line assignment, so a flag that reaches the push through
      # the variable it just set is still readable.
      if (W[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        nm = W[i]; sub(/=.*$/, "", nm)
        v = W[i]; sub(/^[^=]*=/, "", v)
        assign[nm] = v
      }
    }
    # `git>log push` and `git push>log` are pushes too: a redirect glues to the
    # word beside it, and the shell parses both as `git push`.
    if (seg ~ /git[^A-Za-z0-9]*push/) { push_word = 1; ispush = 1; ispush_word = 1 }
    # A quoted span groups into a single word, so a flag written inside one
    # never appears as a word of its own. The raw text is examined as well,
    # which is what finds it.
    if (seg ~ /(-f|--force)([^A-Za-z0-9_-]|$)/ || seg ~ /[ \t]\+[^ \t]/) has = 1
    if (!has) {
      # `F=--force; git push $F` is a force-push whose flag never appears as a
      # word of its own beside the push.
      if (ispush) {
        for (i = 1; i <= n; i++) {
          if (W[i] ~ /^\$[A-Za-z_][A-Za-z0-9_]*$/) {
            nm = substr(W[i], 2)
            if ((nm in assign) && is_force(assign[nm])) { pushforce = 1; return }
          }
        }
      }
      # A push that is an argument to a command able to run a command is how the
      # wrappers receive a flag from elsewhere on the line — `echo --force |
      # xargs git push`. It matters only once a flag has been seen somewhere.
      if (ispush_word && n > 0 && base(W[1]) != "git" && !is_safe(base(W[1]))) {
        push_via_other = 1
      }
      return
    }
    any_token = 1
    if (n == 0) { risky = 1; return }
    w = base(W[1])
    if (w == "git" && ispush) { pushforce = 1; return }
    if (w == "git") {
      # A literal subcommand that is not `push` — `git branch -f`, `git tag -f` —
      # carries its own force flag and forces no push, so it is accounted for.
      # If the subcommand is not a literal at all the guard cannot see what it
      # is, and a force flag beside it is not something it can account for.
      for (i = 2; i <= n; i++) if (W[i] ~ /\$/) { push_word = 1; risky = 1; return }
      # git runs an alias as the subcommand it names, and `-c alias.p=push`
      # defines one for this invocation only.
      if (seg ~ /alias\.[^ ]*=/) { push_word = 1; risky = 1; return }
      any_token = 1
      return
    }
    # `gh alias set --shell` makes an alias gh runs through a shell, so a gh
    # command is not accounted for when it names one.
    if (w == "gh") {
      # Each of these runs or forwards a command: `alias set --shell` defines
      # one, `codespace ssh` runs one remotely, `extension exec` runs one.
      for (i = 2; i <= n; i++) {
        if (W[i] == "alias" || W[i] == "codespace" || W[i] == "extension") {
          risky = 1; return
        }
      }
    }
    if (is_safe(w)) return
    risky = 1
  }

  {
    # Inside a heredoc body every line belongs to the opening command.
    if (hd != "") {
      t = $0
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t == hd) { hd = ""; next }
      if (!hd_safe) {
        # The body is a script. Judge it as one.
        judge(t)
      } else if (t ~ /(-f|--force)([^A-Za-z0-9_-]|$)/) {
        any_token = 1
      }
      next
    }

    # A quoted string may span lines, and a line that starts inside one has no
    # command of its own: segstart 0 means nothing decidable here yet.
    line = buf $0
    buf = ""
    segstart = (q == "") ? 1 : 0

    # A line ending in an unescaped backslash continues onto the next: the shell
    # removes the backslash-newline before it parses anything.
    nb = 0; k = length(line)
    while (k - nb >= 1 && substr(line, k - nb, 1) == "\\") nb++
    if (nb % 2 == 1) { buf = substr(line, 1, k - 1); next }

    # A line that starts inside a quoted string carries that string text, and any
    # flag on it belongs to whatever command opened the string.
    if (segstart == 0 && line ~ /(-f|--force)([^A-Za-z0-9_-]|$)/) {
      any_token = 1
      if (!is_safe(q_owner)) risky = 1
    }

    n = length(line); i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      if (q != "") {
        if (c == "\\" && q == "\"") { i += 2; continue }
        # A substitution runs even inside double quotes. Inside single quotes it
        # is literal text, which is why a quoted mention of a push is one word
        # and not a command.
        if (q == "\"") {
          if (c == BT) { unmodelled = 1 }
          else if (c == "$") {
            nx = substr(line, i + 1, 1)
            if (nx == "(" || nx == "{") unmodelled = 1
          }
        }
        if (c == q) { q = ""; if (segstart == 0) segstart = i + 1 }
        i++; continue
      }
      if (c == "\\") { i += 2; continue }
      # Substitutions are not modelled, and a command the guard cannot read is
      # not one it can allow.
      if (c == "$") {
        nx = substr(line, i + 1, 1)
        if (nx == "(" || nx == "{") {
          unmodelled = 1
          # Skip the whole span. Its inner punctuation is the expansion own, not
          # a separator: splitting at the brace of `${P}` would put the command
          # word and its arguments in different segments.
          op = nx; cl = (nx == "(") ? ")" : "}"
          dep = 1; j = i + 2
          while (j <= n && dep > 0) {
            ch = substr(line, j, 1)
            if (ch == op) dep++
            else if (ch == cl) dep--
            j++
          }
          i = (dep == 0) ? j : n + 1
          continue
        }
        if (nx == SQ) { unmodelled = 1; i += 2; continue }
      }
      if (c == BT) {
        unmodelled = 1
        j = i + 1
        while (j <= n && substr(line, j, 1) != BT) j++
        i = (j <= n) ? j + 1 : n + 1
        continue
      }
      if (c == "(" && substr(line, i + 1, 1) == "(") { unmodelled = 1; i += 2; continue }
      if (c == "\"" || c == SQ) {
        # A string may run past this line, and its continuation lines have no
        # command word of their own. Remember whose argument the span is.
        if (segstart > 0) {
          OW = tokenize(substr(line, segstart, i - segstart), OWW)
          q_owner = (OW > 0) ? base(OWW[1]) : ""
        }
        q = c; i++; continue
      }
      if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;|&(]/)) {
        if (segstart > 0) judge(substr(line, segstart, i - segstart))
        # A comment is prose about the command. Its flags are accounted for,
        # but they are still flags the floor saw, so they are counted.
        if (substr(line, i) ~ /(-f|--force)([^A-Za-z0-9_-]|$)/) any_token = 1
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
        # Who opened it decides whether the body is a script or text — and a
        # body written into a pipeline is being read by the command on the other
        # end of it, not written to a file.
        W2N = tokenize(substr(line, segstart, i - segstart), W2)
        hd_safe = (W2N > 0 && is_safe(base(W2[1]))) ? 1 : 0
        # A pipe or a process substitution reads the body rather than filing it,
        # so the body is a script whichever command opened it.
        if (substr(line, i + 2) ~ /\|/ || substr(line, i + 2) ~ /[<>]\(/) hd_safe = 0
        if (d != "") hd = d
        i += 2; continue
      }
      if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" ||
          c == "{" || c == "}") {
        if (segstart > 0) judge(substr(line, segstart, i - segstart))
        segstart = i + 1
        i++
        continue
      }
      i++
    }
    if (segstart > 0 && segstart <= n) {
      judge(substr(line, segstart, n - segstart + 1))
    }
  }

  END {
    # Reaching the end mid-construct means the scan did not see the whole command
    # and cannot vouch for it. That is a refusal, but not a force-push: the
    # operator is told what actually happened.
    if (hd != "") { verdict = 1; unverified = 1 }
    if (q != "") { verdict = 1; unverified = 1 }
    if (buf != "") judge(buf)

    # A push carrying a force flag is always a block. Otherwise the floor
    # decides: it fires when a push and a force flag share the line, and the
    # command is allowed only if the accounting explained every flag — no
    # substitution it could not read, no flag it never saw, and nothing left
    # running a command the guard cannot name.
    if (pushforce) verdict = 1
    # The floor fired but the accounting found no flag to attribute, which is
    # unexplained. Kept separate from the rule below: a plain push has no flag
    # either, and must stay allowed.
    else if (main_fires + 0 == 1 && !any_token) verdict = 1
    # Otherwise the accounting decides, and it applies whenever a push is
    # present at all — not only when the floor pattern happened to match. The
    # floor is blind to a push whose words arrive through an expansion or a
    # redirect, which is exactly when the accounting has to carry the decision.
    else if (push_word && (unmodelled || risky)) { verdict = 1; unverified = 1 }
    else if (any_token && push_via_other) { verdict = 1; unverified = 1 }
    if (verdict == 1 && !pushforce) unverified = 1
    print (unverified && !pushforce) ? 2 : verdict
  }
') || { echo "BLOCKED: the command could not be scanned, so it cannot be verified." >&2 || true; exit 2; }

case "$VERDICT" in
  0) exit 0 ;;
  1)
    echo "BLOCKED: Force-push detected. This is a Tier 3 action that requires manual execution." >&2 || true
    echo "If you need to force-push, ask the user to run the command directly." >&2 || true
    echo "Note: --force-with-lease is allowed as a safe alternative." >&2 || true
    exit 2
    ;;
  2)
    echo "BLOCKED: this command could not be verified as free of a force-push, so it was not run." >&2 || true
    echo "It carries a construct the guard cannot read — a substitution, or input that ends mid-construct." >&2 || true
    echo "Rewrite it without the substitution, or ask the user to run it directly." >&2 || true
    exit 2
    ;;
  *)
    echo "BLOCKED: the command could not be scanned, so it cannot be verified." >&2 || true
    exit 2
    ;;
esac
