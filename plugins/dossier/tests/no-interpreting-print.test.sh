# Guards that no fenced block in a dossier command prints a value through an
# interpreting builtin.
#
# Command files embed shell in fenced blocks, and the shell that runs them
# interprets backslash escapes in `echo`'s argument: a value holding the two
# printable characters `\` and `n` carries no control character, becomes a real
# newline the moment it is printed, and forges a whole extra `KEY=value` line.
# A config value, a register row or any GitHub payload can carry one.
#
# The scanner is a copy of the one the flow plugin's guard runs. The two
# plugins install independently, so it cannot be shared, and an assertion that
# compares the two copies is not available either: reaching into a sibling
# plugin's tree is an operational dependency this plugin forbids, because the
# path resolves on a development machine with the whole marketplace checked out
# and fails on a real install. What keeps the copy honest is instead the table
# of fixtures below — every command opener the scanner accepts, and every
# non-command shape it must not fire on, each turning the scan red or staying
# quiet on its own. A scanner that drifts away from those properties fails here
# without needing to see the other copy.
#
# What this does NOT claim: it does not inspect bin/*.sh, hooks, or markdown
# outside a fence. Quoted spans are blanked before the scan, so text inside a
# string is not an offender; a line inside a heredoc body is, because such a
# body can become a script the fence then runs and a line-wise scanner cannot
# tell the two apart.

PLUGIN_DIR="$REPO_ROOT/plugins/dossier"

# No EXIT trap here. Test files are sourced, so they share one trap slot, and a
# trap registered here would silently replace the runner's own cleanup trap.
# The runner points TMPDIR at a directory it creates and removes, and every
# mktemp in this file lands under it, so cleanup does not depend on this file.

