# Guards that no fenced block in a flow command prints a value through an
# interpreting builtin.
#
# Command files embed shell in fenced blocks, and the shell that runs them
# interprets backslash escapes in `echo`'s argument: a value holding the two
# printable characters `\` and `n` carries no control character, so it passes
# every byte-level validation in the plugin and becomes a real newline the
# moment it is printed. A settings value, a goal YAML, a review body or any
# GitHub payload can therefore forge a whole extra `KEY=value` line, and `\c`
# truncates the rest of the line outright. `printf '%s\n'` does not interpret
# its argument, so the class is closed by never invoking `echo` in a fence.
#
# Scope is every fenced block of every markdown file in the plugin, not a known
# list. The reference documents carry the canonical snippets the commands are
# copied from, so a defect left there is a defect re-copied; and earlier sweeps
# of this class missed sites each time, including one that read 45 real sites as
# arguments because it recognised only punctuation as a command opener.
# The scan reports how many files, blocks and lines it read, because a scan
# that matched nothing and a scan that read nothing print the same empty list.
#
# What this does NOT claim: it does not inspect bin/*.sh, hooks, or markdown
# outside a fence. A producer's own one-line contract is guarded separately.
#
# Quoted spans are blanked before the scan, so text inside a string is not an
# offender. One deliberate false positive remains: a line inside a heredoc body
# is scanned like any other line, so a fence that writes a script through a
# heredoc and spells `echo` in that script is flagged. That is kept rather than
# tolerated — such a body can become a script the fence then runs, and a
# line-wise scanner cannot tell the two apart. It is stated here so the claim
# matches what the scan does.

PLUGIN_DIR="$REPO_ROOT/plugins/flow"

# No EXIT trap here. Test files are sourced, so they share one trap slot, and a
# trap registered here would silently replace the runner's own cleanup trap.
# The runner points TMPDIR at a directory it creates and removes, and every
# mktemp in this file lands under it, so cleanup does not depend on this file.

# _nip_scan <file> — prints one `OFFENDER <lineno> <text>` line per line inside
# a fenced block that invokes echo, then a final `SCANNED files=1 blocks=<N>
# lines=<L>` trailer. The trailer is emitted even for a file with no fences, so
# a caller can tell "read it, found nothing" from "never read it".
#
# Fence parsing notes, each of which a plausible narrower version gets wrong:
#   - the closing marker may carry trailing whitespace; matching only the bare
#     ``` would leave the block open and swallow the rest of the file
#   - a block may be tagged (```bash, ```!) or untagged; matching only ```!
#     would skip most of the tree
#   - a fence marker with an info string while already inside a block is
#     reported rather than ignored, so a malformed file is visible
#   - an unterminated block is reported, never silently truncated
_nip_scan() {
  awk '
    BEGIN { SQ = sprintf("%c", 39) }
    function comment_at(line,   n, i, c, q, prev) {
      n = length(line); q = ""
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q != "") { if (c == q) q = ""; continue }
        if (c == "\"" || c == SQ) { q = c; continue }
        if (c == "#") {
          prev = (i == 1) ? "" : substr(line, i - 1, 1)
          if (prev == "" || prev == " " || prev == "\t" || prev == ";" ||
              prev == "|" || prev == "&" || prev == "(" || prev == ")") return i
        }
      }
      return 0
    }
    # Openers that put the next word in command position. `case "$v" in *) echo`
    # and `if x; then echo` are ordinary shell; a predicate that recognised only
    # punctuation read real sites in this plugin as arguments while still
    # reporting the tree clean, which is the failure this guard exists to
    # prevent rather than to reproduce.
    #
    # `$` is deliberately absent. A line beginning `$ echo …` is a shell
    # transcript inside a document, not a script the harness runs, and
    # rewriting it would corrupt the example it exists to show.
    function opens_command(b,   lastc) {
      if (b == "") return 1
      lastc = substr(b, length(b), 1)
      if (lastc == ";" || lastc == "&" || lastc == "|" || lastc == "(" ||
          lastc == "{" || lastc == "`" || lastc == ")" || lastc == "!") return 1
      # A launcher word leaves what follows in command position, and so does an
      # assignment prefix: `sudo echo`, `command echo` and `V=x echo` all run
      # echo. Recognising only punctuation left every one of these unread.
      if (b ~ /(^|[^A-Za-z0-9_])(command|env|sudo|xargs|nice|nohup|exec|eval|time)$/) return 1
      if (b ~ /[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$/) return 1
      if (b ~ /(^|[^A-Za-z0-9_])then$/ || b ~ /(^|[^A-Za-z0-9_])do$/ ||
          b ~ /(^|[^A-Za-z0-9_])else$/ || b ~ /(^|[^A-Za-z0-9_])elif$/ ||
          b ~ /(^|[^A-Za-z0-9_])if$/ || b ~ /(^|[^A-Za-z0-9_])while$/ ||
          b ~ /(^|[^A-Za-z0-9_])until$/) return 1
      return 0
    }
    # Blank out quoted spans, keeping every position so the rest of the line
    # still reads the same way. Text inside a string is data, not a command:
    # `printf "%s\n" "run this; echo done"` runs no echo, and flagging it would
    # fail a build on a fence that is doing nothing wrong.
    function strip_quotes(s,   n, i, c, q, out) {
      n = length(s); q = ""; out = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == "\\" && q == "\"") { i++; out = out "  "; continue }
          if (c == q) q = ""
          out = out " "
          continue
        }
        if (c == "\\") { i++; out = out "  "; continue }
        if (c == "\"" || c == SQ) { q = c; out = out " "; continue }
        out = out c
      }
      return out
    }
    # 1 when `code` invokes echo as a command (not as a substring, not as an
    # argument of something else).
    function invokes_echo(code,   pos, p, idx, prevc, nextc, before, b) {
      pos = 1
      while ((p = index(substr(code, pos), "echo")) > 0) {
        idx = pos + p - 1
        prevc = (idx == 1) ? "" : substr(code, idx - 1, 1)
        after = substr(code, idx + 4)
        nextc = (length(after) == 0) ? "" : substr(after, 1, 1)
        if (prevc !~ /[A-Za-z0-9_]/ && nextc !~ /[A-Za-z0-9_]/) {
          before = substr(code, 1, idx - 1)
          b = before
          sub(/[[:space:]]+$/, "", b)
          if (opens_command(b)) return 1
        }
        pos = idx + 4
      }
      return 0
    }

    {
      t = $0
      sub(/^[[:space:]]*>[[:space:]]*/, "", t)
      sub(/^[[:space:]]*/, "", t)
      if (substr(t, 1, 3) == "```") {
        rest = substr(t, 4)
        gsub(/[[:space:]]+$/, "", rest)
        if (inblock == 0) { inblock = 1; blocks++; openline = FNR; next }
        if (rest == "") { inblock = 0; next }
        printf "ANOMALY %d nested fence marker inside a block\n", FNR
        next
      }
      if (inblock == 0) next
      body = $0
      sub(/^[[:space:]]*>[[:space:]]*/, "", body)
      lines++
      cpos = comment_at(body)
      code = (cpos > 0) ? substr(body, 1, cpos - 1) : body
      if (invokes_echo(strip_quotes(code))) printf "OFFENDER %d %s\n", FNR, body
    }
    END {
      if (inblock == 1) printf "ANOMALY block opened at line %d is never closed\n", openline
      printf "SCANNED files=1 blocks=%d lines=%d\n", blocks, lines
    }
  ' openline="" "$1"
}

# _nip_offenders <file> — the offender lines only, so callers can count or grep
# without the trailer.
_nip_offenders() { _nip_scan "$1" | grep -c '^OFFENDER' | tr -d ' '; }

# _nip_fixture <name> <line>... — write a fixture command file under the run's
# temp dir and print its path.
NIP_FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nip-fixtures.XXXXXX")
_nip_fixture() {
  local name="$1"; shift
  local path="$NIP_FIXTURE_DIR/$name"
  : > "$path"
  local l
  for l in "$@"; do printf '%s\n' "$l" >> "$path"; done
  printf '%s' "$path"
}

# ---------------------------------------------------------------- the guard --