_dip_scan() {
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
    # punctuation left 53 real sites unread while still reporting the tree
    # clean, which is the failure this guard exists to prevent rather than to
    # reproduce.
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

# _dip_offenders <file> — the offender lines only, so callers can count or grep
# without the trailer.
_dip_offenders() { _dip_scan "$1" | grep -c '^OFFENDER' | tr -d ' '; }

DIP_FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dip-fixtures.XXXXXX")
_dip_fixture() {
  local name="$1"; shift
  local path="$DIP_FIXTURE_DIR/$name"
  : > "$path"
  local l
  for l in "$@"; do printf '%s\n' "$l" >> "$path"; done
  printf '%s' "$path"
}

# ---------------------------------------------------------------- the guard --

_dossier_test_begin "no fence in any dossier markdown file invokes an interpreting print"
DIP_FILELIST=$(find "$PLUGIN_DIR" -name '*.md' | sort)
DIP_FILES=$(printf '%s\n' "$DIP_FILELIST" | grep -c . || true)
DIP_OFFENDERS=0
DIP_BLOCKS=0
DIP_LINES=0
DIP_UNREAD=0
DIP_SHOWN=0
DIP_DETAIL=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  scanout=$(_dip_scan "$f")
  b=$(printf '%s\n' "$scanout" | sed -n 's/^SCANNED .*blocks=\([0-9]*\).*/\1/p')
  l=$(printf '%s\n' "$scanout" | sed -n 's/^SCANNED .*lines=\([0-9]*\).*/\1/p')
  if [ -z "$b" ] || [ -z "$l" ]; then
    # No trailer at all: the scan aborted. Counting it as clean is the exact
    # failure this trailer exists to prevent.
    DIP_UNREAD=$((DIP_UNREAD + 1))
    continue
  fi
  DIP_BLOCKS=$((DIP_BLOCKS + b))
  DIP_LINES=$((DIP_LINES + l))
  n=$(printf '%s\n' "$scanout" | grep -c '^OFFENDER' || true)
  if [ "$n" -gt 0 ]; then
    DIP_OFFENDERS=$((DIP_OFFENDERS + n))
    # Show the first few sites across the tree, then stop: one file with
    # hundreds of them would otherwise bury the summary it is meant to explain.
    # The budget is on what has been *shown*, not on the running total, or the
    # first offender-heavy file exhausts it before anything is printed.
    if [ "$DIP_SHOWN" -lt 8 ]; then
      DIP_DETAIL="$DIP_DETAIL$(printf '%s\n' "$scanout" | sed -n 's/^OFFENDER /  /p' | head -3 | sed "s|^|$(basename "$f"):|")
"
      DIP_SHOWN=$((DIP_SHOWN + 3))
    fi
  fi
done <<< "$DIP_FILELIST"

assert_equal "0" "$DIP_UNREAD" "every markdown file scan reported its own counts"
if [ "$DIP_FILES" -gt 0 ] && [ "$DIP_BLOCKS" = "0" ]; then
  _dossier_assert_fail "the scan read 0 blocks across $DIP_FILES markdown files - a scan that reads nothing must not read as clean"
elif [ "$DIP_LINES" = "0" ]; then
  _dossier_assert_fail "the scan read $DIP_BLOCKS blocks but 0 lines of them - fence parsing is skipping block bodies"
else
  _dossier_assert_pass "scan reached $DIP_FILES files, $DIP_BLOCKS blocks, $DIP_LINES lines"
fi
if [ "$DIP_OFFENDERS" = "0" ]; then
  _dossier_assert_pass "no fence invokes echo"
else
  _dossier_assert_fail "$DIP_OFFENDERS fence line(s) invoke echo (first few):
$DIP_DETAIL"
fi

_dossier_test_begin "an echo opened by a word or a case arm is still a command"
# The predicate deciding command position is the whole guard, and a version of
# it that knew only punctuation read real sites as arguments while reporting a
# clean tree. Each opener has its own case so a recurrence fails loudly.
DIP_OPENERS=(
  'case-arm|case "$V" in *) echo "K=$V" ;; esac'
  'then-branch|if true; then echo "K=$V"; fi'
  'else-branch|if false; then :; else echo "K=$V"; fi'
  'negated|! echo "K=$V"'
)
for row in "${DIP_OPENERS[@]}"; do
  name=${row%%|*}; code=${row#*|}
  fx=$(_dip_fixture "opener-$name.md" '```bash' "$code" '```')
  assert_equal "1" "$(_dip_offenders "$fx")" "an echo in the $name position is an offender"
done
fx=$(_dip_fixture "prompt.md" '```bash' '$ echo "$x"' '```')
assert_equal "0" "$(_dip_offenders "$fx")" "a shell transcript prompt is not treated as a script"

_dossier_test_begin "an offending line turns the scan red"
fx=$(_dip_fixture "offender.md" '```bash' 'echo "V=$(cat .claude/settings.dossier.json)"' '```')
assert_equal "1" "$(_dip_offenders "$fx")" "a settings-derived echo is reported"
assert_match '^OFFENDER 2 ' "$(_dip_scan "$fx")" "the offender names its line"
fx=$(_dip_fixture "clean.md" '```bash' 'printf "%s\n" "V=$V"' '```')
assert_equal "0" "$(_dip_offenders "$fx")" "a printf fence is not an offender"

# ------------------------- the producer that reads a tracked settings file --
# A fence is only half the contract. The value it prints comes from a helper,
# and a helper that hands over a value containing a real newline forges the
# line before any fence sees it. This resolver is the one path from a tracked,
# pull-request-modifiable settings file to a `KEY=value` line, so it is checked
# here rather than left to the fence.
_dossier_test_begin "the config resolver does not hand over a value that forges a line"
DIPRES_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dip-resolve.XXXXXX")
mkdir -p "$DIPRES_DIR/.claude"
DIPRES="$REPO_ROOT/plugins/dossier/bin/dossier-resolve-config.sh"
if [ ! -x "$DIPRES" ]; then
  _dossier_assert_fail "resolver missing or not executable at $DIPRES"
else
  _dip_settings() {
    python3 - "$DIPRES_DIR" "$1" <<'PY'
import json, sys
# json.dump escapes the control character, so the file holds an escape and jq
# decodes it to a REAL newline -- which is the whole point of the fixture.
json.dump({"dossier": {"engagement": {"deliveryMode": sys.argv[2]}}},
          open(sys.argv[1] + "/.claude/settings.dossier.json", "w"))
PY
  }
  _dip_settings $'a\nFORGED=1'
  OUT=$(cd "$DIPRES_DIR" && bash "$DIPRES" --default auto dossier.engagement.deliveryMode 2>/dev/null)
  assert_equal "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "a newline in a settings value does not add a line"
  assert_equal "0" "$(printf '%s\n' "$OUT" | grep -c '^FORGED=1' || true)" "the forged key never begins a line of its own"
  assert_equal "auto" "$OUT" "the refusal falls back to the declared default"
  # The escape hatch has to keep working, or the refusal is a wall rather than
  # a guard and a legitimate multi-line value becomes unreachable.
  OUT=$(cd "$DIPRES_DIR" && bash "$DIPRES" --allow-control-chars dossier.engagement.deliveryMode 2>/dev/null)
  assert_equal "2" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "--allow-control-chars still passes a multi-line value through"
  # And an ordinary value is untouched by any of it.
  _dip_settings on
  OUT=$(cd "$DIPRES_DIR" && bash "$DIPRES" --default auto dossier.engagement.deliveryMode 2>/dev/null)
  assert_equal "on" "$OUT" "an ordinary value is reported unchanged"
fi

_dossier_test_summary