_flow_test_begin "no fence in any flow markdown file invokes an interpreting print"
NIP_FILELIST=$(find "$PLUGIN_DIR" -name '*.md' | sort)
NIP_FILES=$(printf '%s\n' "$NIP_FILELIST" | grep -c . || true)
NIP_OFFENDERS=0
NIP_BLOCKS=0
NIP_LINES=0
NIP_UNREAD=0
NIP_SHOWN=0
NIP_DETAIL=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  scanout=$(_nip_scan "$f")
  b=$(printf '%s\n' "$scanout" | sed -n 's/^SCANNED .*blocks=\([0-9]*\).*/\1/p')
  l=$(printf '%s\n' "$scanout" | sed -n 's/^SCANNED .*lines=\([0-9]*\).*/\1/p')
  if [ -z "$b" ] || [ -z "$l" ]; then
    # No trailer at all: the scan aborted. Counting it as clean is the exact
    # failure this trailer exists to prevent.
    NIP_UNREAD=$((NIP_UNREAD + 1))
    continue
  fi
  NIP_BLOCKS=$((NIP_BLOCKS + b))
  NIP_LINES=$((NIP_LINES + l))
  n=$(printf '%s\n' "$scanout" | grep -c '^OFFENDER' || true)
  if [ "$n" -gt 0 ]; then
    NIP_OFFENDERS=$((NIP_OFFENDERS + n))
    # Show the first few sites across the tree, then stop: one file with
    # hundreds of them would otherwise bury the summary it is meant to explain.
    # The budget is on what has been *shown*, not on the running total, or the
    # first offender-heavy file exhausts it before anything is printed.
    if [ "$NIP_SHOWN" -lt 8 ]; then
      NIP_DETAIL="$NIP_DETAIL$(printf '%s\n' "$scanout" | sed -n 's/^OFFENDER /  /p' | head -3 | sed "s|^|$(basename "$f"):|")
"
      NIP_SHOWN=$((NIP_SHOWN + 3))
    fi
  fi
done <<< "$NIP_FILELIST"

assert_equal "0" "$NIP_UNREAD" "every markdown file scan reported its own counts"
if [ "$NIP_FILES" -gt 0 ] && [ "$NIP_BLOCKS" = "0" ]; then
  _flow_assert_fail "the scan read 0 blocks across $NIP_FILES markdown files — a scan that reads nothing must not read as clean"
elif [ "$NIP_LINES" = "0" ]; then
  _flow_assert_fail "the scan read $NIP_BLOCKS blocks but 0 lines of them — fence parsing is skipping block bodies"
else
  _flow_assert_pass "scan reached $NIP_FILES files, $NIP_BLOCKS blocks, $NIP_LINES lines"
fi
if [ "$NIP_OFFENDERS" = "0" ]; then
  _flow_assert_pass "no fence invokes echo"
else
  _flow_assert_fail "$NIP_OFFENDERS fence line(s) invoke echo (first few):
$NIP_DETAIL"
fi

# ------------------------------------------------- and that the guard can fail

_flow_test_begin "each offending shape turns the scan red"
# One shape per route a value reaches a print: a tracked settings file, a
# heredoc read inline, a helper's stdout, and a JSON payload piped to a parser.
NIP_SHAPES=(
  'V=$(jq -r .x .claude/settings.flow.json 2>/dev/null); echo "V=$V"'
  'V=$(cat <<INNER
line
INNER
); echo "V=$V"'
  'echo "GOAL=$(plugins/flow/bin/flow-active-goal.sh --status)"'
  'echo "$JSON" | jq -r .name'
)
NIP_SHAPE_NAMES=(settings-derived inlined-heredoc helper-output piped-json)
# The line the echo sits on in each fixture: the heredoc shape spans four lines
# before its closing `); echo …`, so a line-2 expectation would be wrong for it
# and would hide a scanner that reported the wrong position.
NIP_SHAPE_LINES=(2 5 2 2)
for i in "${!NIP_SHAPES[@]}"; do
  fx=$(_nip_fixture "shape-$i.md" '```bash' "${NIP_SHAPES[$i]}" '```')
  got=$(_nip_offenders "$fx")
  assert_equal "1" "$got" "the ${NIP_SHAPE_NAMES[$i]} shape is reported (one offender)"
  # And it must name the offending line, not merely count one.
  assert_match "^OFFENDER ${NIP_SHAPE_LINES[$i]} " "$(_nip_scan "$fx")" "the ${NIP_SHAPE_NAMES[$i]} shape names line ${NIP_SHAPE_LINES[$i]}"
done

_flow_test_begin "an echo opened by a word or a case arm is still a command"
# The predicate deciding whether a token sits in command position is the whole
# guard. An earlier version knew only punctuation, so it read 45 real sites in
# this plugin as arguments while reporting the tree clean — and because the same
# predicate drove the rewrite, each confirmed the other's blind spot. Every
# opener gets its own case here so a recurrence fails loudly rather than
# reading as clean.
NIP_OPENERS=(
  'case-arm|case "$V" in *) echo "K=$V" ;; esac'
  'then-branch|if true; then echo "K=$V"; fi'
  'else-branch|if false; then :; else echo "K=$V"; fi'
  'if-opener|if echo "$V" | jq -e . >/dev/null; then :; fi'
  'while-body|while true; do echo "K=$V"; break; done'
  'negated|! echo "K=$V"'
  'assignment-prefix|V=x echo "K=$V"'
  'command-builtin|command echo "K=$V"'
  'env-wrapper|env echo "K=$V"'
  'sudo-prefix|sudo echo "K=$V"'
)
for row in "${NIP_OPENERS[@]}"; do
  name=${row%%|*}; code=${row#*|}
  fx=$(_nip_fixture "opener-$name.md" '```bash' "$code" '```')
  assert_equal "1" "$(_nip_offenders "$fx")" "an echo in the $name position is an offender"
done
# The one shape deliberately not an offender: a shell transcript inside a
# document, where `$` is a prompt rather than a command. Rewriting it would
# corrupt the example it exists to show.
fx=$(_nip_fixture "prompt.md" '```bash' '$ echo "$x"' '```')
assert_equal "0" "$(_nip_offenders "$fx")" "a shell transcript prompt is not treated as a script"

_flow_test_begin "the scan sees every block, including the ones a narrower parser drops"
# A closing marker with trailing whitespace: matching only a bare ``` leaves the
# first block open and swallows the offender in the second.
fx=$(_nip_fixture "trailing-ws.md" '```bash' 'echo "A=$A"' '``` ' '```!' 'echo "B=$B"' '```')
assert_equal "2" "$(_nip_offenders "$fx")" "trailing whitespace on the closing marker does not hide the next block"
# The offender count alone does not discriminate: with the trailing-whitespace
# tolerance removed, the scanner treats the marked close as a nested marker,
# leaves the first block open, swallows the rest of the file — and still counts
# two offenders while reporting one block instead of two. The block count is
# the signal that tells those apart.
assert_match 'blocks=2 ' "$(_nip_scan "$fx")" "the trailing-whitespace fixture really contains two blocks"
assert_equal "0" "$(_nip_scan "$fx" | grep -c '^ANOMALY' || true)" "no anomaly is reported for a well-formed file"
# An untagged block, a bash-tagged block and a bang-tagged block in one file.
fx=$(_nip_fixture "mixed-tags.md" '```' 'echo "A=$A"' '```' '```bash' 'echo "B=$B"' '```' '```!' 'echo "C=$C"' '```')
assert_equal "3" "$(_nip_offenders "$fx")" "untagged, bash-tagged and bang-tagged blocks are all read"
# An unterminated block is an anomaly, not a silent truncation.
fx=$(_nip_fixture "unterminated.md" '```bash' 'echo "A=$A"')
assert_match '^ANOMALY ' "$(_nip_scan "$fx")" "an unterminated block is reported rather than truncated"

_flow_test_begin "the scan does not fire on echo that is not a command"
fx=$(_nip_fixture "not-a-command.md" \
  '```bash' \
  '# echo "commented out"' \
  'GREP_OUT=$(grep -c echoes file.txt)' \
  'printf "%s\n" "echo inside a string is data"' \
  '```')
assert_equal "0" "$(_nip_offenders "$fx")" "a comment, a longer word, and a quoted string are not offenders"

_flow_test_summary
